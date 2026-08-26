-- Shared "sci-fi fusion lab" look for any pad/interactable part: a dark base
-- material, a glowing Highlight outline, a beveled SpecialMesh, a
-- ground-bleeding light, and a small floating/pulsing accent orb (with
-- optional ambient sparkle). Apply once per part so every pad in the game
-- reads as one consistent visual language instead of one-off colored bricks.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)

local PadStyler = {}

export type PadStyle = {
	AccentColor: Color3?,
	BaseMaterial: Enum.Material?,
	BaseColor: Color3?,
	LightRange: number?,
	LightBrightness: number?,
	UseSpotLight: boolean?,
	WithSparkle: boolean?,
}

local DEFAULT_ACCENT_COLOR = Color3.fromRGB(0, 225, 255)
local DEFAULT_BASE_MATERIAL = Enum.Material.Slate
local DEFAULT_BASE_COLOR = Color3.fromRGB(35, 38, 45)
local DEFAULT_LIGHT_RANGE = 12
local DEFAULT_LIGHT_BRIGHTNESS = 3

-- The floating accent orb hovers above the pad and gently bobs/pulses; it's a
-- separate part (not the pad itself) so styling never disturbs the pad's own
-- Position, which gameplay code (touch detection, floor-snapping) depends on.
local ORB_SIZE = Vector3.new(1, 1, 1)
local ORB_HOVER_HEIGHT_STUDS = 3
local ORB_BOB_HEIGHT_STUDS = 0.6
local ORB_BOB_SECONDS = 1.6
local ORB_PULSE_SECONDS = 1.2
local ORB_PULSE_TRANSPARENCY = 0.4

-- Applies the shared visual style to `part`. Safe to call more than once on
-- the same part: any elements from a previous Apply are cleared first so
-- re-styling doesn't stack duplicate Highlights/lights/orbs.
function PadStyler.Apply(part: BasePart, style: PadStyle?): { [string]: Instance }
	style = style or {}
	local accentColor = style.AccentColor or DEFAULT_ACCENT_COLOR

	local existingElements = part:FindFirstChild("PadStylerElements")
	if existingElements then
		existingElements:Destroy()
	end
	local elementsFolder = Instance.new("Folder")
	elementsFolder.Name = "PadStylerElements"
	elementsFolder.Parent = part

	-- Lights only render while parented directly to a BasePart, so this one
	-- lives outside elementsFolder and needs its own re-apply cleanup.
	local existingLight = part:FindFirstChild("PadStylerLight")
	if existingLight then
		existingLight:Destroy()
	end

	part.Material = style.BaseMaterial or DEFAULT_BASE_MATERIAL
	part.Color = style.BaseColor or DEFAULT_BASE_COLOR

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Brick
	mesh.Parent = elementsFolder

	local highlight = Instance.new("Highlight")
	highlight.FillColor = accentColor
	highlight.FillTransparency = 0.85
	highlight.OutlineColor = accentColor
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = elementsFolder

	local light: PointLight | SpotLight
	if style.UseSpotLight then
		local spotLight = Instance.new("SpotLight")
		spotLight.Face = Enum.NormalId.Bottom
		spotLight.Angle = 90
		light = spotLight
	else
		light = Instance.new("PointLight")
	end
	light.Name = "PadStylerLight"
	light.Color = accentColor
	light.Range = style.LightRange or DEFAULT_LIGHT_RANGE
	light.Brightness = style.LightBrightness or DEFAULT_LIGHT_BRIGHTNESS
	light.Parent = part

	local orb = Instance.new("Part")
	orb.Name = "AccentOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = ORB_SIZE
	orb.Material = Enum.Material.Neon
	orb.Color = accentColor
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanTouch = false
	orb.CanQuery = false
	orb.Position = part.Position + Vector3.new(0, part.Size.Y / 2 + ORB_HOVER_HEIGHT_STUDS, 0)
	orb.Parent = elementsFolder

	local bobTween = TweenService:Create(
		orb,
		TweenInfo.new(ORB_BOB_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = orb.Position + Vector3.new(0, ORB_BOB_HEIGHT_STUDS, 0) }
	)
	bobTween:Play()

	local pulseTween = TweenService:Create(
		orb,
		TweenInfo.new(ORB_PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = ORB_PULSE_TRANSPARENCY }
	)
	pulseTween:Play()

	local sparkle: ParticleEmitter?
	if style.WithSparkle ~= false then
		sparkle = SparkleEmitter.Create({ Color = accentColor })
		sparkle.Parent = orb
	end

	return {
		Elements = elementsFolder,
		Mesh = mesh,
		Highlight = highlight,
		Light = light,
		Orb = orb,
		Sparkle = sparkle,
	}
end

return PadStyler
