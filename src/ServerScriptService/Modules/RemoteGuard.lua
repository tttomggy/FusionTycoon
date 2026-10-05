--!strict
--[[
	RemoteGuard
	-----------
	Shared argument checks and a per-player rate limit for remote handlers
	(not a service; required directly, like AnalyticsKit).

	  RemoteGuard.Int(value, min, max)   a finite whole number in range, or
	                                     nil (rejects NaN, ±inf, 1.5, strings)
	  RemoteGuard.Allow(player, key, perSecond, burst?)
	                                     token bucket: false while `player`
	                                     is firing `key` faster than
	                                     perSecond (after a burst); a
	                                     rejected call does no work at all

	Buckets are dropped on PlayerRemoving.
]]
local Players = game:GetService("Players")

local RemoteGuard = {}

type Bucket = { Tokens: number, At: number }

local buckets: { [Player]: { [string]: Bucket } } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	buckets[player] = nil
end)

function RemoteGuard.Int(value: unknown, min: number, max: number): number?
	if typeof(value) ~= "number" then
		return nil
	end
	local n = value :: number
	if n ~= n or n == math.huge or n == -math.huge or n % 1 ~= 0 or n < min or n > max then
		return nil
	end
	return n
end

function RemoteGuard.Allow(player: Player, key: string, perSecond: number, burst: number?): boolean
	local capacity = burst or math.max(1, perSecond)
	local now = os.clock()
	local byKey = buckets[player]
	if not byKey then
		byKey = {}
		buckets[player] = byKey
	end
	local bucket = byKey[key]
	if not bucket then
		bucket = { Tokens = capacity, At = now }
		byKey[key] = bucket
	end
	bucket.Tokens = math.min(capacity, bucket.Tokens + (now - bucket.At) * perSecond)
	bucket.At = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

-- /selftest: forget a player's buckets so a fuzz run starts fresh.
function RemoteGuard.Reset(player: Player)
	buckets[player] = nil
end

return RemoteGuard
