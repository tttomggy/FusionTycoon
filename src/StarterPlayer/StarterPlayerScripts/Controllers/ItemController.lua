local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local InventoryController = require(script.Parent.InventoryController)
local TycoonController = require(script.Parent.TycoonController)

local ItemController = {}

-- Pedestals aren't built until the plot owner claims their plot (see
-- TycoonService.createPedestals, called from the ClaimButton handler), which
-- can easily take longer than 5 seconds after spawning - a plain
-- `parent:WaitForChild(name)` would print Roblox's "Infinite yield possible"
-- warning the moment that threshold passes, even though nothing is actually
-- wrong. Waiting on ChildAdded in a loop blocks for the same reason but
-- without that warning, since only WaitForChild carries the 5-second heuristic.
local function waitForNamedChild(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	while true do
		local child = parent.ChildAdded:Wait()
		if child.Name == name then
			return child
		end
	end
end

-- Guards per-pedestal so a pending placement on one doesn't block another.
local pendingPedestals: { [number]: boolean } = {}

local placementResolved = Instance.new("BindableEvent")
-- Fires once the server has validated a place-item attempt.
ItemController.PlacementResolved = placementResolved.Event

-- Picks the highest-tier item the player owns that isn't already displayed
-- (or otherwise in use) elsewhere, so there's no separate item-picker UI to
-- build: pressing Display on a pedestal always offers your best available
-- piece.
local function getBestDisplayableItem(): any
	local inventory = InventoryController.GetInventory()
	local best = nil
	local bestTierIndex = 0
	for _, item in inventory do
		if not item.InUse then
			local tierIndex = table.find(FusionConfig.TierOrder, item.Tier) or 0
			if tierIndex > bestTierIndex then
				bestTierIndex = tierIndex
				best = item
			end
		end
	end
	return best
end

local function updatePromptState(pedestal: BasePart, pedestalIndex: number)
	local prompt = pedestal:FindFirstChild("DisplayPrompt") :: ProximityPrompt?
	if not prompt then
		return
	end

	if TycoonController.GetPedestalDisplay(pedestalIndex) then
		prompt.Enabled = false
		prompt.ObjectText = "Occupied"
		return
	end

	local item = getBestDisplayableItem()
	prompt.Enabled = item ~= nil
	prompt.ObjectText = ("Pedestal %d"):format(pedestalIndex)
end

local function requestPlaceItem(pedestalIndex: number)
	if pendingPedestals[pedestalIndex] then
		return
	end
	if TycoonController.GetPedestalDisplay(pedestalIndex) then
		return
	end

	local item = getBestDisplayableItem()
	if not item then
		return
	end

	pendingPedestals[pedestalIndex] = true
	RemoteEvents.RequestPlaceItem:FireServer(item.Uid, pedestalIndex)
end

local function onPlaceItemResult(result: any)
	if result.PedestalIndex then
		pendingPedestals[result.PedestalIndex] = nil
	end
	placementResolved:Fire(result)
end

function ItemController.Init()
	RemoteEvents.PlaceItemResult.OnClientEvent:Connect(onPlaceItemResult)

	local localPlayer = Players.LocalPlayer
	local plotsFolder = Workspace:WaitForChild(PlotNaming.PlotsFolderName)
	local plot = plotsFolder:WaitForChild(PlotNaming.GetPlotName(localPlayer.UserId))
	local pedestalsFolder = waitForNamedChild(plot, "Pedestals") :: Folder

	for _, pedestal in pedestalsFolder:GetChildren() do
		if pedestal:IsA("BasePart") then
			local pedestalIndex = pedestal:GetAttribute("PedestalIndex")
			if typeof(pedestalIndex) == "number" then
				local prompt = pedestal:WaitForChild("DisplayPrompt") :: ProximityPrompt
				prompt.Triggered:Connect(function(triggeringPlayer: Player)
					if triggeringPlayer == localPlayer then
						requestPlaceItem(pedestalIndex)
					end
				end)
				updatePromptState(pedestal, pedestalIndex)
			end
		end
	end

	local function updateAllPrompts()
		for _, pedestal in pedestalsFolder:GetChildren() do
			if pedestal:IsA("BasePart") then
				local pedestalIndex = pedestal:GetAttribute("PedestalIndex")
				if typeof(pedestalIndex) == "number" then
					updatePromptState(pedestal, pedestalIndex)
				end
			end
		end
	end

	InventoryController.InventoryChanged:Connect(updateAllPrompts)
	TycoonController.TycoonChanged:Connect(updateAllPrompts)
end

return ItemController
