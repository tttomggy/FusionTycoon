--!strict
--[[
	TutorialService
	---------------
	The mandatory first-time tutorial (TutorialConfig.Steps). Server-owned:
	the step lives in PlayerData.Tutorial and goes out in every snapshot.

	  * Action steps complete only on the real, server-confirmed action: a
	    PlayerDataService.OnSync hook checks the step's predicate at the
	    start of every sync (claim, upgrade, 2 pulls, a fusion, the
	    Multiplier Pad), so the next step ships in that same snapshot.
	  * Card / Open / Arrive steps complete through the remote
	    TutorialAdvance { Step } (C->S), re-checked here: the step must be
	    the current one and of that kind (Arrive: the player stands within
	    ArriveDistance of the target; Multiplier: done on OK only while the
	    player can't afford level 1). TutorialAdvance { Replay = true }
	    restarts it from Settings: a replay is all OK-cards (no free pulls,
	    no guaranteed fusion again).
	  * Entering a step: the Pull step grants the 2 free pulls (once per
	    account; the pad takes them, PlayerDataService.TakeTutorialFreePull);
	    Action steps record the counter they wait on (Base). Steps the save
	    already satisfies (Skip) are skipped.
	  * Step 0 (a new field on an old save) is decided on the first sync: a
	    save with real progress (Rebirth >= 1 or > 20 pulls) is Done with a
	    one-time "replay it in ⚙" hint; anything else starts at step 1.
	  * Analytics: Custom "TutorialStep" (the step number) on each completed
	    step, "TutorialDone" at the end.

	Follows the ServiceTemplate contract: :Init() connects the remote,
	:Start() resolves PlayerDataService / TycoonService and hooks the sync.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
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

-- Where an Arrive step's target is (plot-local positions, PlotLayout).
local ARRIVE_POSITIONS: { [string]: Vector3 } = {
	LockConsole = PlotLayout.LOCK_CONSOLE,
}

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
		return pullCount(player) >= base + TutorialConfig.FreePulls
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
		if not step or t.Done or step.Kind ~= "Action" or t.Replay then
			return
		end
		local predicate = PREDICATES[step.Id]
		if not predicate or not predicate(player, t.Base) then
			return
		end
		complete(player, t)
	end
end

local function isNear(player: Player, targetName: string): boolean
	local plot = TycoonService.GetPlotForPlayer(player)
	local slot = plot and plot:GetAttribute("SlotIndex")
	local localPosition = ARRIVE_POSITIONS[targetName]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if typeof(slot) ~= "number" or not localPosition or not root or not root:IsA("BasePart") then
		return false
	end
	local target = PlotLayout.GetSlotCFrame(slot):PointToWorldSpace(localPosition)
	local flat = Vector3.new(root.Position.X - target.X, 0, root.Position.Z - target.Z)
	return flat.Magnitude <= TutorialConfig.ArriveDistance
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
	local allowed = t.Replay or step.Kind == "Card" or step.Kind == "Open"
	if step.Kind == "Arrive" and not t.Replay then
		allowed = step.Target ~= nil and isNear(player, step.Target)
	elseif step.Id == "multiplier" and not t.Replay then
		-- Done on OK only when level 1 is out of reach right now.
		local cost = TycoonConfig.GetCashMultiplierUpgradeCost(PlayerDataService.GetCashMultiplierLevel(player))
		allowed = cost ~= nil and PlayerDataService.GetCash(player) < cost
	end
	if not allowed then
		return false
	end
	complete(player, t)
	return true
end

-- Settings' "Replay tutorial": every step again, all OK-cards.
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

-- Studio /tutorial reset | step <n>.
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
end

function TutorialService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)
	PlayerDataService.OnSync(check)
end

return TutorialService
