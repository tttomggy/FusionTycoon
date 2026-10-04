--!strict
--[[
	LeaderboardService
	------------------
	The three street leaderboards (StreetLayout.Leaderboard spots, built here
	at Init): 💰 BEST INCOME /s (PlayerData.BestIncome: the highest base
	income a save has reached), 🏆 MOST REBIRTHS and 📖 INDEX FOUND.

	  * Data: one OrderedDataStore per stat (LB_Income_1, LB_Rebirths_1,
	    LB_Index_1), keyed by UserId. Income is stored as
	    floor(log10(1 + $/s) * 1e12) so huge late-game numbers still fit an
	    integer and still sort.
	  * Writes: at most every WRITE_SECONDS (2 min) per player and only
	    when a value changed, plus on leave (PlayerDataService.OnRelease)
	    and on BindToClose (waits for them, bounded).
	  * Reads: the top 10 of each every READ_SECONDS (2 min); display names
	    (UserService) and headshots (GetUserThumbnailAsync) are cached.
	  * Studio: obvious fake rows ("TestPlayer1…") and no DataStore calls,
	    so the layout can be checked without API access.

	Follows ServiceTemplate:
	  :Init()   builds the boards (own folder), fake rows in Studio.
	  :Start()  resolves PlayerDataService, starts the write / read loops.
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local StreetLayout = require(ReplicatedStorage.Shared.Config.StreetLayout)
local IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))

type Stat = {
	Key: string,
	Title: string,
	TitleColor: Color3,
	StoreName: string,
	Encode: (value: number) -> number,
	Decode: (stored: number) -> number,
	Format: (value: number) -> string,
}

type State = {
	connections: { RBXScriptConnection },
	surfaces: { [string]: SurfaceGui },
	stores: { [string]: OrderedDataStore },
	-- Per player: the encoded value last written per stat, and when.
	lastWritten: { [number]: { [string]: number } },
	lastWriteAt: { [number]: number },
	names: { [number]: string },
	heads: { [number]: string },
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	connections = {},
	surfaces = {},
	stores = {},
	lastWritten = {},
	lastWriteAt = {},
	names = {},
	heads = {},
}

local WRITE_SECONDS = 120
local READ_SECONDS = 120
local TICK_SECONDS = 10
local FIRST_READ_DELAY = 5
local CLOSE_WAIT_SECONDS = 15
local TOP_COUNT = 10
local LOG_SCALE = 1e12
local FAKE_ROWS = 10

local Colors = UITheme.Colors
local World = UITheme.World

local PlayerDataService: PlayerDataServiceModule

local LeaderboardService = {}

LeaderboardService.Name = "LeaderboardService"

local function identity(value: number): number
	return math.max(0, math.floor(value))
end

local STATS: { [string]: Stat } = {
	Income = {
		Key = "Income",
		Title = "💰 BEST INCOME /s",
		TitleColor = Colors.Cash,
		StoreName = "LB_Income_1",
		Encode = function(value: number): number
			return math.floor(math.log10(1 + math.max(0, value)) * LOG_SCALE)
		end,
		Decode = function(stored: number): number
			return 10 ^ (stored / LOG_SCALE) - 1
		end,
		Format = function(value: number): string
			return NumberFormat.Money(value) .. "/s"
		end,
	},
	Rebirths = {
		Key = "Rebirths",
		Title = "🏆 MOST REBIRTHS",
		TitleColor = Colors.Rebirth,
		StoreName = "LB_Rebirths_1",
		Encode = identity,
		Decode = identity,
		Format = function(value: number): string
			return NumberFormat.Short(value)
		end,
	},
	Index = {
		Key = "Index",
		Title = "📖 INDEX FOUND",
		TitleColor = Colors.VioletLight,
		StoreName = "LB_Index_1",
		Encode = identity,
		Decode = identity,
		Format = function(value: number): string
			return ("%d / %d"):format(value, IndexConfig.GetTotalEntries())
		end,
	},
}

--[[ Boards ----------------------------------------------------------------- ]]

-- A board on two posts with a strip along its top (the Event Board look).
local function buildBoard(folder: Folder, spot: StreetLayout.LeaderboardSpot)
	local l = StreetLayout.Leaderboard
	local stat = STATS[spot.Key]
	local cframe = StreetLayout.GetLeaderboardCFrame(spot)
	local model = Instance.new("Model")
	model.Name = "Leaderboard_" .. spot.Key
	local board = PartKit.Part({
		Name = "Board",
		Size = Vector3.new(l.Width, l.Height, l.Thickness),
		CFrame = cframe,
		Color = World.Structure,
		Parent = model,
	})
	local strip = PartKit.Part({
		Name = "Strip",
		Size = Vector3.new(l.Width, 0.4, l.Thickness + 0.2),
		CFrame = cframe * CFrame.new(0, l.Height / 2 + 0.2, 0),
		Color = World.AccentGold,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	PartKit.MakeDecorative(strip)
	local postHeight = l.BottomY + l.Height
	for _, side in { -1, 1 } do
		PartKit.Part({
			Name = "Post",
			Size = Vector3.new(l.PostWidth, postHeight, l.PostWidth),
			CFrame = cframe * CFrame.new(side * (l.Width / 2 - l.PostWidth), -l.Height / 2 - l.BottomY + postHeight / 2, l.Thickness / 2 + l.PostWidth / 2),
			Color = World.StructureLight,
			Parent = model,
		})
	end
	state.surfaces[spot.Key] = BillboardKit.LeaderboardSurface(board, stat.Title, stat.TitleColor, l.PixelsPerStud, l.MaxDistance)
	model.PrimaryPart = board
	model.Parent = folder
end

local function fakeRows(stat: Stat): { BillboardKit.LeaderboardRow }
	local rows = {}
	for rank = 1, FAKE_ROWS do
		local value = if stat.Key == "Income"
			then 10 ^ (13 - rank)
			elseif stat.Key == "Rebirths" then 50 - rank * 4
			else IndexConfig.GetTotalEntries() - rank * 7
		table.insert(rows, { Rank = rank, Name = ("TestPlayer%d"):format(rank), Value = stat.Format(value), Image = "" })
	end
	return rows
end

--[[ Writes ----------------------------------------------------------------- ]]

local function currentValues(player: Player): { [string]: number }?
	local data = PlayerDataService.GetData(player)
	if not data then
		return nil
	end
	return {
		Income = data.BestIncome,
		Rebirths = data.Rebirths,
		Index = IndexConfig.CountFound(data.Index),
	}
end

-- Writes `player`'s changed stats (yields: call on its own thread).
-- `values` is captured by the caller, so a leaving player still writes.
local function writeValues(userId: number, values: { [string]: number })
	local written = state.lastWritten[userId] or {}
	state.lastWritten[userId] = written
	state.lastWriteAt[userId] = os.clock()
	for key, value in values do
		local stat = STATS[key]
		local store = state.stores[key]
		local encoded = stat.Encode(value)
		if store and encoded > 0 and written[key] ~= encoded then
			local ok, err = pcall(function()
				store:SetAsync(tostring(userId), encoded)
			end)
			if ok then
				written[key] = encoded
			else
				warn(("LeaderboardService: %s write failed for %d (%s)"):format(stat.StoreName, userId, tostring(err)))
			end
		end
	end
end

local function hasStores(): boolean
	return next(state.stores) ~= nil
end

local function onTick()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if PlayerDataService.IsDataLoaded(player) then
			PlayerDataService.RecordBestIncome(player, PlayerDataService.GetBasePassiveCashPerSecond(player))
			local last = state.lastWriteAt[player.UserId]
			if hasStores() and (not last or now - last >= WRITE_SECONDS) then
				local values = currentValues(player)
				if values then
					state.lastWriteAt[player.UserId] = now
					task.spawn(writeValues, player.UserId, values)
				end
			end
		end
	end
end

local function onRelease(player: Player)
	local values = currentValues(player)
	local userId = player.UserId
	if values and hasStores() then
		task.spawn(function()
			writeValues(userId, values)
			state.lastWritten[userId] = nil
			state.lastWriteAt[userId] = nil
		end)
	end
end

--[[ Reads ------------------------------------------------------------------ ]]

local function resolveNames(userIds: { number })
	local missing = {}
	for _, userId in userIds do
		if not state.names[userId] then
			table.insert(missing, userId)
		end
	end
	if #missing > 0 then
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(missing)
		end)
		if ok and typeof(infos) == "table" then
			for _, info in infos :: { any } do
				state.names[info.Id] = info.DisplayName
			end
		end
	end
	for _, userId in userIds do
		if not state.heads[userId] then
			local ok, image = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and typeof(image) == "string" then
				state.heads[userId] = image
			end
		end
	end
end

local function readBoard(stat: Stat)
	local store = state.stores[stat.Key]
	local surface = state.surfaces[stat.Key]
	if not store or not surface then
		return
	end
	local ok, entries = pcall(function()
		return store:GetSortedAsync(false, TOP_COUNT):GetCurrentPage()
	end)
	if not ok or typeof(entries) ~= "table" then
		warn(("LeaderboardService: %s read failed (%s)"):format(stat.StoreName, tostring(entries)))
		return
	end
	local ids: { number } = {}
	for _, entry in entries :: { any } do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(ids, userId)
		end
	end
	resolveNames(ids)
	local rows: { BillboardKit.LeaderboardRow } = {}
	for _, entry in entries :: { any } do
		local userId = tonumber(entry.key)
		if userId and typeof(entry.value) == "number" then
			table.insert(rows, {
				Rank = #rows + 1,
				Name = state.names[userId] or ("Player %d"):format(userId),
				Value = stat.Format(stat.Decode(entry.value)),
				Image = state.heads[userId] or "",
			})
		end
	end
	BillboardKit.SetLeaderboard(surface, rows)
end

local function readAll()
	for _, stat in STATS do
		readBoard(stat)
	end
end

local function onClose()
	if not hasStores() then
		return
	end
	local pending = 0
	for _, player in Players:GetPlayers() do
		local values = currentValues(player)
		if values then
			pending += 1
			task.spawn(function()
				writeValues(player.UserId, values)
				pending -= 1
			end)
		end
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < CLOSE_WAIT_SECONDS do
		task.wait(0.2)
	end
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function LeaderboardService:Init()
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	for _, spot in StreetLayout.Leaderboard.Spots do
		buildBoard(folder, spot)
	end
	folder.Parent = Workspace

	if RunService:IsStudio() then
		for key, surface in state.surfaces do
			BillboardKit.SetLeaderboard(surface, fakeRows(STATS[key]))
		end
		return
	end
	for key, stat in STATS do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(stat.StoreName)
		end)
		if ok then
			state.stores[key] = store
		else
			warn(("LeaderboardService: no %s (%s)"):format(stat.StoreName, tostring(store)))
		end
	end
end

function LeaderboardService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	PlayerDataService.OnRelease(onRelease)
	game:BindToClose(onClose)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			onTick()
		end
	end)
	if hasStores() then
		task.spawn(function()
			task.wait(FIRST_READ_DELAY)
			while true do
				readAll()
				task.wait(READ_SECONDS)
			end
		end)
	end
end

function LeaderboardService:Stop()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
end

return LeaderboardService
