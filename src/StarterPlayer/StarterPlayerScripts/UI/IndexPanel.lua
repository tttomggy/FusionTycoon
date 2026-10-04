--[[
	IndexPanel
	----------
	The INDEX modal (HUD button): every item x { Normal, Golden, Diamond,
	Rainbow }, and the income it pays for collecting them (IndexConfig).

	  * Header INDEX with a green "+42% income" pill
	  * "37 / 119 found · +1% each · +5% per full tier page"; 7 variant columns
	    (Normal + six mutations; unfound event-only cells show a clock)
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
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
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

-- Seven variant columns (Normal + six mutations) need the width; on a phone
-- the Modal's 92% fit applies and the page scrolls.
local MAX_SIZE = Vector2.new(720, 560)
local TAB_SIZE = Vector2.new(132, UITheme.MinTapSize)
local ROW_HEIGHT = 52
local CELL_SIZE = UITheme.MinTapSize
local NAME_COLUMN = 0.3 -- of the page width
local HEADING_TEXT_SIZE = 12

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
		-- Event-only mutations: a clock, since only an event can grant them.
		UIKit.Label({
			Name = "Missing",
			Text = if MutationConfig.IsEventOnly(variant) then "🕐" else "?",
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

--[[ "How to get it" (tap a mutation heading) --------------------------------------- ]]

local howToBox: Frame
local howToTitle: TextLabel
local howToLine: TextLabel
local howToCount: TextLabel
local howToShown: string? = nil
local buildHowToBox: (content: Frame, top: number) -> ()
local toggleHowTo: (mutation: string) -> ()

local function pct(chance: number): string
	return ("%d"):format(math.floor(chance * 100 + 0.5))
end

-- One line on how `mutation` is obtained, numbers from EventConfig.
local function howToGet(mutation: string): string
	if mutation == "Charged" then
		return "Only from lightning during a Power Surge."
	elseif mutation == "Void" then
		return ("Only from fusing during a Void Moon (1 in %d fusions). Void Moons come at :00 some hours, and on Admin Abuse Saturdays."):format(
			math.floor(1 / EventConfig.VoidChance + 0.5)
		)
	elseif mutation == "Celestial" then
		return ("Only from meteor cores (%s%%)."):format(pct(EventConfig.MeteorCelestialChance))
	end
	return ("Any pull or fusion. Rainbow Storm makes it ×%d more likely (Golden Rain: Golden ×%d)."):format(
		EventConfig.RainbowStormOdds,
		EventConfig.GoldenRainGoldenOdds
	)
end

local function foundCount(mutation: string): number
	local suffix = "|" .. mutation
	local found = 0
	for key, on in TycoonController.GetIndex() do
		if on and key:sub(-#suffix) == suffix then
			found += 1
		end
	end
	return found
end

buildHowToBox = function(content: Frame, top: number)
	local box = Instance.new("Frame")
	box.Name = "HowToGet"
	box.BackgroundColor3 = Colors.Panel2
	box.Position = UDim2.fromOffset(0, top)
	box.Size = UDim2.new(1, 0, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.ZIndex = content.ZIndex + 5
	box.Visible = false
	box.Parent = content
	UIKit.Corner(box, UITheme.Radius.Row)
	local stroke = UIKit.Stroke(box, 3)
	stroke.Name = "Outline"
	UIKit.Padding(box, 10, 14, 10, 14)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = box
	howToTitle = UIKit.Label({
		Name = "Title",
		Font = Fonts.Display,
		TextSize = 20,
		Size = UDim2.new(1, -UITheme.MinTapSize, 0, 24),
		LayoutOrder = 1,
		ZIndex = box.ZIndex + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = box,
	})
	howToLine = UIKit.Label({
		Name = "Line",
		Font = Fonts.Body,
		TextSize = 15,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		ZIndex = box.ZIndex + 1,
		Parent = box,
	})
	howToCount = UIKit.Label({
		Name = "Count",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = Colors.GoldLabel,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 3,
		ZIndex = box.ZIndex + 1,
		Parent = box,
	})
	-- Tapping the same heading again (or another tier tab) closes it.
	howToBox = box
end

toggleHowTo = function(mutation: string)
	if howToShown == mutation and howToBox.Visible then
		howToShown = nil
		howToBox.Visible = false
		return
	end
	howToShown = mutation
	local color = UITheme.GetMutationColor(mutation) or Colors.Text
	howToTitle.Text = ("%s ×%d"):format(mutation:upper(), MutationConfig.GetMultiplier(mutation))
	howToTitle.TextColor3 = color
	howToLine.Text = howToGet(mutation)
	howToCount.Text = ("You have %d / %d"):format(foundCount(mutation), #ItemConfig.Items)
	local outline = howToBox:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Color = color
	end
	howToBox.Visible = true
end

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
				howToShown = nil
				howToBox.Visible = false
				refresh()
			end,
		})
	end

	local headerY = 24 + TAB_SIZE.Y + UITheme.SmallShadowOffset + 14
	local columnWidth = (1 - NAME_COLUMN) / #IndexConfig.Variants
	local pageY = headerY + 20
	for index, variant in IndexConfig.Variants do
		local isMutation = variant ~= IndexConfig.NORMAL
		local heading = UIKit.Label({
			Name = variant .. "Heading",
			Text = variant:upper() .. (if isMutation then " ⓘ" else ""),
			Font = Fonts.BodyHeavy,
			TextSize = HEADING_TEXT_SIZE,
			TextColor3 = UITheme.GetMutationColor(if isMutation then variant else nil) or Colors.Muted,
			Position = UDim2.new(NAME_COLUMN + (index - 1) * columnWidth, 0, 0, headerY),
			Size = UDim2.new(columnWidth, 0, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = content.ZIndex,
			Parent = content,
		})
		if isMutation then
			-- A 44 px tall invisible tap target centred on the heading.
			local tap = Instance.new("TextButton")
			tap.Name = variant .. "HeadingTap"
			tap.Text = ""
			tap.BackgroundTransparency = 1
			tap.AnchorPoint = Vector2.new(0, 0.5)
			tap.Position = UDim2.new(heading.Position.X.Scale, 0, 0, headerY + 8)
			tap.Size = UDim2.new(columnWidth, 0, 0, UITheme.MinTapSize)
			tap.ZIndex = content.ZIndex
			tap.Parent = content
			tap.Activated:Connect(function()
				toggleHowTo(variant)
			end)
		end
	end
	buildHowToBox(content, pageY)

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
	RemoteEvents.GachaMultiPullResult.OnClientEvent:Connect(function(result: any)
		if typeof(result) == "table" and result.Success == true then
			IndexPanel.ToastBatch(result)
		end
	end)
end

return IndexPanel
