--!strict
--[[
	EventConfig
	-----------
	Lab weather on a shared UTC clock. The schedule is DETERMINISTIC from the
	slot's start time, never random at runtime: every server and every client
	computes the same lineup with no messaging.

	  Slot                  Event
	  every hh:00           Night, 10 min (VoidMoonChance of nights: Void Moon)
	  every hh:15/:30/:45   one weather by weight: Golden Rain 40, Power Surge
	                        35, Meteor Shower 20, Rainbow Storm 5

	GetEventForSlot(slotStartUnix) draws from a HASH of the slot start (see
	slotDraw), not Random.new(slotStart): slot times are only 900 apart and
	Luau's Random gave correlated first draws for nearby seeds (three POWER
	SURGEs in a row). The hash is plain bit32 arithmetic, so the same code
	runs in tools/event_schedule_check.luau to verify the distribution. A
	slot is SlotSeconds (15 min) long and its event lasts Durations[id].
	Between events there is nothing on.

	Effects (all scaled by an event's Strength, 1 normally, admin x2/x3, and
	clamped so x3 can't break the economy) are pure functions here, so the
	server's rolls and every client's displays read the same numbers.
	EventState (Shared/Modules) feeds them the live event from workspace
	attributes; EventService runs the clock and the world effects.
	Mirrored in tools/econ_sim.py (--events).
]]
local EventConfig = {}

export type EventId = "GoldenRain" | "PowerSurge" | "MeteorShower" | "RainbowStorm" | "Night" | "VoidMoon"

export type EventSlot = {
	Id: string,
	StartsAt: number, -- unix seconds
	EndsAt: number,
}

EventConfig.SlotSeconds = 15 * 60
-- Everything an event puts in the world lives in Workspace.EventObjects.<Id>
-- (server objects and each client's own FX), so ending it is one
-- ClearAllChildren on each side. EventService builds the folders at Init.
EventConfig.ObjectsFolderName = "EventObjects"
EventConfig.NightMinute = 0 -- the hh:00 slot is always a night
EventConfig.VoidMoonChance = 0.15

EventConfig.Durations = {
	GoldenRain = 5 * 60,
	PowerSurge = 5 * 60,
	MeteorShower = 3 * 60,
	RainbowStorm = 5 * 60,
	Night = 10 * 60,
	VoidMoon = 10 * 60,
} :: { [string]: number }

-- Weather weights for the hh:15 / hh:30 / hh:45 slots.
EventConfig.WeatherWeights = {
	{ Id = "GoldenRain", Weight = 40 },
	{ Id = "PowerSurge", Weight = 35 },
	{ Id = "MeteorShower", Weight = 20 },
	{ Id = "RainbowStorm", Weight = 5 },
}

-- Every event the admin panel and /event can force, in display order.
EventConfig.Order = { "GoldenRain", "PowerSurge", "MeteorShower", "RainbowStorm", "Night", "VoidMoon" }

EventConfig.Names = {
	GoldenRain = "GOLDEN RAIN",
	PowerSurge = "POWER SURGE",
	MeteorShower = "METEOR SHOWER",
	RainbowStorm = "RAINBOW STORM",
	Night = "NIGHT",
	VoidMoon = "VOID MOON",
} :: { [string]: string }

EventConfig.Icons = {
	GoldenRain = "🪙",
	PowerSurge = "⚡",
	MeteorShower = "☄",
	RainbowStorm = "🌈",
	Night = "🌙",
	VoidMoon = "🌑",
} :: { [string]: string }

-- One line of what it does (the start banner).
EventConfig.Blurbs = {
	GoldenRain = "Grab the gold coins in your lab! Golden odds x3",
	PowerSurge = "Generators x1.25 · lightning can CHARGE a displayed item",
	MeteorShower = "Meteors hit the street: grab a core first!",
	RainbowStorm = "Every mutation chance x5!",
	Night = "Fusion mutation odds x2",
	VoidMoon = "Fusion success +5% · fusions can come out VOID",
} :: { [string]: string }

--[[ Effect numbers (at strength 1) ------------------------------------------ ]]

EventConfig.Strengths = { 1, 2, 3 } -- what the admin panel offers

-- Golden Rain: a coin per claimed plot every CoinIntervalSeconds / strength,
-- each worth CoinIncomeSeconds x strength of the owner's passive income.
EventConfig.CoinIntervalSeconds = 4
EventConfig.CoinIncomeSeconds = 3
EventConfig.CoinMaxIncomeSeconds = 15 -- clamp
EventConfig.CoinMaxLive = 30 -- per plot
EventConfig.CoinLifetimeSeconds = 20
EventConfig.CoinCollectDistance = 5 -- server distance check for a touch
EventConfig.GoldenRainGoldenOdds = 3

-- Power Surge: generators x(1 + 0.25 x strength), clamped; a lightning strike
-- every LightningIntervalSeconds / strength on one random displayed item.
EventConfig.SurgeGeneratorBonus = 0.25 -- was 0.5; cut with the Void Moon halving (15% target)
EventConfig.MaxGeneratorMultiplier = 3 -- clamp
EventConfig.LightningIntervalSeconds = 20
EventConfig.LightningChargeChance = 0.25

-- Meteor Shower: MeteorCount x strength meteors at random times; a core
-- gives one item of a tier by weight, ChanceCelestial of it Celestial.
EventConfig.MeteorCount = 6
EventConfig.MeteorGrabSeconds = 2
EventConfig.MeteorPromptDistance = 8
EventConfig.MeteorCraterLifetime = 60
EventConfig.MeteorFallSeconds = 2.5
EventConfig.MeteorCoreTiers = {
	{ Tier = "Epic", Weight = 60 },
	{ Tier = "Legendary", Weight = 30 },
	{ Tier = "Mythic", Weight = 9 },
	{ Tier = "Secret", Weight = 1 },
}
EventConfig.MeteorCelestialChance = 0.15

-- Night: fusion mutation odds x2. Void Moon (a night): also fusion success
-- +5 points (capped at 100%) and VoidChance of a success coming out Void.
-- Void Moon numbers were halved (and VoidMoonChance 0.3 -> 0.15) to keep
-- events within 15% of the no-event Rebirth 1-3 pace (econ_sim --events).
EventConfig.NightFusionMutationOdds = 2
EventConfig.VoidMoonFusionBonus = 0.05
EventConfig.VoidChance = 0.05

-- Rainbow Storm: every normal mutation chance x5 on pulls and fusions.
EventConfig.RainbowStormOdds = 5

EventConfig.MaxMutationOdds = 15 -- clamp for every mutation multiplier

--[[ The clock ------------------------------------------------------------------ ]]

-- a * b mod 2^32 (Luau numbers are doubles: split into 16-bit halves so no
-- product loses precision).
local function mul32(a: number, b: number): number
	local aHi, aLo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bHi, bLo = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	local mid = bit32.band(aHi * bLo + aLo * bHi, 0xFFFF)
	return bit32.band(aLo * bLo + bit32.lshift(mid, 16), 0xFFFFFFFF)
end

-- lowbias32 (an avalanche integer hash): every input bit flips about half
-- of the output bits, so neighbouring slot times give unrelated draws.
local function hash32(x: number): number
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x7FEB352D)
	x = bit32.bxor(x, bit32.rshift(x, 15))
	x = mul32(x, 0x846CA68B)
	return bit32.bxor(x, bit32.rshift(x, 16))
end

-- Draws discarded per slot before the real ones (belt and braces: with the
-- hash there is no warm-up correlation left, but it keeps the old intent).
local DISCARDED_DRAWS = 2

-- The k-th draw (1-based) for the slot starting at `start`, in [0, 1): a
-- pure function of the two, the same on every server and client.
local function slotDraw(start: number, k: number): number
	local seed = hash32(bit32.band(start, 0xFFFFFFFF))
	local h = hash32(bit32.bxor(seed, mul32(k + DISCARDED_DRAWS, 0x9E3779B9)))
	return h / 4294967296
end

local function pickWeather(draw: number): string
	local total = 0
	for _, entry in EventConfig.WeatherWeights do
		total += entry.Weight
	end
	local roll = draw * total
	for _, entry in EventConfig.WeatherWeights do
		roll -= entry.Weight
		if roll < 0 then
			return entry.Id
		end
	end
	return EventConfig.WeatherWeights[1].Id
end

-- The slot that contains `unix` (its start time).
function EventConfig.GetSlotStart(unix: number): number
	return math.floor(unix / EventConfig.SlotSeconds) * EventConfig.SlotSeconds
end

-- The event of the slot starting at `slotStartUnix`: a pure function of it.
function EventConfig.GetEventForSlot(slotStartUnix: number): EventSlot
	local start = math.floor(slotStartUnix)
	local minute = (start // 60) % 60
	local draw = slotDraw(start, 1)
	local id
	if minute == EventConfig.NightMinute then
		id = if draw < EventConfig.VoidMoonChance then "VoidMoon" else "Night"
	else
		id = pickWeather(draw)
	end
	return { Id = id, StartsAt = start, EndsAt = start + (EventConfig.Durations[id] or 0) }
end

-- The scheduled event running at `unix`, or nil between events.
function EventConfig.GetScheduledEvent(unix: number): EventSlot?
	local slot = EventConfig.GetEventForSlot(EventConfig.GetSlotStart(unix))
	return if unix < slot.EndsAt then slot else nil
end

-- Now (if one is running), then the next ones: `count` events in all.
function EventConfig.GetSchedule(unix: number, count: number): { EventSlot }
	local list = {}
	local slotStart = EventConfig.GetSlotStart(unix)
	local current = EventConfig.GetEventForSlot(slotStart)
	if unix < current.EndsAt then
		table.insert(list, current)
	end
	while #list < count do
		slotStart += EventConfig.SlotSeconds
		table.insert(list, EventConfig.GetEventForSlot(slotStart))
	end
	return list
end

--[[ Effects (pure; EventState feeds them the live event) ------------------------ ]]

local function clampOdds(multiplier: number): number
	return math.clamp(multiplier, 1, EventConfig.MaxMutationOdds)
end

-- A normal mutation's odds multiplier from `source` ("Pull" / "Fusion")
-- during `eventId` at `strength`. Event-only mutations aren't rolled here.
function EventConfig.GetMutationOddsMultiplier(eventId: string?, strength: number, mutation: string, source: string): number
	if eventId == "GoldenRain" and mutation == "Golden" then
		return clampOdds(EventConfig.GoldenRainGoldenOdds * strength)
	elseif eventId == "RainbowStorm" then
		return clampOdds(EventConfig.RainbowStormOdds * strength)
	elseif (eventId == "Night" or eventId == "VoidMoon") and source == "Fusion" then
		return clampOdds(EventConfig.NightFusionMutationOdds * strength)
	end
	return 1
end

-- Added to every fusion success chance (capped at 100% by the caller).
function EventConfig.GetFusionSuccessBonus(eventId: string?, strength: number): number
	if eventId == "VoidMoon" then
		return math.clamp(EventConfig.VoidMoonFusionBonus * strength, 0, 1)
	end
	return 0
end

-- Generator income multiplier (generators only, not pedestals).
function EventConfig.GetGeneratorMultiplier(eventId: string?, strength: number): number
	if eventId == "PowerSurge" then
		return math.clamp(1 + EventConfig.SurgeGeneratorBonus * strength, 1, EventConfig.MaxGeneratorMultiplier)
	end
	return 1
end

-- (mutation, chance): the event mutation a successful fusion may come out
-- as (it replaces the normal fusion roll), or nil.
function EventConfig.GetFusionEventMutation(eventId: string?, strength: number): (string?, number)
	if eventId == "VoidMoon" then
		return "Void", math.clamp(EventConfig.VoidChance * strength, 0, 1)
	end
	return nil, 0
end

return EventConfig
