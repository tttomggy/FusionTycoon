--!strict
--[[
	FriendService
	-------------
	The friend boost (FriendConfig): +15% income per Roblox friend in this
	server, up to 4. Counted server-side only:

	  * a pair is asked with Player:IsFriendsWithAsync (pcall'd: it yields and can
	    fail; a failure counts as "not friends", cached like any answer, so a
	    broken call is never retried in a loop);
	  * answers are cached per pair for FriendConfig.RecheckSeconds;
	  * PlayerAdded rechecks the pairs that involve the new player, and
	    PlayerRemoving drops the leaver from everyone's count. Both run on
	    their own thread (never in Init);
	  * friendships made mid-session: one loop (:Start) rechecks the pairs whose
	    answer is older than RecheckSeconds, ONE pair per RECHECK_STEP_SECONDS
	    (never a burst), and syncs only the players whose count changed. A count
	    that grows shows "You and <Name> are friends" (they were already here).

	The count lives in PlayerDataService (SetFriendCount), ships as
	SyncTycoon.Friends and feeds IncomeInputs.FriendMultiplier. A friend
	joining syncs and notifies both players (FriendJoined remote).

	/selftest swaps the Roblox call for a stub (SetCheck), the clock (SetClock)
	and feeds fake peers (Recount, RecheckStep); SetCheck(nil) / SetClock(nil)
	put the real ones back.

	Follows ServiceTemplate:
	  :Init()   connects PlayerAdded / PlayerRemoving.
	  :Start()  resolves PlayerDataService, counts everyone already here,
	            spawns the recheck loop.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FriendConfig = require(ReplicatedStorage.Shared.Config.FriendConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))

-- (a, b) -> are they friends; may yield or error.
export type FriendCheck = (Player, Player) -> boolean

type CacheEntry = { Friends: boolean, At: number }

type State = {
	connections: { RBXScriptConnection },
	check: FriendCheck,
	-- Seconds; os.clock, or /selftest's fake one (SetClock).
	clock: () -> number,
	-- "lowId:highId" -> the last answer for that pair.
	cache: { [string]: CacheEntry },
}

--[[ Private state -------------------------------------------------------- ]]

local LOAD_WAIT_SECONDS = 30 -- a joiner's banners wait this long for their data
local BANNER_DELAY_SECONDS = 3 -- ...then this long for their client to settle
local RECHECK_STEP_SECONDS = 0.5 -- the recheck loop asks Roblox about one pair per step

local function robloxCheck(a: Player, b: Player): boolean
	return a:IsFriendsWithAsync(b.UserId)
end

local state: State = {
	connections = {},
	check = robloxCheck,
	clock = os.clock,
	cache = {},
}

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule

local FriendService = {}

FriendService.Name = "FriendService"

--[[ Private helpers ------------------------------------------------------ ]]

local function pairKey(a: Player, b: Player): string
	local low, high = a.UserId, b.UserId
	if low > high then
		low, high = high, low
	end
	return ("%d:%d"):format(low, high)
end

-- Are these two friends? Cached for RecheckSeconds; an error or a non-true
-- answer is "not friends".
local function areFriends(a: Player, b: Player): boolean
	local key = pairKey(a, b)
	local now = state.clock()
	local entry = state.cache[key]
	if entry and now - entry.At < FriendConfig.RecheckSeconds then
		return entry.Friends
	end
	local ok, answer = pcall(state.check, a, b)
	local friends = ok and answer == true
	state.cache[key] = { Friends = friends, At = state.clock() }
	return friends
end

-- Friends of `player` among `peers` by the cached answers only (never asks
-- Roblox): the recheck loop's count, so one step is one call.
local function cachedCount(player: Player, peers: { Player }): number
	local count = 0
	for _, peer in peers do
		local entry = if peer.UserId ~= player.UserId then state.cache[pairKey(player, peer)] else nil
		if entry and entry.Friends then
			count += 1
		end
	end
	return count
end

-- Friends of `player` among `peers` (the player itself is skipped).
local function countAmong(player: Player, peers: { Player }): number
	local count = 0
	for _, peer in peers do
		if peer.UserId ~= player.UserId and areFriends(player, peer) then
			count += 1
		end
	end
	return count
end

local function liveUnless(excluded: Player?): { Player }
	local peers: { Player } = {}
	for _, peer in Players:GetPlayers() do
		if peer ~= excluded and peer.Parent == Players then
			table.insert(peers, peer)
		end
	end
	return peers
end

local function sync(player: Player)
	if player.Parent == Players then
		PlayerDataService.SyncTycoon(player)
	end
end

local function dropFromCache(player: Player)
	local prefix = ("%d:"):format(player.UserId)
	local suffix = (":%d"):format(player.UserId)
	for key in state.cache do
		if string.sub(key, 1, #prefix) == prefix or string.sub(key, -#suffix) == suffix then
			state.cache[key] = nil
		end
	end
end

-- `friended`: they became friends while both were here (not "joined").
local function notifyJoined(player: Player, other: Player, friended: boolean?)
	if player.Parent ~= Players then
		return
	end
	RemoteEvents.FriendJoined:FireClient(player, {
		Name = other.DisplayName,
		Percent = FriendConfig.PercentPerFriend,
		Friended = friended == true,
	})
end

-- The joiner's own client is still loading when their friends are counted:
-- hold their banners until their data (and so the first snapshot) is in.
local function whenLoaded(player: Player, callback: () -> ())
	task.spawn(function()
		local deadline = os.clock() + LOAD_WAIT_SECONDS
		while player.Parent == Players and not PlayerDataService.IsDataLoaded(player) and os.clock() < deadline do
			task.wait(0.5)
		end
		if player.Parent ~= Players or not PlayerDataService.IsDataLoaded(player) then
			return
		end
		task.wait(BANNER_DELAY_SECONDS)
		callback()
	end)
end

-- A new player: their friends here, then each of those friends' own counts.
-- A banner only goes where the boost really grew (a full +60% hears nothing).
local function onJoined(player: Player)
	local friends: { Player } = {}
	for _, peer in liveUnless(player) do
		if areFriends(player, peer) then
			table.insert(friends, peer)
		end
	end
	if player.Parent ~= Players then
		return
	end
	local before = PlayerDataService.GetFriendCount(player)
	PlayerDataService.SetFriendCount(player, #friends)
	local after = PlayerDataService.GetFriendCount(player)
	whenLoaded(player, function()
		for index, friend in friends do
			if before + index <= after then
				notifyJoined(player, friend)
			end
		end
	end)
	for _, friend in friends do
		if friend.Parent == Players then
			local friendBefore = PlayerDataService.GetFriendCount(friend)
			-- The friend's pairs with everyone else are cached (or re-asked
			-- once their RecheckSeconds are up); the new pair is fresh.
			PlayerDataService.SetFriendCount(friend, countAmong(friend, liveUnless(nil)))
			if PlayerDataService.GetFriendCount(friend) > friendBefore then
				notifyJoined(friend, player)
			end
			sync(friend)
		end
	end
	sync(player)
end

-- Someone left: whoever counted them as a friend loses one (no banner).
local function onLeaving(player: Player)
	for _, peer in liveUnless(player) do
		local entry = state.cache[pairKey(player, peer)]
		if entry and entry.Friends then
			PlayerDataService.SetFriendCount(peer, countAmong(peer, liveUnless(player)))
			sync(peer)
		end
	end
	dropFromCache(player)
end

--[[ Public API ----------------------------------------------------------- ]]

-- One step of the recheck loop: asks Roblox again about the one pair among
-- `peers` (default: everyone here) whose answer is the oldest and past
-- RecheckSeconds (or missing). If the answer changed, both players are
-- recounted from the cache and synced when their count moved; a count that
-- grew shows "You and <Name> are friends". Returns true if a pair was asked.
function FriendService.RecheckStep(peers: { Player }?): boolean
	local here = peers or liveUnless(nil)
	local now = state.clock()
	local dueA: Player? = nil
	local dueB: Player? = nil
	local oldest = math.huge
	for i = 1, #here do
		for j = i + 1, #here do
			local entry = state.cache[pairKey(here[i], here[j])]
			local at = if entry then entry.At else -math.huge
			if now - at >= FriendConfig.RecheckSeconds and at < oldest then
				oldest = at
				dueA, dueB = here[i], here[j]
			end
		end
	end
	if not dueA or not dueB then
		return false
	end
	local key = pairKey(dueA, dueB)
	local before = state.cache[key]
	local ok, answer = pcall(state.check, dueA, dueB)
	local friends = ok and answer == true
	state.cache[key] = { Friends = friends, At = state.clock() }
	if before and before.Friends == friends then
		return true
	end
	for _, pair in { { dueA, dueB }, { dueB, dueA } } do
		local player, other = pair[1], pair[2]
		local was = PlayerDataService.GetFriendCount(player)
		if PlayerDataService.SetFriendCount(player, cachedCount(player, here)) then
			if PlayerDataService.GetFriendCount(player) > was then
				notifyJoined(player, other, true)
			end
			sync(player)
		end
	end
	return true
end

-- Counts `player`'s friends among `peers` (default: everyone here), stores
-- the count and syncs when it changed. Returns the stored (capped) count.
-- /selftest passes fake peers; the server itself uses it for the catch-up.
function FriendService.Recount(player: Player, peers: { Player }?): number
	local count = countAmong(player, peers or liveUnless(nil))
	if PlayerDataService.SetFriendCount(player, count) then
		sync(player)
	end
	return PlayerDataService.GetFriendCount(player)
end

-- /selftest: swap the Roblox friendship call for a stub (it may error), or
-- nil to put the real one back. The cache is cleared either way.
function FriendService.SetCheck(check: FriendCheck?)
	state.check = check or robloxCheck
	table.clear(state.cache)
end

-- /selftest: swap the clock the cache ages by (seconds), or nil for os.clock.
function FriendService.SetClock(clock: (() -> number)?)
	state.clock = clock or os.clock
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function FriendService:Init()
	table.insert(
		state.connections,
		Players.PlayerAdded:Connect(function(player: Player)
			task.spawn(onJoined, player)
		end)
	)
	table.insert(
		state.connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			task.spawn(onLeaving, player)
		end)
	)
end

function FriendService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	-- Anyone who joined before this service started.
	for _, player in Players:GetPlayers() do
		task.spawn(onJoined, player)
	end
	-- Friends made while both are here: one pair per step, forever.
	task.spawn(function()
		while true do
			task.wait(RECHECK_STEP_SECONDS)
			local ok, err = pcall(FriendService.RecheckStep)
			if not ok then
				warn("[FriendService] recheck failed: " .. tostring(err))
			end
		end
	end)
end

return FriendService
