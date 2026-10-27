-- Shared plot-naming convention. Both TycoonService (which creates plots)
-- and any client code that needs to find the local player's own plot (e.g.
-- ItemController, to locate its Pedestals) rely on this - keeping it in one
-- place means the convention can't drift between server and client.
local PlotNaming = {}

PlotNaming.PlotsFolderName = "PlayerTycoons"

function PlotNaming.GetPlotName(userId: number): string
	return ("Tycoon_%d"):format(userId)
end

-- A rival lab (RivalService) has no user id; it is named by its rival id.
function PlotNaming.GetRivalPlotName(rivalId: number): string
	return ("Rival_%d"):format(rivalId)
end

return PlotNaming
