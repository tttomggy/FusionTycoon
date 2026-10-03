--[[
	ItemPickerUI
	------------
	The inventory, as a grid of item cards. Two modes, same public API:

	  * Pedestal mode - Open(entries, onSelect, title?, options?): tap a card
	    to select it, then DISPLAY sends the Uid of a copy that isn't already
	    on a pedestal. Title "PICK AN ITEM".
	  * Browse mode - Open(entries, nil, title?): cards only show info, no
	    footer. Title "YOUR ITEMS".

	Identical ItemIds are grouped into one card with a count. Entries are
	{Uid, ItemId, Name, Tier, InUse}; callers pass every owned item, including
	ones on pedestals (shown with an ON PEDESTAL tag).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TycoonController = require(script.Parent.Parent.Controllers.TycoonController)
local UIKit = require(script.Parent.UIKit)

local ItemPickerUI = {}

export type PickerEntry = {
	Uid: string,
	ItemId: string?,
	Name: string,
	Tier: string,
	Mutation: string?,
	InUse: boolean?,
}

export type PickerOptions = {
	Subtitle: string?,
}

type Card = {
	ItemId: string,
	Name: string, -- includes the mutation ("Golden Star Core")
	Tier: string,
	Mutation: string?,
	Count: number,
	InUseCount: number,
	FreeEntries: { PickerEntry },
}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(680, 620)
local CARD_HEIGHT = 178
local GRID_GAP = 12
local FOOTER_HEIGHT = 76
local HINT_CARD_THRESHOLD = 8
local PEDESTAL_TITLE = "PICK AN ITEM"
local BROWSE_TITLE = "YOUR ITEMS"

local modal: UIKit.Modal? = nil
local chipsRow: Frame
local grid: ScrollingFrame
local gridLayout: UIGridLayout
local footer: Frame
local footerHolder: Frame
local footerOrbSlot: Frame
local footerName: TextLabel
local footerDetail: TextLabel
local displayButton: TextButton

local currentEntries: { PickerEntry } = {}
local currentOnSelect: ((PickerEntry) -> ())? = nil
local selectedFilter: string? = nil -- nil = All
local selectedCard: Card? = nil
local selectedHolder: Frame? = nil

--[[ Data ----------------------------------------------------------------------- ]]

local function tierRank(tier: string): number
	return ItemConfig.Tiers[tier] or 0
end

local function getMultiplier(): number
	return TycoonController.GetIncomeMultiplier()
end

local function earnRate(tier: string, mutation: string?): number
	return TycoonConfig.GetItemCashPerSecond(tier, mutation) * getMultiplier()
end

local function groupCards(entries: { PickerEntry }): { Card }
	local byId: { [string]: Card } = {}
	local cards: { Card } = {}
	for _, entry in entries do
		-- Mutated and normal copies of an item are separate stacks.
		local id = entry.ItemId or entry.Name
		local key = ("%s|%s"):format(id, entry.Mutation or "Normal")
		local card = byId[key]
		if not card then
			card = {
				ItemId = id,
				Name = MutationConfig.GetDisplayName(entry.Name, entry.Mutation),
				Tier = entry.Tier,
				Mutation = entry.Mutation,
				Count = 0,
				InUseCount = 0,
				FreeEntries = {},
			}
			byId[key] = card
			table.insert(cards, card)
		end
		card.Count += 1
		if entry.InUse then
			card.InUseCount += 1
		else
			table.insert(card.FreeEntries, entry)
		end
	end
	-- Best items first: what they earn (tier x mutation) descending, then
	-- tier, then name.
	table.sort(cards, function(a, b)
		local rateA = TycoonConfig.GetItemCashPerSecond(a.Tier, a.Mutation)
		local rateB = TycoonConfig.GetItemCashPerSecond(b.Tier, b.Mutation)
		if rateA ~= rateB then
			return rateA > rateB
		end
		local rankA, rankB = tierRank(a.Tier), tierRank(b.Tier)
		if rankA ~= rankB then
			return rankA > rankB
		end
		return a.Name < b.Name
	end)
	return cards
end

local function pedestalsUsed(): number
	local used = 0
	for _ in TycoonController.GetPedestalDisplays() do
		used += 1
	end
	return used
end

--[[ Footer ---------------------------------------------------------------------- ]]

local function refreshFooter()
	for _, child in footerOrbSlot:GetChildren() do
		child:Destroy()
	end
	local card = selectedCard
	local pedestals = ("Pedestals %d / %d used"):format(pedestalsUsed(), PlotLayout.PEDESTAL_COUNT)
	if not card then
		footerName.Text = "Tap an item"
		footerDetail.Text = pedestals
		UIKit.SetButton(displayButton, { Style = "Disabled", Text = "DISPLAY", TextColor3 = Colors.Muted })
		return
	end

	local orb = UIKit.TierOrb(card.Tier, 44)
	orb.ZIndex = footerOrbSlot.ZIndex
	orb.Parent = footerOrbSlot
	footerName.Text = card.Name
	footerDetail.Text = ("Earns %s with your %s · %s"):format(
		UIKit.Colored(NumberFormat.Money(earnRate(card.Tier, card.Mutation)) .. "/s", Colors.Cash),
		NumberFormat.Multiplier(getMultiplier()),
		pedestals
	)
	if #card.FreeEntries == 0 then
		UIKit.SetButton(displayButton, { Style = "Disabled", Text = "ALL SHOWN", TextColor3 = Colors.Muted })
	else
		UIKit.SetButton(displayButton, { Style = "Green", Text = "DISPLAY", TextColor3 = Colors.Text })
	end
end

local function onDisplayClicked()
	local card = selectedCard
	local onSelect = currentOnSelect
	if not card or not onSelect or #card.FreeEntries == 0 then
		return
	end
	local entry = card.FreeEntries[1]
	ItemPickerUI.Close()
	onSelect(entry)
end

--[[ Cards ----------------------------------------------------------------------- ]]

local function setSelected(card: Card, holder: Frame)
	if selectedHolder then
		local old = selectedHolder:FindFirstChild("Selection")
		if old then
			old:Destroy()
		end
	end
	selectedCard = card
	selectedHolder = holder

	-- 4 px white outline sitting 2 px outside the card.
	local outline = Instance.new("Frame")
	outline.Name = "Selection"
	outline.BackgroundTransparency = 1
	outline.Position = UDim2.fromOffset(-2, -2)
	outline.Size = UDim2.new(1, 4, 1, 4)
	outline.ZIndex = holder.ZIndex + 8
	outline.Parent = holder
	UIKit.Corner(outline, UITheme.Radius.Row + 2)
	UIKit.Stroke(outline, 4, Colors.White)

	local pop = holder:FindFirstChild("SelectPop") :: UIScale?
	if not pop then
		local newPop = Instance.new("UIScale")
		newPop.Name = "SelectPop"
		newPop.Parent = holder
		pop = newPop
	end
	local scale = pop :: UIScale
	scale.Scale = 1.06
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back), { Scale = 1.03 }):Play()

	refreshFooter()
end

local function buildCard(card: Card, order: number, selectable: boolean)
	local tierColor = FusionConfig.TierAccentColors[card.Tier] or Colors.Text
	local body, holder = UIKit.Panel({
		Name = card.ItemId,
		Parent = grid,
		LayoutOrder = order,
		Gradient = {
			{ 0, UITheme.TowardInk(tierColor, 0.7) },
			{ 0.7, Colors.CardBottom },
			{ 1, Colors.CardBottom },
		},
		Radius = UITheme.Radius.Row,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = 3,
	})
	-- UIGridLayout sizes the holder; the body already fills it.
	local z = body.ZIndex + 1

	local orb = UIKit.TierOrb(card.Tier, 74)
	orb.AnchorPoint = Vector2.new(0.5, 0)
	orb.Position = UDim2.new(0.5, 0, 0, 16)
	orb.ZIndex = z
	orb.Parent = body

	UIKit.Label({
		Name = "ItemName",
		Text = card.Name,
		Font = Fonts.Display,
		TextSize = 16,
		Position = UDim2.fromOffset(6, 100),
		Size = UDim2.new(1, -12, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Label({
		Name = "Tier",
		Text = card.Tier:upper(),
		Font = Fonts.BodyHeavy,
		TextSize = 11,
		TextColor3 = UITheme.GetTierLight(card.Tier),
		Position = UDim2.fromOffset(6, 122),
		Size = UDim2.new(1, -12, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = body,
	})
	UIKit.Label({
		Name = "Earn",
		Text = NumberFormat.Money(earnRate(card.Tier, card.Mutation)) .. "/s",
		Font = Fonts.Body,
		TextSize = 12,
		TextColor3 = Colors.Cash,
		Position = UDim2.fromOffset(6, 140),
		Size = UDim2.new(1, -12, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = body,
	})

	-- Mutation tag top-right (×2 / ×5 / ×12); the stack count drops below it.
	local mutationPill = UIKit.MutationPill({
		Parent = body,
		Mutation = card.Mutation,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		ZIndex = z + 2,
	})
	local countY = if mutationPill then 28 else 6

	if card.Count > 1 then
		UIKit.Label({
			Name = "Count",
			Text = "x" .. NumberFormat.Short(card.Count),
			Font = Fonts.Display,
			TextSize = 16,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, countY),
			Size = UDim2.fromOffset(50, 20),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = z + 2,
			Stroke = UITheme.Stroke.Text,
			Parent = body,
		})
	end

	if card.InUseCount > 0 then
		UIKit.Pill({
			Name = "OnPedestal",
			Parent = body,
			Text = "ON PEDESTAL",
			Color = Colors.Cash,
			TextColor3 = Colors.Ink,
			Font = Fonts.BodyHeavy,
			TextSize = 10,
			Height = 18,
			Position = UDim2.fromOffset(6, 6),
			ZIndex = z + 2,
		})
	end

	if selectable then
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = z + 5
		hit.Parent = body
		hit.Activated:Connect(function()
			setSelected(card, holder)
		end)
	end
end

local function buildHintCard(order: number)
	local holder = Instance.new("Frame")
	holder.Name = "GachaHint"
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = order
	holder.ZIndex = 3
	holder.Parent = grid

	-- "Dashed" look: no fill, a faint, semi-transparent outline.
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = 4
	body.Parent = holder
	UIKit.Corner(body, UITheme.Radius.Row)
	local stroke = UIKit.Stroke(body, 3, Colors.Faint)
	stroke.Transparency = 0.35

	UIKit.Label({
		Text = "Pull at the\nGacha Pad",
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Faint,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 5,
		Parent = body,
	})
end

local function clearGrid()
	for _, child in grid:GetChildren() do
		if not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	selectedCard = nil
	selectedHolder = nil
end

--[[ Chips ----------------------------------------------------------------------- ]]

local renderGrid: () -> ()

local function buildChips(cards: { Card })
	for _, child in chipsRow:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local counts: { [string]: number } = {}
	local total = 0
	for _, card in cards do
		counts[card.Tier] = (counts[card.Tier] or 0) + card.Count
		total += card.Count
	end

	local function chip(label: string, filter: string?, textColor: Color3, order: number)
		local selected = selectedFilter == filter
		local pill = UIKit.Pill({
			Name = filter or "All",
			Parent = chipsRow,
			Text = label,
			Color = if selected then Colors.White else Colors.Panel2,
			TextColor3 = if selected then Colors.Ink else textColor,
			Font = Fonts.BodyHeavy,
			TextSize = 13,
			Height = UITheme.MinTapSize - 8,
			StrokeThickness = 3,
			LayoutOrder = order,
			ZIndex = 5,
		})
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		-- Tap target padded out to the 44 px minimum.
		hit.AnchorPoint = Vector2.new(0.5, 0.5)
		hit.Position = UDim2.fromScale(0.5, 0.5)
		hit.Size = UDim2.new(1, 20, 0, UITheme.MinTapSize)
		hit.ZIndex = 6
		hit.Parent = pill
		hit.Activated:Connect(function()
			selectedFilter = filter
			renderGrid()
		end)
	end

	chip(("All %d"):format(total), nil, Colors.Text, 0)
	local order = 1
	for index = #FusionConfig.TierOrder, 1, -1 do
		local tier = FusionConfig.TierOrder[index]
		local count = counts[tier] or 0
		if count > 0 then
			chip(("%s %d"):format(tier, count), tier, UITheme.GetTierLight(tier), order)
			order += 1
		end
	end
end

renderGrid = function()
	clearGrid()
	local cards = groupCards(currentEntries)
	buildChips(cards)

	local selectable = currentOnSelect ~= nil
	local shown = 0
	for _, card in cards do
		if selectedFilter == nil or card.Tier == selectedFilter then
			shown += 1
			buildCard(card, shown, selectable)
		end
	end
	if shown < HINT_CARD_THRESHOLD then
		buildHintCard(shown + 1)
	end
	grid.CanvasPosition = Vector2.zero
	if selectable then
		refreshFooter()
	end
end

--[[ Build ----------------------------------------------------------------------- ]]

local function build()
	local built = UIKit.Modal({
		Name = "ItemPickerUI",
		Title = BROWSE_TITLE,
		DisplayOrder = 150,
		MaxSize = MAX_SIZE,
		HeaderTop = Colors.InventoryTop,
	})
	modal = built
	local content = built.Content

	chipsRow = Instance.new("Frame")
	chipsRow.Name = "Chips"
	chipsRow.BackgroundTransparency = 1
	chipsRow.Size = UDim2.new(1, 0, 0, UITheme.MinTapSize - 8)
	chipsRow.ZIndex = 5
	chipsRow.Parent = content
	local chipsLayout = Instance.new("UIListLayout")
	chipsLayout.FillDirection = Enum.FillDirection.Horizontal
	chipsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	chipsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipsLayout.Padding = UDim.new(0, 8)
	chipsLayout.Wraps = true
	chipsLayout.Parent = chipsRow

	grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = Colors.Faint
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ZIndex = 3
	grid.Parent = content
	UIKit.Padding(grid, 4, 8, 10, 4)

	gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	-- Selection footer (pedestal mode only).
	local footerBody, holder = UIKit.Panel({
		Name = "Footer",
		Parent = content,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -UITheme.SmallShadowOffset),
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
		Color = Colors.Panel2,
		Radius = UITheme.Radius.Row,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = 5,
	})
	footer = footerBody
	footerHolder = holder
	local z = footer.ZIndex + 1

	footerOrbSlot = Instance.new("Frame")
	footerOrbSlot.Name = "OrbSlot"
	footerOrbSlot.BackgroundTransparency = 1
	footerOrbSlot.AnchorPoint = Vector2.new(0, 0.5)
	footerOrbSlot.Position = UDim2.new(0, 14, 0.5, 0)
	footerOrbSlot.Size = UDim2.fromOffset(44, 44)
	footerOrbSlot.ZIndex = z
	footerOrbSlot.Parent = footer

	footerName = UIKit.Label({
		Name = "SelectedName",
		Font = Fonts.Display,
		TextSize = 18,
		Position = UDim2.fromOffset(70, 12),
		Size = UDim2.new(1, -(70 + 150 + 24), 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = footer,
	})
	footerDetail = UIKit.Label({
		Name = "SelectedDetail",
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Muted,
		RichText = true,
		TextWrapped = true,
		Position = UDim2.fromOffset(70, 38),
		Size = UDim2.new(1, -(70 + 150 + 24), 0, 30),
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = z,
		Parent = footer,
	})
	displayButton = UIKit.Button({
		Name = "Display",
		Parent = footer,
		Style = "Green",
		Text = "DISPLAY",
		TextSize = 20,
		Size = UDim2.fromOffset(150, 52),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, -2),
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z,
		OnClick = onDisplayClicked,
	})
end

local function layoutFor(pedestalMode: boolean, isPhone: boolean)
	local columns = if isPhone then 3 else 4
	local gridTop = UITheme.MinTapSize - 8 + 12
	local footerSpace = if pedestalMode then FOOTER_HEIGHT + UITheme.SmallShadowOffset + 10 else 0
	grid.Position = UDim2.fromOffset(0, gridTop)
	grid.Size = UDim2.new(1, 0, 1, -(gridTop + footerSpace))
	gridLayout.CellSize = UDim2.new(1 / columns, -GRID_GAP * (columns - 1) / columns, 0, CARD_HEIGHT)
	footerHolder.Visible = pedestalMode
end

--[[ Public ---------------------------------------------------------------------- ]]

function ItemPickerUI.Close()
	if modal then
		modal.Close()
	end
end

-- onSelect is optional: nil opens browse mode (cards only show info).
-- title defaults to "PICK AN ITEM" / "YOUR ITEMS"; options.Subtitle adds the
-- line under it (e.g. "For Pedestal 3 · best items first").
function ItemPickerUI.Open(items: { PickerEntry }, onSelect: ((PickerEntry) -> ())?, title: string?, options: PickerOptions?)
	if not modal then
		build()
	end
	local m = modal :: UIKit.Modal

	currentEntries = items
	currentOnSelect = onSelect
	selectedFilter = nil

	local pedestalMode = onSelect ~= nil
	m.Title.Text = title or (if pedestalMode then PEDESTAL_TITLE else BROWSE_TITLE)
	local subtitle = options and options.Subtitle
	m.Subtitle.Text = subtitle or ""
	m.Subtitle.Visible = subtitle ~= nil

	layoutFor(pedestalMode, UIKit.IsPhone())
	renderGrid()
	m.Open()
end

return ItemPickerUI
