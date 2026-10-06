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
PlotLayout.WALL_STRIP_HEIGHT = 0.12
PlotLayout.WALL_STRIP_WIDTH = 0.35
PlotLayout.GATE_HALF_WIDTH = 7 -- front wall gap, x -7..+7

PlotLayout.GATE_RAMP_WIDTH = 14
PlotLayout.GATE_RAMP_HEIGHT = 1 -- street level up to the floor
PlotLayout.GATE_RAMP_LENGTH = 3 -- z +32..+35, outside the gap

PlotLayout.SPAWN_POSITION = v3(0, 0, 40) -- on the street in front of the gate
PlotLayout.SPAWN_SIZE = v3(6, 1, 6)
PlotLayout.SPAWN_CHARACTER_CLEARANCE = 3 -- above the spawn top when moving a character there

-- Inside the walls (the inner wall faces), in plot-local space. The heist
-- uses it for delivery (thief home) and the shield's eject; Y is a generous
-- band so a jump still counts but someone on a roof doesn't.
PlotLayout.INSIDE_MIN_Y = -2
PlotLayout.INSIDE_MAX_Y = 30

function PlotLayout.IsInsidePlot(localPos: Vector3): boolean
	local inner = PlotLayout.PLOT_HALF - PlotLayout.WALL_THICKNESS
	return math.abs(localPos.X) <= inner
		and math.abs(localPos.Z) <= inner
		and localPos.Y >= PlotLayout.INSIDE_MIN_Y
		and localPos.Y <= PlotLayout.INSIDE_MAX_Y
end

-- The lab shield: ForceField panels just outside all four walls (the front
-- one split around the gate) plus a thin Neon line across the gate gap,
-- each panel topped by a glowing Neon edge. Non-colliding: the eject loop
-- does the keeping-out. Clients draw the rest (HeistController): the
-- pulsing lock over the gate and the gate sign every player sees.
PlotLayout.ShieldFence = {
	Height = 12, -- taller than a character (was 10), up to the sign posts
	Thickness = 0.2,
	OutsetFromWall = 0.4, -- gap between the wall's outer face and the panel
	TopEdgeHeight = 0.3, -- the glowing Neon strip along each panel's top
	GateLineThickness = 0.3,
	GateLineY = 0.5,
	LockIconY = 7, -- the pulsing lock, in the gate under the sign board
	GateSignY = 18.8, -- the LOCKED / OPEN sign, above the sign board (top 16.5)
	GateSignStuds = Vector2.new(12, 2.4),
	GateSignMaxDistance = 150,
}

--[[ Plan: local (x, 0, z) of each element --------------------------------- ]]

PlotLayout.CLAIM_STATION = v3(0, 0, 24)
-- The heist LOCK console: inside the gate, right of the walkway, between the
-- claim pad and the Gacha Pad, facing +Z (the gate) so you see it walking in.
PlotLayout.LOCK_CONSOLE = v3(10, 0, 27)
PlotLayout.GACHA_STATION = v3(20, 0, 22)
PlotLayout.MULTIPLIER_STATION = v3(20, 0, 8)

-- Every lab builds all 6; spots 5-6 (a second row behind the first, between
-- its pairs) only work with the +2 Pedestals pass (ShopConfig: 4 base,
-- 6 with the pass). Without it they're a dim plinth with a locked label.
PlotLayout.PEDESTAL_COUNT = 6
PlotLayout.PEDESTAL_XS = { -17, -6, 6, 17, -11.5, 11.5 } -- face +Z (the gate)
PlotLayout.PEDESTAL_ZS = { -2, -2, -2, -2, -10, -10 }
PlotLayout.LockedPedestalTransparency = 0.55 -- the dim plinth (column + cap)
-- The VIP pass's gold band along the top of each wall's outer face.
PlotLayout.VipTrimHeight = 0.35
PlotLayout.VipTrimDepth = 0.12

PlotLayout.FUSION_MACHINE = v3(0, 0, -19)
PlotLayout.ODDS_BOARD = v3(14, 0, -19) -- Events 2: 13 -> 14 for the 9-wide board (clear of the machine and the portal)
-- Faces the gate (+Z), yawed this far toward the walkway (-X from here).
PlotLayout.ODDS_BOARD_YAW_TOWARD_WALKWAY_DEGREES = 30

PlotLayout.SIGN_POST_X = 9 -- posts at (+-9, +32)
PlotLayout.SIGN_Z = 32

--[[ Rebirth Portal (back-right corner) ----------------------------------------
	Faces +Z (toward the plot's centre). A round base with a SurfaceGui ring
	face, two pillars and a beam framing a swirl sheet (SurfaceGui on both
	faces, animated client-side), a light, an owner-only progress label and
	an owner-only prompt that opens the client's Rebirth panel.
]]
PlotLayout.RebirthPortal = {
	Position = v3(24, 0, -24),
	Footprint = 10, -- square footprint kept clear in the overlap check
	BaseDiameter = 8,
	BaseHeight = 0.4, -- top at y 0.4
	PillarSize = v3(1.2, 9, 1.2), -- standing on the base
	PillarX = 3.4, -- pillar centres at x +-3.4 from the portal centre
	BeamSize = v3(8, 1.2, 1.2), -- on top of the pillars
	EdgeWidth = 0.25, -- Neon strip on each pillar's inner face
	EdgeDepth = 0.05,
	SheetSize = v3(5.6, 7.6, 0.2), -- between the pillars, Transparency 1
	SheetPixelsPerStud = 30,
	LightRange = 14,
	LightBrightnessIdle = 0.5,
	LightBrightnessReady = 1.5,
	SwirlIdleTransparency = 0.65,
	SwirlDegPerSec = 40, -- while ready
	RingPulsePeriod = 1.2, -- the base ring pulses while ready
	LabelOffsetY = 13, -- above the portal's base centre
	LabelMaxDistance = 80,
	PromptDistance = 8,
	PromptHoldSeconds = 0.5,
}

--[[ Factory line --------------------------------------------------------------
	The five generators stand in one row along the left wall, cheapest at the
	front (near the gate), each facing +X with a Spout over the FactoryBelt.
	The belt runs toward -Z (the back) into the Collector in the back-left
	corner. The cash balls riding it are client-side only (FactoryController).
]]
export type GeneratorSpot = {
	Position: Vector3, -- plot-local centre
	Footprint: number, -- square body width
	Height: number, -- body height
}

-- Keyed by TycoonConfig generator Id. Every generator faces +X (the belt).
PlotLayout.GENERATORS = {
	basic_generator = { Position = v3(-27, 0, 22), Footprint = 3, Height = 3 },
	ember_forge = { Position = v3(-27, 0, 14), Footprint = 3, Height = 4 },
	flare_reactor = { Position = v3(-27, 0, 6), Footprint = 3, Height = 5 },
	core_engine = { Position = v3(-27, 0, -3), Footprint = 4, Height = 6 },
	singularity_core = { Position = v3(-27, 0, -13), Footprint = 5, Height = 8 },
} :: { [string]: GeneratorSpot }

PlotLayout.FactoryBelt = {
	X = -21, -- centre line
	StartZ = 27, -- front end
	EndZ = -21, -- back end, at the collector's front edge
	Width = 3,
	Height = 0.4, -- bottom on the floor, top at y 0.4
	EdgeSize = v3(0.25, 0.12, 0), -- Neon strip along each long side (Z = belt length)
	Speed = 10, -- studs/s the balls ride at (the belt itself doesn't move players)
}

-- The client-side cash balls (FactoryController).
PlotLayout.FactoryBall = {
	Diameter = {
		Common = 0.9,
		Rare = 1.05,
		Epic = 1.2,
		Legendary = 1.4,
		Mythic = 1.6,
	} :: { [string]: number },
	LightTiers = { Legendary = true, Mythic = true } :: { [string]: boolean },
	LightRange = 4,
	LightBrightness = 1,
	ArcRise = 1, -- studs above the straight spout-to-belt line, mid-arc
}

PlotLayout.Collector = {
	Position = v3(-21, 0, -24),
	Size = v3(6, 0.4, 6), -- top at y 0.4
	EdgeHeight = 0.12,
	EdgeWidth = 0.25,
	LightRange = 10,
	LightBrightness = 1,
	LabelOffsetY = 6, -- pad label, above the collector's centre
	LabelMaxDistance = 60,
	PopHeight = 1.5, -- "+$X" pops start this far above its top
}

PlotLayout.Generator = {
	BandHeight = 0.3,
	BandAt = 0.4, -- fraction of body height
	BandInflate = 0.2, -- band is (footprint + this) wide
	CoreScale = 0.55, -- core diameter / footprint
	CoreInnerScale = 0.65,
	CoreTransparency = 0.15,
	CoreSpinDegPerSec = 30,
	CoreBob = 0.15,
	CoreBobPeriod = 2,
	NeonFromLevel = 10, -- band turns Neon at this level
	MaxLightRange = 8,
	MaxLightBrightness = 1.5,
	GhostLockedTransparency = 0.6,
	GhostBuyTransparency = 0.5,
	ScreenPixelsPerStud = 40,
	LabelAboveCore = 1.5, -- owner label, studs above the core's top
	LabelMaxDistance = 30,
	PromptDistance = 7,
	SpoutSize = 1.4, -- cube on the +X face (toward the belt)
	SpoutAt = 0.7, -- fraction of body height
	SpoutLipWidth = 0.15, -- Neon lip framing the opening, tier colour
}

function PlotLayout.GetBeltLength(): number
	local belt = PlotLayout.FactoryBelt
	return belt.StartZ - belt.EndZ
end

function PlotLayout.GetPedestalPosition(index: number): Vector3
	return v3(PlotLayout.PEDESTAL_XS[index], 0, PlotLayout.PEDESTAL_ZS[index])
end

--[[ Station pads (StationKit) ---------------------------------------------- ]]

PlotLayout.Station = {
	PadDiameter = 8,
	PadHeight = 1,
	PadTopY = 1,
	-- A thin Neon band on the pad's side only (never a flat Neon disc).
	RimDiameter = 8.1, -- pad diameter + 0.1
	RimHeight = 0.15,
	RimCenterBelowTop = 0.35,
	LabelOffsetY = 8,
	PromptDistance = 7,
	MultiPromptOffsetPx = 72, -- screen offset stacking the gacha's Pull x10 prompt under Pull

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

--[[ Pad faces (stations + machine floor) -------------------------------------
	An invisible square part just above a pad top carrying a SurfaceGui: an
	accent ring, a faked radial glow (two stacked translucent circles) and an
	optional word. Replaces the old flat Neon discs, which rendered as a fan
	of triangles ("pizza slices") under bloom.
]]
PlotLayout.Face = {
	Thickness = 0.05,
	GapAbovePad = 0.02, -- face bottom above the pad top
	PixelsPerStud = 50,
	Brightness = 1.6,
	RingStrokePx = 12,
	GlowInset = 0.12, -- each side
	GlowOuterTransparency = 0.92,
	GlowCoreScale = 0.55,
	GlowCoreTransparency = 0.75,
	WordHeight = 0.38, -- of the face
	WordStroke = 3,
	LightBrightness = 1.2,
	LightRange = 9,
}

--[[ Pedestals ------------------------------------------------------------------- ]]

PlotLayout.Pedestal = {
	ColumnSize = v3(3.2, 3.5, 3.2),
	CapSize = v3(3.6, 0.4, 3.6),
	CapLipInflate = 0.2, -- lip is (cap + this) wide
	CapLipHeight = 0.12,
	OrbCenterY = 5.8, -- above the pedestal's bottom
	OrbDiameter = {
		Common = 1.6,
		Rare = 1.9,
		Epic = 2.2,
		Legendary = 2.6,
		Mythic = 3.0,
		Secret = 3.2, -- Mythic + 0.2
	} :: { [string]: number },
	OrbTransparency = 0.15,
	InnerOrbScale = 0.65,
	-- Mutation satellites orbiting the orb (WorldAnimationController, FT_Orbit).
	SatelliteDiameter = 0.35,
	SatelliteRadiusExtra = 0.7, -- orbit radius = orb radius + this
	SatelliteTiltDegrees = 20,
	SatelliteTrailLifetime = 0.25,
	OrbLightRangeBase = 6,
	OrbLightRangePerRank = 1.5,
	OrbLightBrightness = 1,
	OrbSpinDegPerSec = 45,
	OrbBob = 0.25,
	OrbBobPeriod = 2.4,
	LabelOffsetY = 8.5, -- filled label, above the pedestal's bottom
	EmptyLabelOffsetY = 5, -- the small EMPTY pill, above the pedestal's bottom
	StealMarkerOffsetY = 11.5, -- the heist's red hand marker, above the filled label
	GuardedChipOffsetY = 13.5, -- the heist's 🛡 GUARDED chip, above the label and marker
	PromptDistance = 6,
}

--[[ LOCK console (heist shield button) ---------------------------------------------- ]]

PlotLayout.LockConsole = {
	Footprint = 3, -- square, for the overlap check
	PostSize = v3(2, 4.5, 2),
	TopSize = v3(3.5, 0.6, 2.5),
	TopTiltDegrees = 25, -- the top leans toward +Z (the gate)
	ButtonDiameter = 1.5, -- a SurfaceGui disc on the top (no flat Neon disc)
	ButtonGap = 0.03, -- the disc's face part sits this far above the top
	PromptDistance = 8,
	LabelOffsetY = 7, -- above the post's bottom
	LabelMaxDistance = 60,
}

--[[ Golden Rain coins (EventService) ------------------------------------------------- ]]

PlotLayout.EventCoin = {
	Size = v3(0.3, 2, 2), -- a Neon cylinder on its edge (seen from the side)
	CenterY = 1.6, -- above the floor top
	SpawnMargin = 1.5, -- clear of walls and every footprint by this much
	SpawnTries = 12, -- random points tried per coin
	SpinDegPerSec = 120,
	Bob = 0.35,
	BobPeriod = 1.2,
	BigScale = 2, -- a BIG coin is this many times the size
}

--[[ Fusion Machine ---------------------------------------------------------------- ]]

PlotLayout.Machine = {
	BaseDiameter = 18,
	BaseHeight = 1.2,
	RimDiameter = 18.1, -- base diameter + 0.1, a thin band on the side only
	RimHeight = 0.15,
	RimCenterBelowTop = 0.35,
	FaceDiameter = 10,
	PylonSize = v3(1, 9, 1),
	PylonRadius = 6,
	PylonAnglesDegrees = { 45, 135, 225, 315 },
	PylonLeanDegrees = 8,
	PylonStripWidth = 0.25,
	PylonStripDepth = 0.1,
	CoreDiameter = 4,
	CoreY = 9.5,
	RingSize = v3(0.6, 9, 9), -- Cylinder: X = thickness, Y/Z = diameter
	PromptAnchorY = 3,
	PromptDistance = 10,

	OddsPostSize = v3(0.6, 6, 0.6),
	OddsBoardSize = v3(9, 6, 0.4), -- Events 2: a real table (was 7 x 5)
	OddsPixelsPerStud = 60,
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

--[[ World: ground (the street and its belts are in StreetLayout) ------------------------ ]]

PlotLayout.GROUND_SIZE = v3(900, 1, 600)
PlotLayout.GROUND_TOP_Y = -1

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

local function boxFootprint(name: string, position: Vector3, sizeX: number, sizeZ: number): Footprint
	return rect(name, position.X - sizeX / 2, position.X + sizeX / 2, position.Z - sizeZ / 2, position.Z + sizeZ / 2)
end

-- Every footprint on the plan: (stations, machine, board, console and
-- pedestals; the factory line; the walkway). The one list, shared by the
-- assertions and IsFloorPointFree.
local function collectFootprints(): ({ Footprint }, { Footprint }, Footprint)
	local stationRadius = PlotLayout.Station.RimDiameter / 2
	local footprints: { Footprint } = {
		circle("ClaimStation", PlotLayout.CLAIM_STATION, stationRadius),
		circle("GachaStation", PlotLayout.GACHA_STATION, stationRadius),
		circle("MultiplierStation", PlotLayout.MULTIPLIER_STATION, stationRadius),
		circle("FusionMachine", PlotLayout.FUSION_MACHINE, PlotLayout.Machine.RimDiameter / 2),
		circle("OddsBoard", PlotLayout.ODDS_BOARD, PlotLayout.Machine.OddsBoardSize.X / 2),
		boxFootprint("LockConsole", PlotLayout.LOCK_CONSOLE, PlotLayout.LockConsole.Footprint, PlotLayout.LockConsole.Footprint),
	}
	for index = 1, PlotLayout.PEDESTAL_COUNT do
		local cap = PlotLayout.Pedestal.CapSize
		table.insert(footprints, boxFootprint("Pedestal" .. index, PlotLayout.GetPedestalPosition(index), cap.X, cap.Z))
	end
	-- The factory line: generators (with the Spout reaching toward the belt),
	-- the belt, the collector, and the Rebirth Portal's corner.
	local factory: { Footprint } = {}
	for id, spot in PlotLayout.GENERATORS do
		local half = spot.Footprint / 2
		local p = spot.Position
		table.insert(
			factory,
			rect("Generator_" .. id, p.X - half, p.X + half + PlotLayout.Generator.SpoutSize, p.Z - half, p.Z + half)
		)
	end
	local belt = PlotLayout.FactoryBelt
	table.insert(factory, rect("FactoryBelt", belt.X - belt.Width / 2, belt.X + belt.Width / 2, belt.EndZ, belt.StartZ))
	local collector = PlotLayout.Collector
	table.insert(factory, boxFootprint("Collector", collector.Position, collector.Size.X, collector.Size.Z))
	local portal = PlotLayout.RebirthPortal
	table.insert(factory, boxFootprint("RebirthPortal", portal.Position, portal.Footprint, portal.Footprint))
	local walkwayHalfWidth = PlotLayout.WALKWAY_WIDTH / 2
	local walkway = rect(
		"Walkway",
		PlotLayout.WALKWAY_X - walkwayHalfWidth,
		PlotLayout.WALKWAY_X + walkwayHalfWidth,
		PlotLayout.WALKWAY_Z_MIN,
		PlotLayout.WALKWAY_Z_MAX
	)
	return footprints, factory, walkway
end

-- True when a point on the floor (plot-local x, z) is inside the walls by
-- `margin` and at least `margin` from every station, pedestal, machine and
-- factory footprint (the walkway is fine). Golden Rain drops coins here.
function PlotLayout.IsFloorPointFree(x: number, z: number, margin: number): boolean
	local inner = PlotLayout.PLOT_HALF - PlotLayout.WALL_THICKNESS - margin
	if math.abs(x) > inner or math.abs(z) > inner then
		return false
	end
	local footprints, factory = collectFootprints()
	local probe = circle("Probe", v3(x, 0, z), margin)
	for _, list in { footprints, factory } do
		for _, footprint in list do
			if overlaps(probe, footprint) then
				return false
			end
		end
	end
	return true
end

local function checkLayout()
	local footprints, factory, walkway = collectFootprints()
	local belt = PlotLayout.FactoryBelt
	local collector = PlotLayout.Collector
	local portal = PlotLayout.RebirthPortal
	for _, footprint in factory do
		assert(not overlaps(footprint, walkway), ("PlotLayout: %s overlaps the walkway"):format(footprint.Name))
		table.insert(footprints, footprint)
	end
	-- Each Spout must reach no further than the belt's near edge, and the
	-- belt must end where the collector begins.
	for id, spot in PlotLayout.GENERATORS do
		assert(
			spot.Position.X + spot.Footprint / 2 + PlotLayout.Generator.SpoutSize <= belt.X - belt.Width / 2,
			("PlotLayout: Generator_%s's spout reaches over the belt"):format(id)
		)
		assert(
			spot.Position.Z <= belt.StartZ and spot.Position.Z >= belt.EndZ,
			("PlotLayout: Generator_%s is not alongside the belt"):format(id)
		)
	end
	-- The portal's parts must fit its footprint, and the sheet its pillars.
	assert(
		portal.BeamSize.X <= portal.Footprint and portal.BaseDiameter <= portal.Footprint,
		"PlotLayout: the Rebirth Portal is wider than its footprint"
	)
	assert(
		math.abs((portal.PillarX - portal.PillarSize.X / 2) * 2 - portal.SheetSize.X) < 1e-6,
		"PlotLayout: the portal sheet must span exactly between the pillars"
	)
	assert(
		math.abs(portal.BeamSize.X - (portal.PillarX + portal.PillarSize.X / 2) * 2) < 1e-6,
		"PlotLayout: the portal beam must span exactly across the pillars"
	)
	assert(
		belt.X == collector.Position.X and belt.EndZ == collector.Position.Z + collector.Size.Z / 2,
		"PlotLayout: the belt must end at the collector's front edge, on its centre line"
	)

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
	assert(#PlotLayout.PEDESTAL_ZS == PlotLayout.PEDESTAL_COUNT, "PlotLayout: PEDESTAL_ZS must list every pedestal")

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
