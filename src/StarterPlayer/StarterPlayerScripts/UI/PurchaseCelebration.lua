--!strict
--[[
	PurchaseCelebration
	-------------------
	The reveal after a purchase or a Studio test grant (ShopPurchased
	Granted), replacing the plain THANK YOU text. Client-only, skippable
	with a tap after 0.6 s; "AWESOME!" (or any tap once it's done) closes
	it. The shop stays open underneath and its tile updates by itself.

	  Burst (0-0.5 s)   the screen dims, spinning rays and a radial glow, ~60
	                    confetti pieces (the section colour + gold) with
	                    gravity and fade, the RevealMajor sound
	  Item (0.3-1.2 s)  the live store icon (or the glyph in a circle) pops
	                    in with overshoot to 260 px (180 on a phone) and a
	                    shine sweep; "THANK YOU!" and the name in big white
	  What you got      per ShopPurchased.Effects entry, one after another
	                    (bundles too):
	      Cash          "+$250K" counts up, ~15 coins fly into the HUD cash
	                    counter, which ticks up and bounces as they land
	      Boost / Luck / Overclock  "+1 h" flies into its HUD timed pill,
	                    which pops; a boost also counts the $/s line up
	      Pass          a "✓ ACTIVE" stamp with a little shake, then what it
	                    changes: 2x Cash / VIP count the $/s line up, +2
	                    Pedestals pop the two plinths, Neon Pink flashes the
	                    lab pink, Auto-Fuse points at its Fuse panel toggle
	      Tokens        shields drop into a "🛡 Safe Fusion (N)" count

	Every sound goes through SoundKit (the player's SFX volume). Never
	chains into another purchase prompt. The HUD hooks come in through
	SetHud (HudController), so this module doesn't require the HUD.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local ShopPrices = require(ReplicatedStorage.Shared.Modules.ShopPrices)
local ShopState = require(ReplicatedStorage.Shared.Modules.ShopState)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)
local UIKit = require(script.Parent.UIKit)
local TycoonController = require(script.Parent.Parent.Controllers.TycoonController)

local PurchaseCelebration = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local DISPLAY_ORDER = 155 -- over every panel (Shop 141 …) and ShopCards (150)
local CARD_SIZE = Vector2.new(560, 520)
local ICON_SIZE = { Desktop = 260, Phone = 180 }
local SKIP_AFTER_SECONDS = 0.6
local CONFETTI_COUNT = 60
local CONFETTI_SECONDS = 1.8
local CONFETTI_GRAVITY = 900 -- px / s^2
local COIN_COUNT = 15
local COIN_FLIGHT_SECONDS = 0.55
local COUNT_UP_SECONDS = 0.8
local RAY_DEG_PER_SEC = 30
local EFFECT_GAP_SECONDS = 0.35

export type HudHooks = {
	GetCashTarget: () -> Vector2,
	HoldCash: (amount: number, seconds: number) -> (),
	BounceCash: () -> (),
	GetEffectPill: (kind: string) -> TextLabel?,
	PopEffectPill: (kind: string) -> (),
	CountUpIncome: (from: number) -> (),
	GetIncomePerSecond: () -> number,
	GetCash: () -> number,
}

local hud: HudHooks? = nil
local screenGui: ScreenGui? = nil
local token = 0
local closeCurrent: (() -> ())? = nil

-- HudController hands its hooks in at Init.
function PurchaseCelebration.SetHud(hooks: HudHooks)
	hud = hooks
end

local function gui(): ScreenGui
	local existing = screenGui
	if existing then
		return existing
	end
	local created = UIKit.Screen("PurchaseCelebration", DISPLAY_ORDER)
	screenGui = created
	return created
end

local function sectionPair(key: string): UITheme.GradientPair
	for _, section in ShopConfig.Sections do
		if table.find(section.Keys, key) then
			return UITheme.Gradients[section.Gradient] or UITheme.Gradients.Violet
		end
	end
	return UITheme.Gradients.ShopFeatured
end

local function scaleOf(instance: Instance): number
	return UIKit.EffectiveScale(instance)
end

-- A screen point (px) as a position inside `parent` (offsets, logical).
local function toLocal(parent: GuiObject, screen: Vector2): UDim2
	local scale = scaleOf(parent)
	local offset = (screen - parent.AbsolutePosition) / scale
	return UDim2.fromOffset(offset.X, offset.Y)
end

local function span(seconds: number): string
	if seconds >= 3600 and seconds % 3600 == 0 then
		return ("+%d h"):format(seconds // 3600)
	end
	return ("+%d min"):format(seconds // 60)
end

--[[ Burst ------------------------------------------------------------------------------ ]]

local function rays(parent: GuiObject, color: Color3, z: number)
	local holder = Instance.new("Frame")
	holder.Name = "Rays"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, 0, 0, 180)
	holder.Size = UDim2.fromOffset(900, 900)
	holder.BackgroundColor3 = color
	holder.BackgroundTransparency = 0.7
	holder.BorderSizePixel = 0
	holder.ZIndex = z
	holder.Parent = parent
	UIKit.Corner(holder, 999)
	local stripes = Instance.new("UIGradient")
	stripes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.1, 1),
		NumberSequenceKeypoint.new(0.2, 0),
		NumberSequenceKeypoint.new(0.3, 1),
		NumberSequenceKeypoint.new(0.4, 0),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(0.6, 0),
		NumberSequenceKeypoint.new(0.7, 1),
		NumberSequenceKeypoint.new(0.8, 0),
		NumberSequenceKeypoint.new(0.9, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	stripes.Parent = holder
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = holder.Position
	glow.Size = UDim2.fromOffset(420, 420)
	glow.BackgroundColor3 = Colors.White
	glow.BackgroundTransparency = 0.55
	glow.BorderSizePixel = 0
	glow.ZIndex = z
	glow.Parent = parent
	UIKit.Corner(glow, 999)
	local glowFade = Instance.new("UIGradient")
	glowFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	glowFade.Parent = glow
	holder.Size = UDim2.fromOffset(200, 200)
	TweenService:Create(holder, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(900, 900) }):Play()
	local spin: RBXScriptConnection
	spin = RunService.RenderStepped:Connect(function(dt: number)
		if not holder.Parent then
			spin:Disconnect()
			return
		end
		holder.Rotation = (holder.Rotation + RAY_DEG_PER_SEC * dt) % 360
	end)
end

-- ~60 2D pieces from the centre, with gravity and fade, then gone.
local function confetti(parent: GuiObject, colors: { Color3 }, origin: UDim2, z: number)
	type Piece = { Frame: Frame, Velocity: Vector2, Spin: number }
	local pieces: { Piece } = {}
	for index = 1, CONFETTI_COUNT do
		local piece = Instance.new("Frame")
		piece.Name = "Confetti"
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = origin
		piece.Size = UDim2.fromOffset(math.random(8, 14), math.random(5, 9))
		piece.BackgroundColor3 = colors[(index % #colors) + 1]
		piece.BorderSizePixel = 0
		piece.Rotation = math.random(0, 359)
		piece.ZIndex = z
		piece.Parent = parent
		local angle = math.rad(math.random(200, 340))
		local speed = math.random(380, 820)
		table.insert(pieces, {
			Frame = piece,
			Velocity = Vector2.new(math.cos(angle) * speed, math.sin(angle) * speed),
			Spin = math.random(-540, 540),
		})
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt: number)
		local age = os.clock() - started
		if age > CONFETTI_SECONDS or not parent.Parent then
			connection:Disconnect()
			for _, p in pieces do
				p.Frame:Destroy()
			end
			return
		end
		for _, p in pieces do
			p.Velocity += Vector2.new(0, CONFETTI_GRAVITY * dt)
			p.Frame.Position += UDim2.fromOffset(p.Velocity.X * dt, p.Velocity.Y * dt)
			p.Frame.Rotation += p.Spin * dt
			p.Frame.BackgroundTransparency = math.clamp((age - CONFETTI_SECONDS * 0.55) / (CONFETTI_SECONDS * 0.45), 0, 1)
		end
	end)
end

--[[ The item ------------------------------------------------------------------------------ ]]

local function shineSweep(frame: GuiObject)
	frame.ClipsDescendants = true
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(-0.4, 0.5)
	shine.Size = UDim2.new(0.25, 0, 2.2, 0)
	shine.Rotation = 20
	shine.BackgroundColor3 = Colors.White
	shine.BackgroundTransparency = 0.5
	shine.BorderSizePixel = 0
	shine.ZIndex = frame.ZIndex + 2
	shine.Parent = frame
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = shine
	task.delay(0.5, function()
		if shine.Parent then
			TweenService:Create(shine, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				Position = UDim2.fromScale(1.4, 0.5),
			}):Play()
		end
	end)
end

local function itemIcon(parent: GuiObject, key: string, size: number, z: number): Frame
	local disc = Instance.new("Frame")
	disc.Name = "Icon"
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.Position = UDim2.new(0.5, 0, 0, 56)
	disc.Size = UDim2.fromOffset(size, size)
	disc.BackgroundColor3 = Colors.White
	disc.BackgroundTransparency = 0.78
	disc.ZIndex = z
	disc.Parent = parent
	UIKit.Corner(disc, 999)
	UIKit.Stroke(disc, 4)
	local image = ShopPrices.GetIcon(key)
	local entry = ShopConfig.GetItem(key)
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
			Text = if entry then entry.Icon else "🎁",
			TextSize = math.floor(size * 0.55),
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 1,
			Parent = disc,
		})
	end
	shineSweep(disc)
	local pop = Instance.new("UIScale")
	pop.Scale = 0.2
	pop.Parent = disc
	TweenService:Create(pop, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	return disc
end

--[[ Effects ------------------------------------------------------------------------------- ]]

type Context = {
	Token: number,
	Gui: ScreenGui,
	Card: Frame, -- the content column
	Line: TextLabel, -- the effect line under the name
	Z: number,
	Skipped: boolean,
}

local function wait(context: Context, seconds: number): boolean
	local started = os.clock()
	while os.clock() - started < seconds do
		if token ~= context.Token then
			return false
		end
		RunService.Heartbeat:Wait()
	end
	return token == context.Token
end

local function countUp(label: TextLabel, to: number, format: (number) -> string, context: Context)
	local started = os.clock()
	while token == context.Token do
		local u = math.clamp((os.clock() - started) / COUNT_UP_SECONDS, 0, 1)
		label.Text = format(to * TweenService:GetValue(u, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		if u >= 1 or context.Skipped then
			label.Text = format(to)
			return
		end
		RunService.Heartbeat:Wait()
	end
end

-- A little label flies from the card to a screen point, then is gone.
local function flyTo(context: Context, text: string, color: Color3, target: Vector2, seconds: number, size: number?)
	local from = context.Line.AbsolutePosition + context.Line.AbsoluteSize / 2
	local label = UIKit.Label({
		Name = "Flyer",
		Text = text,
		Font = Fonts.Display,
		TextSize = size or 26,
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutomaticSize = Enum.AutomaticSize.XY,
		Position = toLocal(context.Gui :: any, from),
		ZIndex = context.Z + 10,
		Stroke = UITheme.Stroke.Text,
		Parent = context.Gui,
	})
	local tween = TweenService:Create(
		label,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = toLocal(context.Gui :: any, target), TextTransparency = 0.2 }
	)
	tween:Play()
	tween.Completed:Once(function()
		label:Destroy()
	end)
end

local function playCash(context: Context, amount: number)
	local hooks = hud
	local before = if hooks then math.max(0, hooks.GetCash() - amount) else 0
	if hooks then
		hooks.HoldCash(before, 10)
	end
	context.Line.TextColor3 = Colors.Cash
	countUp(context.Line, amount, function(value: number): string
		return "+" .. NumberFormat.Money(math.floor(value))
	end, context)
	if not hooks then
		return
	end
	local target = hooks.GetCashTarget()
	for index = 1, COIN_COUNT do
		if token ~= context.Token then
			break
		end
		flyTo(context, "🪙", Colors.Cash, target + Vector2.new(math.random(-10, 10), math.random(-6, 6)), COIN_FLIGHT_SECONDS, 24)
		task.delay(COIN_FLIGHT_SECONDS, function()
			if index == 1 then
				hooks.HoldCash(before, 0) -- release: the counter ticks up
			end
			hooks.BounceCash()
			if index % 3 == 1 then
				SoundKit.Play("CoinPickup", nil)
			end
		end)
		if not context.Skipped then
			task.wait(0.04)
		end
	end
	if context.Skipped then
		hooks.HoldCash(before, 0)
	end
end

local PILL_FOR: { [string]: string } = { Boost = "Income", Luck = "Luck", Overclock = "Server" }

local function playTimed(context: Context, kind: string, seconds: number)
	context.Line.TextColor3 = Colors.Text
	context.Line.Text = ("%s %s"):format(span(seconds), if kind == "Luck" then "of ×2 luck" elseif kind == "Overclock" then "of ×2 for the server" else "of ×2 income")
	local hooks = hud
	if not hooks then
		return
	end
	local pillKind = PILL_FOR[kind]
	local before = hooks.GetIncomePerSecond()
	-- Only a multiplier that just switched on counts the $/s line up.
	local bank = if kind == "Boost"
		then TycoonController.GetBoostSecondsLeft("Income")
		elseif kind == "Overclock" then ShopState.GetOverclockSeconds()
		else math.huge
	local switchedOn = bank <= seconds + 2
	local pill = hooks.GetEffectPill(pillKind)
	local target = if pill then UIKit.PillRoot(pill).AbsolutePosition + UIKit.PillRoot(pill).AbsoluteSize / 2 else hooks.GetCashTarget()
	flyTo(context, span(seconds), Colors.Text, target, 0.6)
	task.delay(0.6, function()
		hooks.PopEffectPill(pillKind)
		if switchedOn then
			hooks.CountUpIncome(before / 2)
		end
	end)
end

local function plotPart(name: string): Instance?
	local plots = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	local plot = plots and plots:FindFirstChild(PlotNaming.GetPlotName(Players.LocalPlayer.UserId))
	return plot and plot:FindFirstChild(name, true)
end

-- A short local sparkle burst on a world part (looks only, this client).
local function burstOn(part: Instance?, color: Color3, count: number)
	if not part or not part:IsA("BasePart") then
		return
	end
	local emitter = SparkleEmitter.Create({ Color = color })
	emitter.Enabled = false
	emitter.Parent = part
	emitter:Emit(count)
	task.delay(3, function()
		emitter:Destroy()
	end)
end

local function stamp(context: Context, text: string)
	local label = UIKit.Label({
		Name = "Stamp",
		Text = text,
		Font = Fonts.Display,
		TextSize = 34,
		TextColor3 = Colors.Cash,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 120),
		AutomaticSize = Enum.AutomaticSize.XY,
		Rotation = -12,
		ZIndex = context.Z + 8,
		Stroke = 4,
		Parent = context.Card,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 2.4
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 }):Play()
	task.delay(0.22, function()
		SoundKit.Play("Toast", nil)
		-- The little shake on landing.
		local card = context.Card
		local rest = card.Position
		for _, dx in { 6, -5, 3, 0 } do
			card.Position = rest + UDim2.fromOffset(dx, 0)
			task.wait(0.03)
		end
		card.Position = rest
	end)
end

local function playPass(context: Context, key: string)
	stamp(context, "✓ ACTIVE")
	local entry = ShopConfig.GetItem(key)
	context.Line.TextColor3 = Colors.Text
	context.Line.Text = if entry then entry.Effect else ""
	local hooks = hud
	if key == "DoubleCash" or key == "VIP" then
		if hooks then
			local factor = if key == "DoubleCash" then ShopConfig.DoubleCashMultiplier else ShopConfig.VipMultiplier
			hooks.CountUpIncome(hooks.GetIncomePerSecond() / factor)
		end
	elseif key == "ExtraPedestals" then
		for index = PlotLayout.PEDESTAL_COUNT - 1, PlotLayout.PEDESTAL_COUNT do
			burstOn(plotPart("Pedestal" .. index), UITheme.World.AccentGold, 40)
		end
	elseif key == "LabStyle" then
		burstOn(plotPart("PlotOrigin"), UITheme.World.AccentPink, 80)
		burstOn(plotPart("Sign"), UITheme.World.AccentPink, 60)
	elseif key == "AutoFuse" then
		context.Line.Text = "Switch it on: 🔁 Auto-Fuse in the Fuse panel"
	end
end

local function playTokens(context: Context, count: number, total: number)
	context.Line.TextColor3 = Colors.Text
	local before = math.max(0, total - count)
	context.Line.Text = ("🛡 Safe Fusion (%d)"):format(before)
	for index = 1, count do
		if not wait(context, if context.Skipped then 0 else 0.18) then
			return
		end
		local shield = UIKit.Label({
			Name = "Token",
			Text = "🛡",
			TextSize = 34,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 0, 300),
			AutomaticSize = Enum.AutomaticSize.XY,
			ZIndex = context.Z + 6,
			Parent = context.Card,
		})
		TweenService:Create(shield, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = context.Line.Position + UDim2.fromOffset(0, 10),
			TextTransparency = 0.6,
		}):Play()
		task.delay(0.25, function()
			shield:Destroy()
			context.Line.Text = ("🛡 Safe Fusion (%d)"):format(before + index)
			SoundKit.Play("Toast", nil)
		end)
	end
end

local function playEffect(context: Context, effect: { [string]: any })
	local kind = effect.Kind
	if kind == "Cash" and typeof(effect.Amount) == "number" then
		playCash(context, effect.Amount)
	elseif (kind == "Boost" or kind == "Luck" or kind == "Overclock") and typeof(effect.Seconds) == "number" then
		playTimed(context, kind, effect.Seconds)
	elseif kind == "Pass" and typeof(effect.Key) == "string" then
		playPass(context, effect.Key)
	elseif kind == "Tokens" and typeof(effect.Count) == "number" and typeof(effect.Total) == "number" then
		playTokens(context, effect.Count, effect.Total)
	end
end

--[[ Show / close --------------------------------------------------------------------------- ]]

function PurchaseCelebration.IsOpen(): boolean
	return closeCurrent ~= nil
end

function PurchaseCelebration.Close()
	local close = closeCurrent
	if close then
		close()
	end
end

-- `payload`: a Granted ShopPurchased { Key, Lines, Effects, Test }.
function PurchaseCelebration.Show(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Key) ~= "string" then
		return
	end
	PurchaseCelebration.Close()
	token += 1
	local myToken = token
	local key = payload.Key :: string
	local entry = ShopConfig.GetItem(key)
	local effects: { { [string]: any } } = if typeof(payload.Effects) == "table" then payload.Effects else {}
	local screen = gui()
	local phone = UIKit.IsPhone()
	local pair = sectionPair(key)
	local z = 2

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Colors.Black
	backdrop.BackgroundTransparency = 1
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.ZIndex = z
	backdrop.Parent = screen
	TweenService:Create(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.35 }):Play()

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundTransparency = 1
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(CARD_SIZE.X, if phone then CARD_SIZE.Y - 80 else CARD_SIZE.Y)
	card.ZIndex = z + 1
	card.Parent = screen
	UIKit.FitHeight(card, card.Size.Y.Offset)
	UIKit.SetOverlay("PurchaseCelebration", true)

	rays(card, pair.Top, z + 1)
	confetti(card, { pair.Top, pair.Bottom, UITheme.World.AccentGold, UITheme.World.VipGold }, UDim2.new(0.5, 0, 0, 180), z + 9)
	SoundKit.Play("RevealMajor", nil)

	local context: Context = {
		Token = myToken,
		Gui = screen,
		Card = card,
		Line = UIKit.Label({
			Name = "Effect",
			Text = "",
			RichText = true,
			Font = Fonts.Display,
			TextSize = 28,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, if phone then 330 else 410),
			Size = UDim2.new(1, -40, 0, 36),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			ZIndex = z + 6,
			Stroke = UITheme.Stroke.Text,
			Parent = card,
		}),
		Z = z,
		Skipped = false,
	}

	local closed = false
	local sequenceDone = false
	local opened = os.clock()
	local function close()
		if closed then
			return
		end
		closed = true
		context.Skipped = true
		closeCurrent = nil
		UIKit.SetOverlay("PurchaseCelebration", false)
		local fade = TweenService:Create(backdrop, TweenInfo.new(0.15), { BackgroundTransparency = 1 })
		fade:Play()
		UIKit.PopOut(card).Completed:Once(function()
			card:Destroy()
			backdrop:Destroy()
		end)
	end
	closeCurrent = close

	backdrop.Activated:Connect(function()
		if os.clock() - opened < SKIP_AFTER_SECONDS then
			return
		end
		if sequenceDone then
			close()
		else
			context.Skipped = true
		end
	end)

	-- The item (0.3-1.2 s).
	task.delay(0.3, function()
		if token ~= myToken or closed then
			return
		end
		UIKit.Label({
			Name = "Thanks",
			Text = "THANK YOU!",
			Font = Fonts.Display,
			TextSize = 40,
			TextColor3 = Colors.GoldLabel,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Size = UDim2.new(1, 0, 0, 48),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 6,
			Stroke = 4,
			Parent = card,
		})
		itemIcon(card, key, if phone then ICON_SIZE.Phone else ICON_SIZE.Desktop, z + 4)
		local name = if entry then entry.Name else key
		UIKit.Label({
			Name = "Name",
			Text = name .. (if payload.Test == true then "  (Studio test)" else ""),
			Font = Fonts.Display,
			TextSize = if phone then 28 else 36,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, if phone then 56 + ICON_SIZE.Phone + 14 else 56 + ICON_SIZE.Desktop + 18),
			Size = UDim2.new(1, -20, 0, 44),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = z + 6,
			Stroke = 4,
			Parent = card,
		})
	end)

	-- What you got, one effect after another, then AWESOME!.
	task.spawn(function()
		if not wait(context, if context.Skipped then 0 else 1.0) then
			return
		end
		for index, effect in effects do
			if token ~= myToken or closed then
				return
			end
			playEffect(context, effect)
			if index < #effects and not wait(context, if context.Skipped then 0.05 else 1.1 + EFFECT_GAP_SECONDS) then
				return
			end
		end
		if token ~= myToken or closed then
			return
		end
		sequenceDone = true
		UIKit.Button({
			Name = "Awesome",
			Parent = card,
			Style = "Green",
			Text = "AWESOME!",
			TextSize = 22,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.fromOffset(220, 56),
			ZIndex = z + 7,
			OnClick = close,
		})
	end)
end

return PurchaseCelebration
