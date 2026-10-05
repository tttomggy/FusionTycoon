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

-- The start banner's one line is the first "what to do" sentence of the
-- info card (EventConfig.Blurbs, filled from GetInfo below).
EventConfig.Blurbs = {} :: { [string]: string }

--[[ Effect numbers (at strength 1) ------------------------------------------ ]]

EventConfig.Strengths = { 1, 2, 3 } -- what the admin panel offers

-- Golden Rain: a coin per claimed plot every CoinIntervalSeconds / strength,
-- each worth CoinIncomeSeconds x strength of the owner's passive income.
EventConfig.CoinIntervalSeconds = 10 -- Events 2: 4 -> 10 with BIG + street coins (15% target; fewer, bigger coins)
EventConfig.CoinIncomeSeconds = 3
EventConfig.CoinMaxIncomeSeconds = 15 -- clamp
EventConfig.CoinMaxLive = 30 -- per plot
EventConfig.CoinLifetimeSeconds = 20
EventConfig.CoinCollectDistance = 5 -- server distance check for a touch
EventConfig.GoldenRainGoldenOdds = 3
-- BIG coins: 1 in BigCoinChance lab coins is double size and worth
-- BigCoinIncomeSeconds of income instead.
EventConfig.BigCoinChance = 8
EventConfig.BigCoinIncomeSeconds = 20
-- Street coins: one every StreetCoinIntervalSeconds on the street (inside
-- StreetLayout.MeteorBounds), at most StreetCoinMaxLive; anyone can grab
-- one and it pays the GRABBER StreetCoinIncomeSeconds of their income.
EventConfig.StreetCoinIntervalSeconds = 15 -- spec 6; spaced out with the lab coins for the 15% target
EventConfig.StreetCoinMaxLive = 8
EventConfig.StreetCoinIncomeSeconds = 6

-- Power Surge: generators x(1 + 0.25 x strength), clamped; a lightning strike
-- every LightningIntervalSeconds / strength on one random displayed item.
EventConfig.SurgeGeneratorBonus = 0.25 -- was 0.5; cut with the Void Moon halving (15% target)
EventConfig.MaxGeneratorMultiplier = 3 -- clamp
EventConfig.LightningIntervalSeconds = 20
EventConfig.LightningChargeChance = 0.25
-- The target is picked (and marked: pedestal attribute LightningTarget,
-- "⚡ STRIKE IN 3·2·1" on every client) this long before the bolt. The pick
-- is by plot, then by pedestal, so one rich lab doesn't hog the strikes.
EventConfig.LightningWarningSeconds = 3

-- Meteor Shower: MeteorCount x strength meteors at random times; a core
-- gives one item of a tier by weight, ChanceCelestial of it Celestial.
EventConfig.MeteorCount = 6
EventConfig.MeteorGrabSeconds = 2
EventConfig.MeteorPromptDistance = 8
EventConfig.MeteorCraterLifetime = 60
EventConfig.MeteorFallSeconds = 2.5
EventConfig.MeteorWarningSeconds = 2 -- the red "☄ INCOMING" ring shows this long before impact
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

--[[ Info card copy (every number from the fields above) ------------------------ ]]

export type EventInfo = {
	Happening: { string }, -- WHAT'S HAPPENING (2 bullets at most)
	ToDo: string, -- WHAT TO DO (the banner shows its first sentence)
	CanGive: { string }, -- mutation names for the "Can give" pills
	CanGiveNote: string?, -- e.g. "(more often)"
}

-- 1.25 -> "1.25", 3 -> "3", 0.05 * 100 -> "5" (no float noise in copy).
local function num(n: number): string
	local rounded = math.floor(n * 100 + 0.5) / 100
	if rounded == math.floor(rounded) then
		return tostring(math.floor(rounded))
	end
	return (("%.2f"):format(rounded):gsub("0+$", ""))
end

local function oneIn(chance: number): string
	return num(1 / chance)
end

local INFO: { [string]: () -> EventInfo } = {
	GoldenRain = function()
		return {
			Happening = {
				("Gold coins fall in your lab and on the street. Each pays %ss of your income. BIG coins pay %ss."):format(
					num(EventConfig.CoinIncomeSeconds),
					num(EventConfig.BigCoinIncomeSeconds)
				),
				("Golden mutations are ×%s more likely on pulls and fusions."):format(num(EventConfig.GoldenRainGoldenOdds)),
			},
			ToDo = "Run and grab coins! Street coins go to whoever gets there first.",
			CanGive = { "Golden" },
			CanGiveNote = "(more often)",
		}
	end,
	PowerSurge = function()
		return {
			Happening = {
				("Your generators make ×%s cash."):format(num(1 + EventConfig.SurgeGeneratorBonus)),
				("Lightning strikes a displayed item every %ss. 1 in %s strikes turns it CHARGED ×3."):format(
					num(EventConfig.LightningIntervalSeconds),
					oneIn(EventConfig.LightningChargeChance)
				),
			},
			ToDo = "Put your best plain items on pedestals. Mutated items can't be charged.",
			CanGive = { "Charged" },
		}
	end,
	MeteorShower = function()
		return {
			Happening = {
				"Meteors crash onto the street. Each one leaves a glowing core.",
				("Hold E on a crater for %ss. First player wins a free Epic or better item, sometimes CELESTIAL ×20."):format(
					num(EventConfig.MeteorGrabSeconds)
				),
			},
			ToDo = "Get to the street and race!",
			CanGive = { "Celestial" },
		}
	end,
	Night = function()
		return {
			Happening = {
				("Fusions are ×%s more likely to mutate."):format(num(EventConfig.NightFusionMutationOdds)),
			},
			ToDo = "Fuse at your Fusion Machine now.",
			CanGive = { "Golden", "Diamond", "Rainbow" },
			CanGiveNote = "(from fusing)",
		}
	end,
	VoidMoon = function()
		return {
			Happening = {
				("Every fusion is +%s%% more likely to succeed (the odds board turns purple)."):format(
					num(EventConfig.VoidMoonFusionBonus * 100)
				),
				("1 in %s successful fusions comes out VOID ×8."):format(oneIn(EventConfig.VoidChance)),
			},
			ToDo = "Fuse as much as you can before the moon sets!",
			CanGive = { "Void" },
		}
	end,
	RainbowStorm = function()
		return {
			Happening = {
				("Every mutation is ×%s more likely on pulls and fusions."):format(num(EventConfig.RainbowStormOdds)),
			},
			ToDo = "Pull at your Gacha Pad and fuse. The arrow shows you where.",
			CanGive = { "Golden", "Diamond", "Rainbow" },
		}
	end,
}

-- The info card's copy for `eventId` (nil for an unknown id).
function EventConfig.GetInfo(eventId: string): EventInfo?
	local build = INFO[eventId]
	return if build then build() else nil
end

-- The first sentence of a "what to do" line (up to the first ! or .).
local function firstSentence(text: string): string
	local sentence = text:match("^(.-[%.!])%s") or text
	return sentence
end

for _, id in EventConfig.Order do
	local info = EventConfig.GetInfo(id)
	EventConfig.Blurbs[id] = if info then firstSentence(info.ToDo) else ""
end

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

-- Shared with DealConfig (the deal rotation uses the same hash).
EventConfig.Hash32 = hash32

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
