--!nonstrict
--[[
	FusionMachineService
	--------------------
	Builds a plot's Fusion Machine: a round Structure platform with a violet
	Neon rim, four leaning pylons, a floating Neon Core with its spinning
	Ring, a floor glow, and an invisible PromptAnchor holding the fuse
	prompts. Beside it stands the odds board: a post and a real board with
	the odds on a SurfaceGui.

	TycoonService calls Build once per plot. Every position and size comes
	from PlotLayout (Machine, FUSION_MACHINE, ODDS_BOARD).

	RevealEffects animates `Core` (Size) and `Ring` (CFrame) by name, and
	FusionController finds the prompts on `PromptAnchor`.

	Lifecycle: :Init() only removes a leftover shared machine from an older
	build. No cross-service references.
]]
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)

local FusionMachineService = {}

FusionMachineService.Name = "FusionMachineService"
FusionMachineService.MACHINE_NAME = "FusionMachine"

local M = PlotLayout.Machine
local World = UITheme.World
local ACCENT = World.AccentViolet

-- Lighting/particle tuning (not geometry). The Rim is a thin band on the
-- base's side only; flat circles are SurfaceGui faces, never Neon.
local CORE_LIGHT_RANGE = 28
local CORE_LIGHT_BRIGHTNESS = 6
local CORE_SPARKLE_RATE = 4
local RING_TRANSPARENCY = 0.35
local ORBIT_ATTACHMENT_COUNT = 4
local ORBIT_SPARKLE_RATE = 6
local FUSE_ALL_HOLD_SECONDS = 0.6

local function buildPlatform(machine: Model, base: CFrame)
	PartKit.Cylinder({
		Name = "Base",
		Center = base * CFrame.new(0, M.BaseHeight / 2, 0),
		Height = M.BaseHeight,
		Diameter = M.BaseDiameter,
		Color = World.Structure,
		Parent = machine,
	})
	PartKit.Cylinder({
		Name = "Rim",
		Center = base * CFrame.new(0, M.BaseHeight - M.RimCenterBelowTop, 0),
		Height = M.RimHeight,
		Diameter = M.RimDiameter,
		Color = ACCENT,
		Material = Enum.Material.Neon,
		CanQuery = false,
		Parent = machine,
	})
	-- Ring + soft glow face on the platform top (no flat Neon disc).
	BillboardKit.BuildPadFace(machine, base * CFrame.new(0, M.BaseHeight, 0), M.FaceDiameter, ACCENT, nil)
end

-- Four pylons at 45/135/225/315 degrees, each leaning toward the centre,
-- with a Neon strip on its inward face.
local function buildPylons(machine: Model, base: CFrame)
	local top = base * CFrame.new(0, M.BaseHeight, 0)
	for _, degrees in M.PylonAnglesDegrees do
		local angle = math.rad(degrees)
		local foot = top * CFrame.new(math.cos(angle) * M.PylonRadius, 0, math.sin(angle) * M.PylonRadius)
		-- Face the centre (LookVector = -Z), then tip the top forward toward it.
		local facing = CFrame.lookAt(foot.Position, top.Position) * CFrame.Angles(-math.rad(M.PylonLeanDegrees), 0, 0)
		local pylon = PartKit.Part({
			Name = "Pylon",
			Size = M.PylonSize,
			CFrame = facing * CFrame.new(0, M.PylonSize.Y / 2, 0),
			Color = World.StructureLight,
			Parent = machine,
		})
		local strip = PartKit.Part({
			Name = "PylonStrip",
			Size = Vector3.new(M.PylonStripWidth, M.PylonSize.Y, M.PylonStripDepth),
			CFrame = pylon.CFrame * CFrame.new(0, 0, -(M.PylonSize.Z / 2 + M.PylonStripDepth / 2)),
			Color = ACCENT,
			Material = Enum.Material.Neon,
			Parent = machine,
		})
		PartKit.MakeDecorative(strip)
	end
end

local function buildCore(machine: Model, base: CFrame): BasePart
	local core = PartKit.Part({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * M.CoreDiameter,
		CFrame = base * CFrame.new(0, M.CoreY, 0),
		Color = ACCENT,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = machine,
	})
	local light = Instance.new("PointLight")
	light.Color = ACCENT
	light.Range = CORE_LIGHT_RANGE
	light.Brightness = CORE_LIGHT_BRIGHTNESS
	light.Parent = core

	local sparkle = SparkleEmitter.Create({ Color = ACCENT, Rate = CORE_SPARKLE_RATE })
	sparkle.Parent = core
	return core
end

-- A flat Neon disc with sparkle trails on its rim, centred on the Core;
-- RevealEffects spins it during a fusion so the trails orbit the core.
local function buildRing(machine: Model, core: BasePart)
	local ring = PartKit.Part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = M.RingSize,
		CFrame = CFrame.new(core.Position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = ACCENT,
		Material = Enum.Material.Neon,
		Transparency = RING_TRANSPARENCY,
		CanCollide = false,
		CanQuery = false,
		Parent = machine,
	})
	local radius = M.RingSize.Y / 2
	for index = 1, ORBIT_ATTACHMENT_COUNT do
		local angle = (index / ORBIT_ATTACHMENT_COUNT) * math.pi * 2
		local attachment = Instance.new("Attachment")
		attachment.Name = "OrbitAttachment" .. index
		attachment.Position = Vector3.new(0, math.cos(angle) * radius, math.sin(angle) * radius)
		attachment.Parent = ring

		local sparkle = SparkleEmitter.Create({ Color = ACCENT, Rate = ORBIT_SPARKLE_RATE })
		sparkle.Parent = attachment
	end
end

-- Invisible anchor at the platform centre for the prompts, so they show
-- where you stand rather than up at the core.
local function buildPromptAnchor(machine: Model, base: CFrame)
	local anchor = PartKit.Part({
		Name = "PromptAnchor",
		Size = Vector3.one,
		CFrame = base * CFrame.new(0, M.PromptAnchorY, 0),
		Color = ACCENT,
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		Parent = machine,
	})

	-- Left disabled until the owner's client confirms a fusable pair.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FusePrompt"
	prompt.ActionText = "Fuse"
	prompt.ObjectText = "Fusion Machine"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = M.PromptDistance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Enabled = false
	prompt.Parent = anchor

	-- Hold F: fuse every Common/Rare/Epic pair at once. The owner's client
	-- fills in "Fuse All (N)" and enables it when N >= 2.
	local fuseAll = Instance.new("ProximityPrompt")
	fuseAll.Name = "FuseAllPrompt"
	fuseAll.ActionText = "Fuse All"
	fuseAll.ObjectText = "Hold · Common, Rare, Epic"
	fuseAll.KeyboardKeyCode = Enum.KeyCode.F
	fuseAll.GamepadKeyCode = Enum.KeyCode.ButtonY
	fuseAll.HoldDuration = FUSE_ALL_HOLD_SECONDS
	fuseAll.MaxActivationDistance = M.PromptDistance
	fuseAll.RequiresLineOfSight = false
	fuseAll.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	fuseAll.UIOffset = Vector2.new(0, M.FuseAllPromptOffsetPx) -- stacked under FusePrompt
	fuseAll.Enabled = false
	fuseAll.Parent = anchor
end

-- Post + board facing the gate, yawed toward the walkway, with the odds on
-- a SurfaceGui. Not part of the machine Model (it stands beside it).
local function buildOddsBoard(originCFrame: CFrame, parent: Instance)
	local board = Instance.new("Model")
	board.Name = "OddsBoard"

	local foot = PartKit.At(originCFrame, PlotLayout.ODDS_BOARD, 0)
	-- Face +Z (the gate), turned toward the walkway. A part's Front face
	-- looks along its -Z, hence the half turn.
	local towardWalkway = if PlotLayout.ODDS_BOARD.X > PlotLayout.WALKWAY_X then -1 else 1
	local yaw = math.rad(PlotLayout.ODDS_BOARD_YAW_TOWARD_WALKWAY_DEGREES) * towardWalkway
	local facing = foot * CFrame.Angles(0, math.pi + yaw, 0)

	local post = M.OddsPostSize
	PartKit.Part({
		Name = "Post",
		Size = post,
		CFrame = facing * CFrame.new(0, post.Y / 2, 0),
		Color = World.StructureLight,
		Parent = board,
	})
	local boardPart = PartKit.Part({
		Name = "Board",
		Size = M.OddsBoardSize,
		CFrame = facing * CFrame.new(0, post.Y + M.OddsBoardSize.Y / 2, 0),
		Color = World.Structure,
		Parent = board,
	})

	-- The same formatter as the gacha pad (FusionConfig.FormatOdds). Base
	-- luck here; TycoonService refreshes the mutation line at the owner's
	-- luck on every sync.
	local odds = FusionConfig.FormatOdds(1)
	BillboardKit.OddsSurface(boardPart, odds.Fusion, "Mutations · " .. odds.FusionMutations, M.SurfacePixelsPerStud)

	board.Parent = parent
end

-- Builds one machine for a plot at plot-local `localPos` (floor top y = 0).
-- Returns the machine Model (already parented to `parent`).
function FusionMachineService.Build(originCFrame: CFrame, localPos: Vector3, parent: Instance): Model
	local machine = Instance.new("Model")
	machine.Name = FusionMachineService.MACHINE_NAME
	local base = PartKit.At(originCFrame, localPos, 0)

	buildPlatform(machine, base)
	buildPylons(machine, base)
	local core = buildCore(machine, base)
	buildRing(machine, core)
	buildPromptAnchor(machine, base)

	machine.PrimaryPart = core
	machine.Parent = parent
	buildOddsBoard(originCFrame, parent)
	return machine
end

function FusionMachineService:Init()
	-- Older builds put one shared machine directly in Workspace; remove it.
	local legacy = Workspace:FindFirstChild(FusionMachineService.MACHINE_NAME)
	if legacy then
		legacy:Destroy()
	end
end

return FusionMachineService
