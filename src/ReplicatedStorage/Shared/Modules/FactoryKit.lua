--!strict
--[[
	FactoryKit
	----------
	The factory line's static parts, built by TycoonService on claim:

	  * FactoryBelt  Belt-coloured SmoothPlastic strip along the left side,
	                 with a gold Neon edge strip down each long side. Purely
	                 decorative: anchored, walkable, no velocity.
	  * Collector    gold 6 x 0.4 x 6 pad in the back-left corner, Neon edge
	                 strips on all four sides and a gold PointLight.

	The cash balls that ride the belt are client-side only
	(FactoryController); the path helpers below are what it follows, so the
	server parts and the client balls can't drift apart.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)

local FactoryKit = {}

local World = UITheme.World

FactoryKit.BELT_NAME = "FactoryBelt"
FactoryKit.COLLECTOR_NAME = "Collector"

-- Plot-local point on the belt's centre line at `z`, on its top surface.
function FactoryKit.GetBeltPoint(z: number): Vector3
	local belt = PlotLayout.FactoryBelt
	return Vector3.new(belt.X, belt.Height, z)
end

-- Plot-local centre of the collector's top surface.
function FactoryKit.GetCollectorTop(): Vector3
	local collector = PlotLayout.Collector
	return Vector3.new(collector.Position.X, collector.Size.Y, collector.Position.Z)
end

local function edgeStrip(parent: BasePart, size: Vector3, offset: Vector3)
	local strip = PartKit.Part({
		Name = "Edge",
		Size = size,
		CFrame = parent.CFrame * CFrame.new(offset),
		Color = World.AccentGold,
		Material = Enum.Material.Neon,
		Parent = parent,
	})
	PartKit.MakeDecorative(strip)
end

local function buildBelt(origin: CFrame, parent: Instance)
	local belt = PlotLayout.FactoryBelt
	local length = PlotLayout.GetBeltLength()
	local part = PartKit.Part({
		Name = FactoryKit.BELT_NAME,
		Size = Vector3.new(belt.Width, belt.Height, length),
		CFrame = PartKit.At(origin, Vector3.new(belt.X, 0, (belt.StartZ + belt.EndZ) / 2), belt.Height / 2),
		Color = World.Belt,
		Parent = parent,
	})
	local edge = Vector3.new(belt.EdgeSize.X, belt.EdgeSize.Y, length)
	for _, side in { -1, 1 } do
		edgeStrip(part, edge, Vector3.new(side * (belt.Width / 2 - edge.X / 2), belt.Height / 2 + edge.Y / 2, 0))
	end
end

-- Returns the Collector part (the TycoonService label hangs off it).
local function buildCollector(origin: CFrame, parent: Instance): BasePart
	local c = PlotLayout.Collector
	local part = PartKit.Part({
		Name = FactoryKit.COLLECTOR_NAME,
		Size = c.Size,
		CFrame = PartKit.At(origin, c.Position, c.Size.Y / 2),
		Color = World.AccentGold,
		Parent = parent,
	})
	local y = c.Size.Y / 2 + c.EdgeHeight / 2
	local alongX = Vector3.new(c.Size.X, c.EdgeHeight, c.EdgeWidth)
	local alongZ = Vector3.new(c.EdgeWidth, c.EdgeHeight, c.Size.Z)
	for _, side in { -1, 1 } do
		edgeStrip(part, alongX, Vector3.new(0, y, side * (c.Size.Z / 2 - c.EdgeWidth / 2)))
		edgeStrip(part, alongZ, Vector3.new(side * (c.Size.X / 2 - c.EdgeWidth / 2), y, 0))
	end
	local light = Instance.new("PointLight")
	light.Name = "CollectorLight"
	light.Color = World.AccentGold
	light.Range = c.LightRange
	light.Brightness = c.LightBrightness
	light.Parent = part
	return part
end

-- Builds the belt and the collector into `parent`; returns the collector.
function FactoryKit.Build(origin: CFrame, parent: Instance): BasePart
	buildBelt(origin, parent)
	return buildCollector(origin, parent)
end

return FactoryKit
