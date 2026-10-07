--!strict
--[[
	TopStack
	--------
	The one manager of the top-centre of the screen. Fixed slots, top to
	bottom:

	  1. Objective  the tutorial's objective bar (nothing otherwise)
	  2. Chip       the event chip
	  3. Announce   ONE announcement line: banners, toasts and event starts,
	                queued and shown one at a time
	  4. Status     live bars that stay up (the heist's GET HOME! / THIEF IN
	                YOUR LAB! bars) hang below whatever the announcement uses

	Nothing else places anything at top centre: every owner asks
	`GetY(slot)` for its logical y (and re-places on `OnChanged`).

	Slot owners register a height provider (`SetHeight`); the stack polls them
	once a frame and fires `OnChanged` when a slot moved. With no objective
	bar the chip keeps its place beside the Roblox top bar (CHIP_Y); with it,
	the chip and everything below sit under the bar.

	The announcement line: `Announce(item)`; each item is shown for
	`Seconds` (default 2.5), the queue is capped at 4 (the oldest
	lowest-priority item is dropped), a higher `Priority` goes to the front
	(and cuts a lower one that is showing), and an item whose `Key` is
	already queued replaces it. `WhenIdle(fn)` runs `fn` once nothing is
	showing or queued (the welcome splash).

	  Announce({ Key?, Priority?, Seconds?, Height, Show(y), Hide(cut) -> seconds?,
	             Move?(y), Valid?() -> boolean })
]]
local RunService = game:GetService("RunService")

local UIKit = require(script.Parent.UIKit)

local TopStack = {}

export type Slot = "Objective" | "Chip" | "Announce" | "Status"

export type Item = {
	Key: string?,
	Priority: number?,
	Seconds: number?,
	Height: number, -- logical px the line uses while this shows
	Show: (y: number) -> (),
	Hide: (cut: boolean) -> number?, -- returns the seconds its exit takes
	Move: ((y: number) -> ())?, -- the slot moved while it showed
	Valid: (() -> boolean)?, -- checked when it reaches the front
}

TopStack.CHIP_Y = 12
TopStack.GAP = 8
TopStack.DEFAULT_SECONDS = 2.5
TopStack.MAX_QUEUED = 4
local POLL_SECONDS = 0.1

local heights: { [string]: () -> number } = {}
local announceHeight = 0
local listeners: { (slot: Slot) -> () } = {}
local lastY: { [string]: number } = {}

local queue: { Item } = {}
local current: Item? = nil
local running = false
local cutToken = 0
local idleWaiters: { () -> () } = {}

local function height(slot: string): number
	local provider = heights[slot]
	return if provider then math.max(0, provider()) else 0
end

--[[ Slots ---------------------------------------------------------------------- ]]

-- `provider` returns the logical height the slot uses right now (0: empty).
function TopStack.SetHeight(slot: "Objective" | "Chip", provider: () -> number)
	heights[slot] = provider
end

local function computeY(slot: Slot): number
	local objective = height("Objective")
	local chip = height("Chip")
	local gap = TopStack.GAP
	local objectiveY = UIKit.GetCardTop()
	if slot == "Objective" then
		return objectiveY
	end
	local chipY = if objective > 0 then objectiveY + objective + gap else TopStack.CHIP_Y
	if slot == "Chip" then
		return chipY
	end
	local announceY = if chip > 0 then chipY + chip + gap elseif objective > 0 then chipY else TopStack.CHIP_Y
	if slot == "Announce" then
		return announceY
	end
	return if announceHeight > 0 then announceY + announceHeight + gap else announceY
end

function TopStack.GetY(slot: Slot): number
	return computeY(slot)
end

-- Logical px from the top of the screen to the bottom of everything the
-- stack uses right now (a card or panel below must start under it).
function TopStack.GetBottom(): number
	local bottom = TopStack.GetY("Announce")
	if announceHeight > 0 then
		bottom += announceHeight
	end
	return bottom
end

function TopStack.OnChanged(callback: (slot: Slot) -> ())
	table.insert(listeners, callback)
end

local SLOTS: { Slot } = { "Objective", "Chip", "Announce", "Status" }

local function poll()
	for _, slot in SLOTS do
		local y = computeY(slot)
		local old = lastY[slot]
		lastY[slot] = y
		if old ~= nil and math.abs(old - y) > 0.5 then
			for _, callback in listeners do
				task.spawn(callback, slot)
			end
			local showing = current
			local move = if showing then showing.Move else nil
			if slot == "Announce" and move then
				move(y)
			end
		end
	end
end

--[[ The announcement line ---------------------------------------------------------- ]]

local function priorityOf(item: Item): number
	return item.Priority or 0
end

local function setAnnounceHeight(value: number)
	announceHeight = value
	poll()
end

local function fireIdle()
	if current or #queue > 0 then
		return
	end
	local waiting = idleWaiters
	idleWaiters = {}
	for _, callback in waiting do
		task.spawn(callback)
	end
end

local function run()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local item = table.remove(queue, 1) :: Item
			if not item.Valid or item.Valid() then
				current = item
				local myCut = cutToken
				setAnnounceHeight(item.Height)
				item.Show(computeY("Announce"))
				local hold = item.Seconds or TopStack.DEFAULT_SECONDS
				local elapsed = 0
				while elapsed < hold and cutToken == myCut do
					local step = math.min(POLL_SECONDS, hold - elapsed)
					task.wait(step)
					elapsed += step
				end
				local cut = cutToken ~= myCut
				local exit = item.Hide(cut)
				if exit and exit > 0 and not cut then
					task.wait(exit)
				end
				current = nil
				setAnnounceHeight(0)
			end
		end
		running = false
		fireIdle()
	end)
end

function TopStack.Announce(item: Item)
	-- The same key replaces its queued twin: newest wins.
	if item.Key then
		for index = #queue, 1, -1 do
			if queue[index].Key == item.Key then
				table.remove(queue, index)
			end
		end
	end
	local priority = priorityOf(item)
	if priority > 0 then
		-- Front of the queue, behind anything of higher priority.
		local at = 1
		while at <= #queue and priorityOf(queue[at]) >= priority do
			at += 1
		end
		table.insert(queue, at, item)
		if current and priorityOf(current) < priority then
			cutToken += 1
		end
	else
		table.insert(queue, item)
	end
	while #queue > TopStack.MAX_QUEUED do
		-- Drop the oldest of the lowest priority.
		local drop = 1
		for index = 1, #queue do
			if priorityOf(queue[index]) < priorityOf(queue[drop]) then
				drop = index
			end
		end
		table.remove(queue, drop)
	end
	run()
end

function TopStack.IsIdle(): boolean
	return current == nil and #queue == 0
end

function TopStack.GetQueueLength(): number
	return #queue
end

-- Runs `callback` once the line is empty (at once when it already is).
function TopStack.WhenIdle(callback: () -> ())
	if TopStack.IsIdle() then
		task.spawn(callback)
	else
		table.insert(idleWaiters, callback)
	end
end

function TopStack.Init()
	RunService.Heartbeat:Connect(poll)
	UIKit.LayoutChanged:Connect(poll)
	poll()
end

return TopStack
