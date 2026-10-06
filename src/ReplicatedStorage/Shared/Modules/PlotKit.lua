--!strict
--[[
	PlotKit
	-------
	The plot "shell" shared by real plots (TycoonService) and empty-slot
	placeholders (WorldService): floor, walkway inlay, rim walls with their
	Neon strip, the gate ramp, and the plot sign gate. Everything is placed
	in plot-local space from PlotLayout.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)

local PlotKit = {}

local World = UITheme.World

PlotKit.WALL_STRIP_TAG = "FT_WallStrip"

-- Sizes/places `floor` (or a new part) as the 64x64 plot floor, top at y 0.
function PlotKit.BuildFloor(origin: CFrame, parent: Instance, floor: BasePart?): BasePart
	local size = PlotLayout.FLOOR_SIZE
	local cframe = PartKit.At(origin, Vector3.zero, -size.Y / 2)
	local part: BasePart
	if floor then
		floor.Size = size
		floor.CFrame = cframe
		floor.Material = Enum.Material.SmoothPlastic
		floor.Color = World.Floor
		floor.Anchored = true
		floor.Parent = parent
		part = floor
	else
		part = PartKit.Part({ Name = "Floor", Size = size, CFrame = cframe, Color = World.Floor, Parent = parent })
	end
	return part
end

function PlotKit.BuildWalkway(origin: CFrame, parent: Instance): BasePart
	local length = PlotLayout.WALKWAY_Z_MAX - PlotLayout.WALKWAY_Z_MIN
	return PartKit.Part({
		Name = "Walkway",
		Size = Vector3.new(PlotLayout.WALKWAY_WIDTH, PlotLayout.WALKWAY_THICKNESS, length),
		CFrame = PartKit.At(
			origin,
			Vector3.new(PlotLayout.WALKWAY_X, 0, (PlotLayout.WALKWAY_Z_MIN + PlotLayout.WALKWAY_Z_MAX) / 2),
			PlotLayout.WALKWAY_TOP_Y - PlotLayout.WALKWAY_THICKNESS / 2
		),
		Color = World.Walkway,
		CanCollide = false,
		CanQuery = false,
		Parent = parent,
	})
end

-- Rim walls just inside the floor edge (front wall split by the gate gap),
-- each with a Neon strip on top. Returns the "Walls" folder.
function PlotKit.BuildWalls(origin: CFrame, parent: Instance, claimed: boolean): Folder
	local walls = Instance.new("Folder")
	walls.Name = "Walls"

	local half = PlotLayout.PLOT_HALF
	local thickness = PlotLayout.WALL_THICKNESS
	local inset = half - thickness / 2
	local inner = half - thickness
	local gate = PlotLayout.GATE_HALF_WIDTH
	local frontSegment = half - gate
	local segments = {
		{ Name = "BackWall", Center = Vector3.new(0, 0, -inset), Length = Vector3.new(PlotLayout.FLOOR_SIZE.X, 0, thickness) },
		{ Name = "LeftWall", Center = Vector3.new(-inset, 0, 0), Length = Vector3.new(thickness, 0, inner * 2) },
		{ Name = "RightWall", Center = Vector3.new(inset, 0, 0), Length = Vector3.new(thickness, 0, inner * 2) },
		{ Name = "FrontWallLeft", Center = Vector3.new(-(gate + frontSegment / 2), 0, inset), Length = Vector3.new(frontSegment, 0, thickness) },
		{ Name = "FrontWallRight", Center = Vector3.new(gate + frontSegment / 2, 0, inset), Length = Vector3.new(frontSegment, 0, thickness) },
	}
	for _, segment in segments do
		PartKit.Part({
			Name = segment.Name,
			Size = Vector3.new(segment.Length.X, PlotLayout.WALL_HEIGHT, segment.Length.Z),
			CFrame = PartKit.At(origin, segment.Center, PlotLayout.WALL_HEIGHT / 2),
			Color = World.Structure,
			Parent = walls,
		})
		local strip = PartKit.Part({
			Name = "WallStrip",
			-- Full wall length, but only WALL_STRIP_WIDTH across the wall top.
			Size = Vector3.new(
				if segment.Length.X > segment.Length.Z then segment.Length.X else PlotLayout.WALL_STRIP_WIDTH,
				PlotLayout.WALL_STRIP_HEIGHT,
				if segment.Length.Z > segment.Length.X then segment.Length.Z else PlotLayout.WALL_STRIP_WIDTH
			),
			CFrame = PartKit.At(origin, segment.Center, PlotLayout.WALL_HEIGHT + PlotLayout.WALL_STRIP_HEIGHT / 2),
			Color = if claimed then World.AccentViolet else World.Unclaimed,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = walls,
		})
		strip:AddTag(PlotKit.WALL_STRIP_TAG)
		-- The VIP pass's gold trim: a thin band along the top of the wall's
		-- outer face, hidden until ApplyLabLook shows it.
		local alongX = segment.Length.X > segment.Length.Z
		local outward = if alongX
			then Vector3.new(0, 0, math.sign(segment.Center.Z))
			else Vector3.new(math.sign(segment.Center.X), 0, 0)
		local depth = PlotLayout.VipTrimDepth
		local trim = PartKit.Part({
			Name = "VipTrim",
			Size = Vector3.new(
				if alongX then segment.Length.X else depth,
				PlotLayout.VipTrimHeight,
				if alongX then depth else segment.Length.Z
			),
			CFrame = PartKit.At(
				origin,
				segment.Center + outward * (thickness / 2 + depth / 2),
				PlotLayout.WALL_HEIGHT - PlotLayout.VipTrimHeight / 2
			),
			Color = World.VipGold,
			Material = Enum.Material.Neon,
			Transparency = 1,
			CanCollide = false,
			Parent = walls,
		})
		PartKit.MakeDecorative(trim)
		trim:AddTag(PlotKit.VIP_TRIM_TAG)
	end

	walls.Parent = parent
	return walls
end

-- Parts of the lab shield carry this attribute; clients show and hide them
-- from the plot's ShieldUntil (HeistController), so they start invisible.
PlotKit.SHIELD_PART_ATTRIBUTE = "ShieldPart"

-- The lab shield, built hidden: ForceField panels just outside all four
-- walls (the front split around the gate) and a thin Neon line across the
-- gate gap. ForceField is the one material allowed outside SmoothPlastic /
-- Neon (CLAUDE.md). Nothing collides: HeistService's eject loop keeps
-- intruders out.
function PlotKit.BuildShieldFence(origin: CFrame, parent: Instance): Folder
	local f = PlotLayout.ShieldFence
	local fence = Instance.new("Folder")
	fence.Name = "ShieldFence"

	local half = PlotLayout.PLOT_HALF
	local gate = PlotLayout.GATE_HALF_WIDTH
	local centerLine = half + f.OutsetFromWall + f.Thickness / 2
	local outerEdge = half + f.OutsetFromWall + f.Thickness
	local frontLength = outerEdge - gate
	local panels = {
		{ Name = "ShieldBack", Center = Vector3.new(0, 0, -centerLine), Size = Vector3.new(outerEdge * 2, f.Height, f.Thickness) },
		{ Name = "ShieldLeft", Center = Vector3.new(-centerLine, 0, 0), Size = Vector3.new(f.Thickness, f.Height, outerEdge * 2) },
		{ Name = "ShieldRight", Center = Vector3.new(centerLine, 0, 0), Size = Vector3.new(f.Thickness, f.Height, outerEdge * 2) },
		{ Name = "ShieldFrontLeft", Center = Vector3.new(-(gate + frontLength / 2), 0, centerLine), Size = Vector3.new(frontLength, f.Height, f.Thickness) },
		{ Name = "ShieldFrontRight", Center = Vector3.new(gate + frontLength / 2, 0, centerLine), Size = Vector3.new(frontLength, f.Height, f.Thickness) },
	}
	for _, panel in panels do
		local part = PartKit.Part({
			Name = panel.Name,
			Size = panel.Size,
			CFrame = PartKit.At(origin, panel.Center, f.Height / 2),
			Color = World.ShieldBright,
			Material = Enum.Material.ForceField,
			Transparency = 1,
			Parent = fence,
		})
		PartKit.MakeDecorative(part)
		part:SetAttribute(PlotKit.SHIELD_PART_ATTRIBUTE, true)
		-- The glowing top edge, so the wall's height reads from anywhere.
		local edge = PartKit.Part({
			Name = panel.Name .. "Top",
			Size = Vector3.new(panel.Size.X, f.TopEdgeHeight, panel.Size.Z),
			CFrame = PartKit.At(origin, panel.Center, f.Height - f.TopEdgeHeight / 2),
			Color = World.Shield,
			Material = Enum.Material.Neon,
			Transparency = 1,
			Parent = fence,
		})
		PartKit.MakeDecorative(edge)
		edge:SetAttribute(PlotKit.SHIELD_PART_ATTRIBUTE, true)
	end
	local line = PartKit.Part({
		Name = "ShieldGateLine",
		Size = Vector3.new(gate * 2, f.GateLineThickness, f.GateLineThickness),
		CFrame = PartKit.At(origin, Vector3.new(0, 0, half - PlotLayout.WALL_THICKNESS / 2), f.GateLineY),
		Color = World.Shield,
		Material = Enum.Material.Neon,
		Transparency = 1,
		Parent = fence,
	})
	PartKit.MakeDecorative(line)
	line:SetAttribute(PlotKit.SHIELD_PART_ATTRIBUTE, true)

	fence.Parent = parent
	return fence
end

PlotKit.VIP_TRIM_TAG = "FT_VipTrim"

-- The owner's lab look from the shop: Neon Pink strips (LabStyle, looks
-- only) and the VIP gold trim (sign border + the hidden wall trims). Call
-- after the plot is claimed; violet / Ink when neither.
function PlotKit.ApplyLabLook(plot: Instance, pink: boolean, vip: boolean)
	local accent = if pink then World.AccentPink else World.AccentViolet
	local walls = plot:FindFirstChild("Walls")
	if walls then
		for _, part in walls:GetChildren() do
			if part:IsA("BasePart") then
				if part:HasTag(PlotKit.WALL_STRIP_TAG) then
					part.Color = accent
				elseif part:HasTag(PlotKit.VIP_TRIM_TAG) then
					part.Transparency = if vip then 0 else 1
				end
			end
		end
	end
	local gate = plot:FindFirstChild("SignGate")
	if gate then
		local strip = gate:FindFirstChild("SignStrip")
		if strip and strip:IsA("BasePart") then
			strip.Color = accent
		end
		local border = gate:FindFirstChild("SignBorder")
		if border and border:IsA("BasePart") then
			border.Color = if vip then World.VipGold else UITheme.Colors.Ink
			border.Material = if vip then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

-- Violet once claimed, Unclaimed before.
function PlotKit.SetWallStripsClaimed(plot: Instance, claimed: boolean)
	local walls = plot:FindFirstChild("Walls")
	if not walls then
		return
	end
	for _, strip in walls:GetChildren() do
		if strip:IsA("BasePart") and strip:HasTag(PlotKit.WALL_STRIP_TAG) then
			strip.Color = if claimed then World.AccentViolet else World.Unclaimed
		end
	end
end

-- A wedge from street level up to the floor, outside the gate gap. A
-- WedgePart is tallest at its local +Z face, so it's turned to put that
-- face against the floor edge.
function PlotKit.BuildGateRamp(origin: CFrame, parent: Instance): BasePart
	return PartKit.Part({
		Name = "GateRamp",
		ClassName = "WedgePart",
		Size = Vector3.new(PlotLayout.GATE_RAMP_WIDTH, PlotLayout.GATE_RAMP_HEIGHT, PlotLayout.GATE_RAMP_LENGTH),
		CFrame = PartKit.At(origin, Vector3.new(0, 0, PlotLayout.PLOT_HALF + PlotLayout.GATE_RAMP_LENGTH / 2), -PlotLayout.GATE_RAMP_HEIGHT / 2)
			* CFrame.Angles(0, math.pi, 0),
		Color = World.Structure,
		Parent = parent,
	})
end

-- Two posts at (+-9, +32) with a sign board spanning the gate: Ink border,
-- violet Neon strip underneath, and the sign on both faces. Returns the
-- setter for the sign's two lines.
function PlotKit.BuildSignGate(origin: CFrame, parent: Instance): BillboardKit.SignSurface
	local g = PlotLayout.Gate
	local gate = Instance.new("Model")
	gate.Name = "SignGate"

	for _, side in { -1, 1 } do
		PartKit.Part({
			Name = "Post",
			Size = g.PostSize,
			CFrame = PartKit.At(origin, Vector3.new(side * PlotLayout.SIGN_POST_X, 0, PlotLayout.SIGN_Z), g.PostSize.Y / 2),
			Color = World.StructureLight,
			Parent = gate,
		})
	end

	local boardCenter = PartKit.At(origin, Vector3.new(0, 0, PlotLayout.SIGN_Z), g.BoardCenterY)
	local board = PartKit.Part({
		Name = "SignBoard",
		Size = g.BoardSize,
		CFrame = boardCenter,
		Color = World.Structure,
		Parent = gate,
	})
	-- Thinner than the board but larger in face area: shows as a rim
	-- around it from both sides.
	PartKit.Part({
		Name = "SignBorder",
		Size = g.BorderSize,
		CFrame = boardCenter,
		Color = UITheme.Colors.Ink,
		Parent = gate,
	})
	local strip = PartKit.Part({
		Name = "SignStrip",
		Size = g.StripSize,
		CFrame = boardCenter * CFrame.new(0, -(g.BoardSize.Y / 2 + g.StripSize.Y / 2), 0),
		Color = World.AccentViolet,
		Material = Enum.Material.Neon,
		Parent = gate,
	})
	PartKit.MakeDecorative(strip)

	gate.Parent = parent
	return BillboardKit.SignSurface(board, g.SurfacePixelsPerStud)
end

return PlotKit
