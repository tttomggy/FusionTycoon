local TycoonConfig = {}

TycoonConfig.PassiveIncomeIntervalSeconds = 1

-- Physical cash items spawned by a claimed plot's Dropper1.
TycoonConfig.DropperCashValue = 5
TycoonConfig.DropperIntervalSeconds = 3

-- Gacha Pad: the only way to acquire a fusable item. Priced against the same
-- observed real-income anchor as the Multiplier Pad (~1.3M cash/hour, i.e.
-- ~21,667/min under normal, non-maximized play) rather than a theoretical
-- floor - that anchor is what proved correct in testing. $30,000 sits at
-- ~1.4 minutes of real income, cheap enough to pull often without being free.
TycoonConfig.GachaPullCost = 30000

-- Multiplier Pad: a fixed 10-level table, not a scaling formula. Each level
-- has its own hardcoded Cost/Multiplier, and level 10 is a genuine hard cap -
-- there is no purchase beyond it, no matter how much cash a player has.
-- Rebalance by editing these numbers directly; nothing else in the game
-- computes them.
--
-- Costs are calibrated against real observed play (~1.3M cash/hour with
-- normal, non-maximized dropper+generator income), not a theoretical
-- minimum-income floor - an earlier version anchored to "2 droppers, no
-- multiplier" made Level 1 ($750) affordable in seconds against real income.
TycoonConfig.CashMultiplierLevels = {
	{ Level = 1, Cost = 500000, Multiplier = 2 },
	{ Level = 2, Cost = 1300000, Multiplier = 3 },
	{ Level = 3, Cost = 3300000, Multiplier = 4 },
	{ Level = 4, Cost = 8500000, Multiplier = 6 },
	{ Level = 5, Cost = 20000000, Multiplier = 8 },
	{ Level = 6, Cost = 50000000, Multiplier = 10 },
	{ Level = 7, Cost = 120000000, Multiplier = 13 },
	{ Level = 8, Cost = 300000000, Multiplier = 16 },
	{ Level = 9, Cost = 750000000, Multiplier = 20 },
	{ Level = 10, Cost = 1850000000, Multiplier = 25 },
}

-- Multiplies a generator's BaseCashPerSecond according to its Tier. Also
-- reused for the Pedestal Showcase's passive income (see
-- GetPedestalCashPerSecond) rather than introducing a second tier-scaling
-- table - a displayed item's tier is worth the same relative multiplier
-- whichever system is producing the income.
TycoonConfig.TierMultipliers = {
	Common = 1,
	Rare = 2.5,
	Epic = 6,
	Legendary = 15,
	Mythic = 40,
}

-- Occupied pedestals generate passive cash/sec via the same
-- calculateTotalCashPerSecond tick Generators use (see TycoonService), just
-- scaled by TierMultipliers instead of a generator's own level.
TycoonConfig.PedestalBaseCashPerSecond = 1

function TycoonConfig.GetPedestalCashPerSecond(tier: string): number
	return TycoonConfig.PedestalBaseCashPerSecond * (TycoonConfig.TierMultipliers[tier] or 1)
end

-- UnlockRequirement gates a generator behind another generator reaching a level,
-- forming a progression chain. nil means unlocked from the start.
TycoonConfig.Generators = {
	{
		Id = "basic_generator",
		Name = "Basic Generator",
		Tier = "Common",
		BaseCashPerSecond = 1,
		BaseUpgradeCost = 50,
		UpgradeCostGrowth = 1.15,
		MaxLevel = 25,
		UnlockRequirement = nil,
	},
	{
		Id = "ember_forge",
		Name = "Ember Forge",
		Tier = "Rare",
		BaseCashPerSecond = 4,
		BaseUpgradeCost = 500,
		UpgradeCostGrowth = 1.17,
		MaxLevel = 25,
		UnlockRequirement = { GeneratorId = "basic_generator", Level = 5 },
	},
	{
		Id = "flare_reactor",
		Name = "Flare Reactor",
		Tier = "Epic",
		BaseCashPerSecond = 15,
		BaseUpgradeCost = 5000,
		UpgradeCostGrowth = 1.19,
		MaxLevel = 25,
		UnlockRequirement = { GeneratorId = "ember_forge", Level = 10 },
	},
	{
		Id = "core_engine",
		Name = "Core Engine",
		Tier = "Legendary",
		BaseCashPerSecond = 60,
		BaseUpgradeCost = 50000,
		UpgradeCostGrowth = 1.21,
		MaxLevel = 25,
		UnlockRequirement = { GeneratorId = "flare_reactor", Level = 15 },
	},
	{
		Id = "singularity_core",
		Name = "Singularity Core",
		Tier = "Mythic",
		BaseCashPerSecond = 250,
		BaseUpgradeCost = 500000,
		UpgradeCostGrowth = 1.25,
		MaxLevel = 25,
		UnlockRequirement = { GeneratorId = "core_engine", Level = 20 },
	},
}

function TycoonConfig.GetGeneratorById(id: string)
	for _, generator in TycoonConfig.Generators do
		if generator.Id == id then
			return generator
		end
	end
	return nil
end

-- Cost to purchase the level after `currentLevel`.
function TycoonConfig.GetUpgradeCost(generator, currentLevel: number): number
	return math.floor(generator.BaseUpgradeCost * (generator.UpgradeCostGrowth ^ currentLevel))
end

-- Cash/second a generator produces at a given level (0 = not yet purchased).
function TycoonConfig.GetGeneratorCashPerSecond(generator, level: number): number
	local multiplier = TycoonConfig.TierMultipliers[generator.Tier] or 1
	return generator.BaseCashPerSecond * multiplier * level
end

-- The hard cap - there is no level (and no purchase) beyond this.
function TycoonConfig.GetCashMultiplierMaxLevel(): number
	return #TycoonConfig.CashMultiplierLevels
end

-- Cash multiplier applied per dropped item at a given Multiplier Pad level
-- (0 = not yet purchased, baseline x1).
function TycoonConfig.GetCashMultiplierValue(level: number): number
	if level <= 0 then
		return 1
	end
	local entry = TycoonConfig.CashMultiplierLevels[level]
	return entry and entry.Multiplier or 1
end

-- Cost to purchase the level after `currentLevel`, or nil if `currentLevel`
-- is already at (or past) the hard cap - there's nothing left to buy.
function TycoonConfig.GetCashMultiplierUpgradeCost(currentLevel: number): number?
	local entry = TycoonConfig.CashMultiplierLevels[currentLevel + 1]
	return entry and entry.Cost or nil
end

function TycoonConfig.IsUnlocked(generator, generatorLevels: { [string]: number }): boolean
	local requirement = generator.UnlockRequirement
	if not requirement then
		return true
	end
	return (generatorLevels[requirement.GeneratorId] or 0) >= requirement.Level
end

return TycoonConfig
