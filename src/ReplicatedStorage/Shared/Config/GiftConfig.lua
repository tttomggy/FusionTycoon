--!strict
--[[
	GiftConfig
	----------
	Playtime gifts: six gifts that open after 5 / 10 / 15 / 25 / 40 / 60
	minutes of play in one UTC day, summed across sessions (rejoining never
	resets them; a new UTC day does). RewardService ticks the play time and
	grants them (ClaimGift { Index }); the HUD GIFTS button and the Gifts
	panel read the same functions.

	PlayerData.Gifts = { UtcDay, PlaySeconds, Claimed = { index, ... } }.
]]
local RewardConfig = require(script.Parent.RewardConfig)

local GiftConfig = {}

export type Gift = { Minutes: number, Reward: RewardConfig.Reward }
export type State = { UtcDay: number, PlaySeconds: number, Claimed: { number } }

-- Seconds are of BASE income (RewardConfig).
GiftConfig.Gifts = {
	{ Minutes = 5, Reward = { Kind = "Cash", Seconds = 5 * 60, Floor = 1_000 } },
	{ Minutes = 10, Reward = { Kind = "Pulls", Count = 1 } },
	{ Minutes = 15, Reward = { Kind = "IncomeBoost", Seconds = 10 * 60 } },
	{ Minutes = 25, Reward = { Kind = "Cash", Seconds = 15 * 60, Floor = 3_000 } },
	{ Minutes = 40, Reward = { Kind = "LuckBoost", Seconds = 10 * 60 } },
	{
		Minutes = 60,
		Reward = {
			Kind = "Item",
			Odds = {
				{ Tier = "Rare", Weight = 60 },
				{ Tier = "Epic", Weight = 35 },
				{ Tier = "Legendary", Weight = 5 },
			},
		},
	},
} :: { Gift }

function GiftConfig.Default(today: number): State
	return { UtcDay = today, PlaySeconds = 0, Claimed = {} }
end

-- A clean copy of a saved Gifts table; another day's starts fresh.
function GiftConfig.Sanitize(raw: any, today: number): State
	local state = GiftConfig.Default(today)
	if typeof(raw) ~= "table" or raw.UtcDay ~= today then
		return state
	end
	if typeof(raw.PlaySeconds) == "number" and raw.PlaySeconds == raw.PlaySeconds then
		state.PlaySeconds = math.max(0, raw.PlaySeconds)
	end
	if typeof(raw.Claimed) == "table" then
		for _, index in raw.Claimed do
			if typeof(index) == "number" and GiftConfig.Gifts[index] and not table.find(state.Claimed, index) then
				table.insert(state.Claimed, index)
			end
		end
	end
	return state
end

function GiftConfig.IsClaimed(claimed: { number }, index: number): boolean
	return table.find(claimed, index) ~= nil
end

function GiftConfig.IsReady(playSeconds: number, claimed: { number }, index: number): boolean
	local gift = GiftConfig.Gifts[index]
	return gift ~= nil and not GiftConfig.IsClaimed(claimed, index) and playSeconds >= gift.Minutes * 60
end

function GiftConfig.CountReady(playSeconds: number, claimed: { number }): number
	local count = 0
	for index in GiftConfig.Gifts do
		if GiftConfig.IsReady(playSeconds, claimed, index) then
			count += 1
		end
	end
	return count
end

-- Seconds until the next unclaimed gift opens; nil when none is left.
function GiftConfig.GetNextIn(playSeconds: number, claimed: { number }): number?
	for index, gift in GiftConfig.Gifts do
		if not GiftConfig.IsClaimed(claimed, index) and playSeconds < gift.Minutes * 60 then
			return gift.Minutes * 60 - playSeconds
		end
	end
	return nil
end

return GiftConfig
