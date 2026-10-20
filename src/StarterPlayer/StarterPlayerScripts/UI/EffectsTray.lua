--!strict
--[[
	EffectsTray
	-----------
	The active effects as round cartoon STICKER badges with a timer under
	each, bottom LEFT where Bubble Gum Simulator keeps its potion icons.
	Icons fill left to right, 4 to a row; more rows stack upward.

	  Income boost   💵 green   timer            (Boost / Quick Boost / Cash Burst bank)
	  Luck           🍀 teal    timer + "×2"     (Luck Potion / Lucky Charm bank)
	  Server         ⚙️ orange  timer            (the server Overclock)
	  Speed Boots    👟 blue    timer
	  Safe Fusion    🛡 violet  "×N" badge       (tokens you hold)
	  Fusion Spark   ⚡ gold    "×1" badge       (armed for the next fusion)
	  Coin Magnet    🧲 red     READY            (armed for the next rain)

	Every number comes from the synced data the old HUD pills used
	(TycoonController, ShopState): no new server state. No product photos:
	each badge is built in code, a 60 px circle with a bright 2-stop
	gradient, a 3 px white stroke and the ink drop shadow, one big glyph with
	an ink outline (it reads like a sticker) and an EFFECT LAYER behind the
	glyph that moves a little while the tray is on screen (orbiting coins,
	a shine ring, speed lines, a pulse, drifting sparks, a cog). Smooth
	sines only, never a flash, the last minute included.

	Tooltip, on hover (desktop: MouseEnter shows it at once, MouseLeave hides
	it) AND on tap (touch: shows for 3 s or until another tap anywhere): a
	dark card ABOVE the icon with an arrow to it, max 220 px wide, 14 px
	text, clamped on screen: the effect's name in bold, its Plain line
	("Double cash for 1 hour") and "12:41 left" / "×3 left" / "Ready".
	Effects pop in (0.85 -> 1, 0.15 s) when gained and shrink out when they
	end.

	Placement: 16 px from the left edge, its bottom level with the HUD bottom
	row's bottom edge. If it would touch the HUD's left column or the bottom
	row, the icons drop from 60 to 48 px, then to 3 per row; if it still
	touches (a phone with a tall left column) the tray sits to the right of
	the left column, still bottom-aligned.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local ShopState = require(ReplicatedStorage.Shared.Modules.ShopState)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TycoonController = require(script.Parent.Parent.Controllers.TycoonController)
local UIKit = require(script.Parent.UIKit)

local EffectsTray = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

-- Placement tries these in order (icon px, icons per row).
local FITS = { { 60, 4 }, { 48, 4 }, { 48, 3 } }
local GLYPH_FRACTION = 34 / 60 -- of the circle: a 34 px glyph on a 60 px badge
local TIMER_SIZE = 15
local TIMER_HEIGHT = 18
local TIMER_GAP = 4
local CELL_SIDE_GAP = 8
local ROW_GAP = 6
local LEFT_MARGIN = 16
-- HudController: BOTTOM_MARGIN 22 + ShadowOffset: where the bottom row ends.
local BOTTOM_BASE = 22 + UITheme.ShadowOffset
local BESIDE_GAP = 8
local SHRINK_SECONDS = 0.15
local TICK_SECONDS = 0.25
local TOOLTIP_GAP = 6
local TOOLTIP_MAX_WIDTH = 220
local TOOLTIP_TEXT_SIZE = 14
local TOOLTIP_PAD = 10
local TOOLTIP_ARROW = 12 -- the rotated square that points at the icon
local TOOLTIP_EDGE = 8 -- px kept clear of the screen edge
local TAP_SECONDS = 3 -- a tapped tooltip closes by itself after this
local GLYPH_STROKE = 2

type EffectState = {
	Id: string,
	Order: number,
	Gradient: UITheme.GradientPair,
	Glyph: string,
	Fx: string, -- the effect layer behind the glyph (FX_BUILDERS)
	Seconds: number?, -- a timer under the circle ("12:41")
	Ready: boolean?, -- "READY" under the circle
	Badge: string?, -- "×2" on the circle's top-right
	Name: string, -- the tooltip's bold first line
	Plain: string, -- its second line: what the effect does
	Tail: string, -- its third line ("12:41 left", "×3 left", "Ready")
}

type Cell = {
	Id: string,
	Frame: Frame,
	Circle: Frame,
	Glyph: TextLabel,
	FxRoot: Frame, -- the effect layer's parts live here
	Step: (number) -> (), -- moves the effect layer to time t
	Timer: TextLabel,
	Hit: TextButton,
	Fit: number, -- the circle size (px) this cell is laid out for
	Leaving: boolean,
	State: EffectState,
}

export type Rect = { Position: Vector2, Size: Vector2 }

export type Hooks = {
	-- Every HUD rect the tray must stay clear of (left column, bottom row),
	-- screen px with the top-bar inset added back (HudController.GetObstacleRects).
	GetObstacles: () -> { [string]: Rect },
	-- Screen-px rect (AbsolutePosition space) of the HUD bottom row, or nil.
	GetBottomRowRect: () -> Rect?,
}

local hooks: Hooks? = nil
local screenGui: ScreenGui
local tray: Frame
local gridLayout: UIGridLayout
local tooltip: Frame
local tooltipName: TextLabel
local tooltipPlain: TextLabel
local tooltipTime: TextLabel
local tooltipArrow: Frame
local tooltipCover: Frame
local cells: { [string]: Cell } = {}
local shownId: string? = nil
local pinned = false
local pinToken = 0 -- a newer tap makes an older tap's 3 s close do nothing
-- What the last placement settled on (icon px, icons per row, x shift).
local fitSize, fitPerRow = FITS[1][1], FITS[1][2]

--[[ What is active right now ------------------------------------------------------ ]]

local function secondsText(seconds: number): string
	return EventState.FormatTimer(math.ceil(seconds))
end

-- The effects that are on, in tray order.
local function collect(): { EffectState }
	local list: { EffectState } = {}
	local income = TycoonController.GetBoostSecondsLeft("Income")
	if income > 0 then
		table.insert(list, {
			Id = "Income",
			Order = 1,
			Gradient = UITheme.Gradients.Green,
			Glyph = "💵",
			Fx = "Cash",
			Seconds = income,
			Name = "Cash Boost",
			Plain = ("%d× cash from your lab"):format(ShopConfig.BoostMultiplier),
			Tail = ("%s left"):format(secondsText(income)),
		})
	end
	local luck = TycoonController.GetBoostSecondsLeft("Luck")
	if luck > 0 then
		table.insert(list, {
			Id = "Luck",
			Order = 2,
			Gradient = UITheme.Gradients.Teal,
			Glyph = "🍀",
			Fx = "Luck",
			Seconds = luck,
			Badge = ("×%d"):format(ShopConfig.LuckPotionMultiplier),
			Name = "Luck Boost",
			Plain = ("Rare orbs %d× more likely"):format(ShopConfig.LuckPotionMultiplier),
			Tail = ("%s left"):format(secondsText(luck)),
		})
	end
	local server = ShopState.GetOverclockSeconds()
	if server > 0 then
		table.insert(list, {
			Id = "Server",
			Order = 3,
			Gradient = UITheme.Gradients.Orange,
			Glyph = "⚙️",
			Fx = "Cog",
			Seconds = server,
			Name = "Server Overclock",
			Plain = ("Everyone here earns %d× cash"):format(ShopConfig.OverclockMultiplier),
			Tail = ("%s left"):format(secondsText(server)),
		})
	end
	local quests = TycoonController.GetQuests()
	local boots = if quests and typeof(quests.SpeedBootsUntil) == "number"
		then math.max(0, quests.SpeedBootsUntil - Workspace:GetServerTimeNow())
		else 0
	if boots > 0 then
		table.insert(list, {
			Id = "SpeedBoots",
			Order = 4,
			Gradient = UITheme.Gradients.Blue,
			Glyph = "👟",
			Fx = "Speed",
			Seconds = boots,
			Name = QuestConfig.PowerUps.SpeedBoots.Name,
			Plain = ("Run %s× faster"):format(tostring(QuestConfig.PowerUps.SpeedBoots.SpeedMultiplier)),
			Tail = ("%s left"):format(secondsText(boots)),
		})
	end
	local tokens = TycoonController.GetShop().SafeFusionTokens
	if tokens > 0 then
		table.insert(list, {
			Id = "SafeFusion",
			Order = 5,
			Gradient = UITheme.Gradients.Violet,
			Glyph = "🛡",
			Fx = "Safe",
			Badge = ("×%d"):format(tokens),
			Name = "Safe Fusion",
			Plain = (ShopConfig.GetItem("SafeFusion1") :: ShopConfig.Item).Plain,
			Tail = ("×%d left"):format(tokens),
		})
	end
	if TycoonController.IsArmed("FusionSpark") then
		table.insert(list, {
			Id = "FusionSpark",
			Order = 6,
			Gradient = UITheme.Gradients.Gold,
			Glyph = "⚡",
			Fx = "Spark",
			Badge = "×1",
			Name = QuestConfig.PowerUps.FusionSpark.Name,
			Plain = QuestConfig.PowerUps.FusionSpark.Plain,
			Tail = "Ready",
		})
	end
	if TycoonController.IsArmed("CoinMagnet") then
		table.insert(list, {
			Id = "CoinMagnet",
			Order = 7,
			Gradient = UITheme.Gradients.Red,
			Glyph = "🧲",
			Fx = "Magnet",
			Ready = true,
			Name = QuestConfig.PowerUps.CoinMagnet.Name,
			Plain = QuestConfig.PowerUps.CoinMagnet.Plain,
			Tail = "Ready",
		})
	end
	return list
end

--[[ Effect layers ----------------------------------------------------------------------
	Each builder makes the little scene BEHIND the glyph (children of an "Fx"
	frame filling the badge, below the glyph) and returns its step function:
	step(t) places everything for time t (seconds). Positions are scale
	fractions of the circle, so a resize needs nothing. Everything stays
	inside the circle and moves on sines or linear drifts: nothing flashes.
]]

local TAU = math.pi * 2

-- A small emoji / glyph particle in the Fx frame.
local function particle(root: Frame, text: string, size: number): TextLabel
	return UIKit.Label({
		Name = "Particle",
		Text = text,
		TextScaled = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(size, size),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
		Parent = root,
	})
end

local function disc(root: Frame, size: number, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Disc"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(size, size)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = 4
	frame.Parent = root
	UIKit.Corner(frame, 999)
	return frame
end

local FX_BUILDERS: { [string]: (Frame) -> (number) -> () } = {
	-- 3 small coins orbit slowly; a sparkle twinkles in and out every 2 s.
	Cash = function(root)
		local coins: { TextLabel } = {}
		for _ = 1, 3 do
			table.insert(coins, particle(root, "🪙", 0.22))
		end
		local sparkle = particle(root, "✦", 0.26)
		sparkle.Position = UDim2.fromScale(0.76, 0.24)
		sparkle.TextTransparency = 1
		return function(t)
			for index, coin in coins do
				local angle = t * TAU / 6 + (index - 1) * TAU / 3
				coin.Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.34, 0.5 + math.sin(angle) * 0.34)
			end
			local phase = (t % 2) / 0.8
			sparkle.TextTransparency = if phase < 1 then 1 - math.sin(phase * math.pi) else 1
			sparkle.Rotation = phase * 40
		end
	end,
	-- A soft shine runs round a ring inside the rim.
	Luck = function(root)
		local ring = Instance.new("Frame")
		ring.Name = "Ring"
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(0.84, 0.84)
		ring.BackgroundTransparency = 1
		ring.ZIndex = 4
		ring.Parent = root
		UIKit.Corner(ring, 999)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Colors.White
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = ring
		local shine = Instance.new("UIGradient")
		shine.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.28, 0.85),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		shine.Parent = stroke
		return function(t)
			shine.Rotation = (t * 80) % 360
		end
	end,
	-- 3 speed lines slide left and fade at both ends.
	Speed = function(root)
		local lines: { Frame } = {}
		local ys = { 0.32, 0.5, 0.68 }
		for index = 1, 3 do
			local line = disc(root, 0.1, Colors.White)
			line.Name = "Line"
			line.Size = UDim2.fromScale(0.28, 0.05)
			line.Position = UDim2.fromScale(0.8, ys[index])
			lines[index] = line
		end
		return function(t)
			for index, line in lines do
				local p = (t / 1.4 + (index - 1) / 3) % 1
				line.Position = UDim2.fromScale(0.8 - p * 0.5, ys[index])
				line.BackgroundTransparency = 0.3 + 0.7 * (math.abs(p * 2 - 1) ^ 2)
			end
		end
	end,
	-- A gentle glow breathes: scale 1 -> 1.06 -> 1 every 2 s.
	Safe = function(root)
		local glow = disc(root, 0.88, Colors.White)
		local scale = Instance.new("UIScale")
		scale.Parent = glow
		return function(t)
			local breath = 0.5 - 0.5 * math.cos(t * math.pi)
			scale.Scale = 1 + 0.06 * breath
			glow.BackgroundTransparency = 0.9 - 0.15 * breath
		end
	end,
	-- 2 tiny sparks drift up and fade.
	Spark = function(root)
		local sparks: { TextLabel } = {}
		local xs = { 0.3, 0.7 }
		for _ = 1, 2 do
			local spark = particle(root, "✦", 0.2)
			spark.TextTransparency = 1
			table.insert(sparks, spark)
		end
		return function(t)
			for index, spark in sparks do
				local p = (t / 2 + (index - 1) * 0.5) % 1
				spark.Position = UDim2.fromScale(xs[index] + math.sin(t * 1.5 + index) * 0.04, 0.8 - p * 0.55)
				spark.TextTransparency = 1 - math.sin(p * math.pi)
			end
		end
	end,
	-- 2 coins drift in toward the magnet.
	Magnet = function(root)
		local coins: { TextLabel } = {}
		local starts = { Vector2.new(0.2, 0.24), Vector2.new(0.8, 0.78) }
		for _ = 1, 2 do
			table.insert(coins, particle(root, "🪙", 0.2))
		end
		return function(t)
			for index, coin in coins do
				local p = (t / 1.6 + (index - 1) * 0.5) % 1
				local at = starts[index]:Lerp(Vector2.new(0.5, 0.5), p)
				coin.Position = UDim2.fromScale(at.X, at.Y)
				local size = 0.2 * (1 - 0.4 * p)
				coin.Size = UDim2.fromScale(size, size)
				coin.TextTransparency = 1 - math.clamp(math.min(p / 0.2, (1 - p) / 0.3), 0, 1)
			end
		end
	end,
	-- A big faint cog turns slowly behind the glyph.
	Cog = function(root)
		local cog = particle(root, "⚙", 0.92)
		cog.TextTransparency = 0.7
		return function(t)
			cog.Rotation = (t * 25) % 360
		end
	end,
}

--[[ Cells ---------------------------------------------------------------------------- ]]

local function cellWidth(circle: number): number
	return circle + CELL_SIDE_GAP
end

local function cellHeight(circle: number): number
	return circle + TIMER_GAP + TIMER_HEIGHT
end

local function sizeCell(cell: Cell, circle: number)
	cell.Fit = circle
	cell.Frame.Size = UDim2.fromOffset(cellWidth(circle), cellHeight(circle))
	cell.Circle.Size = UDim2.fromOffset(circle, circle)
	cell.Glyph.TextSize = math.floor(circle * GLYPH_FRACTION)
	cell.Timer.Position = UDim2.fromOffset(0, circle + TIMER_GAP)
end

local function viewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1920, 1080)
end

local function closeTooltip()
	shownId = nil
	pinned = false
	pinToken += 1
	tooltip.Visible = false
	tooltipArrow.Visible = false
	tooltipCover.Visible = false
end

-- The card's three lines from the shown cell's live state.
local function fillTooltip(cell: Cell)
	tooltipName.Text = cell.State.Name
	tooltipPlain.Text = cell.State.Plain
	tooltipTime.Text = cell.State.Tail
end

-- Above the shown icon, its arrow on the icon's centre, kept on screen.
-- Runs every frame while open (the card's size settles a frame after its text).
local function placeTooltip()
	local id = shownId
	local cell = if id then cells[id] else nil
	if not cell or cell.Leaving then
		closeTooltip()
		return
	end
	local scale = UIKit.EffectiveScale(tray)
	local view = viewportSize()
	local circlePosition, circleSize = cell.Circle.AbsolutePosition, cell.Circle.AbsoluteSize
	local centreX = (circlePosition.X + circleSize.X / 2) / scale
	local width = tooltip.AbsoluteSize.X / scale
	local left = math.clamp(centreX - width / 2, TOOLTIP_EDGE, math.max(TOOLTIP_EDGE, view.X / scale - width - TOOLTIP_EDGE))
	-- Bottom-anchored: the arrow's tip is TOOLTIP_GAP above the badge.
	local bottom = circlePosition.Y / scale - TOOLTIP_GAP - TOOLTIP_ARROW / 2
	tooltip.Position = UDim2.fromOffset(left, bottom)
	local arrowX = math.clamp(centreX - left, TOOLTIP_ARROW + 6, math.max(TOOLTIP_ARROW + 6, width - TOOLTIP_ARROW - 6))
	tooltipArrow.Position = UDim2.fromOffset(left + arrowX, bottom)
	tooltipCover.Position = UDim2.fromOffset(left + arrowX, bottom)
	tooltip.Visible = true
	tooltipArrow.Visible = true
	tooltipCover.Visible = true
end

local function openTooltip(id: string, pin: boolean)
	local cell = cells[id]
	if not cell or cell.Leaving then
		return
	end
	shownId = id
	pinned = pin
	pinToken += 1
	fillTooltip(cell)
	placeTooltip()
	if pin then
		-- A tap's tooltip closes by itself after TAP_SECONDS (a newer tap or
		-- a close in between makes this do nothing).
		local mine = pinToken
		task.delay(TAP_SECONDS, function()
			if pinToken == mine and shownId == id then
				closeTooltip()
			end
		end)
	end
end

-- Desktop hover: shows at once, hides on leave (a tapped, pinned tooltip
-- ignores both). Also what /selftest "fires" as the cell's MouseEnter / MouseLeave.
local function hoverEnter(id: string)
	if not pinned then
		openTooltip(id, false)
	end
end

local function hoverLeave(id: string)
	if not pinned and shownId == id then
		closeTooltip()
	end
end

-- A tap (or click): pin the tooltip, or unpin it when it is already pinned.
local function tapCell(id: string)
	local cell = cells[id]
	if shownId == id and pinned then
		closeTooltip()
	elseif cell then
		UIKit.SelectFeedback(cell.Circle)
		openTooltip(id, true)
	end
end

local function buildCell(state: EffectState): Cell
	local frame = Instance.new("Frame")
	frame.Name = state.Id
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = state.Order
	frame.ZIndex = 2
	frame.Parent = tray

	-- The sticker: gradient disc, 3 px white rim, the ink drop shadow.
	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.AnchorPoint = Vector2.new(0.5, 0)
	circle.Position = UDim2.new(0.5, 0, 0, 0)
	circle.BackgroundColor3 = Colors.White
	circle.BorderSizePixel = 0
	circle.ZIndex = 3
	circle.Parent = frame
	UIKit.Corner(circle, 999)
	UIKit.Stroke(circle, 3, Colors.White)
	UIKit.PairGradient(circle, state.Gradient)
	UIKit.Shadow(circle, UITheme.SmallShadowOffset)

	-- The effect layer (z 4) sits behind the glyph (z 5).
	local fxRoot = Instance.new("Frame")
	fxRoot.Name = "Fx"
	fxRoot.BackgroundTransparency = 1
	fxRoot.Size = UDim2.fromScale(1, 1)
	fxRoot.ZIndex = 4
	fxRoot.Parent = circle
	local builder = FX_BUILDERS[state.Fx]
	local step: (number) -> () = if builder then builder(fxRoot) else function(_: number) end

	local glyph = UIKit.Label({
		Name = "Glyph",
		Text = state.Glyph,
		TextSize = 34,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 5,
		Stroke = GLYPH_STROKE,
		Parent = circle,
	})
	local timer = UIKit.Label({
		Name = "Timer",
		Text = "",
		Font = Fonts.Display,
		TextSize = TIMER_SIZE,
		Size = UDim2.new(1, 0, 0, TIMER_HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Stroke = 2,
		Parent = frame,
	})
	-- A clear tap target over the whole cell (>= 44 px after the phone scale).
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 8
	hit.Parent = frame

	local cell: Cell = {
		Id = state.Id,
		Frame = frame,
		Circle = circle,
		Glyph = glyph,
		FxRoot = fxRoot,
		Step = step,
		Timer = timer,
		Hit = hit,
		Fit = fitSize,
		Leaving = false,
		State = state,
	}
	sizeCell(cell, fitSize)

	local id = state.Id
	hit.MouseEnter:Connect(function()
		hoverEnter(id)
	end)
	hit.MouseLeave:Connect(function()
		hoverLeave(id)
	end)
	hit.Activated:Connect(function()
		tapCell(id)
	end)
	return cell
end

-- Text and badge of a cell from its current state.
local function updateCell(cell: Cell, state: EffectState)
	cell.State = state
	if state.Seconds then
		cell.Timer.Text = secondsText(state.Seconds)
	elseif state.Ready then
		cell.Timer.Text = "READY"
	else
		cell.Timer.Text = ""
	end
	if state.Badge then
		local badge = UIKit.Badge(cell.Circle, 1)
		badge.Text = state.Badge
		badge.Visible = true
	else
		local badge = cell.Circle:FindFirstChild("Badge")
		if badge and badge:IsA("GuiObject") then
			badge.Visible = false
		end
	end
end

local function removeCell(cell: Cell)
	if cell.Leaving then
		return
	end
	cell.Leaving = true
	cells[cell.Id] = nil
	if shownId == cell.Id then
		closeTooltip()
	end
	-- The same UIScale PopIn used (a second one would not stack).
	local scale = cell.Frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = cell.Frame
	local tween = TweenService:Create(scale, TweenInfo.new(SHRINK_SECONDS), { Scale = 0 })
	tween.Completed:Once(function()
		cell.Frame:Destroy()
	end)
	tween:Play()
end

--[[ Placement ---------------------------------------------------------------------- ]]

local function overlaps(a: Rect, b: Rect): boolean
	local ox = math.min(a.Position.X + a.Size.X, b.Position.X + b.Size.X) - math.max(a.Position.X, b.Position.X)
	local oy = math.min(a.Position.Y + a.Size.Y, b.Position.Y + b.Size.Y) - math.max(a.Position.Y, b.Position.Y)
	return ox > 1 and oy > 1
end

-- Sizes the tray to its cells and puts it 16 px from the left with its
-- bottom level with the bottom row's bottom edge (see the header for what
-- it does when it would touch the left column or the bottom row).
local function place()
	local count = 0
	for _, cell in cells do
		if not cell.Leaving then
			count += 1
		end
	end
	local scale = UIKit.EffectiveScale(tray)
	local view = viewportSize()
	local inset = GuiService:GetGuiInset().Y
	local obstacles: { [string]: Rect } = if hooks and count > 0 then hooks.GetObstacles() else {}

	-- The screen rect (raw AbsolutePosition space) of a fit at `shift` px (logical) from the left margin.
	local function rectFor(circle: number, perRow: number, shift: number): Rect
		local rows = math.max(1, math.ceil(count / perRow))
		local width = math.min(count, perRow) * cellWidth(circle)
		local height = rows * cellHeight(circle) + (rows - 1) * ROW_GAP
		return {
			Position = Vector2.new((LEFT_MARGIN + shift) * scale, view.Y - (BOTTOM_BASE + height) * scale),
			Size = Vector2.new(width * scale, height * scale),
		}
	end
	local function touches(rect: Rect): { string }
		local hit: { string } = {}
		for name, other in obstacles do
			-- Obstacle rects carry the top-bar inset, the tray's don't.
			if overlaps(rect, { Position = other.Position - Vector2.new(0, inset), Size = other.Size }) then
				table.insert(hit, name)
			end
		end
		return hit
	end

	local circle, perRow, shift = FITS[1][1], FITS[1][2], 0
	local found = false
	for _, fit in FITS do
		circle, perRow = fit[1], fit[2]
		if #touches(rectFor(circle, perRow, 0)) == 0 then
			found = true
			break
		end
	end
	if not found then
		-- Still touching: sit to the right of whatever the smallest fit hits.
		local hit = touches(rectFor(circle, perRow, 0))
		local right = 0
		for _, name in hit do
			local other = obstacles[name]
			right = math.max(right, (other.Position.X + other.Size.X) / scale)
		end
		shift = math.max(0, right + BESIDE_GAP - LEFT_MARGIN)
	end

	fitSize, fitPerRow = circle, perRow
	for _, cell in cells do
		if cell.Fit ~= circle then
			sizeCell(cell, circle)
		end
	end
	local rows = math.max(1, math.ceil(count / perRow))
	gridLayout.FillDirectionMaxCells = perRow
	gridLayout.CellSize = UDim2.fromOffset(cellWidth(circle), cellHeight(circle))
	gridLayout.CellPadding = UDim2.fromOffset(0, ROW_GAP)
	tray.Size = UDim2.fromOffset(perRow * cellWidth(circle), rows * cellHeight(circle) + (rows - 1) * ROW_GAP)
	tray.Position = UDim2.new(0, LEFT_MARGIN + shift, 1, -BOTTOM_BASE)
end

--[[ Refresh -------------------------------------------------------------------------- ]]

local function refresh()
	local hidden = TycoonController.IsTutorialActive() or not TycoonController.HasSynced()
	screenGui.Enabled = not hidden
	local states: { [string]: EffectState } = {}
	if not hidden then
		for _, state in collect() do
			states[state.Id] = state
		end
	end
	for id, cell in cells do
		if not states[id] then
			removeCell(cell)
		end
	end
	for id, state in states do
		local cell = cells[id]
		if cell then
			updateCell(cell, state)
		else
			local built = buildCell(state)
			cells[id] = built
			updateCell(built, state)
			-- Pops in (0.85 -> 1) as it's gained.
			UIKit.PopIn(built.Frame)
		end
	end
	place()
	local shown = if shownId then cells[shownId] else nil
	if shown and not shown.Leaving then
		fillTooltip(shown)
	end
	if shownId then
		placeTooltip()
	end
end

--[[ Public ---------------------------------------------------------------------------- ]]

-- Screen-px centre of an effect's icon ("Income" | "Luck" | "Server" | ...),
-- or the tray's first slot when it isn't up yet (the purchase flight lands
-- where the icon is about to appear).
function EffectsTray.GetTarget(id: string): Vector2
	local cell = cells[id]
	if cell and not cell.Leaving then
		local circle = cell.Circle
		return circle.AbsolutePosition + circle.AbsoluteSize / 2
	end
	local scale = UIKit.EffectiveScale(tray)
	local view = viewportSize()
	local circle = fitSize
	return Vector2.new((LEFT_MARGIN + CELL_SIDE_GAP / 2 + circle / 2) * scale, view.Y - (BOTTOM_BASE + cellHeight(circle) - circle / 2) * scale)
end

-- A little bounce on the icon (the purchase flight just landed on it).
function EffectsTray.Pop(id: string)
	local cell = cells[id]
	if cell and not cell.Leaving then
		UIKit.SelectFeedback(cell.Circle)
	end
end

export type CellView = {
	Id: string,
	Timer: string,
	Badge: string?,
	CircleSize: Vector2,
	HitSize: Vector2,
	Glyph: string, -- the glyph's text
	GlyphSize: number, -- its TextSize
	FxCount: number, -- parts in the effect layer behind it
	Position: Vector2, -- the cell's top-left, screen px (top-bar inset added back, as the HUD rects)
	Size: Vector2,
}

-- /selftest: what the tray draws right now.
function EffectsTray.GetCells(): { CellView }
	local inset = GuiService:GetGuiInset().Y
	local views: { CellView } = {}
	for id, cell in cells do
		if not cell.Leaving then
			local badge = cell.Circle:FindFirstChild("Badge")
			table.insert(views, {
				Id = id,
				Timer = cell.Timer.Text,
				Badge = if badge and badge:IsA("TextLabel") and badge.Visible then badge.Text else nil,
				CircleSize = cell.Circle.AbsoluteSize,
				HitSize = cell.Hit.AbsoluteSize,
				Glyph = cell.Glyph.Text,
				GlyphSize = cell.Glyph.TextSize,
				FxCount = #cell.FxRoot:GetChildren(),
				Position = cell.Frame.AbsolutePosition + Vector2.new(0, inset),
				Size = cell.Frame.AbsoluteSize,
			})
		end
	end
	return views
end

export type TooltipView = {
	Visible: boolean,
	Name: string,
	Plain: string,
	Time: string,
	Position: Vector2, -- the card's top-left, screen px (AbsolutePosition space)
	Size: Vector2, -- screen px
	Scale: number, -- the tray's UI scale (logical px x Scale = screen px)
}

-- /selftest: the tooltip card as it reads now.
function EffectsTray.GetTooltip(): TooltipView
	return {
		Visible = tooltip.Visible,
		Name = tooltipName.Text,
		Plain = tooltipPlain.Text,
		Time = tooltipTime.Text,
		Position = tooltip.AbsolutePosition,
		Size = tooltip.AbsoluteSize,
		Scale = UIKit.EffectiveScale(tray),
	}
end

-- /selftest: the cell's MouseEnter / MouseLeave, and a tap on it (the same
-- handlers the real events call; a script cannot fire the real ones).
function EffectsTray.TestHover(id: string, entering: boolean)
	if entering then
		hoverEnter(id)
	else
		hoverLeave(id)
	end
end

function EffectsTray.TestTap(id: string)
	tapCell(id)
end

-- /selftest: forces a refresh now (tests don't wait for the next tick).
function EffectsTray.Refresh()
	refresh()
end

function EffectsTray.Init(hudHooks: Hooks)
	hooks = hudHooks
	screenGui = UIKit.Screen("EffectsTray", 39)

	tray = Instance.new("Frame")
	tray.Name = "Tray"
	tray.BackgroundTransparency = 1
	tray.AnchorPoint = Vector2.new(0, 1)
	tray.Size = UDim2.fromOffset(fitPerRow * cellWidth(fitSize), cellHeight(fitSize))
	tray.Parent = screenGui
	gridLayout = Instance.new("UIGridLayout")
	gridLayout.FillDirection = Enum.FillDirection.Horizontal
	gridLayout.FillDirectionMaxCells = fitPerRow
	gridLayout.StartCorner = Enum.StartCorner.BottomLeft
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gridLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = tray

	-- One tooltip for the whole tray, above whichever icon is shown: a dark
	-- card (max 220 px wide) with its arrow on the icon.
	tooltip = Instance.new("Frame")
	tooltip.Name = "Tooltip"
	tooltip.BackgroundColor3 = Colors.Panel
	tooltip.BorderSizePixel = 0
	tooltip.AnchorPoint = Vector2.new(0, 1)
	tooltip.AutomaticSize = Enum.AutomaticSize.XY
	tooltip.Size = UDim2.new()
	tooltip.Visible = false
	tooltip.ZIndex = 10
	tooltip.Parent = screenGui
	UIKit.Corner(tooltip, 12)
	UIKit.Stroke(tooltip, 2)
	-- The text lives in its own padded column.
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.AutomaticSize = Enum.AutomaticSize.XY
	content.Size = UDim2.new()
	content.ZIndex = 11
	content.Parent = tooltip
	UIKit.Padding(content, TOOLTIP_PAD, TOOLTIP_PAD + 2, TOOLTIP_PAD, TOOLTIP_PAD + 2)
	local lines = Instance.new("UIListLayout")
	lines.SortOrder = Enum.SortOrder.LayoutOrder
	lines.Padding = UDim.new(0, 2)
	lines.Parent = content
	local function line(name: string, order: number, font: Font, color: Color3): TextLabel
		local label = UIKit.Label({
			Name = name,
			Text = "",
			Font = font,
			TextSize = TOOLTIP_TEXT_SIZE,
			TextColor3 = color,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.new(),
			LayoutOrder = order,
			ZIndex = 12,
			Parent = content,
		})
		-- Wraps at the card's max width less its padding, shrinks to short text.
		local limit = Instance.new("UISizeConstraint")
		limit.MaxSize = Vector2.new(TOOLTIP_MAX_WIDTH - 2 * (TOOLTIP_PAD + 2), math.huge)
		limit.Parent = label
		return label
	end
	tooltipName = line("Name", 1, Fonts.Display, Colors.Text)
	tooltipPlain = line("Plain", 2, Fonts.Body, Colors.Muted)
	tooltipTime = line("Time", 3, Fonts.BodyHeavy, Colors.GoldLabel)
	-- The arrow: a rotated square under the card (a sibling, so the card's
	-- body hides its top half), with a small patch over the card's own rim
	-- where the two meet.
	tooltipArrow = Instance.new("Frame")
	tooltipArrow.Name = "TooltipArrow"
	tooltipArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	tooltipArrow.Size = UDim2.fromOffset(TOOLTIP_ARROW, TOOLTIP_ARROW)
	tooltipArrow.Rotation = 45
	tooltipArrow.BackgroundColor3 = Colors.Panel
	tooltipArrow.BorderSizePixel = 0
	tooltipArrow.Visible = false
	tooltipArrow.ZIndex = 9
	tooltipArrow.Parent = screenGui
	UIKit.Stroke(tooltipArrow, 2)
	tooltipCover = Instance.new("Frame")
	tooltipCover.Name = "TooltipArrowCover"
	tooltipCover.AnchorPoint = Vector2.new(0.5, 0.5)
	tooltipCover.Size = UDim2.fromOffset(TOOLTIP_ARROW, 6)
	tooltipCover.BackgroundColor3 = Colors.Panel
	tooltipCover.BorderSizePixel = 0
	tooltipCover.Visible = false
	tooltipCover.ZIndex = 11
	tooltipCover.Parent = screenGui

	-- A tap elsewhere closes a pinned tooltip.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		local id = shownId
		if not id or not pinned then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local cell = cells[id]
		local point = Vector2.new(input.Position.X, input.Position.Y)
		if cell then
			local topLeft, size = cell.Frame.AbsolutePosition, cell.Frame.AbsoluteSize
			-- Input positions start under the top bar; this gui ignores that inset.
			local inset = GuiService:GetGuiInset().Y
			local y = point.Y + inset
			if point.X >= topLeft.X and point.X <= topLeft.X + size.X and y >= topLeft.Y and y <= topLeft.Y + size.Y then
				return
			end
		end
		closeTooltip()
	end)

	-- The effect layers move only while the tray is on screen with something in it.
	RunService.Heartbeat:Connect(function()
		if not screenGui.Enabled or next(cells) == nil then
			return
		end
		local now = os.clock()
		for _, cell in cells do
			if not cell.Leaving then
				cell.Step(now)
			end
		end
		if shownId then
			placeTooltip()
		end
	end)

	UIKit.LayoutChanged:Connect(refresh)
	task.spawn(function()
		while true do
			refresh()
			task.wait(TICK_SECONDS)
		end
	end)
end

return EffectsTray
