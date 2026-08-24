local FusionConfig = {}

FusionConfig.TierOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

-- Chance of a drop landing on each tier; must sum to 1.
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

-- Items of a tier consumed to attempt a fusion into the next tier.
FusionConfig.ItemsRequiredForFusion = {
	Common = 3,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
}

-- Chance a fusion attempt succeeds and yields the next tier's item.
FusionConfig.FusionSuccessRate = {
	Common = 0.75,
	Rare = 0.55,
	Epic = 0.35,
	Legendary = 0.15,
}

function FusionConfig.GetNextTier(tier: string): string?
	for index, currentTier in FusionConfig.TierOrder do
		if currentTier == tier then
			return FusionConfig.TierOrder[index + 1]
		end
	end
	return nil
end

-- Rolls a drop tier using cumulative-weight RNG against DropRates.
function FusionConfig.RollDropTier(randomInstance: Random?): string
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

-- Attempts to fuse ItemsRequiredForFusion[tier] items of `tier` into the next tier.
-- Returns (success: boolean, nextTier: string?).
function FusionConfig.AttemptFusion(tier: string, randomInstance: Random?): (boolean, string?)
	local nextTier = FusionConfig.GetNextTier(tier)
	local successRate = FusionConfig.FusionSuccessRate[tier]
	if not nextTier or not successRate then
		return false, nil
	end

	local rng = randomInstance or Random.new()
	local success = rng:NextNumber() <= successRate

	return success, nextTier
end

return FusionConfig
