--!strict
--[[
	ShopController
	--------------
	The client side of the shop. Everything is granted by the server's
	MonetizationService; this only shows and asks.

	  ShopController.IsAvailable(key)    offered to you right now?
	                                     (ShopConfig.IsOffered + a live sale
	                                     window for a sale product)
	  ShopController.IsOwned(key)        an owned pass / the bought pack
	  ShopController.Buy(key)            RequestShopPurchase { Key }: the server
	                                     checks again, then prompts Roblox
	  ShopController.GetPriceText(key)   "<robux> 79" from the LIVE price
	                                     (ShopPrices), "…" while it loads,
	                                     "TEST" for an Id 0 item in Studio
	  ShopController.GetCashAmount(key)  what a cash pack pays you right now
	                                     (base income, no timed boosts)
	  ShopController.OfferForShortfall(label, cost, fromOverlay?)
	                                     the contextual offer (rules below)
	  ShopController.Purchased           fires (payload) on every ShopPurchased

	Contextual offer, only when the player TAPS something they can't afford
	(an upgrade or MAX, a pull or Pull x10, the Multiplier Pad, REBIRTH):
	the smallest cash pack covering the gap, or the Boost if none does. Never
	more than once per ShopConfig.OfferCooldownSeconds; never in the first
	FirstSessionQuietSeconds of a first session; never over another card
	(UIKit overlays, other than the panel the tap came from); never within
	AfterLossQuietSeconds of a failed fusion, a theft or a caught steal;
	never for players whose policy hides cash / boosts.

	Starter Pack: once, in the player's 2nd session (PlayerData.Sessions),
	StarterOfferDelaySeconds after joining, a dismissible side card. After
	that it only lives in the shop's featured slot until bought.

	Also: refusal toasts, the THANK YOU card after a grant, the VIP chat
	prefix (TextChatService, from the Player attribute "VIP").
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local ShopState = require(ReplicatedStorage.Shared.Modules.ShopState)
local ShopPrices = require(ReplicatedStorage.Shared.Modules.ShopPrices)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonController = require(script.Parent.TycoonController)
local ToastController = require(script.Parent.ToastController)
local FusionController = require(script.Parent.FusionController)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ShopCards = require(script.Parent.Parent.UI.ShopCards)

local ShopController = {}

-- Roblox's Robux glyph (renders as the Robux icon in Roblox fonts).
ShopController.ROBUX = utf8.char(0xE002)

local purchased = Instance.new("BindableEvent")
ShopController.Purchased = purchased.Event

local REFUSAL_TOASTS: { [string]: string } = {
	Restricted = "That item isn't available for your account",
	NotSetUp = "Coming soon!",
	Owned = "You already have that",
	SaleOver = "That sale just ended",
	NothingToDouble = "Nothing to double right now",
	NotLoaded = "Your lab is still loading, try again",
	Unknown = "Couldn't do that, try again",
}

local joinedAt = os.clock()
local lastOfferAt = -math.huge
local lastLossAt = -math.huge
local starterShown = false

--[[ Availability + prices ------------------------------------------------------------ ]]

function ShopController.IsAvailable(key: string): boolean
	local shop = TycoonController.GetShop()
	if not ShopConfig.IsOffered(key, shop.Restricted, RunService:IsStudio(), shop.StarterPackBought) then
		return false
	end
	local item = ShopConfig.GetItem(key) :: ShopConfig.Item
	if item.SaleOf and not ShopState.IsSaleLive(key) then
		return false
	end
	if key == "OfflineDouble" and shop.OfflineDoubleAmount <= 0 then
		return false
	end
	return true
end

function ShopController.IsOwned(key: string): boolean
	local item = ShopConfig.GetItem(key)
	if not item then
		return false
	end
	if item.Kind == "Pass" then
		return TycoonController.OwnsPass(key)
	end
	return key == "StarterPack" and TycoonController.GetShop().StarterPackBought
end

function ShopController.GetPriceText(key: string): string
	local item = ShopConfig.GetItem(key)
	if item and item.Id == 0 then
		return "TEST"
	end
	local price = ShopPrices.Get(key)
	return if price then ("%s %d"):format(ShopController.ROBUX, price) else "…"
end

-- Your income per second without timed boosts (what cash packs pay from).
function ShopController.GetBaseIncome(): number
	local inputs = TycoonController.GetIncomeInputs()
	inputs.BoostMultiplier = 1
	inputs.OverclockMultiplier = 1
	return TycoonConfig.GetPassiveCashPerSecond(inputs)
end

function ShopController.GetCashAmount(key: string): number
	return ShopConfig.GetCashPackAmount(key, ShopController.GetBaseIncome())
end

function ShopController.Buy(key: string)
	RemoteEvents.RequestShopPurchase:FireServer({ Key = key })
end

-- Analytics only (the server whitelists and rate-limits): "ShopOpened",
-- "OfferShown" / "OfferAccepted" / "OfferDismissed" with the offer's key.
function ShopController.Track(event: string, key: string?)
	RemoteEvents.ShopAnalytics:FireServer({ Event = event, Key = key })
end

--[[ Contextual offer --------------------------------------------------------------------- ]]

-- "~4 min", "~2 h": how long your income takes to cover `gap`.
local function waitText(gap: number): string
	local income = TycoonConfig.GetPassiveCashPerSecond(TycoonController.GetIncomeInputs())
	if income <= 0 then
		return "or keep playing to earn it"
	end
	local seconds = gap / income
	if seconds < 90 then
		return "or wait about a minute with your income"
	elseif seconds < 2 * 3600 then
		return ("or wait ~%d min with your income"):format(math.ceil(seconds / 60))
	end
	return ("or wait ~%d h with your income"):format(math.ceil(seconds / 3600))
end

-- Why no offer may show right now (nil = it may).
local function offerBlocked(fromOverlay: string?): string?
	local now = os.clock()
	local shop = TycoonController.GetShop()
	if not TycoonController.HasSynced() then
		return "NotSynced"
	end
	if now - lastOfferAt < ShopConfig.OfferCooldownSeconds then
		return "Cooldown"
	end
	if shop.Sessions <= 1 and now - joinedAt < ShopConfig.FirstSessionQuietSeconds then
		return "FirstSession"
	end
	if now - lastLossAt < ShopConfig.AfterLossQuietSeconds then
		return "AfterLoss"
	end
	if UIKit.IsOverlayOpen(fromOverlay) or ShopCards.IsSideOpen() then
		return "OtherCard"
	end
	return nil
end

-- The player tapped `label` (costing `cost`) and can't afford it. Maybe
-- shows one offer card (see the header for every rule). `fromOverlay`: the
-- UIKit overlay the tap came from (the Upgrades panel), which may stay open.
function ShopController.OfferForShortfall(label: string, cost: number, fromOverlay: string?)
	local gap = cost - TycoonController.GetCash()
	if gap <= 0 or offerBlocked(fromOverlay) then
		return
	end
	local base = ShopController.GetBaseIncome()
	local key = ShopConfig.GetSmallestPackCovering(gap, base, ShopController.IsAvailable)
	local detail: string
	if key then
		detail = ("%s · %s"):format(
			UIKit.Colored("+" .. NumberFormat.Money(ShopController.GetCashAmount(key)), UITheme.Colors.Cash),
			(ShopConfig.GetItem(key) :: ShopConfig.Item).Name
		)
	elseif ShopController.IsAvailable("Boost") then
		-- No pack covers it: the Boost doubles your income instead.
		key = "Boost"
		detail = ("%s · ×%d income for 1 hour"):format((ShopConfig.GetItem("Boost") :: ShopConfig.Item).Name, ShopConfig.BoostMultiplier)
	else
		return
	end
	local offerKey = key :: string
	lastOfferAt = os.clock()
	ShopCards.ShowOffer({
		Name = "ShopOffer",
		Caption = ("You tapped: %s · %s"):format(label, NumberFormat.Money(cost)),
		Title = ("Need %s more?"):format(NumberFormat.Money(gap)),
		Detail = detail,
		Footnote = waitText(gap),
		BuyText = ShopController.GetPriceText(offerKey),
		DismissText = "Not now",
	}, function()
		ShopController.Track("OfferAccepted", offerKey)
		ShopController.Buy(offerKey)
	end, function()
		ShopController.Track("OfferDismissed", offerKey)
	end)
	ShopController.Track("OfferShown", offerKey)
end

--[[ Starter Pack (session 2) --------------------------------------------------------------- ]]

local function maybeShowStarter()
	if starterShown then
		return
	end
	local shop = TycoonController.GetShop()
	if shop.Sessions ~= ShopConfig.StarterOfferSession or not ShopController.IsAvailable("StarterPack") then
		return
	end
	if UIKit.IsOverlayOpen() or ShopCards.IsSideOpen() then
		-- Try again in a little while rather than landing on another card.
		task.delay(20, maybeShowStarter)
		return
	end
	starterShown = true
	local price = ShopPrices.Get("StarterPack")
	local worth = ShopPrices.GetPartsTotal("StarterPack")
	local save = ShopConfig.GetSavePercent(price, worth)
	ShopCards.ShowStarter({
		Name = "StarterOffer",
		Caption = "Welcome back!",
		Title = "🎁 Starter Pack",
		Detail = "Neon Pink Lab + 1 hour ×2 Boost + Pocket Cash"
			.. (if save then ("  ·  %s"):format(UIKit.Colored(("SAVE %d%%"):format(save), UITheme.Colors.GoldLabel)) else ""),
		Footnote = "One time only. Also in the shop.",
		BuyText = ShopController.GetPriceText("StarterPack"),
		DismissText = "No thanks",
	}, function()
		ShopController.Track("OfferAccepted", "StarterPack")
		ShopController.Buy("StarterPack")
	end, function()
		ShopController.Track("OfferDismissed", "StarterPack")
	end)
	ShopController.Track("OfferShown", "StarterPack")
end

--[[ Remotes ---------------------------------------------------------------------------- ]]

local function onPurchased(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Result == "Refused" then
		local reason = if typeof(payload.Reason) == "string" then payload.Reason else "Unknown"
		ToastController.Show(REFUSAL_TOASTS[reason] or REFUSAL_TOASTS.Unknown, "Error")
	elseif payload.Result == "Granted" then
		local lines = if typeof(payload.Lines) == "table" then payload.Lines else {}
		ShopCards.ShowThankYou(lines, payload.Test == true)
	end
	purchased:Fire(payload)
end

-- Losses that keep the offer quiet for AfterLossQuietSeconds.
local function onHeistEnded(payload: any)
	if typeof(payload) ~= "table" or payload.Outcome == "Rejected" then
		return
	end
	local stolenFromYou = payload.Role == "Victim" and payload.Outcome == "Delivered"
	local caught = payload.Role == "Thief" and payload.Outcome ~= "Delivered"
	if stolenFromYou or caught then
		lastLossAt = os.clock()
	end
end

-- "[VIP]" in gold before a VIP's name in chat.
local function onIncomingMessage(message: TextChatMessage): TextChatMessageProperties?
	local source = message.TextSource
	local speaker = source and Players:GetPlayerByUserId(source.UserId)
	if not speaker or speaker:GetAttribute("VIP") ~= true then
		return nil
	end
	local properties = Instance.new("TextChatMessageProperties")
	properties.PrefixText = ('<font color="%s">[VIP]</font> %s'):format(UITheme.ToHex(UITheme.World.VipGold), message.PrefixText)
	return properties
end

function ShopController.Init()
	joinedAt = os.clock()
	RemoteEvents.ShopPurchased.OnClientEvent:Connect(onPurchased)
	RemoteEvents.HeistEnded.OnClientEvent:Connect(onHeistEnded)
	FusionController.FusionResolved:Connect(function(result: any)
		if typeof(result) == "table" and result.Success and not result.Upgraded and not result.Safe then
			lastLossAt = os.clock()
		end
	end)
	TextChatService.OnIncomingMessage = onIncomingMessage
	ShopPrices.Prefetch()
	task.delay(ShopConfig.StarterOfferDelaySeconds, maybeShowStarter)
end

return ShopController
