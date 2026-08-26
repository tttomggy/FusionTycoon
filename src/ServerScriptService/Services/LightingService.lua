-- Sets the plot's lighting mood once at server startup: bright, clearly-lit
-- daytime with a cool blue-tinted ColorShift for a "sci-fi facility" feel,
-- rather than leaning on darkness/haze for atmosphere the way the previous
-- (too dark, night-skybox-with-moon) tuning did.
local Lighting = game:GetService("Lighting")

local LightingService = {}

-- ClockTime 19 ("dusk") still put the sun below Roblox's day/night threshold,
-- so the default sky rendered a visible moon/night look regardless of the
-- Atmosphere/Ambient tuning layered on top - the moon isn't something an
-- Atmosphere or Ambient setting can hide, it's tied to time-of-day. 14
-- (mid-afternoon) is unambiguously daytime, so the sun is the dominant light
-- source and no moon/stars render at all, regardless of any other setting.
local CLOCK_TIME = 14
local BRIGHTNESS = 3
-- Cool blue/violet tint is what actually carries the "sci-fi lab" feel here -
-- kept, just lightened alongside everything else so it reads as a tint on a
-- bright scene rather than the thing making the scene dark.
local COLOR_SHIFT_TOP = Color3.fromRGB(60, 90, 130)
local COLOR_SHIFT_BOTTOM = Color3.fromRGB(40, 30, 60)
-- Previously ~45-65 (already once brightened from an even darker ~20-34) -
-- still dim enough that unlit geometry read as murky. Brightened further so
-- the floor/pads are clearly visible at a glance.
local AMBIENT = Color3.fromRGB(90, 100, 120)
local OUTDOOR_AMBIENT = Color3.fromRGB(85, 95, 115)

function LightingService.Init()
	Lighting.ClockTime = CLOCK_TIME
	Lighting.Brightness = BRIGHTNESS
	Lighting.ColorShift_Top = COLOR_SHIFT_TOP
	Lighting.ColorShift_Bottom = COLOR_SHIFT_BOTTOM
	Lighting.Ambient = AMBIENT
	Lighting.OutdoorAmbient = OUTDOOR_AMBIENT

	-- Atmosphere was trimmed back once already (0.35/1.8 -> 0.15/0.8) but
	-- still added enough haze, stacked with everything else, to dim/wash out
	-- the scene. Removed outright rather than tuned further - a clearly-lit
	-- plot mattered more here than a subtle facility-haze effect.
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere:Destroy()
	end

	-- Kept explicit even though ClockTime = 14 already guarantees no
	-- moon/stars render: guards against a future ClockTime change silently
	-- reintroducing them.
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.StarCount = 0
	sky.Parent = Lighting

	print("LightingService: bright daytime lighting applied")
end

return LightingService
