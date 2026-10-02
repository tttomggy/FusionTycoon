--!strict
--[[
	DropperKit
	----------
	Builds a dropper Model at a plot-local spot, facing +X (toward the
	collector):

	  Body    4x6x4 Structure column, bottom at y 0 (Dropper 1 reuses the
	          template's Dropper1 part as its Body)
	  Hopper  a 5x2x5 funnel on top - a 4x2x4 core plus four upside-down
	          WedgeParts that flare it out to 5 wide - with a green Neon lip
	  Belt    a green Neon band around the body at y 3
	  Spout   a StructureLight block on the body's +X face at y 4.5; cash
	          balls leave from its outer face

	All numbers come from PlotLayout.Dropper. The Model's pivot is the
	bottom centre of the body, so StationKit can stand a ghost copy on a pad.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)

local DropperKit = {}

local D = PlotLayout.Dropper
local World = UITheme.World

local SIDES = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
}

local function decorative(part: BasePart): BasePart
	PartKit.MakeDecorative(part)
	return part
end

-- `base` is the world CFrame of the body's bottom centre (plot-aligned).
local function buildHopper(model: Model, base: CFrame)
	local body = D.BodySize
	local hopper = D.HopperSize
	local flare = (hopper.X - body.X) / 2
	local center = base * CFrame.new(0, body.Y + hopper.Y / 2, 0)

	PartKit.Part({
		Name = "Hopper",
		Size = Vector3.new(body.X, hopper.Y, body.Z),
		CFrame = center,
		Color = World.Structure,
		Parent = model,
	})

	for _, outward in SIDES do
		-- A WedgePart is tallest at its local +Z face with a flat bottom.
		-- Facing -Z outward and flipped about Z, it becomes flat on top and
		-- thin at the bottom: the funnel's flare.
		local position = center * CFrame.new(outward * (body.X / 2 + flare / 2))
		local facing = CFrame.lookAt(position.Position, position.Position + center:VectorToWorldSpace(outward))
		PartKit.Part({
			Name = "HopperFlare",
			ClassName = "WedgePart",
			Size = Vector3.new(hopper.X, hopper.Y, flare),
			CFrame = facing * CFrame.Angles(0, 0, math.pi),
			Color = World.Structure,
			Parent = model,
		})

		-- Green lip along the hopper's top edge.
		local along = Vector3.new(math.abs(outward.Z), 0, math.abs(outward.X))
		local lipSize = along * hopper.X + outward:Abs() * D.HopperLipHeight + Vector3.new(0, D.HopperLipHeight, 0)
		decorative(PartKit.Part({
			Name = "HopperLip",
			Size = lipSize,
			CFrame = center * CFrame.new(outward * (hopper.X / 2 - D.HopperLipHeight / 2) + Vector3.new(0, hopper.Y / 2 + D.HopperLipHeight / 2, 0)),
			Color = World.AccentGreen,
			Material = Enum.Material.Neon,
			Parent = model,
		}))
	end
end

-- Builds a dropper at plot-local `localPos`. Pass `body` to reuse an
-- existing part (the template's Dropper1) as the Body.
function DropperKit.Build(originCFrame: CFrame, localPos: Vector3, name: string, parent: Instance?, body: BasePart?): Model
	local model = Instance.new("Model")
	model.Name = name
	local base = PartKit.At(originCFrame, localPos, 0)
	local size = D.BodySize

	local bodyPart: BasePart
	if body then
		for _, child in body:GetChildren() do
			child:Destroy()
		end
		body.Size = size
		body.CFrame = base * CFrame.new(0, size.Y / 2, 0)
		body.Material = Enum.Material.SmoothPlastic
		body.Color = World.Structure
		body.Transparency = 0
		body.Anchored = true
		body.Parent = model
		bodyPart = body
	else
		bodyPart = PartKit.Part({
			Name = "Body",
			Size = size,
			CFrame = base * CFrame.new(0, size.Y / 2, 0),
			Color = World.Structure,
			Parent = model,
		})
	end
	bodyPart.Name = "Body"

	buildHopper(model, base)

	decorative(PartKit.Part({
		Name = "Belt",
		Size = Vector3.new(size.X + D.BeltInflate * 2, D.BeltHeight, size.Z + D.BeltInflate * 2),
		CFrame = base * CFrame.new(0, D.BeltY, 0),
		Color = World.AccentGreen,
		Material = Enum.Material.Neon,
		Parent = model,
	}))

	PartKit.Part({
		Name = "Spout",
		Size = Vector3.one * D.SpoutSize,
		CFrame = base * CFrame.new(size.X / 2 + D.SpoutSize / 2, D.SpoutY, 0),
		Color = World.StructureLight,
		Parent = model,
	})

	model.PrimaryPart = bodyPart
	model.WorldPivot = base
	model.Parent = parent
	return model
end

-- Where a cash ball spawns: just outside the spout's +X face.
function DropperKit.GetBallSpawn(model: Model): CFrame?
	local spout = model:FindFirstChild("Spout")
	if not spout or not spout:IsA("BasePart") then
		return nil
	end
	return spout.CFrame * CFrame.new(spout.Size.X / 2 + D.BallDiameter / 2, 0, 0)
end

return DropperKit
