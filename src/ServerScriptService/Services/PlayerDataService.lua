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

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

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
}

type State = {
	-- In-memory cache keyed by UserId; the source of truth while a player is
	-- in-session. Private: never exposed on the service table.
	sessionCache: { [number]: PlayerData },
	connections: { RBXScriptConnection },
}

--[[ Constants ------------------------------------------------------------ ]]

local DATASTORE_NAME = "PlayerData_v1"
local SAVE_RETRY_ATTEMPTS = 3
local AUTOSAVE_INTERVAL_SECONDS = 120

local dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

local DEFAULT_DATA: PlayerData = {
	Cash = 0,
	Inventory = {},
	Generators = {},
	CashMultiplierLevel = 0,
	PedestalDisplays = {},
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	sessionCache = {},
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

local function loadData(player: Player)
	local key = "Player_" .. player.UserId
	local success, result = pcall(function()
		return dataStore:GetAsync(key)
	end)

	if success and result then
		state.sessionCache[player.UserId] = result :: PlayerData
	else
		if not success then
			warn(("PlayerDataService: failed to load data for %s (%d): %s"):format(player.Name, player.UserId, tostring(result)))
		end
		state.sessionCache[player.UserId] = deepCopy(DEFAULT_DATA)
	end
end

local function saveData(userId: number, data: PlayerData?): boolean
	if not data then
		return false
	end

	local key = "Player_" .. userId
	local attempt = 0
	local success, err

	repeat
		attempt += 1
		success, err = pcall(function()
			dataStore:SetAsync(key, data)
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

local function onPlayerAdded(player: Player)
	loadData(player)
	createLeaderstats(player)
	updateLeaderstatsCash(player)

	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	RemoteEvents.SyncTycoon:FireClient(player, {
		Cash = PlayerDataService.GetCash(player),
		Generators = PlayerDataService.GetGenerators(player) or {},
		CashMultiplierLevel = PlayerDataService.GetCashMultiplierLevel(player),
		PedestalDisplays = PlayerDataService.GetPedestalDisplays(player),
	})
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	local data = state.sessionCache[userId]
	state.sessionCache[userId] = nil
	if data then
		saveData(userId, data)
	end
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function PlayerDataService:Init()
	table.insert(state.connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))

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
