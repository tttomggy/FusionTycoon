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
	      Featured  one wide banner: the Starter Pack until bought, then a
	                live sale, then the best value; shine sweep.
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
local ShopState = require(ReplicatedStorage.Shared.Modules.ShopState)
local ShopPrices = require(ReplicatedStorage.Shared.Modules.ShopPrices)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local Controllers = script.Parent.Parent.Controllers
local TycoonController = require(Controllers.TycoonController)
local ShopController = require(Controllers.ShopController)
local UIKit = require(script.Parent.UIKit)

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
local FEATURED_HEIGHT = 170
local FEATURED_NARROW_HEIGHT = 262
local PASS_HEIGHT = 140
local TILE_HEIGHT = 244
local GRID_GAP = 12
local NARROW_WIDTH = 560 -- logical px of page width under which tiles go 2-up
local REFRESH_SECONDS = 2
local SHINE_SECONDS = 0.9
local SHINE_EVERY_SECONDS = 3
local BOB_PIXELS = 5
local BOB_SECONDS = 1.1
local SCROLL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_SCALE = 1.03
local PRESS_SCALE = 0.96
local ACTIVE_LINE = 60 -- px below the page top where a header counts as "on screen"

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
local chipButtons: { [string]: TextButton } = {}
local headers: { [string]: Frame } = {}
local sectionOrder: { string } = {}
local tiles: { TileRefs } = {}
local featuredRefs: { Key: string?, Detail: TextLabel?, Price: TextButton?, Timer: TextLabel? } = {}
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

-- Starter Pack until bought, then the live sale, then the best value.
local function featuredKey(): string?
	if ShopController.IsAvailable("StarterPack") then
		return "StarterPack"
	end
	for _, sale in ShopConfig.Sales do
		if ShopController.IsAvailable(sale.SaleKey) then
			return sale.SaleKey
		end
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
		return UIKit.Colored("+" .. NumberFormat.Money(ShopController.GetCashAmount(key)), Colors.Cash),
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

-- A diagonal white shine sweeping across `frame` every few seconds.
local function addShine(frame: GuiObject)
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
		TweenInfo.new(SHINE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, false, SHINE_EVERY_SECONDS),
		{ Position = UDim2.fromScale(1.4, 0.5) }
	):Play()
end

-- The item's icon: the live store icon (what Harris uploaded with the
-- pass / product), else the emoji in a light circle. Bobs gently.
local function iconView(parent: Instance, key: string, size: number, position: UDim2, anchor: Vector2, z: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = anchor
	holder.Position = position
	holder.Size = UDim2.fromOffset(size, size)
	holder.ZIndex = z
	holder.Parent = parent
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.Size = UDim2.fromScale(1, 1)
	disc.BackgroundColor3 = Colors.White
	disc.BackgroundTransparency = 0.75
	disc.ZIndex = z
	disc.Parent = holder
	UIKit.Corner(disc, 999)
	UIKit.Stroke(disc, 3)
	local image = ShopPrices.GetIcon(key)
	if image then
		disc.BackgroundTransparency = 1
		local stroke = disc:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = false
		end
		local picture = Instance.new("ImageLabel")
		picture.Name = "Image"
		picture.BackgroundTransparency = 1
		picture.Size = UDim2.fromScale(1, 1)
		picture.Image = image
		picture.ScaleType = Enum.ScaleType.Fit
		picture.ZIndex = z + 1
		picture.Parent = disc
	else
		UIKit.Label({
			Name = "Glyph",
			Text = item(key).Icon,
			TextSize = math.floor(size * 0.55),
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 1,
			Parent = disc,
		})
	end
	TweenService:Create(
		disc,
		TweenInfo.new(BOB_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromOffset(0, -BOB_PIXELS) }
	):Play()
	return holder
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
		TextSize = 12,
		Height = 22,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		ZIndex = z,
	})
end

-- The chunky rounded panel every tile / card sits on: a light gradient in
-- the section colour, a coloured outline, a gloss, the ink shadow. The
-- holder hovers to 1.03 and bounces on press.
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
	local stops: { { any } } = { { 0, UITheme.TowardInk(pair.Top, 0.35) }, { 1, UITheme.TowardInk(pair.Bottom, 0.62) } }
	local body = UIKit.Panel({
		Name = "Fill",
		Parent = holder,
		Size = UDim2.new(1, 0, 1, -UITheme.SmallShadowOffset),
		Gradient = stops,
		Radius = 18,
		StrokeThickness = 3,
		ShadowOffset = UITheme.SmallShadowOffset,
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
	body.MouseEnter:Connect(function()
		TweenService:Create(scale, HOVER_INFO, { Scale = HOVER_SCALE }):Play()
	end)
	body.MouseLeave:Connect(function()
		TweenService:Create(scale, HOVER_INFO, { Scale = 1 }):Play()
	end)
	return body, holder, scale
end

-- The green buy button (owned pass: grey "OWNED ✓"); pressing it bounces
-- the tile.
local function buyButton(parent: Frame, key: string, scale: UIScale, props: { [string]: any }): TextButton
	local owned = item(key).Kind == "Pass" and ShopController.IsOwned(key)
	local button = UIKit.Button({
		Name = "Buy",
		Parent = parent,
		Style = if owned then "Disabled" else "Green",
		Text = if owned then "OWNED ✓" else ShopController.GetPriceText(key),
		TextColor3 = if owned then Colors.Muted else Colors.Text,
		TextSize = props.TextSize or 20,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = parent.ZIndex + 3,
		OnClick = function()
			if not (item(key).Kind == "Pass" and ShopController.IsOwned(key)) then
				ShopController.Buy(key)
			end
		end,
	})
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, PRESS_INFO, { Scale = PRESS_SCALE }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, HOVER_INFO, { Scale = HOVER_SCALE }):Play()
	end)
	return button
end

local function textLabel(parent: Frame, name: string, props: { [string]: any }): TextLabel
	props.Name = name
	props.Parent = parent
	props.ZIndex = parent.ZIndex + 3
	return UIKit.Label(props)
end

--[[ Sections -------------------------------------------------------------------------- ]]

local function sectionHeader(section: ShopConfig.Section, order: number)
	local row = Instance.new("Frame")
	row.Name = section.Id .. "Header"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	row.LayoutOrder = order
	row.ZIndex = scroller.ZIndex + 1
	row.Parent = scroller
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	UIKit.Label({
		Name = "Title",
		Text = ("%s %s"):format(section.Icon, section.Title),
		Font = Fonts.Display,
		TextSize = 26,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, HEADER_HEIGHT),
		LayoutOrder = 1,
		ZIndex = row.ZIndex,
		Stroke = UITheme.Stroke.Text,
		Parent = row,
	})
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = sectionPair(section).Top
	divider.BackgroundTransparency = 0.35
	divider.BorderSizePixel = 0
	divider.Size = UDim2.fromOffset(0, 3)
	divider.LayoutOrder = 2
	divider.ZIndex = row.ZIndex
	divider.Parent = row
	UIKit.Corner(divider, 2)
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

-- The banner's money line, all from live prices.
local function featuredDetail(key: string): string
	local entry = item(key)
	if entry.SaleOf then
		return saleText(key)
	end
	if entry.Parts then
		local worth = ShopPrices.GetPartsTotal(key)
		if worth then
			return ("Worth <s>%s</s> if bought one by one"):format(robux(worth))
		end
		return entry.Effect
	end
	local main, sub = tileLines(key)
	return ("%s · %s"):format(main, sub)
end

local function buildFeatured(key: string, order: number)
	local entry = item(key)
	local narrow = pageWidth() < NARROW_WIDTH
	local holder = Instance.new("Frame")
	holder.Name = "FeaturedBanner"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, if narrow then FEATURED_NARROW_HEIGHT else FEATURED_HEIGHT)
	holder.LayoutOrder = order
	holder.ZIndex = scroller.ZIndex + 1
	holder.Parent = scroller
	local z = holder.ZIndex + 1
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, -UITheme.SmallShadowOffset)
	fill.BackgroundColor3 = Colors.White
	fill.ZIndex = z
	fill.Parent = holder
	UIKit.Corner(fill, 20)
	UIKit.Stroke(fill, 3)
	UIKit.PairGradient(fill, UITheme.Gradients.ShopFeatured, 20)
	UIKit.Shadow(fill, UITheme.SmallShadowOffset)
	addShine(fill)

	local iconSize = if narrow then 72 else 110
	iconView(
		fill,
		key,
		iconSize,
		if narrow then UDim2.fromOffset(16, 16) else UDim2.new(0, 24, 0.5, 0),
		if narrow then Vector2.zero else Vector2.new(0, 0.5),
		z + 2
	)
	local textLeft = if narrow then 100 else 152
	local textRight = if narrow then 16 else 210
	local caption = if entry.SaleOf then "🔥 ADMIN ABUSE SALE" elseif key == "StarterPack" then "🎁 ONE TIME ONLY" else "⭐ BEST VALUE"
	UIKit.Label({
		Name = "Caption",
		Text = caption,
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		Position = UDim2.fromOffset(textLeft, 18),
		Size = UDim2.new(1, -(textLeft + textRight), 0, 18),
		ZIndex = z + 2,
		Stroke = UITheme.WarmTextStroke,
		Parent = fill,
	})
	UIKit.Label({
		Name = "Title",
		Text = if entry.SaleOf then item(entry.SaleOf).Name else entry.Name,
		Font = Fonts.Display,
		TextSize = if narrow then 24 else 30,
		Position = UDim2.fromOffset(textLeft, 38),
		Size = UDim2.new(1, -(textLeft + textRight), 0, 36),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = z + 2,
		Stroke = 3,
		Parent = fill,
	})
	local detailLeft = if narrow then 16 else textLeft
	featuredRefs.Detail = UIKit.Label({
		Name = "Detail",
		Text = featuredDetail(key),
		RichText = true,
		Font = Fonts.Body,
		TextSize = 16,
		TextWrapped = true,
		Position = UDim2.fromOffset(detailLeft, if narrow then 100 else 78),
		Size = UDim2.new(1, -(detailLeft + textRight), 0, 40),
		ZIndex = z + 2,
		Stroke = UITheme.Stroke.Text,
		Parent = fill,
	})
	-- "SAVE 56%" from live prices (bundles and sales only).
	local tag = tagText(key, nil)
	local tagY = if narrow then 144 else 124
	if tag then
		UIKit.Pill({
			Name = "Save",
			Parent = fill,
			Text = tag,
			Gradient = UITheme.Gradients.Gold,
			Font = Fonts.Display,
			TextSize = 16,
			Height = 28,
			Position = UDim2.fromOffset(detailLeft, tagY),
			ZIndex = z + 2,
		})
	end
	if entry.SaleOf then
		featuredRefs.Timer = UIKit.Label({
			Name = "Ends",
			Font = Fonts.BodyHeavy,
			TextSize = 13,
			Position = UDim2.fromOffset(detailLeft + (if tag then 110 else 0), tagY + 4),
			Size = UDim2.fromOffset(300, 20),
			ZIndex = z + 2,
			Stroke = 1.5,
			Parent = fill,
		})
	end
	featuredRefs.Price = UIKit.Button({
		Name = "Buy",
		Parent = fill,
		Style = "Green",
		Text = ShopController.GetPriceText(key),
		TextSize = 28,
		AnchorPoint = if narrow then Vector2.new(0.5, 1) else Vector2.new(1, 0.5),
		Position = if narrow then UDim2.new(0.5, 0, 1, -14) else UDim2.new(1, -20, 0.5, -2),
		Size = if narrow then UDim2.new(1, -32, 0, 56) else UDim2.fromOffset(170, 64),
		ZIndex = z + 2,
		OnClick = function()
			ShopController.Buy(key)
		end,
	})
	featuredRefs.Key = key
end

-- A pass: a big card (large icon, name, benefit, buy).
local function buildPassCard(parent: Frame, section: ShopConfig.Section, key: string, order: number)
	local entry = item(key)
	local body, _, scale = tilePanel(parent, key, order, sectionPair(section))
	iconView(body, key, 88, UDim2.new(0, 16, 0.5, 0), Vector2.new(0, 0.5), body.ZIndex + 2)
	textLabel(body, "Title", {
		Text = entry.Name,
		Font = Fonts.Display,
		TextSize = 22,
		Position = UDim2.fromOffset(118, 14),
		Size = UDim2.new(1, -134, 0, 26),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Stroke = UITheme.Stroke.Text,
	})
	local main = textLabel(body, "Main", {
		Text = entry.Effect,
		Font = Fonts.Body,
		TextSize = 14,
		TextWrapped = true,
		Position = UDim2.fromOffset(118, 42),
		Size = UDim2.new(1, -134, 0, 36),
		TextYAlignment = Enum.TextYAlignment.Top,
		Stroke = 1.5,
	})
	local button = buyButton(body, key, scale, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 118, 1, -14),
		Size = UDim2.new(1, -134, 0, UITheme.MinTapSize),
	})
	table.insert(tiles, { Key = key, Main = main, Price = button, Owned = ShopController.IsOwned(key) })
end

-- A boost / cash / luck / safe tile.
local function buildTile(parent: Frame, section: ShopConfig.Section, key: string, order: number, best: string?)
	local entry = item(key)
	local body, _, scale = tilePanel(parent, key, order, sectionPair(section))
	iconView(body, key, 72, UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0), body.ZIndex + 2)
	local tag = tagText(key, best)
	if tag then
		cornerTag(body, tag, body.ZIndex + 5)
	end
	textLabel(body, "Title", {
		Text = if entry.SaleOf then item(entry.SaleOf).Name .. " · SALE" else entry.Name,
		Font = Fonts.Display,
		TextSize = 19,
		Position = UDim2.fromOffset(8, 96),
		Size = UDim2.new(1, -16, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Stroke = UITheme.Stroke.Text,
	})
	local mainText, subText = tileLines(key)
	local isCash = ShopConfig.CashPacks[key] ~= nil
	local main = textLabel(body, "Main", {
		Text = mainText,
		RichText = true,
		Font = if isCash then Fonts.Display else Fonts.BodyHeavy,
		TextSize = if isCash then 20 else 13,
		TextWrapped = true,
		Position = UDim2.fromOffset(8, 120),
		Size = UDim2.new(1, -16, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = 1.5,
	})
	local sub = textLabel(body, "Sub", {
		Text = subText,
		RichText = true,
		Font = Fonts.Body,
		TextSize = 12,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		Position = UDim2.fromOffset(8, 144),
		Size = UDim2.new(1, -16, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Stroke = 1,
	})
	local button = buyButton(body, key, scale, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, UITheme.MinTapSize + 4),
	})
	table.insert(tiles, { Key = key, Main = main, Sub = sub, Price = button, Owned = false })
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
local SCROLL_PAD_TOP = 4 -- the page's UIPadding top
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
	local parts = { featuredKey() or "-", bestValueKey() or "-", tostring(isNarrow()), tostring(passColumns()) }
	for _, section in ShopConfig.Sections do
		for _, key in keysFor(section) do
			table.insert(parts, key .. (if ShopController.IsOwned(key) then "+" else "") .. (ShopPrices.GetIcon(key) or ""))
		end
	end
	return table.concat(parts, "|")
end

local function rebuild()
	for _, child in scroller:GetChildren() do
		if child:IsA("GuiObject") and child ~= footer then
			child:Destroy()
		end
	end
	table.clear(headers)
	table.clear(tiles)
	sectionOrder = {}
	featuredRefs = {}
	local best = bestValueKey()
	local order = 0
	for _, section in ShopConfig.Sections do
		local featured = if section.Id == "Featured" then featuredKey() else nil
		local keys: { string } = if section.Id == "Featured" then {} else keysFor(section)
		if featured or #keys > 0 then
			table.insert(sectionOrder, section.Id)
			order += 1
			sectionHeader(section, order)
			order += 1
			if featured then
				buildFeatured(featured, order)
			elseif section.Id == "Passes" then
				local cards = grid("PassesGrid", order, passColumns(), PASS_HEIGHT)
				for index, key in keys do
					buildPassCard(cards, section, key, index)
				end
			else
				local cells = grid(section.Id .. "Grid", order, tileColumns(), TILE_HEIGHT)
				for index, key in keys do
					buildTile(cells, section, key, index, best)
				end
			end
		end
	end
	footer.LayoutOrder = order + 1
	buildChips()
	builtSignature = signature()
end

-- Text-only refresh (cash amounts, banks, prices, tags, the sale timer).
local function refreshTexts()
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
	local key = featuredRefs.Key
	if key then
		local detail = featuredRefs.Detail
		if detail then
			detail.Text = featuredDetail(key)
		end
		local price = featuredRefs.Price
		if price then
			UIKit.SetButton(price, { Text = ShopController.GetPriceText(key) })
		end
		local timer = featuredRefs.Timer
		local sale = item(key).SaleOf
		if timer and sale then
			local _, ends = ShopState.GetLiveSaleFor(sale)
			timer.Text = if ends
				then ("Ends when Admin Abuse ends · %s"):format(EventState.FormatTimer(ends - workspace:GetServerTimeNow()))
				else ""
		end
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
	scroller.ScrollBarImageColor3 = Colors.Faint
	scroller.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroller.ZIndex = content.ZIndex
	scroller.Parent = content
	UIKit.Padding(scroller, 4, 8, 12, 4)
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

	scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(onScrolled)
	-- A phone switch or a resize can change the column counts.
	local function relayout()
		if modal.IsOpen() then
			refresh()
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
