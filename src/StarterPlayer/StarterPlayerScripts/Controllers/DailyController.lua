--!strict
--[[
	DailyController
	---------------
	When the daily reward card opens, and the ClaimDaily round trip.

	  * Once per session, when the snapshot says today's reward can be
	    claimed (Daily.CanClaim), after the welcome-back card has had its
	    turn: it waits OPEN_DELAY_SECONDS after the first sync, then until
	    no other card is open (UIKit overlays, the shop's side cards), so it
	    is never stacked on another card.
	  * DailyController.Open() reopens it (the Gifts panel's daily row).
	  * DailyResult: Granted plays the reveal; Refused toasts.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonController = require(script.Parent.TycoonController)
local ToastController = require(script.Parent.ToastController)
local ShopController = require(script.Parent.ShopController)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ShopCards = require(script.Parent.Parent.UI.ShopCards)
local DailyCard = require(script.Parent.Parent.UI.DailyCard)

local DailyController = {}

local OPEN_DELAY_SECONDS = 2
local RETRY_SECONDS = 0.5
local ANSWER_TIMEOUT_SECONDS = 6

local REFUSALS: { [string]: string } = {
	Claimed = "Already claimed today. Come back tomorrow!",
	NotReady = "Your lab is still loading, try again",
	NotLoaded = "Your lab is still loading, try again",
}

local autoOpened = false
local lastCanClaim = false
local claimSentAt = 0

function DailyController.CanClaim(): boolean
	return TycoonController.HasSynced() and TycoonController.GetDaily().CanClaim
end

function DailyController.Open()
	if DailyController.CanClaim() and not DailyCard.IsOpen() then
		DailyCard.Open(TycoonController.GetDaily())
	end
end

local function tryAutoOpen()
	local canClaim = DailyController.CanClaim()
	if canClaim and not lastCanClaim then
		-- A new claimable day (a new session, or /daily in Studio).
		autoOpened = false
	end
	lastCanClaim = canClaim
	if autoOpened or not canClaim then
		return
	end
	autoOpened = true
	task.spawn(function()
		task.wait(OPEN_DELAY_SECONDS)
		while UIKit.IsOverlayOpen() or ShopCards.IsSideOpen() do
			task.wait(RETRY_SECONDS)
		end
		DailyController.Open()
	end)
end

local function onDailyResult(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	claimSentAt = 0
	if payload.Result == "Granted" then
		local lines = if typeof(payload.Lines) == "table" then payload.Lines else {}
		DailyCard.ShowReveal(TycoonController.GetDaily(), {
			Day = if typeof(payload.Day) == "number" then payload.Day else 1,
			Streak = if typeof(payload.Streak) == "number" then payload.Streak else 1,
			Kind = if typeof(payload.Kind) == "string" then payload.Kind else "",
			Lines = lines,
		})
	else
		local reason = if typeof(payload.Reason) == "string" then payload.Reason else ""
		ToastController.Show(REFUSALS[reason] or "Couldn't claim that, try again", "Error")
		if reason == "Claimed" then
			DailyCard.Close()
		else
			DailyCard.ResetClaim(TycoonController.GetDaily())
		end
	end
end

local function claim()
	claimSentAt = os.clock()
	local sentAt = claimSentAt
	RemoteEvents.ClaimDaily:FireServer()
	task.delay(ANSWER_TIMEOUT_SECONDS, function()
		if claimSentAt == sentAt then
			claimSentAt = 0
			DailyCard.ResetClaim(TycoonController.GetDaily())
		end
	end)
end

function DailyController.Init()
	DailyCard.Init({
		OnClaim = claim,
		BaseIncome = ShopController.GetBaseIncome,
	})
	RemoteEvents.DailyResult.OnClientEvent:Connect(onDailyResult)
	TycoonController.TycoonChanged:Connect(tryAutoOpen)
end

return DailyController
