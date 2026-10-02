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

local function reject(player: Player, reason: string, isSuspicious: boolean?)
	if isSuspicious then
		warn(("ItemService: rejected place-item request from %s (%s)"):format(player.Name, reason))
	end
	RemoteEvents.PlaceItemResult:FireClient(player, { Success = false, Reason = reason })
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

local function syncTycoon(player: Player)
	PlayerDataService.SyncTycoon(player)
end

local function onRequestPlaceItem(player: Player, rawUid: unknown, rawPedestalIndex: unknown)
	if typeof(rawUid) ~= "string" or typeof(rawPedestalIndex) ~= "number" then
		reject(player, "InvalidArguments", true)
		return
	end
	local uid = rawUid :: string
	local pedestalIndex = math.floor(rawPedestalIndex :: number)

	if not PlayerDataService.IsDataLoaded(player) then
		reject(player, "DataNotLoaded")
		return
	end

	-- Never trust client-supplied ownership: the pedestal is only ever
	-- resolved from the requesting player's own server-tracked plot, so a
	-- player can never target another player's pedestal.
	local plot = TycoonService.GetPlotForPlayer(player)
	if not plot then
		reject(player, "NoPlot")
		return
	end

	local pedestal = getPedestalPart(plot, pedestalIndex)
	if not pedestal then
		reject(player, "InvalidPedestal", true)
		return
	end

	local item = PlayerDataService.GetItemByUid(player, uid)
	if not item then
		reject(player, "ItemNotOwned", true)
		return
	end

	if item.InUse then
		reject(player, "ItemInUse", true)
		return
	end

	local pedestalDisplays = PlayerDataService.GetPedestalDisplays(player)
	if pedestalDisplays[pedestalIndex] then
		reject(player, "PedestalOccupied")
		return
	end

	PlayerDataService.SetItemInUse(player, uid, true)
	PlayerDataService.SetPedestalDisplay(player, pedestalIndex, uid)
	syncTycoon(player)

	PedestalVisuals.Apply(pedestal, item.Tier)

	local itemConfigEntry = ItemConfig.GetItemById(item.ItemId)
	local itemName = itemConfigEntry and itemConfigEntry.Name or item.ItemId

	RemoteEvents.PlaceItemResult:FireClient(player, {
		Success = true,
		PedestalIndex = pedestalIndex,
		Item = item,
	})

	local visualConfig = RarityVisuals.Tiers[item.Tier]
	if visualConfig and visualConfig.AnnounceServerWide then
		RemoteEvents.RareFusionAnnouncement:FireAllClients({
			Message = ("%s just displayed a %s %s!"):format(player.DisplayName, item.Tier:upper(), itemName),
			Tier = item.Tier,
		})
	end
end

local function onRequestRemoveItem(player: Player, rawPedestalIndex: unknown)
	if typeof(rawPedestalIndex) ~= "number" then
		reject(player, "InvalidArguments", true)
		return
	end
	local pedestalIndex = math.floor(rawPedestalIndex :: number)

	if not PlayerDataService.IsDataLoaded(player) then
		reject(player, "DataNotLoaded")
		return
	end

	-- Same non-negotiable rule as placement: the pedestal is only ever
	-- resolved from the requesting player's own server-tracked plot.
	local plot = TycoonService.GetPlotForPlayer(player)
	if not plot then
		reject(player, "NoPlot")
		return
	end

	local pedestal = getPedestalPart(plot, pedestalIndex)
	if not pedestal then
		reject(player, "InvalidPedestal", true)
		return
	end

	local pedestalDisplays = PlayerDataService.GetPedestalDisplays(player)
	local uid = pedestalDisplays[pedestalIndex]
	if not uid then
		reject(player, "PedestalEmpty")
		return
	end

	PlayerDataService.SetItemInUse(player, uid, false)
	PlayerDataService.SetPedestalDisplay(player, pedestalIndex, nil)
	syncTycoon(player)

	PedestalVisuals.Clear(pedestal)

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
