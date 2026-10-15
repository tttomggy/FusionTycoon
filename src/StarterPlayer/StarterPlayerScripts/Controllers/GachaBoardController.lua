--!strict
--[[
	GachaBoardController
	--------------------
	The Gacha odds CARD: a BillboardGui that pops up above YOUR Gacha Pad when
	your CHARACTER walks close (Pet Simulator 99 / Bubble Gum Simulator egg
	card). No physical board.

	  1. Sized in STUDS (PlotLayout.Gacha.CardStuds = 7 x 4.8), so it scales
	     with zoom like a world object. The layout is built at a 600 x 410
	     design canvas and scaled by a UIScale (FitScale) from the billboard's
	     on-screen size. A second UIScale (ClampScale) keeps the card at most
	     PlotLayout.Gacha.MaxScreenShare (38%) of the viewport height, worked
	     out each frame from the camera distance: it never takes over the
	     screen however close the camera is.
	  2. Visibility follows the CHARACTER, never the camera: each frame the
	     distance from your HumanoidRootPart to the pad; inside PopInStuds (16)
	     it pops IN (Enabled, UIScale 0.6 -> 1 in 0.2 s, Back-Out); beyond
	     PopOutStuds (19) it pops OUT (1 -> 0.6 in 0.12 s, then Enabled off);
	     the gap stops flicker. MaxDistance 150, so zoom never hides it. It is
	     shifted 2 studs back from the walkway (StudsOffsetWorldSpace).
	  3. No CanvasGroup anywhere; the pop is a UIScale only.

	The face: deep violet glass in a gold rim with diagonal stripes; a gold
	header ribbon (capsule icon, "GACHA PAD", your (i) button); the Luck pill
	when luck > x1 and the live event chip; six tier tiles (tier gradient, a
	spinning 3D orb in a ViewportFrame built by PedestalVisuals, the % huge
	in white with a tier-coloured stroke, a name ribbon; Secret has a rainbow
	stroke and a sparkle); mutation chips; the gold price pill. A tier you
	never found is a black silhouette orb with "?" and STILL shows its %.
	Orbs spin only while the card is open.

	THE KEY BAR under the card (inside the same billboard, pops with it):
	[E] Pull . $285, [R] x10 . $3.5K, [T] Auto . OFF / ON. It does NOT use
	ProximityPrompt UI (the pad's prompts are off; PromptShown never fired for
	the old buttons). While the card is open E / R / T (X / Y / RB on a
	controller) are bound with ContextActionService, and unbound when it pops
	out; the keys and the round >= 44 px buttons send RequestGachaPull
	{ Count = 1 | 10 } and SetAutoPull { On }; the server runs the one shared
	pull function. Desktop shows the key caps, a controller its glyphs, touch
	words on the round buttons. T shows ON in green while Auto pull runs; the
	server's AutoPullState says when and why it stopped (a toast).

	Far away (beyond PopOutStuds) the small server "GachaLabel" (name + price)
	shows instead; this controller hides it while the card is up. Only your own
	pad has a card.

	Odds: FusionConfig.GetGachaOddsRows(luck, EventState.GetOddsEvent()), the
	rows the roll uses, at TycoonController.GetLuck(). Refreshed on every sync
	and every 0.5 s. The (i) panel (UIKit.Modal): HOW IT WORKS first, then
	every orb with its own %.

	Compliance (Paid Random Items): every outcome's % is on the card before
	you pull; luck and the event are the live disclosure; a silhouette hides
	the LOOK, never the odds.
]]
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local GachaConfig = require(ReplicatedStorage.Shared.Config.GachaConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TycoonController = require(script.Parent.TycoonController)
local ToastController = require(script.Parent.ToastController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local GachaBoardController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local G = PlotLayout.Gacha
local CANVAS = G.DesignCanvas -- 600 x 410: the layout is built here, then scaled to the studs
local MARGIN = 14
local SPIN_STUDS = 60 -- orbs spin only while the card is open (and this close to the camera)
local TILE_SIZE = Vector2.new(184, 100)
local TILE_GAP = 6
local HEADER_Y = 12
local HEADER_HEIGHT = 54
local PILLS_Y = 70
local TILES_Y = 100
local CHIP_HEIGHT = 24
local PRICE_HEIGHT = 44
local BUTTON_SIZE = 56
local BUTTON_ROW_HEIGHT = 88
local BUTTON_ROW_WIDTH = 340
local BUTTON_SPACING = 104
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
-- Why Auto pull stopped (AutoPullState.Reason), as a toast.
local AUTO_STOP_TEXT: { [string]: string } = {
	TooFar = "Auto pull stopped: you walked away",
	Carrying = "Auto pull stopped: hands full",
	NoCharacter = "Auto pull stopped",
	NoPad = "Auto pull stopped",
	Tutorial = "Finish the free tutorial pulls first",
	MissingRewardItem = "Auto pull stopped",
}
local TOO_FAR_TEXT = "Step closer to the Gacha Pad"

local localPlayer = Players.LocalPlayer

type KeySpec = {
	Id: string,
	Key: string, -- the key cap
	KeyCode: Enum.KeyCode,
	PadCode: Enum.KeyCode, -- the controller button
	Style: string,
	Touch: string, -- the word on a touch screen
	Action: string, -- the ContextActionService name
}

type ButtonView = {
	Holder: Frame,
	Button: TextButton,
	Circle: TextLabel,
	Glyph: ImageLabel,
	Caption: TextLabel,
}

type Spinner = { Viewport: ViewportFrame, Model: Model, Phase: number }

type CardView = {
	Billboard: BillboardGui,
	Pad: BasePart,
	Pop: UIScale, -- the pop-in / pop-out scale
	Clamp: UIScale, -- keeps the card under MaxScreenShare of the viewport height
	Fit: UIScale, -- design canvas -> on-screen size
	KeyBar: Frame, -- the E / R / T row under the card
	Canvas: Frame, -- the 600 x 410 design canvas (populate builds in here)
	Tiles: { [string]: Frame },
	Spinners: { Spinner },
	Shimmer: UIGradient?,
	Sparkle: TextLabel?,
	Signature: string,
	Label: Instance?, -- the small server GachaLabel
	Open: boolean, -- the character is close (the pop-in side of the hysteresis)
	Tween: Tween?,
}

local card: CardView? = nil
local buttons: { [string]: ButtonView } = {}
local keysBound = false
local autoOn = false -- Auto pull is running (the server's AutoPullState)
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

-- Your luck and prices, from the client's own state.
type Inputs = { Luck: number, Free: number, Cost: number, MultiCost: number }

local function currentInputs(): Inputs
	local pulls = TycoonController.GetGachaPulls()
	return {
		Luck = TycoonController.GetLuck(),
		Free = TycoonController.GetTutorial().FreePulls,
		Cost = TycoonConfig.GetGachaPullCost(pulls),
		MultiCost = TycoonConfig.GetGachaMultiPullCost(pulls, TycoonConfig.MultiPullCount),
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
local function buildOrbViewport(view: CardView, parent: Instance, tier: string, silhouette: boolean)
	local scene = UITheme.HeistScene
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Orb"
	viewport.BackgroundTransparency = 1
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.Position = UDim2.new(0.5, 0, 0, 2)
	viewport.Size = UDim2.fromOffset(44, 44)
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

local function buildTile(view: CardView, parent: Instance, row: FusionConfig.GachaTierOdds, silhouette: boolean): Frame
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
			TextSize = 28,
			TextColor3 = Colors.Muted,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(44, 38),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		})
	end

	-- The % is huge: 34 design px of a 600 x 410 canvas (7 x 4.8 studs) =
	-- 0.4 studs, white with a thick stroke in the tier colour.
	local percent = scaledText(tile, {
		Name = "Percent",
		Text = row.Text,
		Font = Fonts.Display,
		TextColor3 = Colors.White,
		Position = UDim2.fromOffset(4, 44),
		Size = UDim2.new(1, -8, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, 34, 12)
	local percentStroke = UIKit.TextStroke(percent, 4)
	percentStroke.Color = accent

	-- The tier-name ribbon along the bottom.
	local ribbon = frame(tile, "Ribbon", UDim2.new(0, 0, 1, -20), UDim2.new(1, 0, 0, 20), Colors.Ink)
	ribbon.BackgroundTransparency = 0.3
	UIKit.Corner(ribbon, 10)
	scaledText(ribbon, {
		Name = "TierName",
		Text = tier:upper(),
		Font = Fonts.BodyHeavy,
		TextColor3 = Colors.White,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, 14, 8)
	tile.Parent = parent
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
	chip.Parent = parent
	return chip
end

-- (Re)builds the face from scratch: the odds, luck, event, Index and price.
local function populate(view: CardView)
	local gui = view.Canvas
	for _, child in gui:GetChildren() do
		child:Destroy()
	end
	table.clear(view.Tiles)
	table.clear(view.Spinners)
	view.Shimmer = nil
	view.Sparkle = nil

	local inputs = currentInputs()
	local rows = currentRows(inputs.Luck)
	local found = foundTiers()

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
	local ribbon = frame(root, "Header", UDim2.fromOffset(MARGIN, HEADER_Y), UDim2.fromOffset(CANVAS.X - MARGIN * 2, HEADER_HEIGHT), Colors.White)
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
	do
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
	local pills = frame(root, "Pills", UDim2.fromOffset(MARGIN, PILLS_Y), UDim2.fromOffset(CANVAS.X - MARGIN * 2, 24))
	local pillLayout = Instance.new("UIListLayout")
	pillLayout.FillDirection = Enum.FillDirection.Horizontal
	pillLayout.Padding = UDim.new(0, 8)
	pillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pillLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pillLayout.Parent = pills
	if inputs.Luck > 1.0001 then
		UIKit.Pill({ Name = "LuckPill", Parent = pills, Text = luckText(inputs.Luck), Gradient = UITheme.Gradients.Green, TextSize = 15, Height = 24, LayoutOrder = 1 })
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
	local tiles = frame(root, "Tiles", UDim2.fromOffset(MARGIN, TILES_Y), UDim2.fromOffset(CANVAS.X - MARGIN * 2, TILE_SIZE.Y * 2 + TILE_GAP))
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
	local chips = frame(root, "Mutations", UDim2.fromOffset(MARGIN, TILES_Y + TILE_SIZE.Y * 2 + TILE_GAP + 6), UDim2.fromOffset(CANVAS.X - MARGIN * 2, CHIP_HEIGHT))
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
		TextSize = 26,
		Height = PRICE_HEIGHT,
		StrokeThickness = 4,
		TextStroke = 3,
	})
	local priceRoot = UIKit.PillRoot(price)
	priceRoot.AnchorPoint = Vector2.new(0.5, 0)
	priceRoot.Position = UDim2.new(0.5, 0, 0, CANVAS.Y - PRICE_HEIGHT - 16)

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

local function signatureOf(): string
	local inputs = currentInputs()
	local rows = currentRows(inputs.Luck)
	local signature = { priceText(inputs), ("%.5f"):format(inputs.Luck), tostring(oddsEvent(rows, inputs.Luck)) }
	for _, row in rows.Tiers do
		table.insert(signature, row.Text)
	end
	for _, row in rows.Mutations do
		table.insert(signature, row.Mutation .. row.Text)
	end
	do
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
	-- HOW IT WORKS first (it used to be the pad's H prompt).
	label(list, {
		Name = "HowHeader",
		Text = "HOW IT WORKS",
		Font = Fonts.Display,
		TextSize = 22,
		TextColor3 = Colors.GoldLabel,
		Stroke = UITheme.Stroke.Text,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = nextOrder(),
	})
	local helpCards = TutorialConfig.Help.Gacha
	for index, help in helpCards do
		local row = Instance.new("Frame")
		row.Name = "How_" .. index
		row.BackgroundColor3 = Colors.Panel2
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 58)
		row.LayoutOrder = nextOrder()
		row.Parent = list
		UIKit.Corner(row, UITheme.Radius.Button)
		label(row, {
			Name = "Icon",
			Text = help.Icon or "",
			Font = Fonts.Display,
			TextSize = 26,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.fromOffset(36, 58),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		label(row, {
			Name = "Title",
			Text = help.Title,
			Font = Fonts.BodyHeavy,
			TextSize = 16,
			Position = UDim2.fromOffset(50, 4),
			Size = UDim2.new(1, -58, 0, 18),
		})
		label(row, {
			Name = "Body",
			Text = help.Body,
			Font = Fonts.Body,
			TextSize = 13,
			TextColor3 = Colors.Muted,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(50, 22),
			Size = UDim2.new(1, -58, 0, 34),
		})
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

--[[ The key bar ---------------------------------------------------------------------- ]]

local KEYS: { KeySpec } = {
	{ Id = "Pull", Key = "E", KeyCode = Enum.KeyCode.E, PadCode = Enum.KeyCode.ButtonX, Style = "Gold", Touch = "PULL", Action = "GachaPull" },
	{ Id = "Multi", Key = "R", KeyCode = Enum.KeyCode.R, PadCode = Enum.KeyCode.ButtonY, Style = "Blue", Touch = "×10", Action = "GachaPull10" },
	{ Id = "Auto", Key = "T", KeyCode = Enum.KeyCode.T, PadCode = Enum.KeyCode.ButtonR1, Style = "Violet", Touch = "AUTO", Action = "GachaAuto" },
}

local function captionFor(id: string): string
	local pulls = TycoonController.GetGachaPulls()
	if id == "Pull" then
		local free = TycoonController.GetTutorial().FreePulls
		return if free > 0 then "Pull · FREE" else ("Pull · %s"):format(NumberFormat.Money(TycoonConfig.GetGachaPullCost(pulls)))
	elseif id == "Multi" then
		return ("×%d · %s"):format(TycoonConfig.MultiPullCount, NumberFormat.Money(TycoonConfig.GetGachaMultiPullCost(pulls, TycoonConfig.MultiPullCount)))
	end
	return if autoOn then "Auto · ON" else "Auto · OFF"
end

-- Which input the player is using: the key caps (desktop), the controller
-- glyphs, or words on round tap buttons (touch).
local function inputMode(): string
	local last = UserInputService:GetLastInputType()
	if last.Name:find("Gamepad", 1, true) then
		return "Gamepad"
	elseif last == Enum.UserInputType.Touch or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		return "Touch"
	end
	return "Keyboard"
end

local function showInput(view: ButtonView, spec: KeySpec)
	local mode = inputMode()
	view.Glyph.Visible = false
	view.Circle.Visible = true
	if mode == "Gamepad" then
		local ok, image = pcall(function()
			return UserInputService:GetImageForKeyCode(spec.PadCode)
		end)
		if ok and image ~= "" then
			view.Glyph.Image = image
			view.Glyph.Visible = true
			view.Circle.Visible = false
		else
			view.Circle.Text = KEY_WORDS[spec.PadCode.Name] or spec.PadCode.Name
		end
	elseif mode == "Touch" then
		view.Circle.Text = spec.Touch
	else
		view.Circle.Text = spec.Key
	end
end

local function refreshButtons()
	for _, spec in KEYS do
		local view = buttons[spec.Id]
		if view then
			view.Caption.Text = captionFor(spec.Id)
			showInput(view, spec)
			if spec.Id == "Auto" then
				-- ON = the UPGRADES green; OFF = the violet it started as.
				UIKit.SetButton(view.Button, { Style = if autoOn then "Green" else spec.Style })
			end
		end
	end
end

-- Within the server's reach of the pad (the prompt distance + RangeSlack),
-- less a margin so the two never disagree on the edge.
local function inReach(): boolean
	local view = card
	local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not view or not root or not root:IsA("BasePart") then
		return false
	end
	local reach = PlotLayout.Station.PromptDistance + GachaConfig.RangeSlack - GachaConfig.ClientReachMargin
	return (root.Position - view.Pad.Position).Magnitude <= reach
end

local function requestPull(count: number)
	if not inReach() then
		ToastController.Show(TOO_FAR_TEXT, "Neutral")
		return
	end
	RemoteEvents.RequestGachaPull:FireServer({ Count = count })
end

local function requestAuto()
	if not autoOn and not inReach() then
		ToastController.Show(TOO_FAR_TEXT, "Neutral")
		return
	end
	RemoteEvents.SetAutoPull:FireServer({ On = not autoOn })
end

local function runKey(id: string)
	if id == "Pull" then
		requestPull(1)
	elseif id == "Multi" then
		requestPull(TycoonConfig.MultiPullCount)
	else
		requestAuto()
	end
end

-- E / R / T (X / Y / RB), bound ONLY while the card is open. Out of reach the
-- key is passed on, so the other pads' E prompts keep working under the card.
local function onKeyAction(actionName: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not inReach() then
		return Enum.ContextActionResult.Pass
	end
	for _, spec in KEYS do
		if spec.Action == actionName then
			runKey(spec.Id)
			return Enum.ContextActionResult.Sink
		end
	end
	return Enum.ContextActionResult.Pass
end

local function bindKeys()
	if keysBound then
		return
	end
	keysBound = true
	for _, spec in KEYS do
		ContextActionService:BindAction(spec.Action, onKeyAction, false, spec.KeyCode, spec.PadCode)
	end
end

local function unbindKeys()
	if not keysBound then
		return
	end
	keysBound = false
	for _, spec in KEYS do
		ContextActionService:UnbindAction(spec.Action)
	end
end

local function buildKeyBar(root: Instance): Frame
	local row = Instance.new("Frame")
	row.Name = "KeyBar"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 1, 6) -- stepFitScale puts it right under the scaled card
	row.Size = UDim2.fromOffset(BUTTON_ROW_WIDTH, BUTTON_ROW_HEIGHT)
	row.Parent = root
	for index, spec in KEYS do
		local holder = Instance.new("Frame")
		holder.Name = spec.Id .. "Key"
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.new(0.5, (index - 2) * BUTTON_SPACING, 0, 0)
		holder.Size = UDim2.fromOffset(100, BUTTON_ROW_HEIGHT)
		holder.Parent = row
		local body = UIKit.Button({
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
				runKey(spec.Id)
			end,
		})
		local circle = label(body, {
			Name = "Key",
			Text = spec.Key,
			Font = Fonts.Display,
			TextSize = 30,
			TextColor3 = Colors.White,
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
		local caption = label(holder, {
			Name = "Caption",
			Text = captionFor(spec.Id),
			Font = Fonts.BodyHeavy,
			TextSize = 14,
			Stroke = UITheme.Stroke.Text,
			Position = UDim2.fromOffset(0, BUTTON_SIZE + 6),
			Size = UDim2.new(1, 0, 0, 22),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		UIKit.FitText(caption, 14, 9)
		buttons[spec.Id] = { Holder = holder, Button = body, Circle = circle, Glyph = glyph, Caption = caption }
	end
	return row
end

--[[ The card (one BillboardGui above your pad) ---------------------------------------- ]]

-- The ClampScale that keeps the card at most MaxScreenShare of the viewport
-- height. The card is CardStuds.Y tall in the world, `depth` studs in front
-- of the camera (FOV in degrees, vertical), so its on-screen share of the
-- viewport height is CardStuds.Y / (2 tan(FOV / 2) depth), whatever the
-- viewport size.
function GachaBoardController.ClampScaleFor(depth: number, fovDegrees: number): number
	local share = G.CardStuds.Y / (2 * math.tan(math.rad(fovDegrees) / 2) * math.max(depth, 0.5))
	return math.min(1, G.MaxScreenShare / share)
end

-- Design canvas -> the billboard's on-screen size (FitScale), the clamp, and
-- the key bar right under the scaled card.
local function stepFitScale(view: CardView)
	local size = view.Billboard.AbsoluteSize
	if size.X > 1 and size.Y > 1 then
		view.Fit.Scale = math.min(size.X / CANVAS.X, size.Y / CANVAS.Y)
	end
	local camera = Workspace.CurrentCamera
	if camera then
		local center = view.Pad.Position + Vector3.new(0, view.Pad.Size.Y / 2 + G.BottomAbovePad + G.CardStuds.Y / 2, 0)
		local depth = (center - camera.CFrame.Position):Dot(camera.CFrame.LookVector)
		view.Clamp.Scale = GachaBoardController.ClampScaleFor(depth, camera.FieldOfView)
	end
	local half = CANVAS.Y * view.Fit.Scale * view.Clamp.Scale / 2
	view.KeyBar.Position = UDim2.new(0.5, 0, 0.5, half + G.KeyBarGap)
end

local function setLabelEnabled(view: CardView, enabled: boolean)
	local label = view.Label
	if label and label.Parent and label:IsA("BillboardGui") then
		label.Enabled = enabled
	end
end

-- Pops the card in: Enabled, then UIScale 0.6 -> 1, Back-Out.
local function popIn(view: CardView)
	if view.Tween then
		view.Tween:Cancel()
		view.Tween = nil
	end
	view.Open = true
	view.Billboard.Enabled = true
	setLabelEnabled(view, false)
	bindKeys()
	if view.Pop.Scale >= 1 then
		return
	end
	if view.Pop.Scale < G.PopFromScale then
		view.Pop.Scale = G.PopFromScale
	end
	local tween = TweenService:Create(view.Pop, TweenInfo.new(G.PopInSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	view.Tween = tween
	tween:Play()
end

-- Pops it out: UIScale 1 -> 0.6, then Enabled off and the small label back.
local function popOut(view: CardView)
	if view.Tween then
		view.Tween:Cancel()
		view.Tween = nil
	end
	view.Open = false
	unbindKeys()
	local tween = TweenService:Create(view.Pop, TweenInfo.new(G.PopOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = G.PopFromScale })
	view.Tween = tween
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and not view.Open and card == view then
			view.Billboard.Enabled = false
			setLabelEnabled(view, true)
		end
	end)
	tween:Play()
end

local function buildCard(pad: BasePart, plotOrigin: CFrame?)
	local studs = G.CardStuds
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GachaCard"
	billboard.Adornee = pad
	billboard.Size = UDim2.new(studs.X, 0, studs.Y, 0)
	-- The card's bottom edge sits BottomAbovePad studs over the pad's top.
	billboard.StudsOffset = Vector3.new(0, pad.Size.Y / 2 + G.BottomAbovePad + studs.Y / 2, 0)
	-- ... and BackOffset (plot-local, away from the walkway) off your character.
	billboard.StudsOffsetWorldSpace = if plotOrigin then plotOrigin:VectorToWorldSpace(G.BackOffset) else Vector3.zero
	billboard.MaxDistance = G.MaxDistance
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Active = true
	billboard.ClipsDescendants = false
	billboard.Enabled = false

	-- Everything pops with this one scale (a UIScale, never a CanvasGroup),
	-- about its centre.
	local popRoot = Instance.new("Frame")
	popRoot.Name = "PopRoot"
	popRoot.BackgroundTransparency = 1
	popRoot.AnchorPoint = Vector2.new(0.5, 0.5)
	popRoot.Position = UDim2.fromScale(0.5, 0.5)
	popRoot.Size = UDim2.fromScale(1, 1)
	popRoot.Parent = billboard
	local pop = Instance.new("UIScale")
	pop.Name = "PopScale"
	pop.Scale = G.PopFromScale
	pop.Parent = popRoot

	-- The card (its own scale keeps it under MaxScreenShare of the viewport).
	local cardRoot = Instance.new("Frame")
	cardRoot.Name = "CardRoot"
	cardRoot.BackgroundTransparency = 1
	cardRoot.AnchorPoint = Vector2.new(0.5, 0.5)
	cardRoot.Position = UDim2.fromScale(0.5, 0.5)
	cardRoot.Size = UDim2.fromScale(1, 1)
	cardRoot.Parent = popRoot
	local clamp = Instance.new("UIScale")
	clamp.Name = "ClampScale"
	clamp.Parent = cardRoot

	-- The design canvas, scaled to the card's on-screen size.
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y)
	canvas.Parent = cardRoot
	local fit = Instance.new("UIScale")
	fit.Name = "FitScale"
	fit.Parent = canvas

	table.clear(buttons)
	local keyBar = buildKeyBar(popRoot)

	local view: CardView = {
		Billboard = billboard,
		Pad = pad,
		Pop = pop,
		Clamp = clamp,
		Fit = fit,
		KeyBar = keyBar,
		Canvas = canvas,
		Tiles = {},
		Spinners = {},
		Shimmer = nil,
		Sparkle = nil,
		Signature = "",
		Label = pad:FindFirstChild("GachaLabel"),
		Open = false,
		Tween = nil,
	}
	card = view
	billboard.Parent = localPlayer:WaitForChild("PlayerGui")
	populate(view)
	refreshButtons()
	pad.Destroying:Connect(function()
		if card == view then
			card = nil
			unbindKeys()
		end
		billboard:Destroy()
	end)
end

-- Your pad: Workspace.Plots[your plot].GachaStation.Pad (it exists once the lab is claimed).
local function findOwnPad(): (BasePart?, CFrame?)
	local plots = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	local plot = plots and plots:FindFirstChild(PlotNaming.GetPlotName(localPlayer.UserId))
	local station = plot and plot:FindFirstChild("GachaStation")
	local pad = station and station:FindFirstChild("Pad")
	if station and pad and pad:IsA("BasePart") then
		local origin = plot and plot:FindFirstChild("PlotOrigin")
		return pad, if origin and origin:IsA("BasePart") then origin.CFrame else nil
	end
	return nil, nil
end

--[[ Per frame ------------------------------------------------------------------------- ]]

local function stepFrame()
	local view = card
	if not view then
		return
	end
	if not view.Pad.Parent then
		return
	end
	-- Distance from YOUR CHARACTER to the pad, never the camera's.
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local distance = (root.Position - view.Pad.Position).Magnitude
		if not view.Open and distance < G.PopInStuds then
			popIn(view)
		elseif view.Open and distance > G.PopOutStuds then
			popOut(view)
		end
	end
	if not view.Billboard.Enabled then
		return
	end
	stepFitScale(view)
	local camera = Workspace.CurrentCamera
	local now = os.clock()
	if camera and view.Open and (view.Pad.Position - camera.CFrame.Position).Magnitude <= SPIN_STUDS + 40 then
		for _, spinner in view.Spinners do
			if spinner.Model.Parent then
				local angle = spinner.Phase + now * 1.1
				spinner.Model:PivotTo(CFrame.Angles(0.25, angle, 0) * CFrame.new(0, math.sin(now * 1.6 + spinner.Phase) * 0.06, 0))
			end
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

local function refresh()
	local view = card
	if not view then
		local pad, origin = findOwnPad()
		if pad then
			buildCard(pad, origin)
		end
		return
	end
	if not view.Pad.Parent then
		return
	end
	if not view.Label or not view.Label.Parent then
		view.Label = view.Pad:FindFirstChild("GachaLabel")
	end
	if view.Billboard.Enabled then
		setLabelEnabled(view, false) -- the card is up: no small label under it
	end
	local now = signatureOf()
	if now ~= view.Signature then
		populate(view)
		refreshButtons()
		if panel and panel.IsOpen() then
			fillPanel()
		end
	end
end

--[[ /selftest ------------------------------------------------------------------------------ ]]

-- Re-reads the odds, luck, event and Index now (the poll does it every 0.5 s).
function GachaBoardController.RefreshNow()
	refresh()
	if card then
		stepFrame()
	end
end

-- Your card (nil before your pad exists): the billboard, its pieces, and the
-- state the pop logic is in. Every UI check reads the instance tree from
-- Billboard down.
function GachaBoardController.GetCard(): { Billboard: BillboardGui, Pad: BasePart, Canvas: Frame, Pop: UIScale, Clamp: UIScale, Fit: UIScale, Open: boolean, Label: Instance? }?
	local view = card
	if not view then
		return nil
	end
	if not view.Label or not view.Label.Parent then
		view.Label = view.Pad:FindFirstChild("GachaLabel")
	end
	return { Billboard = view.Billboard, Pad = view.Pad, Canvas = view.Canvas, Pop = view.Pop, Clamp = view.Clamp, Fit = view.Fit, Open = view.Open, Label = view.Label }
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

-- The key bar as drawn: each button's id, GuiButton, holder and caption.
function GachaBoardController.GetKeyBar(): { Bar: Frame, Buttons: { { Id: string, Button: TextButton, Holder: Frame, Caption: TextLabel } } }?
	local view = card
	if not view then
		return nil
	end
	local list = {}
	for _, spec in KEYS do
		local button = buttons[spec.Id]
		if button then
			table.insert(list, { Id = spec.Id, Button = button.Button, Holder = button.Holder, Caption = button.Caption })
		end
	end
	return { Bar = view.KeyBar, Buttons = list }
end

-- The key actions this controller has bound right now (ContextActionService).
function GachaBoardController.GetBoundKeys(): { string }
	local bound = ContextActionService:GetAllBoundActionInfo()
	local names = {}
	for _, spec in KEYS do
		if bound[spec.Action] ~= nil then
			table.insert(names, spec.Key)
		end
	end
	return names
end

function GachaBoardController.IsAutoOn(): boolean
	return autoOn
end

function GachaBoardController.GetPanel(): UIKit.Modal?
	return panel
end

--[[ Lifecycle ------------------------------------------------------------------------------ ]]

function GachaBoardController.Init()
	buildPanel()
	RemoteEvents.AutoPullState.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		autoOn = payload.On == true
		refreshButtons()
		if not autoOn and typeof(payload.Reason) == "string" and payload.Reason ~= "Off" then
			local reason = payload.Reason :: string
			if reason == "InsufficientCash" and typeof(payload.Cost) == "number" then
				ToastController.Show(("Auto pull stopped: need %s"):format(NumberFormat.Money(payload.Cost)), "Neutral")
			else
				ToastController.Show(AUTO_STOP_TEXT[reason] or "Auto pull stopped", "Neutral")
			end
		end
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		refreshButtons()
	end)
	TycoonController.TycoonChanged:Connect(function()
		refresh()
	end)
	RunService.Heartbeat:Connect(stepFrame)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
end

return GachaBoardController
