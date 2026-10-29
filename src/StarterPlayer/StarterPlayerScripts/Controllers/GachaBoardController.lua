--!strict
--[[
	GachaBoardController
	--------------------
	The Gacha odds CARD: a pixel-sized BillboardGui ADORNED TO YOUR GACHA PAD,
	floating right over it and opening as you walk up, like a Pet Simulator 99
	egg card. A 300 x 204 px card plus a 72 px E / R / T row, the same size
	at any zoom. On a phone one UIScale shrinks the whole card until it fits
	between TopStack's chip row and the pad (PhoneScaleFor, 0.52..1.0). This is
	the final placement: not docked, not following the camera.

	Why the earlier in-world tries failed: they were sized in studs (huge up
	close) and sat "above your head" while you stand ON the pad (off the top
	of the screen). Fix: pixel size, anchored to the PAD, not the player. You
	pull with E / R / T from PromptDistance + 3 studs, so you stop in front of
	the pad and see the card over it.

	  * The stack clamp (desktop AND phone): every frame the card is up its top
	    is held >= TopStack's STABLE bottom (objective bar + event chip, no
	    toast; x PhoneScale on a phone) + the air (StackGapPx / PhoneTopGapPx,
	    4 px) by sliding the billboard's SizeOffset.Y down (StackShiftFor, pure;
	    SizeOffset.X is kept). A toast never moves the card: it draws over it for
	    its 2.5 s. PhoneScaleFor assumes you stand at the pad's centre; standing
	    off-centre moves the anchor, so the phone clamp is two-sided: the card's
	    top is clamp(natural top, chip row + gap, floor - height), so it slides
	    up as well as down and stays between the chip row and the floor (weapon
	    bar / bottom row); only a card taller than that band lowers the UIScale,
	    down to PhoneScaleMin, and then the top wins (PhonePlanFor, pure).
	    The anchor and the studs offsets below never change; if the clamp moves
	    the card off its anchor, it stays clamped (readable beats anchored).
	  * BillboardGui: Adornee = an Attachment "GachaCardAnchor" on the pad (the
	    pad is a cylinder turned 90 degrees about Z, so an offset on the pad
	    itself would be applied in ITS axes, sideways), Size = (300, 324) px,
	    SizeOffset (0, 0.5) so it grows UPWARD from the anchor (its bottom
	    edge, the key bar's, is on it); StudsOffsetWorldSpace stays zero and
	    StudsOffset is (0, 0, 2) (camera-relative +Z = toward the camera: in
	    front of the ball, radius 1.3; it never shifts the card sideways or up).
	    Both are set once and never written again. The Attachment's WorldCFrame
	    is set once: straight above the pad's centre, UpStuds over its top
	    (world y), with UpStuds = PlotLayout.Gacha.AnchorUpStuds (2.2, computed
	    from the capsule's numbers: the ball's BASE, so the card covers the
	    ball like PS99's egg card), centred on the pad, no backward shift. Set once when built; it never changes (no zoom or
	    top-of-screen logic). AlwaysOnTop false, LightInfluence 0,
	    MaxDistance 150, ResetOnSpawn false. No CanvasGroup.
	  * Pop: in at PopInStuds (16) from your character to the pad, out at
	    PopOutStuds (19); one UIScale 0.85 -> 1 over 0.12 s (Quad).
	  * While it is open it hides what it would cover: the pad's small GACHA /
	    price label, your VIP head chip and the capsule ball (CapsuleTop /
	    CapsuleBottom / CapsuleBand get LocalTransparencyModifier 1, back to 0
	    on close), so nothing pokes out around the card (restored on close). The pad's own
	    prompts stay off.
	  * Hidden (with the pop) while any overlay (modal / big card) is open,
	    during a ragdoll and while carrying, and back after.
	  * Built ONCE, hidden, as soon as your pad exists. A refresh only updates
	    text and colours (the %s, each tier's lock state, luck, the event, the
	    chips, the price), never rebuilds. 2D orbs (UIKit.TierOrb), no
	    ViewportFrame, no CanvasGroup, no TextScaled. One UIScale for the pop
	    (PopScale) plus the phone's PhoneScale (PhoneScaleFor, from the logical
	    viewport) when UIKit.IsPhone().

	The card (design px) copies Pet Sim 99's egg card: a 300 x 196 WHITE card
	(UITheme CardPaper, a soft diagonal, a 3 px light blue-grey rim, 18 px
	corners; no dark panel, no gold rim, no header bar). "Gacha Pad" (Display
	26, white, ink stroke) is centred on its top edge at x 10, the luck pill
	just right of it, the event chip on its own row above; (i) is a 34 px blue
	circle with a white rim at the top-right corner (right edge 6 px in), centred
	on the top edge. Six bare 92 x 82 orb cells, 3 x 2 (no tile, no ribbon): a
	58 px 2D orb with its % (22 px Display, tier colour, ink stroke over a white
	outline) overlapping its bottom; a tier you never found is a solid black orb
	of the same shape (no mark) and STILL shows its %; Secret has a soft rainbow
	glow behind the orb. ONE line of 12 px mutation odds at the bottom left, each
	value in its colour. The price (a gold coin + 24 px Display amount, FREE
	during the tutorial pulls) is centred on the bottom edge at the right.

	THE KEY BAR, 10 px under the card: round solid-blue buttons with a white
	rim and a soft ink shadow, [E] Pull, [R] x10 (bigger, 62 px), [T] Auto x10
	(sides 52 px, 56 on a phone; a key's tap target is its whole 84 x 80 holder,
	>= 44 px on screen down to the phone scale's 0.55 floor); the key
	letter inside, a white caption under each (T turns green and reads
	"Auto x10 ON" while Auto pull runs: a x10 pull per cycle). It does
	NOT use ProximityPrompt UI: the pad's prompts are off (this controller also
	keeps them off on this client). While the card is open E / R / T (X / Y / RB
	on a controller) are bound with ContextActionService, and unbound when it
	closes; the keys and the buttons send RequestGachaPull { Count = 1 | 10 }
	and SetAutoPull { On }; the server runs the one shared pull function.
	Desktop and touch show the key letter (the circles are the tap targets), a
	controller its glyphs; the server's AutoPullState says when and why Auto
	pull stopped (a toast).

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
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TycoonController = require(script.Parent.TycoonController)
local ToastController = require(script.Parent.ToastController)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local TopStack = require(script.Parent.Parent.UI.TopStack)

local GachaBoardController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts
local BLUE = UITheme.Gradients.Blue.Top -- the (i) and the E / R / T circles: solid UITheme blue

local G = PlotLayout.Gacha
local CARD = G.CardPx -- 300 x 196
local TOP_PAD = G.TopPadPx -- room above the card for the title, (i) and event chip
local ROW_HEIGHT = G.ButtonRowPx
local FULL_SIZE = Vector2.new(CARD.X, TOP_PAD + CARD.Y + ROW_HEIGHT) -- pad + card + the button row
local CELL_SIZE = Vector2.new(92, 82)
local CELL_GAP = 4
local GRID_Y = 10
local ORB_SIZE = 58
local PERCENT_SIZE = 22
local PERCENT_Y = 48 -- the % overlaps the orb's bottom by ~10 px
local PERCENT_INK = 2
local PERCENT_OUTLINE = 3
local TITLE_WIDTH = 150
local INFO_SIZE = 34
local INFO_HIT = 56
local MUTATION_WIDTH = 190
local COIN_SIZE = 16
local CENTER_BUTTON = 62
local SIDE_BUTTON = 52
local SIDE_BUTTON_PHONE = 56 -- >= 44 px after the phone's 0.8
local BUTTON_SPACING = 86
local KEY_BAR_GAP = 10
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
	Caption: string,
	Action: string, -- the ContextActionService name
}

type ButtonView = {
	Holder: Frame,
	Shadow: Frame,
	Button: TextButton,
	Circle: TextLabel,
	Glyph: ImageLabel,
	Caption: TextLabel,
	Slot: number, -- -1 / 0 / 1: which side of the centre key (x the row's spacing)
}

type TileView = {
	Frame: Frame,
	Orb: Frame, -- the 2D tier orb (hidden for a never-found tier)
	Silhouette: Frame, -- the solid black orb (shown for a never-found tier)
	Percent: TextLabel,
	Outline: TextLabel, -- the white outline copy behind the %
}

type CardView = {
	Billboard: BillboardGui,
	Pad: BasePart,
	Root: Frame, -- bottom-centre anchored; carries the phone's UIScale
	PopRoot: Frame, -- everything; hidden = the card is closed
	Pop: UIScale, -- the pop-in / pop-out scale
	Card: Frame, -- the 300 x 196 white card
	KeyBar: Frame, -- the E / R / T row under the card
	Tiles: { [string]: TileView },
	MutationLine: TextLabel, -- one line: each mutation's pull % in its colour (desktop only)
	Phone: boolean, -- the phone variant is applied (see applyVariant)
	Title: TextLabel,
	Pills: Frame,
	EventRow: Frame,
	PriceRow: Frame,
	InfoHit: TextButton,
	InfoMark: TextLabel,
	LuckPill: TextLabel,
	EventPill: TextLabel,
	Price: TextLabel,
	Signature: string,
	Label: Instance?, -- the small server GachaLabel
	Near: boolean, -- the character is close (the open side of the distance hysteresis)
	Open: boolean, -- the card is up (near AND nothing is covering it)
	Tween: Tween?,
	Anchor: Attachment, -- the world point the billboard is adorned to (never an offset on the rotated pad)
	UpStuds: number, -- the anchor above the pad's top: above the capsule ball, set once
	VipTag: BillboardGui?, -- your head chip while it is hidden by the card
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
	local steady = TycoonController.GetSteadyIncomePerSecond()
	return {
		Luck = TycoonController.GetLuck(),
		Free = TycoonController.GetTutorial().FreePulls,
		Cost = TycoonConfig.GetGachaPullCost(pulls, steady),
		MultiCost = TycoonConfig.GetGachaMultiPullCost(pulls, TycoonConfig.MultiPullCount, steady),
	}
end

local function priceText(inputs: Inputs): string
	if inputs.Free > 0 then
		return "FREE"
	end
	return NumberFormat.Money(inputs.Cost)
end

local function luckText(luck: number, short: boolean): string
	return ((if short then "🍀×%s" else "🍀 Luck ×%s")):format(NumberFormat.Multiplier(luck):sub(2))
end

--[[ Building the card (once) ----------------------------------------------------------- ]]

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local text = UIKit.Label(props)
	text.Parent = parent
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

-- One orb cell (92 x 82), no tile and no ribbon: a big 2D orb (or the solid
-- black silhouette of a tier you never found) with its % laid over the orb's
-- bottom, in the tier colour with an ink stroke over a white outline. Secret
-- has a soft rainbow glow behind the orb. Built once; updateTile sets the text.
local function buildTile(view: CardView, parent: Instance, tier: string): TileView
	local accent = FusionConfig.TierAccentColors[tier] or Colors.Text
	local cell = Instance.new("Frame")
	cell.Name = "Tile_" .. tier
	cell.BackgroundTransparency = 1
	cell.BorderSizePixel = 0
	cell.Size = UDim2.fromOffset(CELL_SIZE.X, CELL_SIZE.Y)
	cell:SetAttribute("Tier", tier)

	if tier == "Secret" then
		local glowSize = ORB_SIZE + 16
		local glow = frame(cell, "RainbowGlow", UDim2.new(0.5, -glowSize / 2, 0, (ORB_SIZE - glowSize) / 2), UDim2.fromOffset(glowSize, glowSize), Colors.White)
		glow.BackgroundTransparency = 0.5
		UIKit.Corner(glow, 999)
		local gradient = Instance.new("UIGradient")
		gradient.Color = UITheme.GetRainbowSequence()
		gradient.Rotation = 45
		gradient.Parent = glow
	end

	local orb = UIKit.TierOrb(tier, ORB_SIZE)
	orb.Name = "Orb"
	orb.AnchorPoint = Vector2.new(0.5, 0)
	orb.Position = UDim2.new(0.5, 0, 0, 0)
	orb.Parent = cell

	-- The never-found tier: the same shape as a solid black orb, no mark (PS99).
	local silhouette = frame(cell, "Silhouette", UDim2.new(0.5, -ORB_SIZE / 2, 0, 0), UDim2.fromOffset(ORB_SIZE, ORB_SIZE), Colors.Black)
	UIKit.Corner(silhouette, 999)
	silhouette.Visible = false

	-- The %: a white outline copy behind (ink 2 px + white 3 px outside it), then
	-- the accent text with its ink stroke.
	local function percentLabel(name: string, z: number): TextLabel
		return label(cell, {
			Name = name,
			Text = "",
			Font = Fonts.Display,
			TextSize = PERCENT_SIZE,
			TextColor3 = accent,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, PERCENT_Y),
			Size = UDim2.new(1, 0, 0, PERCENT_SIZE + 4),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z,
		})
	end
	local outline = percentLabel("PercentOutline", 5)
	outline.TextColor3 = Colors.White
	local outlineStroke = UIKit.TextStroke(outline, PERCENT_INK + PERCENT_OUTLINE)
	outlineStroke.Color = Colors.White
	local percent = percentLabel("Percent", 6)
	UIKit.TextStroke(percent, PERCENT_INK)

	cell.Parent = parent
	return { Frame = cell, Orb = orb, Silhouette = silhouette, Percent = percent, Outline = outline }
end

-- Builds every piece of the card's face ONCE (hidden). updateContent sets
-- the text and colours; nothing is ever rebuilt.
local function buildContent(view: CardView, card: Frame)
	-- White paper: a soft diagonal, a light blue-grey 3 px rim (corners set by buildCard).
	UIKit.Stroke(card, 3, Colors.CardPaperStroke)
	local paper = Instance.new("UIGradient")
	paper.Color = ColorSequence.new(Colors.CardPaper, Colors.CardPaperShade)
	paper.Rotation = 35
	paper.Parent = card

	-- Title: half above the card's top edge, left at x 10.
	view.Title = label(card, {
		Name = "Title",
		Text = "Gacha Pad",
		Font = Fonts.Display,
		TextSize = 26,
		TextColor3 = Colors.White,
		Stroke = 3,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.fromOffset(TITLE_WIDTH, 34),
		ZIndex = 8,
	})
	-- The luck pill just right of the title; the event chip on its own row above it.
	local pills = frame(card, "Pills", UDim2.fromOffset(10 + TITLE_WIDTH, 0), UDim2.fromOffset(CARD.X - 10 - TITLE_WIDTH - 38, 20))
	pills.AnchorPoint = Vector2.new(0, 0.5)
	pills.ZIndex = 8
	view.Pills = pills
	local pillLayout = Instance.new("UIListLayout")
	pillLayout.FillDirection = Enum.FillDirection.Horizontal
	pillLayout.Padding = UDim.new(0, 4)
	pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pillLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pillLayout.Parent = pills
	local eventRow = frame(card, "EventRow", UDim2.fromOffset(10, -TOP_PAD + 2), UDim2.fromOffset(CARD.X - 20, 20))
	eventRow.ZIndex = 8
	view.EventRow = eventRow
	local eventLayout = Instance.new("UIListLayout")
	eventLayout.FillDirection = Enum.FillDirection.Horizontal
	eventLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	eventLayout.SortOrder = Enum.SortOrder.LayoutOrder
	eventLayout.Parent = eventRow
	view.EventPill = UIKit.Pill({ Name = "EventChip", Parent = eventRow, Text = "", Gradient = UITheme.Gradients.Violet, TextSize = 11, Height = 20 })
	view.LuckPill = UIKit.Pill({ Name = "LuckPill", Parent = pills, Text = "", Gradient = UITheme.Gradients.Green, TextSize = 11, Height = 18 })
	UIKit.SetPillVisible(view.EventPill, false)
	UIKit.SetPillVisible(view.LuckPill, false)

	-- (i): a blue 34 px circle with a white rim, its right edge 6 px inside the
	-- card's corner and its centre on the top edge; a 56 px hit area.
	local infoCentre = UDim2.fromOffset(CARD.X - 6 - INFO_SIZE / 2, 0)
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.AnchorPoint = Vector2.new(0.5, 0.5)
	info.Position = infoCentre
	info.Size = UDim2.fromOffset(INFO_SIZE, INFO_SIZE)
	info.BackgroundColor3 = BLUE
	info.BorderSizePixel = 0
	info.ZIndex = 8
	info.Parent = card
	UIKit.Corner(info, 999)
	UIKit.Stroke(info, 3, Colors.White)
	view.InfoMark = label(info, {
		Name = "Mark",
		Text = "i",
		Font = Fonts.Display,
		TextSize = 22,
		TextColor3 = Colors.White,
		Stroke = UITheme.Stroke.Text,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 9,
	})
	local infoHit = Instance.new("TextButton")
	infoHit.Name = "InfoHit"
	infoHit.AnchorPoint = Vector2.new(0.5, 0.5)
	infoHit.Position = infoCentre
	infoHit.Size = UDim2.fromOffset(INFO_HIT, INFO_HIT)
	infoHit.BackgroundTransparency = 1
	infoHit.Text = ""
	infoHit.ZIndex = 10
	infoHit.Parent = card
	view.InfoHit = infoHit
	infoHit.Activated:Connect(function()
		GachaBoardController.OpenPanel()
	end)

	-- Six orb cells, 3 x 2, centred.
	local gridWidth = CELL_SIZE.X * 3 + CELL_GAP * 2
	local grid = frame(card, "Tiles", UDim2.new(0.5, -gridWidth / 2, 0, GRID_Y), UDim2.fromOffset(gridWidth, CELL_SIZE.Y * 2 + CELL_GAP))
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL_SIZE.X, CELL_SIZE.Y)
	layout.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for index, tier in FusionConfig.TierOrder do
		local tile = buildTile(view, grid, tier)
		tile.Frame.LayoutOrder = index
		view.Tiles[tier] = tile
	end

	-- Mutation odds: ONE line of small text, bottom left, each value in its colour.
	view.MutationLine = label(card, {
		Name = "MutationLine",
		Text = "",
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		RichText = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(12, CARD.Y - 4),
		Size = UDim2.fromOffset(MUTATION_WIDTH, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		Stroke = UITheme.Stroke.Text,
	})

	-- The price: a gold coin and the amount, centred on the card's bottom edge at the right.
	local priceRow = frame(card, "PriceRow", UDim2.fromOffset(CARD.X - 10, CARD.Y), UDim2.fromOffset(0, 30))
	priceRow.AnchorPoint = Vector2.new(1, 0.5)
	priceRow.AutomaticSize = Enum.AutomaticSize.X
	priceRow.ZIndex = 8
	view.PriceRow = priceRow
	local priceLayout = Instance.new("UIListLayout")
	priceLayout.FillDirection = Enum.FillDirection.Horizontal
	priceLayout.Padding = UDim.new(0, 4)
	priceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	priceLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	priceLayout.SortOrder = Enum.SortOrder.LayoutOrder
	priceLayout.Parent = priceRow
	local coin = frame(priceRow, "Coin", UDim2.new(), UDim2.fromOffset(COIN_SIZE, COIN_SIZE), Colors.White)
	coin.LayoutOrder = 1
	coin.ZIndex = 8
	UIKit.Corner(coin, 999)
	UIKit.PairGradient(coin, UITheme.Gradients.Gold)
	UIKit.Stroke(coin, 2, Colors.Ink)
	local face = frame(coin, "Face", UDim2.new(0.5, -3, 0.5, -3), UDim2.fromOffset(6, 6), UITheme.Gradients.Gold.Bottom)
	face.ZIndex = 9
	UIKit.Corner(face, 999)
	view.Price = label(priceRow, {
		Name = "Price",
		Text = "",
		Font = Fonts.Display,
		TextSize = 24,
		TextColor3 = Colors.GoldLabel,
		Stroke = 3,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 2,
		ZIndex = 8,
	})
end

-- A tile's % label: its size and how far to slide it sideways (px) so the text
-- and its outline stay inside the card. `column` is 1..3 (the grid is 3 wide).
-- The phone keeps the full PhoneTextPx for every value (a long one like
-- "0.0035%" used to drop 3 px and fell to 12 px on screen); the odds text
-- itself is never rounded or reformatted. The width is an estimate (the
-- Display font's digits run ~0.56 em), generous so the slide is never short.
local PERCENT_EM_PER_CHAR = 0.56
local CARD_EDGE_MARGIN = 2
function GachaBoardController.PlanPercent(text: string, phone: boolean, column: number): (number, number)
	local base = if phone then G.PhoneTextPx else PERCENT_SIZE
	local size = if phone or #text <= 6 then base else base - 3
	local half = #text * PERCENT_EM_PER_CHAR * size / 2 + PERCENT_INK + PERCENT_OUTLINE
	local gridWidth = CELL_SIZE.X * 3 + CELL_GAP * 2
	local centre = (CARD.X - gridWidth) / 2 + (column - 1) * (CELL_SIZE.X + CELL_GAP) + CELL_SIZE.X / 2
	local shift = 0
	if centre + half > CARD.X - CARD_EDGE_MARGIN then
		shift = CARD.X - CARD_EDGE_MARGIN - half - centre
	elseif centre - half < CARD_EDGE_MARGIN then
		shift = CARD_EDGE_MARGIN + half - centre
	end
	return size, math.round(shift)
end

-- Sets the text and colours from the odds, luck, event, Index and price.
-- Never creates or destroys anything.
local function updateContent(view: CardView)
	local inputs = currentInputs()
	local rows = currentRows(inputs.Luck)
	local found = foundTiers()
	for index, row in rows.Tiers do
		local tile = view.Tiles[row.Tier]
		if tile then
			local size, shift = GachaBoardController.PlanPercent(row.Text, view.Phone, (index - 1) % 3 + 1)
			for _, text in { tile.Percent, tile.Outline } do
				text.Text = row.Text
				text.TextSize = size
				text.Position = UDim2.new(0.5, shift, 0, PERCENT_Y)
			end
			local isFound = found[row.Tier] == true
			tile.Orb.Visible = isFound
			tile.Silhouette.Visible = not isFound
			tile.Frame:SetAttribute("PercentValue", row.Rate * 100)
			tile.Frame:SetAttribute("Silhouette", not isFound)
		end
	end
	-- Mutation odds: one line, each value in its mutation colour (smaller when
	-- an event adds more of them).
	local parts: { string } = {}
	for _, row in rows.Mutations do
		local color = UITheme.GetMutationColor(row.Mutation) or Colors.Text
		table.insert(parts, ('<font color="#%s">%s%s</font>'):format(color:ToHex(), MUTATION_ICONS[row.Mutation] or "", row.Text))
	end
	view.MutationLine.Text = table.concat(parts, "  ")
	view.MutationLine.TextSize = if #parts > 4 then 10 else 12
	view.Price.Text = priceText(inputs)
	view.LuckPill.Text = luckText(inputs.Luck, view.Phone)
	UIKit.SetPillVisible(view.LuckPill, inputs.Luck > 1.0001)
	local eventId = oddsEvent(rows, inputs.Luck)
	if eventId then
		view.EventPill.Text = ("%s %s"):format(EventConfig.Icons[eventId] or "", EventConfig.Names[eventId] or eventId)
	end
	UIKit.SetPillVisible(view.EventPill, eventId ~= nil)

	local signature = { priceText(inputs), ("%.5f"):format(inputs.Luck), tostring(eventId) }
	for _, row in rows.Tiers do
		table.insert(signature, row.Text)
	end
	for _, row in rows.Mutations do
		table.insert(signature, row.Mutation .. row.Text)
	end
	for _, tier in FusionConfig.TierOrder do
		table.insert(signature, if found[tier] then "1" else "0")
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
	local found = foundTiers()
	for _, tier in FusionConfig.TierOrder do
		table.insert(signature, if found[tier] then "1" else "0")
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
	{ Id = "Pull", Key = "E", KeyCode = Enum.KeyCode.E, PadCode = Enum.KeyCode.ButtonX, Caption = "Pull", Action = "GachaPull" },
	{ Id = "Multi", Key = "R", KeyCode = Enum.KeyCode.R, PadCode = Enum.KeyCode.ButtonY, Caption = "×10", Action = "GachaPull10" },
	{ Id = "Auto", Key = "T", KeyCode = Enum.KeyCode.T, PadCode = Enum.KeyCode.ButtonR1, Caption = "Auto ×10", Action = "GachaAuto" },
}

local function captionFor(spec: KeySpec): string
	-- The phone's captions are 25 px (13 px after the scale): "Auto ×10" would not fit under its key.
	local phone = UIKit.IsPhone()
	if spec.Id == "Auto" then
		if phone then
			return if autoOn then "Auto ON" else "Auto"
		end
		return if autoOn then "Auto ×10 ON" else spec.Caption
	end
	return spec.Caption
end

-- Which input the player is using: the key caps (desktop and touch: the same
-- circles are the tap targets) or the controller glyphs.
local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:find("Gamepad", 1, true) ~= nil
end

local function showInput(view: ButtonView, spec: KeySpec)
	view.Glyph.Visible = false
	view.Circle.Visible = true
	view.Circle.Text = spec.Key
	if usingGamepad() then
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
	end
end

local function refreshButtons()
	for _, spec in KEYS do
		local view = buttons[spec.Id]
		if view then
			view.Caption.Text = captionFor(spec)
			showInput(view, spec)
			if spec.Id == "Auto" then
				-- ON = the UPGRADES green; OFF = the same blue as E and R.
				view.Button.BackgroundColor3 = if autoOn then UITheme.Gradients.Green.Bottom else BLUE
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

-- The circles' sizes: the centre (R) 62, the sides 52, or 56 on a phone. The tap
-- target is the key's whole holder (see buildKeyBar), not the circle.
local function applyButtonSizes()
	local side = if UIKit.IsPhone() then SIDE_BUTTON_PHONE else SIDE_BUTTON
	for _, spec in KEYS do
		local view = buttons[spec.Id]
		if view then
			local px = if spec.Id == "Multi" then CENTER_BUTTON else side
			view.Button.Size = UDim2.fromOffset(px, px)
			view.Shadow.Size = UDim2.fromOffset(px, px)
		end
	end
end

-- PS99's buttons: round solid-blue circles with a white rim, the key letter
-- inside, a caption under each; the centre one is bigger.
local function buildKeyBar(root: Instance): Frame
	local row = Instance.new("Frame")
	row.Name = "KeyBar"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, TOP_PAD + CARD.Y + KEY_BAR_GAP)
	row.Size = UDim2.fromOffset(CARD.X, ROW_HEIGHT - KEY_BAR_GAP)
	row.Parent = root
	local centreY = CENTER_BUTTON / 2
	for index, spec in KEYS do
		local holder = frame(row, spec.Id .. "Key", UDim2.new(0.5, (index - 2) * BUTTON_SPACING, 0, 0), UDim2.fromOffset(BUTTON_SPACING - 2, ROW_HEIGHT - KEY_BAR_GAP))
		holder.AnchorPoint = Vector2.new(0.5, 0)
		-- The tap target is the whole holder (84 x 80), not just the circle: on a
		-- phone the card is scaled down to ~0.56 and the circle alone would be
		-- ~32 px; the holder stays >= 44 px at PhoneScaleMin.
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.Size = UDim2.fromScale(1, 1)
		hit.Parent = holder
		hit.Activated:Connect(function()
			UIKit.SelectFeedback(holder)
			runKey(spec.Id)
		end)
		-- A soft ink shadow a few px below the circle.
		local shadow = frame(holder, "Shadow", UDim2.new(0.5, 0, 0, centreY + 3), UDim2.fromOffset(SIDE_BUTTON, SIDE_BUTTON), Colors.Ink)
		shadow.AnchorPoint = Vector2.new(0.5, 0.5)
		shadow.BackgroundTransparency = 0.6
		UIKit.Corner(shadow, 999)
		local body = Instance.new("TextButton")
		body.Name = "Round"
		body.AutoButtonColor = false
		body.Text = ""
		body.BackgroundColor3 = BLUE
		body.BorderSizePixel = 0
		body.AnchorPoint = Vector2.new(0.5, 0.5)
		body.Position = UDim2.new(0.5, 0, 0, centreY)
		body.Size = UDim2.fromOffset(SIDE_BUTTON, SIDE_BUTTON)
		body.Parent = holder
		UIKit.Corner(body, 999)
		UIKit.Stroke(body, 4, Colors.White)
		body.Activated:Connect(function()
			UIKit.SelectFeedback(holder)
			runKey(spec.Id)
		end)
		local circle = label(body, {
			Name = "Key",
			Text = spec.Key,
			Font = Fonts.Display,
			TextSize = 28,
			TextColor3 = Colors.White,
			Stroke = UITheme.Stroke.Text,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
		})
		local glyph = Instance.new("ImageLabel")
		glyph.Name = "Glyph"
		glyph.BackgroundTransparency = 1
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromOffset(34, 34)
		glyph.Visible = false
		glyph.ZIndex = 3
		glyph.Parent = body
		local caption = label(holder, {
			Name = "Caption",
			Text = captionFor(spec),
			Font = Fonts.BodyHeavy,
			TextSize = 14,
			Stroke = UITheme.Stroke.Text,
			Position = UDim2.fromOffset(0, CENTER_BUTTON + 2),
			Size = UDim2.new(1, 0, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		buttons[spec.Id] = { Holder = holder, Shadow = shadow, Button = body, Circle = circle, Glyph = glyph, Caption = caption, Slot = index - 2 }
	end
	applyButtonSizes()
	return row
end

--[[ The card ------------------------------------------------------------------------ ]]

local function setLabelEnabled(view: CardView, enabled: boolean)
	local label = view.Label
	if label and label.Parent and label:IsA("BillboardGui") then
		label.Enabled = enabled
	end
end

-- The capsule ball is replaced by the card while it is open (client-only
-- LocalTransparencyModifier 1; 0 restores it).
local BALL_PARTS = { "CapsuleTop", "CapsuleBottom", "CapsuleBand" }

local function hideBall(view: CardView, hidden: boolean)
	local station = view.Pad.Parent
	if not station then
		return
	end
	for _, name in BALL_PARTS do
		local part = station:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function hideVipTag(view: CardView, hidden: boolean)
	if hidden then
		local character = localPlayer.Character
		local head = character and character:FindFirstChild("Head")
		local tag = head and head:FindFirstChild("VipTag")
		if tag and tag:IsA("BillboardGui") then
			tag.Enabled = false
			view.VipTag = tag
		end
	else
		local tag = view.VipTag
		if tag and tag.Parent then
			tag.Enabled = true
		end
		view.VipTag = nil
	end
end

-- Opens: the PopRoot shows and the pop scale runs 0.85 -> 1 (Quad-Out); the
-- small label and your VIP chip step aside.
local function popIn(view: CardView)
	if view.Tween then
		view.Tween:Cancel()
		view.Tween = nil
	end
	view.Open = true
	view.PopRoot.Visible = true
	setLabelEnabled(view, false)
	hideVipTag(view, true)
	hideBall(view, true)
	bindKeys()
	if view.Pop.Scale >= 1 then
		return
	end
	if view.Pop.Scale < G.PopFromScale then
		view.Pop.Scale = G.PopFromScale
	end
	local tween = TweenService:Create(view.Pop, TweenInfo.new(G.PopSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
	view.Tween = tween
	tween:Play()
end

-- Closes: the same in reverse (1 -> 0.85), then hidden. The small label comes
-- back only when the character is far (not while a modal merely covers the
-- card); the VIP chip comes back at once.
local function popOut(view: CardView)
	if view.Tween then
		view.Tween:Cancel()
		view.Tween = nil
	end
	view.Open = false
	unbindKeys()
	hideVipTag(view, false)
	hideBall(view, false)
	local tween = TweenService:Create(view.Pop, TweenInfo.new(G.PopSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = G.PopFromScale })
	view.Tween = tween
	tween.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and not view.Open and card == view then
			view.PopRoot.Visible = false
			setLabelEnabled(view, not view.Near)
		end
	end)
	tween:Play()
end

--[[ Anchor ---------------------------------------------------------------------- ]]

-- The phone's sizing UIScale: ONE factor for the whole card, from the logical
-- viewport `view` (UIKit.GetLogicalViewport) and the card's size. The card is
-- a pixel-size billboard, so on a phone it must shrink until the whole card
-- (title to key bar, PhoneFullHeight tall) fits between TopStack's chip row and
-- the pad's anchor, which sits at G.PhoneAnchorY of the screen height when you
-- stand on the pad at the default camera. In screen px (logical x PhoneScale):
-- the card's top lands on math.ceil(chip row bottom) + G.PhoneTopGapPx, the
-- height between it and the anchor snapped down to a whole px; the factor is
-- clamped to G.PhoneScaleMin..G.PhoneScaleMax. Pure: /selftest runs it at
-- 844 x 390 and 896 x 414.
function GachaBoardController.PhoneScaleFor(view: Vector2): number
	local anchorPx = G.PhoneAnchorY * view.Y * UITheme.PhoneScale
	local topPx = math.ceil(G.PhoneTopReservePx * UITheme.PhoneScale) + G.PhoneTopGapPx
	local heightPx = math.floor(anchorPx - topPx)
	return math.clamp(heightPx / GachaBoardController.PhoneFullHeight, G.PhoneScaleMin, G.PhoneScaleMax)
end

-- The phone variant: not the desktop card shrunk evenly (its 11-12 px lines
-- fall to ~6 px) but a card laid out for the scale. No mutation line (the
-- (i) panel has it), the %, the pills, the (i) mark and the price big enough
-- to read >= 13 px after the scale, a taller pill row, a card 12 px shorter
-- and an (i) hit area >= 44 px after the scale. Positions and sizes only: it
-- runs on every layout change and creates nothing.
local function applyVariant(view: CardView)
	local phone = UIKit.IsPhone()
	view.Phone = phone
	local topPad = if phone then G.PhoneTopPadPx else TOP_PAD
	local cardHeight = if phone then G.PhoneCardHeightPx else CARD.Y
	local textPx = if phone then G.PhoneTextPx else PERCENT_SIZE
	local pillHeight = if phone then G.PhonePillHeightPx else 20
	local pillTextPx = if phone then G.PhoneTextPx else 11
	local rowHeight = if phone then G.PhoneButtonRowPx else ROW_HEIGHT
	local spacing = if phone then G.PhoneButtonSpacingPx else BUTTON_SPACING
	view.Billboard.Size = UDim2.fromOffset(CARD.X, topPad + cardHeight + rowHeight)
	view.Card.Position = UDim2.fromOffset(0, topPad)
	view.Card.Size = UDim2.fromOffset(CARD.X, cardHeight)
	view.KeyBar.Position = UDim2.fromOffset(0, topPad + cardHeight + KEY_BAR_GAP)
	view.KeyBar.Size = UDim2.fromOffset(CARD.X, rowHeight - KEY_BAR_GAP)
	for _, button in buttons do
		button.Holder.Size = UDim2.fromOffset(spacing - 2, rowHeight - KEY_BAR_GAP)
		button.Holder.Position = UDim2.new(0.5, button.Slot * spacing, 0, 0)
		button.Caption.TextSize = if phone then G.PhoneCaptionPx else 14
		button.Caption.Size = UDim2.new(1, 0, 0, if phone then G.PhoneCaptionPx else 16)
	end
	refreshButtons()
	view.EventRow.Position = UDim2.fromOffset(10, -topPad + 2)
	view.EventRow.Size = UDim2.fromOffset(CARD.X - 20, pillHeight)
	view.Pills.Size = UDim2.fromOffset(CARD.X - 10 - TITLE_WIDTH - 38, pillHeight)
	for _, pill in { view.EventPill, view.LuckPill } do
		pill.TextSize = pillTextPx
		UIKit.PillRoot(pill).Size = UDim2.fromOffset(0, if phone then G.PhonePillHeightPx else (if pill == view.EventPill then 20 else 18))
	end
	view.MutationLine.Visible = not phone
	view.MutationLine.Position = UDim2.fromOffset(12, cardHeight - 4)
	view.PriceRow.Position = UDim2.fromOffset(CARD.X - 10, cardHeight)
	view.PriceRow.Size = UDim2.fromOffset(0, if phone then 34 else 30)
	view.Price.TextSize = if phone then G.PhonePriceTextPx else 24
	view.Price.Size = UDim2.fromOffset(0, if phone then 34 else 30)
	view.InfoMark.TextSize = if phone then G.PhoneTextPx else 22
	local hit = if phone then G.PhoneInfoHitPx else INFO_HIT
	view.InfoHit.Size = UDim2.fromOffset(hit, hit)
	-- Inside the billboard's right edge, or the part past it takes no taps.
	view.InfoHit.Position = UDim2.fromOffset(if phone then CARD.X - hit / 2 else CARD.X - 6 - INFO_SIZE / 2, 0)
	for _, tile in view.Tiles do
		for _, text in { tile.Percent, tile.Outline } do
			text.Size = UDim2.new(1, 0, 0, textPx + 4)
		end
	end
	updateContent(view)
end

GachaBoardController.PhoneFullHeight = G.PhoneTopPadPx + G.PhoneCardHeightPx + G.PhoneButtonRowPx

-- Set on build, on LayoutChanged and on every viewport resize. Scaled about
-- the card's bottom line, so the anchor does not move.
local function applyPhoneScale(view: CardView)
	applyVariant(view)
	local existing = view.Root:FindFirstChild("PhoneScale")
	if UIKit.IsPhone() then
		local scale: UIScale
		if existing and existing:IsA("UIScale") then
			scale = existing
		else
			scale = Instance.new("UIScale")
			scale.Name = "PhoneScale"
			scale.Parent = view.Root
		end
		scale.Scale = GachaBoardController.PhoneScaleFor(UIKit.GetLogicalViewport())
	elseif existing then
		existing:Destroy()
	end
	applyButtonSizes()
end

-- The card's anchor: a world point straight above the pad's centre, `up`
-- studs over the pad's top. An Attachment (not the rotated cylinder) so no
-- offset is ever applied in the pad's own axes: the pad is a cylinder turned
-- 90 degrees about Z, its local +Y points sideways.
local function setUpStuds(view: CardView, up: number)
	view.UpStuds = up
	local pad = view.Pad
	-- The pad's top along the WORLD y axis, whatever its rotation: the centre
	-- plus the half-extent of its oriented box on y.
	local size, cf = pad.Size, pad.CFrame
	local halfY = (math.abs(cf.XVector.Y) * size.X + math.abs(cf.YVector.Y) * size.Y + math.abs(cf.ZVector.Y) * size.Z) / 2
	view.Anchor.WorldCFrame = CFrame.new(pad.Position.X, pad.Position.Y + halfY + up, pad.Position.Z)
end

-- Is something covering the card, or is the character not fit to use it?
local function blocked(): boolean
	if UIKit.IsOverlayOpen() then
		return true
	end
	local ragdolled = localPlayer:GetAttribute("RagdollUntil")
	if typeof(ragdolled) == "number" and ragdolled > Workspace:GetServerTimeNow() then
		return true
	end
	return localPlayer:GetAttribute("HeistTier") ~= nil -- carrying a stolen orb
end

-- Why the card is held shut right now (nil = nothing blocks it), for
-- /selftest: the overlays up, a ragdoll, a carried orb.
function GachaBoardController.GetBlockReason(): string?
	local reasons: { string } = {}
	local overlays = UIKit.GetOpenOverlays()
	if #overlays > 0 then
		table.insert(reasons, "overlays " .. table.concat(overlays, ","))
	end
	local ragdolled = localPlayer:GetAttribute("RagdollUntil")
	if typeof(ragdolled) == "number" and ragdolled > Workspace:GetServerTimeNow() then
		table.insert(reasons, "ragdolled")
	end
	if localPlayer:GetAttribute("HeistTier") ~= nil then
		table.insert(reasons, "carrying")
	end
	return if #reasons > 0 then table.concat(reasons, "; ") else nil
end

-- Why the card is (not) up, as one line for /selftest's FAIL detail: the
-- block reason, Near / Open, how far the character stands from the pad, the
-- pop state (PopRoot, PopScale), the phone UIScale and the billboard's
-- SizeOffset. A shut card names its cause instead of just "not open".
function GachaBoardController.DescribeState(): string
	local view = card
	if not view then
		return "no card"
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local distance = if root and root:IsA("BasePart") then (root.Position - view.Pad.Position).Magnitude else -1
	local phoneScale = view.Root:FindFirstChild("PhoneScale")
	return ("block %s, Near %s, Open %s, %.1f studs from the pad, PopRoot.Visible %s, PopScale %.3f, PhoneScale %s, SizeOffset %s"):format(
		tostring(GachaBoardController.GetBlockReason()),
		tostring(view.Near),
		tostring(view.Open),
		distance,
		tostring(view.PopRoot.Visible),
		view.Pop.Scale,
		if phoneScale and phoneScale:IsA("UIScale") then ("%.4f"):format(phoneScale.Scale) else "none",
		tostring(view.Billboard.SizeOffset)
	)
end

local function buildCard(pad: BasePart)
	local anchor = Instance.new("Attachment")
	anchor.Name = "GachaCardAnchor"
	anchor.Parent = pad

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GachaCard"
	billboard.Adornee = anchor
	billboard.StudsOffset = Vector3.new(0, 0, 2) -- camera-relative +Z = toward the camera: in front of the ball (radius 1.3)
	billboard.StudsOffsetWorldSpace = Vector3.zero
	billboard.Size = UDim2.fromOffset(FULL_SIZE.X, FULL_SIZE.Y)
	billboard.SizeOffset = Vector2.new(0, 0.5) -- grows upward: the bottom edge (the key bar's) is on the anchor
	billboard.MaxDistance = G.MaxDistance
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Active = true
	billboard.ClipsDescendants = false
	billboard.Enabled = true -- layout is always computed; closed = PopRoot hidden

	-- Bottom-centre anchored, so the phone scale and the pop scale work about the card's bottom line.
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.fromScale(0.5, 1)
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = billboard

	local popRoot = Instance.new("Frame")
	popRoot.Name = "PopRoot"
	popRoot.BackgroundTransparency = 1
	popRoot.AnchorPoint = Vector2.new(0.5, 1)
	popRoot.Position = UDim2.fromScale(0.5, 1)
	popRoot.Size = UDim2.fromScale(1, 1)
	popRoot.Visible = false
	popRoot.Parent = root
	local pop = Instance.new("UIScale")
	pop.Name = "PopScale"
	pop.Scale = G.PopFromScale
	pop.Parent = popRoot

	-- The card: fixed pixels, white paper, 18 px corners, below the title/(i) room.
	local cardFrame = Instance.new("Frame")
	cardFrame.Name = "Card"
	cardFrame.BackgroundColor3 = Colors.White -- the paper gradient colours it
	cardFrame.BorderSizePixel = 0
	cardFrame.Position = UDim2.fromOffset(0, TOP_PAD)
	cardFrame.Size = UDim2.fromOffset(CARD.X, CARD.Y)
	cardFrame.Parent = popRoot
	UIKit.Corner(cardFrame, 18)

	table.clear(buttons)
	local keyBar = buildKeyBar(popRoot)

	local view = {
		Billboard = billboard,
		Anchor = anchor,
		Pad = pad,
		Root = root,
		PopRoot = popRoot,
		Pop = pop,
		Card = cardFrame,
		KeyBar = keyBar,
		Tiles = {},
		MutationLine = nil :: any,
		Phone = false,
		Title = nil :: any,
		Pills = nil :: any,
		EventRow = nil :: any,
		PriceRow = nil :: any,
		InfoHit = nil :: any,
		InfoMark = nil :: any,
		LuckPill = nil :: any,
		EventPill = nil :: any,
		Price = nil :: any,
		Signature = "",
		Label = pad:FindFirstChild("GachaLabel"),
		Near = false,
		Open = false,
		Tween = nil,
		UpStuds = G.AnchorUpStuds,
		VipTag = nil,
	} :: CardView
	buildContent(view, cardFrame)
	updateContent(view)
	refreshButtons()
	applyPhoneScale(view)
	setUpStuds(view, G.AnchorUpStuds)
	card = view
	billboard.Parent = localPlayer:WaitForChild("PlayerGui")
	pad.Destroying:Connect(function()
		if card == view then
			hideVipTag(view, false)
			hideBall(view, false)
			card = nil
			unbindKeys()
		end
		billboard:Destroy()
		anchor:Destroy()
	end)
end

-- Your pad: Workspace.Plots[your plot].GachaStation.Pad (it exists once the lab is claimed).
-- Also keeps the station's own prompts OFF on this client (the server turns
-- them off; this makes sure nothing turns them back on and draws a default prompt).
-- (The H "How it works" next to the LOCK console is the LOCK console's own.)
local function keepPromptsOff(station: Instance)
	for _, descendant in station:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and (descendant.Name == "PullPrompt" or descendant.Name == "Pull10Prompt" or descendant.Name == "HelpPrompt") then
			local prompt = descendant
			prompt.Enabled = false
			if not prompt:GetAttribute("GachaKeptOff") then
				prompt:SetAttribute("GachaKeptOff", true)
				prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
					if prompt.Enabled then
						prompt.Enabled = false
					end
				end)
			end
		end
	end
end

local function findOwnPad(): BasePart?
	local plots = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	local plot = plots and plots:FindFirstChild(PlotNaming.GetPlotName(localPlayer.UserId))
	local station = plot and plot:FindFirstChild("GachaStation")
	local pad = station and station:FindFirstChild("Pad")
	if station and pad and pad:IsA("BasePart") then
		keepPromptsOff(station)
		return pad
	end
	return nil
end

--[[ Per frame ------------------------------------------------------------------------- ]]

-- Distance hysteresis (Near), then Open = Near and not covered / ragdolled /
-- carrying; and, while up, the shimmer and the zoom check. The card is
-- adorned to the pad: it never follows the camera.
-- Pure: how many px the card slides so its top starts StackGapPx under the
-- stack. `anchorY` is the anchor's screen y (the card's bottom edge),
-- `cardHeight` the card as drawn (phone scale included), `stackBottom` the
-- bottom of TopStack in screen px, `viewHeight` the screen's. Positive =
-- down. Without `floor` it is one-sided: 0 when the card already clears, else
-- down by the shortfall, never more than the room left under the anchor, so
-- the key bar stays on screen (pass the floor as `viewHeight` to cap the slide
-- there). `gap` is the air under the stack (default G.StackGapPx; the phone
-- passes G.PhoneTopGapPx). With `floor` (screen px; the phone: the weapon
-- bar's top, else the bottom row's) it is two-sided: the card's top is
-- clamp(natural top, minTop, floor - cardHeight), so it also slides UP (a
-- negative result) when the card's bottom would pass the floor; only when the
-- card is taller than the band does the top win. /selftest runs it at
-- 1920 x 1080, 1366 x 768, 844 x 390 and 896 x 414.
function GachaBoardController.StackShiftFor(
	anchorY: number,
	cardHeight: number,
	stackBottom: number,
	viewHeight: number,
	gap: number?,
	floor: number?
): number
	local minTop = math.ceil(stackBottom) + (gap or G.StackGapPx)
	local top = anchorY - cardHeight
	if floor then
		local maxTop = floor - cardHeight
		if maxTop < minTop then
			return minTop - top -- taller than the band: the top wins
		end
		return math.clamp(top, minTop, maxTop) - top
	end
	if top >= minTop then
		return 0
	end
	return math.clamp(minTop - top, 0, math.max(0, viewHeight - anchorY))
end

-- The bottom of TopStack's STABLE rows (chip row) in screen px; its y is
-- logical: x the phone's 0.8. Never the toast-inclusive GetBottom.
local function stackBottomPx(): number
	return TopStack.GetStableBottom() * (if UIKit.IsPhone() then UITheme.PhoneScale else 1)
end

-- The card as drawn: the billboard's height x the phone's scale.
local function drawnHeight(view: CardView): number
	local scale = view.Root:FindFirstChild("PhoneScale")
	return view.Billboard.Size.Y.Offset * (if scale and scale:IsA("UIScale") then scale.Scale else 1)
end

-- Screen y of the card's bottom edge: the anchor plus the billboard's
-- camera-space StudsOffset (2 studs toward the camera), nil behind the camera.
local function anchorScreenY(view: CardView, camera: Camera): number?
	local world = view.Anchor.WorldPosition + camera.CFrame:VectorToWorldSpace(view.Billboard.StudsOffset)
	local point = camera:WorldToViewportPoint(world)
	if point.Z <= 0 then
		return nil
	end
	return point.Y
end

-- Screen y of the phone's floor: the weapon bar's top while it shows, else the
-- HUD's bottom row's top (the card never goes below it).
local function phoneFloorPx(camera: Camera): number
	local bar = (require(script.Parent.CombatController) :: any).GetBarRect()
	if bar then
		return bar.Position.Y
	end
	return camera.ViewportSize.Y - UIKit.GetCardBottomFor(true) * UITheme.PhoneScale
end

-- Pure: the phone card's (UIScale, slide px) for an anchor at screen y
-- `anchorY` (the card's bottom edge), the `baseScale` PhoneScaleFor gave, the
-- STABLE stack bottom and the floor (screen px). The band is minTop (ceil of
-- the stack bottom + G.PhoneTopGapPx) down to the floor (the weapon bar's top,
-- else the bottom row's, never past the screen). The card slides DOWN or UP
-- (a negative slide) to sit inside it (StackShiftFor, two-sided); if it is
-- taller than the band the UIScale drops (down to G.PhoneScaleMin) until it
-- fits; at the minimum the top wins. /selftest runs it at 844 x 390 and
-- 896 x 414.
function GachaBoardController.PhonePlanFor(anchorY: number, baseScale: number, stackBottom: number, floorPx: number, viewHeight: number): (number, number)
	local full = GachaBoardController.PhoneFullHeight
	local minTop = math.ceil(stackBottom) + G.PhoneTopGapPx
	local floor = math.min(floorPx, viewHeight)
	local scale = baseScale
	if full * scale > floor - minTop then
		-- Rounded DOWN (4 decimals) so the fitted card never ends a hair past the floor.
		local fit = math.floor((floor - minTop) / full * 10000) / 10000
		scale = math.clamp(fit, G.PhoneScaleMin, baseScale)
	end
	return scale, GachaBoardController.StackShiftFor(anchorY, full * scale, stackBottom, viewHeight, G.PhoneTopGapPx, floor)
end

-- What the last clamp used and wrote, for /selftest's FAIL detail and the
-- debug print (SetClampDebug): the numbers behind a card that is not where the
-- rule says. `Frame` is the clamp's own counter (a stale trace means the clamp
-- stopped running).
local clampTrace = {
	Frame = 0,
	StackBottom = 0,
	MinTop = 0,
	AnchorY = 0,
	DrawnHeight = 0,
	Shift = 0,
	SizeOffsetY = 0.5,
	Top = 0,
}
local clampDebug = false

-- Debug print of the clamp's numbers (the selftest turns it on around its
-- gacha probe; off otherwise).
function GachaBoardController.SetClampDebug(on: boolean)
	clampDebug = on
end

function GachaBoardController.IsClampDebug(): boolean
	return clampDebug
end

-- The last clamp's numbers as one line ("clamp #N: stack ..., minTop ...").
function GachaBoardController.GetClampTrace(): string
	local t = clampTrace
	return ("clamp #%d: stackBottom %.1f minTop %.1f anchorY %.1f drawnHeight %.1f shift %.2f SizeOffset.Y %.4f top %.1f"):format(
		t.Frame,
		t.StackBottom,
		t.MinTop,
		t.AnchorY,
		t.DrawnHeight,
		t.Shift,
		t.SizeOffsetY,
		t.Top
	)
end

-- Every frame while the card is up: slide it (SizeOffset.Y, a fraction of its
-- own height) so its top starts under the event chip row: down when it would
-- sit under it. The phone is two-sided and also lowers its UIScale when the
-- band is too short (PhonePlanFor): the card never leaves the band between the
-- chip row and the weapon bar. The STABLE bottom is used, so a toast never
-- moves the card. The anchor, the studs offsets and SizeOffset.X are never
-- touched.
local function clampToStack(view: CardView)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local shift = 0
	local anchorY = anchorScreenY(view, camera)
	local stackBottom = stackBottomPx()
	if anchorY then
		if UIKit.IsPhone() then
			local base = GachaBoardController.PhoneScaleFor(UIKit.GetLogicalViewport())
			local scale: number
			scale, shift = GachaBoardController.PhonePlanFor(anchorY, base, stackBottom, phoneFloorPx(camera), camera.ViewportSize.Y)
			local gui = view.Root:FindFirstChild("PhoneScale")
			if gui and gui:IsA("UIScale") and math.abs(gui.Scale - scale) > 0.0005 then
				gui.Scale = scale
			end
		else
			shift = GachaBoardController.StackShiftFor(anchorY, drawnHeight(view), stackBottom, camera.ViewportSize.Y)
		end
	end
	local current = view.Billboard.SizeOffset
	local fullHeight = view.Billboard.Size.Y.Offset
	local want = Vector2.new(current.X, 0.5 - shift / math.max(fullHeight, 1))
	if (current - want).Magnitude > 0.0005 then
		view.Billboard.SizeOffset = want
	end
	local height = drawnHeight(view)
	clampTrace.Frame += 1
	clampTrace.StackBottom = stackBottom
	clampTrace.MinTop = math.ceil(stackBottom) + (if UIKit.IsPhone() then G.PhoneTopGapPx else G.StackGapPx)
	clampTrace.AnchorY = anchorY or -1
	clampTrace.DrawnHeight = height
	clampTrace.Shift = shift
	clampTrace.SizeOffsetY = view.Billboard.SizeOffset.Y
	clampTrace.Top = if anchorY then anchorY - height + (0.5 - view.Billboard.SizeOffset.Y) * fullHeight else -1
	if clampDebug and clampTrace.Frame % 30 == 0 then
		print("[GachaCard] " .. GachaBoardController.GetClampTrace())
	end
end

-- The card's top and bottom on screen as it is drawn right now (anchor
-- projection, less the card's height, plus the slide), and its UIScale (1 on
-- a desktop), for /selftest.
function GachaBoardController.GetDrawnRect(): (number?, number?, number?)
	local view = card
	local camera = Workspace.CurrentCamera
	if not view or not camera then
		return nil, nil, nil
	end
	local anchorY = anchorScreenY(view, camera)
	if not anchorY then
		return nil, nil, nil
	end
	local slide = (0.5 - view.Billboard.SizeOffset.Y) * view.Billboard.Size.Y.Offset
	local height = drawnHeight(view)
	return anchorY - height + slide, anchorY + slide, height / math.max(view.Billboard.Size.Y.Offset, 1)
end

-- The anchor's screen y right now (the card's bottom edge before the slide),
-- for /selftest: the card's top is anchorY - height + slide, so a camera that
-- drifts between two samples moves the top without the card being moved.
function GachaBoardController.GetDrawnAnchorY(): number?
	local view = card
	local camera = Workspace.CurrentCamera
	if not view or not camera then
		return nil
	end
	return anchorScreenY(view, camera)
end

function GachaBoardController.GetDrawnTop(): number?
	local top = GachaBoardController.GetDrawnRect()
	return top
end

-- The phone's floor in screen px (weapon bar top, else the HUD row's top).
function GachaBoardController.GetPhoneFloorPx(): number?
	local camera = Workspace.CurrentCamera
	return if camera then phoneFloorPx(camera) else nil
end

local function stepFrame()
	local view = card
	if not view or not view.Pad.Parent then
		return
	end
	-- Distance from YOUR CHARACTER to the pad, never the camera's.
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local distance = (root.Position - view.Pad.Position).Magnitude
		if not view.Near and distance < G.PopInStuds then
			view.Near = true
		elseif view.Near and distance > G.PopOutStuds then
			view.Near = false
		end
	end
	local want = view.Near and not blocked()
	if want and not view.Open then
		popIn(view)
	elseif not want and view.Open then
		popOut(view)
	end
	if view.PopRoot.Visible then
		clampToStack(view)
	end
end

local function refresh()
	local view = card
	if not view then
		local pad = findOwnPad()
		if pad then
			buildCard(pad)
		end
		return
	end
	if not view.Pad.Parent then
		return
	end
	if not view.Label or not view.Label.Parent then
		view.Label = view.Pad:FindFirstChild("GachaLabel")
	end
	if view.Open then
		hideVipTag(view, true) -- enforce every step: anything that re-enables the chip (or a respawn's new one) is undone
	end
	if view.Open then
		hideBall(view, true) -- the pad's parts can stream back in
	end
	if view.PopRoot.Visible or view.Near then
		setLabelEnabled(view, false) -- the card is up (or about to be): no small label under it
	else
		setLabelEnabled(view, true)
	end
	if signatureOf() ~= view.Signature then
		updateContent(view)
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

-- Your card (nil before your pad exists): the gui, its pieces, and the
-- state the pop logic is in. Every UI check reads the instance tree from
-- Gui down.
function GachaBoardController.GetCard(): { Billboard: BillboardGui, Anchor: Attachment, Pad: BasePart, Root: Frame, PopRoot: Frame, Card: Frame, Pop: UIScale, Open: boolean, Shown: boolean, Label: Instance?, UpStuds: number, VipHidden: boolean, Tiles: { [string]: TileView }, MutationLine: TextLabel, InfoHit: TextButton, Phone: boolean }?
	local view = card
	if not view then
		return nil
	end
	if not view.Label or not view.Label.Parent then
		view.Label = view.Pad:FindFirstChild("GachaLabel")
	end
	return {
		Billboard = view.Billboard,
		Pad = view.Pad,
		Root = view.Root,
		PopRoot = view.PopRoot,
		Card = view.Card,
		Pop = view.Pop,
		Open = view.Open,
		Shown = view.PopRoot.Visible,
		Label = view.Label,
		Anchor = view.Anchor,
		UpStuds = view.UpStuds,
		VipHidden = view.VipTag ~= nil,
		Tiles = view.Tiles,
		MutationLine = view.MutationLine,
		InfoHit = view.InfoHit,
		Phone = view.Phone,
	}
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
				ToastController.Show(("Auto stopped: need %s for 10 pulls"):format(NumberFormat.Money(payload.Cost)), "Neutral")
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
	-- Luck also changes without a sync: an event starting or ending, the
	-- admin luck boost. The card and the (i) panel redraw at once, not at
	-- the next 0.5 s poll.
	for _, name in { "AdminLuck", "AdminLuckUntil", "EventId", "EventEndsAt" } do
		Workspace:GetAttributeChangedSignal(name):Connect(refresh)
	end
	RunService.RenderStepped:Connect(stepFrame)
	-- The phone's 0.8 follows the HUD layout; the anchor itself never changes.
	local function rescale()
		if card then
			applyPhoneScale(card)
		end
	end
	UIKit.LayoutChanged:Connect(rescale)
	-- The phone's card scale follows the viewport (a rotation, a resize).
	local function watchViewport()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
		end
		rescale()
	end
	watchViewport()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
end

return GachaBoardController
