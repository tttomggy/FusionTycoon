--[[
	IndexPanel
	----------
	The INDEX modal (HUD button): every item x { Normal, Golden, Diamond,
	Rainbow }, and the income it pays for collecting them (IndexConfig).

	  * Header INDEX with a green "+42% income" pill
	  * "37 / 68 found · +1% each · +5% per full tier page"
	  * Tier tabs with counts ("Legendary 9/12")
	  * A page per tier: one row per item, a cell per variant. Found cells
	    are filled in the tier colour (Normal) or mutation colour (Rainbow
	    on its gradient); missing ones are a "?" well.

	Also toasts new entries from pulls and fusions (the server flags them):
	"NEW IN INDEX · Golden Star Core · +1%", or "+5% · Legendary page
	complete!" when that entry finished a page.

	Content scrolls, so it fits a phone; every tap target is >= 44 px.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local Controllers = script.Parent.Parent.Controllers
local TycoonController = require(Controllers.TycoonController)
local ToastController = require(Controllers.ToastController)
local FusionController = require(Controllers.FusionController)
local UIKit = require(script.Parent.UIKit)

local IndexPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(560, 560)
local TAB_SIZE = Vector2.new(132, UITheme.MinTapSize)
local ROW_HEIGHT = 52
local CELL_SIZE = UITheme.MinTapSize
local NAME_COLUMN = 0.36 -- of the page width

local modal: UIKit.Modal
local bonusPill: TextLabel
local countLabel: TextLabel
local tabsFrame: ScrollingFrame
local page: ScrollingFrame
local selectedTier = FusionConfig.TierOrder[1]
local tabButtons: { [string]: TextButton } = {}

--[[ Helpers ------------------------------------------------------------------ ]]

local function percent(bonus: number): string
	return ("+%d%%"):format(math.floor(bonus * 100 + 0.5))
end

local function itemName(itemId: string): string
	local def = ItemConfig.GetItemById(itemId)
	return if def then def.Name else itemId
end

-- One variant cell: filled when found, a "?" well when not.
local function buildCell(parent: Instance, tier: string, variant: string, found: boolean, z: number)
	local cell = Instance.new("Frame")
	cell.Name = variant
	cell.AnchorPoint = Vector2.new(0.5, 0.5)
	cell.Position = UDim2.fromScale(0.5, 0.5)
	cell.Size = UDim2.fromOffset(CELL_SIZE, CELL_SIZE)
	cell.ZIndex = z
	cell.Parent = parent
	UIKit.Corner(cell, 10)
	UIKit.Stroke(cell, 2)

	if not found then
		cell.BackgroundColor3 = Colors.Panel2
		UIKit.Label({
			Name = "Missing",
			Text = "?",
			Font = Fonts.Display,
			TextSize = 20,
			TextColor3 = Colors.Faint,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 1,
			Parent = cell,
		})
		return
	end

	if variant == "Rainbow" then
		cell.BackgroundColor3 = Colors.White
		local gradient = Instance.new("UIGradient")
		gradient.Color = UITheme.GetRainbowSequence()
		gradient.Rotation = 45
		gradient.Parent = cell
	else
		cell.BackgroundColor3 = UITheme.GetMutationColor(variant)
			or FusionConfig.TierAccentColors[tier]
			or Colors.Text
	end
	UIKit.Label({
		Name = "Found",
		Text = "✓",
		Font = Fonts.Display,
		TextSize = 20,
		TextColor3 = Colors.Ink,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z + 1,
		Parent = cell,
	})
end

--[[ Refresh ------------------------------------------------------------------ ]]

local function rebuildPage(found: { [string]: boolean })
	for _, child in page:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local z = page.ZIndex + 1
	local columnWidth = (1 - NAME_COLUMN) / #IndexConfig.Variants

	for order, item in ItemConfig.GetItemsByTier(selectedTier) do
		local row = Instance.new("Frame")
		row.Name = item.Id
		row.BackgroundColor3 = Colors.Panel2
		row.BackgroundTransparency = 0.4
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.LayoutOrder = order
		row.ZIndex = z
		row.Parent = page
		UIKit.Corner(row, UITheme.Radius.Row)

		UIKit.Label({
			Name = "Name",
			Text = item.Name,
			Font = Fonts.Display,
			TextSize = 15,
			TextColor3 = UITheme.GetTierLight(item.Tier),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(NAME_COLUMN, -12, 1, 0),
			ZIndex = z + 1,
			Stroke = UITheme.Stroke.Text,
			Parent = row,
		})
		for index, variant in IndexConfig.Variants do
			local slot = Instance.new("Frame")
			slot.Name = "Slot" .. variant
			slot.BackgroundTransparency = 1
			slot.Position = UDim2.fromScale(NAME_COLUMN + (index - 1) * columnWidth, 0)
			slot.Size = UDim2.fromScale(columnWidth, 1)
			slot.ZIndex = z + 1
			slot.Parent = row
			local mutation = if variant == IndexConfig.NORMAL then nil else variant
			buildCell(slot, item.Tier, variant, found[IndexConfig.GetKey(item.Id, mutation)] == true, z + 2)
		end
	end
end

local function refresh()
	if not modal then
		return
	end
	local found = TycoonController.GetIndex()
	bonusPill.Text = ("%s income"):format(percent(IndexConfig.GetMultiplier(found) - 1))
	countLabel.Text = ("%d / %d found · %s each · %s per full tier page"):format(
		IndexConfig.CountFound(found),
		IndexConfig.GetTotalEntries(),
		percent(IndexConfig.BonusPerEntry),
		percent(IndexConfig.BonusPerCompletedTier)
	)
	for tier, button in tabButtons do
		local have, total = IndexConfig.GetTierProgress(found, tier)
		UIKit.SetButton(button, {
			Style = if tier == selectedTier then "Teal" else "Disabled",
			Text = ("%s %d/%d"):format(tier, have, total),
			TextColor3 = if tier == selectedTier then Colors.Text else Colors.Muted,
		})
	end
	rebuildPage(found)
end

--[[ Build -------------------------------------------------------------------- ]]

local function build()
	modal = UIKit.Modal({
		Name = "IndexPanel",
		Title = "INDEX",
		DisplayOrder = 142,
		MaxSize = MAX_SIZE,
		HeaderTop = Colors.PanelTop,
	})
	bonusPill = UIKit.Pill({
		Name = "Bonus",
		Parent = modal.Header,
		Text = "",
		Gradient = UITheme.Gradients.Green,
		Font = Fonts.Display,
		TextSize = 15,
		Height = 28,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(UITheme.MinTapSize + 12), 0, 6),
		ZIndex = modal.Header.ZIndex,
		TextStroke = 1.5,
	})

	local content = modal.Content
	countLabel = UIKit.Label({
		Name = "Count",
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = content.ZIndex,
		Parent = content,
	})

	tabsFrame = Instance.new("ScrollingFrame")
	tabsFrame.Name = "Tabs"
	tabsFrame.BackgroundTransparency = 1
	tabsFrame.BorderSizePixel = 0
	tabsFrame.Position = UDim2.fromOffset(0, 24)
	tabsFrame.Size = UDim2.new(1, 0, 0, TAB_SIZE.Y + UITheme.SmallShadowOffset + 8)
	tabsFrame.ScrollingDirection = Enum.ScrollingDirection.X
	tabsFrame.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabsFrame.CanvasSize = UDim2.new()
	tabsFrame.ScrollBarThickness = 4
	tabsFrame.ScrollBarImageColor3 = Colors.Faint
	tabsFrame.ZIndex = content.ZIndex
	tabsFrame.Parent = content
	UIKit.Padding(tabsFrame, 2, 4, 6, 2)
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabsFrame
	for order, tier in FusionConfig.TierOrder do
		tabButtons[tier] = UIKit.Button({
			Name = tier .. "Tab",
			Parent = tabsFrame,
			Style = "Disabled",
			Text = tier,
			TextSize = 14,
			Size = UDim2.fromOffset(TAB_SIZE.X, TAB_SIZE.Y),
			LayoutOrder = order,
			ShadowOffset = UITheme.SmallShadowOffset,
			ZIndex = tabsFrame.ZIndex + 1,
			OnClick = function()
				selectedTier = tier
				refresh()
			end,
		})
	end

	local headerY = 24 + TAB_SIZE.Y + UITheme.SmallShadowOffset + 14
	local columnWidth = (1 - NAME_COLUMN) / #IndexConfig.Variants
	for index, variant in IndexConfig.Variants do
		UIKit.Label({
			Name = variant .. "Heading",
			Text = variant:upper(),
			Font = Fonts.BodyHeavy,
			TextSize = 11,
			TextColor3 = UITheme.GetMutationColor(if variant == IndexConfig.NORMAL then nil else variant)
				or Colors.Muted,
			Position = UDim2.new(NAME_COLUMN + (index - 1) * columnWidth, 0, 0, headerY),
			Size = UDim2.new(columnWidth, 0, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = content.ZIndex,
			Parent = content,
		})
	end

	local pageY = headerY + 20
	page = Instance.new("ScrollingFrame")
	page.Name = "Page"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Position = UDim2.fromOffset(0, pageY)
	page.Size = UDim2.new(1, 0, 1, -pageY)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new()
	page.ScrollBarThickness = 6
	page.ScrollBarImageColor3 = Colors.Faint
	page.ZIndex = content.ZIndex
	page.Parent = content
	UIKit.Padding(page, 3, 6, 6, 3)
	local pageLayout = Instance.new("UIListLayout")
	pageLayout.Padding = UDim.new(0, 8)
	pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pageLayout.Parent = page
end

--[[ New-entry toasts ----------------------------------------------------------- ]]

local function toastNew(items: { any }, completedTiers: { string })
	if #completedTiers > 0 then
		ToastController.Show(
			("%s · %s page complete!"):format(percent(IndexConfig.BonusPerCompletedTier), completedTiers[#completedTiers]),
			"Neutral"
		)
		return
	end
	if #items == 1 then
		local item = items[1]
		ToastController.Show(
			("NEW IN INDEX · %s · %s"):format(
				MutationConfig.GetDisplayName(itemName(item.ItemId), item.Mutation),
				percent(IndexConfig.BonusPerEntry)
			),
			"Neutral"
		)
	elseif #items > 1 then
		ToastController.Show(
			("NEW IN INDEX · %d entries · %s"):format(#items, percent(IndexConfig.BonusPerEntry * #items)),
			"Neutral"
		)
	end
end

-- A single pull or fusion result: { NewItem, NewIndex, IndexTierComplete }.
local function onSingleResult(result: any)
	if typeof(result) ~= "table" or result.Success ~= true or result.NewIndex ~= true or not result.NewItem then
		return
	end
	local completed = if typeof(result.IndexTierComplete) == "string" then { result.IndexTierComplete } else {}
	toastNew({ result.NewItem }, completed)
end

-- A batch result (Fuse All, Pull x10): { NewIndexItems, IndexTiersCompleted }.
function IndexPanel.ToastBatch(result: any)
	if typeof(result) ~= "table" or typeof(result.NewIndexItems) ~= "table" then
		return
	end
	local completed = if typeof(result.IndexTiersCompleted) == "table" then result.IndexTiersCompleted else {}
	toastNew(result.NewIndexItems, completed)
end

--[[ Public ------------------------------------------------------------------- ]]

function IndexPanel.Toggle()
	if modal.IsOpen() then
		modal.Close()
	else
		refresh()
		modal.Open()
	end
end

function IndexPanel.Init()
	build()
	TycoonController.TycoonChanged:Connect(function()
		if modal.IsOpen() then
			refresh()
		end
	end)
	RemoteEvents.GachaPullResult.OnClientEvent:Connect(onSingleResult)
	-- Fusions toast after the machine's reveal, so they never spoil it.
	FusionController.FusionResolved:Connect(onSingleResult)
	FusionController.FuseAllResolved:Connect(IndexPanel.ToastBatch)
end

return IndexPanel
