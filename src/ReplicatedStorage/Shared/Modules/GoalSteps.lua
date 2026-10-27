--!strict
--[[
	GoalSteps
	---------
	What to do NEXT for an "own a tier" goal (GoalConfig Kind = "OwnTier"),
	from the player's inventory. Pure and shared: GoalService calls Compute on
	every sync and ships the Step with GoalProgress; the HUD tracker calls
	Format on it; /selftest calls both on stubbed inventories.

	Goal tier G, input tier I (the one below G):

	  Fuse       >= 2 orbs of I: fuse them (N = min(owned, 6)) at the Fusion
	             Machine; BestChance is the 6-orb chance while more orbs help
	  FuseLower  < 2 of I but >= 2 of a lower tier: fuse that into I first
	  Pull       nothing to fuse, a pull is affordable: Gacha Pad
	  Earn       nothing to fuse, no pull affordable: cash first (UPGRADES)

	Odds and gating are FusionConfig's (GetFusionChance, CanFuseTierFor,
	MinFusionInputs / MaxFusionInputs), the same rules FusionService rolls.
]]
local FusionConfig = require(script.Parent.Parent.Config.FusionConfig)
local NumberFormat = require(script.Parent.NumberFormat)
local UITheme = require(script.Parent.UITheme)

local GoalSteps = {}

export type Step = {
	Kind: string, -- "Fuse" | "FuseLower" | "Pull" | "Earn"
	Tier: string, -- I, the tier the goal's fusion consumes
	Owned: number, -- orbs of I owned (not carried by a thief)
	Lower: string?, -- FuseLower: the lower tier to fuse into I
	Count: number?, -- Fuse: N
	Chance: number?, -- Fuse: success chance with N orbs
	BestChance: number?, -- Fuse: the 6-orb chance; nil when more orbs don't help
	Cost: number?, -- Earn: the next pull's price
	Target: string, -- GoalConfig-style marker target for this action
}

export type Input = {
	Counts: { [string]: number }, -- orbs owned per tier
	Rebirths: number,
	Cash: number,
	PullCost: number, -- the next Gacha pull's price
	FreePulls: number, -- free pulls left (a pull is affordable with any)
	FusionBonus: number, -- event + armed Fusion Spark, as the Fuse panel adds it
}

export type Lines = {
	Line: string,
	Hint: string?,
}

GoalSteps.Targets = {
	Fuse = "FusionMachine",
	FuseLower = "FusionMachine",
	Pull = "GachaStation",
	Earn = "ui:Upgrades",
}

-- The tier an "own a tier" goal wants, nil for any other goal.
function GoalSteps.GetGoalTier(goal: { Kind: string?, Tier: string? }): string?
	return if goal.Kind == "OwnTier" then goal.Tier else nil
end

-- The tier below `tier` (the one fused to make it).
function GoalSteps.GetInputTier(tier: string): string?
	local index = table.find(FusionConfig.TierOrder, tier)
	return if index and index > 1 then FusionConfig.TierOrder[index - 1] else nil
end

function GoalSteps.Compute(goalTier: string, input: Input): Step?
	local inputTier = GoalSteps.GetInputTier(goalTier)
	if not inputTier then
		return nil
	end
	local owned = input.Counts[inputTier] or 0
	local minInputs = FusionConfig.MinFusionInputs
	local maxInputs = FusionConfig.MaxFusionInputs

	if FusionConfig.CanFuseTierFor(inputTier, input.Rebirths) then
		if owned >= minInputs then
			local count = math.min(owned, maxInputs)
			local chance = FusionConfig.GetFusionChance(inputTier, count, input.FusionBonus)
			local best = FusionConfig.GetFusionChance(inputTier, maxInputs, input.FusionBonus)
			return {
				Kind = "Fuse",
				Tier = inputTier,
				Owned = owned,
				Count = count,
				Chance = chance,
				BestChance = if count < maxInputs and chance < 1 and best > chance then best else nil,
				Target = GoalSteps.Targets.Fuse,
			}
		end
		-- The highest lower tier with a pair to fuse up.
		local inputIndex = table.find(FusionConfig.TierOrder, inputTier) :: number
		for index = inputIndex - 1, 1, -1 do
			local lower = FusionConfig.TierOrder[index]
			if FusionConfig.CanFuseTierFor(lower, input.Rebirths) and (input.Counts[lower] or 0) >= minInputs then
				return {
					Kind = "FuseLower",
					Tier = inputTier,
					Owned = owned,
					Lower = lower,
					Target = GoalSteps.Targets.FuseLower,
				}
			end
		end
	end

	if input.FreePulls > 0 or input.Cash >= input.PullCost then
		return { Kind = "Pull", Tier = inputTier, Owned = owned, Target = GoalSteps.Targets.Pull }
	end
	return { Kind = "Earn", Tier = inputTier, Owned = owned, Cost = input.PullCost, Target = GoalSteps.Targets.Earn }
end

--[[ Text ----------------------------------------------------------------- ]]

-- "Legendary" -> "Legendaries", "Epic" -> "Epics".
function GoalSteps.Plural(tier: string): string
	if tier:sub(-1) == "y" then
		return tier:sub(1, -2) .. "ies"
	end
	return tier .. "s"
end

local function percent(chance: number): string
	return FusionConfig.FormatPercent(chance * 100) .. "%"
end

-- The tier word in its rarity colour (RichText).
local function tierWord(tier: string, plural: boolean): string
	local word = if plural then GoalSteps.Plural(tier) else tier
	return ('<font color="%s">%s</font>'):format(UITheme.ToHex(UITheme.GetTierLight(tier)), word)
end

-- RichText lines for the tracker: the action, and the small odds hint.
function GoalSteps.Format(step: Step): Lines
	if step.Kind == "Fuse" then
		local count = step.Count or FusionConfig.MinFusionInputs
		local line = ("Fuse your %d %s: %s"):format(count, tierWord(step.Tier, true), percent(step.Chance or 0))
		local hint = if step.BestChance
			then ("More %s = better odds (%d → %s)"):format(tierWord(step.Tier, true), FusionConfig.MaxFusionInputs, percent(step.BestChance))
			else nil
		return { Line = line, Hint = hint }
	elseif step.Kind == "FuseLower" then
		local lower = step.Lower or step.Tier
		return {
			Line = ("Fuse %s to make %s (%d / %d %s)"):format(
				tierWord(lower, true),
				tierWord(step.Tier, true),
				math.min(step.Owned, FusionConfig.MinFusionInputs),
				FusionConfig.MinFusionInputs,
				tierWord(step.Tier, false)
			),
		}
	elseif step.Kind == "Pull" then
		return {
			Line = ("Pull from the Gacha for more orbs (%d / %d %s)"):format(
				math.min(step.Owned, FusionConfig.MinFusionInputs),
				FusionConfig.MinFusionInputs,
				tierWord(step.Tier, false)
			),
		}
	end
	return { Line = ("Earn cash for your next pull (%s)"):format(NumberFormat.Money(step.Cost or 0)) }
end

-- `text` without its RichText tags (what /selftest compares).
function GoalSteps.Plain(text: string): string
	return (text:gsub("<[^>]+>", ""))
end

return GoalSteps
