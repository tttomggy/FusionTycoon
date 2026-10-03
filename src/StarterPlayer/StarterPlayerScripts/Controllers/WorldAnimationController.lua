--[[
	WorldAnimationController
	------------------------
	Floats and spins everything tagged FT_Hover (station holograms, pedestal
	orbs), locally on each client every frame, so motion is smooth for
	everyone and the server never tweens.

	Attributes on the tagged Part or Model:
	  SpinDegPerSec  degrees per second around the vertical axis
	  BobStuds       how far it travels up
	  BobPeriod      seconds per cycle
	  Mode           "Bob" (smooth up and down) or "Rise" (up over the period,
	                 then snap back - the multiplier chevrons)

	A tagged Model moves as one group via PivotTo. Each target's resting
	CFrame is captured when it's first seen; only targets within
	ANIMATE_RADIUS of the camera are animated.

	Mutation satellites (Models tagged FT_Orbit, inside a pedestal's
	OrbGroup) orbit the orb: Count balls, Radius studs out, one lap per
	Period seconds, tilted Tilt degrees. All of them move with one
	BulkMoveTo per frame, after the hover step, skipping any beyond
	ORBIT_RADIUS of the camera.

	Rainbow mutation shells (tagged FT_Rainbow) cycle their Color around the
	hue wheel every RAINBOW_CYCLE_SECONDS.

	Rebirth Portal sheets (tagged FT_PortalSwirl) follow their portal's Ready
	attribute: not ready, the swirl is translucent and still; ready, it's
	opaque, its gradient turns at SwirlDegPerSec and the base ring pulses.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local PortalKit = require(ReplicatedStorage.Shared.Modules.PortalKit)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)

local WorldAnimationController = {}

local ANIMATE_RADIUS = 150
local ORBIT_RADIUS = 120
local RAINBOW_CYCLE_SECONDS = 3
local RAINBOW_SATURATION = 0.55
local RAINBOW_VALUE = 1

type Entry = {
	Target: BasePart | Model,
	Base: CFrame,
	Phase: number, -- desyncs neighbours that share the same timing
}

local entries: { [Instance]: Entry } = {}

type Swirl = {
	Sheet: BasePart,
	Portal: Instance,
	Frames: { Frame },
	Gradients: { UIGradient },
	RingStroke: UIStroke?,
}

local swirls: { [Instance]: Swirl } = {}
local rainbows: { [BasePart]: boolean } = {}

type Orbit = { Model: Model, Balls: { BasePart } }
local orbits: { [Instance]: Orbit } = {}
local orbitParts: { BasePart } = {}
local orbitCFrames: { CFrame } = {}

local function getPivot(target: Instance): CFrame?
	if target:IsA("BasePart") then
		return target.CFrame
	elseif target:IsA("Model") then
		return target:GetPivot()
	end
	return nil
end

local function track(target: Instance)
	if entries[target] or not target:IsDescendantOf(Workspace) then
		return
	end
	local base = getPivot(target)
	if not base then
		return
	end
	entries[target] = {
		Target = target :: any,
		Base = base,
		Phase = (math.abs(base.Position.X) + math.abs(base.Position.Z)) % 7,
	}
end

local function untrack(target: Instance)
	entries[target] = nil
end

local function offsetFor(target: Instance, t: number): CFrame
	local spin = (target:GetAttribute("SpinDegPerSec") :: number?) or 0
	local bob = (target:GetAttribute("BobStuds") :: number?) or 0
	local period = (target:GetAttribute("BobPeriod") :: number?) or 1
	local mode = target:GetAttribute("Mode")

	local rise = 0
	if bob ~= 0 and period > 0 then
		local cycle = (t % period) / period
		if mode == "Rise" then
			rise = bob * cycle
		else
			rise = bob * 0.5 * (1 - math.cos(cycle * math.pi * 2))
		end
	end
	return CFrame.new(0, rise, 0) * CFrame.Angles(0, math.rad(spin * t), 0)
end

local function trackSwirl(sheet: Instance)
	if swirls[sheet] or not sheet:IsA("BasePart") or not sheet:IsDescendantOf(Workspace) then
		return
	end
	local portal = sheet.Parent
	if not portal then
		return
	end
	local swirl: Swirl = { Sheet = sheet, Portal = portal, Frames = {}, Gradients = {}, RingStroke = nil }
	for _, descendant in sheet:GetDescendants() do
		if descendant:IsA("Frame") and descendant.Name == "Swirl" then
			table.insert(swirl.Frames, descendant)
		elseif descendant:IsA("UIGradient") then
			table.insert(swirl.Gradients, descendant)
		end
	end
	local face = portal:FindFirstChild("Face")
	local gui = face and face:FindFirstChild("PadFace")
	local ring = gui and gui:FindFirstChild("Ring")
	local stroke = ring and ring:FindFirstChild("RingStroke")
	if stroke and stroke:IsA("UIStroke") then
		swirl.RingStroke = stroke
	end
	swirls[sheet] = swirl
end

local function trackOrbit(model: Instance)
	if orbits[model] or not model:IsA("Model") then
		return
	end
	local balls: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(balls, child)
		end
	end
	table.sort(balls, function(a, b)
		return a.Name < b.Name
	end)
	orbits[model] = { Model = model, Balls = balls }
end

-- Runs after the hover step, so the satellites circle wherever the orb
-- has bobbed to this frame.
local function stepOrbits(cameraPosition: Vector3, now: number)
	table.clear(orbitParts)
	table.clear(orbitCFrames)
	for model, orbit in orbits do
		local group = model.Parent
		local center = group and group:IsA("Model") and group.PrimaryPart
		if center and (center.Position - cameraPosition).Magnitude <= ORBIT_RADIUS then
			local count = math.max((model:GetAttribute("Count") :: number?) or #orbit.Balls, 1)
			local radius = (model:GetAttribute("Radius") :: number?) or 1
			local period = math.max((model:GetAttribute("Period") :: number?) or 2, 0.1)
			local tilt = CFrame.Angles(math.rad((model:GetAttribute("Tilt") :: number?) or 0), 0, 0)
			local base = (now / period) * math.pi * 2
			local origin = CFrame.new(center.Position) * tilt
			for index, ball in orbit.Balls do
				local angle = base + (index - 1) * (math.pi * 2 / count)
				table.insert(orbitParts, ball)
				table.insert(orbitCFrames, origin * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
			end
		end
	end
	if #orbitParts > 0 then
		Workspace:BulkMoveTo(orbitParts, orbitCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function stepRainbows(cameraPosition: Vector3, now: number)
	local color = Color3.fromHSV((now / RAINBOW_CYCLE_SECONDS) % 1, RAINBOW_SATURATION, RAINBOW_VALUE)
	for part in rainbows do
		if (part.Position - cameraPosition).Magnitude <= ANIMATE_RADIUS then
			part.Color = color
		end
	end
end

local function stepSwirls(dt: number, cameraPosition: Vector3, now: number)
	local P = PlotLayout.RebirthPortal
	for _, swirl in swirls do
		if (swirl.Sheet.Position - cameraPosition).Magnitude <= ANIMATE_RADIUS then
			local ready = swirl.Portal:GetAttribute(PortalKit.READY_ATTRIBUTE) == true
			local transparency = if ready then 0 else P.SwirlIdleTransparency
			for _, frame in swirl.Frames do
				frame.BackgroundTransparency = transparency
			end
			if ready then
				for _, gradient in swirl.Gradients do
					gradient.Rotation = (gradient.Rotation + P.SwirlDegPerSec * dt) % 360
				end
			end
			if swirl.RingStroke then
				local pulse = 0.5 * (1 - math.cos((now % P.RingPulsePeriod) / P.RingPulsePeriod * math.pi * 2))
				swirl.RingStroke.Transparency = if ready then pulse * 0.6 else 0
			end
		end
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local now = os.clock()
	stepSwirls(dt, cameraPosition, now)
	stepRainbows(cameraPosition, now)
	for target, entry in entries do
		if (entry.Base.Position - cameraPosition).Magnitude <= ANIMATE_RADIUS then
			local cframe = entry.Base * offsetFor(target, now + entry.Phase)
			if target:IsA("Model") then
				target:PivotTo(cframe)
			elseif target:IsA("BasePart") then
				target.CFrame = cframe
			end
		end
	end
	stepOrbits(cameraPosition, now)
end

function WorldAnimationController.Init()
	for _, target in CollectionService:GetTagged(PartKit.HOVER_TAG) do
		track(target)
	end
	CollectionService:GetInstanceAddedSignal(PartKit.HOVER_TAG):Connect(function(target)
		-- Models arrive before their parts have streamed in; give it a frame.
		task.defer(track, target)
	end)
	CollectionService:GetInstanceRemovedSignal(PartKit.HOVER_TAG):Connect(untrack)

	for _, sheet in CollectionService:GetTagged(PortalKit.SWIRL_TAG) do
		trackSwirl(sheet)
	end
	CollectionService:GetInstanceAddedSignal(PortalKit.SWIRL_TAG):Connect(function(sheet)
		task.defer(trackSwirl, sheet)
	end)
	for _, model in CollectionService:GetTagged(PartKit.ORBIT_TAG) do
		task.defer(trackOrbit, model)
	end
	CollectionService:GetInstanceAddedSignal(PartKit.ORBIT_TAG):Connect(function(model)
		-- The satellites replicate with the model; give them a frame.
		task.defer(trackOrbit, model)
	end)
	CollectionService:GetInstanceRemovedSignal(PartKit.ORBIT_TAG):Connect(function(model)
		orbits[model] = nil
	end)

	local function trackRainbow(part: Instance)
		if part:IsA("BasePart") then
			rainbows[part] = true
		end
	end
	for _, part in CollectionService:GetTagged(PartKit.RAINBOW_TAG) do
		trackRainbow(part)
	end
	CollectionService:GetInstanceAddedSignal(PartKit.RAINBOW_TAG):Connect(trackRainbow)
	CollectionService:GetInstanceRemovedSignal(PartKit.RAINBOW_TAG):Connect(function(part)
		rainbows[part :: BasePart] = nil
	end)

	CollectionService:GetInstanceRemovedSignal(PortalKit.SWIRL_TAG):Connect(function(sheet)
		swirls[sheet] = nil
	end)
	RunService.RenderStepped:Connect(step)
end

return WorldAnimationController
