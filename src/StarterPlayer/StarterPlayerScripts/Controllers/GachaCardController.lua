--!strict
--[[
	GachaCardController
	-------------------
	The Gacha Pad's odds card (Pet Simulator 99 / Bubble Gum Simulator
	style): a card above YOUR OWN pad, built here on the client so it can read
	your Index (silhouettes for orbs you have never found), plus ONE row of
	round buttons under it that replace the pad's three default prompts.

	  * The card (BillboardGui in PlayerGui, Adornee = your pad,
	    AlwaysOnTop false, LightInfluence 0, DistanceLowerLimit; marked
	    OwnerOnly) fades in within FADE_IN_STUDS and out by FADE_OUT_STUDS.
	    Header "GACHA PAD" + an (i) button, a 🍀 Luck pill when luck > x1, the
	    live event chip when it changes the pull odds; a 3 x 2 grid, one tile
	    per tier (orb, big % in the tier colour, the name; a tier you never
	    found is a dark silhouette with "?" and STILL shows its %; Secret has
	    a shimmering stroke); a strip of mutation chips (event-only ones
	    during their event); the price pill ("$936 / pull", "FREE · 2 left").
	  * Odds: FusionConfig.GetGachaOddsRows(luck, event), the rows the roll
	    uses, at TycoonController.GetLuck() (the server's luck from the
	    sync) and EventState.GetOddsEvent(). Refreshed on every sync and
	    every 0.5 s (an event starting, a potion ending).
	  * The (i) panel (UIKit.Modal): every orb of every tier with its own %
	    (the tier % / the number of orbs in the tier: PickRandomOfTier is
	    uniform), found or not, and a line that luck and events are included.
	  * Buttons: the pad's PullPrompt / Pull10Prompt / HelpPrompt are
	    Style = Custom; ProximityPromptService.PromptShown / PromptHidden
	    tell us which are up. [E] Pull + price, [R] x10 + price, [?] help (H).
	    The key on desktop, the gamepad glyph on a controller, plain words on
	    touch; each is a >= 44 px target that runs prompt:InputHoldBegin /
	    InputHoldEnd and presses in (UIKit.SelectFeedback). Other players'
	    pads draw nothing (the prompts are custom and ignored there).
	  * The server's plain GachaLabel (title + price) is hidden while the card
	    is up and shows again far away.

	Compliance (Paid Random Items): the tiles with every odds are on the card
	whenever the buttons are (they are one gui); luck and the event are the
	live disclosure of modifiers; a silhouette hides the LOOK, never the odds.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TycoonController = require(script.Parent.TycoonController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local GachaCardController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local FADE_IN_STUDS = 18 -- fully visible inside this
local FADE_OUT_STUDS = 22 -- gone beyond this
local CARD_WIDTH = 360
local PAD = 12
local TILE = Vector2.new(108, 92)
local TILE_GAP = 6
local CHIP_HEIGHT = 22
local HEADER_HEIGHT = 32
local PILL_ROW_HEIGHT = 26
local PRICE_HEIGHT = 36
local BUTTON_SIZE = 58
local BUTTON_ROW_HEIGHT = 92
local PANEL_DISPLAY_ORDER = 143
local MUTATION_ICONS: { [string]: string } = {
	Golden = "✨",
	Charged = "⚡",
	Diamond = "💎",
	Void = "🌑",
	Rainbow = "🌈",
	Celestial = "🌟",
}
local KEY_WORDS: { [string]: string } = {
	ButtonY = "Y",
	ButtonX = "X",
	ButtonA = "A",
	ButtonB = "B",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
}

local localPlayer = Players.LocalPlayer

type ButtonView = {
	Holder: Frame,
	Button: TextButton,
	Circle: TextLabel,
	Glyph: ImageLabel,
	Caption: TextLabel,
	Badge: TextLabel,
	Prompt: ProximityPrompt?,
}

local pad: BasePart? = nil
local gui: BillboardGui? = nil
local group: CanvasGroup? = nil
local scaleObject: UIScale? = nil
local cardBody: Frame? = nil
local tileGrid: Frame? = nil
local pillRow: Frame? = nil
local chipStrip: Frame? = nil
local pricePill: TextLabel? = nil
local priceHolder: Frame? = nil
local buttonsRow: Frame? = nil
local buttons: { [string]: ButtonView } = {}
local tileViews: { [string]: Frame } = {}
local shownPrompts: { [string]: Enum.ProximityPromptInputType } = {}
local promptsByName: { [string]: ProximityPrompt } = {}
local signature = ""
local forceNear = false
local shimmerStroke: UIGradient? = nil
local panel: UIKit.Modal? = nil
local panelList: ScrollingFrame? = nil

--[[ Data ---------------------------------------------------------------------------- ]]

-- Tiers with at least one orb in your Index.
local function foundTiers(): { [string]: boolean }
	local found: { [string]: boolean } = {}
	for key in TycoonController.GetIndex() do
		local itemId = key:match("^(.-)|")
		local def = if itemId then ItemConfig.GetItemById(itemId) else nil
		if def then
			found[def.Tier] = true
		end
	end
	return found
end

local function foundItems(): { [string]: boolean }
	local found: { [string]: boolean } = {}
	for key in TycoonController.GetIndex() do
		local itemId = key:match("^(.-)|")
		if itemId then
			found[itemId] = true
		end
	end
	return found
end

local function currentRows(): FusionConfig.GachaOddsRows
	return FusionConfig.GetGachaOddsRows(TycoonController.GetLuck(), EventState.GetOddsEvent())
end

-- The live event when it changes the pull odds (luck, or any pull mutation
-- chance), else nil.
local function oddsEvent(rows: FusionConfig.GachaOddsRows): string?
	local id = EventState.GetActive()
	if not id then
		return nil
	end
	if EventState.GetLuckMultiplier() ~= 1 then
		return id
	end
	for _, multiplier in EventState.GetMutationMultipliers("Pull") do
		if multiplier ~= 1 then
			return id
		end
	end
	local normal = FusionConfig.GetGachaOddsRows(TycoonController.GetLuck(), nil)
	return if #rows.Mutations ~= #normal.Mutations then id else nil
end

local function priceText(): string
	local free = TycoonController.GetTutorial().FreePulls
	if free > 0 then
		return ("FREE · %d left"):format(free)
	end
	return ("%s / pull"):format(NumberFormat.Money(TycoonConfig.GetGachaPullCost(TycoonController.GetGachaPulls())))
end

local function luckText(luck: number): string
	return ("🍀 Luck ×%s"):format(NumberFormat.Multiplier(luck):sub(2))
end

--[[ Building the card ------------------------------------------------------------- ]]

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local text = UIKit.Label(props)
	text.Parent = parent
	return text
end

-- One tier tile: orb (or a silhouette), the big %, the tier name.
local function buildTile(parent: Instance, row: FusionConfig.GachaTierOdds, found: boolean): Frame
	local tier = row.Tier
	local color = FusionConfig.TierAccentColors[tier] or Colors.Text
	local tile = Instance.new("Frame")
	tile.Name = "Tile_" .. tier
	tile.BackgroundColor3 = Colors.Panel2
	tile.BorderSizePixel = 0
	tile.Size = UDim2.fromOffset(TILE.X, TILE.Y)
	tile:SetAttribute("Tier", tier)
	tile:SetAttribute("PercentValue", row.Rate * 100)
	tile:SetAttribute("Silhouette", not found)
	UIKit.Corner(tile, UITheme.Radius.Button)
	local stroke = UIKit.Stroke(tile, 3, if tier == "Secret" then Colors.White else Colors.Ink)
	if tier == "Secret" then
		-- A slow shimmer round the Secret tile (rotated in stepFrame).
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, UITheme.GetTierLight("Secret")),
			ColorSequenceKeypoint.new(0.5, Colors.White),
			ColorSequenceKeypoint.new(1, UITheme.GetTierLight("Secret")),
		})
		gradient.Parent = stroke
		shimmerStroke = gradient
	end

	local orbSize = 42
	if found then
		local orb = UIKit.TierOrb(tier, orbSize)
		orb.AnchorPoint = Vector2.new(0.5, 0)
		orb.Position = UDim2.new(0.5, 0, 0, 6)
		orb.Parent = tile
	else
		-- A dark silhouette with a "?": the look is hidden, the % never is.
		local silhouette = Instance.new("Frame")
		silhouette.Name = "Silhouette"
		silhouette.AnchorPoint = Vector2.new(0.5, 0)
		silhouette.Position = UDim2.new(0.5, 0, 0, 6)
		silhouette.Size = UDim2.fromOffset(orbSize, orbSize)
		silhouette.BackgroundColor3 = Colors.Ink
		silhouette.BorderSizePixel = 0
		silhouette.Parent = tile
		UIKit.Corner(silhouette, 999)
		UIKit.Stroke(silhouette, 3, Colors.Faint)
		label(silhouette, {
			Name = "Mark",
			Text = "?",
			Font = Fonts.Display,
			TextSize = 26,
			TextColor3 = Colors.Muted,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end

	local percent = label(tile, {
		Name = "Percent",
		Text = row.Text,
		Font = Fonts.Display,
		TextSize = 24,
		TextColor3 = color,
		Stroke = UITheme.Stroke.Text,
		Position = UDim2.fromOffset(2, 50),
		Size = UDim2.new(1, -4, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	UIKit.FitText(percent, 24, 12)
	local name = label(tile, {
		Name = "TierName",
		Text = tier:upper(),
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(2, 76),
		Size = UDim2.new(1, -4, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	UIKit.FitText(name, 12, 8)
	return tile
end

local function buildChip(parent: Instance, mutation: string, text: string): Frame
	local color = UITheme.GetMutationColor(mutation) or Colors.Text
	local chip = Instance.new("Frame")
	chip.Name = "Chip_" .. mutation
	chip.BackgroundColor3 = Colors.Ink
	chip.BorderSizePixel = 0
	chip.Size = UDim2.fromOffset(TILE.X, CHIP_HEIGHT)
	UIKit.Corner(chip, 999)
	UIKit.Stroke(chip, 2, color)
	local words = label(chip, {
		Name = "Text",
		Text = ("%s %s %s"):format(MUTATION_ICONS[mutation] or "", mutation, text),
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = Colors.Text,
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	UIKit.FitText(words, 12, 8)
	return chip
end

local function buildPill(parent: Instance, text: string, gradient: UITheme.GradientPair, name: string): TextLabel
	local pill = UIKit.Pill({
		Name = name,
		Parent = parent,
		Text = text,
		Gradient = gradient,
		TextSize = 13,
		Height = 22,
	})
	return pill
end

-- (Re)builds everything that depends on the odds, luck, event, Index and
-- price: the pills, the tiles, the chips and the price.
local function rebuild()
	local body, tiles, pills, chips, price, root = cardBody, tileGrid, pillRow, chipStrip, pricePill, gui
	if not (body and tiles and pills and chips and price and root) then
		return
	end
	local rows = currentRows()
	local foundTier = foundTiers()
	local luck = TycoonController.GetLuck()

	for _, child in tiles:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	table.clear(tileViews)
	shimmerStroke = nil
	for index, row in rows.Tiers do
		local tile = buildTile(tiles, row, foundTier[row.Tier] == true)
		tile.LayoutOrder = index
		tile.Parent = tiles
		tileViews[row.Tier] = tile
	end

	for _, child in pills:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if luck > 1.0001 then
		buildPill(pills, luckText(luck), UITheme.Gradients.Green, "LuckPill")
	end
	local eventId = oddsEvent(rows)
	if eventId then
		buildPill(pills, ("%s %s"):format(EventConfig.Icons[eventId] or "", EventConfig.Names[eventId] or eventId), UITheme.GetEventGradient(eventId), "EventChip")
	end

	for _, child in chips:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, row in rows.Mutations do
		local chip = buildChip(chips, row.Mutation, row.Text)
		chip.LayoutOrder = index
		chip.Parent = chips
	end

	price.Text = priceText()

	-- The card's height follows the number of chip rows.
	local chipRows = math.max(1, math.ceil(#rows.Mutations / 3))
	local chipsHeight = chipRows * CHIP_HEIGHT + (chipRows - 1) * 4
	chips.Size = UDim2.new(1, 0, 0, chipsHeight)
	local gridHeight = 2 * TILE.Y + TILE_GAP
	local y = PAD + HEADER_HEIGHT + 4
	pills.Position = UDim2.fromOffset(PAD, y)
	y += PILL_ROW_HEIGHT + 2
	tiles.Position = UDim2.fromOffset(PAD, y)
	y += gridHeight + 8
	chips.Position = UDim2.fromOffset(PAD, y)
	y += chipsHeight + 8
	if priceHolder then
		priceHolder.Position = UDim2.new(0.5, 0, 0, y)
	end
	y += PRICE_HEIGHT + PAD
	local holder = body.Parent :: Frame
	holder.Size = UDim2.fromOffset(CARD_WIDTH, y)
	local row = buttonsRow
	if row then
		row.Position = UDim2.fromOffset(0, y + 8)
	end
	root.Size = UDim2.fromOffset(CARD_WIDTH, y + 8 + BUTTON_ROW_HEIGHT)
end

--[[ The (i) panel --------------------------------------------------------------------- ]]

-- One tier's orbs with their own %: the tier % / the number of orbs in the
-- tier (PickRandomOfTier rolls uniformly).
function GachaCardController.GetPanelData(): { [string]: { Rate: number, Orbs: { { Id: string, Name: string, Percent: number, Found: boolean } } } }
	local rows = currentRows()
	local foundItem = foundItems()
	local data = {}
	for _, row in rows.Tiers do
		local items = ItemConfig.GetItemsByTier(row.Tier)
		local orbs = {}
		for _, item in items do
			table.insert(orbs, { Id = item.Id, Name = item.Name, Percent = row.Rate * 100 / math.max(#items, 1), Found = foundItem[item.Id] == true })
		end
		data[row.Tier] = { Rate = row.Rate * 100, Orbs = orbs }
	end
	return data
end

local function fillPanel()
	local list = panelList
	if not list then
		return
	end
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	local data = GachaCardController.GetPanelData()
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	label(list, {
		Name = "Note",
		Text = ("Luck %s and the current event are already included in these odds."):format(NumberFormat.Multiplier(TycoonController.GetLuck())),
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = nextOrder(),
	})
	for _, tier in FusionConfig.TierOrder do
		local tierData = data[tier]
		if tierData then
			local head = Instance.new("Frame")
			head.Name = "Tier_" .. tier
			head.BackgroundTransparency = 1
			head.Size = UDim2.new(1, 0, 0, 34)
			head.LayoutOrder = nextOrder()
			head.Parent = list
			local orb = UIKit.TierOrb(tier, 28)
			orb.Position = UDim2.fromOffset(0, 3)
			orb.Parent = head
			label(head, {
				Name = "Name",
				Text = tier:upper(),
				Font = Fonts.Display,
				TextSize = 22,
				TextColor3 = FusionConfig.TierAccentColors[tier] or Colors.Text,
				Stroke = UITheme.Stroke.Text,
				Position = UDim2.fromOffset(38, 0),
				Size = UDim2.new(0.5, -38, 1, 0),
			})
			local total = label(head, {
				Name = "Percent",
				Text = FusionConfig.FormatPercent(tierData.Rate) .. "%",
				Font = Fonts.Display,
				TextSize = 22,
				TextColor3 = FusionConfig.TierAccentColors[tier] or Colors.Text,
				Stroke = UITheme.Stroke.Text,
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromScale(0.5, 1),
				TextXAlignment = Enum.TextXAlignment.Right,
			})
			total:SetAttribute("PercentValue", tierData.Rate)
			for _, orbData in tierData.Orbs do
				local line = Instance.new("Frame")
				line.Name = "Orb_" .. orbData.Id
				line.BackgroundColor3 = Colors.Panel2
				line.BorderSizePixel = 0
				line.Size = UDim2.new(1, 0, 0, 34)
				line.LayoutOrder = nextOrder()
				line.Parent = list
				line:SetAttribute("PercentValue", orbData.Percent)
				line:SetAttribute("Tier", tier)
				UIKit.Corner(line, UITheme.Radius.Button)
				if orbData.Found then
					local small = UIKit.TierOrb(tier, 24)
					small.Position = UDim2.fromOffset(8, 5)
					small.Parent = line
				else
					local dark = Instance.new("Frame")
					dark.Name = "Silhouette"
					dark.Position = UDim2.fromOffset(8, 5)
					dark.Size = UDim2.fromOffset(24, 24)
					dark.BackgroundColor3 = Colors.Ink
					dark.BorderSizePixel = 0
					dark.Parent = line
					UIKit.Corner(dark, 999)
					UIKit.Stroke(dark, 2, Colors.Faint)
				end
				label(line, {
					Name = "OrbName",
					Text = if orbData.Found then orbData.Name else "???",
					Font = Fonts.BodyHeavy,
					TextSize = 16,
					Position = UDim2.fromOffset(42, 0),
					Size = UDim2.new(0.5, -42, 1, 0),
				})
				label(line, {
					Name = "FoundMark",
					Text = if orbData.Found then "✓ found" else "not found yet",
					Font = Fonts.Body,
					TextSize = 12,
					TextColor3 = if orbData.Found then Colors.Cash else Colors.Faint,
					Position = UDim2.fromScale(0.5, 0),
					Size = UDim2.new(0.22, 0, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Center,
				})
				label(line, {
					Name = "OrbPercent",
					Text = FusionConfig.FormatPercent(orbData.Percent) .. "%",
					Font = Fonts.BodyHeavy,
					TextSize = 16,
					TextColor3 = FusionConfig.TierAccentColors[tier] or Colors.Text,
					Position = UDim2.fromScale(0.72, 0),
					Size = UDim2.new(0.28, -8, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Right,
				})
			end
		end
	end
	local layout = list:FindFirstChildOfClass("UIListLayout")
	if layout then
		list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
	end
end

local function buildPanel()
	local modal = UIKit.Modal({
		Name = "GachaOdds",
		Title = "ORBS & ODDS",
		DisplayOrder = PANEL_DISPLAY_ORDER,
		MaxSize = Vector2.new(480, 560),
		HeaderTop = UITheme.Colors.PanelTop,
	})
	local list = Instance.new("ScrollingFrame")
	list.Name = "Odds"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Colors.Faint
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = modal.Content.ZIndex
	list.Parent = modal.Content
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list
	UIKit.Padding(list, 2, 8, 8, 2)
	panel = modal
	panelList = list
end

function GachaCardController.OpenPanel()
	if not panel then
		return
	end
	fillPanel()
	panel.Open()
end

function GachaCardController.ClosePanel()
	if panel then
		panel.Close()
	end
end

--[[ The button row ------------------------------------------------------------------- ]]

local BUTTON_SPECS = {
	{ Name = "PullPrompt", Key = "E", Style = "Green", Touch = "PULL" },
	{ Name = "Pull10Prompt", Key = "R", Style = "Blue", Touch = "×10" },
	{ Name = "HelpPrompt", Key = "H", Style = "Violet", Touch = "?" },
}

local function captionFor(name: string): string
	local pulls = TycoonController.GetGachaPulls()
	if name == "PullPrompt" then
		local free = TycoonController.GetTutorial().FreePulls
		return if free > 0 then "Pull · FREE" else ("Pull · %s"):format(NumberFormat.Money(TycoonConfig.GetGachaPullCost(pulls)))
	elseif name == "Pull10Prompt" then
		return ("×%d · %s"):format(TycoonConfig.MultiPullCount, NumberFormat.Money(TycoonConfig.GetGachaMultiPullCost(pulls, TycoonConfig.MultiPullCount)))
	end
	return "How it works"
end

-- What a button shows for the input in use: the key (desktop), the gamepad
-- glyph (controller) or plain words (touch).
local function showInput(view: ButtonView, spec: { [string]: any }, inputType: Enum.ProximityPromptInputType?)
	local prompt = view.Prompt
	view.Glyph.Visible = false
	view.Badge.Visible = false
	view.Circle.Visible = true
	if inputType == Enum.ProximityPromptInputType.Gamepad and prompt then
		local ok, image = pcall(function()
			return UserInputService:GetImageForKeyCode(prompt.GamepadKeyCode)
		end)
		if ok and image ~= "" then
			view.Glyph.Image = image
			view.Glyph.Visible = true
			view.Circle.Visible = false
		else
			view.Circle.Text = KEY_WORDS[prompt.GamepadKeyCode.Name] or prompt.GamepadKeyCode.Name
		end
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		view.Circle.Text = spec.Touch
	else
		local key = if prompt then prompt.KeyboardKeyCode.Name else spec.Key
		view.Circle.Text = if spec.Name == "HelpPrompt" then "?" else key
		if spec.Name == "HelpPrompt" then
			view.Badge.Text = key
			view.Badge.Visible = true
		end
	end
end

local function refreshButtons()
	for _, spec in BUTTON_SPECS do
		local view = buttons[spec.Name]
		if view then
			local inputType = shownPrompts[spec.Name]
			local visible = forceNear or inputType ~= nil
			view.Holder.Visible = visible
			view.Caption.Text = captionFor(spec.Name)
			if visible then
				showInput(view, spec, inputType)
			end
		end
	end
	-- Lay the visible ones out centred.
	local count = 0
	for _, spec in BUTTON_SPECS do
		local view = buttons[spec.Name]
		if view and view.Holder.Visible then
			count += 1
		end
	end
	local slot = 0
	local spacing = 104
	for _, spec in BUTTON_SPECS do
		local view = buttons[spec.Name]
		if view and view.Holder.Visible then
			view.Holder.Position = UDim2.new(0.5, (slot - (count - 1) / 2) * spacing, 0, 0)
			slot += 1
		end
	end
end

local function pressPrompt(name: string)
	if name == "HelpPrompt" and not promptsByName[name] then
		return
	end
	local prompt = promptsByName[name]
	if not prompt or not prompt.Parent then
		return
	end
	task.spawn(function()
		prompt:InputHoldBegin()
		RunService.Heartbeat:Wait()
		prompt:InputHoldEnd()
	end)
end

local function buildButtons(root: GuiObject)
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(CARD_WIDTH, BUTTON_ROW_HEIGHT)
	row.Parent = root
	buttonsRow = row
	for _, spec in BUTTON_SPECS do
		local holder = Instance.new("Frame")
		holder.Name = spec.Name .. "Button"
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromOffset(100, BUTTON_ROW_HEIGHT)
		holder.Parent = row
		local body, buttonHolder = UIKit.Button({
			Name = "Round",
			Parent = holder,
			Style = spec.Style,
			Text = "",
			Radius = 999,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
			OnClick = function()
				UIKit.SelectFeedback(holder)
				pressPrompt(spec.Name)
			end,
		})
		local circle = label(body, {
			Name = "Key",
			Text = spec.Key,
			Font = Fonts.Display,
			TextSize = 30,
			TextColor3 = Colors.Text,
			Stroke = UITheme.Stroke.Text,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = body.ZIndex + 2,
		})
		UIKit.FitText(circle, 30, 14)
		local glyph = Instance.new("ImageLabel")
		glyph.Name = "Glyph"
		glyph.BackgroundTransparency = 1
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromOffset(34, 34)
		glyph.Visible = false
		glyph.ZIndex = body.ZIndex + 2
		glyph.Parent = body
		local badge = label(buttonHolder, {
			Name = "KeyBadge",
			Text = "H",
			Font = Fonts.BodyHeavy,
			TextSize = 13,
			Stroke = UITheme.Stroke.Text,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 2, 0, -2),
			Size = UDim2.fromOffset(20, 18),
			TextXAlignment = Enum.TextXAlignment.Center,
			Visible = false,
			ZIndex = body.ZIndex + 3,
		})
		local caption = label(holder, {
			Name = "Caption",
			Text = captionFor(spec.Name),
			Font = Fonts.BodyHeavy,
			TextSize = 14,
			Stroke = UITheme.Stroke.Text,
			Position = UDim2.fromOffset(0, BUTTON_SIZE + 6),
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		UIKit.FitText(caption, 14, 9)
		buttons[spec.Name] = {
			Holder = holder,
			Button = body,
			Circle = circle,
			Glyph = glyph,
			Caption = caption,
			Badge = badge,
			Prompt = nil,
		}
		holder.Visible = false
	end
end

--[[ The card ----------------------------------------------------------------------------- ]]

local function build(adornee: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GachaCard"
	billboard.Adornee = adornee
	billboard.Size = UDim2.fromOffset(CARD_WIDTH, 460)
	billboard.SizeOffset = Vector2.new(0, 0.5)
	billboard.StudsOffset = Vector3.new(0, PlotLayout.Station.LabelOffsetY - 1, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = FADE_OUT_STUDS + 4
	;(billboard :: any).DistanceLowerLimit = 6
	billboard.ResetOnSpawn = false
	billboard.Active = true
	billboard:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)
	billboard:SetAttribute("OwnerUserId", localPlayer.UserId)

	local scale = Instance.new("UIScale")
	scale.Scale = if UIKit.IsPhone() then UITheme.PhoneScale else 1
	scale.Parent = billboard
	scaleObject = scale

	local fader = Instance.new("CanvasGroup")
	fader.Name = "Fade"
	fader.BackgroundTransparency = 1
	fader.Size = UDim2.fromScale(1, 1)
	fader.Parent = billboard
	group = fader

	local body, holder = UIKit.Panel({
		Name = "Card",
		Parent = fader,
		Size = UDim2.fromOffset(CARD_WIDTH, 380),
		Gradient = { { 0 :: any, Colors.PanelTop }, { 0.3 :: any, Colors.Panel }, { 1 :: any, Colors.Panel } },
		StrokeThickness = UITheme.Stroke.Modal,
	})
	cardBody = body

	label(body, {
		Name = "Title",
		Text = "GACHA PAD",
		Font = Fonts.Display,
		TextSize = 24,
		TextColor3 = Colors.GoldLabel,
		Stroke = UITheme.Stroke.Text,
		Position = UDim2.fromOffset(PAD, PAD),
		Size = UDim2.new(1, -(PAD * 2 + 40), 0, HEADER_HEIGHT),
	})
	local _, infoHolder = UIKit.Button({
		Name = "Info",
		Parent = body,
		Style = "Violet",
		Text = "i",
		TextSize = 20,
		Radius = 999,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, PAD),
		Size = UDim2.fromOffset(34, 34),
		OnClick = function()
			GachaCardController.OpenPanel()
		end,
	})
	infoHolder.ZIndex = body.ZIndex + 2

	local pills = Instance.new("Frame")
	pills.Name = "Pills"
	pills.BackgroundTransparency = 1
	pills.Size = UDim2.fromOffset(CARD_WIDTH - PAD * 2, PILL_ROW_HEIGHT)
	pills.Parent = body
	local pillLayout = Instance.new("UIListLayout")
	pillLayout.FillDirection = Enum.FillDirection.Horizontal
	pillLayout.Padding = UDim.new(0, 6)
	pillLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pillLayout.Parent = pills
	pillRow = pills

	local tiles = Instance.new("Frame")
	tiles.Name = "Tiles"
	tiles.BackgroundTransparency = 1
	tiles.Size = UDim2.fromOffset(CARD_WIDTH - PAD * 2, 2 * TILE.Y + TILE_GAP)
	tiles.Parent = body
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(TILE.X, TILE.Y)
	grid.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = tiles
	tileGrid = tiles

	local chips = Instance.new("Frame")
	chips.Name = "Mutations"
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.fromOffset(CARD_WIDTH - PAD * 2, CHIP_HEIGHT)
	chips.Parent = body
	local chipGrid = Instance.new("UIGridLayout")
	chipGrid.CellSize = UDim2.fromOffset(TILE.X, CHIP_HEIGHT)
	chipGrid.CellPadding = UDim2.fromOffset(TILE_GAP, 4)
	chipGrid.SortOrder = Enum.SortOrder.LayoutOrder
	chipGrid.Parent = chips
	chipStrip = chips

	local priceFill = Instance.new("Frame")
	priceFill.Name = "PriceHolder"
	priceFill.AnchorPoint = Vector2.new(0.5, 0)
	priceFill.BackgroundTransparency = 1
	priceFill.Size = UDim2.fromOffset(220, PRICE_HEIGHT)
	priceFill.Parent = body
	local price = UIKit.Pill({
		Name = "Price",
		Parent = priceFill,
		Text = priceText(),
		Gradient = UITheme.Gradients.Gold,
		Font = Fonts.Display,
		TextSize = 22,
		Height = PRICE_HEIGHT,
		StrokeThickness = 3,
		TextStroke = 2,
	})
	UIKit.PillRoot(price).AnchorPoint = Vector2.new(0.5, 0)
	UIKit.PillRoot(price).Position = UDim2.fromScale(0.5, 0)
	pricePill = price
	priceHolder = priceFill

	buildButtons(fader)
	holder.Position = UDim2.new()
	gui = billboard
	billboard.Parent = localPlayer:WaitForChild("PlayerGui")
	rebuild()
	refreshButtons()
end

--[[ Per frame ------------------------------------------------------------------------- ]]

local function distanceToPad(): number
	local target = pad
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not target or not root or not root:IsA("BasePart") then
		return math.huge
	end
	return (root.Position - target.Position).Magnitude
end

local function stepFrame()
	local billboard, fader = gui, group
	if not billboard or not fader or not pad or not pad.Parent then
		return
	end
	local distance = if forceNear then 0 else distanceToPad()
	local alpha = 1 - math.clamp((distance - FADE_IN_STUDS) / (FADE_OUT_STUDS - FADE_IN_STUDS), 0, 1)
	fader.GroupTransparency = 1 - alpha
	billboard.Enabled = alpha > 0.01
	-- The plain server label (title + price) shows only when the card doesn't.
	local label = pad:FindFirstChild("GachaLabel")
	if label and label:IsA("BillboardGui") then
		label.Enabled = alpha <= 0.01
	end
	local shimmer = shimmerStroke
	if shimmer and alpha > 0.01 then
		shimmer.Rotation = (os.clock() * 60) % 360
	end
end

-- The sync-driven refresh, plus a 0.5 s poll for what replicates by itself
-- (an event starting or ending, a luck potion running out).
local function currentSignature(): string
	local rows = currentRows()
	local parts = { priceText(), tostring(TycoonController.GetGachaPulls()), ("%.5f"):format(TycoonController.GetLuck()), tostring(oddsEvent(rows)) }
	for _, row in rows.Tiers do
		table.insert(parts, row.Text)
	end
	for _, row in rows.Mutations do
		table.insert(parts, row.Mutation .. row.Text)
	end
	local tiers = foundTiers()
	for _, tier in FusionConfig.TierOrder do
		table.insert(parts, if tiers[tier] then "1" else "0")
	end
	return table.concat(parts, "|")
end

local function refresh()
	if not gui then
		return
	end
	local now = currentSignature()
	if now ~= signature then
		signature = now
		rebuild()
		refreshButtons()
		if panel and panel.IsOpen() then
			fillPanel()
		end
	end
end

--[[ Finding the pad ----------------------------------------------------------------------- ]]

local function findOwnPad(): BasePart?
	local plots = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == localPlayer.UserId then
			local station = plot:FindFirstChild("GachaStation")
			local found = station and station:FindFirstChild("Pad")
			if found and found:IsA("BasePart") then
				return found
			end
		end
	end
	return nil
end

local function onPromptShown(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom or not pad or not prompt:IsDescendantOf(pad) then
		return
	end
	shownPrompts[prompt.Name] = inputType
	promptsByName[prompt.Name] = prompt
	local view = buttons[prompt.Name]
	if view then
		view.Prompt = prompt
	end
	refreshButtons()
end

local function onPromptHidden(prompt: ProximityPrompt)
	if shownPrompts[prompt.Name] ~= nil and pad and prompt:IsDescendantOf(pad) then
		shownPrompts[prompt.Name] = nil
		refreshButtons()
	end
end

--[[ /selftest ------------------------------------------------------------------------------ ]]

-- Re-reads the odds, luck, event and Index now (the poll does it every 0.5 s).
function GachaCardController.RefreshNow()
	refresh()
end

function GachaCardController.GetCard(): BillboardGui?
	return gui
end

-- Treat the pad as near (card + button row up) so /selftest can read them.
function GachaCardController.SetForceNear(on: boolean)
	forceNear = on
	for name, prompt in promptsByName do
		local view = buttons[name]
		if view then
			view.Prompt = prompt
		end
	end
	if gui then
		refresh()
		refreshButtons()
		stepFrame()
	end
end

-- Rendered: tier -> { Text = the % label, Value = its number, Silhouette }.
function GachaCardController.GetTiles(): { [string]: { Text: string, Value: number, Silhouette: boolean } }
	local result = {}
	for tier, tile in tileViews do
		local percent = tile:FindFirstChild("Percent")
		result[tier] = {
			Text = if percent and percent:IsA("TextLabel") then percent.Text else "",
			Value = (tile:GetAttribute("PercentValue") :: number?) or 0,
			Silhouette = tile:GetAttribute("Silhouette") == true,
		}
	end
	return result
end

-- The rendered (i) panel lines: tier -> { Total (number), Orbs = { numbers } }.
function GachaCardController.GetPanelLines(): { [string]: { Total: number, Orbs: { number } } }
	local result: { [string]: { Total: number, Orbs: { number } } } = {}
	local list = panelList
	if not list then
		return result
	end
	for _, tier in FusionConfig.TierOrder do
		local head = list:FindFirstChild("Tier_" .. tier)
		local total = head and head:FindFirstChild("Percent")
		result[tier] = { Total = if total then (total:GetAttribute("PercentValue") :: number? or 0) else 0, Orbs = {} }
	end
	for _, line in list:GetChildren() do
		local tier = line:GetAttribute("Tier")
		local value = line:GetAttribute("PercentValue")
		if line.Name:sub(1, 4) == "Orb_" and typeof(tier) == "string" and typeof(value) == "number" and result[tier] then
			table.insert(result[tier].Orbs, value)
		end
	end
	return result
end

function GachaCardController.GetButtons(): { { Name: string, Visible: boolean, Size: Vector2 } }
	local result = {}
	for _, spec in BUTTON_SPECS do
		local view = buttons[spec.Name]
		if view then
			local size = view.Button.AbsoluteSize
			table.insert(result, { Name = spec.Name, Visible = view.Holder.Visible, Size = size })
		end
	end
	return result
end

function GachaCardController.GetPanel(): UIKit.Modal?
	return panel
end

--[[ Lifecycle ------------------------------------------------------------------------------ ]]

function GachaCardController.Init()
	buildPanel()
	ProximityPromptService.PromptShown:Connect(onPromptShown)
	ProximityPromptService.PromptHidden:Connect(onPromptHidden)
	UIKit.LayoutChanged:Connect(function(isPhone: boolean)
		if scaleObject then
			scaleObject.Scale = if isPhone then UITheme.PhoneScale else 1
		end
	end)
	TycoonController.TycoonChanged:Connect(function()
		refresh()
	end)
	task.spawn(function()
		-- Waits for this player's own plot (built when they join).
		while not pad or not pad.Parent do
			local found = findOwnPad()
			if found then
				pad = found
				build(found)
				signature = currentSignature()
			else
				task.wait(0.5)
			end
		end
		RunService.Heartbeat:Connect(stepFrame)
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
end

return GachaCardController
