--!strict
--[[
	TutorialPath
	------------
	The glowing path on the ground from your feet to whatever the goal arrow
	marks (GoalMarkerController.GetMarkedPosition): the tutorial's current
	step, or after the tutorial the current goal (the goal card's 👣 toggle).

	A chain of Beams between Attachments on Workspace.Terrain (client-only),
	laid along PathfindingService waypoints, a straight line when no path is
	found. Rebuilt every TutorialConfig.PathRebuildSeconds as you move; the
	compute runs on its own thread, one at a time. With a PathTexture the
	beams scroll it; without one each segment's glow ripples toward the
	target. Hidden once you're within ARRIVE_STUDS of the target. The pulsing
	ring round the target is the goal marker's own (a SurfaceGui face).
]]
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)

local TutorialPath = {}

local ARRIVE_STUDS = 6
local STEP_STUDS = 4 -- spacing of the straight-line fallback's points
local MAX_POINTS = 40
local LIFT = 0.25 -- above the floor
local BEAM_WIDTH = 1.4
local RIPPLE_SPEED = 6
local RIPPLE_SPACING = 0.8

local localPlayer = Players.LocalPlayer

type Segment = { Beam: Beam, A: Attachment, B: Attachment }

local folder: Folder? = nil
local segments: { Segment } = {}
local enabled = false
local getTarget: () -> Vector3? = function()
	return nil
end
local computing = false
local accumulator = 0

local function getFolder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "TutorialPath"
	created.Parent = Workspace.Terrain
	folder = created
	return created
end

local function clear()
	for _, segment in segments do
		segment.Beam:Destroy()
		segment.A:Destroy()
		segment.B:Destroy()
	end
	segments = {}
end

local function newAttachment(position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "PathPoint"
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	return attachment
end

local function draw(points: { Vector3 })
	-- Same length: move the existing points (no churn every rebuild).
	if #segments == #points - 1 then
		for index, segment in segments do
			segment.A.WorldPosition = points[index]
			segment.B.WorldPosition = points[index + 1]
		end
		return
	end
	clear()
	local color = UITheme.World.AccentGold
	for index = 1, #points - 1 do
		local a = newAttachment(points[index])
		local b = newAttachment(points[index + 1])
		local beam = Instance.new("Beam")
		beam.Name = "PathBeam"
		beam.Attachment0 = a
		beam.Attachment1 = b
		beam.FaceCamera = true
		beam.Width0 = BEAM_WIDTH
		beam.Width1 = BEAM_WIDTH
		beam.Segments = 1
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(color)
		if TutorialConfig.PathTexture ~= "" then
			beam.Texture = TutorialConfig.PathTexture
			beam.TextureMode = Enum.TextureMode.Wrap
			beam.TextureLength = 2
			beam.TextureSpeed = 1.5
		end
		beam.Parent = getFolder()
		table.insert(segments, { Beam = beam, A = a, B = b })
	end
end

local function straightLine(from: Vector3, to: Vector3): { Vector3 }
	local points = {}
	local distance = (to - from).Magnitude
	local count = math.clamp(math.ceil(distance / STEP_STUDS), 1, MAX_POINTS - 1)
	for index = 0, count do
		table.insert(points, from:Lerp(to, index / count))
	end
	return points
end

local function rebuild()
	local target = getTarget()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not enabled or not target or not root or not root:IsA("BasePart") or not humanoid then
		clear()
		return
	end
	local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local goal = target :: Vector3
	if Vector3.new(goal.X - feet.X, 0, goal.Z - feet.Z).Magnitude <= ARRIVE_STUDS then
		clear()
		return
	end
	if computing then
		return
	end
	computing = true
	task.spawn(function()
		local points: { Vector3 } = {}
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(function()
			path:ComputeAsync(feet, goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
				if #points >= MAX_POINTS then
					break
				end
			end
		end
		if #points < 2 then
			points = straightLine(feet, goal)
		end
		for index, point in points do
			points[index] = point + Vector3.new(0, LIFT, 0)
		end
		computing = false
		if enabled then
			draw(points)
		end
	end)
end

local function animate()
	if TutorialConfig.PathTexture ~= "" or #segments == 0 then
		return
	end
	local now = os.clock()
	for index, segment in segments do
		local wave = 0.5 + 0.5 * math.sin(now * RIPPLE_SPEED - index * RIPPLE_SPACING)
		segment.Beam.Transparency = NumberSequence.new(0.15 + 0.55 * (1 - wave))
	end
end

-- `target` returns where the path should end (nil: no path).
function TutorialPath.SetTargetSource(target: () -> Vector3?)
	getTarget = target
end

function TutorialPath.SetEnabled(on: boolean)
	enabled = on
	if not on then
		clear()
	end
end

function TutorialPath.IsShowing(): boolean
	return #segments > 0
end

function TutorialPath.Init()
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator >= TutorialConfig.PathRebuildSeconds then
			accumulator = 0
			rebuild()
		end
		animate()
	end)
end

return TutorialPath
