--!strict
--[[
	WorldService
	------------
	Builds the shared world once at server start: the grass ground, the
	street between the two rows of plots with its two speed belts, and a
	placeholder foundation ("FREE LAB") on every plot slot nobody has taken.
	Removes the default Baseplate if the place still has one.

	TycoonService tells it when a slot is taken or freed
	(WorldService.SetSlotOccupied); the placeholder is destroyed while a
	player's plot stands there and rebuilt when they leave.

	Every position and size comes from PlotLayout.

	Lifecycle: :Init() builds the world and every placeholder (self-contained,
	no other services). No :Start().
]]
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local StreetLayout = require(ReplicatedStorage.Shared.Config.StreetLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local PlotKit = require(ReplicatedStorage.Shared.Modules.PlotKit)

local WorldService = {}

WorldService.Name = "WorldService"

local World = UITheme.World

-- Belts carry characters but never cash balls.
local BELT_COLLISION_GROUP = "StreetBelts"

type State = {
	worldFolder: Folder?,
	placeholders: { [number]: Model },
	occupied: { [number]: boolean },
	belts: { { Part: BasePart, Velocity: Vector3 } },
}

local state: State = {
	worldFolder = nil,
	placeholders = {},
	occupied = {},
	belts = {},
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

	local street = StreetLayout.STREET_SIZE
	PartKit.Part({
		Name = "Street",
		Size = street,
		CFrame = CFrame.new(0, StreetLayout.STREET_TOP_Y - street.Y / 2, 0),
		Color = World.Street,
		Parent = folder,
	})
end

local function setupBeltCollisions()
	-- pcall: a group may already exist (TycoonService registers CashParts;
	-- Init order is not something to depend on).
	for _, group in { BELT_COLLISION_GROUP, PlotKit.CASH_COLLISION_GROUP } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(group)
		end)
	end
	PhysicsService:CollisionGroupSetCollidable(BELT_COLLISION_GROUP, PlotKit.CASH_COLLISION_GROUP, false)
end

-- Two conveyor belts down the street's middle (east lane moves +X, west
-- lane -X) with a median between, a Neon rail on each belt's outer edge and
-- a roller at each end. Anchored parts with an AssemblyLinearVelocity carry
-- whatever stands on them: the standard Roblox conveyor.
local function buildBelts(folder: Folder)
	local belts = Instance.new("Folder")
	belts.Name = "Belts"
	belts.Parent = folder

	local length = StreetLayout.GetBeltLength()
	local streetTop = StreetLayout.STREET_TOP_Y
	local beltTop = StreetLayout.GetBeltTopY()

	local median = PartKit.Part({
		Name = "Median",
		Size = Vector3.new(length, StreetLayout.MEDIAN_HEIGHT, StreetLayout.MEDIAN_WIDTH),
		CFrame = CFrame.new(0, streetTop + StreetLayout.MEDIAN_HEIGHT / 2, 0),
		Color = World.StructureLight,
		Parent = belts,
	})
	median.CollisionGroup = BELT_COLLISION_GROUP

	for _, lane in StreetLayout.LANES do
		local z = lane.Side * StreetLayout.BELT_CENTER_Z
		local belt = PartKit.Part({
			Name = lane.Belt,
			Size = Vector3.new(length, StreetLayout.BELT_HEIGHT, StreetLayout.BELT_WIDTH),
			CFrame = CFrame.new(0, beltTop - StreetLayout.BELT_HEIGHT / 2, z),
			Color = World.Belt,
			Parent = belts,
		})
		belt.CollisionGroup = BELT_COLLISION_GROUP
		local velocity = Vector3.new(lane.Direction * StreetLayout.BELT_SPEED, 0, 0)
		belt.AssemblyLinearVelocity = velocity
		table.insert(state.belts, { Part = belt, Velocity = velocity })

		local railColor = (World :: any)[lane.RailColor] :: Color3
		local rail = PartKit.Part({
			Name = lane.Rail,
			Size = Vector3.new(length, StreetLayout.RAIL_HEIGHT, StreetLayout.RAIL_WIDTH),
			CFrame = CFrame.new(0, beltTop, lane.Side * StreetLayout.RAIL_CENTER_Z),
			Color = railColor,
			Material = Enum.Material.Neon,
			Parent = belts,
		})
		PartKit.MakeDecorative(rail)

		-- Rollers: cylinders whose axis runs along Z, across the belt.
		for _, endSign in { -1, 1 } do
			local roller = PartKit.Part({
				Name = "Roller",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(StreetLayout.BELT_WIDTH, StreetLayout.ROLLER_DIAMETER, StreetLayout.ROLLER_DIAMETER),
				CFrame = CFrame.new(endSign * length / 2, beltTop - StreetLayout.BELT_HEIGHT / 2, z)
					* CFrame.Angles(0, math.rad(90), 0),
				Color = World.StructureLight,
				Parent = belts,
			})
			roller.CollisionGroup = BELT_COLLISION_GROUP
		end
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
	setupBeltCollisions()
	buildBelts(folder)
	-- Re-assert the belt velocities in case anything resets them.
	task.spawn(function()
		while true do
			task.wait(StreetLayout.BELT_VELOCITY_REFRESH_SECONDS)
			for _, belt in state.belts do
				if belt.Part.Parent then
					belt.Part.AssemblyLinearVelocity = belt.Velocity
				end
			end
		end
	end)
	for index = 1, PlotLayout.MAX_PLOT_SLOTS do
		if not state.occupied[index] then
			buildPlaceholder(index)
		end
	end
end

return WorldService
