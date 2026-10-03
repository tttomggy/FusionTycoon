--!strict
local TycoonConfig = {}

--[[ Economy -----------------------------------------------------------------
	Every number in this file was tuned with the greedy-player simulation in
	tools/econ_sim.py, run on a brand-new save (generators -> gacha -> fuse ->
	pedestals -> multiplier; new saves start with Basic Generator at LV 1).
	Median milestones it produces:

	    first Gacha pull ..... ~1:10     first Epic ............ ~3.5 min
	    first Legendary ...... ~7 min    first Mythic .......... ~30 min
	    Singularity Core ..... ~1h43     Multiplier maxed ...... ~3h53
	    4 Mythics displayed .. long-tail chase

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

-- Multiplier Pad: 10 fixed levels with a hard cap. The multiplier now applies
-- to ALL income (generators and pedestals). It once touched only the old
-- dropper balls, which made a $1.85B upgrade worth a few cents per second.
TycoonConfig.CashMultiplierLevels = {
	{ Level = 1, Cost = 5000, Multiplier = 1.5 },
	{ Level = 2, Cost = 30000, Multiplier = 2 },
	{ Level = 3, Cost = 150000, Multiplier = 2.5 },
	{ Level = 4, Cost = 750000, Multiplier = 3 },
	{ Level = 5, Cost = 3500000, Multiplier = 4 },
	{ Level = 6, Cost = 15000000, Multiplier = 5 },
	{ Level = 7, Cost = 60000000, Multiplier = 6.5 },
	{ Level = 8, Cost = 250000000, Multiplier = 8 },
	{ Level = 9, Cost = 1000000000, Multiplier = 10 },
	{ Level = 10, Cost = 4000000000, Multiplier = 12.5 },
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
-- tier costs ~2.5-5 items of the tier below to fuse. This is what makes
-- chasing a Mythic worth it.
TycoonConfig.PedestalCashPerSecond = {
	Common = 3,
	Rare = 12,
	Epic = 50,
	Legendary = 220,
	Mythic = 1000,
} :: { [string]: number }

function TycoonConfig.GetPedestalCashPerSecond(tier: string): number
	return TycoonConfig.PedestalCashPerSecond[tier] or 0
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

-- Single source of truth for passive income, used by the server's payout tick
-- AND the client HUD's "+$X/s" readout so the two can never disagree. This
-- is ALL income: the factory line's balls only picture it.
function TycoonConfig.GetPassiveCashPerSecond(
	generatorLevels: { [string]: number },
	pedestalTiers: { string },
	cashMultiplierLevel: number
): number
	local total = 0
	for _, generator in TycoonConfig.Generators do
		local level = generatorLevels[generator.Id] or 0
		if level > 0 then
			total += TycoonConfig.GetGeneratorCashPerSecond(generator, level)
		end
	end
	for _, tier in pedestalTiers do
		total += TycoonConfig.GetPedestalCashPerSecond(tier)
	end
	return total * TycoonConfig.GetCashMultiplierValue(cashMultiplierLevel)
end

return TycoonConfig
