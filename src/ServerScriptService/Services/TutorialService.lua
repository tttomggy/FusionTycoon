--!strict
--[[
	TutorialService
	---------------
	The mandatory first-time tutorial (TutorialConfig.Steps, Tutorial 2).
	Server-owned: the step lives in PlayerData.Tutorial and goes out in
	every snapshot.

	  * Action steps complete only on the real, server-confirmed action: a
	    PlayerDataService.OnSync hook checks the step's predicate at the
	    start of every sync (claim, an upgrade, each of the 2 pulls, a
	    fusion, the Multiplier Pad), so the next step ships in that same
	    snapshot.
	  * Timed / Open steps (and the Multiplier Pad's "come back with $X")
	    complete through the remote TutorialAdvance { Step } (C->S),
	    re-checked here: the step must be the current one, and a Timed step
	    needs its Seconds on the server's clock (a step the server has only
	    just seen is refused once, then timed from there). Open steps are a
	    UI the server can't watch (the chip, the Rebirth panel), so they are
	    allowed any time: the worst a lie does is skip a sentence.
	    TutorialAdvance { Replay = true } restarts it from Settings: a replay
	    has no free pulls / guaranteed fusion again and every step may be
	    left with the banner's SKIP.
	  * Entering a step: the Pull step grants the 2 free pulls (once per
	    account; the pad takes them, PlayerDataService.TakeTutorialFreePull);
	    Action steps record the counter they wait on (Base). Steps the save
	    already satisfies (Skip) are skipped.
	  * Step 0 (a new field on an old save) is decided on the first sync: a
	    save with real progress (Rebirth >= 1 or > 20 pulls) is Done with a
	    one-time "replay it in ⚙" hint; anything else starts at step 1. A
	    save from Tutorial 1 has its step mapped (PlayerDataService).
	  * Analytics: Custom "TutorialStep" (the step number) on each completed
	    step, "TutorialDone" at the end.

	Follows the ServiceTemplate contract: :Init() connects the remote,
	:Start() resolves PlayerDataService / TycoonService and hooks the sync.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)
local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))

local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule

local TutorialService = {}
TutorialService.Name = "TutorialService"

local ADVANCE_PER_SECOND = 2
local ADVANCE_BURST = 4
local TIMED_SLACK = 0.5 -- the client's timer and the server's clock may differ a little

-- os.clock() each player's current step began (session only). A step the
-- server hasn't seen begin (a resume) is timed from its first Advance.
local enteredAt: { [Player]: number } = {}

--[[ Counters and predicates ------------------------------------------------ ]]

local function generatorLevels(player: Player): number
	local total = 0
	local generators: { [string]: number } = PlayerDataService.GetGenerators(player) or {}
	for _, level in generators do
		total += level
	end
	return total
end

local function pullCount(player: Player): number
	local data = PlayerDataService.GetData(player)
	return if data then data.GachaPulls + data.FreePulls else 0
end

local function isClaimed(player: Player): boolean
	local plot = TycoonService.GetPlotForPlayer(player)
	return plot ~= nil and plot:GetAttribute("Claimed") == true
end

-- The counter an Action step waits on (recorded as Base when it starts).
local COUNTERS: { [string]: (Player) -> number } = {
	upgrade = generatorLevels,
	pull = pullCount,
	pull2 = pullCount,
	fuse = function(player: Player): number
		return PlayerDataService.GetTotalFusions(player)
	end,
}

-- Done? for each Action step, from the real state.
local PREDICATES: { [string]: (Player, number) -> boolean } = {
	claim = function(player)
		return isClaimed(player)
	end,
	upgrade = function(player, base)
		return generatorLevels(player) > base
	end,
	pull = function(player, base)
		return pullCount(player) > base
	end,
	pull2 = function(player, base)
		return pullCount(player) > base
	end,
	fuse = function(player, base)
		return PlayerDataService.GetTotalFusions(player) > base
	end,
	multiplier = function(player)
		return PlayerDataService.GetCashMultiplierLevel(player) >= 1
	end,
}

-- Already true on this save: the step is skipped on entry.
local SKIPS: { [string]: (Player) -> boolean } = {
	Claimed = isClaimed,
	Upgraded = function(player)
		local generators: { [string]: number } = PlayerDataService.GetGenerators(player) or {}
		return (generators["basic_generator"] or 0) >= 2
	end,
	MultiplierBought = function(player)
		return PlayerDataService.GetCashMultiplierLevel(player) >= 1
	end,
}

--[[ Steps ------------------------------------------------------------------- ]]

local function tutorialOf(player: Player): any
	local data = PlayerDataService.GetData(player)
	return data and data.Tutorial
end

-- Starts step `index` (or finishes when past the last); skips satisfied
-- ones. Never syncs.
local function enter(player: Player, t: any, index: number)
	for _ = 1, #TutorialConfig.Steps + 1 do
		local step = TutorialConfig.GetStep(index)
		if not step then
			t.Done = true
			t.Step = #TutorialConfig.Steps
			t.Replay = false
			AnalyticsKit.Custom(player, "TutorialDone")
			return
		end
		t.Step = index
		local skip = step.Skip and SKIPS[step.Skip]
		if skip and skip(player) then
			index += 1
		else
			local counter = COUNTERS[step.Id]
			t.Base = if counter then counter(player) else 0
			if step.Id == "pull" and not t.PullsGranted and not t.Replay then
				t.PullsGranted = true
				t.FreePulls = TutorialConfig.FreePulls
			end
			return
		end
	end
end

local function complete(player: Player, t: any)
	AnalyticsKit.Custom(player, "TutorialStep", t.Step)
	enter(player, t, t.Step + 1)
end

-- The sync hook: decide a new field, then complete Action steps whose real
-- action happened (bounded: a chain of satisfied steps can't spin).
local function check(player: Player)
	local data = PlayerDataService.GetData(player)
	local t = data and data.Tutorial
	if not data or not t or t.Done then
		return
	end
	if t.Step == 0 then
		if data.Rebirths >= TutorialConfig.ProgressRebirths or data.GachaPulls > TutorialConfig.ProgressPulls then
			t.Done = true
			t.ReplayHint = true
			return
		end
		enter(player, t, 1)
	end
	for _ = 1, #TutorialConfig.Steps do
		local step = TutorialConfig.GetStep(t.Step)
		if not step or t.Done or step.Kind ~= "Action" then
			return
		end
		local predicate = PREDICATES[step.Id]
		if not predicate or not predicate(player, t.Base) then
			return
		end
		complete(player, t)
	end
end

-- The remote's rules (also what /selftest drives): true if it advanced.
function TutorialService.Advance(player: Player, stepIndex: number): boolean
	local t = tutorialOf(player)
	if not t or t.Done or stepIndex ~= t.Step then
		return false
	end
	local step = TutorialConfig.GetStep(stepIndex)
	if not step then
		return false
	end
	local began = enteredAt[player]
	if not began then
		-- A resumed step: time it from now (the client asks again).
		enteredAt[player] = os.clock()
		return false
	end
	local elapsed = os.clock() - began
	local allowed = false
	if t.Replay then
		allowed = true -- SKIP
	elseif step.Kind == "Open" then
		allowed = true
	elseif step.Kind == "Timed" then
		allowed = elapsed >= (step.Seconds or 0) - TIMED_SLACK
	elseif step.Id == "multiplier" then
		-- Out of reach right now ("Come back with $X"): leave after SkipSeconds.
		local cost = TycoonConfig.GetCashMultiplierUpgradeCost(PlayerDataService.GetCashMultiplierLevel(player))
		allowed = cost ~= nil
			and PlayerDataService.GetCash(player) < cost
			and elapsed >= (step.SkipSeconds or 0) - TIMED_SLACK
	end
	if not allowed then
		return false
	end
	complete(player, t)
	return true
end

-- Settings' "Replay tutorial": every step again, each with a SKIP.
function TutorialService.Replay(player: Player)
	local t = tutorialOf(player)
	if not t then
		return
	end
	t.Done = false
	t.Replay = true
	t.ReplayHint = false
	enter(player, t, 1)
end

function TutorialService.IsActive(player: Player): boolean
	local t = tutorialOf(player)
	return t ~= nil and not t.Done
end

-- Studio /tutorial reset | step <n>, and the admin panel's RESTART TUTORIAL.
function TutorialService.DebugReset(player: Player)
	local t = tutorialOf(player)
	if not t then
		return
	end
	t.Done = false
	t.Replay = false
	t.ReplayHint = false
	t.FreeFuse = false
	t.PullsGranted = false
	t.FreePulls = 0
	enter(player, t, 1)
end

-- /selftest: as if the current step had begun `seconds` ago (Timed steps).
function TutorialService.DebugBackdate(player: Player, seconds: number)
	enteredAt[player] = os.clock() - seconds
end

function TutorialService.DebugSetStep(player: Player, index: number)
	local t = tutorialOf(player)
	if not t then
		return
	end
	t.Done = false
	enter(player, t, math.clamp(math.floor(index), 1, #TutorialConfig.Steps))
end

local function onAdvance(player: Player, payload: unknown)
	if not RemoteGuard.Allow(player, "TutorialAdvance", ADVANCE_PER_SECOND, ADVANCE_BURST) then
		return
	end
	if typeof(payload) ~= "table" or not PlayerDataService.IsDataLoaded(player) then
		return
	end
	local p = payload :: any
	if p.Replay == true then
		TutorialService.Replay(player)
		PlayerDataService.SyncTycoon(player)
		return
	end
	local step = RemoteGuard.Int(p.Step, 1, #TutorialConfig.Steps)
	if step and TutorialService.Advance(player, step) then
		PlayerDataService.SyncTycoon(player)
	end
end

function TutorialService:Init()
	RemoteEvents.TutorialAdvance.OnServerEvent:Connect(onAdvance)
	Players.PlayerRemoving:Connect(function(player: Player)
		enteredAt[player] = nil
	end)
end

function TutorialService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)
	PlayerDataService.OnSync(check)
end

return TutorialService
