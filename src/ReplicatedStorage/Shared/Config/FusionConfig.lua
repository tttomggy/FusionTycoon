--!strict
local FusionConfig = {}

local RebirthConfig = require(script.Parent.RebirthConfig)

FusionConfig.TierOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

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
	Mythic = 0.08, -- needs RebirthConfig.SecretFusionRebirths (CanFuseTierFor)
	-- Secret is the top tier and can't be fused.
} :: { [string]: number }

-- The Fusion Machine always consumes exactly this many same-tier items per attempt.
FusionConfig.ItemsRequiredPerFusion = 2

-- Fuse All only fuses pairs up to this tier (Common, Rare, Epic). A failed
-- Legendary fusion costs a Legendary, so that stays a manual choice.
FusionConfig.FuseAllMaxTier = "Epic"
FusionConfig.FuseAllMaxFusions = 500 -- safety cap per Fuse All

-- Tiers Fuse All may consume, lowest first.
function FusionConfig.GetFuseAllTiers(): { string }
	local tiers = {}
	for _, tier in FusionConfig.TierOrder do
		if FusionConfig.CanFuseTier(tier) then
			table.insert(tiers, tier)
		end
		if tier == FusionConfig.FuseAllMaxTier then
			break
		end
	end
	return tiers
end

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

-- Tiers whose fusion is gated behind a rebirth count: Mythic -> Secret.
FusionConfig.RebirthGatedTiers = {
	Mythic = RebirthConfig.SecretFusionRebirths,
} :: { [string]: number }

-- CanFuseTier, plus the rebirth gate. FusionService enforces it (rejecting
-- with "NeedsRebirth"); the client shows a lock instead of the fuse prompt.
function FusionConfig.CanFuseTierFor(tier: string, rebirths: number): boolean
	if not FusionConfig.CanFuseTier(tier) then
		return false
	end
	local needed = FusionConfig.RebirthGatedTiers[tier]
	return needed == nil or rebirths >= needed
end

--[[ Gacha --------------------------------------------------------------------
	Odds for a Gacha Pad pull. Must sum to 1.
]]
FusionConfig.GachaRates = {
	Common = 0.77998,
	Rare = 0.18,
	Epic = 0.035,
	Legendary = 0.0045,
	Mythic = 0.0005,
	Secret = 0.00002,
} :: { [string]: number }

do
	local total = 0
	for _, rate in FusionConfig.GachaRates do
		total += rate
	end
	assert(math.abs(total - 1) < 1e-6, "FusionConfig.GachaRates must sum to 1")
end

-- Tiers whose odds rebirth luck multiplies; Common absorbs the difference.
FusionConfig.LuckyTiers = { "Legendary", "Mythic", "Secret" }

-- The effective gacha odds at `luck` (RebirthConfig.GetLuck; 1 = base).
-- Luck multiplies the LuckyTiers' rates and Common takes up the slack, so
-- the table still sums to 1. Every odds display uses this with the
-- player's luck, the same as the roll.
function FusionConfig.GetGachaRates(luck: number): { [string]: number }
	local rates = table.clone(FusionConfig.GachaRates)
	for _, tier in FusionConfig.LuckyTiers do
		rates[tier] = (rates[tier] or 0) * math.max(luck, 0)
	end
	local others = 0
	for tier, rate in rates do
		if tier ~= "Common" then
			others += rate
		end
	end
	rates.Common = math.max(0, 1 - others)
	return rates
end

-- Rolls a Gacha Pad result tier at `luck` using cumulative-weight RNG.
function FusionConfig.RollGachaTier(randomInstance: Random?, luck: number?): string
	local rng = randomInstance or Random.new()
	local rates = FusionConfig.GetGachaRates(luck or 1)
	local roll = rng:NextNumber()
	local cumulative = 0
	for _, tier in FusionConfig.TierOrder do
		cumulative += rates[tier] or 0
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
	Secret = Color3.fromRGB(61, 255, 208), -- mint #3DFFD0, same as UITheme.TierLight.Secret
} :: { [string]: Color3 }

-- Tiers dramatic enough to warrant the "big reveal" treatment (longer pause,
-- screen shake, bigger particle burst, distinct sound) instead of the quick,
-- understated one. See RevealEffects.PlayReveal.
FusionConfig.MajorRevealTiers = {
	Epic = true,
	Legendary = true,
	Mythic = true,
	Secret = true,
} :: { [string]: boolean }

return FusionConfig
