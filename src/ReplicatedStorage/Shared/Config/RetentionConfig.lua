--!strict
--[[
	RetentionConfig
	---------------
	The retention fix (docs/RETENTION_FIX_REPORT.md): the numbers and the pure
	rules of the "come back tomorrow" card and of the first-minutes analytics.
	(The first rival steal's rules are RivalConfig.FirstSteal.)

	Come-back card (ComeBackController + UI/ComeBackCard): ONE card, once per
	account, in the player's FIRST session (Shop.Sessions == 1), never during
	the tutorial. From ComeBack.MinSeconds of this visit's play it opens at the
	first natural pause (a big result card closing: a fusion, a good pull, the
	daily reveal, a delivered steal) and from ComeBack.FallbackSeconds (~4 min,
	the average first session was 4.6 min) the next time the screen is quiet
	(no card or panel, not carrying, not ragdolled). It shows what the player
	gets by coming back, from the real systems: tomorrow's daily reward
	(DailyConfig ladder), today's if it is still waiting, and what the lab
	earns while they are away (OfflineConfig, the server's number). No
	countdown, no pressure copy.

	Analytics (AnalyticsKit, server): SessionMinutes at 2 / 5 / 10 minutes of a
	visit (RewardService's play clock), ComeBackShown (remote ComeBackShown,
	re-checked here), Day2Return (funnel, appended) + ReturnVisit (custom) on the
	first join on a later UTC day than the first one (PlayerData.FirstUtcDay /
	LastJoinUtcDay).
]]
local DailyConfig = require(script.Parent.DailyConfig)
local RewardConfig = require(script.Parent.RewardConfig)

local RetentionConfig = {}

RetentionConfig.ComeBack = {
	MinSeconds = 150, -- earliest (this visit's play): a natural pause after it shows the card
	FallbackSeconds = 240, -- ~4 min: the next quiet moment shows it
	MaxSessions = 1, -- the first session only
	TipId = "comeBack", -- TipConfig: saved once shown (never twice per account)
}

-- A visit's play time marks (seconds) logged as SessionMinutes (value = minutes).
RetentionConfig.SessionMarks = { 120, 300, 600 } :: { number }

export type ComeBackState = {
	Seen: boolean, -- the TipId is saved
	Sessions: number, -- this profile's sessions, this one included
	TutorialActive: boolean,
	PlaySeconds: number, -- this visit
	Moment: boolean, -- a natural pause just happened (a big card closed)
	Quiet: boolean, -- no card / panel / side card open
	Busy: boolean, -- carrying an orb, ragdolled, in the arena
}

-- Whether the come-back card should open now.
function RetentionConfig.ShouldShowComeBack(s: ComeBackState): boolean
	local rule = RetentionConfig.ComeBack
	if s.Seen or s.Sessions < 1 or s.Sessions > rule.MaxSessions or s.TutorialActive or s.Busy or not s.Quiet then
		return false
	end
	if s.PlaySeconds >= rule.FallbackSeconds then
		return true
	end
	return s.Moment and s.PlaySeconds >= rule.MinSeconds
end

-- The server's re-check of a ComeBackShown report: first session, not seen
-- yet, tutorial over and at least MinSeconds into the visit. A junk or early
-- call changes nothing.
function RetentionConfig.CanMarkComeBack(seen: boolean, sessions: number, tutorialDone: boolean, playSeconds: number): boolean
	local rule = RetentionConfig.ComeBack
	return not seen and sessions >= 1 and sessions <= rule.MaxSessions and tutorialDone and playSeconds >= rule.MinSeconds
end

export type DailyView = { CanClaim: boolean, Day: number }

export type ComeBackPlan = {
	TomorrowDay: number,
	Tomorrow: RewardConfig.Reward,
	TodayWaiting: boolean, -- today's reward is not claimed yet
	TodayDay: number,
	Later: { { Day: number, Reward: RewardConfig.Reward } }, -- the next two notable days after tomorrow
	OfflineMax: number, -- cash the lab earns over OfflineConfig.MaxSeconds away (0: nothing)
}

-- What the card shows, from the snapshot's daily status (today's) and the
-- server's offline number. Tomorrow is the day after today's claim (if today's
-- is still waiting, the card says so: claiming it is what keeps the ladder
-- going). `Later` lists the day after tomorrow and Day 7, so the ladder reads.
function RetentionConfig.PlanComeBack(daily: DailyView, offlineMax: number): ComeBackPlan
	local cycle = DailyConfig.Cycle
	local todayDay = math.clamp(math.floor(daily.Day), 1, cycle)
	local tomorrowDay = todayDay % cycle + 1
	local later: { { Day: number, Reward: RewardConfig.Reward } } = {}
	local after = tomorrowDay % cycle + 1
	if after ~= todayDay then
		table.insert(later, { Day = after, Reward = DailyConfig.GetReward(after) })
	end
	if cycle ~= after and cycle ~= tomorrowDay and cycle ~= todayDay then
		table.insert(later, { Day = cycle, Reward = DailyConfig.GetReward(cycle) })
	end
	return {
		TomorrowDay = tomorrowDay,
		Tomorrow = DailyConfig.GetReward(tomorrowDay),
		TodayWaiting = daily.CanClaim,
		TodayDay = todayDay,
		Later = later,
		OfflineMax = math.max(0, math.floor(offlineMax)),
	}
end

-- The marks a visit's play clock crossed going from `before` to `after` seconds.
function RetentionConfig.CrossedMarks(before: number, after: number): { number }
	local crossed: { number } = {}
	for _, mark in RetentionConfig.SessionMarks do
		if before < mark and after >= mark then
			table.insert(crossed, mark)
		end
	end
	return crossed
end

export type JoinDays = { First: number, Last: number, ReturnDays: number? }

-- A join on UTC day `today`. `first` / `last` are the saved FirstUtcDay /
-- LastJoinUtcDay (0 = never recorded, -1 = an old save whose first day is
-- unknown); `sessionsBefore` the sessions before this one; `lastOnlineDay` the
-- UTC day of the save's LastOnline (0 = none). A brand-new save starts its
-- first day today; an old save with exactly one earlier session dates its first
-- day from its last save (the ad-test players); anything older is unknown and
-- never counted. ReturnDays (days since the first day) is set on the FIRST join
-- of each later UTC day.
function RetentionConfig.OnJoin(first: number, last: number, sessionsBefore: number, today: number, lastOnlineDay: number): JoinDays
	if first == 0 then
		if sessionsBefore <= 0 then
			first = today
		elseif sessionsBefore == 1 and lastOnlineDay > 0 then
			first = lastOnlineDay
			last = lastOnlineDay
		else
			first = -1
		end
	end
	local returnDays: number? = nil
	if first > 0 and today > first and today ~= last then
		returnDays = today - first
	end
	return { First = first, Last = today, ReturnDays = returnDays }
end

return RetentionConfig
