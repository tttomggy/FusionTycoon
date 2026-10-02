--!strict
--[[
	WorldService
	------------
	Builds the shared world once at server start: the grass ground, the
	street between the two rows of plots with its lane dashes, and a
	placeholder foundation ("FREE LAB") on every plot slot nobody has taken.
	Removes the default Baseplate if the place still has one.

	TycoonService tells it when a slot is taken or freed
	(WorldService.SetSlotOccupied); the placeholder is destroyed while a
	player's plot stands there and rebuilt when they leave.

	Every position and size comes from PlotLayout.

	Lifecycle: :Init() builds the world and every placeholder (self-contained,
	no other services). No :Start().
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local PlotKit = require(ReplicatedStorage.Shared.Modules.PlotKit)

local WorldService = {}

WorldService.Name = "WorldService"

local World = UITheme.World

type State = {
	worldFolder: Folder?,
	placeholders: { [number]: Model },
	occupied: { [number]: boolean },
}

local state: State = {
	worldFolder = nil,
	placeholders = {},
	occupied = {},
}

local function buildGroundAndStreet(folder: Folder)
	local ground = PlotLayout.GROUND_SIZE
	PartKit.Part({
		Name = "Ground",
		Size = ground,
		CFrame = CFrame.new(0, PlotLayout.GROUND_TOP_Y - ground.Y / 2, 0),
		Color = World.Grass,
		Material = Enum.Material.Grass,
		Parent = folder,
	})

	local street = PlotLayout.STREET_SIZE
	PartKit.Part({
		Name = "Street",
		Size = street,
		CFrame = CFrame.new(0, PlotLayout.STREET_TOP_Y - street.Y / 2, 0),
		Color = World.Street,
		Parent = folder,
	})

	-- Dashes along the street's centre line, one every LANE_DASH_SPACING.
	local dashes = Instance.new("Folder")
	dashes.Name = "LaneDashes"
	dashes.Parent = folder
	local dash = PlotLayout.LANE_DASH_SIZE
	local spacing = PlotLayout.LANE_DASH_SPACING
	local count = math.floor(street.X / spacing)
	local firstX = -street.X / 2 + spacing / 2
	for index = 0, count - 1 do
		local strip = PartKit.Part({
			Name = "Dash",
			Size = dash,
			CFrame = CFrame.new(firstX + index * spacing, PlotLayout.STREET_TOP_Y + dash.Y / 2, 0),
			Color = World.AccentViolet,
			Material = Enum.Material.Neon,
			Transparency = PlotLayout.LANE_DASH_TRANSPARENCY,
			Parent = dashes,
		})
		PartKit.MakeDecorative(strip)
	end
end

-- An empty foundation on slot `index`: floor, unclaimed walls, ramp, and a
-- sign gate reading FREE LAB.
local function buildPlaceholder(index: number)
	local folder = state.worldFolder
	if not folder or state.placeholders[index] then
		return
	end
	local origin = PlotLayout.GetSlotCFrame(index)
	local model = Instance.new("Model")
	model.Name = ("FreeLab_%d"):format(index)
	PlotKit.BuildFloor(origin, model)
	PlotKit.BuildWalls(origin, model, false)
	PlotKit.BuildGateRamp(origin, model)
	local sign = PlotKit.BuildSignGate(origin, model)
	sign.Set("FREE LAB", "Waiting for a scientist")
	model.Parent = folder
	state.placeholders[index] = model
end

local function removePlaceholder(index: number)
	local model = state.placeholders[index]
	if model then
		model:Destroy()
		state.placeholders[index] = nil
	end
end

-- Called by TycoonService: a player's plot now stands on (or has left)
-- slot `index`.
function WorldService.SetSlotOccupied(index: number, occupied: boolean)
	state.occupied[index] = occupied
	if occupied then
		removePlaceholder(index)
	else
		buildPlaceholder(index)
	end
end

function WorldService:Init()
	-- The default Baseplate would cover the street and plots.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "World"
	folder.Parent = Workspace
	state.worldFolder = folder

	buildGroundAndStreet(folder)
	for index = 1, PlotLayout.MAX_PLOT_SLOTS do
		if not state.occupied[index] then
			buildPlaceholder(index)
		end
	end
end

return WorldService
