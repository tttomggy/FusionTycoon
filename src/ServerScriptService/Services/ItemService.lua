--!nonstrict
--[[
	ItemService
	-----------
	Pedestals show the player's best items automatically (Playtest 7):
	highest $/s first (TycoonConfig.GetItemCashPerSecond), filling spots 1
	-> 4 (-> 6 with the +2 Pedestals pass). Players never choose; there are
	no place / remove requests any more.

	ItemService.Arrange(player) is the ONE function that decides it. It runs
	inside every sync (a PlayerDataService.OnSync hook), so a pull, fusion,
	Fuse All / Auto-Fuse, delivery, theft, event mutation, rebirth, reward
	item or /give lands on the pedestals in the same snapshot. A carried
	item (a heist in progress) stays on its pedestal, marked BeingStolen,
	until the heist ends; that pedestal is never re-arranged meanwhile.

	Follows the ServiceTemplate contract:
	  :Init()   nothing cross-service.
	  :Start()  resolves PlayerDataService and TycoonService, registers the
	            sync hook.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local ItemConfig = require(Config.ItemConfig)
local TycoonConfig = require(Config.TycoonConfig)
local RarityVisuals = require(Config.RarityVisuals)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))

-- Resolved in :Start(), not at module scope. Identifier names unchanged, so
-- every call site below reads exactly as before.
local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule

local ItemService = {}

ItemService.Name = "ItemService"

local function getPedestalPart(plot: Model, pedestalIndex: number): BasePart?
	local pedestalsFolder = plot:FindFirstChild("Pedestals")
	if not pedestalsFolder then
		return nil
	end
	local pedestal = pedestalsFolder:FindFirstChild("Pedestal" .. pedestalIndex)
	if pedestal and pedestal:IsA("BasePart") then
		return pedestal :: BasePart
	end
	return nil
end

local function announceDisplay(player: Player, item: any)
	local visualConfig = RarityVisuals.Tiers[item.Tier]
	if not visualConfig or not visualConfig.AnnounceServerWide then
		return
	end
	local itemConfigEntry = ItemConfig.GetItemById(item.ItemId)
	local itemName = itemConfigEntry and itemConfigEntry.Name or item.ItemId
	RemoteEvents.RareFusionAnnouncement:FireAllClients({
		Message = ("%s just displayed a %s %s!"):format(player.DisplayName, item.Tier:upper(), itemName),
		Tier = item.Tier,
		Mutation = item.Mutation,
		-- Parts, so the client can colour the tier word.
		PlayerName = player.DisplayName,
		Verb = "displayed",
		ItemName = itemName,
	})
end

-- The order pedestals fill in: $/s, then tier, then whatever is already up
-- (no needless shuffling between equals), then Uid (stable).
local function better(a: any, b: any, currentIndex: { [string]: number }): boolean
	local rateA = TycoonConfig.GetItemCashPerSecond(a.Tier, a.Mutation)
	local rateB = TycoonConfig.GetItemCashPerSecond(b.Tier, b.Mutation)
	if rateA ~= rateB then
		return rateA > rateB
	end
	local tierA, tierB = ItemConfig.Tiers[a.Tier] or 0, ItemConfig.Tiers[b.Tier] or 0
	if tierA ~= tierB then
		return tierA > tierB
	end
	local indexA, indexB = currentIndex[a.Uid] or math.huge, currentIndex[b.Uid] or math.huge
	if indexA ~= indexB then
		return indexA < indexB
	end
	return a.Uid < b.Uid
end

-- The one re-arrange: pedestals 1..count get the best free items in order;
-- a carried item's pedestal is left exactly as it is. Updates the data
-- (displays + InUse), the visuals of every pedestal that changed, the
-- labels, and the client's inventory tags. Never syncs (it runs inside one).
function ItemService.Arrange(player: Player)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	local inventory = PlayerDataService.GetInventory(player)
	if not inventory then
		return
	end
	local displays = PlayerDataService.GetPedestalDisplays(player)
	local count = PlayerDataService.GetPedestalCount(player)

	-- Pedestals held by a heist, and the items on them.
	local fixed: { [number]: string } = {}
	local fixedUids: { [string]: boolean } = {}
	for index, uid in displays do
		if PlayerDataService.IsItemCarried(player, uid) then
			fixed[index] = uid
			fixedUids[uid] = true
		end
	end

	local currentIndex: { [string]: number } = {}
	for index, uid in displays do
		currentIndex[uid] = index
	end
	local candidates = {}
	for _, item in inventory do
		if not fixedUids[item.Uid] then
			table.insert(candidates, item)
		end
	end
	table.sort(candidates, function(a, b)
		return better(a, b, currentIndex)
	end)

	local wanted: { [number]: string } = {}
	local next = 1
	for index = 1, PlotLayout.PEDESTAL_COUNT do
		if fixed[index] then
			wanted[index] = fixed[index]
		elseif index <= count and candidates[next] then
			wanted[index] = candidates[next].Uid
			next += 1
		end
	end

	local changed: { number } = {}
	for index = 1, PlotLayout.PEDESTAL_COUNT do
		if displays[index] ~= wanted[index] then
			table.insert(changed, index)
		end
	end
	local wasShown: { [string]: boolean } = {}
	for _, uid in displays do
		wasShown[uid] = true
	end
	local inUseChanged = false
	for _, item in inventory do
		local shown = false
		for _, uid in wanted do
			if uid == item.Uid then
				shown = true
				break
			end
		end
		if (item.InUse == true) ~= shown then
			PlayerDataService.SetItemInUse(player, item.Uid, shown)
			inUseChanged = true
		end
	end
	if #changed == 0 and not inUseChanged then
		return
	end
	for _, index in changed do
		PlayerDataService.SetPedestalDisplay(player, index, wanted[index])
	end

	local plot = TycoonService.GetPlotForPlayer(player)
	if plot then
		for _, index in changed do
			local pedestal = getPedestalPart(plot, index)
			local uid = wanted[index]
			local item = uid and PlayerDataService.GetItemByUid(player, uid)
			if pedestal then
				if item then
					PedestalVisuals.Apply(pedestal, item.Tier, item.Mutation)
				else
					PedestalVisuals.Clear(pedestal)
				end
			end
		end
		TycoonService.RefreshPedestalLabels(player)
	end
	-- The ITEMS view's ON DISPLAY tags live in the inventory, not the
	-- tycoon snapshot.
	if inUseChanged then
		RemoteEvents.SyncInventory:FireClient(player, inventory)
	end

	local anyShown = false
	for _, uid in wanted do
		anyShown = true
		if not wasShown[uid] then
			local item = PlayerDataService.GetItemByUid(player, uid)
			if item then
				announceDisplay(player, item)
			end
		end
	end
	if anyShown then
		AnalyticsKit.Funnel(player, "FirstDisplay")
	end
end

-- /selftest: rebuilds every displayed orb of `player` from scratch (new
-- instances, new hover stamps), so the client can re-check that hovering
-- things stay on their plot after a rebuild.
function ItemService.RebuildDisplayVisuals(player: Player)
	local plot = TycoonService.GetPlotForPlayer(player)
	if not plot or not PlayerDataService.IsDataLoaded(player) then
		return
	end
	for index, uid in PlayerDataService.GetPedestalDisplays(player) do
		local pedestal = getPedestalPart(plot, index)
		local item = PlayerDataService.GetItemByUid(player, uid)
		-- A carried item's pedestal is HeistService's until the heist ends.
		if pedestal and item and not PlayerDataService.IsItemCarried(player, uid) then
			PedestalVisuals.Apply(pedestal, item.Tier, item.Mutation)
		end
	end
end

function ItemService:Init()
	-- Nothing to connect: the pedestals arrange themselves in every sync.
end

function ItemService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)
	-- Runs at the start of every SyncTycoon, before the snapshot is built,
	-- so the arrangement ships in the same sync as whatever changed.
	PlayerDataService.OnSync(ItemService.Arrange)
end

return ItemService
