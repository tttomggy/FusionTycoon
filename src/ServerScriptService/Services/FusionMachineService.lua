-- Builds the single, server-authoritative "Fusion Machine" every player
-- shares: a glowing core on a dark plinth, a spinning accent ring, a
-- ProximityPrompt players use to trigger a fusion, and a BillboardGui
-- disclosing live odds pulled straight from FusionConfig. There's no
-- pre-built Studio model for this (everything here is code so it stays
-- Rojo-friendly), so it's assembled once at server startup.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)

local FusionMachineService = {}

local MACHINE_NAME = "FusionMachine"

-- The machine is one object shared by every player, so unlike a per-plot
-- part it has no single PlotOrigin of its own to be a genuine offset from.
-- What it CAN be anchored to deterministically: TycoonService.createPlotForPlayer
-- sets each plot's PrimaryPart to its own PlotOrigin before pivoting it to
-- ((slotIndex - 1) * PLOT_SLOT_SPACING_STUDS, 0, 0) - so slot 1's PlotOrigin
-- always lands at EXACTLY world (0, 0, 0), by construction. Using that as the
-- reference point continues slot 1's own Dropper1/pad row (Dropper1 at +0,
-- Pedestal 4 at +60, edge at +62) along the same local +X axis and Z = 0.
--
-- 95 puts the machine's near edge (95 - 12 half-width = 83) about 21 studs
-- past Pedestal 4's edge - close enough to read as part of the same plot
-- instead of a separate area, comfortably inside Plot 2's row starting at
-- X = 140 (previously 100, which felt like a disconnected walk/bridge away).
--
-- Trade-off worth knowing: this means the shared machine sits authored right
-- next to ONE specific plot (whoever ends up in slot 1) rather than being
-- equidistant from every player's plot. That's an inherent limitation of
-- "one shared machine, positioned plot-relative" - if this ever needs to
-- scale to many concurrent players, the machine should probably become
-- per-plot instead (or move to a genuinely neutral hub position), not stay
-- anchored to slot 1.
local SLOT_1_PLOT_ORIGIN_WORLD_POSITION = Vector3.new(0, 0, 0)
local MACHINE_ROW_OFFSET_STUDS = 95
local BASE_SIZE = Vector3.new(24, 2, 24)
local MACHINE_POSITION = Vector3.new(
	SLOT_1_PLOT_ORIGIN_WORLD_POSITION.X + MACHINE_ROW_OFFSET_STUDS,
	SLOT_1_PLOT_ORIGIN_WORLD_POSITION.Y + BASE_SIZE.Y / 2,
	SLOT_1_PLOT_ORIGIN_WORLD_POSITION.Z
)

-- Bridges the open gap between Floor's row-covering edge (PlotLayout.
-- GetFloorRowEndLocalX(), local X = 78 now that the Gacha Pad extends the
-- row past Pedestal 4) and the machine's own Base (near edge at
-- MACHINE_ROW_OFFSET_STUDS - half-width = 83) - both ends
-- read from the same shared source as TycoonService's own Floor sizing, so
-- this can't silently drift out of alignment with wherever Floor's edge
-- actually ends up. Overlaps a couple studs into both Floor and the Base so
-- there's no visible seam at either end.
local CONNECTOR_WIDTH_STUDS = 16
local CONNECTOR_THICKNESS_STUDS = 1
local CONNECTOR_OVERLAP_STUDS = 2

local CORE_SIZE = Vector3.new(4, 4, 4)
local RING_SIZE = Vector3.new(0.6, 9, 9) -- Cylinder shape: X = thickness, Y/Z = diameter
local ORBIT_ATTACHMENT_COUNT = 4
local ACCENT_COLOR = Color3.fromRGB(140, 70, 255)

local PROMPT_MAX_ACTIVATION_DISTANCE = 10

local function buildBase(): BasePart
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = BASE_SIZE
	base.Anchored = true
	base.CanCollide = true
	base.Material = Enum.Material.Basalt
	base.Color = Color3.fromRGB(22, 22, 27)
	base.Position = MACHINE_POSITION
	return base
end

-- Returns nil if Floor's edge and the Base's near edge already meet or
-- overlap (nothing to bridge) - not expected with current constants, but a
-- future change to either one shouldn't produce a backwards/zero-size part.
local function buildConnectorWalkway(): BasePart?
	local floorEdgeLocalX = PlotLayout.GetFloorRowEndLocalX()
	local baseNearEdgeLocalX = MACHINE_ROW_OFFSET_STUDS - BASE_SIZE.X / 2

	local startX = floorEdgeLocalX - CONNECTOR_OVERLAP_STUDS
	local endX = baseNearEdgeLocalX + CONNECTOR_OVERLAP_STUDS
	if endX <= startX then
		return nil
	end

	local sizeX = endX - startX
	local centerLocalX = (startX + endX) / 2

	local connector = Instance.new("Part")
	connector.Name = "ConnectorWalkway"
	connector.Size = Vector3.new(sizeX, CONNECTOR_THICKNESS_STUDS, CONNECTOR_WIDTH_STUDS)
	connector.Anchored = true
	connector.CanCollide = true
	-- Dark Basalt base matches the machine's own Base/plinth (a deliberate
	-- "dark base + neon accent" language), but this only ever got the dark
	-- half - built purely to fix players falling into the Floor-to-machine
	-- gap, nobody circled back to give it the neon accent glow every other
	-- element in the game has. Highlight + PointLight below add that.
	connector.Material = Enum.Material.Basalt
	connector.Color = Color3.fromRGB(22, 22, 27)
	connector.Position = Vector3.new(
		SLOT_1_PLOT_ORIGIN_WORLD_POSITION.X + centerLocalX,
		SLOT_1_PLOT_ORIGIN_WORLD_POSITION.Y + CONNECTOR_THICKNESS_STUDS / 2,
		SLOT_1_PLOT_ORIGIN_WORLD_POSITION.Z
	)

	local highlight = Instance.new("Highlight")
	highlight.Name = "ConnectorHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = ACCENT_COLOR
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = connector

	local light = Instance.new("PointLight")
	light.Name = "ConnectorLight"
	light.Color = ACCENT_COLOR
	light.Range = math.max(sizeX, CONNECTOR_WIDTH_STUDS)
	light.Brightness = 4
	light.Parent = connector

	-- Diagnostic: confirms the actual applied values with real output, the
	-- same way we verified Dropper1 and CashDrop earlier tonight. Prints the
	-- accent glow (Highlight/Light), not just the base Material/Color -
	-- the base was already dark Basalt by design and isn't what changed;
	-- the Highlight/Light accent is the actual fix being verified here.
	print((
		"FusionMachineService: ConnectorWalkway styled - BaseMaterial=%s BaseColor=(%d,%d,%d) "
			.. "HighlightOutlineColor=(%d,%d,%d) LightColor=(%d,%d,%d) LightBrightness=%d"
	):format(
		tostring(connector.Material),
		math.floor(connector.Color.R * 255),
		math.floor(connector.Color.G * 255),
		math.floor(connector.Color.B * 255),
		math.floor(highlight.OutlineColor.R * 255),
		math.floor(highlight.OutlineColor.G * 255),
		math.floor(highlight.OutlineColor.B * 255),
		math.floor(light.Color.R * 255),
		math.floor(light.Color.G * 255),
		math.floor(light.Color.B * 255),
		light.Brightness
	))

	return connector
end

-- The Core is the machine's centerpiece (and the ProximityPrompt's anchor),
-- so it's styled by hand rather than via PadStyler: PadStyler's floating
-- accent orb + beveled-brick mesh are tuned for flat pad platforms and would
-- clip into/duplicate a spherical centerpiece like this one.
local function buildCore(base: BasePart): BasePart
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = CORE_SIZE
	core.Anchored = true
	core.CanCollide = false
	core.Material = Enum.Material.Neon
	core.Color = ACCENT_COLOR
	core.Position = base.Position + Vector3.new(0, base.Size.Y / 2 + CORE_SIZE.Y / 2, 0)

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = ACCENT_COLOR
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = core

	local light = Instance.new("PointLight")
	light.Color = ACCENT_COLOR
	light.Range = 28
	light.Brightness = 6
	light.Parent = core

	local sparkle = SparkleEmitter.Create({ Color = ACCENT_COLOR, Rate = 4 })
	sparkle.Parent = core

	return core
end

-- A flat neon disc with a handful of Attachments around its rim, each
-- carrying a sparkle trail. Attachments track their parent Part's CFrame
-- automatically, so spinning the Ring (see RevealEffects.PlayChargeUp on the
-- client) visibly drags the sparkle trails around with it - a "spinning
-- ring" that reads clearly even though the disc itself is rotationally
-- symmetric.
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
	-- The cylinder's axis runs along local X; rotating 90 degrees around Z
	-- lays it flat, like a ring/halo around the core, instead of standing up.
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

-- Mounted on the Base, offset slightly toward -X (the side players approach
-- from, since the machine sits at +MACHINE_ROW_OFFSET_STUDS along the plot
-- row). Previously pulled 10 studs toward the row at a low, human-scale
-- height (5) - reasonable back when the machine was 100 studs out, but once
-- it moved to +95 (~21 studs past Pedestal 4) that put the panel low enough
-- and far enough toward the row to visually overlap the Multiplier Pad's
-- billboard from typical viewing angles. Pulled back to a smaller X offset
-- and raised well above the Core's own top (which sits 5 studs above Base
-- center) so it's clearly a fixture ON the machine, vertically separated
-- from every ground-level pad label instead of competing with them.
local ODDS_BILLBOARD_OFFSET = Vector3.new(-4, 8, 0)

local function buildOddsBillboard(anchor: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FusionOddsBillboard"
	billboard.Size = UDim2.fromOffset(200, 170)
	billboard.StudsOffset = ODDS_BILLBOARD_OFFSET
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = frame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.Text = "Fusion Odds"
	title.LayoutOrder = 0
	title.Parent = frame

	for index, tier in FusionConfig.TierOrder do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, 0, 0, 20)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham
		row.TextColor3 = FusionConfig.TierAccentColors[tier] or Color3.new(1, 1, 1)
		row.TextScaled = true
		row.LayoutOrder = index
		row.Text = ("%s  %.1f%%"):format(tier, FusionConfig.DropRates[tier] * 100)
		row.Parent = frame
	end
end

-- Left disabled until the client confirms the local player actually has two
-- same-tier items to offer; see FusionController.
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

function FusionMachineService.Init()
	-- Rebuilt fresh on every server start rather than left alone if one
	-- already exists: skipping-when-present meant a machine built by an
	-- older version of this file (different position/size) would silently
	-- stick around forever instead of ever picking up a fix like this one.
	local existing = Workspace:FindFirstChild(MACHINE_NAME)
	if existing then
		existing:Destroy()
	end

	local machine = Instance.new("Model")
	machine.Name = MACHINE_NAME

	local base = buildBase()
	base.Parent = machine

	local core = buildCore(base)
	core.Parent = machine

	local ring = buildRing(core)
	ring.Parent = machine

	buildOddsBillboard(base)
	buildPrompt(core)

	local connector = buildConnectorWalkway()
	if connector then
		connector.Parent = machine
	end

	machine.PrimaryPart = core
	machine.Parent = Workspace

	print("FusionMachineService: Fusion Machine built")
end

return FusionMachineService
