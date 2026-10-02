--[[
	UpgradesPanel
	-------------
	The UPGRADES modal: one row per generator with its rate, level, and a buy
	button that reflects whether you can afford it, have maxed it, or haven't
	unlocked it yet. All numbers shown are post-multiplier.

	Purchasing is unchanged: TycoonController.RequestUpgrade, server-validated
	by TycoonService. The client-side checks here only decide what to show.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local Controllers = script.Parent.Parent.Controllers
local TycoonController = require(Controllers.TycoonController)
local ToastController = require(Controllers.ToastController)
local UIKit = require(script.Parent.UIKit)

local UpgradesPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(520, 620)
local ROW_HEIGHT = 84
local ROW_GAP = 10
local FOOTER_HEIGHT = 56
local BUTTON_SIZE = Vector2.new(132, 52)
local LOCKED_OPACITY = 0.92
local FAR_LOCKED_OPACITY = 0.7

type Row = {
	Holder: Frame,
	Body: Frame,
	Bar: Frame,
	Icon: Frame,
	LockWell: Frame,
	Name: TextLabel,
	LevelPill: TextLabel,
	Detail: TextLabel,
	Progress: Frame,
	Button: TextButton,
	Opacity: number?,
}

local modal: UIKit.Modal
local cashLabel: TextLabel
local footerPill: TextLabel
local rows: { [string]: Row } = {}

local function tierColor(tier: string): Color3
	return FusionConfig.TierAccentColors[tier] or Colors.Text
end

local function getMultiplier(): number
	return TycoonConfig.GetCashMultiplierValue(TycoonController.GetCashMultiplierLevel())
end

-- "unlocked" | "locked" (next in the chain) | "far" (two or more steps away)
local function getLockState(generator: TycoonConfig.GeneratorDef, levels: { [string]: number }): string
	if TycoonConfig.IsUnlocked(generator, levels) then
		return "unlocked"
	end
	local requirement = generator.UnlockRequirement :: { GeneratorId: string, Level: number }
	local required = TycoonConfig.GetGeneratorById(requirement.GeneratorId)
	if required and not TycoonConfig.IsUnlocked(required, levels) then
		return "far"
	end
	return "locked"
end

--[[ Refresh ------------------------------------------------------------------ ]]

local function setRowOpacity(row: Row, opacity: number)
	if row.Opacity ~= opacity then
		row.Opacity = opacity
		UIKit.SetOpacity(row.Holder, opacity)
	end
end

local function refreshRow(generator: TycoonConfig.GeneratorDef, cash: number, levels: { [string]: number }, multiplier: number)
	local row = rows[generator.Id]
	if not row then
		return
	end
	local level = levels[generator.Id] or 0
	local lockState = getLockState(generator, levels)
	local maxed = level >= generator.MaxLevel

	row.Progress.Visible = lockState == "locked"
	row.Icon.Visible = lockState == "unlocked"
	row.LockWell.Visible = lockState ~= "unlocked"
	row.LevelPill.Visible = lockState == "unlocked"

	if lockState == "unlocked" then
		row.Name.Text = generator.Name
		row.LevelPill.Text = if maxed then "MAX" else ("LV %d"):format(level)
		local current = TycoonConfig.GetGeneratorCashPerSecond(generator, level) * multiplier
		local perLevel = TycoonConfig.GetGeneratorCashPerSecond(generator, 1) * multiplier
		row.Detail.Text = if maxed
			then ("%s/s"):format(NumberFormat.Money(current))
			else ("%s/s · %s next"):format(
				NumberFormat.Money(current),
				UIKit.Colored("+" .. NumberFormat.Money(perLevel) .. "/s", Colors.Cash)
			)

		if maxed then
			UIKit.SetButton(row.Button, { Style = "Disabled", Text = "MAXED", SubText = "", TextColor3 = Colors.Muted })
		else
			local cost = TycoonConfig.GetUpgradeCost(generator, level)
			local affordable = cash >= cost
			UIKit.SetButton(row.Button, {
				Style = if affordable then "Green" else "Disabled",
				Text = NumberFormat.Money(cost),
				SubText = if level == 0 then "BUY" else "UPGRADE",
				TextColor3 = if affordable then Colors.Text else Colors.Muted,
			})
		end
		setRowOpacity(row, 1)
		return
	end

	local requirement = generator.UnlockRequirement :: { GeneratorId: string, Level: number }
	local required = TycoonConfig.GetGeneratorById(requirement.GeneratorId)
	local requiredName = if required then required.Name else "?"
	UIKit.SetButton(row.Button, { Style = "Disabled", Text = "LOCKED", SubText = "", TextColor3 = Colors.Muted })

	if lockState == "locked" then
		row.Name.Text = generator.Name
		row.Detail.Text = ("Unlocks at %s"):format(
			UIKit.Colored(("%s LV %d"):format(UIKit.EscapeRichText(requiredName), requirement.Level), Colors.Text)
		)
		local requiredLevel = levels[requirement.GeneratorId] or 0
		UIKit.SetProgress(row.Progress, requiredLevel / requirement.Level)
		local fill = row.Progress:FindFirstChild("Fill") :: Frame?
		if fill and required then
			fill.BackgroundColor3 = tierColor(required.Tier)
		end
		setRowOpacity(row, LOCKED_OPACITY)
	else
		row.Name.Text = "???"
		row.Detail.Text = ("Unlock %s first"):format(UIKit.EscapeRichText(requiredName))
		setRowOpacity(row, FAR_LOCKED_OPACITY)
	end
end

local function refresh()
	if not modal then
		return
	end
	local cash = TycoonController.GetCash()
	local levels = TycoonController.GetGeneratorLevels()
	local multiplier = getMultiplier()

	cashLabel.Text = NumberFormat.Money(cash)
	footerPill.Text = NumberFormat.Multiplier(multiplier)
	for _, generator in TycoonConfig.Generators do
		refreshRow(generator, cash, levels, multiplier)
	end
end

--[[ Build -------------------------------------------------------------------- ]]

local function onBuyClicked(generator: TycoonConfig.GeneratorDef, row: Row)
	local levels = TycoonController.GetGeneratorLevels()
	local current = levels[generator.Id] or 0
	if current >= generator.MaxLevel or not TycoonConfig.IsUnlocked(generator, levels) then
		return
	end
	local cost = TycoonConfig.GetUpgradeCost(generator, current)
	if TycoonController.GetCash() < cost then
		ToastController.Show(("Need %s"):format(NumberFormat.Money(cost)), "Error")
		return
	end
	if TycoonController.RequestUpgrade(generator.Id) then
		-- Tiny bounce so the purchase feels like it registered.
		local holder = row.Button.Parent :: Frame
		local scale = holder:FindFirstChild("BuyBounce") :: UIScale?
		if not scale then
			local newScale = Instance.new("UIScale")
			newScale.Name = "BuyBounce"
			newScale.Parent = holder
			scale = newScale
		end
		local bounce = scale :: UIScale
		bounce.Scale = 0.92
		TweenService:Create(bounce, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end

local function buildRow(parent: Instance, generator: TycoonConfig.GeneratorDef, order: number)
	local body, holder = UIKit.Panel({
		Name = generator.Id,
		Parent = parent,
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT),
		Color = Colors.Panel2,
		Radius = UITheme.Radius.Row,
		LayoutOrder = order,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = 3,
	})
	local z = body.ZIndex + 1

	local bar = Instance.new("Frame")
	bar.Name = "TierBar"
	bar.BackgroundColor3 = tierColor(generator.Tier)
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(10, 12)
	bar.Size = UDim2.new(0, 10, 1, -24)
	bar.ZIndex = z
	bar.Parent = body
	UIKit.Corner(bar, 5)

	local icon = UIKit.TierSquare(generator.Tier, 52)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 30, 0.5, 0)
	icon.ZIndex = z
	icon.Parent = body

	local lockWell = Instance.new("Frame")
	lockWell.Name = "LockWell"
	lockWell.AnchorPoint = Vector2.new(0, 0.5)
	lockWell.Position = UDim2.new(0, 30, 0.5, 0)
	lockWell.Size = UDim2.fromOffset(52, 52)
	lockWell.BackgroundColor3 = Colors.Panel3
	lockWell.ZIndex = z
	lockWell.Visible = false
	lockWell.Parent = body
	UIKit.Corner(lockWell, 14)
	UIKit.Stroke(lockWell, 3)
	if UITheme.Icons.Lock ~= "" then
		local lockImage = Instance.new("ImageLabel")
		lockImage.BackgroundTransparency = 1
		lockImage.AnchorPoint = Vector2.new(0.5, 0.5)
		lockImage.Position = UDim2.fromScale(0.5, 0.5)
		lockImage.Size = UDim2.fromOffset(28, 28)
		lockImage.Image = UITheme.Icons.Lock
		lockImage.ZIndex = z + 1
		lockImage.Parent = lockWell
	else
		UIKit.Label({
			Text = "🔒",
			TextSize = 24,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 1,
			Parent = lockWell,
		})
	end

	-- Name + level pill on one line.
	local titleRow = Instance.new("Frame")
	titleRow.Name = "TitleRow"
	titleRow.BackgroundTransparency = 1
	titleRow.Position = UDim2.fromOffset(94, 12)
	titleRow.Size = UDim2.new(1, -(94 + BUTTON_SIZE.X + 20), 0, 26)
	titleRow.ZIndex = z
	titleRow.Parent = body
	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.SortOrder = Enum.SortOrder.LayoutOrder
	titleLayout.Padding = UDim.new(0, 8)
	titleLayout.Parent = titleRow

	local nameLabel = UIKit.Label({
		Name = "GeneratorName",
		Text = generator.Name,
		Font = Fonts.Display,
		TextSize = 20,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		LayoutOrder = 1,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = titleRow,
	})
	local levelPill = UIKit.Pill({
		Name = "Level",
		Parent = titleRow,
		Text = "LV 0",
		Color = tierColor(generator.Tier),
		TextColor3 = Colors.Ink,
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		Height = 20,
		LayoutOrder = 2,
		ZIndex = z,
	})

	local detail = UIKit.Label({
		Name = "Detail",
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Muted,
		RichText = true,
		Position = UDim2.fromOffset(94, 40),
		Size = UDim2.new(1, -(94 + BUTTON_SIZE.X + 20), 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = z,
		Parent = body,
	})

	local progress = UIKit.ProgressBar({
		Name = "UnlockProgress",
		Parent = body,
		Position = UDim2.fromOffset(94, 62),
		Size = UDim2.fromOffset(180, 10),
		ZIndex = z,
	})
	progress.Visible = false

	local button: TextButton
	local row: Row
	button = UIKit.Button({
		Name = "Buy",
		Parent = body,
		Style = "Green",
		Text = "",
		SubText = "UPGRADE",
		TextSize = 17,
		Size = UDim2.fromOffset(BUTTON_SIZE.X, BUTTON_SIZE.Y),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, -2),
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z,
		OnClick = function()
			onBuyClicked(generator, row)
		end,
	})

	row = {
		Holder = holder,
		Body = body,
		Bar = bar,
		Icon = icon,
		LockWell = lockWell,
		Name = nameLabel,
		LevelPill = levelPill,
		Detail = detail,
		Progress = progress,
		Button = button,
	}
	rows[generator.Id] = row
end

local function buildTabs(parent: Instance)
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, 34)
	tabs.ZIndex = 5
	tabs.Parent = parent

	local pills = Instance.new("Frame")
	pills.BackgroundTransparency = 1
	pills.Size = UDim2.new(1, -150, 1, 0)
	pills.ZIndex = 5
	pills.Parent = tabs
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = pills

	UIKit.Pill({
		Name = "Generators",
		Parent = pills,
		Text = "Generators",
		Color = Colors.White,
		TextColor3 = Colors.Ink,
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		Height = 30,
		StrokeThickness = 3,
		LayoutOrder = 1,
		ZIndex = 5,
	})
	-- Not clickable: a plain label, no button.
	UIKit.Pill({
		Name = "Boosts",
		Parent = pills,
		Text = "Boosts · soon",
		Color = Colors.Panel2,
		TextColor3 = Colors.Muted,
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		Height = 30,
		StrokeThickness = 3,
		LayoutOrder = 2,
		ZIndex = 5,
	})

	cashLabel = UIKit.Label({
		Name = "Cash",
		Font = Fonts.Display,
		TextSize = 22,
		TextColor3 = Colors.Cash,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 150, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 5,
		Stroke = UITheme.Stroke.Text,
		Parent = tabs,
	})
end

local function buildFooter(parent: Instance)
	local body = UIKit.Panel({
		Name = "Footer",
		Parent = parent,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -UITheme.SmallShadowOffset),
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
		Color = Colors.Panel2,
		Radius = UITheme.Radius.Row,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = 5,
	})
	UIKit.Padding(body, 0, 14, 0, 14)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = body

	footerPill = UIKit.Pill({
		Name = "Multiplier",
		Parent = body,
		Text = "x1",
		Color = Colors.VioletPill,
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		Height = 24,
		LayoutOrder = 1,
		ZIndex = body.ZIndex + 1,
	})
	UIKit.Label({
		Name = "Hint",
		Text = ("All income multiplier · raise it at the %s in your base"):format(
			UIKit.Colored("purple pad", Colors.VioletLight)
		),
		RichText = true,
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		Size = UDim2.new(1, -70, 1, 0),
		LayoutOrder = 2,
		ZIndex = body.ZIndex + 1,
		Parent = body,
	})
end

local function build()
	modal = UIKit.Modal({
		Name = "UpgradesPanel",
		Title = "UPGRADES",
		DisplayOrder = 140,
		MaxSize = MAX_SIZE,
		HeaderTop = Colors.PanelTop,
	})
	local content = modal.Content

	buildTabs(content)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(0, 46)
	list.Size = UDim2.new(1, 0, 1, -(46 + FOOTER_HEIGHT + UITheme.SmallShadowOffset + 12))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Colors.Faint
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 3
	list.Parent = content
	-- Room for the outer strokes/shadows so the list doesn't clip them.
	UIKit.Padding(list, 3, 4, 8, 3)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for index, generator in TycoonConfig.Generators do
		buildRow(list, generator, index)
	end

	buildFooter(content)
end

--[[ Public -------------------------------------------------------------------- ]]

function UpgradesPanel.IsOpen(): boolean
	return modal ~= nil and modal.IsOpen()
end

function UpgradesPanel.Toggle()
	if modal.IsOpen() then
		modal.Close()
	else
		refresh()
		modal.Open()
	end
end

function UpgradesPanel.Refresh()
	if modal and modal.IsOpen() then
		refresh()
	end
end

-- `_hud` is accepted for compatibility with the HUD's call; the panel has
-- its own ScreenGui now.
function UpgradesPanel.Init(_hud: ScreenGui?)
	build()
	refresh()
end

return UpgradesPanel
