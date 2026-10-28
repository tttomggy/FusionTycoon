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
	  Orbs     plain (one Golden chance). Worth the run: the lab's tiers come
	           from the FLOOR = the best tier owned by the LEAST advanced real
	           player in the server (from their inventory): one pedestal at
	           floor + 1 (never above Legendary), one at the floor, the other
	           two from TierWeights (band = the lowest Rebirth count) with
	           every tier below the floor dropped, so a Rare owner never sees
	           four Commons and a brand-new player (floor Common) sees Common /
	           Rare / Epic with at least one Rare. Never BannedTiers.
	  Rotate   every RotateSeconds (+- jitter, staggered so no two labs turn
	           over within RotateMinGapSeconds) a lab re-rolls its orbs by the
	           same rules, unless a pedestal is being carried from, its guard
	           is chasing, a StealPrompt is held or a player stands at a
	           pedestal; a stolen orb's pedestal rolls its new orb when it
	           comes back. A rise of the floor waits for the next rotation.
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
-- The pedestal-side light budget of a rival lab = what a fully filled player
-- lab adds on those pedestals: each filled pedestal has TWO lights (the
-- RarityVisuals "PedestalLight" and the orb's own light). /selftest asserts it.
RivalConfig.MaxPedestalLights = 2 * RivalConfig.PedestalCount
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

-- The tiers a lab can show, lowest first (BannedTiers left out), and where a
-- pedestal's tier comes from (see the header): its ROLE in the lab.
RivalConfig.TierOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" } :: { string }
RivalConfig.PlusOneTierPedestals = 1 -- pedestals at floor + 1 (capped at the best offered tier)
RivalConfig.FloorTierPedestals = 1 -- pedestals at the floor
-- (the rest of the PedestalCount are "Weighted": TierWeights, floor and up)

-- Rotation
RivalConfig.RotateSeconds = 150
RivalConfig.RotateJitterSeconds = 30 -- +- on every interval
RivalConfig.RotateMinGapSeconds = 10 -- no two labs rotate closer than this (/selftest holds 5)
RivalConfig.RotateKeepOutStuds = 14 -- a player this close to one of a lab's pedestals ("about to grab") holds its rotation
RivalConfig.RotateFirstFractions = { 0.5, 0.75, 1 } :: { number } -- the 1st/2nd/3rd lab's first rotation, x RotateSeconds
RivalConfig.PopSeconds = 0.3 -- the swap cue: a flash on the old orb, a shell closing on the new one

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

--[[ Orb tiers: floor + roles ------------------------------------------------- ]]

-- The offered tiers in order (TierOrder without BannedTiers).
function RivalConfig.OfferedTiers(): { string }
	local list: { string } = {}
	for _, tier in RivalConfig.TierOrder do
		if not RivalConfig.BannedTiers[tier] then
			table.insert(list, tier)
		end
	end
	return list
end

-- The position of `tier` among the offered tiers (0: not offered).
local function offeredRank(tier: string): number
	for index, offered in RivalConfig.OfferedTiers() do
		if offered == tier then
			return index
		end
	end
	return 0
end

RivalConfig.OfferedRank = offeredRank

-- A player's best owned tier -> the floor: nil (nothing owned) is Common; a
-- banned or unknown tier (a Mythic owner) is the best tier that is offered.
function RivalConfig.ClampFloor(best: string?): string
	local offered = RivalConfig.OfferedTiers()
	if best == nil then
		return offered[1]
	end
	local rank = offeredRank(best)
	if rank > 0 then
		return best
	end
	local order = table.find(RivalConfig.TierOrder, best)
	return if order and order > 1 then offered[#offered] else offered[1]
end

-- One above `floor`, never past the best offered tier (so never Mythic).
function RivalConfig.PlusOneTier(floor: string): string
	local offered = RivalConfig.OfferedTiers()
	return offered[math.min(offeredRank(floor) + 1, #offered)]
end

-- A weighted tier for band `band` with every tier below `floor` dropped.
-- `roll` is uniform in [0, 1). When the band lists nothing at or above the
-- floor the floor itself comes back.
function RivalConfig.PickTierAtLeast(band: number, floor: string, roll: number): string
	local weights = RivalConfig.TierWeights[RivalConfig.GetBand(band)]
	local minRank = math.max(offeredRank(floor), 1)
	local offered = RivalConfig.OfferedTiers()
	local total = 0
	for index = minRank, #offered do
		total += weights[offered[index]] or 0
	end
	if total <= 0 then
		return floor
	end
	local target = math.clamp(roll, 0, 1 - 1e-9) * total
	for index = minRank, #offered do
		local weight = weights[offered[index]] or 0
		if weight > 0 then
			if target < weight then
				return offered[index]
			end
			target -= weight
		end
	end
	return floor
end

-- The roles of a lab's pedestals, shuffled: PlusOneTierPedestals x "PlusOne",
-- FloorTierPedestals x "Floor", the rest "Weighted". `roll` returns a uniform
-- number in [0, 1) each call.
function RivalConfig.PlanRoles(roll: () -> number): { string }
	local roles: { string } = {}
	for _ = 1, RivalConfig.PlusOneTierPedestals do
		table.insert(roles, "PlusOne")
	end
	for _ = 1, RivalConfig.FloorTierPedestals do
		table.insert(roles, "Floor")
	end
	while #roles < RivalConfig.PedestalCount do
		table.insert(roles, "Weighted")
	end
	while #roles > RivalConfig.PedestalCount do
		table.remove(roles)
	end
	for index = #roles, 2, -1 do
		local other = math.clamp(math.floor(roll() * index) + 1, 1, index)
		roles[index], roles[other] = roles[other], roles[index]
	end
	return roles
end

-- The tier of a pedestal with `role` for `floor` (a ClampFloor result) and
-- the Rebirth band's weights.
function RivalConfig.TierForRole(role: string, floor: string, band: number, roll: () -> number): string
	if role == "PlusOne" then
		return RivalConfig.PlusOneTier(floor)
	elseif role == "Floor" then
		return floor
	end
	return RivalConfig.PickTierAtLeast(band, floor, roll())
end

-- All of a lab's tiers at once, pedestal 1..PedestalCount.
function RivalConfig.PlanTiers(floor: string, band: number, roll: () -> number): { string }
	local tiers: { string } = {}
	for index, role in RivalConfig.PlanRoles(roll) do
		tiers[index] = RivalConfig.TierForRole(role, floor, band, roll)
	end
	return tiers
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
