--[[
	BeltController
	--------------
	Client-only chevrons on the street's speed belts: a ">" every
	CHEVRON_SPACING studs, in the lane's rail colour, sliding along at the
	belt's speed and wrapping at the end, so the belts read as moving.

	All ~100 chevrons (two bars each) move with one BulkMoveTo per lane per
	frame; a lane is skipped while the camera is far from the street.
	Positions come from StreetLayout, so this never waits on the server's
	belt parts.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local StreetLayout = require(ReplicatedStorage.Shared.Config.StreetLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)

local BeltController = {}

type LaneState = {
	Direction: number,
	Z: number,
	Bars: { BasePart }, -- two per chevron, in chevron order
	Offsets: { CFrame }, -- each bar's CFrame relative to its chevron tip
	Count: number,
}

local lanes: { LaneState } = {}
local beltLength = StreetLayout.GetBeltLength()
local chevronY = StreetLayout.GetBeltTopY() + StreetLayout.CHEVRON_LIFT + StreetLayout.CHEVRON_BAR_SIZE.Y / 2
local cframes: { CFrame } = {}

local function newBar(parent: Instance, color: Color3): BasePart
	local bar = Instance.new("Part")
	bar.Name = "ChevronBar"
	bar.Size = StreetLayout.CHEVRON_BAR_SIZE
	bar.Material = Enum.Material.Neon
	bar.Color = color
	bar.Anchored = true
	bar.CanCollide = false
	bar.CanQuery = false
	bar.CanTouch = false
	bar.CastShadow = false
	bar.Parent = parent
	return bar
end

-- The two arms of a ">" pointing along `direction` (+1 = +X), relative to
-- the chevron's tip: each arm runs back from the tip at +-45 degrees.
local function armOffsets(direction: number): { CFrame }
	local half = StreetLayout.CHEVRON_BAR_SIZE.X / 2
	local angle = math.rad(StreetLayout.CHEVRON_ANGLE_DEGREES)
	local offsets = {}
	for _, side in { -1, 1 } do
		local arm = Vector3.new(-direction * math.cos(angle), 0, side * math.sin(angle))
		offsets[#offsets + 1] = CFrame.fromMatrix(arm * half, arm, Vector3.yAxis)
	end
	return offsets
end

local function buildLane(folder: Instance, lane: StreetLayout.Lane)
	local color = (UITheme.World :: any)[lane.RailColor] :: Color3
	local count = math.floor(beltLength / StreetLayout.CHEVRON_SPACING)
	local state: LaneState = {
		Direction = lane.Direction,
		Z = lane.Side * StreetLayout.BELT_CENTER_Z,
		Bars = {},
		Offsets = armOffsets(lane.Direction),
		Count = count,
	}
	for _ = 1, count do
		table.insert(state.Bars, newBar(folder, color))
		table.insert(state.Bars, newBar(folder, color))
	end
	table.insert(lanes, state)
end

local function streetDistance(cameraPosition: Vector3): number
	return Vector3.new(cameraPosition.X, 0, cameraPosition.Z).Magnitude
end

local function step()
	local camera = Workspace.CurrentCamera
	if not camera or streetDistance(camera.CFrame.Position) > StreetLayout.CHEVRON_CULL_DISTANCE then
		return
	end
	local travel = (os.clock() * StreetLayout.BELT_SPEED) % StreetLayout.CHEVRON_SPACING
	local startX = -beltLength / 2
	for _, lane in lanes do
		table.clear(cframes)
		for index = 0, lane.Count - 1 do
			-- Distance along the belt in its own direction, wrapped.
			local along = (index * StreetLayout.CHEVRON_SPACING + travel) % beltLength
			local x = if lane.Direction > 0 then startX + along else -startX - along
			local tip = CFrame.new(x, chevronY, lane.Z)
			table.insert(cframes, tip * lane.Offsets[1])
			table.insert(cframes, tip * lane.Offsets[2])
		end
		Workspace:BulkMoveTo(lane.Bars, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function BeltController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "BeltChevrons" -- client-only, never replicated
	folder.Parent = Workspace
	for _, lane in StreetLayout.LANES do
		buildLane(folder, lane)
	end
	RunService.RenderStepped:Connect(step)
	step()
end

return BeltController
