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
	Inventory = {}, -- array of { Uid: string, ItemId: string, Tier: string }
	Generators = {}, -- map of generatorId -> level
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

function PlayerDataService.GetInventory(player: Player): { any }?
	local data = sessionCache[player.UserId]
	return data and data.Inventory or nil
end

function PlayerDataService.CountItemsOfTier(player: Player, tier: string): number
	local inventory = PlayerDataService.GetInventory(player)
	if not inventory then
		return 0
	end

	local count = 0
	for _, item in inventory do
		if item.Tier == tier then
			count += 1
		end
	end
	return count
end

-- Removes up to `count` items of `tier`. Fails atomically: if the player doesn't have
-- enough, nothing is removed.
function PlayerDataService.RemoveItemsOfTier(player: Player, tier: string, count: number): (boolean, { string })
	local inventory = PlayerDataService.GetInventory(player)
	if not inventory or PlayerDataService.CountItemsOfTier(player, tier) < count then
		return false, {}
	end

	local removedUids = {}
	for index = #inventory, 1, -1 do
		if #removedUids >= count then
			break
		end
		if inventory[index].Tier == tier then
			table.insert(removedUids, inventory[index].Uid)
			table.remove(inventory, index)
		end
	end

	return true, removedUids
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
	}
	table.insert(data.Inventory, entry)
	return entry
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
