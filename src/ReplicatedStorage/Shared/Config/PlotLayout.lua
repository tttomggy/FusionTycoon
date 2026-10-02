--!strict
--[[
	PlotLayout
	----------
	The single source of truth for world geometry: the plot plan, the size
	and shape of everything built on a plot, the slot grid, and the street.
	No service may hard-code a position, offset or size that lives here.

	Plot-local space:
	  * Origin = PlotOrigin, at the CENTRE of the plot, at floor-top height
	    (y = 0).
	  * +X is the plot's right side, +Z the front (the gate, facing the street).
	  * World position = originCFrame:PointToWorldSpace(localPos); facings
	    are relative to originCFrame.

	The assertion block at the bottom checks, at require time, that no two
	footprints in the plan overlap and that everything sits inside the walls,
	so a future edit that breaks the layout fails loudly.
]]
local PlotLayout = {}

local v3 = Vector3.new

--[[ Plot shell ------------------------------------------------------------ ]]

PlotLayout.FLOOR_SIZE = v3(64, 1, 64)
PlotLayout.PLOT_HALF = 32 -- floor half-extent; the walls sit just inside it

PlotLayout.WALKWAY_X = 0
PlotLayout.WALKWAY_Z_MIN = -10
PlotLayout.WALKWAY_Z_MAX = 32
PlotLayout.WALKWAY_WIDTH = 8
PlotLayout.WALKWAY_THICKNESS = 0.05
PlotLayout.WALKWAY_TOP_Y = 0.02

PlotLayout.WALL_THICKNESS = 1
PlotLayout.WALL_HEIGHT = 1.5
PlotLayout.WALL_STRIP_HEIGHT = 0.25
PlotLayout.WALL_STRIP_WIDTH = 1
PlotLayout.GATE_HALF_WIDTH = 7 -- front wall gap, x -7..+7

PlotLayout.GATE_RAMP_WIDTH = 14
PlotLayout.GATE_RAMP_HEIGHT = 1 -- street level up to the floor
PlotLayout.GATE_RAMP_LENGTH = 3 -- z +32..+35, outside the gap

PlotLayout.SPAWN_POSITION = v3(0, 0, 40) -- on the street in front of the gate
PlotLayout.SPAWN_SIZE = v3(6, 1, 6)

--[[ Plan: local (x, 0, z) of each element --------------------------------- ]]

PlotLayout.CLAIM_STATION = v3(0, 0, 24)
PlotLayout.DROPPER1 = v3(-25, 0, 8) -- faces +X
PlotLayout.DROPPER2 = v3(-25, 0, 20)
PlotLayout.COLLECTOR = v3(-16, 0, 14)
PlotLayout.GACHA_STATION = v3(20, 0, 22)
PlotLayout.MULTIPLIER_STATION = v3(20, 0, 8)

PlotLayout.PEDESTAL_COUNT = 4
PlotLayout.PEDESTAL_Z = -2
PlotLayout.PEDESTAL_XS = { -17, -6, 6, 17 } -- face +Z (the gate)

PlotLayout.FUSION_MACHINE = v3(0, 0, -19)
PlotLayout.ODDS_BOARD = v3(13, 0, -19)
-- Faces the gate (+Z), yawed this far toward the walkway (-X from here).
PlotLayout.ODDS_BOARD_YAW_TOWARD_WALKWAY_DEGREES = 30

PlotLayout.SIGN_POST_X = 9 -- posts at (+-9, +32)
PlotLayout.SIGN_Z = 32

-- Reserved for a later feature: nothing may be built here.
PlotLayout.GENERATOR_BAYS = { v3(-24, 0, -24), v3(24, 0, -24) }
PlotLayout.GENERATOR_BAY_SIZE = 10 -- reserved square footprint (not in the spec; chosen for the overlap check)

function PlotLayout.GetPedestalPosition(index: number): Vector3
	return v3(PlotLayout.PEDESTAL_XS[index], 0, PlotLayout.PEDESTAL_Z)
end

--[[ Station pads (StationKit) ---------------------------------------------- ]]

PlotLayout.Station = {
	PadDiameter = 8,
	PadHeight = 1,
	PadTopY = 1,
	RimDiameter = 8.4,
	RimHeight = 0.6,
	RimCenterBelowTop = 0.3,
	GlowDiameter = 5,
	GlowHeight = 0.05,
	GlowTransparency = 0.55,
	LightBrightness = 1.5,
	LightRange = 10,
	LabelOffsetY = 8,
	PromptDistance = 7,

	CapsuleDiameter = 2.6,
	CapsuleY = 4.5,
	CapsuleBandHeight = 0.2,
	CapsuleSpinDegPerSec = 60,
	CapsuleBob = 0.3,
	CapsuleBobPeriod = 2,

	ChevronWidth = 3,
	ChevronHeight = 1.2,
	ChevronDepth = 0.5,
	ChevronYs = { 4, 5 },
	ChevronRise = 1,
	ChevronRisePeriod = 1.2,

	ArrowY = 5,
	ArrowShaftSize = v3(0.8, 1.2, 0.5),
	ArrowHeadWidth = 2.4,
	ArrowHeadHeight = 1.2,
	ArrowBob = 0.5,
	ArrowBobPeriod = 1.2,

	GhostTransparency = 0.5,
}

--[[ Droppers + collector ------------------------------------------------------- ]]

PlotLayout.Dropper = {
	BodySize = v3(4, 6, 4),
	HopperSize = v3(5, 2, 5), -- trapezoid on top of the body
	HopperLipHeight = 0.3,
	BeltHeight = 0.3,
	BeltY = 3,
	BeltInflate = 0.2, -- how far the belt stands proud of the body
	SpoutSize = 1.4,
	SpoutY = 4.5, -- on the body's +X face
	BallDiameter = 1.2,
}

PlotLayout.COLLECTOR_SIZE = v3(6, 0.4, 18)
PlotLayout.COLLECTOR_TOP_Y = 0.2

--[[ Pedestals ------------------------------------------------------------------- ]]

PlotLayout.Pedestal = {
	ColumnSize = v3(3.2, 3.5, 3.2),
	CapSize = v3(3.6, 0.4, 3.6),
	OrbCenterY = 5.8, -- above the pedestal's bottom
	OrbDiameter = {
		Common = 1.6,
		Rare = 1.9,
		Epic = 2.2,
		Legendary = 2.6,
		Mythic = 3.0,
	} :: { [string]: number },
	OrbTransparency = 0.15,
	InnerOrbScale = 0.65,
	OrbLightRangeBase = 8,
	OrbLightRangePerRank = 2,
	OrbLightBrightness = 2,
	OrbSpinDegPerSec = 45,
	OrbBob = 0.25,
	OrbBobPeriod = 2.4,
	LabelOffsetY = 9, -- above the pedestal's bottom
	PromptDistance = 6,
}

--[[ Fusion Machine ---------------------------------------------------------------- ]]

PlotLayout.Machine = {
	BaseDiameter = 18,
	BaseHeight = 1.2,
	RimDiameter = 18.6,
	RimHeight = 0.4,
	RimCenterBelowTop = 0.2,
	PylonSize = v3(1, 9, 1),
	PylonRadius = 6,
	PylonAnglesDegrees = { 45, 135, 225, 315 },
	PylonLeanDegrees = 8,
	PylonStripWidth = 0.25,
	CoreDiameter = 4,
	CoreY = 9.5,
	RingSize = v3(0.6, 9, 9), -- Cylinder: X = thickness, Y/Z = diameter
	FloorGlowDiameter = 6,
	FloorGlowHeight = 0.05,
	FloorGlowTransparency = 0.6,
	PromptAnchorY = 3,
	PromptDistance = 10,

	OddsPostSize = v3(0.6, 6, 0.6),
	OddsBoardSize = v3(7, 5, 0.4),
	SurfacePixelsPerStud = 40,
}

--[[ Plot sign gate ------------------------------------------------------------------ ]]

PlotLayout.Gate = {
	PostSize = v3(1, 14, 1),
	BoardSize = v3(20, 4.5, 0.8),
	BoardCenterY = 14.25,
	BorderSize = v3(20.6, 5.1, 0.6),
	StripSize = v3(20, 0.3, 0.9),
	SurfacePixelsPerStud = 40,
}

--[[ Slot grid -------------------------------------------------------------------------
	Two rows of plots facing each other across the street. Slot i (1-based):
	  column c = (i - 1) // 2, row r = (i - 1) % 2
	  x = (c - 2.5) * 80
	  row 0: z = -50, facing +Z; row 1: z = +50, rotated 180 degrees about Y.
]]
PlotLayout.MAX_PLOT_SLOTS = 12
PlotLayout.SLOT_COLUMN_SPACING = 80
PlotLayout.SLOT_COLUMN_CENTER = 2.5
PlotLayout.SLOT_ROW_Z = 50

function PlotLayout.GetSlotCFrame(index: number): CFrame
	local column = (index - 1) // 2
	local row = (index - 1) % 2
	local x = (column - PlotLayout.SLOT_COLUMN_CENTER) * PlotLayout.SLOT_COLUMN_SPACING
	if row == 0 then
		return CFrame.new(x, 0, -PlotLayout.SLOT_ROW_Z)
	end
	return CFrame.new(x, 0, PlotLayout.SLOT_ROW_Z) * CFrame.Angles(0, math.pi, 0)
end

--[[ World: ground and street ------------------------------------------------------------ ]]

PlotLayout.GROUND_SIZE = v3(900, 1, 600)
PlotLayout.GROUND_TOP_Y = -1
PlotLayout.STREET_SIZE = v3(520, 0.1, 36)
PlotLayout.STREET_TOP_Y = -0.95
PlotLayout.LANE_DASH_SIZE = v3(8, 0.05, 0.6)
PlotLayout.LANE_DASH_SPACING = 16
PlotLayout.LANE_DASH_TRANSPARENCY = 0.45

--[[ Layout assertions ---------------------------------------------------------------------
	Runs at require time. Footprints are circles (radius) or rectangles
	(min/max X and Z) in plot-local space. The walkway inlay is flush with
	the floor and deliberately runs under the claim station, so it isn't a
	footprint; the sign posts stand on the front wall by design.
]]
type Footprint = {
	Name: string,
	Circle: { X: number, Z: number, R: number }?,
	Rect: { MinX: number, MaxX: number, MinZ: number, MaxZ: number }?,
}

local function circle(name: string, position: Vector3, radius: number): Footprint
	return { Name = name, Circle = { X = position.X, Z = position.Z, R = radius } }
end

local function rect(name: string, minX: number, maxX: number, minZ: number, maxZ: number): Footprint
	return { Name = name, Rect = { MinX = minX, MaxX = maxX, MinZ = minZ, MaxZ = maxZ } }
end

local function bounds(footprint: Footprint): (number, number, number, number)
	if footprint.Circle then
		local c = footprint.Circle
		return c.X - c.R, c.X + c.R, c.Z - c.R, c.Z + c.R
	end
	local r = footprint.Rect :: { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
	return r.MinX, r.MaxX, r.MinZ, r.MaxZ
end

local function overlaps(a: Footprint, b: Footprint): boolean
	if a.Circle and b.Circle then
		local dx, dz = a.Circle.X - b.Circle.X, a.Circle.Z - b.Circle.Z
		return math.sqrt(dx * dx + dz * dz) < a.Circle.R + b.Circle.R
	end
	if a.Circle or b.Circle then
		local c = (a.Circle or b.Circle) :: { X: number, Z: number, R: number }
		local r = (if a.Rect then a else b) :: Footprint
		local minX, maxX, minZ, maxZ = bounds(r)
		local nearestX = math.clamp(c.X, minX, maxX)
		local nearestZ = math.clamp(c.Z, minZ, maxZ)
		local dx, dz = c.X - nearestX, c.Z - nearestZ
		return math.sqrt(dx * dx + dz * dz) < c.R
	end
	local aMinX, aMaxX, aMinZ, aMaxZ = bounds(a)
	local bMinX, bMaxX, bMinZ, bMaxZ = bounds(b)
	return aMinX < bMaxX and bMinX < aMaxX and aMinZ < bMaxZ and bMinZ < aMaxZ
end

local function dropperFootprint(name: string, position: Vector3): Footprint
	local d = PlotLayout.Dropper
	local half = d.HopperSize.X / 2
	-- The spout sticks out of the body's +X face.
	local spoutReach = d.BodySize.X / 2 + d.SpoutSize
	return rect(name, position.X - half, position.X + math.max(half, spoutReach), position.Z - half, position.Z + half)
end

local function boxFootprint(name: string, position: Vector3, sizeX: number, sizeZ: number): Footprint
	return rect(name, position.X - sizeX / 2, position.X + sizeX / 2, position.Z - sizeZ / 2, position.Z + sizeZ / 2)
end

local function checkLayout()
	local stationRadius = PlotLayout.Station.RimDiameter / 2
	local footprints: { Footprint } = {
		circle("ClaimStation", PlotLayout.CLAIM_STATION, stationRadius),
		circle("GachaStation", PlotLayout.GACHA_STATION, stationRadius),
		circle("MultiplierStation", PlotLayout.MULTIPLIER_STATION, stationRadius),
		dropperFootprint("Dropper1", PlotLayout.DROPPER1),
		dropperFootprint("Dropper2", PlotLayout.DROPPER2),
		boxFootprint("Collector", PlotLayout.COLLECTOR, PlotLayout.COLLECTOR_SIZE.X, PlotLayout.COLLECTOR_SIZE.Z),
		circle("FusionMachine", PlotLayout.FUSION_MACHINE, PlotLayout.Machine.RimDiameter / 2),
		circle("OddsBoard", PlotLayout.ODDS_BOARD, PlotLayout.Machine.OddsBoardSize.X / 2),
	}
	for index = 1, PlotLayout.PEDESTAL_COUNT do
		local cap = PlotLayout.Pedestal.CapSize
		table.insert(footprints, boxFootprint("Pedestal" .. index, PlotLayout.GetPedestalPosition(index), cap.X, cap.Z))
	end
	for index, bay in PlotLayout.GENERATOR_BAYS do
		local size = PlotLayout.GENERATOR_BAY_SIZE
		table.insert(footprints, boxFootprint("GeneratorBay" .. index, bay, size, size))
	end

	local inner = PlotLayout.PLOT_HALF - PlotLayout.WALL_THICKNESS
	for _, footprint in footprints do
		local minX, maxX, minZ, maxZ = bounds(footprint)
		assert(
			minX >= -inner and maxX <= inner and minZ >= -inner and maxZ <= inner,
			("PlotLayout: %s sits outside the walls"):format(footprint.Name)
		)
	end
	for i = 1, #footprints do
		for j = i + 1, #footprints do
			assert(
				not overlaps(footprints[i], footprints[j]),
				("PlotLayout: %s overlaps %s"):format(footprints[i].Name, footprints[j].Name)
			)
		end
	end

	-- Pedestals must stay clear of the walkway.
	local walkwayHalf = PlotLayout.WALKWAY_WIDTH / 2
	for index = 1, PlotLayout.PEDESTAL_COUNT do
		local x = PlotLayout.PEDESTAL_XS[index]
		assert(
			math.abs(x - PlotLayout.WALKWAY_X) - PlotLayout.Pedestal.CapSize.X / 2 >= walkwayHalf,
			("PlotLayout: Pedestal%d overlaps the walkway"):format(index)
		)
	end
	assert(#PlotLayout.PEDESTAL_XS == PlotLayout.PEDESTAL_COUNT, "PlotLayout: PEDESTAL_XS must list every pedestal")

	-- The gate gap must fit inside the sign posts, and the slots must not
	-- overlap each other.
	assert(PlotLayout.GATE_HALF_WIDTH < PlotLayout.SIGN_POST_X, "PlotLayout: sign posts stand inside the gate gap")
	assert(PlotLayout.SLOT_COLUMN_SPACING > PlotLayout.FLOOR_SIZE.X, "PlotLayout: neighbouring plots overlap")
	assert(
		PlotLayout.SLOT_ROW_Z - PlotLayout.PLOT_HALF - PlotLayout.GATE_RAMP_LENGTH >= 0,
		"PlotLayout: gate ramps cross the street centre line"
	)
end

checkLayout()

return PlotLayout
