--!strict
--[[
	NotifyService
	-------------
	Sends Roblox experience notifications (Open Cloud, one user per call):
	AdminAbuse, DailyStreak, LabFull (NotifyConfig: ids, priority, numbers and
	the pure rules). Roblox lets one notification reach a user per day per
	experience, so everything here is built to send at most one.

	Inert until it can work: off in Studio, off if HttpService.HttpEnabled is
	false, off without the `OpenCloudNotify` secret (one warn at start), and
	a type whose NotifyConfig.StringIds entry is "" is never queued or sent.

	Cross-server state is MemoryStore:
	  NotifyQueue    sorted map userId -> { Type, DueAt, Params }, sort key
	                 DueAt. PlayerRemoving queues the earlier-due of LabFull /
	                 DailyStreak; PlayerAdded removes the entry.
	  RecentPlayers  sorted map userId -> last seen (7 days): who Admin Abuse
	                 reaches.
	  NotifyPresence hash map userId -> true, 90 s, refreshed by the worker
	                 while the player is in ANY server.
	  NotifySent     hash map userId -> UTC day of the last send.

	A worker on every server (30 s) reads the due entries (50 at a time),
	claims each with UpdateAsync (ClaimedUntil, so two servers never send the
	same one), runs Process, then deletes / reschedules it. Process is the
	decision with its world injected (clock, presence, sent-day, sender), so
	/selftest runs it with a fake sender: no HTTP in Studio.

	Join: the whitelisted LaunchData ("daily" / "admin" / "lab") is set as the
	player attribute NotifyConfig.LaunchAttribute; DailyController reads it.

	Follows ServiceTemplate:
	  :Init()   launch data on PlayerAdded (no other service, no yields).
	  :Start()  resolves PlayerDataService, finds out if sending is possible,
	            then the queue hooks and the worker on their own threads.
]]
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local DailyConfig = require(ReplicatedStorage.Shared.Config.DailyConfig)
local NotifyConfig = require(ReplicatedStorage.Shared.Config.NotifyConfig)
local OfflineConfig = require(ReplicatedStorage.Shared.Config.OfflineConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))

type Entry = NotifyConfig.Entry

-- Everything Process needs from the outside world.
export type Deps = {
	Now: () -> number,
	StringId: (notifyType: string) -> string,
	IsPresent: (userId: number) -> boolean,
	GetSentDay: (userId: number) -> number?,
	MarkSent: (userId: number, day: number) -> (),
	-- The Open Cloud status code, or nil if there was no answer.
	Send: (userId: number, entry: Entry, stringId: string) -> number?,
}

type State = {
	connections: { RBXScriptConnection },
	running: boolean,
	enabled: boolean,
	secret: any?,
	universeId: number,
	queue: any?,
	recent: any?,
	presence: any?,
	sent: any?,
	backoffUntil: number,
	sentLocal: { [number]: number },
	loggedStatus: { [string]: boolean },
	lastAdminAbuseAt: number,
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	connections = {},
	running = false,
	enabled = false,
	secret = nil,
	universeId = 0,
	queue = nil,
	recent = nil,
	presence = nil,
	sent = nil,
	backoffUntil = 0,
	sentLocal = {},
	loggedStatus = {},
	lastAdminAbuseAt = -math.huge,
}

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule

local NotifyService = {}

NotifyService.Name = "NotifyService"

--[[ Pure helpers (shared with /selftest) --------------------------------- ]]

local function utcDay(time: number): number
	return time // 86400
end

local function isTypeEnabled(notifyType: string): boolean
	return (NotifyConfig.StringIds[notifyType] or "") ~= ""
end

-- Decides and sends one due entry. Returns "Disabled", "Stale", "Present",
-- "AlreadySent", or the answer's NotifyConfig.Outcome: "Sent", "Backoff",
-- "Drop", "Retry". Marks the day as sent only on "Sent".
function NotifyService.Process(userId: number, entry: Entry, deps: Deps): string
	local stringId = deps.StringId(entry.Type)
	if stringId == "" then
		return "Disabled"
	end
	local now = deps.Now()
	if now - entry.DueAt > NotifyConfig.MaxLateSeconds then
		return "Stale"
	end
	if deps.IsPresent(userId) then
		return "Present"
	end
	if NotifyConfig.SentToday(deps.GetSentDay(userId), now) then
		return "AlreadySent"
	end
	local outcome = NotifyConfig.Outcome(deps.Send(userId, entry, stringId))
	if outcome == "Sent" then
		deps.MarkSent(userId, utcDay(now))
	end
	return outcome
end

-- What to queue for a player who leaves at `now` with `daily` saved and
-- `baseIncome` $/s: the earlier-due of DailyStreak and LabFull (NotifyConfig
-- .PickEntry), skipping types that are off. nil = nothing worth sending.
function NotifyService.PlanLeave(daily: DailyConfig.State, baseIncome: number, now: number, isEnabled: (string) -> boolean): Entry?
	local streak: Entry? = nil
	if isEnabled("DailyStreak") then
		local dueAt, params = NotifyConfig.GetDailyStreakDue(daily, now)
		if dueAt and params then
			streak = { Type = "DailyStreak", DueAt = dueAt, Params = params }
		end
	end
	local lab: Entry? = nil
	if isEnabled("LabFull") then
		local fullCash = OfflineConfig.Compute(baseIncome, OfflineConfig.MaxSeconds)
		local dueAt = NotifyConfig.GetLabFullDueAt(now, fullCash)
		if dueAt then
			lab = { Type = "LabFull", DueAt = dueAt, Params = { cash = NumberFormat.Money(fullCash) } }
		end
	end
	return NotifyConfig.PickEntry(streak, lab)
end

--[[ MemoryStore + HTTP ---------------------------------------------------- ]]

local function keyOf(userId: number): string
	return tostring(userId)
end

local function isPresent(userId: number): boolean
	if Players:GetPlayerByUserId(userId) then
		return true
	end
	local presence = state.presence
	if not presence then
		return false
	end
	local ok, value = pcall(function()
		return presence:GetAsync(keyOf(userId))
	end)
	if not ok then
		-- Never notify (or drop the entry) on a guess: the worker retries it.
		error("presence read failed: " .. tostring(value))
	end
	return value ~= nil
end

local function getSentDay(userId: number): number?
	local known = state.sentLocal[userId]
	if known then
		return known
	end
	local sent = state.sent
	if not sent then
		return nil
	end
	local ok, value = pcall(function()
		return sent:GetAsync(keyOf(userId))
	end)
	if not ok then
		error("sent-day read failed: " .. tostring(value))
	end
	if typeof(value) == "number" then
		state.sentLocal[userId] = value
		return value
	end
	return nil
end

local function markSent(userId: number, day: number)
	state.sentLocal[userId] = day
	local sent = state.sent
	if sent then
		pcall(function()
			sent:SetAsync(keyOf(userId), day, NotifyConfig.SentTtlSeconds)
		end)
	end
end

local function sendHttp(userId: number, entry: Entry, stringId: string): number?
	local body = HttpService:JSONEncode(NotifyConfig.BuildBody(state.universeId, entry, stringId))
	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = NotifyConfig.Endpoint:format(userId),
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["x-api-key"] = state.secret :: any,
			},
			Body = body,
		})
	end)
	if not ok then
		if not state.loggedStatus[entry.Type] then
			state.loggedStatus[entry.Type] = true
			warn(("NotifyService: %s send failed (no answer): %s"):format(entry.Type, tostring(response)))
		end
		return nil
	end
	local code = response.StatusCode
	if not state.loggedStatus[entry.Type] then
		state.loggedStatus[entry.Type] = true
		print(("NotifyService: first %s send answered %d"):format(entry.Type, code))
	end
	return code
end

local realDeps: Deps = {
	Now = os.time,
	StringId = function(notifyType: string): string
		return NotifyConfig.StringIds[notifyType] or ""
	end,
	IsPresent = isPresent,
	GetSentDay = getSentDay,
	MarkSent = markSent,
	Send = sendHttp,
}

-- Writes `entry` for a user, the higher priority already queued staying.
local function enqueue(userId: number, entry: Entry)
	local queue = state.queue
	if not queue then
		return
	end
	local ok, err = pcall(function()
		queue:UpdateAsync(keyOf(userId), function(old: any)
			local merged = NotifyConfig.Merge(NotifyConfig.SanitizeEntry(old), entry)
			return merged, math.floor(merged.DueAt)
		end, NotifyConfig.QueueTtlSeconds)
	end)
	if not ok then
		warn(("NotifyService: queueing %s for %d failed: %s"):format(entry.Type, userId, tostring(err)))
	end
end

local function touchRecent(userId: number)
	local recent = state.recent
	if recent then
		local now = os.time()
		pcall(function()
			recent:SetAsync(keyOf(userId), now, NotifyConfig.RecentPlayersTtlSeconds, now)
		end)
	end
end

--[[ Player lifecycle ------------------------------------------------------ ]]

local function onPlayerAdded(player: Player)
	-- Whitelisted launch data -> an attribute the client reads.
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if ok and typeof(joinData) == "table" then
		local action = NotifyConfig.ParseLaunchData((joinData :: any).LaunchData)
		if action then
			player:SetAttribute(NotifyConfig.LaunchAttribute, action)
		end
	end
	if not state.enabled then
		return
	end
	task.spawn(function()
		local userId = player.UserId
		pcall(function()
			(state.presence :: any):SetAsync(keyOf(userId), true, NotifyConfig.PresenceTtlSeconds)
		end)
		pcall(function()
			(state.queue :: any):RemoveAsync(keyOf(userId))
		end)
		touchRecent(userId)
	end)
end

-- PlayerDataService.OnRelease: the player's save is still loaded.
local function onRelease(player: Player)
	if not state.enabled then
		return
	end
	local userId = player.UserId
	local data = PlayerDataService.GetData(player)
	local entry = if data
		then NotifyService.PlanLeave(data.Daily, PlayerDataService.GetBasePassiveCashPerSecond(player), os.time(), isTypeEnabled)
		else nil
	task.spawn(function()
		pcall(function()
			(state.presence :: any):RemoveAsync(keyOf(userId))
		end)
		touchRecent(userId)
		if entry then
			enqueue(userId, entry)
		end
	end)
end

--[[ Worker ----------------------------------------------------------------- ]]

-- Takes an entry for this server for NotifyConfig.ClaimSeconds. nil = another
-- server has it (or it's gone).
local function claim(key: string): Entry?
	local queue = state.queue :: any
	local ok, claimed = pcall(function()
		return queue:UpdateAsync(key, function(old: any)
			if typeof(old) ~= "table" then
				return nil
			end
			local claimedUntil = old.ClaimedUntil
			if typeof(claimedUntil) == "number" and claimedUntil > os.time() then
				return nil
			end
			old.ClaimedUntil = os.time() + NotifyConfig.ClaimSeconds
			return old, if typeof(old.DueAt) == "number" then math.floor(old.DueAt) else os.time()
		end, NotifyConfig.QueueTtlSeconds)
	end)
	if not ok then
		return nil
	end
	return NotifyConfig.SanitizeEntry(claimed)
end

-- Puts a claimed entry back: due again at `dueAt`, or gone after too many tries.
local function release(key: string, dueAt: number?)
	local queue = state.queue :: any
	pcall(function()
		queue:UpdateAsync(key, function(old: any)
			if typeof(old) ~= "table" then
				return nil
			end
			old.ClaimedUntil = nil
			if dueAt then
				old.Attempts = (if typeof(old.Attempts) == "number" then old.Attempts else 0) + 1
				if old.Attempts >= NotifyConfig.MaxAttempts then
					return nil
				end
				old.DueAt = dueAt
			end
			return old, if typeof(old.DueAt) == "number" then math.floor(old.DueAt) else os.time()
		end, NotifyConfig.QueueTtlSeconds)
	end)
end

local function remove(key: string)
	pcall(function()
		(state.queue :: any):RemoveAsync(key)
	end)
end

local function refreshPresence()
	for _, player in Players:GetPlayers() do
		pcall(function()
			(state.presence :: any):SetAsync(keyOf(player.UserId), true, NotifyConfig.PresenceTtlSeconds)
		end)
	end
end

local function workerTick()
	refreshPresence()
	if os.clock() < state.backoffUntil then
		return
	end
	local queue = state.queue :: any
	local ok, items = pcall(function()
		return queue:GetRangeAsync(Enum.SortDirection.Ascending, NotifyConfig.BatchSize, nil, { sortKey = os.time() + 1 })
	end)
	if not ok or typeof(items) ~= "table" then
		return
	end
	for _, item in items do
		local key = item.key
		local userId = if typeof(key) == "string" then tonumber(key) else nil
		if not userId then
			continue
		end
		local entry = claim(key)
		if not entry then
			continue
		end
		local processed, outcome = pcall(NotifyService.Process, userId, entry, realDeps)
		if not processed then
			-- A MemoryStore read failed (see isPresent / getSentDay): try again later.
			outcome = "Retry"
		end
		if outcome == "Backoff" then
			release(key, nil)
			state.backoffUntil = os.clock() + NotifyConfig.BackoffSeconds
			warn("NotifyService: 429 from Open Cloud, backing off " .. NotifyConfig.BackoffSeconds .. " s")
			return
		elseif outcome == "Retry" then
			release(key, os.time() + NotifyConfig.RetryAfterSeconds)
		else
			-- Sent, Drop (a 4xx is never retried), Present, AlreadySent, Stale, Disabled.
			remove(key)
		end
	end
end

--[[ Admin Abuse ------------------------------------------------------------ ]]

-- Queues AdminAbuse for everyone in RecentPlayers who isn't in this server,
-- most recent first, at most AdminAbuseMaxRecipients, paced for MemoryStore's
-- request budget. Call it only on the server that received the admin's
-- action (AdminService); an event + luck started together queue once.
function NotifyService.QueueAdminAbuse(luck: number, minutes: number)
	if not state.enabled or not isTypeEnabled("AdminAbuse") then
		return
	end
	local now = os.clock()
	if now - state.lastAdminAbuseAt < NotifyConfig.AdminAbuseDedupeSeconds then
		return
	end
	state.lastAdminAbuseAt = now
	task.spawn(function()
		local recent = state.recent :: any
		local entry: Entry = {
			Type = "AdminAbuse",
			DueAt = os.time(),
			Params = { luck = luck, minutes = minutes },
		}
		local queued = 0
		local upper: any = nil
		while state.running and queued < NotifyConfig.AdminAbuseMaxRecipients do
			local ok, items = pcall(function()
				return recent:GetRangeAsync(Enum.SortDirection.Descending, 200, nil, upper)
			end)
			if not ok or typeof(items) ~= "table" or #items == 0 then
				break
			end
			for _, item in items do
				local userId = if typeof(item.key) == "string" then tonumber(item.key) else nil
				if userId and not Players:GetPlayerByUserId(userId) then
					enqueue(userId, entry)
					queued += 1
					task.wait(1 / NotifyConfig.AdminAbuseQueuePerSecond)
					if queued >= NotifyConfig.AdminAbuseMaxRecipients then
						break
					end
				end
			end
			local last = items[#items]
			upper = { key = last.key, sortKey = last.sortKey }
			if #items < 200 then
				break
			end
		end
		print(("NotifyService: queued Admin Abuse for %d players"):format(queued))
	end)
end

--[[ Self-test -------------------------------------------------------------- ]]

-- The pure parts with an injected clock and a fake sender: priority pick,
-- once-a-day, due times, launch-data whitelist, the request body. Nothing
-- touches MemoryStore or HTTP.
function NotifyService.SelfTest(result: (boolean, string, string?) -> ())
	local DAY = 86400
	local day = 20_000 -- a UTC day number
	local midnight = day * DAY

	-- Priority pick.
	local admin: Entry = { Type = "AdminAbuse", DueAt = 100, Params = {} }
	local streak: Entry = { Type = "DailyStreak", DueAt = 100, Params = {} }
	local lab: Entry = { Type = "LabFull", DueAt = 100, Params = {} }
	local pickedAll = NotifyConfig.PickEntry(lab, NotifyConfig.PickEntry(streak, admin))
	result(pickedAll ~= nil and pickedAll.Type == "AdminAbuse", "notify: on a tie AdminAbuse beats DailyStreak beats LabFull", pickedAll and pickedAll.Type or "nil")
	local earlier = NotifyConfig.PickEntry({ Type = "LabFull", DueAt = 50, Params = {} }, streak)
	result(earlier ~= nil and earlier.Type == "LabFull", "notify: the earlier-due entry is kept for a leaver", earlier and earlier.Type or "nil")
	result(NotifyConfig.PickEntry(nil, nil) == nil and NotifyConfig.PickEntry(nil, lab) == lab, "notify: picking from nothing / one entry", "")
	local merged = NotifyConfig.Merge(admin, lab)
	result(merged.Type == "AdminAbuse" and NotifyConfig.Merge(lab, admin).Type == "AdminAbuse", "notify: a queued AdminAbuse is not replaced by a lower type", merged.Type)

	-- Once a day.
	result(NotifyConfig.SentToday(day, midnight + 5) and not NotifyConfig.SentToday(day - 1, midnight + 5) and not NotifyConfig.SentToday(nil, midnight), "notify: one send per UTC day", "")

	-- Due times.
	local freshDaily = DailyConfig.Default()
	local noDue = NotifyConfig.GetDailyStreakDue(freshDaily, midnight)
	result(noDue == nil, "notify: DailyStreak needs a claimed streak", tostring(noDue))
	local claimed: DailyConfig.State = { Day = 3, LastClaimUtcDay = day, Skips = 1, Streak = 3 }
	local dueAt, params = NotifyConfig.GetDailyStreakDue(claimed, midnight + 10 * 3600)
	result(
		dueAt == midnight + DAY + NotifyConfig.DailyStreakDelaySeconds and params ~= nil and params.day == 4 and params.streak == 3,
		"notify: DailyStreak is due 3 h after 00:00 UTC the day after the claim, with Day 4 / streak 3",
		("due %s, params %s/%s"):format(tostring(dueAt), tostring(params and params.day), tostring(params and params.streak))
	)
	local missed: DailyConfig.State = { Day = 3, LastClaimUtcDay = day - 2, Skips = 1, Streak = 3 }
	local lateDue = NotifyConfig.GetDailyStreakDue(missed, midnight + 2 * 3600)
	result(lateDue == midnight + 2 * 3600 + NotifyConfig.DailyStreakMinWaitSeconds, "notify: an already-claimable reward waits 3 h from leaving", tostring(lateDue))
	result(NotifyConfig.GetLabFullDueAt(1000, 500) == 1000 + OfflineConfig.MaxSeconds and NotifyConfig.GetLabFullDueAt(1000, 0) == nil, "notify: LabFull is due MaxSeconds (4 h) after leaving, never for an empty lab", "")
	local plan = NotifyService.PlanLeave(claimed, 100, midnight + 10 * 3600, function()
		return true
	end)
	result(plan ~= nil and plan.Type == "LabFull" and plan.DueAt == midnight + 14 * 3600, "notify: leaving at 10:00 UTC queues LabFull (14:00) before DailyStreak (next day 03:00)", plan and plan.Type or "nil")
	local planOff = NotifyService.PlanLeave(claimed, 100, midnight, function(notifyType: string)
		return notifyType == "DailyStreak"
	end)
	result(planOff ~= nil and planOff.Type == "DailyStreak", "notify: a type with no string id is never planned", planOff and planOff.Type or "nil")

	-- Launch data.
	result(
		NotifyConfig.ParseLaunchData("daily") == "daily"
			and NotifyConfig.ParseLaunchData("admin") == "admin"
			and NotifyConfig.ParseLaunchData("lab") == "lab"
			and NotifyConfig.ParseLaunchData("DAILY") == nil
			and NotifyConfig.ParseLaunchData("daily; drop") == nil
			and NotifyConfig.ParseLaunchData(5) == nil
			and NotifyConfig.ParseLaunchData(nil) == nil,
		"notify: launch data is whitelisted (daily / admin / lab only)",
		""
	)

	-- Request body.
	local body = NotifyConfig.BuildBody(123, { Type = "DailyStreak", DueAt = 0, Params = { day = 4 } }, "999")
	result(
		body.source.universe == "universes/123"
			and body.payload.message_id == "999"
			and body.payload.parameters.day.string_value == "4"
			and body.join_experience.launch_data == "daily"
			and body.analytics_data.category == "DailyStreak",
		"notify: the Open Cloud body carries the universe, string id, parameters, launch data and category",
		""
	)
	local outcomes = { NotifyConfig.Outcome(200), NotifyConfig.Outcome(429), NotifyConfig.Outcome(403), NotifyConfig.Outcome(500), NotifyConfig.Outcome(nil) }
	result(table.concat(outcomes, ",") == "Sent,Backoff,Drop,Retry,Retry", "notify: 2xx sent, 429 backs off, other 4xx dropped, 5xx / no answer retried", table.concat(outcomes, ","))

	-- Process with a fake world.
	local now = midnight + 12 * 3600
	local sends: { string } = {}
	local sentDay: { [number]: number } = {}
	local presentIds: { [number]: boolean } = {}
	local status = 200
	local ids: { [string]: string } = { AdminAbuse = "1", DailyStreak = "2", LabFull = "" }
	local deps: Deps = {
		Now = function()
			return now
		end,
		StringId = function(notifyType: string)
			return ids[notifyType] or ""
		end,
		IsPresent = function(userId: number)
			return presentIds[userId] == true
		end,
		GetSentDay = function(userId: number)
			return sentDay[userId]
		end,
		MarkSent = function(userId: number, sentOn: number)
			sentDay[userId] = sentOn
		end,
		Send = function(userId: number, entry: Entry, stringId: string)
			table.insert(sends, ("%d:%s:%s"):format(userId, entry.Type, stringId))
			return status
		end,
	}
	local due: Entry = { Type = "DailyStreak", DueAt = now - 60, Params = { day = 2, streak = 2 } }
	local first = NotifyService.Process(7, due, deps)
	local second = NotifyService.Process(7, { Type = "AdminAbuse", DueAt = now, Params = {} }, deps)
	result(first == "Sent" and second == "AlreadySent" and #sends == 1 and sends[1] == "7:DailyStreak:2", "notify: a second notification the same UTC day is never sent", ("%s, %s, %d sends"):format(first, second, #sends))
	now += DAY
	result(NotifyService.Process(7, { Type = "AdminAbuse", DueAt = now, Params = {} }, deps) == "Sent", "notify: the next UTC day sends again", "")
	presentIds[8] = true
	result(NotifyService.Process(8, { Type = "DailyStreak", DueAt = now, Params = {} }, deps) == "Present", "notify: never to someone who's in the game", "")
	result(NotifyService.Process(9, { Type = "LabFull", DueAt = now, Params = {} }, deps) == "Disabled", "notify: an empty string id is never sent", "")
	result(NotifyService.Process(9, { Type = "DailyStreak", DueAt = now - NotifyConfig.MaxLateSeconds - 5, Params = {} }, deps) == "Stale", "notify: an entry due over a day ago is dropped", "")
	local before = #sends
	status = 429
	local limited = NotifyService.Process(10, { Type = "AdminAbuse", DueAt = now, Params = {} }, deps)
	status = 403
	local refused = NotifyService.Process(11, { Type = "AdminAbuse", DueAt = now, Params = {} }, deps)
	status = 500
	local failed = NotifyService.Process(12, { Type = "AdminAbuse", DueAt = now, Params = {} }, deps)
	result(
		limited == "Backoff" and refused == "Drop" and failed == "Retry" and sentDay[10] == nil and sentDay[11] == nil and sentDay[12] == nil and #sends == before + 3,
		"notify: 429 / 4xx / 5xx answers never use up the day",
		("%s %s %s"):format(limited, refused, failed)
	)
	local clean = NotifyConfig.SanitizeEntry({ Type = "LabFull", DueAt = 5, Params = { cash = "$1K", bad = {}, n = 2 } })
	result(
		clean ~= nil and clean.Params.cash == "$1K" and clean.Params.n == 2 and clean.Params.bad == nil and NotifyConfig.SanitizeEntry({ Type = "Nope", DueAt = 1 }) == nil and NotifyConfig.SanitizeEntry("x") == nil,
		"notify: a queue value is sanitised (unknown type / bad params dropped)",
		""
	)
	result(not NotifyService.IsEnabled(), "notify: sending is off in Studio (no secret, no HTTP, no MemoryStore)", "")
end

-- True once sending can work (never in Studio).
function NotifyService.IsEnabled(): boolean
	return state.enabled
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function NotifyService:Init()
	table.insert(state.connections, Players.PlayerAdded:Connect(onPlayerAdded))
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function NotifyService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	if RunService:IsStudio() then
		return
	end
	if not HttpService.HttpEnabled then
		warn("NotifyService: HttpService.HttpEnabled is off (Game Settings -> Security); notifications disabled")
		return
	end
	local ok, secret = pcall(function()
		return HttpService:GetSecret(NotifyConfig.SecretName)
	end)
	if not ok or secret == nil then
		warn(("NotifyService: no %q secret; notifications disabled"):format(NotifyConfig.SecretName))
		return
	end
	state.secret = secret
	state.universeId = game.GameId
	state.queue = MemoryStoreService:GetSortedMap(NotifyConfig.QueueMap)
	state.recent = MemoryStoreService:GetSortedMap(NotifyConfig.RecentPlayersMap)
	state.presence = MemoryStoreService:GetHashMap(NotifyConfig.PresenceMap)
	state.sent = MemoryStoreService:GetHashMap(NotifyConfig.SentMap)
	state.enabled = true
	state.running = true

	PlayerDataService.OnRelease(onRelease)
	-- Players who joined before this ran.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	task.spawn(function()
		while state.running do
			task.wait(NotifyConfig.WorkerSeconds)
			local tickOk, err = pcall(workerTick)
			if not tickOk then
				warn("NotifyService: worker tick failed: " .. tostring(err))
			end
		end
	end)
end

function NotifyService:Stop()
	state.running = false
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
end

return NotifyService
