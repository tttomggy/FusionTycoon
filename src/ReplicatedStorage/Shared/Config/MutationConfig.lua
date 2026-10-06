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

	STACKING (Grow a Garden style): an item has ONE base mutation (none /
	Golden / Diamond / Rainbow: Item.Mutation) plus any SET of event
	mutations (Charged / Void / Celestial: Item.EventMutations, sorted by
	rank, never the same one twice). The multiplier is additive:
	1 + sum(mult - 1), so Rainbow + Celestial = 31x, not 240x
	(GetStackedMultiplier; TycoonConfig.GetItemCashPerSecond). Events ADD
	to the set (AddEvent); a fusion success keeps the lowest base and the
	event mutations every input shares (Intersect).

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

-- The BASE roll: one roll against the cumulative chances of the base
-- mutations, rarest first. nil = no mutation. Event-only mutations are
-- never the base: RollEvents stacks them on top.
function MutationConfig.Roll(rng: Random, luck: number, source: MutationSource, multipliers: OddsMultipliers?): string?
	local roll = rng:NextNumber()
	local cumulative = 0
	for index = #MutationConfig.Order, 1, -1 do
		local mutation = MutationConfig.Order[index]
		if MutationConfig.IsEventOnly(mutation) then
			continue
		end
		cumulative += MutationConfig.GetChance(mutation, source, luck, multipliers)
		if roll < cumulative then
			return mutation
		end
	end
	return nil
end

-- The EVENT roll, on top of the base roll: each event-only mutation rolls
-- on its own (its chance x luck x the event multiplier; 0 outside its
-- event). Returns the set, or nil.
function MutationConfig.RollEvents(rng: Random, luck: number, source: MutationSource, multipliers: OddsMultipliers?): { string }?
	local list: { string } = {}
	for _, mutation in MutationConfig.Order do
		if MutationConfig.IsEventOnly(mutation) then
			local chance = MutationConfig.GetChance(mutation, source, luck, multipliers)
			if chance > 0 and rng:NextNumber() < chance then
				table.insert(list, mutation)
			end
		end
	end
	return if #list > 0 then list else nil
end

-- The higher-ranked of two mutations (either may be nil); `a` on a tie.
function MutationConfig.Better(a: string?, b: string?): string?
	return if MutationConfig.GetRank(b) > MutationConfig.GetRank(a) then b else a
end

-- The lower-ranked of two mutations; nil if either is normal.
function MutationConfig.Worse(a: string?, b: string?): string?
	return if MutationConfig.GetRank(b) < MutationConfig.GetRank(a) then b else a
end

--[[ Stacking ----------------------------------------------------------- ]]

-- An item's base mutation and event set (any table with these fields).
export type Stack = { Mutation: string?, EventMutations: { string }? }

local function byRank(a: string, b: string): boolean
	return MutationConfig.GetRank(a) < MutationConfig.GetRank(b)
end

-- A clean event set: known event-only names, no repeats, sorted by rank;
-- nil when empty (saves stay sparse). Anything else is dropped.
function MutationConfig.SanitizeEvents(value: unknown): { string }?
	if typeof(value) ~= "table" then
		return nil
	end
	local seen: { [string]: boolean } = {}
	local list: { string } = {}
	for _, name in value :: { any } do
		if typeof(name) == "string" and MutationConfig.IsEventOnly(name) and not seen[name] then
			seen[name] = true
			table.insert(list, name)
		end
	end
	if #list == 0 then
		return nil
	end
	table.sort(list, byRank)
	return list
end

-- Splits a base + set into the stacking shape: an event-only base (an old
-- save, or a source that hands one name) moves into the set. Returns
-- (base, events).
function MutationConfig.Normalize(base: string?, events: { string }?): (string?, { string }?)
	local list: { string } = table.clone(events or {})
	local cleanBase = if MutationConfig.IsValid(base) then base else nil
	if cleanBase and MutationConfig.IsEventOnly(cleanBase) then
		table.insert(list, cleanBase)
		cleanBase = nil
	end
	return cleanBase, MutationConfig.SanitizeEvents(list)
end

-- `events` plus `mutation` (an event-only name); the same set if it is
-- already there. Returns (newSet, added).
function MutationConfig.AddEvent(events: { string }?, mutation: string): ({ string }?, boolean)
	if not MutationConfig.IsEventOnly(mutation) then
		return events, false
	end
	if events and table.find(events, mutation) then
		return events, false
	end
	local list: { string } = table.clone(events or {})
	table.insert(list, mutation)
	return MutationConfig.SanitizeEvents(list), true
end

function MutationConfig.HasEvent(events: { string }?, mutation: string): boolean
	return events ~= nil and table.find(events, mutation) ~= nil
end

-- The event mutations EVERY set shares (a fusion success keeps these).
function MutationConfig.Intersect(sets: { { string }? }): { string }?
	if #sets == 0 then
		return nil
	end
	local list: { string } = {}
	local first: { string } = sets[1] or {}
	for _, name in first do
		local everywhere = true
		for i = 2, #sets do
			if not MutationConfig.HasEvent(sets[i], name) then
				everywhere = false
				break
			end
		end
		if everywhere then
			table.insert(list, name)
		end
	end
	return MutationConfig.SanitizeEvents(list)
end

-- Every mutation of a stack, base first then the events by rank.
function MutationConfig.List(base: string?, events: { string }?): { string }
	local list: { string } = {}
	if MutationConfig.IsValid(base) then
		table.insert(list, base :: string)
	end
	local extra: { string } = events or {}
	for _, name in extra do
		if MutationConfig.IsValid(name) and not table.find(list, name) then
			table.insert(list, name)
		end
	end
	return list
end

-- 1 + sum(mult - 1) over every mutation (additive stacking).
function MutationConfig.GetStackedMultiplier(base: string?, events: { string }?): number
	local total = 1
	for _, name in MutationConfig.List(base, events) do
		total += MutationConfig.GetMultiplier(name) - 1
	end
	return total
end

-- The highest-ranked mutation of a stack (the shell colour, the banner word).
function MutationConfig.GetTop(base: string?, events: { string }?): string?
	local top: string? = nil
	for _, name in MutationConfig.List(base, events) do
		top = MutationConfig.Better(top, name)
	end
	return top
end

-- Whether the two stacks are the same (base and set).
function MutationConfig.SameStack(baseA: string?, eventsA: { string }?, baseB: string?, eventsB: { string }?): boolean
	local a = MutationConfig.List(baseA, eventsA)
	local b = MutationConfig.List(baseB, eventsB)
	if #a ~= #b then
		return false
	end
	for _, name in a do
		if not table.find(b, name) then
			return false
		end
	end
	return true
end

-- "RAINBOW · CHARGED" (pills, labels); "" for a plain item.
function MutationConfig.GetStackLabel(base: string?, events: { string }?): string
	local words = {}
	for _, name in MutationConfig.List(base, events) do
		table.insert(words, string.upper(name))
	end
	return table.concat(words, " · ")
end

-- "Golden Star Core", "Rainbow Charged Star Core"; just the item name for a
-- normal item.
function MutationConfig.GetDisplayName(itemName: string, mutation: string?, events: { string }?): string
	local words = MutationConfig.List(mutation, events)
	if #words > 0 then
		return ("%s %s"):format(table.concat(words, " "), itemName)
	end
	return itemName
end

return MutationConfig
