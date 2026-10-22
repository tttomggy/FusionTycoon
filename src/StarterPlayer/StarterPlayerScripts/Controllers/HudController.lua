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

	PHONE (UIKit.IsPhone, < 500 px tall) is a compact, icon-button HUD: a slim
	cash panel (cash over "$/s" + pills), then a utility GRID of 56 px icon
	cards (a glyph over a 13 px word; 3 per row, 6 px gaps): SHOP, GIFTS,
	QUESTS, the power-ups and the LOCK chip; the deal tile and "next in" under
	it; the bottom row is five 56 px icon cards. Desktop is unchanged. The
	same buttons are re-parented and restyled by applyLayout (setCardCompact),
	so every handler, badge and bounce is the one desktop uses.
]]
local GuiService = game:GetService("GuiService")
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
local HudGate = require(script.Parent.Parent.UI.HudGate)
local DealParts = require(script.Parent.Parent.UI.DealParts)
local EffectsTray = require(script.Parent.Parent.UI.EffectsTray)
local UpgradesPanel = require(script.Parent.Parent.UI.UpgradesPanel)
local RebirthPanel = require(script.Parent.Parent.UI.RebirthPanel)
local IndexPanel = require(script.Parent.Parent.UI.IndexPanel)
local ShopPanel = require(script.Parent.Parent.UI.ShopPanel)
local PurchaseCelebration = require(script.Parent.Parent.UI.PurchaseCelebration)
local GiftsPanel = require(script.Parent.Parent.UI.GiftsPanel)
local QuestsPanel = require(script.Parent.Parent.UI.QuestsPanel)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local ShopController = require(script.Parent.ShopController)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ShopPrices = require(ReplicatedStorage.Shared.Modules.ShopPrices)
local DealState = require(ReplicatedStorage.Shared.Modules.DealState)
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
		-- Unused on a phone: the goal pill sits under the cash panel (placeColumnFor).
		GoalPosition = UDim2.fromOffset(10, 184),
		GoalWidth = 232, -- a one-line pill as wide as the slim cash panel (CASH_CARD_PHONE.X)
		GoalBarHeight = 10,
		CashPosition = UDim2.fromOffset(10, 76),
		ButtonSize = Vector2.new(84, 60),
		ButtonTextSize = 13,
	},
}
local CASH_CARD_SIZE = Vector2.new(260, 96)
local PILL_ROW_WIDTH = 132 -- room for the rebirth pill and the Multiplier pill
-- Phone: the slim cash panel (62% of the desktop card's height) and the
-- 56 px icon cards of the utility grid and the bottom row.
local CASH_CARD_PHONE = Vector2.new(232, 60)
local PILL_ROW_PHONE = 124
local PHONE_CARD = 56
local PHONE_CARD_GAP = 6
local PHONE_GRID_COLUMNS = 3
local PHONE_GLYPH_SIZE = 28
local PHONE_WORD_SIZE = 13
local PHONE_BUTTON_GAP = 6
local BOTTOM_MARGIN = 22
local BUTTON_GAP = 14
local SETTINGS_BUTTON_SIZE = 56

local CASH_POP_LIFETIME = 0.8
local CASH_POP_RISE_STUDS = 3

local screenGui: ScreenGui
local displayedCash = 0

local cashLabel: TextLabel
local incomeLabel: TextLabel
local multiplierPill: TextLabel
local breakdownHolder: Frame
local breakdownLabel: TextLabel
local breakdownToken = 0
local BREAKDOWN_SECONDS = 5
local rebirthPill: TextLabel
-- The phone flag for the bottom row (buildButtons sets it; layoutIsPhone
-- below is the left column's).
local layoutIsPhoneEarly = false
-- /selftest's left-column and coverage checks hold the forced cards (the
-- refresh ticks would hide them again).
local selfTestHold = false
local cashCoin: Frame
local cashPadding: UIPadding
local cashPills: Frame
-- Phone: the utility grid the SHOP / GIFTS / QUESTS / power-up / LOCK cards live in.
local phoneGrid: Frame
local phoneGridLayout: UIGridLayout

local goalHolder: Frame
local goalBody: Frame
local goalRewardLabel: TextLabel
local goalTextLabel: TextLabel
local goalBar: Frame
local goalCountLabel: TextLabel
local goalPathButton: TextButton? = nil
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

local buttonRow: Frame
local upgradesButton: TextButton? = nil
local upgradesHolder: Frame? = nil
-- The bottom bar's REBIRTH button (always there): cash vs the next cost.
local rebirthButton: TextButton? = nil
local rebirthFill: Frame? = nil
local rebirthGlow: Frame? = nil
local rebirthScale: UIScale? = nil
local rebirthPulse: Tween? = nil
local rebirthGlowTween: Tween? = nil
local REBIRTH_FILL_TRANSPARENCY = 0.72
local REBIRTH_BAR_HEIGHT = 6 -- phone: the progress bar along the card's bottom edge
local REBIRTH_GLOW_PAD = 14
local REBIRTH_PULSE_SCALE = 1.08
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
end

-- Phone: the one-line pill; desktop: the full card.
local function applyGoalLayout(isPhone: boolean)
	goalPhoneMode = isPhone
	goalHeader.Visible = not isPhone
	goalTextLabel.Visible = not isPhone
	goalBar.Visible = not isPhone
	goalCountLabel.Visible = goalHasCount and not isPhone
	goalPhoneLine.Visible = isPhone
	local vertical, horizontal = if isPhone then 6 else 12, if isPhone then 10 else 14
	goalPadding.PaddingTop = UDim.new(0, vertical)
	goalPadding.PaddingBottom = UDim.new(0, vertical)
	goalPadding.PaddingLeft = UDim.new(0, horizontal)
	goalPadding.PaddingRight = UDim.new(0, horizontal)
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
	cashPadding = UIKit.Padding(body, 12, 14, 12, 14)
	local z = body.ZIndex + 1

	-- Row 1: coin + amount.
	local coin = Instance.new("Frame")
	coin.Name = "Coin"
	coin.Size = UDim2.fromOffset(34, 34)
	coin.Position = UDim2.fromOffset(0, 3)
	coin.BackgroundColor3 = Colors.White
	coin.ZIndex = z
	coin.Parent = body
	cashCoin = coin
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
	cashPills = pills
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
-- then it ticks up to the real cash as usual (seconds 0 = release now).
function HudController.HoldCash(amount: number, seconds: number)
	if seconds > 0 then
		displayedCash = math.max(0, amount)
	end
	cashHoldUntil = os.clock() + seconds
end

function HudController.BounceCash()
	bounce(cashLabel)
end

-- Where an effect's icon is (EffectsTray, right edge) for a purchase flight:
-- "Income" | "Luck" | "Server", screen px.
function HudController.GetEffectTarget(kind: string): Vector2
	return EffectsTray.GetTarget(kind)
end

function HudController.PopEffect(kind: string)
	EffectsTray.Pop(kind)
end

-- The HUD bottom row's rect (AbsolutePosition space), for the effects tray.
function HudController.GetBottomRowRect(): { Position: Vector2, Size: Vector2 }?
	if buttonRow and buttonRow.Visible and buttonRow.AbsoluteSize.X > 0 then
		return { Position = buttonRow.AbsolutePosition, Size = buttonRow.AbsoluteSize }
	end
	return nil
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
			EventMutations = item.EventMutations,
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

--[[ Icon cards (phone) ------------------------------------------------------------
	SHOP, GIFTS, QUESTS and the power-ups are built once, as the wide desktop
	buttons. On a phone setCardCompact turns each into a 56 px square card: the
	glyph at 28 px over its word at 13 px, in the button's own colour; the badges,
	bounces and handlers stay. Desktop gets its wide button back.
]]
type Card = {
	Button: TextButton,
	Holder: Frame,
	Glyph: string,
	Word: string,
	DesktopSize: UDim2,
	DesktopText: string,
	DesktopTextSize: number,
	DesktopRadius: number,
}

local cards: { Card } = {}

local function addCard(button: TextButton, holder: Frame, glyph: string, word: string, desktopText: string, desktopTextSize: number): Card
	-- A power-up button has two UICorners (UIKit.Button's and its round one):
	-- the later one is what draws.
	local corner: UICorner? = nil
	for _, child in button:GetChildren() do
		if child:IsA("UICorner") then
			corner = child
		end
	end
	local card: Card = {
		Button = button,
		Holder = holder,
		Glyph = glyph,
		Word = word,
		DesktopSize = holder.Size,
		DesktopText = desktopText,
		DesktopTextSize = desktopTextSize,
		DesktopRadius = if corner then corner.CornerRadius.Offset else UITheme.Radius.Button,
	}
	table.insert(cards, card)
	return card
end

local function setCardCompact(card: Card, compact: boolean)
	local content = card.Button:FindFirstChild("Content")
	local layout = content and content:FindFirstChildOfClass("UIListLayout")
	local column = content and content:FindFirstChild("TextColumn")
	local label = column and column:FindFirstChild("Label") :: TextLabel?
	local sub = column and column:FindFirstChild("SubLabel") :: TextLabel?
	if not (layout and label and sub) then
		return
	end
	if compact then
		card.Holder.Size = UDim2.fromOffset(PHONE_CARD, PHONE_CARD)
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.Padding = UDim.new(0, 0)
		label.Text = card.Glyph
		label.TextSize = PHONE_GLYPH_SIZE
		sub.Text = card.Word
		sub.TextSize = PHONE_WORD_SIZE
		sub.Visible = card.Word ~= ""
		for _, child in card.Button:GetChildren() do
			if child:IsA("UICorner") then
				child.CornerRadius = UDim.new(0, UITheme.Radius.Button)
			end
		end
	else
		card.Holder.Size = card.DesktopSize
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 8)
		label.Text = card.DesktopText
		label.TextSize = card.DesktopTextSize
		sub.Text = ""
		sub.Visible = false
		for _, child in card.Button:GetChildren() do
			if child:IsA("UICorner") then
				child.CornerRadius = UDim.new(0, card.DesktopRadius)
			end
		end
	end
end

local function buildButtons(isPhone: boolean)
	layoutIsPhoneEarly = isPhone
	for _, child in buttonRow:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local rowLayout = buttonRow:FindFirstChildOfClass("UIListLayout")
	if rowLayout then
		rowLayout.Padding = UDim.new(0, if isPhone then PHONE_BUTTON_GAP else BUTTON_GAP)
	end

	local layout = if isPhone then LAYOUT.Phone else LAYOUT.Desktop
	local size = UDim2.fromOffset(layout.ButtonSize.X, layout.ButtonSize.Y)
	-- Phone: a 56 px icon card (an emoji glyph over a 13 px word), no image icon.
	local function forPhone(props: any, glyph: string, word: string): any
		if isPhone then
			props.Text = glyph
			props.TextSize = PHONE_GLYPH_SIZE
			props.SubText = word
			props.SubTextSize = PHONE_WORD_SIZE
			props.Icon = nil
			props.Size = UDim2.fromOffset(PHONE_CARD, PHONE_CARD)
		end
		return props
	end

	local upgrades, holder = UIKit.Button(forPhone({
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
	}, "⬆️", "UPGRADE"))
	upgradesButton = upgrades
	upgradesHolder = holder
	buttonsByName.Upgrades = upgrades
	local pulseScale = Instance.new("UIScale")
	pulseScale.Name = "PulseScale"
	pulseScale.Parent = holder

	buttonsByName.Items = UIKit.Button(forPhone({
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
	}, "🎒", "ITEMS"))

	buttonsByName.Index = UIKit.Button(forPhone({
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
	}, "📖", "INDEX"))

	-- REBIRTH: always there, a fill of cash against the next rebirth's cost
	-- and "$2.1M / $15M"; glows and pulses once you can afford it. Opens
	-- the Rebirth panel from anywhere (the Portal still works too).
	local rebirth, rebirthHolder = UIKit.Button(forPhone({
		Name = "RebirthButton",
		Parent = buttonRow,
		Style = "Violet",
		Text = "REBIRTH",
		SubText = " ",
		SubTextSize = if isPhone then 10 else 13,
		IconStacked = isPhone,
		Size = size,
		TextSize = layout.ButtonTextSize,
		LayoutOrder = 4,
		OnClick = RebirthPanel.Open,
	}, "🔁", "REBIRTH"))
	buttonsByName.Rebirth = rebirth
	rebirthButton = rebirth
	local fill = Instance.new("Frame")
	fill.Name = "RebirthFill"
	fill.BackgroundColor3 = Colors.White
	fill.BackgroundTransparency = REBIRTH_FILL_TRANSPARENCY
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = rebirth.ZIndex
	fill.Parent = rebirth
	if isPhone then
		-- The progress runs along the card's bottom edge.
		fill.AnchorPoint = Vector2.new(0, 1)
		fill.Position = UDim2.fromScale(0, 1)
		fill.Size = UDim2.new(0, 0, 0, REBIRTH_BAR_HEIGHT)
		fill.BackgroundTransparency = 0.1
		UIKit.Corner(fill, REBIRTH_BAR_HEIGHT / 2)
	else
		UIKit.Corner(fill, UITheme.Radius.Button)
	end
	rebirthFill = fill
	local glow = Instance.new("Frame")
	glow.Name = "RebirthGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, REBIRTH_GLOW_PAD, 1, REBIRTH_GLOW_PAD)
	glow.BackgroundColor3 = Colors.VioletLight
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.ZIndex = math.max(rebirthHolder.ZIndex - 2, 0)
	glow.Parent = rebirthHolder
	UIKit.Corner(glow, UITheme.Radius.Button + REBIRTH_GLOW_PAD / 2)
	rebirthGlow = glow
	local scale = Instance.new("UIScale")
	scale.Name = "RebirthPulse"
	scale.Parent = rebirthHolder
	rebirthScale = scale
	rebirthPulse = nil
	rebirthGlowTween = nil

	-- ⚙ Settings: a 56 px square at the right end of the bar.
	buttonsByName.Settings = UIKit.Button(forPhone({
		Name = "SettingsButton",
		Parent = buttonRow,
		Style = "Disabled",
		Text = "⚙",
		Size = UDim2.fromOffset(SETTINGS_BUTTON_SIZE, SETTINGS_BUTTON_SIZE),
		TextSize = 26,
		LayoutOrder = 5,
		OnClick = SettingsPanel.Toggle,
	}, "⚙️", "OPTIONS"))
	if isPhone then
		-- The fixed-size buttons above have no stacked icon layout: stack the
		-- glyph over the word (what IconStacked does for the others).
		local settingsContent = buttonsByName.Settings:FindFirstChild("Content")
		local settingsLayout = settingsContent and settingsContent:FindFirstChildOfClass("UIListLayout")
		if settingsLayout then
			settingsLayout.FillDirection = Enum.FillDirection.Vertical
			settingsLayout.Padding = UDim.new(0, 2)
		end
	end

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

--[[ REBIRTH button (bottom bar) -------------------------------------------------
	Built with the bar (buildButtons); this keeps its fill, "$2.1M / $15M"
	and the ready glow + pulse in step with your cash.
]]

local function refreshRebirthButton()
	local button = rebirthButton
	local fill = rebirthFill
	if not button or not fill then
		return
	end
	local cost = TycoonController.GetRebirthCost()
	local cash = TycoonController.GetCash()
	local progress = if cost > 0 then math.clamp(cash / cost, 0, 1) else 0
	if layoutIsPhoneEarly then
		fill.Size = UDim2.new(progress, 0, 0, REBIRTH_BAR_HEIGHT)
	else
		fill.Size = UDim2.fromScale(progress, 1)
		UIKit.SetButton(button, {
			SubText = ("%s / %s"):format(NumberFormat.Money(math.min(cash, cost)), NumberFormat.Money(cost)),
		})
	end
	local ready = TycoonController.IsRebirthReady()
	if ready and not rebirthPulse and rebirthScale and rebirthGlow then
		local pulse = TweenService:Create(
			rebirthScale,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = REBIRTH_PULSE_SCALE }
		)
		pulse:Play()
		rebirthPulse = pulse
		rebirthGlow.BackgroundTransparency = 0.75
		local glow = TweenService:Create(
			rebirthGlow,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = 0.25 }
		)
		glow:Play()
		rebirthGlowTween = glow
	elseif not ready and rebirthPulse then
		(rebirthPulse :: Tween):Cancel()
		rebirthPulse = nil
		if rebirthGlowTween then
			rebirthGlowTween:Cancel()
			rebirthGlowTween = nil
		end
		if rebirthScale then
			rebirthScale.Scale = 1
		end
		if rebirthGlow then
			rebirthGlow.BackgroundTransparency = 1
		end
	end
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
local lockPadding: UIPadding? = nil
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
		lockPadding = UIKit.Padding(content, 0, LOCK_CHIP_PADDING, 0, LOCK_CHIP_PADDING)
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

-- Phone: the chip is a 56 px icon card (a glyph over a 13 px word: "LOCK",
-- the seconds left, "RUN!"); desktop: the chip that sizes itself to its text.
local function applyLockLayout(isPhone: boolean)
	local content = lockChip:FindFirstChild("Content")
	local layout = content and content:FindFirstChildOfClass("UIListLayout")
	local column = content and content:FindFirstChild("TextColumn")
	local label = column and column:FindFirstChild("Label") :: TextLabel?
	local sub = column and column:FindFirstChild("SubLabel") :: TextLabel?
	if not (content and content:IsA("Frame") and layout and label and sub) then
		return
	end
	if isPhone then
		lockHolder.AutomaticSize = Enum.AutomaticSize.None
		lockHolder.Size = UDim2.fromOffset(PHONE_CARD, PHONE_CARD)
		lockChip.AutomaticSize = Enum.AutomaticSize.None
		lockChip.Size = UDim2.fromScale(1, 1)
		content.AutomaticSize = Enum.AutomaticSize.None
		content.Size = UDim2.fromScale(1, 1)
		if lockPadding then
			lockPadding.PaddingLeft = UDim.new(0, 0)
			lockPadding.PaddingRight = UDim.new(0, 0)
		end
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.Padding = UDim.new(0, 0)
		label.TextSize = PHONE_GLYPH_SIZE
		sub.TextSize = PHONE_WORD_SIZE
	else
		lockHolder.AutomaticSize = Enum.AutomaticSize.X
		lockHolder.Size = UDim2.fromOffset(0, LOCK_CHIP_HEIGHT)
		lockChip.AutomaticSize = Enum.AutomaticSize.X
		lockChip.Size = UDim2.new(0, 0, 1, 0)
		content.AutomaticSize = Enum.AutomaticSize.X
		content.Size = UDim2.new(0, 0, 1, 0)
		if lockPadding then
			lockPadding.PaddingLeft = UDim.new(0, LOCK_CHIP_PADDING)
			lockPadding.PaddingRight = UDim.new(0, LOCK_CHIP_PADDING)
		end
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, 8)
		label.TextSize = LOCK_CHIP_TEXT_SIZE
		sub.Text = ""
		sub.Visible = false
	end
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
	if selfTestHold then
		return
	end
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
	-- Phone card: glyph over a short word.
	local glyph = if alarm then "🚨" elseif state == "Locked" then "🛡" elseif state == "Recharging" then "⏳" else "🔓"
	local word = if alarm then "RUN!" elseif state == "Ready" then "LOCK" else ("%ds"):format(seconds)
	UIKit.SetButton(lockChip, {
		Style = if style ~= lockStyle then style else nil,
		Text = if layoutIsPhoneEarly then glyph else text,
		SubText = if layoutIsPhoneEarly then word else nil,
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

-- The cash panel: desktop is the big card; the phone's is slim (cash over
-- "$/s" + the multiplier pills, ~60% of the height) with the cash number
-- still the largest text on the HUD.
local function applyCashLayout(isPhone: boolean)
	local size = if isPhone then CASH_CARD_PHONE else CASH_CARD_SIZE
	cashHolder.Size = UDim2.fromOffset(size.X, size.Y)
	local coinLabel = cashCoin:FindFirstChildOfClass("TextLabel")
	local pillRoots = { UIKit.PillRoot(rebirthPill), UIKit.PillRoot(multiplierPill) }
	if isPhone then
		cashPadding.PaddingTop = UDim.new(0, 6)
		cashPadding.PaddingBottom = UDim.new(0, 6)
		cashPadding.PaddingLeft = UDim.new(0, 10)
		cashPadding.PaddingRight = UDim.new(0, 10)
		cashCoin.Size = UDim2.fromOffset(24, 24)
		cashCoin.Position = UDim2.fromOffset(0, 2)
		if coinLabel then
			coinLabel.TextSize = 14
		end
		cashLabel.TextSize = 28
		cashLabel.Position = UDim2.fromOffset(30, 0)
		cashLabel.Size = UDim2.new(1, -30, 0, 28)
		incomeLabel.TextSize = 13
		incomeLabel.Position = UDim2.fromOffset(0, 30)
		incomeLabel.Size = UDim2.new(1, -PILL_ROW_PHONE, 0, 20)
		cashPills.Position = UDim2.new(1, 0, 0, 30)
		cashPills.Size = UDim2.fromOffset(PILL_ROW_PHONE, 20)
	else
		cashPadding.PaddingTop = UDim.new(0, 12)
		cashPadding.PaddingBottom = UDim.new(0, 12)
		cashPadding.PaddingLeft = UDim.new(0, 14)
		cashPadding.PaddingRight = UDim.new(0, 14)
		cashCoin.Size = UDim2.fromOffset(34, 34)
		cashCoin.Position = UDim2.fromOffset(0, 3)
		if coinLabel then
			coinLabel.TextSize = 18
		end
		cashLabel.TextSize = 34
		cashLabel.Position = UDim2.fromOffset(44, 0)
		cashLabel.Size = UDim2.new(1, -44, 0, 40)
		incomeLabel.TextSize = 16
		incomeLabel.Position = UDim2.fromOffset(0, 46)
		incomeLabel.Size = UDim2.new(1, -PILL_ROW_WIDTH, 0, 24)
		cashPills.Position = UDim2.new(1, 0, 0, 46)
		cashPills.Size = UDim2.fromOffset(PILL_ROW_WIDTH, 24)
	end
	for _, root in pillRoots do
		root.Size = UDim2.fromOffset(0, if isPhone then 20 else 24)
		local padding = root:FindFirstChild("Text") and (root :: any).Text:FindFirstChildOfClass("UIPadding")
		if padding then
			padding.PaddingLeft = UDim.new(0, if isPhone then 6 else 10)
			padding.PaddingRight = UDim.new(0, if isPhone then 6 else 10)
		end
	end
end

--[[ SHOP button ---------------------------------------------------------------------
	A big gold "🛒 SHOP" on the left edge, above the LOCK chip (>= 56 px
	tall), wiggling gently every SHOP_WIGGLE_SECONDS; a red SALE tag only
	while a real sale is live. The active effects (boost, luck,
	Overclock, ...) are round icons in UI/EffectsTray, a column on the right edge.
	Beside SHOP, the pink "🎁 GIFTS" (GiftsPanel): a green count badge and a
	bounce while any playtime gift is ready, otherwise a small "next in
	3:12" pill (hidden once this visit's gifts are all open).
]]
local SHOP_BUTTON_SIZE = Vector2.new(132, 56)
-- Room for the SALE tag (it pokes 8 px past SHOP's right edge) beside the
-- bouncing GIFTS button (×1.08).
local SHOP_ROW_GAP = 14
local SHOP_WIGGLE_SECONDS = 20
local SHOP_WIGGLE_DEGREES = 7
local GIFTS_NEXT_HEIGHT = 24
local GIFTS_BUTTON_SIZE = Vector2.new(124, 56)
local GIFTS_BOUNCE_SCALE = 1.08

local shopRow: Frame
local shopHolder: Frame
local saleTag: TextLabel
local giftsButton: TextButton
local giftsHolderRef: Frame
local giftsScale: UIScale
local giftsNextPill: TextLabel
-- Phone only: the left-column stack under SHOP / GIFTS that holds the deal
-- badge on its own line, then "next in", so nothing grows toward the screen
-- centre (applyLayout).
local phoneStatus: Frame
local phoneStatusLayout: UIListLayout
local PHONE_STATUS_GAP = 4
local giftsBounce: Tween? = nil

-- The deal tile (ShopController.GetDeal): a pack picture on a Deal-pink tile
-- with slow rays behind it, a gold "−23%" ribbon (the live saving) and the
-- real countdown in a pill under it. A new slot pulses it once and plays the
-- shine at once; a tap opens the shop at the deal. Under SHOP / GIFTS on its
-- own line, desktop and phone alike (on a phone it heads the status stack,
-- with "next in" under it). Idle motion is only the rays (360° per
-- 12 s) and one 0.5 s shine every 6 s: no flashing, and the timer looks the
-- same at 5:59 and at 0:30 (monetization.md "never" list).
local DEAL_TILE_SIZE = { Desktop = 92, Phone = 56 } -- phone: the same 56 px card as the grid
local DEAL_HOLDER_WIDTH = 92
local DEAL_TILE_RADIUS = 16
local DEAL_ART_SCALE = 0.66 -- the pack picture, of the tile (it leaves the bottom strip free)
local DEAL_ART_Y = 0.4
local DEAL_STRIP_HEIGHT = 0.24 -- the part glyphs along the bottom edge, of the tile
local DEAL_TIMER_HEIGHT = 22
local DEAL_TIMER_GAP = 6
local DEAL_RAY_SECONDS = 12
local DEAL_RAY_BARS = 6 -- thin bars through the centre = 12 rays
local DEAL_RAY_TRANSPARENCY = 0.6
local DEAL_SHINE_PERIOD = 6
local DEAL_SHINE_SECONDS = 0.5
local dealHolder: Frame
local dealTile: Frame
local dealRays: Frame
local dealImage: ImageLabel
local dealGlyph: TextLabel
local dealRibbonText: TextLabel
local dealParts: TextLabel
local dealTimer: TextLabel
local dealShine: UIGradient
-- "<deal key>|<icon asset>" of the art on show, so the picture is only
-- touched when it changes.
local dealArtKey = ""
local dealShineStart = 0 -- os.clock() of the sweep in progress / the last one
local dealMotion: RBXScriptConnection? = nil
local dealSlot: number? = nil
local dealShown = false
local layoutIsPhone = false

local function dealTileSize(isPhone: boolean): number
	return if isPhone then DEAL_TILE_SIZE.Phone else DEAL_TILE_SIZE.Desktop
end

-- Tile + gap + timer pill: the height the left column reserves.
local function dealHolderHeight(isPhone: boolean): number
	return dealTileSize(isPhone) + DEAL_TIMER_GAP + DEAL_TIMER_HEIGHT
end

local function sizeDealTile(isPhone: boolean)
	local size = dealTileSize(isPhone)
	dealHolder.Size = UDim2.fromOffset(DEAL_HOLDER_WIDTH, dealHolderHeight(isPhone))
	dealTile.Size = UDim2.fromOffset(size, size)
	dealGlyph.TextSize = math.floor(size * 0.46) -- 42 px on desktop
	dealParts.TextSize = math.max(13, math.floor(size * 0.17)) -- 15 px on desktop; never under 13
	UIKit.PillRoot(dealTimer).Position = UDim2.fromOffset(0, size + DEAL_TIMER_GAP)
end

-- Rays turn and the shine sweeps only while the tile is on screen.
local function setDealMotion(on: boolean)
	if on and not dealMotion then
		dealShineStart = os.clock()
		dealMotion = RunService.RenderStepped:Connect(function(dt: number)
			dealRays.Rotation = (dealRays.Rotation + 360 / DEAL_RAY_SECONDS * dt) % 360
			local t = (os.clock() - dealShineStart) % DEAL_SHINE_PERIOD
			-- Off the tile (-1) between sweeps, across it (-1 -> 1) in 0.5 s.
			dealShine.Offset = Vector2.new(if t < DEAL_SHINE_SECONDS then -1 + 2 * t / DEAL_SHINE_SECONDS else -1, 0)
		end)
	elseif not on and dealMotion then
		dealMotion:Disconnect()
		dealMotion = nil
	end
end

local function buildDealBadge()
	local holder = Instance.new("Frame")
	holder.Name = "DealBadge"
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = 0
	holder.Visible = false
	holder.Parent = screenGui
	dealHolder = holder

	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.BackgroundColor3 = Colors.White
	tile.BorderSizePixel = 0
	tile.ZIndex = 2
	tile.Parent = holder
	UIKit.Corner(tile, DEAL_TILE_RADIUS)
	UIKit.Stroke(tile, 3, Colors.White)
	UIKit.PairGradient(tile, UITheme.Gradients.Pink)
	UIKit.Shadow(tile, UITheme.SmallShadowOffset)
	dealTile = tile

	-- Everything inside is clipped to the rounded tile.
	local clip = Instance.new("CanvasGroup")
	clip.Name = "Clip"
	clip.BackgroundTransparency = 1
	clip.Size = UDim2.fromScale(1, 1)
	clip.ZIndex = 2
	clip.Parent = tile
	UIKit.Corner(clip, DEAL_TILE_RADIUS)

	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromScale(1.5, 1.5) -- covers the corners while it turns
	rays.ZIndex = 2
	rays.Parent = clip
	for index = 1, DEAL_RAY_BARS do
		local bar = Instance.new("Frame")
		bar.Name = "Ray"
		bar.BackgroundColor3 = Colors.DealRay
		bar.BackgroundTransparency = DEAL_RAY_TRANSPARENCY
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(0, 9, 1, 0)
		bar.Rotation = (index - 1) * (180 / DEAL_RAY_BARS)
		bar.ZIndex = 2
		bar.Parent = rays
	end
	dealRays = rays

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.BackgroundColor3 = Colors.DealRay
	glow.BackgroundTransparency = 0.75
	glow.BorderSizePixel = 0
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, DEAL_ART_Y)
	glow.Size = UDim2.fromScale(0.62, 0.62)
	glow.ZIndex = 3
	glow.Parent = clip
	UIKit.Corner(glow, 999)

	local image = Instance.new("ImageLabel")
	image.Name = "Art"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, DEAL_ART_Y)
	image.Size = UDim2.fromScale(DEAL_ART_SCALE, DEAL_ART_SCALE)
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = 4
	image.Visible = false
	image.Parent = clip
	dealImage = image

	-- No icon yet (not set in Creator Hub, or still loading): the deal's
	-- emoji, so the tile never looks broken.
	dealGlyph = UIKit.Label({
		Name = "Glyph",
		Text = "🔥",
		TextSize = 48,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, DEAL_ART_Y),
		Size = UDim2.fromScale(DEAL_ART_SCALE, DEAL_ART_SCALE),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
		Parent = clip,
	})

	-- The part glyphs along the bottom edge ("⚡ 🧪"): a hint of what's inside.
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundColor3 = Colors.Ink
	strip.BackgroundTransparency = 0.35
	strip.BorderSizePixel = 0
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.Position = UDim2.fromScale(0, 1)
	strip.Size = UDim2.fromScale(1, DEAL_STRIP_HEIGHT)
	strip.ZIndex = 5
	strip.Parent = clip
	dealParts = UIKit.Label({
		Name = "Parts",
		Text = "",
		TextSize = 15,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6,
		Parent = strip,
	})

	-- Diagonal gold ribbon across the top-right corner: white text with the
	-- ink stroke (the contrast rule).
	local ribbon = Instance.new("Frame")
	ribbon.Name = "Ribbon"
	ribbon.BackgroundColor3 = Colors.White
	ribbon.BorderSizePixel = 0
	ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
	ribbon.Position = UDim2.fromScale(0.77, 0.23)
	ribbon.Size = UDim2.fromScale(0.95, 0.21)
	ribbon.Rotation = 45
	ribbon.ZIndex = 6
	ribbon.Parent = clip
	UIKit.PairGradient(ribbon, UITheme.Gradients.Gold)
	UIKit.Stroke(ribbon, 1.5)
	dealRibbonText = UIKit.Label({
		Name = "Text",
		Text = "DEAL",
		Font = Fonts.Display,
		TextColor3 = UITheme.WarmText,
		Stroke = UITheme.WarmTextStroke,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 7,
		Parent = ribbon,
	})
	UIKit.FitText(dealRibbonText, 14, 8)

	-- The shine: a white diagonal band that sweeps across once per period.
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Colors.White
	shine.BorderSizePixel = 0
	shine.Size = UDim2.fromScale(1, 1)
	shine.ZIndex = 8
	shine.Parent = clip
	local sweep = Instance.new("UIGradient")
	sweep.Rotation = 30
	sweep.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.38, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(0.62, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sweep.Offset = Vector2.new(-1, 0)
	sweep.Parent = shine
	dealShine = sweep

	dealTimer = UIKit.Pill({
		Name = "Timer",
		Parent = holder,
		Text = "🔥",
		Color = Colors.Panel,
		Font = Fonts.Display,
		TextSize = 13,
		Height = DEAL_TIMER_HEIGHT,
		ZIndex = 3,
		TextStroke = 1.5,
	})

	-- The whole tile and the timer are one tap target (holder >= 44 px).
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 20
	hit.Parent = holder
	hit.Activated:Connect(function()
		UIKit.SelectFeedback(tile)
		ShopPanel.Open("Deal")
	end)
	sizeDealTile(false)

	phoneStatus = Instance.new("Frame")
	phoneStatus.Name = "PhoneStatus"
	phoneStatus.BackgroundTransparency = 1
	phoneStatus.AutomaticSize = Enum.AutomaticSize.XY
	phoneStatus.Size = UDim2.new()
	phoneStatus.Visible = false
	phoneStatus.Parent = screenGui
	phoneStatusLayout = Instance.new("UIListLayout")
	phoneStatusLayout.FillDirection = Enum.FillDirection.Vertical
	phoneStatusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	phoneStatusLayout.Padding = UDim.new(0, PHONE_STATUS_GAP)
	phoneStatusLayout.SortOrder = Enum.SortOrder.LayoutOrder
	phoneStatusLayout.Parent = phoneStatus
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

	local shopButton, holder = UIKit.Button({
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
	addCard(shopButton, holder, "🛒", "SHOP", "🛒 SHOP", 22).Holder.LayoutOrder = 1
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
	giftsHolderRef = giftsHolder
	addCard(gifts, giftsHolder, "🎁", "GIFTS", "🎁 GIFTS", 20)
	giftsScale = Instance.new("UIScale")
	giftsScale.Parent = giftsHolder
	giftsNextPill = UIKit.Pill({
		Name = "GiftsNext",
		Parent = shopRow,
		Text = "",
		Color = Colors.Panel2,
		TextColor3 = Colors.Muted,
		TextSize = 13,
		Height = GIFTS_NEXT_HEIGHT,
		LayoutOrder = 3,
		TextStroke = 1.5,
	})
	UIKit.SetPillVisible(giftsNextPill, false)

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

--[[ QUESTS button, power-up row, goal tracker ----------------------------------
	Under SHOP / GIFTS: the amber "📜 QUESTS" (QuestsPanel) with a red "!"
	badge (a quest or the lab chain step done, not claimed) and a bounce
	while any is, then
	one round button per power-up you own (QuestConfig.PowerUpOrder; glyph,
	a count badge; tap = UsePowerUp, server re-checked). An armed one shows
	✓, Speed Boots its seconds left. Under the NEXT GOAL card, a small
	tracker: the nearest unfinished quest ("📜 Pull 20 times · 12 / 20"),
	a tap opens the panel.
]]
local QUESTS_BUTTON_SIZE = Vector2.new(124, 52)
local POWER_BUTTON_SIZE = UITheme.MinTapSize + 4
local QUEST_TRACKER_HEIGHT = 32
local QUEST_TRACKER_GAP = 6
local questRow: Frame
local questsButton: TextButton
local questsHolderRef: Frame
local questsScale: UIScale
local questsBounce: Tween? = nil
local powerButtons: { [string]: { Holder: Frame, Button: TextButton } } = {}
local questTracker: TextButton

local function buildQuestRow()
	questRow = Instance.new("Frame")
	questRow.Name = "QuestRow"
	questRow.BackgroundTransparency = 1
	questRow.AutomaticSize = Enum.AutomaticSize.X
	questRow.Size = UDim2.fromOffset(0, QUESTS_BUTTON_SIZE.Y + UITheme.ShadowOffset)
	questRow.Parent = screenGui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = questRow

	local button, holder = UIKit.Button({
		Name = "QuestsButton",
		Parent = questRow,
		Style = "Orange",
		Text = "📜 QUESTS",
		TextSize = 18,
		Size = UDim2.fromOffset(QUESTS_BUTTON_SIZE.X, QUESTS_BUTTON_SIZE.Y),
		LayoutOrder = 0,
		OnClick = function()
			QuestsPanel.Toggle()
		end,
	})
	questsButton = button
	questsHolderRef = holder
	addCard(button, holder, "📜", "QUESTS", "📜 QUESTS", 18)
	questsScale = Instance.new("UIScale")
	questsScale.Parent = holder

	for order, key in QuestConfig.PowerUpOrder do
		local def = QuestConfig.PowerUps[key]
		local powerButton, powerHolder = UIKit.Button({
			Name = "PowerUp_" .. key,
			Parent = questRow,
			Style = "Violet",
			Text = def.Glyph,
			TextSize = 22,
			Size = UDim2.fromOffset(POWER_BUTTON_SIZE, POWER_BUTTON_SIZE),
			ShadowOffset = UITheme.SmallShadowOffset,
			LayoutOrder = order,
			OnClick = function()
				QuestsPanel.UsePowerUp(key)
			end,
		})
		UIKit.Corner(powerButton, 999)
		powerHolder.Visible = false
		powerButtons[key] = { Holder = powerHolder, Button = powerButton }
		addCard(powerButton, powerHolder, def.Glyph, "", def.Glyph, 22)
	end

	local tracker = Instance.new("TextButton")
	tracker.Name = "QuestTracker"
	tracker.AutoButtonColor = false
	tracker.BackgroundColor3 = Colors.Panel
	tracker.BackgroundTransparency = 0.1
	tracker.Text = ""
	tracker.FontFace = Fonts.BodyHeavy
	tracker.TextSize = 14
	tracker.TextColor3 = Colors.Text
	tracker.TextTruncate = Enum.TextTruncate.AtEnd
	tracker.Size = UDim2.fromOffset(LAYOUT.Desktop.GoalWidth, QUEST_TRACKER_HEIGHT)
	tracker.Visible = false
	tracker.Parent = screenGui
	UIKit.Corner(tracker, 10)
	UIKit.Stroke(tracker, 2)
	UIKit.Padding(tracker, 0, 10, 0, 10)
	tracker.Activated:Connect(function()
		QuestsPanel.Open()
	end)
	questTracker = tracker
end

-- Once a second: the badge, the power-up buttons, the tracker.
local function refreshQuestRow()
	if selfTestHold then
		return
	end
	local ready = if TycoonController.HasSynced() then QuestsPanel.GetReadyCount() else 0
	-- A red "!" while any quest (a daily or the lab chain) is done and not
	-- claimed; UIKit.Badge hides it at 0.
	local badge = UIKit.Badge(questsButton, ready)
	badge.Text = "!"
	if ready > 0 and not questsBounce then
		local tween = TweenService:Create(
			questsScale,
			TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = GIFTS_BOUNCE_SCALE }
		)
		tween:Play()
		questsBounce = tween
	elseif ready == 0 and questsBounce then
		(questsBounce :: Tween):Cancel()
		questsBounce = nil
		questsScale.Scale = 1
	end
	local quests = TycoonController.GetQuests()
	local speedLeft = if quests and typeof(quests.SpeedBootsUntil) == "number"
		then math.max(0, math.ceil(quests.SpeedBootsUntil - workspace:GetServerTimeNow()))
		else 0
	for key, view in powerButtons do
		local count = TycoonController.GetPowerUpCount(key)
		local armed = TycoonController.IsArmed(key)
		local timed = key == "SpeedBoots" and speedLeft > 0
		view.Holder.Visible = count > 0 or armed or timed
		local def = QuestConfig.PowerUps[key]
		if layoutIsPhone then
			-- A card: the glyph over "ON" / the seconds left; the count is the badge.
			UIKit.SetButton(view.Button, {
				Text = def.Glyph,
				TextSize = PHONE_GLYPH_SIZE,
				SubText = if timed then ("%ds"):format(speedLeft) elseif armed then "ON" else "",
			})
		else
			UIKit.SetButton(view.Button, {
				Text = if timed then ("%s%d"):format(def.Glyph, speedLeft) elseif armed then def.Glyph .. "✓" else def.Glyph,
				TextSize = if timed or armed then 15 else 22,
			})
		end
		local countBadge = UIKit.Badge(view.Button, count)
		countBadge.BackgroundColor3 = Colors.Panel2
	end
	local nearest = QuestsPanel.GetNearest()
	-- Not on a phone: the QUESTS card's red ! and the panel cover it.
	questTracker.Visible = not layoutIsPhone and nearest ~= nil and TycoonController.HasSynced()
	if nearest then
		questTracker.Text = ("📜 %s · %s / %s"):format(
			tostring(nearest.Text),
			NumberFormat.Short(tonumber(nearest.Progress) or 0),
			NumberFormat.Short(tonumber(nearest.Target) or 0)
		)
	end
end

-- /selftest: redraws the QUESTS button now and returns whether its badge is
-- showing and what it says (a red "!" while a quest or the chain is unclaimed).
function HudController.GetQuestsBadge(): (boolean, string)
	refreshQuestRow()
	local badge = questsButton:FindFirstChild("Badge")
	if badge and badge:IsA("TextLabel") then
		return badge.Visible, badge.Text
	end
	return false, ""
end

-- The tracker sits under the goal card (or where it would be when the
-- last goal is done).
local function placeQuestTracker()
	local layout = if layoutIsPhone then LAYOUT.Phone else LAYOUT.Desktop
	questTracker.Size = UDim2.fromOffset(layout.GoalWidth, QUEST_TRACKER_HEIGHT)
	local goalHeight = if goalHolder.Visible then goalHolder.AbsoluteSize.Y / UIKit.EffectiveScale(goalHolder) else 0
	questTracker.Position = goalHolder.Position
		+ UDim2.fromOffset(0, if goalHeight > 0 then math.ceil(goalHeight) + UITheme.ShadowOffset + QUEST_TRACKER_GAP else 0)
end

-- Once a second: the effect pills' timers and the SALE tag.
local applyLayout: (isPhone: boolean) -> ()

-- Whether the tile is up: a live deal for this player (GetDeal is nil for
-- policy-restricted players and without a real saving), not in the
-- tutorial, not while a heist has your hands full, not just after a loss.
local function dealTileShouldShow(deal: any?, tutorial: boolean, quiet: boolean): boolean
	return deal ~= nil and not tutorial and not quiet
end

-- Art: the product's live store icon, else the deal's emoji. Ribbon: the
-- live saving, "DEAL" when unknown. Timer: the real seconds left.
local function applyDealView(item: { Icon: string }, key: string, icon: string?, save: number?, secondsLeft: number, parts: { string }?)
	local artKey = key .. "|" .. (icon or "")
	if artKey ~= dealArtKey then
		dealArtKey = artKey
		dealImage.Visible = icon ~= nil
		dealGlyph.Visible = icon == nil
		if icon then
			dealImage.Image = icon
		end
		dealGlyph.Text = item.Icon
	end
	dealParts.Text = if parts then DealParts.Glyphs(parts) else ""
	dealRibbonText.Text = if save then ("−%d%%"):format(save) else "DEAL"
	dealTimer.Text = "🔥 " .. EventState.FormatTimer(secondsLeft)
end

local function pulseDeal()
	local pulse = dealHolder:FindFirstChild("DealPulse") :: UIScale?
	if not pulse then
		local created = Instance.new("UIScale")
		created.Name = "DealPulse"
		created.Parent = dealHolder
		pulse = created
	end
	local scale = pulse :: UIScale
	scale.Scale = 1.25
	TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function refreshDealBadge()
	local deal = ShopController.GetDeal()
	local shown = dealTileShouldShow(deal, TycoonController.IsTutorialActive(), ShopController.IsDealTileQuiet())
	if deal and shown then
		applyDealView(deal.Item, deal.Key, ShopPrices.GetIcon(deal.Key), deal.Save, deal.SecondsLeft, deal.Item.Parts)
		if dealSlot and dealSlot ~= deal.SlotStart then
			pulseDeal()
			dealShineStart = os.clock() -- the shine plays at once too
		end
		dealSlot = deal.SlotStart
	end
	if shown ~= dealShown then
		dealShown = shown
		dealHolder.Visible = shown
		setDealMotion(shown)
		applyLayout(layoutIsPhone)
	end
end

local function refreshShopRow()
	-- Cash ticks between snapshots: keep the REBIRTH fill moving.
	refreshRebirthButton()
	refreshQuestRow()
	placeQuestTracker()
	if selfTestHold then
		return
	end
	refreshDealBadge()
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

-- Phone: the utility grid of 56 px icon cards (3 per row, 6 px gaps).
local function buildPhoneGrid()
	phoneGrid = Instance.new("Frame")
	phoneGrid.Name = "PhoneGrid"
	phoneGrid.BackgroundTransparency = 1
	phoneGrid.AutomaticSize = Enum.AutomaticSize.Y
	phoneGrid.Size = UDim2.fromOffset(PHONE_CARD, 0)
	phoneGrid.Visible = false
	phoneGrid.Parent = screenGui
	phoneGridLayout = Instance.new("UIGridLayout")
	phoneGridLayout.CellSize = UDim2.fromOffset(PHONE_CARD, PHONE_CARD)
	-- 6 px between cards; the rows' gap also holds the 5 px shadow.
	phoneGridLayout.CellPadding = UDim2.fromOffset(PHONE_CARD_GAP, PHONE_CARD_GAP + UITheme.ShadowOffset)
	phoneGridLayout.FillDirection = Enum.FillDirection.Horizontal
	phoneGridLayout.FillDirectionMaxCells = PHONE_GRID_COLUMNS
	phoneGridLayout.StartCorner = Enum.StartCorner.TopLeft
	phoneGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	phoneGridLayout.Parent = phoneGrid
end

-- The cards live in the grid on a phone and in their desktop rows otherwise.
local function parentCards(isPhone: boolean)
	local function put(holder: Frame, desktopParent: Instance, desktopOrder: number, gridOrder: number)
		holder.Parent = if isPhone then phoneGrid else desktopParent
		holder.LayoutOrder = if isPhone then gridOrder else desktopOrder
	end
	put(shopHolder, shopRow, 1, 1)
	put(giftsHolderRef, shopRow, 2, 2)
	put(questsHolderRef, questRow, 0, 3)
	for order, key in QuestConfig.PowerUpOrder do
		put(powerButtons[key].Holder, questRow, order, 10 + order)
	end
	put(lockHolder, lockRow, 1, 30)
	put(helpHolder, lockRow, 2, 31)
	for _, card in cards do
		setCardCompact(card, isPhone)
	end
	applyLockLayout(isPhone)
end

local function placeColumnFor(isPhone: boolean)
	local layout = if isPhone then LAYOUT.Phone else LAYOUT.Desktop
	-- The left column is one stack. Desktop: NEXT GOAL, the quest tracker,
	-- then the cash card (never above where the card used to sit), so a
	-- goal that wraps or a tracker that appears pushes everything down
	-- instead of overlapping it. Phone: the goal follows the LOCK row.
	local cashPosition = layout.CashPosition
	if not isPhone then
		local bottom = layout.GoalPosition.Y.Offset
		if goalHolder.Visible then
			bottom += math.ceil(goalHolder.AbsoluteSize.Y / UIKit.EffectiveScale(goalHolder)) + UITheme.ShadowOffset
		end
		if questTracker.Visible then
			bottom += (if goalHolder.Visible then QUEST_TRACKER_GAP else 0) + QUEST_TRACKER_HEIGHT
		end
		cashPosition = UDim2.fromOffset(layout.CashPosition.X.Offset, math.max(layout.CashPosition.Y.Offset, bottom + LOCK_BUTTON_GAP))
	end
	cashHolder.Position = cashPosition
	if isPhone then
		-- Phone stack: the slim cash panel, the one-line NEXT GOAL pill (when
		-- there is a goal), then the utility grid (3 per row) with the status
		-- stack (deal tile, "next in") BESIDE it, so the column stays short.
		-- SHOP / QUESTS / LOCK rows are empty here (their cards are in the
		-- grid); the quest tracker is hidden.
		local x = cashPosition.X.Offset
		local gridTop = cashPosition.Y.Offset + CASH_CARD_PHONE.Y + UITheme.ShadowOffset + PHONE_CARD_GAP
		goalHolder.Position = UDim2.fromOffset(x, gridTop)
		if goalHolder.Visible then
			-- AbsoluteSize is in screen px; the offsets are design px.
			gridTop += math.ceil(goalHolder.AbsoluteSize.Y / UIKit.EffectiveScale(goalHolder)) + UITheme.ShadowOffset + PHONE_CARD_GAP
		end
		local shown = 0
		for _, child in phoneGrid:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				shown += 1
			end
		end
		local columns = math.clamp(shown, 1, PHONE_GRID_COLUMNS)
		phoneGrid.Size = UDim2.fromOffset(columns * PHONE_CARD + (columns - 1) * PHONE_CARD_GAP, 0)
		phoneGrid.Position = UDim2.fromOffset(x, gridTop)
		local statusX = x
		if shown > 0 then
			statusX += phoneGrid.Size.X.Offset + PHONE_CARD_GAP + UITheme.ShadowOffset
		end
		for _, row in { shopRow, questRow, lockRow } do
			row.Position = phoneGrid.Position
		end
		phoneStatus.Visible = true
		sizeDealTile(true)
		dealHolder.Parent = phoneStatus
		UIKit.PillRoot(giftsNextPill).Parent = phoneStatus
		phoneStatus.Position = UDim2.fromOffset(statusX, gridTop)
		placeQuestTracker()
		return
	end
	phoneStatus.Visible = false
	-- The left column on desktop: cash card, then the SHOP / GIFTS row, then
	-- the QUESTS row, then the LOCK row (the goal tracker sits above the cash card).
	local shopTop = cashPosition + UDim2.fromOffset(0, CASH_CARD_SIZE.Y + UITheme.ShadowOffset + LOCK_BUTTON_GAP)
	shopRow.Position = shopTop
	-- The QUESTS row under SHOP / GIFTS.
	local questTop = shopTop + UDim2.fromOffset(0, SHOP_BUTTON_SIZE.Y + UITheme.ShadowOffset + LOCK_BUTTON_GAP)
	questRow.Position = questTop
	local lockTop = questTop + UDim2.fromOffset(0, QUESTS_BUTTON_SIZE.Y + UITheme.ShadowOffset + LOCK_BUTTON_GAP)
	sizeDealTile(false)
	UIKit.PillRoot(giftsNextPill).Parent = shopRow
	dealHolder.Parent = screenGui
	dealHolder.Position = lockTop
	if dealShown then
		lockTop += UDim2.fromOffset(0, dealHolderHeight(false) + UITheme.SmallShadowOffset + LOCK_BUTTON_GAP)
	end
	lockRow.Position = lockTop
	goalHolder.Position = layout.GoalPosition
	placeQuestTracker()
end

-- Re-places the left column only (the phone status stack changed height:
-- a pill came or went); no button rebuild.
local function placeColumn()
	placeColumnFor(layoutIsPhone)
end

function applyLayout(isPhone: boolean)
	layoutIsPhone = isPhone
	local layout = if isPhone then LAYOUT.Phone else LAYOUT.Desktop
	applyGoalLayout(isPhone)
	if isPhone then
		questTracker.Visible = false
	end
	applyCashLayout(isPhone)
	parentCards(isPhone)
	-- Which of the rows / the grid is the live one follows the layout; the
	-- tutorial gate (HudGate "Shop") decides whether it shows yet.
	local gateOpen = HudGate.IsShown("Shop")
	phoneGrid.Visible = isPhone and gateOpen
	shopRow.Visible = not isPhone and gateOpen
	questRow.Visible = not isPhone and gateOpen
	placeColumnFor(isPhone)
	goalHolder.Size = UDim2.fromOffset(layout.GoalWidth, 0)
	goalRewardLabel.Visible = not isPhone
	goalBar.Size = UDim2.new(1, 0, 0, layout.GoalBarHeight)
	buildButtons(isPhone)
	refreshRebirthButton()
end

--[[ /selftest ------------------------------------------------------------- ]]

-- The phone Harris tested on (844 × 390): on a wider Studio window the left
-- group is measured against this width, so a badge drifting to the centre
-- of a phone still fails.
local SELFTEST_PHONE_WIDTH = 844
local SELFTEST_LEFT_SHARE = 0.4
-- The test phones' heights (844 x 390 and 896 x 414) and the gap the column
-- keeps above the bottom edge, in the HUD's design px after the UIScale.
local SELFTEST_PHONE_HEIGHTS = { 390, 414 }
local SELFTEST_BOTTOM_MARGIN = 8

-- Shows the deal badge and "next in" with long sample texts, then checks every element of the left group ends inside
-- the left 40% of the screen. The caller forces the phone layout first.
function HudController.SelfTestLeftColumn(scaleName: string): { string }
	selfTestHold = true
	dealShown = true
	dealHolder.Visible = true
	applyDealView({ Icon = "🔥" }, "SelfTest", nil, 23, 5 * 3600 + 59 * 60 + 59, { "Boost", "LuckPotion" })
	UIKit.SetPillVisible(giftsNextPill, true)
	giftsNextPill.Text = "next in 59:59"
	-- Worst case for the height: every card of the grid up, three power-ups.
	lockHolder.Visible = true
	helpHolder.Visible = true
	shopHolder.Visible = true
	for order, key in QuestConfig.PowerUpOrder do
		powerButtons[key].Holder.Visible = order <= 3
	end
	phoneGrid.Visible = true
	goalHolder.Visible = true
	goalPhoneText.Text = "Fuse 5 times to unlock the next orb tier"
	goalPhoneReward.Text = "+$1.25M"
	applyLayout(layoutIsPhone)
	task.wait(0.3)

	local limit = SELFTEST_LEFT_SHARE * math.min(screenGui.AbsoluteSize.X, SELFTEST_PHONE_WIDTH)
	local parts: { [string]: GuiObject } = {
		CashCard = cashHolder,
		ShopRow = shopRow,
		QuestRow = questRow,
		PhoneGrid = phoneGrid,
		PhoneStatus = phoneStatus,
		DealBadge = dealHolder,
		GiftsNext = UIKit.PillRoot(giftsNextPill),
		LockRow = lockRow,
		Goal = goalHolder,
	}
	local bad: { string } = {}
	local checked = 0
	for name, gui in parts do
		if layoutIsPhone and gui.Visible and gui:IsDescendantOf(screenGui) then
			checked += 1
			local right = gui.AbsolutePosition.X + gui.AbsoluteSize.X
			if right > limit then
				table.insert(bad, ("%s ends at %d px"):format(name, math.floor(right)))
			end
		end
	end

	-- Nothing in the column may overlap anything else: the rows, the goal
	-- card, the quest tracker and the deal badge are laid out as one stack.
	local stacked: { [string]: GuiObject } = {
		CashCard = cashHolder,
		ShopRow = shopRow,
		QuestRow = questRow,
		PhoneGrid = phoneGrid,
		LockRow = lockRow,
		Goal = goalHolder,
		QuestTracker = questTracker,
		DealBadge = if layoutIsPhone then phoneStatus else dealHolder,
	}
	local trackerWas, goalWas = questTracker.Visible, goalHolder.Visible
	questTracker.Visible = not layoutIsPhone -- hidden on a phone
	goalHolder.Visible = true
	task.wait(0.2)
	local names: { string } = {}
	for name in stacked do
		table.insert(names, name)
	end
	table.sort(names)
	local overlaps: { string } = {}
	local measured = 0
	for i, a in names do
		local ga = stacked[a]
		if not (ga.Visible and ga:IsDescendantOf(screenGui)) then
			continue
		end
		measured += 1
		for j = i + 1, #names do
			local gb = stacked[names[j]]
			if gb.Visible and gb:IsDescendantOf(screenGui) then
				local pa, sa, pb, sb = ga.AbsolutePosition, ga.AbsoluteSize, gb.AbsolutePosition, gb.AbsoluteSize
				local overlapX = math.min(pa.X + sa.X, pb.X + sb.X) - math.max(pa.X, pb.X)
				local overlapY = math.min(pa.Y + sa.Y, pb.Y + sb.Y) - math.max(pa.Y, pb.Y)
				if overlapX > 1 and overlapY > 1 then
					table.insert(overlaps, ("%s/%s"):format(a, names[j]))
				end
			end
		end
	end

	-- The phone's column must fit the screen: every element's bottom is at
	-- least SELFTEST_BOTTOM_MARGIN above the bottom edge of both test phones
	-- (the column is pinned to the top-left, so the window size does not matter).
	local lowest, lowestName = 0, ""
	local inset = GuiService:GetGuiInset().Y
	local columnScale = UIKit.EffectiveScale(screenGui)
	for name, gui in stacked do
		if gui.Visible and gui:IsDescendantOf(screenGui) then
			local bottom = (gui.AbsolutePosition.Y + gui.AbsoluteSize.Y + inset) / columnScale
			if bottom > lowest then
				lowest, lowestName = bottom, name
			end
		end
	end
	local cutOff: { string } = {}
	for _, height in SELFTEST_PHONE_HEIGHTS do
		local edge = height / UITheme.PhoneScale - SELFTEST_BOTTOM_MARGIN
		if lowest > edge then
			table.insert(cutOff, ("%s ends at %d, past %d on a %d px tall phone"):format(lowestName, math.ceil(lowest), math.floor(edge), height))
		end
	end

	questTracker.Visible = trackerWas
	goalHolder.Visible = goalWas
	selfTestHold = false
	refreshShopRow()
	refreshQuestRow()
	refreshLockChip()
	local lines: { string } = {}
	if layoutIsPhone then
		table.insert(lines, if #cutOff == 0
			then ("PASS hud left column fits the screen (%s, lowest element %s ends at %d, 844 x 390 and 896 x 414 allow %d and %d)"):format(
				scaleName, lowestName, math.ceil(lowest),
				math.floor(SELFTEST_PHONE_HEIGHTS[1] / UITheme.PhoneScale - SELFTEST_BOTTOM_MARGIN),
				math.floor(SELFTEST_PHONE_HEIGHTS[2] / UITheme.PhoneScale - SELFTEST_BOTTOM_MARGIN))
			else ("FAIL hud left column fits the screen (%s): %s"):format(scaleName, table.concat(cutOff, "; ")))
	end
	if not layoutIsPhone then
		-- The 40% rule is the phone's; desktop has the room.
	elseif #bad > 0 then
		table.sort(bad)
		table.insert(lines, ("FAIL hud left column (%s): past %d px: %s"):format(scaleName, math.floor(limit), table.concat(bad, ", ")))
	else
		table.insert(lines, ("PASS hud left column (%s, %d elements inside %d px)"):format(scaleName, checked, math.floor(limit)))
	end
	if #overlaps > 0 then
		table.insert(lines, ("FAIL hud left column overlap (%s): %s"):format(scaleName, table.concat(overlaps, ", ")))
	else
		table.insert(lines, ("PASS hud left column overlap (%s, %d rects)"):format(scaleName, measured))
	end
	return lines
end

-- Screen-px rects (Position, Size; the top-bar inset added back, as /selftest
-- measures) of what the Gacha pop-up card must stay clear of: the left
-- column (cash card, SHOP / QUESTS / LOCK rows, goal card, quest tracker,
-- deal badge / phone status) and the bottom button row. Only
-- what is shown right now.
type ScreenRect = { Position: Vector2, Size: Vector2 }

local function isShown(gui: GuiObject): boolean
	local current: Instance? = gui
	while current and current ~= screenGui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current == screenGui and screenGui.Enabled
end

function HudController.GetObstacleRects(): { [string]: ScreenRect }
	local inset = GuiService:GetGuiInset().Y
	local parts: { [string]: GuiObject } = {
		CashCard = cashHolder,
		ShopRow = shopRow,
		QuestRow = questRow,
		LockRow = lockRow,
		PhoneGrid = phoneGrid,
		Goal = goalHolder,
		QuestTracker = questTracker,
		DealBadge = dealHolder,
		PhoneStatus = phoneStatus,
		BottomRow = buttonRow,
	}
	local rects: { [string]: ScreenRect } = {}
	for name, gui in parts do
		if isShown(gui) and gui.AbsoluteSize.X > 0 and gui.AbsoluteSize.Y > 0 then
			rects[name] = { Position = gui.AbsolutePosition + Vector2.new(0, inset), Size = gui.AbsoluteSize }
		end
	end
	return rects
end

-- /selftest: the same rects in logical px (screen space divided by the HUD's
-- UIScale) as they would sit in a `view` (logical px) of another size: the
-- left column is pinned to the top-left, the bottom row is centred on the
-- bottom edge. The caller has forced the layout (phone / desktop) first.
function HudController.GetObstacleRectsFor(view: Vector2): { [string]: ScreenRect }
	local rects: { [string]: ScreenRect } = {}
	local scale = UIKit.EffectiveScale(screenGui)
	for name, rect in HudController.GetObstacleRects() do
		local position = rect.Position / scale
		local size = rect.Size / scale
		if name == "BottomRow" then
			position = Vector2.new((view.X - size.X) / 2, view.Y - (BOTTOM_MARGIN + UITheme.ShadowOffset) - size.Y)
		end
		rects[name] = { Position = position, Size = size }
	end
	return rects
end

-- /selftest "deal tile": the art (picture or emoji fallback) is drawn, the
-- ribbon and the timer show the numbers they were given, the tile overlaps
-- no other HUD rect (left column, bottom row, weapon bar), and it is hidden for a
-- restricted player, in the tutorial and while carrying. The caller forces
-- the layout (phone / desktop) first.
function HudController.SelfTestDealTile(scaleName: string): { string }
	selfTestHold = true
	local save, seconds = 23, 4 * 3600 + 8 * 60 + 48
	dealShown = true
	dealHolder.Visible = true
	applyDealView({ Icon = "🔥" }, "SelfTest", nil, save, seconds, { "Boost", "LuckPotion" })
	-- "next in" shares the column, as in the left-column check.
	UIKit.SetPillVisible(giftsNextPill, true)
	applyLayout(layoutIsPhone)
	task.wait(0.3)

	local lines: { string } = {}
	local art: GuiObject = if dealImage.Visible then dealImage else dealGlyph
	local wantRibbon, wantTimer = ("−%d%%"):format(save), "🔥 " .. EventState.FormatTimer(seconds)
	local drawn = isShown(art) and art.AbsoluteSize.X > 0 and art.AbsoluteSize.Y > 0
	if drawn and dealRibbonText.Text == wantRibbon and dealTimer.Text == wantTimer then
		table.insert(lines, ("PASS deal tile (%s): art drawn %dx%d, ribbon %s, timer %s"):format(
			scaleName, art.AbsoluteSize.X, art.AbsoluteSize.Y, dealRibbonText.Text, dealTimer.Text))
	else
		table.insert(lines, ("FAIL deal tile (%s): art drawn %s (%s), ribbon '%s' (want '%s'), timer '%s' (want '%s')"):format(
			scaleName, tostring(drawn), tostring(art.AbsoluteSize), dealRibbonText.Text, wantRibbon, dealTimer.Text, wantTimer))
	end

	local rects = HudController.GetObstacleRects()
	local weaponBar = (require(script.Parent.CombatController) :: any).GetBarRect()
	if weaponBar then
		rects.WeaponBar = weaponBar
	end
	local mine = rects.DealBadge
	local overlaps: { string } = {}
	local compared = 0
	if not mine then
		table.insert(overlaps, "tile not on screen")
	else
		for name, rect in rects do
			-- On a phone the tile lives inside the status stack.
			if name ~= "DealBadge" and name ~= "PhoneStatus" then
				compared += 1
				local overlapX = math.min(mine.Position.X + mine.Size.X, rect.Position.X + rect.Size.X) - math.max(mine.Position.X, rect.Position.X)
				local overlapY = math.min(mine.Position.Y + mine.Size.Y, rect.Position.Y + rect.Size.Y) - math.max(mine.Position.Y, rect.Position.Y)
				if overlapX > 1 and overlapY > 1 then
					table.insert(overlaps, name)
				end
			end
		end
	end
	table.sort(overlaps)
	table.insert(lines, if #overlaps == 0
		then ("PASS deal tile no overlap (%s, vs %d HUD rects)"):format(scaleName, compared)
		else ("FAIL deal tile overlap (%s): %s"):format(scaleName, table.concat(overlaps, ", ")))

	-- Hidden: the gates the real refresh uses (a live deal, no tutorial, not
	-- quiet), and a restricted player is never offered a deal product.
	local key = DealState.GetCurrent()
	local restrictedOffered = ShopConfig.IsOffered(key, true, false, false)
	local hidden = not dealTileShouldShow(nil, false, false)
		and not dealTileShouldShow({}, true, false)
		and not dealTileShouldShow({}, false, true)
		and dealTileShouldShow({}, false, false)
		and not restrictedOffered
	table.insert(lines, if hidden
		then ("PASS deal tile hidden for restricted, tutorial and carrying (%s)"):format(scaleName)
		else ("FAIL deal tile hidden gates (%s): restrictedOffered %s"):format(scaleName, tostring(restrictedOffered)))

	dealArtKey = ""
	selfTestHold = false
	refreshShopRow()
	return lines
end

-- /selftest "phone HUD coverage": the busiest phone HUD (every card up: SHOP,
-- GIFTS, QUESTS, three power-ups, LOCK and its "?", the deal tile, "next
-- in", the goal card and the quest tracker) is built, `measure` runs on it,
-- and the real state comes back. The caller forces the phone layout first.
function HudController.SelfTestBusy(measure: () -> any): any
	selfTestHold = true
	dealShown = true
	dealHolder.Visible = true
	applyDealView({ Icon = "🔥" }, "SelfTest", nil, 23, 5 * 3600 + 59 * 60 + 59, { "Boost", "LuckPotion" })
	UIKit.SetPillVisible(giftsNextPill, true)
	giftsNextPill.Text = "next in 59:59"
	local goalWas, trackerWas = goalHolder.Visible, questTracker.Visible
	goalHolder.Visible = true
	questTracker.Visible = not layoutIsPhone -- hidden on a phone
	lockHolder.Visible = true
	helpHolder.Visible = true
	shopHolder.Visible = true
	-- A few power-ups (three of the five), as in a real session.
	for order, key in QuestConfig.PowerUpOrder do
		powerButtons[key].Holder.Visible = order <= 3
	end
	phoneGrid.Visible = true
	applyLayout(layoutIsPhone)
	task.wait(0.4)
	placeColumn()
	task.wait(0.2)
	local ok, result = pcall(measure)
	goalHolder.Visible = goalWas
	questTracker.Visible = trackerWas
	selfTestHold = false
	applyLayout(layoutIsPhone)
	refreshShopRow()
	refreshQuestRow()
	refreshLockChip()
	if not ok then
		error(result)
	end
	return result
end

export type CardView = { Name: string, Size: Vector2, GlyphSize: number, WordSize: number?, WordText: string }

-- /selftest: every icon card on screen right now (the grid cards, the LOCK
-- card and the bottom row): its size in screen px and its text sizes.
function HudController.GetCardViews(): { CardView }
	local views: { CardView } = {}
	local function add(name: string, holder: GuiObject, button: TextButton)
		if not isShown(holder) then
			return
		end
		local content = button:FindFirstChild("Content")
		local column = content and content:FindFirstChild("TextColumn")
		local label = column and column:FindFirstChild("Label") :: TextLabel?
		local sub = column and column:FindFirstChild("SubLabel") :: TextLabel?
		if not label then
			return
		end
		table.insert(views, {
			Name = name,
			Size = holder.AbsoluteSize,
			GlyphSize = label.TextSize,
			WordSize = if sub and sub.Visible then sub.TextSize else nil,
			WordText = if sub and sub.Visible then sub.Text else "",
		})
	end
	for _, card in cards do
		add(card.Button.Parent and card.Button.Parent.Name or "Card", card.Holder, card.Button)
	end
	add("LockChip", lockHolder, lockChip)
	for name, button in buttonsByName do
		local holder = button.Parent
		if holder and holder:IsA("GuiObject") then
			add(name, holder, button)
		end
	end
	return views
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

local function refreshGoalPathButton()
	local button = goalPathButton
	if button then
		local on = TycoonController.IsGoalPathOn()
		UIKit.SetButton(button, { Style = if on then "Green" else "Disabled", TextColor3 = if on then Colors.Text else Colors.Muted })
	end
end

local function refreshAll()
	refreshGoalPathButton()
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
	refreshRebirthButton()
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

-- What the tutorial's hand points at: a bottom-bar button (Upgrades, Items,
-- Index, Rebirth, Settings), "Gifts", "Quests", or "Income" (the $/s line).
function HudController.GetCoachTarget(name: string): GuiObject?
	if name == "Gifts" then
		return giftsButton
	elseif name == "Income" then
		return incomeLabel
	elseif name == "Quests" then
		return questsButton
	end
	return buttonsByName[name]
end

-- The progressive HUD (UI/HudGate): a new player's HUD is the cash card and
-- the tutorial banner; everything else is registered under its key and pops
-- in when the step that introduces it begins (TutorialConfig.HudReveal).
local function registerGate()
	local function button(name: string): () -> { GuiObject }
		return function()
			local body = buttonsByName[name]
			local holder = body and body.Parent
			return if holder and holder:IsA("GuiObject") then { holder } else {}
		end
	end
	for key, name in { Upgrades = "Upgrades", Items = "Items", Index = "Index", Rebirth = "Rebirth", Settings = "Settings" } do
		HudGate.Register(key, { Roots = button(name) })
	end
	-- SHOP, GIFTS, QUESTS, the deal badge, the power-ups and every pill
	-- that hangs off them (on a phone they live in the status stack).
	HudGate.Register("Shop", {
		Roots = function()
			-- A phone's SHOP / GIFTS / QUESTS cards live in the grid.
			return if layoutIsPhone then { phoneGrid } else { shopRow, questRow }
		end,
		AlsoHide = function()
			return { dealHolder, phoneStatus, UIKit.PillRoot(giftsNextPill) }
		end,
		ForceShow = false,
		NewSide = "Right",
		OnShow = function()
			shopRow.Visible = true
			questRow.Visible = true
			phoneGrid.Visible = true
			applyLayout(layoutIsPhone)
			dealHolder.Visible = dealShown
			refreshShopRow()
		end,
	})
	-- NEXT GOAL and the quest tracker: when the tutorial ends.
	HudGate.Register("Goal", {
		Roots = function()
			return { goalHolder }
		end,
		AlsoHide = function()
			return { questTracker }
		end,
		ForceShow = false,
		NewSide = "Right",
		OnShow = function()
			refreshGoal()
			refreshQuestRow()
			placeQuestTracker()
		end,
	})
end

function HudController.Init()
	screenGui = UIKit.Screen("Hud", 40)

	buildGoalTracker()
	cashHolder = buildCashCard()
	PurchaseCelebration.SetHud({
		GetCashTarget = HudController.GetCashTarget,
		HoldCash = HudController.HoldCash,
		BounceCash = HudController.BounceCash,
		GetEffectTarget = HudController.GetEffectTarget,
		PopEffect = HudController.PopEffect,
		CountUpIncome = HudController.CountUpIncome,
		GetIncomePerSecond = HudController.GetIncomePerSecond,
		GetCash = TycoonController.GetCash,
	})
	buildButtonRow()
	buildLockChip()
	buildShopRow()
	buildQuestRow()
	buildDealBadge()
	buildPhoneGrid()
	UpgradesPanel.Init(screenGui)
	RebirthPanel.Init()
	IndexPanel.Init()
	ShopPanel.Init()
	GiftsPanel.Init()
	QuestsPanel.Init()
	SettingsPanel.Init()
	FusePanel.Init()
	HowToHeistPanel.Init()

	applyLayout(UIKit.IsPhone())
	EffectsTray.Init({
		GetObstacles = function()
			-- The HUD's rects plus the weapon bar (CombatController requires nothing of ours at load).
			local rects = HudController.GetObstacleRects()
			local weaponBar = (require(script.Parent.CombatController) :: any).GetBarRect()
			if weaponBar then
				rects.WeaponBar = weaponBar
			end
			return rects
		end,
		GetBottomRowRect = HudController.GetBottomRowRect,
		GetDisplayOrder = function()
			return screenGui.DisplayOrder
		end,
	})
	registerGate()
	UIKit.LayoutChanged:Connect(applyLayout)
	phoneStatusLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if layoutIsPhone then
			placeColumn()
		end
	end)
	-- A card came or went (a power-up, LOCK): the grid grows or shrinks.
	phoneGridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if layoutIsPhone then
			placeColumn()
		end
	end)
	-- Desktop: the cash card follows the goal card and the quest tracker; phone:
	-- the grid follows the goal pill.
	for _, signalSource in { goalHolder, questTracker } do
		signalSource:GetPropertyChangedSignal("Visible"):Connect(placeColumn)
	end
	-- Desktop: the cash card follows the goal card; phone: the grid follows the pill.
	goalHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeColumn)

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
