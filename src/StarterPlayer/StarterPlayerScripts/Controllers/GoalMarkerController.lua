--[[
	GoalMarkerController
	--------------------
	Points at the current goal's target (GoalConfig[i].Target):

	  * World target (a part/model in your own plot, or "FirstEmptyPedestal"):
	    a constant-screen-size BillboardGui seen through walls - a gold pill
	    with the goal in caps, a pointer and a live "24 studs" line, bobbing -
	    plus a pulsing gold floor ring around the target (client-only part).
	    Hidden while you're within HIDE_RADIUS of it.
	  * UI target ("ui:Upgrades"): a pulsing gold outline on that HUD button.

	An override (SetOverride) replaces the goal while it lasts: the heist
	points a thief at their own gate (gold) and a victim at the thief's root
	(Danger red, following them, no floor ring). Under it sits the event
	override (SetEventOverride, EventController): what to do during the
	running event (the Gacha Pad in a Rainbow Storm, the Fusion Machine at
	night, the nearest crater or street coin). Heist > event > goal.

	Goal targets resolve inside YOUR plot only: the marker is placed from
	the target's own parts that stand inside your walls (never a model's
	pivot, which for a part-less or still-streaming model is the world
	origin: the middle of the street), and it moves if those parts move or
	stream in. The one exception is "NearestEnemyPedestal" (the steal goal),
	which is in another lab by definition.

	Updates on every goal change and goes away after the last goal. A world
	target that still can't be found TARGET_WARN_SECONDS after the plot is
	claimed warns once (a renamed part or a stale GoalConfig entry).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GoalConfig = require(ReplicatedStorage.Shared.Config.GoalConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local TycoonController = require(script.Parent.TycoonController)
local HudController = require(script.Parent.HudController)

local GoalMarkerController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MARKER_SIZE = UDim2.fromOffset(170, 80)
local MARKER_HEIGHT_ABOVE_TARGET = 3
local BOB_PIXELS = 6
local BOB_SECONDS = 1
local HIDE_RADIUS = 8
local RING_MARGIN = 2
local RING_PULSE_SECONDS = 1.2
local RESOLVE_INTERVAL = 0.5
local TARGET_WARN_SECONDS = 10

local localPlayer = Players.LocalPlayer

local currentGoalIndex: number? = nil
local currentTarget: Instance? = nil
local currentUiButton: string? = nil

local marker: BillboardGui? = nil
local markerAnchor: Attachment? = nil
local distanceText: TextLabel? = nil
local ring: BasePart? = nil
local targetPosition: Vector3? = nil
-- Centre of the bounds the marker was last placed from (moves re-place it).
local placedCenter: Vector3? = nil
local PLACE_MOVE_STUDS = 1
-- A moving override target (the thief's root): distance is measured to it live.
local movingTarget: BasePart? = nil

type Override = { Target: Instance, Text: string, Danger: boolean, Pulse: boolean }
local override: Override? = nil
local eventOverride: Override? = nil
-- The tutorial's layer (TutorialController): while it's active the goal
-- arrow is replaced by the current step's target (resolved by name each
-- refresh, since stations appear on claim), or by nothing on a UI step.
-- Heist > tutorial > event > goal.
type TutorialLayer = { Name: string?, Text: string }
local tutorialLayer: TutorialLayer? = nil

-- os.clock() a target name was first missed on a claimed plot; names that
-- already warned.
local missingSince: { [string]: number } = {}
local warnedTargets: { [string]: boolean } = {}

--[[ Target resolution ---------------------------------------------------------- ]]

local function getPlot(): Instance?
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	return folder and folder:FindFirstChild(PlotNaming.GetPlotName(localPlayer.UserId))
end

local function resolveTarget(name: string): Instance?
	local plot = getPlot()
	if not plot then
		return nil
	end
	if name == "FirstEmptyPedestal" then
		local pedestals = plot:FindFirstChild("Pedestals")
		if not pedestals then
			return nil
		end
		for _, index in TycoonController.GetPedestalOrder() do
			if not TycoonController.GetPedestalDisplay(index) then
				return pedestals:FindFirstChild("Pedestal" .. index)
			end
		end
		return nil
	end
	local pedestalIndex = name:match("^Pedestal(%d+)$")
	if pedestalIndex then
		local pedestals = plot:FindFirstChild("Pedestals")
		return pedestals and pedestals:FindFirstChild(name)
	end
	if name == "NearestEnemyPedestal" then
		-- The closest pedestal in another lab you could grab right now
		-- (WorldLabelController marks its StealPrompt Mode "Steal").
		local folder = plot.Parent
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not folder or not root or not root:IsA("BasePart") then
			return nil
		end
		local best: Instance? = nil
		local bestDistance = math.huge
		for _, other in folder:GetChildren() do
			local pedestals = other ~= plot and other:FindFirstChild("Pedestals")
			if pedestals then
				for _, pedestal in pedestals:GetChildren() do
					local prompt = pedestal:FindFirstChild("StealPrompt")
					local mode = prompt and prompt:GetAttribute("Mode")
					if pedestal:IsA("BasePart") and mode == "Steal" then
						local distance = (pedestal.Position - root.Position).Magnitude
						if distance < bestDistance then
							best, bestDistance = pedestal, distance
						end
					end
				end
			end
		end
		return best
	end
	return plot:FindFirstChild(name)
end

local function getPlotOrigin(): CFrame?
	local plot = getPlot()
	local origin = plot and plot:FindFirstChild("PlotOrigin", true)
	return if origin and origin:IsA("BasePart") then origin.CFrame else nil
end

-- World-space box (centre CFrame, size) of the target's own BaseParts: the
-- target itself and its descendants. Never Model:GetBoundingBox, whose
-- fallback for a model with no parts here yet (streaming) is its pivot.
-- With `origin`, only parts standing inside that plot's walls count.
-- (nil, nil) when no part qualifies yet.
local function getBounds(target: Instance, origin: CFrame?): (CFrame?, Vector3?)
	local low: Vector3? = nil
	local high: Vector3? = nil
	local function add(part: BasePart)
		if origin and not PlotLayout.IsInsidePlot(origin:PointToObjectSpace(part.Position)) then
			return
		end
		local cf, size = part.CFrame, part.Size / 2
		local extent = Vector3.new(
			math.abs(cf.RightVector.X) * size.X + math.abs(cf.UpVector.X) * size.Y + math.abs(cf.LookVector.X) * size.Z,
			math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z,
			math.abs(cf.RightVector.Z) * size.X + math.abs(cf.UpVector.Z) * size.Y + math.abs(cf.LookVector.Z) * size.Z
		)
		local a, b = part.Position - extent, part.Position + extent
		low = if low then low:Min(a) else a
		high = if high then high:Max(b) else b
	end
	if target:IsA("BasePart") then
		add(target)
	end
	for _, descendant in target:GetDescendants() do
		if descendant:IsA("BasePart") then
			add(descendant)
		end
	end
	if not low or not high then
		return nil, nil
	end
	local lowV, highV = low :: Vector3, high :: Vector3
	return CFrame.new((lowV + highV) / 2), highV - lowV
end

--[[ Marker visuals ---------------------------------------------------------------- ]]

local function clearWorldMarker()
	if marker then
		marker:Destroy()
		marker = nil
	end
	if markerAnchor then
		markerAnchor:Destroy()
		markerAnchor = nil
	end
	if ring then
		ring:Destroy()
		ring = nil
	end
	distanceText = nil
	targetPosition = nil
	placedCenter = nil
	movingTarget = nil
	currentTarget = nil
end

local PULSE_SCALE = 1.25
local PULSE_SECONDS = 0.6

local function buildMarker(goalText: string, danger: boolean, pulse: boolean?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "GoalMarker"
	gui.AlwaysOnTop = true -- a guide, meant to be seen through walls
	gui.Size = MARKER_SIZE -- constant screen size
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = gui

	-- Gold gradient on a Frame with the words in a child label (a gradient on
	-- the label itself would tint the text gold-on-gold).
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.fromScale(0.5, 0)
	pill.Size = UDim2.new(1, 0, 0, 36)
	pill.BackgroundColor3 = Colors.White
	pill.ZIndex = 2
	pill.Parent = content
	UIKit.PairGradient(pill, if danger then UITheme.Gradients.Heist else UITheme.Gradients.Gold)
	UIKit.Corner(pill, 999)
	UIKit.Stroke(pill, 3)
	UIKit.Padding(pill, 4, 12, 4, 12)
	UIKit.Label({
		Name = "Text",
		Text = goalText:upper(),
		Font = Fonts.Display,
		TextSize = 20,
		-- White with the ink stroke on gold (the contrast rule) or red.
		TextColor3 = Colors.Text,
		Stroke = UITheme.WarmTextStroke,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		ZIndex = 3,
		Parent = pill,
	})

	-- Down-pointing triangle: a gold square turned 45 degrees, half tucked
	-- under the pill.
	local pointer = Instance.new("Frame")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Position = UDim2.new(0.5, 0, 0, 38)
	pointer.Size = UDim2.fromOffset(14, 14)
	pointer.Rotation = 45
	pointer.BackgroundColor3 = if danger then UITheme.Gradients.Heist.Bottom else UITheme.Gradients.Gold.Bottom
	pointer.ZIndex = 1
	pointer.Parent = content
	UIKit.Stroke(pointer, 3)

	local distance = UIKit.Label({
		Name = "Distance",
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = if danger then Colors.Danger else Colors.GoldLabel,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
		Stroke = 1.5,
		Parent = content,
	})

	TweenService:Create(
		content,
		TweenInfo.new(BOB_SECONDS / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromOffset(0, -BOB_PIXELS) }
	):Play()
	if pulse then
		-- The heist's first-catch tip: the red arrow throbs.
		local scale = Instance.new("UIScale")
		scale.Parent = content
		TweenService:Create(
			scale,
			TweenInfo.new(PULSE_SECONDS / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = PULSE_SCALE }
		):Play()
	end

	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	marker = gui
	distanceText = distance
end

-- A pulsing gold ring on the floor around the target: a SurfaceGui ring
-- face (client-only part), not a flat Neon disc.
local function buildRing(bottomCenter: Vector3, footprint: number)
	local face = BillboardKit.BuildPadFace(
		Workspace, -- created on the client: only this player sees it
		CFrame.new(bottomCenter),
		footprint + RING_MARGIN,
		UITheme.World.AccentGold,
		nil
	)
	face.Name = "GoalRing"
	local gui = face:FindFirstChild("PadFace")
	local ringFrame = gui and gui:FindFirstChild("Ring")
	local stroke = ringFrame and ringFrame:FindFirstChild("RingStroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Transparency = 0.2
		TweenService:Create(
			stroke,
			TweenInfo.new(RING_PULSE_SECONDS / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.7 }
		):Play()
	end
	ring = face
end

local function showWorldMarker(target: Instance, goalText: string, danger: boolean?, pulse: boolean?, origin: CFrame?)
	-- An unanchored part (a character's root) moves: adorn to it directly.
	if target:IsA("BasePart") and not target.Anchored then
		clearWorldMarker()
		currentTarget = target
		movingTarget = target
		buildMarker(goalText, danger == true, pulse)
		local gui = marker :: BillboardGui
		gui.Adornee = target
		gui.StudsOffset = Vector3.new(0, MARKER_HEIGHT_ABOVE_TARGET + 2, 0)
		return
	end
	local center, size = getBounds(target, origin)
	if not center or not size then
		-- Nothing of it here yet (not built / not streamed in): retried.
		clearWorldMarker()
		return
	end
	clearWorldMarker()
	currentTarget = target
	placedCenter = center.Position

	local top = center.Position + Vector3.new(0, size.Y / 2, 0)
	local bottom = center.Position - Vector3.new(0, size.Y / 2, 0)
	targetPosition = bottom

	local anchor = Instance.new("Attachment")
	anchor.Name = "GoalMarkerAnchor"
	anchor.WorldPosition = top + Vector3.new(0, MARKER_HEIGHT_ABOVE_TARGET, 0)
	anchor.Parent = Workspace.Terrain
	markerAnchor = anchor

	buildMarker(goalText, danger == true)
	local gui = marker :: BillboardGui
	gui.Adornee = anchor
	buildRing(bottom, math.max(size.X, size.Z))
end

--[[ Goal changes -------------------------------------------------------------------- ]]

-- Warns once for a world target that never turns up. Only counts while the
-- plot is claimed (stations and generators are built on claim), and skips
-- "FirstEmptyPedestal", which is legitimately missing when all are full.
local function checkTargetExists(name: string, target: Instance?)
	local plot = getPlot()
	if target or name == "FirstEmptyPedestal" or name == "NearestEnemyPedestal" or not plot or plot:GetAttribute("Claimed") ~= true then
		missingSince[name] = nil
		return
	end
	local since = missingSince[name]
	if not since then
		missingSince[name] = os.clock()
	elseif not warnedTargets[name] and os.clock() - since >= TARGET_WARN_SECONDS then
		warnedTargets[name] = true
		warn(("GoalMarkerController: goal target %q not found in your plot; check GoalConfig"):format(name))
	end
end

local function setUiTarget(name: string?)
	if currentUiButton and currentUiButton ~= name then
		HudController.SetButtonHighlight(currentUiButton, false)
	end
	currentUiButton = name
	if name then
		HudController.SetButtonHighlight(name, true)
	end
end

local function refresh()
	local layer = tutorialLayer
	if not override and layer then
		setUiTarget(nil)
		local target = if layer.Name then resolveTarget(layer.Name) else nil
		local origin = getPlotOrigin()
		if not target or not origin then
			clearWorldMarker()
			return
		end
		local moved = false
		if target == currentTarget and placedCenter then
			local center = getBounds(target, origin)
			moved = center == nil or (center.Position - placedCenter).Magnitude > PLACE_MOVE_STUDS
		end
		if target ~= currentTarget or moved or not placedCenter then
			showWorldMarker(target, layer.Text, nil, nil, origin)
		end
		currentGoalIndex = nil
		return
	end
	local active = override or eventOverride
	if active then
		setUiTarget(nil)
		if active.Target ~= currentTarget then
			showWorldMarker(active.Target, active.Text, active.Danger, active.Pulse)
		end
		return
	end
	local index = TycoonController.GetGoalIndex()
	local goal = index and GoalConfig.GetGoal(index)
	if not goal then
		clearWorldMarker()
		setUiTarget(nil)
		currentGoalIndex = index
		return
	end

	local targetName = goal.Target
	if targetName:sub(1, 3) == "ui:" then
		clearWorldMarker()
		setUiTarget(targetName:sub(4))
		currentGoalIndex = index
		return
	end
	setUiTarget(nil)

	local target = resolveTarget(targetName)
	checkTargetExists(targetName, target)
	-- Inside your own walls only (the steal goal is the one exception).
	local origin = if targetName == "NearestEnemyPedestal" then nil else getPlotOrigin()
	if target and not origin and targetName ~= "NearestEnemyPedestal" then
		target = nil -- no plot origin yet: can't check, so don't guess
	end
	if target and origin and not getBounds(target, origin) and getBounds(target) then
		-- It exists but stands outside your walls: never point there.
		local key = "outside:" .. targetName
		if not warnedTargets[key] then
			warnedTargets[key] = true
			warn(("GoalMarkerController: goal target %q resolved to %s, outside your plot; ignored"):format(targetName, target:GetFullName()))
		end
	end
	local moved = false
	if target and target == currentTarget and placedCenter then
		local center = getBounds(target, origin)
		moved = center == nil or (center.Position - placedCenter).Magnitude > PLACE_MOVE_STUDS
	end
	if target ~= currentTarget or index ~= currentGoalIndex or moved or (target and not placedCenter) then
		currentGoalIndex = index
		if target then
			showWorldMarker(target, goal.Text, nil, nil, origin)
		else
			-- Not built yet (e.g. stations appear after claiming); retried.
			clearWorldMarker()
		end
	end
end

local function update()
	local gui = marker
	local position = if movingTarget then movingTarget.Position else targetPosition
	if not gui or not position then
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local offset = root.Position - position
	local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local near = distance <= HIDE_RADIUS
	gui.Enabled = not near
	if distanceText then
		distanceText.Text = ("%d studs"):format(math.floor(distance + 0.5))
	end
end

-- Points the marker at `target` instead of the goal until cleared (nil).
-- `danger` tints it red (the heist's victim arrow); `pulse` makes it throb.
function GoalMarkerController.SetOverride(target: Instance?, text: string?, danger: boolean?, pulse: boolean?)
	if target then
		override = { Target = target, Text = text or "", Danger = danger == true, Pulse = pulse == true }
	else
		override = nil
	end
	clearWorldMarker()
	currentGoalIndex = nil -- re-show the goal marker when the override ends
	refresh()
end

-- The event layer, under any heist override: points at `target` (nil
-- clears it). Called often; a no-op while nothing changes.
function GoalMarkerController.SetEventOverride(target: Instance?, text: string?)
	local current = eventOverride
	if target and current and current.Target == target and current.Text == (text or "") then
		return
	end
	if not target and not current then
		return
	end
	eventOverride = if target then { Target = target, Text = text or "", Danger = false, Pulse = false } else nil
	if override then
		return -- the heist arrow stays; this shows when it ends
	end
	clearWorldMarker()
	currentGoalIndex = nil
	refresh()
end

-- The tutorial layer: `targetName` (a plot target, or nil on a UI step)
-- with `text`; SetTutorialTarget(nil, nil, false) ends it.
function GoalMarkerController.SetTutorialTarget(targetName: string?, text: string?, active: boolean)
	local current = tutorialLayer
	if active and current and current.Name == targetName and current.Text == (text or "") then
		return
	end
	if not active and not current then
		return
	end
	tutorialLayer = if active then { Name = targetName, Text = text or "" } else nil
	clearWorldMarker()
	currentGoalIndex = nil
	refresh()
end

-- Where the marker points now (the floor under the target), for the lit
-- path; nil when nothing is marked.
function GoalMarkerController.GetMarkedPosition(): Vector3?
	if movingTarget then
		return movingTarget.Position
	end
	return targetPosition
end

-- A target in your own plot by GoalConfig name ("GachaStation",
-- "FusionMachine", ...), or nil before it's built.
function GoalMarkerController.ResolvePlotTarget(name: string): Instance?
	return resolveTarget(name)
end

function GoalMarkerController.Init()
	TycoonController.TycoonChanged:Connect(refresh)
	RunService.Heartbeat:Connect(update)
	-- Targets that don't exist yet (stations built on claim) and targets that
	-- move (the first empty pedestal, the nearest enemy pedestal) are
	-- re-resolved on a slow timer.
	task.spawn(function()
		while true do
			task.wait(RESOLVE_INTERVAL)
			refresh()
		end
	end)
	refresh()
end

return GoalMarkerController
