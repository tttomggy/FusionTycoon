--!strict
--[[
	GoalTracker
	-----------
	The NEXT GOAL card under the Roblox top bar (desktop) / the one-line goal
	pill (phone), with the loop strip (🎰 → 🔮 → 💰 → ⬆️  🏃) and the goal's
	next-action lines (GoalSteps / LoopCoach). HudController builds it, places
	it in the left column and calls Refresh / SetGoal; this module owns
	everything inside the card.

	It lives outside HudController because Luau allows 200 locals alive in one
	function and a module's top level is one function: with the tracker in
	HudController (1bc04bb) the module did not compile ("Out of local
	registers") and took most of the client down. tools/compile_check.py
	catches that.
]]
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoalConfig = require(ReplicatedStorage.Shared.Config.GoalConfig)
local LoopCoach = require(ReplicatedStorage.Shared.Config.LoopCoach)
local GoalSteps = require(ReplicatedStorage.Shared.Modules.GoalSteps)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TycoonController = require(script.Parent.Parent.Controllers.TycoonController)
local UIKit = require(script.Parent.UIKit)

local GoalTracker = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

-- The card's desktop width (the quest tracker under it is as wide).
GoalTracker.DesktopWidth = 260

-- Card sizes (design px, before the phone UIScale). HudController places the card.
local SIZES = {
	Desktop = { Width = GoalTracker.DesktopWidth, BarHeight = 14 },
	-- A one-line pill as wide as the slim cash panel.
	Phone = { Width = 232, BarHeight = 10 },
}

local goalHolder: Frame
local goalBody: Frame
local goalRewardLabel: TextLabel
local goalTextLabel: TextLabel
local goalBar: Frame
local goalCountLabel: TextLabel
-- An "own a tier" goal's next action (GoalSteps) and its small odds hint.
local goalStepLabel: TextLabel
local goalHintLabel: TextLabel
local goalHasStep = false
local goalHasHint = false
local goalPathButton: TextButton? = nil
-- The loop strip (🎰 → 🔮 → 💰 → ⬆️  🏃): one cell per LoopCoach step, the
-- coach's current one lit. Shown after the tutorial only (a coach is there).
type StripCell = { Cell: TextButton, Chip: Frame, Icon: TextLabel, Pulse: Tween? }
local goalStrip: Frame
local goalStripTrack: Frame
local stripCells: { [string]: StripCell } = {}
local stripArrows: { TextLabel } = {}
local stripShown = false
local goalPadding: UIPadding
local goalHeader: Frame
-- Phone: NEXT GOAL is one line, the goal text and its reward (no caption,
-- bar or count); the full card is the desktop's.
local goalPhoneLine: Frame
local goalPhoneText: TextLabel
local goalPhoneReward: TextLabel
local goalPhoneMode = false
local goalHasCount = false
local GOAL_PHONE_LINE_HEIGHT = 22
local GOAL_PHONE_REWARD_WIDTH = 64
-- The strip: a row of icon chips (visual height) over >= 44 px tap cells, so
-- the card grows by at most STRIP_GROWTH: the row and the list gap, less what
-- the card's vertical padding gives back. The 44 px tap rule wins over the old
-- "+20 px" spec (five >= 44 px cells can't add only 20), hence 62 / 40.
local STRIP_CELL = UITheme.MinTapSize
local STRIP_CHIP_WIDTH = 30
local STRIP_HEIGHT = { Desktop = 22, Phone = 18 }
local STRIP_PAD_TRIM = { Desktop = 4, Phone = 2 } -- off each of the card's top / bottom padding
local STRIP_ICON_SIZE = { Desktop = 15, Phone = 12 }
local STRIP_PULSE_SCALE = 1.08
local STRIP_PULSE_SECONDS = 0.7
local STRIP_UNLIT_TRANSPARENCY = 0.4
local STRIP_GROWTH = { Desktop = 62, Phone = 40 } -- px the strip may add to the card (/selftest)

--[[ Goal tracker ---------------------------------------------------------- ]]

local function setStripLit(step: string?)
	for name, cell in stripCells do
		local lit = name == step
		UIKit.SetSelectedFill(cell.Chip, lit, Colors.Panel3)
		cell.Icon.TextTransparency = if lit then 0 else STRIP_UNLIT_TRANSPARENCY
		local pulse = cell.Chip:FindFirstChild("LitPulse") :: UIScale?
		if lit and not pulse then
			local scale = Instance.new("UIScale")
			scale.Name = "LitPulse"
			scale.Parent = cell.Chip
			local tween = TweenService:Create(
				scale,
				TweenInfo.new(STRIP_PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = STRIP_PULSE_SCALE }
			)
			cell.Pulse = tween
			tween:Play()
		elseif not lit and pulse then
			local running = cell.Pulse
			if running then
				running:Cancel()
				cell.Pulse = nil
			end
			pulse:Destroy()
		end
	end
end

-- Positions the strip for the layout: five >= 44 px cells across the card's
-- full width (the track reaches past the card's side padding), the main road
-- first, the side road at the right end.
local function layoutStrip(isPhone: boolean)
	local layout = if isPhone then SIZES.Phone else SIZES.Desktop
	local height = if isPhone then STRIP_HEIGHT.Phone else STRIP_HEIGHT.Desktop
	local width = layout.Width
	goalStrip.Size = UDim2.new(1, 0, 0, height)
	goalStripTrack.Size = UDim2.fromOffset(width, height)
	local function place(step: string, x: number)
		local cell = stripCells[step]
		cell.Cell.Position = UDim2.new(0, x, 0.5, 0)
		cell.Chip.Size = UDim2.fromOffset(STRIP_CHIP_WIDTH, height)
		cell.Icon.TextSize = if isPhone then STRIP_ICON_SIZE.Phone else STRIP_ICON_SIZE.Desktop
	end
	for index, step in LoopCoach.Road do
		place(step, (index - 1) * STRIP_CELL)
	end
	place(LoopCoach.SideRoad, width - STRIP_CELL)
	for index, arrow in stripArrows do
		arrow.Position = UDim2.new(0, index * STRIP_CELL, 0.5, 0)
		arrow.Size = UDim2.fromOffset(STRIP_CELL - STRIP_CHIP_WIDTH, height)
	end
end

local function buildLoopStrip(body: Frame)
	local z = body.ZIndex + 1
	local row = Instance.new("Frame")
	row.Name = "LoopStrip"
	row.BackgroundTransparency = 1
	row.LayoutOrder = -1
	row.Visible = false
	row.ZIndex = z
	row.Parent = body
	goalStrip = row
	-- The track is as wide as the card (not the padded content): five 44 px
	-- cells need 220 px, the phone's padded content is 212.
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundTransparency = 1
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.fromScale(0.5, 0)
	track.ZIndex = z
	track.Parent = row
	goalStripTrack = track

	local steps: { string } = table.clone(LoopCoach.Road)
	table.insert(steps, LoopCoach.SideRoad)
	for _, step in steps do
		local cell = Instance.new("TextButton")
		cell.Name = step
		cell.Text = ""
		cell.AutoButtonColor = false
		cell.BackgroundTransparency = 1
		cell.AnchorPoint = Vector2.new(0, 0.5)
		cell.Size = UDim2.fromOffset(STRIP_CELL, STRIP_CELL)
		cell.ZIndex = z + 1
		cell.Parent = track
		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Position = UDim2.fromScale(0.5, 0.5)
		chip.BorderSizePixel = 0
		chip.ZIndex = z + 2
		chip.Parent = cell
		UIKit.Corner(chip, 8)
		UIKit.Stroke(chip, 1.5)
		local icon = UIKit.Label({
			Name = "Icon",
			Text = LoopCoach.Icons[step],
			Font = Fonts.Body,
			TextSize = STRIP_ICON_SIZE.Desktop,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 3,
			Parent = chip,
		})
		stripCells[step] = { Cell = cell, Chip = chip, Icon = icon, Pulse = nil }
		-- One line on what the step is (the same slot every banner uses).
		cell.Activated:Connect(function()
			UIKit.SelectFeedback(chip)
			local announcements = require(script.Parent.Parent.Controllers.AnnouncementController) :: any
			announcements.ShowLine(LoopCoach.Explain[step], "LoopStrip")
		end)
	end
	-- The arrows between the main road's icons sit in the chips' side margins,
	-- so they never cover a tap cell's chip (and, as labels, take no taps).
	for index = 1, #LoopCoach.Road - 1 do
		local arrow = UIKit.Label({
			Name = "Arrow" .. index,
			Text = "→",
			Font = Fonts.BodyHeavy,
			TextSize = 12,
			TextColor3 = Colors.Muted,
			AnchorPoint = Vector2.new(0.5, 0.5),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 4,
			Parent = track,
		})
		table.insert(stripArrows, arrow)
	end
	setStripLit(nil)
	layoutStrip(false)
end

-- Builds the card under `parent` at `position` (the desktop spot; HudController
-- re-places it). Hidden until the server sends a goal. Returns the card's holder.
function GoalTracker.Build(parent: ScreenGui, position: UDim2): Frame
	local body, holder = UIKit.Panel({
		Name = "GoalTracker",
		Parent = parent,
		Size = UDim2.fromOffset(SIZES.Desktop.Width, 0),
		Position = position,
		AutomaticSize = Enum.AutomaticSize.Y,
		Color = Colors.Panel,
	})
	goalHolder = holder
	goalBody = body
	-- Hidden until the server sends a goal (and after the last one).
	holder.Visible = false

	-- 👣: the lit path to the goal (TutorialPath), on by default for the
	-- first sessions (TycoonController.IsGoalPathOn); beside the card.
	local pathButton = UIKit.Button({
		Name = "GoalPathToggle",
		Parent = holder,
		Style = "Green",
		Text = "👣",
		TextSize = 22,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(1, 6, 0, 0),
		Size = UDim2.fromOffset(UITheme.MinTapSize, UITheme.MinTapSize),
		ShadowOffset = UITheme.SmallShadowOffset,
		OnClick = function()
			TycoonController.SetGoalPath(not TycoonController.IsGoalPathOn())
		end,
	})
	goalPathButton = pathButton

	goalPadding = UIKit.Padding(body, 12, 14, 12, 14)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = body
	buildLoopStrip(body)

	local headerRow = Instance.new("Frame")
	goalHeader = headerRow
	headerRow.Name = "Header"
	headerRow.BackgroundTransparency = 1
	headerRow.Size = UDim2.new(1, 0, 0, 16)
	headerRow.LayoutOrder = 1
	headerRow.ZIndex = body.ZIndex + 1
	headerRow.Parent = body

	UIKit.Label({
		Name = "Caption",
		Text = "NEXT GOAL",
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = Colors.Goal,
		Size = UDim2.fromScale(0.6, 1),
		ZIndex = headerRow.ZIndex,
		Parent = headerRow,
	})
	goalRewardLabel = UIKit.Label({
		Name = "Reward",
		Font = Fonts.Body,
		TextSize = 12,
		TextColor3 = Colors.Muted,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.4, 1),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = headerRow.ZIndex,
		Parent = headerRow,
	})

	goalTextLabel = UIKit.Label({
		Name = "GoalText",
		Font = Fonts.Body,
		TextSize = 16,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = 2,
		ZIndex = body.ZIndex + 1,
		Parent = body,
	})

	goalBar = UIKit.ProgressBar({
		Name = "Progress",
		Parent = body,
		Size = UDim2.new(1, 0, 0, SIZES.Desktop.BarHeight),
		Fill = UITheme.Gradients.Gold,
		LayoutOrder = 5,
		ZIndex = body.ZIndex + 1,
	})

	goalCountLabel = UIKit.Label({
		Name = "Count",
		Font = Fonts.Body,
		TextSize = 12,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 6,
		ZIndex = body.ZIndex + 1,
		Parent = body,
	})

	-- The next action under the goal text, and (while more orbs help) the
	-- odds hint under that. Wrapped, so a long line grows the card and never clips.
	goalStepLabel = UIKit.Label({
		Name = "Step",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		RichText = true,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = 3,
		Visible = false,
		ZIndex = body.ZIndex + 1,
		Parent = body,
	})
	goalHintLabel = UIKit.Label({
		Name = "Hint",
		Font = Fonts.Body,
		TextSize = 12,
		TextColor3 = Colors.Muted,
		RichText = true,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = 4,
		Visible = false,
		ZIndex = body.ZIndex + 1,
		Parent = body,
	})

	-- The phone's one line: the goal on the left (cut with "…" when long), its
	-- reward on the right. Hidden on desktop.
	goalPhoneLine = Instance.new("Frame")
	goalPhoneLine.Name = "PhoneLine"
	goalPhoneLine.BackgroundTransparency = 1
	goalPhoneLine.Size = UDim2.new(1, 0, 0, GOAL_PHONE_LINE_HEIGHT)
	goalPhoneLine.LayoutOrder = 0
	goalPhoneLine.Visible = false
	goalPhoneLine.ZIndex = body.ZIndex + 1
	goalPhoneLine.Parent = body
	goalPhoneText = UIKit.Label({
		Name = "Text",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		Size = UDim2.new(1, -GOAL_PHONE_REWARD_WIDTH, 1, 0),
		ZIndex = goalPhoneLine.ZIndex,
		Parent = goalPhoneLine,
	})
	goalPhoneText.TextTruncate = Enum.TextTruncate.AtEnd
	goalPhoneReward = UIKit.Label({
		Name = "Reward",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = Colors.GoldLabel,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, GOAL_PHONE_REWARD_WIDTH, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = goalPhoneLine.ZIndex,
		Parent = goalPhoneLine,
	})
	return holder
end

-- Phone: the one-line pill; desktop: the full card.
function GoalTracker.ApplyLayout(isPhone: boolean)
	goalPhoneMode = isPhone
	goalHeader.Visible = not isPhone
	goalTextLabel.Visible = not isPhone
	goalBar.Visible = not isPhone
	goalCountLabel.Visible = goalHasCount and not isPhone
	-- The action stays on the phone pill too, a size smaller.
	goalStepLabel.TextSize = if isPhone then 12 else 14
	goalHintLabel.TextSize = 12
	goalStepLabel.Visible = goalHasStep
	goalHintLabel.Visible = goalHasHint
	goalPhoneLine.Visible = isPhone
	layoutStrip(isPhone)
	local vertical, horizontal = if isPhone then 6 else 12, if isPhone then 10 else 14
	if stripShown then
		-- The strip's row gives the card some vertical padding back (growth <= STRIP_GROWTH net).
		vertical -= if isPhone then STRIP_PAD_TRIM.Phone else STRIP_PAD_TRIM.Desktop
	end
	goalPadding.PaddingTop = UDim.new(0, vertical)
	goalPadding.PaddingBottom = UDim.new(0, vertical)
	goalPadding.PaddingLeft = UDim.new(0, horizontal)
	goalPadding.PaddingRight = UDim.new(0, horizontal)
end

-- Card width and progress-bar height for the layout (HudController's applyLayout).
function GoalTracker.ApplySizing(isPhone: boolean)
	local size = if isPhone then SIZES.Phone else SIZES.Desktop
	goalHolder.Size = UDim2.fromOffset(size.Width, 0)
	goalRewardLabel.Visible = not isPhone
	goalBar.Size = UDim2.new(1, 0, 0, size.BarHeight)
end

-- /selftest's long sample title on the phone pill.
function GoalTracker.SetPhoneText(text: string)
	goalPhoneText.Text = text
end

export type GoalView = {
	Text: string,
	Reward: number,
	Current: number,
	Target: number,
	Unit: string?, -- e.g. "Rare"; nil hides the count line
	Lines: GoalSteps.Lines?, -- an "own a tier" goal's next action (RichText); nil hides both lines
	StripLit: string?, -- the loop strip icon to light (LoopCoach step); nil hides the strip
}

-- The goal on the tracker now (/selftest puts it back after its samples).
local lastGoalView: GoalView? = nil

function GoalTracker.GetGoal(): GoalView?
	return lastGoalView
end

-- Shows a goal on the tracker, or hides the tracker when `goal` is nil.
function GoalTracker.SetGoal(goal: GoalView?)
	lastGoalView = goal
	if not goal then
		goalHolder.Visible = false
		return
	end
	goalHolder.Visible = true
	goalRewardLabel.Text = "+" .. NumberFormat.Money(goal.Reward)
	goalTextLabel.Text = goal.Text
	goalPhoneText.Text = goal.Text
	goalPhoneReward.Text = goalRewardLabel.Text
	UIKit.SetProgress(goalBar, if goal.Target > 0 then goal.Current / goal.Target else 0, true)
	goalHasCount = goal.Unit ~= nil
	if goal.Unit then
		goalCountLabel.Text = ("%s / %s %s"):format(
			NumberFormat.Short(math.min(goal.Current, goal.Target)),
			NumberFormat.Short(goal.Target),
			goal.Unit
		)
	end
	goalCountLabel.Visible = goalHasCount and not goalPhoneMode
	local lines = goal.Lines
	goalHasStep = lines ~= nil
	goalHasHint = lines ~= nil and lines.Hint ~= nil
	goalStepLabel.Text = if lines then lines.Line else ""
	goalHintLabel.Text = if lines and lines.Hint then lines.Hint else ""
	goalStepLabel.Visible = goalHasStep
	goalHintLabel.Visible = goalHasHint
	local showStrip = goal.StripLit ~= nil
	goalStrip.Visible = showStrip
	if showStrip ~= stripShown then
		stripShown = showStrip
		GoalTracker.ApplyLayout(goalPhoneMode)
	end
	setStripLit(goal.StripLit)
end

-- Completion flourish: flash the border Goal-coloured and pop the panel.
function GoalTracker.Flash()
	local stroke = goalBody:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Colors.Goal
		TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Color = Colors.Ink }):Play()
	end
	UIKit.PopIn(goalHolder)
end

--[[ Refresh -------------------------------------------------------------- ]]

function GoalTracker.Refresh()
	local index = TycoonController.GetGoalIndex()
	local goal = index and GoalConfig.GetGoal(index)
	local progress = TycoonController.GetGoalProgress()
	if not goal or not progress then
		-- Before the first snapshot, and for good after the last goal.
		GoalTracker.SetGoal(nil)
		return
	end
	-- The goal's own next action, or the coach's when the goal can't be done
	-- right now (a goal keeps its title either way).
	local coach = progress.Coach
	local lines: GoalSteps.Lines? = nil
	if coach and coach.Takes then
		lines = { Line = LoopCoach.Format(coach) }
	elseif progress.Step then
		lines = GoalSteps.Format(progress.Step)
	end
	GoalTracker.SetGoal({
		Text = goal.Text,
		Reward = goal.Reward,
		Current = progress.Current,
		Target = progress.Target,
		Unit = goal.Unit,
		Lines = lines,
		StripLit = if coach then coach.Lit else nil,
	})
end

function GoalTracker.RefreshPathButton()
	local button = goalPathButton
	if button then
		local on = TycoonController.IsGoalPathOn()
		UIKit.SetButton(button, { Style = if on then "Green" else "Disabled", TextColor3 = if on then Colors.Text else Colors.Muted })
	end
end

--[[ /selftest ------------------------------------------------------------- ]]

-- What the tests need from HudController: the HUD's ScreenGui, whether the
-- phone layout is up, the hold on the refresh ticks, and a re-layout.
export type TestContext = {
	ScreenGui: ScreenGui,
	Phone: boolean,
	Hold: (held: boolean) -> (),
	Relayout: () -> (),
}

-- The tallest goal card: a long title, the action line and the odds hint
-- (a 3-orb Legendary fuse with more orbs to gain).
function GoalTracker.SelfTestView(): GoalView
	return {
		Text = "Fuse Legendaries into a Mythic",
		Reward = 1.25e6,
		Current = 1,
		Target = 2,
		Unit = "Legendary",
		Lines = GoalSteps.Format({
			Kind = "Fuse",
			Tier = "Legendary",
			Owned = 3,
			Count = 3,
			Chance = 0.27,
			BestChance = 0.45,
			Target = GoalSteps.Targets.Fuse,
		}),
		StripLit = "Fuse",
	}
end

-- /selftest: the goal card with all three lines up (title, action, odds hint)
-- shows every line without clipping, stays on screen, and keeps the 👣
-- toggle a full-size tap target. The caller forces the layout first.
function GoalTracker.SelfTestGoalLines(scaleName: string, ctx: TestContext): { string }
	local goalWas = goalHolder.Visible
	local previous = lastGoalView
	ctx.Hold(true)
	goalHolder.Visible = true
	GoalTracker.SetGoal(GoalTracker.SelfTestView())
	ctx.Relayout()
	task.wait(0.4)
	local problems: { string } = {}
	local labels: { [string]: TextLabel } = { Step = goalStepLabel, Hint = goalHintLabel }
	if ctx.Phone then
		labels.Title = goalPhoneText
	else
		labels.Title = goalTextLabel
	end
	for name, label in labels do
		if not label.Visible then
			table.insert(problems, name .. " hidden")
		elseif name ~= "Title" or not ctx.Phone then
			-- (The phone's title line truncates with "…" on purpose.)
			if not label.TextFits then
				table.insert(problems, name .. " clipped")
			end
		end
	end
	local screen = ctx.ScreenGui.AbsoluteSize
	local position, size = goalHolder.AbsolutePosition, goalHolder.AbsoluteSize
	if position.X + size.X > screen.X + 1 or position.Y + size.Y > screen.Y + 1 then
		table.insert(problems, ("card ends at %.0f x %.0f on a %.0f x %.0f screen"):format(position.X + size.X, position.Y + size.Y, screen.X, screen.Y))
	end
	local button = goalPathButton
	local tap = if button then button.AbsoluteSize / UIKit.EffectiveScale(button) else Vector2.zero
	if not button or tap.X < UITheme.MinTapSize - 1 or tap.Y < UITheme.MinTapSize - 1 then
		table.insert(problems, ("👣 toggle is %.0f x %.0f"):format(tap.X, tap.Y))
	end
	GoalTracker.SetGoal(previous)
	-- SetGoal(nil) hides the card; put the caller's visibility back.
	goalHolder.Visible = goalWas
	ctx.Hold(false)
	ctx.Relayout()
	return {
		if #problems == 0
			then ("PASS hud goal tracker shows 3 lines (%s, card %.0f x %.0f px, 👣 %.0f px)"):format(scaleName, size.X, size.Y, tap.X)
			else ("FAIL hud goal tracker 3 lines (%s): %s"):format(scaleName, table.concat(problems, "; ")),
	}
end

-- /selftest: the loop strip (the tracker's icon row). Each step lights only
-- its own chip; the five cells are >= 44 px, inside the card and clear of
-- each other; the card grows by at most STRIP_GROWTH px (per layout) for the strip. The
-- caller forces the layout first.
function GoalTracker.SelfTestLoopStrip(scaleName: string, ctx: TestContext): { string }
	local goalWas = goalHolder.Visible
	local previous = lastGoalView
	ctx.Hold(true)
	goalHolder.Visible = true
	local view = GoalTracker.SelfTestView()
	view.StripLit = nil
	GoalTracker.SetGoal(view)
	ctx.Relayout()
	task.wait(0.4)
	local function cardHeight(): number
		return goalHolder.AbsoluteSize.Y / UIKit.EffectiveScale(goalHolder)
	end
	local without = cardHeight()
	view.StripLit = "Fuse"
	GoalTracker.SetGoal(view)
	task.wait(0.4)
	local with = cardHeight()
	local problems: { string } = {}
	if not goalStrip.Visible then
		table.insert(problems, "strip hidden after the tutorial")
	end
	local growthLimit = if ctx.Phone then STRIP_GROWTH.Phone else STRIP_GROWTH.Desktop
	if with - without > growthLimit + 0.5 then
		table.insert(problems, ("card grew %.1f px for the strip (max %d)"):format(with - without, growthLimit))
	end

	-- Every step lights its own chip and no other.
	local steps: { string } = table.clone(LoopCoach.Road)
	table.insert(steps, LoopCoach.SideRoad)
	for _, lit in steps do
		view.StripLit = lit
		GoalTracker.SetGoal(view)
		for name, cell in stripCells do
			local fill = cell.Chip:FindFirstChild("SelectFill") :: UIGradient?
			local on = fill ~= nil and fill.Enabled
			if on ~= (name == lit) then
				table.insert(problems, ("lit %s: the %s chip is %s"):format(lit, name, if on then "lit" else "dark"))
			end
		end
	end

	-- Taps: >= 44 px, inside the card, never overlapping a neighbour.
	local scale = UIKit.EffectiveScale(goalHolder)
	local card = goalHolder.AbsolutePosition
	local cardSize = goalHolder.AbsoluteSize
	local smallest = math.huge
	for index, a in steps do
		local ca = stripCells[a].Cell
		local size = ca.AbsoluteSize / scale
		smallest = math.min(smallest, size.X, size.Y)
		if ca.AbsolutePosition.X < card.X - 1 or ca.AbsolutePosition.X + ca.AbsoluteSize.X > card.X + cardSize.X + 1 then
			table.insert(problems, a .. " cell leaves the card")
		end
		for other = index + 1, #steps do
			local cb = stripCells[steps[other]].Cell
			local overlapX = math.min(ca.AbsolutePosition.X + ca.AbsoluteSize.X, cb.AbsolutePosition.X + cb.AbsoluteSize.X) - math.max(ca.AbsolutePosition.X, cb.AbsolutePosition.X)
			if overlapX > 1 then
				table.insert(problems, ("%s / %s taps overlap by %.0f px"):format(a, steps[other], overlapX))
			end
		end
	end
	if smallest < UITheme.MinTapSize - 1 then
		table.insert(problems, ("a tap cell is %.0f px"):format(smallest))
	end

	GoalTracker.SetGoal(previous)
	goalHolder.Visible = goalWas
	ctx.Hold(false)
	ctx.Relayout()
	return {
		if #problems == 0
			then ("PASS hud loop strip (%s: 5 cells >= %.0f px, card +%.0f px for the strip, each step lights its own chip)"):format(scaleName, smallest, with - without)
			else ("FAIL hud loop strip (%s): %s"):format(scaleName, table.concat(problems, "; ")),
	}
end

return GoalTracker