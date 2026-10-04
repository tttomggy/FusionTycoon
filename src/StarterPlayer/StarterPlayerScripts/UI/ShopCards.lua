--!strict
--[[
	ShopCards
	---------
	The shop's small cards (ShopController decides when; these only draw):

	  ShowThankYou(lines, test)   centre: "THANK YOU!", what you got, a gold
	                              sunburst and the RevealMajor sound
	  ShowOffer(offer, onBuy)     bottom-right, NOT a modal: "You tapped:
	                              Core Engine LV 7 · $8.2M", "Need $3.4M
	                              more?", the smallest pack that covers it,
	                              "Not now" + the price button, and the
	                              honest "or wait ~4 min with your income"
	  ShowStarter(offer, onBuy)   bottom-right, dismissible: "Welcome back!
	                              Starter Pack" with its live price

	Every price string comes from the caller (ShopPrices, live).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local UIKit = require(script.Parent.UIKit)

local ShopCards = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local THANK_YOU_SIZE = Vector2.new(400, 300)
local THANK_YOU_GRADIENT: { { any } } = {
	{ 0, Colors.Panel },
	{ 0.5, UITheme.TowardInk(UITheme.World.VipGold, 0.55) },
	{ 1, Colors.Panel },
}
local SIDE_GRADIENT: { { any } } = { { 0, Colors.Panel2 }, { 1, Colors.Panel } }
local SIDE_CARD_WIDTH = 330
local SIDE_CARD_MARGIN = 16
local SIDE_CARD_BOTTOM = UITheme.BottomStackOffset
local SUNBURST_DEG_PER_SEC = 25

local screenGui: ScreenGui? = nil
local thankYouHolder: Frame? = nil
local sideHolder: Frame? = nil

local function gui(): ScreenGui
	local existing = screenGui
	if existing then
		return existing
	end
	-- Above every panel (Upgrades 140, Shop 141, Settings 143), so an offer
	-- from the Upgrades panel and the THANK YOU over the shop both show.
	local created = UIKit.Screen("ShopCards", 150)
	screenGui = created
	return created
end

--[[ Thank you ------------------------------------------------------------------ ]]

local function closeThankYou()
	local holder = thankYouHolder
	thankYouHolder = nil
	UIKit.SetOverlay("ShopThankYou", false)
	if holder then
		UIKit.PopOut(holder).Completed:Once(function()
			holder:Destroy()
		end)
	end
end

function ShopCards.ShowThankYou(lines: { string }, test: boolean)
	if thankYouHolder then
		(thankYouHolder :: Frame):Destroy()
	end
	local body, holder = UIKit.Panel({
		Name = "ShopThankYou",
		Parent = gui(),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(THANK_YOU_SIZE.X, THANK_YOU_SIZE.Y),
		Gradient = THANK_YOU_GRADIENT,
		Radius = 24,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	thankYouHolder = holder
	UIKit.SetOverlay("ShopThankYou", true)
	local z = body.ZIndex + 2

	-- A slow gold sunburst behind the words (the reveal-card look).
	local burst = Instance.new("Frame")
	burst.Name = "Sunburst"
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.42)
	burst.Size = UDim2.fromOffset(520, 520)
	burst.BackgroundColor3 = UITheme.World.VipGold
	burst.BackgroundTransparency = 0.82
	burst.ZIndex = body.ZIndex + 1
	burst.Parent = body
	local burstGradient = Instance.new("UIGradient")
	burstGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 1),
		NumberSequenceKeypoint.new(0.4, 0),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(0.8, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	burstGradient.Parent = burst
	body.ClipsDescendants = true
	local spin: RBXScriptConnection
	spin = RunService.RenderStepped:Connect(function(dt: number)
		if not burst.Parent then
			spin:Disconnect()
			return
		end
		burst.Rotation = (burst.Rotation + SUNBURST_DEG_PER_SEC * dt) % 360
	end)

	UIKit.Label({
		Name = "Title",
		Text = "THANK YOU!",
		Font = Fonts.Display,
		TextSize = 44,
		TextColor3 = Colors.GoldLabel,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 52),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 4,
		Parent = body,
	})
	UIKit.Label({
		Name = "Lines",
		Text = table.concat(lines, "\n") .. (if test then "\n(Studio test grant: no Robux)" else ""),
		Font = Fonts.Body,
		TextSize = 17,
		TextWrapped = true,
		Position = UDim2.fromOffset(20, 84),
		Size = UDim2.new(1, -40, 0, 130),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	UIKit.Button({
		Name = "Nice",
		Parent = body,
		Style = "Gold",
		Text = "AWESOME",
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(180, 52),
		ZIndex = z,
		OnClick = closeThankYou,
	})
	UIKit.PopIn(holder)
	SoundKit.Play("RevealMajor", nil)
end

--[[ Side cards (offer, Starter Pack) --------------------------------------------- ]]

function ShopCards.CloseSide()
	local holder = sideHolder
	sideHolder = nil
	if holder then
		UIKit.PopOut(holder).Completed:Once(function()
			holder:Destroy()
		end)
	end
end

function ShopCards.IsSideOpen(): boolean
	return sideHolder ~= nil
end

export type SideCard = {
	Name: string,
	Caption: string, -- small line at the top
	Title: string, -- the big line
	Detail: string, -- what you'd get (RichText)
	Footnote: string?, -- the honest "or wait ~4 min" line
	BuyText: string, -- the price button ("<robux> 49")
	DismissText: string, -- "Not now"
}

local function sideCard(card: SideCard, onBuy: () -> (), onDismiss: (() -> ())?)
	ShopCards.CloseSide()
	local body, holder = UIKit.Panel({
		Name = card.Name,
		Parent = gui(),
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -SIDE_CARD_MARGIN, 1, -SIDE_CARD_BOTTOM),
		Size = UDim2.fromOffset(SIDE_CARD_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Gradient = SIDE_GRADIENT,
		Radius = 18,
		ZIndex = 2,
	})
	sideHolder = holder
	UIKit.Padding(body, 12, 14, 12, 14)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body
	local z = body.ZIndex + 1
	local function line(name: string, text: string, font: Font, size: number, color: Color3, order: number, stroke: boolean?)
		UIKit.Label({
			Name = name,
			Text = text,
			RichText = true,
			Font = font,
			TextSize = size,
			TextColor3 = color,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, size + 2),
			LayoutOrder = order,
			ZIndex = z,
			Stroke = if stroke then UITheme.Stroke.Text else nil,
			Parent = body,
		})
	end
	line("Caption", card.Caption, Fonts.BodyHeavy, 13, Colors.Muted, 1)
	line("Title", card.Title, Fonts.Display, 22, Colors.Text, 2, true)
	line("Detail", card.Detail, Fonts.Body, 15, Colors.Text, 3)

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, UITheme.MinTapSize + UITheme.SmallShadowOffset)
	buttons.LayoutOrder = 4
	buttons.ZIndex = z
	buttons.Parent = body
	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.Padding = UDim.new(0, 8)
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Parent = buttons
	UIKit.Button({
		Name = "NotNow",
		Parent = buttons,
		Style = "Disabled",
		Text = card.DismissText,
		TextColor3 = Colors.Muted,
		TextSize = 15,
		Size = UDim2.new(0.42, -4, 0, UITheme.MinTapSize),
		LayoutOrder = 1,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z,
		OnClick = function()
			ShopCards.CloseSide()
			if onDismiss then
				onDismiss()
			end
		end,
	})
	UIKit.Button({
		Name = "Buy",
		Parent = buttons,
		Style = "Green",
		Text = card.BuyText,
		TextSize = 20,
		Size = UDim2.new(0.58, -4, 0, UITheme.MinTapSize),
		LayoutOrder = 2,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z,
		OnClick = function()
			ShopCards.CloseSide()
			onBuy()
		end,
	})
	if card.Footnote then
		line("Footnote", card.Footnote, Fonts.Body, 13, Colors.Faint, 5)
	end
	UIKit.PopIn(holder)
	-- A gentle slide so it reads as "here if you want it", not a popup.
	local scale = holder:FindFirstChild("PopScale")
	if scale then
		TweenService:Create(holder, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = holder.Position }):Play()
	end
end

function ShopCards.ShowOffer(card: SideCard, onBuy: () -> (), onDismiss: (() -> ())?)
	sideCard(card, onBuy, onDismiss)
end

function ShopCards.ShowStarter(card: SideCard, onBuy: () -> (), onDismiss: () -> ())
	sideCard(card, onBuy, onDismiss)
end

return ShopCards
