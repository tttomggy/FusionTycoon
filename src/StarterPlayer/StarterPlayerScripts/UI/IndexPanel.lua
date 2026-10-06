--[[
	IndexPanel
	----------
	The INDEX modal (HUD button), laid out as a collection book: every item x
	{ Normal + six mutations }, and the income it pays for collecting them
	(IndexConfig: the data, counts and bonus rules all live there).

	  * Header "INDEX", under it "18 / 119 found · every find +1% income · a
	    full page +5%", the green "+18% income" pill and ✕ on the right.
	  * Tier tabs Common → Secret: the tier name in its colour, "8 / 21", a
	    thin progress bar, and "+5% at 21" on the selected tab.
	  * Column header: the seven variant names in their mutation colours;
	    the event-only ones carry their event icon (⚡ 🌙 ☄). Not tappable.
	  * One row card per item: name, "3 / 7 · $12/s", then seven orb cells.
	    Found = the real orb in that variant (UIKit.TierOrb + the mutation's
	    look); not found = a dark dashed circle with "?" (event-only: its
	    icon). A complete row (7/7) gets a gold stroke, a soft gold glow and
	    "★ COMPLETE 7/7".
	  * The info strip at the bottom: tap any orb for "<Item> · <Variant ×N>",
	    how to get it, and found / not found yet.

	Only the selected tier's rows exist; they rebuild on a tab change, an
	Index change or a phone/desktop switch (orbs 54 px, 40 px on a phone;
	the cell is the >= 44 px tap target, not the orb).

	Also toasts new entries from pulls and fusions (the server flags them):
	"NEW IN INDEX · Golden Star Core · +1%", or "+5% · Legendary page
	complete!" when that entry finished a page.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local Controllers = script.Parent.Parent.Controllers
local TycoonController = require(Controllers.TycoonController)
local ToastController = require(Controllers.ToastController)
local FusionController = require(Controllers.FusionController)
local TutorialCards = require(script.Parent.TutorialCards)
local UIKit = require(script.Parent.UIKit)

local IndexPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

-- 720 wide on desktop; on a phone the Modal's 92% fit applies and the rows
-- scroll.
local MAX_SIZE = Vector2.new(720, 600)
local TAB_SIZE = Vector2.new(140, 62)
local TAB_GAP = 8
local HEADING_HEIGHT = 20
local NAME_COLUMN = 0.27 -- of the row width
local ORB_SIZE = 54
local PHONE_ORB_SIZE = 40
local ROW_PADDING = 8 -- above and below the orbs
local INFO_HEIGHT = 66
local SCROLLBAR = 6
local GLOW_SPREAD = 6 -- px the complete row's gold glow shows past the card
local RAINBOW_DEG_PER_SEC = 90

-- The event that grants each event-only mutation (its icon on the column
-- heading and on an unfound cell).
local EVENT_ICON = {
	Charged = EventConfig.Icons.PowerSurge,
	Void = EventConfig.Icons.Night,
	Celestial = EventConfig.Icons.MeteorShower,
} :: { [string]: string }

type Tab = { Button: TextButton, Name: TextLabel, Count: TextLabel, Goal: TextLabel, Bar: Frame, Stroke: UIStroke }

local modal: UIKit.Modal
local bonusPill: TextLabel
local page: ScrollingFrame
local infoTitle: TextLabel
local infoLine: TextLabel
local infoStatus: TextLabel
local selectedTier = FusionConfig.TierOrder[1]
local tabs: { [string]: Tab } = {}
local builtKey: string? = nil -- tier|found count|phone the page was built for
local rainbowGradients: { UIGradient } = {}
local rainbowConnection: RBXScriptConnection? = nil

--[[ Helpers ------------------------------------------------------------------ ]]

local function percent(bonus: number): string
	return ("+%d%%"):format(math.floor(bonus * 100 + 0.5))
end

local function itemName(itemId: string): string
	local def = ItemConfig.GetItemById(itemId)
	return if def then def.Name else itemId
end

local function pct(chance: number): string
	return ("%d"):format(math.floor(chance * 100 + 0.5))
end

local function mutationOf(variant: string): string?
	return if variant == IndexConfig.NORMAL then nil else variant
end

-- One line on how `variant` is obtained, numbers from EventConfig.
local function howToGet(variant: string): string
	if variant == IndexConfig.NORMAL then
		return "Any pull, or a fusion without a mutation."
	elseif variant == "Charged" then
		return "Only from lightning during a Power Surge."
	elseif variant == "Void" then
		return ("Only from fusing during a Void Moon (1 in %d fusions). Void Moons come at :00 some hours, and on Admin Abuse Saturdays."):format(
			math.floor(1 / EventConfig.VoidChance + 0.5)
		)
	elseif variant == "Celestial" then
		return ("Only from meteor cores (%s%%)."):format(pct(EventConfig.MeteorCelestialChance))
	end
	return ("Any pull or fusion. Rainbow Storm makes it ×%d more likely (Golden Rain: Golden ×%d)."):format(
		EventConfig.RainbowStormOdds,
		EventConfig.GoldenRainGoldenOdds
	)
end

local function variantColor(variant: string): Color3
	return UITheme.GetMutationColor(mutationOf(variant)) or Colors.Muted
end

local function variantLabel(variant: string): string
	local mutation = mutationOf(variant)
	if not mutation then
		return variant
	end
	return ("%s ×%d"):format(variant, MutationConfig.GetMultiplier(mutation))
end

--[[ Rainbow hue cycle (client-only, only while the panel is open) --------------- ]]

local function stopRainbow()
	local connection = rainbowConnection
	if connection then
		connection:Disconnect()
		rainbowConnection = nil
	end
end

local function startRainbow()
	if rainbowConnection or #rainbowGradients == 0 then
		return
	end
	rainbowConnection = RunService.RenderStepped:Connect(function(dt: number)
		for _, gradient in rainbowGradients do
			gradient.Rotation = (gradient.Rotation + RAINBOW_DEG_PER_SEC * dt) % 360
		end
	end)
end

--[[ Orb cells ------------------------------------------------------------------ ]]

local function circle(parent: Instance, name: string, scale: number, color: Color3, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(scale, scale)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UIKit.Corner(frame, 999)
	return frame
end

-- The mutation's look on top of a TierOrb (which already carries the Ink gap
-- and the mutation-colour ring, like MutationPill): a tint over the orb,
-- plus a glow behind it for Charged / Celestial, a faceted sweep for
-- Diamond and the hue-cycling gradient for Rainbow.
local function applyLook(holder: Frame, mutation: string)
	local orb = holder:FindFirstChild("Orb") :: Frame?
	if not orb then
		return
	end
	local color = UITheme.GetMutationColor(mutation) or Colors.White
	if mutation == "Golden" then
		circle(orb, "Tint", 1, color, 0.45)
	elseif mutation == "Charged" then
		circle(holder, "MutationGlow", 1.3, color, 0.5)
		circle(orb, "Tint", 1, color, 0.55)
	elseif mutation == "Diamond" then
		local sheen = circle(orb, "Tint", 1, color, 0)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 35
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.28, 0.75),
			NumberSequenceKeypoint.new(0.3, 0.1),
			NumberSequenceKeypoint.new(0.42, 0.6),
			NumberSequenceKeypoint.new(0.52, 0.15),
			NumberSequenceKeypoint.new(0.55, 0.8),
			NumberSequenceKeypoint.new(0.75, 0.45),
			NumberSequenceKeypoint.new(1, 0.85),
		})
		gradient.Parent = sheen
	elseif mutation == "Void" then
		circle(orb, "Tint", 1, UITheme.MutationOrbTint.Void, 0.3)
	elseif mutation == "Rainbow" then
		local tint = circle(orb, "Tint", 1, Colors.White, 0.35)
		local gradient = Instance.new("UIGradient")
		gradient.Color = UITheme.GetRainbowSequence()
		gradient.Parent = tint
		table.insert(rainbowGradients, gradient)
	elseif mutation == "Celestial" then
		circle(holder, "MutationGlow", 1.35, color, 0.45)
		circle(orb, "Tint", 1, color, 0.45)
	end
end

-- The unfound cell: a dark circle with a dashed-look stroke (a striped
-- transparency gradient on the stroke) and a muted "?" or the event icon.
local function buildEmpty(parent: Instance, variant: string, size: number, z: number)
	local well = Instance.new("Frame")
	well.Name = "Empty"
	well.AnchorPoint = Vector2.new(0.5, 0.5)
	well.Position = UDim2.fromScale(0.5, 0.5)
	well.Size = UDim2.fromOffset(size, size)
	well.BackgroundColor3 = Colors.Ink
	well.BackgroundTransparency = 0.25
	well.ZIndex = z
	well.Parent = parent
	UIKit.Corner(well, 999)
	local stroke = UIKit.Stroke(well, 2, Colors.Faint)
	local keypoints = {}
	local dashes = 5 -- x4 keypoints: a NumberSequence holds at most 20
	for index = 0, dashes - 1 do
		local a = index / dashes
		local b = (index + 0.5) / dashes
		table.insert(keypoints, NumberSequenceKeypoint.new(a, 0))
		table.insert(keypoints, NumberSequenceKeypoint.new(math.max(a, b - 0.001), 0))
		table.insert(keypoints, NumberSequenceKeypoint.new(b, 1))
		table.insert(keypoints, NumberSequenceKeypoint.new(math.max(b, (index + 1) / dashes - 0.001), 1))
	end
	keypoints[#keypoints] = NumberSequenceKeypoint.new(1, 1)
	local dash = Instance.new("UIGradient")
	dash.Rotation = 45
	dash.Transparency = NumberSequence.new(keypoints)
	dash.Parent = stroke
	local icon = EVENT_ICON[variant]
	UIKit.Label({
		Name = "Missing",
		Text = icon or "?",
		Font = Fonts.Display,
		TextSize = math.floor(size * 0.4),
		TextColor3 = Colors.Faint,
		TextTransparency = if icon then 0.3 else 0,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z + 1,
		Parent = well,
	})
end

local function showInfo(item: ItemConfig.ItemDef, variant: string, found: boolean)
	local mutation = mutationOf(variant)
	infoTitle.Text = ("%s · %s"):format(item.Name, variantLabel(variant))
	infoTitle.TextColor3 = if mutation then variantColor(variant) else UITheme.GetTierLight(item.Tier)
	infoLine.Text = howToGet(variant)
	infoStatus.Text = if found then "✦ found" else "not found yet"
	infoStatus.TextColor3 = if found then Colors.ShieldTeal else Colors.Faint
end

local function buildCell(parent: Instance, item: ItemConfig.ItemDef, variant: string, found: boolean, orbSize: number, z: number)
	-- The whole column slot is the tap target (>= 44 px on every layout).
	local cell = Instance.new("TextButton")
	cell.Name = variant
	cell.Text = ""
	cell.AutoButtonColor = false
	cell.BackgroundTransparency = 1
	cell.Size = UDim2.fromScale(1, 1)
	cell.ZIndex = z
	cell.Parent = parent
	cell.Activated:Connect(function()
		showInfo(item, variant, found)
	end)

	if not found then
		buildEmpty(cell, variant, orbSize, z + 1)
		return
	end
	local mutation = mutationOf(variant)
	local orb = UIKit.TierOrb(item.Tier, orbSize, 0, mutation)
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Position = UDim2.fromScale(0.5, 0.5)
	if mutation then
		applyLook(orb, mutation)
	end
	orb.Parent = cell
	orb.ZIndex = z + 1
	for _, child in orb:GetChildren() do
		-- The look's extra layers: the glow under everything, tints on the orb.
		if child:IsA("GuiObject") and child.Name == "MutationGlow" then
			child.ZIndex = z + 1
		end
	end
	local body = orb:FindFirstChild("Orb")
	if body then
		for _, child in body:GetChildren() do
			if child:IsA("GuiObject") then
				child.ZIndex = z + 4
			end
		end
	end
end

--[[ Page ----------------------------------------------------------------------- ]]

local function rowHeight(orbSize: number): number
	return math.max(orbSize, UITheme.MinTapSize) + ROW_PADDING * 2
end

local function buildRow(item: ItemConfig.ItemDef, order: number, found: { [string]: boolean }, orbSize: number, z: number)
	local have = 0
	for _, variant in IndexConfig.Variants do
		if found[IndexConfig.GetKey(item.Id, mutationOf(variant))] then
			have += 1
		end
	end
	local total = #IndexConfig.Variants
	local complete = have == total
	local height = rowHeight(orbSize)

	-- A holder per row so the gold glow can sit behind the card inside the
	-- list layout.
	local holder = Instance.new("Frame")
	holder.Name = item.Id
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, height + GLOW_SPREAD * 2)
	holder.LayoutOrder = order
	holder.ZIndex = z
	holder.Parent = page

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundColor3 = Colors.Panel2
	card.Position = UDim2.fromOffset(GLOW_SPREAD, GLOW_SPREAD)
	card.Size = UDim2.new(1, -GLOW_SPREAD * 2, 0, height)
	card.ZIndex = z + 1
	card.Parent = holder
	UIKit.Corner(card, UITheme.Radius.Row)
	if complete then
		UIKit.Stroke(card, 3, Colors.GoldLabel)
		local glow = Instance.new("Frame")
		glow.Name = "CompleteGlow"
		glow.BackgroundColor3 = Colors.GoldLabel
		glow.BackgroundTransparency = 0.8
		glow.BorderSizePixel = 0
		glow.Size = UDim2.fromScale(1, 1)
		glow.ZIndex = z
		glow.Parent = holder
		UIKit.Corner(glow, UITheme.Radius.Row + GLOW_SPREAD)
	else
		UIKit.Stroke(card, 2)
	end

	UIKit.Label({
		Name = "Name",
		Text = item.Name,
		Font = Fonts.Display,
		TextSize = 17,
		TextColor3 = UITheme.GetTierLight(item.Tier),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, 12, 0.5, -20),
		Size = UDim2.new(NAME_COLUMN, -14, 0, 22),
		ZIndex = z + 2,
		Stroke = UITheme.Stroke.Text,
		Parent = card,
	})
	local rate = NumberFormat.Money(TycoonConfig.GetItemCashPerSecond(item.Tier, nil)) .. "/s"
	UIKit.Label({
		Name = "Progress",
		Text = if complete then ("★ COMPLETE %d/%d · %s"):format(have, total, rate) else ("%d / %d · %s"):format(have, total, rate),
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		TextColor3 = if complete then Colors.GoldLabel else Colors.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.new(0, 12, 0.5, 3),
		Size = UDim2.new(NAME_COLUMN, -14, 0, 16),
		ZIndex = z + 2,
		Parent = card,
	})

	local columnWidth = (1 - NAME_COLUMN) / total
	for index, variant in IndexConfig.Variants do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. variant
		slot.BackgroundTransparency = 1
		slot.Position = UDim2.fromScale(NAME_COLUMN + (index - 1) * columnWidth, 0)
		slot.Size = UDim2.fromScale(columnWidth, 1)
		slot.ZIndex = z + 2
		slot.Parent = card
		buildCell(slot, item, variant, found[IndexConfig.GetKey(item.Id, mutationOf(variant))] == true, orbSize, z + 3)
	end
end

local function rebuildPage(found: { [string]: boolean })
	for _, child in page:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(rainbowGradients)
	local orbSize = if UIKit.IsPhone() then PHONE_ORB_SIZE else ORB_SIZE
	local z = page.ZIndex + 1
	for order, item in ItemConfig.GetItemsByTier(selectedTier) do
		buildRow(item, order, found, orbSize, z)
	end
	page.CanvasPosition = Vector2.zero
	stopRainbow()
	if modal.IsOpen() then
		startRainbow()
	end
end

--[[ Refresh ------------------------------------------------------------------ ]]

local function refresh(force: boolean?)
	if not modal then
		return
	end
	local found = TycoonController.GetIndex()
	local count = IndexConfig.CountFound(found)
	bonusPill.Text = ("%s income"):format(percent(IndexConfig.GetMultiplier(found) - 1))
	modal.Subtitle.Text = ("%d / %d found · every find %s income · a full page %s"):format(
		count,
		IndexConfig.GetTotalEntries(),
		percent(IndexConfig.BonusPerEntry),
		percent(IndexConfig.BonusPerCompletedTier)
	)
	for tier, tab in tabs do
		local have, total = IndexConfig.GetTierProgress(found, tier)
		local selected = tier == selectedTier
		tab.Count.Text = ("%d / %d"):format(have, total)
		tab.Goal.Text = if have >= total
			then "★ " .. percent(IndexConfig.BonusPerCompletedTier)
			else ("%s at %d"):format(percent(IndexConfig.BonusPerCompletedTier), total)
		tab.Goal.Visible = selected
		UIKit.SetProgress(tab.Bar, if total > 0 then have / total else 0)
		-- The active pill is the UPGRADES green (the name keeps its tier
		-- colour); the rest stay the muted panel colour.
		UIKit.SetSelectedFill(tab.Button, selected, Colors.Panel2)
		tab.Button.BackgroundTransparency = if selected then 0 else 0.45
		tab.Stroke.Color = if selected then Colors.Text else Colors.Ink
		tab.Stroke.Thickness = if selected then 3 else 2
	end
	-- The page only rebuilds when what it shows changed.
	local key = ("%s|%d|%s"):format(selectedTier, count, tostring(UIKit.IsPhone()))
	if force or key ~= builtKey then
		builtKey = key
		rebuildPage(found)
	end
end

--[[ Build -------------------------------------------------------------------- ]]

local function buildTab(parent: Instance, tier: string, order: number, z: number)
	local color = UITheme.GetTierLight(tier)
	local button = Instance.new("TextButton")
	button.Name = tier .. "Tab"
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = Colors.Panel2
	button.Size = UDim2.fromOffset(TAB_SIZE.X, TAB_SIZE.Y)
	button.LayoutOrder = order
	button.ZIndex = z
	button.Parent = parent
	UIKit.Corner(button, UITheme.Radius.Row)
	local stroke = UIKit.Stroke(button, 2)
	UIKit.AttachPress(button)
	local name = UIKit.Label({
		Name = "TierName",
		Text = tier,
		Font = Fonts.Display,
		TextSize = 16,
		TextColor3 = color,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.new(1, -20, 0, 20),
		ZIndex = z + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = button,
	})
	local count = UIKit.Label({
		Name = "Count",
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		TextColor3 = Colors.Text,
		Position = UDim2.fromOffset(10, 27),
		Size = UDim2.new(0.5, -10, 0, 16),
		ZIndex = z + 1,
		Stroke = 1.5,
		Parent = button,
	})
	local goal = UIKit.Label({
		Name = "Goal",
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = Colors.Text,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 27),
		Size = UDim2.new(0.5, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = z + 1,
		Stroke = 1.5,
		Parent = button,
	})
	local bar = UIKit.ProgressBar({
		Name = "Progress",
		Parent = button,
		Position = UDim2.new(0, 10, 1, -14),
		Size = UDim2.new(1, -20, 0, 8),
		FillColor = color,
		ZIndex = z + 1,
	})
	button.Activated:Connect(function()
		UIKit.SelectFeedback(button)
		if selectedTier ~= tier then
			selectedTier = tier
			refresh()
		end
	end)
	tabs[tier] = { Button = button, Name = name, Count = count, Goal = goal, Bar = bar, Stroke = stroke }
end

local function build()
	modal = UIKit.Modal({
		Name = "IndexPanel",
		Title = "INDEX",
		DisplayOrder = 142,
		MaxSize = MAX_SIZE,
		HeaderTop = Colors.PanelTop,
		OnClose = stopRainbow,
	})
	UIKit.AddHelpButton(modal, function()
		TutorialCards.ShowTopic("Index")
	end)
	modal.Title.TextSize = 30
	modal.Subtitle.Visible = true
	modal.Subtitle.Size = UDim2.new(1, -(UITheme.MinTapSize * 2 + 208), 0, 16)
	modal.Subtitle.TextTruncate = Enum.TextTruncate.AtEnd
	bonusPill = UIKit.Pill({
		Name = "Bonus",
		Parent = modal.Header,
		Text = "",
		Gradient = UITheme.Gradients.Green,
		Font = Fonts.Display,
		TextSize = 15,
		Height = 28,
		AnchorPoint = Vector2.new(1, 0),
		-- Left of the "?" and the ✕.
		Position = UDim2.new(1, -(UITheme.MinTapSize * 2 + 20), 0, 6),
		ZIndex = modal.Header.ZIndex,
		TextStroke = 1.5,
	})

	local content = modal.Content
	local z = content.ZIndex

	-- Tier tabs.
	local tabsFrame = Instance.new("ScrollingFrame")
	tabsFrame.Name = "Tabs"
	tabsFrame.BackgroundTransparency = 1
	tabsFrame.BorderSizePixel = 0
	tabsFrame.Size = UDim2.new(1, 0, 0, TAB_SIZE.Y + 14)
	tabsFrame.ScrollingDirection = Enum.ScrollingDirection.X
	tabsFrame.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabsFrame.CanvasSize = UDim2.new()
	tabsFrame.ScrollBarThickness = 4
	tabsFrame.ScrollBarImageColor3 = Colors.Faint
	tabsFrame.ZIndex = z
	tabsFrame.Parent = content
	UIKit.Padding(tabsFrame, 3, 4, 8, 3)
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, TAB_GAP)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabsFrame
	for order, tier in FusionConfig.TierOrder do
		buildTab(tabsFrame, tier, order, z + 1)
	end

	-- Column headings, inset like the row cards so they line up with the
	-- orb columns.
	local headerY = TAB_SIZE.Y + 18
	local headings = Instance.new("Frame")
	headings.Name = "Headings"
	headings.BackgroundTransparency = 1
	headings.Position = UDim2.fromOffset(GLOW_SPREAD, headerY)
	headings.Size = UDim2.new(1, -(GLOW_SPREAD * 2 + SCROLLBAR), 0, HEADING_HEIGHT)
	headings.ZIndex = z
	headings.Parent = content
	local columnWidth = (1 - NAME_COLUMN) / #IndexConfig.Variants
	for index, variant in IndexConfig.Variants do
		local icon = EVENT_ICON[variant]
		UIKit.Label({
			Name = variant .. "Heading",
			Text = (if icon then icon .. " " else "") .. variant:upper(),
			Font = Fonts.BodyHeavy,
			TextSize = 11,
			TextColor3 = variantColor(variant),
			TextScaled = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromScale(NAME_COLUMN + (index - 1) * columnWidth, 0),
			Size = UDim2.fromScale(columnWidth, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z,
			Parent = headings,
		})
	end

	-- The rows.
	local pageY = headerY + HEADING_HEIGHT + 2
	page = Instance.new("ScrollingFrame")
	page.Name = "Page"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Position = UDim2.fromOffset(0, pageY)
	page.Size = UDim2.new(1, 0, 1, -(pageY + INFO_HEIGHT + 8))
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new()
	page.ScrollBarThickness = SCROLLBAR
	page.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	page.ScrollBarImageColor3 = Colors.Faint
	page.ZIndex = z
	page.Parent = content
	local pageLayout = Instance.new("UIListLayout")
	pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pageLayout.Parent = page

	-- The info strip.
	local strip = Instance.new("Frame")
	strip.Name = "InfoStrip"
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.Position = UDim2.fromScale(0, 1)
	strip.Size = UDim2.new(1, 0, 0, INFO_HEIGHT)
	strip.BackgroundColor3 = Colors.Panel2
	strip.ZIndex = z
	strip.Parent = content
	UIKit.Corner(strip, UITheme.Radius.Row)
	UIKit.Stroke(strip, 2)
	infoTitle = UIKit.Label({
		Name = "Title",
		Text = "Tap any orb",
		Font = Fonts.Display,
		TextSize = 17,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(12, 7),
		Size = UDim2.new(1, -150, 0, 22),
		ZIndex = z + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = strip,
	})
	infoStatus = UIKit.Label({
		Name = "Status",
		Text = "",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = Colors.Faint,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 9),
		Size = UDim2.fromOffset(130, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = z + 1,
		Parent = strip,
	})
	infoLine = UIKit.Label({
		Name = "Line",
		Text = "to see how to get it.",
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(12, 31),
		Size = UDim2.new(1, -24, 0, 32),
		ZIndex = z + 1,
		Parent = strip,
	})

	UIKit.LayoutChanged:Connect(function()
		if modal.IsOpen() then
			refresh()
		end
	end)
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

function IndexPanel.IsOpen(): boolean
	return modal ~= nil and modal.IsOpen()
end

function IndexPanel.Toggle()
	if modal.IsOpen() then
		modal.Close()
	else
		refresh()
		modal.Open()
		startRainbow()
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
