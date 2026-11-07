--!strict
--[[
	RivalConfig
	-----------
	Rival labs: NPC-owned labs in plot slots no player owns, so a brand-new
	player can steal from minute 3 even in an empty server. Player-vs-player
	stealing keeps its Rebirth 1 gate (HeistConfig.MinRebirthsVsPlayers); a
	rival has its own gate per DIFFICULTY (RivalConfig.Tiers[...].MinRebirths).

	  Fill       MaxRivals (4) labs, ONE per difficulty (Easy, Medium, Hard,
	             Insane), in free slots nearest the real players' labs
	             (RivalService). A real player is never refused a plot: with no
	             slot free the lowest difficulty goes first (Easy, Medium, Hard,
	             Insane last), the lab farthest from every player breaking a tie.
	  Difficulty decides everything below (the table in Tiers): the orb tiers
	             (weights; only Insane rolls Mythic / Secret), the guards (how
	             many, how fast, how far they chase, how long a weapon stuns
	             one), the Rebirths a thief needs, the delivered steals an hour
	             (Easy and Medium share one pool), the respawn after a steal and
	             the Golden chance.
	  Rotate     every RotateSeconds (+- jitter, staggered so no two labs turn
	             over within RotateMinGapSeconds) a lab re-rolls its orbs by the
	             same rules, unless a pedestal is being carried from, a guard is
	             chasing, a StealPrompt is held or a player stands at a
	             pedestal; a stolen orb's pedestal rolls its new orb when it
	             comes back.
	  Guards     up to two chase one carrier; the rest hold the gate. A touch
	             (HeistConfig.TagDistance) from ANY guard sends the orb back.

	Nothing here is saved (the hourly times are: PlayerData.RivalSteals, and
	RivalStealPools for the Hard / Insane pools).
]]
local FusionConfig = require(script.Parent.FusionConfig)
local HeistConfig = require(script.Parent.HeistConfig)

local RivalConfig = {}

RivalConfig.MaxRivals = 4
RivalConfig.PedestalCount = 4 -- pedestals 1..4 (the ground floor's first four) hold orbs
-- The pedestal-side light budget of a rival lab = what a fully filled player
-- lab adds on those pedestals: each filled pedestal has TWO lights (the
-- RarityVisuals "PedestalLight" and the orb's own light). /selftest asserts it.
RivalConfig.MaxPedestalLights = 2 * RivalConfig.PedestalCount

-- A rival lab's name, in the order they spawn ("Dr. Fizz's Lab" ...).
RivalConfig.Names = {
	"Dr. Fizz's Lab",
	"Professor Volt's Lab",
	"Captain Ooze's Lab",
	"Madame Quark's Lab",
	"Baron Sprocket's Lab",
} :: { string }

-- Every tier a rival can show, lowest first (the order of the orb tables).
RivalConfig.TierOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" } :: { string }

--[[ Difficulty tiers ---------------------------------------------------------------- ]]

export type Difficulty = "Easy" | "Medium" | "Hard" | "Insane"

export type DifficultyDef = {
	Id: Difficulty,
	Rank: number, -- 1 = Easy ... 4 = Insane (despawn order: lowest first)
	Label: string, -- the gate sign's chip
	Weights: { [string]: number }, -- orb tier -> weight; a tier with no weight is never rolled or grabbed
	Guards: number,
	GuardSpeed: number, -- chasing (the carrier walks at HeistConfig.CarryWalkSpeed)
	Leash: number, -- studs past the lab's gate before a chasing guard gives up (math.huge: chases to your gate)
	StunSeconds: number, -- a weapon hit on ONE guard
	MinRebirths: number, -- the thief's Rebirths to rob it (the lab is still open to walk into)
	StealsPerHour: number, -- delivered steals per player per rolling hour in this lab's pool
	Pool: string, -- "Shared" (Easy + Medium), "Hard" or "Insane": which hourly counter it uses
	RespawnSeconds: number, -- a stolen orb is back this long after delivery
	GoldenChance: number,
	GuardScale: number, -- the guard rig's BodyScale
	Look: string, -- "Plain" | "Big" | "Helmet" | "Elite" (RivalService.buildGuard)
}

RivalConfig.Difficulties = { "Easy", "Medium", "Hard", "Insane" } :: { Difficulty }

RivalConfig.Tiers = {
	Easy = {
		Id = "Easy",
		Rank = 1,
		Label = "EASY",
		Weights = { Common = 65, Rare = 35 },
		Guards = 1,
		GuardSpeed = 11,
		Leash = 40,
		StunSeconds = 3,
		MinRebirths = 0,
		StealsPerHour = 12,
		Pool = "Shared",
		RespawnSeconds = 60,
		GoldenChance = 0.05,
		GuardScale = 1,
		Look = "Plain",
	},
	Medium = {
		Id = "Medium",
		Rank = 2,
		Label = "MEDIUM",
		Weights = { Rare = 60, Epic = 40 },
		Guards = 1,
		GuardSpeed = 13,
		Leash = 60,
		StunSeconds = 3,
		MinRebirths = 0,
		StealsPerHour = 12,
		Pool = "Shared",
		RespawnSeconds = 90,
		GoldenChance = 0.05,
		GuardScale = 1.1,
		Look = "Big",
	},
	Hard = {
		Id = "Hard",
		Rank = 3,
		Label = "HARD",
		Weights = { Epic = 65, Legendary = 35 },
		Guards = 2,
		GuardSpeed = 14,
		Leash = 90,
		StunSeconds = 2,
		MinRebirths = 2,
		StealsPerHour = 4,
		Pool = "Hard",
		RespawnSeconds = 150,
		GoldenChance = 0.05,
		GuardScale = 1.2,
		Look = "Helmet",
	},
	Insane = {
		Id = "Insane",
		Rank = 4,
		Label = "INSANE",
		Weights = { Legendary = 85, Mythic = 14.5, Secret = 0.5 },
		Guards = 3,
		GuardSpeed = 15,
		Leash = math.huge,
		StunSeconds = 1.2,
		MinRebirths = 4,
		StealsPerHour = 2,
		Pool = "Insane",
		RespawnSeconds = 300,
		GoldenChance = 0.08,
		GuardScale = 1.35,
		Look = "Elite",
	},
} :: { [string]: DifficultyDef }

-- The hourly pools: "Shared" is the legacy PlayerData.RivalSteals list.
RivalConfig.Pools = { "Shared", "Hard", "Insane" } :: { string }

RivalConfig.StealWindowSeconds = 3600
RivalConfig.MaxChasers = 2 -- guards that chase one carrier; any others hold the gate
RivalConfig.SpottedSeconds = 1.5 -- the red "!" over a guard that starts chasing (the carrier only)
RivalConfig.InsaneHumSeconds = 3.5 -- the Insane lab's low hum repeats this often while you are near
RivalConfig.InsaneHumStuds = 70 -- ... within this many studs of the lab's centre

function RivalConfig.GetTier(difficulty: string): DifficultyDef
	return RivalConfig.Tiers[difficulty] or RivalConfig.Tiers.Easy
end

-- Whether a lab of `difficulty` may show / hand out an orb of `tier` (its
-- weight is above 0). HeistService re-checks this at grab time.
function RivalConfig.IsTierAllowed(difficulty: string, tier: string): boolean
	local weight = RivalConfig.GetTier(difficulty).Weights[tier]
	return weight ~= nil and weight > 0
end

-- One tier for `difficulty`; `roll` is uniform in [0, 1).
function RivalConfig.PickTier(difficulty: string, roll: number): string
	local weights = RivalConfig.GetTier(difficulty).Weights
	local total = 0
	for _, tier in RivalConfig.TierOrder do
		total += weights[tier] or 0
	end
	local target = math.clamp(roll, 0, 1 - 1e-9) * total
	local last = RivalConfig.TierOrder[1]
	for _, tier in RivalConfig.TierOrder do
		local weight = weights[tier] or 0
		if weight > 0 then
			last = tier
			if target < weight then
				return tier
			end
			target -= weight
		end
	end
	return last
end

-- The tiers a difficulty can show, lowest first.
function RivalConfig.TiersOf(difficulty: string): { string }
	local list: { string } = {}
	for _, tier in RivalConfig.TierOrder do
		if RivalConfig.IsTierAllowed(difficulty, tier) then
			table.insert(list, tier)
		end
	end
	return list
end

-- The weight of `tier` as a share of the lab's total (0..1), for the odds board.
function RivalConfig.ShareOf(difficulty: string, tier: string): number
	local weights = RivalConfig.GetTier(difficulty).Weights
	local total = 0
	for _, name in RivalConfig.TierOrder do
		total += weights[name] or 0
	end
	return if total > 0 then (weights[tier] or 0) / total else 0
end

-- The Rebirth rule for robbing a lab of `difficulty`: nil = allowed.
function RivalConfig.WhyCantRob(thiefRebirths: number, difficulty: string): string?
	return if thiefRebirths < RivalConfig.GetTier(difficulty).MinRebirths then "NeedsRebirth" else nil
end

-- "Rebirth 4 to rob" (the locked StealPrompt's action text).
function RivalConfig.LockedText(difficulty: string): string
	return ("Rebirth %d to rob"):format(RivalConfig.GetTier(difficulty).MinRebirths)
end

-- The odds line on a lab's board, the Gacha board's format:
-- "Common 65 · Rare 35%" (FusionConfig.FormatPercent, trailing %).
function RivalConfig.FormatOdds(difficulty: string): string
	local parts: { string } = {}
	for _, tier in RivalConfig.TiersOf(difficulty) do
		table.insert(parts, ("%s %s"):format(tier, FusionConfig.FormatPercent(RivalConfig.ShareOf(difficulty, tier) * 100)))
	end
	return table.concat(parts, " · ") .. "%"
end

-- The gate sign's two lines for a lab of `difficulty`.
function RivalConfig.SignText(difficulty: string): (string, string)
	if difficulty == "Insane" then
		return "INSANE LAB", "steal if you dare"
	elseif difficulty == "Hard" then
		return "RIVAL LAB", RivalConfig.LockedText(difficulty)
	end
	return "RIVAL LAB", "steal me!"
end

-- Rotation
RivalConfig.RotateSeconds = 150
RivalConfig.RotateJitterSeconds = 30 -- +- on every interval
RivalConfig.RotateMinGapSeconds = 10 -- no two labs rotate closer than this (/selftest holds 5)
RivalConfig.RotateKeepOutStuds = 14 -- a player this close to one of a lab's pedestals ("about to grab") holds its rotation
RivalConfig.RotateFirstFractions = { 0.5, 0.75, 1, 1.25 } :: { number } -- the 1st/2nd/3rd/4th lab's first rotation, x RotateSeconds
RivalConfig.PopSeconds = 0.3 -- the swap cue: a flash on the old orb, a shell closing on the new one

-- Guard
RivalConfig.GuardPatrolSpeed = 8
-- (the chase speed, leash and stun are per difficulty: RivalConfig.Tiers)
RivalConfig.GuardPathSeconds = 0.5 -- the chase path is recomputed at most this often
RivalConfig.GuardTickSeconds = 0.1 -- the one guard loop
RivalConfig.GuardPatrolPauseSeconds = 1.5
RivalConfig.GuardWaypointReach = 3 -- a patrol / home waypoint counts as reached within this
-- Plot-local patrol stops (x, z): in front of the four pedestals and the hub.
-- All on the open floor of a rival lab (no stations are built there).
RivalConfig.PatrolPoints = {
	Vector3.new(-14, 0, 5),
	Vector3.new(-6, 0, 12),
	Vector3.new(6, 0, 12),
	Vector3.new(14, 0, 5),
	Vector3.new(0, 0, 5),
} :: { Vector3 }
RivalConfig.GuardHome = Vector3.new(0, 0, 10) -- plot-local; where the first guard spawns / returns
-- The gate-holder (every guard past MaxChasers: Insane's third) stands IN the
-- gate all the time, facing the street, on the exit path just inside the wall
-- (the gate gap is x -7..+7 at z 31..32), and tags inside HolderTagRadius
-- instead of HeistConfig.TagDistance: 8 studs from (0, 29) reaches both gap
-- corners (7.6 studs), so there is no way out past it that is not in its reach.
RivalConfig.GateHoldPoint = Vector3.new(0, 0, 29)
RivalConfig.HolderTagRadius = 8
RivalConfig.HolderStunSeconds = 3 -- a weapon hit on the gate-holder (the chasers keep tier.StunSeconds, 1.2 on Insane): long enough for one skilled player with Boots to freeze it from range and slip past
RivalConfig.HolderRouteBack = 3 -- the holder stands this far short of the gate along the exit route (gate z 32 - 29)
RivalConfig.GuardSpread = 4 -- guards beyond the first start this many studs apart across x, so they never stack
-- Staying upright: the self-heal stands a guard up when its root's up-vector
-- is more than UprightLimitDegrees off vertical for GuardDownSeconds without
-- a stun; /selftest holds every guard to GuardUprightSelfTestDegrees.
RivalConfig.UprightLimitDegrees = 45
RivalConfig.GuardDownSeconds = 1 -- tilted this long (not stunned) before the self-heal; also the GettingUp grace
RivalConfig.GuardUprightSelfTestDegrees = 20
RivalConfig.GuardNameDistance = 60 -- the guard's name label (MaxDistance)

-- What a rival lab's decorative factory line shows (generator id -> level).
-- Below max everywhere (no generator lights), above the first Neon band so the
-- line reads as a running lab; it is a picture, nothing pays from it.
RivalConfig.GeneratorLevels = {
	basic_generator = 12,
	ember_forge = 9,
	flare_reactor = 6,
	core_engine = 3,
	singularity_core = 1,
} :: { [string]: number }

-- Housekeeping
RivalConfig.FillSeconds = 3 -- RivalService re-checks the fill / band this often

--[[ Escape model (also /selftest) ---------------------------------------------------- ]]

export type EscapeInput = {
	Difficulty: string,
	Distance: number, -- the route the carrier runs to their own plot, studs
	CarrierSpeed: number, -- 12 carrying; x1.5 with Speed Boots
	Gaps: { number }, -- each CHASER's distance behind the carrier when the grab lands
	StunAt: number?, -- seconds into the carry both chasers are hit by a weapon (nil: never)
	ReactionSeconds: number?, -- before a guard's first path is computed (default 0.3)
	GateAt: number?, -- where the lab's gate is along the route (default 34: pedestal row to gate); a chaser quits Leash studs past it
	HolderStunAt: number?, -- seconds into the carry a weapon hits the gate-holder (nil: never); only for a difficulty that has one
}

-- Whether a lab of `difficulty` has a gate-holder (more guards than MaxChasers).
function RivalConfig.HasHolder(difficulty: string): boolean
	return RivalConfig.GetTier(difficulty).Guards > RivalConfig.MaxChasers
end

-- A kinematic model of a carry on a straight route against a lab's chasers
-- (the gate-holder only stands, so it is left out): the carrier runs at
-- CarrierSpeed; each chaser runs at the difficulty's GuardSpeed once its path
-- is in, stands still while stunned (StunSeconds) and then runs again, gives up
-- once it is Leash studs past the lab's gate; any chaser within TagDistance
-- after TagGraceSeconds tags. A difficulty with a gate-holder (Insane) also has
-- it standing HolderRouteBack short of the gate, tagging within HolderTagRadius
-- of its spot (after the grace) unless a weapon hit it (HolderStunAt) and it is
-- still down. Returns (escaped,
-- seconds). Idealised: real guards path around things, so this is the best a
-- guard does, and the numbers are what /selftest holds.
function RivalConfig.SimulateEscape(input: EscapeInput): (boolean, number)
	local tier = RivalConfig.GetTier(input.Difficulty)
	local step = 0.02
	local reaction = input.ReactionSeconds or 0.3
	local carrier = 0
	local chasers: { { Pos: number, StunnedUntil: number } } = {}
	for _, gap in input.Gaps do
		table.insert(chasers, { Pos = -gap, StunnedUntil = -1 })
	end
	local stunned = false
	local gateAt = input.GateAt or 34
	local holderAt = gateAt - RivalConfig.HolderRouteBack
	local holderStunnedUntil = -1
	local holderStunApplied = false
	local hasHolder = RivalConfig.HasHolder(input.Difficulty)
	local quitAt = gateAt + tier.Leash
	local t = 0
	while t < HeistConfig.CarrySeconds do
		if carrier >= input.Distance then
			return true, t
		end
		local stunAt = input.StunAt
		if stunAt and not stunned and t >= stunAt then
			stunned = true
			for _, chaser in chasers do
				chaser.StunnedUntil = t + tier.StunSeconds
			end
		end
		local holderStunAt = input.HolderStunAt
		if holderStunAt and not holderStunApplied and t >= holderStunAt then
			holderStunApplied = true
			holderStunnedUntil = t + RivalConfig.HolderStunSeconds
		end
		carrier += input.CarrierSpeed * step
		-- The gate-holder stands in the gate and tags anyone inside its radius.
		if
			hasHolder
			and t >= HeistConfig.TagGraceSeconds
			and t >= holderStunnedUntil
			and math.abs(carrier - holderAt) <= RivalConfig.HolderTagRadius
		then
			return false, t
		end
		for _, chaser in chasers do
			if t >= reaction and t >= chaser.StunnedUntil and chaser.Pos < quitAt then
				chaser.Pos = math.min(chaser.Pos + tier.GuardSpeed * step, carrier)
			end
			if t >= HeistConfig.TagGraceSeconds and chaser.Pos < quitAt and carrier - chaser.Pos <= HeistConfig.TagDistance then
				return false, t
			end
		end
		t += step
	end
	return false, t
end

--[[ Rotation timing ------------------------------------------------------------ ]]

-- The seconds until a lab's next rotation: RotateSeconds +- jitter (`roll` in [0, 1)).
function RivalConfig.RotateDelay(roll: number): number
	return RivalConfig.RotateSeconds + (math.clamp(roll, 0, 1) * 2 - 1) * RivalConfig.RotateJitterSeconds
end

-- Moves `candidate` later until it is at least RotateMinGapSeconds from every
-- time in `others` (the other labs' next rotations).
function RivalConfig.SpaceRotation(candidate: number, others: { number }): number
	local gap = RivalConfig.RotateMinGapSeconds
	local moved = true
	local guard = 0
	while moved and guard < 100 do
		moved = false
		guard += 1
		for _, other in others do
			if math.abs(candidate - other) < gap then
				candidate = other + gap
				moved = true
			end
		end
	end
	return candidate
end

-- "1:48" for a countdown (the gate sign's "fresh orbs in 1:48").
function RivalConfig.FormatCountdown(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(whole // 60, whole % 60)
end

-- "Dr. Fizz's Lab" -> "Dr. Fizz" (the guard's name label).
function RivalConfig.GetShortName(labName: string): string
	return (labName:gsub("'s Lab$", ""))
end

-- The sign / log name of the nth rival lab.
function RivalConfig.GetName(serial: number): string
	local names = RivalConfig.Names
	return names[((serial - 1) % #names) + 1]
end

return RivalConfig
