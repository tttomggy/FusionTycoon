--!nonstrict
--[[
	ItemService
	-----------
	Server-authoritative pedestal placement/removal: validates that the
	requesting player owns the item and owns the pedestal, then mutates
	PedestalDisplays and applies the tier visuals.

	Follows the ServiceTemplate contract:
	  :Init()   connects its own remote handlers and nothing else.
	  :Start()  resolves PlayerDataService and TycoonService.

	The TycoonService reference in particular is why this pattern exists: it
	used to be a module-scope require, which runs at load time. TycoonService
	does not currently require ItemService back, but nothing structurally
	prevented it, and the day someone added that line the two would have
	deadlocked on require. Resolving in :Start() makes that impossible.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local ItemConfig = require(Config.ItemConfig)
local RarityVisuals = require(Config.RarityVisuals)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)
local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))

type State = {
	connections: { RBXScriptConnection },
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	connections = {},
}

-- Resolved in :Start(), not at module scope. Identifier names unchanged, so
-- every call site below reads exactly as before.
local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule

local ItemService = {}

ItemService.Name = "ItemService"

-- Every result carries the PedestalIndex the request named (when it had a
-- valid one), so the client can clear that pedestal's pending flag even on
-- a rejection - without it one rejection locked the pedestal for the session.
-- Rejections that mean the client's inventory is stale (it offered an item
-- that's displayed or gone): re-send it so the next try picks a free copy.
local STALE_INVENTORY_REASONS = { ItemInUse = true, ItemNotOwned = true }

local function reject(player: Player, reason: string, pedestalIndex: number?, isSuspicious: boolean?)
	if isSuspicious then
		warn(("ItemService: rejected place-item request from %s (%s)"):format(player.Name, reason))
	end
	if STALE_INVENTORY_REASONS[reason] and PlayerDataService.IsDataLoaded(player) then
		RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	end
	RemoteEvents.PlaceItemResult:FireClient(player, { Success = false, Reason = reason, PedestalIndex = pedestalIndex })
end

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

-- Place and remove flip item.InUse, which lives in the inventory, not the
-- tycoon snapshot: both go out, or the client keeps offering the displayed
-- copy of a stack and every later place is rejected as ItemInUse.
local function syncAll(player: Player)
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	PlayerDataService.SyncTycoon(player)
end

-- Place / remove share one spam guard (each accepted call syncs).
local ITEM_OPS_PER_SECOND = 6
local ITEM_OPS_BURST = 8
local MAX_UID_LENGTH = 64

local function onRequestPlaceItem(player: Player, rawUid: unknown, rawPedestalIndex: unknown)
	local pedestalIndex = RemoteGuard.Int(rawPedestalIndex, 1, PlotLayout.PEDESTAL_COUNT)
	if typeof(rawUid) ~= "string" or #(rawUid :: string) > MAX_UID_LENGTH or not pedestalIndex then
		reject(player, "InvalidArguments", nil, true)
		return
	end
	local uid = rawUid :: string
	if not RemoteGuard.Allow(player, "ItemOps", ITEM_OPS_PER_SECOND, ITEM_OPS_BURST) then
		reject(player, "TooFast", pedestalIndex)
		return
	end

	if not PlayerDataService.IsDataLoaded(player) then
		reject(player, "DataNotLoaded", pedestalIndex)
		return
	end

	-- Never trust client-supplied ownership: the pedestal is only ever
	-- resolved from the requesting player's own server-tracked plot, so a
	-- player can never target another player's pedestal.
	local plot = TycoonService.GetPlotForPlayer(player)
	if not plot then
		reject(player, "NoPlot", pedestalIndex)
		return
	end

	local pedestal = getPedestalPart(plot, pedestalIndex)
	if not pedestal then
		reject(player, "InvalidPedestal", pedestalIndex, true)
		return
	end
	-- Spots 5-6 need the +2 Pedestals pass.
	if pedestalIndex > PlayerDataService.GetPedestalCount(player) then
		reject(player, "PedestalLocked", pedestalIndex)
		return
	end

	local item = PlayerDataService.GetItemByUid(player, uid)
	if not item then
		reject(player, "ItemNotOwned", pedestalIndex, true)
		return
	end

	if item.InUse then
		reject(player, "ItemInUse", pedestalIndex, true)
		return
	end

	local pedestalDisplays = PlayerDataService.GetPedestalDisplays(player)
	if pedestalDisplays[pedestalIndex] then
		reject(player, "PedestalOccupied", pedestalIndex)
		return
	end

	PlayerDataService.SetItemInUse(player, uid, true)
	PlayerDataService.SetPedestalDisplay(player, pedestalIndex, uid)
	syncAll(player)

	PedestalVisuals.Apply(pedestal, item.Tier, item.Mutation)
	TycoonService.RefreshPedestalLabels(player)

	local itemConfigEntry = ItemConfig.GetItemById(item.ItemId)
	local itemName = itemConfigEntry and itemConfigEntry.Name or item.ItemId

	RemoteEvents.PlaceItemResult:FireClient(player, {
		Success = true,
		PedestalIndex = pedestalIndex,
		Item = item,
	})
	AnalyticsKit.Funnel(player, "FirstDisplay")

	local visualConfig = RarityVisuals.Tiers[item.Tier]
	if visualConfig and visualConfig.AnnounceServerWide then
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
end

local function onRequestRemoveItem(player: Player, rawPedestalIndex: unknown)
	local pedestalIndex = RemoteGuard.Int(rawPedestalIndex, 1, PlotLayout.PEDESTAL_COUNT)
	if not pedestalIndex then
		reject(player, "InvalidArguments", nil, true)
		return
	end
	if not RemoteGuard.Allow(player, "ItemOps", ITEM_OPS_PER_SECOND, ITEM_OPS_BURST) then
		reject(player, "TooFast", pedestalIndex)
		return
	end

	if not PlayerDataService.IsDataLoaded(player) then
		reject(player, "DataNotLoaded", pedestalIndex)
		return
	end

	-- Same non-negotiable rule as placement: the pedestal is only ever
	-- resolved from the requesting player's own server-tracked plot.
	local plot = TycoonService.GetPlotForPlayer(player)
	if not plot then
		reject(player, "NoPlot", pedestalIndex)
		return
	end

	local pedestal = getPedestalPart(plot, pedestalIndex)
	if not pedestal then
		reject(player, "InvalidPedestal", pedestalIndex, true)
		return
	end

	local pedestalDisplays = PlayerDataService.GetPedestalDisplays(player)
	local uid = pedestalDisplays[pedestalIndex]
	if not uid then
		reject(player, "PedestalEmpty", pedestalIndex)
		return
	end
	-- A thief is carrying it: it stays put until the heist ends (HeistService).
	if PlayerDataService.IsItemCarried(player, uid) then
		reject(player, "BeingStolen", pedestalIndex)
		return
	end

	PlayerDataService.SetItemInUse(player, uid, false)
	PlayerDataService.SetPedestalDisplay(player, pedestalIndex, nil)
	syncAll(player)

	PedestalVisuals.Clear(pedestal)
	TycoonService.RefreshPedestalLabels(player)

	RemoteEvents.PlaceItemResult:FireClient(player, {
		Success = true,
		PedestalIndex = pedestalIndex,
		Removed = true,
	})
end

function ItemService:Init()
	table.insert(state.connections, RemoteEvents.RequestPlaceItem.OnServerEvent:Connect(onRequestPlaceItem))
	table.insert(state.connections, RemoteEvents.RequestRemoveItem.OnServerEvent:Connect(onRequestRemoveItem))
end

function ItemService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)
end

return ItemService
