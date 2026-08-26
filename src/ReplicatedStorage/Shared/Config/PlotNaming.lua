-- Shared plot-naming convention. Both TycoonService (which creates plots)
-- and any client code that needs to find the local player's own plot (e.g.
-- ItemController, to locate its Pedestals) rely on this - keeping it in one
-- place means the convention can't drift between server and client.
local PlotNaming = {}

PlotNaming.PlotsFolderName = "PlayerTycoons"

function PlotNaming.GetPlotName(userId: number): string
	return ("Tycoon_%d"):format(userId)
end

return PlotNaming
