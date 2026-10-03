--!strict
--[[
	PlayerDataService
	-----------------
	Owns the authoritative, in-memory copy of every in-session player's saved
	data, and is the only module that talks to the DataStore. Every other
	service reads and mutates player state exclusively through the public API
	below - nothing else may touch the session cache.

	Follows the ServiceTemplate contract: :Init() is self-contained (it
	connects only to Players and its own remotes), so it has no :Start().
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)

--[[ Types ---------------------------------------------------------------- ]]

-- Exported so other services stop typing inventory entries as `any`.
export type InventoryItem = {
	Uid: string,
	ItemId: string,
	Tier: string,
	InUse: boolean,
}

export type PlayerData = {
	Cash: number,
	Inventory: { InventoryItem },
	Generators: { [string]: number },
	-- Multiplier Pad level; see TycoonConfig.GetCashMultiplierValue.
	CashMultiplierLevel: number,
	-- Map of pedestalIndex -> displayed item's Uid. The value type is
	-- optional because assigning nil is the intentional way to clear a
	-- pedestal slot (see SetPedestalDisplay) - Luau treats key removal as an
	-- assignment of nil, so `{ [number]: string }` would reject it.
	PedestalDisplays: { [number]: string? },
	-- How many Gacha pulls this player has made; drives the pull price.
	GachaPulls: number,
	-- Legacy (the droppers are gone): still loaded and saved so old saves
	-- round-trip unchanged, but nothing reads it.
	HasDropper2: boolean,
	-- 1-based index into GoalConfig.Goals of the goal currently being
	-- worked on; past the end means every goal is done.
	GoalIndex: number,
	-- Every resolved fusion attempt, success or fail (drives a goal).
	TotalFusions: number,
}

-- Server-computed progress toward the current goal, sent with the snapshot.
export type GoalProgress = {
	Current: number,
	Target: number,
}

-- What SyncTycoon sends to the client. One builder (GetTycoonSnapshot) so the
-- four services that sync no longer each hand-copy the payload shape.
export type TycoonSnapshot = {
	Cash: number,
	Generators: { [string]: number },
	CashMultiplierLevel: number,
	-- String keys ("1".."4") on the wire, like on disk: a RemoteEvent drops
	-- entries after a gap in a sparse numeric table ({[1]=a, [3]=b, [4]=c}),
	-- which made the client think occupied pedestals were empty.
	PedestalDisplays: { [string]: string },
	GachaPulls: number,
	GoalIndex: number,
	GoalProgress: GoalProgress?,
}

type State = {
	-- In-memory cache keyed by UserId; the source of truth while a player is
	-- in-session. Private: never exposed on the service table.
	sessionCache: { [number]: PlayerData },
	-- UserIds whose data must NEVER be written back (load failed in Studio and
	-- we fell back to a blank profile). See loadData.
	noSave: { [number]: boolean },
	-- Session-only: GoalService's latest progress readout per UserId.
	goalProgress: { [number]: GoalProgress? },
	-- Called synchronously at the start of every SyncTycoon (see OnSync).
	syncHooks: { (Player) -> () },
	-- os.clock() of each player's last honoured RequestSync.
	lastSyncRequest: { [number]: number },
	connections: { RBXScriptConnection },
}

--[[ Constants ------------------------------------------------------------ ]]

local DATASTORE_NAME = "PlayerData_v1"
local SAVE_RETRY_ATTEMPTS = 3
local LOAD_RETRY_ATTEMPTS = 3
local LOAD_RETRY_DELAY_SECONDS = 2
local AUTOSAVE_INTERVAL_SECONDS = 120
local SYNC_REQUEST_COOLDOWN_SECONDS = 2

local dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

local DEFAULT_DATA: PlayerData = {
	Cash = 0,
	Inventory = {},
	Generators = {},
	CashMultiplierLevel = 0,
	PedestalDisplays = {},
	GachaPulls = 0,
	HasDropper2 = false,
	GoalIndex = 1,
	TotalFusions = 0,
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	sessionCache = {},
	noSave = {},
	goalProgress = {},
	syncHooks = {},
	lastSyncRequest = {},
	connections = {},
}

local PlayerDataService = {}

PlayerDataService.Name = "PlayerDataService"

--[[ Private helpers ------------------------------------------------------ ]]

local function deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end

	local copy: { [any]: any } = {}
	for key, nested in (value :: any) :: { [any]: any } do
		copy[key] = deepCopy(nested)
	end
	return (copy :: any) :: T
end

-- DataStores serialize numeric keys with gaps ({[2] = uid}) unreliably: they
-- can come back as string keys ("2"), and the next SetPedestalDisplay(2, ...)
-- then makes a mixed string/number table that DataStores refuse to save at
-- all - silently losing every bit of progress after it. So pedestal slots are
-- stored on disk with string keys and converted back to numbers on load.
local function pedestalDisplaysToDisk(displays: { [number]: string? }): { [string]: string }
	local out: { [string]: string } = {}
	for index, uid in displays do
		if uid then
			out[tostring(index)] = uid
		end
	end
	return out
end

local function pedestalDisplaysFromDisk(raw: any): { [number]: string? }
	local out: { [number]: string? } = {}
	if typeof(raw) ~= "table" then
		return out
	end
	for key, uid in raw do
		local index = tonumber(key)
		if index and typeof(uid) == "string" then
			out[math.floor(index)] = uid
		end
	end
	return out
end

-- Fills any field missing from an older save with its default, so new
-- features never index nil on an old profile.
local function reconcile(raw: any): PlayerData
	local data = deepCopy(DEFAULT_DATA)
	if typeof(raw) ~= "table" then
		return data
	end
	if typeof(raw.Cash) == "number" then
		data.Cash = raw.Cash
	end
	if typeof(raw.Inventory) == "table" then
		data.Inventory = raw.Inventory
	end
	if typeof(raw.Generators) == "table" then
		data.Generators = raw.Generators
	end
	if typeof(raw.CashMultiplierLevel) == "number" then
		data.CashMultiplierLevel = raw.CashMultiplierLevel
	end
	data.PedestalDisplays = pedestalDisplaysFromDisk(raw.PedestalDisplays)
	if typeof(raw.GachaPulls) == "number" then
		data.GachaPulls = raw.GachaPulls
	end
	if typeof(raw.HasDropper2) == "boolean" then
		data.HasDropper2 = raw.HasDropper2
	end
	if typeof(raw.GoalIndex) == "number" and raw.GoalIndex >= 1 then
		data.GoalIndex = math.floor(raw.GoalIndex)
	end
	if typeof(raw.TotalFusions) == "number" then
		data.TotalFusions = raw.TotalFusions
	end

	-- Any item flagged InUse that isn't actually on a pedestal (e.g. the save
	-- happened mid-change) would be stuck forever: unfusable and undisplayable.
	local displayed: { [string]: boolean } = {}
	for _, uid in data.PedestalDisplays do
		if uid then
			displayed[uid] = true
		end
	end
	for _, item in data.Inventory do
		item.InUse = displayed[item.Uid] == true
	end
	return data
end

-- Returns true if the player's data is ready. On a DataStore failure this
-- used to fall back to a BLANK profile and then autosave it over the real
-- one - one Roblox outage and a player's whole save was wiped. Now: retry,
-- and if it still fails, kick in a live game (nothing gets overwritten), or
-- in Studio play on a blank profile that is never saved.
local function loadData(player: Player): boolean
	local key = "Player_" .. player.UserId
	local result: any = nil
	local success = false
	local lastError: any = nil

	for attempt = 1, LOAD_RETRY_ATTEMPTS do
		local ok, value = pcall(function()
			return dataStore:GetAsync(key)
		end)
		if ok then
			success = true
			result = value
			break
		end
		lastError = value
		warn(("PlayerDataService: load attempt %d/%d failed for %s (%d): %s"):format(
			attempt,
			LOAD_RETRY_ATTEMPTS,
			player.Name,
			player.UserId,
			tostring(value)
		))
		if attempt < LOAD_RETRY_ATTEMPTS then
			task.wait(LOAD_RETRY_DELAY_SECONDS)
		end
	end

	if not player.Parent then
		return false
	end

	if success then
		state.sessionCache[player.UserId] = reconcile(result)
		return true
	end

	if RunService:IsStudio() then
		warn(("PlayerDataService: using a blank, UNSAVED profile for %s in Studio (%s). "
			.. "Enable Studio API access in Game Settings > Security to test saving."):format(player.Name, tostring(lastError)))
		state.sessionCache[player.UserId] = deepCopy(DEFAULT_DATA)
		state.noSave[player.UserId] = true
		return true
	end

	player:Kick("Couldn't load your save (Roblox data servers are having trouble). Your progress is safe - please rejoin in a minute.")
	return false
end

local function saveData(userId: number, data: PlayerData?): boolean
	if not data or state.noSave[userId] then
		return false
	end

	local toSave = deepCopy(data) :: any
	toSave.PedestalDisplays = pedestalDisplaysToDisk(data.PedestalDisplays)

	local key = "Player_" .. userId
	local attempt = 0
	local success, err

	repeat
		attempt += 1
		success, err = pcall(function()
			dataStore:SetAsync(key, toSave)
		end)
		if not success then
			warn(("PlayerDataService: save attempt %d/%d failed for %d: %s"):format(attempt, SAVE_RETRY_ATTEMPTS, userId, tostring(err)))
		end
	until success or attempt >= SAVE_RETRY_ATTEMPTS

	return success
end

local function saveAll()
	for userId, data in state.sessionCache do
		saveData(userId, data)
	end
end

--[[ Public API: data ----------------------------------------------------- ]]

function PlayerDataService.IsDataLoaded(player: Player): boolean
	return state.sessionCache[player.UserId] ~= nil
end

function PlayerDataService.GetData(player: Player): PlayerData?
	return state.sessionCache[player.UserId]
end

--[[ Public API: cash ----------------------------------------------------- ]]

function PlayerDataService.GetCash(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.Cash else 0
end

-- Mirrors the authoritative Cash value onto the player's leaderstats display.
local function updateLeaderstatsCash(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local cashValue = leaderstats and leaderstats:FindFirstChild("Cash")
	if cashValue and cashValue:IsA("IntValue") then
		cashValue.Value = math.floor(PlayerDataService.GetCash(player))
	end
end

function PlayerDataService.AddCash(player: Player, amount: number)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	data.Cash = math.max(0, data.Cash + amount)
	updateLeaderstatsCash(player)
end

-- Atomically checks-and-deducts; fails (no mutation) if funds are insufficient.
function PlayerDataService.SpendCash(player: Player, amount: number): boolean
	local data = state.sessionCache[player.UserId]
	if not data or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	updateLeaderstatsCash(player)
	return true
end

--[[ Public API: generators ----------------------------------------------- ]]

function PlayerDataService.GetGenerators(player: Player): { [string]: number }?
	local data = state.sessionCache[player.UserId]
	return if data then data.Generators else nil
end

function PlayerDataService.GetGeneratorLevel(player: Player, generatorId: string): number
	local generators = PlayerDataService.GetGenerators(player)
	return if generators then generators[generatorId] or 0 else 0
end

function PlayerDataService.SetGeneratorLevel(player: Player, generatorId: string, level: number)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	data.Generators[generatorId] = level
end

--[[ Public API: cash multiplier ------------------------------------------ ]]

-- Falls back to 0 so saves from before the Multiplier Pad existed still work.
function PlayerDataService.GetCashMultiplierLevel(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.CashMultiplierLevel or 0 else 0
end

function PlayerDataService.SetCashMultiplierLevel(player: Player, level: number)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	data.CashMultiplierLevel = level
end

--[[ Public API: inventory ------------------------------------------------ ]]

function PlayerDataService.GetInventory(player: Player): { InventoryItem }?
	local data = state.sessionCache[player.UserId]
	return if data then data.Inventory else nil
end

-- Looks up a single inventory entry by its Uid, or nil if the player doesn't
-- currently own an item with that Uid (already consumed, never owned, etc).
function PlayerDataService.GetItemByUid(player: Player, uid: string): InventoryItem?
	local inventory = PlayerDataService.GetInventory(player)
	if not inventory then
		return nil
	end
	for _, item in inventory do
		if item.Uid == uid then
			return item
		end
	end
	return nil
end

-- Atomically removes the exact items named by `uids`. Fails (no mutation) if
-- any uid isn't currently in the player's inventory - e.g. it was already
-- consumed by an earlier request.
function PlayerDataService.RemoveItemsByUid(player: Player, uids: { string }): (boolean, { InventoryItem })
	local inventory = PlayerDataService.GetInventory(player)
	if not inventory then
		return false, {}
	end

	for _, uid in uids do
		if not PlayerDataService.GetItemByUid(player, uid) then
			return false, {}
		end
	end

	local removedEntries: { InventoryItem } = {}
	for _, uid in uids do
		for index = #inventory, 1, -1 do
			if inventory[index].Uid == uid then
				table.insert(removedEntries, inventory[index])
				table.remove(inventory, index)
				break
			end
		end
	end

	return true, removedEntries
end

function PlayerDataService.AddItem(player: Player, itemId: string, tier: string): InventoryItem?
	local data = state.sessionCache[player.UserId]
	if not data then
		return nil
	end

	local entry: InventoryItem = {
		Uid = HttpService:GenerateGUID(false),
		ItemId = itemId,
		Tier = tier,
		InUse = false,
	}
	table.insert(data.Inventory, entry)
	return entry
end

-- Marks/unmarks an inventory item as "in use" (e.g. currently displayed on a
-- pedestal) so other systems - fusion in particular - can refuse to consume
-- an item that's doing something else elsewhere. Returns false if the uid
-- isn't currently owned.
function PlayerDataService.SetItemInUse(player: Player, uid: string, inUse: boolean): boolean
	local item = PlayerDataService.GetItemByUid(player, uid)
	if not item then
		return false
	end
	item.InUse = inUse
	return true
end

--[[ Public API: pedestal displays ---------------------------------------- ]]

-- Lazily initializes PedestalDisplays so saves from before the Pedestal
-- Showcase existed still work.
function PlayerDataService.GetPedestalDisplays(player: Player): { [number]: string? }
	local data = state.sessionCache[player.UserId]
	if not data then
		return {}
	end
	data.PedestalDisplays = data.PedestalDisplays or {}
	return data.PedestalDisplays
end

-- Sets pedestalIndex's displayed item Uid, or clears it if uid is nil.
function PlayerDataService.SetPedestalDisplay(player: Player, pedestalIndex: number, uid: string?)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	data.PedestalDisplays = data.PedestalDisplays or {}
	data.PedestalDisplays[pedestalIndex] = uid
end

--[[ Public API: gacha ---------------------------------------------------- ]]

function PlayerDataService.GetGachaPulls(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.GachaPulls else 0
end

function PlayerDataService.IncrementGachaPulls(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.GachaPulls += 1
	end
end

--[[ Public API: goals ---------------------------------------------------- ]]

function PlayerDataService.GetGoalIndex(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.GoalIndex else 1
end

function PlayerDataService.SetGoalIndex(player: Player, index: number)
	local data = state.sessionCache[player.UserId]
	if data then
		data.GoalIndex = index
	end
end

function PlayerDataService.GetTotalFusions(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.TotalFusions else 0
end

function PlayerDataService.IncrementTotalFusions(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.TotalFusions += 1
	end
end

-- Session-only progress readout for the current goal (nil once every goal is
-- done). Not saved: GoalService recomputes it on every sync.
function PlayerDataService.SetGoalProgress(player: Player, progress: GoalProgress?)
	state.goalProgress[player.UserId] = progress
end

--[[ Public API: income + sync -------------------------------------------- ]]

-- Tiers of the items currently on this player's pedestals.
function PlayerDataService.GetDisplayedTiers(player: Player): { string }
	local tiers = {}
	for _, uid in PlayerDataService.GetPedestalDisplays(player) do
		if uid then
			local item = PlayerDataService.GetItemByUid(player, uid)
			if item then
				table.insert(tiers, item.Tier)
			end
		end
	end
	return tiers
end

-- Generators + pedestals, multiplier applied: all of a player's income.
function PlayerDataService.GetPassiveCashPerSecond(player: Player): number
	local data = state.sessionCache[player.UserId]
	if not data then
		return 0
	end
	return TycoonConfig.GetPassiveCashPerSecond(
		data.Generators,
		PlayerDataService.GetDisplayedTiers(player),
		data.CashMultiplierLevel
	)
end

function PlayerDataService.GetTycoonSnapshot(player: Player): TycoonSnapshot
	return {
		Cash = PlayerDataService.GetCash(player),
		Generators = PlayerDataService.GetGenerators(player) or {},
		CashMultiplierLevel = PlayerDataService.GetCashMultiplierLevel(player),
		PedestalDisplays = pedestalDisplaysToDisk(PlayerDataService.GetPedestalDisplays(player)),
		GachaPulls = PlayerDataService.GetGachaPulls(player),
		GoalIndex = PlayerDataService.GetGoalIndex(player),
		GoalProgress = state.goalProgress[player.UserId],
	}
end

-- Registers `callback(player)` to run synchronously at the start of every
-- SyncTycoon, BEFORE the snapshot is built - so anything it changes (a goal
-- reward, the next goal's progress) goes out in that same snapshot. A plain
-- callback rather than a BindableEvent on purpose: under deferred signal
-- behaviour a BindableEvent handler would run after the snapshot was sent.
-- Callbacks must not call SyncTycoon themselves.
function PlayerDataService.OnSync(callback: (Player) -> ())
	table.insert(state.syncHooks, callback)
end

-- The one way every service pushes cash/upgrade state to a client.
function PlayerDataService.SyncTycoon(player: Player)
	if not state.sessionCache[player.UserId] then
		return
	end
	for _, hook in state.syncHooks do
		-- A failing hook must never stop the snapshot from going out.
		xpcall(hook, function(err)
			warn(("PlayerDataService: OnSync hook failed for %s: %s"):format(player.Name, tostring(err)))
		end, player)
	end
	RemoteEvents.SyncTycoon:FireClient(player, PlayerDataService.GetTycoonSnapshot(player))
end

--[[ Player lifecycle ----------------------------------------------------- ]]

local function createLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local cashValue = Instance.new("IntValue")
	cashValue.Name = "Cash"
	cashValue.Value = 0
	cashValue.Parent = leaderstats

	leaderstats.Parent = player
end

local dataLoaded = Instance.new("BindableEvent")
-- Fires (player) once a player's data is in the session cache. TycoonService
-- waits on this before restoring saved pedestals on claim.
PlayerDataService.DataLoaded = dataLoaded.Event

local function onPlayerAdded(player: Player)
	if not loadData(player) then
		return
	end
	createLeaderstats(player)
	updateLeaderstatsCash(player)

	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	PlayerDataService.SyncTycoon(player)
	dataLoaded:Fire(player)
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	local data = state.sessionCache[userId]
	state.sessionCache[userId] = nil
	if data then
		saveData(userId, data)
	end
	state.noSave[userId] = nil
	state.goalProgress[userId] = nil
	state.lastSyncRequest[userId] = nil
end

-- A client asking for a fresh snapshot (it just had a request rejected and
-- its view may be stale). At most once per SYNC_REQUEST_COOLDOWN_SECONDS.
local function onRequestSync(player: Player)
	local now = os.clock()
	local last = state.lastSyncRequest[player.UserId]
	if last and now - last < SYNC_REQUEST_COOLDOWN_SECONDS then
		return
	end
	state.lastSyncRequest[player.UserId] = now
	PlayerDataService.SyncTycoon(player)
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function PlayerDataService:Init()
	table.insert(state.connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	table.insert(state.connections, RemoteEvents.RequestSync.OnServerEvent:Connect(onRequestSync))

	-- Covers anyone who joined before this service finished initialising.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(saveAll)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL_SECONDS)
			saveAll()
		end
	end)
end

return PlayerDataService
