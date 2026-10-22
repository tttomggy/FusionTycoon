--!strict
--[[
	GiftConfig
	----------
	Playtime gifts: six gifts that open after 5 / 10 / 15 / 25 / 40 / 60
	minutes of play in THIS VISIT. Every visit starts fresh: on join the play
	time is 0 and nothing is claimed; leaving loses the unclaimed ones.
	RewardService keeps the visit's State in memory (created on join, dropped
	on leave; nothing is saved, an old save's Gifts table is ignored), ticks
	the play time and grants them (ClaimGift { Index }); the HUD GIFTS button
	and the Gifts panel read the same functions.

	State = { PlaySeconds, Claimed = { index, ... } }.
]]
local RewardConfig = require(script.Parent.RewardConfig)

local GiftConfig = {}

export type Gift = { Minutes: number, Reward: RewardConfig.Reward }
export type State = { PlaySeconds: number, Claimed: { number } }

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

-- A new visit: no play time, nothing claimed.
function GiftConfig.Fresh(): State
	return { PlaySeconds = 0, Claimed = {} }
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
