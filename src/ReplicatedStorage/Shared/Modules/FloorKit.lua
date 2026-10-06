--!strict
--[[
	FloorKit
	--------
	Builds a lab's 2nd floor (built once per plot by TycoonService, every
	lab, locked or not; pedestals 7-10 are built with the others):

	  Deck        a SmoothPlastic slab over the back-left of the lab, with
	              a thin Neon band along its open edges' faces (side-on).
	  Columns     SmoothPlastic posts under its free corners.
	  Railings    SmoothPlastic posts and a thin Neon top rail round every
	              edge, with a gap in the front over the jump pad.
	  JumpPad     a low SmoothPlastic disc on the floor with a SurfaceGui
	              ring face (BillboardKit.BuildPadFace, never a flat Neon
	              disc), tagged FT_JumpPad: every client launches its own
	              character from it (JumpPadController).
	  LockLabel   the owner-only "🔒 2ND FLOOR · Rebirth 2" chip over the
	              deck, shown while it's locked (FloorKit.SetLocked).

	Every number comes from PlotLayout.Floor2. SetLocked dims the rails
	and the band (StructureLight) and turns the label on; unlocked they're
	the lab's violet.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)

local FloorKit = {}

FloorKit.MODEL_NAME = "SecondFloor"
FloorKit.JUMP_PAD_TAG = "FT_JumpPad"
-- Parts recoloured by SetLocked (the Neon rails and edge band).
local ACCENT_ATTRIBUTE = "Floor2Accent"

local World = UITheme.World

local function v3(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- One straight railing from `a` to `b` (plot-local, on the deck top):
-- posts every RailPostSpacing and a Neon rail along the top.
local function buildRail(model: Model, origin: CFrame, name: string, a: Vector3, b: Vector3)
	local f2 = PlotLayout.Floor2
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	local direction = (b - a).Unit
	local posts = math.max(1, math.ceil(length / f2.RailPostSpacing))
	for i = 0, posts do
		local point = a + direction * (length * i / posts)
		PartKit.Part({
			Name = name .. "Post" .. i,
			Size = v3(f2.RailPostSize, f2.RailHeight, f2.RailPostSize),
			CFrame = PartKit.At(origin, point, f2.TopY + f2.RailHeight / 2),
			Color = World.StructureLight,
			Parent = model,
		})
	end
	local middle = (a + b) / 2
	local yaw = math.atan2(-direction.Z, direction.X)
	local rail = PartKit.Part({
		Name = name .. "Rail",
		Size = v3(length + f2.RailPostSize, f2.RailThickness, f2.RailThickness),
		CFrame = PartKit.At(origin, middle, f2.TopY + f2.RailHeight) * CFrame.Angles(0, yaw, 0),
		Color = World.AccentViolet,
		Material = Enum.Material.Neon,
		CastShadow = false,
		Parent = model,
	})
	rail:SetAttribute(ACCENT_ATTRIBUTE, true)
end

-- Builds the 2nd floor into `parent` (the plot) and returns the model.
function FloorKit.Build(origin: CFrame, parent: Instance): Model
	local f2 = PlotLayout.Floor2
	local model = Instance.new("Model")
	model.Name = FloorKit.MODEL_NAME

	local sizeX, sizeZ = f2.MaxX - f2.MinX, f2.MaxZ - f2.MinZ
	local center = v3((f2.MinX + f2.MaxX) / 2, 0, (f2.MinZ + f2.MaxZ) / 2)
	PartKit.Part({
		Name = "Deck",
		Size = v3(sizeX, f2.Thickness, sizeZ),
		CFrame = PartKit.At(origin, center, f2.TopY - f2.Thickness / 2),
		Color = World.Floor,
		Parent = model,
	})
	-- The Neon band along the two open edges' faces (front and right),
	-- just proud of the slab so it reads from below.
	local bandY = f2.TopY - f2.Thickness / 2
	local front = PartKit.Part({
		Name = "FrontBand",
		Size = v3(sizeX, f2.EdgeStripHeight, 0.1),
		CFrame = PartKit.At(origin, v3(center.X, 0, f2.MaxZ + 0.05), bandY),
		Color = World.AccentViolet,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = model,
	})
	front:SetAttribute(ACCENT_ATTRIBUTE, true)
	local side = PartKit.Part({
		Name = "SideBand",
		Size = v3(0.1, f2.EdgeStripHeight, sizeZ),
		CFrame = PartKit.At(origin, v3(f2.MaxX + 0.05, 0, center.Z), bandY),
		Color = World.AccentViolet,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		Parent = model,
	})
	side:SetAttribute(ACCENT_ATTRIBUTE, true)

	local columnHeight = f2.TopY - f2.Thickness
	for index, column in f2.Columns do
		PartKit.Part({
			Name = "Column" .. index,
			Size = v3(f2.ColumnSize, columnHeight, f2.ColumnSize),
			CFrame = PartKit.At(origin, column, columnHeight / 2),
			Color = World.Structure,
			Parent = model,
		})
	end

	-- Railings on every edge (the back and left ones stand just inside the
	-- low plot walls), the front one split round the landing gap.
	local inset = f2.RailInset
	local minX, maxX = f2.MinX + inset, f2.MaxX - inset
	local minZ, maxZ = f2.MinZ + inset, f2.MaxZ - inset
	buildRail(model, origin, "Back", v3(minX, 0, minZ), v3(maxX, 0, minZ))
	buildRail(model, origin, "Left", v3(minX, 0, minZ), v3(minX, 0, maxZ))
	buildRail(model, origin, "Right", v3(maxX, 0, minZ), v3(maxX, 0, maxZ))
	buildRail(model, origin, "FrontA", v3(minX, 0, maxZ), v3(f2.LandingMinX, 0, maxZ))
	buildRail(model, origin, "FrontB", v3(f2.LandingMaxX, 0, maxZ), v3(maxX, 0, maxZ))

	-- The jump pad: a low disc with a ring face; clients do the launch.
	local jp = f2.JumpPad
	local pad = PartKit.Cylinder({
		Name = "JumpPad",
		Center = PartKit.At(origin, jp.Position, jp.Height / 2),
		Height = jp.Height,
		Diameter = jp.Radius * 2,
		Color = World.Structure,
		Parent = model,
	})
	-- World-space, so clients needn't know the plot's facing.
	pad:SetAttribute("LaunchVelocity", origin:VectorToWorldSpace(jp.LaunchVelocity))
	pad:SetAttribute("Radius", jp.Radius)
	pad:AddTag(FloorKit.JUMP_PAD_TAG)
	BillboardKit.BuildPadFace(model, PartKit.At(origin, jp.Position, jp.Height), jp.Radius * 2, World.AccentBlue, "⬆")
	BillboardKit.Chip(pad, {
		Name = "JumpLabel",
		Text = "⬆ 2ND FLOOR",
		Studs = Vector2.new(5, 1.2),
		StudsOffset = v3(0, jp.LabelOffsetY, 0),
		MaxDistance = jp.LabelMaxDistance,
	})

	-- The owner-only lock label over the deck (shown while locked).
	local anchor = PartKit.Part({
		Name = "LabelAnchor",
		Size = Vector3.one * 0.2,
		CFrame = PartKit.At(origin, center, f2.TopY + f2.LabelOffsetY),
		Color = World.Structure,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = model,
	})
	local chip = BillboardKit.Chip(anchor, {
		Name = "LockLabel",
		Text = ("🔒 2ND FLOOR · Rebirth %d"):format(RebirthConfig.SecondFloorRebirths),
		Gradient = UITheme.Gradients.Orange,
		Studs = Vector2.new(10, 1.8),
		MaxDistance = f2.LabelMaxDistance,
	})
	chip.Gui:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)

	model.Parent = parent
	return model
end

-- Dims the rails and band and shows the lock label (locked), or lights
-- them in the lab's violet and hides it.
function FloorKit.SetLocked(model: Instance, locked: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute(ACCENT_ATTRIBUTE) then
			part.Color = if locked then World.StructureLight else World.AccentViolet
			part.Material = if locked then Enum.Material.SmoothPlastic else Enum.Material.Neon
		end
	end
	local anchor = model:FindFirstChild("LabelAnchor")
	local label = anchor and anchor:FindFirstChild("LockLabel")
	if label and label:IsA("BillboardGui") then
		label.Enabled = locked
	end
	model:SetAttribute("Locked", locked)
end

return FloorKit
