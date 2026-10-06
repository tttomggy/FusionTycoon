--!strict
--[[
	TutorialBanner
	--------------
	Tutorial 2's one instruction at a time: a big banner at the top centre
	(where the event chip lives; the chip stays hidden until its own step),
	the way the egg games do it.

	  "Upgrade your generator · 8m"      big white Display text, ink stroke
	  "Your first 2 are free!"           optional second line, muted, small
	  [SKIP ›]                            only in a replay (every step may be left)

	No panel, no button, nothing to read twice: it changes the moment the
	step is done (Complete: a green ✓ and the word pops, then it slides out;
	the controller slides the next one in 0.4 s later).

	The only card the tutorial still has is the welcome splash after the
	claim: "WELCOME TO YOUR LAB!" and the lab's name, centred, fading by
	itself after TutorialConfig.WelcomeSeconds. No button.

	  Show(text, sub?)       slides in (replaces what's up)
	  SetDistance(studs?)    " · 24m" after the text (nil: none)
	  Complete()             ✓ + pop, then out; returns when it is gone
	  Hide()                 out at once
	  SetSkip(handler?)      the replay's SKIP chip (nil hides it)
	  ShowSplash(title, sub) the welcome splash
	  GetText() / IsShown()  /selftest
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
local TOP = 12 -- the event chip's row
local TEXT_SIZE = { Desktop = 36, Phone = 28 }
local SUB_SIZE = { Desktop = 18, Phone = 14 }
local MAX_WIDTH = 720
local SLIDE_OFFSET = 70
local SLIDE_SECONDS = 0.3
local OUT_SECONDS = 0.2

local screenGui: ScreenGui
local root: Frame
local rootScale: UIScale
local textLabel: TextLabel
local subLabel: TextLabel
local skipHolder: Frame
local shown = false
local baseText = ""
local distanceText = ""
local completing = false
local token = 0
local skipHandler: (() -> ())? = nil

local splashGui: ScreenGui
local splashHolder: Frame
local splashTitle: TextLabel
local splashSub: TextLabel
local splashToken = 0

local function isPhone(): boolean
	return UIKit.IsPhone()
end

local function render()
	textLabel.Text = baseText .. distanceText
end

local function applySizes()
	local phone = isPhone()
	textLabel.TextSize = if phone then TEXT_SIZE.Phone else TEXT_SIZE.Desktop
	subLabel.TextSize = if phone then SUB_SIZE.Phone else SUB_SIZE.Desktop
end

local function slideTo(y: number, transparency: number, seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, if transparency == 0 then Enum.EasingDirection.Out else Enum.EasingDirection.In)
	TweenService:Create(root, info, { Position = UDim2.new(0.5, 0, 0, y) }):Play()
	for _, label in { textLabel, subLabel } do
		TweenService:Create(label, info, { TextTransparency = transparency }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, info, { Transparency = transparency }):Play()
		end
	end
end

function TutorialBanner.Show(text: string, sub: string?)
	token += 1
	completing = false
	baseText = text
	distanceText = ""
	applySizes()
	render()
	textLabel.TextColor3 = Colors.Text
	rootScale.Scale = 1
	subLabel.Text = sub or ""
	subLabel.Visible = sub ~= nil and sub ~= ""
	root.Visible = true
	if not shown then
		root.Position = UDim2.new(0.5, 0, 0, TOP - SLIDE_OFFSET)
		textLabel.TextTransparency = 1
		subLabel.TextTransparency = 1
		for _, label in { textLabel, subLabel } do
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 1
			end
		end
	else
		-- A new instruction replaces the old one in place with a small pop.
		textLabel.TextTransparency = 0
		subLabel.TextTransparency = 0
	end
	shown = true
	slideTo(TOP, 0, SLIDE_SECONDS)
	rootScale.Scale = 0.92
	TweenService:Create(rootScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function TutorialBanner.SetDistance(studs: number?)
	if completing then
		return
	end
	local text = if studs then (" · %dm"):format(math.max(0, math.floor(studs + 0.5))) else ""
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
	baseText = "✓ " .. baseText
	distanceText = ""
	render()
	textLabel.TextColor3 = Colors.Cash
	rootScale.Scale = 1.12
	TweenService:Create(rootScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.wait(TutorialConfig.StepDelay)
	if token ~= mine then
		return
	end
	slideTo(TOP - SLIDE_OFFSET, 1, OUT_SECONDS)
	shown = false
end

function TutorialBanner.Hide()
	token += 1
	completing = false
	if shown then
		slideTo(TOP - SLIDE_OFFSET, 1, OUT_SECONDS)
		shown = false
	end
	root.Visible = false
end

function TutorialBanner.SetSkip(handler: (() -> ())?)
	skipHandler = handler
	skipHolder.Visible = handler ~= nil
end

function TutorialBanner.GetText(): string
	return textLabel.Text
end

function TutorialBanner.IsShown(): boolean
	return shown and root.Visible
end

-- Words in the instruction (/selftest: at most 6).
function TutorialBanner.GetBaseText(): string
	return baseText
end

--[[ Welcome splash ----------------------------------------------------------------- ]]

function TutorialBanner.ShowSplash(title: string, sub: string)
	splashToken += 1
	local mine = splashToken
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

	root = Instance.new("Frame")
	root.Name = "Banner"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, TOP - SLIDE_OFFSET)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Size = UDim2.new(0.8, 0, 0, 0)
	root.Visible = false
	root.Parent = screenGui
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(MAX_WIDTH, math.huge)
	sizeLimit.Parent = root
	rootScale = Instance.new("UIScale")
	rootScale.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = root

	textLabel = UIKit.Label({
		Name = "Text",
		Font = Fonts.Display,
		TextSize = TEXT_SIZE.Desktop,
		TextColor3 = Colors.Text,
		Size = UDim2.new(1, 0, 0, 46),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		LayoutOrder = 1,
		Stroke = 4,
		Parent = root,
	})
	UIKit.FitText(textLabel, TEXT_SIZE.Desktop, 18)
	subLabel = UIKit.Label({
		Name = "Sub",
		Font = Fonts.BodyHeavy,
		TextSize = SUB_SIZE.Desktop,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		LayoutOrder = 2,
		Stroke = 3,
		Visible = false,
		Parent = root,
	})

	-- SKIP › (a replay only).
	local _, holder = UIKit.Button({
		Name = "Skip",
		Parent = root,
		Style = "Disabled",
		Text = "SKIP ›",
		TextSize = 16,
		Size = UDim2.fromOffset(110, UITheme.MinTapSize),
		LayoutOrder = 3,
		OnClick = function()
			local handler = skipHandler
			if handler then
				handler()
			end
		end,
	})
	skipHolder = holder
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

	UIKit.LayoutChanged:Connect(function()
		applySizes()
	end)
end

return TutorialBanner
