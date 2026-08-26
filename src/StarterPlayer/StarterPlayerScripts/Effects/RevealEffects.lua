-- Generic "charge up -> reveal" VFX sequence. Any system that wants a
-- suspenseful build-up followed by a tier-weighted payoff (the Fusion
-- Machine today, future crates/gacha features later) can reuse this without
-- depending on any Fusion-specific code - callers own all RNG/validation and
-- only hand this module a couple of parts to animate plus the reveal's
-- accent color and dramatic weight.
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)

local RevealEffects = {}

export type EffectHandles = {
	Core: BasePart,
	Ring: BasePart?,
}

export type RevealOptions = {
	AccentColor: Color3,
	IsMajor: boolean,
}

local DEFAULT_CHARGE_DURATION_SECONDS = 2.2
local CHARGE_SPINS = 3
local CHARGE_CORE_GROWTH = 1.35

local FLASH_DURATION_SECONDS = 0.25
local MINOR_PAUSE_SECONDS = 0.2
local MAJOR_PAUSE_SECONDS = 1
local MINOR_BURST_COUNT = 25
local MAJOR_BURST_COUNT = 80

local MAJOR_SHAKE_MAGNITUDE_STUDS = 0.35
local MAJOR_SHAKE_DURATION_SECONDS = 0.5

local MINOR_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
local MAJOR_SOUND_ID = "rbxasset://sounds/bell.wav"

-- Randomized, decaying screen shake via small Camera CFrame offsets. Safe to
-- call for any "impactful moment," not just a fusion reveal.
function RevealEffects.ShakeCamera(magnitudeStuds: number, durationSeconds: number)
	if magnitudeStuds <= 0 or durationSeconds <= 0 then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local startTime = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed >= durationSeconds then
			connection:Disconnect()
			return
		end
		local falloff = 1 - (elapsed / durationSeconds)
		local offset = Vector3.new(
			(math.random() * 2 - 1) * magnitudeStuds * falloff,
			(math.random() * 2 - 1) * magnitudeStuds * falloff,
			0
		)
		camera.CFrame *= CFrame.new(offset)
	end)
end

-- Plays the "charging up" build: the Core grows/brightens and the Ring (if
-- given) spins, ending at exactly `durationSeconds` so callers can line the
-- animation up with an expected server-response window. Blocks the calling
-- thread for the full duration - run it in task.spawn if you need to do
-- something else (like waiting on a network response) at the same time.
function RevealEffects.PlayChargeUp(handles: EffectHandles, durationSeconds: number?)
	local duration = durationSeconds or DEFAULT_CHARGE_DURATION_SECONDS
	local core = handles.Core
	local originalSize = core.Size

	local chargeTween = TweenService:Create(
		core,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = originalSize * CHARGE_CORE_GROWTH }
	)
	chargeTween:Play()

	if handles.Ring then
		-- TweenService slerps a CFrame along the shortest rotational path, so
		-- a target that's a multiple of 360 degrees away is indistinguishable
		-- from the start orientation - it would tween to a no-op. Multi-turn
		-- spins need manual per-frame stepping instead.
		local ring = handles.Ring :: BasePart
		local startCFrame = ring.CFrame
		local totalRadians = math.rad(360 * CHARGE_SPINS)
		local elapsed = 0
		local connection: RBXScriptConnection
		connection = RunService.Heartbeat:Connect(function(deltaTime: number)
			elapsed += deltaTime
			local alpha = math.min(elapsed / duration, 1)
			ring.CFrame = startCFrame * CFrame.Angles(totalRadians * (alpha * alpha), 0, 0)
			if alpha >= 1 then
				connection:Disconnect()
			end
		end)
	end

	chargeTween.Completed:Wait()
	core.Size = originalSize
end

-- Flash/burst "pop" moment, weighted by tier: Common/Rare get a quick,
-- understated flash; Epic/Legendary/Mythic get a longer pause, screen shake,
-- a bigger particle burst, and a distinct sound.
function RevealEffects.PlayReveal(handles: EffectHandles, options: RevealOptions)
	local core = handles.Core
	local accentColor = options.AccentColor
	local isMajor = options.IsMajor

	local flash = Instance.new("Highlight")
	flash.FillColor = Color3.new(1, 1, 1)
	flash.FillTransparency = 0
	flash.OutlineColor = accentColor
	flash.OutlineTransparency = 0
	flash.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	flash.Parent = core

	local burst = SparkleEmitter.Create({ Color = accentColor })
	-- A one-shot pop, not ambient sparkle: only the explicit :Emit() below
	-- should produce particles, not the emitter's own ongoing Rate.
	burst.Enabled = false
	burst.Parent = core
	burst:Emit(if isMajor then MAJOR_BURST_COUNT else MINOR_BURST_COUNT)

	local sound = Instance.new("Sound")
	sound.SoundId = if isMajor then MAJOR_SOUND_ID else MINOR_SOUND_ID
	sound.Volume = if isMajor then 1 else 0.55
	sound.Parent = core
	sound:Play()

	if isMajor then
		RevealEffects.ShakeCamera(MAJOR_SHAKE_MAGNITUDE_STUDS, MAJOR_SHAKE_DURATION_SECONDS)
	end

	TweenService:Create(flash, TweenInfo.new(FLASH_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FillTransparency = 1,
		OutlineTransparency = 1,
	}):Play()

	task.wait(if isMajor then MAJOR_PAUSE_SECONDS else MINOR_PAUSE_SECONDS)

	flash:Destroy()
	Debris:AddItem(sound, 3)
	Debris:AddItem(burst, 3)
end

return RevealEffects
