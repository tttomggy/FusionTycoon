-- A persistent, always-visible button (bottom-center of the screen, not tied
-- to being near a pedestal) that opens the shared ItemPickerUI in read-only
-- browse mode over everything the player currently owns and isn't displaying
-- anywhere. Reuses ItemPickerUI rather than building a separate inventory
-- screen, per the same reasoning that made ItemPickerUI a standalone
-- component in the first place.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local InventoryController = require(script.Parent.InventoryController)
local ItemPickerUI = require(script.Parent.Parent.UI.ItemPickerUI)

local InventoryButtonController = {}

-- Square icon button instead of the old wide text button - same bottom-center
-- anchor/margin, just resized to suit a single glyph instead of a text label.
local BUTTON_SIZE = UDim2.fromOffset(56, 56)
local BUTTON_BOTTOM_MARGIN = 24
local BROWSE_TITLE = "Your Items"
local BUTTON_COLOR = Color3.fromRGB(36, 36, 44)
-- User-supplied, uploaded asset (not a built-in rbxasset:// engine file like
-- the bell.wav sound that silently failed to load) - a real Roblox CDN asset
-- ID, so it doesn't carry the same load-failure risk.
local ICON_IMAGE_ID = "rbxassetid://18469524765"
local ICON_PADDING_SCALE = 0.68

local function buildEntries(): { any }
	local entries = {}
	for _, item in InventoryController.GetDisplayableItems() do
		local itemConfigEntry = ItemConfig.GetItemById(item.ItemId)
		table.insert(entries, {
			Uid = item.Uid,
			Name = itemConfigEntry and itemConfigEntry.Name or item.ItemId,
			Tier = item.Tier,
		})
	end
	return entries
end

local function onButtonClicked()
	-- No onSelect: browsing your own inventory doesn't place/consume
	-- anything, so rows are inert - only the X/backdrop closes the panel.
	ItemPickerUI.Open(buildEntries(), nil, BROWSE_TITLE)
end

function InventoryButtonController.Init()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryButton"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = playerGui

	local button = Instance.new("TextButton")
	button.Name = "InventoryButton"
	button.Size = BUTTON_SIZE
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -BUTTON_BOTTOM_MARGIN)
	button.BackgroundColor3 = BUTTON_COLOR
	button.Text = ""
	button.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = button

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(ICON_PADDING_SCALE, ICON_PADDING_SCALE)
	icon.BackgroundTransparency = 1
	icon.Image = ICON_IMAGE_ID
	icon.Parent = button

	button.MouseButton1Click:Connect(onButtonClicked)
end

return InventoryButtonController
