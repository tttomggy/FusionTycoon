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
local Workspace = game:GetService("Workspace")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)

local UIKit = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local PRESS_DOWN_INFO = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_UP_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_IN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PRESS_DEPTH = 4

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
	local gradient = UIKit.PairGradient(button, UITheme.Gradients[props.Style or "Green"] or UITheme.Gradients.Green)
	gradient.Name = "Fill"

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
		TextColor3 = props.TextColor3 or Colors.Text,
		AutomaticSize = Enum.AutomaticSize.XY,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		ZIndex = content.ZIndex,
		Stroke = UITheme.Stroke.Text,
		Parent = textColumn,
	})
	-- No drop stroke on the tiny sub-label; it would swallow the glyphs.
	UIKit.Label({
		Name = "SubLabel",
		Text = props.SubText or "",
		Font = Fonts.BodyHeavy,
		TextSize = props.SubTextSize or 11,
		TextColor3 = props.TextColor3 or Colors.Text,
		AutomaticSize = Enum.AutomaticSize.XY,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		ZIndex = content.ZIndex,
		Visible = props.SubText ~= nil and props.SubText ~= "",
		Parent = textColumn,
	})

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
function UIKit.SetButton(button: TextButton, state: ButtonState)
	if state.Style then
		local gradient = button:FindFirstChild("Fill") :: UIGradient?
		local pair = UITheme.Gradients[state.Style]
		if gradient and pair then
			UIKit.SetPairGradient(gradient, pair)
		end
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
	if state.TextColor3 then
		if label then
			label.TextColor3 = state.TextColor3
		end
		if subLabel then
			subLabel.TextColor3 = state.TextColor3
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

-- Auto-width rounded capsule. Returns the TextLabel itself (Text is live).
function UIKit.Pill(props: PillProps): TextLabel
	local pill = UIKit.Label({
		Name = props.Name or "Pill",
		Text = props.Text or "",
		Font = props.Font or Fonts.BodyHeavy,
		TextSize = props.TextSize or 13,
		TextColor3 = props.TextColor3 or Colors.Text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, props.Height or 24),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		Stroke = props.TextStroke,
	})
	if props.Gradient then
		pill.BackgroundColor3 = Colors.White
		UIKit.PairGradient(pill, props.Gradient)
	else
		pill.BackgroundColor3 = props.Color or Colors.Panel2
	end
	UIKit.Corner(pill, 999)
	UIKit.Stroke(pill, props.StrokeThickness or 2)
	UIKit.Padding(pill, 0, 10, 0, 10)
	pill.Parent = props.Parent
	return pill
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
function UIKit.TierOrb(tier: string, size: number, transparency: number?): Frame
	local alpha = transparency or 0
	local holder = Instance.new("Frame")
	holder.Name = "TierOrb"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)

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
	orb.ZIndex = 2
	orb.Parent = holder
	UIKit.Corner(orb, 999)
	local stops = UITheme.GetTierOrb(tier)
	UIKit.Gradient(orb, { { 0, stops.Light }, { 0.5, stops.Mid }, { 1, stops.Dark } }, 135)
	local stroke = UIKit.Stroke(orb, 3)
	stroke.Transparency = alpha

	-- Keep children (glow/orb) at the holder's ZIndex band when re-parented.
	holder:GetPropertyChangedSignal("ZIndex"):Connect(function()
		for _, child in holder:GetChildren() do
			if child:IsA("GuiObject") then
				child.ZIndex = holder.ZIndex + (if child.Name == "Orb" then 1 else 0)
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

-- Opens from 0.85 to 1 with a Back ease. A CanvasGroup also fades in.
function UIKit.PopIn(gui: GuiObject)
	local scale = getPopScale(gui)
	scale.Scale = 0.85
	gui.Visible = true
	if gui:IsA("CanvasGroup") then
		gui.GroupTransparency = 0
	end
	TweenService:Create(scale, POP_IN_INFO, { Scale = 1 }):Play()
end

-- Shrinks to 0.9 and fades (CanvasGroup) over 0.12 s, then hides. Returns
-- the tween so callers can wait on it.
function UIKit.PopOut(gui: GuiObject): Tween
	local scale = getPopScale(gui)
	local tween = TweenService:Create(scale, POP_OUT_INFO, { Scale = 0.9 })
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

function UIKit.IsPhone(): boolean
	return viewportHeight() < UITheme.PhoneHeightThreshold
end

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
	if isPhone ~= lastIsPhone then
		lastIsPhone = isPhone
		layoutChanged:Fire(isPhone)
	end
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

-- Escapes text for safe use inside a RichText label.
function UIKit.EscapeRichText(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- `<font color="#...">text</font>`
function UIKit.Colored(text: string, color: Color3): string
	return ('<font color="%s">%s</font>'):format(UITheme.ToHex(color), text)
end

return UIKit
