--!strict
--[[
	EventService
	------------
	Runs the lab weather clock (EventConfig). Every second it works out which
	event should be on from the clock, deterministically from the UTC slot
	time (never random at runtime), so every server agrees with no messaging,
	and starts or ends it. An override (Studio /event, the admin panel)
	replaces the scheduled event until it ends; then the clock resumes.

	It publishes the live event as workspace attributes (EventId,
	EventEndsAt in server time, EventStrength), which every client and the
	leaf services read through EventState. The effect hooks below are the
	server's way in; they read the same EventState, so a roll always matches
	what the odds displays show:

	  EventService.GetMutationOddsMultiplier(mutation, source)
	  EventService.GetFusionSuccessBonus()
	  EventService.GetGeneratorMultiplier()
	  EventService.GetFusionEventMutation()

	Other code reacts to start/end through EventService.OnEventChanged.

	Follows ServiceTemplate:
	  :Init()   publishes the empty state.
	  :Start()  starts the clock loop.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)

--[[ Types ---------------------------------------------------------------- ]]

-- The running event: id, strength, end in server time. Id nil = nothing on.
export type ActiveEvent = { Id: string?, Strength: number, EndsAt: number }

type Override = { Id: string?, Strength: number, EndsAt: number }

type State = {
	active: ActiveEvent,
	-- An admin/debug event (or a forced quiet spell) until EndsAt (server time).
	override: Override?,
	changeHandlers: { (newEvent: ActiveEvent, oldEvent: ActiveEvent) -> () },
	running: boolean,
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	active = { Id = nil, Strength = 1, EndsAt = 0 },
	override = nil,
	changeHandlers = {},
	running = false,
}

local TICK_SECONDS = 1

local EventService = {}

EventService.Name = "EventService"

--[[ Private helpers ------------------------------------------------------ ]]

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function publish(event: ActiveEvent)
	Workspace:SetAttribute("EventId", event.Id or "")
	Workspace:SetAttribute("EventEndsAt", event.EndsAt)
	Workspace:SetAttribute("EventStrength", event.Strength)
end

-- What should be on right now: the override if it's live, else the clock.
local function desiredEvent(): ActiveEvent
	local now = serverNow()
	local override = state.override
	if override and override.EndsAt > now then
		return { Id = override.Id, Strength = override.Strength, EndsAt = override.EndsAt }
	end
	state.override = nil
	local clock = EventState.Now()
	local slot = EventConfig.GetScheduledEvent(clock)
	if slot then
		-- The slot's end on the event clock, in server time.
		return { Id = slot.Id, Strength = 1, EndsAt = now + (slot.EndsAt - clock) }
	end
	return { Id = nil, Strength = 1, EndsAt = 0 }
end

local function tick()
	local wanted = desiredEvent()
	local current = state.active
	if wanted.Id == current.Id and wanted.Strength == current.Strength then
		-- Same event: keep its end time fresh (an override can extend it).
		if wanted.Id and math.abs(wanted.EndsAt - current.EndsAt) > 1 then
			current.EndsAt = wanted.EndsAt
			publish(current)
		end
		return
	end
	state.active = wanted
	publish(wanted)
	if current.Id or wanted.Id then
		warn(("EventService: %s -> %s (x%d)"):format(tostring(current.Id), tostring(wanted.Id), wanted.Strength))
	end
	for _, handler in state.changeHandlers do
		task.spawn(handler, wanted, current)
	end
end

--[[ Public API ------------------------------------------------------------ ]]

-- The running event (Id nil between events).
function EventService.GetActive(): ActiveEvent
	return state.active
end

-- Registers `handler(newEvent, oldEvent)` for every start/end/switch.
function EventService.OnEventChanged(handler: (newEvent: ActiveEvent, oldEvent: ActiveEvent) -> ())
	table.insert(state.changeHandlers, handler)
end

-- Forces `id` at `strength` for `seconds` (admin panel, /event). It replaces
-- the scheduled event until it ends; then the clock resumes.
function EventService.ForceEvent(id: string, seconds: number, strength: number?)
	state.override = {
		Id = id,
		Strength = math.clamp(math.floor(strength or 1), 1, 3),
		EndsAt = serverNow() + math.max(seconds, 1),
	}
	tick()
end

-- Ends whatever is on now (/event off). A scheduled event stays off until
-- its slot is over, so it doesn't snap straight back.
function EventService.EndEvent()
	local current = state.active
	if current.Id then
		state.override = { Id = nil, Strength = 1, EndsAt = current.EndsAt }
	else
		state.override = nil
	end
	tick()
end

-- Studio /eventclock: shifts the clock by `minutes` so the schedule can be
-- walked through. Clients read the same offset (EventState.Now).
function EventService.SetClockOffset(minutes: number)
	Workspace:SetAttribute("EventClockOffset", math.floor(minutes * 60))
	state.override = nil
	tick()
end

--[[ Effect hooks (other code reads these; no globals) ---------------------- ]]

function EventService.GetMutationOddsMultiplier(mutation: string, source: string): number
	local event = state.active
	return EventConfig.GetMutationOddsMultiplier(event.Id, event.Strength, mutation, source)
end

function EventService.GetFusionSuccessBonus(): number
	local event = state.active
	return EventConfig.GetFusionSuccessBonus(event.Id, event.Strength)
end

function EventService.GetGeneratorMultiplier(): number
	local event = state.active
	return EventConfig.GetGeneratorMultiplier(event.Id, event.Strength)
end

function EventService.GetFusionEventMutation(): (string?, number)
	local event = state.active
	return EventConfig.GetFusionEventMutation(event.Id, event.Strength)
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function EventService:Init()
	publish(state.active)
end

function EventService:Start()
	state.running = true
	tick()
	task.spawn(function()
		while state.running do
			task.wait(TICK_SECONDS)
			tick()
		end
	end)
end

function EventService:Stop()
	state.running = false
end

return EventService
