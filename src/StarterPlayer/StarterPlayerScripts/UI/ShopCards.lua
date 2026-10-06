--!strict
--[[
	ShopCards
	---------
	The shop's small cards (ShopController decides when; these only draw):

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
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.UIKit)

local ShopCards = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local SIDE_GRADIENT: { { any } } = { { 0, Colors.Panel2 }, { 1, Colors.Panel } }
local SIDE_CARD_WIDTH = 330
local SIDE_CARD_MARGIN = 16
local SIDE_CARD_BOTTOM = UITheme.BottomStackOffset

local screenGui: ScreenGui? = nil
local sideHolder: Frame? = nil

local function gui(): ScreenGui
	local existing = screenGui
	if existing then
		return existing
	end
	-- Above every panel (Upgrades 140, Shop 141, Settings 143), so an offer
	-- from the Upgrades panel shows over it.
	local created = UIKit.Screen("ShopCards", 150)
	screenGui = created
	return created
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

-- The open side card's Name ("ShopOffer", "DealOffer", ...), for /selftest.
function ShopCards.GetSideName(): string?
	local holder = sideHolder
	return if holder then holder.Name else nil
end

export type SideCard = {
	Name: string,
	Caption: string, -- small line at the top
	Title: string, -- the big line
	Detail: string, -- what you'd get (RichText)
	Footnote: string?, -- the honest "or wait ~4 min" line
	BuyText: string, -- the price button ("<robux> 49")
	DismissText: string, -- "Not now"
	MoreText: string?, -- a quiet link under the buttons ("See all in the shop ›")
}

local function sideCard(card: SideCard, onBuy: () -> (), onDismiss: (() -> ())?, onMore: (() -> ())?)
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
	local moreText = card.MoreText
	if moreText and onMore then
		-- A quiet text link, still a full 44 px tap target.
		local more = Instance.new("TextButton")
		more.Name = "More"
		more.BackgroundTransparency = 1
		more.AutoButtonColor = false
		more.FontFace = Fonts.BodyHeavy
		more.TextSize = 14
		more.TextColor3 = Colors.Muted
		more.Text = moreText
		more.Size = UDim2.new(1, 0, 0, UITheme.MinTapSize)
		more.LayoutOrder = 6
		more.ZIndex = z
		more.Parent = body
		more.Activated:Connect(function()
			ShopCards.CloseSide()
			onMore()
		end)
	end
	UIKit.PopIn(holder)
	-- A gentle slide so it reads as "here if you want it", not a popup.
	local scale = holder:FindFirstChild("PopScale")
	if scale then
		TweenService:Create(holder, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = holder.Position }):Play()
	end
end

function ShopCards.ShowOffer(card: SideCard, onBuy: () -> (), onDismiss: (() -> ())?, onMore: (() -> ())?)
	sideCard(card, onBuy, onDismiss, onMore)
end

function ShopCards.ShowStarter(card: SideCard, onBuy: () -> (), onDismiss: () -> ())
	sideCard(card, onBuy, onDismiss)
end

return ShopCards
