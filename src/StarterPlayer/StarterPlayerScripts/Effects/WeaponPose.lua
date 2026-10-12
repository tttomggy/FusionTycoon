--!strict
--[[
	WeaponPose
	----------
	The right arm while a weapon is out, and its swings. Procedural, no
	animation uploads, and purely local: every client runs it for every
	character that holds a weapon (yours from your click, theirs from the
	HitFx you cause).

	THE POSE IS ABSOLUTE. While a weapon is in the hand this module sets the
	RightShoulder's Motor6D.Transform to the whole arm pose (hold + swing /
	recoil / toss), not an offset on top of whatever Animate plays. So it
	cannot "fight" the tool-hold animation (Animate's `toolnone` plays at
	Idle priority and the idle / run animations override its arm anyway):
	the shoulder is ours while we hold, the Animator keeps the elbow and
	everything else, and when the weapon goes away we stop writing and the
	Animator takes the arm back by itself.

	The Animator rewrites Transform on its own step of the frame and the
	engine reads it again at the physics step, so the same value is written
	at RenderStepped, Stepped (PreSimulation) and Heartbeat: whichever of
	them lands after the Animator and before the next draw wins, and since
	the pose is absolute, writing it three times is harmless.

	  Hold(c, weapon)      the weapon came up: the 0.15 s raise, then the
	                       held pose (guns: arm straight out, aimed)
	  Release(c)           the weapon is gone: stop writing, restore
	  Swing(c, id)         "Bat" | "SlapGlove": wind back, then a big fast arc
	                       across (about 0.35 s)
	  Recoil(c)            a 0.1 s gun kick
	  Throw(c)             the Banana Peel's overhand toss
	  SetAimPitch(c, rad)  where a gun is aimed (pitch only)

	/selftest: GetArmDirection(c) (where the arm points, in torso space) and
	GetRestDirection(c) (where it would hang). R15 only.
]]
local RunService = game:GetService("RunService")

local CombatConfig = require(game:GetService("ReplicatedStorage").Shared.Config.CombatConfig)

local WeaponPose = {}

local EQUIP_SECONDS = 0.15
local RECOIL_SECONDS = 0.1
local RECOIL_KICK = 0.4
local THROW_SECONDS = 0.3
local AIM_PITCH_LIMIT = 0.9
local AIM_PITCH_SMOOTH = 14
local GUN_YAW = 0.12 -- a little across the body, like a two-handed stance

-- Arm elevation while held (radians above hanging straight down; pi/2 =
-- straight out in front).
local HOLD_PITCH: { [string]: number } = {
	Bat = 1.25, -- raised, the bat up and forward
	SlapGlove = 1.45, -- hand out, ready to slap
	BananaPeel = 1.3,
}
local GUN_HOLD_PITCH = math.pi / 2

export type SwingShape = {
	Wind: Vector3, -- pitch, yaw, roll offsets from the hold at the end of the wind-up
	Arc: Vector3, -- ... at the end of the fast arc
	WindSeconds: number,
	ArcSeconds: number,
	SettleSeconds: number,
}

local SWINGS: { [string]: SwingShape } = {
	-- Raised and cocked back to the right, then a big arc across and down to
	-- the left.
	Bat = {
		Wind = Vector3.new(0.5, -1.35, 0.3),
		Arc = Vector3.new(-0.45, 1.5, 0),
		WindSeconds = 0.1,
		ArcSeconds = 0.14,
		SettleSeconds = 0.11,
	},
	-- A flat backhand slap.
	SlapGlove = {
		Wind = Vector3.new(0.2, -1.4, 0),
		Arc = Vector3.new(0, 1.35, 0),
		WindSeconds = 0.1,
		ArcSeconds = 0.13,
		SettleSeconds = 0.12,
	},
}

type State = {
	Motor: Motor6D,
	WeaponId: string,
	Gun: boolean,
	HoldPitch: number,
	HeldAt: number,
	SwingAt: number?,
	Swing: SwingShape?,
	RecoilAt: number?,
	ThrowAt: number?,
	AimPitch: number,
	AimTarget: number,
	Pose: CFrame, -- the last computed Transform
}

local states: { [Model]: State } = {}
local connections: { RBXScriptConnection } = {}
local lastStep = os.clock()

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function easeIn(t: number): number
	return t * t
end

local function findShoulder(character: Model): Motor6D?
	local arm = character:FindFirstChild("RightUpperArm")
	local motor = arm and arm:FindFirstChild("RightShoulder")
	return if motor and motor:IsA("Motor6D") then motor else nil
end

-- The pose in the torso's axes (pitch, yaw, roll), turned into the
-- Transform the joint needs: Transform acts inside C0's frame, so an avatar
-- whose shoulder C0 is rotated still raises its arm FORWARD.
local function transformFor(motor: Motor6D, pitch: number, yaw: number, roll: number): CFrame
	local rotation = motor.C0 - motor.C0.Position
	return rotation:Inverse() * CFrame.fromOrientation(pitch, yaw, roll) * rotation
end

-- The swing's offsets at `elapsed`; nil once it is over.
local function swingOffset(shape: SwingShape, elapsed: number): Vector3?
	local windEnd = shape.WindSeconds
	local arcEnd = windEnd + shape.ArcSeconds
	if elapsed >= arcEnd + shape.SettleSeconds then
		return nil
	elseif elapsed < windEnd then
		return Vector3.zero:Lerp(shape.Wind, easeOut(elapsed / windEnd))
	elseif elapsed < arcEnd then
		return shape.Wind:Lerp(shape.Arc, easeIn((elapsed - windEnd) / shape.ArcSeconds))
	end
	return shape.Arc:Lerp(Vector3.zero, easeOut((elapsed - arcEnd) / shape.SettleSeconds))
end

-- Computes the state's pose for this frame (RenderStepped only: it
-- integrates the aim smoothing with dt).
local function compute(state: State, now: number, dt: number)
	local pitch, yaw, roll = state.HoldPitch, 0, 0

	-- The raise from hanging down to the held pose.
	local raise = (now - state.HeldAt) / EQUIP_SECONDS
	if raise < 1 then
		pitch = state.HoldPitch * easeOut(math.max(raise, 0))
	end

	if state.Gun then
		state.AimPitch += (state.AimTarget - state.AimPitch) * math.min(1, dt * AIM_PITCH_SMOOTH)
		pitch += state.AimPitch
		yaw += GUN_YAW
	end

	local swingAt, shape = state.SwingAt, state.Swing
	if swingAt and shape then
		local offset = swingOffset(shape, now - swingAt)
		if offset then
			pitch += offset.X
			yaw += offset.Y
			roll += offset.Z
		else
			state.SwingAt, state.Swing = nil, nil
		end
	end

	local recoilAt = state.RecoilAt
	if recoilAt then
		local t = (now - recoilAt) / RECOIL_SECONDS
		if t >= 1 then
			state.RecoilAt = nil
		else
			pitch += RECOIL_KICK * (1 - t) * (1 - t)
		end
	end

	local throwAt = state.ThrowAt
	if throwAt then
		local t = (now - throwAt) / THROW_SECONDS
		if t >= 1 then
			state.ThrowAt = nil
		else
			-- Up and back, then forward and down.
			pitch += if t < 0.4 then 1.1 * easeOut(t / 0.4) else 1.1 - 1.7 * easeIn((t - 0.4) / 0.6)
		end
	end

	state.Pose = transformFor(state.Motor, pitch, yaw, roll)
end

local function apply()
	for character, state in states do
		if not character.Parent or not state.Motor.Parent then
			states[character] = nil
		else
			state.Motor.Transform = state.Pose
		end
	end
end

local function stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function onRender()
	local now = os.clock()
	local dt = math.min(now - lastStep, 0.1)
	lastStep = now
	for character, state in states do
		if not character.Parent or not state.Motor.Parent then
			states[character] = nil
		else
			compute(state, now, dt)
		end
	end
	apply()
	if next(states) == nil then
		stop()
	end
end

local function ensureRunning()
	if #connections > 0 then
		return
	end
	lastStep = os.clock()
	table.insert(connections, RunService.RenderStepped:Connect(onRender))
	table.insert(connections, RunService.Stepped:Connect(apply))
	table.insert(connections, RunService.Heartbeat:Connect(apply))
end

--[[ Public API ------------------------------------------------------------------------ ]]

-- A weapon came up in `character`'s hand.
function WeaponPose.Hold(character: Model, weapon: CombatConfig.Weapon)
	local motor = findShoulder(character)
	if not motor then
		return
	end
	local old = states[character]
	if old then
		-- Switching straight from one weapon to another: nothing to restore.
		old.Motor.Transform = CFrame.new()
	end
	local gun = weapon.Kind == "Ranged" or weapon.Kind == "Freeze"
	local state: State = {
		Motor = motor,
		WeaponId = weapon.Id,
		Gun = gun,
		HoldPitch = if gun then GUN_HOLD_PITCH else (HOLD_PITCH[weapon.Id] or 1.3),
		HeldAt = os.clock(),
		AimPitch = 0,
		AimTarget = 0,
		Pose = CFrame.new(),
	}
	states[character] = state
	compute(state, os.clock(), 0)
	state.Motor.Transform = state.Pose
	ensureRunning()
end

-- The weapon is gone: stop writing; the Animator takes the arm back.
function WeaponPose.Release(character: Model)
	local state = states[character]
	if state then
		states[character] = nil
		if state.Motor.Parent then
			state.Motor.Transform = CFrame.new()
		end
	end
end

function WeaponPose.IsHolding(character: Model): boolean
	return states[character] ~= nil
end

-- Returns the swing's length in seconds (0 for a weapon that doesn't swing).
function WeaponPose.Swing(character: Model, weaponId: string): number
	local shape = SWINGS[weaponId]
	local state = states[character]
	if not shape or not state then
		return 0
	end
	state.SwingAt = os.clock()
	state.Swing = shape
	return shape.WindSeconds + shape.ArcSeconds + shape.SettleSeconds
end

function WeaponPose.Recoil(character: Model)
	local state = states[character]
	if state then
		state.RecoilAt = os.clock()
	end
end

function WeaponPose.Throw(character: Model)
	local state = states[character]
	if state then
		state.ThrowAt = os.clock()
	end
end

-- Where a gun is aimed: radians above level (pitch only).
function WeaponPose.SetAimPitch(character: Model, pitch: number)
	local state = states[character]
	if state and state.Gun then
		state.AimTarget = math.clamp(pitch, -AIM_PITCH_LIMIT, AIM_PITCH_LIMIT)
	end
end

--[[ /selftest -------------------------------------------------------------------------- ]]

-- Where the right arm points now, in the torso's axes (the shoulder's C0 and
-- Transform applied to "straight down"). nil without an R15 shoulder.
function WeaponPose.GetArmDirection(character: Model): Vector3?
	local motor = findShoulder(character)
	if not motor then
		return nil
	end
	return (motor.C0 * motor.Transform):VectorToWorldSpace(Vector3.new(0, -1, 0))
end

-- Where it would hang with no pose at all.
function WeaponPose.GetRestDirection(character: Model): Vector3?
	local motor = findShoulder(character)
	if not motor then
		return nil
	end
	return motor.C0:VectorToWorldSpace(Vector3.new(0, -1, 0))
end

return WeaponPose
