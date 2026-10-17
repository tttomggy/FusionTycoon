--!strict
--[[
	EffectsTray
	-----------
	The active effects as round icons with a timer under each, bottom LEFT
	where Bubble Gum Simulator keeps its potion icons. Icons fill left to
	right, 4 to a row; more rows stack upward.

	  Income boost   ⚡ timer            (Boost / Quick Boost / Cash Burst bank)
	  Luck           🍀 timer + "×2"     (Luck Potion / Lucky Charm bank)
	  Server         🌐 timer            (the server Overclock)
	  Speed Boots    👟 timer
	  Safe Fusion    🛡 "×N" badge       (tokens you hold)
	  Fusion Spark   ⚗️ "×1" badge       (armed for the next fusion)
	  Coin Magnet    🧲 READY            (armed for the next rain)

	Every number comes from the synced data the old HUD pills used
	(TycoonController, ShopState): no new server state. Where the effect is a
	shop product the circle shows its live store icon (ShopPrices), else the
	glyph. Tap or hover an icon for a tooltip ("Rare orbs 2× more likely ·
	12:41 left"); one at a time, a tap elsewhere closes it. Effects pop in
	(0.85 -> 1, 0.15 s) when gained and shrink out when they end. Nothing
	flashes, the last minute included.

	Placement: 16 px from the left edge, its bottom level with the HUD bottom
	row's bottom edge. If it would touch the HUD's left column or the bottom
	row, the icons drop from 64 to 48 px, then to 3 per row; if it still
	touches (a phone with a tall left column) the tray sits to the right of
	the left column, still bottom-aligned.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local ShopPrices = require(ReplicatedStorage.Shared.Modules.ShopPrices)
local ShopState = require(ReplicatedStorage.Shared.Modules.ShopState)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TycoonController = require(script.Parent.Parent.Controllers.TycoonController)
local UIKit = require(script.Parent.UIKit)

local EffectsTray = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

-- Placement tries these in order (icon px, icons per row).
local FITS = { { 64, 4 }, { 48, 4 }, { 48, 3 } }
local ICON_FRACTION = 0.74 -- of the circle
local GLYPH_FRACTION = 0.5 -- of the circle
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

type EffectState = {
	Id: string,
	Order: number,
	Gradient: UITheme.GradientPair,
	Glyph: string,
	IconKey: string?, -- a shop product whose live icon the circle shows
	Seconds: number?, -- a timer under the circle ("12:41")
	Ready: boolean?, -- "READY" under the circle
	Badge: string?, -- "×2" on the circle's top-right
	Tip: string, -- the tooltip's first part
	Tail: string, -- its second part ("12:41 left")
}

type Cell = {
	Id: string,
	Frame: Frame,
	Circle: Frame,
	Image: ImageLabel,
	Glyph: TextLabel,
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
local tooltipLabel: TextLabel
local cells: { [string]: Cell } = {}
local shownId: string? = nil
local pinned = false
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
			Gradient = UITheme.Gradients.Violet,
			Glyph = "⚡",
			IconKey = "Boost",
			Seconds = income,
			Tip = "Double cash",
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
			IconKey = "LuckPotion",
			Seconds = luck,
			Badge = ("×%d"):format(ShopConfig.LuckPotionMultiplier),
			Tip = ("Rare orbs %d× more likely"):format(ShopConfig.LuckPotionMultiplier),
			Tail = ("%s left"):format(secondsText(luck)),
		})
	end
	local server = ShopState.GetOverclockSeconds()
	if server > 0 then
		table.insert(list, {
			Id = "Server",
			Order = 3,
			Gradient = UITheme.Gradients.Gold,
			Glyph = "🌐",
			IconKey = "Overclock",
			Seconds = server,
			Tip = ("Everyone here earns %d× cash"):format(ShopConfig.OverclockMultiplier),
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
			Glyph = QuestConfig.PowerUps.SpeedBoots.Glyph,
			Seconds = boots,
			Tip = ("Run %s× faster"):format(tostring(QuestConfig.PowerUps.SpeedBoots.SpeedMultiplier)),
			Tail = ("%s left"):format(secondsText(boots)),
		})
	end
	local tokens = TycoonController.GetShop().SafeFusionTokens
	if tokens > 0 then
		table.insert(list, {
			Id = "SafeFusion",
			Order = 5,
			Gradient = UITheme.Gradients.Indigo,
			Glyph = "🛡",
			IconKey = "SafeFusion1",
			Badge = ("×%d"):format(tokens),
			Tip = (ShopConfig.GetItem("SafeFusion1") :: ShopConfig.Item).Plain,
			Tail = ("%d left"):format(tokens),
		})
	end
	if TycoonController.IsArmed("FusionSpark") then
		table.insert(list, {
			Id = "FusionSpark",
			Order = 6,
			Gradient = UITheme.Gradients.Orange,
			Glyph = QuestConfig.PowerUps.FusionSpark.Glyph,
			Badge = "×1",
			Tip = QuestConfig.PowerUps.FusionSpark.Plain,
			Tail = "ready",
		})
	end
	if TycoonController.IsArmed("CoinMagnet") then
		table.insert(list, {
			Id = "CoinMagnet",
			Order = 7,
			Gradient = UITheme.Gradients.Green,
			Glyph = QuestConfig.PowerUps.CoinMagnet.Glyph,
			Ready = true,
			Tip = QuestConfig.PowerUps.CoinMagnet.Plain,
			Tail = "ready for the next rain",
		})
	end
	return list
end

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
	local icon = math.floor(circle * ICON_FRACTION)
	cell.Image.Size = UDim2.fromOffset(icon, icon)
	cell.Glyph.TextSize = math.floor(circle * GLYPH_FRACTION)
	cell.Timer.Position = UDim2.fromOffset(0, circle + TIMER_GAP)
end

local function closeTooltip()
	shownId = nil
	pinned = false
	tooltip.Visible = false
end

local function placeTooltip()
	local id = shownId
	local cell = if id then cells[id] else nil
	if not cell or cell.Leaving then
		closeTooltip()
		return
	end
	local scale = UIKit.EffectiveScale(tray)
	tooltipLabel.Text = ("%s · %s"):format(cell.State.Tip, cell.State.Tail)
	-- Left-aligned to the icon's cell, above it (the tray hugs the left edge).
	local leftEdge = cell.Frame.AbsolutePosition.X / scale
	tooltip.Position = UDim2.fromOffset(leftEdge, cell.Frame.AbsolutePosition.Y / scale - TOOLTIP_GAP)
	tooltip.Visible = true
end

local function openTooltip(id: string, pin: boolean)
	shownId = id
	pinned = pin
	placeTooltip()
end

local function buildCell(state: EffectState): Cell
	local frame = Instance.new("Frame")
	frame.Name = state.Id
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = state.Order
	frame.ZIndex = 2
	frame.Parent = tray

	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.AnchorPoint = Vector2.new(0.5, 0)
	circle.Position = UDim2.new(0.5, 0, 0, 0)
	circle.BackgroundColor3 = Colors.White
	circle.BorderSizePixel = 0
	circle.ZIndex = 3
	circle.Parent = frame
	UIKit.Corner(circle, 999)
	UIKit.Stroke(circle, 2, Colors.White)
	UIKit.PairGradient(circle, state.Gradient)
	UIKit.Shadow(circle, UITheme.SmallShadowOffset)

	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = 4
	image.Visible = false
	image.Parent = circle
	local glyph = UIKit.Label({
		Name = "Glyph",
		Text = state.Glyph,
		TextSize = 30,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
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
		Image = image,
		Glyph = glyph,
		Timer = timer,
		Hit = hit,
		Fit = fitSize,
		Leaving = false,
		State = state,
	}
	sizeCell(cell, fitSize)

	local id = state.Id
	hit.MouseEnter:Connect(function()
		if not pinned then
			openTooltip(id, false)
		end
	end)
	hit.MouseLeave:Connect(function()
		if not pinned and shownId == id then
			closeTooltip()
		end
	end)
	hit.Activated:Connect(function()
		if shownId == id and pinned then
			closeTooltip()
		else
			UIKit.SelectFeedback(circle)
			openTooltip(id, true)
		end
	end)
	return cell
end

-- Text, picture and badge of a cell from its current state.
local function updateCell(cell: Cell, state: EffectState)
	cell.State = state
	local icon = if state.IconKey then ShopPrices.GetIcon(state.IconKey) else nil
	cell.Image.Visible = icon ~= nil
	cell.Glyph.Visible = icon == nil
	if icon and cell.Image.Image ~= icon then
		cell.Image.Image = icon
	end
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

local function viewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1920, 1080)
end

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
				Position = cell.Frame.AbsolutePosition + Vector2.new(0, inset),
				Size = cell.Frame.AbsoluteSize,
			})
		end
	end
	return views
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

	-- One tooltip for the whole tray, above whichever icon is shown.
	tooltip = Instance.new("Frame")
	tooltip.Name = "Tooltip"
	tooltip.BackgroundColor3 = Colors.Panel
	tooltip.BorderSizePixel = 0
	tooltip.AnchorPoint = Vector2.new(1, 1)
	tooltip.AutomaticSize = Enum.AutomaticSize.XY
	tooltip.Size = UDim2.new()
	tooltip.Visible = false
	tooltip.ZIndex = 10
	tooltip.Parent = screenGui
	UIKit.Corner(tooltip, 12)
	UIKit.Stroke(tooltip, 2)
	UIKit.Padding(tooltip, 8, 12, 8, 12)
	tooltipLabel = UIKit.Label({
		Name = "Text",
		Text = "",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		ZIndex = 11,
		Parent = tooltip,
	})

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

	UIKit.LayoutChanged:Connect(refresh)
	task.spawn(function()
		while true do
			refresh()
			task.wait(TICK_SECONDS)
		end
	end)
end

return EffectsTray
