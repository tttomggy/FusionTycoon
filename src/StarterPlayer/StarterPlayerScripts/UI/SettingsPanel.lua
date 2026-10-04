--!strict
--[[
	SettingsPanel
	-------------
	The ⚙ modal (bottom bar, after INDEX). Sections stack in one scrolling
	list so later ones (music / sound volume) just append a section.

	  Big reveal card   "Pick when a pull or fusion gets the big card…";
	                    one row per tier Common → Mythic: the tier name in its
	                    colour + a 5-option segmented control (Never / Golden+
	                    / Diamond+ / Rainbow+ / Always); a locked Secret row.

	Changes apply at once (TycoonController.SetRevealRule, optimistic) and
	save on the server (SetSetting). 620 wide; on a phone the list scrolls.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage.Shared.Config.SettingsConfig)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TycoonController = require(script.Parent.Parent.Controllers.TycoonController)
local UIKit = require(script.Parent.UIKit)

local SettingsPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(620, 560)
local ROW_HEIGHT = UITheme.MinTapSize + 12
local TIER_COLUMN = 110
local SEGMENT_GAP = 4

type Segment = { Button: TextButton, Label: TextLabel, Stroke: UIStroke }

local modal: UIKit.Modal
local list: ScrollingFrame
local segments: { [string]: { [string]: Segment } } = {}
local order = 0

local function nextOrder(): number
	order += 1
	return order
end

local function refresh()
	local rule = TycoonController.GetRevealRule()
	for tier, row in segments do
		for value, segment in row do
			local selected = rule[tier] == value
			segment.Button.BackgroundColor3 = if selected then Colors.ShieldTeal else Colors.Panel3
			segment.Label.TextColor3 = if selected then Colors.Text else Colors.Muted
			segment.Stroke.Color = if selected then Colors.Text else Colors.Ink
		end
	end
end

--[[ Build -------------------------------------------------------------------- ]]

local function sectionTitle(text: string)
	UIKit.Label({
		Name = "SectionTitle",
		Text = text,
		Font = Fonts.Display,
		TextSize = 20,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = nextOrder(),
		ZIndex = list.ZIndex + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = list,
	})
end

local function note(text: string, color: Color3?)
	UIKit.Label({
		Name = "Note",
		Text = text,
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = color or Colors.Muted,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = nextOrder(),
		ZIndex = list.ZIndex + 1,
		Parent = list,
	})
end

local function tierRow(tier: string)
	local z = list.ZIndex + 1
	local row = Instance.new("Frame")
	row.Name = tier .. "Row"
	row.BackgroundColor3 = Colors.Panel2
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.LayoutOrder = nextOrder()
	row.ZIndex = z
	row.Parent = list
	UIKit.Corner(row, UITheme.Radius.Row)
	UIKit.Stroke(row, 2)
	UIKit.Label({
		Name = "Tier",
		Text = tier,
		Font = Fonts.Display,
		TextSize = 17,
		TextColor3 = UITheme.GetTierLight(tier),
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0, TIER_COLUMN - 12, 1, 0),
		ZIndex = z + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = row,
	})
	local control = Instance.new("Frame")
	control.Name = "Segments"
	control.BackgroundTransparency = 1
	control.AnchorPoint = Vector2.new(1, 0.5)
	control.Position = UDim2.new(1, -6, 0.5, 0)
	control.Size = UDim2.new(1, -(TIER_COLUMN + 6), 0, UITheme.MinTapSize)
	control.ZIndex = z + 1
	control.Parent = row
	local values = SettingsConfig.RevealValues
	local count = #values
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, SEGMENT_GAP)
	layout.Parent = control
	segments[tier] = {}
	for index, value in values do
		local button = Instance.new("TextButton")
		button.Name = value
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = Colors.Panel3
		button.Size = UDim2.new(1 / count, -SEGMENT_GAP * (count - 1) / count, 1, 0)
		button.LayoutOrder = index
		button.ZIndex = z + 2
		button.Parent = control
		UIKit.Corner(button, 10)
		local stroke = UIKit.Stroke(button, 2)
		local label = UIKit.Label({
			Name = "Label",
			Text = SettingsConfig.RevealLabels[value] or value,
			Font = Fonts.BodyHeavy,
			TextSize = 13,
			TextScaled = true,
			Size = UDim2.new(1, -8, 1, -12),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 3,
			Parent = button,
		})
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = 14
		cap.Parent = label
		UIKit.AttachPress(button)
		button.Activated:Connect(function()
			TycoonController.SetRevealRule(tier, value)
			refresh()
		end)
		segments[tier][value] = { Button = button, Label = label, Stroke = stroke }
	end
end

local function lockedRow()
	local row = Instance.new("Frame")
	row.Name = "SecretRow"
	row.BackgroundColor3 = Colors.Panel2
	row.BackgroundTransparency = 0.4
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.LayoutOrder = nextOrder()
	row.ZIndex = list.ZIndex + 1
	row.Parent = list
	UIKit.Corner(row, UITheme.Radius.Row)
	UIKit.Stroke(row, 2)
	local tier = SettingsConfig.AlwaysTier
	UIKit.Label({
		Name = "Tier",
		Text = tier,
		Font = Fonts.Display,
		TextSize = 17,
		TextColor3 = UITheme.GetTierLight(tier),
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0, TIER_COLUMN - 12, 1, 0),
		ZIndex = row.ZIndex + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = row,
	})
	UIKit.Label({
		Name = "Locked",
		Text = ("🔒 Always shows. So do %s Charged, %s Void and %s Celestial."):format(
			EventConfig.Icons.PowerSurge,
			EventConfig.Icons.Night,
			EventConfig.Icons.MeteorShower
		),
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		Position = UDim2.fromOffset(TIER_COLUMN, 0),
		Size = UDim2.new(1, -(TIER_COLUMN + 12), 1, 0),
		ZIndex = row.ZIndex + 1,
		Parent = row,
	})
end

local function build()
	modal = UIKit.Modal({
		Name = "SettingsPanel",
		Title = "SETTINGS",
		DisplayOrder = 143,
		MaxSize = MAX_SIZE,
		HeaderTop = Colors.PanelTop,
	})
	local content = modal.Content
	list = Instance.new("ScrollingFrame")
	list.Name = "Sections"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Colors.Faint
	list.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	list.ZIndex = content.ZIndex
	list.Parent = content
	UIKit.Padding(list, 2, 4, 8, 2)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	-- Section: Big reveal card. (Future sections append below.)
	sectionTitle("Big reveal card")
	note("Pick when a pull or fusion gets the big card. Everything else just pops a small line.")
	for _, tier in SettingsConfig.RevealTiers do
		tierRow(tier)
	end
	lockedRow()
end

--[[ Public ------------------------------------------------------------------- ]]

function SettingsPanel.Toggle()
	if modal.IsOpen() then
		modal.Close()
	else
		refresh()
		modal.Open()
	end
end

function SettingsPanel.Init()
	build()
	TycoonController.TycoonChanged:Connect(function()
		if modal.IsOpen() then
			refresh()
		end
	end)
end

return SettingsPanel
