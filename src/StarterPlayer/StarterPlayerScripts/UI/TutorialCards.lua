--!strict
--[[
	TutorialCards
	-------------
	The tutorial's small centred card and the "?" help slideshows (one
	UIKit.Modal, FitContent, placed by the card rule, dimming the game):
	a big icon, the title in the header, at most two short sentences, and a
	green OK (>= 44 px). A slideshow adds ◀ / ▶ and "2 / 5"; OK on the last
	card. Above every panel, so a "?" inside the Fuse panel opens over it.

	  ShowStep(card, okText?, onOk)   one card; OK (or ✕) calls onOk
	  ShowSlides(cards)               ◀ ▶ through them, OK closes
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local UIKit = require(script.Parent.UIKit)

local TutorialCards = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(460, 300)
local DISPLAY_ORDER = 165 -- over every panel (Rebirth 145, its confirm 160)
local ICON_HEIGHT = 64
local NAV_HEIGHT = 52
local ARROW_SIZE = 52

local modal: UIKit.Modal? = nil
local iconLabel: TextLabel
local bodyLabel: TextLabel
local prevHolder: Frame
local nextHolder: Frame
local okButton: TextButton
local counterLabel: TextLabel

local cards: { TutorialConfig.Card } = {}
local index = 1
local onOk: (() -> ())? = nil
local closingByOk = false

local function render()
	local m = modal :: UIKit.Modal
	local card = cards[index]
	if not card then
		return
	end
	m.Title.Text = card.Title
	iconLabel.Text = card.Icon
	bodyLabel.Text = card.Body
	local slideshow = #cards > 1
	local last = index >= #cards
	prevHolder.Visible = slideshow
	nextHolder.Visible = slideshow and not last
	counterLabel.Visible = slideshow
	counterLabel.Text = ("%d / %d"):format(index, #cards)
	local okHolder = okButton.Parent :: GuiObject
	okHolder.Visible = last
	UIKit.SetButton((prevHolder:FindFirstChildWhichIsA("TextButton") :: TextButton), {
		Style = if index > 1 then "Blue" else "Disabled",
	})
end

local function finish()
	local callback = onOk
	onOk = nil
	if callback then
		callback()
	end
end

local function build()
	local m = UIKit.Modal({
		Name = "TutorialCard",
		Title = "",
		DisplayOrder = DISPLAY_ORDER,
		MaxSize = MAX_SIZE,
		FitContent = true,
		HeaderTop = UITheme.Gradients.Teal.Bottom,
		-- ✕ or a tap outside counts as OK: the tutorial keeps going.
		OnClose = function()
			if not closingByOk then
				finish()
			end
		end,
	})
	modal = m
	local content = m.Content

	iconLabel = UIKit.Label({
		Name = "Icon",
		Font = Fonts.Display,
		TextSize = 56,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 0, 0, ICON_HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = content.ZIndex + 1,
		Parent = content,
	})
	bodyLabel = UIKit.Label({
		Name = "Body",
		Font = Fonts.BodyHeavy,
		TextSize = 20,
		Position = UDim2.fromOffset(8, ICON_HEIGHT + 4),
		Size = UDim2.new(1, -16, 1, -(ICON_HEIGHT + NAV_HEIGHT + 16 + UITheme.ShadowOffset)),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = content.ZIndex + 1,
		Parent = content,
	})
	UIKit.FitText(bodyLabel, 20, 13)

	local nav = Instance.new("Frame")
	nav.Name = "Nav"
	nav.BackgroundTransparency = 1
	nav.AnchorPoint = Vector2.new(0, 1)
	nav.Position = UDim2.new(0, 0, 1, -UITheme.ShadowOffset)
	nav.Size = UDim2.new(1, 0, 0, NAV_HEIGHT)
	nav.ZIndex = content.ZIndex + 1
	nav.Parent = content

	local _, prev = UIKit.Button({
		Name = "Prev",
		Parent = nav,
		Style = "Blue",
		Text = "◀",
		TextSize = 22,
		Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE),
		ZIndex = nav.ZIndex,
		OnClick = function()
			if index > 1 then
				index -= 1
				render()
			end
		end,
	})
	prevHolder = prev
	counterLabel = UIKit.Label({
		Name = "Counter",
		Font = Fonts.BodyHeavy,
		TextSize = 16,
		TextColor3 = Colors.Muted,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(80, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = nav.ZIndex,
		Parent = nav,
	})
	local _, nextButtonHolder = UIKit.Button({
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
			if index < #cards then
				index += 1
				render()
			end
		end,
	})
	nextHolder = nextButtonHolder
	okButton = UIKit.Button({
		Name = "Ok",
		Parent = nav,
		Style = "Green",
		Text = "OK",
		TextSize = 24,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(150, ARROW_SIZE),
		ZIndex = nav.ZIndex,
		OnClick = function()
			closingByOk = true
			m.Close()
			closingByOk = false
			finish()
		end,
	})
end

local function show(newCards: { TutorialConfig.Card }, okText: string?, callback: (() -> ())?)
	if not modal then
		build()
	end
	cards = newCards
	index = 1
	onOk = callback
	UIKit.SetButton(okButton, { Text = okText or "OK" })
	render()
	local m = modal :: UIKit.Modal
	if not m.IsOpen() then
		m.Open()
	end
end

-- One tutorial card; OK (or ✕) calls `callback`.
function TutorialCards.ShowStep(card: TutorialConfig.Card, okText: string?, callback: () -> ())
	show({ card }, okText, callback)
end

-- A "?" topic: ◀ ▶ through its cards, OK closes.
function TutorialCards.ShowSlides(topicCards: { TutorialConfig.Card })
	show(topicCards, nil, nil)
end

function TutorialCards.ShowTopic(topic: string)
	local topicCards = TutorialConfig.Help[topic]
	if topicCards then
		TutorialCards.ShowSlides(topicCards)
	end
end

function TutorialCards.Close()
	local m = modal
	if m and m.IsOpen() then
		closingByOk = true
		m.Close()
		closingByOk = false
	end
	onOk = nil
end

function TutorialCards.IsOpen(): boolean
	local m = modal
	return m ~= nil and m.IsOpen()
end

function TutorialCards.Init()
	build()
end

return TutorialCards
