--!strict
-- Lighting mood: late-afternoon golden hour (ClockTime 17.2) with a soft
-- violet haze, a light bloom on only the brightest Neon, and slight
-- contrast/saturation.
-- Set once at server start. Lighting.Technology can't be set from a script:
-- set it to Future in Studio.
local Lighting = game:GetService("Lighting")

local LightingService = {}

LightingService.Name = "LightingService"

local function getOrCreate(className: string): Instance
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Parent = Lighting
	return created
end

function LightingService:Init()
	Lighting.ClockTime = 17.2
	Lighting.GeographicLatitude = 25
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(58, 54, 82)
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 112, 140)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 200, 150)
	Lighting.ColorShift_Bottom = Color3.fromRGB(60, 40, 100)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true

	local atmosphere = getOrCreate("Atmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.25
	atmosphere.Glare = 0.15
	atmosphere.Haze = 1
	atmosphere.Color = Color3.fromRGB(190, 170, 255)
	atmosphere.Decay = Color3.fromRGB(90, 70, 150)

	local bloom = getOrCreate("BloomEffect") :: BloomEffect
	bloom.Intensity = 0.35
	bloom.Size = 20
	bloom.Threshold = 2 -- only the brightest Neon blooms

	local colorCorrection = getOrCreate("ColorCorrectionEffect") :: ColorCorrectionEffect
	colorCorrection.Brightness = 0.02
	colorCorrection.Contrast = 0.12
	colorCorrection.Saturation = 0.12
	colorCorrection.TintColor = Color3.fromRGB(255, 248, 255)

	local sunRays = getOrCreate("SunRaysEffect") :: SunRaysEffect
	sunRays.Intensity = 0.06
	sunRays.Spread = 0.6

	-- Any other post effect (blur, depth of field, extra copies) goes.
	local keep: { [Instance]: boolean } = { [bloom] = true, [colorCorrection] = true, [sunRays] = true }
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") and not keep[child] then
			child:Destroy()
		end
	end
end

return LightingService
