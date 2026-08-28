-- The one piece of plot-row layout math that two otherwise-independent
-- services both need to agree on: where Floor's row-covering edge actually
-- ends up. TycoonService.resizeFloorToFitRow uses it to size Floor itself;
-- FusionMachineService uses it as the starting point for the connector
-- walkway bridging Floor's edge to the machine's own Base. Kept here instead
-- of duplicated as a hardcoded number in FusionMachineService, since that's
-- exactly the kind of silent-assumption mismatch that's caused most of this
-- project's layout bugs so far (pedestal row vs. plot spacing, the machine
-- vs. the row, the Multiplier Pad vs. ClaimButton).
local PlotLayout = {}

PlotLayout.PEDESTAL_ROW_START_OFFSET_STUDS = 36
PlotLayout.PEDESTAL_COUNT = 4
PlotLayout.PEDESTAL_SPACING_STUDS = 8
PlotLayout.PEDESTAL_SIZE_X_STUDS = 4
PlotLayout.FLOOR_ROW_MARGIN_STUDS = 10

-- Gacha Pad sits one more row-slot past the last Pedestal - it's now the
-- true end of the row, not Pedestal 4.
PlotLayout.GACHA_PAD_ROW_OFFSET_STUDS = PlotLayout.PEDESTAL_ROW_START_OFFSET_STUDS
	+ (PlotLayout.PEDESTAL_COUNT - 1) * PlotLayout.PEDESTAL_SPACING_STUDS
	+ 6
PlotLayout.GACHA_PAD_SIZE_X_STUDS = 4

-- The local-X offset (from PlotOrigin) where Floor's row-covering edge ends:
-- the Gacha Pad's own edge (the last row element), plus margin.
function PlotLayout.GetFloorRowEndLocalX(): number
	return PlotLayout.GACHA_PAD_ROW_OFFSET_STUDS + PlotLayout.GACHA_PAD_SIZE_X_STUDS / 2 + PlotLayout.FLOOR_ROW_MARGIN_STUDS
end

return PlotLayout
