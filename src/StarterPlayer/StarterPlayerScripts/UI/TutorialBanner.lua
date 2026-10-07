--!strict
--[[
	TutorialBanner
	--------------
	Tutorial 3's OBJECTIVE BAR: one instruction at a time in a solid dark
	panel with a lime border, top centre just under the Roblox top bar. It
	sits below the event chip's row while the tutorial runs.

	  [ 48 px step icon ]  Upgrade your generator          [ 24m ]
	                       3 / 11 · Your first 2 are free!

	The instruction is 36 px white display text (28 on a phone, where the bar
	is the full width minus 16 px margins), the live distance a lime pill on
	the right, a small step counter under it (the step's sub line follows it
	after a "·"). It pulses when it changes. Desktop width 600 px
	(TutorialConfig.Objective: 520-640). A replay adds a SKIP chip at the
	right end.

	No button, nothing to read twice: it changes the moment the step is done
	(Complete: a green ✓ and the word pops, then it slides out; the
	controller slides the next one in 0.4 s later).

	The welcome splash after the claim ("WELCOME TO YOUR LAB!" + the lab's
	name, centred, fading by itself after TutorialConfig.WelcomeSeconds, no
	button).

	  Show(text, sub?, icon?, step?, total?)   slides in / pops (replaces what's up)
	  SetDistance(studs?)    the lime pill "24m" (nil: none)
	  SetSub(text?)          the counter line's second part only, no slide
	  Complete()             ✓ + pop, then out; returns when it is gone
	  Hide()                 out at once
	  SetSkip(handler?)      the replay's SKIP chip (nil hides it)
	  ShowSplash(title, sub) the welcome splash
	  GetText() / GetBaseText() / IsShown() / GetFrame()   /selftest
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.UIKit)

local TutorialBanner = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local DISPLAY_ORDER = 60 -- over the HUD (40) and the event chip (41), under every panel
local TEXT_SIZE = { Desktop = 36, Phone = 28 }
local BAR_HEIGHT = { Desktop = 84, Phone = 72 }
local ICON_SIZE = 48
local PADDING = 14
local SLIDE_OFFSET = 110 -- px above its place when hidden
local SLIDE_SECONDS = 0.3
local OUT_SECONDS = 0.2
local PULSE_SCALE = 1.06

local screenGui: ScreenGui
local holder: Frame
local body: Frame
local pulse: UIScale
local iconLabel: TextLabel
local textLabel: TextLabel
local counterLabel: TextLabel
local distancePill: TextLabel
local skipHolder: Frame
local slideValue: NumberValue
local shown = false
local baseText = ""
local distanceText = ""
local subText = ""
local stepText = ""
local completing = false
local token = 0
local skipHandler: (() -> ())? = nil

local splashGui: ScreenGui
local splashHolder: Frame
local splashTitle: TextLabel
local splashSub: TextLabel
local splashToken = 0
local playSplash: (string, string, number) -> ()

local function isPhone(): boolean
	return UIKit.IsPhone()
end

local function barHeight(): number
	return if isPhone() then BAR_HEIGHT.Phone else BAR_HEIGHT.Desktop
end

-- Just under the Roblox top bar, plus the slide.
local function apply()
	holder.Position = UDim2.new(0.5, 0, 0, UIKit.GetCardTop() - slideValue.Value)
end

local function applyLayout()
	local phone = isPhone()
	local height = barHeight()
	local width = TutorialConfig.ObjectiveWidth
	holder.Size = if phone
		then UDim2.new(1, -math.ceil(TutorialConfig.ObjectiveMarginPhone / UITheme.PhoneScale), 0, height + UITheme.ShadowOffset)
		else UDim2.fromOffset(width, height + UITheme.ShadowOffset)
	body.Size = UDim2.new(1, 0, 0, height)
	textLabel.TextSize = if phone then TEXT_SIZE.Phone else TEXT_SIZE.Desktop
	UIKit.FitText(textLabel, textLabel.TextSize, 18)
	iconLabel.TextSize = if phone then 34 else 40
end

local function render()
	textLabel.Text = baseText
	local parts = {}
	if stepText ~= "" then
		table.insert(parts, stepText)
	end
	if subText ~= "" then
		table.insert(parts, subText)
	end
	counterLabel.Text = table.concat(parts, " · ")
	local pillRoot = UIKit.PillRoot(distancePill)
	pillRoot.Visible = distanceText ~= ""
	distancePill.Text = distanceText
end

local function slideTo(target: number, seconds: number, direction: Enum.EasingDirection)
	TweenService:Create(slideValue, TweenInfo.new(seconds, Enum.EasingStyle.Quad, direction), { Value = target }):Play()
end

local function popPulse(from: number)
	pulse.Scale = from
	TweenService:Create(pulse, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function TutorialBanner.Show(text: string, sub: string?, icon: string?, step: number?, total: number?)
	token += 1
	completing = false
	baseText = text
	distanceText = ""
	subText = sub or ""
	stepText = if step and total then ("%d / %d"):format(step, total) else ""
	iconLabel.Text = icon or ""
	iconLabel.Visible = icon ~= nil
	textLabel.TextColor3 = Colors.Text
	applyLayout()
	render()
	holder.Visible = true
	if not shown then
		slideValue.Value = SLIDE_OFFSET
		shown = true
		slideTo(0, SLIDE_SECONDS, Enum.EasingDirection.Out)
	end
	apply()
	popPulse(PULSE_SCALE)
end

-- Changes only the counter line's second part (no slide): "Come back with
-- $X" ticks with cash.
function TutorialBanner.SetSub(sub: string?)
	local text = sub or ""
	if text ~= subText then
		subText = text
		render()
	end
end

function TutorialBanner.SetDistance(studs: number?)
	if completing then
		return
	end
	local text = if studs then ("%dm"):format(math.max(0, math.floor(studs + 0.5))) else ""
	if text ~= distanceText then
		distanceText = text
		render()
	end
end

-- ✓ in green, a pop, a short hold (TutorialConfig.StepDelay), then out.
-- Yields for the hold, so the next step's banner slides in right after it.
function TutorialBanner.Complete()
	if not shown then
		return
	end
	completing = true
	token += 1
	local mine = token
	iconLabel.Text = "✓"
	iconLabel.Visible = true
	baseText = "✓ " .. baseText
	distanceText = ""
	render()
	textLabel.TextColor3 = Colors.Cash
	popPulse(1.12)
	task.wait(TutorialConfig.StepDelay)
	if token ~= mine then
		return
	end
	slideTo(SLIDE_OFFSET, OUT_SECONDS, Enum.EasingDirection.In)
	shown = false
end

function TutorialBanner.Hide()
	token += 1
	completing = false
	if shown then
		slideTo(SLIDE_OFFSET, OUT_SECONDS, Enum.EasingDirection.In)
		shown = false
	end
	task.delay(OUT_SECONDS, function()
		if not shown then
			holder.Visible = false
		end
	end)
end

function TutorialBanner.SetSkip(handler: (() -> ())?)
	skipHandler = handler
	skipHolder.Visible = handler ~= nil
end

function TutorialBanner.GetText(): string
	return textLabel.Text
end

function TutorialBanner.IsShown(): boolean
	return shown and holder.Visible
end

-- Words in the instruction (/selftest: at most 6).
function TutorialBanner.GetBaseText(): string
	return baseText
end

-- The bar's body (/selftest: size, text size, border).
function TutorialBanner.GetFrame(): Frame
	return body
end

function TutorialBanner.GetTextLabel(): TextLabel
	return textLabel
end

function TutorialBanner.GetStepText(): string
	return stepText
end

--[[ Welcome splash ----------------------------------------------------------------- ]]

function TutorialBanner.ShowSplash(title: string, sub: string)
	splashToken += 1
	local mine = splashToken
	task.spawn(playSplash, title, sub, mine)
end

function playSplash(title: string, sub: string, mine: number)
	if splashToken ~= mine then
		return
	end
	splashTitle.Text = title
	splashSub.Text = sub
	splashHolder.Visible = true
	local scale = splashHolder:FindFirstChild("SplashScale") :: UIScale
	scale.Scale = 0.7
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	for _, label in { splashTitle, splashSub } do
		label.TextTransparency = 1
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 1
		end
		TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 0 }):Play()
		end
	end
	task.delay(TutorialConfig.WelcomeSeconds, function()
		if splashToken ~= mine then
			return
		end
		for _, label in { splashTitle, splashSub } do
			TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
			end
		end
		task.wait(0.4)
		if splashToken == mine then
			splashHolder.Visible = false
		end
	end)
end

function TutorialBanner.IsSplashShown(): boolean
	return splashHolder.Visible
end

--[[ Build ------------------------------------------------------------------------------ ]]

function TutorialBanner.Init()
	screenGui = UIKit.Screen("TutorialBanner", DISPLAY_ORDER)

	slideValue = Instance.new("NumberValue")
	slideValue.Value = SLIDE_OFFSET
	slideValue.Changed:Connect(apply)

	holder = Instance.new("Frame")
	holder.Name = "ObjectiveBar"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Size = UDim2.fromOffset(TutorialConfig.ObjectiveWidth, BAR_HEIGHT.Desktop + UITheme.ShadowOffset)
	holder.Visible = false
	holder.Parent = screenGui
	pulse = Instance.new("UIScale")
	pulse.Parent = holder

	-- A solid dark panel with a lime border.
	body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = Colors.Panel
	body.BorderSizePixel = 0
	body.Size = UDim2.new(1, 0, 0, BAR_HEIGHT.Desktop)
	body.ZIndex = 2
	body.Parent = holder
	UIKit.Corner(body, 18)
	UIKit.Stroke(body, 4, UITheme.World.TutorialPath)
	UIKit.Shadow(body)

	iconLabel = UIKit.Label({
		Name = "Icon",
		Font = Fonts.Display,
		TextSize = 40,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, PADDING, 0.5, 0),
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Parent = body,
	})
	local left = PADDING + ICON_SIZE + 10
	local right = 100 -- the distance pill's room
	textLabel = UIKit.Label({
		Name = "Text",
		Font = Fonts.Display,
		TextSize = TEXT_SIZE.Desktop,
		TextColor3 = Colors.Text,
		Position = UDim2.fromOffset(left, 6),
		Size = UDim2.new(1, -(left + right), 0, 46),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Stroke = 3,
		Parent = body,
	})
	UIKit.FitText(textLabel, TEXT_SIZE.Desktop, 18)
	counterLabel = UIKit.Label({
		Name = "Counter",
		Font = Fonts.BodyHeavy,
		TextSize = 16,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(left, 54),
		Size = UDim2.new(1, -(left + right), 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
		Stroke = 2,
		Parent = body,
	})
	UIKit.FitText(counterLabel, 16, 11)

	-- The distance: a lime pill at the right end.
	distancePill = UIKit.Pill({
		Name = "Distance",
		Parent = body,
		Text = "",
		Color = UITheme.World.TutorialPath,
		Font = Fonts.Display,
		TextSize = 24,
		Height = 36,
		TextStroke = 2,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -PADDING, 0.5, 0),
		ZIndex = 3,
	})
	UIKit.PillRoot(distancePill).Visible = false

	-- SKIP › (a replay only), left of the pill.
	local _, skip = UIKit.Button({
		Name = "Skip",
		Parent = body,
		Style = "Disabled",
		Text = "SKIP ›",
		TextSize = 16,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(PADDING + 84), 0.5, 0),
		Size = UDim2.fromOffset(90, UITheme.MinTapSize),
		ZIndex = 4,
		OnClick = function()
			local handler = skipHandler
			if handler then
				handler()
			end
		end,
	})
	skipHolder = skip
	skipHolder.Visible = false

	-- The welcome splash: centred plain text, no card, no button.
	splashGui = UIKit.Screen("TutorialSplash", DISPLAY_ORDER + 1)
	splashHolder = Instance.new("Frame")
	splashHolder.Name = "Splash"
	splashHolder.BackgroundTransparency = 1
	splashHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	splashHolder.Position = UDim2.fromScale(0.5, 0.42)
	splashHolder.Size = UDim2.new(0.9, 0, 0, 150)
	splashHolder.Visible = false
	splashHolder.Parent = splashGui
	local splashScale = Instance.new("UIScale")
	splashScale.Name = "SplashScale"
	splashScale.Parent = splashHolder
	splashTitle = UIKit.Label({
		Name = "Title",
		Font = Fonts.Display,
		TextSize = 56,
		TextColor3 = Colors.Text,
		Size = UDim2.new(1, 0, 0, 80),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = 5,
		Parent = splashHolder,
	})
	UIKit.FitText(splashTitle, 56, 24)
	splashSub = UIKit.Label({
		Name = "Sub",
		Font = Fonts.Display,
		TextSize = 30,
		TextColor3 = Colors.GoldLabel,
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.new(1, 0, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = 4,
		Parent = splashHolder,
	})
	UIKit.FitText(splashSub, 30, 16)

	applyLayout()
	UIKit.LayoutChanged:Connect(applyLayout)
end

return TutorialBanner
