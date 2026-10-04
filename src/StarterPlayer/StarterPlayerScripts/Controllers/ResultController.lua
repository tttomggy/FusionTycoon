--[[
	ResultController
	----------------
	What you see after a fusion or a gacha pull:

	  * Big result card (centre) - Epic/Legendary/Mythic fusion successes and
	    Epic+ gacha pulls. Sunburst, tier name, 132 px orb, DISPLAY IT / NICE.
	    Fusion cards wait for FusionController.FusionResolved, i.e. after the
	    machine's reveal animation, so the card never spoils it.
	  * Fail card (bottom) - a failed fusion, 3 s, with an AGAIN button.
	  * Small pull card (bottom) - Common/Rare gacha pulls; each new pull
	    replaces the previous card.

	  * Pull x10 grid (centre) - all ten pulls popping in 0.06 s apart; the
	    best one (by GetItemCashPerSecond) is outlined and, if it qualifies,
	    also gets the big card.
	  * Rebirth card (centre) - "REBIRTH 3!" with "Income x2.5 · Luck +15%"
	    on a successful RebirthResult (RebirthPanel plays the flash).
	  * Heist cards (centre) - "HEIST COMPLETE!" for a thief who got home,
	    "<name> stole your <item>" for the victim (HeistController).
	  * Welcome-back card (modal) - offline earnings, once per snapshot that
	    brings new PendingOffline; COLLECT fires ClaimOffline and bursts coins.

	Rare fusion successes keep the top banner (AnnouncementController).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local OfflineConfig = require(ReplicatedStorage.Shared.Config.OfflineConfig)
local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local HowToHeistPanel = require(script.Parent.Parent.UI.HowToHeistPanel)
local RevealEffects = require(script.Parent.Parent.Effects.RevealEffects)
local FusionController = require(script.Parent.FusionController)
local TycoonController = require(script.Parent.TycoonController)
local ItemController = require(script.Parent.ItemController)
local HudController = require(script.Parent.HudController)
local ToastController = require(script.Parent.ToastController)

local ResultController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local BIG_CARD_SIZE = Vector2.new(380, 420)
local SUNBURST_RAYS = 12
local SUNBURST_DEGREES_PER_SECOND = 20
local SUNBURST_RAY_LENGTH = 720

local BOTTOM_CARD_OFFSET = UITheme.BottomStackOffset -- above the HUD buttons and REBIRTH!, same baseline as toasts
local FAIL_CARD_SIZE = Vector2.new(470, 92)
local PULL_CARD_SIZE = Vector2.new(440, 74)
local BOTTOM_CARD_SECONDS = 3

local MYTHIC_SHAKE_MAGNITUDE = 0.35
local MYTHIC_SHAKE_SECONDS = 0.5

local screenGui: ScreenGui

--[[ Helpers ------------------------------------------------------------------- ]]

-- "Golden Star Core" for a mutated item, "Star Core" otherwise.
local function itemName(item: any): string
	local def = ItemConfig.GetItemById(item.ItemId)
	return MutationConfig.GetDisplayName(if def then def.Name else tostring(item.ItemId), item.Mutation)
end

-- What `item` earns on a pedestal, income multiplier included.
local function earnRate(item: any): number
	return TycoonConfig.GetItemCashPerSecond(item.Tier, item.Mutation) * TycoonController.GetIncomeMultiplier()
end

--[[ Big result card -------------------------------------------------------------- ]]

local bigHolder: Frame? = nil
local sunburstConnection: RBXScriptConnection? = nil

local function closeBigCard()
	if sunburstConnection then
		sunburstConnection:Disconnect()
		sunburstConnection = nil
	end
	local holder = bigHolder
	bigHolder = nil
	if holder then
		local tween = UIKit.PopOut(holder)
		tween.Completed:Once(function()
			holder:Destroy()
		end)
	end
end

local function buildSunburst(body: Frame)
	local burst = Instance.new("CanvasGroup")
	burst.Name = "Sunburst"
	burst.BackgroundTransparency = 1
	burst.Size = UDim2.fromScale(1, 1)
	burst.ZIndex = body.ZIndex + 1
	burst.Parent = body
	UIKit.Corner(burst, 24)

	local spinner: GuiObject
	if UITheme.Icons.Sunburst ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = UITheme.Icons.Sunburst
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.42)
		image.Size = UDim2.fromOffset(SUNBURST_RAY_LENGTH, SUNBURST_RAY_LENGTH)
		image.ImageTransparency = 0.6
		image.ZIndex = burst.ZIndex
		image.Parent = burst
		spinner = image
	else
		local pivot = Instance.new("Frame")
		pivot.Name = "Rays"
		pivot.BackgroundTransparency = 1
		pivot.AnchorPoint = Vector2.new(0.5, 0.5)
		pivot.Position = UDim2.fromScale(0.5, 0.42)
		pivot.Size = UDim2.fromOffset(SUNBURST_RAY_LENGTH, SUNBURST_RAY_LENGTH)
		pivot.ZIndex = burst.ZIndex
		pivot.Parent = burst
		-- 12 thin bars through the centre = 24 rays.
		for index = 1, SUNBURST_RAYS do
			local ray = Instance.new("Frame")
			ray.Name = "Ray"
			ray.BackgroundColor3 = Colors.White
			ray.BackgroundTransparency = 0.9
			ray.BorderSizePixel = 0
			ray.AnchorPoint = Vector2.new(0.5, 0.5)
			ray.Position = UDim2.fromScale(0.5, 0.5)
			ray.Size = UDim2.new(0, 10, 1, 0)
			ray.Rotation = (index - 1) * (180 / SUNBURST_RAYS)
			ray.ZIndex = burst.ZIndex
			ray.Parent = pivot
		end
		spinner = pivot
	end

	-- Rotating the parent rotates every ray around the shared centre.
	sunburstConnection = RunService.RenderStepped:Connect(function(dt: number)
		spinner.Rotation = (spinner.Rotation + SUNBURST_DEGREES_PER_SECOND * dt) % 360
	end)
end

local function onDisplayIt(uid: string)
	closeBigCard()
	if not ItemController.PlaceOnFirstEmpty(uid) then
		HudController.OpenInventory()
		ToastController.Show("Pedestals full · remove one first", "Error")
	end
end

type BigCardInfo = {
	Caption: string,
	Item: any,
	Description: string,
}

local function showBigCard(info: BigCardInfo)
	if bigHolder then
		if sunburstConnection then
			sunburstConnection:Disconnect()
			sunburstConnection = nil
		end
		(bigHolder :: Frame):Destroy()
		bigHolder = nil
	end

	local tier = info.Item.Tier :: string
	local tierColor = FusionConfig.TierAccentColors[tier] or Colors.Text
	local tierLight = UITheme.GetTierLight(tier)

	local body, holder = UIKit.Panel({
		Name = "BigResult",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BIG_CARD_SIZE.X, BIG_CARD_SIZE.Y),
		Gradient = {
			{ 0, Colors.Panel },
			{ 0.25, Colors.ResultMid },
			{ 0.5, UITheme.TowardInk(tierColor, 0.5) },
			{ 0.75, Colors.ResultMid },
			{ 1, Colors.Panel },
		},
		Radius = 24,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	bigHolder = holder
	buildSunburst(body)
	local z = body.ZIndex + 3

	UIKit.Label({
		Name = "Caption",
		Text = info.Caption,
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = tierLight,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = body,
	})
	UIKit.Label({
		Name = "TierName",
		Text = tier:upper() .. "!",
		Font = Fonts.Display,
		TextSize = 64,
		TextColor3 = tierLight,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 4,
		Parent = body,
	})

	UIKit.MutationCardStroke(body, info.Item.Mutation)
	local orb = UIKit.TierOrb(tier, 132, nil, info.Item.Mutation)
	orb.AnchorPoint = Vector2.new(0.5, 0)
	orb.Position = UDim2.new(0.5, 0, 0, 116)
	orb.ZIndex = z
	orb.Parent = body
	UIKit.MutationPill({
		Parent = body,
		Mutation = info.Item.Mutation,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 228),
		TextSize = 14,
		Height = 24,
		ZIndex = z + 1,
	})

	UIKit.Label({
		Name = "ItemName",
		Text = itemName(info.Item),
		Font = Fonts.Display,
		TextSize = 28,
		Position = UDim2.fromOffset(12, 258),
		Size = UDim2.new(1, -24, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Label({
		Name = "Description",
		Text = info.Description,
		Font = Fonts.Body,
		TextSize = 15,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		Position = UDim2.fromOffset(20, 294),
		Size = UDim2.new(1, -40, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = z,
		Parent = body,
	})

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.AnchorPoint = Vector2.new(0.5, 0)
	buttons.Position = UDim2.new(0.5, 0, 0, 342)
	buttons.Size = UDim2.fromOffset(170 + 12 + 120, 52)
	buttons.ZIndex = z
	buttons.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = buttons

	local uid = info.Item.Uid :: string
	UIKit.Button({
		Name = "DisplayIt",
		Parent = buttons,
		Style = "Green",
		Text = "DISPLAY IT",
		TextSize = 20,
		Size = UDim2.fromOffset(170, 52),
		LayoutOrder = 1,
		ZIndex = z,
		OnClick = function()
			onDisplayIt(uid)
		end,
	})
	UIKit.Button({
		Name = "Nice",
		Parent = buttons,
		Style = "Disabled",
		Text = "NICE",
		TextSize = 20,
		Size = UDim2.fromOffset(120, 52),
		LayoutOrder = 2,
		ZIndex = z,
		OnClick = closeBigCard,
	})

	UIKit.PopIn(holder)
	if tier == "Mythic" or tier == "Secret" then
		RevealEffects.ShakeCamera(MYTHIC_SHAKE_MAGNITUDE, MYTHIC_SHAKE_SECONDS)
	end
end

--[[ Event mutation reveal --------------------------------------------------------------
	Charged / Void / Celestial (MutationConfig.IsEventOnly) replace the normal
	result card with this one, from any source (a Void Moon fusion, a
	lightning strike, a meteor core, /eventmut): the mutation colour behind
	a sunburst, "EVENT-ONLY MUTATION", the giant word ("VOID!"), the orb in
	its shell, the item, "VOID ×8 income", how you got it, the Index count,
	and DISPLAY / OK. Everyone else sees the SERVER banner
	(AnnouncementController, Verb "event").
]]

local EVENT_CARD_SIZE = Vector2.new(400, 500)
local EVENT_SHAKE_MAGNITUDE = 0.5
local EVENT_SHAKE_SECONDS = 0.6

local function oneIn(chance: number): number
	return math.floor(1 / chance + 0.5)
end

local HOW_YOU_GOT_IT: { [string]: () -> string } = {
	Void = function()
		return ("🌙 You fused during a Void Moon. Only 1 in %d fusions come out Void, and Void Moons are rare."):format(
			oneIn(EventConfig.VoidChance)
		)
	end,
	Charged = function()
		return "⚡ Lightning hit it during a Power Surge."
	end,
	Celestial = function()
		return "☄ You found it in a meteor core."
	end,
}

-- "Void 3 / 17": found Index entries with `mutation`, out of every item.
local function indexCount(mutation: string): (number, number)
	local found = 0
	local suffix = "|" .. mutation
	for key, on in TycoonController.GetIndex() do
		if on and key:sub(-#suffix) == suffix then
			found += 1
		end
	end
	return found, #ItemConfig.Items
end

local function showEventMutationCard(item: any, newIndex: boolean)
	if bigHolder then
		if sunburstConnection then
			sunburstConnection:Disconnect()
			sunburstConnection = nil
		end
		(bigHolder :: Frame):Destroy()
		bigHolder = nil
	end
	local mutation = item.Mutation :: string
	local color = UITheme.GetMutationColor(mutation) or Colors.Text
	local tier = item.Tier :: string

	local body, holder = UIKit.Panel({
		Name = "EventMutationReveal",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(EVENT_CARD_SIZE.X, EVENT_CARD_SIZE.Y),
		-- A "radial" look: the mutation colour in the middle fading to ink.
		Gradient = {
			{ 0, Colors.Ink },
			{ 0.3, UITheme.TowardInk(color, 0.55) },
			{ 0.5, UITheme.TowardInk(color, 0.25) },
			{ 0.7, UITheme.TowardInk(color, 0.55) },
			{ 1, Colors.Ink },
		},
		Radius = 24,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	bigHolder = holder
	buildSunburst(body)
	UIKit.MutationCardStroke(body, mutation)
	local z = body.ZIndex + 3
	local function label(name: string, text: string, font: Font, size: number, y: number, height: number, textColor: Color3, stroke: number?)
		return UIKit.Label({
			Name = name,
			Text = text,
			Font = font,
			TextSize = size,
			TextColor3 = textColor,
			TextWrapped = true,
			Position = UDim2.fromOffset(16, y),
			Size = UDim2.new(1, -32, 0, height),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z,
			Stroke = stroke,
			Parent = body,
		})
	end
	label("Caption", "EVENT-ONLY MUTATION", Fonts.BodyHeavy, 14, 18, 18, color)
	label("Word", mutation:upper() .. "!", Fonts.Display, 44, 38, 52, color, 4)
	local orb = UIKit.TierOrb(tier, 112, nil, mutation)
	orb.AnchorPoint = Vector2.new(0.5, 0)
	orb.Position = UDim2.new(0.5, 0, 0, 96)
	orb.ZIndex = z
	orb.Parent = body
	label("ItemName", itemName(item), Fonts.Display, 24, 214, 30, Colors.Text, UITheme.Stroke.Text)
	UIKit.MutationPill({
		Parent = body,
		Mutation = mutation,
		Label = ("%s ×%d income"):format(mutation:upper(), MutationConfig.GetMultiplier(mutation)),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 250),
		TextSize = 15,
		Height = 26,
		ZIndex = z + 1,
	})
	-- How you got it.
	local box = Instance.new("Frame")
	box.Name = "HowYouGotIt"
	box.BackgroundColor3 = Colors.Panel2
	box.BackgroundTransparency = 0.15
	box.Position = UDim2.fromOffset(20, 288)
	box.Size = UDim2.new(1, -40, 0, 64)
	box.ZIndex = z
	box.Parent = body
	UIKit.Corner(box, UITheme.Radius.Row)
	UIKit.Stroke(box, 2, color)
	local how = HOW_YOU_GOT_IT[mutation]
	UIKit.Label({
		Name = "Text",
		Text = if how then how() else "",
		Font = Fonts.Body,
		TextSize = 14,
		TextWrapped = true,
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 1, -8),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z + 1,
		Parent = box,
	})
	local found, total = indexCount(mutation)
	label(
		"IndexLine",
		(if newIndex then "Index +1 · " else "") .. ("%s %d / %d"):format(mutation, found, total),
		Fonts.BodyHeavy,
		14,
		360,
		18,
		Colors.GoldLabel
	)

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.AnchorPoint = Vector2.new(0.5, 0)
	buttons.Position = UDim2.new(0.5, 0, 0, 392)
	buttons.Size = UDim2.fromOffset(170 + 12 + 120, 52)
	buttons.ZIndex = z
	buttons.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = buttons
	local uid = item.Uid :: string
	UIKit.Button({
		Name = "DisplayIt",
		Parent = buttons,
		Style = "Green",
		Text = "DISPLAY",
		TextSize = 20,
		Size = UDim2.fromOffset(170, 52),
		LayoutOrder = 1,
		ZIndex = z,
		OnClick = function()
			onDisplayIt(uid)
		end,
	})
	UIKit.Button({
		Name = "Ok",
		Parent = buttons,
		Style = "Disabled",
		Text = "OK",
		TextSize = 20,
		Size = UDim2.fromOffset(120, 52),
		LayoutOrder = 2,
		ZIndex = z,
		OnClick = closeBigCard,
	})

	UIKit.PopIn(holder)
	-- The major reveal: a shake and the reveal sound.
	RevealEffects.ShakeCamera(EVENT_SHAKE_MAGNITUDE, EVENT_SHAKE_SECONDS)
	SoundKit.Play("EventReveal", holder)
end

-- An event-only mutation always gets the reveal card instead.
local function isEventMutation(item: any): boolean
	return typeof(item) == "table" and MutationConfig.IsEventOnly(item.Mutation)
end

--[[ Pull x10 grid -------------------------------------------------------------------- ]]

local MULTI_COLUMNS = 5
local MULTI_CELL = Vector2.new(100, 112)
local MULTI_GAP = 10
local MULTI_POP_STAGGER = 0.06

local multiHolder: Frame? = nil

local function closeMultiCard()
	local holder = multiHolder
	multiHolder = nil
	if holder then
		local tween = UIKit.PopOut(holder)
		tween.Completed:Once(function()
			holder:Destroy()
		end)
	end
end

local function pullRank(tier: string): number
	return ItemConfig.Tiers[tier] or 0
end

local function itemValue(item: any): number
	return TycoonConfig.GetItemCashPerSecond(item.Tier, item.Mutation)
end

local function buildMiniCard(parent: Instance, item: any, order: number, isBest: boolean, z: number): Frame
	local tierColor = FusionConfig.TierAccentColors[item.Tier] or Colors.Text
	local body, holder = UIKit.Panel({
		Name = "Pull" .. order,
		Parent = parent,
		LayoutOrder = order,
		Gradient = { { 0, UITheme.TowardInk(tierColor, 0.6) }, { 1, Colors.CardBottom } },
		Radius = UITheme.Radius.Row,
		StrokeColor = if isBest then UITheme.Gradients.Gold.Top else nil,
		StrokeThickness = if isBest then 4 else nil,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z,
	})
	if not isBest then
		UIKit.MutationCardStroke(body, item.Mutation)
	end
	local orb = UIKit.TierOrb(item.Tier, 44, nil, item.Mutation)
	orb.AnchorPoint = Vector2.new(0.5, 0)
	orb.Position = UDim2.new(0.5, 0, 0, 10)
	orb.ZIndex = z + 1
	orb.Parent = body
	UIKit.MutationPill({
		Parent = body,
		Mutation = item.Mutation,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		TextSize = 10,
		Height = 16,
		ZIndex = z + 2,
	})
	UIKit.Label({
		Name = "ItemName",
		Text = itemName(item),
		Font = Fonts.Display,
		TextSize = 12,
		TextWrapped = true,
		Position = UDim2.fromOffset(4, 58),
		Size = UDim2.new(1, -8, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z + 1,
		Stroke = 1.5,
		Parent = body,
	})
	UIKit.Label({
		Name = "Tier",
		Text = item.Tier:upper(),
		Font = Fonts.BodyHeavy,
		TextSize = 10,
		TextColor3 = UITheme.GetTierLight(item.Tier),
		Position = UDim2.fromOffset(4, 90),
		Size = UDim2.new(1, -8, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z + 1,
		Parent = body,
	})
	holder.Visible = false
	return holder
end

local function showMultiCard(items: { any })
	if multiHolder then
		(multiHolder :: Frame):Destroy()
		multiHolder = nil
	end
	-- Best by what it earns, then tier.
	local best = items[1]
	for _, item in items do
		local better = itemValue(item) > itemValue(best)
			or (itemValue(item) == itemValue(best) and pullRank(item.Tier) > pullRank(best.Tier))
		if better then
			best = item
		end
	end

	local rows = math.ceil(#items / MULTI_COLUMNS)
	local width = MULTI_COLUMNS * MULTI_CELL.X + (MULTI_COLUMNS - 1) * MULTI_GAP + 32
	local height = 56 + rows * MULTI_CELL.Y + (rows - 1) * MULTI_GAP + 80
	local body, holder = UIKit.Panel({
		Name = "MultiPull",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		Color = Colors.Panel,
		Radius = 24,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 1, -- under the big card the best pull may also get
	})
	multiHolder = holder
	local z = body.ZIndex + 1

	UIKit.Label({
		Name = "Title",
		Text = ("%d PULLS"):format(#items),
		Font = Fonts.Display,
		TextSize = 30,
		TextColor3 = Colors.GoldLabel,
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(16, 56)
	grid.Size = UDim2.new(1, -32, 0, rows * MULTI_CELL.Y + (rows - 1) * MULTI_GAP)
	grid.ZIndex = z
	grid.Parent = body
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(MULTI_CELL.X, MULTI_CELL.Y)
	layout.CellPadding = UDim2.fromOffset(MULTI_GAP, MULTI_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local cards = {}
	for order, item in items do
		table.insert(cards, buildMiniCard(grid, item, order, item == best, z + 1))
	end

	UIKit.Button({
		Name = "Nice",
		Parent = body,
		Style = "Gold",
		Text = "NICE",
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(160, 52),
		ZIndex = z,
		OnClick = closeMultiCard,
	})

	UIKit.PopIn(holder)
	task.spawn(function()
		for _, card in cards do
			if multiHolder ~= holder then
				return
			end
			card.Visible = true
			UIKit.PopIn(card)
			task.wait(MULTI_POP_STAGGER)
		end
		-- The best pull also gets the big card (and its reveal) if it
		-- qualifies on its own.
		if multiHolder == holder and ResultController.ShowsBigCardFor(best.Tier, best.Mutation) then
			showBigCard({
				Caption = "BEST OF 10",
				Item = best,
				Description = ("earns %s/s on a pedestal"):format(NumberFormat.Money(earnRate(best))),
			})
		end
	end)
end

local function onGachaMultiPullResult(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Success ~= true then
		if payload.Reason == "InsufficientCash" and typeof(payload.Cost) == "number" then
			ToastController.Show(("Need %s for 10 pulls"):format(NumberFormat.Money(payload.Cost)), "Error")
		end
		return
	end
	if typeof(payload.Items) == "table" and #payload.Items > 0 then
		showMultiCard(payload.Items)
	end
end

--[[ Rebirth card -------------------------------------------------------------------- ]]

local REBIRTH_CARD_SIZE = Vector2.new(360, 270)
local REBIRTH_UNLOCK_EXTRA = 54 -- taller card when a heist unlock line shows

local function showRebirthCard(rebirths: number)
	if bigHolder then
		if sunburstConnection then
			sunburstConnection:Disconnect()
			sunburstConnection = nil
		end
		(bigHolder :: Frame):Destroy()
		bigHolder = nil
	end

	local body, holder = UIKit.Panel({
		Name = "RebirthResult",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(REBIRTH_CARD_SIZE.X, REBIRTH_CARD_SIZE.Y),
		Gradient = {
			{ 0, Colors.Panel },
			{ 0.5, UITheme.TowardInk(Colors.Rebirth, 0.5) },
			{ 1, Colors.Panel },
		},
		Radius = 24,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	bigHolder = holder
	buildSunburst(body)
	local z = body.ZIndex + 3

	UIKit.Label({
		Name = "Caption",
		Text = "A NEW RUN BEGINS",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = Colors.RebirthLabel,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = body,
	})
	UIKit.Label({
		Name = "Title",
		Text = ("REBIRTH %d!"):format(rebirths),
		Font = Fonts.Display,
		TextSize = 54,
		TextColor3 = Colors.Rebirth,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 64),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 4,
		Parent = body,
	})
	UIKit.Label({
		Name = "Detail",
		Text = ("Income %s · Luck +%d%%"):format(
			NumberFormat.Multiplier(RebirthConfig.GetIncomeMultiplier(rebirths)),
			math.floor((RebirthConfig.GetLuck(rebirths) - 1) * 100 + 0.5)
		),
		Font = Fonts.Display,
		TextSize = 22,
		Position = UDim2.fromOffset(12, 128),
		Size = UDim2.new(1, -24, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	-- The rebirth that unlocks stealing says so.
	local unlocksStealing = rebirths == HeistConfig.MinRebirths
	if unlocksStealing then
		holder.Size = UDim2.fromOffset(REBIRTH_CARD_SIZE.X, REBIRTH_CARD_SIZE.Y + REBIRTH_UNLOCK_EXTRA)
		UIKit.Label({
			Name = "Unlock",
			Text = "🫳 STEALING UNLOCKED: grab items off other labs' pedestals and run them home!",
			Font = Fonts.BodyHeavy,
			TextSize = 15,
			TextColor3 = Colors.RebirthLabel,
			TextWrapped = true,
			Position = UDim2.fromOffset(16, 166),
			Size = UDim2.new(1, -32, 0, 44),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z,
			Stroke = 1.5,
			Parent = body,
		})
	end
	UIKit.Button({
		Name = "Nice",
		Parent = body,
		Style = "Orange",
		Text = "LET'S GO",
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, if unlocksStealing then 186 + REBIRTH_UNLOCK_EXTRA else 186),
		Size = UDim2.fromOffset(180, 52),
		ZIndex = z,
		OnClick = function()
			closeBigCard()
			-- The moment stealing unlocks: HOW TO HEIST, once per account.
			if unlocksStealing and not TycoonController.HasSeenTip("howToHeist") then
				TycoonController.MarkTipSeen("howToHeist")
				HowToHeistPanel.Open()
			end
		end,
	})
	UIKit.PopIn(holder)
end

local function onRebirthResult(result: any)
	if typeof(result) == "table" and result.Success == true and typeof(result.Rebirths) == "number" then
		showRebirthCard(result.Rebirths)
	end
end

--[[ Heist cards ------------------------------------------------------------------- ]]

local HEIST_CARD_SIZE = Vector2.new(380, 360)

export type HeistItem = { ItemId: string, Tier: string, Mutation: string?, Name: string }

local function showHeistCard(title: string, titleColor: Color3, caption: string, item: HeistItem, subline: string, buttonStyle: string)
	if bigHolder then
		if sunburstConnection then
			sunburstConnection:Disconnect()
			sunburstConnection = nil
		end
		(bigHolder :: Frame):Destroy()
		bigHolder = nil
	end
	local body, holder = UIKit.Panel({
		Name = "HeistResult",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(HEIST_CARD_SIZE.X, HEIST_CARD_SIZE.Y),
		Gradient = {
			{ 0, Colors.Panel },
			{ 0.5, UITheme.TowardInk(titleColor, 0.55) },
			{ 1, Colors.Panel },
		},
		Radius = 24,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	bigHolder = holder
	UIKit.MutationCardStroke(body, item.Mutation)
	local z = body.ZIndex + 3
	UIKit.Label({
		Name = "Caption",
		Text = caption,
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(12, 20),
		Size = UDim2.new(1, -24, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = body,
	})
	UIKit.Label({
		Name = "Title",
		Text = title,
		Font = Fonts.Display,
		TextSize = 40,
		TextColor3 = titleColor,
		TextScaled = true,
		Position = UDim2.fromOffset(16, 42),
		Size = UDim2.new(1, -32, 0, 48),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 4,
		Parent = body,
	})
	local orb = UIKit.TierOrb(item.Tier, 96, nil, item.Mutation)
	orb.AnchorPoint = Vector2.new(0.5, 0)
	orb.Position = UDim2.new(0.5, 0, 0, 100)
	orb.ZIndex = z
	orb.Parent = body
	UIKit.Label({
		Name = "ItemName",
		Text = item.Name,
		Font = Fonts.Display,
		TextSize = 22,
		TextColor3 = UITheme.GetTierLight(item.Tier),
		Position = UDim2.fromOffset(12, 204),
		Size = UDim2.new(1, -24, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Label({
		Name = "Subline",
		Text = subline,
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		Position = UDim2.fromOffset(16, 234),
		Size = UDim2.new(1, -32, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = body,
	})
	UIKit.Button({
		Name = "Ok",
		Parent = body,
		Style = buttonStyle,
		Text = "OK",
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 282),
		Size = UDim2.fromOffset(160, 52),
		ZIndex = z,
		OnClick = closeBigCard,
	})
	UIKit.PopIn(holder)
end

-- The thief got home: the item is theirs.
-- `subline`: the steal timer ("You can steal again in 60s").
function ResultController.ShowHeistComplete(item: HeistItem, victimName: string, subline: string?)
	showHeistCard(
		"HEIST COMPLETE!",
		Colors.Rebirth,
		("FROM %s'S LAB"):format(victimName:upper()),
		item,
		subline or "It's in your inventory now",
		"Orange"
	)
end

-- The victim lost an item.
function ResultController.ShowItemStolen(item: HeistItem, thiefName: string, shieldSeconds: number)
	showHeistCard(
		("%s stole your"):format(thiefName),
		Colors.Danger,
		"ROBBED!",
		item,
		("Your shield is up for %d min"):format(math.floor(shieldSeconds / 60 + 0.5)),
		"Red"
	)
end

--[[ Fuse All summary card ---------------------------------------------------------- ]]

local FUSE_ALL_CARD_WIDTH = 400
local LEGENDARY_RANK = ItemConfig.Tiers.Legendary

local function tierRank(tier: string): number
	return ItemConfig.Tiers[tier] or 0
end

-- Tiers in a {[tier]: n} map, highest tier first.
local function sortedTiers(counts: { [string]: number }): { string }
	local tiers = {}
	for tier, n in counts do
		if typeof(n) == "number" and n > 0 then
			table.insert(tiers, tier)
		end
	end
	table.sort(tiers, function(a, b)
		return tierRank(a) > tierRank(b)
	end)
	return tiers
end

local function addChip(parent: Instance, tier: string, text: string, color: Color3, order: number, z: number)
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.BackgroundTransparency = 1
	chip.LayoutOrder = order
	chip.ZIndex = z
	chip.Parent = parent
	local orb = UIKit.TierOrb(tier, 26)
	orb.AnchorPoint = Vector2.new(0, 0.5)
	orb.Position = UDim2.new(0, 4, 0.5, 0)
	orb.ZIndex = z
	orb.Parent = chip
	UIKit.Label({
		Text = text,
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = color,
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -38, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = z,
		Parent = chip,
	})
end

local function showFuseAllCard(result: any)
	if bigHolder then
		if sunburstConnection then
			sunburstConnection:Disconnect()
			sunburstConnection = nil
		end
		(bigHolder :: Frame):Destroy()
		bigHolder = nil
	end

	local body, holder = UIKit.Panel({
		Name = "FuseAllSummary",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(FUSE_ALL_CARD_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Gradient = { { 0, Colors.FuseAllTop }, { 0.4, Colors.Panel }, { 1, Colors.Panel } },
		Radius = 24,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	bigHolder = holder
	local z = body.ZIndex + 1
	UIKit.Padding(body, 18, 20, 18, 20)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = body

	local count = result.Count :: number
	local upgraded = (result.Upgraded :: number?) or 0
	UIKit.Label({
		Text = "FUSE ALL",
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		TextColor3 = Colors.VioletLight,
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		ZIndex = z,
		Parent = body,
	})
	UIKit.Label({
		Text = ("%d %s"):format(count, if count == 1 then "fusion" else "fusions"),
		Font = Fonts.Display,
		TextSize = 44,
		Size = UDim2.new(1, 0, 0, 48),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Label({
		Text = ("%s · %d failed"):format(UIKit.Colored(("%d upgraded"):format(upgraded), Colors.Cash), count - upgraded),
		RichText = true,
		Font = Fonts.Body,
		TextSize = 15,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 3,
		ZIndex = z,
		Parent = body,
	})

	-- Two-column chips: gains first (highest tier first), then what was used up.
	local grid = Instance.new("Frame")
	grid.Name = "Chips"
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Size = UDim2.fromScale(1, 0)
	grid.LayoutOrder = 4
	grid.ZIndex = z
	grid.Parent = body
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -4, 0, 34)
	gridLayout.CellPadding = UDim2.fromOffset(8, 4)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local order = 0
	local gained = if typeof(result.Gained) == "table" then result.Gained else {}
	for _, tier in sortedTiers(gained) do
		order += 1
		addChip(grid, tier, ("+%d %s"):format(gained[tier], tier:upper()), UITheme.GetTierLight(tier), order, z)
	end
	local consumed = if typeof(result.Consumed) == "table" then result.Consumed else {}
	for _, tier in sortedTiers(consumed) do
		order += 1
		addChip(grid, tier, ("−%d %s"):format(consumed[tier], tier:upper()), Colors.Muted, order, z)
	end

	local best = result.Best
	if typeof(best) == "table" and typeof(best.Tier) == "string" then
		local row = UIKit.Panel({
			Name = "Best",
			Parent = body,
			Size = UDim2.new(1, 0, 0, 56),
			Color = Colors.Panel2,
			Radius = UITheme.Radius.Row,
			ShadowOffset = UITheme.SmallShadowOffset,
			LayoutOrder = 5,
			ZIndex = z,
		})
		local orb = UIKit.TierOrb(best.Tier, 38, nil, best.Mutation)
		orb.AnchorPoint = Vector2.new(0, 0.5)
		orb.Position = UDim2.new(0, 12, 0.5, 0)
		orb.ZIndex = row.ZIndex + 1
		orb.Parent = row
		UIKit.Label({
			Text = ("BEST · %s"):format(UIKit.Colored(best.Tier:upper(), UITheme.GetTierLight(best.Tier))),
			RichText = true,
			Font = Fonts.BodyHeavy,
			TextSize = 12,
			TextColor3 = Colors.Muted,
			Position = UDim2.fromOffset(62, 8),
			Size = UDim2.new(1, -74, 0, 16),
			ZIndex = row.ZIndex + 1,
			Parent = row,
		})
		UIKit.Label({
			Text = itemName(best),
			Font = Fonts.Display,
			TextSize = 18,
			Position = UDim2.fromOffset(62, 26),
			Size = UDim2.new(1, -74, 0, 22),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = row.ZIndex + 1,
			Stroke = UITheme.Stroke.Text,
			Parent = row,
		})
	end

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 52 + UITheme.ShadowOffset)
	buttons.LayoutOrder = 6
	buttons.ZIndex = z
	buttons.Parent = body
	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Padding = UDim.new(0, 12)
	buttonLayout.Parent = buttons

	if typeof(best) == "table" and typeof(best.Uid) == "string" then
		local uid = best.Uid :: string
		UIKit.Button({
			Name = "DisplayBest",
			Parent = buttons,
			Style = "Green",
			Text = "DISPLAY BEST",
			TextSize = 18,
			Size = UDim2.fromOffset(180, 52),
			LayoutOrder = 1,
			ZIndex = z,
			OnClick = function()
				onDisplayIt(uid)
			end,
		})
	end
	UIKit.Button({
		Name = "Ok",
		Parent = buttons,
		Style = "Disabled",
		Text = "OK",
		TextSize = 20,
		Size = UDim2.fromOffset(110, 52),
		LayoutOrder = 2,
		ZIndex = z,
		OnClick = closeBigCard,
	})

	UIKit.PopIn(holder)
	if typeof(best) == "table" and tierRank(best.Tier) >= LEGENDARY_RANK then
		RevealEffects.ShakeCamera(MYTHIC_SHAKE_MAGNITUDE, MYTHIC_SHAKE_SECONDS)
	end
end

local function onFuseAllResolved(result: any)
	if typeof(result) ~= "table" or typeof(result.Count) ~= "number" or result.Count <= 0 then
		ToastController.Show("Nothing to fuse", "Neutral")
		return
	end
	showFuseAllCard(result)
end

--[[ Bottom cards (fail / small pull) --------------------------------------------- ]]

local bottomHolder: Frame? = nil
local bottomGeneration = 0

local function hideBottomCard(generation: number)
	if generation ~= bottomGeneration then
		return
	end
	local holder = bottomHolder
	bottomHolder = nil
	ToastController.SetBottomInset(0)
	if holder then
		local tween = UIKit.PopOut(holder)
		tween.Completed:Once(function()
			holder:Destroy()
		end)
	end
end

-- Builds the shared bottom-row panel, replacing whatever card is showing.
local function newBottomCard(name: string, size: Vector2): (Frame, number)
	bottomGeneration += 1
	if bottomHolder then
		(bottomHolder :: Frame):Destroy()
		bottomHolder = nil
	end
	local body, holder = UIKit.Panel({
		Name = name,
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(BOTTOM_CARD_OFFSET + UITheme.SmallShadowOffset)),
		Size = UDim2.fromOffset(size.X, size.Y),
		Gradient = { { 0, Colors.Panel2 }, { 1, Colors.Panel } },
		Radius = 18,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = 2,
	})
	bottomHolder = holder
	ToastController.SetBottomInset(size.Y + 12)
	UIKit.PopIn(holder)

	local generation = bottomGeneration
	task.delay(BOTTOM_CARD_SECONDS, hideBottomCard, generation)
	return body, generation
end

local function showFailCard(item: any, lostCount: number)
	local tier = item.Tier :: string
	local body, generation = newBottomCard("FailCard", FAIL_CARD_SIZE)
	local z = body.ZIndex + 1

	local orb = UIKit.TierOrb(tier, 56, 0.15, item.Mutation)
	orb.AnchorPoint = Vector2.new(0, 0.5)
	orb.Position = UDim2.new(0, 16, 0.5, 0)
	orb.ZIndex = z
	orb.Parent = body

	UIKit.Label({
		Name = "Title",
		Text = "So close…",
		Font = Fonts.Display,
		TextSize = 22,
		Position = UDim2.fromOffset(86, 14),
		Size = UDim2.new(1, -(86 + 104 + 28), 0, 26),
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Label({
		Name = "Detail",
		Text = ("Kept %s, lost %d"):format(
			"<b>" .. UIKit.Colored(UIKit.EscapeRichText(itemName(item)), UITheme.GetTierLight(tier)) .. "</b>",
			lostCount
		),
		RichText = true,
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		Position = UDim2.fromOffset(86, 42),
		Size = UDim2.new(1, -(86 + 104 + 28), 0, 36),
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = z,
		Parent = body,
	})

	local again = UIKit.Button({
		Name = "Again",
		Parent = body,
		Style = "Violet",
		Text = "AGAIN",
		TextSize = 18,
		Size = UDim2.fromOffset(104, 46),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, -2),
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z,
		OnClick = function()
			if FusionController.CanRequestFusion() then
				hideBottomCard(generation)
				task.spawn(FusionController.RequestFusion)
			end
		end,
	})

	-- Enabled only while you're still at your machine with another pair.
	task.spawn(function()
		while bottomGeneration == generation and again.Parent do
			local canFuse = FusionController.CanRequestFusion()
			UIKit.SetButton(again, {
				Style = if canFuse then "Violet" else "Disabled",
				TextColor3 = if canFuse then Colors.Text else Colors.Muted,
			})
			task.wait(0.25)
		end
	end)
end

local function showPullCard(item: any)
	local tier = item.Tier :: string
	local body = newBottomCard("PullCard", PULL_CARD_SIZE)
	local z = body.ZIndex + 1

	UIKit.Label({
		Name = "Caption",
		Text = "PULLED",
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = Colors.GoldLabel,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(56, 16),
		ZIndex = z,
		Parent = body,
	})

	UIKit.MutationCardStroke(body, item.Mutation)
	local orb = UIKit.TierOrb(tier, 40, nil, item.Mutation)
	orb.AnchorPoint = Vector2.new(0, 0.5)
	orb.Position = UDim2.new(0, 78, 0.5, 0)
	orb.ZIndex = z
	orb.Parent = body
	-- Mutation tag under the orb, on the card's bottom edge.
	UIKit.MutationPill({
		Parent = body,
		Mutation = item.Mutation,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 98, 1, -4),
		TextSize = 11,
		Height = 18,
		ZIndex = z + 1,
	})

	UIKit.Label({
		Name = "ItemName",
		Text = itemName(item),
		Font = Fonts.Display,
		TextSize = 18,
		Position = UDim2.fromOffset(130, 14),
		Size = UDim2.new(1, -(130 + 130), 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Label({
		Name = "Tier",
		Text = tier:upper(),
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = UITheme.GetTierLight(tier),
		Position = UDim2.fromOffset(130, 40),
		Size = UDim2.new(1, -(130 + 130), 0, 16),
		ZIndex = z,
		Parent = body,
	})
	UIKit.Label({
		Name = "NextPull",
		Text = ("next pull %s"):format(NumberFormat.Money(TycoonConfig.GetGachaPullCost(TycoonController.GetGachaPulls()))),
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Muted,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(120, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = z,
		Parent = body,
	})
end

--[[ Event routing ------------------------------------------------------------------ ]]

-- Exposed so AnnouncementController can skip the banner for these cases.
-- Epic+ tiers, and Diamond/Rainbow at any tier.
-- The big card for an item granted outside a pull or fusion (a meteor core,
-- an admin gift): `caption` over the tier name, the earn rate under it.
function ResultController.ShowItemCard(caption: string, item: any, description: string?, newIndex: boolean?)
	if typeof(item) ~= "table" or typeof(item.Tier) ~= "string" or typeof(item.Uid) ~= "string" then
		return
	end
	if isEventMutation(item) then
		showEventMutationCard(item, newIndex == true)
		return
	end
	showBigCard({
		Caption = caption,
		Item = item,
		Description = description or ("Earns %s/s on a pedestal"):format(NumberFormat.Money(earnRate(item))),
	})
end

function ResultController.ShowsBigCardFor(tier: string, mutation: string?): boolean
	return FusionConfig.IsMajorReveal(tier, mutation)
end

local function onFusionResolved(result: any)
	if typeof(result) ~= "table" or not result.Success or not result.NewItem then
		return
	end
	local newItem = result.NewItem
	if not result.Upgraded then
		showFailCard(newItem, if typeof(result.LostCount) == "number" then result.LostCount else 1)
		return
	end
	if isEventMutation(newItem) then
		showEventMutationCard(newItem, result.IsNewIndex == true or result.NewIndex == true)
		return
	end
	if ResultController.ShowsBigCardFor(newItem.Tier, newItem.Mutation) then
		showBigCard({
			Caption = "FUSION SUCCESS",
			Item = newItem,
			Description = ("%dx %s → %s · earns %s/s on a pedestal"):format(
				if typeof(result.Count) == "number" then result.Count else 2,
				tostring(result.ConsumedTier),
				newItem.Tier,
				NumberFormat.Money(earnRate(newItem))
			),
		})
	end
end

local function onGachaPullResult(payload: any)
	if typeof(payload) ~= "table" or not payload.Success or not payload.NewItem then
		return
	end
	local newItem = payload.NewItem
	if isEventMutation(newItem) then
		showEventMutationCard(newItem, payload.NewIndex == true)
		return
	end
	if ResultController.ShowsBigCardFor(newItem.Tier, newItem.Mutation) then
		showBigCard({
			Caption = "YOU PULLED",
			Item = newItem,
			Description = ("earns %s/s on a pedestal"):format(NumberFormat.Money(earnRate(newItem))),
		})
	else
		showPullCard(newItem)
	end
end

--[[ Welcome-back card (offline earnings) ------------------------------------------ ]]

local WELCOME_SIZE = Vector2.new(460, 300)
local WELCOME_DISPLAY_ORDER = 125 -- over the Fuse panel, under Results (130)
local COLLECT_SIZE = Vector2.new(200, 56)
local COIN_COUNT = 16
local COIN_SIZE = 26
local COIN_SECONDS = 0.6
local COIN_SPREAD = 170

local welcome: UIKit.Modal? = nil
local welcomeAway: TextLabel
local welcomeAmount: TextLabel
local lastPendingOffline = 0

-- "3h 12m", "45m"; capped at "4h+" (OfflineConfig.MaxSeconds).
local function formatAway(seconds: number): string
	if seconds >= OfflineConfig.MaxSeconds then
		return ("%dh+"):format(OfflineConfig.MaxSeconds // 3600)
	end
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	if hours > 0 then
		return ("%dh %dm"):format(hours, minutes)
	end
	return ("%dm"):format(minutes)
end

-- Green "$" coins fly out of the amount and fade (UI only). They go on the
-- Results gui, which stays enabled after the modal's own gui switches off.
local function coinBurst(gui: ScreenGui, from: GuiObject)
	local scale = gui:FindFirstChildOfClass("UIScale")
	local factor = if scale then scale.Scale else 1
	local centre = (from.AbsolutePosition + from.AbsoluteSize / 2) / factor
	for index = 1, COIN_COUNT do
		local coin = Instance.new("Frame")
		coin.Name = "Coin"
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.Position = UDim2.fromOffset(centre.X, centre.Y)
		coin.Size = UDim2.fromOffset(COIN_SIZE, COIN_SIZE)
		coin.BackgroundColor3 = Colors.White
		coin.ZIndex = 50
		UIKit.Corner(coin, 999)
		UIKit.PairGradient(coin, UITheme.Gradients.Green)
		UIKit.Stroke(coin, 2)
		UIKit.Label({
			Name = "Sign",
			Text = "$",
			Font = Fonts.Display,
			TextSize = 16,
			TextColor3 = Colors.CoinText,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 51,
			Parent = coin,
		})
		coin.Parent = gui
		local angle = (index / COIN_COUNT) * math.pi * 2 + math.random() * 0.4
		local distance = COIN_SPREAD * (0.6 + math.random() * 0.4)
		local info = TweenInfo.new(COIN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(coin, info, {
			Position = UDim2.fromOffset(centre.X + math.cos(angle) * distance, centre.Y + math.sin(angle) * distance),
			BackgroundTransparency = 1,
			Rotation = math.random(-90, 90),
		}):Play()
		for _, child in coin:GetDescendants() do
			if child:IsA("UIStroke") then
				TweenService:Create(child, info, { Transparency = 1 }):Play()
			elseif child:IsA("TextLabel") then
				TweenService:Create(child, info, { TextTransparency = 1 }):Play()
			end
		end
		task.delay(COIN_SECONDS, coin.Destroy, coin)
	end
end

local function buildWelcome(): UIKit.Modal
	local modal = UIKit.Modal({
		Name = "WelcomeBack",
		Title = "WELCOME BACK!",
		DisplayOrder = WELCOME_DISPLAY_ORDER,
		MaxSize = WELCOME_SIZE,
		HeaderTop = Colors.WelcomeTop,
	})
	local content = modal.Content
	welcomeAway = UIKit.Label({
		Name = "Away",
		Font = Fonts.BodyHeavy,
		TextSize = 18,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = content.ZIndex + 1,
		Parent = content,
	})
	welcomeAmount = UIKit.Label({
		Name = "Amount",
		Font = Fonts.Display,
		TextSize = 54,
		TextColor3 = Colors.Cash,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 62),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = content.ZIndex + 1,
		Stroke = 4,
		Parent = content,
	})
	UIKit.Label({
		Name = "Rule",
		Text = ("Your lab earned %d%% while you were gone"):format(math.floor(OfflineConfig.Rate * 100 + 0.5)),
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Faint,
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = content.ZIndex + 1,
		Parent = content,
	})

	-- Buttons centre themselves; COLLECT x2 is a hidden slot for the
	-- monetization pass (a Developer Product), not built out yet.
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, 126)
	row.Size = UDim2.new(1, 0, 0, COLLECT_SIZE.Y + UITheme.ShadowOffset)
	row.ZIndex = content.ZIndex + 1
	row.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	UIKit.Button({
		Name = "Collect",
		Parent = row,
		Style = "Green",
		Text = "COLLECT",
		TextSize = 24,
		Size = UDim2.fromOffset(COLLECT_SIZE.X, COLLECT_SIZE.Y),
		LayoutOrder = 1,
		ZIndex = row.ZIndex,
		OnClick = function()
			if lastPendingOffline > 0 then
				RemoteEvents.ClaimOffline:FireServer()
				coinBurst(screenGui, welcomeAmount)
			end
			modal.Close()
		end,
	})
	local _, doubleHolder = UIKit.Button({
		Name = "CollectDouble",
		Parent = row,
		Style = "Gold",
		Text = "COLLECT ×2",
		TextSize = 22,
		Size = UDim2.fromOffset(COLLECT_SIZE.X, COLLECT_SIZE.Y),
		LayoutOrder = 2,
		ZIndex = row.ZIndex,
	})
	doubleHolder.Visible = false
	return modal
end

-- Shows the card when a snapshot brings new offline earnings (the first
-- sync after joining, or /offline); closes it once they're paid elsewhere
-- (the server's 30 s auto-claim).
local function onTycoonChanged()
	local amount, away = TycoonController.GetPendingOffline()
	local modal = welcome or buildWelcome()
	welcome = modal
	if amount > 0 then
		welcomeAway.Text = ("You were away %s"):format(formatAway(away))
		welcomeAmount.Text = "+" .. NumberFormat.Money(amount)
		if lastPendingOffline <= 0 then
			modal.Open()
		end
	elseif lastPendingOffline > 0 and modal.IsOpen() then
		modal.Close()
	end
	lastPendingOffline = amount
end

function ResultController.Init()
	screenGui = UIKit.Screen("Results", 130)
	TycoonController.TycoonChanged:Connect(onTycoonChanged)
	if TycoonController.HasSynced() then
		onTycoonChanged()
	end
	FusionController.FusionResolved:Connect(onFusionResolved)
	FusionController.FuseAllResolved:Connect(onFuseAllResolved)
	RemoteEvents.GachaPullResult.OnClientEvent:Connect(onGachaPullResult)
	RemoteEvents.RebirthResult.OnClientEvent:Connect(onRebirthResult)
	RemoteEvents.GachaMultiPullResult.OnClientEvent:Connect(onGachaMultiPullResult)
end

return ResultController
