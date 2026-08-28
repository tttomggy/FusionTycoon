local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local ItemConfig = require(Config.ItemConfig)
local RarityVisuals = require(Config.RarityVisuals)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)

local PlayerDataService = require(script.Parent.PlayerDataService)
local TycoonService = require(script.Parent.TycoonService)

local ItemService = {}

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

-- Pushes a fresh Cash/Generators/... snapshot after a placement changes
-- PedestalDisplays. Mirrors TycoonService's own syncTycoon payload shape;
-- duplicated rather than shared since TycoonService's version is a private
-- local function, and the two rarely change independently anyway.
local function syncTycoon(player: Player)
	RemoteEvents.SyncTycoon:FireClient(player, {
		Cash = PlayerDataService.GetCash(player),
		Generators = PlayerDataService.GetGenerators(player) or {},
		CashMultiplierLevel = PlayerDataService.GetCashMultiplierLevel(player),
		PedestalDisplays = PlayerDataService.GetPedestalDisplays(player),
	})
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

	print(("ItemService: %s displayed a %s %s on pedestal %d"):format(player.Name, item.Tier, itemName, pedestalIndex))

	RemoteEvents.PlaceItemResult:FireClient(player, {
		Success = true,
		PedestalIndex = pedestalIndex,
		Item = item,
	})

	local visualConfig = RarityVisuals.Tiers[item.Tier]
	if visualConfig and visualConfig.AnnounceServerWide then
		RemoteEvents.RareFusionAnnouncement:FireAllClients({
			Message = ("%s just displayed a %s %s!"):format(player.Name, item.Tier:upper(), itemName),
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

	print(("ItemService: %s picked an item back up from pedestal %d"):format(player.Name, pedestalIndex))

	RemoteEvents.PlaceItemResult:FireClient(player, {
		Success = true,
		PedestalIndex = pedestalIndex,
		Removed = true,
	})
end

function ItemService.Init()
	RemoteEvents.RequestPlaceItem.OnServerEvent:Connect(onRequestPlaceItem)
	RemoteEvents.RequestRemoveItem.OnServerEvent:Connect(onRequestRemoveItem)
end

return ItemService
