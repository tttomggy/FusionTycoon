--!strict
--[[
	NotifyOptInController
	---------------------
	Asks the player, once per session, to opt in to Roblox experience
	notifications. The ask is Roblox's own modal (PromptOptIn); we add no
	card before it.

	  * When: right after the daily reward card closes from a granted claim
	    (DailyCard's OnRevealClosed), the "come back tomorrow" moment.
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

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonController = require(script.Parent.TycoonController)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ShopCards = require(script.Parent.Parent.UI.ShopCards)

local NotifyOptInController = {}

local SETTLE_SECONDS = 0.5
local RETRY_SECONDS = 0.5
local WAIT_LIMIT_SECONDS = 20
local LOSS_QUIET_SECONDS = 1

-- The two calls we make on the Roblox service, so /selftest can swap in a stub.
export type Service = {
	CanPromptOptInAsync: (Service) -> boolean,
	PromptOptIn: (Service) -> (),
	OptInPromptClosed: RBXScriptSignal?,
}

local realService = ExperienceNotificationService :: any
local service: Service = realService
local tutorialActive: () -> boolean = TycoonController.IsTutorialActive

local attempted = false -- the ask was made (or ruled out) this session
local pending = false -- a reveal close is waiting on its guards
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

-- DailyCard: the card closed after a granted claim.
function NotifyOptInController.OnDailyRevealClosed()
	if attempted or pending or suppressed or tutorialActive() then
		return
	end
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

-- /selftest: while on, the real prompt never opens by itself.
function NotifyOptInController.SelfTestSuppress(on: boolean)
	suppressed = on
end

-- /selftest: swap in a stub service (and a tutorial probe); nil puts the real
-- ones back. Either way the session starts fresh (not asked yet).
function NotifyOptInController.SetServiceForTest(stub: Service?, isTutorialActive: (() -> boolean)?)
	service = stub or realService
	tutorialActive = isTutorialActive or TycoonController.IsTutorialActive
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
end

return NotifyOptInController
