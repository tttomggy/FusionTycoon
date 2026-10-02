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

local BillboardKit = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

BillboardKit.PAD_MAX_DISTANCE = 90
BillboardKit.PEDESTAL_MAX_DISTANCE = 70
BillboardKit.EMPTY_PEDESTAL_MAX_DISTANCE = 25
BillboardKit.OWNER_ONLY_ATTRIBUTE = "OwnerOnly"

-- Billboard sizes in studs.
local PAD_LABEL_STUDS = Vector2.new(9, 3.4)
local PEDESTAL_LABEL_STUDS = Vector2.new(6.5, 2.6)
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

--[[ Pedestal labels ---------------------------------------------------------- ]]

export type PedestalInfo = {
	Tier: string,
	ItemName: string,
	Rate: number, -- per second, owner's multiplier included
}

-- PlotLayout.Pedestal.LabelOffsetY is measured from the pedestal's bottom;
-- StudsOffset is from its centre.
local function pedestalLabelOffset(pedestal: BasePart): Vector3
	local baseSize = (pedestal:GetAttribute("BaseSize") :: Vector3?) or pedestal.Size
	return Vector3.new(0, PlotLayout.Pedestal.LabelOffsetY - baseSize.Y / 2, 0)
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
	local gui = newBillboard(pedestal, "FilledLabel", PEDESTAL_LABEL_STUDS, pedestalLabelOffset(pedestal), BillboardKit.PEDESTAL_MAX_DISTANCE)
	local panel = pedestalPanel(gui, 0.08, Colors.Ink)
	scaledLabel(panel, "Tier", Fonts.BodyHeavy, Colors.Text, 0.06, 0.2)
	local name = scaledLabel(panel, "ItemName", Fonts.Display, Colors.Text, 0.28, 0.4)
	textStroke(name, 2)
	scaledLabel(panel, "Rate", Fonts.Body, Colors.Cash, 0.7, 0.24)
	return gui
end

local function buildEmptyLabel(pedestal: BasePart): BillboardGui
	local gui = newBillboard(pedestal, "EmptyLabel", PEDESTAL_LABEL_STUDS, pedestalLabelOffset(pedestal), BillboardKit.EMPTY_PEDESTAL_MAX_DISTANCE)
	gui:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)
	-- "Dashed" look: a faint outline instead of the solid ink one.
	local panel = pedestalPanel(gui, 0.3, Colors.Faint)
	local empty = scaledLabel(panel, "Empty", Fonts.Display, Colors.Muted, 0.12, 0.44)
	empty.Text = "EMPTY"
	local hint = scaledLabel(panel, "Hint", Fonts.Body, Colors.Faint, 0.6, 0.26)
	hint.Text = "E to display an item"
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
		tierLabel.Text = info.Tier:upper()
		tierLabel.TextColor3 = UITheme.GetTierLight(info.Tier)
		nameLabel.Text = info.ItemName
		rateLabel.Text = ("+%s/s"):format(NumberFormat.Money(info.Rate))
	end
	filledGui.Enabled = info ~= nil
	emptyGui.Enabled = info == nil
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

return BillboardKit
