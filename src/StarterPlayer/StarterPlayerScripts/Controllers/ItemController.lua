local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local InventoryController = require(script.Parent.InventoryController)
local TycoonController = require(script.Parent.TycoonController)
local ItemPickerUI = require(script.Parent.Parent.UI.ItemPickerUI)

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
-- True once this player's Pedestals folder exists (their plot is claimed).
local pedestalsReady = false

local placementResolved = Instance.new("BindableEvent")
-- Fires once the server has validated a place-item attempt.
ItemController.PlacementResolved = placementResolved.Event

local function hasDisplayableItem(): boolean
	return #InventoryController.GetDisplayableItems() > 0
end

-- An occupied pedestal always belongs to the local player (pedestals are
-- per-plot/per-owner), so the same prompt just switches to a pickup action
-- instead of being disabled once something's displayed.
local function updatePromptState(pedestal: BasePart, pedestalIndex: number)
	local prompt = pedestal:FindFirstChild("DisplayPrompt") :: ProximityPrompt?
	if not prompt then
		return
	end

	if TycoonController.GetPedestalDisplay(pedestalIndex) then
		prompt.Enabled = true
		prompt.ActionText = "Remove"
		prompt.ObjectText = ("Pedestal %d"):format(pedestalIndex)
		return
	end

	prompt.Enabled = hasDisplayableItem()
	prompt.ActionText = "Display"
	prompt.ObjectText = ("Pedestal %d"):format(pedestalIndex)
end

local function requestPlaceItem(pedestalIndex: number, uid: string)
	if pendingPedestals[pedestalIndex] then
		return
	end
	if TycoonController.GetPedestalDisplay(pedestalIndex) then
		return
	end

	pendingPedestals[pedestalIndex] = true
	RemoteEvents.RequestPlaceItem:FireServer(uid, pedestalIndex)
end

-- Opens the shared ItemPickerUI over the player's current undisplayed items,
-- so they choose which one lands on this specific pedestal instead of the
-- game auto-selecting for them. Server-side validation in ItemService is
-- unchanged - it already checks ownership/InUse/pedestal-empty for whichever
-- Uid the client sends, so this only changes which Uid gets picked, not the
-- trust boundary.
local function openItemPicker(pedestalIndex: number)
	if pendingPedestals[pedestalIndex] then
		return
	end
	if TycoonController.GetPedestalDisplay(pedestalIndex) then
		return
	end

	-- Every owned item, including ones already on pedestals: the grid groups
	-- copies, tags displayed ones, and DISPLAY only ever sends a free copy.
	local entries = {}
	for _, item in InventoryController.GetInventory() do
		local itemConfigEntry = ItemConfig.GetItemById(item.ItemId)
		table.insert(entries, {
			Uid = item.Uid,
			ItemId = item.ItemId,
			Name = itemConfigEntry and itemConfigEntry.Name or item.ItemId,
			Tier = item.Tier,
			InUse = item.InUse == true,
		})
	end

	ItemPickerUI.Open(entries, function(entry)
		requestPlaceItem(pedestalIndex, entry.Uid)
	end, nil, { Subtitle = ("For Pedestal %d · best items first"):format(pedestalIndex) })
end

-- Places `uid` on the lowest-numbered empty pedestal (the result card's
-- DISPLAY IT). Returns false if the plot isn't claimed yet or every pedestal
-- is full, so the caller can fall back to the inventory picker.
function ItemController.PlaceOnFirstEmpty(uid: string): boolean
	if not pedestalsReady then
		return false
	end
	for index = 1, PlotLayout.PEDESTAL_COUNT do
		if not TycoonController.GetPedestalDisplay(index) and not pendingPedestals[index] then
			requestPlaceItem(index, uid)
			return true
		end
	end
	return false
end

local function requestRemoveItem(pedestalIndex: number)
	if pendingPedestals[pedestalIndex] then
		return
	end
	if not TycoonController.GetPedestalDisplay(pedestalIndex) then
		return
	end

	pendingPedestals[pedestalIndex] = true
	RemoteEvents.RequestRemoveItem:FireServer(pedestalIndex)
end

-- Routes to whichever action the pedestal's current state calls for, so
-- pressing the same prompt either opens the item picker or picks up
-- whatever's already there.
local function onPedestalTriggered(pedestalIndex: number)
	if TycoonController.GetPedestalDisplay(pedestalIndex) then
		requestRemoveItem(pedestalIndex)
	else
		openItemPicker(pedestalIndex)
	end
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
	pedestalsReady = true

	for _, pedestal in pedestalsFolder:GetChildren() do
		if pedestal:IsA("BasePart") then
			local pedestalIndex = pedestal:GetAttribute("PedestalIndex")
			if typeof(pedestalIndex) == "number" then
				local prompt = pedestal:WaitForChild("DisplayPrompt") :: ProximityPrompt
				prompt.Triggered:Connect(function(triggeringPlayer: Player)
					if triggeringPlayer == localPlayer then
						onPedestalTriggered(pedestalIndex)
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
