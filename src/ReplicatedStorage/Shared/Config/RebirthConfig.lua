--!strict
--[[
	RebirthConfig
	-------------
	Rebirth costs cash: once you hold GetCost(rebirths), you can reset cash
	(which pays the price), generators, the Multiplier Pad and the gacha
	price for a permanent income and luck boost. Items, pedestals, the
	Index and goals are kept. (A cash price reads for kids; the old hidden
	"run earnings" counter didn't.)

	Mirrored in tools/econ_sim.py (REBIRTH_*); change both together.
]]
local RebirthConfig = {}

RebirthConfig.BaseCost = 15_000_000 -- cash price of the 1st rebirth
RebirthConfig.CostGrowth = 3.2 -- each rebirth costs 3.2x the last ($15M, $48M, $154M, $492M, ...)
RebirthConfig.IncomePerRebirth = 0.5 -- income x(1 + 0.5 * rebirths)
RebirthConfig.LuckPerRebirth = 0.05 -- luck x(1 + 0.05 * rebirths)
RebirthConfig.SecretFusionRebirths = 1 -- Mythic -> Secret fusion unlocks at this many rebirths
RebirthConfig.Unlocks = { -- rebirth number -> what it unlocks (shown in the Rebirth panel)
	[1] = "Stealing + Mythic → Secret fusion",
} :: { [number]: string }

-- Cash price of the next rebirth after `rebirths` so far.
function RebirthConfig.GetCost(rebirths: number): number
	return math.floor(RebirthConfig.BaseCost * RebirthConfig.CostGrowth ^ math.max(0, rebirths))
end

function RebirthConfig.GetIncomeMultiplier(rebirths: number): number
	return 1 + RebirthConfig.IncomePerRebirth * math.max(0, rebirths)
end

-- Multiplies the Legendary/Mythic/Secret gacha rates (FusionConfig.GetGachaRates)
-- and every mutation chance (MutationConfig.Roll).
function RebirthConfig.GetLuck(rebirths: number): number
	return 1 + RebirthConfig.LuckPerRebirth * math.max(0, rebirths)
end

return RebirthConfig
