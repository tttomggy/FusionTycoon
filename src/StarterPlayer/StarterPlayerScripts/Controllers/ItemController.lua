local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local InventoryController = require(script.Parent.InventoryController)
local TycoonController = require(script.Parent.TycoonController)
local ItemPickerUI = require(script.Parent.Parent.UI.ItemPickerUI)
local ToastController = require(script.Parent.ToastController)
local ShopController = require(script.Parent.ShopController)

local ItemController = {}

-- Guards per-pedestal so a pending placement on one doesn't block another.
-- Value = the os.clock() it was set; a flag older than PENDING_TIMEOUT is
-- treated as cleared, so a lost reply can never lock a pedestal for good.
local pendingPedestals: { [number]: number } = {}
local PENDING_TIMEOUT_SECONDS = 5

local function isPending(pedestalIndex: number): boolean
	local since = pendingPedestals[pedestalIndex]
	if since and os.clock() - since < PENDING_TIMEOUT_SECONDS then
		return true
	end
	pendingPedestals[pedestalIndex] = nil
	return false
end

local function setPending(pedestalIndex: number)
	pendingPedestals[pedestalIndex] = os.clock()
end

-- Short, never-blank toast text for every rejection reason.
local REJECTION_TOASTS: { [string]: string } = {
	PedestalOccupied = "That pedestal is already in use",
	PedestalEmpty = "Nothing on that pedestal",
	ItemInUse = "That item is already on display",
	ItemNotOwned = "You don't have that item anymore",
	BeingStolen = "A thief has it! Tag them to get it back",
	NoPlot = "Your lab isn't ready yet, try again",
	DataNotLoaded = "Your lab isn't ready yet, try again",
	PedestalLocked = "That spot needs the +2 Pedestals pass",
	TooFast = "Slow down a little",
}
local FALLBACK_REJECTION_TOAST = "Couldn't do that, try again"
-- True once this player's plot is claimed (its pedestals then exist).
local pedestalsReady = false

local placementResolved = Instance.new("BindableEvent")
-- Fires once the server has validated a place-item attempt.
ItemController.PlacementResolved = placementResolved.Event

local function requestPlaceItem(pedestalIndex: number, uid: string)
	if isPending(pedestalIndex) then
		return
	end
	if TycoonController.GetPedestalDisplay(pedestalIndex) then
		return
	end

	setPending(pedestalIndex)
	RemoteEvents.RequestPlaceItem:FireServer(uid, pedestalIndex)
end

-- Opens the shared ItemPickerUI over the player's items (with none, it shows
-- its "Pull at the Gacha Pad" empty state - a prompt never does nothing),
-- so they choose which one lands on this specific pedestal instead of the
-- game auto-selecting for them. Server-side validation in ItemService is
-- unchanged - it already checks ownership/InUse/pedestal-empty for whichever
-- Uid the client sends, so this only changes which Uid gets picked, not the
-- trust boundary.
local function openItemPicker(pedestalIndex: number)
	if isPending(pedestalIndex) then
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
			Mutation = item.Mutation,
			InUse = InventoryController.IsInUse(item),
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
	for index = 1, TycoonController.GetPedestalCount() do
		if not TycoonController.GetPedestalDisplay(index) and not isPending(index) then
			requestPlaceItem(index, uid)
			return true
		end
	end
	return false
end

local function requestRemoveItem(pedestalIndex: number)
	if isPending(pedestalIndex) then
		return
	end
	if not TycoonController.GetPedestalDisplay(pedestalIndex) then
		return
	end

	setPending(pedestalIndex)
	RemoteEvents.RequestRemoveItem:FireServer(pedestalIndex)
end

-- Routes to whichever action the pedestal's current state calls for, so
-- pressing the same prompt either opens the item picker or picks up
-- whatever's already there.
local function onPedestalTriggered(pedestalIndex: number)
	if pedestalIndex > TycoonController.GetPedestalCount() then
		-- A locked spot: the one in-world sell, only on the owner's own tap,
		-- and only once the pass is really for sale (no id yet: no prompt).
		if ShopController.IsAvailable("ExtraPedestals") then
			ShopController.Buy("ExtraPedestals")
		else
			ToastController.Show("Coming soon!", "Neutral")
		end
		return
	end
	if TycoonController.GetPedestalDisplay(pedestalIndex) then
		requestRemoveItem(pedestalIndex)
	else
		openItemPicker(pedestalIndex)
	end
end

local function onPlaceItemResult(result: any)
	if typeof(result) ~= "table" then
		return
	end
	if typeof(result.PedestalIndex) == "number" then
		pendingPedestals[result.PedestalIndex] = nil
	end
	if not result.Success then
		local reason = if typeof(result.Reason) == "string" then result.Reason else ""
		ToastController.Show(REJECTION_TOASTS[reason] or FALLBACK_REJECTION_TOAST, "Error")
		-- Our view of the pedestals may be stale; ask for a fresh snapshot.
		RemoteEvents.RequestSync:FireServer()
	end
	placementResolved:Fire(result)
end

local DISPLAY_PROMPT_NAME = "DisplayPrompt"

-- The pedestal index for a DisplayPrompt inside the local player's own plot,
-- or nil for any other prompt.
local function getOwnPedestalIndex(prompt: ProximityPrompt, plot: Instance): number?
	if prompt.Name ~= DISPLAY_PROMPT_NAME or not prompt:IsDescendantOf(plot) then
		return nil
	end
	local pedestal = prompt.Parent
	local index = pedestal and pedestal:GetAttribute("PedestalIndex")
	return if typeof(index) == "number" then index else nil
end

function ItemController.Init()
	RemoteEvents.PlaceItemResult.OnClientEvent:Connect(onPlaceItemResult)

	local localPlayer = Players.LocalPlayer
	local plotsFolder = Workspace:WaitForChild(PlotNaming.PlotsFolderName)
	local plot = plotsFolder:WaitForChild(PlotNaming.GetPlotName(localPlayer.UserId))

	-- Pedestals exist once the plot is claimed.
	local function refreshReady()
		pedestalsReady = plot:GetAttribute("Claimed") == true
	end
	plot:GetAttributeChangedSignal("Claimed"):Connect(refreshReady)
	refreshReady()

	-- One service-wide handler instead of wiring each prompt as it's found:
	-- nothing can be missed however the pedestals replicate.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, triggeringPlayer: Player)
		if triggeringPlayer ~= localPlayer then
			return
		end
		local index = getOwnPedestalIndex(prompt, plot)
		if index then
			onPedestalTriggered(index)
		end
	end)

	-- Label the prompt for what pressing it will do, as it appears.
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		local index = getOwnPedestalIndex(prompt, plot)
		if index and index > TycoonController.GetPedestalCount() then
			local forSale = ShopController.IsAvailable("ExtraPedestals")
			prompt.ActionText = if forSale then "Unlock" else "Locked"
			prompt.ObjectText = if forSale then "+2 Pedestals" else "+2 Pedestals · coming soon"
		elseif index then
			prompt.ActionText = if TycoonController.GetPedestalDisplay(index) then "Remove" else "Display"
			prompt.ObjectText = ("Pedestal %d"):format(index)
		end
	end)
end

return ItemController
