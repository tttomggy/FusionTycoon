--[[
	HudController
	-------------
	The always-on HUD (one ScreenGui, "Hud"):
	  * Goal tracker (top-left, under the Roblox top bar)
	  * Cash card: coin + counting-up cash, income/s and the multiplier pill
	  * Bottom buttons: UPGRADES (with an affordable-count badge) and ITEMS
	  * FloatPop: the "+$X" world pop FactoryController shows at the collector

	Nothing is placed in the top-left 170x60 px, which belongs to the Roblox
	top bar.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local GoalConfig = require(ReplicatedStorage.Shared.Config.GoalConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonController = require(script.Parent.TycoonController)
local InventoryController = require(script.Parent.InventoryController)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local UpgradesPanel = require(script.Parent.Parent.UI.UpgradesPanel)
local RebirthPanel = require(script.Parent.Parent.UI.RebirthPanel)
local IndexPanel = require(script.Parent.Parent.UI.IndexPanel)
local FusePanel = require(script.Parent.Parent.UI.FusePanel)
local ItemPickerUI = require(script.Parent.Parent.UI.ItemPickerUI)

local HudController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local localPlayer = Players.LocalPlayer

-- Layout (design px, before the phone UIScale). Phone values keep the cash
-- card's top edge clear of the top bar AFTER the 0.8 scale (76 * 0.8 > 60).
local LAYOUT = {
	Desktop = {
		GoalPosition = UDim2.fromOffset(12, 74),
		GoalWidth = 260,
		GoalBarHeight = 14,
		CashPosition = UDim2.fromOffset(12, 274),
		ButtonSize = Vector2.new(176, 64),
		ButtonTextSize = 22,
	},
	Phone = {
		GoalPosition = UDim2.fromOffset(10, 154),
		GoalWidth = 168,
		GoalBarHeight = 10,
		CashPosition = UDim2.fromOffset(10, 76),
		ButtonSize = Vector2.new(84, 60),
		ButtonTextSize = 13,
	},
}
local CASH_CARD_SIZE = Vector2.new(260, 96)
local PILL_ROW_WIDTH = 132 -- room for the rebirth pill and the Multiplier pill
local BOTTOM_MARGIN = 22
local BUTTON_GAP = 14

local CASH_POP_LIFETIME = 0.8
local CASH_POP_RISE_STUDS = 3

local screenGui: ScreenGui
local displayedCash = 0

local cashLabel: TextLabel
local incomeLabel: TextLabel
local multiplierPill: TextLabel
local rebirthPill: TextLabel

local goalHolder: Frame
local goalBody: Frame
local goalRewardLabel: TextLabel
local goalTextLabel: TextLabel
local goalBar: Frame
local goalCountLabel: TextLabel

local buttonRow: Frame
local upgradesButton: TextButton? = nil
local upgradesHolder: Frame? = nil
local rebirthReadyHolder: Frame
local buttonsByName: { [string]: TextButton } = {}
-- Buttons the goal marker wants highlighted; reapplied after a rebuild.
local highlighted: { [string]: boolean? } = {}

--[[ Income ---------------------------------------------------------------- ]]

local function getIncomePerSecond(): number
	return TycoonConfig.GetPassiveCashPerSecond(TycoonController.GetIncomeInputs())
end

-- Generators that are unlocked, not maxed, and affordable right now.
local function countAffordableUpgrades(): number
	local count = 0
	local cash = TycoonController.GetCash()
	local levels = TycoonController.GetGeneratorLevels()
	for _, generator in TycoonConfig.Generators do
		local level = levels[generator.Id] or 0
		if level < generator.MaxLevel
			and TycoonConfig.IsUnlocked(generator, levels)
			and cash >= TycoonConfig.GetUpgradeCost(generator, level)
		then
			count += 1
		end
	end
	return count
end

--[[ Goal tracker ---------------------------------------------------------- ]]

local function buildGoalTracker()
	local body, holder = UIKit.Panel({
		Name = "GoalTracker",
		Parent = screenGui,
		Size = UDim2.fromOffset(LAYOUT.Desktop.GoalWidth, 0),
		Position = LAYOUT.Desktop.GoalPosition,
		AutomaticSize = Enum.AutomaticSize.Y,
		Color = Colors.Panel,
	})
	goalHolder = holder
	goalBody = body
	-- Hidden until the server sends a goal (and after the last one).
	holder.Visible = false

	UIKit.Padding(body, 12, 14, 12, 14)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = body

	local headerRow = Instance.new("Frame")
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
		Size = UDim2.new(1, 0, 0, LAYOUT.Desktop.GoalBarHeight),
		Fill = UITheme.Gradients.Gold,
		LayoutOrder = 3,
		ZIndex = body.ZIndex + 1,
	})

	goalCountLabel = UIKit.Label({
		Name = "Count",
		Font = Fonts.Body,
		TextSize = 12,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 4,
		ZIndex = body.ZIndex + 1,
		Parent = body,
	})
end

export type GoalView = {
	Text: string,
	Reward: number,
	Current: number,
	Target: number,
	Unit: string?, -- e.g. "Rare"; nil hides the count line
}

-- Shows a goal on the tracker, or hides the tracker when `goal` is nil.
function HudController.SetGoal(goal: GoalView?)
	if not goal then
		goalHolder.Visible = false
		return
	end
	goalHolder.Visible = true
	goalRewardLabel.Text = "+" .. NumberFormat.Money(goal.Reward)
	goalTextLabel.Text = goal.Text
	UIKit.SetProgress(goalBar, if goal.Target > 0 then goal.Current / goal.Target else 0, true)
	if goal.Unit then
		goalCountLabel.Visible = true
		goalCountLabel.Text = ("%s / %s %s"):format(
			NumberFormat.Short(math.min(goal.Current, goal.Target)),
			NumberFormat.Short(goal.Target),
			goal.Unit
		)
	else
		goalCountLabel.Visible = false
	end
end

-- Completion flourish: flash the border Goal-coloured and pop the panel.
function HudController.FlashGoal()
	local stroke = goalBody:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Colors.Goal
		TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Color = Colors.Ink }):Play()
	end
	UIKit.PopIn(goalHolder)
end

--[[ Cash card ------------------------------------------------------------- ]]

local function buildCashCard(): Frame
	local body, holder = UIKit.Panel({
		Name = "CashCard",
		Parent = screenGui,
		Size = UDim2.fromOffset(CASH_CARD_SIZE.X, CASH_CARD_SIZE.Y),
		Position = LAYOUT.Desktop.CashPosition,
		Color = Colors.Panel,
	})
	UIKit.Padding(body, 12, 14, 12, 14)
	local z = body.ZIndex + 1

	-- Row 1: coin + amount.
	local coin = Instance.new("Frame")
	coin.Name = "Coin"
	coin.Size = UDim2.fromOffset(34, 34)
	coin.Position = UDim2.fromOffset(0, 3)
	coin.BackgroundColor3 = Colors.White
	coin.ZIndex = z
	coin.Parent = body
	UIKit.Corner(coin, 999)
	UIKit.PairGradient(coin, UITheme.Gradients.Green)
	UIKit.Stroke(coin, 3)
	UIKit.Label({
		Text = "$",
		Font = Fonts.Display,
		TextSize = 18,
		TextColor3 = Colors.CoinText,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z + 1,
		Parent = coin,
	})

	cashLabel = UIKit.Label({
		Name = "Cash",
		Text = "0",
		Font = Fonts.Display,
		TextSize = 34,
		TextColor3 = Colors.Cash,
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -44, 0, 40),
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})

	-- Row 2: income + multiplier pill.
	incomeLabel = UIKit.Label({
		Name = "Income",
		Font = Fonts.Body,
		TextSize = 16,
		RichText = true,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, -PILL_ROW_WIDTH, 0, 24),
		ZIndex = z,
		Parent = body,
	})

	-- Right-aligned pill row: the rebirth pill (hidden at 0 rebirths) then
	-- the Multiplier Pad pill.
	local pills = Instance.new("Frame")
	pills.Name = "Pills"
	pills.BackgroundTransparency = 1
	pills.AnchorPoint = Vector2.new(1, 0)
	pills.Position = UDim2.new(1, 0, 0, 46)
	pills.Size = UDim2.fromOffset(PILL_ROW_WIDTH, 24)
	pills.ZIndex = z
	pills.Parent = body
	local pillLayout = Instance.new("UIListLayout")
	pillLayout.FillDirection = Enum.FillDirection.Horizontal
	pillLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	pillLayout.Padding = UDim.new(0, 6)
	pillLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pillLayout.Parent = pills

	rebirthPill = UIKit.Pill({
		Name = "Rebirth",
		Parent = pills,
		Text = "",
		Gradient = UITheme.Gradients.Orange,
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		Height = 24,
		LayoutOrder = 1,
		ZIndex = z,
		TextStroke = 1.5,
	})
	local rebirthFill = rebirthPill.Parent :: Frame
	rebirthFill.Visible = false
	-- The pill is small; this clear button gives it a >= 44 px hit area.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Size = UDim2.new(1, 16, 0, UITheme.MinTapSize)
	hit.ZIndex = z + 2
	hit.Parent = rebirthFill
	hit.Activated:Connect(RebirthPanel.Open)

	multiplierPill = UIKit.Pill({
		Name = "Multiplier",
		Parent = pills,
		Text = "x1",
		Color = Colors.VioletPill,
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		Height = 24,
		LayoutOrder = 2,
		ZIndex = z,
	})

	return holder
end

local function onRenderStep(dt: number)
	local target = TycoonController.GetCash()
	-- Ease toward the real value so income "ticks up" instead of snapping;
	-- big drops (spending) snap immediately so it never shows cash you don't have.
	if target < displayedCash then
		displayedCash = target
	else
		displayedCash += (target - displayedCash) * math.min(1, dt * 8)
		if target - displayedCash < 0.5 then
			displayedCash = target
		end
	end
	-- The coin stands for "$": the number only.
	cashLabel.Text = NumberFormat.Short(math.floor(displayedCash))
end

--[[ Bottom buttons -------------------------------------------------------- ]]

local function buildBrowseEntries(): { any }
	local entries = {}
	for _, item in InventoryController.GetInventory() do
		local def = ItemConfig.GetItemById(item.ItemId)
		table.insert(entries, {
			Uid = item.Uid,
			ItemId = item.ItemId,
			Name = def and def.Name or item.ItemId,
			Tier = item.Tier,
			Mutation = item.Mutation,
			InUse = item.InUse == true,
		})
	end
	return entries
end

function HudController.OpenInventory()
	-- Browse mode: no onSelect, cards only show info.
	ItemPickerUI.Open(buildBrowseEntries(), nil, "YOUR ITEMS")
end

local function refreshBadge()
	if upgradesButton then
		UIKit.Badge(upgradesButton, countAffordableUpgrades())
	end
end

local GOAL_HIGHLIGHT_NAME = "GoalHighlight"

local function applyHighlight(name: string)
	local button = buttonsByName[name]
	if not button then
		return
	end
	local existing = button:FindFirstChild(GOAL_HIGHLIGHT_NAME)
	if not highlighted[name] then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end
	-- A separate overlay, because the button's own UIStroke is its ink border.
	local overlay = Instance.new("Frame")
	overlay.Name = GOAL_HIGHLIGHT_NAME
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = button.ZIndex + 6
	overlay.Parent = button
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		UIKit.Corner(overlay, corner.CornerRadius.Offset)
	end
	local stroke = UIKit.Stroke(overlay, 4, UITheme.Gradients.Gold.Top)
	TweenService:Create(
		stroke,
		TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.7 }
	):Play()
end

-- Pulsing 4 px gold outline on a HUD button ("Upgrades" or "Items") while
-- the current goal points at it.
function HudController.SetButtonHighlight(name: string, on: boolean)
	highlighted[name] = if on then true else nil
	applyHighlight(name)
end

local function buildButtons(isPhone: boolean)
	for _, child in buttonRow:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local layout = if isPhone then LAYOUT.Phone else LAYOUT.Desktop
	local size = UDim2.fromOffset(layout.ButtonSize.X, layout.ButtonSize.Y)

	local upgrades, holder = UIKit.Button({
		Name = "UpgradesButton",
		Parent = buttonRow,
		Style = "Green",
		Text = "UPGRADES",
		Icon = UITheme.Icons.Upgrades,
		IconStacked = isPhone,
		Size = size,
		TextSize = layout.ButtonTextSize,
		LayoutOrder = 1,
		OnClick = function()
			UpgradesPanel.Toggle()
		end,
	})
	upgradesButton = upgrades
	upgradesHolder = holder
	buttonsByName.Upgrades = upgrades
	local pulseScale = Instance.new("UIScale")
	pulseScale.Name = "PulseScale"
	pulseScale.Parent = holder

	buttonsByName.Items = UIKit.Button({
		Name = "ItemsButton",
		Parent = buttonRow,
		Style = "Blue",
		Text = "ITEMS",
		Icon = UITheme.Icons.Items,
		IconStacked = isPhone,
		Size = size,
		TextSize = layout.ButtonTextSize,
		LayoutOrder = 2,
		OnClick = HudController.OpenInventory,
	})

	buttonsByName.Index = UIKit.Button({
		Name = "IndexButton",
		Parent = buttonRow,
		Style = "Teal",
		Text = "INDEX",
		Icon = UITheme.Icons.Index,
		IconStacked = isPhone,
		Size = size,
		TextSize = layout.ButtonTextSize,
		LayoutOrder = 3,
		OnClick = IndexPanel.Toggle,
	})

	refreshBadge()
	for name in highlighted do
		applyHighlight(name)
	end
end

local function buildButtonRow()
	buttonRow = Instance.new("Frame")
	buttonRow.Name = "Buttons"
	buttonRow.BackgroundTransparency = 1
	buttonRow.AnchorPoint = Vector2.new(0.5, 1)
	-- Shadow hangs 5 px below the buttons; keep the margin to the shadow.
	buttonRow.Position = UDim2.new(0.5, 0, 1, -(BOTTOM_MARGIN + UITheme.ShadowOffset))
	buttonRow.AutomaticSize = Enum.AutomaticSize.XY
	buttonRow.Size = UDim2.new()
	buttonRow.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, BUTTON_GAP)
	layout.Parent = buttonRow
end

--[[ REBIRTH! button -----------------------------------------------------------
	Centred above the bottom button row while the player can afford the next
	rebirth; pulses so it's hard to miss, and opens the Rebirth panel.
]]
local REBIRTH_READY_SIZE = { Desktop = Vector2.new(220, 56), Phone = Vector2.new(170, 48) }
local REBIRTH_READY_GAP = 14 -- above the button row's top

local function buildRebirthReadyButton()
	local _, holder = UIKit.Button({
		Name = "RebirthReady",
		Parent = screenGui,
		Style = "Orange",
		Text = "REBIRTH!",
		TextSize = 24,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(REBIRTH_READY_SIZE.Desktop.X, REBIRTH_READY_SIZE.Desktop.Y),
		OnClick = RebirthPanel.Open,
	})
	rebirthReadyHolder = holder
	holder.Visible = false
	local scale = Instance.new("UIScale")
	scale.Name = "PulseScale"
	scale.Parent = holder
	TweenService:Create(
		scale,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = 1.08 }
	):Play()
end

local function layoutRebirthReady(isPhone: boolean)
	local layout = if isPhone then LAYOUT.Phone else LAYOUT.Desktop
	local size = if isPhone then REBIRTH_READY_SIZE.Phone else REBIRTH_READY_SIZE.Desktop
	local bottom = BOTTOM_MARGIN + UITheme.ShadowOffset + layout.ButtonSize.Y + REBIRTH_READY_GAP
	rebirthReadyHolder.Size = UDim2.fromOffset(size.X, size.Y)
	rebirthReadyHolder.Position = UDim2.new(0.5, 0, 1, -bottom)
end

-- Gentle pulse on UPGRADES while something is affordable, so new players notice it.
local function runUpgradesPulse()
	while screenGui.Parent do
		local holder = upgradesHolder
		local scale = holder and holder:FindFirstChild("PulseScale") :: UIScale?
		if scale and countAffordableUpgrades() > 0 and not UpgradesPanel.IsOpen() then
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { Scale = 1.08 }):Play()
			task.wait(0.35)
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
			task.wait(0.6)
		else
			if scale then
				scale.Scale = 1
			end
			task.wait(0.5)
		end
	end
end

--[[ Cash pops ------------------------------------------------------------- ]]

-- Floats `text` up from `position` and fades it over CASH_POP_LIFETIME.
-- Returns the label so a caller can fold more into it while it's alive.
-- FactoryController's collector pops use it.
function HudController.FloatPop(position: Vector3, text: string, color: Color3): TextLabel
	local anchor = Instance.new("Attachment")
	anchor.Name = "CashPopAnchor"
	anchor.WorldPosition = position
	anchor.Parent = Workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Name = "CashPop"
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(160, 40)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local label = UIKit.Label({
		Text = text,
		Font = Fonts.Display,
		TextSize = 26,
		TextColor3 = color,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = UITheme.Stroke.Text,
		Parent = gui,
	})

	local info = TweenInfo.new(CASH_POP_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = Vector3.new(0, CASH_POP_RISE_STUDS, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	end

	task.delay(CASH_POP_LIFETIME, function()
		gui:Destroy()
		anchor:Destroy()
	end)
	return label
end

--[[ Layout ---------------------------------------------------------------- ]]

local cashHolder: Frame

local function applyLayout(isPhone: boolean)
	local layout = if isPhone then LAYOUT.Phone else LAYOUT.Desktop
	cashHolder.Position = layout.CashPosition
	goalHolder.Position = layout.GoalPosition
	goalHolder.Size = UDim2.fromOffset(layout.GoalWidth, 0)
	goalRewardLabel.Visible = not isPhone
	goalBar.Size = UDim2.new(1, 0, 0, layout.GoalBarHeight)
	buildButtons(isPhone)
	layoutRebirthReady(isPhone)
end

--[[ Init ------------------------------------------------------------------ ]]

local function refreshGoal()
	local index = TycoonController.GetGoalIndex()
	local goal = index and GoalConfig.GetGoal(index)
	local progress = TycoonController.GetGoalProgress()
	if not goal or not progress then
		-- Before the first snapshot, and for good after the last goal.
		HudController.SetGoal(nil)
		return
	end
	HudController.SetGoal({
		Text = goal.Text,
		Reward = goal.Reward,
		Current = progress.Current,
		Target = progress.Target,
		Unit = goal.Unit,
	})
end

local function refreshAll()
	incomeLabel.Text = ("+%s%s"):format(
		NumberFormat.Money(getIncomePerSecond()),
		UIKit.Colored("/s", Colors.Muted)
	)
	-- The Multiplier Pad's own value; rebirth has its own pill beside it.
	multiplierPill.Text = NumberFormat.Multiplier(
		TycoonConfig.GetCashMultiplierValue(TycoonController.GetCashMultiplierLevel())
	)
	rebirthReadyHolder.Visible = TycoonController.IsRebirthReady()
	local rebirths = TycoonController.GetRebirths()
	local rebirthFill = rebirthPill.Parent :: Frame
	rebirthFill.Visible = rebirths > 0
	rebirthPill.Text = ("⟳ %d · %s"):format(rebirths, NumberFormat.Multiplier(RebirthConfig.GetIncomeMultiplier(rebirths)))
	refreshBadge()
	refreshGoal()
	UpgradesPanel.Refresh()
end

function HudController.Init()
	screenGui = UIKit.Screen("Hud", 40)

	buildGoalTracker()
	cashHolder = buildCashCard()
	buildButtonRow()
	buildRebirthReadyButton()
	UpgradesPanel.Init(screenGui)
	RebirthPanel.Init()
	IndexPanel.Init()
	FusePanel.Init()

	applyLayout(UIKit.IsPhone())
	UIKit.LayoutChanged:Connect(applyLayout)

	RunService.RenderStepped:Connect(onRenderStep)
	task.spawn(runUpgradesPulse)

	TycoonController.TycoonChanged:Connect(refreshAll)
	InventoryController.InventoryChanged:Connect(refreshAll)
	-- Arrives just before the snapshot that carries the next goal, so the
	-- flash plays on the finished goal and the swap follows.
	RemoteEvents.GoalCompleted.OnClientEvent:Connect(function()
		if goalHolder.Visible then
			HudController.FlashGoal()
		end
	end)
	refreshAll()
end

return HudController
