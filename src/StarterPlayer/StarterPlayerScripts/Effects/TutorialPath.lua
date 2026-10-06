--!strict
--[[
	TutorialPath
	------------
	The way to the target, drawn like the egg games do it: a dotted line from
	your feet to whatever the goal arrow marks
	(GoalMarkerController.GetMarkedPosition), the tutorial's current step, or
	after the tutorial the current goal (the goal card's 👣 toggle).

	  * Dots, not rails: small lime Ball parts (about 0.5 studs, Neon, so the
	    "no flat Neon circles" rule never applies) every 2 studs along
	    PathfindingService waypoints, a straight line when no path is found,
	    floating 0.5 studs up. Each one swells in turn so a pulse runs from
	    you to the target. At most PathMaxDots of them (the spacing widens on
	    a very long way); a fixed pool, moved, never rebuilt.
	  * Lime (UITheme.World.TutorialPath): nothing else in the lab is lime, so
	    it can't be taken for part of the level.
	  * At the target: three big chevrons on the floor pointing in, in a row
	    on the side you come from (two thin Neon bars each), lighting in turn.
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
local PULSE_PHASE = 0.45 -- radians between neighbouring dots
local PULSE_GROW = 0.9 -- a dot swells up to 1 + this
local CHEVRON_FIRST_GAP = 3 -- studs from the target's edge to the nearest chevron
local CHEVRON_GAP = 3.4
local CHEVRON_ARM = Vector3.new(3.2, 0.18, 0.9)
local CHEVRON_LIFT = 0.12
local CHEVRON_PULSE_SECONDS = 1.2

local localPlayer = Players.LocalPlayer

local folder: Folder? = nil
local dots: { BasePart } = {} -- the pool, in path order
local dotCount = 0 -- how many are placed (the rest sit hidden)
local chevrons: { { Left: BasePart, Right: BasePart } } = {}
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

local function ensureDots(count: number)
	while #dots < count do
		table.insert(dots, newPart("PathDot", Enum.PartType.Ball, Vector3.one * TutorialConfig.PathDotSize))
	end
end

local function ensureChevrons()
	local f = getFolder()
	while #chevrons < TutorialConfig.ChevronCount do
		table.insert(chevrons, {
			Left = newPart("ChevronArm", Enum.PartType.Block, CHEVRON_ARM),
			Right = newPart("ChevronArm", Enum.PartType.Block, CHEVRON_ARM),
		})
	end
	for _, chevron in chevrons do
		chevron.Left.Parent = f
		chevron.Right.Parent = f
	end
end

local function hideAll()
	dotCount = 0
	for _, dot in dots do
		dot.Transparency = 1
	end
	for _, chevron in chevrons do
		chevron.Left.Transparency = 1
		chevron.Right.Transparency = 1
	end
end

-- The polyline resampled every `spacing` studs (the first point is `points[1]`).
local function resample(points: { Vector3 }, spacing: number): { Vector3 }
	local out: { Vector3 } = { points[1] }
	local carried = 0 -- distance walked since the last dot
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

local function placeDots(points: { Vector3 })
	local spacing = math.max(TutorialConfig.PathDotSpacing, pathLength(points) / TutorialConfig.PathMaxDots)
	local placed = resample(points, spacing)
	-- The first dot sits under your feet: start one step ahead.
	table.remove(placed, 1)
	local count = math.min(#placed, TutorialConfig.PathMaxDots)
	ensureDots(count)
	local lift = Vector3.new(0, TutorialConfig.PathDotLift, 0)
	for index = 1, count do
		dots[index].Position = placed[index] + lift
	end
	for index = count + 1, #dots do
		dots[index].Transparency = 1
	end
	dotCount = count
end

-- Three chevrons in a row on the side you approach from, each pointing at
-- the target.
local function placeChevrons(target: Vector3, from: Vector3)
	local flat = Vector3.new(from.X - target.X, 0, from.Z - target.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	ensureChevrons()
	local outward = flat.Unit -- target -> you
	local inward = -outward -- what a chevron points along
	local a = CHEVRON_ARM.X * math.cos(math.rad(45))
	for index, chevron in chevrons do
		local distance = CHEVRON_FIRST_GAP + (index - 1) * CHEVRON_GAP
		local tip = Vector3.new(target.X, target.Y + CHEVRON_LIFT, target.Z) + outward * distance
		local base = CFrame.lookAt(tip, tip + inward)
		chevron.Left.CFrame = base * CFrame.new(-a / 2, 0, a / 2) * CFrame.Angles(0, math.rad(45), 0)
		chevron.Right.CFrame = base * CFrame.new(a / 2, 0, a / 2) * CFrame.Angles(0, math.rad(-45), 0)
	end
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
			placeDots(points)
			placeChevrons(goal, feet)
		end
	end)
end

-- Every frame: the pulse runs down the dots, the chevrons light in turn.
local function animate()
	if dotCount == 0 then
		return
	end
	local now = os.clock()
	local base = TutorialConfig.PathDotSize
	local omega = (2 * math.pi) / TutorialConfig.PathFlowSeconds
	for index = 1, dotCount do
		local wave = 0.5 + 0.5 * math.sin(now * omega - index * PULSE_PHASE)
		local dot = dots[index]
		dot.Size = Vector3.one * (base * (0.75 + PULSE_GROW * wave))
		dot.Transparency = 0.1 + 0.5 * (1 - wave)
	end
	local chevronOmega = (2 * math.pi) / CHEVRON_PULSE_SECONDS
	local count = #chevrons
	for index, chevron in chevrons do
		-- The farthest chevron lights first; the one at the target last.
		local wave = 0.5 + 0.5 * math.sin(now * chevronOmega - (count - index) * 1.1)
		local transparency = 0.05 + 0.6 * (1 - wave)
		chevron.Left.Transparency = transparency
		chevron.Right.Transparency = transparency
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
	return dotCount > 0
end

-- How many dots are placed now (/selftest, the performance report).
function TutorialPath.GetDotCount(): number
	return dotCount
end

function TutorialPath.GetChevronCount(): number
	return #chevrons
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
