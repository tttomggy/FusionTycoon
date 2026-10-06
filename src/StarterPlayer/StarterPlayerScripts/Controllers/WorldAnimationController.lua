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

	The resting pose is the server's HoverBase attribute (PartKit.SetHover
	stamps it at the final position), never a "first seen" pose: with
	streaming a Model arrives before its parts, its pivot was then the
	origin, and PivotTo dragged pedestal orbs and generator cores into the
	middle of the street every frame. Each part is placed relative to
	HoverBase from the CFrame it arrived with (the server never moves it),
	so parts that stream in late, or out and back, land right; satellites
	(FT_Orbit) are left to the orbit step. One BulkMoveTo per frame; only
	targets within ANIMATE_RADIUS of the camera move.

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
	Base: CFrame?, -- nil until a pose is known (a legacy target with no parts yet)
	Phase: number, -- desyncs neighbours that share the same timing
	Parts: { [BasePart]: CFrame }, -- each part relative to Base
	Connections: { RBXScriptConnection },
}

local entries: { [Instance]: Entry } = {}
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

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

-- Satellites (inside an FT_Orbit model) move with the orbit step instead.
local function inOrbit(part: Instance, root: Instance): boolean
	local current = part.Parent
	while current and current ~= root do
		if current:HasTag(PartKit.ORBIT_TAG) then
			return true
		end
		current = current.Parent
	end
	return false
end

local function addPart(entry: Entry, part: BasePart)
	local base = entry.Base
	if base and not entry.Parts[part] and not inOrbit(part, entry.Target) then
		-- The CFrame it arrived with is its rest pose (the server never
		-- animates it).
		entry.Parts[part] = base:ToObjectSpace(part.CFrame)
	end
end

local function setBase(entry: Entry, base: CFrame)
	entry.Base = base
	entry.Phase = (math.abs(base.Position.X) + math.abs(base.Position.Z)) % 7
	local target = entry.Target
	if target:IsA("BasePart") then
		addPart(entry, target)
	else
		for _, descendant in target:GetDescendants() do
			if descendant:IsA("BasePart") then
				addPart(entry, descendant)
			end
		end
	end
end

local function untrack(target: Instance)
	local entry = entries[target]
	if entry then
		for _, connection in entry.Connections do
			connection:Disconnect()
		end
		entries[target] = nil
	end
end

local function track(target: Instance)
	if entries[target] or not target:IsDescendantOf(Workspace) or not (target:IsA("BasePart") or target:IsA("Model")) then
		return
	end
	local entry: Entry = { Target = target :: any, Base = nil, Phase = 0, Parts = {}, Connections = {} }
	entries[target] = entry
	local function readBase()
		local stamped = target:GetAttribute(PartKit.HOVER_BASE_ATTRIBUTE)
		if typeof(stamped) == "CFrame" then
			-- A server move re-stamps it: the parts keep their offsets.
			setBase(entry, stamped)
		elseif not entry.Base then
			-- Legacy (no stamp): only once a part is really here.
			local pose = PartKit.GetRestPose(target)
			if pose then
				setBase(entry, pose)
			end
		end
	end
	readBase()
	table.insert(entry.Connections, target:GetAttributeChangedSignal(PartKit.HOVER_BASE_ATTRIBUTE):Connect(readBase))
	if target:IsA("Model") then
		table.insert(
			entry.Connections,
			target.DescendantAdded:Connect(function(descendant)
				if descendant:IsA("BasePart") then
					if entry.Base then
						addPart(entry, descendant)
					else
						readBase()
					end
				end
			end)
		)
		table.insert(
			entry.Connections,
			target.DescendantRemoving:Connect(function(descendant)
				if descendant:IsA("BasePart") then
					entry.Parts[descendant] = nil
				end
			end)
		)
	end
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
	table.clear(moveParts)
	table.clear(moveCFrames)
	for target, entry in entries do
		local base = entry.Base
		if base and (base.Position - cameraPosition).Magnitude <= ANIMATE_RADIUS then
			local cframe = base * offsetFor(target, now + entry.Phase)
			for part, relative in entry.Parts do
				table.insert(moveParts, part)
				table.insert(moveCFrames, cframe * relative)
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
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
