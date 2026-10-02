--!nonstrict
--[[
	FusionMachineService
	--------------------
	Builds a Fusion Machine: a glowing core on a dark plinth, a spinning accent
	ring, a ProximityPrompt to fuse, and a board showing the live success odds
	from FusionConfig. All code-built so it stays Rojo-friendly.

	One machine PER PLOT now. It used to be a single shared machine parked next
	to whoever got plot slot 1, so the player in slot 5 had a ~560-stud walk to
	fuse anything. TycoonService calls FusionMachineService.Build for each plot,
	at the same plot-relative spot slot 1's machine always used (local +95 X),
	which already fits between plots (spacing 140).

	Lifecycle: :Init() only removes any leftover shared machine from an older
	build. No cross-service references.
]]
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)

local FusionMachineService = {}

FusionMachineService.Name = "FusionMachineService"

FusionMachineService.MACHINE_NAME = "FusionMachine"

local BASE_SIZE = Vector3.new(24, 2, 24)

local CORE_SIZE = Vector3.new(4, 4, 4)
local RING_SIZE = Vector3.new(0.6, 9, 9) -- Cylinder shape: X = thickness, Y/Z = diameter
local ORBIT_ATTACHMENT_COUNT = 4
local ACCENT_COLOR = Color3.fromRGB(140, 70, 255)
local DARK_COLOR = Color3.fromRGB(22, 22, 27)

local PROMPT_MAX_ACTIVATION_DISTANCE = 10
-- MaxDistance comes from BillboardKit (26, like every pad label).
local ODDS_BILLBOARD_OFFSET = Vector3.new(0, 9, 0)

local function buildBase(position: Vector3): BasePart
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = BASE_SIZE
	base.Anchored = true
	base.CanCollide = true
	base.Material = Enum.Material.SmoothPlastic
	base.Color = DARK_COLOR
	base.Position = position
	return base
end

local function buildCore(base: BasePart): BasePart
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = CORE_SIZE
	core.Anchored = true
	core.CanCollide = false
	core.Material = Enum.Material.Neon
	core.Color = ACCENT_COLOR
	core.Position = base.Position + Vector3.new(0, base.Size.Y / 2 + CORE_SIZE.Y / 2 + 1, 0)

	local light = Instance.new("PointLight")
	light.Color = ACCENT_COLOR
	light.Range = 28
	light.Brightness = 6
	light.Parent = core

	local sparkle = SparkleEmitter.Create({ Color = ACCENT_COLOR, Rate = 4 })
	sparkle.Parent = core

	return core
end

-- A flat neon disc with sparkle trails on its rim; RevealEffects spins it
-- during a fusion so the trails visibly orbit the core.
local function buildRing(core: BasePart): BasePart
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = RING_SIZE
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = ACCENT_COLOR
	ring.Transparency = 0.35
	ring.CFrame = CFrame.new(core.Position) * CFrame.Angles(0, 0, math.rad(90))

	local radius = RING_SIZE.Y / 2
	for index = 1, ORBIT_ATTACHMENT_COUNT do
		local angle = (index / ORBIT_ATTACHMENT_COUNT) * math.pi * 2
		local attachment = Instance.new("Attachment")
		attachment.Name = "OrbitAttachment" .. index
		attachment.Position = Vector3.new(0, math.cos(angle) * radius, math.sin(angle) * radius)
		attachment.Parent = ring

		local sparkle = SparkleEmitter.Create({ Color = ACCENT_COLOR, Rate = 6 })
		sparkle.Parent = attachment
	end

	return ring
end

-- "Fusion Odds": what 2 of each tier turn into, and how likely. Built by
-- BillboardKit so it matches every other world label.
local function buildOddsBillboard(anchor: BasePart)
	local rows = {}
	for _, tier in FusionConfig.TierOrder do
		local nextTier = FusionConfig.GetNextTier(tier)
		local chance = FusionConfig.SuccessChance[tier]
		if nextTier and chance then
			table.insert(rows, { FromTier = tier, ToTier = nextTier, Chance = chance })
		end
	end
	BillboardKit.OddsBoard(anchor, rows, ODDS_BILLBOARD_OFFSET)
end

-- Left disabled until the client confirms the owner has a fusable pair.
local function buildPrompt(core: BasePart): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FusePrompt"
	prompt.ActionText = "Fuse"
	prompt.ObjectText = "Fusion Machine"
	prompt.MaxActivationDistance = PROMPT_MAX_ACTIVATION_DISTANCE
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = core
	return prompt
end

-- Builds one machine for a plot at plot-local `localPos` (floor top y = 0).
-- Returns the Model (already parented to `parent`).
function FusionMachineService.Build(originCFrame: CFrame, localPos: Vector3, parent: Instance): Model
	local machine = Instance.new("Model")
	machine.Name = FusionMachineService.MACHINE_NAME

	local basePosition = originCFrame:PointToWorldSpace(Vector3.new(localPos.X, BASE_SIZE.Y / 2, localPos.Z))
	local base = buildBase(basePosition)
	base.Parent = machine

	local core = buildCore(base)
	core.Parent = machine

	local ring = buildRing(core)
	ring.Parent = machine

	buildOddsBillboard(base)
	buildPrompt(core)

	machine.PrimaryPart = core
	machine.Parent = parent
	return machine
end

function FusionMachineService:Init()
	-- Older builds put one shared machine directly in Workspace; if a place
	-- file still has it saved, remove it so it doesn't sit there unused.
	local legacy = Workspace:FindFirstChild(FusionMachineService.MACHINE_NAME)
	if legacy then
		legacy:Destroy()
	end
end

return FusionMachineService
