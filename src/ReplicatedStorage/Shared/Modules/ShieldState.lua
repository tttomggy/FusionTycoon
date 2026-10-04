--!strict
--[[
	ShieldState
	-----------
	A lab's LOCK state from the attributes HeistService publishes on the
	plot (Protected, ShieldUntil, ShieldRearmAt; server times), so every
	client view (the LOCK console, the HUD LOCK chip) reads it the same
	way without a remote.

	  Protected   owner under HeistConfig.MinRebirths (also before known)
	  Locked      shield up; seconds = time left
	  Recharging  LOCK recharging after a shield ended; seconds = time left
	  Ready       LOCK would raise the shield now
]]
local Workspace = game:GetService("Workspace")

local ShieldState = {}

export type State = "Ready" | "Locked" | "Recharging" | "Protected"

function ShieldState.Get(plot: Instance): (State, number)
	local now = Workspace:GetServerTimeNow()
	if plot:GetAttribute("Protected") ~= false then
		return "Protected", 0
	end
	local shieldUntil = plot:GetAttribute("ShieldUntil")
	if typeof(shieldUntil) == "number" and shieldUntil > now then
		return "Locked", math.ceil(shieldUntil - now)
	end
	local rearmAt = plot:GetAttribute("ShieldRearmAt")
	if typeof(rearmAt) == "number" and rearmAt > now then
		return "Recharging", math.ceil(rearmAt - now)
	end
	return "Ready", 0
end

return ShieldState
