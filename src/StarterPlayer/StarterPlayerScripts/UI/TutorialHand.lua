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
local GuiService = game:GetService("GuiService")
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
-- The fingertip inside the glyph box (fractions of HAND_SIZE).
local TIP_X = 0.5
local TIP_UP = 0.12 -- 👆: near the top
local TIP_DOWN = 0.88 -- 👇: near the bottom
local BUTTON_SIZE = { Desktop = Vector2.new(280, 84), Phone = Vector2.new(240, 72) }
local BUTTON_GAP = 14 -- above the bottom bar's reserve

local handGui: ScreenGui
local handRoot: Frame
local handLabel: TextLabel
local handShadow: TextLabel
local target: GuiObject? = nil
local tipAbs: Vector2? = nil

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

-- The target's centre must be on the screen and inside every scrolling
-- frame it sits in (a button scrolled out of its list is not pointed at).
local function centreVisible(gui: GuiObject, centre: Vector2): boolean
	local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	local inset = GuiService:GetGuiInset().Y
	if centre.X < 0 or centre.X > view.X or centre.Y < -inset or centre.Y > view.Y - inset then
		return false
	end
	local current = gui.Parent
	while current and not current:IsA("LayerCollector") do
		if current:IsA("ScrollingFrame") then
			local p, sz = current.AbsolutePosition, current.AbsoluteSize
			if centre.X < p.X or centre.X > p.X + sz.X or centre.Y < p.Y or centre.Y > p.Y + sz.Y then
				return false
			end
		end
		current = current.Parent
	end
	return true
end

local function placeHand()
	local gui = target
	if not gui or not isOnScreen(gui) then
		handRoot.Visible = false
		tipAbs = nil
		return
	end
	-- AbsolutePosition is measured BELOW the Roblox top bar even in an
	-- IgnoreGuiInset gui (the hand's), so the inset is added back when
	-- converting to the hand gui's logical px.
	local scale = UIKit.EffectiveScale(handRoot)
	local inset = GuiService:GetGuiInset().Y
	local absPos, absSize = gui.AbsolutePosition, gui.AbsoluteSize
	if not centreVisible(gui, absPos + absSize / 2) then
		handRoot.Visible = false
		tipAbs = nil
		return
	end
	local viewport = UIKit.GetLogicalViewport()
	local centreY = (absPos.Y + inset + absSize.Y / 2) / scale
	local below = centreY < viewport.Y * 0.6
	local bob = math.sin(os.clock() * (math.pi * 2) / (BOB_SECONDS * 2)) * 0.5 + 0.5 -- 0..1
	local heightLogical = absSize.Y / scale
	local toward = bob * math.min(BOB_PIXELS, heightLogical * 0.3)
	handLabel.Text = if below then "👆" else "👇"
	handShadow.Text = handLabel.Text
	-- The fingertip lands inside the target: low in it for a 👆 (the hand
	-- hangs below), high in it for a 👇 (the hand hangs above), nudged
	-- toward its middle as it bobs.
	local tipX = (absPos.X + absSize.X * 0.5) / scale
	local tipY = (absPos.Y + inset) / scale + heightLogical * (if below then 0.65 else 0.35) + (if below then -toward else toward)
	local x = tipX - HAND_SIZE * TIP_X
	local y = tipY - HAND_SIZE * (if below then TIP_UP else TIP_DOWN)
	handRoot.Position = UDim2.fromOffset(x, y)
	handRoot.Visible = true
	tipAbs = Vector2.new(tipX * scale, tipY * scale - inset)
end

-- Where the fingertip is, in the same px space as a GuiObject's
-- AbsolutePosition (/selftest: it must lie inside the target's rect).
function TutorialHand.GetTip(): Vector2?
	return if handRoot.Visible then tipAbs else nil
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
