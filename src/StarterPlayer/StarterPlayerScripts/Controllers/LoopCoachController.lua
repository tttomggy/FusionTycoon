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

	The strip, the tracker's lines and the arrow are the HUD's and
	GoalMarkerController's (LoopCoach in GoalProgress.Coach); this controller
	only watches for the moments. The planning is pure (Plan*) so /selftest
	can run it.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local AnnouncementController = require(script.Parent.AnnouncementController)
local TycoonController = require(script.Parent.TycoonController)

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

local function onTycoonChanged()
	if TycoonController.IsTutorialActive() then
		return
	end
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

function LoopCoachController.Init()
	RemoteEvents.FusionResult.OnClientEvent:Connect(onFusionResult)
	RemoteEvents.HeistEnded.OnClientEvent:Connect(onHeistEnded)
	TycoonController.TycoonChanged:Connect(onTycoonChanged)
end

return LoopCoachController
