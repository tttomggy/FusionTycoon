--!strict
--[[
	LoopCoach
	---------
	The core loop as ONE "do this now": Pull orbs at the Gacha Pad -> Fuse them
	-> they Earn on the pedestals -> Upgrade -> pull more (and Steal from a
	rival lab for a free orb). Pure and shared: GoalService works out the
	Result on every sync and ships it in GoalProgress.Coach; the HUD tracker
	(the loop strip and, when it takes over, its 2nd line), the goal arrow and
	/selftest all read it from here.

	Priority (the first that is doable wins):

	  Fuse     a tier the player may fuse (FusionConfig.CanFuseTierFor) has
	           >= 2 orbs: the highest such tier, N = min(owned, 6)
	  Pull     cash >= the next pull's price
	  Upgrade  cash >= a generator / Multiplier level (the best +$/s per $)
	  Steal    a rival lab holds an orb and the player is under StealsPerHour
	  Earn     otherwise: seconds to the next pull from the current income

	Hysteresis (Resolve): the step changes at most once per HoldSeconds, so
	cash ticking past a price never flickers the arrow. A held step that is
	no longer doable (the orbs were fused, the cash was spent) is dropped at
	once; only a still-doable one is held.

	The tracker's own goal keeps its title. The coach owns the 2nd line and
	the arrow only when the goal's step can't be done right now (GoalBlocked):
	GOAL_STEPS' rules (GoalSteps) stay for "own a tier" goals.
]]
local FusionConfig = require(script.Parent.FusionConfig)
local RebirthConfig = require(script.Parent.RebirthConfig)
local TycoonConfig = require(script.Parent.TycoonConfig)
local GoalSteps = require(script.Parent.Parent.Modules.GoalSteps)
local NumberFormat = require(script.Parent.Parent.Modules.NumberFormat)

local LoopCoach = {}

--[[ Constants ----------------------------------------------------------------- ]]

-- The loop strip: the main road in order, then the side road after a gap.
LoopCoach.Road = { "Pull", "Fuse", "Earn", "Upgrade" } :: { string }
LoopCoach.SideRoad = "Steal"
-- Highest priority first.
LoopCoach.Priority = { "Fuse", "Pull", "Upgrade", "Steal", "Earn" } :: { string }

LoopCoach.Icons = {
	Pull = "🎰",
	Fuse = "🔮",
	Earn = "💰",
	Upgrade = "⬆️",
	Steal = "🏃",
} :: { [string]: string }

-- Tapping a strip icon announces this (one TopStack line).
LoopCoach.Explain = {
	Pull = "Pull orbs at the Gacha Pad",
	Fuse = "Fuse 2+ same orbs into a better one",
	Earn = "Orbs on pedestals and generators both earn $/s",
	Upgrade = "Upgrade generators to earn more",
	Steal = "Steal a free orb from a rival lab",
} :: { [string]: string }

-- The goal arrow's caption while the coach points.
LoopCoach.ArrowText = {
	Pull = "Pull",
	Fuse = "Fuse",
	Earn = "Earn",
	Upgrade = "Upgrade",
	Steal = "Steal",
} :: { [string]: string }

LoopCoach.Targets = {
	Fuse = "FusionMachine",
	Pull = "GachaStation",
	Steal = "NearestRivalPedestal",
} :: { [string]: string }

LoopCoach.HoldSeconds = 3

--[[ Types --------------------------------------------------------------------- ]]

export type Upgrade = {
	Name: string, -- "Ember Forge" / "Multiplier"
	Target: string, -- "Generator_ember_forge" / "MultiplierStation"
	StationId: string, -- the generator id ("ember_forge") / "multiplier": the UPGRADES panel row the hand points into
	Cost: number,
	Gain: number, -- +$/s it adds right now
}

export type Input = {
	Counts: { [string]: number }, -- orbs owned per tier (not carried)
	Rebirths: number,
	FusionBonus: number, -- event + armed Fusion Spark
	Cash: number,
	PullCost: number,
	Income: number, -- passive $/s now
	Upgrade: Upgrade?, -- PickUpgrade's choice (nil: none affordable)
	Rival: string?, -- the nearest rival lab with an orb to grab (nil: none)
	StealsLeft: number, -- delivered-steal allowance left this hour
	-- What GoalBlocked reads:
	Levels: { [string]: number }, -- generator levels
	MultiplierLevel: number,
}

-- One step with the numbers its line needs. Also the wire shape (plus
-- Takes / Lit, added by GoalService.BuildCoach).
export type Result = {
	Step: string, -- "Pull" | "Fuse" | "Earn" | "Upgrade" | "Steal"
	Target: string?, -- a GoalConfig-style marker target; nil: no arrow
	Tier: string?, -- Fuse
	Count: number?, -- Fuse: N
	Chance: number?, -- Fuse: success chance with N orbs
	Cost: number?, -- Pull / Earn: the next pull's price
	Name: string?, -- Upgrade: the station's name
	Gain: number?, -- Upgrade: +$/s
	UpgradeTarget: UpgradeTarget?, -- Upgrade: where the hand points inside the UPGRADES panel
	Rival: string?, -- Steal: the lab's name
	Income: number?, -- Earn: $/s now
	Seconds: number?, -- Earn: seconds until the next pull (nil: no income)
}

-- Where the hand points inside the UPGRADES panel: the station's row and
-- which of its buttons ("Upgrade": the buy button; "Max": the MAX ×N one).
export type UpgradeTarget = { StationId: string, Kind: string }

export type Wire = {
	Step: string,
	Target: string?,
	Tier: string?,
	Count: number?,
	Chance: number?,
	Cost: number?,
	Name: string?,
	Gain: number?,
	UpgradeTarget: UpgradeTarget?, -- Upgrade only
	Rival: string?,
	Income: number?,
	Seconds: number?,
	Takes: boolean, -- the coach owns the tracker's 2nd line and the arrow
	Lit: string, -- the strip icon to light
}

export type Hold = { Step: string?, ChangedAt: number }

--[[ Rules --------------------------------------------------------------------- ]]

-- The best affordable generator / Multiplier level: the most +$/s per $
-- (ties: the cheaper). `inputs` is the player's IncomeInputs.
function LoopCoach.PickUpgrade(inputs: TycoonConfig.IncomeInputs, cash: number): Upgrade?
	local base = TycoonConfig.GetPassiveCashPerSecond(inputs)
	local best: Upgrade? = nil
	local bestScore = -1
	local function consider(name: string, target: string, stationId: string, cost: number, changed: TycoonConfig.IncomeInputs)
		if cost > cash then
			return
		end
		local gain = math.max(0, TycoonConfig.GetPassiveCashPerSecond(changed) - base)
		local score = gain / math.max(cost, 1)
		local current = best
		if score > bestScore or (score == bestScore and current ~= nil and cost < current.Cost) then
			best = { Name = name, Target = target, StationId = stationId, Cost = cost, Gain = gain }
			bestScore = score
		end
	end
	for _, generator in TycoonConfig.Generators do
		local level = inputs.GeneratorLevels[generator.Id] or 0
		if level < generator.MaxLevel and TycoonConfig.IsUnlocked(generator, inputs.GeneratorLevels) then
			local levels = table.clone(inputs.GeneratorLevels)
			levels[generator.Id] = level + 1
			local changed = table.clone(inputs)
			changed.GeneratorLevels = levels
			consider(generator.Name, "Generator_" .. generator.Id, generator.Id, TycoonConfig.GetUpgradeCost(generator, level), changed)
		end
	end
	local padCost = TycoonConfig.GetCashMultiplierUpgradeCost(inputs.CashMultiplierLevel)
	if padCost then
		local changed = table.clone(inputs)
		changed.CashMultiplierLevel = inputs.CashMultiplierLevel + 1
		consider("Multiplier", "MultiplierStation", "multiplier", padCost, changed)
	end
	return best
end

-- The highest tier the player may fuse that has a pair to fuse, with N and
-- its chance; nil when there is none.
local function bestFuse(input: Input): Result?
	local minInputs, maxInputs = FusionConfig.MinFusionInputs, FusionConfig.MaxFusionInputs
	for index = #FusionConfig.TierOrder, 1, -1 do
		local tier = FusionConfig.TierOrder[index]
		local owned = input.Counts[tier] or 0
		if owned >= minInputs and FusionConfig.CanFuseTierFor(tier, input.Rebirths) then
			local count = math.min(owned, maxInputs)
			return {
				Step = "Fuse",
				Target = LoopCoach.Targets.Fuse,
				Tier = tier,
				Count = count,
				Chance = FusionConfig.GetFusionChance(tier, count, input.FusionBonus),
			}
		end
	end
	return nil
end

-- Every step that is doable now, by step name. Earn is always there.
function LoopCoach.Candidates(input: Input): { [string]: Result }
	local candidates: { [string]: Result } = {}
	local fuse = bestFuse(input)
	if fuse then
		candidates.Fuse = fuse
	end
	if input.Cash >= input.PullCost then
		candidates.Pull = { Step = "Pull", Target = LoopCoach.Targets.Pull, Cost = input.PullCost }
	end
	local upgrade = input.Upgrade
	if upgrade and input.Cash >= upgrade.Cost then
		candidates.Upgrade = { Step = "Upgrade", Target = upgrade.Target, Name = upgrade.Name, Gain = upgrade.Gain, Cost = upgrade.Cost, UpgradeTarget = { StationId = upgrade.StationId, Kind = "Upgrade" } }
	end
	if input.Rival and input.StealsLeft > 0 then
		candidates.Steal = { Step = "Steal", Target = LoopCoach.Targets.Steal, Rival = input.Rival }
	end
	local seconds: number? = nil
	if input.Income > 0 then
		seconds = math.max(1, math.ceil((input.PullCost - input.Cash) / input.Income))
	end
	candidates.Earn = { Step = "Earn", Target = nil, Cost = input.PullCost, Income = input.Income, Seconds = seconds }
	return candidates
end

-- The step the priority picks.
function LoopCoach.Pick(candidates: { [string]: Result }): Result
	for _, step in LoopCoach.Priority do
		local found = candidates[step]
		if found then
			return found
		end
	end
	return candidates.Earn :: Result
end

-- The step to show now. `hold` is the player's state (mutated): the picked
-- step is held for HoldSeconds, and a switch inside that window is refused
-- unless the held step is no longer doable.
function LoopCoach.Resolve(hold: Hold, candidates: { [string]: Result }, now: number): Result
	local wanted = LoopCoach.Pick(candidates)
	local held = if hold.Step then candidates[hold.Step] else nil
	if held and wanted.Step ~= held.Step and now - hold.ChangedAt < LoopCoach.HoldSeconds then
		return held
	end
	if wanted.Step ~= hold.Step then
		hold.Step = wanted.Step
		hold.ChangedAt = now
	end
	return wanted
end

-- Whether the tracker's current goal can't be done right now (not enough
-- cash, nothing to fuse), so the coach takes the 2nd line and the arrow.
-- `goalStep` is the "own a tier" goal's GoalSteps step (nil for others).
function LoopCoach.GoalBlocked(goalId: string, goalStep: GoalSteps.Step?, input: Input, candidates: { [string]: Result }): boolean
	if goalStep then
		return goalStep.Kind == "Earn"
	end
	local function cannotAfford(generatorId: string): boolean
		local generator = TycoonConfig.GetGeneratorById(generatorId)
		if not generator then
			return false
		end
		local level = input.Levels[generatorId] or 0
		return level < generator.MaxLevel
			and (not TycoonConfig.IsUnlocked(generator, input.Levels) or input.Cash < TycoonConfig.GetUpgradeCost(generator, level))
	end
	if goalId == "upgrade_basic" or goalId == "basic_lv5" or goalId == "max_basic" then
		return cannotAfford("basic_generator")
	elseif goalId == "unlock_flare_reactor" then
		return cannotAfford(if (input.Levels.ember_forge or 0) < 10 then "ember_forge" else "flare_reactor")
	elseif goalId == "unlock_ember_forge" then
		return cannotAfford(if (input.Levels.basic_generator or 0) < 5 then "basic_generator" else "ember_forge")
	elseif goalId == "gacha_pull" then
		return input.Cash < input.PullCost
	elseif goalId == "first_fusion" then
		return candidates.Fuse == nil
	elseif goalId == "upgrade_multiplier" or goalId == "multiplier_x1_5" or goalId == "multiplier_x2" then
		local cost = TycoonConfig.GetCashMultiplierUpgradeCost(input.MultiplierLevel)
		return cost ~= nil and input.Cash < cost
	elseif goalId == "first_rebirth" then
		return input.Cash < RebirthConfig.GetCost(input.Rebirths)
	end
	return false
end

--[[ Text ---------------------------------------------------------------------- ]]

-- "0:42", "12:05", "1:02:03".
function LoopCoach.FormatClock(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	local hours, minutes, secs = total // 3600, (total // 60) % 60, total % 60
	if hours > 0 then
		return ("%d:%02d:%02d"):format(hours, minutes, secs)
	end
	return ("%d:%02d"):format(minutes, secs)
end

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- The tracker's 2nd line (RichText) for a Result.
function LoopCoach.Format(result: Result): string
	local step = result.Step
	if step == "Fuse" then
		local tier = result.Tier or "Common"
		local percent = FusionConfig.FormatPercent((result.Chance or 0) * 100) .. "%"
		return ("Fuse your %d %s: %s"):format(result.Count or FusionConfig.MinFusionInputs, GoalSteps.TierWord(tier, true), percent)
	elseif step == "Pull" then
		return ("Pull from the Gacha (%s)"):format(NumberFormat.Money(result.Cost or 0))
	elseif step == "Upgrade" then
		return ("Upgrade your %s: +%s/s"):format(escape(result.Name or "Generator"), NumberFormat.Money(result.Gain or 0))
	elseif step == "Steal" then
		return ("Steal a free orb from %s!"):format(escape(result.Rival or "a rival lab"))
	end
	local seconds = result.Seconds
	if seconds then
		return ("Your orbs earn %s/s: next pull in %s"):format(NumberFormat.Money(result.Income or 0), LoopCoach.FormatClock(seconds))
	end
	return ("Earn cash for your next pull (%s)"):format(NumberFormat.Money(result.Cost or 0))
end

-- `text` without its RichText tags (what /selftest compares).
function LoopCoach.Plain(text: string): string
	return GoalSteps.Plain(text)
end

return LoopCoach
