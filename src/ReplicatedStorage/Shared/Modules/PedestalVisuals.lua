-- Reads RarityVisuals and builds/tears down the corresponding effects on a
-- pedestal part: glow (Highlight + PointLight), ambient particles, a
-- rotating light ring, a pulse animation, a sky beam, an ambient sound loop,
-- and a proximity particle burst. Every branch below is gated purely by
-- which fields are present in the tier's RarityVisuals entry, so adding or
-- retuning a tier never requires touching this file or ItemService.
--
-- Runs server-side only: these are persistent, shared-world effects (not a
-- one-off personal animation), so they need to be built by the server to
-- replicate to every player, the same way TycoonService's pads/machine are.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RarityVisuals = require(ReplicatedStorage.Shared.Config.RarityVisuals)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)

local PedestalVisuals = {}

local ELEMENTS_FOLDER_NAME = "PedestalVisualElements"

local RING_DIAMETER = 5
local RING_HEIGHT_OFFSET_STUDS = 0.2

local SECRET_SHELL_TRANSPARENCY = 0.35

-- A mutation adds a second glass shell around the orb, in the mutation's
-- colour, with its own sparkle. Rainbow's shell is tagged FT_Rainbow and
-- cycles hue on clients (WorldAnimationController).
local MUTATION_SHELL_SCALE = 1.15
local MUTATION_SHELL_TRANSPARENCY = 0.6
type ShellSparkle = { Rate: number, Size: number, Speed: NumberRange }
local MUTATION_SPARKLES: { [string]: ShellSparkle } = {
	Golden = { Rate = 6, Size = 0.35, Speed = NumberRange.new(0.5, 1) },
	Charged = { Rate = 14, Size = 0.2, Speed = NumberRange.new(2, 3) },
	Diamond = { Rate = 12, Size = 0.22, Speed = NumberRange.new(1.5, 2.5) },
	Void = { Rate = 8, Size = 0.3, Speed = NumberRange.new(0.3, 0.8) },
	Rainbow = { Rate = 10, Size = 0.3, Speed = NumberRange.new(1, 2) },
	-- Celestial: a big, slow white star sparkle.
	Celestial = { Rate = 9, Size = 0.5, Speed = NumberRange.new(0.4, 0.9) },
}
-- Void's shell is the dark VoidShell glass (a dark core shell) with its
-- violet sparkle; every other shell is the mutation colour.
local DARK_SHELL_MUTATIONS: { [string]: boolean } = { Void = true }

local PULSE_SECONDS = 1.4
local PULSE_GROWTH = 1.08

local BEAM_HEIGHT_STUDS = 300
-- From the user-supplied "Beam Texture Pack" (Workspace, ~80 near-identical
-- energy-beam textures with no descriptive names/metadata to pick from) -
-- an arbitrary but reasonable pick, not a verified "best" one: no tool here
-- can render/preview a texture to judge it. Swap this single ID if it
-- doesn't read well in testing; nothing else about the beam depends on it.
local BEAM_TEXTURE_ID = "rbxassetid://5697446711"

local PROXIMITY_RADIUS_STUDS = 14
local PROXIMITY_COOLDOWN_SECONDS = 6
local PROXIMITY_BURST_COUNT = 40

-- The floating item orb: a glass ball in the tier colour (bigger for
-- higher tiers) around a Neon core, with a light. Its centre sits
-- PlotLayout.Pedestal.OrbCenterY above the pedestal's bottom. The group is
-- tagged FT_Hover, so clients spin and bob it. Returns the glass Orb part.
-- Satellites per mutation: how many, seconds per lap, and whether they
-- leave a short trail. Rainbow's take one RainbowStops hue each.
type SatelliteSpec = { Count: number, Period: number, Trail: boolean }
local MUTATION_SATELLITES: { [string]: SatelliteSpec } = {
	Golden = { Count = 2, Period = 2.4, Trail = false },
	Charged = { Count = 3, Period = 1.4, Trail = true }, -- a lightning-blue trail
	Diamond = { Count = 4, Period = 1.8, Trail = true },
	Void = { Count = 5, Period = 2.2, Trail = false },
	Rainbow = { Count = 6, Period = 1.5, Trail = true },
	Celestial = { Count = 6, Period = 1.2, Trail = true },
}

-- Neon balls the client orbits round the orb (FT_Orbit). Built here so
-- every player sees them; positions are set every frame on clients.
local function buildSatellites(group: Model, center: CFrame, diameter: number, mutation: string)
	local spec = MUTATION_SATELLITES[mutation]
	local color = UITheme.GetMutationColor(mutation)
	if not spec or not color then
		return
	end
	local p = PlotLayout.Pedestal
	local satellites = Instance.new("Model")
	satellites.Name = "Satellites"
	local stops = UITheme.Mutation.RainbowStops
	for index = 1, spec.Count do
		local hue = if mutation == "Rainbow" then stops[(index - 1) % #stops + 1] else color
		local ball = PartKit.Part({
			Name = "Satellite" .. index,
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * p.SatelliteDiameter,
			CFrame = center,
			Color = hue,
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = satellites,
		})
		PartKit.MakeDecorative(ball)
		if spec.Trail then
			local top = Instance.new("Attachment")
			top.Name = "TrailTop"
			top.Position = Vector3.new(0, p.SatelliteDiameter / 2, 0)
			top.Parent = ball
			local bottom = Instance.new("Attachment")
			bottom.Name = "TrailBottom"
			bottom.Position = Vector3.new(0, -p.SatelliteDiameter / 2, 0)
			bottom.Parent = ball
			local trail = Instance.new("Trail")
			trail.Attachment0 = top
			trail.Attachment1 = bottom
			trail.Lifetime = p.SatelliteTrailLifetime
			trail.Color = ColorSequence.new(hue)
			trail.LightEmission = 1
			trail.Transparency = NumberSequence.new(0.2, 1)
			trail.FaceCamera = true
			trail.Parent = ball
		end
	end
	satellites:SetAttribute("Count", spec.Count)
	satellites:SetAttribute("Radius", diameter / 2 + p.SatelliteRadiusExtra)
	satellites:SetAttribute("Period", spec.Period)
	satellites:SetAttribute("Tilt", p.SatelliteTiltDegrees)
	satellites:AddTag(PartKit.ORBIT_TAG)
	satellites.Parent = group
end

local function buildShell(group: Model, center: CFrame, diameter: number, mutation: string)
	local color = UITheme.GetMutationColor(mutation)
	if not color then
		return
	end
	local shell = PartKit.Part({
		Name = "MutationShell",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter * MUTATION_SHELL_SCALE,
		CFrame = center,
		Color = if DARK_SHELL_MUTATIONS[mutation] then UITheme.World.VoidShell else color,
		Material = Enum.Material.Glass,
		Transparency = if DARK_SHELL_MUTATIONS[mutation] then SECRET_SHELL_TRANSPARENCY else MUTATION_SHELL_TRANSPARENCY,
		Parent = group,
	})
	PartKit.MakeDecorative(shell)
	if mutation == "Rainbow" then
		shell:AddTag(PartKit.RAINBOW_TAG)
	end
	local preset = MUTATION_SPARKLES[mutation]
	if preset then
		local sparkle = SparkleEmitter.Create({ Color = color, Rate = preset.Rate })
		sparkle.Name = "MutationSparkle"
		sparkle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, preset.Size * 0.5),
			NumberSequenceKeypoint.new(0.5, preset.Size),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkle.Speed = preset.Speed
		if mutation == "Rainbow" then
			sparkle.Color = UITheme.GetRainbowSequence()
		end
		sparkle.Parent = shell
	end
end

-- The orb group (glass orb, Neon core, light, mutation shell and
-- satellites) centred on `center`. `hover` tags it FT_Hover (pedestals);
-- the heist's carried orb is welded to a head instead.
local function buildOrbAt(center: CFrame, tier: string, tierColor: Color3, parent: Instance, mutation: string?, hover: boolean): Model
	local p = PlotLayout.Pedestal
	local diameter = p.OrbDiameter[tier] or p.OrbDiameter.Common

	local group = Instance.new("Model")
	group.Name = "OrbGroup"

	-- Secret is the one dark orb, so it reads instantly: a VoidShell glass
	-- shell around the mint core.
	local isSecret = tier == "Secret"
	local orb = PartKit.Part({
		Name = "Orb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = center,
		Color = if isSecret then UITheme.World.VoidShell else tierColor,
		Material = Enum.Material.Glass,
		Transparency = if isSecret then SECRET_SHELL_TRANSPARENCY else p.OrbTransparency,
		Parent = group,
	})
	PartKit.MakeDecorative(orb)
	local core = PartKit.Part({
		Name = "OrbCore",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter * p.InnerOrbScale,
		CFrame = center,
		Color = tierColor,
		Material = Enum.Material.Neon,
		Parent = group,
	})
	PartKit.MakeDecorative(core)

	local light = Instance.new("PointLight")
	light.Color = tierColor
	light.Range = p.OrbLightRangeBase + p.OrbLightRangePerRank * (ItemConfig.Tiers[tier] or 1)
	light.Brightness = p.OrbLightBrightness
	light.Shadows = false
	light.Parent = orb

	if mutation then
		buildShell(group, center, diameter, mutation)
		buildSatellites(group, center, diameter, mutation)
	end

	group.PrimaryPart = orb
	if hover then
		PartKit.SetHover(group, p.OrbSpinDegPerSec, p.OrbBob, p.OrbBobPeriod, "Bob")
	end
	group.Parent = parent
	return group
end

local function buildOrb(pedestal: BasePart, tier: string, tierColor: Color3, parent: Instance, mutation: string?): BasePart
	local baseSize = (pedestal:GetAttribute("BaseSize") :: Vector3?) or pedestal.Size
	local bottom = pedestal.CFrame * CFrame.new(0, -baseSize.Y / 2, 0)
	local center = bottom * CFrame.new(0, PlotLayout.Pedestal.OrbCenterY, 0)
	local group = buildOrbAt(center, tier, tierColor, parent, mutation, true)
	return group.PrimaryPart :: BasePart
end

-- A cosmetic copy of a pedestal orb (mutation shell and satellites
-- included) for the heist's carried item, built on each client. Not
-- hovering: the caller welds the orb (PrimaryPart) to a character.
function PedestalVisuals.BuildCarryOrb(tier: string, mutation: string?, center: CFrame, parent: Instance): Model
	local config = RarityVisuals.Tiers[tier]
	local tierColor = FusionConfig.TierAccentColors[tier] or (config and config.GlowColor) or UITheme.Colors.Text
	return buildOrbAt(center, tier, tierColor, parent, mutation, false)
end

-- Removes every effect PedestalVisuals.Apply may have added, restoring the
-- pedestal to its bare, unoccupied appearance. Safe to call on a pedestal
-- that was never styled.
function PedestalVisuals.Clear(pedestal: BasePart)
	-- The orb pulse (PartKit.Pulse) dies with the orb in the elements folder.

	local cap = pedestal:FindFirstChild("Cap")
	if cap and cap:IsA("BasePart") then
		cap.Material = Enum.Material.SmoothPlastic
		cap.Color = UITheme.World.StructureLight
		local lip = cap:FindFirstChild("CapLip")
		if lip and lip:IsA("BasePart") then
			lip.Transparency = 1
		end
	end

	local elements = pedestal:FindFirstChild(ELEMENTS_FOLDER_NAME)
	if elements then
		elements:Destroy()
	end

	local light = pedestal:FindFirstChild("PedestalLight")
	if light then
		light:Destroy()
	end

	-- Older builds added a Highlight here; clear any left behind.
	local highlight = pedestal:FindFirstChild("PedestalHighlight")
	if highlight then
		highlight:Destroy()
	end

end

-- A thief is carrying this pedestal's item: the orb, light and effects go
-- and a dim Danger ghost ring sits on the cap until it's back (Apply) or
-- gone (Clear).
function PedestalVisuals.SetStolen(pedestal: BasePart)
	PedestalVisuals.Clear(pedestal)
	local elements = Instance.new("Folder")
	elements.Name = ELEMENTS_FOLDER_NAME
	local cap = pedestal:FindFirstChild("Cap")
	if cap and cap:IsA("BasePart") then
		local top = cap.CFrame * CFrame.new(0, cap.Size.Y / 2, 0)
		local ring = BillboardKit.BuildPadFace(elements, top, PlotLayout.Pedestal.CapSize.X, UITheme.Colors.Danger, nil)
		ring.Name = "StolenRing"
	end
	elements.Parent = pedestal
end

-- Applies tier's RarityVisuals entry to `pedestal`, plus a mutation shell
-- when the item has one. Clears any previous styling first, so this is
-- also how a pedestal gets reset/restyled.
function PedestalVisuals.Apply(pedestal: BasePart, tier: string, mutation: string?)
	PedestalVisuals.Clear(pedestal)

	local config = RarityVisuals.Tiers[tier]
	if not config then
		warn(("PedestalVisuals: no RarityVisuals entry for tier %s"):format(tier))
		return
	end

	if not pedestal:GetAttribute("BaseSize") then
		pedestal:SetAttribute("BaseSize", pedestal.Size)
	end

	local elements = Instance.new("Folder")
	elements.Name = ELEMENTS_FOLDER_NAME
	elements.Parent = pedestal

	local tierColor = FusionConfig.TierAccentColors[tier] or config.GlowColor
	local cap = pedestal:FindFirstChild("Cap")
	if cap and cap:IsA("BasePart") then
		-- The cap itself stays matte; only the thin lip under it glows.
		cap.Material = Enum.Material.SmoothPlastic
		cap.Color = tierColor
		local lip = cap:FindFirstChild("CapLip")
		if lip and lip:IsA("BasePart") then
			lip.Color = tierColor
			lip.Transparency = 0
		end
	end
	local orb = buildOrb(pedestal, tier, tierColor, elements, mutation)

	-- No Highlight: Roblox renders at most 31 per client, and 12 plots x 4
	-- pedestals can reach 48, so outlines silently vanish. The cap lip glow
	-- above already marks a filled pedestal.

	local light = Instance.new("PointLight")
	light.Name = "PedestalLight"
	light.Color = config.GlowColor
	light.Brightness = config.LightBrightness
	light.Range = config.LightRange
	light.Shadows = false
	light.Parent = pedestal

	if config.Particles then
		local particles = config.Particles
		local sparkle = SparkleEmitter.Create({ Color = config.GlowColor, Rate = particles.Rate })
		if particles.Speed then
			sparkle.Speed = particles.Speed
		end
		if particles.SpreadAngle then
			sparkle.SpreadAngle = particles.SpreadAngle
		end
		sparkle.Parent = orb
	end

	if config.RotatingRing then
		-- A glowing ring around the cap, drawn as a SurfaceGui face rather
		-- than a flat Neon disc (which renders as a fan of triangles under
		-- bloom). The orb already carries this pedestal's light.
		local baseSize = (pedestal:GetAttribute("BaseSize") :: Vector3?) or pedestal.Size
		local capTop = pedestal.CFrame * CFrame.new(0, baseSize.Y / 2 + RING_HEIGHT_OFFSET_STUDS, 0)
		local ring = BillboardKit.BuildPadFace(elements, capTop, RING_DIAMETER, config.GlowColor, nil)
		ring.Name = "Ring"
		local ringLight = ring:FindFirstChild("FaceLight")
		if ringLight then
			ringLight:Destroy()
		end
	end

	-- The pulse breathes the orb (pulsing the column would push its cap
	-- and bottom out of place).
	if config.Pulse then
		PartKit.Pulse(orb, PULSE_GROWTH, PULSE_SECONDS, true)
	end

	if config.Beam then
		local bottomAttachment = Instance.new("Attachment")
		bottomAttachment.Name = "BeamBottom"
		bottomAttachment.Parent = orb

		local topAttachment = Instance.new("Attachment")
		topAttachment.Name = "BeamTop"
		topAttachment.Position = Vector3.new(0, BEAM_HEIGHT_STUDS, 0)
		topAttachment.Parent = orb

		local beam = Instance.new("Beam")
		beam.Name = "SkyBeam"
		beam.Attachment0 = bottomAttachment
		beam.Attachment1 = topAttachment
		beam.Color = ColorSequence.new(config.GlowColor)
		beam.Width0 = 2
		beam.Width1 = 0.2
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.LightEmission = 1
		-- Previously untextured (a flat gradient with no pattern) - this was
		-- the actual gap RarityVisuals.Tiers.Mythic's Beam = true never
		-- filled. A slow upward scroll reads as an ambient, always-alive
		-- effect rather than a static column.
		beam.Texture = BEAM_TEXTURE_ID
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 4
		beam.TextureSpeed = 0.5
		beam.Parent = elements
	end

	if config.ProximityBurst then
		local triggerZone = Instance.new("Part")
		triggerZone.Name = "ProximityTrigger"
		triggerZone.Shape = Enum.PartType.Ball
		triggerZone.Size = Vector3.new(1, 1, 1) * (PROXIMITY_RADIUS_STUDS * 2)
		triggerZone.Transparency = 1
		triggerZone.Anchored = true
		triggerZone.CanCollide = false
		triggerZone.CanQuery = false
		triggerZone.Position = pedestal.Position
		triggerZone.Parent = elements

		local lastBurstAt = 0
		triggerZone.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			if not character or not character:FindFirstChildOfClass("Humanoid") then
				return
			end
			local now = os.clock()
			if now - lastBurstAt < PROXIMITY_COOLDOWN_SECONDS then
				return
			end
			lastBurstAt = now

			local burst = SparkleEmitter.Create({ Color = config.GlowColor })
			burst.Enabled = false
			burst.Parent = pedestal
			burst:Emit(PROXIMITY_BURST_COUNT)
			Debris:AddItem(burst, 3)
		end)
	end
end

return PedestalVisuals
