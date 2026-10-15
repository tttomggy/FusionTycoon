--!strict
--[[
	GachaBoardController
	--------------------
	The Gacha odds CARD: a pixel-sized BillboardGui ADORNED TO YOUR GACHA PAD,
	floating right over it and opening as you walk up, like a Pet Simulator 99
	egg card. A 300 x 204 px card plus a 72 px E / R / T row, the same size
	at any zoom (0.8 on a phone via one UIScale). This is the final
	placement: not docked, not following the camera.

	Why the earlier in-world tries failed: they were sized in studs (huge up
	close) and sat "above your head" while you stand ON the pad (off the top
	of the screen). Fix: pixel size, anchored to the PAD, not the player. You
	pull with E / R / T from PromptDistance + 3 studs, so you stop in front of
	the pad and see the card over it.

	  * BillboardGui: Adornee = the pad, Size = (300, 276) px, SizeOffset
	    (0, 0.5) so it grows UPWARD from the anchor (its bottom edge, the key
	    bar's, is on the anchor), StudsOffsetWorldSpace (0, pad half-height +
	    UpStuds, 0) with UpStuds = 3 (just above the floating capsule orb), centred on the
	    pad, no backward shift. AlwaysOnTop false, LightInfluence 0,
	    MaxDistance 150, ResetOnSpawn false. No CanvasGroup.
	  * Pop: in at PopInStuds (16) from your character to the pad, out at
	    PopOutStuds (19); one UIScale 0.85 -> 1 over 0.12 s (Quad).
	  * While it is open it hides what it would cover: the pad's small GACHA /
	    price label and your VIP head chip (restored on close). The pad's own
	    prompts stay off.
	  * Standing on the pad with a close camera the top could clip. Guard
	    (FitAnchor): on open, on a viewport / layout change and when the zoom
	    (camera to character) changes by more than 2 studs (never per frame,
	    never from a yaw), the card's top is projected; if it would be above
	    TopStack.GetBottom() + 8 the anchor is LOWERED (never raised above 3
	    studs) down to a floor of pad top + 0.5. Turning the camera never moves
	    it.
	  * Hidden (with the pop) while any overlay (modal / big card) is open,
	    during a ragdoll and while carrying, and back after.
	  * Built ONCE, hidden, as soon as your pad exists. A refresh only updates
	    text and colours (the %s, each tier's lock state, luck, the event, the
	    chips, the price), never rebuilds. 2D orbs (UIKit.TierOrb), no
	    ViewportFrame, no CanvasGroup, no TextScaled. One UIScale for the pop
	    (PopScale) plus the phone's PhoneScale (0.8) when UIKit.IsPhone().

	The card (design px): a dark violet panel with a 3 px gold stroke, a
	header (GACHA PAD, the luck pill when luck > x1, the event chip, an (i)),
	six tier tiles 3 x 2 (tier gradient, a 2D orb, the % in white with a
	tier-colour stroke, the tier name; Secret has an animated rainbow
	stroke), the mutation chips at the bottom left and the gold price pill at
	the bottom right. A tier you never found is a black orb with "?" and
	STILL shows its %.

	THE KEY BAR under the card: [E] Pull . $285, [R] x10 . $3.5K, [T] Auto .
	OFF / ON, round 56 px buttons (>= 44 px even at the phone's 0.8). It does
	NOT use ProximityPrompt UI: the pad's prompts are off (this controller also
	keeps them off on this client). While the card is open E / R / T (X / Y / RB
	on a controller) are bound with ContextActionService, and unbound when it
	closes; the keys and the buttons send RequestGachaPull { Count = 1 | 10 }
	and SetAutoPull { On }; the server runs the one shared pull function.
	Desktop shows the key caps, a controller its glyphs, touch words. T shows
	ON in green while Auto pull runs; the server's AutoPullState says when and
	why it stopped (a toast).

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
local GuiService = game:GetService("GuiService")
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
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TycoonController = require(script.Parent.TycoonController)
local TopStack = require(script.Parent.Parent.UI.TopStack)
local ToastController = require(script.Parent.ToastController)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local GachaBoardController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local G = PlotLayout.Gacha
local CARD = G.CardPx -- 300 x 204
local ROW_HEIGHT = G.ButtonRowPx
local FULL_SIZE = Vector2.new(CARD.X, CARD.Y + ROW_HEIGHT) -- the card + the key bar
local MARGIN = 12
local HEADER_Y = 6
local HEADER_HEIGHT = 28
local TILE_SIZE = Vector2.new(88, 58)
local TILE_GAP = 6
local TILES_Y = 38
local ORB_SIZE = 26
local CHIP_HEIGHT = 16
local CHIPS_Y = 174
local CHIPS_WIDTH = 190
local PRICE_HEIGHT = 28
local BUTTON_SIZE = 56
local BUTTON_SPACING = 92
local KEY_BAR_GAP = 4
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

type TileView = {
	Frame: Frame,
	Orb: Frame, -- the 2D tier orb (hidden for a never-found tier)
	Silhouette: Frame, -- the black orb (shown for a never-found tier)
	Percent: TextLabel,
}

type CardView = {
	Billboard: BillboardGui,
	Pad: BasePart,
	Root: Frame, -- bottom-centre anchored; carries the phone's UIScale
	PopRoot: Frame, -- everything; hidden = the card is closed
	Pop: UIScale, -- the pop-in / pop-out scale
	Card: Frame, -- the 300 x 204 card
	KeyBar: Frame, -- the E / R / T row under the card
	Tiles: { [string]: TileView },
	Chips: { [string]: Frame }, -- one per mutation, shown while it has a pull chance
	LuckPill: TextLabel,
	EventPill: TextLabel,
	Price: TextLabel,
	Shimmer: UIGradient?,
	Sparkle: TextLabel?,
	Signature: string,
	Label: Instance?, -- the small server GachaLabel
	Near: boolean, -- the character is close (the open side of the distance hysteresis)
	Open: boolean, -- the card is up (near AND nothing is covering it)
	Tween: Tween?,
	UpStuds: number, -- the anchor above the pad's top (3, lowered only if the top would clip)
	ZoomAt: number, -- the camera-to-character distance the anchor was last fitted at
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
	return NumberFormat.Money(inputs.Cost)
end

local function luckText(luck: number): string
	return ("🍀 Luck ×%s"):format(NumberFormat.Multiplier(luck):sub(2))
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

-- One tier tile (88 x 58): the tier gradient, a 2D orb on top (or the black
-- "?" orb), the % in white with a tier-colour stroke, the name ribbon.
-- Built once; updateTile sets the text and the lock state.
local function buildTile(view: CardView, parent: Instance, tier: string): TileView
	local accent = FusionConfig.TierAccentColors[tier] or Colors.Text
	local stops = UITheme.GetTierOrb(tier)
	local tile = Instance.new("Frame")
	tile.Name = "Tile_" .. tier
	tile.BackgroundColor3 = Colors.White
	tile.BorderSizePixel = 0
	tile.Size = UDim2.fromOffset(TILE_SIZE.X, TILE_SIZE.Y)
	tile:SetAttribute("Tier", tier)
	UIKit.Corner(tile, 10)
	-- From the tier colour down to dark.
	UIKit.PairGradient(tile, { Top = stops.Mid, Bottom = stops.Dark })
	local stroke = UIKit.Stroke(tile, 2, Colors.White)
	if tier == "Secret" then
		-- An animated rainbow stroke (rotated each frame while open) and a sparkle.
		local gradient = Instance.new("UIGradient")
		gradient.Color = UITheme.GetRainbowSequence()
		gradient.Parent = stroke
		view.Shimmer = gradient
		view.Sparkle = label(tile, {
			Name = "Sparkle",
			Text = "✦",
			Font = Fonts.Display,
			TextSize = 12,
			TextColor3 = Colors.White,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -3, 0, 1),
			Size = UDim2.fromOffset(14, 14),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 5,
		})
	end

	local orb = UIKit.TierOrb(tier, ORB_SIZE)
	orb.Name = "Orb"
	orb.AnchorPoint = Vector2.new(0.5, 0)
	orb.Position = UDim2.new(0.5, 0, 0, 3)
	orb.Parent = tile

	-- The never-found tier: a black orb with "?" (its % still shows).
	local silhouette = frame(tile, "Silhouette", UDim2.new(0.5, -ORB_SIZE / 2, 0, 3), UDim2.fromOffset(ORB_SIZE, ORB_SIZE), Colors.Black)
	UIKit.Corner(silhouette, 999)
	UIKit.Stroke(silhouette, 2, Colors.Faint)
	silhouette.Visible = false
	label(silhouette, {
		Name = "Mark",
		Text = "?",
		Font = Fonts.Display,
		TextSize = 18,
		TextColor3 = Colors.Muted,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})

	local percent = label(tile, {
		Name = "Percent",
		Text = "",
		Font = Fonts.Display,
		TextSize = 18,
		TextColor3 = Colors.White,
		Position = UDim2.fromOffset(2, 30),
		Size = UDim2.new(1, -4, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local percentStroke = UIKit.TextStroke(percent, 3)
	percentStroke.Color = accent

	-- The tier-name ribbon along the bottom.
	local ribbon = frame(tile, "Ribbon", UDim2.new(0, 0, 1, -12), UDim2.new(1, 0, 0, 12), Colors.Ink)
	ribbon.BackgroundTransparency = 0.3
	UIKit.Corner(ribbon, 6)
	label(ribbon, {
		Name = "TierName",
		Text = tier:upper(),
		Font = Fonts.BodyHeavy,
		TextSize = 9,
		TextColor3 = Colors.White,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	tile.Parent = parent
	return { Frame = tile, Orb = orb, Silhouette = silhouette, Percent = percent }
end

-- A mutation chip (16 px tall): "✨13.8%" on Ink with a mutation-colour stroke.
local function buildChip(parent: Instance, mutation: string): Frame
	local color = UITheme.GetMutationColor(mutation) or Colors.Text
	local chip = Instance.new("Frame")
	chip.Name = "Chip_" .. mutation
	chip.BackgroundColor3 = Colors.Ink
	chip.BorderSizePixel = 0
	chip.Size = UDim2.fromOffset(58, CHIP_HEIGHT)
	chip.Visible = false
	UIKit.Corner(chip, 999)
	UIKit.Stroke(chip, 1.5, color)
	label(chip, {
		Name = "Text",
		Text = "",
		Font = Fonts.BodyHeavy,
		TextSize = 10,
		TextColor3 = Colors.White,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	chip.Parent = parent
	return chip
end

-- Builds every piece of the card's face ONCE (hidden). updateContent sets
-- the text and colours; nothing is ever rebuilt.
local function buildContent(view: CardView, card: Frame)
	-- Dark violet glass with a 3 px gold stroke.
	local gold = UIKit.Stroke(card, 3, UITheme.Gradients.Gold.Top)
	local goldGradient = Instance.new("UIGradient")
	goldGradient.Color = ColorSequence.new(UITheme.Gradients.Gold.Top, UITheme.Gradients.Gold.Bottom)
	goldGradient.Rotation = 90
	goldGradient.Parent = gold

	-- Header: the title on the left; the event chip, the luck pill and (i) on the right.
	local header = frame(card, "Header", UDim2.fromOffset(MARGIN, HEADER_Y), UDim2.fromOffset(CARD.X - MARGIN * 2, HEADER_HEIGHT))
	local title = label(header, {
		Name = "Title",
		Text = "🔮 GACHA PAD",
		Font = Fonts.Display,
		TextSize = 16,
		TextColor3 = Colors.White,
		Size = UDim2.new(0, 112, 1, 0),
		Stroke = 3,
	})
	title.TextXAlignment = Enum.TextXAlignment.Left
	local pills = frame(header, "Pills", UDim2.new(0, 112, 0, 0), UDim2.new(1, -112 - 34, 1, 0))
	local pillLayout = Instance.new("UIListLayout")
	pillLayout.FillDirection = Enum.FillDirection.Horizontal
	pillLayout.Padding = UDim.new(0, 4)
	pillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	pillLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pillLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pillLayout.Parent = pills
	view.EventPill = UIKit.Pill({ Name = "EventChip", Parent = pills, Text = "", Gradient = UITheme.Gradients.Violet, TextSize = 10, Height = 18, LayoutOrder = 1 })
	view.LuckPill = UIKit.Pill({ Name = "LuckPill", Parent = pills, Text = "", Gradient = UITheme.Gradients.Green, TextSize = 11, Height = 18, LayoutOrder = 2 })
	UIKit.SetPillVisible(view.EventPill, false)
	UIKit.SetPillVisible(view.LuckPill, false)
	-- The (i): a 26 px button with a 44 px hit area.
	UIKit.Button({
		Name = "Info",
		Parent = header,
		Style = "Violet",
		Text = "i",
		TextSize = 16,
		Radius = 999,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
	})
	local infoHit = Instance.new("TextButton")
	infoHit.Name = "InfoHit"
	infoHit.AnchorPoint = Vector2.new(1, 0.5)
	infoHit.Position = UDim2.new(1, 9, 0.5, 0)
	infoHit.Size = UDim2.fromOffset(44, 44)
	infoHit.BackgroundTransparency = 1
	infoHit.Text = ""
	infoHit.ZIndex = 10
	infoHit.Parent = header
	infoHit.Activated:Connect(function()
		GachaBoardController.OpenPanel()
	end)

	-- Six tiles, 3 x 2, centred.
	local tilesWidth = TILE_SIZE.X * 3 + TILE_GAP * 2
	local tiles = frame(card, "Tiles", UDim2.new(0.5, -tilesWidth / 2, 0, TILES_Y), UDim2.fromOffset(tilesWidth, TILE_SIZE.Y * 2 + TILE_GAP))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(TILE_SIZE.X, TILE_SIZE.Y)
	grid.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = tiles
	for index, tier in FusionConfig.TierOrder do
		local tile = buildTile(view, tiles, tier)
		tile.Frame.LayoutOrder = index
		view.Tiles[tier] = tile
	end

	-- Mutation chips, bottom left (one per mutation; the ones with a pull chance show).
	local chips = frame(card, "Mutations", UDim2.fromOffset(MARGIN, CHIPS_Y), UDim2.fromOffset(CHIPS_WIDTH, CHIP_HEIGHT))
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, 4)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chips
	for index, mutation in MutationConfig.Order do
		local chip = buildChip(chips, mutation)
		chip.LayoutOrder = index
		view.Chips[mutation] = chip
	end

	-- The gold price pill, bottom right.
	view.Price = UIKit.Pill({
		Name = "Price",
		Parent = card,
		Text = "",
		Gradient = UITheme.Gradients.Gold,
		Font = Fonts.Display,
		TextSize = 16,
		Height = PRICE_HEIGHT,
		StrokeThickness = 2,
		TextStroke = 2,
	})
	local priceRoot = UIKit.PillRoot(view.Price)
	priceRoot.AnchorPoint = Vector2.new(1, 0.5)
	priceRoot.Position = UDim2.new(1, -MARGIN, 0, CHIPS_Y + CHIP_HEIGHT / 2)
end

-- Sets the text and colours from the odds, luck, event, Index and price.
-- Never creates or destroys anything.
local function updateContent(view: CardView)
	local inputs = currentInputs()
	local rows = currentRows(inputs.Luck)
	local found = foundTiers()
	for _, row in rows.Tiers do
		local tile = view.Tiles[row.Tier]
		if tile then
			tile.Percent.Text = row.Text
			local length = #row.Text
			tile.Percent.TextSize = if length <= 5 then 18 elseif length == 6 then 16 else 14
			local isFound = found[row.Tier] == true
			tile.Orb.Visible = isFound
			tile.Silhouette.Visible = not isFound
			tile.Frame:SetAttribute("PercentValue", row.Rate * 100)
			tile.Frame:SetAttribute("Silhouette", not isFound)
		end
	end
	-- Mutation chips: the ones with a pull chance, narrower when there are many.
	local shown = 0
	for _, row in rows.Mutations do
		if view.Chips[row.Mutation] then
			shown += 1
		end
	end
	local chipWidth = math.min(60, math.floor((CHIPS_WIDTH - 4 * math.max(shown - 1, 0)) / math.max(shown, 1)))
	local chipByMutation: { [string]: FusionConfig.GachaMutationOdds } = {}
	for _, row in rows.Mutations do
		chipByMutation[row.Mutation] = row
	end
	for mutation, chip in view.Chips do
		local row = chipByMutation[mutation]
		chip.Visible = row ~= nil
		if row then
			chip.Size = UDim2.fromOffset(chipWidth, CHIP_HEIGHT)
			local text = chip:FindFirstChild("Text") :: TextLabel
			text.Text = ("%s%s"):format(MUTATION_ICONS[mutation] or "", row.Text)
		end
	end
	view.Price.Text = priceText(inputs)
	view.LuckPill.Text = luckText(inputs.Luck)
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
	row.Position = UDim2.fromOffset(0, CARD.Y + KEY_BAR_GAP)
	row.Size = UDim2.fromOffset(CARD.X, ROW_HEIGHT - KEY_BAR_GAP)
	row.Parent = root
	for index, spec in KEYS do
		local holder = Instance.new("Frame")
		holder.Name = spec.Id .. "Key"
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.new(0.5, (index - 2) * BUTTON_SPACING, 0, 0)
		holder.Size = UDim2.fromOffset(BUTTON_SPACING - 2, ROW_HEIGHT - KEY_BAR_GAP)
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
			TextSize = 24,
			TextColor3 = Colors.White,
			Stroke = UITheme.Stroke.Text,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = body.ZIndex + 2,
		})
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
			TextSize = 11,
			Stroke = UITheme.Stroke.Text,
			Position = UDim2.fromOffset(0, BUTTON_SIZE + 1),
			Size = UDim2.new(1, 0, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		buttons[spec.Id] = { Holder = holder, Button = body, Circle = circle, Glyph = glyph, Caption = caption }
	end
	return row
end

--[[ The card (a screen-space gui docked on the right) --------------------------------- ]]

local function setLabelEnabled(view: CardView, enabled: boolean)
	local label = view.Label
	if label and label.Parent and label:IsA("BillboardGui") then
		label.Enabled = enabled
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
	GachaBoardController.FitAnchor()
	view.PopRoot.Visible = true
	setLabelEnabled(view, false)
	hideVipTag(view, true)
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

-- The phone's sizing UIScale (0.8), set once and on LayoutChanged. Scaled
-- about the card's bottom line, so the anchor does not move.
local function applyPhoneScale(view: CardView)
	local existing = view.Root:FindFirstChild("PhoneScale")
	if UIKit.IsPhone() then
		if not existing then
			local scale = Instance.new("UIScale")
			scale.Name = "PhoneScale"
			scale.Scale = UITheme.PhoneScale
			scale.Parent = view.Root
		end
	elseif existing then
		existing:Destroy()
	end
end

local function setUpStuds(view: CardView, up: number)
	view.UpStuds = up
	-- World space (StudsOffset is camera-relative and would swing with the view).
	view.Billboard.StudsOffsetWorldSpace = Vector3.new(0, view.Pad.Size.Y / 2 + up, 0)
end

-- Camera to character: the zoom, which does not change when the camera turns.
local function zoomDistance(): number?
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if camera and root and root:IsA("BasePart") then
		return (camera.CFrame.Position - root.Position).Magnitude
	end
	return nil
end

-- The top-of-screen guard. The card's bottom is the anchor's screen point and
-- its top is its (pixel) height above that; if the top would be above
-- TopStack's bottom + SafeMargin the anchor is lowered in 0.25-stud steps from
-- AnchorUpStuds (never above it) to the floor AnchorFloorStuds. Runs on open,
-- on a viewport / layout change and when the zoom changed by > 2 studs.
function GachaBoardController.FitAnchor()
	local view = card
	local camera = Workspace.CurrentCamera
	if not view or not camera then
		return
	end
	applyPhoneScale(view)
	view.ZoomAt = zoomDistance() or view.ZoomAt
	local scale = if UIKit.IsPhone() then UITheme.PhoneScale else 1
	local heightPx = FULL_SIZE.Y * scale
	local minTop = (TopStack.GetBottom() + G.SafeMargin) * scale + GuiService:GetGuiInset().Y
	local base = view.Pad.Position + Vector3.new(0, view.Pad.Size.Y / 2, 0)
	local best = G.AnchorUpStuds
	local up = G.AnchorUpStuds
	while true do
		local projected = camera:WorldToViewportPoint(base + Vector3.new(0, up, 0))
		if projected.Z <= 0 or projected.Y - heightPx >= minTop then
			best = up
			break
		end
		if up <= G.AnchorFloorStuds then
			best = G.AnchorFloorStuds
			break
		end
		up = math.max(G.AnchorFloorStuds, up - 0.25)
	end
	setUpStuds(view, best)
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

local function buildCard(pad: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "GachaCard"
	billboard.Adornee = pad
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

	-- The card: fixed pixels, dark violet, 16 px corners.
	local cardFrame = Instance.new("Frame")
	cardFrame.Name = "Card"
	cardFrame.BackgroundColor3 = Colors.Panel
	cardFrame.BorderSizePixel = 0
	cardFrame.Position = UDim2.new()
	cardFrame.Size = UDim2.fromOffset(CARD.X, CARD.Y)
	cardFrame.Parent = popRoot
	UIKit.Corner(cardFrame, 16)

	table.clear(buttons)
	local keyBar = buildKeyBar(popRoot)

	local view = {
		Billboard = billboard,
		Pad = pad,
		Root = root,
		PopRoot = popRoot,
		Pop = pop,
		Card = cardFrame,
		KeyBar = keyBar,
		Tiles = {},
		Chips = {},
		LuckPill = nil :: any,
		EventPill = nil :: any,
		Price = nil :: any,
		Shimmer = nil,
		Sparkle = nil,
		Signature = "",
		Label = pad:FindFirstChild("GachaLabel"),
		Near = false,
		Open = false,
		Tween = nil,
		UpStuds = G.AnchorUpStuds,
		ZoomAt = 0,
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
			card = nil
			unbindKeys()
		end
		billboard:Destroy()
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
	if not view.PopRoot.Visible then
		return
	end
	-- The top-of-screen guard re-checks only when the zoom changed (never on a turn).
	local zoom = zoomDistance()
	if zoom and math.abs(zoom - view.ZoomAt) > G.ZoomRecheckStuds then
		GachaBoardController.FitAnchor()
	end
	local now = os.clock()
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
	if view.Open and not view.VipTag then
		hideVipTag(view, true) -- a respawn builds a new VIP chip
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
function GachaBoardController.GetCard(): { Billboard: BillboardGui, Pad: BasePart, Root: Frame, PopRoot: Frame, Card: Frame, Pop: UIScale, Open: boolean, Shown: boolean, Label: Instance?, UpStuds: number, VipHidden: boolean }?
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
		UpStuds = view.UpStuds,
		VipHidden = view.VipTag ~= nil,
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
	RunService.RenderStepped:Connect(stepFrame)
	-- Re-fit the top-of-screen guard when the layout changes (never per frame).
	UIKit.LayoutChanged:Connect(GachaBoardController.FitAnchor)
	local function watchViewport()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(GachaBoardController.FitAnchor)
		end
	end
	watchViewport()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchViewport()
		GachaBoardController.FitAnchor()
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
end

return GachaBoardController
