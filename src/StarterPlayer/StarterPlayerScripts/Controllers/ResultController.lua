--[[
	ResultController
	----------------
	What you see after a fusion or a gacha pull:

	  * Big result card (centre) - Epic/Legendary/Mythic fusion successes and
	    Epic+ gacha pulls. Sunburst, tier name, 132 px orb, DISPLAY IT / NICE.
	    Fusion cards wait for FusionController.FusionResolved, i.e. after the
	    machine's reveal animation, so the card never spoils it.
	  * Fail card (bottom) - a failed fusion, 3 s, with an AGAIN button.
	  * Small pull card (bottom) - Common/Rare gacha pulls; each new pull
	    replaces the previous card.

	  * Rebirth card (centre) - "REBIRTH 3!" with "Income x2.5 · Luck +15%"
	    on a successful RebirthResult (RebirthPanel plays the flash).

	Rare fusion successes keep the top banner (AnnouncementController).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local RevealEffects = require(script.Parent.Parent.Effects.RevealEffects)
local FusionController = require(script.Parent.FusionController)
local TycoonController = require(script.Parent.TycoonController)
local ItemController = require(script.Parent.ItemController)
local HudController = require(script.Parent.HudController)
local ToastController = require(script.Parent.ToastController)

local ResultController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local BIG_CARD_SIZE = Vector2.new(380, 420)
local SUNBURST_RAYS = 12
local SUNBURST_DEGREES_PER_SECOND = 20
local SUNBURST_RAY_LENGTH = 720

local BOTTOM_CARD_OFFSET = 104 -- above the HUD buttons, same baseline as toasts
local FAIL_CARD_SIZE = Vector2.new(470, 92)
local PULL_CARD_SIZE = Vector2.new(440, 74)
local BOTTOM_CARD_SECONDS = 3

local MYTHIC_SHAKE_MAGNITUDE = 0.35
local MYTHIC_SHAKE_SECONDS = 0.5

local screenGui: ScreenGui

--[[ Helpers ------------------------------------------------------------------- ]]

local function itemName(item: any): string
	local def = ItemConfig.GetItemById(item.ItemId)
	return if def then def.Name else tostring(item.ItemId)
end

local function earnRate(tier: string): number
	return TycoonConfig.GetPedestalCashPerSecond(tier) * TycoonController.GetIncomeMultiplier()
end

--[[ Big result card -------------------------------------------------------------- ]]

local bigHolder: Frame? = nil
local sunburstConnection: RBXScriptConnection? = nil

local function closeBigCard()
	if sunburstConnection then
		sunburstConnection:Disconnect()
		sunburstConnection = nil
	end
	local holder = bigHolder
	bigHolder = nil
	if holder then
		local tween = UIKit.PopOut(holder)
		tween.Completed:Once(function()
			holder:Destroy()
		end)
	end
end

local function buildSunburst(body: Frame)
	local burst = Instance.new("CanvasGroup")
	burst.Name = "Sunburst"
	burst.BackgroundTransparency = 1
	burst.Size = UDim2.fromScale(1, 1)
	burst.ZIndex = body.ZIndex + 1
	burst.Parent = body
	UIKit.Corner(burst, 24)

	local spinner: GuiObject
	if UITheme.Icons.Sunburst ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = UITheme.Icons.Sunburst
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.42)
		image.Size = UDim2.fromOffset(SUNBURST_RAY_LENGTH, SUNBURST_RAY_LENGTH)
		image.ImageTransparency = 0.6
		image.ZIndex = burst.ZIndex
		image.Parent = burst
		spinner = image
	else
		local pivot = Instance.new("Frame")
		pivot.Name = "Rays"
		pivot.BackgroundTransparency = 1
		pivot.AnchorPoint = Vector2.new(0.5, 0.5)
		pivot.Position = UDim2.fromScale(0.5, 0.42)
		pivot.Size = UDim2.fromOffset(SUNBURST_RAY_LENGTH, SUNBURST_RAY_LENGTH)
		pivot.ZIndex = burst.ZIndex
		pivot.Parent = burst
		-- 12 thin bars through the centre = 24 rays.
		for index = 1, SUNBURST_RAYS do
			local ray = Instance.new("Frame")
			ray.Name = "Ray"
			ray.BackgroundColor3 = Colors.White
			ray.BackgroundTransparency = 0.9
			ray.BorderSizePixel = 0
			ray.AnchorPoint = Vector2.new(0.5, 0.5)
			ray.Position = UDim2.fromScale(0.5, 0.5)
			ray.Size = UDim2.new(0, 10, 1, 0)
			ray.Rotation = (index - 1) * (180 / SUNBURST_RAYS)
			ray.ZIndex = burst.ZIndex
			ray.Parent = pivot
		end
		spinner = pivot
	end

	-- Rotating the parent rotates every ray around the shared centre.
	sunburstConnection = RunService.RenderStepped:Connect(function(dt: number)
		spinner.Rotation = (spinner.Rotation + SUNBURST_DEGREES_PER_SECOND * dt) % 360
	end)
end

local function onDisplayIt(uid: string)
	closeBigCard()
	if not ItemController.PlaceOnFirstEmpty(uid) then
		HudController.OpenInventory()
		ToastController.Show("Pedestals full · remove one first", "Error")
	end
end

type BigCardInfo = {
	Caption: string,
	Item: any,
	Description: string,
}

local function showBigCard(info: BigCardInfo)
	if bigHolder then
		if sunburstConnection then
			sunburstConnection:Disconnect()
			sunburstConnection = nil
		end
		(bigHolder :: Frame):Destroy()
		bigHolder = nil
	end

	local tier = info.Item.Tier :: string
	local tierColor = FusionConfig.TierAccentColors[tier] or Colors.Text
	local tierLight = UITheme.GetTierLight(tier)

	local body, holder = UIKit.Panel({
		Name = "BigResult",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(BIG_CARD_SIZE.X, BIG_CARD_SIZE.Y),
		Gradient = {
			{ 0, Colors.Panel },
			{ 0.25, Colors.ResultMid },
			{ 0.5, UITheme.TowardInk(tierColor, 0.5) },
			{ 0.75, Colors.ResultMid },
			{ 1, Colors.Panel },
		},
		Radius = 24,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	bigHolder = holder
	buildSunburst(body)
	local z = body.ZIndex + 3

	UIKit.Label({
		Name = "Caption",
		Text = info.Caption,
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = tierLight,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = body,
	})
	UIKit.Label({
		Name = "TierName",
		Text = tier:upper() .. "!",
		Font = Fonts.Display,
		TextSize = 64,
		TextColor3 = tierLight,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 4,
		Parent = body,
	})

	local orb = UIKit.TierOrb(tier, 132)
	orb.AnchorPoint = Vector2.new(0.5, 0)
	orb.Position = UDim2.new(0.5, 0, 0, 116)
	orb.ZIndex = z
	orb.Parent = body

	UIKit.Label({
		Name = "ItemName",
		Text = itemName(info.Item),
		Font = Fonts.Display,
		TextSize = 28,
		Position = UDim2.fromOffset(12, 258),
		Size = UDim2.new(1, -24, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Label({
		Name = "Description",
		Text = info.Description,
		Font = Fonts.Body,
		TextSize = 15,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		Position = UDim2.fromOffset(20, 294),
		Size = UDim2.new(1, -40, 0, 38),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = z,
		Parent = body,
	})

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.AnchorPoint = Vector2.new(0.5, 0)
	buttons.Position = UDim2.new(0.5, 0, 0, 342)
	buttons.Size = UDim2.fromOffset(170 + 12 + 120, 52)
	buttons.ZIndex = z
	buttons.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = buttons

	local uid = info.Item.Uid :: string
	UIKit.Button({
		Name = "DisplayIt",
		Parent = buttons,
		Style = "Green",
		Text = "DISPLAY IT",
		TextSize = 20,
		Size = UDim2.fromOffset(170, 52),
		LayoutOrder = 1,
		ZIndex = z,
		OnClick = function()
			onDisplayIt(uid)
		end,
	})
	UIKit.Button({
		Name = "Nice",
		Parent = buttons,
		Style = "Disabled",
		Text = "NICE",
		TextSize = 20,
		Size = UDim2.fromOffset(120, 52),
		LayoutOrder = 2,
		ZIndex = z,
		OnClick = closeBigCard,
	})

	UIKit.PopIn(holder)
	if tier == "Mythic" then
		RevealEffects.ShakeCamera(MYTHIC_SHAKE_MAGNITUDE, MYTHIC_SHAKE_SECONDS)
	end
end

--[[ Rebirth card -------------------------------------------------------------------- ]]

local REBIRTH_CARD_SIZE = Vector2.new(360, 270)

local function showRebirthCard(rebirths: number)
	if bigHolder then
		if sunburstConnection then
			sunburstConnection:Disconnect()
			sunburstConnection = nil
		end
		(bigHolder :: Frame):Destroy()
		bigHolder = nil
	end

	local body, holder = UIKit.Panel({
		Name = "RebirthResult",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(REBIRTH_CARD_SIZE.X, REBIRTH_CARD_SIZE.Y),
		Gradient = {
			{ 0, Colors.Panel },
			{ 0.5, UITheme.TowardInk(Colors.Rebirth, 0.5) },
			{ 1, Colors.Panel },
		},
		Radius = 24,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	bigHolder = holder
	buildSunburst(body)
	local z = body.ZIndex + 3

	UIKit.Label({
		Name = "Caption",
		Text = "A NEW RUN BEGINS",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = Colors.RebirthLabel,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = body,
	})
	UIKit.Label({
		Name = "Title",
		Text = ("REBIRTH %d!"):format(rebirths),
		Font = Fonts.Display,
		TextSize = 54,
		TextColor3 = Colors.Rebirth,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 64),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 4,
		Parent = body,
	})
	UIKit.Label({
		Name = "Detail",
		Text = ("Income %s · Luck +%d%%"):format(
			NumberFormat.Multiplier(RebirthConfig.GetIncomeMultiplier(rebirths)),
			math.floor((RebirthConfig.GetLuck(rebirths) - 1) * 100 + 0.5)
		),
		Font = Fonts.Display,
		TextSize = 22,
		Position = UDim2.fromOffset(12, 128),
		Size = UDim2.new(1, -24, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Button({
		Name = "Nice",
		Parent = body,
		Style = "Orange",
		Text = "LET'S GO",
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 186),
		Size = UDim2.fromOffset(180, 52),
		ZIndex = z,
		OnClick = closeBigCard,
	})
	UIKit.PopIn(holder)
end

local function onRebirthResult(result: any)
	if typeof(result) == "table" and result.Success == true and typeof(result.Rebirths) == "number" then
		showRebirthCard(result.Rebirths)
	end
end

--[[ Fuse All summary card ---------------------------------------------------------- ]]

local FUSE_ALL_CARD_WIDTH = 400
local LEGENDARY_RANK = ItemConfig.Tiers.Legendary

local function tierRank(tier: string): number
	return ItemConfig.Tiers[tier] or 0
end

-- Tiers in a {[tier]: n} map, highest tier first.
local function sortedTiers(counts: { [string]: number }): { string }
	local tiers = {}
	for tier, n in counts do
		if typeof(n) == "number" and n > 0 then
			table.insert(tiers, tier)
		end
	end
	table.sort(tiers, function(a, b)
		return tierRank(a) > tierRank(b)
	end)
	return tiers
end

local function addChip(parent: Instance, tier: string, text: string, color: Color3, order: number, z: number)
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.BackgroundTransparency = 1
	chip.LayoutOrder = order
	chip.ZIndex = z
	chip.Parent = parent
	local orb = UIKit.TierOrb(tier, 26)
	orb.AnchorPoint = Vector2.new(0, 0.5)
	orb.Position = UDim2.new(0, 4, 0.5, 0)
	orb.ZIndex = z
	orb.Parent = chip
	UIKit.Label({
		Text = text,
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = color,
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -38, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = z,
		Parent = chip,
	})
end

local function showFuseAllCard(result: any)
	if bigHolder then
		if sunburstConnection then
			sunburstConnection:Disconnect()
			sunburstConnection = nil
		end
		(bigHolder :: Frame):Destroy()
		bigHolder = nil
	end

	local body, holder = UIKit.Panel({
		Name = "FuseAllSummary",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(FUSE_ALL_CARD_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Gradient = { { 0, Colors.FuseAllTop }, { 0.4, Colors.Panel }, { 1, Colors.Panel } },
		Radius = 24,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	bigHolder = holder
	local z = body.ZIndex + 1
	UIKit.Padding(body, 18, 20, 18, 20)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = body

	local count = result.Count :: number
	local upgraded = (result.Upgraded :: number?) or 0
	UIKit.Label({
		Text = "FUSE ALL",
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		TextColor3 = Colors.VioletLight,
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		ZIndex = z,
		Parent = body,
	})
	UIKit.Label({
		Text = ("%d %s"):format(count, if count == 1 then "fusion" else "fusions"),
		Font = Fonts.Display,
		TextSize = 44,
		Size = UDim2.new(1, 0, 0, 48),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Label({
		Text = ("%s · %d failed"):format(UIKit.Colored(("%d upgraded"):format(upgraded), Colors.Cash), count - upgraded),
		RichText = true,
		Font = Fonts.Body,
		TextSize = 15,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 3,
		ZIndex = z,
		Parent = body,
	})

	-- Two-column chips: gains first (highest tier first), then what was used up.
	local grid = Instance.new("Frame")
	grid.Name = "Chips"
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Size = UDim2.fromScale(1, 0)
	grid.LayoutOrder = 4
	grid.ZIndex = z
	grid.Parent = body
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -4, 0, 34)
	gridLayout.CellPadding = UDim2.fromOffset(8, 4)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local order = 0
	local gained = if typeof(result.Gained) == "table" then result.Gained else {}
	for _, tier in sortedTiers(gained) do
		order += 1
		addChip(grid, tier, ("+%d %s"):format(gained[tier], tier:upper()), UITheme.GetTierLight(tier), order, z)
	end
	local consumed = if typeof(result.Consumed) == "table" then result.Consumed else {}
	for _, tier in sortedTiers(consumed) do
		order += 1
		addChip(grid, tier, ("−%d %s"):format(consumed[tier], tier:upper()), Colors.Muted, order, z)
	end

	local best = result.Best
	if typeof(best) == "table" and typeof(best.Tier) == "string" then
		local row = UIKit.Panel({
			Name = "Best",
			Parent = body,
			Size = UDim2.new(1, 0, 0, 56),
			Color = Colors.Panel2,
			Radius = UITheme.Radius.Row,
			ShadowOffset = UITheme.SmallShadowOffset,
			LayoutOrder = 5,
			ZIndex = z,
		})
		local orb = UIKit.TierOrb(best.Tier, 38)
		orb.AnchorPoint = Vector2.new(0, 0.5)
		orb.Position = UDim2.new(0, 12, 0.5, 0)
		orb.ZIndex = row.ZIndex + 1
		orb.Parent = row
		UIKit.Label({
			Text = ("BEST · %s"):format(UIKit.Colored(best.Tier:upper(), UITheme.GetTierLight(best.Tier))),
			RichText = true,
			Font = Fonts.BodyHeavy,
			TextSize = 12,
			TextColor3 = Colors.Muted,
			Position = UDim2.fromOffset(62, 8),
			Size = UDim2.new(1, -74, 0, 16),
			ZIndex = row.ZIndex + 1,
			Parent = row,
		})
		UIKit.Label({
			Text = itemName(best),
			Font = Fonts.Display,
			TextSize = 18,
			Position = UDim2.fromOffset(62, 26),
			Size = UDim2.new(1, -74, 0, 22),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = row.ZIndex + 1,
			Stroke = UITheme.Stroke.Text,
			Parent = row,
		})
	end

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 52 + UITheme.ShadowOffset)
	buttons.LayoutOrder = 6
	buttons.ZIndex = z
	buttons.Parent = body
	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Padding = UDim.new(0, 12)
	buttonLayout.Parent = buttons

	if typeof(best) == "table" and typeof(best.Uid) == "string" then
		local uid = best.Uid :: string
		UIKit.Button({
			Name = "DisplayBest",
			Parent = buttons,
			Style = "Green",
			Text = "DISPLAY BEST",
			TextSize = 18,
			Size = UDim2.fromOffset(180, 52),
			LayoutOrder = 1,
			ZIndex = z,
			OnClick = function()
				onDisplayIt(uid)
			end,
		})
	end
	UIKit.Button({
		Name = "Ok",
		Parent = buttons,
		Style = "Disabled",
		Text = "OK",
		TextSize = 20,
		Size = UDim2.fromOffset(110, 52),
		LayoutOrder = 2,
		ZIndex = z,
		OnClick = closeBigCard,
	})

	UIKit.PopIn(holder)
	if typeof(best) == "table" and tierRank(best.Tier) >= LEGENDARY_RANK then
		RevealEffects.ShakeCamera(MYTHIC_SHAKE_MAGNITUDE, MYTHIC_SHAKE_SECONDS)
	end
end

local function onFuseAllResolved(result: any)
	if typeof(result) ~= "table" or typeof(result.Count) ~= "number" or result.Count <= 0 then
		ToastController.Show("Nothing to fuse", "Neutral")
		return
	end
	showFuseAllCard(result)
end

--[[ Bottom cards (fail / small pull) --------------------------------------------- ]]

local bottomHolder: Frame? = nil
local bottomGeneration = 0

local function hideBottomCard(generation: number)
	if generation ~= bottomGeneration then
		return
	end
	local holder = bottomHolder
	bottomHolder = nil
	ToastController.SetBottomInset(0)
	if holder then
		local tween = UIKit.PopOut(holder)
		tween.Completed:Once(function()
			holder:Destroy()
		end)
	end
end

-- Builds the shared bottom-row panel, replacing whatever card is showing.
local function newBottomCard(name: string, size: Vector2): (Frame, number)
	bottomGeneration += 1
	if bottomHolder then
		(bottomHolder :: Frame):Destroy()
		bottomHolder = nil
	end
	local body, holder = UIKit.Panel({
		Name = name,
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(BOTTOM_CARD_OFFSET + UITheme.SmallShadowOffset)),
		Size = UDim2.fromOffset(size.X, size.Y),
		Gradient = { { 0, Colors.Panel2 }, { 1, Colors.Panel } },
		Radius = 18,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = 2,
	})
	bottomHolder = holder
	ToastController.SetBottomInset(size.Y + 12)
	UIKit.PopIn(holder)

	local generation = bottomGeneration
	task.delay(BOTTOM_CARD_SECONDS, hideBottomCard, generation)
	return body, generation
end

local function showFailCard(item: any)
	local tier = item.Tier :: string
	local body, generation = newBottomCard("FailCard", FAIL_CARD_SIZE)
	local z = body.ZIndex + 1

	local orb = UIKit.TierOrb(tier, 56, 0.15)
	orb.AnchorPoint = Vector2.new(0, 0.5)
	orb.Position = UDim2.new(0, 16, 0.5, 0)
	orb.ZIndex = z
	orb.Parent = body

	UIKit.Label({
		Name = "Title",
		Text = "So close…",
		Font = Fonts.Display,
		TextSize = 22,
		Position = UDim2.fromOffset(86, 14),
		Size = UDim2.new(1, -(86 + 104 + 28), 0, 26),
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Label({
		Name = "Detail",
		Text = ("Fusion failed · you kept %s (%s)"):format(
			"<b>" .. UIKit.Colored("1 " .. tier, UITheme.GetTierLight(tier)) .. "</b>",
			UIKit.EscapeRichText(itemName(item))
		),
		RichText = true,
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		Position = UDim2.fromOffset(86, 42),
		Size = UDim2.new(1, -(86 + 104 + 28), 0, 36),
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = z,
		Parent = body,
	})

	local again = UIKit.Button({
		Name = "Again",
		Parent = body,
		Style = "Violet",
		Text = "AGAIN",
		TextSize = 18,
		Size = UDim2.fromOffset(104, 46),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, -2),
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z,
		OnClick = function()
			if FusionController.CanRequestFusion() then
				hideBottomCard(generation)
				task.spawn(FusionController.RequestFusion)
			end
		end,
	})

	-- Enabled only while you're still at your machine with another pair.
	task.spawn(function()
		while bottomGeneration == generation and again.Parent do
			local canFuse = FusionController.CanRequestFusion()
			UIKit.SetButton(again, {
				Style = if canFuse then "Violet" else "Disabled",
				TextColor3 = if canFuse then Colors.Text else Colors.Muted,
			})
			task.wait(0.25)
		end
	end)
end

local function showPullCard(item: any)
	local tier = item.Tier :: string
	local body = newBottomCard("PullCard", PULL_CARD_SIZE)
	local z = body.ZIndex + 1

	UIKit.Label({
		Name = "Caption",
		Text = "PULLED",
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = Colors.GoldLabel,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(56, 16),
		ZIndex = z,
		Parent = body,
	})

	local orb = UIKit.TierOrb(tier, 40)
	orb.AnchorPoint = Vector2.new(0, 0.5)
	orb.Position = UDim2.new(0, 78, 0.5, 0)
	orb.ZIndex = z
	orb.Parent = body

	UIKit.Label({
		Name = "ItemName",
		Text = itemName(item),
		Font = Fonts.Display,
		TextSize = 18,
		Position = UDim2.fromOffset(130, 14),
		Size = UDim2.new(1, -(130 + 130), 0, 24),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Label({
		Name = "Tier",
		Text = tier:upper(),
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = UITheme.GetTierLight(tier),
		Position = UDim2.fromOffset(130, 40),
		Size = UDim2.new(1, -(130 + 130), 0, 16),
		ZIndex = z,
		Parent = body,
	})
	UIKit.Label({
		Name = "NextPull",
		Text = ("next pull %s"):format(NumberFormat.Money(TycoonConfig.GetGachaPullCost(TycoonController.GetGachaPulls()))),
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Muted,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(120, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = z,
		Parent = body,
	})
end

--[[ Event routing ------------------------------------------------------------------ ]]

-- Exposed so AnnouncementController can skip the banner for these cases.
function ResultController.ShowsBigCardFor(tier: string): boolean
	return FusionConfig.MajorRevealTiers[tier] == true
end

local function onFusionResolved(result: any)
	if typeof(result) ~= "table" or not result.Success or not result.NewItem then
		return
	end
	local newItem = result.NewItem
	if not result.Upgraded then
		showFailCard(newItem)
		return
	end
	if ResultController.ShowsBigCardFor(newItem.Tier) then
		showBigCard({
			Caption = "FUSION SUCCESS",
			Item = newItem,
			Description = ("2x %s → %s · earns %s/s on a pedestal"):format(
				tostring(result.ConsumedTier),
				newItem.Tier,
				NumberFormat.Money(earnRate(newItem.Tier))
			),
		})
	end
end

local function onGachaPullResult(payload: any)
	if typeof(payload) ~= "table" or not payload.Success or not payload.NewItem then
		return
	end
	local newItem = payload.NewItem
	if ResultController.ShowsBigCardFor(newItem.Tier) then
		showBigCard({
			Caption = "YOU PULLED",
			Item = newItem,
			Description = ("earns %s/s on a pedestal"):format(NumberFormat.Money(earnRate(newItem.Tier))),
		})
	else
		showPullCard(newItem)
	end
end

function ResultController.Init()
	screenGui = UIKit.Screen("Results", 130)
	FusionController.FusionResolved:Connect(onFusionResolved)
	FusionController.FuseAllResolved:Connect(onFuseAllResolved)
	RemoteEvents.GachaPullResult.OnClientEvent:Connect(onGachaPullResult)
	RemoteEvents.RebirthResult.OnClientEvent:Connect(onRebirthResult)
end

return ResultController
