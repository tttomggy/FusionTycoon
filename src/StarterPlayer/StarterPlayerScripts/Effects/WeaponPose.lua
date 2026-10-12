--!strict
--[[
	WeaponPose
	----------
	Procedural arm poses for the weapons: no animation uploads. Every pose
	is a rotation of the character's RIGHT SHOULDER added on top of whatever
	the Animate script plays (the tool-hold arm), written every frame from
	RenderStepped, so it is purely local: other players run the same pose
	for you from the HitFx you cause.

	The offset rides Motor6D.C0 (the shoulder frame, torso space) rather
	than Motor6D.Transform: the Animator rewrites Transform on its own step,
	so a Transform edit made here can be overwritten before it is drawn,
	while nothing ever writes C0 back. The pose is the same either way
	(C0 * delta * Transform).

	  Equip(c)          a quick 0.15 s raise
	  Swing(c, kind)    "Bat" | "SlapGlove": wind back, then a fast arc
	                    across (about 0.35 s)
	  Recoil(c)         a 0.1 s gun kick
	  Throw(c)          the Banana Peel: a short overhand toss
	  SetAim(c, on, pitch?)   guns: the arm held out, pitched at the aim
	  Clear(c)          drop everything, restore the joint

	R15 only (an R6 rig or an avatar without the joint is left alone).
]]
local RunService = game:GetService("RunService")

local WeaponPose = {}

local EQUIP_SECONDS = 0.15
local EQUIP_DROP = 0.9 -- radians the arm starts below its hold pose
local RECOIL_SECONDS = 0.1
local RECOIL_KICK = 0.4
local THROW_SECONDS = 0.3
local AIM_BLEND_SECONDS = 0.12
local AIM_PITCH_LIMIT = 0.9
local AIM_PITCH_SMOOTH = 14

-- name -> { Wind = {pitch, yaw, roll}, Arc = {...}, Wind/Arc/Settle seconds }
export type SwingShape = {
	Wind: Vector3,
	Arc: Vector3,
	WindSeconds: number,
	ArcSeconds: number,
	SettleSeconds: number,
}

local SWINGS: { [string]: SwingShape } = {
	-- Raised and cocked back to the right, then across and down to the left.
	Bat = {
		Wind = Vector3.new(0.55, -1.0, 0.25),
		Arc = Vector3.new(-0.35, 1.15, 0),
		WindSeconds = 0.1,
		ArcSeconds = 0.14,
		SettleSeconds = 0.11,
	},
	-- A flat backhand slap.
	SlapGlove = {
		Wind = Vector3.new(0.25, -1.25, 0),
		Arc = Vector3.new(0, 1.0, 0),
		WindSeconds = 0.1,
		ArcSeconds = 0.13,
		SettleSeconds = 0.12,
	},
}

type State = {
	Motor: Motor6D,
	BaseC0: CFrame,
	EquipAt: number?,
	SwingAt: number?,
	Swing: SwingShape?,
	RecoilAt: number?,
	ThrowAt: number?,
	Aim: boolean,
	AimBlend: number,
	AimPitch: number,
	AimTarget: number,
}

local states: { [Model]: State } = {}
local connection: RBXScriptConnection? = nil

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

local function getState(character: Model): State?
	local state = states[character]
	if state then
		return state
	end
	local motor = findShoulder(character)
	if not motor then
		return nil
	end
	local created: State = {
		Motor = motor,
		BaseC0 = motor.C0,
		Aim = false,
		AimBlend = 0,
		AimPitch = 0,
		AimTarget = 0,
	}
	states[character] = created
	return created
end

local function angles(v: Vector3): CFrame
	-- Yaw about the torso's vertical, then pitch, then roll: a sideways
	-- sweep stays level.
	return CFrame.fromOrientation(v.X, v.Y, v.Z)
end

local function lerpVector(a: Vector3, b: Vector3, t: number): Vector3
	return a:Lerp(b, t)
end

-- The swing's offset (pitch, yaw, roll) at `elapsed`; nil once it is over.
local function swingOffset(shape: SwingShape, elapsed: number): Vector3?
	local windEnd = shape.WindSeconds
	local arcEnd = windEnd + shape.ArcSeconds
	local settleEnd = arcEnd + shape.SettleSeconds
	if elapsed >= settleEnd then
		return nil
	elseif elapsed < windEnd then
		return lerpVector(Vector3.zero, shape.Wind, easeOut(elapsed / windEnd))
	elseif elapsed < arcEnd then
		return lerpVector(shape.Wind, shape.Arc, easeIn((elapsed - windEnd) / shape.ArcSeconds))
	end
	return lerpVector(shape.Arc, Vector3.zero, easeOut((elapsed - arcEnd) / shape.SettleSeconds))
end

-- True while the state still has something to show.
local function stepState(state: State, now: number, dt: number): boolean
	local offset = CFrame.new()
	local busy = false

	local equipAt = state.EquipAt
	if equipAt then
		local t = (now - equipAt) / EQUIP_SECONDS
		if t >= 1 then
			state.EquipAt = nil
		else
			offset = offset * angles(Vector3.new(-EQUIP_DROP * (1 - easeOut(t)), 0, 0))
			busy = true
		end
	end

	local swingAt, shape = state.SwingAt, state.Swing
	if swingAt and shape then
		local value = swingOffset(shape, now - swingAt)
		if value then
			offset = offset * angles(value)
			busy = true
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
			offset = offset * angles(Vector3.new(RECOIL_KICK * (1 - t) * (1 - t), 0, 0))
			busy = true
		end
	end

	local throwAt = state.ThrowAt
	if throwAt then
		local t = (now - throwAt) / THROW_SECONDS
		if t >= 1 then
			state.ThrowAt = nil
		else
			-- Up and back, then forward and down.
			local pitch = if t < 0.4 then 1.1 * easeOut(t / 0.4) else 1.1 - 1.7 * easeIn((t - 0.4) / 0.6)
			offset = offset * angles(Vector3.new(pitch, 0, 0))
			busy = true
		end
	end

	-- Aim: blend in, follow the aim pitch.
	local blendTarget = if state.Aim then 1 else 0
	if state.AimBlend ~= blendTarget then
		local step = dt / AIM_BLEND_SECONDS
		state.AimBlend = if blendTarget > state.AimBlend then math.min(1, state.AimBlend + step) else math.max(0, state.AimBlend - step)
	end
	if state.AimBlend > 0 then
		state.AimPitch += (state.AimTarget - state.AimPitch) * math.min(1, dt * AIM_PITCH_SMOOTH)
		offset = offset * angles(Vector3.new(state.AimPitch * state.AimBlend, 0.12 * state.AimBlend, 0))
		busy = true
	end

	if busy then
		state.Motor.C0 = state.BaseC0 * offset
	end
	return busy
end

local function release(character: Model, state: State)
	if state.Motor.Parent then
		state.Motor.C0 = state.BaseC0
	end
	states[character] = nil
end

local function step(dt: number)
	local now = os.clock()
	for character, state in states do
		if not character.Parent or not state.Motor.Parent then
			states[character] = nil
		elseif not stepState(state, now, dt) then
			release(character, state)
		end
	end
	if next(states) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function ensureRunning()
	if not connection then
		connection = RunService.RenderStepped:Connect(step)
	end
end

--[[ Public API ------------------------------------------------------------------------ ]]

function WeaponPose.Equip(character: Model)
	local state = getState(character)
	if state then
		state.EquipAt = os.clock()
		ensureRunning()
	end
end

-- Returns the swing's length in seconds (0 for an unknown kind).
function WeaponPose.Swing(character: Model, kind: string): number
	local shape = SWINGS[kind]
	local state = if shape then getState(character) else nil
	if not state or not shape then
		return 0
	end
	state.SwingAt = os.clock()
	state.Swing = shape
	ensureRunning()
	return shape.WindSeconds + shape.ArcSeconds + shape.SettleSeconds
end

function WeaponPose.GetSwingSeconds(kind: string): number
	local shape = SWINGS[kind]
	return if shape then shape.WindSeconds + shape.ArcSeconds + shape.SettleSeconds else 0
end

function WeaponPose.Recoil(character: Model)
	local state = getState(character)
	if state then
		state.RecoilAt = os.clock()
		ensureRunning()
	end
end

function WeaponPose.Throw(character: Model)
	local state = getState(character)
	if state then
		state.ThrowAt = os.clock()
		ensureRunning()
	end
end

-- Hold the aim pose (guns) while `on`; `pitch` is radians above level.
function WeaponPose.SetAim(character: Model, on: boolean, pitch: number?)
	local state = if on then getState(character) else states[character]
	if not state then
		return
	end
	state.Aim = on
	if pitch then
		state.AimTarget = math.clamp(pitch, -AIM_PITCH_LIMIT, AIM_PITCH_LIMIT)
	end
	ensureRunning()
end

function WeaponPose.Clear(character: Model)
	local state = states[character]
	if state then
		release(character, state)
	end
end

-- /selftest: the pose currently applied to this character's shoulder (nil
-- when none is active).
function WeaponPose.IsActive(character: Model): boolean
	return states[character] ~= nil
end

return WeaponPose
