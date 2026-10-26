--!strict
--[[
	NotifyConfig
	------------
	Two halves.

	Opt-in (NotifyOptInController, client): when it asks for Roblox
	experience notifications (once per session, Roblox's own modal). Never on
	join: not before MinSessionSeconds of this session's play and a finished
	tutorial, then at the first high moment (a successful fusion's card
	closing, a pull of MinPullTier or better closing, the daily reveal
	closing), or at FallbackSeconds the next time no overlay is open.

	Sending (NotifyService, server): the three notification types, their
	Creator Hub string ids, the queue numbers, and the PURE rules the service
	and /selftest share (priority pick, once-a-day, due times, launch data,
	the request body). Roblox allows one notification per user per day per
	experience; a type whose StringId is "" never sends.
]]
local DailyConfig = require(script.Parent.DailyConfig)
local OfflineConfig = require(script.Parent.OfflineConfig)

local NotifyConfig = {}

export type NotifyType = "AdminAbuse" | "DailyStreak" | "LabFull"

export type Entry = {
	Type: NotifyType,
	DueAt: number,
	Params: { [string]: number | string },
}

--[[ Opt-in ---------------------------------------------------------------- ]]

NotifyConfig.MinSessionSeconds = 300
NotifyConfig.FallbackSeconds = 480
NotifyConfig.MinPullTier = "Epic"

--[[ Sending ---------------------------------------------------------------- ]]

-- Highest priority first: the one a user gets that day.
NotifyConfig.Priority = { "AdminAbuse", "DailyStreak", "LabFull" } :: { NotifyType }

-- Creator Hub -> the experience -> Engagement -> Notifications: the three
-- strings (<= 99 chars). The ids are the strings' UUIDs (not asset numbers),
-- sent as-is in the request's message_id. {experienceName} is not sent: the
-- notification's title is the game's name. "" = that type never sends.
NotifyConfig.StringIds = {
	AdminAbuse = "a951a5cd-b76b-8642-9854-b00b979e3224", -- Admin Abuse is LIVE: x{luck} luck for {minutes} min!
	DailyStreak = "723f39b7-ec59-b247-8974-f952865a812d", -- Your Day {day} reward is ready. Keep your {streak}-day streak!
	LabFull = "f8502273-b1a4-9442-ba36-b11fa7e8509c", -- Your lab is full: {cash} is waiting for you.
} :: { [string]: string }

-- The parameters each string takes, exactly its placeholders above: an entry's
-- Params keys are these and no others (/selftest checks).
NotifyConfig.Placeholders = {
	AdminAbuse = { "luck", "minutes" },
	DailyStreak = { "day", "streak" },
	LabFull = { "cash" },
} :: { [string]: { string } }

-- LaunchData the notification hands the joining client (whitelisted on join).
NotifyConfig.LaunchData = {
	AdminAbuse = "admin",
	DailyStreak = "daily",
	LabFull = "lab",
} :: { [string]: string }

NotifyConfig.AnalyticsCategory = {
	AdminAbuse = "AdminAbuse",
	DailyStreak = "DailyStreak",
	LabFull = "LabFull",
} :: { [string]: string }

NotifyConfig.SecretName = "OpenCloudNotify"
NotifyConfig.Endpoint = "https://apis.roblox.com/cloud/v2/users/%d/notifications"

-- DailyStreak goes out this long after 00:00 UTC of the day after the claim.
NotifyConfig.DailyStreakDelaySeconds = 3 * 3600
-- A lab that is already claimable when the player leaves waits this long.
NotifyConfig.DailyStreakMinWaitSeconds = 3 * 3600

NotifyConfig.AdminAbuseMaxRecipients = 2000

-- The worker, per server.
NotifyConfig.WorkerSeconds = 30
NotifyConfig.BatchSize = 50
NotifyConfig.BackoffSeconds = 60 -- after a 429
NotifyConfig.ClaimSeconds = 120 -- an entry claimed by a server that dies is retried after this
NotifyConfig.RetryAfterSeconds = 300 -- a failed send (5xx / no answer) is retried after this
NotifyConfig.MaxAttempts = 3
NotifyConfig.MaxLateSeconds = 86400 -- an entry due longer ago than this is dropped, not sent
NotifyConfig.AdminAbuseDedupeSeconds = 600 -- an event + luck started together queue one
NotifyConfig.AdminAbuseQueuePerSecond = 10 -- MemoryStore budget: 1000 + 100 x players requests a minute

-- MemoryStore (max expiry is 45 days).
NotifyConfig.QueueMap = "NotifyQueue"
NotifyConfig.RecentPlayersMap = "RecentPlayers"
NotifyConfig.PresenceMap = "NotifyPresence"
NotifyConfig.SentMap = "NotifySent"
NotifyConfig.RecentPlayersTtlSeconds = 7 * 86400
NotifyConfig.QueueTtlSeconds = 8 * 86400
NotifyConfig.PresenceTtlSeconds = 90 -- refreshed by every server's worker tick
NotifyConfig.SentTtlSeconds = 2 * 86400

-- The player attribute the server sets from the join's LaunchData.
NotifyConfig.LaunchAttribute = "LaunchAction"

--[[ Pure rules ------------------------------------------------------------- ]]

local function utcDay(time: number): number
	return time // 86400
end

function NotifyConfig.GetPriorityIndex(notifyType: string): number
	return table.find(NotifyConfig.Priority, notifyType :: NotifyType) or math.huge
end

-- The entry to keep for a user: the earlier DueAt wins, then the higher
-- priority. Either argument may be nil.
function NotifyConfig.PickEntry(a: Entry?, b: Entry?): Entry?
	if not a or not b then
		return a or b
	end
	if a.DueAt ~= b.DueAt then
		return if a.DueAt < b.DueAt then a else b
	end
	return if NotifyConfig.GetPriorityIndex(a.Type) <= NotifyConfig.GetPriorityIndex(b.Type) then a else b
end

-- The queued entry a new one replaces (or not) for the same user: the higher
-- priority wins, the newer one on a tie.
function NotifyConfig.Merge(old: Entry?, new: Entry): Entry
	if old and NotifyConfig.GetPriorityIndex(old.Type) < NotifyConfig.GetPriorityIndex(new.Type) then
		return old
	end
	return new
end

-- A clean Entry from a MemoryStore value, or nil if it isn't one.
function NotifyConfig.SanitizeEntry(raw: unknown): Entry?
	if typeof(raw) ~= "table" then
		return nil
	end
	local value = raw :: { [string]: any }
	if typeof(value.Type) ~= "string" or not table.find(NotifyConfig.Priority, value.Type :: NotifyType) then
		return nil
	end
	if typeof(value.DueAt) ~= "number" or value.DueAt ~= value.DueAt then
		return nil
	end
	local params: { [string]: number | string } = {}
	if typeof(value.Params) == "table" then
		for name, param in value.Params do
			if typeof(name) == "string" and (typeof(param) == "number" or typeof(param) == "string") then
				params[name] = param
			end
		end
	end
	return { Type = value.Type :: NotifyType, DueAt = value.DueAt, Params = params }
end

-- True if a notification went out on `today` (UTC day) or later: one a day.
function NotifyConfig.SentToday(lastSentDay: number?, now: number): boolean
	return lastSentDay ~= nil and lastSentDay >= utcDay(now)
end

-- When LabFull is due for a player who left at `leftAt`, or nil if the lab
-- would earn nothing.
function NotifyConfig.GetLabFullDueAt(leftAt: number, fullCash: number): number?
	if fullCash <= 0 then
		return nil
	end
	return leftAt + OfflineConfig.MaxSeconds
end

-- When DailyStreak is due for a player who left at `leftAt` with `daily`
-- saved, plus the {day, streak} parameters; nil if they never claimed
-- (no streak to keep). The next UTC day after the last claim, 3 h after
-- 00:00 UTC; a reward that is claimable already waits DailyStreakMinWaitSeconds.
function NotifyConfig.GetDailyStreakDue(daily: DailyConfig.State, leftAt: number): (number?, { [string]: number }?)
	if daily.LastClaimUtcDay < 0 or daily.Streak <= 0 then
		return nil, nil
	end
	local dueAt = (daily.LastClaimUtcDay + 1) * 86400 + NotifyConfig.DailyStreakDelaySeconds
	if dueAt <= leftAt then
		dueAt = leftAt + NotifyConfig.DailyStreakMinWaitSeconds
	end
	local status = DailyConfig.GetStatus(daily, utcDay(dueAt))
	return dueAt, { day = status.Day, streak = daily.Streak }
end

-- "daily" / "admin" / "lab" from a join's LaunchData, or nil for anything else.
function NotifyConfig.ParseLaunchData(raw: unknown): string?
	if typeof(raw) ~= "string" or #raw > 16 then
		return nil
	end
	for _, value in NotifyConfig.LaunchData do
		if raw == value then
			return value
		end
	end
	return nil
end

-- The AdminAbuse entry for a start with `luck` x luck for `minutes` minutes.
function NotifyConfig.BuildAdminAbuseEntry(dueAt: number, luck: number, minutes: number): Entry
	return { Type = "AdminAbuse", DueAt = dueAt, Params = { luck = luck, minutes = minutes } }
end

-- The Open Cloud request body for one entry (parameters are string values).
function NotifyConfig.BuildBody(universeId: number, entry: Entry, stringId: string): { [string]: any }
	local parameters = {}
	for name, value in entry.Params do
		parameters[name] = { string_value = tostring(value) }
	end
	return {
		source = { universe = ("universes/%d"):format(universeId) },
		payload = {
			message_id = stringId,
			type = "MOMENT",
			parameters = parameters,
		},
		join_experience = { launch_data = NotifyConfig.LaunchData[entry.Type] },
		analytics_data = { category = NotifyConfig.AnalyticsCategory[entry.Type] },
	}
end

-- What to do with an Open Cloud answer: "Sent", "Backoff" (429), "Drop"
-- (any other 4xx: never retried) or "Retry" (5xx / no answer).
function NotifyConfig.Outcome(statusCode: number?): string
	if statusCode == nil then
		return "Retry"
	elseif statusCode >= 200 and statusCode < 300 then
		return "Sent"
	elseif statusCode == 429 then
		return "Backoff"
	elseif statusCode >= 400 and statusCode < 500 then
		return "Drop"
	end
	return "Retry"
end

return NotifyConfig
