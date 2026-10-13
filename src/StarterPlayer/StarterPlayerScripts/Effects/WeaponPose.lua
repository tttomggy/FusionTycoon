--!strict
--[[
	WeaponPose
	----------
	The right arm while a weapon is out, and its swings. Procedural, no
	animation uploads, and purely local: every client runs it for every
	character that holds a weapon (yours from your click, theirs from the
	HitFx you cause).

	THE POSE GOES THROUGH THE JOINT'S C0, NEVER Transform. In 2026 Roblox
	ignores client writes to Motor6D.Transform while an animation plays (fixed
	simulation / Server Authority), and an Avatar Joint Upgrade rig may drive
	the shoulder through an AnimationConstraint instead. The Animator never
	touches C0 (or an Attachment's CFrame), so those writes always show.
	While a weapon is held: joint = BaseC0 rotated by the pose, position kept.
	BaseC0 (a stored attribute on the joint, like the BaseSize rule) is the
	untouched value; the pose is NEVER built from the live C0, or it would
	compound. Release / respawn / weapon switch restore BaseC0 and clear the
	attribute. The Animator keeps writing Transform, so walk / idle sway adds
	on top of our pose, and Animate's `toolnone` track (which raises the arm
	in Transform too) is stopped while we hold.

	  Hold(c, weapon)      the weapon came up: the 0.15 s raise, then the
	                       held pose (guns: arm straight out, aimed)
	  Release(c, id?)      the weapon is gone: restore BaseC0 (only if `id` is
	                       the held weapon: a slot switch fires the new tool's
	                       ChildAdded before the old one's ChildRemoved)
	  Swing(c, id)         "Bat" | "SlapGlove": wind back, hold, a big fast arc
	                       across, follow-through, settle (about 0.7 s); the
	                       Waist twists and the RightElbow snaps straight too
	  Recoil(c)            a 0.1 s gun kick
	  Throw(c)             the Banana Peel's overhand toss
	  SetAimPitch(c, rad)  where a gun is aimed (pitch only)

	/selftest: GetHandOffset(c) = RightHand.Position in UpperTorso space (what
	is DRAWN, read after the joints solve) and HasBaseStored(c). R15 only.
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

-- One keyframe of a swing, as offsets from the hold.
export type SwingKey = {
	Arm: Vector3, -- shoulder pitch, yaw, roll (torso axes)
	Waist: number, -- Waist twist about the spine (negative = to the right)
	Elbow: number, -- RightElbow bend (0 = straight)
}

-- wind -> hold at the top -> arc (accelerating) -> follow-through -> settle.
export type SwingShape = {
	Wind: SwingKey,
	Arc: SwingKey, -- the end of the fast arc (the impact: elbow snapped straight)
	Follow: SwingKey, -- past the left hip
	WindSeconds: number,
	HoldSeconds: number,
	ArcSeconds: number,
	FollowSeconds: number,
	SettleSeconds: number,
}

local SWINGS: { [string]: SwingShape } = {
	-- Raised and cocked back over the right shoulder, a beat at the top, a big
	-- sweep down and across to the left, through past the left hip. 0.68 s.
	Bat = {
		Wind = { Arm = Vector3.new(0.55, -1.4, 0.3), Waist = -0.5, Elbow = 0.6 },
		Arc = { Arm = Vector3.new(-0.5, 1.5, 0), Waist = 0.6, Elbow = 0 },
		Follow = { Arm = Vector3.new(-0.75, 2.0, 0), Waist = 0.75, Elbow = 0.15 },
		WindSeconds = 0.18,
		HoldSeconds = 0.06,
		ArcSeconds = 0.14,
		FollowSeconds = 0.1,
		SettleSeconds = 0.2,
	},
	-- A wide, flat backhand at shoulder height, same shape.
	SlapGlove = {
		Wind = { Arm = Vector3.new(0.1, -1.5, 0), Waist = -0.45, Elbow = 0.45 },
		Arc = { Arm = Vector3.new(0, 1.4, 0), Waist = 0.55, Elbow = 0 },
		Follow = { Arm = Vector3.new(-0.1, 1.85, 0), Waist = 0.7, Elbow = 0.1 },
		WindSeconds = 0.18,
		HoldSeconds = 0.06,
		ArcSeconds = 0.13,
		FollowSeconds = 0.1,
		SettleSeconds = 0.2,
	},
}

local ZERO_KEY: SwingKey = { Arm = Vector3.zero, Waist = 0, Elbow = 0 }

-- A joint we pose: a Motor6D (C0) or, on an Avatar Joint Upgrade rig, the
-- AnimationConstraint's Attachment0 (CFrame).
type Joint = {
	Instance: Instance, -- the Motor6D, or Attachment0
	Property: string, -- "C0" | "CFrame"
	Attribute: string, -- "BaseC0" | "BaseCFrame"
	Base: CFrame,
	Written: CFrame, -- the last value written
}

type State = {
	Shoulder: Joint,
	Waist: Joint?,
	Elbow: Joint?,
	Animator: Animator?,
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
	Pose: Vector3, -- the shoulder: pitch, yaw, roll in torso axes
	WaistYaw: number,
	ElbowBend: number,
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

local function jointValue(joint: Joint): CFrame
	return (joint.Instance :: any)[joint.Property]
end

local function setJoint(joint: Joint, value: CFrame)
	local instance = joint.Instance :: any
	instance[joint.Property] = value
end

-- `partName`'s joint `jointName` (RightUpperArm / RightShoulder, UpperTorso /
-- Waist, RightLowerArm / RightElbow), with its untouched base value.
local function findJoint(character: Model, partName: string, jointName: string): Joint?
	local part = character:FindFirstChild(partName)
	if not part then
		return nil
	end
	local motor = part:FindFirstChild(jointName)
	if motor and motor:IsA("Motor6D") and motor.Enabled then
		local stored = motor:GetAttribute("BaseC0")
		local base = if typeof(stored) == "CFrame" then stored else motor.C0
		return {
			Instance = motor :: Instance,
			Property = "C0",
			Attribute = "BaseC0",
			Base = base,
			Written = motor.C0,
		}
	end
	for _, child in part:GetChildren() do
		if child:IsA("AnimationConstraint") and child.Enabled and child.Attachment0 and child.Attachment1 then
			local attachment = child.Attachment0 :: Attachment
			local stored = attachment:GetAttribute("BaseCFrame")
			local base = if typeof(stored) == "CFrame" then stored else attachment.CFrame
			return {
				Instance = attachment :: Instance,
				Property = "CFrame",
				Attribute = "BaseCFrame",
				Base = base,
				Written = attachment.CFrame,
			}
		end
	end
	return nil
end

-- The joint value for a pose given in the torso's axes (pitch, yaw, roll):
-- the base position with the base rotation turned by the pose. (Same as
-- BaseC0 * Transform with Transform = R^-1 * pose * R, so an avatar whose
-- shoulder C0 is rotated still raises its arm FORWARD.)
local function jointFor(base: CFrame, pose: Vector3): CFrame
	return CFrame.new(base.Position) * CFrame.fromOrientation(pose.X, pose.Y, pose.Z) * (base - base.Position)
end

-- Animate's tool-hold track also raises the arm; with our pose it would
-- double-raise, so it is faded out while we hold.
local function stopToolHold(state: State)
	local animator = state.Animator
	if not animator or not animator.Parent then
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		local animation = track.Animation
		if animation and (animation.Name == "ToolNoneAnim" or (animation.Parent and animation.Parent.Name == "toolnone")) then
			track:Stop(0.1)
		end
	end
end

-- Writes one joint; if something else moved it (the Humanoid rescaling the
-- rig) the base follows its position, and the rotation stays ours.
local function writeJoint(joint: Joint, value: (CFrame) -> CFrame)
	local live = jointValue(joint)
	if (live.Position - joint.Written.Position).Magnitude > 1e-3 then
		joint.Base = CFrame.new(live.Position) * (joint.Base - joint.Base.Position)
		joint.Instance:SetAttribute(joint.Attribute, joint.Base)
	end
	joint.Written = value(joint.Base)
	setJoint(joint, joint.Written)
end

local function write(state: State)
	local pose = state.Pose
	writeJoint(state.Shoulder, function(base)
		return jointFor(base, pose)
	end)
	local waist, elbow = state.Waist, state.Elbow
	if waist then
		local yaw = state.WaistYaw
		writeJoint(waist, function(base)
			return base * CFrame.Angles(0, yaw, 0)
		end)
	end
	if elbow then
		local bend = state.ElbowBend
		writeJoint(elbow, function(base)
			return base * CFrame.Angles(bend, 0, 0)
		end)
	end
end

local function restoreJoint(joint: Joint?)
	if joint and joint.Instance.Parent then
		setJoint(joint, joint.Base)
		joint.Instance:SetAttribute(joint.Attribute, nil)
	end
end

local function restore(state: State)
	restoreJoint(state.Shoulder)
	restoreJoint(state.Waist)
	restoreJoint(state.Elbow)
end

local function lerpKey(a: SwingKey, b: SwingKey, t: number): SwingKey
	return {
		Arm = a.Arm:Lerp(b.Arm, t),
		Waist = a.Waist + (b.Waist - a.Waist) * t,
		Elbow = a.Elbow + (b.Elbow - a.Elbow) * t,
	}
end

-- The swing's offsets at `elapsed`; nil once it is over.
local function swingOffset(shape: SwingShape, elapsed: number): SwingKey?
	local windEnd = shape.WindSeconds
	local holdEnd = windEnd + shape.HoldSeconds
	local arcEnd = holdEnd + shape.ArcSeconds
	local followEnd = arcEnd + shape.FollowSeconds
	if elapsed >= followEnd + shape.SettleSeconds then
		return nil
	elseif elapsed < windEnd then
		return lerpKey(ZERO_KEY, shape.Wind, easeOut(elapsed / windEnd))
	elseif elapsed < holdEnd then
		return shape.Wind
	elseif elapsed < arcEnd then
		return lerpKey(shape.Wind, shape.Arc, easeIn((elapsed - holdEnd) / shape.ArcSeconds))
	elseif elapsed < followEnd then
		return lerpKey(shape.Arc, shape.Follow, easeOut((elapsed - arcEnd) / shape.FollowSeconds))
	end
	return lerpKey(shape.Follow, ZERO_KEY, easeOut((elapsed - followEnd) / shape.SettleSeconds))
end

function WeaponPose.GetSwingSeconds(weaponId: string): number
	local shape = SWINGS[weaponId]
	if not shape then
		return 0
	end
	return shape.WindSeconds + shape.HoldSeconds + shape.ArcSeconds + shape.FollowSeconds + shape.SettleSeconds
end

-- Computes the state's pose for this frame (RenderStepped only: it
-- integrates the aim smoothing with dt).
local function compute(state: State, now: number, dt: number)
	local pitch, yaw, roll = state.HoldPitch, 0, 0
	local waistYaw, elbowBend = 0, 0

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
			pitch += offset.Arm.X
			yaw += offset.Arm.Y
			roll += offset.Arm.Z
			waistYaw += offset.Waist
			elbowBend += offset.Elbow
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

	state.Pose = Vector3.new(pitch, yaw, roll)
	state.WaistYaw = waistYaw
	state.ElbowBend = elbowBend
end

local function apply()
	for character, state in states do
		if not character.Parent or not state.Shoulder.Instance.Parent then
			states[character] = nil
		else
			write(state)
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
		if not character.Parent or not state.Shoulder.Instance.Parent then
			states[character] = nil
		else
			compute(state, now, dt)
			stopToolHold(state)
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
end

--[[ Public API ------------------------------------------------------------------------ ]]

-- A weapon came up in `character`'s hand.
function WeaponPose.Hold(character: Model, weapon: CombatConfig.Weapon)
	local old = states[character]
	if old then
		-- Switching straight from one weapon to another: back to base first.
		restore(old)
		states[character] = nil
	end
	local shoulder = findJoint(character, "RightUpperArm", "RightShoulder")
	if not shoulder then
		return
	end
	local waist = findJoint(character, "UpperTorso", "Waist")
	local elbow = findJoint(character, "RightLowerArm", "RightElbow")
	for _, joint in { shoulder, waist :: Joint, elbow :: Joint } do
		if joint then
			joint.Instance:SetAttribute(joint.Attribute, joint.Base)
		end
	end
	local gun = weapon.Kind == "Ranged" or weapon.Kind == "Freeze"
	local state: State = {
		Shoulder = shoulder,
		Waist = waist,
		Elbow = elbow,
		Animator = character:FindFirstChildWhichIsA("Animator", true),
		WeaponId = weapon.Id,
		Gun = gun,
		HoldPitch = if gun then GUN_HOLD_PITCH else (HOLD_PITCH[weapon.Id] or 1.3),
		HeldAt = os.clock(),
		AimPitch = 0,
		AimTarget = 0,
		Pose = Vector3.zero,
		WaistYaw = 0,
		ElbowBend = 0,
	}
	states[character] = state
	compute(state, os.clock(), 0)
	stopToolHold(state)
	write(state)
	ensureRunning()
end

-- The weapon is gone: base values back, attributes cleared. With `weaponId`,
-- only if that weapon is the one held: on a slot-to-slot switch the NEW
-- tool can arrive before the OLD one leaves, and the old one's release must
-- not wipe the new pose.
function WeaponPose.Release(character: Model, weaponId: string?)
	local state = states[character]
	if state and (weaponId == nil or state.WeaponId == weaponId) then
		states[character] = nil
		restore(state)
	end
end

-- The id of the weapon whose pose is up, if any.
function WeaponPose.GetHeldWeapon(character: Model): string?
	local state = states[character]
	return if state then state.WeaponId else nil
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
	return WeaponPose.GetSwingSeconds(weaponId)
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

-- RightHand.Position in UpperTorso space: what is DRAWN (the joints solved),
-- not the value we wrote. Sample on Heartbeat. nil without an R15 hand.
function WeaponPose.GetHandOffset(character: Model): Vector3?
	local hand = character:FindFirstChild("RightHand")
	local torso = character:FindFirstChild("UpperTorso")
	if not (hand and hand:IsA("BasePart") and torso and torso:IsA("BasePart")) then
		return nil
	end
	return torso.CFrame:PointToObjectSpace(hand.Position)
end

-- The live joint values (Motor6D C0, or the AnimationConstraint's Attachment0
-- CFrame) of the shoulder, waist and elbow: /selftest compares them before a
-- weapon and after its release.
function WeaponPose.GetJointValues(character: Model): { CFrame? }
	local values: { CFrame? } = {}
	for index, pair in { { "RightUpperArm", "RightShoulder" }, { "UpperTorso", "Waist" }, { "RightLowerArm", "RightElbow" } } do
		local part = character:FindFirstChild(pair[1])
		local motor = part and part:FindFirstChild(pair[2])
		if motor and motor:IsA("Motor6D") and motor.Enabled then
			values[index] = motor.C0
		elseif part then
			for _, child in part:GetChildren() do
				if child:IsA("AnimationConstraint") and child.Attachment0 then
					values[index] = child.Attachment0.CFrame
					break
				end
			end
		end
	end
	return values
end

-- Whether any pose joint (shoulder, waist, elbow) still carries a stored base
-- (false once released).
function WeaponPose.HasBaseStored(character: Model): boolean
	for _, descendant in character:GetDescendants() do
		if descendant:GetAttribute("BaseC0") ~= nil or descendant:GetAttribute("BaseCFrame") ~= nil then
			return true
		end
	end
	return false
end

-- How far the held tool's parts reach beyond the UpperTorso's surface (studs).
function WeaponPose.GetToolClearance(character: Model, tool: Instance): number?
	local torso = character:FindFirstChild("UpperTorso")
	if not (torso and torso:IsA("BasePart")) then
		return nil
	end
	local half = torso.Size / 2
	local best = 0
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") then
			local at = torso.CFrame:PointToObjectSpace(part.Position)
			local outside = Vector3.new(math.max(math.abs(at.X) - half.X, 0), math.max(math.abs(at.Y) - half.Y, 0), math.max(math.abs(at.Z) - half.Z, 0))
			best = math.max(best, outside.Magnitude)
		end
	end
	return best
end

return WeaponPose
