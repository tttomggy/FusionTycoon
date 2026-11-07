--!strict
--[[
	ArenaLayout
	-----------
	Geometry of the ORB RUSH arena (MinigameService builds it): a floating
	disc far above and away from the plots, with invisible walls, a ring of
	spawn points, a score tower in the middle and lab debris round it. The
	single source for every position and size, with a require-time assertion
	block like PlotLayout's: the arena is MIN_PLOT_DISTANCE studs from every
	plot slot, the spawns and the tower sit on the disc, the walls enclose it.

	World space; the floor TOP is y = CENTER.Y.
]]
local PlotLayout = require(script.Parent.PlotLayout)

local ArenaLayout = {}

local v3 = Vector3.new

ArenaLayout.CENTER = v3(0, 260, 900) -- the middle of the floor's top face
ArenaLayout.FLOOR_RADIUS = 58
ArenaLayout.FLOOR_THICKNESS = 3
ArenaLayout.PLAY_RADIUS = 52 -- orbs land and bots walk inside this
ArenaLayout.DROP_MIN_RADIUS = 9 -- orbs never land inside the score tower's footprint
ArenaLayout.MIN_PLOT_DISTANCE = 500

-- Invisible walls (a ring of blocks round the rim) and the kill plane under it.
ArenaLayout.WALL_SEGMENTS = 16
ArenaLayout.WALL_HEIGHT = 70
ArenaLayout.WALL_THICKNESS = 2
ArenaLayout.FALL_BELOW = 30 -- below the floor top this far = fell off: back to a spawn

-- Rim: a thin Neon band seen from the side, and SurfaceGui rings on the floor.
ArenaLayout.RIM_BAND_HEIGHT = 0.4
ArenaLayout.RING_DIAMETERS = { 40, 78, 112 }

-- Spawn points on a ring, facing the middle.
ArenaLayout.SPAWN_COUNT = 8
ArenaLayout.SPAWN_RADIUS = 38
ArenaLayout.SPAWN_LIFT = 3 -- the character's root above the floor top

-- The score tower (top 3 live).
ArenaLayout.TOWER_SIZE = v3(7, 22, 7)

-- Lab debris floating round the disc (decoration; deterministic).
ArenaLayout.DEBRIS_COUNT = 26
ArenaLayout.DEBRIS_MIN_RADIUS = 80
ArenaLayout.DEBRIS_MAX_RADIUS = 190

function ArenaLayout.GetFloorTopY(): number
	return ArenaLayout.CENTER.Y
end

-- Spawn `index` (1..SPAWN_COUNT): where a character's root goes, facing the middle.
function ArenaLayout.GetSpawnCFrame(index: number): CFrame
	local angle = (index - 1) / ArenaLayout.SPAWN_COUNT * 2 * math.pi
	local position = ArenaLayout.CENTER + v3(math.cos(angle) * ArenaLayout.SPAWN_RADIUS, ArenaLayout.SPAWN_LIFT, math.sin(angle) * ArenaLayout.SPAWN_RADIUS)
	return CFrame.lookAt(position, v3(ArenaLayout.CENTER.X, position.Y, ArenaLayout.CENTER.Z))
end

-- Whether a world point is over the playable disc (flat distance).
function ArenaLayout.IsOnDisc(position: Vector3): boolean
	local flat = v3(position.X - ArenaLayout.CENTER.X, 0, position.Z - ArenaLayout.CENTER.Z)
	return flat.Magnitude <= ArenaLayout.FLOOR_RADIUS
end

-- A random landing point on the playable disc (outside the tower), from two
-- numbers in [0, 1): `a` picks the angle, `b` the (area-uniform) distance.
function ArenaLayout.GetDropPoint(a: number, b: number): Vector3
	local minR, maxR = ArenaLayout.DROP_MIN_RADIUS, ArenaLayout.PLAY_RADIUS
	local radius = math.sqrt(minR * minR + b * (maxR * maxR - minR * minR))
	local angle = a * 2 * math.pi
	return v3(ArenaLayout.CENTER.X + math.cos(angle) * radius, ArenaLayout.CENTER.Y, ArenaLayout.CENTER.Z + math.sin(angle) * radius)
end

export type Debris = { Position: Vector3, Size: Vector3, Yaw: number, Wedge: boolean }

-- The floating debris, the same on server and client (a fixed LCG, no Random).
function ArenaLayout.GetDebris(): { Debris }
	local list: { Debris } = {}
	local seed = 20240607
	local function nextNumber(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	for _ = 1, ArenaLayout.DEBRIS_COUNT do
		local angle = nextNumber() * 2 * math.pi
		local radius = ArenaLayout.DEBRIS_MIN_RADIUS + nextNumber() * (ArenaLayout.DEBRIS_MAX_RADIUS - ArenaLayout.DEBRIS_MIN_RADIUS)
		local height = (nextNumber() - 0.5) * 90
		local size = v3(3 + nextNumber() * 9, 2 + nextNumber() * 6, 3 + nextNumber() * 9)
		table.insert(list, {
			Position = ArenaLayout.CENTER + v3(math.cos(angle) * radius, height, math.sin(angle) * radius),
			Size = size,
			Yaw = nextNumber() * 360,
			Wedge = nextNumber() < 0.3,
		})
	end
	return list
end

--[[ Assertions -------------------------------------------------------------- ]]

do
	local center = ArenaLayout.CENTER
	-- Far from every plot slot (centre to centre, 3D).
	for slot = 1, PlotLayout.MAX_PLOT_SLOTS do
		local distance = (PlotLayout.GetSlotCFrame(slot).Position - center).Magnitude
		assert(
			distance >= ArenaLayout.MIN_PLOT_DISTANCE,
			("ArenaLayout: the arena is %d studs from plot slot %d (needs %d)"):format(distance, slot, ArenaLayout.MIN_PLOT_DISTANCE)
		)
	end
	assert(ArenaLayout.PLAY_RADIUS < ArenaLayout.FLOOR_RADIUS, "ArenaLayout: the play area must sit inside the floor")
	assert(ArenaLayout.DROP_MIN_RADIUS > ArenaLayout.TOWER_SIZE.X * 0.75, "ArenaLayout: orbs would land in the score tower")
	assert(ArenaLayout.SPAWN_RADIUS + 4 < ArenaLayout.PLAY_RADIUS, "ArenaLayout: a spawn point sits off the play area")
	assert(ArenaLayout.SPAWN_RADIUS > ArenaLayout.DROP_MIN_RADIUS + 6, "ArenaLayout: spawn points are inside the tower's ring")
	assert(ArenaLayout.SPAWN_COUNT >= 8, "ArenaLayout: a round has up to 8 players and needs a spawn each")
	assert(ArenaLayout.WALL_SEGMENTS >= 12, "ArenaLayout: too few wall segments to enclose a disc")
	assert(ArenaLayout.WALL_HEIGHT > 20, "ArenaLayout: the walls must be taller than a jump")
	local ringMax = 0
	for _, diameter in ArenaLayout.RING_DIAMETERS do
		ringMax = math.max(ringMax, diameter)
	end
	assert(ringMax / 2 <= ArenaLayout.FLOOR_RADIUS, "ArenaLayout: a floor ring is wider than the floor")
	for _, debris in ArenaLayout.GetDebris() do
		local flat = Vector3.new(debris.Position.X - center.X, 0, debris.Position.Z - center.Z).Magnitude
		assert(flat > ArenaLayout.FLOOR_RADIUS + 8, "ArenaLayout: debris overlaps the floor")
	end
end

return ArenaLayout
