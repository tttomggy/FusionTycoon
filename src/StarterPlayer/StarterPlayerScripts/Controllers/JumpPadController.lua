--!strict
--[[
	JumpPadController
	-----------------
	Every lab's jump pad to its 2nd floor (FloorKit, tagged FT_JumpPad)
	launches the LOCAL character: the client owns its character's physics,
	so a velocity set here is smooth where a server push would stutter.
	Anyone can use any lab's pad (thieves take it too; the heist rules are
	the server's). A root within the pad's Radius (flat) and at most
	PlotLayout.Floor2.JumpPad.TriggerHeight above it is thrown along the
	pad's LaunchVelocity attribute (world-space), at most once per
	CooldownSeconds. Not while ragdolled (Physics state) or seated.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local FloorKit = require(ReplicatedStorage.Shared.Modules.FloorKit)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)

local JumpPadController = {}

local JP = PlotLayout.Floor2.JumpPad
local localPlayer = Players.LocalPlayer
local lastLaunch = -math.huge

local function step()
	if os.clock() - lastLaunch < JP.CooldownSeconds then
		return
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 or humanoid.Sit then
		return
	end
	if humanoid:GetState() == Enum.HumanoidStateType.Physics then
		return
	end
	local position = root.Position
	for _, pad in CollectionService:GetTagged(FloorKit.JUMP_PAD_TAG) do
		if pad:IsA("BasePart") then
			local radius = pad:GetAttribute("Radius")
			local velocity = pad:GetAttribute("LaunchVelocity")
			if typeof(radius) == "number" and typeof(velocity) == "Vector3" then
				local offset = position - pad.Position
				local above = offset.Y - JP.Height / 2 - humanoid.HipHeight - root.Size.Y / 2
				if Vector2.new(offset.X, offset.Z).Magnitude <= radius and above >= -1 and above <= JP.TriggerHeight then
					lastLaunch = os.clock()
					humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
					root.AssemblyLinearVelocity = velocity
					SoundKit.Play("Toast", root)
					return
				end
			end
		end
	end
end

function JumpPadController.Init()
	RunService.Heartbeat:Connect(step)
end

return JumpPadController
