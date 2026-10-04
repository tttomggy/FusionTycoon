--!strict
--[[
	DailyConfig
	-----------
	The 7-day daily reward and its streak rules (RewardService grants it, the
	Daily card shows it; both go through GetStatus / Apply).

	PlayerData.Daily = { Day, LastClaimUtcDay, Skips, Streak }:
	  Day              the cycle day of the LAST claim (0 = never claimed)
	  LastClaimUtcDay  RewardConfig.GetUtcDay of that claim (-1 = never)
	  Skips            free skips left (one; restored when the streak resets)
	  Streak           consecutive claims (keeps counting past Day 7)

	Rules: one claim per UTC day. Missing exactly one day spends the free
	skip and the streak goes on; missing more (or one with no skip left)
	restarts at Day 1 with the skip back. After Day 7 comes Day 1.
]]
local RewardConfig = require(script.Parent.RewardConfig)

local DailyConfig = {}

export type State = { Day: number, LastClaimUtcDay: number, Skips: number, Streak: number }

export type Status = {
	CanClaim: boolean,
	Day: number, -- the day you claim next (today's, once claimed)
	Streak: number, -- the streak after that claim (today's, once claimed)
	Skips: number, -- skips left after that claim
	UsesSkip: boolean, -- this claim spends the skip
	Resets: boolean, -- this claim restarts at Day 1 (a streak was lost)
}

DailyConfig.Cycle = 7
DailyConfig.MaxSkips = 1

-- Seconds are of BASE income (RewardConfig).
DailyConfig.Days = {
	{ Kind = "Cash", Seconds = 10 * 60, Floor = 2_500 },
	{ Kind = "IncomeBoost", Seconds = 15 * 60 },
	{ Kind = "Pulls", Count = 3 },
	{ Kind = "LuckBoost", Seconds = 15 * 60 },
	{ Kind = "SafeFusion", Count = 1 },
	{ Kind = "IncomeBoost", Seconds = 60 * 60 },
	{
		Kind = "Item",
		Odds = {
			{ Tier = "Epic", Weight = 70 },
			{ Tier = "Legendary", Weight = 25 },
			{ Tier = "Mythic", Weight = 5 },
		},
	},
} :: { RewardConfig.Reward }

function DailyConfig.Default(): State
	return { Day = 0, LastClaimUtcDay = -1, Skips = DailyConfig.MaxSkips, Streak = 0 }
end

-- A clean copy of a saved Daily table (old saves: a fresh streak).
function DailyConfig.Sanitize(raw: any): State
	local state = DailyConfig.Default()
	if typeof(raw) ~= "table" then
		return state
	end
	local function int(value: any, low: number, high: number, fallback: number): number
		return if typeof(value) == "number" and value == value then math.clamp(math.floor(value), low, high) else fallback
	end
	state.Day = int(raw.Day, 0, DailyConfig.Cycle, 0)
	state.LastClaimUtcDay = int(raw.LastClaimUtcDay, -1, math.huge, -1)
	state.Skips = int(raw.Skips, 0, DailyConfig.MaxSkips, DailyConfig.MaxSkips)
	state.Streak = int(raw.Streak, 0, math.huge, 0)
	return state
end

function DailyConfig.GetStatus(state: State, today: number): Status
	local last = state.LastClaimUtcDay
	if last >= 0 and today <= last then
		return { CanClaim = false, Day = math.max(1, state.Day), Streak = state.Streak, Skips = state.Skips, UsesSkip = false, Resets = false }
	end
	local gap = if last < 0 then math.huge else today - last
	local nextDay = state.Day % DailyConfig.Cycle + 1
	if last >= 0 and gap == 1 then
		return { CanClaim = true, Day = nextDay, Streak = state.Streak + 1, Skips = state.Skips, UsesSkip = false, Resets = false }
	elseif last >= 0 and gap == 2 and state.Skips > 0 then
		return { CanClaim = true, Day = nextDay, Streak = state.Streak + 1, Skips = state.Skips - 1, UsesSkip = true, Resets = false }
	end
	return {
		CanClaim = true,
		Day = 1,
		Streak = 1,
		Skips = DailyConfig.MaxSkips,
		UsesSkip = false,
		Resets = last >= 0 and state.Streak > 0,
	}
end

-- Records today's claim (call only when GetStatus says CanClaim). Returns
-- the day claimed.
function DailyConfig.Apply(state: State, today: number): number
	local status = DailyConfig.GetStatus(state, today)
	state.Day = status.Day
	state.Streak = status.Streak
	state.Skips = status.Skips
	state.LastClaimUtcDay = today
	return status.Day
end

function DailyConfig.GetReward(day: number): RewardConfig.Reward
	return DailyConfig.Days[math.clamp(day, 1, DailyConfig.Cycle)]
end

-- The card's footer: the skip rule and the Day 7 odds.
function DailyConfig.GetFooter(): string
	local odds = DailyConfig.Days[DailyConfig.Cycle].Odds
	return ("Miss 1 day: your free skip keeps the streak. Miss more: back to Day 1. Day 7: %s"):format(
		if odds then RewardConfig.FormatOdds(odds) else ""
	)
end

return DailyConfig
