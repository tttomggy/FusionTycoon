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
local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local ShieldState = require(ReplicatedStorage.Shared.Modules.ShieldState)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonController = require(script.Parent.TycoonController)
local InventoryController = require(script.Parent.InventoryController)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local UpgradesPanel = require(script.Parent.Parent.UI.UpgradesPanel)
local RebirthPanel = require(script.Parent.Parent.UI.RebirthPanel)
local IndexPanel = require(script.Parent.Parent.UI.IndexPanel)
local ShopPanel = require(script.Parent.Parent.UI.ShopPanel)
local PurchaseCelebration = require(script.Parent.Parent.UI.PurchaseCelebration)
local GiftsPanel = require(script.Parent.Parent.UI.GiftsPanel)
local ShopController = require(script.Parent.ShopController)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ShopState = require(ReplicatedStorage.Shared.Modules.ShopState)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local SettingsPanel = require(script.Parent.Parent.UI.SettingsPanel)
local FusePanel = require(script.Parent.Parent.UI.FusePanel)
local HowToHeistPanel = require(script.Parent.Parent.UI.HowToHeistPanel)
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
		-- Unused on a phone: the goal tracker follows the SHOP and LOCK rows
		-- in the left column (applyLayout).
		GoalPosition = UDim2.fromOffset(10, 184),
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
local SETTINGS_BUTTON_SIZE = 56

local CASH_POP_LIFETIME = 0.8
local CASH_POP_RISE_STUDS = 3

local screenGui: ScreenGui
local displayedCash = 0

local cashLabel: TextLabel
local incomeLabel: TextLabel
local effectPills: { Income: TextLabel, Luck: TextLabel, Server: TextLabel }
local multiplierPill: TextLabel
local breakdownHolder: Frame
local breakdownLabel: TextLabel
local breakdownToken = 0
local BREAKDOWN_SECONDS = 5
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
	local rebirthFill = UIKit.PillRoot(rebirthPill)
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
	-- Tap the total for its breakdown (pad, rebirths, Index, passes, boost,
	-- Overclock); a >= 44 px clear hit area like the rebirth pill's.
	local multiplierHit = Instance.new("TextButton")
	multiplierHit.Name = "Hit"
	multiplierHit.Text = ""
	multiplierHit.BackgroundTransparency = 1
	multiplierHit.AnchorPoint = Vector2.new(0.5, 0.5)
	multiplierHit.Position = UDim2.fromScale(0.5, 0.5)
	multiplierHit.Size = UDim2.new(1, 16, 0, UITheme.MinTapSize)
	multiplierHit.ZIndex = z + 2
	multiplierHit.Parent = UIKit.PillRoot(multiplierPill)
	multiplierHit.Activated:Connect(function()
		HudController.ToggleIncomeBreakdown()
	end)

	local breakdown, breakdownFrame = UIKit.Panel({
		Name = "IncomeBreakdown",
		Parent = holder,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 1, 8),
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Color = Colors.Panel,
		Radius = UITheme.Radius.Row,
		ZIndex = z + 5,
	})
	UIKit.Padding(breakdown, 8, 12, 8, 12)
	breakdownLabel = UIKit.Label({
		Name = "Lines",
		Font = Fonts.Body,
		TextSize = 14,
		RichText = true,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 18),
		ZIndex = z + 6,
		Parent = breakdown,
	})
	breakdownFrame.Visible = false
	breakdownHolder = breakdownFrame

	return holder
end

-- The purchase celebration holds the counter at the old amount until its
-- coins land (HudController.HoldCash).
local cashHoldUntil = 0
local incomeCountFrom: number? = nil
local incomeCountStart = 0
local INCOME_COUNT_SECONDS = 0.8

local function onRenderStep(dt: number)
	local count = incomeCountFrom
	if count then
		local u = math.clamp((os.clock() - incomeCountStart) / INCOME_COUNT_SECONDS, 0, 1)
		local now = getIncomePerSecond()
		incomeLabel.Text = ("+%s%s"):format(NumberFormat.Money(count + (now - count) * u), UIKit.Colored("/s", Colors.Muted))
		if u >= 1 then
			incomeCountFrom = nil
			incomeLabel.TextColor3 = Colors.Text
		end
	end
	if os.clock() < cashHoldUntil then
		cashLabel.Text = NumberFormat.Short(math.floor(displayedCash))
		return
	end
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

--[[ Purchase celebration hooks (UI/PurchaseCelebration) ------------------------ ]]

local function screenCentre(gui: GuiObject): Vector2
	return gui.AbsolutePosition + gui.AbsoluteSize / 2
end

local function bounce(gui: GuiObject)
	local scale = gui:FindFirstChild("BounceScale") :: UIScale?
	if not scale then
		local created = Instance.new("UIScale")
		created.Name = "BounceScale"
		created.Parent = gui
		scale = created
	end
	local s = scale :: UIScale
	s.Scale = 1.18
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Screen point (px) of the cash counter: where the coins fly.
function HudController.GetCashTarget(): Vector2
	return screenCentre(cashLabel)
end

-- Shows `amount` on the counter for `seconds` (the coins are in the air),
-- then it ticks up to the real cash as usual.
function HudController.HoldCash(amount: number, seconds: number)
	displayedCash = math.max(0, amount)
	cashHoldUntil = os.clock() + seconds
end

function HudController.BounceCash()
	bounce(cashLabel)
end

-- The timed pill for "Income" | "Luck" | "Server" (nil while it's hidden).
function HudController.GetEffectPill(kind: string): TextLabel?
	local pill = (effectPills :: any)[kind] :: TextLabel?
	return pill
end

function HudController.PopEffectPill(kind: string)
	local pill = HudController.GetEffectPill(kind)
	if pill then
		local fill = UIKit.PillRoot(pill)
		fill.Visible = true
		bounce(fill)
	end
end

-- The $/s line counts up from `from` to the real income with a green flash.
function HudController.CountUpIncome(from: number)
	incomeCountFrom = from
	incomeCountStart = os.clock()
	incomeLabel.TextColor3 = Colors.Cash
	bounce(incomeLabel)
end

function HudController.GetIncomePerSecond(): number
	return getIncomePerSecond()
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
			InUse = InventoryController.IsInUse(item),
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

	-- ⚙ Settings: a 56 px square at the right end of the bar.
	buttonsByName.Settings = UIKit.Button({
		Name = "SettingsButton",
		Parent = buttonRow,
		Style = "Disabled",
		Text = "⚙",
		Size = UDim2.fromOffset(SETTINGS_BUTTON_SIZE, SETTINGS_BUTTON_SIZE),
		TextSize = 26,
		LayoutOrder = 4,
		OnClick = SettingsPanel.Toggle,
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
	-- Toasts and bottom cards sit on UITheme.BottomStackOffset, above this slot.
	assert(bottom + size.Y * 1.08 <= UITheme.BottomStackOffset, "BottomStackOffset must clear REBIRTH!")
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

--[[ LOCK status chip ------------------------------------------------------
	Under the cash card (beside it on a phone). It is NOT a lock button:
	locking only happens at your LOCK console (HeistService.TryLock checks
	you're there). It shows the state from the plot's published attributes
	(ShieldState):
	  Unlocked    muted, amber text   "🔓 UNLOCKED"
	  Locked      teal                "🛡 LOCKED · 42s"
	  Recharging  muted               "RECHARGING · 12s"
	  Alarm       red, pulsing        "🚨 RUN TO LOCK!"
	              (lock ready AND a non-owner's root inside your walls)
	It sizes itself to its text (AutomaticSize X, 44 px tall, 14 px side
	padding); the round "?" sits 8 px to its right (one row frame with a
	horizontal list layout).
	Tapping it calls the handler HeistController registers
	(SetLockChipHandler): the goal arrow points at your console for a few
	seconds. Hidden under HeistConfig.MinRebirths and before you claim.
]]
local LOCK_CHIP_HEIGHT = 44
local LOCK_CHIP_PADDING = 14
local LOCK_CHIP_TEXT_SIZE = 15
local LOCK_BUTTON_GAP = 8
local LOCK_REFRESH_SECONDS = 0.25

local lockChip: TextButton
local lockHolder: Frame
-- The row holding the LOCK chip and the "?" (it takes the position).
local lockRow: Frame
-- The round "?" beside it: opens HOW TO HEIST (visible from Rebirth 1).
local HELP_BUTTON_SIZE = 52 -- >= 44 px after the phone UIScale
local helpHolder: Frame
local lockScale: UIScale
local lockPulse: Tween? = nil
local lockStyle: string? = nil
local lockChipHandler: (() -> ())? = nil

local function buildLockChip()
	lockRow = Instance.new("Frame")
	lockRow.Name = "LockRow"
	lockRow.BackgroundTransparency = 1
	lockRow.AutomaticSize = Enum.AutomaticSize.X
	lockRow.Size = UDim2.fromOffset(0, HELP_BUTTON_SIZE)
	lockRow.Parent = screenGui
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, LOCK_BUTTON_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = lockRow

	lockChip, lockHolder = UIKit.Button({
		Name = "LockChip",
		Parent = lockRow,
		Style = "Disabled",
		Text = "🔓 UNLOCKED",
		TextSize = LOCK_CHIP_TEXT_SIZE,
		Size = UDim2.fromOffset(0, LOCK_CHIP_HEIGHT),
		LayoutOrder = 1,
		OnClick = function()
			if lockChipHandler then
				lockChipHandler()
			end
		end,
	})
	-- Fit the text: holder, body and content all auto-size on X (minimum 0).
	lockHolder.AutomaticSize = Enum.AutomaticSize.X
	lockChip.AutomaticSize = Enum.AutomaticSize.X
	lockChip.Size = UDim2.new(0, 0, 1, 0)
	local content = lockChip:FindFirstChild("Content")
	if content and content:IsA("Frame") then
		content.AutomaticSize = Enum.AutomaticSize.X
		content.Size = UDim2.new(0, 0, 1, 0)
		UIKit.Padding(content, 0, LOCK_CHIP_PADDING, 0, LOCK_CHIP_PADDING)
	end
	lockHolder.Visible = false
	lockScale = Instance.new("UIScale")
	lockScale.Parent = lockHolder

	local _, help = UIKit.Button({
		Name = "HowToHeistButton",
		Parent = lockRow,
		LayoutOrder = 2,
		Style = "Blue",
		Text = "?",
		TextSize = 26,
		Radius = 999,
		Size = UDim2.fromOffset(HELP_BUTTON_SIZE, HELP_BUTTON_SIZE),
		OnClick = HowToHeistPanel.Open,
	})
	helpHolder = help
	helpHolder.Visible = false
end

-- HeistController's tap handler (it owns the goal-arrow override).
function HudController.SetLockChipHandler(handler: () -> ())
	lockChipHandler = handler
end

local function setLockPulse(on: boolean)
	if on and not lockPulse then
		local tween = TweenService:Create(
			lockScale,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.06 }
		)
		tween:Play()
		lockPulse = tween
	elseif not on and lockPulse then
		lockPulse:Cancel()
		lockPulse = nil
		lockScale.Scale = 1
	end
end

local function getOwnPlot(): Instance?
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	return folder and folder:FindFirstChild(PlotNaming.GetPlotName(localPlayer.UserId))
end

-- A non-owner's root is inside this plot's walls.
local function hasIntruder(plot: Instance): boolean
	local origin = plot:IsA("Model") and plot.PrimaryPart
	if not origin then
		return false
	end
	for _, other in Players:GetPlayers() do
		if other ~= localPlayer then
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and PlotLayout.IsInsidePlot(origin.CFrame:PointToObjectSpace(root.Position)) then
				return true
			end
		end
	end
	return false
end

-- True while LOCK is ready and someone else is in your lab (the alarm
-- state; HeistController's intruder tip reads it too).
function HudController.IsLockUrgent(): boolean
	return lockPulse ~= nil
end

local function refreshLockChip()
	local plot = getOwnPlot()
	local eligible = TycoonController.GetRebirths() >= HeistConfig.MinRebirths
	helpHolder.Visible = eligible
	if not plot or plot:GetAttribute("Claimed") ~= true or not eligible then
		lockHolder.Visible = false
		setLockPulse(false)
		return
	end
	local state, seconds = ShieldState.Get(plot)
	if state == "Protected" then
		lockHolder.Visible = false
		setLockPulse(false)
		return
	end
	lockHolder.Visible = true
	local alarm = state == "Ready" and hasIntruder(plot)
	local style = if alarm then "Red" elseif state == "Locked" then "Teal" else "Disabled"
	local text = if alarm
		then "🚨 RUN TO LOCK!"
		elseif state == "Locked" then ("🛡 LOCKED · %ds"):format(seconds)
		elseif state == "Recharging" then ("RECHARGING · %ds"):format(seconds)
		else "🔓 UNLOCKED"
	UIKit.SetButton(lockChip, {
		Style = if style ~= lockStyle then style else nil,
		Text = text,
		TextColor3 = if state == "Recharging" and not alarm
			then Colors.Muted
			elseif state == "Ready" and not alarm then Colors.ShieldAmber
			else Colors.Text,
	})
	lockStyle = style
	setLockPulse(alarm)
end

--[[ Layout ---------------------------------------------------------------- ]]

local cashHolder: Frame

--[[ SHOP button + timed-effect pills -------------------------------------------------
	A big gold "🛒 SHOP" on the left edge, above the LOCK chip (>= 56 px
	tall), wiggling gently every SHOP_WIGGLE_SECONDS; a red SALE tag only
	while a real sale is live (ShopState); and a pill per active timed
	effect: "⚡ 2× · 12:41", "🍀 2× luck · 3:10", "⚡ SERVER 2× · 8:02".
	Beside SHOP, the pink "🎁 GIFTS" (GiftsPanel): a green count badge and a
	bounce while any playtime gift is ready, otherwise a small "next in
	3:12" pill (hidden once today's gifts are all open).
]]
local SHOP_BUTTON_SIZE = Vector2.new(132, 56)
-- Room for the SALE tag (it pokes 8 px past SHOP's right edge) beside the
-- bouncing GIFTS button (×1.08).
local SHOP_ROW_GAP = 14
local SHOP_WIGGLE_SECONDS = 20
local SHOP_WIGGLE_DEGREES = 7
local EFFECT_PILL_HEIGHT = 28
local GIFTS_BUTTON_SIZE = Vector2.new(124, 56)
local GIFTS_BOUNCE_SCALE = 1.08

local shopRow: Frame
local shopHolder: Frame
local saleTag: TextLabel
local giftsButton: TextButton
local giftsScale: UIScale
local giftsNextPill: TextLabel
local giftsBounce: Tween? = nil

-- The 🔥 deal badge (ShopController.GetDeal): the live saving and the real
-- countdown; it pulses once when a new slot starts; a tap opens the shop at
-- the deal. Under SHOP / GIFTS on desktop, at the end of their row on a
-- phone (the column there is full).
local DEAL_BADGE_SIZE = Vector2.new(176, 40)
local dealButton: TextButton
local dealHolder: Frame
local dealSlot: number? = nil
local dealShown = false
local layoutIsPhone = false

local function buildDealBadge()
	local button, holder = UIKit.Button({
		Name = "DealBadge",
		Style = "Pink",
		Text = "🔥 DEAL",
		TextSize = 16,
		Size = UDim2.fromOffset(DEAL_BADGE_SIZE.X, DEAL_BADGE_SIZE.Y + 4),
		ShadowOffset = UITheme.SmallShadowOffset,
		LayoutOrder = 9,
		OnClick = function()
			ShopPanel.Open("Deal")
		end,
	})
	dealButton = button
	dealHolder = holder
	holder.Visible = false
	holder.Parent = screenGui
end

local function buildShopRow()
	shopRow = Instance.new("Frame")
	shopRow.Name = "ShopRow"
	shopRow.BackgroundTransparency = 1
	shopRow.AutomaticSize = Enum.AutomaticSize.X
	shopRow.Size = UDim2.fromOffset(0, SHOP_BUTTON_SIZE.Y + UITheme.ShadowOffset)
	shopRow.Parent = screenGui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, SHOP_ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = shopRow

	local _, holder = UIKit.Button({
		Name = "ShopButton",
		Parent = shopRow,
		Style = "Gold",
		Text = "🛒 SHOP",
		TextSize = 22,
		Size = UDim2.fromOffset(SHOP_BUTTON_SIZE.X, SHOP_BUTTON_SIZE.Y),
		LayoutOrder = 1,
		OnClick = function()
			ShopPanel.Toggle()
		end,
	})
	shopHolder = holder
	saleTag = UIKit.Pill({
		Name = "Sale",
		Parent = holder,
		Text = "SALE",
		Color = Colors.Sale,
		Font = Fonts.Display,
		TextSize = 12,
		Height = 20,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 8, 0, -8),
		ZIndex = 10,
		TextStroke = 1.5,
	})
	UIKit.SetPillVisible(saleTag, false)

	local gifts, giftsHolder = UIKit.Button({
		Name = "GiftsButton",
		Parent = shopRow,
		Style = "Pink",
		Text = "🎁 GIFTS",
		TextSize = 20,
		Size = UDim2.fromOffset(GIFTS_BUTTON_SIZE.X, GIFTS_BUTTON_SIZE.Y),
		LayoutOrder = 2,
		OnClick = function()
			GiftsPanel.Toggle()
		end,
	})
	giftsButton = gifts
	giftsScale = Instance.new("UIScale")
	giftsScale.Parent = giftsHolder
	giftsNextPill = UIKit.Pill({
		Name = "GiftsNext",
		Parent = shopRow,
		Text = "",
		Color = Colors.Panel2,
		TextColor3 = Colors.Muted,
		TextSize = 13,
		Height = EFFECT_PILL_HEIGHT - 4,
		LayoutOrder = 3,
		TextStroke = 1.5,
	})
	UIKit.SetPillVisible(giftsNextPill, false)

	local pills = Instance.new("Frame")
	pills.Name = "Effects"
	pills.BackgroundTransparency = 1
	pills.AutomaticSize = Enum.AutomaticSize.XY
	pills.Size = UDim2.new()
	pills.LayoutOrder = 4
	pills.Parent = shopRow
	local pillLayout = Instance.new("UIListLayout")
	pillLayout.Padding = UDim.new(0, 4)
	pillLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pillLayout.Parent = pills
	local function pill(name: string, order: number, pair: UITheme.GradientPair): TextLabel
		local label = UIKit.Pill({
			Name = name,
			Parent = pills,
			Text = "",
			Gradient = pair,
			Font = Fonts.BodyHeavy,
			TextSize = 13,
			Height = EFFECT_PILL_HEIGHT - 4,
			LayoutOrder = order,
			TextStroke = 1.5,
		})
		local fill = UIKit.PillRoot(label)
		fill.Visible = false
		return label
	end
	effectPills = {
		Income = pill("IncomeBoost", 1, UITheme.Gradients.Violet),
		Luck = pill("LuckBoost", 2, UITheme.Gradients.Teal),
		Server = pill("Overclock", 3, UITheme.Gradients.Gold),
	}

	-- A gentle wiggle every SHOP_WIGGLE_SECONDS.
	task.spawn(function()
		while shopHolder.Parent do
			task.wait(SHOP_WIGGLE_SECONDS)
			local info = TweenInfo.new(0.09, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			for _, angle in { SHOP_WIGGLE_DEGREES, -SHOP_WIGGLE_DEGREES, SHOP_WIGGLE_DEGREES * 0.5, 0 } do
				local tween = TweenService:Create(shopHolder, info, { Rotation = angle })
				tween:Play()
				tween.Completed:Wait()
			end
		end
	end)
end

-- Once a second: the effect pills' timers and the SALE tag.
local applyLayout: (isPhone: boolean) -> ()

local function refreshDealBadge()
	local deal = ShopController.GetDeal()
	local shown = deal ~= nil
	if deal then
		UIKit.SetButton(dealButton, {
			Text = ("🔥 %s · %s"):format(if deal.Save then ("−%d%%"):format(deal.Save) else "DEAL", EventState.FormatTimer(deal.SecondsLeft)),
		})
		if dealSlot and dealSlot ~= deal.SlotStart then
			local pulse = dealButton:FindFirstChild("DealPulse") :: UIScale?
			if not pulse then
				local created = Instance.new("UIScale")
				created.Name = "DealPulse"
				created.Parent = dealButton
				pulse = created
			end
			local scale = pulse :: UIScale
			scale.Scale = 1.25
			TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		dealSlot = deal.SlotStart
	end
	if shown ~= dealShown then
		dealShown = shown
		dealHolder.Visible = shown
		applyLayout(layoutIsPhone)
	end
end

local function refreshShopRow()
	refreshDealBadge()
	local function setPill(label: TextLabel, seconds: number, format: string)
		local fill = UIKit.PillRoot(label)
		fill.Visible = seconds > 0
		if seconds > 0 then
			label.Text = format:format(EventState.FormatTimer(seconds))
		end
	end
	setPill(effectPills.Income, TycoonController.GetBoostSecondsLeft("Income"), ("⚡ %d× · %%s"):format(ShopConfig.BoostMultiplier))
	setPill(effectPills.Luck, TycoonController.GetBoostSecondsLeft("Luck"), ("🍀 %d× luck · %%s"):format(ShopConfig.LuckPotionMultiplier))
	setPill(effectPills.Server, ShopState.GetOverclockSeconds(), ("⚡ SERVER %d× · %%s"):format(ShopConfig.OverclockMultiplier))
	local saleLive = false
	for _, sale in ShopConfig.Sales do
		if ShopController.IsAvailable(sale.SaleKey) then
			saleLive = true
		end
	end
	UIKit.SetPillVisible(saleTag, saleLive)
	-- Live with no product ids set yet: nothing to sell, so no SHOP button
	-- (GIFTS slides left); it appears once any item is set up.
	shopHolder.Visible = ShopController.HasAnyOffer()

	-- GIFTS: the ready count (green badge + bounce) or "next in 3:12".
	local ready, nextIn = GiftsPanel.GetStatus()
	local badge = UIKit.Badge(giftsButton, if TycoonController.HasSynced() then ready else 0)
	badge.BackgroundColor3 = Colors.Cash
	badge.TextColor3 = Colors.CoinText
	UIKit.SetPillVisible(giftsNextPill, TycoonController.HasSynced() and ready == 0 and nextIn ~= nil)
	if nextIn then
		giftsNextPill.Text = ("next in %s"):format(EventState.FormatTimer(nextIn))
	end
	local shouldBounce = ready > 0 and TycoonController.HasSynced()
	if shouldBounce and not giftsBounce then
		local tween = TweenService:Create(
			giftsScale,
			TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = GIFTS_BOUNCE_SCALE }
		)
		tween:Play()
		giftsBounce = tween
	elseif not shouldBounce and giftsBounce then
		(giftsBounce :: Tween):Cancel()
		giftsBounce = nil
		giftsScale.Scale = 1
	end
end

function applyLayout(isPhone: boolean)
	layoutIsPhone = isPhone
	local layout = if isPhone then LAYOUT.Phone else LAYOUT.Desktop
	cashHolder.Position = layout.CashPosition
	-- The left column, desktop and phone alike: cash card, then the SHOP /
	-- GIFTS / timed-pill row, then the LOCK row (on a phone the goal
	-- tracker follows them; on desktop it sits above the cash card).
	local shopTop = layout.CashPosition + UDim2.fromOffset(0, CASH_CARD_SIZE.Y + UITheme.ShadowOffset + LOCK_BUTTON_GAP)
	shopRow.Position = shopTop
	local lockTop = shopTop + UDim2.fromOffset(0, SHOP_BUTTON_SIZE.Y + UITheme.ShadowOffset + LOCK_BUTTON_GAP)
	if isPhone then
		dealHolder.Parent = shopRow
	else
		dealHolder.Parent = screenGui
		dealHolder.Position = lockTop
		if dealShown then
			lockTop += UDim2.fromOffset(0, DEAL_BADGE_SIZE.Y + 4 + UITheme.SmallShadowOffset + LOCK_BUTTON_GAP)
		end
	end
	lockRow.Position = lockTop
	goalHolder.Position = if isPhone
		then UDim2.fromOffset(layout.CashPosition.X.Offset, lockTop.Y.Offset + HELP_BUTTON_SIZE + UITheme.ShadowOffset + LOCK_BUTTON_GAP)
		else layout.GoalPosition
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
	-- The TOTAL income multiplier (pad x rebirth x Index x the shop); tap
	-- it for the breakdown.
	multiplierPill.Text = NumberFormat.Multiplier(TycoonController.GetIncomeMultiplier())
	if breakdownHolder.Visible then
		HudController.RefreshIncomeBreakdown()
	end
	rebirthReadyHolder.Visible = TycoonController.IsRebirthReady()
	local rebirths = TycoonController.GetRebirths()
	local rebirthFill = UIKit.PillRoot(rebirthPill)
	rebirthFill.Visible = rebirths > 0
	rebirthPill.Text = ("⟳ %d · %s"):format(rebirths, NumberFormat.Multiplier(RebirthConfig.GetIncomeMultiplier(rebirths)))
	refreshBadge()
	refreshGoal()
	UpgradesPanel.Refresh()
end

-- The lines under the multiplier pill: every factor that isn't x1, then the
-- total. Same IncomeInputs as the HUD's income (one formula).
function HudController.RefreshIncomeBreakdown()
	local inputs = TycoonController.GetIncomeInputs()
	local lines = {}
	for _, part in TycoonConfig.GetIncomeBreakdown(inputs) do
		if math.abs(part.Value - 1) > 1e-6 then
			table.insert(lines, ("%s  %s"):format(part.Label, UIKit.Colored(NumberFormat.Multiplier(part.Value), Colors.Cash)))
		end
	end
	if #lines == 0 then
		table.insert(lines, "No boosts yet")
	end
	table.insert(lines, ("<b>Total  %s</b>"):format(UIKit.Colored(NumberFormat.Multiplier(TycoonConfig.GetIncomeMultiplier(inputs)), Colors.Cash)))
	breakdownLabel.Text = table.concat(lines, "\n")
end

function HudController.ToggleIncomeBreakdown()
	breakdownToken += 1
	if breakdownHolder.Visible then
		breakdownHolder.Visible = false
		return
	end
	HudController.RefreshIncomeBreakdown()
	breakdownHolder.Visible = true
	UIKit.PopIn(breakdownHolder)
	local token = breakdownToken
	task.delay(BREAKDOWN_SECONDS, function()
		if breakdownToken == token then
			breakdownHolder.Visible = false
		end
	end)
end

function HudController.Init()
	screenGui = UIKit.Screen("Hud", 40)

	buildGoalTracker()
	cashHolder = buildCashCard()
	PurchaseCelebration.SetHud({
		GetCashTarget = HudController.GetCashTarget,
		HoldCash = HudController.HoldCash,
		BounceCash = HudController.BounceCash,
		GetEffectPill = HudController.GetEffectPill,
		PopEffectPill = HudController.PopEffectPill,
		CountUpIncome = HudController.CountUpIncome,
		GetIncomePerSecond = HudController.GetIncomePerSecond,
		GetCash = TycoonController.GetCash,
	})
	buildButtonRow()
	buildRebirthReadyButton()
	buildLockChip()
	buildShopRow()
	buildDealBadge()
	UpgradesPanel.Init(screenGui)
	RebirthPanel.Init()
	IndexPanel.Init()
	ShopPanel.Init()
	GiftsPanel.Init()
	SettingsPanel.Init()
	FusePanel.Init()
	HowToHeistPanel.Init()

	applyLayout(UIKit.IsPhone())
	UIKit.LayoutChanged:Connect(applyLayout)

	RunService.RenderStepped:Connect(onRenderStep)
	task.spawn(function()
		while true do
			refreshShopRow()
			task.wait(1)
		end
	end)
	task.spawn(runUpgradesPulse)
	task.spawn(function()
		while true do
			refreshLockChip()
			task.wait(LOCK_REFRESH_SECONDS)
		end
	end)

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
