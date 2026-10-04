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
	(Danger red, following them, no floor ring).

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
-- A moving override target (the thief's root): distance is measured to it live.
local movingTarget: BasePart? = nil

type Override = { Target: Instance, Text: string, Danger: boolean, Pulse: boolean }
local override: Override? = nil

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
		for index = 1, PlotLayout.PEDESTAL_COUNT do
			if not TycoonController.GetPedestalDisplay(index) then
				return pedestals:FindFirstChild("Pedestal" .. index)
			end
		end
		return nil
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
					if pedestal:IsA("BasePart") and (mode == "Steal" or mode == "Cooldown") then
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

-- World-space bounding box of a part or model: (centre CFrame, size).
local function getBounds(target: Instance): (CFrame?, Vector3?)
	if target:IsA("Model") then
		return target:GetBoundingBox()
	elseif target:IsA("BasePart") then
		return target.CFrame, target.Size
	end
	return nil, nil
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
		TextColor3 = if danger then Colors.Text else Colors.GoldText,
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

local function showWorldMarker(target: Instance, goalText: string, danger: boolean?, pulse: boolean?)
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
	local center, size = getBounds(target)
	if not center or not size then
		return
	end
	clearWorldMarker()
	currentTarget = target

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
	local active = override
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
	if target ~= currentTarget or index ~= currentGoalIndex then
		currentGoalIndex = index
		if target then
			showWorldMarker(target, goal.Text)
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
