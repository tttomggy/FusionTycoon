--!strict
--[[
	TutorialHand
	------------
	Tutorial 2's two pointers, both drawn here and nowhere else:

	  * THE HAND 👇: one for the whole UI, never a rectangle. A big glyph with
	    a drop shadow that sits ABOVE its target, fingertip about 6 px over
	    the target's top edge (centred), and bobs down toward it; it never
	    covers the target (and so never its text). A target too near the top
	    of the screen for that gets the hand BELOW it, a 👆 pointing up. Its
	    target is any GuiObject: a HUD button, a panel button (AUTO-FILL,
	    FUSE) or the contextual button. It follows the target every frame and
	    hides when the target isn't on screen. Above every panel, never takes
	    a tap.
	  * THE CONTEXTUAL BUTTON: a big green button just above the bottom bar,
	    labelled with the action ("PULL", "UPGRADE", "FUSE", "BUY"), shown
	    while you stand at a world target so nobody needs to know about E.
	    Tapping it runs `onClick` (the controller fires the real prompt).

	  SetTarget(gui?)              where the hand points (nil: no hand)
	  SetCaption(text?)            a small pill beside the hand ("+$13.3/s")
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
local BOB_SECONDS = 0.45
-- The fingertip inside the glyph (fractions of HAND_SIZE). The hand's box
-- (the rect /selftest checks) ends exactly AT the fingertip, so the box
-- itself never reaches the target: the glyph is shifted inside it.
local TIP_X = 0.5
local TIP_UP = 0.12 -- 👆: near the top of the glyph
local TIP_DOWN = 0.88 -- 👇: near the bottom of the glyph
local TIP_GAP = 6 -- px between the fingertip and the target's edge (nearest the bob)
local BOB_PIXELS = 5 -- the tip bobs from TIP_GAP to TIP_GAP + this away
local BUTTON_SIZE = { Desktop = Vector2.new(280, 84), Phone = Vector2.new(240, 72) }
local BUTTON_GAP = 14 -- above the bottom bar's reserve

local handGui: ScreenGui
local handRoot: Frame
local handLabel: TextLabel
local handShadow: TextLabel
local target: GuiObject? = nil
local tipAbs: Vector2? = nil
local rectAbs: { Position: Vector2, Size: Vector2 }? = nil

local captionPill: TextLabel
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
		rectAbs = nil
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
		rectAbs = nil
		return
	end
	local top = (absPos.Y + inset) / scale
	local bottom = top + absSize.Y / scale
	-- Above the target unless that would run off the top of the screen.
	local above = top - TIP_GAP - BOB_PIXELS - HAND_SIZE >= 0
	local bob = math.sin(os.clock() * (math.pi * 2) / (BOB_SECONDS * 2)) * 0.5 + 0.5 -- 0..1
	local away = TIP_GAP + (1 - bob) * BOB_PIXELS -- nearest the target at the bottom of the bob
	handLabel.Text = if above then "👇" else "👆"
	handShadow.Text = handLabel.Text
	-- The glyph sits in the box so its fingertip is on the box's edge.
	local glyphY = if above then HAND_SIZE * (1 - TIP_DOWN) else -HAND_SIZE * TIP_UP
	handLabel.Position = UDim2.fromOffset(0, glyphY)
	handShadow.Position = UDim2.fromOffset(4, glyphY + 5)
	local tipX = (absPos.X + absSize.X * 0.5) / scale
	local tipY = if above then top - away else bottom + away
	local x = tipX - HAND_SIZE * TIP_X
	local y = if above then tipY - HAND_SIZE else tipY
	handRoot.Position = UDim2.fromOffset(x, y)
	handRoot.Visible = true
	tipAbs = Vector2.new(tipX * scale, tipY * scale - inset)
	rectAbs = { Position = Vector2.new(x * scale, y * scale - inset), Size = Vector2.new(HAND_SIZE * scale, HAND_SIZE * scale) }
end

-- Where the fingertip is, in the same px space as a GuiObject's
-- AbsolutePosition (/selftest: within 12 px of the target's top-centre).
function TutorialHand.GetTip(): Vector2?
	return if handRoot.Visible then tipAbs else nil
end

-- The hand's box in the same px space (/selftest: it must not overlap the
-- target's rect).
function TutorialHand.GetRect(): { Position: Vector2, Size: Vector2 }?
	return if handRoot.Visible then rectAbs else nil
end

-- /selftest: why the hand is not showing ("not placed yet" before its first
-- frame), nil while it shows.
function TutorialHand.GetBlocker(): string?
	if handRoot.Visible then
		return nil
	end
	local gui = target
	if not gui then
		return "no target"
	end
	if not isOnScreen(gui) then
		return "the target is not shown (hidden, disabled, or zero width)"
	end
	local centre = gui.AbsolutePosition + gui.AbsoluteSize / 2
	if not centreVisible(gui, centre) then
		return ("the target's centre %.0f,%.0f is off the screen or outside a scroll view"):format(centre.X, centre.Y)
	end
	return "not placed yet"
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

-- A small pill beside the hand (right of the glyph, level with the
-- fingertip's side); nil hides it.
function TutorialHand.SetCaption(text: string?)
	UIKit.SetPillVisible(captionPill, text ~= nil)
	captionPill.Text = text or ""
end

function TutorialHand.GetCaption(): string?
	return if UIKit.PillRoot(captionPill).Visible then captionPill.Text else nil
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
	-- The caption pill rides the hand: right of the glyph, mid-height.
	captionPill = UIKit.Pill({
		Name = "Caption",
		Parent = handRoot,
		Text = "",
		Gradient = UITheme.Gradients.Green,
		TextSize = 16,
		Height = 26,
		Position = UDim2.fromOffset(HAND_SIZE + 2, HAND_SIZE / 2 - 13),
		ZIndex = 3,
	})
	UIKit.SetPillVisible(captionPill, false)
	RunService:BindToRenderStep("TutorialHand", Enum.RenderPriority.Last.Value + 1, placeHand)
end

return TutorialHand
