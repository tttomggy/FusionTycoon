--!strict
--[[
	FuseLadder
	----------
	The pure rules behind "the Fuse panel leads you up the ladder"
	(UI/FusePanel, ResultController's fusion card). Everything takes plain
	counts, so /selftest runs it with stubbed inventories.

	  PickTab      the tab the panel opens on / jumps to: the HIGHEST tier with
	               >= 2 fusable orbs that the player may fuse; Common when
	               nothing is fusable.
	  IsReady      a tab with >= 2 fusable orbs gets the pulsing ready dot.
	  BestOwned    the highest tier the player owns (the ladder strip lights it).
	  NextAim      the tier above BestOwned: the strip's pulsing "Next: Epic".
	  ResultNext   under a fusion's "NEW ORB!": a "Fuse 2 Rares -> Epic next"
	               button when the player owns >= 2 of the new tier, else the
	               "Pull more orbs" line with the Gacha arrow.

	Tier names, order and gates come from FusionConfig, never typed here.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local GoalSteps = require(ReplicatedStorage.Shared.Modules.GoalSteps)

local FuseLadder = {}

FuseLadder.PullLine = "Pull more orbs, then fuse 2 of these!"

export type Counts = { [string]: number }

export type ResultNext = {
	Kind: string, -- "Fuse" | "Pull" | "None"
	Tier: string?, -- the tab to jump to (the new orb's tier)
	NextTier: string?, -- what fusing it makes
	Line: string?,
	Button: string?,
}

-- >= MinFusionInputs fusable orbs: the tab has something to fuse.
function FuseLadder.IsReady(count: number): boolean
	return count >= FusionConfig.MinFusionInputs
end

-- The tab to open on: the highest tier with a fusable pair that `rebirths`
-- lets the player fuse; the first tier (Common) when there is none.
function FuseLadder.PickTab(counts: Counts, rebirths: number): string
	local order = FusionConfig.TierOrder
	for index = #order, 1, -1 do
		local tier = order[index]
		if FusionConfig.CanFuseTierFor(tier, rebirths) and FuseLadder.IsReady(counts[tier] or 0) then
			return tier
		end
	end
	return order[1]
end

-- The highest tier with at least one orb owned; nil with an empty inventory.
function FuseLadder.BestOwned(counts: Counts): string?
	local order = FusionConfig.TierOrder
	for index = #order, 1, -1 do
		if (counts[order[index]] or 0) > 0 then
			return order[index]
		end
	end
	return nil
end

-- The tier to aim for: the one above the best owned (Common's Rare for an
-- empty inventory). nil once the top tier is owned.
function FuseLadder.NextAim(counts: Counts): string?
	local best = FuseLadder.BestOwned(counts)
	if best == nil then
		return FusionConfig.GetNextTier(FusionConfig.TierOrder[1])
	end
	return FusionConfig.GetNextTier(best)
end

-- After a successful fusion made a `newTier` orb and the player now owns
-- `ownedOfNewTier` of them (the new one included).
function FuseLadder.ResultNext(newTier: string, ownedOfNewTier: number, rebirths: number): ResultNext
	local nextTier = FusionConfig.GetNextTier(newTier)
	if nextTier == nil or not FusionConfig.CanFuseTierFor(newTier, rebirths) then
		return { Kind = "None" }
	end
	if FuseLadder.IsReady(ownedOfNewTier) then
		return {
			Kind = "Fuse",
			Tier = newTier,
			NextTier = nextTier,
			Line = ("Fuse %d %s → %s next"):format(FusionConfig.MinFusionInputs, GoalSteps.Plural(newTier), nextTier),
			Button = ("GO TO %s"):format(newTier:upper()),
		}
	end
	return { Kind = "Pull", Tier = newTier, NextTier = nextTier, Line = FuseLadder.PullLine }
end

return FuseLadder
