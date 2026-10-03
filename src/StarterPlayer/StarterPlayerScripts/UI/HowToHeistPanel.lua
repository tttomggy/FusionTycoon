--[[
	HowToHeistPanel
	---------------
	The HOW TO HEIST card: a UIKit Modal with four slides, one at a time
	(◀ ▶, dots, GOT IT on the last). Each slide is a picture built from UIKit
	pieces (TierOrb, rounded frames as players, UITheme colours; no image
	assets), a title and one line:

	  1 GRAB   orb over a player, an arrow to a house
	  2 GUARD  orb on a pedestal, the owner beside it, the teal GUARDED pill
	  3 CATCH  two players and CAUGHT!
	  4 LOCK   a pink fence outline with 🔒

	Numbers come from HeistConfig (CarrySeconds, ShieldSeconds). The picture
	always sits over the text, so the same layout fits a phone (390 px tall
	after the UIScale).

	Opened automatically once per account right after the first-rebirth
	result card closes (ResultController; TipConfig id "howToHeist"), and
	any time from the HUD's "?" button.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.UIKit)

local HowToHeistPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(560, 420)
local DISPLAY_ORDER = 118 -- over the HUD and Fuse panel, under Toasts (120)
local PICTURE_HEIGHT = 160
local NAV_HEIGHT = 52
local ARROW_SIZE = 52
local DOT_SIZE = 12

type Slide = { Title: string, Line: string, Picture: (parent: Frame) -> () }

local modal: UIKit.Modal
local pictureFrame: Frame
local titleLabel: TextLabel
local lineLabel: TextLabel
local dots: { Frame } = {}
local prevButton: TextButton
local nextButton: TextButton
local gotItHolder: Frame
local nextHolder: Frame
local slides: { Slide }
local index = 1

--[[ Picture pieces ----------------------------------------------------------- ]]

-- A little player: a round head over a rounded body.
local function player(parent: Instance, x: number, color: Color3): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Player"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(x, 0, 1, -8)
	holder.Size = UDim2.fromOffset(40, 76)
	holder.Parent = parent
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.fromScale(0.5, 0)
	head.Size = UDim2.fromOffset(26, 26)
	head.BackgroundColor3 = color
	head.Parent = holder
	UIKit.Corner(head, 999)
	UIKit.Stroke(head, 3)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 1)
	body.Size = UDim2.fromOffset(36, 46)
	body.BackgroundColor3 = color
	body.Parent = holder
	UIKit.Corner(body, 12)
	UIKit.Stroke(body, 3)
	return holder
end

local function orbAt(parent: Instance, position: UDim2, size: number)
	local orb = UIKit.TierOrb("Mythic", size, nil, "Golden")
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Position = position
	orb.Parent = parent
end

local function word(parent: Instance, text: string, position: UDim2, size: number, color: Color3)
	UIKit.Label({
		Name = "Word",
		Text = text,
		Font = Fonts.Display,
		TextSize = size,
		TextColor3 = color,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(220, size + 8),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = UITheme.Stroke.Text,
		Parent = parent,
	})
end

-- A house: a square body and a square roof turned 45 degrees.
local function house(parent: Instance, x: number)
	local roof = Instance.new("Frame")
	roof.Name = "Roof"
	roof.AnchorPoint = Vector2.new(0.5, 0.5)
	roof.Position = UDim2.new(x, 0, 1, -66)
	roof.Size = UDim2.fromOffset(46, 46)
	roof.Rotation = 45
	roof.BackgroundColor3 = UITheme.World.AccentViolet
	roof.Parent = parent
	UIKit.Stroke(roof, 3)
	local body = Instance.new("Frame")
	body.Name = "House"
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.new(x, 0, 1, -8)
	body.Size = UDim2.fromOffset(64, 52)
	body.BackgroundColor3 = UITheme.World.Structure
	body.Parent = parent
	UIKit.Corner(body, 6)
	UIKit.Stroke(body, 3)
end

local function pedestal(parent: Instance, x: number)
	local column = Instance.new("Frame")
	column.Name = "Pedestal"
	column.AnchorPoint = Vector2.new(0.5, 1)
	column.Position = UDim2.new(x, 0, 1, -8)
	column.Size = UDim2.fromOffset(40, 46)
	column.BackgroundColor3 = UITheme.World.StructureLight
	column.Parent = parent
	UIKit.Corner(column, 6)
	UIKit.Stroke(column, 3)
end

--[[ Slides --------------------------------------------------------------------- ]]

local function buildSlides(): { Slide }
	return {
		{
			Title = "GRAB",
			Line = ("Hold E on someone's pedestal. Run it home in %ds and it's yours."):format(HeistConfig.CarrySeconds),
			Picture = function(parent)
				player(parent, 0.3, Colors.Rebirth)
				orbAt(parent, UDim2.new(0.3, 0, 1, -112), 36)
				word(parent, "→", UDim2.new(0.5, 0, 1, -48), 44, Colors.Text)
				house(parent, 0.72)
			end,
		},
		{
			Title = "GUARD",
			Line = "Stand next to your item. Nobody can steal it while you're there.",
			Picture = function(parent)
				pedestal(parent, 0.42)
				orbAt(parent, UDim2.new(0.42, 0, 1, -82), 34)
				player(parent, 0.62, Colors.ShieldTeal)
				UIKit.Pill({
					Name = "Guarded",
					Parent = parent,
					Text = "🛡 GUARDED",
					Color = Colors.ShieldTeal,
					Font = Fonts.Display,
					TextSize = 16,
					Height = 30,
					TextStroke = 1.5,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 10),
				})
			end,
		},
		{
			Title = "CATCH",
			Line = "A thief has your item? Touch them and it flies back.",
			Picture = function(parent)
				player(parent, 0.4, Colors.Rebirth)
				orbAt(parent, UDim2.new(0.4, 0, 1, -112), 30)
				player(parent, 0.58, Colors.ShieldTeal)
				word(parent, "CAUGHT!", UDim2.new(0.5, 0, 0, 24), 30, Colors.Danger)
			end,
		},
		{
			Title = "LOCK",
			Line = ("Press LOCK LAB. Nobody gets in for %ds. Then it recharges."):format(HeistConfig.ShieldSeconds),
			Picture = function(parent)
				local fence = Instance.new("Frame")
				fence.Name = "Fence"
				fence.AnchorPoint = Vector2.new(0.5, 0.5)
				fence.Position = UDim2.fromScale(0.5, 0.5)
				fence.Size = UDim2.fromOffset(200, 120)
				fence.BackgroundColor3 = UITheme.World.Shield
				fence.BackgroundTransparency = 0.85
				fence.Parent = parent
				UIKit.Corner(fence, 16)
				UIKit.Stroke(fence, 4, UITheme.World.Shield)
				word(parent, "🔒", UDim2.fromScale(0.5, 0.5), 52, Colors.Text)
			end,
		},
	}
end

--[[ Paging --------------------------------------------------------------------- ]]

local function show(newIndex: number)
	index = math.clamp(newIndex, 1, #slides)
	local slide = slides[index]
	for _, child in pictureFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	slide.Picture(pictureFrame)
	titleLabel.Text = slide.Title
	lineLabel.Text = slide.Line
	for i, dot in dots do
		dot.BackgroundColor3 = if i == index then Colors.Text else Colors.Faint
	end
	local last = index == #slides
	UIKit.SetButton(prevButton, {
		Style = if index > 1 then "Blue" else "Disabled",
		TextColor3 = if index > 1 then Colors.Text else Colors.Muted,
	})
	nextHolder.Visible = not last
	gotItHolder.Visible = last
	nextButton.Visible = not last
end

--[[ Build ---------------------------------------------------------------------- ]]

local function build()
	modal = UIKit.Modal({
		Name = "HowToHeist",
		Title = "HOW TO HEIST",
		DisplayOrder = DISPLAY_ORDER,
		MaxSize = MAX_SIZE,
		HeaderTop = Colors.MythicBannerLeft,
	})
	local content = modal.Content

	pictureFrame = Instance.new("Frame")
	pictureFrame.Name = "Picture"
	pictureFrame.Size = UDim2.new(1, 0, 0, PICTURE_HEIGHT)
	pictureFrame.BackgroundColor3 = Colors.Panel2
	pictureFrame.ClipsDescendants = true
	pictureFrame.ZIndex = content.ZIndex + 1
	pictureFrame.Parent = content
	UIKit.Corner(pictureFrame, UITheme.Radius.Row)
	UIKit.Stroke(pictureFrame, 2)

	titleLabel = UIKit.Label({
		Name = "SlideTitle",
		Font = Fonts.Display,
		TextSize = 30,
		Position = UDim2.fromOffset(0, PICTURE_HEIGHT + 6),
		Size = UDim2.new(1, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = UITheme.Stroke.Text,
		ZIndex = content.ZIndex + 1,
		Parent = content,
	})
	lineLabel = UIKit.Label({
		Name = "SlideLine",
		Font = Fonts.Body,
		TextSize = 16,
		TextWrapped = true,
		Position = UDim2.fromOffset(8, PICTURE_HEIGHT + 42),
		Size = UDim2.new(1, -16, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = content.ZIndex + 1,
		Parent = content,
	})

	local nav = Instance.new("Frame")
	nav.Name = "Nav"
	nav.BackgroundTransparency = 1
	nav.AnchorPoint = Vector2.new(0, 1)
	nav.Position = UDim2.new(0, 0, 1, -UITheme.ShadowOffset)
	nav.Size = UDim2.new(1, 0, 0, NAV_HEIGHT)
	nav.ZIndex = content.ZIndex + 1
	nav.Parent = content

	prevButton = UIKit.Button({
		Name = "Prev",
		Parent = nav,
		Style = "Blue",
		Text = "◀",
		TextSize = 22,
		Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE),
		ZIndex = nav.ZIndex,
		OnClick = function()
			show(index - 1)
		end,
	})
	local dotRow = Instance.new("Frame")
	dotRow.Name = "Dots"
	dotRow.BackgroundTransparency = 1
	dotRow.AnchorPoint = Vector2.new(0.5, 0.5)
	dotRow.Position = UDim2.fromScale(0.5, 0.5)
	dotRow.Size = UDim2.fromOffset(4 * (DOT_SIZE + 10), DOT_SIZE)
	dotRow.ZIndex = nav.ZIndex
	dotRow.Parent = nav
	local dotLayout = Instance.new("UIListLayout")
	dotLayout.FillDirection = Enum.FillDirection.Horizontal
	dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotLayout.Padding = UDim.new(0, 10)
	dotLayout.Parent = dotRow

	slides = buildSlides()
	for i = 1, #slides do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
		dot.BackgroundColor3 = Colors.Faint
		dot.LayoutOrder = i
		dot.ZIndex = nav.ZIndex
		dot.Parent = dotRow
		UIKit.Corner(dot, 999)
		table.insert(dots, dot)
	end

	local nextBody, holder = UIKit.Button({
		Name = "Next",
		Parent = nav,
		Style = "Blue",
		Text = "▶",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE),
		ZIndex = nav.ZIndex,
		OnClick = function()
			show(index + 1)
		end,
	})
	nextButton, nextHolder = nextBody, holder
	local _, gotIt = UIKit.Button({
		Name = "GotIt",
		Parent = nav,
		Style = "Green",
		Text = "GOT IT",
		TextSize = 20,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(140, ARROW_SIZE),
		ZIndex = nav.ZIndex,
		OnClick = function()
			modal.Close()
		end,
	})
	gotItHolder = gotIt
	gotItHolder.Visible = false
end

--[[ Public --------------------------------------------------------------------- ]]

-- Opens on the first slide.
function HowToHeistPanel.Open()
	if not modal then
		return
	end
	show(1)
	modal.Open()
end

function HowToHeistPanel.Init()
	build()
end

return HowToHeistPanel
