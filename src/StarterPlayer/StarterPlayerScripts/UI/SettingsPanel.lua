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

	  Sound effects     a 0–100% slider (default 80%) and a mute toggle
	                    beside it; every SoundKit slot scales with it.

	Changes apply at once (TycoonController.SetRevealRule / SetSfxVolume /
	SetSfxMuted, optimistic) and save on the server (SetSetting); the slider
	saves on release and plays a click at the new level. 620 wide; on a
	phone the list scrolls.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SettingsConfig = require(ReplicatedStorage.Shared.Config.SettingsConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local TycoonController = require(script.Parent.Parent.Controllers.TycoonController)
local UIKit = require(script.Parent.UIKit)

local SettingsPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(620, 560)
local ROW_HEIGHT = UITheme.MinTapSize + 12
local TIER_COLUMN = 110
local SEGMENT_GAP = 4
local SLIDER_LABEL_WIDTH = 64 -- "80%"
local SLIDER_TRACK_HEIGHT = 10
local SLIDER_KNOB = 28
local MUTE_SIZE = UITheme.MinTapSize

type Segment = { Button: TextButton, Label: TextLabel, LabelStroke: UIStroke }

local modal: UIKit.Modal
local list: ScrollingFrame
local segments: { [string]: { [string]: Segment } } = {}
local order = 0
local sliderTrack: Frame
local sliderFill: Frame
local sliderKnob: Frame
local sliderLabel: TextLabel
local muteButton: TextButton
local dragging = false

local function nextOrder(): number
	order += 1
	return order
end

local function refreshSound()
	local volume = TycoonController.GetSfxVolume()
	local muted = TycoonController.IsSfxMuted()
	sliderFill.Size = UDim2.fromScale(volume, 1)
	sliderKnob.Position = UDim2.fromScale(volume, 0.5)
	sliderLabel.Text = ("%d%%"):format(math.floor(volume * 100 + 0.5))
	sliderLabel.TextColor3 = if muted then Colors.Faint else Colors.Text
	sliderFill.BackgroundColor3 = if muted then Colors.Faint else Colors.ShieldTeal
	UIKit.SetButton(muteButton, {
		Style = if muted then "Red" else "Disabled",
		Text = if muted then "🔇" else "🔊",
	})
end

local function refresh()
	refreshSound()
	local rule = TycoonController.GetRevealRule()
	for tier, row in segments do
		for value, segment in row do
			local selected = rule[tier] == value
			-- Selected = the UPGRADES green with white text (UIKit).
			UIKit.SetSelectedFill(segment.Button, selected)
			segment.Label.TextColor3 = if selected then Colors.Text else Colors.Muted
			segment.LabelStroke.Enabled = selected
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
		UIKit.Stroke(button, 2)
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
		local labelStroke = UIKit.TextStroke(label, 1.5)
		labelStroke.Enabled = false
		UIKit.AttachPress(button)
		button.Activated:Connect(function()
			UIKit.SelectFeedback(button)
			TycoonController.SetRevealRule(tier, value)
			refresh()
		end)
		segments[tier][value] = { Button = button, Label = label, LabelStroke = labelStroke }
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

-- The volume at a screen x on the track (0..1).
local function volumeAt(x: number): number
	local left = sliderTrack.AbsolutePosition.X
	local width = math.max(sliderTrack.AbsoluteSize.X, 1)
	return math.clamp((x - left) / width, 0, 1)
end

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function soundRow()
	local z = list.ZIndex + 1
	local row = Instance.new("Frame")
	row.Name = "SoundRow"
	row.BackgroundColor3 = Colors.Panel2
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.LayoutOrder = nextOrder()
	row.ZIndex = z
	row.Parent = list
	UIKit.Corner(row, UITheme.Radius.Row)
	UIKit.Stroke(row, 2)
	UIKit.Label({
		Name = "Title",
		Text = "Volume",
		Font = Fonts.Display,
		TextSize = 17,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0, TIER_COLUMN - 12, 1, 0),
		ZIndex = z + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = row,
	})
	-- The whole strip is the drag target (>= 44 px tall); the track is the
	-- thin bar inside it.
	local hit = Instance.new("TextButton")
	hit.Name = "Slider"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.new(0, TIER_COLUMN, 0.5, -UITheme.MinTapSize / 2)
	hit.Size = UDim2.new(1, -(TIER_COLUMN + SLIDER_LABEL_WIDTH + MUTE_SIZE + 30), 0, UITheme.MinTapSize)
	hit.ZIndex = z + 1
	hit.Parent = row
	sliderTrack = Instance.new("Frame")
	sliderTrack.Name = "Track"
	sliderTrack.AnchorPoint = Vector2.new(0, 0.5)
	sliderTrack.Position = UDim2.new(0, SLIDER_KNOB / 2, 0.5, 0)
	sliderTrack.Size = UDim2.new(1, -SLIDER_KNOB, 0, SLIDER_TRACK_HEIGHT)
	sliderTrack.BackgroundColor3 = Colors.Ink
	sliderTrack.ZIndex = z + 2
	sliderTrack.Parent = hit
	UIKit.Corner(sliderTrack, 999)
	sliderFill = Instance.new("Frame")
	sliderFill.Name = "Fill"
	sliderFill.BackgroundColor3 = Colors.ShieldTeal
	sliderFill.BorderSizePixel = 0
	sliderFill.ZIndex = z + 3
	sliderFill.Parent = sliderTrack
	UIKit.Corner(sliderFill, 999)
	sliderKnob = Instance.new("Frame")
	sliderKnob.Name = "Knob"
	sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	sliderKnob.Size = UDim2.fromOffset(SLIDER_KNOB, SLIDER_KNOB)
	sliderKnob.BackgroundColor3 = Colors.White
	sliderKnob.ZIndex = z + 4
	sliderKnob.Parent = sliderTrack
	UIKit.Corner(sliderKnob, 999)
	UIKit.Stroke(sliderKnob, 3)
	sliderLabel = UIKit.Label({
		Name = "Percent",
		Font = Fonts.Display,
		TextSize = 17,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(MUTE_SIZE + 18), 0.5, 0),
		Size = UDim2.fromOffset(SLIDER_LABEL_WIDTH, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = z + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = row,
	})
	muteButton = UIKit.Button({
		Name = "Mute",
		Parent = row,
		Style = "Disabled",
		Text = "🔊",
		TextSize = 20,
		Size = UDim2.fromOffset(MUTE_SIZE, MUTE_SIZE),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, -2),
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z + 1,
		OnClick = function()
			TycoonController.SetSfxMuted(not TycoonController.IsSfxMuted())
			refreshSound()
			SoundKit.Play("Toast", nil)
		end,
	})

	hit.InputBegan:Connect(function(input: InputObject)
		if isPointer(input) then
			dragging = true
			TycoonController.SetSfxVolume(volumeAt(input.Position.X), false)
			refreshSound()
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local moved = input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		if dragging and moved then
			TycoonController.SetSfxVolume(volumeAt(input.Position.X), false)
			refreshSound()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if dragging and isPointer(input) then
			dragging = false
			-- Save on release, and let them hear the new level.
			TycoonController.SetSfxVolume(TycoonController.GetSfxVolume(), true)
			SoundKit.Play("Toast", nil)
		end
	end)
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

	-- Section: Sound effects.
	sectionTitle("Sound effects")
	note("Every sound in the game. Music isn't in yet.")
	soundRow()

	-- Section: Tutorial.
	sectionTitle("Tutorial")
	note("Walk through every system again, card by card. Nothing is reset.")
	local row = Instance.new("Frame")
	row.Name = "TutorialRow"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.LayoutOrder = nextOrder()
	row.ZIndex = list.ZIndex + 1
	row.Parent = list
	UIKit.Button({
		Name = "ReplayTutorial",
		Parent = row,
		Style = "Teal",
		Text = "▶ REPLAY TUTORIAL",
		TextSize = 18,
		Size = UDim2.fromOffset(240, UITheme.MinTapSize + 4),
		ZIndex = row.ZIndex,
		OnClick = function()
			RemoteEvents.TutorialAdvance:FireServer({ Replay = true })
			modal.Close()
		end,
	})
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
		if modal.IsOpen() and not dragging then
			refresh()
		end
	end)
end

return SettingsPanel
