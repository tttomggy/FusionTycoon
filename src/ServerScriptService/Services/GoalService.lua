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

	No polling: it runs from PlayerDataService.OnSync, which every service
	already triggers through SyncTycoon after any state change.

	Follows the ServiceTemplate contract:
	  :Init()   nothing to set up (no remotes of its own to listen to).
	  :Start()  resolves PlayerDataService and TycoonService and registers
	            the sync hook.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoalConfig = require(ReplicatedStorage.Shared.Config.GoalConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local GoalSteps = require(ReplicatedStorage.Shared.Modules.GoalSteps)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))
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

-- The next action toward an "own a tier" goal (nil for any other goal).
-- `inventory` and `cash` default to the player's own; /selftest passes
-- stubbed ones. Orbs a thief is carrying can't be fused, so they don't count.
function GoalService.ComputeStep(player: Player, goal: GoalConfig.GoalDef, inventory: { { Uid: string, Tier: string } }?, cash: number?): GoalSteps.Step?
	local tier = GoalSteps.GetGoalTier(goal)
	if not tier then
		return nil
	end
	local counts: { [string]: number } = {}
	local owned: { any } = inventory or PlayerDataService.GetInventory(player) or {}
	for _, item in owned do
		if not PlayerDataService.IsItemCarried(player, item.Uid) then
			counts[item.Tier] = (counts[item.Tier] or 0) + 1
		end
	end
	-- The same bonus the Fuse panel adds: the live event and an armed Fusion Spark.
	local sparkDef = QuestConfig.PowerUps.FusionSpark
	local spark = if PlayerDataService.IsArmed(player, sparkDef.Key) then sparkDef.FusionBonus or 0 else 0
	return GoalSteps.Compute(tier, {
		Counts = counts,
		Rebirths = PlayerDataService.GetRebirths(player),
		Cash = cash or PlayerDataService.GetCash(player),
		PullCost = TycoonConfig.GetGachaPullCost(PlayerDataService.GetGachaPulls(player), PlayerDataService.GetSteadyIncomePerSecond(player)),
		FreePulls = PlayerDataService.GetTutorialFreePulls(player),
		FusionBonus = EventState.GetFusionSuccessBonus() + spark,
	})
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
			PlayerDataService.SetGoalProgress(player, {
				Current = current,
				Target = target,
				Step = GoalService.ComputeStep(player, goal),
			})
			return
		end

		PlayerDataService.AddCash(player, goal.Reward)
		PlayerDataService.SetGoalIndex(player, index + 1)
		RemoteEvents.GoalCompleted:FireClient(player, { Index = index, Reward = goal.Reward })
	end
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function GoalService:Init() end

function GoalService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)
	PlayerDataService.OnSync(checkGoals)
end

return GoalService
