--!strict
--[[
	DealState
	---------
	The current deal on the shared UTC clock (DealConfig), read the same way
	by servers and clients.

	  Workspace attribute DealClockOffset  seconds added to the clock
	                                       (Studio /deal slot <offsetHours>)

	  DealState.Now()            server time + the offset
	  DealState.GetCurrent()     (key, slotStart, secondsLeft)
	  DealState.IsCurrent(key)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DealConfig = require(ReplicatedStorage.Shared.Config.DealConfig)

local DealState = {}

function DealState.Now(): number
	local offset = Workspace:GetAttribute("DealClockOffset")
	return Workspace:GetServerTimeNow() + (if typeof(offset) == "number" then offset else 0)
end

function DealState.GetCurrent(): (string, number, number)
	local now = DealState.Now()
	local slotStart = DealConfig.GetSlotStart(now)
	return DealConfig.GetDealForSlot(slotStart), slotStart, math.max(0, slotStart + DealConfig.SlotSeconds - now)
end

function DealState.IsCurrent(key: string): boolean
	local current = DealState.GetCurrent()
	return current == key
end

return DealState
