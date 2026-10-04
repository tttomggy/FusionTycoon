--!strict
--[[
	RewardConfig
	------------
	The free rewards DailyConfig and GiftConfig hand out, and the words for
	them. RewardService (server) grants them; the Daily card and the Gifts
	panel describe them with the same functions, so a label and its grant
	always agree.

	Kinds:
	  Cash         Seconds of BASE income (no timed boosts), like the shop's
	               cash packs, never less than Floor
	  IncomeBoost  Seconds into the shop's ×2 income boost bank
	               (ShopConfig.BoostMultiplier)
	  LuckBoost    Seconds into the Luck Potion bank
	               (ShopConfig.LuckPotionMultiplier)
	  Pulls        Count free gacha pulls: the real pull (rolls, Index,
	               reveal), paid by the game; they don't raise your pad
	               price
	  SafeFusion   Count Safe Fusion tokens
	  Item         One item: a tier by Odds weights, then the normal pull
	               mutation roll
]]
local RewardConfig = {}

export type Kind = "Cash" | "IncomeBoost" | "LuckBoost" | "Pulls" | "SafeFusion" | "Item"

export type TierOdds = { Tier: string, Weight: number }

export type Reward = {
	Kind: Kind,
	Seconds: number?, -- Cash / IncomeBoost / LuckBoost
	Floor: number?, -- Cash: the least it pays
	Count: number?, -- Pulls / SafeFusion
	Odds: { TierOdds }?, -- Item
}

local ICONS: { [string]: string } = {
	Cash = "💰",
	IncomeBoost = "⚡",
	LuckBoost = "🍀",
	Pulls = "🎰",
	SafeFusion = "🛡",
	Item = "🔮",
}

-- "10 min", "1 h", "90 s".
function RewardConfig.FormatDuration(seconds: number): string
	if seconds >= 3600 and seconds % 3600 == 0 then
		return ("%d h"):format(seconds // 3600)
	elseif seconds >= 60 then
		return ("%d min"):format(math.floor(seconds / 60))
	end
	return ("%d s"):format(seconds)
end

function RewardConfig.GetIcon(reward: Reward): string
	return ICONS[reward.Kind] or "🎁"
end

-- What a Cash reward pays at `baseIncome` ($/s without timed boosts).
function RewardConfig.GetCashAmount(reward: Reward, baseIncome: number): number
	if reward.Kind ~= "Cash" then
		return 0
	end
	return math.max(reward.Floor or 0, math.floor(math.max(0, baseIncome) * (reward.Seconds or 0)))
end

-- "Epic 70% · Legendary 25% · Mythic 5%".
function RewardConfig.FormatOdds(odds: { TierOdds }): string
	local total = 0
	for _, entry in odds do
		total += entry.Weight
	end
	local parts = {}
	for _, entry in odds do
		local percent = if total > 0 then entry.Weight / total * 100 else 0
		table.insert(parts, ("%s %s%%"):format(entry.Tier, if percent % 1 == 0 then tostring(math.floor(percent)) else ("%.1f"):format(percent)))
	end
	return table.concat(parts, " · ")
end

-- The lowest tier an Item reward can give ("Epic").
local function lowestTier(reward: Reward): string
	local odds = reward.Odds
	return if odds and odds[1] then odds[1].Tier else "Item"
end

-- The short tile label: "10 min", "×2 · 15 min", "3 pulls", "Epic+".
function RewardConfig.GetShortLabel(reward: Reward): string
	local kind = reward.Kind
	if kind == "Cash" then
		return RewardConfig.FormatDuration(reward.Seconds or 0)
	elseif kind == "IncomeBoost" or kind == "LuckBoost" then
		return ("×2 · %s"):format(RewardConfig.FormatDuration(reward.Seconds or 0))
	elseif kind == "Pulls" then
		local count = reward.Count or 1
		return if count == 1 then "1 pull" else ("%d pulls"):format(count)
	elseif kind == "SafeFusion" then
		return "Safe Fusion"
	end
	return lowestTier(reward) .. "+"
end

-- The full line: "10 min of income", "×2 income for 15 min", "3 free
-- pulls", "×2 luck for 15 min", "1 Safe Fusion token", "1 Epic+ item".
function RewardConfig.GetTitle(reward: Reward): string
	local kind = reward.Kind
	local duration = RewardConfig.FormatDuration(reward.Seconds or 0)
	if kind == "Cash" then
		return ("%s of income"):format(duration)
	elseif kind == "IncomeBoost" then
		return ("×2 income for %s"):format(duration)
	elseif kind == "LuckBoost" then
		return ("×2 luck for %s"):format(duration)
	elseif kind == "Pulls" then
		local count = reward.Count or 1
		return if count == 1 then "1 free pull" else ("%d free pulls"):format(count)
	elseif kind == "SafeFusion" then
		local count = reward.Count or 1
		return if count == 1 then "1 Safe Fusion token" else ("%d Safe Fusion tokens"):format(count)
	end
	return ("1 %s+ item"):format(lowestTier(reward))
end

-- Rolls an Item reward's tier (weights in order).
function RewardConfig.RollTier(odds: { TierOdds }, rng: Random): string
	local total = 0
	for _, entry in odds do
		total += entry.Weight
	end
	local roll = rng:NextNumber() * total
	for _, entry in odds do
		roll -= entry.Weight
		if roll < 0 then
			return entry.Tier
		end
	end
	return odds[#odds].Tier
end

-- The UTC day number (days since 1970-01-01 UTC) of `time` (os.time()).
function RewardConfig.GetUtcDay(time: number): number
	return time // 86400
end

return RewardConfig
