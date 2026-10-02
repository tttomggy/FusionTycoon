--[[
	HudController
	-------------
	The always-on HUD:
	  * Cash readout (bottom-left) that counts up smoothly, with income/sec
	    under it. Before this the only place to see your cash was the
	    leaderboard, and there was no way to see your income at all.
	  * An UPGRADES button next to the Inventory button that opens the
	    Generators panel. The five generators existed on the server the whole
	    time, but nothing in the game let a player buy them.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local TycoonController = require(script.Parent.TycoonController)
local InventoryController = require(script.Parent.InventoryController)

local HudController = {}

local COLORS = {
	Panel = Color3.fromRGB(18, 18, 26),
	PanelLight = Color3.fromRGB(30, 30, 42),
	Stroke = Color3.fromRGB(70, 70, 95),
	Text = Color3.fromRGB(245, 245, 250),
	Muted = Color3.fromRGB(150, 150, 170),
	Cash = Color3.fromRGB(85, 255, 127),
	Buy = Color3.fromRGB(46, 204, 113),
	BuyDisabled = Color3.fromRGB(60, 60, 72),
}

local localPlayer = Players.LocalPlayer

local screenGui: ScreenGui
local cashLabel: TextLabel
local incomeLabel: TextLabel
local upgradesPanel: Frame
local generatorRows: { [string]: { [string]: any } } = {}
local multiplierLabel: TextLabel

local displayedCash = 0

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function textLabel(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = COLORS.Text
	label.TextScaled = true
	for key, value in props do
		(label :: any)[key] = value
	end
	return label
end

--[[ Income ---------------------------------------------------------------- ]]

local function isPlotClaimed(): boolean
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	local plot = folder and folder:FindFirstChild(PlotNaming.GetPlotName(localPlayer.UserId))
	return plot ~= nil and plot:GetAttribute("Claimed") == true
end

local function getDisplayedTiers(): { string }
	local byUid: { [string]: any } = {}
	for _, item in InventoryController.GetInventory() do
		byUid[item.Uid] = item
	end
	local tiers = {}
	for _, uid in TycoonController.GetPedestalDisplays() do
		local item = byUid[uid]
		if item then
			table.insert(tiers, item.Tier)
		end
	end
	return tiers
end

local function getIncomePerSecond(): number
	local multiplierLevel = TycoonController.GetCashMultiplierLevel()
	local passive = TycoonConfig.GetPassiveCashPerSecond(
		TycoonController.GetGeneratorLevels(),
		getDisplayedTiers(),
		multiplierLevel
	)
	if isPlotClaimed() then
		local droppers = if TycoonController.HasDropper2() then 2 else 1
		passive += TycoonConfig.GetDropperCashPerSecond(droppers, multiplierLevel)
	end
	return passive
end

--[[ Cash card ------------------------------------------------------------- ]]

local function buildCashCard()
	local card = Instance.new("Frame")
	card.Name = "CashCard"
	-- Left edge, a bit above centre: clear of the Roblox top bar, the mobile
	-- thumbstick (bottom-left) and the bottom-centre buttons.
	card.AnchorPoint = Vector2.new(0, 0.5)
	card.Position = UDim2.new(0, 12, 0.42, 0)
	card.Size = UDim2.fromOffset(200, 70)
	card.BackgroundColor3 = COLORS.Panel
	card.BackgroundTransparency = 0.1
	card.Parent = screenGui
	corner(card, 14)
	stroke(card, COLORS.Stroke, 1.5)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = card

	cashLabel = textLabel({
		Name = "Cash",
		Size = UDim2.new(1, 0, 0.62, 0),
		Font = Enum.Font.GothamBlack,
		TextColor3 = COLORS.Cash,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "$0",
		Parent = card,
	})

	incomeLabel = textLabel({
		Name = "Income",
		Position = UDim2.fromScale(0, 0.64),
		Size = UDim2.new(1, 0, 0.36, 0),
		Font = Enum.Font.GothamMedium,
		TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "+$0/s",
		Parent = card,
	})
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
	cashLabel.Text = NumberFormat.Money(math.floor(displayedCash))
end

--[[ Upgrades panel -------------------------------------------------------- ]]

local function refreshUpgrades()
	if not upgradesPanel then
		return
	end
	local cash = TycoonController.GetCash()
	local levels = TycoonController.GetGeneratorLevels()
	local multiplierLevel = TycoonController.GetCashMultiplierLevel()
	local multiplier = TycoonConfig.GetCashMultiplierValue(multiplierLevel)

	multiplierLabel.Text = ("All income %s  ·  upgrade at the purple pad"):format(NumberFormat.Multiplier(multiplier))

	for _, generator in TycoonConfig.Generators do
		local row = generatorRows[generator.Id]
		if row then
			local level = levels[generator.Id] or 0
			local unlocked = TycoonConfig.IsUnlocked(generator, levels)
			local maxed = level >= generator.MaxLevel
			local perLevel = TycoonConfig.GetGeneratorCashPerSecond(generator, 1) * multiplier

			row.Level.Text = ("Lv %d/%d"):format(level, generator.MaxLevel)
			row.Detail.Text = if level > 0
				then ("%s/s now  ·  +%s/s per level"):format(
					NumberFormat.Money(TycoonConfig.GetGeneratorCashPerSecond(generator, level) * multiplier),
					NumberFormat.Money(perLevel)
				)
				else ("+%s/s per level"):format(NumberFormat.Money(perLevel))

			local button: TextButton = row.Button
			if maxed then
				button.Text = "MAX"
				button.BackgroundColor3 = COLORS.BuyDisabled
				button.AutoButtonColor = false
			elseif not unlocked then
				local requirement = generator.UnlockRequirement :: { GeneratorId: string, Level: number }
				local required = TycoonConfig.GetGeneratorById(requirement.GeneratorId)
				button.Text = ("🔒 %s Lv %d"):format(required and required.Name or "?", requirement.Level)
				button.BackgroundColor3 = COLORS.BuyDisabled
				button.AutoButtonColor = false
			else
				local cost = TycoonConfig.GetUpgradeCost(generator, level)
				local affordable = cash >= cost
				button.Text = (if level == 0 then "Buy " else "Upgrade ") .. NumberFormat.Money(cost)
				button.BackgroundColor3 = if affordable then COLORS.Buy else COLORS.BuyDisabled
				button.AutoButtonColor = affordable
			end
		end
	end
end

local function buildGeneratorRow(parent: Instance, generator: TycoonConfig.GeneratorDef, order: number)
	local row = Instance.new("Frame")
	row.Name = generator.Id
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 64)
	row.BackgroundColor3 = COLORS.PanelLight
	row.Parent = parent
	corner(row, 10)

	local tierColor = FusionConfig.TierAccentColors[generator.Tier] or COLORS.Text
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 5, 1, -16)
	stripe.Position = UDim2.fromOffset(8, 8)
	stripe.BackgroundColor3 = tierColor
	stripe.BorderSizePixel = 0
	stripe.Parent = row
	corner(stripe, 3)

	textLabel({
		Name = "Name",
		Position = UDim2.fromOffset(22, 8),
		Size = UDim2.new(0.58, -22, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = generator.Name,
		Parent = row,
	})

	local level = textLabel({
		Name = "Level",
		Position = UDim2.new(0.58, -70, 0, 10),
		Size = UDim2.fromOffset(64, 18),
		Font = Enum.Font.GothamMedium,
		TextColor3 = tierColor,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local detail = textLabel({
		Name = "Detail",
		Position = UDim2.fromOffset(22, 34),
		Size = UDim2.new(0.58, -22, 0, 18),
		Font = Enum.Font.GothamMedium,
		TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local button = Instance.new("TextButton")
	button.Name = "Buy"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.new(0.4, -10, 0, 40)
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = COLORS.Text
	button.BackgroundColor3 = COLORS.BuyDisabled
	button.Parent = row
	corner(button, 8)
	local buttonPadding = Instance.new("UIPadding")
	buttonPadding.PaddingLeft = UDim.new(0, 8)
	buttonPadding.PaddingRight = UDim.new(0, 8)
	buttonPadding.PaddingTop = UDim.new(0, 8)
	buttonPadding.PaddingBottom = UDim.new(0, 8)
	buttonPadding.Parent = button

	button.MouseButton1Click:Connect(function()
		local levels = TycoonController.GetGeneratorLevels()
		local current = levels[generator.Id] or 0
		if current >= generator.MaxLevel or not TycoonConfig.IsUnlocked(generator, levels) then
			return
		end
		if TycoonController.GetCash() < TycoonConfig.GetUpgradeCost(generator, current) then
			return
		end
		if TycoonController.RequestUpgrade(generator.Id) then
			-- Tiny press bounce so the click feels like it registered.
			local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			scale.Parent = button
			scale.Scale = 0.92
			TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end)

	generatorRows[generator.Id] = { Level = level, Detail = detail, Button = button }
end

local function buildUpgradesPanel()
	upgradesPanel = Instance.new("Frame")
	upgradesPanel.Name = "UpgradesPanel"
	upgradesPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	upgradesPanel.Position = UDim2.fromScale(0.5, 0.5)
	upgradesPanel.Size = UDim2.new(0.92, 0, 0, 470)
	upgradesPanel.BackgroundColor3 = COLORS.Panel
	upgradesPanel.Visible = false
	upgradesPanel.Parent = screenGui
	corner(upgradesPanel, 16)
	stroke(upgradesPanel, COLORS.Stroke, 2)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(480, 470)
	sizeConstraint.Parent = upgradesPanel

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.Parent = upgradesPanel

	textLabel({
		Name = "Title",
		Size = UDim2.new(1, -44, 0, 30),
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "GENERATORS",
		Parent = upgradesPanel,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(32, 32)
	close.Text = "✕"
	close.Font = Enum.Font.GothamBold
	close.TextScaled = true
	close.TextColor3 = COLORS.Text
	close.BackgroundColor3 = COLORS.PanelLight
	close.Parent = upgradesPanel
	corner(close, 8)
	close.MouseButton1Click:Connect(function()
		upgradesPanel.Visible = false
	end)

	multiplierLabel = textLabel({
		Name = "Multiplier",
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 18),
		Font = Enum.Font.GothamMedium,
		TextColor3 = Color3.fromRGB(200, 60, 255),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = upgradesPanel,
	})

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(0, 62)
	list.Size = UDim2.new(1, 0, 1, -62)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = upgradesPanel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for index, generator in TycoonConfig.Generators do
		buildGeneratorRow(list, generator, index)
	end
end

local function buildUpgradesButton()
	-- Sits just left of the bottom-centre Inventory button (56px wide).
	local button = Instance.new("TextButton")
	button.Name = "UpgradesButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(0.5, -36, 1, -24)
	button.Size = UDim2.fromOffset(132, 56)
	button.BackgroundColor3 = COLORS.Buy
	button.Font = Enum.Font.GothamBlack
	button.TextScaled = true
	button.TextColor3 = COLORS.Text
	button.Text = "UPGRADES"
	button.Parent = screenGui
	corner(button, 16)
	stroke(button, Color3.fromRGB(20, 120, 60), 2)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.Parent = button

	-- Gentle pulse while something is affordable, so new players notice it.
	local scale = Instance.new("UIScale")
	scale.Parent = button
	task.spawn(function()
		while button.Parent do
			local affordable = false
			local levels = TycoonController.GetGeneratorLevels()
			for _, generator in TycoonConfig.Generators do
				local level = levels[generator.Id] or 0
				if level < generator.MaxLevel
					and TycoonConfig.IsUnlocked(generator, levels)
					and TycoonController.GetCash() >= TycoonConfig.GetUpgradeCost(generator, level)
				then
					affordable = true
					break
				end
			end
			if affordable and not upgradesPanel.Visible then
				TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { Scale = 1.08 }):Play()
				task.wait(0.35)
				TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
				task.wait(0.6)
			else
				scale.Scale = 1
				task.wait(0.5)
			end
		end
	end)

	button.MouseButton1Click:Connect(function()
		upgradesPanel.Visible = not upgradesPanel.Visible
		if upgradesPanel.Visible then
			refreshUpgrades()
		end
	end)
end

--[[ Init ------------------------------------------------------------------ ]]

function HudController.Init()
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "Hud"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 40
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	buildCashCard()
	buildUpgradesPanel()
	buildUpgradesButton()

	RunService.RenderStepped:Connect(onRenderStep)

	local function refreshAll()
		incomeLabel.Text = ("+%s/s"):format(NumberFormat.Money(getIncomePerSecond()))
		if upgradesPanel.Visible then
			refreshUpgrades()
		end
	end
	TycoonController.TycoonChanged:Connect(refreshAll)
	InventoryController.InventoryChanged:Connect(refreshAll)
	refreshAll()
end

return HudController
