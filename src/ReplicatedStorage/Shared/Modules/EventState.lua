--!strict
--[[
	EventState
	----------
	The live event as everyone sees it, from the workspace attributes
	EventService publishes (the one writer):

	  EventId           the running event's id, "" between events
	  EventEndsAt       server time (Workspace:GetServerTimeNow()) it ends
	  EventStrength     1 normally; an admin event can be 2 or 3
	  EventClockOffset  seconds added to the clock (Studio /eventclock)
	  AdminLuck         admin luck multiplier (1 = none) ...
	  AdminLuckUntil    ... until this server time
	  NextAdminAbuse    unix seconds (UTC) of the next Admin Abuse, 0 = unset

	Server code that can't reference EventService (PlayerDataService is a
	leaf) and every client read effects through here, so a roll and the
	number shown for it always agree. The effect formulas live in
	EventConfig.
]]
local Workspace = game:GetService("Workspace")

local EventConfig = require(script.Parent.Parent.Config.EventConfig)
local MutationConfig = require(script.Parent.Parent.Config.MutationConfig)
local FusionConfig = require(script.Parent.Parent.Config.FusionConfig)

local EventState = {}

-- The event clock (unix seconds, plus the /eventclock offset).
function EventState.Now(): number
	local offset = Workspace:GetAttribute("EventClockOffset")
	return math.floor(Workspace:GetServerTimeNow()) + (if typeof(offset) == "number" then offset else 0)
end

-- (id, strength, endsAt) of the running event, or nil between events.
function EventState.GetActive(): (string?, number, number)
	local id = Workspace:GetAttribute("EventId")
	local endsAt = Workspace:GetAttribute("EventEndsAt")
	local strength = Workspace:GetAttribute("EventStrength")
	if typeof(id) ~= "string" or id == "" or typeof(endsAt) ~= "number" or endsAt <= Workspace:GetServerTimeNow() then
		return nil, 1, 0
	end
	return id, if typeof(strength) == "number" then strength else 1, endsAt
end

-- Mutation -> odds multiplier from `source` for every normal mutation (the
-- table MutationConfig.Roll / GetChance / FusionConfig.FormatOdds take).
function EventState.GetMutationMultipliers(source: string): { [string]: number }
	local id, strength = EventState.GetActive()
	local multipliers: { [string]: number } = {}
	for _, mutation in MutationConfig.Order do
		multipliers[mutation] = EventConfig.GetMutationOddsMultiplier(id, strength, mutation, source)
	end
	return multipliers
end

function EventState.GetFusionSuccessBonus(): number
	local id, strength = EventState.GetActive()
	return EventConfig.GetFusionSuccessBonus(id, strength)
end

function EventState.GetGeneratorMultiplier(): number
	local id, strength = EventState.GetActive()
	return EventConfig.GetGeneratorMultiplier(id, strength)
end

function EventState.GetFusionEventMutation(): (string?, number)
	local id, strength = EventState.GetActive()
	return EventConfig.GetFusionEventMutation(id, strength)
end

-- The live event's boosts for FusionConfig.FormatOdds (every odds display).
function EventState.GetOddsEvent(): FusionConfig.OddsEvent
	return {
		PullMultipliers = EventState.GetMutationMultipliers("Pull"),
		FusionMultipliers = EventState.GetMutationMultipliers("Fusion"),
		FusionBonus = EventState.GetFusionSuccessBonus(),
	}
end

export type LineupEntry = {
	Id: string,
	Now: boolean, -- running now
	Seconds: number, -- left if Now, else until it starts
}

-- What the HUD chip, schedule card and Event Boards show: the running
-- event (if any, admin ones included), then the scheduled ones after it.
function EventState.GetLineup(count: number): { LineupEntry }
	local list: { LineupEntry } = {}
	local id, _, endsAt = EventState.GetActive()
	if id then
		table.insert(list, { Id = id, Now = true, Seconds = math.max(0, endsAt - Workspace:GetServerTimeNow()) })
	end
	local clock = EventState.Now()
	local slotStart = EventConfig.GetSlotStart(clock) + EventConfig.SlotSeconds
	while #list < count do
		local slot = EventConfig.GetEventForSlot(slotStart)
		table.insert(list, { Id = slot.Id, Now = false, Seconds = slot.StartsAt - clock })
		slotStart += EventConfig.SlotSeconds
	end
	return list
end

-- "3:12", "1:04:09".
function EventState.FormatTimer(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return ("%d:%02d:%02d"):format(s // 3600, (s // 60) % 60, s % 60)
	end
	return ("%d:%02d"):format(s // 60, s % 60)
end

local ADMIN_ABUSE_LIVE_SECONDS = 60 * 60

-- The Admin Abuse line ("ADMIN ABUSE · Sat 18:00 · in 2d 4h"), the time in
-- the viewer's local zone.
function EventState.GetAdminAbuseText(): string
	local at = Workspace:GetAttribute("NextAdminAbuse")
	local now = Workspace:GetServerTimeNow()
	if typeof(at) ~= "number" or at <= 0 or now > at + ADMIN_ABUSE_LIVE_SECONDS then
		return "ADMIN ABUSE · date coming soon"
	end
	if now >= at then
		return "ADMIN ABUSE · LIVE NOW!"
	end
	local left = math.floor(at - now)
	local inText = if left >= 86400
		then ("%dd %dh"):format(left // 86400, (left // 3600) % 24)
		elseif left >= 3600 then ("%dh %dm"):format(left // 3600, (left // 60) % 60)
		else EventState.FormatTimer(left)
	local when = DateTime.fromUnixTimestamp(math.floor(at)):FormatLocalTime("ddd HH:mm", "en-us")
	return ("ADMIN ABUSE · %s · in %s"):format(when, inText)
end

-- The admin luck boost (stacks with rebirth luck); 1 when none.
function EventState.GetLuckMultiplier(): number
	local luck = Workspace:GetAttribute("AdminLuck")
	local untilTime = Workspace:GetAttribute("AdminLuckUntil")
	if typeof(luck) == "number" and typeof(untilTime) == "number" and untilTime > Workspace:GetServerTimeNow() then
		return luck
	end
	return 1
end

return EventState
