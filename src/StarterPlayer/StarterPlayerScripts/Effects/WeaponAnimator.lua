--!strict
--[[
	WeaponAnimator
	--------------
	Real animation tracks for the weapons, played on every character's
	Animator by every client (local, like WeaponPose; Animator tracks are not
	affected by the 2026 "Transform" rule). Driven by the same CombatController
	paths as WeaponPose:

	  Hold(c, weapon)          true = tracks are used (hold track looping).
	                           false = no clip is available (an empty id on a
	                           live server): the caller falls back to
	                           WeaponPose's C0 pose, and we warned once.
	  Release(c, id?)          stop that weapon's tracks (only if `id` is the
	                           held one: a slot switch fires the new tool's add
	                           before the old one's remove)
	  Swing(c, id, onHit?)     the melee action track; returns its length (0 =
	                           not playing). `onHit` fires ONCE at the clip's
	                           "Hit" marker (or at 55% of the length if the
	                           marker never arrives): the trail starts there.
	  Recoil(c) / Throw(c, onHit?)   the gun kick / the peel toss
	  HitStop(c, seconds)      the action track at speed 0 for a moment
	  GetHeldWeapon(c)         the weapon whose hold track is up
	  GetTracks(c)             name -> AnimationTrack (for /selftest)

	Clip source per name (CombatConfig.AnimationIds):
	  an id set                 that asset
	  empty, in Studio          WeaponAnims.Build(name) registered with
	                            KeyframeSequenceProvider (a temporary id)
	  empty, live               nothing: WeaponPose takes over
	Tracks are loaded once per Animator and cached. While a hold track plays
	Animate's `toolnone` is stopped (it raises the arm too).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeaponAnims = require(ReplicatedStorage.Shared.Anim.WeaponAnims)
local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local WeaponAnimator = {}

-- weapon id -> { Hold, Action } clip names.
local CLIPS: { [string]: { Hold: string, Action: string? } } = {
	Bat = { Hold = "BatHold", Action = "BatSwing" },
	SlapGlove = { Hold = "GloveHold", Action = "GloveSlap" },
	LaserGun = { Hold = "GunAim", Action = "GunRecoil" },
	FreezeRay = { Hold = "GunAim", Action = "GunRecoil" },
	BananaPeel = { Hold = "GloveHold", Action = "PeelThrow" }, -- no hold clip of its own
}

type Rig = {
	Animator: Animator,
	Tracks: { [string]: AnimationTrack },
	WeaponId: string?,
	Hit: RBXScriptConnection?,
	Token: number,
}

local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any
local animationIds: { [string]: string } = {} -- clip name -> the id to play ("" = none)
local warned = false
local forceFallback = false -- /selftest: pretend "no id, not Studio"
local toolHoldConnection: RBXScriptConnection? = nil

-- The id to play for a clip, or nil when there is none (live fallback).
local function idFor(name: string): string?
	if forceFallback then
		return nil
	end
	local cached = animationIds[name]
	if cached ~= nil then
		return if cached == "" then nil else cached
	end
	local configured = CombatConfig.AnimationIds[name]
	if configured and configured ~= "" then
		animationIds[name] = configured
		return configured
	end
	if RunService:IsStudio() then
		local sequence = WeaponAnims.Build(name)
		if sequence then
			local ok, id = pcall(function()
				return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
			end)
			if ok and typeof(id) == "string" and id ~= "" then
				animationIds[name] = id
				return id
			end
		end
	end
	animationIds[name] = ""
	return nil
end

local function getRig(character: Model): Rig?
	local existing = rigs[character]
	if existing and existing.Animator.Parent then
		return existing
	end
	local animator = character:FindFirstChildWhichIsA("Animator", true)
	if not animator then
		return nil
	end
	local rig: Rig = { Animator = animator, Tracks = {}, WeaponId = nil, Token = 0 }
	rigs[character] = rig
	return rig
end

local function getTrack(rig: Rig, name: string): AnimationTrack?
	if forceFallback then
		return nil -- /selftest: no cached track either
	end
	local cached = rig.Tracks[name]
	if cached then
		return cached
	end
	local id = idFor(name)
	if not id then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = id
	local ok, track = pcall(function()
		return rig.Animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Priority = WeaponAnims.GetPriority(name)
	track.Looped = WeaponAnims.IsLooped(name)
	rig.Tracks[name] = track
	return track
end

-- Animate's tool-hold animation also raises the arm: stop it while any hold
-- track plays (it is replayed by Animate when a tool is equipped).
local function stopToolNone()
	for _, rig in rigs do
		if rig.WeaponId and rig.Animator.Parent then
			for _, playing in rig.Animator:GetPlayingAnimationTracks() do
				local animation = playing.Animation
				if animation and (animation.Name == "ToolNoneAnim" or (animation.Parent and animation.Parent.Name == "toolnone")) then
					playing:Stop(0.1)
				end
			end
		end
	end
end

local function ensureLoop()
	if toolHoldConnection then
		return
	end
	toolHoldConnection = RunService.Heartbeat:Connect(function()
		stopToolNone()
		local any = false
		for _, rig in rigs do
			if rig.WeaponId then
				any = true
				break
			end
		end
		if not any and toolHoldConnection then
			toolHoldConnection:Disconnect()
			toolHoldConnection = nil
		end
	end)
end

local function stopRig(rig: Rig)
	rig.Token += 1
	if rig.Hit then
		rig.Hit:Disconnect()
		rig.Hit = nil
	end
	for _, track in rig.Tracks do
		if track.IsPlaying then
			track:Stop(0.1)
		end
	end
	rig.WeaponId = nil
end

--[[ Public API ------------------------------------------------------------------------ ]]

function WeaponAnimator.Hold(character: Model, weapon: CombatConfig.Weapon): boolean
	if forceFallback then
		return false -- /selftest: the live "no id, not Studio" path: no track at all
	end
	local clips = CLIPS[weapon.Id]
	local rig = getRig(character)
	if not clips or not rig then
		return false
	end
	stopRig(rig) -- every hold / action track of the previous weapon, held or not
	local track = getTrack(rig, clips.Hold)
	if not track then
		if not warned and not forceFallback then
			warned = true
			warn("WeaponAnimator: no animation id and not Studio: using the C0 WeaponPose fallback (fill CombatConfig.AnimationIds)")
		end
		return false
	end
	rig.WeaponId = weapon.Id
	if clips.Action then
		getTrack(rig, clips.Action) -- loaded now, so the first swing has no load hitch
	end
	track:Play(0.15)
	ensureLoop()
	return true
end

function WeaponAnimator.Release(character: Model, weaponId: string?)
	local rig = rigs[character]
	if rig and rig.WeaponId and (weaponId == nil or rig.WeaponId == weaponId) then
		stopRig(rig)
	end
end

function WeaponAnimator.GetHeldWeapon(character: Model): string?
	local rig = rigs[character]
	return if rig then rig.WeaponId else nil
end

function WeaponAnimator.GetTracks(character: Model): { [string]: AnimationTrack }
	local rig = rigs[character]
	return if rig then rig.Tracks else {}
end

-- /selftest: the held weapon's looping hold track / its action track.
function WeaponAnimator.GetHoldTrack(character: Model): AnimationTrack?
	local rig = rigs[character]
	local clips = rig and rig.WeaponId and CLIPS[rig.WeaponId]
	return if rig and clips then rig.Tracks[clips.Hold] else nil
end

function WeaponAnimator.GetActionTrack(character: Model): AnimationTrack?
	local rig = rigs[character]
	local clips = rig and rig.WeaponId and CLIPS[rig.WeaponId]
	return if rig and clips and clips.Action then rig.Tracks[clips.Action] else nil
end

-- /selftest: is any weapon track of this character still playing?
function WeaponAnimator.AnyPlaying(character: Model): boolean
	local rig = rigs[character]
	if rig then
		for _, track in rig.Tracks do
			if track.IsPlaying then
				return true
			end
		end
	end
	return false
end

-- Plays the weapon's action clip. `onHit` fires once at the "Hit" marker, or
-- at 55% of the clip if no marker arrives.
local function playAction(character: Model, weaponId: string, onHit: (() -> ())?): number
	local clips = CLIPS[weaponId]
	local rig = rigs[character]
	if not clips or not clips.Action or not rig or rig.WeaponId ~= weaponId then
		return 0
	end
	local track = getTrack(rig, clips.Action)
	if not track then
		return 0
	end
	if rig.Hit then
		rig.Hit:Disconnect()
		rig.Hit = nil
	end
	rig.Token += 1
	local mine = rig.Token
	local fired = false
	local function hit()
		if fired or rig.Token ~= mine then
			return
		end
		fired = true
		if onHit then
			onHit()
		end
	end
	rig.Hit = track:GetMarkerReachedSignal("Hit"):Connect(hit)
	track:Play(0.05)
	local length = if track.Length > 0 then track.Length else WeaponAnims.GetLength(clips.Action)
	task.delay(length * 0.55, hit)
	return length
end

function WeaponAnimator.Swing(character: Model, weaponId: string, onHit: (() -> ())?): number
	return playAction(character, weaponId, onHit)
end

function WeaponAnimator.Recoil(character: Model)
	local rig = rigs[character]
	if rig and rig.WeaponId then
		playAction(character, rig.WeaponId, nil)
	end
end

function WeaponAnimator.Throw(character: Model, onHit: (() -> ())?)
	playAction(character, "BananaPeel", onHit)
end

-- The action track frozen for `seconds` (a landed hit's hit-stop).
function WeaponAnimator.HitStop(character: Model, seconds: number)
	local rig = rigs[character]
	local clips = rig and rig.WeaponId and CLIPS[rig.WeaponId]
	local track = if rig and clips and clips.Action then rig.Tracks[clips.Action] else nil
	if track and track.IsPlaying then
		track:AdjustSpeed(0)
		task.delay(seconds, function()
			if track.IsPlaying then
				track:AdjustSpeed(1)
			end
		end)
	end
end

-- /selftest: pretend there is no id and this is not Studio (the live
-- fallback), so Hold returns false.
function WeaponAnimator.SelfTestForceFallback(on: boolean)
	forceFallback = on
end

-- /selftest diagnostics: is the fallback switch still on?
function WeaponAnimator.SelfTestIsForcingFallback(): boolean
	return forceFallback
end

return WeaponAnimator
