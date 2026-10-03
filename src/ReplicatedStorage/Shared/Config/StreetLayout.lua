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
end

return StreetLayout
