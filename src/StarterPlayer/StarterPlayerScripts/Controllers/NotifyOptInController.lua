--!strict
--[[
	NotifyOptInController
	---------------------
	Asks the player, once per session, to opt in to Roblox experience
	notifications. The ask is Roblox's own modal (PromptOptIn); we add no
	card before it.

	  * When: never on join. Earliest NotifyConfig.MinSessionSeconds into this
	    session's play AND the tutorial done. Then at the first high moment
	    (OnMoment): a successful fusion's result card closing, a pull of
	    NotifyConfig.MinPullTier or better closing (ResultController), or the
	    daily reveal closing (DailyCard's OnRevealClosed). If none happened by
	    NotifyConfig.FallbackSeconds, the next time no overlay is open (Tick).
	  * Guards: no tutorial; no card open (UIKit overlays, the shop's side
	    cards: waits up to WAIT_LIMIT_SECONDS, then gives up for the
	    session); not within LOSS_QUIET_SECONDS of a purchase prompt or a
	    failed fusion (no asks after a loss); not suppressed by /selftest;
	    Roblox's CanPromptOptInAsync (under-13, already opted in and the
	    30-day cooldown are Roblox's to enforce, nothing saved by us).
	  * Logs NotifyOptInShown / NotifyOptInClosed through the server's
	    AnalyticsKit (remote NotifyOptInAnalytics).
]]
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local NotifyConfig = require(ReplicatedStorage.Shared.Config.NotifyConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonController = require(script.Parent.TycoonController)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ShopCards = require(script.Parent.Parent.UI.ShopCards)

local NotifyOptInController = {}

local SETTLE_SECONDS = 0.5
local RETRY_SECONDS = 0.5
local WAIT_LIMIT_SECONDS = 20
local LOSS_QUIET_SECONDS = 1
local TICK_SECONDS = 1 -- the fallback's check rate

export type Moment = "Fusion" | "Pull" | "Daily"

-- The two calls we make on the Roblox service, so /selftest can swap in a stub.
export type Service = {
	CanPromptOptInAsync: (Service) -> boolean,
	PromptOptIn: (Service) -> (),
	OptInPromptClosed: RBXScriptSignal?,
}

local realService = ExperienceNotificationService :: any
local service: Service = realService
local tutorialActive: () -> boolean = TycoonController.IsTutorialActive
local clock: () -> number = os.clock -- /selftest swaps in a fake one
local realSessionStart = os.clock() -- the module loads when the client boots
local sessionStart = realSessionStart

local attempted = false -- the ask was made (or ruled out) this session
local pending = false -- an ask is waiting on its guards
local suppressed = false -- /selftest
local lastLossAt = -math.huge

local function noteLoss()
	lastLossAt = os.clock()
end

local function report(event: string)
	RemoteEvents.NotifyOptInAnalytics:FireServer({ Event = event })
end

local function overlayOpen(): boolean
	return UIKit.IsOverlayOpen() or ShopCards.IsSideOpen()
end

local function blocked(): boolean
	return overlayOpen() or os.clock() - lastLossAt < LOSS_QUIET_SECONDS
end

local function ask()
	local ok, canPrompt = pcall(function()
		return service:CanPromptOptInAsync()
	end)
	attempted = true
	if not ok or canPrompt ~= true then
		return
	end
	local shown = pcall(service.PromptOptIn, service)
	if not shown then
		return
	end
	report("Shown")
	local closedSignal = service.OptInPromptClosed
	if closedSignal then
		closedSignal:Once(function()
			report("Closed")
		end)
	end
end

-- Waits out the guards (up to WAIT_LIMIT_SECONDS), then asks.
local function startAsk()
	pending = true
	task.spawn(function()
		task.wait(SETTLE_SECONDS)
		local waited = SETTLE_SECONDS
		while blocked() and not tutorialActive() do
			if waited >= WAIT_LIMIT_SECONDS then
				attempted = true -- give up for this session
				pending = false
				return
			end
			task.wait(RETRY_SECONDS)
			waited += RETRY_SECONDS
		end
		pending = false
		if not suppressed and not tutorialActive() and not attempted then
			ask()
		end
	end)
end

local function sessionSeconds(): number
	return clock() - sessionStart
end

-- A high moment just ended (its card closed). Nothing before the session has
-- run MinSessionSeconds, none during the tutorial, a pull only from
-- MinPullTier up; the first one after that starts the ask.
function NotifyOptInController.OnMoment(kind: Moment, tier: string?)
	if attempted or pending or suppressed or tutorialActive() then
		return
	end
	if sessionSeconds() < NotifyConfig.MinSessionSeconds then
		return
	end
	if kind == "Pull" then
		local minRank = ItemConfig.Tiers[NotifyConfig.MinPullTier] or math.huge
		if (ItemConfig.Tiers[tier or ""] or 0) < minRank then
			return
		end
	end
	startAsk()
end

-- DailyCard: the card closed after a granted claim.
function NotifyOptInController.OnDailyRevealClosed()
	NotifyOptInController.OnMoment("Daily")
end

-- Once a second: no moment came by FallbackSeconds, so ask the next time no
-- overlay is open.
function NotifyOptInController.Tick()
	if attempted or pending or suppressed or tutorialActive() then
		return
	end
	if sessionSeconds() >= NotifyConfig.FallbackSeconds then
		startAsk()
	end
end

-- /selftest: while on, the real prompt never opens by itself.
function NotifyOptInController.SelfTestSuppress(on: boolean)
	suppressed = on
end

-- /selftest: swap in a stub service, a tutorial probe and a clock (seconds
-- of session play); nil puts the real ones back. Either way the session
-- starts fresh (not asked yet).
function NotifyOptInController.SetServiceForTest(stub: Service?, isTutorialActive: (() -> boolean)?, fakeClock: (() -> number)?)
	service = stub or realService
	tutorialActive = isTutorialActive or TycoonController.IsTutorialActive
	clock = fakeClock or os.clock
	sessionStart = if fakeClock then fakeClock() else realSessionStart
	attempted = false
	pending = false
	lastLossAt = -math.huge
end

function NotifyOptInController.Init()
	-- A failed fusion or a purchase prompt just happened: no ask in the same second.
	RemoteEvents.FusionResult.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and payload.Success == false then
			noteLoss()
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number)
		if userId == Players.LocalPlayer.UserId then
			noteLoss()
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(noteLoss)
	MarketplaceService.PromptPurchaseFinished:Connect(noteLoss)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			NotifyOptInController.Tick()
		end
	end)
end

return NotifyOptInController
