--!strict
--[[
	EffectsTray
	-----------
	The active effects as round cartoon STICKER badges with a timer under
	each, a COLUMN on the RIGHT edge (clear of the weapon bar at the bottom
	and the HUD on the left). Icons stack downward from 35% of the screen
	height; when the column would run into the phone's jump button it wraps
	into a second column to the LEFT of the first.

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
	dark card LEFT of the icon with an arrow to it, max 220 px wide, 14 px
	text, clamped on screen: the effect's name in bold, its Plain line
	("Double cash for 1 hour") and "12:41 left" / "×3 left" / "Ready".
	Effects pop in (0.85 -> 1, 0.15 s) when gained and shrink out when they
	end.

	Placement: RIGHT_MARGIN (12 px) from the right edge, top at 35% of the
	screen height (never above the top bar). On a phone the Roblox jump button
	(bottom right: JumpRectFor, Roblox's TouchJump numbers) plus 12 px is an
	obstacle, so the column ends above it and wraps into more columns to the
	left (the first column is the rightmost). The plan tries the icons at 60 px,
	then 48 px, each from 35%, then from the top; the first spot that touches no
	HUD rect, the weapon bar or the jump button wins; with none, the least overlap.
	EffectsTray.PlanTrayFor / PlanTooltipFor are that maths on their own
	(logical px, screen space), so /selftest runs them at 1251 x 666,
	1366 x 768 and 844 x 390.

	The tooltip tries LEFT of the icon, ABOVE-LEFT, BELOW-LEFT, then centred
	ABOVE, centred BELOW and RIGHT, each against every HUD rect; none clear ->
	the card narrows to 140 px, and with still none the one that overlaps
	least is used.
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

-- Placement tries these icon sizes (px) in order.
local FITS = { 60, 48 }
local GLYPH_FRACTION = 34 / 60 -- of the circle: a 34 px glyph on a 60 px badge
local TIMER_SIZE = 15
local TIMER_HEIGHT = 18
local TIMER_GAP = 4
local CELL_SIDE_GAP = 8
local ROW_GAP = 6
local RIGHT_MARGIN = 12
local TOP_FRACTION = 0.35 -- the column starts this far down the screen
local TOP_MIN = UIKit.TOP_BAR_HEIGHT + 8 -- never above the Roblox top bar
local BOTTOM_EDGE = 16 -- px kept free under the column when there is no jump button
local JUMP_GAP = 12 -- px between the column and the jump button
local SHRINK_SECONDS = 0.15
local TICK_SECONDS = 0.25
local TOOLTIP_GAP = 6
local TOOLTIP_MAX_WIDTH = 220
local TOOLTIP_MIN_WIDTH = 140 -- the narrow card used when no spot is clear at full width
local TOOLTIP_TEXT_SIZE = 14
local TOOLTIP_PAD = 10
local TOOLTIP_ARROW = 12 -- the rotated square that points at the icon
local TOOLTIP_EDGE = 8 -- px kept clear of the screen edge
local TOOLTIP_LAYER_ABOVE_HUD = 5 -- the tooltip gui's DisplayOrder over the HUD's
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

export type TrayPlan = {
	Circle: number, -- icon px
	PerColumn: number, -- icons in a full column
	Columns: number,
	Top: number, -- y of the column's top
	Rect: Rect, -- the tray's cells
	Hits: { string }, -- obstacles it still touches (empty = clear)
}

export type TooltipPlan = {
	Side: string, -- "Left" | "Above" | "Below" | "Right"
	Left: number,
	Top: number, -- of the card ("Above": its bottom is AboveBottom)
	AboveBottom: number,
	Overlap: number, -- px² still touching a HUD rect (0 = clear)
	OnScreen: boolean,
	Hits: { string },
}

export type Hooks = {
	-- Every HUD rect the tray must stay clear of (left column, bottom row),
	-- screen px with the top-bar inset added back (HudController.GetObstacleRects).
	GetObstacles: () -> { [string]: Rect },
	-- Screen-px rect (AbsolutePosition space) of the HUD bottom row, or nil.
	GetBottomRowRect: () -> Rect?,
	-- The HUD ScreenGui's DisplayOrder: the tooltip layer sits just above it.
	GetDisplayOrder: () -> number,
}

local hooks: Hooks? = nil
local screenGui: ScreenGui
-- The tooltip, its arrow and cover live in their own ScreenGui above the HUD
-- (the tray's own layer is below it, so a tooltip over the HUD's left column
-- was drawn under it).
local tooltipGui: ScreenGui
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
local tooltipMax = TOOLTIP_MAX_WIDTH -- the card's current max width (narrowed when nothing is clear)
local tooltipLimits: { UISizeConstraint } = {}
-- What the last placement settled on (icon px, icons per column).
local fitSize, fitPerColumn = FITS[1], 1
local lastPlan: TrayPlan? = nil

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

-- The card wraps at `width` less its padding.
local function setTooltipMax(width: number)
	if tooltipMax == width then
		return
	end
	tooltipMax = width
	for _, limit in tooltipLimits do
		limit.MaxSize = Vector2.new(width - 2 * (TOOLTIP_PAD + 2), math.huge)
	end
end

local function closeTooltip()
	shownId = nil
	pinned = false
	pinToken += 1
	tooltip.Visible = false
	tooltipArrow.Visible = false
	tooltipCover.Visible = false
	setTooltipMax(TOOLTIP_MAX_WIDTH)
end

-- The card's three lines from the shown cell's live state.
local function fillTooltip(cell: Cell)
	tooltipName.Text = cell.State.Name
	tooltipPlain.Text = cell.State.Plain
	tooltipTime.Text = cell.State.Tail
end

--[[ Placement maths (pure) ----------------------------------------------------------
	Logical px in screen space: AbsolutePosition + the top-bar inset, divided
	by the gui's UIScale (the same space as the Position offsets of this
	gui's children). The HUD's obstacle rects arrive in the same space.
]]

local function overlapArea(a: Rect, b: Rect): number
	local ox = math.min(a.Position.X + a.Size.X, b.Position.X + b.Size.X) - math.max(a.Position.X, b.Position.X)
	local oy = math.min(a.Position.Y + a.Size.Y, b.Position.Y + b.Size.Y) - math.max(a.Position.Y, b.Position.Y)
	if ox > 1 and oy > 1 then
		return ox * oy
	end
	return 0
end

-- Names and total area of the obstacles `rect` touches.
local function touching(rect: Rect, obstacles: { [string]: Rect }): ({ string }, number)
	local names: { string } = {}
	local total = 0
	for name, other in obstacles do
		local area = overlapArea(rect, other)
		if area > 0 then
			table.insert(names, name)
			total += area
		end
	end
	table.sort(names)
	return names, total
end

-- Roblox's jump button on a touch screen (TouchJump: 70 px at 20 px from the
-- bottom on a small screen, 120 px higher up on a larger one; 1.5 x its size
-- less 10 from the right), as a rect in the `view`'s logical px. nil on desktop.
function EffectsTray.JumpRectFor(view: Vector2, scale: number, phone: boolean): Rect?
	if not phone then
		return nil
	end
	local small = math.min(view.X, view.Y) * scale < 500
	local size = if small then 70 else 120
	local bottomGap = if small then 20 else size * 1.75 - size
	local left = view.X * scale - (size * 1.5 - 10)
	local top = view.Y * scale - size - bottomGap
	return { Position = Vector2.new(left, top) / scale, Size = Vector2.new(size, size) / scale }
end

-- Where the tray goes for `count` cells in a `view` (logical px): see the
-- header for the order it tries. `jump` is JumpRectFor's rect (nil: none).
function EffectsTray.PlanTrayFor(view: Vector2, obstacles: { [string]: Rect }, count: number, jump: Rect?): TrayPlan
	local cellCount = math.max(1, count)
	local blocked: { [string]: Rect } = table.clone(obstacles)
	local bottom = view.Y - BOTTOM_EDGE
	if jump then
		blocked.JumpButton = {
			Position = jump.Position - Vector2.new(JUMP_GAP, JUMP_GAP),
			Size = jump.Size + Vector2.new(2 * JUMP_GAP, 2 * JUMP_GAP),
		}
		bottom = math.min(bottom, jump.Position.Y - JUMP_GAP)
	end
	local best: TrayPlan? = nil
	local bestScore = math.huge
	local function consider(circle: number, top: number): TrayPlan?
		local pitch = cellHeight(circle) + ROW_GAP
		local perColumn = math.clamp(math.floor((bottom - top + ROW_GAP) / pitch), 1, cellCount)
		local columns = math.ceil(cellCount / perColumn)
		local width = columns * cellWidth(circle)
		local height = perColumn * pitch - ROW_GAP
		local rect: Rect = {
			Position = Vector2.new(view.X - RIGHT_MARGIN - width, top),
			Size = Vector2.new(width, height),
		}
		local hits, area = touching(rect, blocked)
		-- Off the screen counts as a heavy overlap.
		if rect.Position.X < 0 or rect.Position.Y < 0 or rect.Position.Y + height > view.Y then
			area += 1e6
		end
		local plan: TrayPlan = { Circle = circle, PerColumn = perColumn, Columns = columns, Top = top, Rect = rect, Hits = hits }
		if area < bestScore then
			best, bestScore = plan, area
		end
		return if area == 0 then plan else nil
	end
	-- 60 px then 48 px, from 35% of the screen height, then from the top bar.
	for _, top in { math.max(view.Y * TOP_FRACTION, TOP_MIN), TOP_MIN } do
		for _, circle in FITS do
			local plan = consider(circle, top)
			if plan then
				return plan
			end
		end
	end
	return best :: TrayPlan
end

-- The circle of the tray's `slot`-th cell (1 = top of the right column, then
-- down, then the next column to the left).
function EffectsTray.CircleRectFor(plan: TrayPlan, slot: number): Rect
	local column = (slot - 1) // plan.PerColumn
	local row = (slot - 1) % plan.PerColumn
	local cellLeft = plan.Rect.Position.X + plan.Rect.Size.X - (column + 1) * cellWidth(plan.Circle)
	return {
		Position = Vector2.new(
			cellLeft + (cellWidth(plan.Circle) - plan.Circle) / 2,
			plan.Rect.Position.Y + row * (cellHeight(plan.Circle) + ROW_GAP)
		),
		Size = Vector2.new(plan.Circle, plan.Circle),
	}
end

-- Candidates, first that is on screen and clears every HUD rect wins (the
-- tray is a column on the right edge, so the sides are mirrored):
-- 1. LEFT of the icon, centred on the badge, its arrow pointing right;
-- 2. ABOVE-LEFT: over the icon, pushed left; 3. BELOW-LEFT: under the cell,
-- pushed left; 4. ABOVE and 5. BELOW, centred on the icon; 6. RIGHT of it.
-- None clear: the on-screen one that overlaps least (the caller narrows
-- the card first).
function EffectsTray.PlanTooltipFor(view: Vector2, obstacles: { [string]: Rect }, circle: Rect, size: Vector2): TooltipPlan
	local width, height = size.X, size.Y
	local centreX = circle.Position.X + circle.Size.X / 2
	local centreY = circle.Position.Y + circle.Size.Y / 2
	local rightEdge = circle.Position.X + circle.Size.X
	local aboveBottom = circle.Position.Y - TOOLTIP_GAP - TOOLTIP_ARROW / 2
	-- Under the cell: past the timer.
	local belowTop = circle.Position.Y + circle.Size.Y + TIMER_GAP + TIMER_HEIGHT + TOOLTIP_GAP + TOOLTIP_ARROW / 2
	local sideTop = math.clamp(centreY - height / 2, TOOLTIP_EDGE, math.max(TOOLTIP_EDGE, view.Y - height - TOOLTIP_EDGE))
	local function clampX(left: number): number
		return math.clamp(left, TOOLTIP_EDGE, math.max(TOOLTIP_EDGE, view.X - width - TOOLTIP_EDGE))
	end
	local candidates = {
		{ Side = "Left", Left = circle.Position.X - TOOLTIP_GAP - TOOLTIP_ARROW / 2 - width, Top = sideTop },
		{ Side = "Above", Left = clampX(circle.Position.X + 24 - width), Top = aboveBottom - height },
		{ Side = "Below", Left = clampX(circle.Position.X + 24 - width), Top = belowTop },
		{ Side = "Above", Left = clampX(centreX - width / 2), Top = aboveBottom - height },
		{ Side = "Below", Left = clampX(centreX - width / 2), Top = belowTop },
		{ Side = "Right", Left = rightEdge + TOOLTIP_GAP + TOOLTIP_ARROW / 2, Top = sideTop },
	}
	local chosen: TooltipPlan? = nil
	local fallback: TooltipPlan? = nil
	local lastResort: TooltipPlan? = nil
	for index, candidate in candidates do
		local rect: Rect = { Position = Vector2.new(candidate.Left, candidate.Top), Size = size }
		local onScreen = rect.Position.X >= TOOLTIP_EDGE
			and rect.Position.Y >= TOOLTIP_EDGE
			and rect.Position.X + width + TOOLTIP_EDGE <= view.X
			and rect.Position.Y + height + TOOLTIP_EDGE <= view.Y
		local hits, area = touching(rect, obstacles)
		local plan: TooltipPlan = {
			Side = candidate.Side,
			Left = candidate.Left,
			Top = candidate.Top,
			AboveBottom = aboveBottom,
			Overlap = area,
			OnScreen = onScreen,
			Hits = hits,
		}
		if onScreen and area == 0 then
			chosen = plan
			break
		end
		if onScreen and (not fallback or area < fallback.Overlap) then
			fallback = plan
		end
		-- The last resort: the first "Above" card, on screen or not.
		if index == 2 then
			lastResort = plan
		end
	end
	return (chosen or fallback or lastResort) :: TooltipPlan
end

-- The shown icon's tooltip. Runs every frame while open (the card's size
-- settles a frame after its text).
local function placeTooltip()
	local id = shownId
	local cell = if id then cells[id] else nil
	if not cell or cell.Leaving then
		closeTooltip()
		return
	end
	local scale = UIKit.EffectiveScale(tray)
	local inset = GuiService:GetGuiInset().Y
	local view = viewportSize() / scale
	local circle: Rect = {
		Position = (cell.Circle.AbsolutePosition + Vector2.new(0, inset)) / scale,
		Size = cell.Circle.AbsoluteSize / scale,
	}
	local size = tooltip.AbsoluteSize / scale
	local margin = TOOLTIP_ARROW + 6
	local obstacles: { [string]: Rect } = {}
	if hooks then
		for name, rect in hooks.GetObstacles() do
			obstacles[name] = { Position = rect.Position / scale, Size = rect.Size / scale }
		end
	end
	local plan = EffectsTray.PlanTooltipFor(view, obstacles, circle, size)
	if plan.Overlap > 0 and tooltipMax > TOOLTIP_MIN_WIDTH then
		-- Nothing is clear at full width: narrow the card (it re-plans next frame).
		setTooltipMax(TOOLTIP_MIN_WIDTH)
	end
	local centreY = circle.Position.Y + circle.Size.Y / 2
	local centreX = circle.Position.X + circle.Size.X / 2
	if plan.Side == "Right" or plan.Side == "Left" then
		local left, top = plan.Left, plan.Top
		local arrowY = top + math.clamp(centreY - top, margin, math.max(margin, size.Y - margin))
		local arrowX = if plan.Side == "Right" then left else left + size.X
		tooltip.AnchorPoint = Vector2.new(0, 0)
		tooltip.Position = UDim2.fromOffset(left, top)
		tooltipCover.Size = UDim2.fromOffset(6, TOOLTIP_ARROW)
		tooltipArrow.Position = UDim2.fromOffset(arrowX, arrowY)
		tooltipCover.Position = UDim2.fromOffset(arrowX, arrowY)
	else
		local left = plan.Left
		local arrowX = math.clamp(centreX - left, margin, math.max(margin, size.X - margin))
		local above = plan.Side == "Above"
		-- Above: the card's bottom is on the arrow; below: its top is.
		local edgeY = if above then plan.AboveBottom else plan.Top
		tooltip.AnchorPoint = Vector2.new(0, if above then 1 else 0)
		tooltip.Position = UDim2.fromOffset(left, edgeY)
		tooltipCover.Size = UDim2.fromOffset(TOOLTIP_ARROW, 6)
		tooltipArrow.Position = UDim2.fromOffset(left + arrowX, edgeY)
		tooltipCover.Position = UDim2.fromOffset(left + arrowX, edgeY)
	end
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
	setTooltipMax(TOOLTIP_MAX_WIDTH)
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

-- Sizes the tray to its cells and puts it where PlanTrayFor says (see the
-- header): a column on the right edge from 35% of the screen height, wrapping
-- left above the phone's jump button.
local function place()
	local count = 0
	for _, cell in cells do
		if not cell.Leaving then
			count += 1
		end
	end
	local scale = UIKit.EffectiveScale(tray)
	local view = viewportSize() / scale
	local obstacles: { [string]: Rect } = {}
	if hooks and count > 0 then
		for name, rect in hooks.GetObstacles() do
			obstacles[name] = { Position = rect.Position / scale, Size = rect.Size / scale }
		end
	end
	local jump = EffectsTray.JumpRectFor(view, scale, UIKit.IsPhone())
	local plan = EffectsTray.PlanTrayFor(view, obstacles, count, jump)
	local circle, perColumn = plan.Circle, plan.PerColumn
	lastPlan = plan
	fitSize, fitPerColumn = circle, perColumn
	for _, cell in cells do
		if cell.Fit ~= circle then
			sizeCell(cell, circle)
		end
	end
	gridLayout.FillDirectionMaxCells = perColumn
	gridLayout.CellSize = UDim2.fromOffset(cellWidth(circle), cellHeight(circle))
	gridLayout.CellPadding = UDim2.fromOffset(0, ROW_GAP)
	tray.Size = UDim2.fromOffset(plan.Rect.Size.X, plan.Rect.Size.Y)
	tray.Position = UDim2.new(1, -RIGHT_MARGIN, 0, plan.Top)
end

--[[ Refresh -------------------------------------------------------------------------- ]]

local function refresh()
	local hidden = TycoonController.IsTutorialActive() or not TycoonController.HasSynced()
	screenGui.Enabled = not hidden
	tooltipGui.Enabled = not hidden
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
	local top = if lastPlan then lastPlan.Top else math.max(view.Y / scale * TOP_FRACTION, TOP_MIN)
	return Vector2.new(view.X - (RIGHT_MARGIN + cellWidth(circle) / 2) * scale, (top + circle / 2) * scale)
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

-- /selftest: the tooltip layer's DisplayOrder (it must be above the HUD's).
function EffectsTray.GetTooltipDisplayOrder(): number
	return tooltipGui.DisplayOrder
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

-- /selftest: what the last placement settled on (nil before the first).
function EffectsTray.GetPlan(): TrayPlan?
	return lastPlan
end

-- /selftest: forces a refresh now (tests don't wait for the next tick).
function EffectsTray.Refresh()
	refresh()
end

function EffectsTray.Init(hudHooks: Hooks)
	hooks = hudHooks
	screenGui = UIKit.Screen("EffectsTray", 39)
	tooltipGui = UIKit.Screen("EffectsTooltip", hudHooks.GetDisplayOrder() + TOOLTIP_LAYER_ABOVE_HUD)

	tray = Instance.new("Frame")
	tray.Name = "Tray"
	tray.BackgroundTransparency = 1
	tray.AnchorPoint = Vector2.new(1, 0)
	tray.Size = UDim2.fromOffset(cellWidth(fitSize), cellHeight(fitSize))
	tray.Parent = screenGui
	gridLayout = Instance.new("UIGridLayout")
	gridLayout.FillDirection = Enum.FillDirection.Vertical
	gridLayout.FillDirectionMaxCells = fitPerColumn
	gridLayout.StartCorner = Enum.StartCorner.TopRight
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = tray

	-- One tooltip for the whole tray, beside whichever icon is shown (to its left): a dark
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
	tooltip.Parent = tooltipGui
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
		table.insert(tooltipLimits, limit)
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
	tooltipArrow.Parent = tooltipGui
	UIKit.Stroke(tooltipArrow, 2)
	tooltipCover = Instance.new("Frame")
	tooltipCover.Name = "TooltipArrowCover"
	tooltipCover.AnchorPoint = Vector2.new(0.5, 0.5)
	tooltipCover.Size = UDim2.fromOffset(TOOLTIP_ARROW, 6)
	tooltipCover.BackgroundColor3 = Colors.Panel
	tooltipCover.BorderSizePixel = 0
	tooltipCover.Visible = false
	tooltipCover.ZIndex = 11
	tooltipCover.Parent = tooltipGui

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
