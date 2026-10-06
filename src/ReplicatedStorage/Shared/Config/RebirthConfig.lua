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
local CombatConfig = require(script.Parent.CombatConfig)

local RebirthConfig = {}

RebirthConfig.BaseCost = 15_000_000 -- cash price of the 1st rebirth
RebirthConfig.CostGrowth = 3.2 -- each rebirth costs 3.2x the last ($15M, $48M, $154M, $492M, ...)
RebirthConfig.IncomePerRebirth = 0.5 -- income x(1 + 0.5 * rebirths)
RebirthConfig.LuckPerRebirth = 0.05 -- luck x(1 + 0.05 * rebirths)
RebirthConfig.SecretFusionRebirths = 1 -- Mythic -> Secret fusion unlocks at this many rebirths
RebirthConfig.SecondFloorRebirths = 2 -- the 2nd floor's 4 pedestals (PlotLayout.Floor2)
RebirthConfig.Unlocks = { -- rebirth number -> what it unlocks (shown in the Rebirth panel)
	[1] = "stealing, Mythic → Secret fusion",
	[2] = "the 2nd floor (+4 pedestals)",
} :: { [number]: string }

-- Everything rebirth `n` unlocks: Unlocks[n] plus its weapons
-- (CombatConfig), "the 2nd floor (+4 pedestals) and the 🔫 Laser Gun".
function RebirthConfig.GetUnlockText(n: number): string?
	local parts = {}
	if RebirthConfig.Unlocks[n] then
		table.insert(parts, RebirthConfig.Unlocks[n])
	end
	local weapons = CombatConfig.GetUnlockText(n)
	if weapons then
		table.insert(parts, "the " .. weapons)
	end
	return if #parts > 0 then table.concat(parts, " and ") else nil
end

-- The Rebirth panel's line: "Rebirth 2: unlocks the 2nd floor (+4
-- pedestals) and the 🔫 Laser Gun."
function RebirthConfig.GetUnlockLine(n: number): string?
	local text = RebirthConfig.GetUnlockText(n)
	return if text then ("Rebirth %d: unlocks %s."):format(n, text) else nil
end

function RebirthConfig.HasSecondFloor(rebirths: number): boolean
	return rebirths >= RebirthConfig.SecondFloorRebirths
end

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
