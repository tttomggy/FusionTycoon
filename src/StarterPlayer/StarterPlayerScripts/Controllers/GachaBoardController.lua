--!strict
--[[
	GachaBoardController
	--------------------
	The Gacha odds as a real BOARD in the world (Pet Simulator 99 / Bubble
	Gum Simulator egg-card style), not a billboard: PlotLayout.Gacha, built
	by TycoonService.buildGachaBoard on the far side of every lab's Gacha
	Pad, tilted back and yawed a little toward the gate. This controller
	draws its face, for EVERY plot's board, and one row of round buttons for
	YOUR pad.

	  * The face (a SurfaceGui in PlayerGui, Adornee = the board's Face,
	    60 px/stud, MaxDistance 100, LightInfluence 0, no CanvasGroup, no
	    fade: it is always there). Deep violet glass with diagonal stripes in
	    a thick gold rim; a gold header ribbon (capsule icon, "GACHA PAD",
	    your (i) button); the 🍀 Luck pill when luck > x1 and the live event
	    chip; six tier tiles (the tier's gradient, a spinning 3D orb in a
	    ViewportFrame built by PedestalVisuals, the % huge in white with a
	    tier-coloured stroke, a name ribbon); mutation chips (event-only ones
	    during their event); a big gold price pill.
	  * Your board: a tier you never found is a black silhouette orb with a
	    "?" and STILL shows its %. Other players' boards: no silhouettes, at
	    THAT owner's luck and price (attributes the server stamps on the
	    board).
	  * Odds: FusionConfig.GetGachaOddsRows(luck, EventState.GetOddsEvent()),
	    the rows the roll uses; yours at TycoonController.GetLuck(). Refreshed
	    on every sync and every 0.5 s.
	  * The (i) panel (UIKit.Modal): every orb with its own %, found or not.
	  * Buttons: the pad's three prompts are Style = Custom; PromptShown /
	    PromptHidden say which are up. A BillboardGui with a PIXEL size, on
	    the board's ButtonAnchor (just under its bottom edge): [E] Pull +
	    price, [R] x10 + price, [?] help. The key on desktop, the gamepad
	    glyph on a controller, words on touch; each >= 44 px; they run
	    prompt:InputHoldBegin / End. No CanvasGroup; AlwaysOnTop false.
	  * Orbs spin only while their board is within SPIN_STUDS of the camera.

	Compliance (Paid Random Items): every outcome's % is on the board before
	you pull; luck and the event are the live disclosure; a silhouette hides
	the LOOK, never the odds.
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
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TycoonController = require(script.Parent.TycoonController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local GachaBoardController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local CANVAS = Vector2.new(PlotLayout.Gacha.BoardSize.X, PlotLayout.Gacha.BoardSize.Y) * PlotLayout.Gacha.PixelsPerStud -- 600 x 450
local MARGIN = 14
local SPIN_STUDS = 60 -- orbs spin only while the board is this close to the camera
local TILE_SIZE = Vector2.new(184, 118)
local TILE_GAP = 8
local CHIP_HEIGHT = 26
local BUTTON_SIZE = 58
local BUTTON_ROW_HEIGHT = 92
local BUTTON_ROW_WIDTH = 340
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

type Spinner = { Viewport: ViewportFrame, Model: Model, Phase: number }

type BoardView = {
	Model: Model,
	Face: BasePart,
	Gui: SurfaceGui,
	Own: boolean,
	Tiles: { [string]: Frame },
	Spinners: { Spinner },
	Shimmer: UIGradient?,
	Sparkle: TextLabel?,
	Signature: string,
}

local boards: { [Model]: BoardView } = {}
local ownBoard: BoardView? = nil
local ownStation: Instance? = nil
local rowGui: BillboardGui? = nil
local rowScale: UIScale? = nil
local buttons: { [string]: ButtonView } = {}
local shownPrompts: { [string]: Enum.ProximityPromptInputType } = {}
local promptsByName: { [string]: ProximityPrompt } = {}
local forceNear = false
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

local function currentRows(luck: number): FusionConfig.GachaOddsRows
	return FusionConfig.GetGachaOddsRows(luck, EventState.GetOddsEvent())
end

-- The live event when it changes the pull odds (luck, or any pull mutation
-- chance), else nil.
local function oddsEvent(rows: FusionConfig.GachaOddsRows, luck: number): string?
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
	local normal = FusionConfig.GetGachaOddsRows(luck, nil)
	return if #rows.Mutations ~= #normal.Mutations then id else nil
end

-- Luck / price of the board's OWNER: yours from the client's own state, a
-- neighbour's from the attributes the server stamps on their board.
type Inputs = { Luck: number, Free: number, Cost: number, MultiCost: number }

local function inputsFor(view: BoardView): Inputs
	if view.Own then
		local pulls = TycoonController.GetGachaPulls()
		return {
			Luck = TycoonController.GetLuck(),
			Free = TycoonController.GetTutorial().FreePulls,
			Cost = TycoonConfig.GetGachaPullCost(pulls),
			MultiCost = TycoonConfig.GetGachaMultiPullCost(pulls, TycoonConfig.MultiPullCount),
		}
	end
	local model = view.Model
	local function number(name: string, default: number): number
		local value = model:GetAttribute(name)
		return if typeof(value) == "number" then value else default
	end
	return {
		Luck = number("Luck", 1),
		Free = number("FreePulls", 0),
		Cost = number("PullCost", TycoonConfig.GetGachaPullCost(0)),
		MultiCost = number("MultiCost", TycoonConfig.GetGachaMultiPullCost(0, TycoonConfig.MultiPullCount)),
	}
end

local function priceText(inputs: Inputs): string
	if inputs.Free > 0 then
		return ("FREE · %d left"):format(inputs.Free)
	end
	return ("%s / pull  ·  ×%d %s"):format(NumberFormat.Money(inputs.Cost), TycoonConfig.MultiPullCount, NumberFormat.Money(inputs.MultiCost))
end

local function luckText(luck: number): string
	return ("🍀 Luck ×%s"):format(NumberFormat.Multiplier(luck):sub(2))
end

--[[ Building a board face ------------------------------------------------------------ ]]

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local text = UIKit.Label(props)
	text.Parent = parent
	return text
end

local function scaledText(parent: Instance, props: { [string]: any }, maxSize: number, minSize: number): TextLabel
	props.TextScaled = true
	local text = label(parent, props)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxSize
	constraint.MinTextSize = minSize
	constraint.Parent = text
	return text
end

local function frame(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Position = position
	f.Size = size
	if color then
		f.BackgroundColor3 = color
	else
		f.BackgroundTransparency = 1
	end
	f.Parent = parent
	return f
end

-- The tier's orb in a ViewportFrame, built by the pedestals' own builder.
local function buildOrbViewport(view: BoardView, parent: Instance, tier: string, silhouette: boolean)
	local scene = UITheme.HeistScene
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Orb"
	viewport.BackgroundTransparency = 1
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.Position = UDim2.new(0.5, 0, 0, 2)
	viewport.Size = UDim2.fromOffset(52, 52)
	viewport.Ambient = scene.Ambient
	viewport.LightColor = scene.LightColor
	viewport.LightDirection = scene.LightDirection
	local orb = PedestalVisuals.BuildCarryOrb(tier, nil, CFrame.new(), viewport, nil)
	local _, size = orb:GetBoundingBox()
	local fov = 30
	local camera = Instance.new("Camera")
	camera.FieldOfView = fov
	camera.CFrame = CFrame.new(Vector3.new(0, 0, size.Magnitude / 2 / math.sin(math.rad(fov / 2)) * 1.05), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	if silhouette then
		-- A black silhouette: the look is hidden (the % never is).
		viewport.ImageColor3 = Colors.Black
	end
	viewport.Parent = parent
	table.insert(view.Spinners, { Viewport = viewport, Model = orb, Phase = math.random() * math.pi * 2 })
end

local function buildTile(view: BoardView, parent: Instance, row: FusionConfig.GachaTierOdds, silhouette: boolean): Frame
	local tier = row.Tier
	local accent = FusionConfig.TierAccentColors[tier] or Colors.Text
	local stops = UITheme.GetTierOrb(tier)
	local tile = Instance.new("Frame")
	tile.Name = "Tile_" .. tier
	tile.BackgroundColor3 = Colors.White
	tile.BorderSizePixel = 0
	tile.Size = UDim2.fromOffset(TILE_SIZE.X, TILE_SIZE.Y)
	tile:SetAttribute("Tier", tier)
	tile:SetAttribute("PercentValue", row.Rate * 100)
	tile:SetAttribute("Silhouette", silhouette)
	UIKit.Corner(tile, 18)
	-- From the tier colour down to dark.
	UIKit.PairGradient(tile, { Top = stops.Mid, Bottom = stops.Dark })
	local stroke = UIKit.Stroke(tile, 3, Colors.White)
	if tier == "Secret" then
		-- An animated rainbow stroke (rotated every frame) and a sparkle.
		local gradient = Instance.new("UIGradient")
		gradient.Color = UITheme.GetRainbowSequence()
		gradient.Parent = stroke
		view.Shimmer = gradient
		view.Sparkle = label(tile, {
			Name = "Sparkle",
			Text = "✦",
			Font = Fonts.Display,
			TextSize = 22,
			TextColor3 = Colors.White,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 2),
			Size = UDim2.fromOffset(26, 26),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 5,
		})
	end

	buildOrbViewport(view, tile, tier, silhouette)
	if silhouette then
		label(tile, {
			Name = "Mark",
			Text = "?",
			Font = Fonts.Display,
			TextSize = 32,
			TextColor3 = Colors.Muted,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(52, 44),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		})
	end

	-- The % is huge: 42 px at 60 px/stud = 0.7 studs, white with a thick
	-- stroke in the tier colour.
	local percent = scaledText(tile, {
		Name = "Percent",
		Text = row.Text,
		Font = Fonts.Display,
		TextColor3 = Colors.White,
		Position = UDim2.fromOffset(4, 54),
		Size = UDim2.new(1, -8, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, 42, 14)
	local percentStroke = UIKit.TextStroke(percent, 4)
	percentStroke.Color = accent

	-- The tier-name ribbon along the bottom.
	local ribbon = frame(tile, "Ribbon", UDim2.new(0, 0, 1, -22), UDim2.new(1, 0, 0, 22), Colors.Ink)
	ribbon.BackgroundTransparency = 0.3
	UIKit.Corner(ribbon, 10)
	scaledText(ribbon, {
		Name = "TierName",
		Text = tier:upper(),
		Font = Fonts.BodyHeavy,
		TextColor3 = Colors.White,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, 16, 8)
	return tile
end

local function buildChip(parent: Instance, mutation: string, text: string, width: number): Frame
	local color = UITheme.GetMutationColor(mutation) or Colors.Text
	local chip = Instance.new("Frame")
	chip.Name = "Chip_" .. mutation
	chip.BackgroundColor3 = Colors.Ink
	chip.BorderSizePixel = 0
	chip.Size = UDim2.fromOffset(width, CHIP_HEIGHT)
	UIKit.Corner(chip, 999)
	UIKit.Stroke(chip, 2, color)
	scaledText(chip, {
		Name = "Text",
		Text = ("%s %s %s"):format(MUTATION_ICONS[mutation] or "", mutation, text),
		Font = Fonts.BodyHeavy,
		TextColor3 = Colors.White,
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -12, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, 15, 8)
	return chip
end

-- (Re)builds the face from scratch: the odds, luck, event, Index and price.
local function populate(view: BoardView)
	local gui = view.Gui
	for _, child in gui:GetChildren() do
		child:Destroy()
	end
	table.clear(view.Tiles)
	table.clear(view.Spinners)
	view.Shimmer = nil
	view.Sparkle = nil

	local inputs = inputsFor(view)
	local rows = currentRows(inputs.Luck)
	local found = if view.Own then foundTiers() else nil

	-- Deep violet glass in a thick gold rim, with diagonal stripes.
	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Colors.White
	root.BorderSizePixel = 0
	root.Parent = gui
	UIKit.Corner(root, 30)
	UIKit.Gradient(root, { { 0 :: any, Colors.PanelTop }, { 0.45 :: any, Colors.Panel2 }, { 1 :: any, Colors.Panel } }, 90)
	local rim = UIKit.Stroke(root, 12, UITheme.Gradients.Gold.Top)
	local rimGradient = Instance.new("UIGradient")
	rimGradient.Color = ColorSequence.new(UITheme.Gradients.Gold.Top, UITheme.Gradients.Gold.Bottom)
	rimGradient.Rotation = 90
	rimGradient.Parent = rim
	local glow = frame(root, "Glow", UDim2.fromOffset(8, 8), UDim2.new(1, -16, 1, -16))
	UIKit.Corner(glow, 24)
	local glowStroke = UIKit.Stroke(glow, 6, UITheme.Gradients.Gold.Top)
	glowStroke.Transparency = 0.7
	local stripes = frame(root, "Stripes", UDim2.new(), UDim2.fromScale(1, 1), Colors.White)
	UIKit.Corner(stripes, 30)
	local stripePoints: { NumberSequenceKeypoint } = { NumberSequenceKeypoint.new(0, 1) }
	for index = 0, 3 do
		local a = 0.04 + index * 0.24
		table.insert(stripePoints, NumberSequenceKeypoint.new(a, 1))
		table.insert(stripePoints, NumberSequenceKeypoint.new(a + 0.001, 0.93))
		table.insert(stripePoints, NumberSequenceKeypoint.new(a + 0.12, 0.93))
		table.insert(stripePoints, NumberSequenceKeypoint.new(a + 0.121, 1))
	end
	table.insert(stripePoints, NumberSequenceKeypoint.new(1, 1))
	local stripeGradient = Instance.new("UIGradient")
	stripeGradient.Transparency = NumberSequence.new(stripePoints)
	stripeGradient.Rotation = 45
	stripeGradient.Parent = stripes

	-- Header ribbon: capsule icon, GACHA PAD, (i).
	local ribbon = frame(root, "Header", UDim2.fromOffset(MARGIN, 12), UDim2.fromOffset(CANVAS.X - MARGIN * 2, 54), Colors.White)
	UIKit.Corner(ribbon, 16)
	UIKit.PairGradient(ribbon, UITheme.Gradients.Gold)
	UIKit.Stroke(ribbon, 4, Colors.Ink)
	local capsule = frame(ribbon, "Capsule", UDim2.fromOffset(10, 5), UDim2.fromOffset(44, 44), Colors.White)
	UIKit.Corner(capsule, 999)
	UIKit.Stroke(capsule, 3, Colors.Ink)
	local capsuleGradient = Instance.new("UIGradient")
	capsuleGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UITheme.Gradients.Violet.Top),
		ColorSequenceKeypoint.new(0.5, UITheme.Gradients.Violet.Bottom),
		ColorSequenceKeypoint.new(0.501, UITheme.World.CapsuleWhite),
		ColorSequenceKeypoint.new(1, UITheme.World.CapsuleWhite),
	})
	capsuleGradient.Rotation = 90
	capsuleGradient.Parent = capsule
	local title = scaledText(ribbon, {
		Name = "Title",
		Text = "GACHA PAD",
		Font = Fonts.Display,
		TextColor3 = Colors.White,
		Position = UDim2.fromOffset(64, 4),
		Size = UDim2.new(1, -64 - 64, 1, -8),
	}, 44, 18)
	UIKit.TextStroke(title, 4)
	if view.Own then
		local _, infoHolder = UIKit.Button({
			Name = "Info",
			Parent = ribbon,
			Style = "Violet",
			Text = "i",
			TextSize = 26,
			Radius = 999,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(44, 44),
			OnClick = function()
				GachaBoardController.OpenPanel()
			end,
		})
		infoHolder.ZIndex = ribbon.ZIndex + 3
	end

	-- Luck pill and the live event chip, under the ribbon.
	local pills = frame(root, "Pills", UDim2.fromOffset(MARGIN, 70), UDim2.fromOffset(CANVAS.X - MARGIN * 2, 26))
	local pillLayout = Instance.new("UIListLayout")
	pillLayout.FillDirection = Enum.FillDirection.Horizontal
	pillLayout.Padding = UDim.new(0, 8)
	pillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pillLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pillLayout.Parent = pills
	if inputs.Luck > 1.0001 then
		UIKit.Pill({ Name = "LuckPill", Parent = pills, Text = luckText(inputs.Luck), Gradient = UITheme.Gradients.Green, TextSize = 16, Height = 26, LayoutOrder = 1 })
	end
	local eventId = oddsEvent(rows, inputs.Luck)
	if eventId then
		UIKit.Pill({
			Name = "EventChip",
			Parent = pills,
			Text = ("%s %s"):format(EventConfig.Icons[eventId] or "", EventConfig.Names[eventId] or eventId),
			Gradient = UITheme.GetEventGradient(eventId),
			TextSize = 16,
			Height = 26,
			LayoutOrder = 2,
		})
	end

	-- Six tiles, 3 x 2.
	local tiles = frame(root, "Tiles", UDim2.fromOffset(MARGIN, 100), UDim2.fromOffset(CANVAS.X - MARGIN * 2, TILE_SIZE.Y * 2 + TILE_GAP))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(TILE_SIZE.X, TILE_SIZE.Y)
	grid.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = tiles
	for index, row in rows.Tiers do
		local tile = buildTile(view, tiles, row, found ~= nil and found[row.Tier] ~= true)
		tile.LayoutOrder = index
		view.Tiles[row.Tier] = tile
	end

	-- Mutation chips.
	local chips = frame(root, "Mutations", UDim2.fromOffset(MARGIN, 100 + TILE_SIZE.Y * 2 + TILE_GAP + 8), UDim2.fromOffset(CANVAS.X - MARGIN * 2, CHIP_HEIGHT))
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 4)
	chipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chips
	local count = math.max(#rows.Mutations, 1)
	local chipWidth = math.min(150, (CANVAS.X - MARGIN * 2 - 4 * (count - 1)) / count)
	for index, row in rows.Mutations do
		buildChip(chips, row.Mutation, row.Text, chipWidth).LayoutOrder = index
	end

	-- The big gold price pill.
	local price = UIKit.Pill({
		Name = "Price",
		Parent = root,
		Text = priceText(inputs),
		Gradient = UITheme.Gradients.Gold,
		Font = Fonts.Display,
		TextSize = 28,
		Height = 46,
		StrokeThickness = 4,
		TextStroke = 3,
	})
	local priceRoot = UIKit.PillRoot(price)
	priceRoot.AnchorPoint = Vector2.new(0.5, 0)
	priceRoot.Position = UDim2.new(0.5, 0, 0, CANVAS.Y - 46 - 18)

	local signature = { priceText(inputs), ("%.5f"):format(inputs.Luck), tostring(eventId) }
	for _, row in rows.Tiers do
		table.insert(signature, row.Text)
	end
	for _, row in rows.Mutations do
		table.insert(signature, row.Mutation .. row.Text)
	end
	if found then
		for _, tier in FusionConfig.TierOrder do
			table.insert(signature, if found[tier] then "1" else "0")
		end
	end
	view.Signature = table.concat(signature, "|")
end

local function signatureOf(view: BoardView): string
	local inputs = inputsFor(view)
	local rows = currentRows(inputs.Luck)
	local signature = { priceText(inputs), ("%.5f"):format(inputs.Luck), tostring(oddsEvent(rows, inputs.Luck)) }
	for _, row in rows.Tiers do
		table.insert(signature, row.Text)
	end
	for _, row in rows.Mutations do
		table.insert(signature, row.Mutation .. row.Text)
	end
	if view.Own then
		local found = foundTiers()
		for _, tier in FusionConfig.TierOrder do
			table.insert(signature, if found[tier] then "1" else "0")
		end
	end
	return table.concat(signature, "|")
end

--[[ The (i) panel --------------------------------------------------------------------- ]]

-- One tier's orbs with their own %: the tier % / the number of orbs in the
-- tier (PickRandomOfTier rolls uniformly).
function GachaBoardController.GetPanelData(): { [string]: { Rate: number, Orbs: { { Id: string, Name: string, Percent: number, Found: boolean } } } }
	local rows = currentRows(TycoonController.GetLuck())
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
	local data = GachaBoardController.GetPanelData()
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

function GachaBoardController.OpenPanel()
	if not panel then
		return
	end
	fillPanel()
	panel.Open()
end

function GachaBoardController.ClosePanel()
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

local function buildButtons(root: Instance)
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(BUTTON_ROW_WIDTH, BUTTON_ROW_HEIGHT)
	row.Parent = root
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


--[[ The button row (a pixel-size BillboardGui under the board) -------------------------- ]]

local function buildButtonRow(anchor: BasePart)
	local G = PlotLayout.Gacha
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GachaButtons"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(BUTTON_ROW_WIDTH, BUTTON_ROW_HEIGHT)
	-- Hangs BELOW the anchor (the board's bottom edge).
	billboard.SizeOffset = Vector2.new(0, -0.5)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = G.ButtonMaxDistance
	billboard.ResetOnSpawn = false
	billboard.Active = true
	local scale = Instance.new("UIScale")
	scale.Scale = if UIKit.IsPhone() then UITheme.PhoneScale else 1
	scale.Parent = billboard
	rowScale = scale
	table.clear(buttons)
	buildButtons(billboard)
	rowGui = billboard
	billboard.Parent = localPlayer:WaitForChild("PlayerGui")
	refreshButtons()
end

--[[ Boards ----------------------------------------------------------------------------- ]]

local function ownerOf(instance: Instance): number?
	local current: Instance? = instance
	while current do
		local owner = current:GetAttribute("OwnerUserId")
		if typeof(owner) == "number" then
			return owner
		end
		current = current.Parent
	end
	return nil
end

local function addBoard(model: Model)
	if boards[model] then
		return
	end
	local face = model:WaitForChild("Face", 10)
	if not face or not face:IsA("BasePart") or boards[model] then
		return
	end
	local G = PlotLayout.Gacha
	local own = ownerOf(model) == localPlayer.UserId
	local surface = Instance.new("SurfaceGui")
	surface.Name = "GachaBoard_" .. tostring(ownerOf(model) or 0)
	surface.Adornee = face
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = G.PixelsPerStud
	surface.LightInfluence = 0
	surface.AlwaysOnTop = false
	surface.ClipsDescendants = true
	surface.Active = own
	surface.ResetOnSpawn = false
	;(surface :: any).MaxDistance = G.MaxDistance
	surface:SetAttribute("Own", own)
	local view: BoardView = {
		Model = model,
		Face = face,
		Gui = surface,
		Own = own,
		Tiles = {},
		Spinners = {},
		Shimmer = nil,
		Sparkle = nil,
		Signature = "",
	}
	boards[model] = view
	surface.Parent = localPlayer:WaitForChild("PlayerGui")
	populate(view)
	model.Destroying:Connect(function()
		boards[model] = nil
		if ownBoard == view then
			ownBoard = nil
		end
		surface:Destroy()
	end)
	if own then
		ownBoard = view
		ownStation = model.Parent and model.Parent:FindFirstChild("GachaStation")
		local anchor = model:FindFirstChild("ButtonAnchor")
		if anchor and anchor:IsA("BasePart") and not rowGui then
			buildButtonRow(anchor)
		end
	end
end

local function consider(instance: Instance)
	if instance.Name == "GachaBoard" and instance:IsA("Model") then
		task.spawn(addBoard, instance)
	end
end

--[[ Per frame ------------------------------------------------------------------------- ]]

local function stepFrame()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	for _, view in boards do
		if view.Face.Parent and (view.Face.Position - camera.CFrame.Position).Magnitude <= SPIN_STUDS then
			for _, spinner in view.Spinners do
				if spinner.Model.Parent then
					local angle = spinner.Phase + now * 1.1
					spinner.Model:PivotTo(CFrame.Angles(0.25, angle, 0) * CFrame.new(0, math.sin(now * 1.6 + spinner.Phase) * 0.06, 0))
				end
			end
			local shimmer, sparkle = view.Shimmer, view.Sparkle
			if shimmer then
				shimmer.Rotation = (now * 90) % 360
			end
			if sparkle then
				sparkle.Rotation = (now * 120) % 360
				sparkle.TextTransparency = 0.5 + 0.5 * math.sin(now * 5)
			end
		end
	end
end

local function refresh()
	for _, view in boards do
		if view.Gui.Parent then
			local now = signatureOf(view)
			if now ~= view.Signature then
				populate(view)
				if view.Own then
					refreshButtons()
					if panel and panel.IsOpen() then
						fillPanel()
					end
				end
			end
		end
	end
end

local function onPromptShown(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom or not ownStation or not prompt:IsDescendantOf(ownStation) then
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
	if shownPrompts[prompt.Name] ~= nil and ownStation and prompt:IsDescendantOf(ownStation) then
		shownPrompts[prompt.Name] = nil
		refreshButtons()
	end
end

--[[ /selftest ------------------------------------------------------------------------------ ]]

-- Re-reads the odds, luck, event and Index now (the poll does it every 0.5 s).
function GachaBoardController.RefreshNow()
	refresh()
end

-- Show the button row as if you stood on the pad (the prompts are not up).
function GachaBoardController.SetForceNear(on: boolean)
	forceNear = on
	for name, prompt in promptsByName do
		local view = buttons[name]
		if view then
			view.Prompt = prompt
		end
	end
	refreshButtons()
end

-- Your board's face and its button-row anchor (nil before it streams in).
function GachaBoardController.GetOwnBoard(): { Gui: SurfaceGui, Face: BasePart, Anchor: BasePart? }?
	local view = ownBoard
	if not view then
		return nil
	end
	local anchor = view.Model:FindFirstChild("ButtonAnchor")
	return { Gui = view.Gui, Face = view.Face, Anchor = if anchor and anchor:IsA("BasePart") then anchor else nil }
end

-- Every board face this client draws: { Gui, Own, Spinners }.
function GachaBoardController.GetBoards(): { { Gui: SurfaceGui, Own: boolean, Orbs: number, Tiles: number } }
	local result = {}
	for _, view in boards do
		local orbs = 0
		for _, spinner in view.Spinners do
			if spinner.Viewport:FindFirstChildWhichIsA("Model") then
				orbs += 1
			end
		end
		local tiles = 0
		for _ in view.Tiles do
			tiles += 1
		end
		table.insert(result, { Gui = view.Gui, Own = view.Own, Orbs = orbs, Tiles = tiles })
	end
	return result
end

-- Rendered, on your board: tier -> { Text = the % label, Value = its number, Silhouette }.
function GachaBoardController.GetTiles(): { [string]: { Text: string, Value: number, Silhouette: boolean } }
	local result = {}
	local view = ownBoard
	if not view then
		return result
	end
	for tier, tile in view.Tiles do
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
function GachaBoardController.GetPanelLines(): { [string]: { Total: number, Orbs: { number } } }
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

function GachaBoardController.GetButtons(): { { Name: string, Visible: boolean, Size: Vector2 } }
	local result = {}
	for _, spec in BUTTON_SPECS do
		local view = buttons[spec.Name]
		if view then
			table.insert(result, { Name = spec.Name, Visible = view.Holder.Visible, Size = view.Button.AbsoluteSize })
		end
	end
	return result
end

function GachaBoardController.GetButtonRow(): BillboardGui?
	return rowGui
end

function GachaBoardController.GetPanel(): UIKit.Modal?
	return panel
end

--[[ Lifecycle ------------------------------------------------------------------------------ ]]

function GachaBoardController.Init()
	buildPanel()
	ProximityPromptService.PromptShown:Connect(onPromptShown)
	ProximityPromptService.PromptHidden:Connect(onPromptHidden)
	UIKit.LayoutChanged:Connect(function(isPhone: boolean)
		if rowScale then
			rowScale.Scale = if isPhone then UITheme.PhoneScale else 1
		end
	end)
	TycoonController.TycoonChanged:Connect(function()
		refresh()
	end)
	task.spawn(function()
		local plots = Workspace:WaitForChild(PlotNaming.PlotsFolderName)
		for _, descendant in plots:GetDescendants() do
			consider(descendant)
		end
		plots.DescendantAdded:Connect(consider)
		RunService.Heartbeat:Connect(stepFrame)
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
end

return GachaBoardController
