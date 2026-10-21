--!strict
--[[
	ShopPanel
	---------
	The SHOP modal (the HUD's 🛒 SHOP button): ONE scrolling page, the
	pattern kids know from the big simulator games. Every number on it is
	real.

	  * Sticky: the modal header (title + ✕) and, under it, the category
	    chip bar (⭐ Featured · 🎟 Passes · ⚡ Boosts · 💰 Cash · 🍀 Luck ·
	    🛡 Safe, ShopConfig.Sections). A chip TWEENS the scroll to its
	    section (it never filters); while you scroll, the chip of the section
	    on screen turns green (UIKit.SetSelected). The bar scrolls sideways
	    when it doesn't fit.
	  * Sections, each with a big header row (icon, title, thin divider):
	      Featured  one wide banner: the Starter Pack until bought (then
	                dimmed in place, "OWNED ✓"), a live sale, else the best
	                value. A bundle (Parts) lists its contents: DealParts
	                tiles + a ✓ YOU GET line per part + the live worth.
	                Polish 11 look: art box + glow (rays on Featured / Deal),
	                30 / 16 / 13 px text only, 160 x 64 buy button.
	      Passes    big cards (icon, name, benefit, buy); an owned pass
	                shows a grey "OWNED ✓" and sorts to the end.
	      Boosts    QuickBoost, Boost (BoostSale while its window is live),
	                Overclock: "+1 h · you have 0:42" (the real bank).
	      Cash      what each pack pays YOU right now; "BEST VALUE" on the
	                most $ per Robux, from live prices only.
	      Luck      the Luck Potion (the Lucky pass is in Passes).
	      Safe      Safe Fusion x1 / x5, "SAVE N%" from live prices.
	    An empty section (policy, nothing set up) is left out with its chip.
	  * Tiles: 4 columns (2 on a phone or a narrow screen), each its own
	    rounded panel in its section colour; the live store icon
	    (ShopPrices.GetIcon) or the emoji in a circle; a green buy button
	    with the live price ("TEST" in Studio for Id 0). Hover 1.03, press
	    bounce.
	  * Footer: the honest line about live prices and shown odds.

	Prices come from ShopPrices (live, cached 10 min) through
	ShopController.GetPriceText; nothing here is typed in. Items you can't
	be sold (policy, not set up, a sale outside its window) never show.
	OfflineDouble lives only on the welcome-back card.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local ShopState = require(ReplicatedStorage.Shared.Modules.ShopState)
local ShopPrices = require(ReplicatedStorage.Shared.Modules.ShopPrices)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local Controllers = script.Parent.Parent.Controllers
local TycoonController = require(Controllers.TycoonController)
local ShopController = require(Controllers.ShopController)
local UIKit = require(script.Parent.UIKit)
local DealParts = require(script.Parent.DealParts)

local ShopPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(820, 640)
local CHIP_WIDTH = 124
local CHIP_HEIGHT = UITheme.MinTapSize
local CHIP_GAP = 8
local CHIP_BAR_HEIGHT = CHIP_HEIGHT + UITheme.SmallShadowOffset + 4
local SECTION_GAP = 10
local HEADER_HEIGHT = 44
local HEADER_SPACE = 14 -- + SECTION_GAP = 24 px above each section
-- Banners: the art 120 px on the left; a bundle also lists what is inside.
local BANNER_ART = 120
local BANNER_TILE = 64 -- DealParts tile size on a banner / a bundle tile
local PLAIN_HEIGHT = 176 -- a sale or best-value banner (no parts)
local PARTS_HEIGHT = 244 -- a bundle banner (Starter Pack, a deal), wide
local BANNER_PARTS_NARROW = 700 -- page width under which a bundle banner stacks
-- Tiles: the art 96 px; a pass card is 172, a tile 304 (340 with a bundle's list).
local TILE_ART = 96
local PASS_HEIGHT = 172
local TILE_HEIGHT = 304
local TILE_PARTS_HEIGHT = 340
local GRID_GAP = 12
local NARROW_WIDTH = 560 -- logical px of page width under which tiles go 2-up
local REFRESH_SECONDS = 1
local SHINE_SECONDS = 0.9
local SHINE_EVERY_SECONDS = 3
local BUY_SHINE_SECONDS = 5 -- the Featured buy button's gentle sweep
local BOB_PIXELS = 5
local BOB_SECONDS = 1.1
local RAY_BARS = 6 -- thin bars through the centre = 12 rays
local RAY_SECONDS = 24
-- Depth: a 6 px drop shadow under every card.
local SHOP_SHADOW = 6
-- The type scale: the name 30, lines 16, small labels 13. Nothing smaller.
local NAME_TEXT = 30
local LINE_TEXT = 16
local SMALL_TEXT = 13
-- The buy button: 160 x 64 with the price at 28 px.
local BUY_WIDTH = 160
local BUY_HEIGHT = 64
local BUY_TEXT = 28
local OWNED_OPACITY = 0.7
local SCROLL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_SCALE = 1.04
local PRESS_SCALE = 0.96
local ACTIVE_LINE = 60 -- px below the page top where a header counts as "on screen"

type BannerRefs = {
	Key: string?,
	Detail: TextLabel?, -- a sale / best-value banner's money line
	Worth: TextLabel?, -- a bundle's "Worth R$ N if bought separately"
	YouGet: Frame?, -- a bundle's YOU GET list (cash lines follow your income)
	Parts: { string }?,
	Price: TextButton?,
	Timer: TextLabel?,
}

type TileRefs = {
	Key: string,
	Main: TextLabel?,
	Sub: TextLabel?,
	Price: TextButton,
	Owned: boolean,
}

local modal: UIKit.Modal
local chipBar: ScrollingFrame
local scroller: ScrollingFrame
local footer: TextLabel
local tail: Frame -- blank space after the footer: lets the LAST chip put its header at the top too
local chipButtons: { [string]: TextButton } = {}
local headers: { [string]: Frame } = {}
local sectionOrder: { string } = {}
local tiles: { TileRefs } = {}
local featuredRefs: BannerRefs = {}
local dealRefs: BannerRefs = {}
local activeSection: string? = nil
local scrollLockUntil = 0 -- a chip's tween owns the active chip until then
local builtSignature = ""
local refreshToken = 0

--[[ Helpers ------------------------------------------------------------------------- ]]

local function item(key: string): ShopConfig.Item
	return ShopConfig.GetItem(key) :: ShopConfig.Item
end

local function robux(price: number): string
	return ("%s %d"):format(ShopController.ROBUX, price)
end

local function span(seconds: number): string
	if seconds >= 3600 and seconds % 3600 == 0 then
		return ("%d h"):format(seconds // 3600)
	end
	return ("%d min"):format(seconds // 60)
end

local function sectionPair(section: ShopConfig.Section): UITheme.GradientPair
	return UITheme.Gradients[section.Gradient] or UITheme.Gradients.Violet
end

-- Logical page width (after the phone UIScale).
local function pageWidth(): number
	local width = scroller.AbsoluteSize.X / UIKit.EffectiveScale(scroller)
	return if width > 0 then width else MAX_SIZE.X
end

local function isNarrow(): boolean
	return UIKit.IsPhone() or pageWidth() < NARROW_WIDTH
end

-- A bundle banner (it lists its parts) needs more room before it stacks.
local function bannerNarrow(hasParts: boolean): boolean
	return pageWidth() < (if hasParts then BANNER_PARTS_NARROW else NARROW_WIDTH)
end

local function tileColumns(): number
	return if isNarrow() then 2 else 4
end

local function passColumns(): number
	return if pageWidth() < NARROW_WIDTH then 1 else 2
end

-- Shown at all: offered now, or an owned pass ("OWNED ✓").
local function isListed(key: string): boolean
	return ShopController.IsAvailable(key) or (item(key).Kind == "Pass" and ShopController.IsOwned(key))
end

-- The keys a section lists right now, in order: a live sale replaces its
-- normal product; owned passes go last.
local function keysFor(section: ShopConfig.Section): { string }
	local keys = {}
	for _, key in section.Keys do
		local sale = ShopConfig.GetSaleFor(key)
		if sale and ShopController.IsAvailable(sale.SaleKey) then
			table.insert(keys, sale.SaleKey)
		elseif isListed(key) then
			table.insert(keys, key)
		end
	end
	local owned: { string }, rest: { string } = {}, {}
	for _, key in keys do
		table.insert(if ShopController.IsOwned(key) and item(key).Kind == "Pass" then owned else rest, key)
	end
	for _, key in owned do
		table.insert(rest, key)
	end
	return rest
end

-- The cash pack with the most $ per Robux for THIS player at live prices.
local function bestValueKey(): string?
	local cash = {}
	for _, key in ShopConfig.CashPackOrder do
		if ShopController.IsAvailable(key) then
			table.insert(cash, key)
		end
	end
	return ShopConfig.GetBestValueKey(cash, ShopController.GetCashAmount, ShopPrices.Get)
end

-- Starter Pack until bought, then the live sale, then the (dimmed) bought
-- Starter Pack, then the best value.
local function featuredKey(): string?
	if ShopController.IsAvailable("StarterPack") then
		return "StarterPack"
	end
	for _, sale in ShopConfig.Sales do
		if ShopController.IsAvailable(sale.SaleKey) then
			return sale.SaleKey
		end
	end
	-- Bought: it stays here, dimmed "OWNED ✓", so the page does not jump.
	if ShopController.IsShownOwned("StarterPack") then
		return "StarterPack"
	end
	return bestValueKey()
end

-- "+1 h · you have 0:42" from the real bank; "Bank full" at the cap.
local function bankText(key: string): string?
	local add, have, cap, who
	local boost = if key == "StarterPack" then nil else ShopConfig.BoostSeconds[key]
	if key == "LuckPotion" then
		add, have, cap, who = ShopConfig.LuckPotionSeconds, TycoonController.GetBoostSecondsLeft("Luck"), ShopConfig.MaxLuckBankSeconds, "you have"
	elseif key == "Overclock" then
		add, have, cap, who = ShopConfig.OverclockSeconds, ShopState.GetOverclockSeconds(), ShopConfig.MaxOverclockSeconds, "server has"
	elseif boost then
		add, have, cap, who = boost, TycoonController.GetBoostSecondsLeft("Income"), ShopConfig.MaxBoostBankSeconds, "you have"
	else
		return nil
	end
	if have >= cap then
		return ("Bank full (%s) · %s %s"):format(span(cap), who, EventState.FormatTimer(have))
	end
	return ("+%s · %s %s"):format(span(add), who, EventState.FormatTimer(have))
end

-- The sale line, all from live prices.
local function saleText(key: string): string
	local entry = item(key)
	local normal = entry.SaleOf and ShopPrices.Get(entry.SaleOf)
	local today = ShopPrices.Get(key)
	if normal and today then
		local off = ShopConfig.GetSavePercent(today, normal)
		return ("normally <s>%s</s> · today %s%s"):format(robux(normal), robux(today), if off then (" (−%d%%)"):format(off) else "")
	end
	return entry.Effect
end

-- A tile's two text lines (RichText).
local function tileLines(key: string): (string, string)
	local entry = item(key)
	local pack = ShopConfig.CashPacks[key]
	if pack then
		-- White on the vivid green tile (green-on-green would vanish).
		return "+" .. NumberFormat.Money(ShopController.GetCashAmount(key)),
			("%s of your income"):format(span(pack.Minutes * 60))
	end
	if entry.SaleOf then
		return saleText(key), bankText(key) or ""
	end
	local tokens = ShopConfig.SafeFusionTokens[key]
	if tokens then
		local have = TycoonController.GetShop().SafeFusionTokens
		return entry.Effect, if have > 0 then ("You have %d"):format(have) else ""
	end
	return entry.Effect, bankText(key) or ""
end

-- "BEST VALUE" (cash, live) or "SAVE N%" (a bundle or a sale, live).
local function tagText(key: string, best: string?): string?
	if key == best then
		return "BEST VALUE"
	end
	local entry = item(key)
	local price = ShopPrices.Get(key)
	local save = if entry.SaleOf
		then ShopConfig.GetSavePercent(price, ShopPrices.Get(entry.SaleOf))
		else ShopConfig.GetSavePercent(price, ShopPrices.GetPartsTotal(key))
	return if save then ("SAVE %d%%"):format(save) else nil
end

--[[ Building blocks --------------------------------------------------------------- ]]

-- A diagonal white shine sweeping across `frame` every `every` seconds.
local function addShine(frame: GuiObject, every: number)
	frame.ClipsDescendants = true
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(-0.4, 0.5)
	shine.Size = UDim2.new(0.22, 0, 2.2, 0)
	shine.Rotation = 20
	shine.BackgroundColor3 = Colors.White
	shine.BackgroundTransparency = 0.6
	shine.BorderSizePixel = 0
	shine.ZIndex = frame.ZIndex + 1
	shine.Parent = frame
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = shine
	TweenService:Create(
		shine,
		TweenInfo.new(SHINE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, false, every),
		{ Position = UDim2.fromScale(1.4, 0.5) }
	):Play()
end

-- The 1 px light line along a card's top edge (the depth highlight).
local function highlightLine(body: GuiObject, z: number)
	local line = Instance.new("Frame")
	line.Name = "Highlight"
	line.BackgroundColor3 = Colors.ShopHighlight
	line.BackgroundTransparency = 0.45
	line.BorderSizePixel = 0
	line.Position = UDim2.fromOffset(14, 8)
	line.Size = UDim2.new(1, -28, 0, 1)
	line.ZIndex = z
	line.Parent = body
end

-- The art box every product sits in (120 px on banners, 96 on tiles): the
-- live store icon (what Harris uploaded with the pass / product), else the
-- emoji, over a radial glow in the card's colour. `rays` (Featured and Deal
-- only) turn slowly behind it. The picture bobs gently.
local function artBox(parent: Instance, key: string, size: number, position: UDim2, anchor: Vector2, z: number, pair: UITheme.GradientPair, rays: boolean): Frame
	local box = Instance.new("Frame")
	box.Name = "Art"
	box.AnchorPoint = anchor
	box.Position = position
	box.Size = UDim2.fromOffset(size, size)
	box.BackgroundColor3 = Colors.ShopArtWell
	box.BackgroundTransparency = 0.3
	box.BorderSizePixel = 0
	box.ClipsDescendants = true
	box.ZIndex = z
	box.Parent = parent
	UIKit.Corner(box, 18)
	local rim = UIKit.Stroke(box, 2, Colors.White)
	rim.Transparency = 0.55
	if rays then
		local turning = Instance.new("Frame")
		turning.Name = "Rays"
		turning.BackgroundTransparency = 1
		turning.AnchorPoint = Vector2.new(0.5, 0.5)
		turning.Position = UDim2.fromScale(0.5, 0.5)
		turning.Size = UDim2.fromScale(1.5, 1.5) -- covers the corners while it turns
		turning.ZIndex = z + 1
		turning.Parent = box
		for index = 1, RAY_BARS do
			local bar = Instance.new("Frame")
			bar.Name = "Ray"
			bar.BackgroundColor3 = Colors.ShopRay
			bar.BackgroundTransparency = 0.82
			bar.BorderSizePixel = 0
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.new(0, 9, 1, 0)
			bar.Rotation = (index - 1) * (180 / RAY_BARS)
			bar.ZIndex = z + 1
			bar.Parent = turning
		end
		TweenService:Create(turning, TweenInfo.new(RAY_SECONDS, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 }):Play()
	end
	-- The radial glow: three soft discs in the card's colour.
	for index, fraction in { 0.96, 0.7, 0.44 } do
		local disc = Instance.new("Frame")
		disc.Name = "Glow" .. index
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(0.5, 0.5)
		disc.Size = UDim2.fromScale(fraction, fraction)
		disc.BackgroundColor3 = pair.Top
		disc.BackgroundTransparency = 0.82 - 0.14 * (index - 1)
		disc.BorderSizePixel = 0
		disc.ZIndex = z + 1
		disc.Parent = box
		UIKit.Corner(disc, 999)
	end
	local pictureSize = math.floor(size * 0.74)
	local image = ShopPrices.GetIcon(key)
	local piece: GuiObject
	if image then
		local picture = Instance.new("ImageLabel")
		picture.Name = "Image"
		picture.BackgroundTransparency = 1
		picture.AnchorPoint = Vector2.new(0.5, 0.5)
		picture.Position = UDim2.fromScale(0.5, 0.5)
		picture.Size = UDim2.fromOffset(pictureSize, pictureSize)
		picture.Image = image
		picture.ScaleType = Enum.ScaleType.Fit
		picture.ZIndex = z + 3
		picture.Parent = box
		piece = picture
	else
		piece = UIKit.Label({
			Name = "Glyph",
			Text = item(key).Icon,
			TextSize = math.floor(size * 0.55),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(pictureSize, pictureSize),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 3,
			Parent = box,
		})
	end
	TweenService:Create(
		piece,
		TweenInfo.new(BOB_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.new(0.5, 0, 0.5, -BOB_PIXELS) }
	):Play()
	return box
end

-- A gold corner tag ("BEST VALUE", "SAVE 56%"): white + ink by the
-- contrast rule (UIKit.Pill on a warm gradient).
local function cornerTag(parent: Instance, text: string, z: number): TextLabel
	return UIKit.Pill({
		Name = "Tag",
		Parent = parent,
		Text = text,
		Gradient = UITheme.Gradients.Gold,
		Font = Fonts.Display,
		TextSize = SMALL_TEXT,
		Height = 22,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 12),
		ZIndex = z,
	})
end

-- "NEW!" (top-left) on an item that really went on sale this week
-- (ShopConfig.IsNew).
local function newTag(parent: Frame, entry: ShopConfig.Item)
	local today = RewardConfig.GetUtcDay(math.floor(workspace:GetServerTimeNow()))
	if not ShopConfig.IsNew(entry, today) then
		return
	end
	UIKit.Pill({
		Name = "New",
		Parent = parent,
		Text = "NEW!",
		Gradient = UITheme.Gradients.Red,
		Font = Fonts.Display,
		TextSize = SMALL_TEXT,
		Height = 22,
		TextStroke = 1.5,
		Position = UDim2.fromOffset(8, 12),
		ZIndex = parent.ZIndex + 5,
	})
end

-- The chunky rounded panel every tile / card sits on: a lighter-on-top
-- gradient in the section colour, a darker 3 px outline, a 1 px highlight
-- line along the top, a gloss and a 6 px drop shadow. The holder hovers to
-- 1.04 and bounces on press.
local function tilePanel(parent: Instance, name: string, order: number, pair: UITheme.GradientPair): (Frame, Frame, UIScale)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = order
	holder.ZIndex = parent:IsA("GuiObject") and (parent :: GuiObject).ZIndex + 1 or 2
	holder.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Name = "HoverScale"
	scale.Parent = holder
	-- The section's own vivid gradient (white text with the ink stroke on it).
	local stops: { { any } } = { { 0, pair.Top }, { 1, pair.Bottom } }
	local body = UIKit.Panel({
		Name = "Fill",
		Parent = holder,
		Size = UDim2.new(1, 0, 1, -SHOP_SHADOW),
		Gradient = stops,
		Radius = 18,
		StrokeThickness = 3,
		ShadowOffset = SHOP_SHADOW,
		ZIndex = holder.ZIndex,
	})
	-- Gloss: a soft white wash over the top half.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Size = UDim2.fromScale(1, 0.45)
	gloss.BackgroundColor3 = Colors.White
	gloss.BackgroundTransparency = 0.9
	gloss.BorderSizePixel = 0
	gloss.ZIndex = body.ZIndex
	gloss.Parent = body
	UIKit.Corner(gloss, 18)
	-- A coloured band along the top edge: the section's colour, loud.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.Size = UDim2.new(1, 0, 0, 6)
	band.BackgroundColor3 = Colors.White
	band.BorderSizePixel = 0
	band.ZIndex = body.ZIndex
	band.Parent = body
	UIKit.Corner(band, 3)
	UIKit.PairGradient(band, pair, 0)
	highlightLine(body, body.ZIndex + 1)
	-- Hover: 1.04 and a white glow stroke.
	local stroke = body:FindFirstChildOfClass("UIStroke")
	body.MouseEnter:Connect(function()
		TweenService:Create(scale, HOVER_INFO, { Scale = HOVER_SCALE }):Play()
		if stroke then
			stroke.Color = Colors.White
			stroke.Thickness = 4
		end
	end)
	body.MouseLeave:Connect(function()
		TweenService:Create(scale, HOVER_INFO, { Scale = 1 }):Play()
		if stroke then
			stroke.Color = Colors.Ink
			stroke.Thickness = 3
		end
	end)
	return body, holder, scale
end

-- The green buy button, 160 x 64 with the live price at 28 px (a bought
-- pass / one-time product: grey "OWNED ✓"). It presses in over 0.12 s and
-- the tile bounces with it. `props.Fill` lets it stretch up to its 160 px cap.
local function buyButton(parent: Frame, key: string, scale: UIScale?, props: { [string]: any }): TextButton
	local owned = ShopController.IsOwned(key)
	local button, holder = UIKit.Button({
		Name = "Buy",
		Parent = parent,
		Style = if owned then "Disabled" else "Green",
		Text = if owned then "OWNED ✓" else ShopController.GetPriceText(key),
		TextColor3 = if owned then Colors.Muted else Colors.Text,
		TextSize = BUY_TEXT,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size or UDim2.fromOffset(BUY_WIDTH, BUY_HEIGHT),
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = parent.ZIndex + 3,
		OnClick = function()
			if not ShopController.IsOwned(key) then
				ShopController.Buy(key)
			end
		end,
	})
	if props.Fill then
		local cap = Instance.new("UISizeConstraint")
		cap.MaxSize = Vector2.new(BUY_WIDTH, BUY_HEIGHT)
		cap.Parent = holder
	end
	if scale then
		button.MouseButton1Down:Connect(function()
			TweenService:Create(scale, PRESS_INFO, { Scale = PRESS_SCALE }):Play()
		end)
		button.MouseButton1Up:Connect(function()
			TweenService:Create(scale, PRESS_INFO, { Scale = HOVER_SCALE }):Play()
		end)
	end
	return button
end

local function textLabel(parent: Frame, name: string, props: { [string]: any }): TextLabel
	props.Name = name
	props.Parent = parent
	props.ZIndex = parent.ZIndex + 3
	return UIKit.Label(props)
end

-- Dims a bought card to 70%, in place.
local function dimOwned(root: Instance)
	UIKit.SetOpacity(root, OWNED_OPACITY)
end

--[[ Sections -------------------------------------------------------------------------- ]]

local function sectionHeader(section: ShopConfig.Section, order: number)
	local row = Instance.new("Frame")
	row.Name = section.Id .. "Header"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT + HEADER_SPACE)
	row.LayoutOrder = order
	row.ZIndex = scroller.ZIndex + 1
	row.Parent = scroller
	-- The extra space above the section (SECTION_GAP + HEADER_SPACE = 24 px).
	UIKit.Padding(row, HEADER_SPACE, 0, 0, 0)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	-- The coloured icon chip.
	local iconPill = Instance.new("Frame")
	iconPill.Name = "IconPill"
	iconPill.Size = UDim2.fromOffset(52, 36)
	iconPill.BackgroundColor3 = Colors.White
	iconPill.LayoutOrder = 0
	iconPill.ZIndex = row.ZIndex
	iconPill.Parent = row
	UIKit.Corner(iconPill, 999)
	UIKit.Stroke(iconPill, 3)
	UIKit.PairGradient(iconPill, sectionPair(section))
	UIKit.Label({
		Name = "Icon",
		Text = section.Icon,
		TextSize = 22,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = row.ZIndex + 1,
		Parent = iconPill,
	})
	UIKit.Label({
		Name = "Title",
		Text = section.Title,
		Font = Fonts.Display,
		TextSize = 26,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, HEADER_HEIGHT),
		LayoutOrder = 1,
		ZIndex = row.ZIndex,
		Stroke = UITheme.Stroke.Text,
		Parent = row,
	})
	-- The 2 px rule to the right.
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = sectionPair(section).Top
	divider.BackgroundTransparency = 0.25
	divider.BorderSizePixel = 0
	divider.Size = UDim2.fromOffset(0, 2)
	divider.LayoutOrder = 2
	divider.ZIndex = row.ZIndex
	divider.Parent = row
	UIKit.Corner(divider, 1)
	local flex = Instance.new("UIFlexItem")
	flex.FlexMode = Enum.UIFlexMode.Fill
	flex.Parent = divider
	headers[section.Id] = row
end

local function grid(name: string, order: number, columns: number, cellHeight: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	frame.ZIndex = scroller.ZIndex + 1
	frame.Parent = scroller
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP)
	-- 1 px of slack so rounding never wraps a row (see GiftsPanel).
	layout.CellSize = UDim2.new(1 / columns, -GRID_GAP * (columns - 1) / columns - 1, 0, cellHeight)
	layout.FillDirectionMaxCells = columns
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

-- The banner's money line (a sale or a plain product), all from live prices.
local function featuredDetail(key: string): string
	local entry = item(key)
	if entry.SaleOf then
		return saleText(key)
	end
	local main, sub = tileLines(key)
	return if sub ~= "" then ("%s · %s"):format(main, sub) else main
end

-- The ONE banner builder: the ⭐ Featured banner (the Starter Pack until
-- bought and then dimmed in place, a live sale, the best value) and the 🔥 DEAL banner.
-- Any item with `Parts` (Starter Pack, every deal) shows what is inside:
-- one DealParts tile per distinct part, then a ✓ YOU GET line per part in
-- plain words, then "Worth R$ N if bought separately" (live prices) and
-- the live SAVE %. Everything is 30 / 16 / 13 px. Rays turn behind the art;
-- only the Featured buy button gets a shine sweep.
local function buildBanner(kind: string, key: string, order: number, refs: BannerRefs)
	local entry = item(key)
	local isDeal = kind == "Deal"
	local owned = ShopController.IsOwned(key)
	local parts: { string } = entry.Parts or {}
	local hasParts = #parts > 0
	local narrow = bannerNarrow(hasParts)
	local pair = if isDeal then UITheme.Gradients.Pink else UITheme.Gradients.ShopFeatured
	local distinct = #DealParts.Distinct(parts)
	local tilesWidth = distinct * DealParts.TileWidth(BANNER_TILE) + math.max(0, distinct - 1) * 4
	local tileHeight = DealParts.TileHeight(BANNER_TILE)
	local artSize = if narrow then 96 else BANNER_ART
	local x0 = if narrow then 16 + artSize + 12 else 16 + artSize + 16 -- the text column
	local rightReserve = if narrow then 16 else 20 + BUY_WIDTH + 16 -- the buy button's column
	local tag = tagText(key, nil)

	-- Heights (the holder includes the 6 px shadow).
	local listHeight = 26 + distinct * 40
	local height: number
	if hasParts then
		if narrow then
			height = 16 + artSize + 10 + tileHeight + 8 + listHeight + 6 + 28 + 10 + BUY_HEIGHT + 14 + SHOP_SHADOW
		else
			height = PARTS_HEIGHT
		end
	elseif narrow then
		height = 16 + artSize + 8 + 46 + 8 + 28 + 10 + BUY_HEIGHT + 14 + SHOP_SHADOW
	else
		height = PLAIN_HEIGHT
	end

	local holder = Instance.new("Frame")
	holder.Name = if isDeal then "DealBanner" else "FeaturedBanner"
	holder:SetAttribute("ShopKey", key) -- /selftest: which item this banner sells
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, height)
	holder.LayoutOrder = order
	holder.ZIndex = scroller.ZIndex + 1
	holder.Parent = scroller
	local z = holder.ZIndex + 1
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, -SHOP_SHADOW)
	fill.BackgroundColor3 = Colors.White
	fill.ZIndex = z
	fill.Parent = holder
	UIKit.Corner(fill, 20)
	UIKit.Stroke(fill, 3)
	UIKit.PairGradient(fill, pair)
	UIKit.Shadow(fill, SHOP_SHADOW)
	highlightLine(fill, z + 1)

	artBox(fill, key, artSize, if narrow then UDim2.fromOffset(16, 16) else UDim2.new(0, 16, 0.5, 0), if narrow then Vector2.zero else Vector2.new(0, 0.5), z + 2, pair, true)

	-- The small label: what this is (or, on the deal, how long it lasts).
	local caption = if isDeal
		then "🔥 DEAL"
		elseif entry.SaleOf then "🔥 ADMIN ABUSE SALE"
		elseif key == "StarterPack" then "🎁 ONE TIME ONLY"
		else "⭐ BEST VALUE"
	local captionPill = UIKit.Pill({
		Name = "Caption",
		Parent = fill,
		Text = caption,
		Gradient = if isDeal then UITheme.Gradients.Violet else UITheme.Gradients.Gold,
		Font = Fonts.BodyHeavy,
		TextSize = SMALL_TEXT,
		Height = 22,
		Position = UDim2.fromOffset(x0, 14),
		ZIndex = z + 2,
	})
	if isDeal then
		refs.Timer = captionPill
	end

	-- Where the YOU GET list starts (wide parts banner: beside the tiles).
	local listX = x0 + math.max(tilesWidth, 232) + 16
	local titleRight = if hasParts and not narrow then 0 else rightReserve
	local title = UIKit.Label({
		Name = "Title",
		Text = if entry.SaleOf then item(entry.SaleOf).Name else entry.Name,
		Font = Fonts.Display,
		TextSize = NAME_TEXT,
		Position = UDim2.fromOffset(x0, 42),
		Size = if hasParts and not narrow
			then UDim2.fromOffset(listX - x0 - 8, 36)
			else UDim2.new(1, -(x0 + titleRight), 0, 36),
		ZIndex = z + 2,
		Stroke = 3,
		Parent = fill,
	})
	UIKit.FitText(title, NAME_TEXT, 20)

	local worthLabel: TextLabel? = nil
	if hasParts then
		local tilesY = if narrow then 16 + artSize + 10 else 82
		local partRow = DealParts.BuildTiles(fill, parts, z + 2, BANNER_TILE)
		partRow.Position = UDim2.fromOffset(if narrow then 16 else x0, tilesY)
		local youGet: Frame
		local listTop: number
		if narrow then
			listTop = tilesY + tileHeight + 8
			youGet = DealParts.BuildYouGet(fill, parts, z + 2, UDim.new(1, -32), LINE_TEXT)
			youGet.Position = UDim2.fromOffset(16, listTop)
		else
			listTop = 14
			youGet = DealParts.BuildYouGet(fill, parts, z + 2, UDim.new(1, -(listX + 16)), LINE_TEXT)
			youGet.Position = UDim2.fromOffset(listX, listTop)
		end
		refs.YouGet = youGet
		refs.Parts = parts
		-- "Worth R$ N if bought separately" and the live SAVE %, in a row.
		local rowY = if narrow then listTop + listHeight + 6 else tilesY + tileHeight + 6
		local row = Instance.new("Frame")
		row.Name = "WorthRow"
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(if narrow then 16 else x0, rowY)
		row.Size = UDim2.new(1, -((if narrow then 16 else x0) + 16), 0, 28)
		row.ZIndex = z + 2
		row.Parent = fill
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Padding = UDim.new(0, 10)
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Parent = row
		worthLabel = UIKit.Label({
			Name = "Worth",
			Text = ShopController.GetWorthLine(key) or "",
			Font = Fonts.BodyHeavy,
			TextSize = LINE_TEXT,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 22),
			LayoutOrder = 1,
			ZIndex = z + 2,
			Stroke = 1.5,
			Parent = row,
		})
		if tag then
			UIKit.Pill({
				Name = "Save",
				Parent = row,
				Text = tag,
				Gradient = UITheme.Gradients.Gold,
				Font = Fonts.Display,
				TextSize = LINE_TEXT,
				Height = 28,
				LayoutOrder = 2,
				ZIndex = z + 2,
			})
		end
	else
		-- A sale or the best value: its one live money line, then SAVE / ends.
		local detailY = if narrow then 16 + artSize + 8 else 84
		refs.Detail = UIKit.Label({
			Name = "Detail",
			Text = featuredDetail(key),
			RichText = true,
			Font = Fonts.BodyHeavy,
			TextSize = LINE_TEXT,
			TextWrapped = true,
			Position = UDim2.fromOffset(if narrow then 16 else x0, detailY),
			Size = UDim2.new(1, -((if narrow then 16 else x0) + (if narrow then 16 else rightReserve)), 0, if narrow then 46 else 44),
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = z + 2,
			Stroke = 1.5,
			Parent = fill,
		})
		local rowY = if narrow then detailY + 46 + 8 else 134
		local rowX = if narrow then 16 else x0
		if tag then
			UIKit.Pill({
				Name = "Save",
				Parent = fill,
				Text = tag,
				Gradient = UITheme.Gradients.Gold,
				Font = Fonts.Display,
				TextSize = LINE_TEXT,
				Height = 28,
				Position = UDim2.fromOffset(rowX, rowY),
				ZIndex = z + 2,
			})
		end
		if entry.SaleOf then
			refs.Timer = UIKit.Label({
				Name = "Ends",
				Font = Fonts.BodyHeavy,
				TextSize = SMALL_TEXT,
				Position = UDim2.fromOffset(rowX + (if tag then 120 else 0), rowY + 4),
				Size = UDim2.fromOffset(300, 20),
				ZIndex = z + 2,
				Stroke = 1.5,
				Parent = fill,
			})
		end
	end

	local buy = buyButton(fill, key, nil, {
		AnchorPoint = if narrow then Vector2.new(0.5, 1) else if hasParts then Vector2.new(1, 1) else Vector2.new(1, 0.5),
		Position = if narrow
			then UDim2.new(0.5, 0, 1, -14)
			elseif hasParts then UDim2.new(1, -20, 1, -16)
			else UDim2.new(1, -20, 0.5, 0),
		Size = if narrow then UDim2.new(1, -32, 0, BUY_HEIGHT) else UDim2.fromOffset(BUY_WIDTH, BUY_HEIGHT),
	})
	if kind == "Featured" and not owned then
		addShine(buy, BUY_SHINE_SECONDS)
	end
	refs.Price = buy
	refs.Worth = worthLabel
	refs.Key = key
	if owned then
		dimOwned(holder)
	end
end

-- A pass: a big card (art, name, benefit, buy). An owned pass dims, in place.
local function buildPassCard(parent: Frame, section: ShopConfig.Section, key: string, order: number)
	local entry = item(key)
	local pair = sectionPair(section)
	local body, holder, scale = tilePanel(parent, key, order, pair)
	newTag(body, entry)
	artBox(body, key, TILE_ART, UDim2.new(0, 14, 0.5, -SHOP_SHADOW / 2), Vector2.new(0, 0.5), body.ZIndex + 2, pair, false)
	local textLeft = 14 + TILE_ART + 12
	local title = textLabel(body, "Title", {
		Text = entry.Name,
		Font = Fonts.Display,
		TextSize = NAME_TEXT,
		Position = UDim2.fromOffset(textLeft, 12),
		Size = UDim2.new(1, -(textLeft + 12), 0, 34),
		Stroke = 3,
	})
	UIKit.FitText(title, NAME_TEXT, 16)
	local main = textLabel(body, "Main", {
		Text = entry.Effect,
		Font = Fonts.BodyHeavy,
		TextSize = LINE_TEXT,
		TextWrapped = true,
		Position = UDim2.fromOffset(textLeft, 48),
		Size = UDim2.new(1, -(textLeft + 12), 0, 40),
		TextYAlignment = Enum.TextYAlignment.Top,
		Stroke = 1.5,
	})
	UIKit.FitText(main, LINE_TEXT, SMALL_TEXT)
	local button = buyButton(body, key, scale, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, textLeft, 1, -12),
		Size = UDim2.new(1, -(textLeft + 12), 0, BUY_HEIGHT),
		Fill = true,
	})
	local owned = ShopController.IsOwned(key)
	table.insert(tiles, { Key = key, Main = main, Price = button, Owned = owned })
	if owned then
		dimOwned(holder)
	end
end

-- A boost / cash / luck / safe tile. A bundle (Safe Fusion x5) shows its
-- parts as a tile and a YOU GET line instead of the art box.
local function buildTile(parent: Frame, section: ShopConfig.Section, key: string, order: number, best: string?)
	local entry = item(key)
	local pair = sectionPair(section)
	local body, holder, scale = tilePanel(parent, key, order, pair)
	local parts: { string } = entry.Parts or {}
	local hasParts = #parts > 0
	local titleY = if hasParts then 110 else 116
	if hasParts then
		local row = DealParts.BuildTiles(body, parts, body.ZIndex + 2, BANNER_TILE)
		row.AnchorPoint = Vector2.new(0.5, 0)
		row.Position = UDim2.new(0.5, 0, 0, 8)
	else
		artBox(body, key, TILE_ART, UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0), body.ZIndex + 2, pair, false)
	end
	local tag = tagText(key, best)
	if tag then
		cornerTag(body, tag, body.ZIndex + 5)
	end
	newTag(body, entry)
	local title = textLabel(body, "Title", {
		Text = if entry.SaleOf then item(entry.SaleOf).Name .. " · SALE" else entry.Name,
		Font = Fonts.Display,
		TextSize = NAME_TEXT,
		Position = UDim2.fromOffset(8, titleY),
		Size = UDim2.new(1, -16, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = 3,
	})
	UIKit.FitText(title, NAME_TEXT, 16)
	local mainText, subText = tileLines(key)
	local isCash = ShopConfig.CashPacks[key] ~= nil
	local main: TextLabel? = nil
	local subY = titleY + 38 + 40 + 2
	if hasParts then
		local list = DealParts.BuildYouGet(body, parts, body.ZIndex + 3, UDim.new(1, -20), LINE_TEXT)
		list.Position = UDim2.fromOffset(10, titleY + 38)
		subY = titleY + 38 + 84
	else
		main = textLabel(body, "Main", {
			Text = mainText,
			RichText = true,
			Font = if isCash then Fonts.Display else Fonts.BodyHeavy,
			TextSize = LINE_TEXT,
			TextWrapped = true,
			Position = UDim2.fromOffset(8, titleY + 38),
			Size = UDim2.new(1, -16, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			Stroke = 1.5,
		})
		-- Two lines at most; a longer line shrinks instead of spilling out.
		UIKit.FitText(main :: TextLabel, LINE_TEXT, SMALL_TEXT)
	end
	local sub = textLabel(body, "Sub", {
		Text = subText,
		RichText = true,
		Font = Fonts.Body,
		TextSize = SMALL_TEXT,
		TextWrapped = true,
		Position = UDim2.fromOffset(8, subY),
		Size = UDim2.new(1, -16, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Stroke = 1.5,
	})
	local button = buyButton(body, key, scale, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -20, 0, BUY_HEIGHT),
		Fill = true,
	})
	table.insert(tiles, { Key = key, Main = main, Sub = sub, Price = button, Owned = false })
	if ShopController.IsOwned(key) then
		dimOwned(holder)
	end
end

--[[ Chips + scrolling -------------------------------------------------------------- ]]

local function setActive(id: string?)
	if id == activeSection then
		return
	end
	activeSection = id
	for sectionId, button in chipButtons do
		UIKit.SetSelected(button, sectionId == id)
	end
	-- Keep the active chip in view when the bar scrolls sideways.
	local chip = id and chipButtons[id]
	if chip then
		local scale = UIKit.EffectiveScale(chipBar)
		local left = (chip.AbsolutePosition.X - chipBar.AbsolutePosition.X) / scale
		local right = left + chip.AbsoluteSize.X / scale
		local width = chipBar.AbsoluteSize.X / scale
		local x = chipBar.CanvasPosition.X
		if left < 0 then
			chipBar.CanvasPosition = Vector2.new(math.max(0, x + left - CHIP_GAP), 0)
		elseif right > width then
			chipBar.CanvasPosition = Vector2.new(x + right - width + CHIP_GAP, 0)
		end
	end
end

-- The section whose header is on screen: the last header above the
-- ACTIVE_LINE, or the last section once the page is scrolled to its end.
-- Screen-space only (AbsolutePosition), so the phone UIScale can't skew it.
local function sectionOnScreen(): string?
	local top = scroller.AbsolutePosition.Y
	local bottom = top + scroller.AbsoluteSize.Y
	if footer.AbsolutePosition.Y + footer.AbsoluteSize.Y <= bottom + 2 and scroller.CanvasPosition.Y > 0 then
		return sectionOrder[#sectionOrder]
	end
	local line = top + ACTIVE_LINE * UIKit.EffectiveScale(scroller)
	local found = sectionOrder[1]
	for _, id in sectionOrder do
		local header = headers[id]
		if header and header.AbsolutePosition.Y <= line then
			found = id
		end
	end
	return found
end

local function onScrolled()
	if os.clock() < scrollLockUntil then
		return
	end
	setActive(sectionOnScreen())
end

--[[ Chip jumps ---------------------------------------------------------------------
	A chip puts its section's header right under the chip bar (the page's
	top padding), within 2 px. The target comes from the header's position
	inside the canvas; the screen px per CanvasPosition unit (1, or the
	effective UIScale, depending on how the engine counts under a UIScale)
	is measured from each move and kept, so one nudge after the tween lands
	it exactly. The end of the canvas clamps: the last sections may not be
	able to reach the top. ]]
local SCROLL_PAD_TOP = 12 -- the page's UIPadding top
local JUMP_TOLERANCE = 2 -- logical px
local canvasUnitRatio: number? = nil -- measured screen px per canvas unit, / effective scale

local function canvasUnit(): number
	local scale = UIKit.EffectiveScale(scroller)
	return scale * (canvasUnitRatio or 1)
end

-- Screen px from where `id`'s header is to where it should be.
local function headerResidual(id: string): number?
	local header = headers[id]
	if not header then
		return nil
	end
	local scale = UIKit.EffectiveScale(scroller)
	return header.AbsolutePosition.Y - (scroller.AbsolutePosition.Y + SCROLL_PAD_TOP * scale)
end

-- The furthest CanvasPosition.Y the canvas allows.
local function maxCanvas(): number
	local overflow = scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y
	return math.max(0, overflow / canvasUnit())
end

local function sectionTarget(id: string): number?
	local residual = headerResidual(id)
	if not residual then
		return nil
	end
	return math.clamp(scroller.CanvasPosition.Y + residual / canvasUnit(), 0, maxCanvas())
end

-- Learns the unit from a move: the header went from s0 to s1 (screen) while
-- the canvas went from p0 to p1.
local function learnUnit(p0: number, s0: number, p1: number, s1: number)
	local moved = p1 - p0
	if math.abs(moved) > 8 then
		local ratio = ((s0 - s1) / moved) / UIKit.EffectiveScale(scroller)
		if ratio > 0.2 and ratio < 5 then
			canvasUnitRatio = ratio
		end
	end
end

-- Verify and nudge once (synchronously).
local function nudge(id: string)
	local target = sectionTarget(id)
	if target and math.abs(target - scroller.CanvasPosition.Y) * canvasUnit() > 1 then
		scroller.CanvasPosition = Vector2.new(0, target)
	end
end

-- Tweens (or jumps) the page to a section; it never filters anything.
local function scrollTo(id: string, animate: boolean)
	local header = headers[id]
	local target = sectionTarget(id)
	if not header or not target then
		return
	end
	setActive(id)
	local p0, s0 = scroller.CanvasPosition.Y, header.AbsolutePosition.Y
	if not animate then
		scroller.CanvasPosition = Vector2.new(0, target)
		RunService.Heartbeat:Wait()
		learnUnit(p0, s0, scroller.CanvasPosition.Y, header.AbsolutePosition.Y)
		nudge(id)
		return
	end
	scrollLockUntil = os.clock() + SCROLL_TWEEN.Time + 0.2
	local tween = TweenService:Create(scroller, SCROLL_TWEEN, { CanvasPosition = Vector2.new(0, target) })
	tween:Play()
	tween.Completed:Once(function()
		RunService.Heartbeat:Wait()
		if header.Parent then
			learnUnit(p0, s0, scroller.CanvasPosition.Y, header.AbsolutePosition.Y)
			nudge(id)
		end
		scrollLockUntil = 0
		onScrolled()
	end)
end

-- /selftest: jumps to every chip; PASS when the header lands within 2 px of
-- the top, or the canvas end stopped it short.
function ShopPanel.SelfTestChipJumps(label: string): { string }
	local lines: { string } = {}
	for _, id in sectionOrder do
		scrollTo(id, false)
		RunService.Heartbeat:Wait()
		RunService.Heartbeat:Wait()
		local residual = headerResidual(id)
		local scale = UIKit.EffectiveScale(scroller)
		local off = if residual then residual / scale else math.huge
		local clamped = off > 0 and scroller.CanvasPosition.Y >= maxCanvas() - 1
		if math.abs(off) <= JUMP_TOLERANCE or clamped then
			table.insert(lines, ("PASS chip %s (%s)%s"):format(id, label, if clamped and math.abs(off) > JUMP_TOLERANCE then " · canvas end" else ""))
		else
			table.insert(lines, ("FAIL chip %s (%s): header %.1f px from the top"):format(id, label, off))
		end
	end
	return lines
end

local function buildChips()
	for _, child in chipBar:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(chipButtons)
	for order, id in sectionOrder do
		local section: ShopConfig.Section? = nil
		for _, s in ShopConfig.Sections do
			if s.Id == id then
				section = s
			end
		end
		if section then
			local button: TextButton
			button = UIKit.Button({
				Name = id .. "Chip",
				Parent = chipBar,
				Style = UIKit.UNSELECTED_STYLE,
				Text = section.Chip,
				TextColor3 = Colors.Muted,
				TextSize = 15,
				Size = UDim2.fromOffset(CHIP_WIDTH, CHIP_HEIGHT),
				LayoutOrder = order,
				ShadowOffset = UITheme.SmallShadowOffset,
				ZIndex = chipBar.ZIndex + 1,
				OnClick = function()
					UIKit.SelectFeedback(button)
					scrollTo(id, true)
				end,
			})
			chipButtons[id] = button
		end
	end
	activeSection = nil
end

--[[ Build / refresh --------------------------------------------------------------- ]]

-- What the page shows; a change means a rebuild (a purchase, a sale
-- starting, an icon arriving, a layout switch).
local function signature(): string
	local deal = ShopController.GetDeal()
	local dealIcons = ""
	if deal then
		-- The deal's part tiles redraw when a part's icon arrives.
		local dealPartKeys: { string } = deal.Item.Parts or {}
		for _, part in dealPartKeys do
			dealIcons ..= (ShopPrices.GetIcon(part) or "") .. ","
		end
	end
	local parts = { if deal then deal.Key .. ":" .. tostring(deal.SlotStart) .. dealIcons else "-", featuredKey() or "-", bestValueKey() or "-", tostring(isNarrow()), tostring(passColumns()), tostring(bannerNarrow(true)), tostring(bannerNarrow(false)) }
	for _, section in ShopConfig.Sections do
		for _, key in keysFor(section) do
			table.insert(parts, key .. (if ShopController.IsOwned(key) then "+" else "") .. (ShopPrices.GetIcon(key) or ""))
		end
	end
	return table.concat(parts, "|")
end

-- Sizes the tail so the last section can scroll its header up to the top
-- like every other chip (the canvas used to end under it: the Safe chip on a
-- phone left its header 32 px low).
local function updateTail()
	local lastId = sectionOrder[#sectionOrder]
	local header = if lastId then headers[lastId] else nil
	if not header or not header.Parent or not tail.Parent then
		return
	end
	local scale = UIKit.EffectiveScale(scroller)
	local blockPx = footer.AbsolutePosition.Y + footer.AbsoluteSize.Y - header.AbsolutePosition.Y
	local windowPx = scroller.AbsoluteWindowSize.Y - 2 * SCROLL_PAD_TOP * scale
	local need = math.max(0, math.ceil((windowPx - blockPx) / scale) - SECTION_GAP)
	if math.abs(tail.Size.Y.Offset - need) > 0.5 then
		tail.Size = UDim2.new(1, 0, 0, need)
	end
end

local function rebuild()
	for _, child in scroller:GetChildren() do
		if child:IsA("GuiObject") and child ~= footer and child ~= tail then
			child:Destroy()
		end
	end
	table.clear(headers)
	table.clear(tiles)
	sectionOrder = {}
	featuredRefs = {}
	dealRefs = {}
	local deal = ShopController.GetDeal()
	local best = bestValueKey()
	local order = 0
	for _, section in ShopConfig.Sections do
		local featured = if section.Id == "Featured" then featuredKey() else nil
		local banner = section.Id == "Featured" or section.Id == "Deal"
		local keys: { string } = if banner then {} else keysFor(section)
		local hasDeal = section.Id == "Deal" and deal ~= nil
		if featured or hasDeal or #keys > 0 then
			table.insert(sectionOrder, section.Id)
			order += 1
			sectionHeader(section, order)
			order += 1
			if hasDeal and deal then
				buildBanner("Deal", deal.Key, order, dealRefs)
			elseif featured then
				buildBanner("Featured", featured, order, featuredRefs)
			elseif section.Id == "Passes" then
				local cards = grid("PassesGrid", order, passColumns(), PASS_HEIGHT)
				for index, key in keys do
					buildPassCard(cards, section, key, index)
				end
			else
				-- A bundle tile lists its parts, so its row is taller.
				local cellHeight = TILE_HEIGHT
				for _, key in keys do
					if item(key).Parts then
						cellHeight = TILE_PARTS_HEIGHT
					end
				end
				local cells = grid(section.Id .. "Grid", order, tileColumns(), cellHeight)
				for index, key in keys do
					buildTile(cells, section, key, index, best)
				end
			end
		end
	end
	footer.LayoutOrder = order + 1
	tail.LayoutOrder = order + 2
	buildChips()
	builtSignature = signature()
	task.spawn(function()
		RunService.Heartbeat:Wait() -- the new rows are laid out first
		updateTail()
	end)
end

-- A banner's live texts: the money line, the worth, the cash amounts in
-- its YOU GET list and the price (unless bought).
local function refreshBanner(refs: BannerRefs)
	local key = refs.Key
	if not key then
		return
	end
	local detail = refs.Detail
	if detail then
		detail.Text = featuredDetail(key)
	end
	local worth = refs.Worth
	if worth then
		worth.Text = ShopController.GetWorthLine(key) or ""
	end
	local list, parts = refs.YouGet, refs.Parts
	if list and parts then
		DealParts.UpdateYouGet(list, parts)
	end
	local price = refs.Price
	if price and not ShopController.IsOwned(key) then
		UIKit.SetButton(price, { Text = ShopController.GetPriceText(key) })
	end
end

-- Text-only refresh (cash amounts, banks, prices, tags, the deal and sale timers).
local function refreshTexts()
	refreshBanner(dealRefs)
	local dealTimer = dealRefs.Timer
	if dealRefs.Key and dealTimer then
		local deal = ShopController.GetDeal()
		if deal then
			dealTimer.Text = ("🔥 DEAL · ends in %s"):format(EventState.FormatTimer(deal.SecondsLeft))
		end
	end
	for _, refs in tiles do
		local main, sub = tileLines(refs.Key)
		if refs.Sub then
			if refs.Main then
				refs.Main.Text = main
			end
			refs.Sub.Text = sub
		end
		if not refs.Owned then
			UIKit.SetButton(refs.Price, { Text = ShopController.GetPriceText(refs.Key) })
		end
	end
	refreshBanner(featuredRefs)
	local key = featuredRefs.Key
	local timer = featuredRefs.Timer
	local sale = if key then item(key).SaleOf else nil
	if timer and sale then
		local _, ends = ShopState.GetLiveSaleFor(sale)
		timer.Text = if ends
			then ("Ends when Admin Abuse ends · %s"):format(EventState.FormatTimer(ends - workspace:GetServerTimeNow()))
			else ""
	end
end

local function refresh()
	if signature() ~= builtSignature then
		local y = scroller.CanvasPosition.Y
		rebuild()
		scroller.CanvasPosition = Vector2.new(0, y)
	end
	refreshTexts()
	onScrolled()
end

local function startTicking()
	refreshToken += 1
	local token = refreshToken
	task.spawn(function()
		while refreshToken == token and modal.IsOpen() do
			task.wait(REFRESH_SECONDS)
			if refreshToken ~= token or not modal.IsOpen() then
				return
			end
			refresh()
		end
	end)
end

local function build()
	modal = UIKit.Modal({
		Name = "ShopPanel",
		Title = "🛒 SHOP",
		DisplayOrder = 141,
		MaxSize = MAX_SIZE,
		HeaderTop = Colors.ShopTop,
	})
	modal.Title.TextColor3 = Colors.GoldLabel
	modal.Title.TextSize = 34
	-- A soft shine sweeping the header now and then.
	local shineStrip = Instance.new("Frame")
	shineStrip.Name = "HeaderShine"
	shineStrip.BackgroundTransparency = 1
	shineStrip.Size = UDim2.new(1, -60, 1, 0)
	shineStrip.ZIndex = modal.Header.ZIndex
	shineStrip.Parent = modal.Header
	addShine(shineStrip, SHINE_EVERY_SECONDS)
	-- A radial-looking violet glow behind the title.
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0, 70, 0, 18)
	glow.Size = UDim2.fromOffset(260, 120)
	glow.BackgroundColor3 = Colors.ShopGlow
	glow.BackgroundTransparency = 0.55
	glow.BorderSizePixel = 0
	glow.ZIndex = modal.Header.ZIndex - 1
	glow.Parent = modal.Header
	UIKit.Corner(glow, 999)
	local glowGradient = Instance.new("UIGradient")
	glowGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	glowGradient.Parent = glow

	local content = modal.Content
	-- The sticky chip bar (outside the page scroller), sideways-scrolling.
	chipBar = Instance.new("ScrollingFrame")
	chipBar.Name = "Chips"
	chipBar.BackgroundTransparency = 1
	chipBar.BorderSizePixel = 0
	chipBar.Size = UDim2.new(1, 0, 0, CHIP_BAR_HEIGHT)
	chipBar.ScrollingDirection = Enum.ScrollingDirection.X
	chipBar.AutomaticCanvasSize = Enum.AutomaticSize.X
	chipBar.CanvasSize = UDim2.new()
	chipBar.ScrollBarThickness = 0
	chipBar.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	chipBar.ZIndex = content.ZIndex
	chipBar.Parent = content
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Padding = UDim.new(0, CHIP_GAP)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chipBar

	-- The one page.
	scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroll"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Position = UDim2.fromOffset(0, CHIP_BAR_HEIGHT + 6)
	scroller.Size = UDim2.new(1, 0, 1, -(CHIP_BAR_HEIGHT + 6))
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.ScrollingDirection = Enum.ScrollingDirection.Y
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = Colors.ShopScrollbar
	scroller.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroller.ZIndex = content.ZIndex
	scroller.Parent = content
	UIKit.Padding(scroller, 12, 12, 12, 12)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, SECTION_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroller

	footer = UIKit.Label({
		Name = "Footer",
		Text = "Prices read live from Roblox · odds are always shown at the Gacha Pad and the Fusion Machine",
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Faint,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 999,
		ZIndex = scroller.ZIndex + 1,
		Parent = scroller,
	})

	tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.BackgroundTransparency = 1
	tail.BorderSizePixel = 0
	tail.Size = UDim2.new(1, 0, 0, 0)
	tail.LayoutOrder = 1000
	tail.Parent = scroller

	scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(onScrolled)
	-- A phone switch or a resize can change the column counts.
	local function relayout()
		if modal.IsOpen() then
			refresh()
			task.defer(updateTail)
		end
	end
	UIKit.LayoutChanged:Connect(relayout)
	scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
end

--[[ Public ------------------------------------------------------------------------- ]]

-- Opens at the top, or scrolled to `section` (a ShopConfig.Sections id:
-- the contextual offer opens Cash or Boosts).
function ShopPanel.Open(section: string?)
	rebuild()
	refreshTexts()
	scroller.CanvasPosition = Vector2.zero
	if not modal.IsOpen() then
		modal.Open()
		ShopController.Track("ShopOpened")
	end
	setActive(sectionOrder[1])
	if section then
		-- Wait for the layout and the pop-in (its UIScale skews positions),
		-- then jump.
		task.spawn(function()
			task.wait(0.25)
			if modal.IsOpen() then
				scrollTo(section, true)
			end
		end)
	end
	startTicking()
end

function ShopPanel.Toggle()
	if modal.IsOpen() then
		modal.Close()
	else
		ShopPanel.Open()
	end
end

function ShopPanel.Init()
	build()
	ShopController.SetShopOpener(ShopPanel.Open)
	-- Owned states, token counts and what's listed change after a purchase
	-- or a sync; prices and icons change when they arrive.
	ShopController.Purchased:Connect(function()
		if modal.IsOpen() then
			refresh()
		end
	end)
	TycoonController.TycoonChanged:Connect(function()
		if modal.IsOpen() then
			refresh()
		end
	end)
	ShopPrices.Changed:Connect(function()
		if modal.IsOpen() then
			refresh()
		end
	end)
end

return ShopPanel
