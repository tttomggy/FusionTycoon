--!strict
--[[
	RivalConfig
	-----------
	Rival labs: NPC-owned labs in plot slots no player owns, so a brand-new
	player can steal from minute 3 even in an empty server. Player-vs-player
	stealing keeps its Rebirth 1 gate (HeistConfig.MinRebirthsVsPlayers); a
	rival has no such gate (HeistConfig.MinRebirthsVsRivals).

	  Fill     up to MaxRivals rival labs in free slots (RivalService). A real
	           player is never refused a plot: with no slot free, the rival
	           lab farthest from every player despawns first.
	  Orbs     plain (one Golden chance), rolled from TierWeights for the
	           LOWEST Rebirth count among the real players in the server, so a
	           new player never sees a Mythic. Never BannedTiers.
	  Respawn  a stolen orb is back on its pedestal after RespawnSeconds.
	  Guard    one NPC per lab: patrols, chases a carrier at GuardSpeed (the
	           carrier walks at HeistConfig.CarryWalkSpeed), gives up
	           GuardLeash studs past its gate. A touch (HeistConfig.TagDistance)
	           sends the orb back, like the owner's tag.
	  Limits   StealsPerHour delivered per player; never a banned tier.

	Nothing here is saved.
]]
local RivalConfig = {}

RivalConfig.MaxRivals = 3
RivalConfig.PedestalCount = 4 -- pedestals 1..4 (the ground floor's first four) hold orbs
RivalConfig.RespawnSeconds = 90
RivalConfig.GoldenChance = 0.05 -- the only mutation a rival orb ever has

-- A rival lab's name, in the order they spawn ("Dr. Fizz's Lab" ...).
RivalConfig.Names = {
	"Dr. Fizz's Lab",
	"Professor Volt's Lab",
	"Captain Ooze's Lab",
	"Madame Quark's Lab",
	"Baron Sprocket's Lab",
} :: { string }

-- Never offered by a rival, whatever the weights say.
RivalConfig.BannedTiers = { Mythic = true, Secret = true } :: { [string]: boolean }

-- Tier weights by band = the lowest Rebirth count among real players (the
-- last band covers everything above it). No Mythic / Secret in any band.
RivalConfig.TierWeights = {
	[0] = { Common = 60, Rare = 30, Epic = 10 },
	[1] = { Common = 40, Rare = 38, Epic = 18, Legendary = 4 },
	[2] = { Common = 25, Rare = 35, Epic = 28, Legendary = 12 },
	[3] = { Common = 15, Rare = 30, Epic = 35, Legendary = 20 },
} :: { [number]: { [string]: number } }
RivalConfig.MaxBand = 3

-- Guard
RivalConfig.GuardSpeed = 13 -- chasing (the carrier walks at 12)
RivalConfig.GuardPatrolSpeed = 8
RivalConfig.GuardLeash = 60 -- studs past its gate, then it walks home
RivalConfig.GuardPathSeconds = 0.5 -- the chase path is recomputed at most this often
RivalConfig.GuardTickSeconds = 0.1 -- the one guard loop
RivalConfig.GuardStunSeconds = 3 -- a weapon hit: it falls over and loses the chase
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
RivalConfig.GuardHome = Vector3.new(0, 0, 10) -- plot-local; where it spawns and returns
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

-- Limits
RivalConfig.StealsPerHour = 12 -- delivered rival steals per player in any rolling hour
RivalConfig.StealWindowSeconds = 3600

-- Housekeeping
RivalConfig.FillSeconds = 3 -- RivalService re-checks the fill / band this often

--[[ Pure rules (also /selftest) ------------------------------------------- ]]

-- The weights band for a lowest-Rebirth count.
function RivalConfig.GetBand(lowestRebirths: number): number
	return math.clamp(math.floor(lowestRebirths), 0, RivalConfig.MaxBand)
end

-- One tier from the band's weights; `roll` is a uniform number in [0, 1).
-- Banned tiers are skipped even if a band lists them.
function RivalConfig.PickTier(band: number, roll: number): string
	local weights = RivalConfig.TierWeights[RivalConfig.GetBand(band)]
	local total = 0
	local order = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
	for _, tier in order do
		if not RivalConfig.BannedTiers[tier] then
			total += weights[tier] or 0
		end
	end
	local target = math.clamp(roll, 0, 1 - 1e-9) * total
	local last = "Common"
	for _, tier in order do
		local weight = if RivalConfig.BannedTiers[tier] then 0 else weights[tier] or 0
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
