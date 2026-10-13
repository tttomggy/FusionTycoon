--!strict
--[[
	WeaponAnims
	-----------
	The weapon animation clips, built in code as R15 KeyframeSequences (no
	uploads needed to try them: WeaponAnimator registers them with
	KeyframeSequenceProvider in Studio; `/anim export` puts them in
	ServerStorage.WeaponAnimExports so they can be saved to Roblox and the
	ids pasted into CombatConfig.AnimationIds).

	  WeaponAnims.Names            every clip name
	  WeaponAnims.Build(name)      a new KeyframeSequence (nil for an unknown name)
	  WeaponAnims.IsLooped(name)   hold / aim clips loop
	  WeaponAnims.GetPriority(name)

	A clip keys ONLY the joints it needs (no pose = the joint is not animated
	by it), so walk / run keep driving the legs and the rest. Exaggerated,
	cartoon: it has to read from 30 studs on a small avatar.

	Joint names -> R15 parts (a Pose is named after the Part1 of its joint):
	  Root LowerTorso   Waist UpperTorso   Neck Head
	  RShoulder RightUpperArm  RElbow RightLowerArm  RWrist RightHand
	  LShoulder LeftUpperArm   LElbow LeftLowerArm    LWrist LeftHand
	  RHip RightUpperLeg  RKnee RightLowerLeg  RAnkle RightFoot  (L likewise)

	Rotations are DEGREES about the joint's local axes, the way a Motor6D
	Transform reads. Forward is -Z, the character's right is +X:
	  X +  swings a limb FORWARD / leans the torso BACK
	  Y +  turns LEFT        (Y -  turns right)
	  Z +  swings the RIGHT arm out to the right / the left arm across
	Easing is the one INTO a keyframe.
]]
local WeaponAnims = {}

local PARENT: { [string]: string } = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	RightUpperArm = "UpperTorso",
	RightLowerArm = "RightUpperArm",
	RightHand = "RightLowerArm",
	LeftUpperArm = "UpperTorso",
	LeftLowerArm = "LeftUpperArm",
	LeftHand = "LeftLowerArm",
	RightUpperLeg = "LowerTorso",
	RightLowerLeg = "RightUpperLeg",
	RightFoot = "RightLowerLeg",
	LeftUpperLeg = "LowerTorso",
	LeftLowerLeg = "LeftUpperLeg",
	LeftFoot = "LeftLowerLeg",
}

local PART: { [string]: string } = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	RShoulder = "RightUpperArm",
	RElbow = "RightLowerArm",
	RWrist = "RightHand",
	LShoulder = "LeftUpperArm",
	LElbow = "LeftLowerArm",
	LWrist = "LeftHand",
	RHip = "RightUpperLeg",
	RKnee = "RightLowerLeg",
	RAnkle = "RightFoot",
	LHip = "LeftUpperLeg",
	LKnee = "LeftLowerLeg",
	LAnkle = "LeftFoot",
}

-- A joint transform: rotation in degrees, optional offset in studs.
local function J(x: number, y: number, z: number, px: number?, py: number?, pz: number?): CFrame
	return CFrame.new(px or 0, py or 0, pz or 0) * CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

type Frame = {
	T: number,
	Joints: { [string]: CFrame },
	Style: Enum.PoseEasingStyle?,
	Direction: Enum.PoseEasingDirection?,
	Marker: string?,
}

type Clip = {
	Looped: boolean,
	Priority: Enum.AnimationPriority,
	Frames: { Frame },
}

local Cubic, Out, In = Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.Out, Enum.PoseEasingDirection.In

--[[ The poses reused by a hold and the action that starts from it ---------------- ]]

-- Bat on the right shoulder, elbow out, a slight crouch.
local BAT_HOLD: { [string]: CFrame } = {
	Root = J(4, 0, 0, 0, -0.1, 0),
	Waist = J(-4, -12, 0),
	RShoulder = J(75, 0, 18),
	RElbow = J(115, 0, 0),
	LShoulder = J(45, 0, -12),
	LElbow = J(75, 0, 0),
	RHip = J(14, 0, 0),
	RKnee = J(-28, 0, 0),
	LHip = J(14, 0, 0),
	LKnee = J(-28, 0, 0),
}

-- Glove raised beside the head, palm forward.
local GLOVE_HOLD: { [string]: CFrame } = {
	Waist = J(-3, -8, 0),
	RShoulder = J(55, 0, 62),
	RElbow = J(95, 0, 0),
	LShoulder = J(8, 0, -8),
	LElbow = J(15, 0, 0),
}

-- Both arms forward, the left hand under the gun, a slight lean.
local GUN_AIM: { [string]: CFrame } = {
	Waist = J(-6, 8, 0),
	RShoulder = J(90, 0, -4),
	RElbow = J(8, 0, 0),
	LShoulder = J(84, 0, -32),
	LElbow = J(24, 0, 0),
}

local function merge(base: { [string]: CFrame }, over: { [string]: CFrame }): { [string]: CFrame }
	local out: { [string]: CFrame } = {}
	for name, value in base do
		out[name] = value
	end
	for name, value in over do
		out[name] = value
	end
	return out
end

local Action, Action2 = Enum.AnimationPriority.Action, Enum.AnimationPriority.Action2

local CLIPS: { [string]: Clip } = {
	BatHold = {
		Looped = true,
		Priority = Action,
		Frames = {
			{ T = 0, Joints = BAT_HOLD },
			{ T = 0.6, Joints = merge(BAT_HOLD, { Waist = J(-5, -14, 0), RShoulder = J(78, 0, 20) }), Style = Enum.PoseEasingStyle.Cubic, Direction = Enum.PoseEasingDirection.InOut },
			{ T = 1.2, Joints = BAT_HOLD, Style = Enum.PoseEasingStyle.Cubic, Direction = Enum.PoseEasingDirection.InOut },
		},
	},

	-- A big horizontal baseball swing, ~0.55 s: load (bat back behind the head,
	-- torso twisted right, weight on the back leg), whip (front foot steps,
	-- hips and torso snap ~140 degrees left, arms fully out), follow-through
	-- (the bat wraps past the left shoulder), recover into the hold.
	BatSwing = {
		Looped = false,
		Priority = Action2,
		Frames = {
			{ T = 0, Joints = BAT_HOLD },
			{
				T = 0.18,
				Style = Cubic,
				Direction = Out,
				Joints = {
					Root = J(10, -22, 0, 0, -0.18, 0.25),
					Waist = J(0, -70, 0),
					RShoulder = J(125, -20, 42),
					RElbow = J(105, 0, 0),
					LShoulder = J(72, 0, -8),
					LElbow = J(62, 0, 0),
					RHip = J(10, 0, 0),
					RKnee = J(-34, 0, 0),
					LHip = J(-8, 0, 0),
					LKnee = J(-12, 0, 0),
				},
			},
			{
				T = 0.28,
				Style = Cubic,
				Direction = In,
				Marker = "Hit",
				Joints = {
					Root = J(-12, 38, 0, 0, -0.1, -0.5),
					Waist = J(-4, 70, 0),
					RShoulder = J(88, 10, 2),
					RElbow = J(4, 0, 0),
					LShoulder = J(84, 0, -26),
					LElbow = J(10, 0, 0),
					RHip = J(-18, 0, 0),
					RKnee = J(-8, 0, 0),
					LHip = J(38, 0, 0),
					LKnee = J(-24, 0, 0),
				},
			},
			{
				T = 0.4,
				Style = Cubic,
				Direction = Out,
				Joints = {
					Root = J(-6, 52, 0, 0, -0.1, -0.4),
					Waist = J(-2, 98, 0),
					RShoulder = J(72, 0, -58),
					RElbow = J(48, 0, 0),
					LShoulder = J(70, 0, -50),
					LElbow = J(40, 0, 0),
					RHip = J(-10, 0, 0),
					RKnee = J(-10, 0, 0),
					LHip = J(30, 0, 0),
					LKnee = J(-26, 0, 0),
				},
			},
			{ T = 0.55, Style = Cubic, Direction = Out, Joints = BAT_HOLD },
		},
	},

	GloveHold = {
		Looped = true,
		Priority = Action,
		Frames = {
			{ T = 0, Joints = GLOVE_HOLD },
			{ T = 0.5, Joints = merge(GLOVE_HOLD, { RShoulder = J(58, 0, 64) }), Style = Enum.PoseEasingStyle.Cubic, Direction = Enum.PoseEasingDirection.InOut },
			{ T = 1, Joints = GLOVE_HOLD, Style = Enum.PoseEasingStyle.Cubic, Direction = Enum.PoseEasingDirection.InOut },
		},
	},

	-- A huge open-palm slap, ~0.5 s: wind-up (arm pulled far back and out,
	-- torso turned away, a lean back), slap (a wide flat arc across at head
	-- height, lunging a step), follow-through (arm across the body), recover.
	GloveSlap = {
		Looped = false,
		Priority = Action2,
		Frames = {
			{ T = 0, Joints = GLOVE_HOLD },
			{
				T = 0.2,
				Style = Cubic,
				Direction = Out,
				Joints = {
					Root = J(12, -26, 0, 0, -0.05, 0.2),
					Waist = J(6, -62, 0),
					RShoulder = J(-14, -10, 100),
					RElbow = J(28, 0, 0),
					LShoulder = J(30, 0, -20),
					LElbow = J(40, 0, 0),
					RHip = J(8, 0, 0),
					RKnee = J(-14, 0, 0),
					LHip = J(-6, 0, 0),
				},
			},
			{
				T = 0.28,
				Style = Cubic,
				Direction = In,
				Marker = "Hit",
				Joints = {
					Root = J(-10, 34, 0, 0, -0.1, -0.65),
					Waist = J(-6, 66, 0),
					RShoulder = J(92, 0, -34),
					RElbow = J(0, 0, 0),
					LShoulder = J(20, 0, -20),
					LElbow = J(30, 0, 0),
					RHip = J(-16, 0, 0),
					LHip = J(34, 0, 0),
					LKnee = J(-22, 0, 0),
				},
			},
			{
				T = 0.38,
				Style = Cubic,
				Direction = Out,
				Joints = {
					Root = J(-6, 44, 0, 0, -0.08, -0.5),
					Waist = J(-4, 84, 0),
					RShoulder = J(78, 0, -62),
					RElbow = J(26, 0, 0),
					LShoulder = J(20, 0, -20),
					LElbow = J(30, 0, 0),
					RHip = J(-12, 0, 0),
					LHip = J(28, 0, 0),
					LKnee = J(-20, 0, 0),
				},
			},
			{ T = 0.5, Style = Cubic, Direction = Out, Joints = GLOVE_HOLD },
		},
	},

	GunAim = {
		Looped = true,
		Priority = Action,
		Frames = {
			{ T = 0, Joints = GUN_AIM },
			{ T = 0.7, Joints = merge(GUN_AIM, { Waist = J(-7, 8, 0) }), Style = Enum.PoseEasingStyle.Cubic, Direction = Enum.PoseEasingDirection.InOut },
			{ T = 1.4, Joints = GUN_AIM, Style = Enum.PoseEasingStyle.Cubic, Direction = Enum.PoseEasingDirection.InOut },
		},
	},

	-- Kick up and back.
	GunRecoil = {
		Looped = false,
		Priority = Action2,
		Frames = {
			{ T = 0, Joints = GUN_AIM },
			{
				T = 0.04,
				Style = Cubic,
				Direction = Out,
				Joints = merge(GUN_AIM, {
					Waist = J(4, 8, 0),
					RShoulder = J(106, 0, -4),
					RElbow = J(30, 0, 0),
					LShoulder = J(98, 0, -32),
					LElbow = J(40, 0, 0),
				}),
			},
			{ T = 0.12, Style = Cubic, Direction = Out, Joints = GUN_AIM },
		},
	},

	-- Overhand toss with a step.
	PeelThrow = {
		Looped = false,
		Priority = Action2,
		Frames = {
			{ T = 0, Joints = {} },
			{
				T = 0.12,
				Style = Cubic,
				Direction = Out,
				Joints = {
					Root = J(8, -14, 0),
					Waist = J(8, -34, 0),
					RShoulder = J(205, 0, 24),
					RElbow = J(70, 0, 0),
					LShoulder = J(50, 0, -20),
					LElbow = J(20, 0, 0),
					LHip = J(-10, 0, 0),
				},
			},
			{
				T = 0.22,
				Style = Cubic,
				Direction = In,
				Marker = "Hit",
				Joints = {
					Root = J(-10, 22, 0, 0, -0.05, -0.4),
					Waist = J(-8, 42, 0),
					RShoulder = J(62, 0, 6),
					RElbow = J(2, 0, 0),
					LShoulder = J(40, 0, -30),
					LElbow = J(20, 0, 0),
					LHip = J(30, 0, 0),
					LKnee = J(-20, 0, 0),
					RHip = J(-14, 0, 0),
				},
			},
			{ T = 0.35, Style = Cubic, Direction = Out, Joints = {} },
		},
	},
}

-- Which clips exist, in a stable order.
WeaponAnims.Names = { "BatHold", "BatSwing", "GloveHold", "GloveSlap", "GunAim", "GunRecoil", "PeelThrow" }

function WeaponAnims.IsLooped(name: string): boolean
	local clip = CLIPS[name]
	return clip ~= nil and clip.Looped
end

function WeaponAnims.GetPriority(name: string): Enum.AnimationPriority
	local clip = CLIPS[name]
	return if clip then clip.Priority else Action
end

-- The clip's length in seconds (its last keyframe).
function WeaponAnims.GetLength(name: string): number
	local clip = CLIPS[name]
	return if clip then clip.Frames[#clip.Frames].T else 0
end

-- A new KeyframeSequence for `name`. A Pose tree mirrors the rig; ancestors
-- of a keyed joint that the clip does not key get Weight 0 (pass-through).
function WeaponAnims.Build(name: string): KeyframeSequence?
	local clip = CLIPS[name]
	if not clip then
		return nil
	end
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = clip.Looped
	sequence.Priority = clip.Priority
	for _, frame in clip.Frames do
		local keyframe = Instance.new("Keyframe")
		keyframe.Name = if frame.Marker then frame.Marker else ("K%.2f"):format(frame.T)
		keyframe.Time = frame.T
		local poses: { [string]: Pose } = {}
		local function ensure(part: string, cframe: CFrame?): Pose
			local existing = poses[part]
			if existing then
				if cframe then
					existing.CFrame = cframe
					existing.Weight = 1
				end
				return existing
			end
			local pose = Instance.new("Pose")
			pose.Name = part
			pose.CFrame = cframe or CFrame.new()
			pose.Weight = if cframe then 1 else 0
			pose.EasingStyle = frame.Style or Enum.PoseEasingStyle.Linear
			pose.EasingDirection = frame.Direction or Enum.PoseEasingDirection.Out
			local parentName = PARENT[part]
			if parentName then
				pose.Parent = ensure(parentName, nil)
			else
				pose.Parent = keyframe
			end
			poses[part] = pose
			return pose
		end
		ensure("HumanoidRootPart", nil)
		for joint, cframe in frame.Joints do
			local part = PART[joint]
			if part then
				ensure(part, cframe)
			end
		end
		if frame.Marker then
			local marker = Instance.new("KeyframeMarker")
			marker.Name = frame.Marker
			marker.Value = ""
			keyframe:AddMarker(marker)
		end
		keyframe.Parent = sequence
	end
	return sequence
end

return WeaponAnims
