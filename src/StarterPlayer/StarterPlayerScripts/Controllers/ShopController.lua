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
	  ShopController.OpenShop(section?)  opens the shop (scrolled to a
	                                     ShopConfig.Sections id); ShopPanel
	                                     registers itself with SetShopOpener

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

	Also: refusal toasts, the purchase celebration after a grant
	(UI/PurchaseCelebration), the VIP chat
	prefix (TextChatService, from the Player attribute "VIP").
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local DealConfig = require(ReplicatedStorage.Shared.Config.DealConfig)
local DealState = require(ReplicatedStorage.Shared.Modules.DealState)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
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
local PurchaseCelebration = require(script.Parent.Parent.UI.PurchaseCelebration)

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
	DealOver = "That deal just ended: a new one is up",
	NothingToDouble = "Nothing to double right now",
	NotLoaded = "Your lab is still loading, try again",
	Unknown = "Couldn't do that, try again",
}

local shopOpener: ((section: string?) -> ())? = nil

local DEAL_CHECK_SECONDS = 15
local localPlayer = Players.LocalPlayer

local joinedAt = os.clock()
local lastOfferAt = -math.huge
local lastLossAt = -math.huge
local starterShown = false

--[[ Opening the shop ---------------------------------------------------------------- ]]

-- ShopPanel requires this module, so it hands its Open in at Init.
function ShopController.SetShopOpener(opener: (section: string?) -> ())
	shopOpener = opener
end

function ShopController.OpenShop(section: string?)
	if shopOpener then
		shopOpener(section)
	end
end

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
	if item.Deal and not DealState.IsCurrent(key) then
		return false
	end
	if key == "OfflineDouble" and shop.OfflineDoubleAmount <= 0 then
		return false
	end
	return true
end

-- Anything in the shop right now (offered, or an owned pass to show)? A
-- live game with no product ids set yet has nothing: the HUD hides SHOP
-- rather than open an empty panel.
function ShopController.HasAnyOffer(): boolean
	for _, key in ShopConfig.Order do
		if ShopController.IsAvailable(key) or ShopController.IsOwned(key) then
			return true
		end
	end
	return false
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
	-- The tutorial never sells anything; nothing pops up over it.
	if TycoonController.IsTutorialActive() then
		return "Tutorial"
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
		MoreText = "See all in the shop ›",
	}, function()
		ShopController.Track("OfferAccepted", offerKey)
		ShopController.Buy(offerKey)
	end, function()
		ShopController.Track("OfferDismissed", offerKey)
	end, function()
		-- Opens the shop scrolled to the section the offer came from.
		ShopController.OpenShop(if ShopConfig.CashPacks[offerKey] then "Cash" else "Boosts")
	end)
	ShopController.Track("OfferShown", offerKey)
end

--[[ Rotating deals (DealConfig) ----------------------------------------------------------
	The current slot's deal, shown only while its LIVE saving is at least
	DealConfig.MinSavePercent (Studio: Id 0 deals show as TEST with no %).
	The "New deal!" side card shows at most once per slot, under the same
	guards and shared 5-minute limit as the contextual offer, never while
	you carry or are being stolen from; "Not now" hides it until the next
	slot. ]]

export type DealView = {
	Key: string,
	Item: ShopConfig.Item,
	Icons: string, -- the parts' icons, "⚡ 🧪"
	Price: number?,
	Normal: number?, -- the parts at live prices
	Save: number?,
	SlotStart: number,
	SecondsLeft: number,
}

-- The current slot's deal. `gated`: only while it's offered to you and its
-- live saving reaches DealConfig.MinSavePercent (a Studio Id 0 deal has no
-- price, so it shows as TEST with no saving). Ungated (Studio /deal pop):
-- the slot's deal whatever the price or policy says.
local function dealView(gated: boolean): DealView?
	local key, slotStart, secondsLeft = DealState.GetCurrent()
	if gated and not ShopController.IsAvailable(key) then
		return nil
	end
	local item = ShopConfig.GetItem(key) :: ShopConfig.Item
	local price = ShopPrices.Get(key)
	local normal = ShopPrices.GetPartsTotal(key)
	local save = ShopConfig.GetSavePercent(price, normal)
	local studioTest = item.Id == 0 and RunService:IsStudio()
	if gated and not studioTest and (not save or save < DealConfig.MinSavePercent) then
		return nil
	end
	local icons, seen = {}, {}
	local parts: { string } = item.Parts or {}
	for _, part in parts do
		local partItem = ShopConfig.GetItem(part)
		if partItem and not seen[part] then
			seen[part] = true
			table.insert(icons, partItem.Icon)
		end
	end
	return {
		Key = key,
		Item = item,
		Icons = table.concat(icons, " "),
		Price = price,
		Normal = normal,
		Save = save,
		SlotStart = slotStart,
		SecondsLeft = secondsLeft,
	}
end

function ShopController.GetDeal(): DealView?
	return dealView(true)
end

-- "normally ~~128~~ R$ · now 99 R$ (−23%)", all live (RichText).
function ShopController.GetDealPriceLine(deal: DealView): string
	if deal.Price and deal.Normal then
		return ("normally <s>%s %d</s> · now %s %d%s"):format(
			ShopController.ROBUX,
			deal.Normal,
			ShopController.ROBUX,
			deal.Price,
			if deal.Save then (" (−%d%%)"):format(deal.Save) else ""
		)
	end
	return "Studio test: live prices appear once the product is set up"
end

-- The slot whose card was shown (or dismissed) this session; the saved
-- copy (snapshot Shop.DealPopupSlot) covers a rejoin in the same slot.
local dealPopSlot: number? = nil

-- Carrying a stolen item, or one of yours is being carried off.
local function heistBusy(): boolean
	if localPlayer:GetAttribute("HeistTier") ~= nil then
		return true
	end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("HeistVictimUserId") == localPlayer.UserId and player:GetAttribute("HeistTier") ~= nil then
			return true
		end
	end
	return false
end

-- Why the real (unforced) path won't show the card now (nil = it may).
local function dealBlocked(deal: DealView, ignoreSaved: boolean): string?
	if heistBusy() then
		return "Heist"
	end
	if dealPopSlot == deal.SlotStart or (not ignoreSaved and TycoonController.GetShop().DealPopupSlot == deal.SlotStart) then
		return "ShownThisSlot"
	end
	return offerBlocked(nil)
end

local function showDealCard(deal: DealView, track: boolean)
	dealPopSlot = deal.SlotStart
	lastOfferAt = os.clock()
	local key = deal.Key
	ShopCards.ShowOffer({
		Name = "DealOffer",
		Caption = "🔥 New deal!",
		Title = deal.Item.Name,
		Detail = ("%s  ·  %s"):format(deal.Icons, ShopController.GetDealPriceLine(deal)),
		Footnote = ("New deal in %s"):format(EventState.FormatTimer(deal.SecondsLeft)),
		-- A Studio Id 0 deal: "TEST" (no price, no saving).
		BuyText = if deal.Item.Id == 0 then "TEST" else "See deal",
		DismissText = "Not now",
	}, function()
		ShopController.Track("DealOpened", key)
		ShopController.OpenShop("Deal")
	end, function()
		ShopController.Track("DealDismissed", key)
	end)
	if track then
		ShopController.Track("DealShown", key)
	end
end

-- The real path: once per deal slot (saved), under the offer guards.
local function maybeShowDeal()
	local deal = dealView(true)
	if not deal or dealBlocked(deal, false) then
		return
	end
	showDealCard(deal, true)
	RemoteEvents.MarkDealPopup:FireServer({ Slot = deal.SlotStart })
end

-- Studio /deal pop: bypasses every guard (first session, cooldown, shown
-- this slot, another card open, heist, policy, no live saving) and shows
-- the slot's deal now. Not saved, so the real path can still be tested.
local function forceShowDeal()
	local deal = dealView(false)
	if not deal then
		return
	end
	-- ShopCards draw above every panel, so an open one doesn't hide it.
	showDealCard(deal, false)
end

-- /selftest: the real path with the clock moved past every time guard
-- (first session, cooldown, after a loss) and the shown-this-slot marks
-- cleared, nothing saved. The card must show; everything is restored.
function ShopController.SelfTestDealPath(): { string }
	local deal = dealView(true)
	if not deal then
		return { "PASS deal real path (skipped: no deal on offer here: policy or no live saving)" }
	end
	local savedJoined, savedOffer, savedLoss, savedSlot = joinedAt, lastOfferAt, lastLossAt, dealPopSlot
	joinedAt = os.clock() - ShopConfig.FirstSessionQuietSeconds - 1
	lastOfferAt = -math.huge
	lastLossAt = -math.huge
	dealPopSlot = nil
	ShopCards.CloseSide()
	local blocked = dealBlocked(deal, true)
	if not blocked then
		showDealCard(deal, false)
	end
	local shown = ShopCards.GetSideName() == "DealOffer"
	ShopCards.CloseSide()
	joinedAt, lastOfferAt, lastLossAt, dealPopSlot = savedJoined, savedOffer, savedLoss, savedSlot
	if blocked then
		return { ("FAIL deal real path: still blocked by %s with the guards cleared"):format(blocked) }
	end
	return { if shown then "PASS deal real path (card shown)" else "FAIL deal real path: no card" }
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
	if UIKit.IsOverlayOpen() or ShopCards.IsSideOpen() or TycoonController.IsTutorialActive() then
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
		PurchaseCelebration.Show(payload)
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
	-- The deal card: checked every DEAL_CHECK_SECONDS (a new slot, the quiet
	-- time ending); Studio /deal pop forces it once (bypasses every guard).
	task.spawn(function()
		while true do
			task.wait(DEAL_CHECK_SECONDS)
			maybeShowDeal()
		end
	end)
	localPlayer:GetAttributeChangedSignal("DealPopNonce"):Connect(forceShowDeal)
end

return ShopController
