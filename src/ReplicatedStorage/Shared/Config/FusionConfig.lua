local FusionConfig = {}

FusionConfig.TierOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

-- Chance a fusion's output lands on each tier; must sum to 1. Independent of
-- which tier the two consumed items were - the Fusion Machine is a gamble,
-- not a guaranteed step up.
FusionConfig.DropRates = {
	Common = 0.60,
	Rare = 0.25,
	Epic = 0.10,
	Legendary = 0.04,
	Mythic = 0.01,
}

do
	local total = 0
	for _, rate in FusionConfig.DropRates do
		total += rate
	end
	assert(math.abs(total - 1) < 1e-6, "FusionConfig.DropRates must sum to 1")
end

-- The Fusion Machine always consumes exactly this many same-tier items per attempt.
FusionConfig.ItemsRequiredPerFusion = 2

-- Per-tier accent color, shared by the machine's own styling, the odds panel,
-- and the client's reveal effects, so a given tier always reads the same
-- color everywhere it shows up.
FusionConfig.TierAccentColors = {
	Common = Color3.fromRGB(200, 200, 200),
	Rare = Color3.fromRGB(60, 160, 255),
	Epic = Color3.fromRGB(190, 60, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
	Mythic = Color3.fromRGB(255, 60, 90),
}

-- Tiers dramatic enough to warrant the "big reveal" treatment (longer pause,
-- screen shake, bigger particle burst, distinct sound) instead of the quick,
-- understated one. See RevealEffects.PlayReveal.
FusionConfig.MajorRevealTiers = {
	Epic = true,
	Legendary = true,
	Mythic = true,
}

-- Rolls a result tier using cumulative-weight RNG against DropRates.
function FusionConfig.RollResultTier(randomInstance: Random?): string
	local rng = randomInstance or Random.new()
	local roll = rng:NextNumber()
	local cumulative = 0
	for _, tier in FusionConfig.TierOrder do
		cumulative += FusionConfig.DropRates[tier]
		if roll <= cumulative then
			return tier
		end
	end
	return FusionConfig.TierOrder[#FusionConfig.TierOrder]
end

return FusionConfig
