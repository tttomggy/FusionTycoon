--!strict
--[[
	BillboardKit
	------------
	The "Fusion Lab" look for world labels (BillboardGuis), built by the
	server: pad labels (title + gradient price pill + detail line), pedestal
	labels, the Fusion odds board and the plot sign. Colours and fonts come
	from UITheme, like the HUD's.

	Every label: LightInfluence 0, AlwaysOnTop false (true drew them through
	walls), and a MaxDistance so they don't litter the map.

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

BillboardKit.PAD_MAX_DISTANCE = 26
BillboardKit.PEDESTAL_MAX_DISTANCE = 70
BillboardKit.PLOT_SIGN_MAX_DISTANCE = 120
BillboardKit.OWNER_ONLY_ATTRIBUTE = "OwnerOnly"

--[[ Primitives ------------------------------------------------------------- ]]

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
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

local function textStroke(label: TextLabel, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Colors.Ink
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
end

local function gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = parent
end

local function listLayout(parent: Instance, padding: number)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent
end

local function label(
	parent: Instance,
	name: string,
	font: Font,
	size: number,
	color: Color3,
	height: number,
	order: number
): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = color
	text.Size = UDim2.new(1, 0, 0, height)
	text.LayoutOrder = order
	text.RichText = false
	text.Parent = parent
	return text
end

local function newBillboard(parent: Instance, name: string, size: Vector2, offset: Vector3, maxDistance: number): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = name
	billboard.Size = UDim2.fromOffset(size.X, size.Y)
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

-- Title (Display 30, coloured, 2.5 ink stroke), a gradient price pill
-- (Display 22, ink stroke 3) and an optional detail line (Body 13).
function BillboardKit.Pad(parent: Instance, props: PadProps): PadLabel
	local gui = newBillboard(
		parent,
		props.Name or "PadLabel",
		Vector2.new(300, 120),
		props.StudsOffset or Vector3.new(0, 3, 0),
		props.MaxDistance or BillboardKit.PAD_MAX_DISTANCE
	)
	if props.OwnerOnly then
		gui:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)
	end

	local stack = Instance.new("Frame")
	stack.BackgroundTransparency = 1
	stack.Size = UDim2.fromScale(1, 1)
	stack.Parent = gui
	listLayout(stack, 4)

	local title = label(stack, "Title", Fonts.Display, 30, props.TitleColor, 34, 1)
	title.Text = props.Title
	textStroke(title, 2.5)

	local pill = label(stack, "Pill", Fonts.Display, 22, props.PillTextColor or Colors.Text, 34, 2)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromOffset(0, 34)
	pill.BackgroundTransparency = 0
	pill.BackgroundColor3 = Colors.White
	gradient(pill, props.PillGradient.Top, props.PillGradient.Bottom)
	corner(pill, 999)
	borderStroke(pill, 3)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = pill
	if props.PillTextStroke ~= false then
		textStroke(pill, 2)
	end
	pill.Text = props.Pill

	local detail = label(stack, "Detail", Fonts.Body, 13, Colors.Text, 18, 3)
	textStroke(detail, 1.5)

	local function setDetail(text: string?)
		detail.Text = text or ""
		detail.Visible = text ~= nil and text ~= ""
	end
	setDetail(props.Detail)

	return {
		Gui = gui,
		SetPill = function(text: string)
			pill.Text = text
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

local function buildFilledLabel(pedestal: BasePart): BillboardGui
	local gui = newBillboard(pedestal, "FilledLabel", Vector2.new(210, 86), pedestalLabelOffset(pedestal), BillboardKit.PEDESTAL_MAX_DISTANCE)
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Colors.Panel
	panel.BackgroundTransparency = 0.08
	panel.Size = UDim2.new(1, -6, 1, -6)
	panel.Position = UDim2.fromOffset(3, 3)
	panel.Parent = gui
	corner(panel, 14)
	borderStroke(panel, 3)
	listLayout(panel, 0)

	label(panel, "Tier", Fonts.BodyHeavy, 11, Colors.Text, 16, 1)
	local name = label(panel, "ItemName", Fonts.Display, 22, Colors.Text, 28, 2)
	textStroke(name, 2)
	label(panel, "Rate", Fonts.Body, 14, Colors.Cash, 20, 3)
	return gui
end

local function buildEmptyLabel(pedestal: BasePart): BillboardGui
	local gui = newBillboard(pedestal, "EmptyLabel", Vector2.new(190, 64), pedestalLabelOffset(pedestal), BillboardKit.PAD_MAX_DISTANCE)
	gui:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Colors.Panel
	panel.BackgroundTransparency = 0.3
	panel.Size = UDim2.new(1, -6, 1, -6)
	panel.Position = UDim2.fromOffset(3, 3)
	panel.Parent = gui
	corner(panel, 14)
	-- "Dashed" look: a faint outline instead of the solid ink one.
	borderStroke(panel, 3, Colors.Faint)
	listLayout(panel, 0)

	local empty = label(panel, "Empty", Fonts.Display, 18, Colors.Muted, 24, 1)
	empty.Text = "EMPTY"
	local hint = label(panel, "Hint", Fonts.Body, 12, Colors.Faint, 16, 2)
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

--[[ Fusion odds board ---------------------------------------------------------- ]]

export type OddsRow = {
	FromTier: string,
	ToTier: string,
	Chance: number, -- 0..1
}

function BillboardKit.OddsBoard(anchor: Instance, rows: { OddsRow }, offset: Vector3): BillboardGui
	local gui = newBillboard(anchor, "FusionOddsBillboard", Vector2.new(250, 60 + 26 * #rows), offset, BillboardKit.PAD_MAX_DISTANCE)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Colors.Panel
	panel.Size = UDim2.new(1, -8, 1, -8)
	panel.Position = UDim2.fromOffset(4, 4)
	panel.Parent = gui
	corner(panel, 18)
	borderStroke(panel, 3)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = panel
	listLayout(panel, 0)

	local title = label(panel, "Title", Fonts.Display, 20, Colors.VioletLight, 26, 0)
	title.Text = "FUSE 2 → TIER UP"
	textStroke(title, 2)

	for index, row in rows do
		local line = Instance.new("Frame")
		line.Name = "Row" .. index
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(1, 0, 0, 24)
		line.LayoutOrder = index
		line.Parent = panel

		local left = label(line, "Recipe", Fonts.Body, 15, UITheme.GetTierLight(row.ToTier), 24, 0)
		left.Text = ("2 %s → %s"):format(row.FromTier, row.ToTier)
		left.TextXAlignment = Enum.TextXAlignment.Left
		textStroke(left, 1.5)

		local right = label(line, "Chance", Fonts.Display, 16, Colors.Text, 24, 0)
		right.Text = ("%d%%"):format(math.floor(row.Chance * 100 + 0.5))
		right.TextXAlignment = Enum.TextXAlignment.Right
		textStroke(right, 1.5)
	end

	local footer = label(panel, "Footer", Fonts.Body, 11, Colors.Muted, 16, #rows + 1)
	footer.Text = "Fail = keep 1 of the 2"
	return gui
end

--[[ Plot sign ------------------------------------------------------------------- ]]

export type PlotSign = {
	Gui: BillboardGui,
	Set: (title: string, detail: string) -> (),
}

function BillboardKit.PlotSign(anchor: Instance, offset: Vector3): PlotSign
	local gui = newBillboard(anchor, "PlotSign", Vector2.new(320, 86), offset, BillboardKit.PLOT_SIGN_MAX_DISTANCE)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Colors.White
	panel.Size = UDim2.new(1, -8, 1, -8)
	panel.Position = UDim2.fromOffset(4, 4)
	panel.Parent = gui
	gradient(panel, UITheme.Gradients.Violet.Top, UITheme.Gradients.Violet.Bottom)
	corner(panel, 18)
	borderStroke(panel, 4)
	listLayout(panel, 0)

	local title = label(panel, "Title", Fonts.Display, 28, Colors.Text, 34, 1)
	textStroke(title, 2.5)
	local detail = label(panel, "Detail", Fonts.Body, 13, Colors.PlotSignDetail, 18, 2)
	textStroke(detail, 1.5)

	return {
		Gui = gui,
		Set = function(titleText: string, detailText: string)
			title.Text = titleText
			detail.Text = detailText
		end,
	}
end

return BillboardKit
