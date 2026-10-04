--!strict
--[[
	StreetLayout
	------------
	Geometry of the street between the two rows of plots, and the speed
	belts running down its middle. World space: the street's long axis is
	world X, centred on z = 0.

	Across the street (z):  plain | EastRail | EastBelt (+X) | Median |
	WestBelt (-X) | WestRail | plain. The belts replace the old centre-line
	dashes.

	The assertion block at the bottom runs at require time.
]]
local PlotLayout = require(script.Parent.PlotLayout)

local StreetLayout = {}

local v3 = Vector3.new

StreetLayout.STREET_SIZE = v3(520, 0.1, 36)
StreetLayout.STREET_TOP_Y = -0.95

-- Belts and median run the street's length minus this (8 at each end).
StreetLayout.BELT_END_INSET = 16
StreetLayout.BELT_WIDTH = 7
StreetLayout.BELT_HEIGHT = 0.3 -- belt top sits this far above the street top
StreetLayout.BELT_CENTER_Z = 4.5
StreetLayout.BELT_SPEED = 28 -- studs/s
StreetLayout.BELT_VELOCITY_REFRESH_SECONDS = 1

StreetLayout.MEDIAN_WIDTH = 2
StreetLayout.MEDIAN_HEIGHT = 0.5

StreetLayout.RAIL_WIDTH = 0.3 -- across the street
StreetLayout.RAIL_HEIGHT = 0.12
StreetLayout.RAIL_CENTER_Z = 8.15 -- on each belt's outer edge

StreetLayout.ROLLER_DIAMETER = 0.6 -- end caps; length = BELT_WIDTH

StreetLayout.CHEVRON_SPACING = 10
StreetLayout.CHEVRON_BAR_SIZE = v3(1.8, 0.05, 0.22)
StreetLayout.CHEVRON_ANGLE_DEGREES = 45
StreetLayout.CHEVRON_LIFT = 0.03 -- above the belt top
StreetLayout.CHEVRON_CULL_DISTANCE = 260 -- from the street centre

-- Plain street wanted on each side of the belts + median.
StreetLayout.MIN_PLAIN_STREET = 8

export type Lane = {
	Belt: string,
	Rail: string,
	Side: number, -- -1 = the -Z half of the street, +1 = the +Z half
	Direction: number, -- +1 moves toward +X, -1 toward -X
	RailColor: string, -- UITheme.World token
}

StreetLayout.LANES = {
	{ Belt = "EastBelt", Rail = "EastRail", Side = -1, Direction = 1, RailColor = "AccentGreen" },
	{ Belt = "WestBelt", Rail = "WestRail", Side = 1, Direction = -1, RailColor = "AccentBlue" },
} :: { Lane }

-- Meteor Shower landing zone: the plain street strips between each rail and
-- the gate ramps (|z| from MinAbsZ to MaxAbsZ, either side), clear of the
-- belts' edges and of every plot, inset from the street's ends.
StreetLayout.MeteorBounds = {
	EndInset = 30, -- from each end of the street
	MinAbsZ = 9.5, -- beyond the rails (8.15 + 0.15) with a margin
	MaxAbsZ = 13.5, -- short of the gate ramps (they reach |z| 15)
	GateRampReachAbsZ = 15, -- the ramps poke 3 studs into the street from the kerb
}

-- The crater a meteor leaves: a dark rock disc (SmoothPlastic, not Neon)
-- with orange Neon crack strips and a glowing core rock.
StreetLayout.MeteorCrater = {
	Diameter = 7,
	Height = 0.5,
	CrackCount = 5,
	CrackLength = 3,
	CrackWidth = 0.22,
	CrackHeight = 0.08,
	CoreDiameter = 1.4,
	FallFrom = Vector3.new(70, 140, 30), -- start offset of the falling rock
	RockDiameter = 3,
}

-- A random street point inside MeteorBounds (y = street top).
function StreetLayout.GetRandomMeteorPoint(rng: Random): Vector3
	local b = StreetLayout.MeteorBounds
	local halfX = StreetLayout.STREET_SIZE.X / 2 - b.EndInset
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	return Vector3.new(rng:NextNumber(-halfX, halfX), StreetLayout.STREET_TOP_Y, side * rng:NextNumber(b.MinAbsZ, b.MaxAbsZ))
end

-- The two Event Boards (NOW / NEXT / THEN + the Admin Abuse line): one past
-- each end of the street, on the grass, its Front face looking down the
-- street at the plots. Past the street's end, so no belt, rail or gate ramp
-- is ever behind one (asserted below).
StreetLayout.EventBoard = {
	CenterAbsX = 276, -- board centre, from the street centre along x
	Width = 30, -- across the street (z)
	Height = 17,
	Thickness = 1,
	BottomY = 3, -- above the street top
	PostWidth = 1.2,
	EndMargin = 6, -- at least this far past the street's end
	PixelsPerStud = 24,
	MaxDistance = 420, -- SurfaceGui: readable from most of the street
}

-- Each board's centre CFrame, looking at the street centre (Front = LookVector).
function StreetLayout.GetEventBoardCFrames(): { CFrame }
	local b = StreetLayout.EventBoard
	local y = StreetLayout.STREET_TOP_Y + b.BottomY + b.Height / 2
	local list = {}
	for _, side in { -1, 1 } do
		local position = Vector3.new(side * b.CenterAbsX, y, 0)
		table.insert(list, CFrame.lookAt(position, Vector3.new(0, y, 0)))
	end
	return list
end

-- The three street leaderboards (LeaderboardService): on the grass past the
-- street's ends, flanking the Event Boards (one each side of the west board,
-- one on the east board's -z side), facing down the street like them. Past
-- the street's end and the last plot column, so no belt, gate or plot is
-- behind one; clear of the Event Boards in z (asserted below).
export type LeaderboardSpot = { Key: string, SideX: number, SideZ: number }

StreetLayout.Leaderboard = {
	CenterAbsX = 276, -- in line with the Event Boards
	Width = 26, -- along z
	Height = 20,
	Thickness = 1,
	BottomY = 2, -- above the street top
	PostWidth = 1.2,
	EventBoardGap = 4, -- clear z between an Event Board's edge and a leaderboard's
	PlotClearance = 6, -- clear x past the outermost plot's floor
	PixelsPerStud = 24,
	MaxDistance = 420,
	Spots = {
		{ Key = "Income", SideX = -1, SideZ = -1 },
		{ Key = "Rebirths", SideX = -1, SideZ = 1 },
		{ Key = "Index", SideX = 1, SideZ = -1 },
	} :: { LeaderboardSpot },
}

-- A leaderboard's centre z distance from the street's centre line.
function StreetLayout.GetLeaderboardAbsZ(): number
	local l = StreetLayout.Leaderboard
	return StreetLayout.EventBoard.Width / 2 + l.EventBoardGap + l.Width / 2
end

-- Each spot's centre CFrame, its Front face looking along the street.
function StreetLayout.GetLeaderboardCFrame(spot: LeaderboardSpot): CFrame
	local l = StreetLayout.Leaderboard
	local y = StreetLayout.STREET_TOP_Y + l.BottomY + l.Height / 2
	local position = Vector3.new(spot.SideX * l.CenterAbsX, y, spot.SideZ * StreetLayout.GetLeaderboardAbsZ())
	return CFrame.lookAt(position, position + Vector3.new(-spot.SideX, 0, 0))
end

function StreetLayout.GetBeltLength(): number
	return StreetLayout.STREET_SIZE.X - StreetLayout.BELT_END_INSET
end

function StreetLayout.GetBeltTopY(): number
	return StreetLayout.STREET_TOP_Y + StreetLayout.BELT_HEIGHT
end

--[[ Assertions -------------------------------------------------------------- ]]

do
	local halfStreet = StreetLayout.STREET_SIZE.Z / 2
	local beltsAndMedian = StreetLayout.BELT_WIDTH * 2 + StreetLayout.MEDIAN_WIDTH
	assert(
		halfStreet * 2 - beltsAndMedian >= StreetLayout.MIN_PLAIN_STREET * 2,
		"StreetLayout: belts + median leave less than MIN_PLAIN_STREET on each side"
	)

	-- Belts sit edge to edge with the median, rails hug the belts' outer
	-- edges, and everything stays MIN_PLAIN_STREET clear of the kerb.
	local beltInner = StreetLayout.BELT_CENTER_Z - StreetLayout.BELT_WIDTH / 2
	local beltOuter = StreetLayout.BELT_CENTER_Z + StreetLayout.BELT_WIDTH / 2
	assert(
		math.abs(beltInner - StreetLayout.MEDIAN_WIDTH / 2) < 1e-6,
		"StreetLayout: belts must sit against the median"
	)
	local railInner = StreetLayout.RAIL_CENTER_Z - StreetLayout.RAIL_WIDTH / 2
	local railOuter = StreetLayout.RAIL_CENTER_Z + StreetLayout.RAIL_WIDTH / 2
	assert(railInner >= beltOuter - 1e-6, "StreetLayout: rails overlap the belts")
	assert(
		halfStreet - railOuter >= StreetLayout.MIN_PLAIN_STREET,
		"StreetLayout: rails leave less than MIN_PLAIN_STREET to the kerb"
	)
	assert(StreetLayout.GetBeltLength() > 0, "StreetLayout: belts are longer than the street")

	-- Meteors land on plain street: past the rails, short of the gate ramps
	-- and inside the kerb, so never on a belt or in a plot.
	local meteor = StreetLayout.MeteorBounds
	assert(meteor.MinAbsZ > railOuter, "StreetLayout: meteor zone overlaps the rails/belts")
	assert(meteor.MaxAbsZ < meteor.GateRampReachAbsZ, "StreetLayout: meteor zone reaches the gate ramps")
	assert(meteor.MaxAbsZ < halfStreet and meteor.MinAbsZ < meteor.MaxAbsZ, "StreetLayout: meteor zone is off the street")

	-- Event Boards stand past the street's ends: the belts (and their end
	-- rollers) stop inside the street, and every plot gate faces the street
	-- inside its length, so nothing walkable is blocked.
	local board = StreetLayout.EventBoard
	local boardInnerX = board.CenterAbsX - board.Thickness / 2
	assert(
		boardInnerX - StreetLayout.STREET_SIZE.X / 2 >= board.EndMargin,
		"StreetLayout: an Event Board stands on the street"
	)
	assert(boardInnerX > StreetLayout.GetBeltLength() / 2, "StreetLayout: an Event Board blocks a belt")

	-- Leaderboards: past the street's end, past the outermost plot, clear of
	-- the Event Boards, on the ground, and never two on one spot.
	local lb = StreetLayout.Leaderboard
	local lbInnerX = lb.CenterAbsX - lb.Thickness / 2
	assert(lbInnerX - StreetLayout.STREET_SIZE.X / 2 >= board.EndMargin, "StreetLayout: a leaderboard stands on the street")
	local outermostPlotX = (PlotLayout.MAX_PLOT_SLOTS / 2 - 1 - PlotLayout.SLOT_COLUMN_CENTER) * PlotLayout.SLOT_COLUMN_SPACING
		+ PlotLayout.FLOOR_SIZE.X / 2
	assert(lbInnerX - outermostPlotX >= lb.PlotClearance, "StreetLayout: a leaderboard stands in a plot")
	local lbAbsZ = StreetLayout.GetLeaderboardAbsZ()
	assert(lbAbsZ - lb.Width / 2 - board.Width / 2 >= lb.EventBoardGap - 1e-6, "StreetLayout: a leaderboard overlaps an Event Board")
	assert(
		lb.CenterAbsX + lb.Thickness / 2 + lb.PostWidth * 2 < PlotLayout.GROUND_SIZE.X / 2
			and lbAbsZ + lb.Width / 2 < PlotLayout.GROUND_SIZE.Z / 2,
		"StreetLayout: a leaderboard stands off the ground"
	)
	local taken: { [string]: boolean } = {}
	for _, spot in lb.Spots do
		local key = ("%d,%d"):format(spot.SideX, spot.SideZ)
		assert(not taken[key], "StreetLayout: two leaderboards share a spot")
		taken[key] = true
	end
end

return StreetLayout
