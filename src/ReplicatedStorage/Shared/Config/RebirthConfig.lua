--!strict
--[[
	RebirthConfig
	-------------
	Rebirth: once a run has earned enough (RunEarnings, counted from the
	passive payout only), the player can reset cash, generators, the
	Multiplier Pad and the gacha price for a permanent income and luck boost.
	Items, pedestals and goals are kept.

	Mirrored in tools/econ_sim.py (REBIRTH_*); change both together.
]]
local RebirthConfig = {}

RebirthConfig.BaseRequirement = 30_000_000 -- run earnings for the 1st rebirth
RebirthConfig.RequirementGrowth = 3.2 -- each rebirth needs 3.2x the last
RebirthConfig.IncomePerRebirth = 0.5 -- income x(1 + 0.5 * rebirths)
RebirthConfig.LuckPerRebirth = 0.05 -- luck x(1 + 0.05 * rebirths)
RebirthConfig.Unlocks = {} :: { [number]: string } -- rebirth number -> unlock text (filled by Depth 1)

-- Run earnings needed for the next rebirth after `rebirths` so far.
function RebirthConfig.GetRequirement(rebirths: number): number
	return math.floor(RebirthConfig.BaseRequirement * RebirthConfig.RequirementGrowth ^ math.max(0, rebirths))
end

function RebirthConfig.GetIncomeMultiplier(rebirths: number): number
	return 1 + RebirthConfig.IncomePerRebirth * math.max(0, rebirths)
end

-- Multiplies the Legendary/Mythic gacha rates (FusionConfig.GetGachaRates).
function RebirthConfig.GetLuck(rebirths: number): number
	return 1 + RebirthConfig.LuckPerRebirth * math.max(0, rebirths)
end

return RebirthConfig
