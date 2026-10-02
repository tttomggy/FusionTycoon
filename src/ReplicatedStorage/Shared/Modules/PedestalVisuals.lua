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
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RarityVisuals = require(ReplicatedStorage.Shared.Config.RarityVisuals)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)

local PedestalVisuals = {}

local ELEMENTS_FOLDER_NAME = "PedestalVisualElements"

local RING_SIZE = Vector3.new(0.4, 5, 5) -- Cylinder shape: X = thickness, Y/Z = diameter
local RING_HEIGHT_OFFSET_STUDS = 0.2
local RING_SPIN_RADIANS_PER_SECOND = math.rad(90)

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

-- Continuous per-pedestal state that can't be cleaned up just by destroying
-- instances (a running Heartbeat connection, an active looped Tween). Keyed
-- by the pedestal part so Clear() only ever touches what it itself started.
local activeSpins: { [BasePart]: RBXScriptConnection } = {}
local activePulses: { [BasePart]: Tween } = {}

local function stopSpin(ring: BasePart)
	local connection = activeSpins[ring]
	if connection then
		connection:Disconnect()
		activeSpins[ring] = nil
	end
end

local function startSpin(ring: BasePart)
	stopSpin(ring)
	activeSpins[ring] = RunService.Heartbeat:Connect(function(deltaTime: number)
		ring.CFrame *= CFrame.Angles(RING_SPIN_RADIANS_PER_SECOND * deltaTime, 0, 0)
	end)
	-- Safety net: if the ring is ever destroyed some other way (e.g. the
	-- whole plot getting torn down) the Heartbeat connection above would
	-- otherwise run forever against a dead instance.
	ring.Destroying:Connect(function()
		stopSpin(ring)
	end)
end

local function stopPulse(pedestal: BasePart)
	local tween = activePulses[pedestal]
	if tween then
		tween:Cancel()
		activePulses[pedestal] = nil
	end
	local baseSize = pedestal:GetAttribute("BaseSize")
	if baseSize then
		pedestal.Size = baseSize
	end
end

local function startPulse(pedestal: BasePart)
	stopPulse(pedestal)
	local baseSize = pedestal:GetAttribute("BaseSize") :: Vector3?
	if not baseSize then
		baseSize = pedestal.Size
		pedestal:SetAttribute("BaseSize", baseSize)
	end

	local tween = TweenService:Create(
		pedestal,
		TweenInfo.new(PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = (baseSize :: Vector3) * PULSE_GROWTH }
	)
	activePulses[pedestal] = tween
	tween:Play()

	pedestal.Destroying:Connect(function()
		stopPulse(pedestal)
	end)
end

-- The floating item orb: a glass ball in the tier colour (bigger for
-- higher tiers) around a Neon core, with a light. Its centre sits
-- PlotLayout.Pedestal.OrbCenterY above the pedestal's bottom. The group is
-- tagged FT_Hover, so clients spin and bob it. Returns the glass Orb part.
local function buildOrb(pedestal: BasePart, tier: string, tierColor: Color3, parent: Instance): BasePart
	local p = PlotLayout.Pedestal
	local baseSize = (pedestal:GetAttribute("BaseSize") :: Vector3?) or pedestal.Size
	local bottom = pedestal.CFrame * CFrame.new(0, -baseSize.Y / 2, 0)
	local center = bottom * CFrame.new(0, p.OrbCenterY, 0)
	local diameter = p.OrbDiameter[tier] or p.OrbDiameter.Common

	local group = Instance.new("Model")
	group.Name = "OrbGroup"

	local orb = PartKit.Part({
		Name = "Orb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = center,
		Color = tierColor,
		Material = Enum.Material.Glass,
		Transparency = p.OrbTransparency,
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
	light.Parent = orb

	group.PrimaryPart = orb
	PartKit.SetHover(group, p.OrbSpinDegPerSec, p.OrbBob, p.OrbBobPeriod, "Bob")
	group.Parent = parent
	return orb
end

-- Removes every effect PedestalVisuals.Apply may have added, restoring the
-- pedestal to its bare, unoccupied appearance. Safe to call on a pedestal
-- that was never styled.
function PedestalVisuals.Clear(pedestal: BasePart)
	stopPulse(pedestal)

	local cap = pedestal:FindFirstChild("Cap")
	if cap and cap:IsA("BasePart") then
		cap.Material = Enum.Material.SmoothPlastic
		cap.Color = UITheme.World.StructureLight
	end

	local elements = pedestal:FindFirstChild(ELEMENTS_FOLDER_NAME)
	if elements then
		for _, descendant in elements:GetDescendants() do
			if descendant:IsA("BasePart") then
				stopSpin(descendant)
			end
		end
		elements:Destroy()
	end

	local light = pedestal:FindFirstChild("PedestalLight")
	if light then
		light:Destroy()
	end

	local highlight = pedestal:FindFirstChild("PedestalHighlight")
	if highlight then
		highlight:Destroy()
	end

	local sound = pedestal:FindFirstChild("PedestalAmbientSound")
	if sound then
		sound:Destroy()
	end
end

-- Applies tier's RarityVisuals entry to `pedestal`. Clears any previous
-- styling first, so this is also how a pedestal gets reset/restyled.
function PedestalVisuals.Apply(pedestal: BasePart, tier: string)
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
		cap.Material = Enum.Material.Neon
		cap.Color = tierColor
	end
	local orb = buildOrb(pedestal, tier, tierColor, elements)

	local highlight = Instance.new("Highlight")
	highlight.Name = "PedestalHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = config.GlowColor
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = pedestal

	local light = Instance.new("PointLight")
	light.Name = "PedestalLight"
	light.Color = config.GlowColor
	light.Brightness = config.LightBrightness
	light.Range = config.LightRange
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
		local ring = Instance.new("Part")
		ring.Name = "Ring"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = RING_SIZE
		ring.Anchored = true
		ring.CanCollide = false
		ring.Material = Enum.Material.Neon
		ring.Color = config.GlowColor
		ring.Transparency = 0.4
		-- The cylinder's axis runs along local X; rotating 90 degrees around
		-- Z lays it flat, like a ring around the pedestal's base.
		-- At the cap, around the top of the column.
		ring.CFrame = CFrame.new(pedestal.Position + Vector3.new(0, pedestal.Size.Y / 2 + RING_HEIGHT_OFFSET_STUDS, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = elements

		startSpin(ring)
	end

	-- The pulse breathes the orb (pulsing the column would push its cap
	-- and bottom out of place).
	if config.Pulse then
		startPulse(orb)
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

	if config.AmbientSoundId then
		local sound = Instance.new("Sound")
		sound.Name = "PedestalAmbientSound"
		sound.SoundId = config.AmbientSoundId
		sound.Looped = true
		sound.Volume = 0.4
		sound.Parent = pedestal
		sound:Play()
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
