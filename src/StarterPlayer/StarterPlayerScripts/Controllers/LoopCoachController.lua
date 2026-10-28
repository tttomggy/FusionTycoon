--!strict
--[[
	LoopCoachController
	-------------------
	Closes the core loop out loud, at the three moments it happens. One
	TopStack line each (AnnouncementController.ShowLine: 2.5 s, the existing
	queue), once per session per kind, never during the tutorial:

	  NewOrb        a fusion succeeded and the new orb went on a pedestal:
	                "Your new orb earns $X/s more!"
	  MoreCash      the first time a pull is affordable AGAIN after a fuse:
	                "More cash = more pulls = more fusions!"
	  FreeOrb       the first rival steal delivered: "Free orb! Fuse it with yours."

	The IDLE NUDGE: never leave the player standing around with cash to burn.
	No pull, fuse, upgrade, steal or Multiplier purchase for 40 s (the clock
	also restarts whenever a tip, the steal mission box, a modal or the
	tutorial is up, so it never fires the moment one closes), cash for a pull
	and nothing else asking for attention -> one TopStack line and the arrow
	on the Gacha Pad (GoalMarkerController.SetNudge), cleared by the next
	action. A fusable pair + cash says both and points at the Fusion Machine
	first, then the Gacha Pad once the fuse landed. Once per idle spell, again
	after another 90 s idle, at most 3 a session, never the same line twice in
	a row. Broke with nothing to fuse is the coach's Earn line, not a nudge.

	The strip, the tracker's lines and the arrow are the HUD's and
	GoalMarkerController's (LoopCoach in GoalProgress.Coach); this controller
	only watches for the moments. The planning is pure (Plan*) so /selftest
	can run it.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local TipConfig = require(ReplicatedStorage.Shared.Config.TipConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local GoalSteps = require(ReplicatedStorage.Shared.Modules.GoalSteps)
local AnnouncementController = require(script.Parent.AnnouncementController)
local TycoonController = require(script.Parent.TycoonController)
local GoalMarkerController = require(script.Parent.GoalMarkerController)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local TopStack = require(script.Parent.Parent.UI.TopStack)

local LoopCoachController = {}

LoopCoachController.Lines = {
	MoreCash = "More cash = more pulls = more fusions!",
	FreeOrb = "Free orb! Fuse it with yours.",
}

-- A new orb on a pedestal has this long to show up in a sync after the fuse.
local NEW_ORB_WAIT_SECONDS = 6

type State = {
	Fired: { [string]: boolean }, -- kinds already announced this session
	PendingOrb: { Before: number, At: number }?, -- a fuse landed; waiting for the pedestal
	AfterFuse: boolean, -- a fuse landed, MoreCash not yet announced
	SawBroke: boolean, -- ... and a pull was unaffordable since
}

local state: State = { Fired = {}, PendingOrb = nil, AfterFuse = false, SawBroke = false }

--[[ Pure planning ------------------------------------------------------------- ]]

function LoopCoachController.NewOrbLine(gain: number): string
	return ("Your new orb earns %s/s more!"):format(NumberFormat.Money(gain))
end

-- The first sync after a fuse whose pedestal income went up: the NewOrb line.
-- A fuse whose orb never reached a pedestal gives up after NEW_ORB_WAIT_SECONDS.
-- Returns (line to announce, pending to keep).
function LoopCoachController.PlanNewOrb(
	pending: { Before: number, At: number }?,
	income: number,
	now: number,
	alreadyFired: boolean
): (string?, { Before: number, At: number }?)
	if not pending then
		return nil, nil
	end
	if income > pending.Before + 1e-9 then
		return if alreadyFired then nil else LoopCoachController.NewOrbLine(income - pending.Before), nil
	end
	if now - pending.At > NEW_ORB_WAIT_SECONDS then
		return nil, nil
	end
	return nil, pending
end

-- After a fuse: the first time a pull is affordable again (it was not, at
-- some sync since). Returns (announce, sawBroke).
function LoopCoachController.PlanMoreCash(afterFuse: boolean, sawBroke: boolean, canAffordPull: boolean): (boolean, boolean)
	if not afterFuse then
		return false, false
	end
	if not canAffordPull then
		return false, true
	end
	return sawBroke, sawBroke
end

-- The earnBoth announce: after the tutorial, once per account, when an orb is
-- displayed AND some generator was upgraded past its first level (the Basic
-- Generator starts at LV 1, so the level sum is 1 until the first upgrade).
function LoopCoachController.PlanEarnBoth(tutorialDone: boolean, seen: boolean, displayedOrbs: number, generatorLevelSum: number): boolean
	return tutorialDone and not seen and displayedOrbs >= 1 and generatorLevelSum >= 2
end

--[[ Live ---------------------------------------------------------------------- ]]

local function pedestalIncome(): number
	local inputs = TycoonController.GetIncomeInputs()
	local total = 0
	for _, item in inputs.PedestalItems do
		total += TycoonConfig.GetStackCashPerSecond(item)
	end
	return total * TycoonConfig.GetIncomeMultiplier(inputs)
end

local function announce(kind: string, text: string)
	state.Fired[kind] = true
	AnnouncementController.ShowLine(text, "Loop" .. kind)
end

local function checkEarnBoth()
	if not TycoonController.HasSynced() then
		return
	end
	local levelSum = 0
	for _, level in TycoonController.GetGeneratorLevels() do
		levelSum += level
	end
	local seen = TycoonController.HasSeenTip("earnBoth")
	if LoopCoachController.PlanEarnBoth(TycoonController.GetTutorial().Done, seen, #TycoonController.GetIncomeInputs().PedestalItems, levelSum) then
		TycoonController.MarkTipSeen("earnBoth")
		AnnouncementController.ShowLine(TipConfig.EarnBothLine, "LoopEarnBoth")
	end
end

local function onTycoonChanged()
	if TycoonController.IsTutorialActive() then
		return
	end
	checkEarnBoth()
	local line, pending = LoopCoachController.PlanNewOrb(state.PendingOrb, pedestalIncome(), os.clock(), state.Fired.NewOrb == true)
	state.PendingOrb = pending
	if line then
		announce("NewOrb", line)
	end
	if state.Fired.MoreCash ~= true then
		local say, saw = LoopCoachController.PlanMoreCash(state.AfterFuse, state.SawBroke, TycoonController.CanAffordPull())
		state.SawBroke = saw
		if say then
			state.AfterFuse = false
			announce("MoreCash", LoopCoachController.Lines.MoreCash)
		end
	end
end

local function onFusionResult(payload: any)
	if typeof(payload) ~= "table" or payload.Success ~= true or TycoonController.IsTutorialActive() then
		return
	end
	-- Before the sync that carries the new pedestal.
	if payload.Upgraded == true and state.Fired.NewOrb ~= true then
		state.PendingOrb = { Before = pedestalIncome(), At = os.clock() }
	end
	if state.Fired.MoreCash ~= true then
		state.AfterFuse = true
		state.SawBroke = not TycoonController.CanAffordPull()
	end
end

local function onHeistEnded(payload: any)
	if typeof(payload) ~= "table" or TycoonController.IsTutorialActive() then
		return
	end
	if payload.Role == "Thief" and payload.Outcome == "Delivered" and payload.Rival == true and state.Fired.FreeOrb ~= true then
		announce("FreeOrb", LoopCoachController.Lines.FreeOrb)
	end
end

--[[ Idle nudge --------------------------------------------------------------- ]]

LoopCoachController.NudgeIdleSeconds = 40
LoopCoachController.NudgeRepeatSeconds = 90
LoopCoachController.NudgeMax = 3
LoopCoachController.NudgeLines = {
	"Pull more orbs! More orbs → fuse them → more cash every second.",
	"Orbs make your cash: pull more at the Gacha Pad!",
	"Keep pulling! Every orb you fuse earns more every second.",
} :: { string }

export type Nudger = {
	LastAction: number, -- the clock at the last pull / fuse / upgrade / steal / Multiplier buy
	SpellNudges: number, -- nudges since that action
	LastNudgeAt: number,
	Total: number, -- this session
	LastLine: string?,
	Target: string?, -- the arrow: "GachaStation" | "FusionMachine" | nil
}

export type NudgeInput = {
	Blocked: boolean, -- tutorial, a tip, the steal mission box, a modal, a carried orb
	CanPull: boolean, -- cash for the next pull
	FuseTier: string?, -- a fusable pair (the coach's Fuse step) ...
	FuseCount: number?, -- ... and how many
}

export type Nudge = { Line: string, Target: string }

function LoopCoachController.NewNudger(now: number): Nudger
	return { LastAction = now, SpellNudges = 0, LastNudgeAt = -math.huge, Total = 0, LastLine = nil, Target = nil }
end

-- A pull, fuse, upgrade, steal or Multiplier purchase: the spell starts
-- over and the arrow goes, except a fuse during the pair nudge, which
-- sends the arrow on to the Gacha Pad.
function LoopCoachController.NudgeAction(nudger: Nudger, now: number, kind: string)
	nudger.LastAction = now
	nudger.SpellNudges = 0
	if kind == "Fuse" and nudger.Target == "FusionMachine" then
		nudger.Target = "GachaStation"
	else
		nudger.Target = nil
	end
end

-- The line for this input, never the one just shown.
local function pickNudgeLine(nudger: Nudger, input: NudgeInput): string
	local candidates: { string } = {}
	local tier = input.FuseTier
	if tier then
		table.insert(candidates, ("Fuse your %d %s, then pull more orbs for the next fuse!"):format(input.FuseCount or 2, GoalSteps.TierWord(tier, true)))
	end
	for _, line in LoopCoachController.NudgeLines do
		table.insert(candidates, line)
	end
	for _, line in candidates do
		if line ~= nudger.LastLine then
			return line
		end
	end
	return candidates[1]
end

-- One look at the clock: the nudge to show now, or nil. Mutates `nudger`.
-- Blocked time restarts the idle clock (a closed shop is not "idle").
function LoopCoachController.NudgeTick(nudger: Nudger, now: number, input: NudgeInput): Nudge?
	if input.Blocked then
		nudger.LastAction = now
		nudger.Target = nil
		return nil
	end
	if nudger.Total >= LoopCoachController.NudgeMax or not input.CanPull then
		return nil
	end
	if now - nudger.LastAction < LoopCoachController.NudgeIdleSeconds then
		return nil
	end
	if nudger.SpellNudges > 0 and now - nudger.LastNudgeAt < LoopCoachController.NudgeRepeatSeconds then
		return nil
	end
	local line = pickNudgeLine(nudger, input)
	local target = if input.FuseTier then "FusionMachine" else "GachaStation"
	nudger.Total += 1
	nudger.SpellNudges += 1
	nudger.LastNudgeAt = now
	nudger.LastLine = line
	nudger.Target = target
	return { Line = line, Target = target }
end

local nudger = LoopCoachController.NewNudger(os.clock())
local activitySignature: string? = nil

-- Pulls, generator levels, the Multiplier level and a carried orb: any
-- change is a player action.
local function liveSignature(): (string, string)
	local levelSum = 0
	for _, level in TycoonController.GetGeneratorLevels() do
		levelSum += level
	end
	local carrying = Players.LocalPlayer:GetAttribute("HeistTier") ~= nil
	local pulls = TycoonController.GetGachaPulls()
	local rest = ("%d|%d|%s"):format(levelSum, TycoonController.GetCashMultiplierLevel(), tostring(carrying))
	return tostring(pulls), rest
end

local function nudgeBlocked(): boolean
	return not TycoonController.HasSynced()
		or not TycoonController.GetTutorial().Done
		or UIKit.IsOverlayOpen()
		or GoalMarkerController.IsTipActive()
		or TopStack.IsMissionShown()
		or Players.LocalPlayer:GetAttribute("HeistTier") ~= nil
end

local function nudgeFrame()
	local now = os.clock()
	local pulls, rest = liveSignature()
	local signature = pulls .. "/" .. rest
	if activitySignature ~= nil and signature ~= activitySignature then
		local before = activitySignature
		activitySignature = signature
		local oldPulls = before:match("^[^/]*")
		LoopCoachController.NudgeAction(nudger, now, if oldPulls ~= pulls then "Pull" else "Upgrade")
	end
	activitySignature = signature
	local progress = TycoonController.GetGoalProgress()
	local coach = if progress then progress.Coach else nil
	local fuse = coach ~= nil and coach.Step == "Fuse"
	local nudge = LoopCoachController.NudgeTick(nudger, now, {
		Blocked = nudgeBlocked(),
		CanPull = TycoonController.CanAffordPull(),
		FuseTier = if fuse and coach then coach.Tier else nil,
		FuseCount = if fuse and coach then coach.Count else nil,
	})
	if nudge then
		AnnouncementController.ShowLine(nudge.Line, "LoopNudge")
	end
	GoalMarkerController.SetNudge(nudger.Target)
end

-- /selftest: the live nudger's state.
function LoopCoachController.GetNudger(): Nudger
	return nudger
end

function LoopCoachController.Init()
	RemoteEvents.FusionResult.OnClientEvent:Connect(onFusionResult)
	RemoteEvents.HeistEnded.OnClientEvent:Connect(onHeistEnded)
	TycoonController.TycoonChanged:Connect(onTycoonChanged)
	-- A fuse (single or Fuse All) is an action whatever its outcome.
	local function fused()
		LoopCoachController.NudgeAction(nudger, os.clock(), "Fuse")
	end
	RemoteEvents.FusionResult.OnClientEvent:Connect(fused)
	RemoteEvents.FuseAllResult.OnClientEvent:Connect(fused)
	task.spawn(function()
		while true do
			task.wait(0.5)
			nudgeFrame()
		end
	end)
end

return LoopCoachController
