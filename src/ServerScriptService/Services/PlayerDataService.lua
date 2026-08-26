local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

local PlayerDataService = {}

local DATASTORE_NAME = "PlayerData_v1"
local SAVE_RETRY_ATTEMPTS = 3
local AUTOSAVE_INTERVAL_SECONDS = 120

local dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

local DEFAULT_DATA = {
	Cash = 0,
	Inventory = {}, -- array of { Uid: string, ItemId: string, Tier: string, InUse: boolean }
	Generators = {}, -- map of generatorId -> level
	CashMultiplierLevel = 0, -- Multiplier Pad level; see TycoonConfig.GetCashMultiplierValue
	PedestalDisplays = {}, -- map of pedestalIndex -> displayed item's Uid
}

-- In-memory cache keyed by UserId; the source of truth while a player is in-session.
local sessionCache: { [number]: any } = {}

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, nested in value do
		copy[key] = deepCopy(nested)
	end
	return copy
end

local function loadData(player: Player)
	local key = "Player_" .. player.UserId
	local success, result = pcall(function()
		return dataStore:GetAsync(key)
	end)

	if success and result then
		sessionCache[player.UserId] = result
	else
		if not success then
			warn(("PlayerDataService: failed to load data for %s (%d): %s"):format(player.Name, player.UserId, tostring(result)))
		end
		sessionCache[player.UserId] = deepCopy(DEFAULT_DATA)
	end
end

local function saveData(userId: number, data: any): boolean
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

function PlayerDataService.IsDataLoaded(player: Player): boolean
	return sessionCache[player.UserId] ~= nil
end

function PlayerDataService.GetData(player: Player): any
	return sessionCache[player.UserId]
end

-- Mirrors the authoritative Cash value onto the player's leaderstats display.
local function updateLeaderstatsCash(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local cashValue = leaderstats and leaderstats:FindFirstChild("Cash")
	if cashValue then
		(cashValue :: IntValue).Value = math.floor(PlayerDataService.GetCash(player))
	end
end

function PlayerDataService.GetCash(player: Player): number
	local data = sessionCache[player.UserId]
	return data and data.Cash or 0
end

function PlayerDataService.AddCash(player: Player, amount: number)
	local data = sessionCache[player.UserId]
	if not data then
		return
	end
	data.Cash = math.max(0, data.Cash + amount)
	updateLeaderstatsCash(player)
end

-- Atomically checks-and-deducts; fails (no mutation) if funds are insufficient.
function PlayerDataService.SpendCash(player: Player, amount: number): boolean
	local data = sessionCache[player.UserId]
	if not data or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	updateLeaderstatsCash(player)
	return true
end

function PlayerDataService.GetGenerators(player: Player): { [string]: number }?
	local data = sessionCache[player.UserId]
	return data and data.Generators or nil
end

function PlayerDataService.GetGeneratorLevel(player: Player, generatorId: string): number
	local generators = PlayerDataService.GetGenerators(player)
	return generators and generators[generatorId] or 0
end

function PlayerDataService.SetGeneratorLevel(player: Player, generatorId: string, level: number)
	local data = sessionCache[player.UserId]
	if not data then
		return
	end
	data.Generators[generatorId] = level
end

-- Falls back to 0 so saves from before the Multiplier Pad existed still work.
function PlayerDataService.GetCashMultiplierLevel(player: Player): number
	local data = sessionCache[player.UserId]
	return data and data.CashMultiplierLevel or 0
end

function PlayerDataService.SetCashMultiplierLevel(player: Player, level: number)
	local data = sessionCache[player.UserId]
	if not data then
		return
	end
	data.CashMultiplierLevel = level
end

function PlayerDataService.GetInventory(player: Player): { any }?
	local data = sessionCache[player.UserId]
	return data and data.Inventory or nil
end

-- Looks up a single inventory entry by its Uid, or nil if the player doesn't
-- currently own an item with that Uid (already consumed, never owned, etc).
function PlayerDataService.GetItemByUid(player: Player, uid: string): any
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
function PlayerDataService.RemoveItemsByUid(player: Player, uids: { string }): (boolean, { any })
	local inventory = PlayerDataService.GetInventory(player)
	if not inventory then
		return false, {}
	end

	for _, uid in uids do
		if not PlayerDataService.GetItemByUid(player, uid) then
			return false, {}
		end
	end

	local removedEntries = {}
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

function PlayerDataService.AddItem(player: Player, itemId: string, tier: string): any
	local data = sessionCache[player.UserId]
	if not data then
		return nil
	end

	local entry = {
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

-- Lazily initializes PedestalDisplays so saves from before the Pedestal
-- Showcase existed still work.
function PlayerDataService.GetPedestalDisplays(player: Player): { [number]: string }
	local data = sessionCache[player.UserId]
	if not data then
		return {}
	end
	data.PedestalDisplays = data.PedestalDisplays or {}
	return data.PedestalDisplays
end

-- Sets pedestalIndex's displayed item Uid, or clears it if uid is nil.
function PlayerDataService.SetPedestalDisplay(player: Player, pedestalIndex: number, uid: string?)
	local data = sessionCache[player.UserId]
	if not data then
		return
	end
	data.PedestalDisplays = data.PedestalDisplays or {}
	data.PedestalDisplays[pedestalIndex] = uid
end

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
	local data = sessionCache[userId]
	sessionCache[userId] = nil
	if data then
		saveData(userId, data)
	end
end

function PlayerDataService.Init()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		for userId, data in sessionCache do
			saveData(userId, data)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL_SECONDS)
			for userId, data in sessionCache do
				saveData(userId, data)
			end
		end
	end)
end

return PlayerDataService
