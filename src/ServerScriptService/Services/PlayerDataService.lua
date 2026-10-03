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
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
local OfflineConfig = require(ReplicatedStorage.Shared.Config.OfflineConfig)
local TipConfig = require(ReplicatedStorage.Shared.Config.TipConfig)

--[[ Types ---------------------------------------------------------------- ]]

-- Exported so other services stop typing inventory entries as `any`.
export type InventoryItem = {
	Uid: string,
	ItemId: string,
	Tier: string,
	InUse: boolean,
	-- MutationConfig name ("Golden", "Diamond", "Rainbow"); nil = normal.
	Mutation: string?,
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
	-- Heist: items delivered home, and shields raised with LOCK (console or HUD button)
	-- (drive the first_steal / first_shield goals).
	TotalSteals: number,
	ShieldRaises: number,
	-- One-time tips/cards already shown (TipConfig ids -> true).
	Tips: { [string]: boolean },
	-- How many times the player has rebirthed (RebirthConfig).
	Rebirths: number,
	-- Index entries found ("<itemId>|<Mutation or Normal>" -> true). Kept
	-- through rebirths; see IndexConfig.
	Index: { [string]: boolean },
	-- os.time() when this profile was last saved (every autosave and on
	-- leaving) or loaded. nil on old saves: no offline payout the first time.
	LastOnline: number?,
}

-- Offline earnings waiting to be collected (session only, never saved).
export type PendingOffline = {
	Amount: number,
	AwaySeconds: number,
	Since: number, -- os.clock() when it was computed (auto-claim timer)
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
	Rebirths: number,
	-- Found Index keys as a dense list (the client builds the set and
	-- computes the Index multiplier).
	IndexKeys: { string },
	-- Offline earnings not yet collected (0 = none) and the away time they
	-- cover, for the welcome-back card.
	PendingOffline: number,
	AwaySeconds: number,
	-- Uids of this player's displayed items a thief is carrying right now:
	-- they earn nothing until back (the client's income skips them too).
	CarriedUids: { string },
	-- One-time tips already seen (TipConfig ids), as a dense list.
	TipKeys: { string },
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
	-- Session-only: offline earnings computed on load, until claimed.
	pendingOffline: { [number]: PendingOffline },
	-- Session-only heist flags HeistService sets (it owns the heist state;
	-- these are the parts income, sync and other services' guards need):
	-- each owner's displayed Uids being carried, and who is carrying.
	carriedUids: { [number]: { [string]: boolean } },
	carrying: { [number]: boolean },
	-- Called synchronously before a player's data is saved and released
	-- (leaving, or the server closing). See OnRelease.
	releaseHooks: { (Player) -> () },
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
	TotalSteals = 0,
	ShieldRaises = 0,
	Tips = {},
	Rebirths = 0,
	Index = {},
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	sessionCache = {},
	noSave = {},
	goalProgress = {},
	pendingOffline = {},
	carriedUids = {},
	carrying = {},
	releaseHooks = {},
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
	if typeof(raw.TotalSteals) == "number" then
		data.TotalSteals = raw.TotalSteals
	end
	if typeof(raw.ShieldRaises) == "number" then
		data.ShieldRaises = raw.ShieldRaises
	end
	if typeof(raw.Tips) == "table" then
		for id, seen in raw.Tips do
			if seen == true and TipConfig.IsValid(id) then
				data.Tips[id] = true
			end
		end
	end
	if typeof(raw.Rebirths) == "number" and raw.Rebirths >= 0 then
		data.Rebirths = math.floor(raw.Rebirths)
	end
	if typeof(raw.LastOnline) == "number" then
		data.LastOnline = raw.LastOnline
	end
	if typeof(raw.Index) == "table" then
		for key, found in raw.Index do
			if found == true and IndexConfig.IsValidKey(key) then
				data.Index[key] = true
			end
		end
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
		-- Old saves have no mutation; an unknown one (renamed/removed) is
		-- dropped rather than left to break lookups.
		if item.Mutation ~= nil and not MutationConfig.IsValid(item.Mutation) then
			item.Mutation = nil
		end
		-- Backfill: everything already owned counts as found.
		data.Index[IndexConfig.GetKey(item.ItemId, item.Mutation)] = true
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
	data.LastOnline = os.time()

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

-- Saves `player`'s data now, on its own thread (never yields the caller).
-- RebirthService calls it so a rebirth can't be lost to a crash.
function PlayerDataService.SaveNow(player: Player)
	local userId = player.UserId
	local data = state.sessionCache[userId]
	if data then
		task.spawn(saveData, userId, data)
	end
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

local function updateLeaderstatsRebirths(player: Player)
	local data = state.sessionCache[player.UserId]
	local leaderstats = player:FindFirstChild("leaderstats")
	local rebirthsValue = leaderstats and leaderstats:FindFirstChild("Rebirths")
	if data and rebirthsValue and rebirthsValue:IsA("IntValue") then
		rebirthsValue.Value = data.Rebirths
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

-- Adds an item and marks its Index entry. Returns (entry, isNewIndexEntry).
function PlayerDataService.AddItem(
	player: Player,
	itemId: string,
	tier: string,
	mutation: string?
): (InventoryItem?, boolean)
	local data = state.sessionCache[player.UserId]
	if not data then
		return nil, false
	end

	local entry: InventoryItem = {
		Uid = HttpService:GenerateGUID(false),
		ItemId = itemId,
		Tier = tier,
		InUse = false,
		Mutation = if MutationConfig.IsValid(mutation) then mutation else nil,
	}
	table.insert(data.Inventory, entry)
	local key = IndexConfig.GetKey(itemId, entry.Mutation)
	local isNew = not data.Index[key]
	data.Index[key] = true
	return entry, isNew
end

function PlayerDataService.GetIndex(player: Player): { [string]: boolean }
	local data = state.sessionCache[player.UserId]
	return if data then data.Index else {}
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

--[[ Public API: rebirth -------------------------------------------------- ]]

function PlayerDataService.GetRebirths(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.Rebirths else 0
end

-- Studio debug (/rebirths <n>).
function PlayerDataService.SetRebirths(player: Player, rebirths: number)
	local data = state.sessionCache[player.UserId]
	if data then
		data.Rebirths = math.max(0, math.floor(rebirths))
		updateLeaderstatsRebirths(player)
	end
end

-- Applies a rebirth in one go, with no yields: RebirthService validates
-- first (cash >= RebirthConfig.GetCost), then calls this. Resets the run:
-- cash to 0 (which pays the price), generators to Basic at
-- `startingBasicLevel`, the Multiplier Pad and the gacha price; adds a
-- rebirth. Inventory, pedestals, goals and everything else stay.
-- Returns the new rebirth count.
function PlayerDataService.ApplyRebirth(player: Player, startingBasicLevel: number): number
	local data = state.sessionCache[player.UserId]
	if not data then
		return 0
	end
	data.Cash = 0
	data.Generators = { basic_generator = startingBasicLevel }
	data.CashMultiplierLevel = 0
	data.GachaPulls = 0
	data.Rebirths += 1
	updateLeaderstatsCash(player)
	updateLeaderstatsRebirths(player)
	return data.Rebirths
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

-- Marks a one-time tip seen (TipConfig ids only).
function PlayerDataService.MarkTipSeen(player: Player, id: string)
	local data = state.sessionCache[player.UserId]
	if data and TipConfig.IsValid(id) then
		data.Tips[id] = true
	end
end

-- Studio /tips reset.
function PlayerDataService.ResetTips(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.Tips = {}
	end
end

-- A heist delivered (HeistService).
function PlayerDataService.IncrementTotalSteals(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.TotalSteals += 1
	end
end

-- A shield raised with LOCK (HeistService.TryLock).
function PlayerDataService.IncrementShieldRaises(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.ShieldRaises += 1
	end
end

-- Session-only progress readout for the current goal (nil once every goal is
-- done). Not saved: GoalService recomputes it on every sync.
function PlayerDataService.SetGoalProgress(player: Player, progress: GoalProgress?)
	state.goalProgress[player.UserId] = progress
end

--[[ Public API: income + sync -------------------------------------------- ]]

-- Tiers of the items currently on this player's pedestals.
-- Tier and mutation of every item on the player's pedestals.
function PlayerDataService.GetDisplayedItems(player: Player): { TycoonConfig.PedestalItem }
	local items = {}
	local carried = state.carriedUids[player.UserId]
	for _, uid in PlayerDataService.GetPedestalDisplays(player) do
		-- A pedestal whose item is being carried off earns nothing.
		if uid and not (carried and carried[uid]) then
			local item = PlayerDataService.GetItemByUid(player, uid)
			if item then
				table.insert(items, { Tier = item.Tier, Mutation = item.Mutation })
			end
		end
	end
	return items
end

-- The one place the server builds TycoonConfig.IncomeInputs. nil until the
-- player's data has loaded.
function PlayerDataService.GetIncomeInputs(player: Player): TycoonConfig.IncomeInputs?
	local data = state.sessionCache[player.UserId]
	if not data then
		return nil
	end
	return {
		GeneratorLevels = data.Generators,
		PedestalItems = PlayerDataService.GetDisplayedItems(player),
		CashMultiplierLevel = data.CashMultiplierLevel,
		Rebirths = data.Rebirths,
		IndexMultiplier = IndexConfig.GetMultiplier(data.Index),
	}
end

-- Pad x rebirth: the multiplier every per-generator/per-item number shows.
function PlayerDataService.GetIncomeMultiplier(player: Player): number
	local inputs = PlayerDataService.GetIncomeInputs(player)
	return if inputs then TycoonConfig.GetIncomeMultiplier(inputs) else 1
end

-- Generators + pedestals, multiplier applied: all of a player's income.
function PlayerDataService.GetPassiveCashPerSecond(player: Player): number
	local inputs = PlayerDataService.GetIncomeInputs(player)
	return if inputs then TycoonConfig.GetPassiveCashPerSecond(inputs) else 0
end

local function indexKeys(index: { [string]: boolean }): { string }
	local keys = {}
	for key in index do
		table.insert(keys, key)
	end
	return keys
end

function PlayerDataService.GetTycoonSnapshot(player: Player): TycoonSnapshot
	local pending = state.pendingOffline[player.UserId]
	local data = state.sessionCache[player.UserId]
	return {
		Cash = PlayerDataService.GetCash(player),
		Generators = PlayerDataService.GetGenerators(player) or {},
		CashMultiplierLevel = PlayerDataService.GetCashMultiplierLevel(player),
		PedestalDisplays = pedestalDisplaysToDisk(PlayerDataService.GetPedestalDisplays(player)),
		GachaPulls = PlayerDataService.GetGachaPulls(player),
		GoalIndex = PlayerDataService.GetGoalIndex(player),
		GoalProgress = state.goalProgress[player.UserId],
		Rebirths = PlayerDataService.GetRebirths(player),
		IndexKeys = indexKeys(PlayerDataService.GetIndex(player)),
		PendingOffline = if pending then pending.Amount else 0,
		AwaySeconds = if pending then pending.AwaySeconds else 0,
		CarriedUids = indexKeys(state.carriedUids[player.UserId] or {}),
		TipKeys = indexKeys(data and data.Tips or {}),
	}
end

--[[ Public API: heist flags ---------------------------------------------- ]]
-- HeistService owns the heist; these flags are what the rest of the server
-- needs to see of it without referencing HeistService (income, sync, and
-- the "not while carrying / being stolen" guards in other services).

-- Marks one of `owner`'s displayed items as being carried off (or not).
function PlayerDataService.SetItemCarried(owner: Player, uid: string, carried: boolean)
	local set = state.carriedUids[owner.UserId]
	if carried then
		if not set then
			set = {}
			state.carriedUids[owner.UserId] = set
		end
		set[uid] = true
	elseif set then
		set[uid] = nil
		if next(set) == nil then
			state.carriedUids[owner.UserId] = nil
		end
	end
end

function PlayerDataService.IsItemCarried(owner: Player, uid: string): boolean
	local set = state.carriedUids[owner.UserId]
	return set ~= nil and set[uid] == true
end

-- Any of `owner`'s items is being carried right now.
function PlayerDataService.HasCarriedItems(owner: Player): boolean
	return state.carriedUids[owner.UserId] ~= nil
end

-- `player` is carrying a stolen item (can't pull, fuse, upgrade or rebirth).
function PlayerDataService.SetCarrying(player: Player, carrying: boolean)
	if carrying then
		state.carrying[player.UserId] = true
	else
		state.carrying[player.UserId] = nil
	end
end

function PlayerDataService.IsCarrying(player: Player): boolean
	return state.carrying[player.UserId] == true
end

-- Registers `callback(player)` to run synchronously before `player`'s data
-- is saved and released: at the start of PlayerRemoving, and for every
-- loaded player when the server closes. HeistService fails active carries
-- here, so a save never races a half-finished steal.
function PlayerDataService.OnRelease(callback: (Player) -> ())
	table.insert(state.releaseHooks, callback)
end

local function runReleaseHooks(player: Player)
	for _, hook in state.releaseHooks do
		xpcall(hook, function(err)
			warn(("PlayerDataService: OnRelease hook failed for %s: %s"):format(player.Name, tostring(err)))
		end, player)
	end
end

--[[ Public API: offline earnings ------------------------------------------ ]]

-- Uncollected offline earnings, or nil.
function PlayerDataService.GetPendingOffline(player: Player): PendingOffline?
	return state.pendingOffline[player.UserId]
end

-- Replaces the pending offline earnings (0 clears them). /offline uses it.
function PlayerDataService.SetPendingOffline(player: Player, amount: number, awaySeconds: number)
	if amount > 0 then
		state.pendingOffline[player.UserId] = { Amount = amount, AwaySeconds = awaySeconds, Since = os.clock() }
	else
		state.pendingOffline[player.UserId] = nil
	end
end

-- Clears the pending offline earnings and returns the amount (0 if none).
-- The caller pays it; taking and paying happen with no yield between them.
function PlayerDataService.TakePendingOffline(player: Player): number
	local pending = state.pendingOffline[player.UserId]
	state.pendingOffline[player.UserId] = nil
	return if pending then pending.Amount else 0
end

-- On load: what the lab earned while away, at the income the player left
-- with. LastOnline moves to now straight away (and is saved), so a rejoin
-- can't claim the same time twice.
local function computeOfflineEarnings(player: Player)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	local lastOnline = data.LastOnline
	data.LastOnline = os.time()
	if not lastOnline then
		return
	end
	local away = math.max(0, os.time() - lastOnline)
	local amount = OfflineConfig.Compute(PlayerDataService.GetPassiveCashPerSecond(player), away)
	PlayerDataService.SetPendingOffline(player, amount, away)
	if amount > 0 then
		PlayerDataService.SaveNow(player)
	end
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

	-- Created before Cash so it's the first leaderboard column.
	local rebirthsValue = Instance.new("IntValue")
	rebirthsValue.Name = "Rebirths"
	rebirthsValue.Value = 0
	rebirthsValue.Parent = leaderstats

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
	updateLeaderstatsRebirths(player)
	computeOfflineEarnings(player)

	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	PlayerDataService.SyncTycoon(player)
	dataLoaded:Fire(player)
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	-- Before anything is saved: active steals on either side resolve first.
	runReleaseHooks(player)
	state.carriedUids[userId] = nil
	state.carrying[userId] = nil
	local data = state.sessionCache[userId]
	-- Left before collecting (or before the auto-claim): pay it, never lose it.
	local pending = state.pendingOffline[userId]
	if data and pending then
		data.Cash += pending.Amount
	end
	state.pendingOffline[userId] = nil
	state.sessionCache[userId] = nil
	if data then
		saveData(userId, data)
	end
	state.noSave[userId] = nil
	state.goalProgress[userId] = nil
	state.lastSyncRequest[userId] = nil
end

-- A client asking for a fresh snapshot (it just had a request rejected and
-- its view may be stale): the inventory too, since InUse lives there. At
-- most once per SYNC_REQUEST_COOLDOWN_SECONDS.
local function onRequestSync(player: Player)
	local now = os.clock()
	local last = state.lastSyncRequest[player.UserId]
	if last and now - last < SYNC_REQUEST_COOLDOWN_SECONDS then
		return
	end
	state.lastSyncRequest[player.UserId] = now
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	PlayerDataService.SyncTycoon(player)
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function PlayerDataService:Init()
	table.insert(state.connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	table.insert(state.connections, RemoteEvents.RequestSync.OnServerEvent:Connect(onRequestSync))
	-- MarkTipSeen { Id }: only TipConfig ids are stored; no reply needed (the
	-- client marks it locally too, and the next snapshot carries it).
	table.insert(
		state.connections,
		RemoteEvents.MarkTipSeen.OnServerEvent:Connect(function(player: Player, payload: unknown)
			local id = typeof(payload) == "table" and (payload :: any).Id or nil
			if TipConfig.IsValid(id) then
				PlayerDataService.MarkTipSeen(player, id :: string)
			end
		end)
	)

	-- Covers anyone who joined before this service finished initialising.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Release hooks (active steals fail and return) run before any save.
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			if state.sessionCache[player.UserId] then
				runReleaseHooks(player)
			end
		end
		saveAll()
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL_SECONDS)
			saveAll()
		end
	end)
end

return PlayerDataService
