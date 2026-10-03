--!strict
--[[
	OfflineConfig
	-------------
	Offline earnings, the reason to come back tomorrow: while you're away
	your lab earns Rate x your passive income per second, for at most
	MaxSeconds of away time. Away time under MinSeconds pays nothing (a
	quick rejoin isn't "away").

	The server computes it once on load (PlayerDataService) from the income
	you left with; the welcome-back card shows it and COLLECT claims it
	(OfflineService). Mirrored in tools/econ_sim.py (OFFLINE_*).
]]
local OfflineConfig = {}

OfflineConfig.Rate = 0.25 -- share of passive income per second earned while away
OfflineConfig.MaxSeconds = 4 * 3600 -- away time counted at most
OfflineConfig.MinSeconds = 120 -- shorter absences pay nothing
OfflineConfig.AutoClaimSeconds = 30 -- unclaimed earnings pay themselves on the first payout tick after this

-- Cash earned for `awaySeconds` away at `incomePerSecond`; 0 below the minimum.
function OfflineConfig.Compute(incomePerSecond: number, awaySeconds: number): number
	if awaySeconds < OfflineConfig.MinSeconds or incomePerSecond <= 0 then
		return 0
	end
	return math.floor(incomePerSecond * OfflineConfig.Rate * math.min(awaySeconds, OfflineConfig.MaxSeconds))
end

return OfflineConfig
