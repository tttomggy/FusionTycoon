--!strict
--[[
	GoalService
	-----------
	Server-authoritative onboarding goals (GoalConfig). Whenever a player's
	tycoon state is synced, checks their current goal; when it's met, pays the
	reward, advances GoalIndex and fires GoalCompleted. Several goals can
	complete in one check (e.g. an older save that already did them). Also
	publishes progress toward the current goal, which goes out with the same
	snapshot. For "own a tier" goals the progress carries the NEXT ACTION
	(GoalSteps: fuse N orbs, fuse a lower tier, pull, or earn cash), worked
	out from the inventory with FusionService's rules and re-evaluated on
	every sync, so it switches the moment a pull lands or a fuse ends.

	It also ships the LoopCoach (Shared/Config/LoopCoach): the core loop's
	one "do this now" (Fuse > Pull > Upgrade > Steal > Earn), computed here on
	every sync, held for LoopCoach.HoldSeconds per player, and absent during
	the tutorial. The goal keeps its title; the coach takes the tracker's 2nd
	line and the arrow only when the goal's own step can't be done right now.

	No polling: it runs from PlayerDataService.OnSync, which every service
	already triggers through SyncTycoon after any state change.

	Follows the ServiceTemplate contract:
	  :Init()   nothing to set up (no remotes of its own to listen to).
	  :Start()  resolves PlayerDataService, TycoonService, TutorialService,
	            HeistService and RivalService, registers the sync hook and
	            drops a leaving player's coach hold.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoalConfig = require(ReplicatedStorage.Shared.Config.GoalConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local LoopCoach = require(ReplicatedStorage.Shared.Config.LoopCoach)
local RivalConfig = require(ReplicatedStorage.Shared.Config.RivalConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local GoalSteps = require(ReplicatedStorage.Shared.Modules.GoalSteps)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))
type TutorialServiceModule = typeof(require(script.Parent.TutorialService))
type HeistServiceModule = typeof(require(script.Parent.HeistService))
type RivalServiceModule = typeof(require(script.Parent.RivalService))
-- The slice of PlayerDataService.PlayerData the evaluators read. Declared
-- here because an exported type can't be reached through a type-only
-- typeof(require(...)) reference.
type PlayerData = {
	Inventory: { any },
	Generators: { [string]: number },
	PedestalDisplays: { [number]: string? },
	CashMultiplierLevel: number,
	GachaPulls: number,
	FreePulls: number,
	GoalIndex: number,
	TotalFusions: number,
	Rebirths: number,
	TotalSteals: number,
	ShieldRaises: number,
}

-- (done, current, target)
type Evaluator = (player: Player, data: PlayerData) -> (boolean, number, number)

--[[ Private state -------------------------------------------------------- ]]

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule
local TutorialService: TutorialServiceModule
local HeistService: HeistServiceModule
local RivalService: RivalServiceModule

-- Each player's held coach step (LoopCoach.Resolve); dropped on leave and
-- during the tutorial.
local coachHolds: { [number]: LoopCoach.Hold } = {}

local GoalService = {}

GoalService.Name = "GoalService"

--[[ Evaluators ------------------------------------------------------------ ]]

local function yesNo(done: boolean): (boolean, number, number)
	return done, if done then 1 else 0, 1
end

local function countTier(data: PlayerData, tier: string): number
	local count = 0
	for _, item in data.Inventory do
		if item.Tier == tier then
			count += 1
		end
	end
	return count
end

local function ownsTierAtLeast(data: PlayerData, tier: string): boolean
	local wanted = ItemConfig.Tiers[tier] or math.huge
	for _, item in data.Inventory do
		if (ItemConfig.Tiers[item.Tier] or 0) >= wanted then
			return true
		end
	end
	return false
end

local function generatorLevel(data: PlayerData, generatorId: string): number
	return data.Generators[generatorId] or 0
end

-- "Own a <tier>" goals whose progress is how many of the tier below you
-- hold toward the 2 needed to fuse one.
local function ownTierGoal(tier: string, feederTier: string, feederTarget: number): Evaluator
	return function(_player, data)
		local done = ownsTierAtLeast(data, tier)
		return done, if done then feederTarget else countTier(data, feederTier), feederTarget
	end
end

local EVALUATORS: { [string]: Evaluator } = {
	claim_base = function(player, _data)
		local plot = TycoonService.GetPlotForPlayer(player)
		return yesNo(plot ~= nil and plot:GetAttribute("Claimed") == true)
	end,
	upgrade_basic = function(_player, data)
		return yesNo(generatorLevel(data, "basic_generator") >= 2)
	end,
	basic_lv5 = function(_player, data)
		local level = generatorLevel(data, "basic_generator")
		return level >= 5, math.min(level, 5), 5
	end,
	gacha_pull = function(_player, data)
		-- Free pulls (daily / gifts) count too: they're real pulls, they
		-- just don't move the pad price.
		return yesNo(data.GachaPulls >= 1 or data.FreePulls >= 1)
	end,
	display_item = function(_player, data)
		return yesNo(next(data.PedestalDisplays) ~= nil)
	end,
	first_fusion = function(_player, data)
		return yesNo(data.TotalFusions >= 1)
	end,
	own_rare = ownTierGoal("Rare", "Rare", 1),
	upgrade_multiplier = function(_player, data)
		return yesNo(data.CashMultiplierLevel >= 1)
	end,
	fill_pedestals = function(_player, data)
		local filled = 0
		for _, uid in data.PedestalDisplays do
			if uid ~= nil then
				filled += 1
			end
		end
		return filled >= 4, math.min(filled, 4), 4
	end,
	max_basic = function(_player, data)
		local level = generatorLevel(data, "basic_generator")
		return level >= 25, math.min(level, 25), 25
	end,
	-- 3 Rares at once, or already past them (an Epic: they fused the Rares).
	own_3_rares = function(_player, data)
		local done = countTier(data, "Rare") >= 3 or ownsTierAtLeast(data, "Epic")
		return done, if done then 3 else countTier(data, "Rare"), 3
	end,
	multiplier_x1_5 = function(_player, data)
		-- Pad LV 2 = x1.5.
		return data.CashMultiplierLevel >= 2, math.min(data.CashMultiplierLevel, 2), 2
	end,
	-- 2 Epics at once, or already past them (a Legendary).
	own_2_epics = function(_player, data)
		local done = countTier(data, "Epic") >= 2 or ownsTierAtLeast(data, "Legendary")
		return done, if done then 2 else countTier(data, "Epic"), 2
	end,
	unlock_flare_reactor = function(_player, data)
		local done = generatorLevel(data, "flare_reactor") >= 1
		return done, if done then 10 else generatorLevel(data, "ember_forge"), 10
	end,
	own_epic = ownTierGoal("Epic", "Rare", 2),
	unlock_ember_forge = function(_player, data)
		local done = generatorLevel(data, "ember_forge") >= 1
		return done, if done then 5 else generatorLevel(data, "basic_generator"), 5
	end,
	own_legendary = ownTierGoal("Legendary", "Epic", 2),
	multiplier_x2 = function(_player, data)
		-- Pad LV 4 = x2.
		return data.CashMultiplierLevel >= 4, math.min(data.CashMultiplierLevel, 4), 4
	end,
	own_mythic = ownTierGoal("Mythic", "Legendary", 2),
	first_rebirth = function(_player, data)
		return yesNo(data.Rebirths >= 1)
	end,
	first_shield = function(_player, data)
		return yesNo(data.ShieldRaises >= 1)
	end,
	first_steal = function(_player, data)
		return yesNo(data.TotalSteals >= 1)
	end,
}

--[[ Next action --------------------------------------------------------- ]]

-- Orbs owned per tier. Orbs a thief is carrying can't be fused, so they
-- don't count. `inventory` defaults to the player's own; /selftest passes
-- stubbed ones.
local function countOrbs(player: Player, inventory: { { Uid: string, Tier: string } }?): { [string]: number }
	local counts: { [string]: number } = {}
	local owned: { any } = inventory or PlayerDataService.GetInventory(player) or {}
	for _, item in owned do
		if not PlayerDataService.IsItemCarried(player, item.Uid) then
			counts[item.Tier] = (counts[item.Tier] or 0) + 1
		end
	end
	return counts
end

-- The same bonus the Fuse panel adds: the live event and an armed Fusion Spark.
local function fusionBonus(player: Player): number
	local sparkDef = QuestConfig.PowerUps.FusionSpark
	local spark = if PlayerDataService.IsArmed(player, sparkDef.Key) then sparkDef.FusionBonus or 0 else 0
	return EventState.GetFusionSuccessBonus() + spark
end

local function pullCostFor(player: Player): number
	return TycoonConfig.GetGachaPullCost(PlayerDataService.GetGachaPulls(player), PlayerDataService.GetSteadyIncomePerSecond(player))
end

-- The next action toward an "own a tier" goal (nil for any other goal).
-- `inventory` and `cash` default to the player's own; /selftest passes
-- stubbed ones.
function GoalService.ComputeStep(player: Player, goal: GoalConfig.GoalDef, inventory: { { Uid: string, Tier: string } }?, cash: number?): GoalSteps.Step?
	local tier = GoalSteps.GetGoalTier(goal)
	if not tier then
		return nil
	end
	return GoalSteps.Compute(tier, {
		Counts = countOrbs(player, inventory),
		Rebirths = PlayerDataService.GetRebirths(player),
		Cash = cash or PlayerDataService.GetCash(player),
		PullCost = pullCostFor(player),
		FreePulls = PlayerDataService.GetTutorialFreePulls(player),
		FusionBonus = fusionBonus(player),
	})
end

--[[ Loop coach ------------------------------------------------------------ ]]

-- The name of the rival lab nearest the player that holds an orb to grab
-- (the arrow's NearestRivalPedestal picks the same lab), or nil.
local function nearestRivalWithOrb(player: Player): string?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local best: string? = nil
	local bestDistance = math.huge
	for _, rival in RivalService.GetRivals() do
		local hasOrb = false
		for index = 1, RivalConfig.PedestalCount do
			if RivalService.GetOrb(rival.Id, index) then
				hasOrb = true
				break
			end
		end
		if hasOrb then
			local distance = if root and root:IsA("BasePart") then (rival.Origin.Position - root.Position).Magnitude else 0
			if distance < bestDistance then
				best, bestDistance = rival.Name, distance
			end
		end
	end
	return best
end

-- The player's own state as the coach's input (nil until their data loads).
local function liveCoachInput(player: Player): LoopCoach.Input?
	local inputs = PlayerDataService.GetIncomeInputs(player)
	if not inputs then
		return nil
	end
	local cash = PlayerDataService.GetCash(player)
	local stealsLeft = HeistService.GetRivalStealsLeft(player)
	return {
		Counts = countOrbs(player, nil),
		Rebirths = inputs.Rebirths,
		FusionBonus = fusionBonus(player),
		Cash = cash,
		PullCost = pullCostFor(player),
		Income = TycoonConfig.GetPassiveCashPerSecond(inputs),
		Upgrade = LoopCoach.PickUpgrade(inputs, cash),
		Rival = nearestRivalWithOrb(player),
		StealsLeft = stealsLeft,
		Levels = inputs.GeneratorLevels,
		MultiplierLevel = inputs.CashMultiplierLevel,
	}
end

-- The loop strip icon a goal's own "own a tier" step is.
local STEP_ICONS: { [string]: string } = { Fuse = "Fuse", FuseLower = "Fuse", Pull = "Pull" }

export type CoachOptions = {
	Input: LoopCoach.Input?, -- /selftest: a stubbed state
	Now: number?, -- /selftest: the clock the hold runs on
	Hold: LoopCoach.Hold?, -- /selftest: a hold of its own
	TutorialActive: boolean?, -- /selftest: pretend the tutorial is (not) running
}

-- The coach for the player's current goal, or nil (the tutorial is running,
-- or the player's data isn't loaded). `step` is the goal's GoalSteps step.
-- Hysteresis lives in the player's hold (LoopCoach.Resolve).
function GoalService.BuildCoach(player: Player, goal: GoalConfig.GoalDef, step: GoalSteps.Step?, options: CoachOptions?): LoopCoach.Wire?
	local given: CoachOptions = options or {}
	local tutorial = given.TutorialActive
	if tutorial == nil then
		tutorial = TutorialService.IsActive(player)
	end
	if tutorial then
		coachHolds[player.UserId] = nil
		return nil
	end
	local input = given.Input or liveCoachInput(player)
	if not input then
		return nil
	end
	local hold = given.Hold
	if not hold then
		hold = coachHolds[player.UserId]
		if not hold then
			hold = { Step = nil, ChangedAt = 0 }
			coachHolds[player.UserId] = hold
		end
	end
	local candidates = LoopCoach.Candidates(input)
	local result = LoopCoach.Resolve(hold :: LoopCoach.Hold, candidates, given.Now or os.clock())
	local takes = LoopCoach.GoalBlocked(goal.Id, step, input, candidates)
	local lit = result.Step
	if not takes then
		if step then
			lit = STEP_ICONS[step.Kind] or lit
		elseif goal.Loop then
			lit = goal.Loop
		end
	end
	return {
		Step = result.Step,
		Target = result.Target,
		Tier = result.Tier,
		Count = result.Count,
		Chance = result.Chance,
		Cost = result.Cost,
		Name = result.Name,
		Gain = result.Gain,
		UpgradeTarget = result.UpgradeTarget,
		Rival = result.Rival,
		Income = result.Income,
		Seconds = result.Seconds,
		Takes = takes,
		Lit = lit,
	}
end

--[[ Check ---------------------------------------------------------------- ]]

local function checkGoals(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end

	-- Bounded by the goal count, so a bad evaluator can't spin forever.
	for _ = 1, #GoalConfig.Goals do
		local index = data.GoalIndex
		local goal = GoalConfig.GetGoal(index)
		if not goal then
			PlayerDataService.SetGoalProgress(player, nil)
			return
		end

		local evaluate = EVALUATORS[goal.Id]
		if not evaluate then
			warn(("GoalService: no evaluator for goal %s"):format(goal.Id))
			PlayerDataService.SetGoalProgress(player, nil)
			return
		end

		local done, current, target = evaluate(player, data)
		if not done then
			local step = GoalService.ComputeStep(player, goal)
			PlayerDataService.SetGoalProgress(player, {
				Current = current,
				Target = target,
				Step = step,
				Coach = GoalService.BuildCoach(player, goal, step),
			})
			return
		end

		PlayerDataService.AddCash(player, goal.Reward)
		PlayerDataService.SetGoalIndex(player, index + 1)
		RemoteEvents.GoalCompleted:FireClient(player, { Index = index, Reward = goal.Reward })
	end
end

-- /selftest: a goal's evaluator on stubbed data (the data-only goals read no
-- player). nil for an unknown id.
function GoalService.EvaluateStub(goalId: string, data: any): (boolean?, number?, number?)
	local evaluate = EVALUATORS[goalId]
	if not evaluate then
		return nil, nil, nil
	end
	return evaluate(nil :: any, data)
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function GoalService:Init() end

function GoalService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)
	TutorialService = require(script.Parent.TutorialService)
	HeistService = require(script.Parent.HeistService)
	RivalService = require(script.Parent.RivalService)
	PlayerDataService.OnSync(checkGoals)
	Players.PlayerRemoving:Connect(function(player)
		coachHolds[player.UserId] = nil
	end)
end

return GoalService
