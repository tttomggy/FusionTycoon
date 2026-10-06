--[[
	UIKit
	-----
	Constructors for the "Fusion Lab" look: chunky dark-violet panels, a thick
	ink outline on everything, and top-lit gradient buttons sitting on a solid
	ink shadow. Every screen in the game is built from these; all colours come
	from UITheme.

	Shadows: a sibling Frame named "Shadow", same size and corner radius,
	filled Ink, offset down. Because a sibling would become its own cell in a
	UIListLayout/UIGridLayout, Panel/Button wrap their body in a transparent
	holder (returned as the second value) - position and parent the holder,
	style the body.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)

local UIKit = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MUTATION_RING_GAP = 2 -- px of Ink between the orb and its mutation ring
local MUTATION_RING_WIDTH = 3

local PRESS_DOWN_INFO = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_UP_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_IN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PRESS_DEPTH = 4
local SELECT_BOUNCE_INFO = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SELECT_BOUNCE_FROM = 0.94

--[[ Small helpers ------------------------------------------------------------ ]]

function UIKit.Corner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

-- Border stroke (panels, rows, buttons).
function UIKit.Stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Colors.Ink
	stroke.Thickness = thickness or UITheme.Stroke.Default
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

-- The "drop" look on big text: an ink contextual stroke on the glyphs.
function UIKit.TextStroke(label: Instance, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Colors.Ink
	stroke.Thickness = thickness or UITheme.Stroke.Text
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return stroke
end

function UIKit.Padding(parent: Instance, top: number, right: number?, bottom: number?, left: number?): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, top)
	padding.PaddingRight = UDim.new(0, right or top)
	padding.PaddingBottom = UDim.new(0, bottom or top)
	padding.PaddingLeft = UDim.new(0, left or right or top)
	padding.Parent = parent
	return padding
end

-- Vertical UIGradient. `stops` is a list of {time, Color3}; a GradientPair is
-- the common two-stop case.
function UIKit.Gradient(parent: Instance, stops: { { any } }, rotation: number?): UIGradient
	local keypoints = {}
	for _, stop in stops do
		table.insert(keypoints, ColorSequenceKeypoint.new(stop[1], stop[2]))
	end
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(keypoints)
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
	return gradient
end

function UIKit.PairGradient(parent: Instance, pair: UITheme.GradientPair, rotation: number?): UIGradient
	return UIKit.Gradient(parent, { { 0, pair.Top }, { 1, pair.Bottom } }, rotation)
end

function UIKit.SetPairGradient(gradient: UIGradient, pair: UITheme.GradientPair)
	gradient.Color = ColorSequence.new(pair.Top, pair.Bottom)
end

export type LabelProps = {
	Text: string?,
	Font: Font?,
	TextSize: number?,
	TextColor3: Color3?,
	Stroke: number?, -- adds the ink drop stroke at this thickness
	[string]: any,
}

-- TextLabel with sensible defaults; any extra key is assigned as a property.
function UIKit.Label(props: LabelProps): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = props.Font or Fonts.Body
	label.TextSize = props.TextSize or 16
	label.TextColor3 = props.TextColor3 or Colors.Text
	label.Text = props.Text or ""
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		if key ~= "Font" and key ~= "Stroke" and key ~= "Text" and key ~= "TextSize" and key ~= "TextColor3" then
			(label :: any)[key] = value
		end
	end
	if props.Stroke then
		UIKit.TextStroke(label, props.Stroke)
	end
	return label
end

-- Text that must never be cut off (a longer translation, a narrow card):
-- wraps and scales down from `maxSize` to at least `minSize` to fit its box.
function UIKit.FitText(label: TextLabel, maxSize: number, minSize: number)
	label.TextWrapped = true
	label.TextScaled = true
	label.TextTruncate = Enum.TextTruncate.None
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxSize
	constraint.MinTextSize = minSize
	constraint.Parent = label
end

--[[ Shadow ------------------------------------------------------------------ ]]

-- Product of every UIScale between `gui` and its ScreenGui, so an
-- AutomaticSize target's AbsoluteSize can be converted back to offsets.
local function effectiveScale(gui: Instance): number
	local scale = 1
	local current: Instance? = gui
	while current and not current:IsA("LayerCollector") do
		local uiScale = current:FindFirstChildOfClass("UIScale")
		if uiScale then
			scale *= uiScale.Scale
		end
		current = current.Parent
	end
	if current then
		local uiScale = current:FindFirstChildOfClass("UIScale")
		if uiScale then
			scale *= uiScale.Scale
		end
	end
	return if scale > 0 then scale else 1
end

-- The same, for callers converting AbsolutePosition / AbsoluteSize deltas
-- back to offsets (scroll targets).
function UIKit.EffectiveScale(gui: Instance): number
	return effectiveScale(gui)
end

-- Builds the ink drop shadow as a sibling of `target` and keeps it in sync
-- with the target's size/position/visibility. While a Button is pressed it
-- sets the "Pressing" attribute so the shadow stays put as the body sinks.
function UIKit.Shadow(target: GuiObject, offset: number?): Frame
	local shadowOffset = offset or UITheme.ShadowOffset
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = Colors.Ink
	shadow.BorderSizePixel = 0
	shadow.ZIndex = target.ZIndex - 1
	shadow.Active = false

	local corner = target:FindFirstChildOfClass("UICorner")
	if corner then
		local shadowCorner = Instance.new("UICorner")
		shadowCorner.CornerRadius = corner.CornerRadius
		shadowCorner.Parent = shadow
	end

	local function sync()
		shadow.AnchorPoint = target.AnchorPoint
		shadow.Visible = target.Visible
		if not target:GetAttribute("Pressing") then
			shadow.Position = target.Position + UDim2.fromOffset(0, shadowOffset)
		end
		if target.AutomaticSize == Enum.AutomaticSize.None then
			shadow.Size = target.Size
		else
			local scale = effectiveScale(target)
			shadow.Size = UDim2.fromOffset(target.AbsoluteSize.X / scale, target.AbsoluteSize.Y / scale)
		end
	end

	for _, property in { "Position", "Size", "AnchorPoint", "Visible", "AbsoluteSize" } do
		target:GetPropertyChangedSignal(property):Connect(sync)
	end
	sync()
	shadow.Parent = target.Parent
	return shadow
end

--[[ Panel ------------------------------------------------------------------- ]]

export type PanelProps = {
	Name: string?,
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	AutomaticSize: Enum.AutomaticSize?,
	Color: Color3?, -- body fill (ignored when Gradient is given)
	Gradient: { { any } }?, -- vertical gradient stops on the body
	Radius: number?,
	StrokeThickness: number?,
	StrokeColor: Color3?,
	ShadowOffset: number?,
	NoShadow: boolean?,
	ZIndex: number?,
	Transparency: number?,
}

-- Returns (body, holder). The holder is transparent and takes the layout
-- props; the body fills it and carries the fill, corner and stroke.
function UIKit.Panel(props: PanelProps): (Frame, Frame)
	local holder = Instance.new("Frame")
	holder.Name = props.Name or "Panel"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = props.Size or UDim2.fromOffset(200, 100)
	holder.Position = props.Position or UDim2.new()
	holder.AnchorPoint = props.AnchorPoint or Vector2.zero
	holder.LayoutOrder = props.LayoutOrder or 0
	holder.ZIndex = props.ZIndex or 1

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BorderSizePixel = 0
	body.ZIndex = holder.ZIndex + 1
	body.BackgroundTransparency = props.Transparency or 0
	if props.AutomaticSize and props.AutomaticSize ~= Enum.AutomaticSize.None then
		holder.AutomaticSize = props.AutomaticSize
		body.AutomaticSize = props.AutomaticSize
		local holderSize = holder.Size
		body.Size = UDim2.new(
			if props.AutomaticSize == Enum.AutomaticSize.X then 0 else 1,
			0,
			if props.AutomaticSize == Enum.AutomaticSize.X then 1 else 0,
			0
		)
		-- The holder auto-sizes around the body only.
		holder.Size = UDim2.new(holderSize.X.Scale, holderSize.X.Offset, 0, 0)
	else
		body.Size = UDim2.fromScale(1, 1)
	end
	body.Parent = holder

	if props.Gradient then
		body.BackgroundColor3 = Colors.White
		UIKit.Gradient(body, props.Gradient)
	else
		body.BackgroundColor3 = props.Color or Colors.Panel
	end
	UIKit.Corner(body, props.Radius or UITheme.Radius.Panel)
	UIKit.Stroke(body, props.StrokeThickness, props.StrokeColor)
	if not props.NoShadow then
		UIKit.Shadow(body, props.ShadowOffset)
	end

	holder.Parent = props.Parent
	return body, holder
end

--[[ Button ------------------------------------------------------------------ ]]

export type ButtonProps = {
	Name: string?,
	Parent: Instance?,
	Style: string?, -- UITheme.Gradients key
	Text: string?,
	SubText: string?, -- optional second line (e.g. "UPGRADE" under a cost)
	Icon: string?, -- image asset id; "" or nil renders the label only
	IconStacked: boolean?, -- phone layout: icon above the label
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	TextSize: number?,
	SubTextSize: number?,
	TextColor3: Color3?,
	Radius: number?,
	ShadowOffset: number?,
	OnClick: (() -> ())?,
	ZIndex: number?,
}

-- Returns (button, holder). The button is a TextButton with Text = "" and
-- its own Label/SubLabel/Icon children; use UIKit.SetButton to restyle.
function UIKit.Button(props: ButtonProps): (TextButton, Frame)
	local holder = Instance.new("Frame")
	holder.Name = props.Name or "Button"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = props.Size or UDim2.fromOffset(160, 56)
	holder.Position = props.Position or UDim2.new()
	holder.AnchorPoint = props.AnchorPoint or Vector2.zero
	holder.LayoutOrder = props.LayoutOrder or 0
	holder.ZIndex = props.ZIndex or 1

	local button = Instance.new("TextButton")
	button.Name = "Body"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundColor3 = Colors.White
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = holder.ZIndex + 1
	button.Parent = holder
	UIKit.Corner(button, props.Radius or UITheme.Radius.Button)
	UIKit.Stroke(button)
	local pair = UITheme.Gradients[props.Style or "Green"] or UITheme.Gradients.Green
	local gradient = UIKit.PairGradient(button, pair)
	gradient.Name = "Fill"
	-- The contrast rule: a warm fill always gets white text (UITheme.TextOn).
	local warm = UITheme.IsWarmPair(pair)
	button:SetAttribute("Warm", warm)
	local textColor = if warm then UITheme.WarmText else (props.TextColor3 or Colors.Text)
	if props.TextColor3 then
		button:SetAttribute("TextColor", props.TextColor3)
	end

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = button.ZIndex + 1
	content.Parent = button
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = if props.IconStacked then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, if props.IconStacked then 2 else 8)
	layout.Parent = content

	local textSize = props.TextSize or 20
	local hasIcon = props.Icon ~= nil and props.Icon ~= ""
	if hasIcon then
		local iconSize = if props.IconStacked then 26 else math.floor(textSize * 1.4)
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(iconSize, iconSize)
		icon.Image = props.Icon :: string
		icon.LayoutOrder = 1
		icon.ZIndex = content.ZIndex
		icon.Parent = content
	end

	local textColumn = Instance.new("Frame")
	textColumn.Name = "TextColumn"
	textColumn.BackgroundTransparency = 1
	textColumn.AutomaticSize = Enum.AutomaticSize.XY
	textColumn.Size = UDim2.new()
	textColumn.LayoutOrder = 2
	textColumn.ZIndex = content.ZIndex
	textColumn.Parent = content
	local columnLayout = Instance.new("UIListLayout")
	columnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnLayout.Padding = UDim.new(0, -2)
	columnLayout.Parent = textColumn

	UIKit.Label({
		Name = "Label",
		Text = props.Text or "",
		Font = Fonts.Display,
		TextSize = textSize,
		TextColor3 = textColor,
		AutomaticSize = Enum.AutomaticSize.XY,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		ZIndex = content.ZIndex,
		Stroke = UITheme.Stroke.Text,
		Parent = textColumn,
	})
	-- No heavy drop stroke on the tiny sub-label; it would swallow the
	-- glyphs. A 1 px one on warm fills keeps white legible on gold.
	local subLabel = UIKit.Label({
		Name = "SubLabel",
		Text = props.SubText or "",
		Font = Fonts.BodyHeavy,
		TextSize = props.SubTextSize or 11,
		TextColor3 = textColor,
		AutomaticSize = Enum.AutomaticSize.XY,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		ZIndex = content.ZIndex,
		Visible = props.SubText ~= nil and props.SubText ~= "",
		Parent = textColumn,
	})
	local subStroke = UIKit.TextStroke(subLabel, 1)
	subStroke.Name = "WarmStroke"
	subStroke.Enabled = warm

	UIKit.Shadow(button, props.ShadowOffset)
	UIKit.AttachPress(button)

	if props.OnClick then
		local onClick = props.OnClick
		button.Activated:Connect(function()
			onClick()
		end)
	end

	holder.Parent = props.Parent
	return button, holder
end

export type ButtonState = {
	Style: string?,
	Text: string?,
	SubText: string?,
	TextColor3: Color3?,
}

-- Restyles a UIKit.Button in place (state changes: affordable, locked, ...).
-- The text colour follows the contrast rule: white on a warm Style, else
-- state.TextColor3 (or the one the button was built with).
function UIKit.SetButton(button: TextButton, state: ButtonState)
	if state.Style then
		local gradient = button:FindFirstChild("Fill") :: UIGradient?
		local pair = UITheme.Gradients[state.Style]
		if gradient and pair then
			UIKit.SetPairGradient(gradient, pair)
			button:SetAttribute("Warm", UITheme.IsWarmPair(pair))
		end
	end
	if state.TextColor3 then
		button:SetAttribute("TextColor", state.TextColor3)
	end
	local column = button:FindFirstChild("Content") and (button :: any).Content:FindFirstChild("TextColumn")
	if not column then
		return
	end
	local label = column:FindFirstChild("Label") :: TextLabel?
	local subLabel = column:FindFirstChild("SubLabel") :: TextLabel?
	if label and state.Text then
		label.Text = state.Text
	end
	if subLabel and state.SubText ~= nil then
		subLabel.Text = state.SubText
		subLabel.Visible = state.SubText ~= ""
	end
	local warm = button:GetAttribute("Warm") == true
	local chosen = button:GetAttribute("TextColor")
	local color = if warm then UITheme.WarmText elseif typeof(chosen) == "Color3" then chosen else Colors.Text
	if label then
		label.TextColor3 = color
	end
	if subLabel then
		subLabel.TextColor3 = color
		local stroke = subLabel:FindFirstChild("WarmStroke") :: UIStroke?
		if stroke then
			stroke.Enabled = warm
		end
	end
end

-- The press feel: sink 4 px onto the shadow on press, spring back on release.
-- The body lives at Position (0,0,0,0) inside its holder, so "rest" is known.
function UIKit.AttachPress(button: GuiButton)
	local rest = button.Position
	local down = rest + UDim2.fromOffset(0, PRESS_DEPTH)
	local pressed = false

	local function release()
		if not pressed then
			return
		end
		pressed = false
		local tween = TweenService:Create(button, PRESS_UP_INFO, { Position = rest })
		tween:Play()
		tween.Completed:Once(function()
			if not pressed then
				button:SetAttribute("Pressing", nil)
			end
		end)
	end

	button.MouseButton1Down:Connect(function()
		pressed = true
		button:SetAttribute("Pressing", true)
		TweenService:Create(button, PRESS_DOWN_INFO, { Position = down }):Play()
	end)
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.SelectionLost:Connect(release)
end

--[[ Selected state -------------------------------------------------------------
	Every tab, chip and segment row: the SELECTED item is the UPGRADES green
	with white text; the rest stay the muted panel colour. A tap bounces the
	item (UIScale 0.94 -> 1) and plays the Toast slot.
]]
UIKit.SELECTED_STYLE = "Green"
UIKit.UNSELECTED_STYLE = "Disabled"

-- A UIKit.Button as a tab / chip: green + white when selected, else the
-- muted Disabled fill with `unselectedText` (default Muted).
function UIKit.SetSelected(button: TextButton, selected: boolean, unselectedText: Color3?)
	UIKit.SetButton(button, {
		Style = if selected then UIKit.SELECTED_STYLE else UIKit.UNSELECTED_STYLE,
		TextColor3 = if selected then Colors.Text else (unselectedText or Colors.Muted),
	})
end

-- The same for a plain Frame / TextButton (custom tabs, segments): a green
-- gradient named "SelectFill" when selected, else `unselected` (default
-- Panel3). Text on it is the caller's (white when selected).
function UIKit.SetSelectedFill(gui: GuiObject, selected: boolean, unselected: Color3?)
	local gradient = gui:FindFirstChild("SelectFill") :: UIGradient?
	if not gradient then
		local created = UIKit.PairGradient(gui, UITheme.Gradients[UIKit.SELECTED_STYLE])
		created.Name = "SelectFill"
		gradient = created
	end
	(gradient :: UIGradient).Enabled = selected
	gui.BackgroundColor3 = if selected then Colors.White else (unselected or Colors.Panel3)
end

-- The tap feedback for a tab / chip / segment: a quick press-bounce and
-- the Toast sound. Uses its own UIScale ("SelectScale"); an object that
-- already has another UIScale (a PopScale) only gets the sound.
function UIKit.SelectFeedback(gui: GuiObject)
	local scale = gui:FindFirstChild("SelectScale") :: UIScale?
	if not scale and not gui:FindFirstChildOfClass("UIScale") then
		local created = Instance.new("UIScale")
		created.Name = "SelectScale"
		created.Parent = gui
		scale = created
	end
	if scale then
		scale.Scale = SELECT_BOUNCE_FROM
		TweenService:Create(scale, SELECT_BOUNCE_INFO, { Scale = 1 }):Play()
	end
	SoundKit.Play("Toast", nil)
end

--[[ Pill / Badge ------------------------------------------------------------- ]]

export type PillProps = {
	Name: string?,
	Parent: Instance?,
	Text: string?,
	Color: Color3?, -- fill
	Gradient: UITheme.GradientPair?,
	TextColor3: Color3?,
	Font: Font?,
	TextSize: number?,
	StrokeThickness: number?,
	Height: number?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	ZIndex: number?,
	TextStroke: number?,
}

-- Auto-width rounded capsule. ALWAYS two instances: a fill Frame (takes
-- the layout props, carries the colour or gradient, corner and stroke) and
-- the clear TextLabel inside it, which is what this returns (set .Text on
-- it). So `pill.Parent` is always the pill's own fill, never the caller's
-- container: show / hide / move / hit-area a pill through
-- UIKit.PillRoot(pill) (or UIKit.SetPillVisible).
function UIKit.Pill(props: PillProps): TextLabel
	local fill = Instance.new("Frame")
	fill.Name = props.Name or "Pill"
	fill.BorderSizePixel = 0
	fill.AutomaticSize = Enum.AutomaticSize.X
	fill.Size = UDim2.fromOffset(0, props.Height or 24)
	fill.Position = props.Position or UDim2.new()
	fill.AnchorPoint = props.AnchorPoint or Vector2.zero
	fill.LayoutOrder = props.LayoutOrder or 0
	fill.ZIndex = props.ZIndex or 1
	UIKit.Corner(fill, 999)
	UIKit.Stroke(fill, props.StrokeThickness or 2)
	if props.Gradient then
		-- On the Frame: a UIGradient on the label would tint its text too.
		fill.BackgroundColor3 = Colors.White
		UIKit.PairGradient(fill, props.Gradient)
	else
		fill.BackgroundColor3 = props.Color or Colors.Panel2
	end
	-- The contrast rule: white text with the ink stroke on a warm fill.
	local warm = if props.Gradient then UITheme.IsWarmPair(props.Gradient) else UITheme.IsWarm(fill.BackgroundColor3)

	local pill = UIKit.Label({
		Name = "Text",
		Text = props.Text or "",
		Font = props.Font or Fonts.BodyHeavy,
		TextSize = props.TextSize or 13,
		TextColor3 = if warm then UITheme.WarmText else (props.TextColor3 or Colors.Text),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		ZIndex = fill.ZIndex + 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = if warm then math.max(props.TextStroke or 0, UITheme.WarmTextStroke) else props.TextStroke,
	})
	UIKit.Padding(pill, 0, 10, 0, 10)
	pill.Parent = fill
	fill.Parent = props.Parent
	return pill
end

-- The pill's fill Frame (what to show, hide, move or parent a hit area to).
function UIKit.PillRoot(pill: TextLabel): Frame
	return pill.Parent :: Frame
end

-- Shows / hides a pill from UIKit.Pill (its fill, label and all).
function UIKit.SetPillVisible(pill: TextLabel, visible: boolean)
	UIKit.PillRoot(pill).Visible = visible
end

--[[ Mutation marks ------------------------------------------------------------
	They must read on every tier: a gold mark on a gold Legendary card used to
	vanish. So marks sit on Ink (a pill with an outline, an Ink gap round the
	orb) and say the word. Rainbow marks use the rainbow gradient, slowly
	rotated on the client.
]]
local RAINBOW_SPIN_DEG_PER_SEC = 45
-- Weak keys: destroyed cards drop out by themselves.
local spinningGradients: { [UIGradient]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local spinConnection: RBXScriptConnection? = nil

local function spinRainbow(gradient: UIGradient)
	spinningGradients[gradient] = true
	if not spinConnection then
		spinConnection = RunService.RenderStepped:Connect(function(dt: number)
			for g in spinningGradients do
				if g.Parent then
					g.Rotation = (g.Rotation + RAINBOW_SPIN_DEG_PER_SEC * dt) % 360
				end
			end
		end)
	end
end

local function rainbowGradient(parent: Instance, spin: boolean): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Name = "RainbowGradient"
	gradient.Color = UITheme.GetRainbowSequence()
	gradient.Parent = parent
	if spin then
		spinRainbow(gradient)
	end
	return gradient
end

-- The mutation tag: an Ink pill with a 2 px outline and the word in the
-- mutation colour - "GOLDEN ×2", "DIAMOND ×5", "RAINBOW ×12". Rainbow is
-- white text under the rainbow gradient with a gradient outline. Returns
-- nil for a normal item.
function UIKit.MutationPill(props: {
	Parent: Instance?,
	Mutation: string?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
	TextSize: number?,
	Height: number?,
	Label: string?, -- default "GOLDEN ×2"
}): GuiObject?
	local mutation = props.Mutation
	local color = UITheme.GetMutationColor(mutation)
	if not mutation or not color then
		return nil
	end
	local rainbow = mutation == "Rainbow"
	local pill = UIKit.Pill({
		Name = "Mutation",
		Parent = props.Parent,
		Text = props.Label or ("%s ×%d"):format(mutation:upper(), MutationConfig.GetMultiplier(mutation)),
		Color = Colors.Ink,
		TextColor3 = if rainbow then Colors.White else color,
		Font = Fonts.Display,
		TextSize = props.TextSize or 12,
		Height = props.Height or 20,
		StrokeThickness = 2,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = props.ZIndex,
	})
	-- The outline is on the pill's fill Frame (UIKit.Pill).
	local root = UIKit.PillRoot(pill)
	local outline = root:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Color = if rainbow then Colors.White else color
		if rainbow then
			rainbowGradient(outline, true)
		end
	end
	if rainbow then
		-- Intended tinting: white text under the rainbow.
		rainbowGradient(pill, false)
	end
	-- The fill Frame, so callers can lay it out (LayoutOrder, Visible).
	return root
end

-- A 3 px outline in the mutation colour round a card body (its existing
-- UIStroke). Rainbow gets a slowly rotating gradient. No-op for normal.
function UIKit.MutationCardStroke(body: GuiObject, mutation: string?)
	local color = UITheme.GetMutationColor(mutation)
	if not mutation or not color then
		return
	end
	local stroke = body:FindFirstChildOfClass("UIStroke") or UIKit.Stroke(body, 3)
	stroke.Thickness = 3
	stroke.Color = if mutation == "Rainbow" then Colors.White else color
	if mutation == "Rainbow" then
		rainbowGradient(stroke, true)
	end
end

-- Red count badge pinned to the top-right corner of `parent`. Idempotent:
-- call again with a new count to update; a count of 0 hides it.
function UIKit.Badge(parent: GuiObject, count: number): TextLabel
	local badge = parent:FindFirstChild("Badge") :: TextLabel?
	if not badge then
		local newBadge = UIKit.Label({
			Name = "Badge",
			Font = Fonts.Display,
			TextSize = 15,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.fromOffset(26, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0,
			BackgroundColor3 = Colors.Danger,
			ZIndex = parent.ZIndex + 5,
		})
		UIKit.Corner(newBadge, 999)
		UIKit.Stroke(newBadge, 2)
		UIKit.Padding(newBadge, 0, 6, 0, 6)
		newBadge.Parent = parent
		badge = newBadge
	end
	local resolved = badge :: TextLabel
	resolved.Text = tostring(count)
	resolved.Visible = count > 0
	return resolved
end

--[[ Tier orb ------------------------------------------------------------------ ]]

-- A circle with a light-centre -> tier -> dark-edge gradient and the ink
-- outline. Epic and above also get a soft glow circle behind it. Returns the
-- holder (size x size); position/parent that.
-- `mutation` adds a ring: a 2 px Ink gap, then a 3 px ring in the mutation
-- colour (Rainbow: the rotating gradient). The Ink gap is what keeps
-- gold-on-gold readable.
function UIKit.TierOrb(tier: string, size: number, transparency: number?, mutation: string?): Frame
	local alpha = transparency or 0
	local holder = Instance.new("Frame")
	holder.Name = "TierOrb"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)

	local ringColor = UITheme.GetMutationColor(mutation)
	if mutation and ringColor then
		-- Ink disc just larger than the orb (and its 3 px Ink stroke): the gap.
		local gapPx = UITheme.Stroke.Default + MUTATION_RING_GAP
		local gap = Instance.new("Frame")
		gap.Name = "MutationGap"
		gap.AnchorPoint = Vector2.new(0.5, 0.5)
		gap.Position = UDim2.fromScale(0.5, 0.5)
		gap.Size = UDim2.new(1, gapPx * 2, 1, gapPx * 2)
		gap.BackgroundColor3 = Colors.Ink
		gap.BackgroundTransparency = alpha
		gap.BorderSizePixel = 0
		gap.ZIndex = 2
		gap.Parent = holder
		UIKit.Corner(gap, 999)
		local ring = UIKit.Stroke(gap, MUTATION_RING_WIDTH, if mutation == "Rainbow" then Colors.White else ringColor)
		ring.Name = "MutationRing"
		ring.Transparency = alpha
		if mutation == "Rainbow" then
			rainbowGradient(ring, true)
		end
	end

	if UITheme.GlowTiers[tier] then
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.fromScale(1.35, 1.35)
		glow.BackgroundColor3 = UITheme.GetTierOrb(tier).Mid
		glow.BackgroundTransparency = 0.6 + (1 - 0.6) * alpha
		glow.BorderSizePixel = 0
		glow.Parent = holder
		UIKit.Corner(glow, 999)
	end

	local orb = Instance.new("Frame")
	orb.Name = "Orb"
	orb.Size = UDim2.fromScale(1, 1)
	orb.BackgroundColor3 = Colors.White
	orb.BackgroundTransparency = alpha
	orb.BorderSizePixel = 0
	orb.ZIndex = 3
	orb.Parent = holder
	UIKit.Corner(orb, 999)
	local stops = UITheme.GetTierOrb(tier)
	UIKit.Gradient(orb, { { 0, stops.Light }, { 0.5, stops.Mid }, { 1, stops.Dark } }, 135)
	local stroke = UIKit.Stroke(orb, 3)
	stroke.Transparency = alpha

	-- Keep children at the holder's ZIndex band when re-parented: glow at
	-- the bottom, then the mutation gap/ring, then the orb.
	local function layer(child: Instance): number
		if child.Name == "Orb" then
			return 2
		elseif child.Name == "MutationGap" then
			return 1
		end
		return 0
	end
	holder:GetPropertyChangedSignal("ZIndex"):Connect(function()
		for _, child in holder:GetChildren() do
			if child:IsA("GuiObject") then
				child.ZIndex = holder.ZIndex + layer(child)
			end
		end
	end)
	return holder
end

-- The same gradient on a rounded square (Upgrades row icons).
function UIKit.TierSquare(tier: string, size: number): Frame
	local square = Instance.new("Frame")
	square.Name = "TierSquare"
	square.Size = UDim2.fromOffset(size, size)
	square.BackgroundColor3 = Colors.White
	square.BorderSizePixel = 0
	UIKit.Corner(square, 14)
	local stops = UITheme.GetTierOrb(tier)
	UIKit.Gradient(square, { { 0, stops.Light }, { 0.5, stops.Mid }, { 1, stops.Dark } }, 135)
	UIKit.Stroke(square, 3)
	return square
end

--[[ Progress bar ---------------------------------------------------------------- ]]

export type ProgressBarProps = {
	Name: string?,
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Fill: UITheme.GradientPair?,
	FillColor: Color3?,
	Value: number?, -- 0..1
	ZIndex: number?,
}

-- Ink track with 2 px padding and a rounded fill. Use UIKit.SetProgress.
function UIKit.ProgressBar(props: ProgressBarProps): Frame
	local track = Instance.new("Frame")
	track.Name = props.Name or "ProgressBar"
	track.BackgroundColor3 = Colors.Ink
	track.BorderSizePixel = 0
	track.Size = props.Size or UDim2.new(1, 0, 0, 14)
	track.Position = props.Position or UDim2.new()
	track.AnchorPoint = props.AnchorPoint or Vector2.zero
	track.LayoutOrder = props.LayoutOrder or 0
	track.ZIndex = props.ZIndex or 1
	UIKit.Corner(track, 999)
	UIKit.Padding(track, 2)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = track.ZIndex + 1
	fill.Parent = track
	UIKit.Corner(fill, 999)
	if props.Fill then
		fill.BackgroundColor3 = Colors.White
		UIKit.PairGradient(fill, props.Fill)
	else
		fill.BackgroundColor3 = props.FillColor or Colors.Goal
	end

	UIKit.SetProgress(track, props.Value or 0)
	track.Parent = props.Parent
	return track
end

function UIKit.SetProgress(bar: Frame, value: number, animate: boolean?)
	local fill = bar:FindFirstChild("Fill") :: Frame?
	if not fill then
		return
	end
	local alpha = math.clamp(if value ~= value then 0 else value, 0, 1)
	fill.Visible = alpha > 0
	local target = UDim2.fromScale(alpha, 1)
	if animate then
		TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = target }):Play()
	else
		fill.Size = target
	end
end

--[[ Popups ---------------------------------------------------------------------- ]]

local function getPopScale(gui: GuiObject): UIScale
	local scale = gui:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		local newScale = Instance.new("UIScale")
		newScale.Name = "PopScale"
		newScale.Parent = gui
		scale = newScale
	end
	return scale :: UIScale
end

-- A card's resting scale: 1, or less once UIKit.FitHeight shrank it.
local function restScale(gui: GuiObject): number
	local fit = gui:GetAttribute("FitScale")
	return if typeof(fit) == "number" then fit else 1
end

-- Opens from 0.85 to its rest scale with a Back ease. A CanvasGroup also
-- fades in.
function UIKit.PopIn(gui: GuiObject)
	local scale = getPopScale(gui)
	local rest = restScale(gui)
	scale.Scale = 0.85 * rest
	gui.Visible = true
	if gui:IsA("CanvasGroup") then
		gui.GroupTransparency = 0
	end
	TweenService:Create(scale, POP_IN_INFO, { Scale = rest }):Play()
end

-- Shrinks to 0.9 and fades (CanvasGroup) over 0.12 s, then hides. Returns
-- the tween so callers can wait on it.
function UIKit.PopOut(gui: GuiObject): Tween
	local scale = getPopScale(gui)
	local tween = TweenService:Create(scale, POP_OUT_INFO, { Scale = 0.9 * restScale(gui) })
	if gui:IsA("CanvasGroup") then
		TweenService:Create(gui, POP_OUT_INFO, { GroupTransparency = 1 }):Play()
	end
	tween:Play()
	tween.Completed:Once(function(playbackState)
		if playbackState == Enum.PlaybackState.Completed then
			gui.Visible = false
		end
	end)
	return tween
end

--[[ Screens & phone layout --------------------------------------------------------- ]]

local function viewportHeight(): number
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize.Y else 720
end

-- /selftest: pretend to be (or not be) a phone; nil = the real viewport.
local forcedPhone: boolean? = nil

function UIKit.IsPhone(): boolean
	if forcedPhone ~= nil then
		return forcedPhone
	end
	return viewportHeight() < UITheme.PhoneHeightThreshold
end

--[[ Card placement -------------------------------------------------------------------
	Every UIKit.Modal and centred card lives in the BAND between the Roblox
	top bar (GetCardTop) and the HUD's bottom button row (GetCardBottom),
	horizontally centred. What you see (the panel and its shadow) is
	centred vertically in that band (GetCardY); a card as tall as the band
	starts at GetCardTop and is shrunk as a whole to fit. On a phone the top
	also clears the Roblox top-left buttons (60 px after the 0.8 scale). The
	desktop chat window only matters when the card's left edge overlaps its
	~400 px span: then the card slides right if there's room, else the
	overlap stays (chat is collapsible). Cards are never pushed down for
	chat.

	The *For functions take the viewport and phone flag explicitly, so
	/selftest can check the real placement at any screen size.
]]
UIKit.TOP_BAR_HEIGHT = 58 -- the Roblox top bar (IgnoreGuiInset guis)
UIKit.CARD_TOP_GAP = 8
UIKit.CHAT_WIDTH = 400 -- screen px from the left the desktop chat window spans
UIKit.CARD_CHAT_GAP = 8
-- The HUD's bottom button row (HudController: 22 margin + button + 5 shadow)
-- plus an 8 px gap: cards stop above it.
UIKit.BOTTOM_BAR_RESERVE = { Desktop = 22 + 64 + 5 + 8, Phone = 22 + 60 + 5 + 8 }
local TOP_LEFT_CLEAR_PX = 60 -- the 170 x 60 Roblox buttons, in screen px

local function currentScale(): number
	return if UIKit.IsPhone() then UITheme.PhoneScale else 1
end

local function viewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1280, 720)
end

-- The viewport in logical px (after the phone UIScale).
function UIKit.GetLogicalViewport(): Vector2
	return viewportSize() / currentScale()
end

-- Logical y where the band (and a card that fills it) starts.
function UIKit.GetCardTopFor(phone: boolean): number
	local scale = if phone then UITheme.PhoneScale else 1
	return math.max(UIKit.TOP_BAR_HEIGHT + UIKit.CARD_TOP_GAP, math.ceil(TOP_LEFT_CLEAR_PX / scale) + 4)
end

function UIKit.GetCardTop(): number
	return UIKit.GetCardTopFor(UIKit.IsPhone())
end

-- Logical px a card leaves free at the bottom (the HUD button row).
function UIKit.GetCardBottomFor(phone: boolean): number
	return if phone then UIKit.BOTTOM_BAR_RESERVE.Phone else UIKit.BOTTOM_BAR_RESERVE.Desktop
end

function UIKit.GetCardBottom(): number
	return UIKit.GetCardBottomFor(UIKit.IsPhone())
end

-- Logical y for the top of a card `visualHeight` px tall (what you see,
-- after its fit scale) on a viewport `viewY` logical px tall: centred in
-- the band, so a short card on a full-screen desktop sits mid-screen; a
-- card that fills the band starts at its top.
function UIKit.GetCardYFor(visualHeight: number, viewY: number, phone: boolean): number
	local top = UIKit.GetCardTopFor(phone)
	local band = viewY - top - UIKit.GetCardBottomFor(phone)
	return top + math.max(0, (band - visualHeight) / 2)
end

function UIKit.GetCardY(visualHeight: number): number
	return UIKit.GetCardYFor(visualHeight, UIKit.GetLogicalViewport().Y, UIKit.IsPhone())
end

-- /selftest's rule for a placed card (logical px): nil = it passes, else
-- why not. Fits the band: its centre within 2 px of the band's centre and
-- inside the band. Taller: starts at the band's top.
function UIKit.CheckCardPlacement(top: number, height: number, viewY: number, phone: boolean): string?
	local bandTop = UIKit.GetCardTopFor(phone)
	local bandBottom = viewY - UIKit.GetCardBottomFor(phone)
	if height > bandBottom - bandTop + 0.5 then
		if math.abs(top - bandTop) > 1 then
			return ("taller than the band but starts at %d, not %d"):format(math.floor(top), bandTop)
		end
		return nil
	end
	local centre = top + height / 2
	local bandCentre = (bandTop + bandBottom) / 2
	if math.abs(centre - bandCentre) > 2 then
		return ("centre %d vs band centre %d"):format(math.floor(centre), math.floor(bandCentre))
	end
	if top < bandTop - 0.5 then
		return ("top %d above %d"):format(math.floor(top), bandTop)
	end
	if top + height > bandBottom + 0.5 then
		return ("bottom %d below %d"):format(math.floor(top + height), math.floor(bandBottom))
	end
	return nil
end

local function chatWindowOn(): boolean
	if UIKit.IsPhone() or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		return false
	end
	local ok, on = pcall(function()
		return TextChatService.ChatVersion == Enum.ChatVersion.TextChatService
			and TextChatService.ChatWindowConfiguration.Enabled
	end)
	return ok and on == true
end

-- Logical x offset that slides a centred card of `width` (logical px) clear
-- of the desktop chat window, when it overlaps it and there's room; else 0.
function UIKit.GetCardShift(width: number): number
	if not chatWindowOn() then
		return 0
	end
	local view = UIKit.GetLogicalViewport()
	local left = (view.X - width) / 2
	local chatRight = UIKit.CHAT_WIDTH / currentScale() + UIKit.CARD_CHAT_GAP
	if left >= chatRight or chatRight + width > view.X - UIKit.CARD_CHAT_GAP then
		return 0
	end
	return chatRight - left
end

-- A fixed-size card (offset layout). A card centred at (0.5, 0.5) is
-- centred in the card band (GetCardY, shadow included; slid clear of
-- chat), and shrunk as a whole (through its PopScale, so PopIn / PopOut
-- keep working) when it's taller than the band. Any other card just shrinks to leave `margin`
-- px above and below. Call before PopIn. Returns the scale used.
-- Where a centred card goes: its visible height `visual` (the holder plus
-- the shadow below it) on a viewport `viewY` tall -> (top, fit scale).
function UIKit.PlanCardFor(visual: number, viewY: number, phone: boolean): (number, number)
	local band = viewY - UIKit.GetCardTopFor(phone) - UIKit.GetCardBottomFor(phone)
	local fit = math.clamp(band / visual, 0.5, 1)
	return UIKit.GetCardYFor(visual * fit, viewY, phone), fit
end

-- How far a Panel holder's shadow hangs below it (0 for a plain frame).
local function shadowBelow(holder: GuiObject): number
	local shadow = holder:FindFirstChild("Shadow")
	return if shadow and shadow:IsA("GuiObject") then math.max(0, shadow.Position.Y.Offset) else 0
end

function UIKit.FitHeight(holder: GuiObject, height: number, margin: number?): number
	local view = UIKit.GetLogicalViewport()
	local position = holder.Position
	local centred = holder:GetAttribute("CardPlaced") == true
		or (holder.AnchorPoint.Y == 0.5 and position.Y.Scale == 0.5)
	local fit: number
	if centred then
		-- Centre what you see: the card and its shadow. The UIScale shrinks
		-- it about its anchor (top centre), so the top stays put.
		local top: number
		top, fit = UIKit.PlanCardFor(height + shadowBelow(holder), view.Y, UIKit.IsPhone())
		local width = holder.Size.X.Offset
		if width <= 0 then
			width = holder.AbsoluteSize.X / currentScale()
		end
		holder:SetAttribute("CardPlaced", true)
		holder.AnchorPoint = Vector2.new(holder.AnchorPoint.X, 0)
		holder.Position = UDim2.new(position.X.Scale, 0, 0, top) + UDim2.fromOffset(UIKit.GetCardShift(width * fit), 0)
	else
		fit = math.clamp((view.Y - 2 * (margin or 12)) / height, 0.5, 1)
	end
	holder:SetAttribute("FitScale", fit)
	getPopScale(holder).Scale = fit
	return fit
end

-- Re-placed on every viewport change (UIKit.Modal registers here).
local cardPlacers: { () -> () } = {}

local layoutChanged = Instance.new("BindableEvent")
-- Fires (isPhone) whenever the viewport crosses the phone threshold.
UIKit.LayoutChanged = layoutChanged.Event

local lastIsPhone: boolean? = nil
local scales: { UIScale } = {}

local function refreshLayout()
	local isPhone = UIKit.IsPhone()
	for _, scale in scales do
		scale.Scale = if isPhone then UITheme.PhoneScale else 1
	end
	for _, place in cardPlacers do
		task.spawn(place)
	end
	if isPhone ~= lastIsPhone then
		lastIsPhone = isPhone
		layoutChanged:Fire(isPhone)
	end
end

-- Studio /selftest only: build every panel at both scales.
function UIKit.SetForcedPhone(value: boolean?)
	forcedPhone = value
	refreshLayout()
end

local function watchCamera(camera: Camera?)
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshLayout)
	end
	refreshLayout()
end
watchCamera(Workspace.CurrentCamera)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	watchCamera(Workspace.CurrentCamera)
end)

-- A ScreenGui with the single mobile UIScale (0.8 under 500 px tall).
function UIKit.Screen(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local scale = Instance.new("UIScale")
	scale.Name = "MobileScale"
	scale.Scale = if UIKit.IsPhone() then UITheme.PhoneScale else 1
	scale.Parent = gui
	table.insert(scales, scale)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

-- Red 44x44 close (X) button.
function UIKit.CloseButton(props: { Parent: Instance?, Position: UDim2?, AnchorPoint: Vector2?, OnClick: () -> (), ZIndex: number? }): (TextButton, Frame)
	return UIKit.Button({
		Name = "Close",
		Parent = props.Parent,
		Style = "Red",
		Text = "X",
		Icon = UITheme.Icons.Close,
		TextSize = 22,
		Size = UDim2.fromOffset(UITheme.MinTapSize, UITheme.MinTapSize),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Radius = 12,
		ShadowOffset = UITheme.SmallShadowOffset,
		OnClick = props.OnClick,
		ZIndex = props.ZIndex,
	})
end

--[[ Opacity --------------------------------------------------------------------
	Fades a whole subtree (row opacity 0.92 / 0.7) without a CanvasGroup, which
	would nest inside the modal's own CanvasGroup. The authored transparency of
	each element is remembered on first use so the call is repeatable.
]]
local OPACITY_PROPS = {
	{ Class = "GuiObject", Prop = "BackgroundTransparency" },
	{ Class = "TextLabel", Prop = "TextTransparency" },
	{ Class = "TextButton", Prop = "TextTransparency" },
	{ Class = "ImageLabel", Prop = "ImageTransparency" },
	{ Class = "ImageButton", Prop = "ImageTransparency" },
	{ Class = "UIStroke", Prop = "Transparency" },
}

function UIKit.SetOpacity(root: Instance, opacity: number)
	local function apply(instance: Instance)
		for _, entry in OPACITY_PROPS do
			if instance:IsA(entry.Class) then
				local key = "Base" .. entry.Prop
				local base = instance:GetAttribute(key)
				if base == nil then
					base = (instance :: any)[entry.Prop]
					instance:SetAttribute(key, base)
				end
				(instance :: any)[entry.Prop] = 1 - (1 - base) * opacity
			end
		end
	end
	apply(root)
	for _, descendant in root:GetDescendants() do
		apply(descendant)
	end
end

--[[ Overlay registry --------------------------------------------------------------
	Which full-screen cards / modals are up right now, by name. Every
	UIKit.Modal registers itself; custom cards (ResultController's big result
	card, the Pull x10 grid) call SetOverlay. The shop's contextual offer
	reads it so it never lands on top of another card.
]]
local openOverlays: { [string]: boolean } = {}

function UIKit.SetOverlay(name: string, open: boolean)
	openOverlays[name] = open
end

-- Is any overlay other than `except` open?
-- Is the overlay called `name` open right now?
function UIKit.IsOverlayNamed(name: string): boolean
	return openOverlays[name] == true
end

function UIKit.IsOverlayOpen(except: string?): boolean
	for name, open in openOverlays do
		if open and name ~= except then
			return true
		end
	end
	return false
end

--[[ Modal ----------------------------------------------------------------------- ]]

export type ModalProps = {
	Name: string,
	Title: string,
	DisplayOrder: number,
	MaxSize: Vector2,
	HeaderTop: Color3, -- gradient top colour (fades to Panel at 22%)
	OnClose: (() -> ())?,
	-- Fixed layout (no scrolling): keep the design height and shrink the
	-- whole card to fit instead of squashing it.
	FitContent: boolean?,
}

export type Modal = {
	Gui: ScreenGui,
	Root: CanvasGroup,
	Body: Frame,
	Content: Frame, -- everything below the header row
	Header: Frame,
	Title: TextLabel,
	Subtitle: TextLabel,
	Open: () -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
}

-- Centered modal: dim backdrop, 92% wide on phone, capped at MaxSize by a
-- UISizeConstraint, header gradient, title and red close button. The panel
-- sits inside a CanvasGroup so PopOut can fade it; the group is a few px
-- larger than the panel so the 4 px stroke and the shadow aren't clipped.
-- Placed by the card rule above (centred in the band; FitContent modals
-- keep their design height and shrink as a whole instead).
local MODAL_MARGIN = 4
UIKit.MODAL_MARGIN = MODAL_MARGIN -- /selftest: the visible panel's inset in the root

-- Every modal's ScreenGui (/selftest: each must draw over the HUD).
local modalGuis: { ScreenGui } = {}

-- The root is the panel plus MODAL_MARGIN all round and the shadow below:
-- the visible panel + shadow sits symmetrically inside it, so centring the
-- root centres what you see.
local MODAL_CHROME = Vector2.new(MODAL_MARGIN * 2, MODAL_MARGIN * 2 + UITheme.ShadowOffset)

export type ModalPlan = {
	RootHeight: number, -- the root's Size.Y offset (before the size cap)
	Visual: number, -- what you see (logical px, after the cap and the fit)
	Top: number, -- the root's top (logical px)
	Fit: number,
}

-- Where a modal with `maxSize` goes on a `view` (logical px) viewport.
-- placeRoot uses it, and /selftest runs it at 1920x1080, 1366x768 and the
-- phone size.
function UIKit.PlanModalFor(maxSize: Vector2, fitContent: boolean, view: Vector2, phone: boolean): ModalPlan
	local top = UIKit.GetCardTopFor(phone)
	local available = math.max(120, view.Y - top - UIKit.GetCardBottomFor(phone))
	if fitContent then
		-- Its layout needs its design height: keep it, shrink to fit.
		local design = math.min(maxSize.Y + MODAL_CHROME.Y, view.Y * 0.9)
		local fit = math.clamp(available / design, 0.5, 1)
		return { RootHeight = design, Visual = design * fit, Top = UIKit.GetCardYFor(design * fit, view.Y, phone), Fit = fit }
	end
	-- The UISizeConstraint caps the root at MaxSize + chrome.
	local visual = math.min(available, maxSize.Y + MODAL_CHROME.Y)
	return { RootHeight = available, Visual = visual, Top = UIKit.GetCardYFor(visual, view.Y, phone), Fit = 1 }
end

export type ModalSpec = { Name: string, MaxSize: Vector2, FitContent: boolean }
local modalSpecs: { ModalSpec } = {}

-- Every modal built so far (/selftest's "cards centred" math check).
function UIKit.GetModalSpecs(): { ModalSpec }
	return table.clone(modalSpecs)
end

function UIKit.GetModalGuis(): { ScreenGui }
	return table.clone(modalGuis)
end

function UIKit.Modal(props: ModalProps): Modal
	local gui = UIKit.Screen(props.Name, props.DisplayOrder)
	table.insert(modalGuis, gui)
	gui.Enabled = false

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Colors.Black
	backdrop.BackgroundTransparency = 0.45
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Parent = gui

	local root = Instance.new("CanvasGroup")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.BackgroundTransparency = 1
	root.ZIndex = 2
	root.Parent = gui
	table.insert(modalSpecs, { Name = props.Name, MaxSize = props.MaxSize, FitContent = props.FitContent == true })
	local function placeRoot()
		local view = UIKit.GetLogicalViewport()
		local plan = UIKit.PlanModalFor(props.MaxSize, props.FitContent == true, view, UIKit.IsPhone())
		local fit = plan.Fit
		local width = math.min(view.X * 0.92, props.MaxSize.X + MODAL_CHROME.X)
		root.Size = UDim2.new(0.92, 0, 0, plan.RootHeight)
		root.Position = UDim2.new(0.5, UIKit.GetCardShift(width * fit), 0, plan.Top)
		root:SetAttribute("FitScale", fit)
		if gui.Enabled then
			getPopScale(root).Scale = fit
		end
	end
	placeRoot()
	table.insert(cardPlacers, placeRoot)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = props.MaxSize + MODAL_CHROME
	constraint.Parent = root

	local body = UIKit.Panel({
		Name = "Panel",
		Parent = root,
		Position = UDim2.fromOffset(MODAL_MARGIN, MODAL_MARGIN),
		Size = UDim2.new(1, -MODAL_MARGIN * 2, 1, -(MODAL_MARGIN * 2 + UITheme.ShadowOffset)),
		Gradient = { { 0, props.HeaderTop }, { 0.22, Colors.Panel }, { 1, Colors.Panel } },
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	UIKit.Padding(body, 16)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 48)
	header.ZIndex = body.ZIndex + 1
	header.Parent = body

	local title = UIKit.Label({
		Name = "Title",
		Text = props.Title,
		Font = Fonts.Display,
		TextSize = 32,
		Size = UDim2.new(1, -60, 0, 34),
		ZIndex = header.ZIndex,
		Stroke = UITheme.Stroke.Text,
		Parent = header,
	})
	UIKit.FitText(title, 32, 18)
	local subtitle = UIKit.Label({
		Name = "Subtitle",
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, -60, 0, 16),
		ZIndex = header.ZIndex,
		Visible = false,
		Parent = header,
	})

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(0, 58)
	content.Size = UDim2.new(1, 0, 1, -58)
	content.ZIndex = body.ZIndex + 1
	content.Parent = body

	local isOpen = false
	local modal: Modal

	local function close()
		if not isOpen then
			return
		end
		isOpen = false
		UIKit.SetOverlay(props.Name, false)
		local tween = UIKit.PopOut(root)
		TweenService:Create(backdrop, POP_OUT_INFO, { BackgroundTransparency = 1 }):Play()
		tween.Completed:Once(function()
			if not isOpen then
				gui.Enabled = false
			end
		end)
		if props.OnClose then
			props.OnClose()
		end
	end

	local function open()
		isOpen = true
		placeRoot()
		UIKit.SetOverlay(props.Name, true)
		gui.Enabled = true
		backdrop.BackgroundTransparency = 1
		TweenService:Create(backdrop, POP_IN_INFO, { BackgroundTransparency = 0.45 }):Play()
		UIKit.PopIn(root)
	end

	UIKit.CloseButton({
		Parent = header,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		OnClick = close,
		ZIndex = header.ZIndex,
	})
	backdrop.Activated:Connect(close)

	modal = {
		Gui = gui,
		Root = root,
		Body = body,
		Content = content,
		Header = header,
		Title = title,
		Subtitle = subtitle,
		Open = open,
		Close = close,
		IsOpen = function()
			return isOpen
		end,
	}
	return modal
end

-- Escapes text for safe use inside a RichText label.
function UIKit.EscapeRichText(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- `<font color="#...">text</font>`
function UIKit.Colored(text: string, color: Color3): string
	return ('<font color="%s">%s</font>'):format(UITheme.ToHex(color), text)
end

return UIKit
