--!strict
--[[
	ComeBackCard
	------------
	The "come back tomorrow" card (ComeBackController decides when; this only
	draws a RetentionConfig.PlanComeBack plan). A UIKit.Modal (FitContent),
	centred in the card band like every card:

	  📅  TOMORROW · DAY 2
	      ×2 income for 15 min
	      Then Day 3: 3 free pulls · Day 7: 1 Epic+ item
	  💤  WHILE YOU'RE AWAY
	      Your lab earns up to $1.04M
	      25% of your income, for up to 4 h
	  🎁  TODAY'S REWARD IS READY       (or: EVERY VISIT · 6 playtime gifts)
	      Day 1 · 10 min of income
	  [ CLAIM TODAY'S REWARD ]  /  [ GOT IT ]

	Every number is the real one (the daily ladder, the server's offline
	number, GiftConfig's count). No countdown, no pressure copy.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyConfig = require(ReplicatedStorage.Shared.Config.DailyConfig)
local GiftConfig = require(ReplicatedStorage.Shared.Config.GiftConfig)
local OfflineConfig = require(ReplicatedStorage.Shared.Config.OfflineConfig)
local RetentionConfig = require(ReplicatedStorage.Shared.Config.RetentionConfig)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.UIKit)

local ComeBackCard = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local CARD_SIZE = Vector2.new(560, 392)
local DISPLAY_ORDER = 125 -- the daily card's layer (under Results, 130)
local ROW_HEIGHT = 78
local ROW_GAP = 8
local ICON_WIDTH = 56

export type Handlers = {
	OnClaimToday: () -> (), -- the button while today's reward waits: close, open the daily card
}

type Row = { Icon: TextLabel, Title: TextLabel, Main: TextLabel, Sub: TextLabel }

local modal: UIKit.Modal? = nil
local handlers: Handlers? = nil
local rows: { Row } = {}
local actionButton: TextButton
local todayWaiting = false

local ROW_GRADIENT: { { any } } = { { 0, Colors.Panel3 }, { 1, Colors.Panel2 } }

local function buildRow(content: Frame, index: number, z: number): Row
	local body = UIKit.Panel({
		Name = ("Row%d"):format(index),
		Parent = content,
		Position = UDim2.fromOffset(0, (index - 1) * (ROW_HEIGHT + ROW_GAP)),
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT - UITheme.SmallShadowOffset),
		Gradient = ROW_GRADIENT,
		Radius = 14,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z,
	})
	local inner = body.ZIndex + 1
	local icon = UIKit.Label({
		Name = "Icon",
		TextSize = 32,
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.new(0, ICON_WIDTH, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = inner,
		Parent = body,
	})
	local function line(name: string, y: number, height: number, font: any, size: number, color: Color3): TextLabel
		local label = UIKit.Label({
			Name = name,
			RichText = true,
			Font = font,
			TextSize = size,
			TextColor3 = color,
			TextScaled = true,
			Position = UDim2.fromOffset(ICON_WIDTH + 10, y),
			Size = UDim2.new(1, -(ICON_WIDTH + 20), 0, height),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = inner,
			Parent = body,
		})
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = size
		limit.MinTextSize = 10
		limit.Parent = label
		return label
	end
	return {
		Icon = icon,
		Title = line("Title", 6, 18, Fonts.BodyHeavy, 14, Colors.Muted),
		Main = line("Main", 25, 24, Fonts.Display, 20, Colors.Text),
		Sub = line("Sub", 50, 16, Fonts.Body, 13, Colors.Faint),
	}
end

local function build(): UIKit.Modal
	local created = UIKit.Modal({
		Name = "ComeBack",
		Title = "SEE YOU TOMORROW!",
		DisplayOrder = DISPLAY_ORDER,
		MaxSize = CARD_SIZE,
		FitContent = true,
		HeaderTop = Colors.DailyTop,
	})
	created.Subtitle.Text = "Your lab keeps going while you're gone"
	created.Subtitle.Visible = true
	local content = created.Content
	local z = content.ZIndex + 1
	rows = {}
	for index = 1, 3 do
		table.insert(rows, buildRow(content, index, z))
	end
	actionButton = UIKit.Button({
		Name = "Action",
		Parent = content,
		Style = "Green",
		Text = "GOT IT",
		TextSize = 22,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.fromOffset(300, 54),
		ZIndex = z,
		OnClick = function()
			local current = handlers
			created.Close()
			if todayWaiting and current then
				current.OnClaimToday()
			end
		end,
	})
	modal = created
	return created
end

local function setRow(row: Row, icon: string, title: string, main: string, sub: string)
	row.Icon.Text = icon
	row.Title.Text = title
	row.Main.Text = main
	row.Sub.Text = sub
end

-- The text of each row for `plan` (pure; /selftest reads it).
function ComeBackCard.Lines(plan: RetentionConfig.ComeBackPlan): { { string } }
	local later: { string } = {}
	for _, entry in plan.Later do
		table.insert(later, ("Day %d: %s"):format(entry.Day, RewardConfig.GetTitle(entry.Reward)))
	end
	local lines: { { string } } = {
		{
			"📅",
			("TOMORROW · DAY %d"):format(plan.TomorrowDay),
			RewardConfig.GetTitle(plan.Tomorrow),
			if #later > 0 then "Then " .. table.concat(later, " · ") else "A new reward every day",
		},
	}
	if plan.OfflineMax > 0 then
		table.insert(lines, {
			"💤",
			"WHILE YOU'RE AWAY",
			"Your lab earns up to " .. UIKit.Colored(NumberFormat.Money(plan.OfflineMax), Colors.Cash),
			("%d%% of your income, for up to %s"):format(
				math.floor(OfflineConfig.Rate * 100 + 0.5),
				RewardConfig.FormatDuration(OfflineConfig.MaxSeconds)
			),
		})
	else
		table.insert(lines, {
			"💤",
			"WHILE YOU'RE AWAY",
			"Your lab keeps earning",
			("%d%% of your income, for up to %s"):format(
				math.floor(OfflineConfig.Rate * 100 + 0.5),
				RewardConfig.FormatDuration(OfflineConfig.MaxSeconds)
			),
		})
	end
	if plan.TodayWaiting then
		table.insert(lines, {
			"🎁",
			"TODAY'S REWARD IS READY",
			("Day %d · %s"):format(plan.TodayDay, RewardConfig.GetTitle(DailyConfig.GetReward(plan.TodayDay))),
			"Claim it today, then tomorrow's is next",
		})
	else
		table.insert(lines, {
			"🎁",
			"EVERY VISIT",
			("%d playtime gifts"):format(#GiftConfig.Gifts),
			"They open as you play, fresh each time you join",
		})
	end
	return lines
end

-- The button's text for `plan`.
function ComeBackCard.ActionText(plan: RetentionConfig.ComeBackPlan): string
	return if plan.TodayWaiting then "CLAIM TODAY'S REWARD" else "GOT IT"
end

function ComeBackCard.Init(newHandlers: Handlers)
	handlers = newHandlers
end

function ComeBackCard.IsOpen(): boolean
	return modal ~= nil and (modal :: UIKit.Modal).IsOpen()
end

function ComeBackCard.Open(plan: RetentionConfig.ComeBackPlan)
	local card = modal or build()
	todayWaiting = plan.TodayWaiting
	for index, texts in ComeBackCard.Lines(plan) do
		local row = rows[index]
		if row then
			setRow(row, texts[1], texts[2], texts[3], texts[4])
		end
	end
	UIKit.SetButton(actionButton, { Text = ComeBackCard.ActionText(plan), Style = "Green" })
	card.Open()
end

function ComeBackCard.Close()
	local current = modal
	if current then
		current.Close()
	end
end

-- /selftest: the open card's row texts (Main lines) and button, or nil.
function ComeBackCard.GetShown(): { Main: { string }, Button: string }?
	if not ComeBackCard.IsOpen() then
		return nil
	end
	local mains: { string } = {}
	for _, row in rows do
		table.insert(mains, row.Main.Text)
	end
	return { Main = mains, Button = actionButton.Text }
end

-- /selftest: every row label's text fits its box (TextFits) while open.
function ComeBackCard.GetLabels(): { TextLabel }
	local labels: { TextLabel } = {}
	for _, row in rows do
		table.insert(labels, row.Title)
		table.insert(labels, row.Main)
		table.insert(labels, row.Sub)
	end
	return labels
end

return ComeBackCard
