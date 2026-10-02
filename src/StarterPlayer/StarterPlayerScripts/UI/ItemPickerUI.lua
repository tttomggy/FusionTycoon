-- Generic modal list-picker: a dimmed backdrop + centered panel showing a
-- scrollable list of tier-colored rows. Used both for pedestal item selection
-- (an onSelect callback + "Select an Item" title) and for the persistent
-- Inventory button's read-only browse view (no onSelect, "Your Items" title -
-- rows are inert, only the X/backdrop closes it). Deliberately decoupled from
-- pedestals/items specifically - it only knows about {Uid, Name, Tier}
-- entries and an optional selection callback, so any future picker/browser
-- can reuse the same list rendering instead of rebuilding it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RarityVisuals = require(ReplicatedStorage.Shared.Config.RarityVisuals)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)

local ItemPickerUI = {}

export type PickerEntry = {
	Uid: string,
	Name: string,
	Tier: string,
}

local PANEL_SIZE = UDim2.fromOffset(420, 460)
local ROW_HEIGHT = 44
local ROW_SPACING = 6
local EMPTY_STATE_TEXT = "No items to display - pull from the Gacha Pad or fuse something first."
local DEFAULT_TITLE = "Select an Item"

local screenGui: ScreenGui? = nil
local titleLabel: TextLabel? = nil
local listFrame: ScrollingFrame? = nil
local emptyLabel: TextLabel? = nil

local function buildUI()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "ItemPickerUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 150
	gui.Enabled = false

	local backdropButton = Instance.new("TextButton")
	backdropButton.Name = "Backdrop"
	backdropButton.Size = UDim2.fromScale(1, 1)
	backdropButton.BackgroundColor3 = Color3.new(0, 0, 0)
	backdropButton.BackgroundTransparency = 0.45
	backdropButton.AutoButtonColor = false
	backdropButton.Text = ""
	backdropButton.Parent = gui

	local panelFrame = Instance.new("Frame")
	panelFrame.Name = "Panel"
	panelFrame.Size = PANEL_SIZE
	panelFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	panelFrame.Position = UDim2.fromScale(0.5, 0.5)
	panelFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
	panelFrame.BorderSizePixel = 0
	panelFrame.Parent = gui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panelFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -50, 0, 44)
	title.Position = UDim2.new(0, 16, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = DEFAULT_TITLE
	title.Parent = panelFrame

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.fromOffset(32, 32)
	closeButton.Position = UDim2.new(1, -40, 0, 8)
	closeButton.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.TextScaled = true
	closeButton.Text = "X"
	closeButton.Parent = panelFrame

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeButton

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, -32, 0, 1)
	divider.Position = UDim2.new(0, 16, 0, 46)
	divider.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
	divider.BorderSizePixel = 0
	divider.Parent = panelFrame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Size = UDim2.new(1, -32, 1, -62)
	scroll.Position = UDim2.new(0, 16, 0, 54)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panelFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, ROW_SPACING)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll

	local empty = Instance.new("TextLabel")
	empty.Name = "EmptyState"
	empty.Size = UDim2.new(1, -32, 1, -62)
	empty.Position = UDim2.new(0, 16, 0, 54)
	empty.BackgroundTransparency = 1
	empty.Font = Enum.Font.Gotham
	empty.TextColor3 = Color3.fromRGB(200, 200, 200)
	empty.TextWrapped = true
	empty.TextScaled = true
	empty.Text = EMPTY_STATE_TEXT
	empty.Visible = false
	empty.Parent = panelFrame

	gui.Parent = playerGui

	screenGui = gui
	titleLabel = title
	listFrame = scroll
	emptyLabel = empty

	backdropButton.MouseButton1Click:Connect(function()
		ItemPickerUI.Close()
	end)
	closeButton.MouseButton1Click:Connect(function()
		ItemPickerUI.Close()
	end)
end

local function clearRows()
	local scroll = listFrame :: ScrollingFrame
	for _, child in scroll:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

function ItemPickerUI.Close()
	if screenGui then
		local gui = screenGui :: ScreenGui
		gui.Enabled = false
	end
end

-- onSelect is optional: pass nil for a read-only browse view (e.g. the
-- persistent Inventory button) where rows are inert and only the X/backdrop
-- closes the panel. title defaults to "Select an Item".
function ItemPickerUI.Open(items: { PickerEntry }, onSelect: ((PickerEntry) -> ())?, title: string?)
	if not screenGui then
		buildUI()
	end

	clearRows()

	local currentTitle = titleLabel :: TextLabel
	currentTitle.Text = title or DEFAULT_TITLE

	local scroll = listFrame :: ScrollingFrame
	local empty = emptyLabel :: TextLabel

	if #items == 0 then
		empty.Visible = true
		scroll.Visible = false
	else
		empty.Visible = false
		scroll.Visible = true

		-- Best items first, so the one you want on a pedestal is at the top.
		local sorted = table.clone(items)
		table.sort(sorted, function(a, b)
			local rankA = ItemConfig.Tiers[a.Tier] or 0
			local rankB = ItemConfig.Tiers[b.Tier] or 0
			if rankA ~= rankB then
				return rankA > rankB
			end
			return a.Name < b.Name
		end)

		for index, entry in sorted do
			local tierVisual = RarityVisuals.Tiers[entry.Tier]
			local tierColor = (tierVisual and tierVisual.GlowColor) or Color3.new(1, 1, 1)

			local row = Instance.new("TextButton")
			row.Name = "Row"
			row.LayoutOrder = index
			row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
			row.BackgroundColor3 = Color3.fromRGB(36, 36, 44)
			row.AutoButtonColor = true
			row.Text = ""
			row.Parent = scroll

			local rowCorner = Instance.new("UICorner")
			rowCorner.CornerRadius = UDim.new(0, 8)
			rowCorner.Parent = row

			local accentBar = Instance.new("Frame")
			accentBar.Name = "AccentBar"
			accentBar.Size = UDim2.new(0, 6, 1, -12)
			accentBar.Position = UDim2.new(0, 6, 0, 6)
			accentBar.BackgroundColor3 = tierColor
			accentBar.BorderSizePixel = 0
			accentBar.Parent = row

			local accentCorner = Instance.new("UICorner")
			accentCorner.CornerRadius = UDim.new(0, 3)
			accentCorner.Parent = accentBar

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "NameLabel"
			nameLabel.Size = UDim2.new(0.6, -24, 1, 0)
			nameLabel.Position = UDim2.new(0, 24, 0, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
			nameLabel.TextScaled = true
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Text = entry.Name
			nameLabel.Parent = row

			local tierLabel = Instance.new("TextLabel")
			tierLabel.Name = "TierLabel"
			tierLabel.Size = UDim2.new(0.4, -16, 1, 0)
			tierLabel.Position = UDim2.new(0.6, 0, 0, 0)
			tierLabel.BackgroundTransparency = 1
			tierLabel.Font = Enum.Font.GothamBold
			tierLabel.TextColor3 = tierColor
			tierLabel.TextScaled = true
			tierLabel.TextXAlignment = Enum.TextXAlignment.Right
			-- What it earns on a pedestal (before the multiplier).
			tierLabel.Text = ("%s · %s/s"):format(
				entry.Tier:upper(),
				NumberFormat.Money(TycoonConfig.GetPedestalCashPerSecond(entry.Tier))
			)
			tierLabel.Parent = row

			if onSelect then
				row.MouseButton1Click:Connect(function()
					ItemPickerUI.Close()
					onSelect(entry)
				end)
			end
		end
	end

	local gui = screenGui :: ScreenGui
	gui.Enabled = true
end

return ItemPickerUI
