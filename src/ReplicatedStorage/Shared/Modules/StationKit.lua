--!strict
--[[
	StationKit
	----------
	Builds a station: the round pad you walk up to for an E prompt (claim,
	Dropper 2, gacha, multiplier).

	  Pad       8-wide cylinder, Structure colour, top at y 1. Holds the
	            ProximityPrompt and the label. (The claim station passes the
	            template's ClaimButton in to become its Pad.)
	  Rim       a slightly wider Neon accent cylinder just under the pad top -
	            reads as a glowing ring.
	  Glow      a translucent Neon disc on top, with a PointLight.
	  Hologram  a floating accent shape above the pad (a Model tagged
	            FT_Hover; WorldAnimationController animates it on clients).

	All numbers come from PlotLayout.Station.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)

local StationKit = {}

export type Hologram = "Capsule" | "Chevrons" | "Arrow" | "Ghost"

local S = PlotLayout.Station
local World = UITheme.World

local setHover = PartKit.SetHover

local function decorative(part: BasePart): BasePart
	PartKit.MakeDecorative(part)
	return part
end

-- A filled up-pointing triangle ("^") of two WedgeParts, centred on `center`.
-- A WedgePart is tallest at its local +Z face; turning each half +-90 degrees
-- about Y puts both tall faces against the centre line.
local function upTriangle(parent: Instance, name: string, center: CFrame, width: number, height: number, depth: number, color: Color3)
	for _, side in { -1, 1 } do
		decorative(PartKit.Part({
			Name = name,
			ClassName = "WedgePart",
			Size = Vector3.new(depth, height, width / 2),
			CFrame = center * CFrame.new(side * width / 4, 0, 0) * CFrame.Angles(0, -side * math.pi / 2, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = parent,
		}))
	end
end

local function buildCapsule(model: Model, top: CFrame, accent: Color3)
	local center = top * CFrame.new(0, S.CapsuleY - S.PadTopY, 0)
	local diameter = S.CapsuleDiameter
	-- Two balls nudged apart vertically: each wins its own hemisphere, and a
	-- thin band hides the seam - visually a two-tone capsule.
	local nudge = S.CapsuleBandHeight / 2
	decorative(PartKit.Part({
		Name = "CapsuleTop",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = center * CFrame.new(0, nudge, 0),
		Color = accent,
		Material = Enum.Material.Neon,
		Parent = model,
	}))
	decorative(PartKit.Part({
		Name = "CapsuleBottom",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = center * CFrame.new(0, -nudge, 0),
		Color = World.CapsuleWhite,
		Parent = model,
	}))
	decorative(PartKit.Cylinder({
		Name = "CapsuleBand",
		Center = center,
		Height = S.CapsuleBandHeight,
		Diameter = diameter + S.CapsuleBandHeight,
		Color = World.Structure,
		Parent = model,
	}))
	setHover(model, S.CapsuleSpinDegPerSec, S.CapsuleBob, S.CapsuleBobPeriod, "Bob")
end

local function buildChevrons(model: Model, top: CFrame, accent: Color3)
	for index, y in S.ChevronYs do
		upTriangle(
			model,
			"Chevron" .. index,
			top * CFrame.new(0, y - S.PadTopY, 0),
			S.ChevronWidth,
			S.ChevronHeight,
			S.ChevronDepth,
			accent
		)
	end
	setHover(model, 0, S.ChevronRise, S.ChevronRisePeriod, "Rise")
end

local function buildArrow(model: Model, top: CFrame, accent: Color3)
	-- Built pointing up around its own centre, then flipped to point down.
	local center = top * CFrame.new(0, S.ArrowY - S.PadTopY, 0)
	local shaft = S.ArrowShaftSize
	local arrow = Instance.new("Model")
	arrow.Name = "Arrow"
	decorative(PartKit.Part({
		Name = "Shaft",
		Size = shaft,
		CFrame = center * CFrame.new(0, -S.ArrowHeadHeight / 2, 0),
		Color = accent,
		Material = Enum.Material.Neon,
		Parent = arrow,
	}))
	upTriangle(
		arrow,
		"Head",
		center * CFrame.new(0, shaft.Y / 2, 0),
		S.ArrowHeadWidth,
		S.ArrowHeadHeight,
		shaft.Z,
		accent
	)
	arrow.WorldPivot = center
	arrow:PivotTo(center * CFrame.Angles(0, 0, math.pi))
	for _, part in arrow:GetChildren() do
		part.Parent = model
	end
	arrow:Destroy()
	setHover(model, 0, S.ArrowBob, S.ArrowBobPeriod, "Bob")
end

-- `ghost` is a dropper Model to show translucent on the pad (Dropper 2 slot).
local function buildGhost(model: Model, top: CFrame, accent: Color3, ghost: Model?)
	if not ghost then
		return
	end
	ghost:PivotTo(top)
	for _, descendant in ghost:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Material = Enum.Material.ForceField
			descendant.Color = accent
			descendant.Transparency = S.GhostTransparency
			PartKit.MakeDecorative(descendant)
		end
	end
	ghost.Name = "Ghost"
	ghost.Parent = model
end

export type BuildOptions = {
	Pad: BasePart?, -- reuse this part as the Pad (the claim station's ClaimButton)
	Ghost: Model?, -- the model shown for the "Ghost" hologram
}

-- Builds a station at plot-local `localPos` (floor top y = 0) and returns
-- the Model. Name it yourself; `Model.Pad` holds the prompt and label.
function StationKit.Build(
	originCFrame: CFrame,
	localPos: Vector3,
	accent: Color3,
	hologram: Hologram,
	parent: Instance,
	options: BuildOptions?
): Model
	local model = Instance.new("Model")
	model.Name = "Station"

	local base = PartKit.At(originCFrame, localPos, 0)
	local top = base * CFrame.new(0, S.PadTopY, 0)

	local padCenter = top * CFrame.new(0, -S.PadHeight / 2, 0)
	local pad: BasePart
	local existing = options and options.Pad
	if existing and existing:IsA("Part") then
		existing.Shape = Enum.PartType.Cylinder
		existing.Size = Vector3.new(S.PadHeight, S.PadDiameter, S.PadDiameter)
		existing.CFrame = padCenter * CFrame.Angles(0, 0, math.rad(90))
		existing.Material = Enum.Material.SmoothPlastic
		existing.Color = World.Structure
		existing.Transparency = 0
		existing.Anchored = true
		existing.CanCollide = true
		existing.Parent = model
		pad = existing
	else
		pad = PartKit.Cylinder({
			Name = "Pad",
			Center = padCenter,
			Height = S.PadHeight,
			Diameter = S.PadDiameter,
			Color = World.Structure,
			Parent = model,
		})
	end
	pad.Name = "Pad"

	PartKit.Cylinder({
		Name = "Rim",
		Center = top * CFrame.new(0, -S.RimCenterBelowTop, 0),
		Height = S.RimHeight,
		Diameter = S.RimDiameter,
		Color = accent,
		Material = Enum.Material.Neon,
		CanQuery = false,
		Parent = model,
	})

	local glow = decorative(PartKit.Cylinder({
		Name = "Glow",
		Center = top * CFrame.new(0, S.GlowHeight / 2, 0),
		Height = S.GlowHeight,
		Diameter = S.GlowDiameter,
		Color = accent,
		Material = Enum.Material.Neon,
		Transparency = S.GlowTransparency,
		Parent = model,
	}))
	local light = Instance.new("PointLight")
	light.Color = accent
	light.Brightness = S.LightBrightness
	light.Range = S.LightRange
	light.Parent = glow

	local holo = Instance.new("Model")
	holo.Name = "Hologram"
	if hologram == "Capsule" then
		buildCapsule(holo, top, accent)
	elseif hologram == "Chevrons" then
		buildChevrons(holo, top, accent)
	elseif hologram == "Arrow" then
		buildArrow(holo, top, accent)
	elseif hologram == "Ghost" then
		buildGhost(holo, top, accent, options and options.Ghost)
	end
	holo.Parent = model

	model.PrimaryPart = pad
	model.Parent = parent
	return model
end

return StationKit
