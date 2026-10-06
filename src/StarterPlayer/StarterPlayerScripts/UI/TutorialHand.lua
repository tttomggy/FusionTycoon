--!strict
--[[
	TutorialHand
	------------
	Tutorial 2's two pointers, both drawn here and nowhere else:

	  * THE HAND 👆: one for the whole UI, never a rectangle. A big glyph with
	    a drop shadow that sits just below-right of its target and bobs toward
	    it (a 👇 above the target when the target is on the lower half of the
	    screen, where there is no room below). Its target is any GuiObject: a
	    HUD button, a panel button (AUTO-FILL, FUSE) or the contextual button.
	    It follows the target every frame and hides when the target isn't
	    on screen. Above every panel, never takes a tap.
	  * THE CONTEXTUAL BUTTON: a big green button just above the bottom bar,
	    labelled with the action ("PULL", "UPGRADE", "FUSE", "BUY"), shown
	    while you stand at a world target so nobody needs to know about E.
	    Tapping it runs `onClick` (the controller fires the real prompt).

	  SetTarget(gui?)              where the hand points (nil: no hand)
	  SetContextual(text?, onClick) show / hide the big button
	  GetContextualButton()        its holder (the hand's target on world steps)
	  IsContextualShown() / GetTarget()
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.UIKit)

local TutorialHand = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local HAND_DISPLAY_ORDER = 175 -- over every modal (the Tutorial cards are 165)
local BUTTON_DISPLAY_ORDER = 62 -- over the HUD, under every panel
local HAND_SIZE = 64
local BOB_PIXELS = 12
local BOB_SECONDS = 0.45
local BUTTON_SIZE = { Desktop = Vector2.new(280, 84), Phone = Vector2.new(240, 72) }
local BUTTON_GAP = 14 -- above the bottom bar's reserve

local handGui: ScreenGui
local handRoot: Frame
local handLabel: TextLabel
local handShadow: TextLabel
local target: GuiObject? = nil

local buttonGui: ScreenGui
local buttonHolder: Frame
local buttonBody: TextButton
local buttonOnClick: (() -> ())? = nil
local buttonShown = false

local function isOnScreen(gui: GuiObject): boolean
	if not gui:IsDescendantOf(game) or gui.AbsoluteSize.X <= 0 then
		return false
	end
	-- Visible all the way up (a hidden panel keeps its children's Visible).
	local current: Instance? = gui
	while current and not current:IsA("LayerCollector") do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	if current and current:IsA("ScreenGui") and not current.Enabled then
		return false
	end
	return true
end

local function placeHand()
	local gui = target
	if not gui or not isOnScreen(gui) then
		handRoot.Visible = false
		return
	end
	local scale = UIKit.EffectiveScale(handRoot)
	local position = gui.AbsolutePosition / scale
	local size = gui.AbsoluteSize / scale
	local viewport = UIKit.GetLogicalViewport()
	local below = (position.Y + size.Y / 2) < viewport.Y * 0.6
	local bob = math.sin(os.clock() * (math.pi * 2) / (BOB_SECONDS * 2)) * 0.5 + 0.5 -- 0..1
	local toward = bob * BOB_PIXELS
	handLabel.Text = if below then "👆" else "👇"
	handShadow.Text = handLabel.Text
	-- Below-right of the target (or above-right on the lower half), nudged
	-- toward it as it bobs.
	local x = position.X + size.X * 0.7
	local y = if below then position.Y + size.Y * 0.75 - toward else position.Y - HAND_SIZE * 0.75 + size.Y * 0.25 + toward
	x = math.clamp(x, 0, viewport.X - HAND_SIZE)
	y = math.clamp(y, 0, viewport.Y - HAND_SIZE)
	handRoot.Position = UDim2.fromOffset(x, y)
	handRoot.Visible = true
end

function TutorialHand.SetTarget(gui: GuiObject?)
	target = gui
	if not gui then
		handRoot.Visible = false
	end
end

function TutorialHand.GetTarget(): GuiObject?
	return target
end

--[[ The contextual button ------------------------------------------------------------- ]]

local function placeButton()
	local phone = UIKit.IsPhone()
	local size = if phone then BUTTON_SIZE.Phone else BUTTON_SIZE.Desktop
	buttonHolder.Size = UDim2.fromOffset(size.X, size.Y)
	buttonHolder.Position = UDim2.new(0.5, 0, 1, -(UIKit.GetCardBottom() + BUTTON_GAP))
end

function TutorialHand.SetContextual(text: string?, onClick: (() -> ())?)
	if not text then
		buttonOnClick = nil
		if buttonShown then
			buttonShown = false
			local tween = UIKit.PopOut(buttonHolder)
			tween.Completed:Once(function()
				if not buttonShown then
					buttonHolder.Visible = false
				end
			end)
		end
		return
	end
	buttonOnClick = onClick
	UIKit.SetButton(buttonBody, { Text = text })
	if not buttonShown then
		buttonShown = true
		placeButton()
		UIKit.PopIn(buttonHolder)
	end
end

function TutorialHand.GetContextualButton(): GuiObject?
	return if buttonShown then buttonHolder else nil
end

function TutorialHand.IsContextualShown(): boolean
	return buttonShown
end

function TutorialHand.Init()
	buttonGui = UIKit.Screen("TutorialAction", BUTTON_DISPLAY_ORDER)
	local body, holder = UIKit.Button({
		Name = "ContextualButton",
		Parent = buttonGui,
		Style = "Green",
		Text = "GO",
		TextSize = 36,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(BUTTON_SIZE.Desktop.X, BUTTON_SIZE.Desktop.Y),
		OnClick = function()
			local handler = buttonOnClick
			if handler then
				handler()
			end
		end,
	})
	buttonBody = body
	buttonHolder = holder
	holder.Visible = false
	placeButton()
	UIKit.LayoutChanged:Connect(placeButton)

	handGui = UIKit.Screen("TutorialHand", HAND_DISPLAY_ORDER)
	handRoot = Instance.new("Frame")
	handRoot.Name = "Hand"
	handRoot.BackgroundTransparency = 1
	handRoot.Active = false
	handRoot.Size = UDim2.fromOffset(HAND_SIZE, HAND_SIZE)
	handRoot.Visible = false
	handRoot.Parent = handGui
	-- A shadow: the same glyph in ink, offset down-right.
	handShadow = UIKit.Label({
		Name = "Shadow",
		Text = "👆",
		Font = Fonts.Display,
		TextSize = HAND_SIZE,
		TextColor3 = Colors.Ink,
		TextTransparency = 0.55,
		Position = UDim2.fromOffset(4, 5),
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 1,
		Parent = handRoot,
	})
	handLabel = UIKit.Label({
		Name = "Glyph",
		Text = "👆",
		Font = Fonts.Display,
		TextSize = HAND_SIZE,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
		Parent = handRoot,
	})
	RunService:BindToRenderStep("TutorialHand", Enum.RenderPriority.Last.Value + 1, placeHand)
end

return TutorialHand
