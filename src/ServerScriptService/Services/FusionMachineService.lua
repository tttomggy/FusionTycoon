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
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)

local FusionMachineService = {}

FusionMachineService.Name = "FusionMachineService"

FusionMachineService.MACHINE_NAME = "FusionMachine"

-- Local offset from PlotOrigin along the plot row. Near edge = 95 - 12 = 83,
-- past the Gacha Pad (edge ~54) and well short of the next plot (140).
local MACHINE_ROW_OFFSET_STUDS = 95
local BASE_SIZE = Vector3.new(24, 2, 24)

-- Bridges Floor's row edge (PlotLayout.GetFloorRowEndLocalX()) to the Base.
local CONNECTOR_WIDTH_STUDS = 16
local CONNECTOR_THICKNESS_STUDS = 1
local CONNECTOR_OVERLAP_STUDS = 2

local CORE_SIZE = Vector3.new(4, 4, 4)
local RING_SIZE = Vector3.new(0.6, 9, 9) -- Cylinder shape: X = thickness, Y/Z = diameter
local ORBIT_ATTACHMENT_COUNT = 4
local ACCENT_COLOR = Color3.fromRGB(140, 70, 255)
local DARK_COLOR = Color3.fromRGB(22, 22, 27)

local PROMPT_MAX_ACTIVATION_DISTANCE = 10
-- Readable a little before the prompt is in range; hidden from across the map.
local ODDS_BILLBOARD_MAX_DISTANCE_STUDS = 24
local ODDS_BILLBOARD_OFFSET = Vector3.new(0, 9, 0)

local function buildBase(position: Vector3): BasePart
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = BASE_SIZE
	base.Anchored = true
	base.CanCollide = true
	base.Material = Enum.Material.Basalt
	base.Color = DARK_COLOR
	base.Position = position
	return base
end

local function buildConnectorWalkway(originCFrame: CFrame, originY: number): BasePart?
	local floorEdgeLocalX = PlotLayout.GetFloorRowEndLocalX()
	local baseNearEdgeLocalX = MACHINE_ROW_OFFSET_STUDS - BASE_SIZE.X / 2

	local startX = floorEdgeLocalX - CONNECTOR_OVERLAP_STUDS
	local endX = baseNearEdgeLocalX + CONNECTOR_OVERLAP_STUDS
	if endX <= startX then
		return nil
	end

	local sizeX = endX - startX
	local centerLocalX = (startX + endX) / 2
	local center = originCFrame:PointToWorldSpace(Vector3.new(centerLocalX, 0, 0))

	local connector = Instance.new("Part")
	connector.Name = "ConnectorWalkway"
	connector.Size = Vector3.new(sizeX, CONNECTOR_THICKNESS_STUDS, CONNECTOR_WIDTH_STUDS)
	connector.Anchored = true
	connector.CanCollide = true
	connector.Material = Enum.Material.Basalt
	connector.Color = DARK_COLOR
	connector.CFrame = CFrame.new(center.X, originY + CONNECTOR_THICKNESS_STUDS / 2, center.Z) * originCFrame.Rotation

	-- Two thin neon edge strips instead of an always-on-top Highlight, which
	-- drew the walkway's outline through walls from anywhere on the map.
	for _, side in { -1, 1 } do
		local strip = Instance.new("Part")
		strip.Name = "EdgeStrip"
		strip.Size = Vector3.new(sizeX, 0.2, 0.4)
		strip.Anchored = true
		strip.CanCollide = false
		strip.CanQuery = false
		strip.Material = Enum.Material.Neon
		strip.Color = ACCENT_COLOR
		strip.CFrame = connector.CFrame
			* CFrame.new(0, CONNECTOR_THICKNESS_STUDS / 2 + 0.1, side * (CONNECTOR_WIDTH_STUDS / 2 - 0.3))
		strip.Parent = connector
	end

	return connector
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

-- "Fusion Odds": what 2x of each tier turns into, and how likely.
local function buildOddsBillboard(anchor: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FusionOddsBillboard"
	billboard.Size = UDim2.fromOffset(230, 160)
	billboard.StudsOffset = ODDS_BILLBOARD_OFFSET
	billboard.MaxDistance = ODDS_BILLBOARD_MAX_DISTANCE_STUDS
	billboard.LightInfluence = 0
	billboard.Parent = anchor

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT_COLOR
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.Text = "FUSE 2 → 1 TIER UP"
	title.LayoutOrder = 0
	title.Parent = frame

	for index, tier in FusionConfig.TierOrder do
		local nextTier = FusionConfig.GetNextTier(tier)
		local chance = FusionConfig.SuccessChance[tier]
		if nextTier and chance then
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, 0, 0, 24)
			row.BackgroundTransparency = 1
			row.Font = Enum.Font.GothamBold
			row.TextColor3 = FusionConfig.TierAccentColors[nextTier] or Color3.new(1, 1, 1)
			row.TextScaled = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.LayoutOrder = index
			row.Text = ("2x %s → %s   %d%%"):format(tier, nextTier, math.floor(chance * 100 + 0.5))
			row.Parent = frame
		end
	end
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

-- Builds one machine for a plot, positioned from its PlotOrigin. Returns the
-- Model (already parented to `parent`).
function FusionMachineService.Build(originCFrame: CFrame, originY: number, parent: Instance): Model
	local machine = Instance.new("Model")
	machine.Name = FusionMachineService.MACHINE_NAME

	local basePosition = originCFrame:PointToWorldSpace(Vector3.new(MACHINE_ROW_OFFSET_STUDS, 0, 0))
	local base = buildBase(Vector3.new(basePosition.X, originY + BASE_SIZE.Y / 2, basePosition.Z))
	base.Parent = machine

	local core = buildCore(base)
	core.Parent = machine

	local ring = buildRing(core)
	ring.Parent = machine

	buildOddsBillboard(base)
	buildPrompt(core)

	local connector = buildConnectorWalkway(originCFrame, originY)
	if connector then
		connector.Parent = machine
	end

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
