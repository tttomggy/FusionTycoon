--!strict
--[[
	FriendConfig
	------------
	The friend boost: every Roblox friend in your server adds
	PercentPerFriend % to ALL your income, up to MaxFriends of them (+60 %).
	It is a boost, like the Boost / Overclock: it is not in the steady income
	(the gacha price) and not in offline earnings or cash packs.

	FriendService counts the friends per server (server-authoritative) and
	PlayerDataService ships the count in the SyncTycoon snapshot; the income
	formula (TycoonConfig.IncomeInputs.FriendMultiplier) and the HUD chip
	(UI/EffectsTray "Friends") read the multiplier through here.
]]
local FriendConfig = {}

FriendConfig.PercentPerFriend = 15
FriendConfig.MaxFriends = 4 -- friends past this add nothing (+60% at most)
FriendConfig.RecheckSeconds = 60 -- a friendship result is trusted this long

-- The friends that count (0..MaxFriends); junk or negative counts are 0.
function FriendConfig.ClampCount(count: number): number
	if count ~= count or count < 0 then
		return 0
	end
	return math.min(math.floor(count), FriendConfig.MaxFriends)
end

-- 1 + 0.15 x min(count, 4).
function FriendConfig.GetMultiplier(count: number): number
	return 1 + FriendConfig.PercentPerFriend / 100 * FriendConfig.ClampCount(count)
end

-- The chip's number: 0, 15, 30, 45 or 60.
function FriendConfig.GetPercent(count: number): number
	return FriendConfig.PercentPerFriend * FriendConfig.ClampCount(count)
end

-- The tooltip's rule line (no number but the config's).
function FriendConfig.RuleText(): string
	return ("Friends in this server: +%d%% income each (max +%d%%)"):format(
		FriendConfig.PercentPerFriend,
		FriendConfig.PercentPerFriend * FriendConfig.MaxFriends
	)
end

return FriendConfig
