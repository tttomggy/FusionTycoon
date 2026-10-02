--!strict
local FusionConfig = {}

FusionConfig.TierOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

--[[ Fusion -------------------------------------------------------------------
	Fusing two items of the same tier tries to make ONE item of the next tier.
	  success -> 1 item of the next tier
	  fail    -> 1 item of the SAME tier back (you lose one, not both)

	The old machine ignored the input tier entirely (60% Common no matter
	what), so fusing two Mythics usually handed back a Common. Nobody would
	ever press that button twice.
]]
FusionConfig.SuccessChance = {
	Common = 0.70,
	Rare = 0.50,
	Epic = 0.35,
	Legendary = 0.20,
	-- Mythic is the top tier and can't be fused.
} :: { [string]: number }

-- The Fusion Machine always consumes exactly this many same-tier items per attempt.
FusionConfig.ItemsRequiredPerFusion = 2

function FusionConfig.GetNextTier(tier: string): string?
	for index, candidate in FusionConfig.TierOrder do
		if candidate == tier then
			return FusionConfig.TierOrder[index + 1]
		end
	end
	return nil
end

function FusionConfig.CanFuseTier(tier: string): boolean
	return FusionConfig.SuccessChance[tier] ~= nil and FusionConfig.GetNextTier(tier) ~= nil
end

--[[ Gacha --------------------------------------------------------------------
	Odds for a Gacha Pad pull. Must sum to 1.
]]
FusionConfig.GachaRates = {
	Common = 0.78,
	Rare = 0.18,
	Epic = 0.035,
	Legendary = 0.0045,
	Mythic = 0.0005,
} :: { [string]: number }

do
	local total = 0
	for _, rate in FusionConfig.GachaRates do
		total += rate
	end
	assert(math.abs(total - 1) < 1e-6, "FusionConfig.GachaRates must sum to 1")
end

-- Rolls a Gacha Pad result tier using cumulative-weight RNG.
function FusionConfig.RollGachaTier(randomInstance: Random?): string
	local rng = randomInstance or Random.new()
	local roll = rng:NextNumber()
	local cumulative = 0
	for _, tier in FusionConfig.TierOrder do
		cumulative += FusionConfig.GachaRates[tier]
		if roll <= cumulative then
			return tier
		end
	end
	return FusionConfig.TierOrder[#FusionConfig.TierOrder]
end

-- Per-tier accent color, shared by the machine's own styling, the odds panel,
-- and the client's reveal effects, so a given tier always reads the same
-- color everywhere it shows up.
FusionConfig.TierAccentColors = {
	Common = Color3.fromRGB(200, 200, 200),
	Rare = Color3.fromRGB(60, 160, 255),
	Epic = Color3.fromRGB(190, 60, 255),
	Legendary = Color3.fromRGB(255, 190, 40),
	Mythic = Color3.fromRGB(255, 60, 90),
} :: { [string]: Color3 }

-- Tiers dramatic enough to warrant the "big reveal" treatment (longer pause,
-- screen shake, bigger particle burst, distinct sound) instead of the quick,
-- understated one. See RevealEffects.PlayReveal.
FusionConfig.MajorRevealTiers = {
	Epic = true,
	Legendary = true,
	Mythic = true,
} :: { [string]: boolean }

return FusionConfig
