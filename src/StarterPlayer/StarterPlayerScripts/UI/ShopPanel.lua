--!strict
--[[
	ShopPanel
	---------
	The SHOP modal (the HUD's gold 🛒 SHOP button). Loud and fun to look at;
	every number on it is real:

	  * Header: a gold "🛒 SHOP" on a radial violet glow.
	  * Featured banner: the Starter Pack until bought, then the live sale,
	    then the best value. A warm gradient with a diagonal shine sweep (a
	    client tween every ~3 s), a big icon orb, the title, "Worth ~~227~~
	    R$ if bought one by one" and "SAVE 56%" (both from LIVE prices), or
	    a sale's "normally ~~79~~ R$ · today 49 R$ (−38%)" with its real end
	    time, and a big green Robux price button.
	  * Tabs: 🔥 Deals · ⚡ Boosts · 💰 Cash · 🎟 Passes · 🍀 Luck.
	  * Tiles (4 columns, 2 on a phone): a glossy gradient with the shine
	    sweep, a bobbing icon, the title, a one-line effect (cash tiles show
	    what you'd get right now: "+$4.1M · 20 min of your income"), and a
	    green Robux price button. Ribbons POPULAR / BEST VALUE / VIP; owned
	    passes "✓ OWNED"; Safe Fusion "OWNED 3" plus the buy button.
	  * Footer: "Prices read live from Roblox · odds are always shown at the
	    Gacha Pad and the Fusion Machine".

	Prices come from ShopPrices (live, cached 10 min) through
	ShopController.GetPriceText; nothing here is typed in. Items you can't
	be sold (policy, not set up, a sale outside its window) never show.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local MAX_SIZE = Vector2.new(820, 620)
local FEATURED_HEIGHT = 170
local TAB_HEIGHT = UITheme.MinTapSize
local TILE_HEIGHT = 214
local TILE_GAP = 12
local COLUMNS = { Desktop = 4, Phone = 2 }
local REFRESH_SECONDS = 2
local SHINE_SECONDS = 0.9
local SHINE_EVERY_SECONDS = 3
local BOB_PIXELS = 5
local BOB_SECONDS = 1.1

-- Each tab's tile gradient (UITheme.Gradients keys).
local TAB_GRADIENT: { [string]: string } = {
	Deals = "ShopFeatured",
	Boosts = "Violet",
	Cash = "Green",
	Passes = "Blue",
	Luck = "Teal",
}

type TileRefs = { Key: string, Effect: TextLabel, Price: TextButton, Owned: TextLabel? }

local modal: UIKit.Modal
local scroller: ScrollingFrame
local featured: Frame
local tabsRow: Frame
local grid: Frame
local gridLayout: UIGridLayout
local selectedTab = "Deals"
local tabButtons: { [string]: TextButton } = {}
local tiles: { TileRefs } = {}
local featuredRefs: { Key: string?, Detail: TextLabel?, Price: TextButton?, Timer: TextLabel? } = {}
local refreshToken = 0

--[[ Helpers ------------------------------------------------------------------------- ]]

local function item(key: string): ShopConfig.Item
	return ShopConfig.GetItem(key) :: ShopConfig.Item
end

local function robux(price: number): string
	return ("%s %d"):format(ShopController.ROBUX, price)
end

-- The line under a tile's title: cash packs say what you'd get right now.
local function effectText(key: string): string
	local pack = ShopConfig.CashPacks[key]
	if pack then
		local minutes = pack.Minutes
		local span = if minutes >= 60 then ("%d h"):format(minutes // 60) else ("%d min"):format(minutes)
		return ("%s · %s of your income"):format(
			UIKit.Colored("+" .. NumberFormat.Money(ShopController.GetCashAmount(key)), Colors.Cash),
			span
		)
	end
	if key == "OfflineDouble" then
		return ("×2 your welcome-back cash (+%s)"):format(NumberFormat.Money(TycoonController.GetShop().OfflineDoubleAmount))
	end
	return item(key).Effect
end

-- Shown in the shop at all: offered now, or an owned pass ("✓ OWNED").
local function isListed(key: string): boolean
	return ShopController.IsAvailable(key) or (item(key).Kind == "Pass" and ShopController.IsOwned(key))
end

local function keysForTab(tab: string): { string }
	local keys = {}
	for _, key in ShopConfig.Order do
		local entry = item(key)
		local inTab = entry.Tab == tab
		if tab == "Deals" then
			-- Deals: bundles, the live sale, and the best value.
			inTab = entry.Tab == "Deals" or entry.SaleOf ~= nil or entry.Parts ~= nil or key == ShopConfig.BestValueKey
		elseif entry.SaleOf then
			inTab = false -- a sale lives in Deals and the banner only
		end
		if inTab and isListed(key) then
			table.insert(keys, key)
		end
	end
	return keys
end

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

-- A round icon orb (emoji on a light disc) that bobs gently.
local function iconOrb(parent: Instance, icon: string, size: number, position: UDim2, z: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0)
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
	UIKit.Label({
		Name = "Glyph",
		Text = icon,
		TextSize = math.floor(size * 0.55),
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z + 1,
		Parent = disc,
	})
	TweenService:Create(
		disc,
		TweenInfo.new(BOB_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromOffset(0, -BOB_PIXELS) }
	):Play()
	return holder
end

local function ribbon(parent: Instance, text: string, z: number)
	UIKit.Pill({
		Name = "Ribbon",
		Parent = parent,
		Text = text,
		Gradient = if text == "VIP" then UITheme.Gradients.Gold else UITheme.Gradients.Red,
		Font = Fonts.Display,
		TextSize = 12,
		Height = 22,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		ZIndex = z,
		TextStroke = 1.5,
	})
end

--[[ Featured banner ------------------------------------------------------------------ ]]

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
	if ShopController.IsAvailable(ShopConfig.BestValueKey) then
		return ShopConfig.BestValueKey
	end
	return nil
end

-- The banner's money line, all from live prices.
local function featuredDetail(key: string): string
	local entry = item(key)
	if entry.SaleOf then
		local normal = ShopPrices.Get(entry.SaleOf)
		local today = ShopPrices.Get(key)
		if normal and today then
			local off = ShopConfig.GetSavePercent(today, normal)
			return ("normally <s>%s</s> · today %s%s"):format(robux(normal), robux(today), if off then (" (−%d%%)"):format(off) else "")
		end
		return entry.Effect
	end
	if entry.Parts then
		local worth = ShopPrices.GetPartsTotal(key)
		if worth then
			return ("Worth <s>%s</s> if bought one by one"):format(robux(worth))
		end
		return entry.Effect
	end
	return effectText(key)
end

local function buildFeatured()
	for _, child in featured:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	featuredRefs = {}
	local key = featuredKey()
	featured.Visible = key ~= nil
	if not key then
		return
	end
	local entry = item(key)
	local z = featured.ZIndex + 1
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Colors.White
	fill.ZIndex = z
	fill.Parent = featured
	UIKit.Corner(fill, 20)
	UIKit.Stroke(fill, 3)
	UIKit.PairGradient(fill, UITheme.Gradients.ShopFeatured, 20)
	addShine(fill)

	iconOrb(fill, entry.Icon, 110, UDim2.new(0, 80, 0.5, -55), z + 2)
	local textLeft = 160
	UIKit.Label({
		Name = "Caption",
		Text = if entry.SaleOf then "🔥 ADMIN ABUSE SALE" elseif key == "StarterPack" then "🎁 ONE TIME ONLY" else "⭐ BEST VALUE",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = Colors.Text,
		Position = UDim2.fromOffset(textLeft, 18),
		Size = UDim2.new(1, -(textLeft + 200), 0, 18),
		ZIndex = z + 2,
		Stroke = 1.5,
		Parent = fill,
	})
	UIKit.Label({
		Name = "Title",
		Text = if entry.SaleOf then item(entry.SaleOf).Name else entry.Name,
		Font = Fonts.Display,
		TextSize = 30,
		Position = UDim2.fromOffset(textLeft, 38),
		Size = UDim2.new(1, -(textLeft + 200), 0, 36),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = z + 2,
		Stroke = 3,
		Parent = fill,
	})
	featuredRefs.Detail = UIKit.Label({
		Name = "Detail",
		Text = featuredDetail(key),
		RichText = true,
		Font = Fonts.Body,
		TextSize = 16,
		TextWrapped = true,
		Position = UDim2.fromOffset(textLeft, 78),
		Size = UDim2.new(1, -(textLeft + 200), 0, 40),
		ZIndex = z + 2,
		Stroke = UITheme.Stroke.Text,
		Parent = fill,
	})
	-- "SAVE 56%" from live prices (bundles and sales only).
	local price = ShopPrices.Get(key)
	local save = if entry.SaleOf
		then ShopConfig.GetSavePercent(price, ShopPrices.Get(entry.SaleOf))
		else ShopConfig.GetSavePercent(price, ShopPrices.GetPartsTotal(key))
	if save then
		UIKit.Pill({
			Name = "Save",
			Parent = fill,
			Text = ("SAVE %d%%"):format(save),
			Gradient = UITheme.Gradients.Gold,
			Font = Fonts.Display,
			TextSize = 16,
			Height = 28,
			Position = UDim2.fromOffset(textLeft, 124),
			ZIndex = z + 2,
		})
	end
	if entry.SaleOf then
		featuredRefs.Timer = UIKit.Label({
			Name = "Ends",
			Font = Fonts.BodyHeavy,
			TextSize = 13,
			TextColor3 = Colors.Text,
			Position = UDim2.fromOffset(textLeft + (if save then 110 else 0), 128),
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
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, -2),
		Size = UDim2.fromOffset(170, 64),
		ZIndex = z + 2,
		OnClick = function()
			ShopController.Buy(key)
		end,
	})
	featuredRefs.Key = key
end

--[[ Tiles ------------------------------------------------------------------------- ]]

local function buildTile(key: string, order: number)
	local entry = item(key)
	local holder = Instance.new("Frame")
	holder.Name = key
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = order
	holder.ZIndex = grid.ZIndex + 1
	holder.Parent = grid
	local z = holder.ZIndex + 1
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, -UITheme.SmallShadowOffset)
	fill.BackgroundColor3 = Colors.White
	fill.ZIndex = z
	fill.Parent = holder
	UIKit.Corner(fill, 18)
	UIKit.Stroke(fill, 3)
	UIKit.PairGradient(fill, UITheme.Gradients[TAB_GRADIENT[entry.Tab] or "Violet"] or UITheme.Gradients.Violet)
	-- Gloss: a soft white wash over the top half.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Size = UDim2.fromScale(1, 0.5)
	gloss.BackgroundColor3 = Colors.White
	gloss.BackgroundTransparency = 0.82
	gloss.BorderSizePixel = 0
	gloss.ZIndex = z
	gloss.Parent = fill
	UIKit.Corner(gloss, 18)
	addShine(fill)

	iconOrb(fill, entry.Icon, 64, UDim2.new(0.5, 0, 0, 14), z + 2)
	local ribbonText = entry.Ribbon
	if ribbonText then
		ribbon(fill, ribbonText, z + 4)
	end
	UIKit.Label({
		Name = "Title",
		Text = if entry.SaleOf then item(entry.SaleOf).Name .. " · SALE" else entry.Name,
		Font = Fonts.Display,
		TextSize = 18,
		Position = UDim2.fromOffset(8, 84),
		Size = UDim2.new(1, -16, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = z + 2,
		Stroke = UITheme.Stroke.Text,
		Parent = fill,
	})
	local effect = UIKit.Label({
		Name = "Effect",
		Text = if entry.SaleOf then featuredDetail(key) else effectText(key),
		RichText = true,
		Font = Fonts.Body,
		TextSize = 13,
		TextWrapped = true,
		Position = UDim2.fromOffset(8, 108),
		Size = UDim2.new(1, -16, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = z + 2,
		Stroke = 1.5,
		Parent = fill,
	})
	local owned = ShopController.IsOwned(key)
	local ownedLabel: TextLabel? = nil
	local tokens = TycoonController.GetShop().SafeFusionTokens
	if (key == "SafeFusion1" or key == "SafeFusion5") and tokens > 0 then
		ownedLabel = UIKit.Pill({
			Name = "OwnedCount",
			Parent = fill,
			Text = ("OWNED %d"):format(tokens),
			Color = Colors.Ink,
			TextColor3 = Colors.Text,
			Font = Fonts.BodyHeavy,
			TextSize = 12,
			Height = 20,
			Position = UDim2.fromOffset(8, 8),
			ZIndex = z + 4,
		})
	end
	local button = UIKit.Button({
		Name = "Buy",
		Parent = fill,
		Style = if owned then "Disabled" else "Green",
		Text = if owned then "✓ OWNED" else ShopController.GetPriceText(key),
		TextColor3 = if owned then Colors.Muted else Colors.Text,
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, UITheme.MinTapSize + 4),
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z + 2,
		OnClick = function()
			if not ShopController.IsOwned(key) then
				ShopController.Buy(key)
			end
		end,
	})
	table.insert(tiles, { Key = key, Effect = effect, Price = button, Owned = ownedLabel })
end

local function buildGrid()
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	tiles = {}
	for order, key in keysForTab(selectedTab) do
		buildTile(key, order)
	end
	for tab, button in tabButtons do
		local selected = tab == selectedTab
		UIKit.SetSelected(button, selected)
	end
end

local function applyColumns()
	local columns = if UIKit.IsPhone() then COLUMNS.Phone else COLUMNS.Desktop
	-- 1 px of slack so rounding never wraps a row (see GiftsPanel).
	gridLayout.CellSize = UDim2.new(1 / columns, -TILE_GAP * (columns - 1) / columns - 1, 0, TILE_HEIGHT)
	gridLayout.FillDirectionMaxCells = columns
end

--[[ Refresh ------------------------------------------------------------------------- ]]

-- Text-only refresh (cash amounts, prices, the sale timer); cheap.
local function refreshTexts()
	for _, refs in tiles do
		local entry = item(refs.Key)
		refs.Effect.Text = if entry.SaleOf then featuredDetail(refs.Key) else effectText(refs.Key)
		if not ShopController.IsOwned(refs.Key) then
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

-- Full rebuild (what's listed can change: a purchase, a sale starting).
local function rebuild()
	buildFeatured()
	buildGrid()
	refreshTexts()
end

local function startTicking()
	refreshToken += 1
	local token = refreshToken
	task.spawn(function()
		local lastFeatured = featuredKey()
		while refreshToken == token and modal.IsOpen() do
			task.wait(REFRESH_SECONDS)
			if refreshToken ~= token or not modal.IsOpen() then
				return
			end
			-- A sale opening or closing changes the banner and the tiles.
			local nowFeatured = featuredKey()
			if nowFeatured ~= lastFeatured then
				lastFeatured = nowFeatured
				rebuild()
			else
				refreshTexts()
			end
		end
	end)
end

--[[ Build ------------------------------------------------------------------------- ]]

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
	scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroll"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = Colors.Faint
	scroller.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroller.ZIndex = content.ZIndex
	scroller.Parent = content
	UIKit.Padding(scroller, 4, 6, 10, 4)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroller

	featured = Instance.new("Frame")
	featured.Name = "Featured"
	featured.BackgroundTransparency = 1
	featured.Size = UDim2.new(1, 0, 0, FEATURED_HEIGHT)
	featured.LayoutOrder = 1
	featured.ZIndex = scroller.ZIndex + 1
	featured.Parent = scroller

	tabsRow = Instance.new("Frame")
	tabsRow.Name = "Tabs"
	tabsRow.BackgroundTransparency = 1
	tabsRow.Size = UDim2.new(1, 0, 0, TAB_HEIGHT + UITheme.SmallShadowOffset)
	tabsRow.LayoutOrder = 2
	tabsRow.ZIndex = scroller.ZIndex + 1
	tabsRow.Parent = scroller
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabsRow
	local tabCount = #ShopConfig.Tabs
	for order, tab in ShopConfig.Tabs do
		tabButtons[tab.Id] = UIKit.Button({
			Name = tab.Id .. "Tab",
			Parent = tabsRow,
			Style = "Disabled",
			Text = tab.Label,
			TextSize = 15,
			Size = UDim2.new(1 / tabCount, -8 * (tabCount - 1) / tabCount, 0, TAB_HEIGHT),
			LayoutOrder = order,
			ShadowOffset = UITheme.SmallShadowOffset,
			ZIndex = tabsRow.ZIndex,
			OnClick = function()
				selectedTab = tab.Id
				buildGrid()
				refreshTexts()
			end,
		})
	end

	grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 3
	grid.ZIndex = scroller.ZIndex + 1
	grid.Parent = scroller
	gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	applyColumns()

	UIKit.Label({
		Name = "Footer",
		Text = "Prices read live from Roblox · odds are always shown at the Gacha Pad and the Fusion Machine",
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Faint,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 4,
		ZIndex = scroller.ZIndex + 1,
		Parent = scroller,
	})

	UIKit.LayoutChanged:Connect(function()
		applyColumns()
	end)
end

--[[ Public ------------------------------------------------------------------------- ]]

function ShopPanel.Open(tab: string?)
	if tab then
		selectedTab = tab
	end
	rebuild()
	if not modal.IsOpen() then
		modal.Open()
		ShopController.Track("ShopOpened")
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
	-- Owned states, token counts and what's listed change after a purchase
	-- or a sync; prices change when they arrive.
	ShopController.Purchased:Connect(function()
		if modal.IsOpen() then
			rebuild()
		end
	end)
	TycoonController.TycoonChanged:Connect(function()
		if modal.IsOpen() then
			refreshTexts()
		end
	end)
	ShopPrices.Changed:Connect(function()
		if modal.IsOpen() then
			rebuild()
		end
	end)
end

return ShopPanel
