--!strict
local RebirthConfig = require(script.Parent.RebirthConfig)
local MutationConfig = require(script.Parent.MutationConfig)

local TycoonConfig = {}

--[[ Economy -----------------------------------------------------------------
	Every number in this file was tuned with the greedy-player simulation in
	tools/econ_sim.py, run on a brand-new save (generators -> gacha -> fuse ->
	pedestals -> multiplier -> rebirth; new saves start with Basic Generator
	at LV 1; rebirth costs cash). Medians from
	`python3 tools/econ_sim.py 30 12 --fuse=2` (the player fuses pairs), with
	`--fuse=3` (triples) in brackets:

	    first Gacha pull ..... ~1:10 (1:10)    first Legendary ....... ~6 min (13 min)
	    first Mythic ......... ~1:05 (2:10)    Rebirth 1 ............. ~1:04 (1:10)
	    Rebirth 2 ............ ~1:46 (2:13)    Rebirth 3 ............. ~2:46 (3:15)
	    Singularity Core ..... ~2:37 (3:05)    first Secret .......... ~8:30 (not in 12 h)
	    Index after 12 h ..... ~38/68 (34/68)  Multiplier maxed ...... never in 12 h

	Secret and Rainbow have huge spreads; judge them by order of magnitude.

	Income is generators + pedestals only (the factory line's cash balls are
	a client-side picture of it). If you rebalance, change the sim's
	tunables to match and re-run it rather than eyeballing.
]]

-- Passive income (generators + pedestals) is paid out on this tick.
TycoonConfig.PassiveIncomeIntervalSeconds = 1

-- A claimed plot's Basic Generator never sits below this level, so a new
-- player's factory line is running from the start.
TycoonConfig.StartingBasicGeneratorLevel = 1

-- Gacha Pad: the only way to get a brand-new item. The price rises a little
-- with every pull (GachaPullCostGrowth ^ pulls) so pulling stays a real choice
-- against buying upgrades instead of becoming free spam once income grows.
TycoonConfig.GachaBasePullCost = 250
TycoonConfig.GachaPullCostGrowth = 1.045

function TycoonConfig.GetGachaPullCost(pullsSoFar: number): number
	return math.floor(TycoonConfig.GachaBasePullCost * TycoonConfig.GachaPullCostGrowth ^ math.max(0, pullsSoFar))
end

-- Pull xN: the sum of the next `count` single-pull prices (no discount).
function TycoonConfig.GetGachaMultiPullCost(pullsSoFar: number, count: number): number
	local total = 0
	for offset = 0, count - 1 do
		total += TycoonConfig.GetGachaPullCost(pullsSoFar + offset)
	end
	return total
end

-- Multiplier Pad: 15 levels, +0.25 each, and the last level jumps to x5.
-- A long climb, not a quick max: it multiplies ALL income, so a cheap max
-- trivialised the generators. Written out literally (no formula). Saves
-- keep their level number, so an old LV 10 save is now x3.5.
TycoonConfig.CashMultiplierLevels = {
	{ Level = 1, Cost = 5_000, Multiplier = 1.25 },
	{ Level = 2, Cost = 30_000, Multiplier = 1.5 },
	{ Level = 3, Cost = 150_000, Multiplier = 1.75 },
	{ Level = 4, Cost = 750_000, Multiplier = 2 },
	{ Level = 5, Cost = 3_500_000, Multiplier = 2.25 },
	{ Level = 6, Cost = 15_000_000, Multiplier = 2.5 },
	{ Level = 7, Cost = 60_000_000, Multiplier = 2.75 },
	{ Level = 8, Cost = 250_000_000, Multiplier = 3 },
	{ Level = 9, Cost = 1_000_000_000, Multiplier = 3.25 },
	{ Level = 10, Cost = 4_000_000_000, Multiplier = 3.5 },
	{ Level = 11, Cost = 15_000_000_000, Multiplier = 3.75 },
	{ Level = 12, Cost = 50_000_000_000, Multiplier = 4 },
	{ Level = 13, Cost = 150_000_000_000, Multiplier = 4.25 },
	{ Level = 14, Cost = 500_000_000_000, Multiplier = 4.5 },
	{ Level = 15, Cost = 1_500_000_000_000, Multiplier = 5 },
}

-- Generator output scaling by the generator's own tier.
TycoonConfig.TierMultipliers = {
	Common = 1,
	Rare = 2.5,
	Epic = 6,
	Legendary = 15,
	Mythic = 40,
} :: { [string]: number }

-- What a displayed item pays per second on a pedestal (before multiplier).
-- Deliberately steep: each tier is worth ~4x the one below it, because each
-- tier costs ~2.5-5 items of the tier below to fuse, and the top tiers jump
-- further (Legendary 300, Mythic 3000) so displayed items stay worth having
-- next to late-game generators.
TycoonConfig.PedestalCashPerSecond = {
	Common = 3,
	Rare = 12,
	Epic = 50,
	Legendary = 300,
	Mythic = 3000,
	Secret = 50000,
} :: { [string]: number }

function TycoonConfig.GetPedestalCashPerSecond(tier: string): number
	return TycoonConfig.PedestalCashPerSecond[tier] or 0
end

-- What one item earns on a pedestal, before the income multiplier: its
-- tier's rate x its STACKED mutation multiplier (1 + sum(mult - 1) over
-- the base and every event mutation; MutationConfig.GetStackedMultiplier).
-- `mutations` is the item's base name or the whole list
-- (MutationConfig.List). Every item $/s shown or paid goes through this.
function TycoonConfig.GetItemCashPerSecond(tier: string, mutations: (string | { string })?): number
	local multiplier = if typeof(mutations) == "table"
		then MutationConfig.GetStackedMultiplier(nil, mutations)
		else MutationConfig.GetMultiplier(mutations)
	return TycoonConfig.GetPedestalCashPerSecond(tier) * multiplier
end

-- The same for an item (anything with Tier / Mutation / EventMutations).
function TycoonConfig.GetStackCashPerSecond(item: { Tier: string, Mutation: string?, EventMutations: { string }? }): number
	return TycoonConfig.GetItemCashPerSecond(item.Tier, MutationConfig.List(item.Mutation, item.EventMutations))
end

export type GeneratorDef = {
	Id: string,
	Name: string,
	Tier: string,
	BaseCashPerSecond: number,
	BaseUpgradeCost: number,
	UpgradeCostGrowth: number,
	MaxLevel: number,
	UnlockRequirement: { GeneratorId: string, Level: number }?,
}

-- UnlockRequirement gates a generator behind another generator reaching a level,
-- forming a progression chain. nil means unlocked from the start.
TycoonConfig.Generators = {
	{
		Id = "basic_generator",
		Name = "Basic Generator",
		Tier = "Common",
		BaseCashPerSecond = 2,
		BaseUpgradeCost = 25,
		UpgradeCostGrowth = 1.15,
		MaxLevel = 25,
		UnlockRequirement = nil,
	},
	{
		Id = "ember_forge",
		Name = "Ember Forge",
		Tier = "Rare",
		BaseCashPerSecond = 4,
		BaseUpgradeCost = 400,
		UpgradeCostGrowth = 1.17,
		MaxLevel = 25,
		UnlockRequirement = { GeneratorId = "basic_generator", Level = 5 },
	},
	{
		Id = "flare_reactor",
		Name = "Flare Reactor",
		Tier = "Epic",
		BaseCashPerSecond = 15,
		BaseUpgradeCost = 8000,
		UpgradeCostGrowth = 1.19,
		MaxLevel = 25,
		UnlockRequirement = { GeneratorId = "ember_forge", Level = 10 },
	},
	{
		Id = "core_engine",
		Name = "Core Engine",
		Tier = "Legendary",
		BaseCashPerSecond = 60,
		BaseUpgradeCost = 150000,
		UpgradeCostGrowth = 1.21,
		MaxLevel = 25,
		UnlockRequirement = { GeneratorId = "flare_reactor", Level = 15 },
	},
	{
		Id = "singularity_core",
		Name = "Singularity Core",
		Tier = "Mythic",
		BaseCashPerSecond = 250,
		BaseUpgradeCost = 4000000,
		UpgradeCostGrowth = 1.23,
		MaxLevel = 25,
		UnlockRequirement = { GeneratorId = "core_engine", Level = 20 },
	},
} :: { GeneratorDef }

function TycoonConfig.GetGeneratorById(id: string): GeneratorDef?
	for _, generator in TycoonConfig.Generators do
		if generator.Id == id then
			return generator
		end
	end
	return nil
end

-- Cost to purchase the level after `currentLevel`.
function TycoonConfig.GetUpgradeCost(generator: GeneratorDef, currentLevel: number): number
	return math.floor(generator.BaseUpgradeCost * (generator.UpgradeCostGrowth ^ currentLevel))
end

-- Cash/second a generator produces at a given level (0 = not yet purchased),
-- before the cash multiplier.
function TycoonConfig.GetGeneratorCashPerSecond(generator: GeneratorDef, level: number): number
	local multiplier = TycoonConfig.TierMultipliers[generator.Tier] or 1
	return generator.BaseCashPerSecond * multiplier * level
end

-- The hard cap - there is no level (and no purchase) beyond this.
function TycoonConfig.GetCashMultiplierMaxLevel(): number
	return #TycoonConfig.CashMultiplierLevels
end

-- Income multiplier at a given Multiplier Pad level (0 = baseline x1).
function TycoonConfig.GetCashMultiplierValue(level: number): number
	if level <= 0 then
		return 1
	end
	local entry = TycoonConfig.CashMultiplierLevels[level]
	return if entry then entry.Multiplier else 1
end

-- Cost to purchase the level after `currentLevel`, or nil at the hard cap.
function TycoonConfig.GetCashMultiplierUpgradeCost(currentLevel: number): number?
	local entry = TycoonConfig.CashMultiplierLevels[currentLevel + 1]
	return if entry then entry.Cost else nil
end

function TycoonConfig.IsUnlocked(generator: GeneratorDef, generatorLevels: { [string]: number }): boolean
	local requirement = generator.UnlockRequirement
	if not requirement then
		return true
	end
	return (generatorLevels[requirement.GeneratorId] or 0) >= requirement.Level
end

--[[ MAX upgrades -------------------------------------------------------------
	The Upgrades panel's MAX ×N / MAX ALL labels and TycoonService's
	RequestUpgradeMax loop agree through these: same costs (GetUpgradeCost),
	same unlocks, same caps. Pure functions of (levels, cash).
]]
TycoonConfig.MaxUpgradeSteps = 500 -- levels one MAX request may buy

-- Levels of `generator` that `cash` buys in a row from `level`: how many,
-- their total cost, and the price of the first one it can't afford (nil
-- when it stopped at the max level).
function TycoonConfig.GetMaxAffordable(generator: GeneratorDef, level: number, cash: number): (number, number, number?)
	local count, total, current = 0, 0, level
	while count < TycoonConfig.MaxUpgradeSteps and current < generator.MaxLevel do
		local cost = TycoonConfig.GetUpgradeCost(generator, current)
		if total + cost > cash then
			return count, total, cost
		end
		total += cost
		count += 1
		current += 1
	end
	return count, total, nil
end

-- The cheapest next level across every unlocked, unmaxed generator (ties:
-- the earlier generator in the line), or nil when everything is maxed.
function TycoonConfig.GetCheapestUpgrade(levels: { [string]: number }): (GeneratorDef?, number)
	local best: GeneratorDef? = nil
	local bestCost = math.huge
	for _, generator in TycoonConfig.Generators do
		local level = levels[generator.Id] or 0
		if level < generator.MaxLevel and TycoonConfig.IsUnlocked(generator, levels) then
			local cost = TycoonConfig.GetUpgradeCost(generator, level)
			if cost < bestCost then
				best, bestCost = generator, cost
			end
		end
	end
	return best, bestCost
end

export type MaxAllPlan = {
	Levels: number,
	Spent: number,
	PerGenerator: { [string]: number },
	NextCost: number?, -- the cheapest level it couldn't afford (nil: all maxed)
}

-- MAX ALL: buy the cheapest available level, one at a time, re-checking
-- unlocks after each (a newly unlocked generator joins), until cash runs
-- out, everything is maxed or MaxUpgradeSteps levels.
function TycoonConfig.GetMaxAllPlan(levels: { [string]: number }, cash: number): MaxAllPlan
	local simulated = table.clone(levels)
	local plan: MaxAllPlan = { Levels = 0, Spent = 0, PerGenerator = {}, NextCost = nil }
	while plan.Levels < TycoonConfig.MaxUpgradeSteps do
		local generator, cost = TycoonConfig.GetCheapestUpgrade(simulated)
		if not generator then
			return plan
		end
		if plan.Spent + cost > cash then
			plan.NextCost = cost
			return plan
		end
		plan.Spent += cost
		plan.Levels += 1
		simulated[generator.Id] = (simulated[generator.Id] or 0) + 1
		plan.PerGenerator[generator.Id] = (plan.PerGenerator[generator.Id] or 0) + 1
	end
	return plan
end

--[[ Income -----------------------------------------------------------------
	ONE formula, ONE input table. Build IncomeInputs only through
	PlayerDataService.GetIncomeInputs (server) or
	TycoonController.GetIncomeInputs (client); later features add fields
	here, so nothing else should assemble one by hand.
]]
export type PedestalItem = { Tier: string, Mutation: string?, EventMutations: { string }? }

export type IncomeInputs = {
	GeneratorLevels: { [string]: number },
	PedestalItems: { PedestalItem },
	CashMultiplierLevel: number,
	Rebirths: number,
	IndexMultiplier: number, -- IndexConfig.GetMultiplier(found entries)
	-- The live event's generator boost (EventState.GetGeneratorMultiplier;
	-- Power Surge). Generators only, never pedestals. nil = 1.
	EventGeneratorMultiplier: number?,
	-- The shop (ShopConfig), all on ALL income; nil = 1:
	PassMultiplier: number?, -- 2x Cash x VIP (permanent passes)
	BoostMultiplier: number?, -- a timed Boost / Quick Boost
	OverclockMultiplier: number?, -- the Server Overclock (everyone here)
}

-- "The multiplier" for every per-generator or per-item number the game
-- shows: Multiplier Pad x rebirth x Index x the shop's passes, boost and
-- Server Overclock. (GetCashMultiplierValue is the pad alone; only the
-- pad's own label and Upgrades row use it.)
function TycoonConfig.GetIncomeMultiplier(inputs: IncomeInputs): number
	return TycoonConfig.GetCashMultiplierValue(inputs.CashMultiplierLevel)
		* RebirthConfig.GetIncomeMultiplier(inputs.Rebirths)
		* inputs.IndexMultiplier
		* (inputs.PassMultiplier or 1)
		* (inputs.BoostMultiplier or 1)
		* (inputs.OverclockMultiplier or 1)
end

-- The pieces of GetIncomeMultiplier, for the HUD pill's breakdown.
function TycoonConfig.GetIncomeBreakdown(inputs: IncomeInputs): { { Label: string, Value: number } }
	return {
		{ Label = "Multiplier Pad", Value = TycoonConfig.GetCashMultiplierValue(inputs.CashMultiplierLevel) },
		{ Label = "Rebirths", Value = RebirthConfig.GetIncomeMultiplier(inputs.Rebirths) },
		{ Label = "Index", Value = inputs.IndexMultiplier },
		{ Label = "Passes", Value = inputs.PassMultiplier or 1 },
		{ Label = "Boost", Value = inputs.BoostMultiplier or 1 },
		{ Label = "Server Overclock", Value = inputs.OverclockMultiplier or 1 },
	}
end

-- Sum of every generator's output, before the multiplier.
local function baseGeneratorCashPerSecond(generatorLevels: { [string]: number }): number
	local total = 0
	for _, generator in TycoonConfig.Generators do
		local level = generatorLevels[generator.Id] or 0
		if level > 0 then
			total += TycoonConfig.GetGeneratorCashPerSecond(generator, level)
		end
	end
	return total
end

-- Single source of truth for passive income, used by the server's payout tick
-- AND the client HUD's "+$X/s" readout so the two can never disagree. This
-- is ALL income: the factory line's balls only picture it.
-- (generators + pedestals) x pad x rebirth x Index.
function TycoonConfig.GetPassiveCashPerSecond(inputs: IncomeInputs): number
	local total = baseGeneratorCashPerSecond(inputs.GeneratorLevels) * (inputs.EventGeneratorMultiplier or 1)
	for _, item in inputs.PedestalItems do
		total += TycoonConfig.GetStackCashPerSecond(item)
	end
	return total * TycoonConfig.GetIncomeMultiplier(inputs)
end

-- The generators' share of GetPassiveCashPerSecond (what the factory balls
-- add up to): the collector label and the Upgrades panel total.
function TycoonConfig.GetGeneratorIncome(inputs: IncomeInputs): number
	return baseGeneratorCashPerSecond(inputs.GeneratorLevels)
		* (inputs.EventGeneratorMultiplier or 1)
		* TycoonConfig.GetIncomeMultiplier(inputs)
end

return TycoonConfig
