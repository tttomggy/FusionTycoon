--!strict
--[[
	TutorialPath
	------------
	The way to the target, drawn like the egg games do it: a line of small
	arrows from your feet to whatever the goal arrow marks
	(GoalMarkerController.GetMarkedPosition), the tutorial's current step, or
	after the tutorial the current goal (the goal card's 👣 toggle).

	  * Arrows, not rails: a small flat chevron ">" (two thin lime Neon bars,
	    1.2 studs long, so the "no flat Neon circles" rule never applies)
	    every PathArrowSpacing studs along PathfindingService waypoints, a
	    straight line when no path is found, lying 0.2 studs above the
	    floor and pointing along the path toward the target. Each one
	    brightens and fades in turn so a pulse flows from you to the target.
	    At most PathMaxArrows of them (the spacing widens on a very long
	    way); a fixed pool, moved, never rebuilt.
	  * Lime (UITheme.World.TutorialPath): nothing else in the lab is lime, so
	    it can't be taken for part of the level.
	  * One arrow size only: the same small arrows run right up to the target
	    (no big chevrons at the end; the goal arrow's bouncing pill stays).
	  * Hidden once you're within PathArriveStuds of the target.

	All of it is client-only (parts under Workspace.Terrain). Rebuilt every
	TutorialConfig.PathRebuildSeconds as you move; the compute runs on its
	own thread, one at a time.
]]
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)

local TutorialPath = {}

local MAX_WAYPOINTS = 80
local PULSE_PHASE = 0.45 -- radians between neighbouring arrows

local localPlayer = Players.LocalPlayer

local folder: Folder? = nil
local arrows: { { Left: BasePart, Right: BasePart } } = {} -- the pool, in path order
local arrowCount = 0 -- how many are placed (the rest sit hidden)
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

local function newPart(name: string, shape: Enum.PartType, size: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = UITheme.World.TutorialPath
	part.Transparency = 1
	part.Parent = getFolder()
	return part
end

local function ensureArrows(count: number)
	while #arrows < count do
		table.insert(arrows, {
			Left = newPart("PathArrowArm", Enum.PartType.Block, TutorialConfig.PathArrowSize),
			Right = newPart("PathArrowArm", Enum.PartType.Block, TutorialConfig.PathArrowSize),
		})
	end
end

-- Lays a flat ">" with its tip at `tip`, pointing along `direction` (flat,
-- unit): two bars of `length` back from the tip at +-45 degrees.
local function layChevron(left: BasePart, right: BasePart, tip: Vector3, direction: Vector3, length: number)
	local a = length * math.cos(math.rad(45))
	local base = CFrame.lookAt(tip, tip + direction)
	left.CFrame = base * CFrame.new(-a / 2, 0, a / 2) * CFrame.Angles(0, math.rad(45), 0)
	right.CFrame = base * CFrame.new(a / 2, 0, a / 2) * CFrame.Angles(0, math.rad(-45), 0)
end

local function hideAll()
	arrowCount = 0
	for _, arrow in arrows do
		arrow.Left.Transparency = 1
		arrow.Right.Transparency = 1
	end
end

-- The polyline resampled every `spacing` studs (the first point is `points[1]`).
local function resample(points: { Vector3 }, spacing: number): { Vector3 }
	local out: { Vector3 } = { points[1] }
	local carried = 0 -- distance walked since the last arrow
	for index = 2, #points do
		local a, b = points[index - 1], points[index]
		local segment = (b - a).Magnitude
		if segment > 1e-3 then
			local direction = (b - a) / segment
			local at = spacing - carried
			while at <= segment do
				table.insert(out, a + direction * at)
				at += spacing
			end
			carried = segment - (at - spacing)
		end
	end
	return out
end

local function pathLength(points: { Vector3 }): number
	local total = 0
	for index = 2, #points do
		total += (points[index] - points[index - 1]).Magnitude
	end
	return total
end

local function placeArrows(points: { Vector3 })
	local spacing = math.max(TutorialConfig.PathArrowSpacing, pathLength(points) / TutorialConfig.PathMaxArrows)
	local placed = resample(points, spacing)
	-- Each arrow points along the path at its spot (flat, toward the
	-- target); the last one keeps the direction of the step before it.
	local directions: { Vector3 } = {}
	for index = 1, #placed do
		local nextPoint = placed[index + 1]
		local delta = if nextPoint then nextPoint - placed[index] else placed[index] - (placed[index - 1] or placed[index])
		local flat = Vector3.new(delta.X, 0, delta.Z)
		directions[index] = if flat.Magnitude > 1e-3 then flat.Unit else directions[index - 1] or Vector3.zAxis * -1
	end
	-- The first spot is under your feet: start one step ahead.
	table.remove(placed, 1)
	table.remove(directions, 1)
	local count = math.min(#placed, TutorialConfig.PathMaxArrows)
	ensureArrows(count)
	local lift = Vector3.new(0, TutorialConfig.PathArrowLift, 0)
	local length = TutorialConfig.PathArrowSize.X
	local half = length * math.cos(math.rad(45)) / 2
	for index = 1, count do
		-- Centre the ">" on the spot: its tip half its depth ahead.
		local tip = placed[index] + lift + directions[index] * half
		layChevron(arrows[index].Left, arrows[index].Right, tip, directions[index], length)
	end
	for index = count + 1, #arrows do
		arrows[index].Left.Transparency = 1
		arrows[index].Right.Transparency = 1
	end
	arrowCount = count
end

local function straightLine(from: Vector3, to: Vector3): { Vector3 }
	return { from, to }
end

local function rebuild()
	local target = getTarget()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not enabled or not target or not root or not root:IsA("BasePart") or not humanoid then
		hideAll()
		return
	end
	local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	local goal = target :: Vector3
	if Vector3.new(goal.X - feet.X, 0, goal.Z - feet.Z).Magnitude <= TutorialConfig.PathArriveStuds then
		hideAll()
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
				if #points >= MAX_WAYPOINTS then
					break
				end
			end
		end
		if #points < 2 then
			points = straightLine(feet, goal)
		end
		computing = false
		if enabled then
			placeArrows(points)
		end
	end)
end

-- Every frame: the pulse runs down the arrows.
local function animate()
	if arrowCount == 0 then
		return
	end
	local now = os.clock()
	local omega = (2 * math.pi) / TutorialConfig.PathFlowSeconds
	for index = 1, arrowCount do
		local wave = 0.5 + 0.5 * math.sin(now * omega - index * PULSE_PHASE)
		local transparency = 0.05 + 0.65 * (1 - wave)
		arrows[index].Left.Transparency = transparency
		arrows[index].Right.Transparency = transparency
	end
end

-- `target` returns where the path should end (nil: no path).
function TutorialPath.SetTargetSource(target: () -> Vector3?)
	getTarget = target
end

function TutorialPath.SetEnabled(on: boolean)
	enabled = on
	if not on then
		hideAll()
	end
end

function TutorialPath.IsShowing(): boolean
	return arrowCount > 0
end

-- How many arrows are placed now (/selftest, the performance report).
function TutorialPath.GetArrowCount(): number
	return arrowCount
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
