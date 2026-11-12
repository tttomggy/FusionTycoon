--!strict
--[[
	ComeBackController
	------------------
	When the "come back tomorrow" card (UI/ComeBackCard) opens: ONE card, once
	per account, in the player's first session (RetentionConfig.ComeBack and
	the pure RetentionConfig.ShouldShowComeBack).

	  * From MinSeconds (150 s) of this visit's play, at the first natural pause:
	    OnMoment(), called when a big result card closes (ResultController: a
	    fusion, a pull), the daily reveal closes (DailyController) or a rival
	    steal is delivered (HeistController).
	  * From FallbackSeconds (240 s, ~4 min; the average first session was 4.6
	    min) the next time the screen is quiet (Tick, once a second).
	  * Never during the tutorial, while a card / panel / shop side card is open,
	    while carrying an orb, ragdolled or frozen.
	  * It shows the real numbers: tomorrow's daily reward and the next ones
	    (DailyConfig), today's if it still waits (the button then opens the daily
	    card), what the lab earns while away (the server's OfflineMax).
	  * Opening reports ComeBackShown { Event = "Shown" } (the server re-checks,
	    saves the comeBack tip and logs it); the card never opens twice in a
	    session either way.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RetentionConfig = require(ReplicatedStorage.Shared.Config.RetentionConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonController = require(script.Parent.TycoonController)
local DailyController = require(script.Parent.DailyController)
local HeistController = require(script.Parent.HeistController)
local ResultController = require(script.Parent.ResultController)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ShopCards = require(script.Parent.Parent.UI.ShopCards)
local ComeBackCard = require(script.Parent.Parent.UI.ComeBackCard)

local ComeBackController = {}

local TICK_SECONDS = 1
local MOMENT_WINDOW_SECONDS = 20 -- a moment counts as "just happened" this long (the card waits for quiet)

local localPlayer = Players.LocalPlayer
local shown = false -- opened (or reported) this session
local suppressed = false -- /selftest
local momentAt = -math.huge

-- Carrying an orb, ragdolled or frozen: not a pause.
local function isBusy(): boolean
	if localPlayer:GetAttribute("HeistTier") ~= nil then
		return true
	end
	local now = Workspace:GetServerTimeNow()
	for _, name in { "RagdollUntil", "FrozenUntil" } do
		local untilTime = localPlayer:GetAttribute(name)
		if typeof(untilTime) == "number" and untilTime > now then
			return true
		end
	end
	return false
end

local function isQuiet(): boolean
	return not UIKit.IsOverlayOpen() and not ShopCards.IsSideOpen()
end

-- The rule's input, from the live client state.
function ComeBackController.GetState(): RetentionConfig.ComeBackState
	return {
		Seen = shown or TycoonController.HasSeenTip(RetentionConfig.ComeBack.TipId),
		Sessions = TycoonController.GetShop().Sessions,
		TutorialActive = TycoonController.IsTutorialActive(),
		PlaySeconds = TycoonController.GetGiftPlaySeconds(),
		Moment = os.clock() - momentAt <= MOMENT_WINDOW_SECONDS,
		Quiet = isQuiet(),
		Busy = isBusy(),
	}
end

-- The card's content right now (the snapshot's daily status, the server's
-- offline number).
function ComeBackController.GetPlan(): RetentionConfig.ComeBackPlan
	local daily = TycoonController.GetDaily()
	return RetentionConfig.PlanComeBack({ CanClaim = daily.CanClaim, Day = daily.Day }, TycoonController.GetOfflineMax())
end

local function open()
	shown = true
	ComeBackCard.Open(ComeBackController.GetPlan())
	RemoteEvents.ComeBackShown:FireServer({ Event = "Shown" })
end

local function evaluate()
	if shown or suppressed or not TycoonController.HasSynced() then
		return
	end
	if RetentionConfig.ShouldShowComeBack(ComeBackController.GetState()) then
		open()
	end
end

-- A natural pause just happened (a big card closed, a steal landed). The card
-- opens at once if the rule allows, else Tick tries while the moment is fresh.
function ComeBackController.OnMoment()
	momentAt = os.clock()
	task.defer(evaluate)
end

function ComeBackController.Tick()
	evaluate()
end

-- /selftest: while on, the card never opens by itself.
function ComeBackController.SelfTestSuppress(on: boolean)
	suppressed = on
end

-- /selftest (client probe): the card opened with a plan is placed in the card
-- band and shows the plan's lines; then closed. The card's own layout only.
function ComeBackController.SelfTestOpen(plan: RetentionConfig.ComeBackPlan): ({ Main: { string }, Button: string }?, { TextLabel })
	ComeBackCard.Open(plan)
	return ComeBackCard.GetShown(), ComeBackCard.GetLabels()
end

function ComeBackController.SelfTestClose()
	ComeBackCard.Close()
end

type ProbeLine = { Ok: boolean, Name: string, Detail: string? }

-- /selftest (client probe "ComeBack"): the pure rule case by case, the plan for
-- a Day 1 player, then the real card opened with a plan: its lines, its button,
-- centred in the card band (UIKit.CheckCardPlacement) and every label's text
-- fitting; closed again. Never reports ComeBackShown (SelfTestOpen).
function ComeBackController.SelfTestProbe(): { ProbeLine }
	local lines: { ProbeLine } = {}
	local function check(ok: boolean, name: string, detail: string?)
		table.insert(lines, { Ok = ok, Name = "come-back card: " .. name, Detail = detail })
	end
	local rule = RetentionConfig.ComeBack
	local function state(overrides: { [string]: any }): RetentionConfig.ComeBackState
		local base: { [string]: any } = {
			Seen = false,
			Sessions = 1,
			TutorialActive = false,
			PlaySeconds = rule.MinSeconds + 10,
			Moment = true,
			Quiet = true,
			Busy = false,
		}
		for key, value in overrides do
			base[key] = value
		end
		return base :: any
	end
	local cases: { { any } } = {
		{ "a pause after MinSeconds in the first session shows it", {}, true },
		{ "not before MinSeconds", { PlaySeconds = rule.MinSeconds - 10 }, false },
		{ "no pause before FallbackSeconds: waits", { Moment = false }, false },
		{ "FallbackSeconds with a quiet screen shows it", { Moment = false, PlaySeconds = rule.FallbackSeconds }, true },
		{ "never over another card", { Moment = false, PlaySeconds = rule.FallbackSeconds, Quiet = false }, false },
		{ "never while carrying / ragdolled", { PlaySeconds = rule.FallbackSeconds, Busy = true }, false },
		{ "never during the tutorial", { PlaySeconds = rule.FallbackSeconds, TutorialActive = true }, false },
		{ "never twice (seen)", { PlaySeconds = rule.FallbackSeconds, Seen = true }, false },
		{ "never in a later session", { PlaySeconds = rule.FallbackSeconds, Sessions = 2 }, false },
	}
	for _, case in cases do
		local got = RetentionConfig.ShouldShowComeBack(state(case[2]))
		check(got == case[3], case[1], ("got %s"):format(tostring(got)))
	end
	local plan = RetentionConfig.PlanComeBack({ CanClaim = true, Day = 1 }, 1_040_000)
	check(
		plan.TomorrowDay == 2 and plan.TodayWaiting and plan.TodayDay == 1 and #plan.Later == 2 and plan.Later[1].Day == 3 and plan.Later[2].Day == 7,
		"a Day 1 player's plan: tomorrow Day 2, today's waiting, then Day 3 and Day 7",
		("tomorrow %d, later %d"):format(plan.TomorrowDay, #plan.Later)
	)
	local ok, err = pcall(function()
		local shownCard, labels = ComeBackController.SelfTestOpen(plan)
		task.wait(0.4) -- PopIn
		local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat) :: any
		local money = NumberFormat.Money(1_040_000)
		check(
			shownCard ~= nil and #shownCard.Main == 3 and string.find(shownCard.Main[2], money, 1, true) ~= nil,
			"the card shows tomorrow's reward and the real offline number",
			if shownCard then table.concat(shownCard.Main, " | ") else "not open"
		)
		check(shownCard ~= nil and shownCard.Button == "CLAIM TODAY'S REWARD", "today's reward waiting: the button claims it", if shownCard then shownCard.Button else nil)
		local unfit: { string } = {}
		for _, label in labels do
			if label.Text ~= "" and not label.TextFits then
				table.insert(unfit, label.Name .. " '" .. label.Text .. "'")
			end
		end
		check(#unfit == 0, "every line fits", table.concat(unfit, "; "))
		-- Placement: the panel + its shadow in the card band, centred.
		local GuiService = game:GetService("GuiService")
		local placed: string? = "the modal was not found"
		for _, gui in UIKit.GetModalGuis() do
			local root = if gui.Name == "ComeBack" and gui.Enabled then gui:FindFirstChild("Root") else nil
			local panel = root and root:FindFirstChild("Panel")
			local body = panel and panel:FindFirstChild("Body")
			if panel and body and body:IsA("GuiObject") then
				local mobile = gui:FindFirstChild("MobileScale")
				local scale = if mobile and mobile:IsA("UIScale") then mobile.Scale else 1
				local inset = GuiService:GetGuiInset().Y
				local top = body.AbsolutePosition.Y + inset
				local bottom = top + body.AbsoluteSize.Y
				local shadow = panel:FindFirstChild("Shadow")
				if shadow and shadow:IsA("GuiObject") and shadow.Visible then
					bottom = math.max(bottom, shadow.AbsolutePosition.Y + inset + shadow.AbsoluteSize.Y)
				end
				placed = UIKit.CheckCardPlacement(top / scale, (bottom - top) / scale, UIKit.GetLogicalViewport().Y, UIKit.IsPhone())
			end
		end
		check(placed == nil, "centred in the card band", placed)
		ComeBackController.SelfTestClose()
		task.wait(0.4)
		check(not ComeBackCard.IsOpen(), "closes")
		local claimed = RetentionConfig.PlanComeBack({ CanClaim = false, Day = 1 }, 0)
		check(ComeBackCard.ActionText(claimed) == "GOT IT" and claimed.TomorrowDay == 2, "today's claimed: GOT IT, tomorrow still Day 2")
	end)
	if not ok then
		check(false, "probe errored", tostring(err))
		ComeBackController.SelfTestClose()
	end
	return lines
end

function ComeBackController.Init()
	ComeBackCard.Init({
		OnClaimToday = function()
			task.delay(0.3, DailyController.Open)
		end,
	})
	DailyController.OnRevealClosed(ComeBackController.OnMoment)
	ResultController.SetMomentHook(ComeBackController.OnMoment)
	HeistController.SetDeliveryHook(ComeBackController.OnMoment)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			xpcall(ComeBackController.Tick, function(err: any)
				warn("ComeBackController: " .. tostring(err))
			end)
		end
	end)
end

return ComeBackController
