--[[
	event_schedule_check.luau
	-------------------------
	Runs the REAL EventConfig.GetEventForSlot over consecutive slots and
	prints the share of each event against its target (weights /
	VoidMoonChance) and the longest run of the same weather.

	  luau tools/event_schedule_check.luau          (from the repo root)

	EventConfig has no requires and only uses bit32/math, so the standalone
	Luau CLI can load it as-is.
]]
local EventConfig = require("../src/ReplicatedStorage/Shared/Config/EventConfig")

local SLOTS = 10000
local START = 1767225600 -- 2026-01-01 00:00 UTC (an hh:00 slot)

local counts: { [string]: number } = {}
local nights, weathers = 0, 0
local longestRun, longestId = 0, ""
local runId, runLength = "", 0
-- Independence: after weather X, how often is the next weather X again?
-- Independent slots repeat at X's own weight; the old Random.new(slot) seed
-- repeated far more often.
local after: { [string]: number } = {}
local repeats: { [string]: number } = {}
local previous = ""

for i = 0, SLOTS - 1 do
	local slot = EventConfig.GetEventForSlot(START + i * EventConfig.SlotSeconds)
	counts[slot.Id] = (counts[slot.Id] or 0) + 1
	if slot.Id == "Night" or slot.Id == "VoidMoon" then
		nights += 1
	else
		weathers += 1
		-- Runs of the same weather across consecutive weather slots (the hh:00
		-- night between two hours doesn't break a run).
		if previous ~= "" then
			after[previous] = (after[previous] or 0) + 1
			if slot.Id == previous then
				repeats[previous] = (repeats[previous] or 0) + 1
			end
		end
		previous = slot.Id
		if slot.Id == runId then
			runLength += 1
		else
			runId, runLength = slot.Id, 1
		end
		if runLength > longestRun then
			longestRun, longestId = runLength, runId
		end
	end
end

local totalWeight = 0
for _, entry in EventConfig.WeatherWeights do
	totalWeight += entry.Weight
end

print(("%d slots from %d: %d nights, %d weathers"):format(SLOTS, START, nights, weathers))
local worst = 0
local function line(id: string, share: number, target: number)
	local diff = math.abs(share - target) * 100
	worst = math.max(worst, diff)
	print(("  %-13s %5.1f%%  target %5.1f%%  (%+.1f pts)"):format(id, share * 100, target * 100, (share - target) * 100))
end
print("nights:")
line("VoidMoon", (counts.VoidMoon or 0) / nights, EventConfig.VoidMoonChance)
line("Night", (counts.Night or 0) / nights, 1 - EventConfig.VoidMoonChance)
print("weathers:")
for _, entry in EventConfig.WeatherWeights do
	line(entry.Id, (counts[entry.Id] or 0) / weathers, entry.Weight / totalWeight)
end
print("next weather repeats (independent = its own share):")
for _, entry in EventConfig.WeatherWeights do
	local n = after[entry.Id] or 0
	local share = if n > 0 then (repeats[entry.Id] or 0) / n else 0
	print(("  %-13s %5.1f%%  vs %5.1f%%"):format(entry.Id, share * 100, entry.Weight / totalWeight * 100))
end
print(("longest run of one weather: %d x %s"):format(longestRun, longestId))
print(if worst <= 2 then ("OK: every share within 2 points (worst %.1f)"):format(worst) else ("FAIL: a share is %.1f points off"):format(worst))
