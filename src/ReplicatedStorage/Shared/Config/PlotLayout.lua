-- The one piece of plot-row layout math that two otherwise-independent
-- services both need to agree on: where Floor's row-covering edges actually
-- end up. TycoonService.resizeFloorToFitRow uses it to size Floor itself;
-- FusionMachineService uses it as the starting point for the connector
-- walkway bridging Floor's edge to the machine's own Base. Kept here instead
-- of duplicated as a hardcoded number in FusionMachineService, since that's
-- exactly the kind of silent-assumption mismatch that's caused most of this
-- project's layout bugs so far (pedestal row vs. plot spacing, the machine
-- vs. the row, the Multiplier Pad vs. ClaimButton).
local PlotLayout = {}

PlotLayout.FLOOR_ROW_MARGIN_STUDS = 10

-- Main row (Dropper1 -> Dropper2 button -> Multiplier Pad -> Gacha Pad), all
-- at local Z = 0. Gacha Pad follows the Multiplier Pad (default X = 24, can
-- be pushed as far as X = 32 to dodge ClaimButton - see
-- MULTIPLIER_PAD_MAX_ROW_OFFSET_STUDS in TycoonService.lua) - it no longer
-- follows the Pedestal row, since Pedestals moved off the row entirely into
-- their own showcase area below.
--
-- 52, not 36: Gacha Pad's ProximityPrompt has a 10-stud MaxActivationDistance,
-- so its activation boundary sits at (GACHA_PAD_ROW_OFFSET_STUDS - 10). Two
-- cases both have to clear Multiplier Pad's own 4-stud-wide footprint
-- (half-width 2) with real margin, not just avoid touching exactly:
--   - Default Multiplier position (X = 24): footprint edge at X = 26.
--   - Worst case, pushed to MULTIPLIER_PAD_MAX_ROW_OFFSET_STUDS (X = 32):
--     footprint edge at X = 34.
-- At 36, the boundary (36 - 10 = 26) landed EXACTLY on the default case's
-- edge (26) - a real 0-stud gap, and 4 studs INSIDE the pushed case's edge
-- (34 > 26) - an actual overlap, not just a tight boundary. At 52, the
-- boundary is 52 - 10 = 42: a 16-stud gap past the default case (26) and an
-- 8-stud gap past the worst pushed case (34) - both genuinely clear.
PlotLayout.GACHA_PAD_ROW_OFFSET_STUDS = 52
PlotLayout.GACHA_PAD_SIZE_X_STUDS = 4

-- The local-X offset (from PlotOrigin) where Floor's row-covering edge ends:
-- the Gacha Pad's own edge (the last row element), plus margin.
function PlotLayout.GetFloorRowEndLocalX(): number
	return PlotLayout.GACHA_PAD_ROW_OFFSET_STUDS + PlotLayout.GACHA_PAD_SIZE_X_STUDS / 2 + PlotLayout.FLOOR_ROW_MARGIN_STUDS
end

-- Pedestal Showcase: a dedicated alcove off the main row instead of inline
-- with it, so it reads as a display case players walk up to on purpose
-- rather than something they walk past/through on the way to the other pads.
-- A straight line of 4 pedestals at a fixed local X, stepping into -Z (away
-- from the row's own Z = 0 centerline) - Pedestal 1 closest to the row,
-- Pedestal 4 deepest into the alcove.
PlotLayout.PEDESTAL_SHOWCASE_X_OFFSET_STUDS = 30
PlotLayout.PEDESTAL_SHOWCASE_Z_OFFSET_STUDS = -18
PlotLayout.PEDESTAL_COUNT = 4
PlotLayout.PEDESTAL_SPACING_STUDS = 8
PlotLayout.PEDESTAL_SIZE_X_STUDS = 4
PlotLayout.PEDESTAL_SIZE_Z_STUDS = 4

-- Floor used to be a fixed 50x50 square (every row element sat at local
-- Z = 0, so a flat +/-25 margin covered the whole row's width). Now that the
-- showcase reaches into -Z, Floor's Z extent is computed the same
-- margin-based way its X extent already is: a positive-side margin for the
-- row/walkway's own width, and a negative-side reach that covers however far
-- the showcase's last pedestal goes.
PlotLayout.FLOOR_ROW_POSITIVE_Z_MARGIN_STUDS = 25

-- The local-Z offset (from PlotOrigin) where Floor's row-covering edge ends
-- on the showcase side: the last pedestal's own far edge, plus margin.
function PlotLayout.GetFloorRowStartLocalZ(): number
	local lastPedestalLocalZ = PlotLayout.PEDESTAL_SHOWCASE_Z_OFFSET_STUDS
		- (PlotLayout.PEDESTAL_COUNT - 1) * PlotLayout.PEDESTAL_SPACING_STUDS
	return lastPedestalLocalZ - PlotLayout.PEDESTAL_SIZE_Z_STUDS / 2 - PlotLayout.FLOOR_ROW_MARGIN_STUDS
end

-- The local-Z offset (from PlotOrigin) where Floor's row-covering edge ends
-- on the main row's own side (unchanged generous walkway/connector margin).
function PlotLayout.GetFloorRowEndLocalZ(): number
	return PlotLayout.FLOOR_ROW_POSITIVE_Z_MARGIN_STUDS
end

return PlotLayout
