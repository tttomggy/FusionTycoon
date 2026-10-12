--!strict
--[[
	WeaponFx
	--------
	The little pieces of weapon feedback, all client-only and short-lived
	(CombatController decides when; colours come from UITheme):

	  Trail(tool, color, seconds)   a ribbon between the weapon's TrailA /
	                                TrailB for the swing only
	  FlashRing(position, color)    the white ring where a melee hit lands
	  MuzzleFlash(tool, color)      PointLight + a small Neon burst
	  Beam(from, to, color, ...)    a thin Neon cylinder seen from the side
	  FreezeCone(from, to)          an icy cone of sparkle "snowflakes"
	  Impact(position, color)       a tiny burst where a shot ends
	  Frost.On / Off(character)     frost particles on a frozen player
	  Throw(from, to)               the Banana Peel's arc (a banana model)

	No flat Neon circles: the beam is a cylinder seen from the side, the
	burst a Neon ball, the ring a GUI circle on a camera-facing Billboard.
]]
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local WeaponKit = require(ReplicatedStorage.Shared.Modules.WeaponKit)

local WeaponFx = {}
WeaponFx.Frost = {}

local World = UITheme.World

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local BEAM_THICKNESS = 0.25
local THROW_SECONDS = 0.5
local THROW_HEIGHT = 5

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

-- An invisible anchored point in Terrain that carries lights / emitters.
local function anchorAt(cframe: CFrame, lifetime: number): Part
	local part = Instance.new("Part")
	part.Name = "WeaponFxAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = cframe
	part.Parent = Workspace.Terrain
	Debris:AddItem(part, lifetime)
	return part
end

--[[ Swing trail ---------------------------------------------------------------------- ]]

-- A Trail between the tool's TrailA / TrailB while `seconds` last, then it
-- fades out (it stops emitting and the ribbon's lifetime runs off).
function WeaponFx.Trail(tool: Instance, color: Color3, seconds: number)
	local handle = WeaponKit.GetHandle(tool)
	local a, b = WeaponKit.GetTrailPoints(tool)
	if not handle or not a or not b then
		return
	end
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = a
	trail.Attachment1 = b
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 0.8
	trail.LightInfluence = 0
	trail.Lifetime = 0.22
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Parent = handle
	task.delay(seconds, function()
		trail.Enabled = false
	end)
	Debris:AddItem(trail, seconds + 0.5)
end

--[[ Rings, flashes, bursts ---------------------------------------------------------- ]]

-- A white ring that opens and fades where a melee hit lands (a circle
-- stroke on a camera-facing Billboard: never a flat Neon disc).
function WeaponFx.FlashRing(position: Vector3, color: Color3)
	local anchor = anchorAt(CFrame.new(position + Vector3.new(0, 1.5, 0)), 0.5)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(60, 60)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Adornee = anchor
	gui.Parent = anchor
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.3, 0.3)
	ring.BackgroundTransparency = 1
	ring.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 6
	stroke.Parent = ring
	tween(ring, 0.3, { Size = UDim2.fromScale(1, 1) })
	tween(stroke, 0.3, { Thickness = 1, Transparency = 1 })
end

-- A Neon ball that swells and fades (a muzzle burst, a shot's impact).
local function burst(position: Vector3, color: Color3, from: number, to: number, seconds: number)
	local part = Instance.new("Part")
	part.Name = "WeaponBurst"
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(from, from, from)
	part.Position = position
	part.Parent = Workspace.Terrain
	tween(part, seconds, { Size = Vector3.new(to, to, to), Transparency = 1 })
	Debris:AddItem(part, seconds + 0.1)
end

function WeaponFx.Impact(position: Vector3, color: Color3)
	burst(position, color, 0.5, 1.6, 0.18)
end

-- PointLight + a small Neon burst + a few sparks at the tool's Muzzle.
function WeaponFx.MuzzleFlash(tool: Instance, color: Color3)
	local muzzle = WeaponKit.GetMuzzle(tool)
	if not muzzle then
		return
	end
	local position = muzzle.WorldPosition
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2
	light.Range = 10
	light.Shadows = false
	light.Parent = muzzle
	Debris:AddItem(light, 0.1)
	burst(position, color, 0.5, 1.2, 0.1)
	local anchor = anchorAt(CFrame.new(position), 0.6)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARKLE
	sparks.Color = ColorSequence.new(color)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.15, 0.3)
	sparks.Speed = NumberRange.new(8, 14)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Rate = 0
	sparks.Parent = anchor
	sparks:Emit(8)
end

--[[ Beams ------------------------------------------------------------------------------ ]]

-- A thin Neon cylinder between two points (seen from the side, never a
-- flat circle facing up), gone in `seconds`.
function WeaponFx.Beam(from: Vector3, to: Vector3, color: Color3, seconds: number, thickness: number?)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local width = thickness or BEAM_THICKNESS
	local part = Instance.new("Part")
	part.Name = "WeaponBeam"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(length, width, width)
	part.CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0)
	part.Parent = Workspace.Terrain
	tween(part, seconds, { Transparency = 1, Size = Vector3.new(length, width * 0.3, width * 0.3) })
	Debris:AddItem(part, seconds + 0.1)
end

-- An icy cone of sparkle "snowflakes" from `from` toward `to`.
function WeaponFx.FreezeCone(from: Vector3, to: Vector3)
	local direction = to - from
	if direction.Magnitude < 0.1 then
		return
	end
	local anchor = anchorAt(CFrame.lookAt(from, to), 1)
	local cone = Instance.new("ParticleEmitter")
	cone.Texture = SPARKLE
	cone.Color = ColorSequence.new(World.IceWhite, World.Ice)
	cone.LightEmission = 0.8
	cone.LightInfluence = 0
	cone.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.2) })
	cone.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	cone.Lifetime = NumberRange.new(0.35, 0.6)
	cone.Speed = NumberRange.new(30, 46)
	cone.SpreadAngle = Vector2.new(18, 18)
	cone.Rotation = NumberRange.new(0, 360)
	cone.RotSpeed = NumberRange.new(-120, 120)
	cone.EmissionDirection = Enum.NormalId.Front
	cone.Rate = 0
	cone.Parent = anchor
	cone:Emit(36)
end

--[[ Frost on a frozen player ---------------------------------------------------------- ]]

local frost: { [Model]: ParticleEmitter } = setmetatable({}, { __mode = "k" }) :: any

function WeaponFx.Frost.On(character: Model)
	if frost[character] then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FrostParticles"
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(World.IceWhite, World.Ice)
	emitter.LightEmission = 0.6
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(0.5, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -3, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Rate = 22
	emitter.Parent = root
	frost[character] = emitter
end

function WeaponFx.Frost.Off(character: Model)
	local emitter = frost[character]
	if emitter then
		emitter.Enabled = false
		Debris:AddItem(emitter, 1.2)
		frost[character] = nil
	end
end

--[[ Banana Peel throw ----------------------------------------------------------------- ]]

-- A banana flies from `from` to `to` in a spinning arc and is gone on landing.
function WeaponFx.Throw(from: Vector3, to: Vector3)
	local banana = WeaponKit.BuildModel("BananaPeel")
	banana.Parent = Workspace.Terrain
	local started = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - started) / THROW_SECONDS, 0, 1)
		local position = from:Lerp(to, t) + Vector3.new(0, THROW_HEIGHT * 4 * t * (1 - t), 0)
		banana:PivotTo(CFrame.new(position) * CFrame.Angles(t * math.pi * 6, 0, 0))
		if t >= 1 then
			if connection then
				connection:Disconnect()
			end
			banana:Destroy()
		end
	end)
end

WeaponFx.THROW_SECONDS = THROW_SECONDS

return WeaponFx
