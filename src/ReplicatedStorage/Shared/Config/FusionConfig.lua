--!strict
local FusionConfig = {}

local RebirthConfig = require(script.Parent.RebirthConfig)
local MutationConfig = require(script.Parent.MutationConfig)

FusionConfig.TierOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

--[[ Fusion -------------------------------------------------------------------
	Put 2 to 6 items of one tier into the Fuse panel:
	  success -> 1 random item of the next tier
	  fail    -> you keep your best input (highest mutation rank; the first
	             on a tie) and lose the rest
	More inputs = a higher chance. Mirrored in tools/econ_sim.py (FUSE_CHANCE).
]]
FusionConfig.MinFusionInputs = 2
FusionConfig.MaxFusionInputs = 6

-- Success chance by tier and input count.
FusionConfig.SuccessChanceByCount = {
	Common = { [2] = 0.55, [3] = 0.68, [4] = 0.78, [5] = 0.90, [6] = 1.00 },
	Rare = { [2] = 0.45, [3] = 0.57, [4] = 0.66, [5] = 0.74, [6] = 0.80 },
	Epic = { [2] = 0.35, [3] = 0.45, [4] = 0.53, [5] = 0.60, [6] = 0.66 },
	Legendary = { [2] = 0.20, [3] = 0.27, [4] = 0.33, [5] = 0.39, [6] = 0.45 },
	-- Needs RebirthConfig.SecretFusionRebirths (CanFuseTierFor).
	Mythic = { [2] = 0.07, [3] = 0.09, [4] = 0.11, [5] = 0.13, [6] = 0.15 },
	-- Secret is the top tier and can't be fused.
} :: { [string]: { [number]: number } }

-- Chance that `count` items of `tier` fuse into the next tier; 0 if that
-- tier or count can't be fused.
-- `bonus`: an event's success bonus (EventState.GetFusionSuccessBonus,
-- Void Moon +0.10), added on top and capped at 100%.
function FusionConfig.GetFusionChance(tier: string, count: number, bonus: number?): number
	local byCount = FusionConfig.SuccessChanceByCount[tier]
	local base = if byCount then byCount[count] or 0 else 0
	if base <= 0 then
		return 0
	end
	return math.min(1, base + (bonus or 0))
end

-- Fuse All only fuses pairs (count 2, unmutated) up to this tier (Common,
-- Rare, Epic). A failed Legendary fusion costs a Legendary, so that stays
-- a manual choice.
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
	return FusionConfig.SuccessChanceByCount[tier] ~= nil and FusionConfig.GetNextTier(tier) ~= nil
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

--[[ Odds disclosure ------------------------------------------------------------
	ONE formatter for every odds display (the gacha pad label, the Fusion
	Machine board), built from the same functions the rolls use, so a paid
	luck boost can never show different numbers from what's rolled.
]]

-- A percentage with at least 2 significant figures and never "0":
-- 77.9, 18, 3.5, 0.50, 0.055, 0.0022.
function FusionConfig.FormatPercent(percent: number): string
	if percent >= 10 then
		local text = ("%.1f"):format(percent)
		return (text:gsub("%.0$", ""))
	end
	if percent <= 0 then
		return "0"
	end
	local decimals = math.max(0, 1 - math.floor(math.log10(percent)))
	-- Nudge so a value sitting on a rounding edge (0.495) rounds half up.
	return ("%." .. decimals .. "f"):format(percent * (1 + 1e-9))
end

export type FusionOddsRow = {
	FromTier: string,
	ToTier: string,
	-- Index i = MinFusionInputs + i - 1 inputs: "55%", "68%", ... "100%".
	ChanceTexts: { string },
	RebirthsNeeded: number?,
}

export type Odds = {
	Gacha: string, -- "Common 77.9 · Rare 18 · ... · Secret 0.0022%"
	PullMutations: string, -- "Golden 4.4% · Diamond 0.88% · Rainbow 0.11%"
	Fusion: { FusionOddsRow },
	FusionMutations: string, -- "Golden 2.2% · Diamond 0.44% · Rainbow 0.055%"
}

local function mutationLine(source: MutationConfig.MutationSource, luck: number, multipliers: MutationConfig.OddsMultipliers?): string
	local parts = {}
	for _, mutation in MutationConfig.Order do
		local chance = MutationConfig.GetChance(mutation, source, luck, multipliers)
		-- Event-only mutations (no normal chance) aren't listed here.
		if chance > 0 then
			table.insert(parts, ("%s %s%%"):format(mutation, FusionConfig.FormatPercent(chance * 100)))
		end
	end
	return table.concat(parts, " · ")
end

-- The live event's effect on the odds (EventState): per-source mutation
-- multipliers and the fusion success bonus. nil = no event.
export type OddsEvent = {
	PullMultipliers: MutationConfig.OddsMultipliers?,
	FusionMultipliers: MutationConfig.OddsMultipliers?,
	FusionBonus: number?,
}

-- Every odds line at `luck` (RebirthConfig.GetLuck), with the live event's
-- boosts when given: the same functions the rolls use.
function FusionConfig.FormatOdds(luck: number, event: OddsEvent?): Odds
	local rates = FusionConfig.GetGachaRates(luck)
	local gacha = {}
	for _, tier in FusionConfig.TierOrder do
		table.insert(gacha, ("%s %s"):format(tier, FusionConfig.FormatPercent((rates[tier] or 0) * 100)))
	end
	local fusion: { FusionOddsRow } = {}
	for _, tier in FusionConfig.TierOrder do
		local nextTier = FusionConfig.GetNextTier(tier)
		if nextTier and FusionConfig.CanFuseTier(tier) then
			local texts = {}
			for count = FusionConfig.MinFusionInputs, FusionConfig.MaxFusionInputs do
				local chance = FusionConfig.GetFusionChance(tier, count, event and event.FusionBonus)
				table.insert(texts, FusionConfig.FormatPercent(chance * 100) .. "%")
			end
			table.insert(fusion, {
				FromTier = tier,
				ToTier = nextTier,
				ChanceTexts = texts,
				RebirthsNeeded = FusionConfig.RebirthGatedTiers[tier],
			})
		end
	end
	return {
		Gacha = table.concat(gacha, " · ") .. "%",
		PullMutations = mutationLine("Pull", luck, event and event.PullMultipliers),
		Fusion = fusion,
		FusionMutations = mutationLine("Fusion", luck, event and event.FusionMultipliers),
	}
end

-- Diamond and up (Diamond, Void, Rainbow, Celestial) get the major reveal
-- whatever the tier.
FusionConfig.MajorRevealMutationRank = 3

function FusionConfig.IsMajorReveal(tier: string, mutation: string?): boolean
	return FusionConfig.MajorRevealTiers[tier] == true
		or MutationConfig.GetRank(mutation) >= FusionConfig.MajorRevealMutationRank
end

return FusionConfig
