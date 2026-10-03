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
	CollectionService:GetInstanceRemovedSignal(PortalKit.SWIRL_TAG):Connect(function(sheet)
		swirls[sheet] = nil
	end)
	RunService.RenderStepped:Connect(step)
end

return WorldAnimationController
