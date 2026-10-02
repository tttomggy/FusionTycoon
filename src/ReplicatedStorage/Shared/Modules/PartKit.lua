--!strict
--[[
	PartKit
	-------
	Small helpers for building world geometry in code: anchored SmoothPlastic
	parts by default (the world's only solid material; accents pass Neon),
	vertical cylinders, and plot-local placement. Positions and sizes come
	from the caller (PlotLayout); this module only knows how to make parts.
]]
local PartKit = {}

export type PartProps = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3,
	Parent: Instance?,
	ClassName: string?, -- "Part" (default) or "WedgePart"
	Shape: Enum.PartType?,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	CastShadow: boolean?,
}

function PartKit.Part(props: PartProps): BasePart
	local part = Instance.new(props.ClassName or "Part") :: BasePart
	part.Name = props.Name
	if props.Shape and part:IsA("Part") then
		part.Shape = props.Shape
	end
	part.Size = props.Size
	part.CFrame = props.CFrame
	part.Color = props.Color
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.Anchored = true
	part.CanCollide = if props.CanCollide == nil then true else props.CanCollide
	part.CanQuery = if props.CanQuery == nil then true else props.CanQuery
	part.CanTouch = if props.CanTouch == nil then true else props.CanTouch
	if props.CastShadow ~= nil then
		part.CastShadow = props.CastShadow
	end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = props.Parent
	return part
end

-- Roblox cylinders run along X; this stands one upright, centred on `center`.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

export type CylinderProps = {
	Name: string,
	Center: CFrame, -- centre of the cylinder (its own orientation is upright)
	Height: number,
	Diameter: number,
	Color: Color3,
	Parent: Instance?,
	Material: Enum.Material?,
	Transparency: number?,
	CanCollide: boolean?,
	CanQuery: boolean?,
	CanTouch: boolean?,
	CastShadow: boolean?,
}

function PartKit.Cylinder(props: CylinderProps): BasePart
	return PartKit.Part({
		Name = props.Name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(props.Height, props.Diameter, props.Diameter),
		CFrame = props.Center * UPRIGHT,
		Color = props.Color,
		Parent = props.Parent,
		Material = props.Material,
		Transparency = props.Transparency,
		CanCollide = props.CanCollide,
		CanQuery = props.CanQuery,
		CanTouch = props.CanTouch,
		CastShadow = props.CastShadow,
	})
end

-- Plot-local (localPos.X, y, localPos.Z) as a world CFrame aligned with the plot.
function PartKit.At(origin: CFrame, localPos: Vector3, y: number?): CFrame
	return origin * CFrame.new(localPos.X, y or localPos.Y, localPos.Z)
end

-- Parts/Models with this tag float and spin on clients
-- (WorldAnimationController); the attributes below drive the motion.
PartKit.HOVER_TAG = "FT_Hover"

-- mode "Bob": sine bob of `bob` studs per `period`; "Rise": move up `bob`
-- studs over `period`, then snap back.
function PartKit.SetHover(target: Instance, spinDegPerSec: number, bob: number, period: number, mode: string)
	target:SetAttribute("SpinDegPerSec", spinDegPerSec)
	target:SetAttribute("BobStuds", bob)
	target:SetAttribute("BobPeriod", period)
	target:SetAttribute("Mode", mode)
	target:AddTag(PartKit.HOVER_TAG)
end

-- Decorative parts (holograms, glows): no collision, no queries, no touches.
function PartKit.MakeDecorative(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

return PartKit
