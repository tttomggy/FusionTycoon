--!strict
--[[
	GiftsPanel
	----------
	The HUD GIFTS button's panel (UIKit.Modal): today's six playtime gifts
	(GiftConfig) as boxes, 3 × 2:

	  claimed  dim, a green ✓
	  ready    green glow, "OPEN!" (tap = ClaimGift { Index })
	  locked   the minute it opens ("25 min") and a thin progress bar

	A strip on top shows the daily reward (ready: OPEN reopens the daily
	card; claimed: when the next one comes). Play time comes from
	TycoonController (counting on between snapshots); the server re-checks
	every claim. Pulls and the item show through the real pull cards.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GiftConfig = require(ReplicatedStorage.Shared.Config.GiftConfig)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local Controllers = script.Parent.Parent.Controllers
local TycoonController = require(Controllers.TycoonController)
local ToastController = require(Controllers.ToastController)
local DailyController = require(Controllers.DailyController)
local UIKit = require(script.Parent.UIKit)

local GiftsPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local PANEL_SIZE = Vector2.new(560, 430)
local DISPLAY_ORDER = 142 -- between the Shop (141) and Settings (143)
local COLUMNS = 3
local BOX_GAP = 10
local BOX_HEIGHT = 118
local STRIP_HEIGHT = 48
local CLAIMED_OPACITY = 0.45
local REVEAL_SECONDS = 1.6
local AUTO_CLOSE_PULL_SECONDS = 0.4

local REFUSALS: { [string]: string } = {
	Claimed = "Already opened",
	NotYet = "Not open yet, keep playing!",
	NotReady = "Your lab is still loading, try again",
	NotLoaded = "Your lab is still loading, try again",
}

local modal: UIKit.Modal? = nil
local stripLabel: TextLabel
local stripButtonHolder: Frame
local playLabel: TextLabel
local grid: Frame
local boxes: { [number]: Frame } = {}
local lastSignature = ""
local glowTweens: { Tween } = {}
local pending: { [number]: boolean } = {} -- claims sent, no answer yet
local revealUntil: { [number]: number } = {} -- os.clock() a reveal shows until
local revealText: { [number]: string } = {}

local function stopGlows()
	for _, tween in glowTweens do
		tween:Cancel()
	end
	table.clear(glowTweens)
end

-- "Claimed" | "Ready" | "Locked" | "Reveal".
local function boxState(index: number, playSeconds: number, claimed: { number }): string
	if (revealUntil[index] or 0) > os.clock() then
		return "Reveal"
	elseif GiftConfig.IsClaimed(claimed, index) then
		return "Claimed"
	elseif GiftConfig.IsReady(playSeconds, claimed, index) then
		return "Ready"
	end
	return "Locked"
end

local function claim(index: number)
	if pending[index] then
		return
	end
	pending[index] = true
	RemoteEvents.ClaimGift:FireServer({ Index = index })
	task.delay(6, function()
		pending[index] = nil
	end)
end

local function buildBox(index: number, stateName: string, playSeconds: number)
	local gift = GiftConfig.Gifts[index]
	local reward = gift.Reward
	local ready = stateName == "Ready"
	local gradient: { { any } } = if ready
		then { { 0, UITheme.Gradients.Green.Top }, { 1, UITheme.Gradients.Green.Bottom } }
		else { { 0, Colors.Panel3 }, { 1, Colors.Panel2 } }
	local body, holder = UIKit.Panel({
		Name = ("Gift%d"):format(index),
		Parent = grid,
		LayoutOrder = index,
		Gradient = gradient,
		Radius = 16,
		StrokeThickness = if ready then 3 else nil,
		StrokeColor = if ready then Colors.Cash else nil,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = grid.ZIndex,
	})
	boxes[index] = holder
	local inner = body.ZIndex + 1
	local textColor = if ready then Colors.CoinText else Colors.Text

	if ready then
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.new(1, 12, 1, 12)
		glow.BackgroundColor3 = Colors.Cash
		glow.BackgroundTransparency = 0.7
		glow.ZIndex = holder.ZIndex
		glow.Parent = holder
		UIKit.Corner(glow, 20)
		local tween = TweenService:Create(
			glow,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.4, Size = UDim2.new(1, 20, 1, 20) }
		)
		tween:Play()
		table.insert(glowTweens, tween)
	end

	UIKit.Label({
		Name = "Icon",
		Text = if stateName == "Reveal" then RewardConfig.GetIcon(reward) else "🎁",
		TextSize = 34,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = inner,
		Parent = body,
	})
	UIKit.Label({
		Name = "Reward",
		Text = if stateName == "Reveal" then revealText[index] or "" else RewardConfig.GetTitle(reward),
		RichText = true,
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		TextColor3 = if stateName == "Reveal" then Colors.Cash else textColor,
		TextWrapped = true,
		Position = UDim2.fromOffset(6, 50),
		Size = UDim2.new(1, -12, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = inner,
		Parent = body,
	})
	local bottomText = if ready then "OPEN!" elseif stateName == "Locked" then ("%d min"):format(gift.Minutes) else ""
	UIKit.Label({
		Name = "State",
		Text = bottomText,
		Font = Fonts.Display,
		TextSize = if ready then 20 else 16,
		TextColor3 = if ready then Colors.CoinText else Colors.Muted,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -10),
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = inner,
		Parent = body,
	})
	if stateName == "Locked" then
		local bar = UIKit.ProgressBar({
			Name = "Progress",
			Parent = body,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -24, 0, 5),
			ZIndex = inner,
		})
		UIKit.SetProgress(bar, math.clamp(playSeconds / (gift.Minutes * 60), 0, 1))
	elseif stateName == "Claimed" then
		UIKit.SetOpacity(holder, CLAIMED_OPACITY)
		UIKit.Label({
			Name = "Check",
			Text = "✓",
			Font = Fonts.Display,
			TextSize = 44,
			TextColor3 = Colors.Cash,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = inner + 2,
			Stroke = UITheme.Stroke.Text,
			Parent = holder,
		})
	end
	if ready then
		local hit = Instance.new("TextButton")
		hit.Name = "Open"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = inner + 3
		hit.Parent = body
		hit.Activated:Connect(function()
			claim(index)
		end)
		UIKit.AttachPress(hit)
	end
end

-- Seconds to the next UTC midnight (the next daily reward).
local function secondsToUtcMidnight(): number
	return 86400 - os.time() % 86400
end

local function refresh(force: boolean?)
	local card = modal
	if not card or not card.IsOpen() then
		return
	end
	local playSeconds = TycoonController.GetGiftPlaySeconds()
	local claimed = TycoonController.GetClaimedGifts()
	playLabel.Text = ("Played today: %s"):format(EventState.FormatTimer(playSeconds))

	local daily = TycoonController.GetDaily()
	local canDaily = DailyController.CanClaim()
	stripButtonHolder.Visible = canDaily
	stripLabel.Text = if canDaily
		then ("📅 Daily reward ready · Day %d"):format(daily.Day)
		else ("📅 Daily reward claimed · next in %s"):format(EventState.FormatTimer(secondsToUtcMidnight()))

	local states = {}
	for index in GiftConfig.Gifts do
		table.insert(states, boxState(index, playSeconds, claimed))
	end
	local signature = table.concat(states, ",")
	-- Locked boxes' bars move every second; the rest only on a change.
	if force or signature ~= lastSignature then
		lastSignature = signature
		stopGlows()
		for _, child in grid:GetChildren() do
			if not child:IsA("UIGridLayout") then
				child:Destroy()
			end
		end
		table.clear(boxes)
		for index, stateName in states do
			buildBox(index, stateName, playSeconds)
		end
	else
		for index, stateName in states do
			local holder = boxes[index]
			local bar = holder and holder:FindFirstChild("Progress", true)
			if stateName == "Locked" and bar and bar:IsA("Frame") then
				UIKit.SetProgress(bar, math.clamp(playSeconds / (GiftConfig.Gifts[index].Minutes * 60), 0, 1))
			end
		end
	end
end

local function build(): UIKit.Modal
	local created = UIKit.Modal({
		Name = "Gifts",
		Title = "🎁 GIFTS",
		DisplayOrder = DISPLAY_ORDER,
		MaxSize = PANEL_SIZE,
		HeaderTop = Colors.GiftsTop,
		OnClose = stopGlows,
	})
	created.Subtitle.Text = "Free gifts for playing today"
	created.Subtitle.Visible = true
	local content = created.Content
	local z = content.ZIndex + 1

	local strip = UIKit.Panel({
		Name = "DailyStrip",
		Parent = content,
		Size = UDim2.new(1, 0, 0, STRIP_HEIGHT),
		Color = Colors.Panel2,
		Radius = 14,
		NoShadow = true,
		ZIndex = z,
	})
	UIKit.Padding(strip, 0, 6, 0, 12)
	stripLabel = UIKit.Label({
		Name = "Text",
		Font = Fonts.BodyHeavy,
		TextSize = 15,
		Size = UDim2.new(1, -110, 1, 0),
		TextScaled = false,
		ZIndex = strip.ZIndex + 1,
		Parent = strip,
	})
	local _, buttonHolder = UIKit.Button({
		Name = "OpenDaily",
		Parent = strip,
		Style = "Gold",
		Text = "OPEN",
		TextColor3 = Colors.GoldText,
		TextSize = 16,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(96, UITheme.MinTapSize - 4),
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = strip.ZIndex + 1,
		OnClick = function()
			created.Close()
			DailyController.Open()
		end,
	})
	stripButtonHolder = buttonHolder

	playLabel = UIKit.Label({
		Name = "Played",
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(0, STRIP_HEIGHT + 8),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = content,
	})

	-- The boxes and the footer scroll together: at full size the pinned
	-- footer covered the second row's bottom 20 px, and on a phone (0.8
	-- scale, ~335 px of content) the second row didn't fit at all.
	local scrollTop = STRIP_HEIGHT + 30
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroll"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Position = UDim2.fromOffset(0, scrollTop)
	scroller.Size = UDim2.new(1, 0, 1, -scrollTop)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = Colors.Faint
	scroller.ZIndex = z
	scroller.Parent = content
	-- Room for the ready boxes' glow (it reaches ~10 px past a box).
	UIKit.Padding(scroller, 8, 14, 8, 8)
	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.Padding = UDim.new(0, 8)
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Parent = scroller

	grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, BOX_HEIGHT * 2 + BOX_GAP + UITheme.SmallShadowOffset)
	grid.LayoutOrder = 1
	grid.ZIndex = z
	grid.Parent = scroller
	local layout = Instance.new("UIGridLayout")
	-- 1 px of slack: an exact 1/3 split rounds over the row width and wraps the
	-- grid to 2 columns (which pushed the last gifts below the panel).
	layout.CellSize = UDim2.new(1 / COLUMNS, -BOX_GAP * (COLUMNS - 1) / COLUMNS - 1, 0, BOX_HEIGHT)
	layout.FillDirectionMaxCells = COLUMNS
	layout.CellPadding = UDim2.fromOffset(BOX_GAP, BOX_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local itemGift = GiftConfig.Gifts[#GiftConfig.Gifts].Reward
	UIKit.Label({
		Name = "Footer",
		Text = ("Gifts reset at 00:00 UTC; time adds up across visits. Last gift: %s"):format(
			if itemGift.Odds then RewardConfig.FormatOdds(itemGift.Odds) else ""
		),
		Font = Fonts.Body,
		TextSize = 12,
		TextColor3 = Colors.Faint,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = scroller,
	})

	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
	modal = created
	return created
end

local function onGiftResult(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local index = if typeof(payload.Index) == "number" then payload.Index else nil
	if index then
		pending[index] = nil
	end
	if payload.Result ~= "Granted" or not index then
		local reason = if typeof(payload.Reason) == "string" then payload.Reason else ""
		ToastController.Show(REFUSALS[reason] or "Couldn't open that, try again", "Error")
		refresh(true)
		return
	end
	local lines = if typeof(payload.Lines) == "table" then payload.Lines else {}
	revealText[index] = table.concat(lines, "\n")
	revealUntil[index] = os.clock() + REVEAL_SECONDS
	SoundKit.Play("RevealMinor", nil)
	refresh(true)
	local holder = boxes[index]
	if holder then
		UIKit.PopIn(holder)
	end
	task.delay(REVEAL_SECONDS + 0.05, function()
		refresh(true)
	end)
	if payload.Kind == "Pulls" or payload.Kind == "Item" then
		-- The real pull card shows what you got.
		task.delay(AUTO_CLOSE_PULL_SECONDS, GiftsPanel.Close)
	end
end

function GiftsPanel.Init()
	RemoteEvents.GiftResult.OnClientEvent:Connect(onGiftResult)
	TycoonController.TycoonChanged:Connect(function()
		refresh()
	end)
end

function GiftsPanel.IsOpen(): boolean
	return modal ~= nil and (modal :: UIKit.Modal).IsOpen()
end

function GiftsPanel.Open()
	local card = modal or build()
	if not card.IsOpen() then
		card.Open()
	end
	refresh(true)
end

function GiftsPanel.Close()
	if modal then
		(modal :: UIKit.Modal).Close()
	end
end

function GiftsPanel.Toggle()
	if GiftsPanel.IsOpen() then
		GiftsPanel.Close()
	else
		GiftsPanel.Open()
	end
end

-- For the HUD: (ready count, seconds to the next gift or nil).
function GiftsPanel.GetStatus(): (number, number?)
	local playSeconds = TycoonController.GetGiftPlaySeconds()
	local claimed = TycoonController.GetClaimedGifts()
	return GiftConfig.CountReady(playSeconds, claimed), GiftConfig.GetNextIn(playSeconds, claimed)
end

return GiftsPanel
