--!strict
--[[
	BillboardKit
	------------
	The "Fusion Lab" look for world labels, built by the server:

	  * Pad labels and pedestal labels - BillboardGuis sized IN STUDS
	    (UDim2.fromScale), with scale-based contents and TextScaled text
	    (capped by a UITextSizeConstraint), so they shrink with distance like
	    real signs instead of filling the screen up close.
	  * The Fusion odds board and the plot sign - SurfaceGuis on real parts.

	Colours and fonts come from UITheme. Every BillboardGui: LightInfluence 0,
	AlwaysOnTop false, and a MaxDistance.

	Labels only the plot owner should see carry the attribute OwnerOnly =
	true; the client's WorldLabelController disables them for everyone else.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)

local BillboardKit = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

BillboardKit.PAD_MAX_DISTANCE = 90
BillboardKit.PEDESTAL_MAX_DISTANCE = 70
BillboardKit.EMPTY_PEDESTAL_MAX_DISTANCE = 20
BillboardKit.OWNER_ONLY_ATTRIBUTE = "OwnerOnly"

-- Billboard sizes in studs.
local PAD_LABEL_STUDS = Vector2.new(9, 3.4)
local PEDESTAL_LABEL_STUDS = Vector2.new(6.5, 2.6)
local EMPTY_PILL_STUDS = Vector2.new(3.6, 1.1)
local GENERATOR_LABEL_STUDS = Vector2.new(4.4, 1.7)
local PROGRESS_PAD_STUDS = Vector2.new(9, 4.4)
local MAX_TEXT_SIZE = 64

--[[ Primitives ------------------------------------------------------------- ]]

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function borderStroke(parent: Instance, thickness: number, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Colors.Ink
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

local function textStroke(text: TextLabel, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Colors.Ink
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = text
end

local function gradient(parent: Instance, top: Color3, bottom: Color3)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = 90
	g.Parent = parent
end

-- A TextScaled label occupying `height` (a fraction of its parent) at `y`,
-- capped at MAX_TEXT_SIZE.
local function scaledLabel(parent: Instance, name: string, font: Font, color: Color3, y: number, height: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextColor3 = color
	text.TextScaled = true
	text.RichText = false
	text.Position = UDim2.fromScale(0, y)
	text.Size = UDim2.fromScale(1, height)
	text.Parent = parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = MAX_TEXT_SIZE
	constraint.Parent = text
	return text
end

local function newBillboard(parent: Instance, name: string, studs: Vector2, offset: Vector3, maxDistance: number): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = name
	billboard.Size = UDim2.fromScale(studs.X, studs.Y)
	billboard.StudsOffset = offset
	billboard.MaxDistance = maxDistance
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = false
	billboard.ResetOnSpawn = false
	billboard.Parent = parent
	return billboard
end

--[[ Pad label --------------------------------------------------------------- ]]

export type PadProps = {
	Name: string?,
	Title: string,
	TitleColor: Color3,
	Pill: string,
	PillGradient: UITheme.GradientPair,
	PillTextColor: Color3?,
	PillTextStroke: boolean?, -- default true; the gold pill turns it off
	Detail: string?,
	StudsOffset: Vector3?,
	MaxDistance: number?,
	OwnerOnly: boolean?,
}

export type PadLabel = {
	Gui: BillboardGui,
	SetPill: (text: string) -> (),
	SetDetail: (text: string?) -> (),
}

-- Title (Display, coloured, ink stroke), a gradient price pill (Display,
-- ink stroke) and an optional detail line (Body). 9 x 3.4 studs.
function BillboardKit.Pad(parent: Instance, props: PadProps): PadLabel
	local gui = newBillboard(
		parent,
		props.Name or "PadLabel",
		PAD_LABEL_STUDS,
		props.StudsOffset or Vector3.new(0, PlotLayout.Station.LabelOffsetY, 0),
		props.MaxDistance or BillboardKit.PAD_MAX_DISTANCE
	)
	if props.OwnerOnly then
		gui:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)
	end

	local title = scaledLabel(gui, "Title", Fonts.Display, props.TitleColor, 0, 0.4)
	title.Text = props.Title
	textStroke(title, 2.5)

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.fromScale(0.5, 0.42)
	pill.Size = UDim2.fromScale(0.62, 0.34)
	pill.BackgroundColor3 = Colors.White
	pill.Parent = gui
	gradient(pill, props.PillGradient.Top, props.PillGradient.Bottom)
	corner(pill, UDim.new(0.5, 0))
	borderStroke(pill, 3)
	local pillText = scaledLabel(pill, "Text", Fonts.Display, props.PillTextColor or Colors.Text, 0.12, 0.76)
	if props.PillTextStroke ~= false then
		textStroke(pillText, 2)
	end
	pillText.Text = props.Pill

	local detail = scaledLabel(gui, "Detail", Fonts.Body, Colors.Text, 0.8, 0.2)
	textStroke(detail, 1.5)

	local function setDetail(text: string?)
		detail.Text = text or ""
		detail.Visible = text ~= nil and text ~= ""
	end
	setDetail(props.Detail)

	return {
		Gui = gui,
		SetPill = function(text: string)
			pillText.Text = text
		end,
		SetDetail = setDetail,
	}
end

--[[ Progress pad label --------------------------------------------------------
	A pad label with a progress bar: title, gradient pill, bar and a caption
	(the Rebirth Portal). Updates only set text and the bar's size; nothing
	is rebuilt.
]]

export type ProgressPadProps = {
	Name: string?,
	Title: string,
	TitleColor: Color3,
	Pill: string,
	PillGradient: UITheme.GradientPair,
	BarColor: Color3,
	Caption: string?,
	CaptionColor: Color3?,
	StudsOffset: Vector3,
	MaxDistance: number,
	OwnerOnly: boolean?,
}

export type ProgressPadLabel = {
	Gui: BillboardGui,
	SetPill: (text: string) -> (),
	SetProgress: (fraction: number) -> (),
	SetCaption: (text: string) -> (),
}

-- A horizontal bar (Panel2 track, Ink stroke, a fill in `color`) filling
-- `parent` at the given scale position/size. Returns a setter for 0..1.
function BillboardKit.Bar(parent: Instance, position: UDim2, size: UDim2, color: Color3): (number) -> ()
	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.BackgroundColor3 = Colors.Panel2
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = position
	track.Size = size
	track.ClipsDescendants = true
	track.Parent = parent
	corner(track, UDim.new(0.5, 0))
	borderStroke(track, 2)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	corner(fill, UDim.new(0.5, 0))

	return function(fraction: number)
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	end
end

function BillboardKit.ProgressPad(parent: Instance, props: ProgressPadProps): ProgressPadLabel
	local gui = newBillboard(parent, props.Name or "ProgressLabel", PROGRESS_PAD_STUDS, props.StudsOffset, props.MaxDistance)
	if props.OwnerOnly then
		gui:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)
	end

	local title = scaledLabel(gui, "Title", Fonts.Display, props.TitleColor, 0, 0.3)
	title.Text = props.Title
	textStroke(title, 2.5)

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.fromScale(0.5, 0.32)
	pill.Size = UDim2.fromScale(0.86, 0.24)
	pill.BackgroundColor3 = Colors.White
	pill.Parent = gui
	gradient(pill, props.PillGradient.Top, props.PillGradient.Bottom)
	corner(pill, UDim.new(0.5, 0))
	borderStroke(pill, 3)
	local pillText = scaledLabel(pill, "Text", Fonts.Display, Colors.Text, 0.12, 0.76)
	textStroke(pillText, 2)
	pillText.Text = props.Pill

	local setBar = BillboardKit.Bar(gui, UDim2.fromScale(0.5, 0.62), UDim2.fromScale(0.8, 0.1), props.BarColor)

	local caption = scaledLabel(gui, "Caption", Fonts.Body, props.CaptionColor or Colors.Text, 0.78, 0.2)
	textStroke(caption, 1.5)
	caption.Text = props.Caption or ""

	return {
		Gui = gui,
		SetPill = function(text: string)
			pillText.Text = text
		end,
		SetProgress = setBar,
		SetCaption = function(text: string)
			caption.Text = text
		end,
	}
end

--[[ Pedestal labels ---------------------------------------------------------- ]]

export type PedestalInfo = {
	Tier: string,
	Mutation: string?, -- shows as "GOLDEN · MYTHIC" in the mutation colour
	ItemName: string,
	Rate: number, -- per second, owner's multiplier included
}

-- PlotLayout's label heights are measured from the pedestal's bottom;
-- StudsOffset is from its centre.
local function pedestalLabelOffset(pedestal: BasePart, heightAboveBottom: number): Vector3
	local baseSize = (pedestal:GetAttribute("BaseSize") :: Vector3?) or pedestal.Size
	return Vector3.new(0, heightAboveBottom - baseSize.Y / 2, 0)
end

local function pedestalPanel(gui: BillboardGui, transparency: number, strokeColor: Color3): Frame
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Colors.Panel
	panel.BackgroundTransparency = transparency
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.96, 0.92)
	panel.Parent = gui
	corner(panel, UDim.new(0.18, 0))
	borderStroke(panel, 3, strokeColor)
	return panel
end

local function buildFilledLabel(pedestal: BasePart): BillboardGui
	local gui = newBillboard(
		pedestal,
		"FilledLabel",
		PEDESTAL_LABEL_STUDS,
		pedestalLabelOffset(pedestal, PlotLayout.Pedestal.LabelOffsetY),
		BillboardKit.PEDESTAL_MAX_DISTANCE
	)
	local panel = pedestalPanel(gui, 0.08, Colors.Ink)
	scaledLabel(panel, "Tier", Fonts.BodyHeavy, Colors.Text, 0.06, 0.2)
	local name = scaledLabel(panel, "ItemName", Fonts.Display, Colors.Text, 0.28, 0.4)
	textStroke(name, 2)
	scaledLabel(panel, "Rate", Fonts.Body, Colors.Cash, 0.7, 0.24)
	return gui
end

-- A small, low pill: circled "+" then EMPTY. Owner-only.
local function buildEmptyLabel(pedestal: BasePart): BillboardGui
	local gui = newBillboard(
		pedestal,
		"EmptyLabel",
		EMPTY_PILL_STUDS,
		pedestalLabelOffset(pedestal, PlotLayout.Pedestal.EmptyLabelOffsetY),
		BillboardKit.EMPTY_PEDESTAL_MAX_DISTANCE
	)
	gui:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)

	local pill = Instance.new("Frame")
	pill.Name = "Panel"
	pill.BackgroundColor3 = Colors.Panel
	pill.BackgroundTransparency = 0.15
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromScale(0.96, 0.9)
	pill.Parent = gui
	corner(pill, UDim.new(0.5, 0))
	borderStroke(pill, 3, Colors.Faint)

	-- Circled "+": a ring with the glyph inside, sized to the pill height.
	local badge = Instance.new("Frame")
	badge.Name = "Plus"
	badge.BackgroundTransparency = 1
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.fromScale(0.08, 0.5)
	badge.Size = UDim2.fromScale(0.62, 0.62)
	badge.SizeConstraint = Enum.SizeConstraint.RelativeYY
	badge.Parent = pill
	corner(badge, UDim.new(0.5, 0))
	borderStroke(badge, 2, Colors.Muted)
	local plus = scaledLabel(badge, "Glyph", Fonts.Display, Colors.Muted, 0.05, 0.9)
	plus.Text = "+"
	textStroke(plus, 2)

	local word = scaledLabel(pill, "Empty", Fonts.Display, Colors.Muted, 0.18, 0.64)
	word.Position = UDim2.fromScale(0.34, 0.18)
	word.Size = UDim2.fromScale(0.58, 0.64)
	word.TextXAlignment = Enum.TextXAlignment.Left
	word.Text = "EMPTY"
	return gui
end

-- Shows the filled label (everyone) for `info`, or the owner-only empty
-- label when `info` is nil. Creates both on first use.
function BillboardKit.SetPedestalLabel(pedestal: BasePart, info: PedestalInfo?)
	local filled = pedestal:FindFirstChild("FilledLabel") :: BillboardGui?
	if not filled then
		filled = buildFilledLabel(pedestal)
	end
	local empty = pedestal:FindFirstChild("EmptyLabel") :: BillboardGui?
	if not empty then
		empty = buildEmptyLabel(pedestal)
	end
	local filledGui = filled :: BillboardGui
	local emptyGui = empty :: BillboardGui

	if info then
		local panel = filledGui:FindFirstChild("Panel") :: Frame
		local tierLabel = panel:FindFirstChild("Tier") :: TextLabel
		local nameLabel = panel:FindFirstChild("ItemName") :: TextLabel
		local rateLabel = panel:FindFirstChild("Rate") :: TextLabel
		local mutationColor = UITheme.GetMutationColor(info.Mutation)
		local tint = tierLabel:FindFirstChild("RainbowTint")
		if info.Mutation and mutationColor then
			tierLabel.Text = ("%s · %s"):format(info.Mutation:upper(), info.Tier:upper())
			if info.Mutation == "Rainbow" then
				-- Intended tinting: white text under a rainbow UIGradient.
				tierLabel.TextColor3 = Colors.White
				if not tint then
					local gradient = Instance.new("UIGradient")
					gradient.Name = "RainbowTint"
					gradient.Color = UITheme.GetRainbowSequence()
					gradient.Parent = tierLabel
				end
			else
				tierLabel.TextColor3 = mutationColor
				if tint then
					tint:Destroy()
				end
			end
		else
			tierLabel.Text = info.Tier:upper()
			tierLabel.TextColor3 = UITheme.GetTierLight(info.Tier)
			if tint then
				tint:Destroy()
			end
		end
		nameLabel.Text = info.ItemName
		rateLabel.Text = ("+%s/s"):format(NumberFormat.Money(info.Rate))
	end
	filledGui.Enabled = info ~= nil
	emptyGui.Enabled = info == nil
end

--[[ Generator label ----------------------------------------------------------- ]]

export type GeneratorLabel = {
	Gui: BillboardGui,
	Set: (title: string, detail: string, detailColor: Color3) -> (),
}

-- A small owner-only panel over a generator: a Display title ("LOCKED",
-- "BUY") over a Body detail line (the requirement, or the price in Cash).
function BillboardKit.GeneratorLabel(parent: Instance, offset: Vector3, maxDistance: number): GeneratorLabel
	local gui = newBillboard(parent, "GeneratorLabel", GENERATOR_LABEL_STUDS, offset, maxDistance)
	gui:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)
	local panel = pedestalPanel(gui, 0.1, Colors.Ink)
	local title = scaledLabel(panel, "Title", Fonts.Display, Colors.Text, 0.08, 0.46)
	textStroke(title, 2)
	local detail = scaledLabel(panel, "Detail", Fonts.Body, Colors.Muted, 0.56, 0.34)
	return {
		Gui = gui,
		Set = function(titleText: string, detailText: string, detailColor: Color3)
			title.Text = titleText
			detail.Text = detailText
			detail.TextColor3 = detailColor
		end,
	}
end

--[[ Surfaces ------------------------------------------------------------------ ]]

local function newSurface(part: BasePart, name: string, face: Enum.NormalId, pixelsPerStud: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = part
	return gui
end

export type OddsRow = {
	FromTier: string,
	ToTier: string,
	Chance: number, -- 0..1
	RebirthsNeeded: number?, -- shown as "(Rebirth n)" after the recipe
}

-- The odds board's content on the Front face of `board` (a real board part,
-- not a billboard): title, one row per recipe coloured by the tier it fuses
-- into, and the fail rule.
function BillboardKit.OddsSurface(board: BasePart, rows: { OddsRow }, pixelsPerStud: number): SurfaceGui
	local gui = newSurface(board, "OddsSurface", Enum.NormalId.Front, pixelsPerStud)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Colors.Panel
	panel.Size = UDim2.fromScale(1, 1)
	panel.Parent = gui
	borderStroke(panel, 6)

	local titleHeight, footerHeight = 0.2, 0.12
	local rowHeight = (1 - titleHeight - footerHeight - 0.08) / math.max(#rows, 1)

	local title = scaledLabel(panel, "Title", Fonts.Display, Colors.VioletLight, 0.03, titleHeight)
	title.Text = "FUSE 2 → TIER UP"
	textStroke(title, 2)

	for index, row in rows do
		local y = 0.04 + titleHeight + (index - 1) * rowHeight
		local left = scaledLabel(panel, "Recipe" .. index, Fonts.Body, UITheme.GetTierLight(row.ToTier), y, rowHeight * 0.9)
		left.Position = UDim2.fromScale(0.06, y)
		left.Size = UDim2.fromScale(0.66, rowHeight * 0.9)
		left.TextXAlignment = Enum.TextXAlignment.Left
		left.Text = ("2 %s → %s"):format(row.FromTier, row.ToTier)
			.. (if row.RebirthsNeeded then (" (Rebirth %d)"):format(row.RebirthsNeeded) else "")
		textStroke(left, 1.5)

		local right = scaledLabel(panel, "Chance" .. index, Fonts.Display, Colors.Text, y, rowHeight * 0.9)
		right.Position = UDim2.fromScale(0.72, y)
		right.Size = UDim2.fromScale(0.22, rowHeight * 0.9)
		right.TextXAlignment = Enum.TextXAlignment.Right
		right.Text = ("%d%%"):format(math.floor(row.Chance * 100 + 0.5))
		textStroke(right, 1.5)
	end

	local footer = scaledLabel(panel, "Footer", Fonts.Body, Colors.Muted, 1 - footerHeight - 0.03, footerHeight)
	footer.Text = "Fail = keep 1 of the 2"
	return gui
end

export type SignSurface = {
	Set: (title: string, detail: string) -> (),
}

-- The plot sign's content on BOTH the Front and Back faces of `board`: the
-- Violet button gradient, "<NAME>'S LAB" and the income/best line.
function BillboardKit.SignSurface(board: BasePart, pixelsPerStud: number): SignSurface
	local titles: { TextLabel } = {}
	local details: { TextLabel } = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = newSurface(board, "Sign" .. face.Name, face, pixelsPerStud)
		local panel = Instance.new("Frame")
		panel.Name = "Panel"
		panel.BackgroundColor3 = Colors.White
		panel.Size = UDim2.fromScale(1, 1)
		panel.Parent = gui
		gradient(panel, UITheme.Gradients.Violet.Top, UITheme.Gradients.Violet.Bottom)

		local title = scaledLabel(panel, "Title", Fonts.Display, Colors.Text, 0.08, 0.52)
		textStroke(title, 4)
		local detail = scaledLabel(panel, "Detail", Fonts.Body, Colors.PlotSignDetail, 0.64, 0.26)
		table.insert(titles, title)
		table.insert(details, detail)
	end
	return {
		Set = function(titleText: string, detailText: string)
			for _, title in titles do
				title.Text = titleText
			end
			for _, detail in details do
				detail.Text = detailText
			end
		end,
	}
end

--[[ Pad faces ------------------------------------------------------------------
	A station pad's (or the machine floor's) top: an invisible square part
	just above the pad carrying a SurfaceGui with an accent ring, a faked
	radial glow and an optional word. Replaces the flat Neon discs, which
	Roblox draws as a fan of triangles that catch the light unevenly.
]]

local function circle(parent: Instance, name: string, scale: number, color: Color3, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(scale, scale)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.Parent = parent
	corner(frame, UDim.new(0.5, 0))
	return frame
end

-- Builds the Face part on top of a pad and returns it. `top` is the pad
-- top's centre (plot-aligned), so the word reads upright walking in from
-- the gate (+Z); `word` nil = ring and glow only.
function BillboardKit.BuildPadFace(parent: Instance, top: CFrame, diameter: number, accent: Color3, word: string?): BasePart
	local f = PlotLayout.Face
	local face = PartKit.Part({
		Name = "Face",
		Size = Vector3.new(diameter, f.Thickness, diameter),
		CFrame = top * CFrame.new(0, f.GapAbovePad + f.Thickness / 2, 0),
		Color = accent,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = parent,
	})

	local gui = newSurface(face, "PadFace", Enum.NormalId.Top, f.PixelsPerStud)
	gui.Brightness = f.Brightness

	local ring = circle(gui, "Ring", 1, accent, 1)
	borderStroke(ring, f.RingStrokePx, accent).Name = "RingStroke"

	-- UIGradient can't go radial: a faint outer circle plus a stronger
	-- smaller core reads as a soft centre glow.
	local glowScale = 1 - f.GlowInset * 2
	circle(gui, "GlowOuter", glowScale, accent, f.GlowOuterTransparency)
	circle(gui, "GlowCore", glowScale * f.GlowCoreScale, accent, f.GlowCoreTransparency)

	if word then
		local label = Instance.new("TextLabel")
		label.Name = "Word"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0.8, f.WordHeight)
		label.FontFace = Fonts.Display
		label.TextScaled = true
		label.TextColor3 = Colors.Text
		label.Text = word
		label.Parent = gui
		textStroke(label, f.WordStroke)
	end

	local light = Instance.new("PointLight")
	light.Name = "FaceLight"
	light.Color = accent
	light.Brightness = f.LightBrightness
	light.Range = f.LightRange
	light.Parent = face
	return face
end

-- Recolours a pad face's ring and glow and optionally swaps its word; pass
-- removeLight to drop its PointLight (the claim pad once claimed).
function BillboardKit.SetPadFace(face: BasePart, color: Color3, word: string?, removeLight: boolean?)
	local gui = face:FindFirstChild("PadFace")
	if not gui then
		return
	end
	local ring = gui:FindFirstChild("Ring")
	local stroke = ring and ring:FindFirstChild("RingStroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = color
	end
	for _, name in { "GlowOuter", "GlowCore" } do
		local glow = gui:FindFirstChild(name)
		if glow and glow:IsA("Frame") then
			glow.BackgroundColor3 = color
		end
	end
	local label = gui:FindFirstChild("Word")
	if word and label and label:IsA("TextLabel") then
		label.Text = word
	end
	if removeLight then
		local light = face:FindFirstChild("FaceLight")
		if light then
			light:Destroy()
		end
	end
end

return BillboardKit
