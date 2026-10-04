--!strict
--[[
	MutationConfig
	--------------
	Mutations every gacha pull and every successful fusion can roll. An item
	keeps its tier colour; a mutation multiplies what it earns on a pedestal
	and gives it a shell (PedestalVisuals) and a name prefix.

	  Mutation   Rank  Income x  Pull chance  Fusion-success chance  Source
	  (none)     0     1         -            -
	  Golden     1     2         4%           2%                     pulls / fusions
	  Charged    2     3         0            0                      Power Surge lightning only
	  Diamond    3     5         0.8%         0.4%                   pulls / fusions
	  Void       4     8         0            0                      Void Moon fusions only
	  Rainbow    5     12        0.1%         0.05%                  pulls / fusions
	  Celestial  6     20        0            0                      Meteor Shower cores only

	Ranks follow the multiplier. Saves store the NAME, so re-ranking is safe;
	the fusion rules compare ranks (a success keeps the lowest input rank, a
	fail keeps the best input). Event-only mutations (EventOnly) have no
	normal chance: only their event grants them (EventService).

	Every chance is x luck (RebirthConfig.GetLuck) x an optional per-mutation
	event multiplier (EventState.GetMutationMultipliers; this config never
	requires an event module). Mirrored in tools/econ_sim.py (MUTATIONS);
	change both together.
]]
local MutationConfig = {}

export type MutationSource = "Pull" | "Fusion"

export type MutationDef = {
	Rank: number,
	Multiplier: number,
	PullChance: number,
	FusionChance: number,
	EventOnly: boolean?, -- only an event grants it (no normal chance)
}

MutationConfig.Mutations = {
	Golden = { Rank = 1, Multiplier = 2, PullChance = 0.04, FusionChance = 0.02 },
	Charged = { Rank = 2, Multiplier = 3, PullChance = 0, FusionChance = 0, EventOnly = true },
	Diamond = { Rank = 3, Multiplier = 5, PullChance = 0.008, FusionChance = 0.004 },
	Void = { Rank = 4, Multiplier = 8, PullChance = 0, FusionChance = 0, EventOnly = true },
	Rainbow = { Rank = 5, Multiplier = 12, PullChance = 0.001, FusionChance = 0.0005 },
	Celestial = { Rank = 6, Multiplier = 20, PullChance = 0, FusionChance = 0, EventOnly = true },
} :: { [string]: MutationDef }

-- Lowest rank first; "Normal" (no mutation) is not in this list.
MutationConfig.Order = { "Golden", "Charged", "Diamond", "Void", "Rainbow", "Celestial" }

-- Granted only by an event (the Index marks these columns with a clock).
function MutationConfig.IsEventOnly(mutation: string?): boolean
	local def = mutation and MutationConfig.Mutations[mutation]
	return def ~= nil and def.EventOnly == true
end

-- True for a known mutation name (nil = normal is handled by callers).
function MutationConfig.IsValid(mutation: any): boolean
	return typeof(mutation) == "string" and MutationConfig.Mutations[mutation] ~= nil
end

function MutationConfig.GetMultiplier(mutation: string?): number
	local def = mutation and MutationConfig.Mutations[mutation]
	return if def then def.Multiplier else 1
end

function MutationConfig.GetRank(mutation: string?): number
	local def = mutation and MutationConfig.Mutations[mutation]
	return if def then def.Rank else 0
end

-- Event odds multipliers by mutation (EventState.GetMutationMultipliers);
-- a missing entry is x1.
export type OddsMultipliers = { [string]: number }

-- The chance of `mutation` from `source` at `luck` (x its event multiplier).
function MutationConfig.GetChance(mutation: string, source: MutationSource, luck: number, multipliers: OddsMultipliers?): number
	local def = MutationConfig.Mutations[mutation]
	if not def then
		return 0
	end
	local event = if multipliers then multipliers[mutation] or 1 else 1
	return (if source == "Pull" then def.PullChance else def.FusionChance) * math.max(luck, 0) * event
end

-- One roll against the cumulative chances, rarest first. nil = no mutation.
function MutationConfig.Roll(rng: Random, luck: number, source: MutationSource, multipliers: OddsMultipliers?): string?
	local roll = rng:NextNumber()
	local cumulative = 0
	for index = #MutationConfig.Order, 1, -1 do
		local mutation = MutationConfig.Order[index]
		cumulative += MutationConfig.GetChance(mutation, source, luck, multipliers)
		if roll < cumulative then
			return mutation
		end
	end
	return nil
end

-- The higher-ranked of two mutations (either may be nil); `a` on a tie.
function MutationConfig.Better(a: string?, b: string?): string?
	return if MutationConfig.GetRank(b) > MutationConfig.GetRank(a) then b else a
end

-- The lower-ranked of two mutations; nil if either is normal.
function MutationConfig.Worse(a: string?, b: string?): string?
	return if MutationConfig.GetRank(b) < MutationConfig.GetRank(a) then b else a
end

-- "Golden Star Core"; just the item name for a normal item.
function MutationConfig.GetDisplayName(itemName: string, mutation: string?): string
	if mutation and MutationConfig.Mutations[mutation] then
		return ("%s %s"):format(mutation, itemName)
	end
	return itemName
end

return MutationConfig
