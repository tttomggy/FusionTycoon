--!strict
--[[
	DailyCard
	---------
	The daily reward card (DailyController decides when it opens; this only
	draws). A UIKit.Modal:

	  "🔥 4-day streak" pill            "1 free skip"
	  [DAY 1 ✓][DAY 2 ✓][DAY 3 ✓][DAY 4 TODAY][DAY 5][DAY 6][DAY 7]
	  Day 4 · ×2 luck for 15 min
	  [ CLAIM DAY 4 ]
	  footer: the skip rule and the Day 7 odds (DailyConfig.GetFooter)

	Claimed tiles are dim with a ✓; today's is gold, glowing, "TODAY"; Day 7
	is purple. CLAIM fires ClaimDaily; ShowReveal plays the result on the
	card (the claimed tile pops its ✓, the lines in green) and turns the
	button into NICE. Pulls and the Day 7 item show through the real pull
	cards, so the card closes itself for those.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DailyConfig = require(ReplicatedStorage.Shared.Config.DailyConfig)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.UIKit)

local DailyCard = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local CARD_SIZE = Vector2.new(640, 390)
local DISPLAY_ORDER = 125 -- the welcome-back card's layer, under Results (130)
local TILE_GAP = 6
local TILE_HEIGHT = 118
local CLAIMED_TRANSPARENCY = 0.55
local GLOW_PERIOD = 1.4
local AUTO_CLOSE_PULL_SECONDS = 0.5

export type View = {
	CanClaim: boolean,
	Day: number,
	Streak: number,
	Skips: number,
	UsesSkip: boolean,
	Resets: boolean,
}

export type Handlers = {
	OnClaim: () -> (),
	BaseIncome: () -> number, -- $/s without timed boosts (a cash day's amount)
}

local modal: UIKit.Modal? = nil
local handlers: Handlers? = nil
local tilesFrame: Frame
local streakPill: TextLabel
local skipPill: TextLabel
local detailLabel: TextLabel
local subLabel: TextLabel
local actionButton: TextButton
local footerLabel: TextLabel
local glowTween: Tween? = nil
local claimed = false -- this opening's claim was granted (button = NICE)
local waiting = false -- CLAIM sent, no answer yet

local function stopGlow()
	if glowTween then
		glowTween:Cancel()
		glowTween = nil
	end
end

-- One day's tile. `stateName`: "Claimed" | "Today" | "Future".
local function buildTile(day: number, stateName: string, z: number)
	local reward = DailyConfig.GetReward(day)
	local isToday = stateName == "Today"
	local isSeventh = day == DailyConfig.Cycle
	local gradient: { { any } } = if isToday
		then { { 0, UITheme.Gradients.Gold.Top }, { 1, UITheme.Gradients.Gold.Bottom } }
		elseif isSeventh then { { 0, UITheme.Gradients.Violet.Top }, { 1, UITheme.Gradients.Violet.Bottom } }
		else { { 0, Colors.Panel3 }, { 1, Colors.Panel2 } }
	local body, holder = UIKit.Panel({
		Name = ("Day%d"):format(day),
		Parent = tilesFrame,
		Size = UDim2.new(1 / DailyConfig.Cycle, -TILE_GAP * (DailyConfig.Cycle - 1) / DailyConfig.Cycle, 1, -UITheme.SmallShadowOffset),
		LayoutOrder = day,
		Gradient = gradient,
		Radius = 14,
		StrokeThickness = if isToday then 3 else nil,
		StrokeColor = if isToday then Colors.GoldLabel else nil,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z,
	})
	local textColor = if isToday then Colors.GoldText else Colors.Text
	local inner = body.ZIndex + 1
	UIKit.Label({
		Name = "DayLabel",
		Text = ("DAY %d"):format(day),
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		TextColor3 = textColor,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = inner,
		Parent = body,
	})
	UIKit.Label({
		Name = "Icon",
		Text = RewardConfig.GetIcon(reward),
		TextSize = 30,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = inner,
		Parent = body,
	})
	UIKit.Label({
		Name = "Short",
		Text = RewardConfig.GetShortLabel(reward),
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = textColor,
		TextWrapped = true,
		Position = UDim2.fromOffset(2, 62),
		Size = UDim2.new(1, -4, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = inner,
		Parent = body,
	})
	if isToday then
		UIKit.Label({
			Name = "Today",
			Text = "TODAY",
			Font = Fonts.Display,
			TextSize = 14,
			TextColor3 = Colors.GoldText,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -6),
			Size = UDim2.new(1, 0, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = inner,
			Parent = body,
		})
		-- The glow: a soft gold halo behind the tile, breathing.
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.new(1, 14, 1, 14)
		glow.BackgroundColor3 = Colors.GoldLabel
		glow.BackgroundTransparency = 0.75
		glow.ZIndex = holder.ZIndex
		glow.Parent = holder
		UIKit.Corner(glow, 18)
		stopGlow()
		local tween = TweenService:Create(
			glow,
			TweenInfo.new(GLOW_PERIOD / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.45, Size = UDim2.new(1, 22, 1, 22) }
		)
		tween:Play()
		glowTween = tween
	end
	if stateName == "Claimed" then
		UIKit.SetOpacity(holder, 1 - CLAIMED_TRANSPARENCY)
		UIKit.Label({
			Name = "Check",
			Text = "✓",
			Font = Fonts.Display,
			TextSize = 40,
			TextColor3 = Colors.Cash,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = inner + 2,
			Stroke = UITheme.Stroke.Text,
			Parent = holder,
		})
	end
end

local function buildTiles(view: View, claimedToday: boolean)
	stopGlow()
	for _, child in tilesFrame:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local z = tilesFrame.ZIndex
	for day = 1, DailyConfig.Cycle do
		local stateName = "Future"
		if day < view.Day or (claimedToday and day == view.Day) then
			stateName = "Claimed"
		elseif day == view.Day and view.CanClaim then
			stateName = "Today"
		end
		buildTile(day, stateName, z)
	end
end

local function rewardDetail(view: View): string
	local reward = DailyConfig.GetReward(view.Day)
	local text = ("Day %d · %s"):format(view.Day, RewardConfig.GetTitle(reward))
	if reward.Kind == "Cash" and handlers then
		local amount = RewardConfig.GetCashAmount(reward, (handlers :: Handlers).BaseIncome())
		text ..= "  " .. UIKit.Colored("+" .. NumberFormat.Money(amount), Colors.Cash)
	end
	return text
end

local function subline(view: View): string
	if view.UsesSkip then
		return "You missed a day: your free skip kept the streak going!"
	elseif view.Resets then
		return "Your streak ended: a fresh run starts at Day 1."
	end
	local reward = DailyConfig.GetReward(view.Day)
	if reward.Kind == "Item" and reward.Odds then
		return RewardConfig.FormatOdds(reward.Odds)
	end
	return "Come back tomorrow for the next day's reward."
end

local function setAction(text: string, style: string)
	UIKit.SetButton(actionButton, { Text = text, Style = style })
end

local function build()
	local created = UIKit.Modal({
		Name = "DailyReward",
		Title = "DAILY REWARD",
		DisplayOrder = DISPLAY_ORDER,
		MaxSize = CARD_SIZE,
		HeaderTop = Colors.DailyTop,
		OnClose = stopGlow,
	})
	created.Subtitle.Text = "A new reward every UTC day"
	created.Subtitle.Visible = true
	local content = created.Content
	local z = content.ZIndex + 1

	streakPill = UIKit.Pill({
		Name = "Streak",
		Parent = content,
		Text = "🔥 1-day streak",
		Gradient = UITheme.Gradients.Orange,
		TextSize = 15,
		Height = 28,
		ZIndex = z,
	})
	skipPill = UIKit.Pill({
		Name = "Skips",
		Parent = content,
		Text = "1 free skip",
		Color = Colors.Panel2,
		TextColor3 = Colors.Muted,
		TextSize = 13,
		Height = 28,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		ZIndex = z,
	})

	tilesFrame = Instance.new("Frame")
	tilesFrame.Name = "Tiles"
	tilesFrame.BackgroundTransparency = 1
	tilesFrame.Position = UDim2.fromOffset(0, 40)
	tilesFrame.Size = UDim2.new(1, 0, 0, TILE_HEIGHT)
	tilesFrame.ZIndex = z
	tilesFrame.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, TILE_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tilesFrame

	detailLabel = UIKit.Label({
		Name = "Detail",
		RichText = true,
		Font = Fonts.Display,
		TextSize = 20,
		Position = UDim2.fromOffset(0, 40 + TILE_HEIGHT + 10),
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = content,
	})
	local detailSize = Instance.new("UITextSizeConstraint")
	detailSize.MaxTextSize = 20
	detailSize.Parent = detailLabel
	subLabel = UIKit.Label({
		Name = "Sub",
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(0, 40 + TILE_HEIGHT + 36),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = content,
	})

	actionButton = UIKit.Button({
		Name = "Claim",
		Parent = content,
		Style = "Green",
		Text = "CLAIM",
		TextSize = 22,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -34),
		Size = UDim2.fromOffset(260, 54),
		ZIndex = z,
		OnClick = function()
			if claimed then
				created.Close()
			elseif not waiting and handlers then
				local current = handlers :: Handlers
				waiting = true
				setAction("…", "Disabled")
				current.OnClaim()
			end
		end,
	})
	footerLabel = UIKit.Label({
		Name = "Footer",
		Text = DailyConfig.GetFooter(),
		Font = Fonts.Body,
		TextSize = 12,
		TextColor3 = Colors.Faint,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = content,
	})
	modal = created
	return created
end

function DailyCard.Init(newHandlers: Handlers)
	handlers = newHandlers
end

function DailyCard.IsOpen(): boolean
	return modal ~= nil and (modal :: UIKit.Modal).IsOpen()
end

function DailyCard.Open(view: View)
	local card = modal or build()
	claimed = false
	waiting = false
	streakPill.Text = ("🔥 %d-day streak"):format(view.Streak)
	skipPill.Text = if view.Skips == 1 then "1 free skip" else ("%d free skips"):format(view.Skips)
	buildTiles(view, false)
	detailLabel.Text = rewardDetail(view)
	subLabel.Text = subline(view)
	footerLabel.Text = DailyConfig.GetFooter()
	setAction(("CLAIM DAY %d"):format(view.Day), "Green")
	card.Open()
end

export type Result = {
	Day: number,
	Streak: number,
	Kind: string,
	Lines: { string },
}

-- The claim was granted: ✓ on the tile, what you got, NICE.
function DailyCard.ShowReveal(view: View, result: Result)
	local card = modal
	if not card or not card.IsOpen() then
		return
	end
	claimed = true
	waiting = false
	stopGlow()
	streakPill.Text = ("🔥 %d-day streak"):format(result.Streak)
	buildTiles({
		CanClaim = false,
		Day = result.Day,
		Streak = result.Streak,
		Skips = view.Skips,
		UsesSkip = false,
		Resets = false,
	}, true)
	local tile = tilesFrame:FindFirstChild(("Day%d"):format(result.Day))
	if tile and tile:IsA("GuiObject") then
		UIKit.PopIn(tile)
	end
	detailLabel.Text = UIKit.Colored(table.concat(result.Lines, "  ·  "), Colors.Cash)
	subLabel.Text = "Come back tomorrow for the next one!"
	setAction("NICE", "Gold")
	local isPull = result.Kind == "Pulls" or result.Kind == "Item"
	SoundKit.Play(if result.Day == DailyConfig.Cycle then "RevealMajor" else "RevealMinor", nil)
	if isPull then
		-- The real pull card shows what you got.
		task.delay(AUTO_CLOSE_PULL_SECONDS, function()
			if modal == card and claimed then
				card.Close()
			end
		end)
	end
end

-- The claim was refused (or the server never answered): CLAIM again.
function DailyCard.ResetClaim(view: View)
	if not modal then
		return
	end
	waiting = false
	setAction(("CLAIM DAY %d"):format(view.Day), "Green")
end

function DailyCard.Close()
	if modal then
		(modal :: UIKit.Modal).Close()
	end
end

return DailyCard
