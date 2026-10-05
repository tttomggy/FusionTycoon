--!strict
--[[
	SoundKit
	--------
	The one way to play a sound (slots in SoundConfig):

	  SoundKit.Play(slot, parent?, options?)  -> Sound?
	      A new Sound per play, parented to `parent` (positional) or
	      SoundService (2D), Debris-cleaned. An empty Id, an unknown slot,
	      an Id that failed to load, or a slot already playing
	      SoundConfig.MaxConcurrentPerSlot (6) sounds plays nothing and
	      returns nil.
	  SoundKit.PlayAt(slot, position, options?)  -> Sound?
	      Positional at a world point (a temporary Attachment in Terrain).
	  SoundKit.SetVolume(volume)   (client)
	      The player's sound-effects volume, 0..1 (0 = muted): the local
	      Volume of the shared "SFX" SoundGroup every sound plays through,
	      so it scales every slot, server-played ones too.
	  SoundKit.Preload()   (client, once at boot)
	      ContentProvider:PreloadAsync over every slot with a status
	      callback; a failed Id warns ONCE ("SoundKit: <slot> failed to load
	      <id>") and that slot is silent from then on.
]]
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)

local SoundKit = {}

export type PlayOptions = {
	PlaybackSpeed: number?,
	Volume: number?, -- multiplies the slot's volume
	Lifetime: number?, -- seconds before cleanup (default 6)
}

local DEFAULT_LIFETIME = 6

-- Ids that failed to load (silenced) and slots already warned about.
local failedIds: { [string]: boolean } = {}
local warned: { [string]: boolean } = {}
-- Sounds of each slot currently playing (the per-slot cap).
local playing: { [string]: number } = {}
local sfxVolume = 1
local rng = Random.new()

local function warnOnce(slot: string, id: string)
	if not warned[slot] then
		warned[slot] = true
		warn(("SoundKit: %s failed to load %s"):format(slot, id))
	end
end

-- The shared SoundGroup. The server makes it (it replicates); a client
-- that plays before it arrives uses a local one of the same name, and
-- SetVolume covers both.
local function getGroup(): SoundGroup
	local existing = SoundService:FindFirstChild(SoundConfig.GroupName)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = SoundConfig.GroupName
	group.Volume = if RunService:IsClient() then sfxVolume else 1
	group.Parent = SoundService
	return group
end

if RunService:IsServer() then
	getGroup()
else
	SoundService.ChildAdded:Connect(function(child)
		if child:IsA("SoundGroup") and child.Name == SoundConfig.GroupName then
			child.Volume = sfxVolume
		end
	end)
end

function SoundKit.Play(slot: string, parent: Instance?, options: PlayOptions?): Sound?
	local config = SoundConfig.Slots[slot]
	if not config or config.Id == "" or failedIds[config.Id] then
		return nil
	end
	if (playing[slot] or 0) >= SoundConfig.MaxConcurrentPerSlot then
		return nil -- dropped, not stacked
	end
	local sound = Instance.new("Sound")
	sound.Name = slot
	sound.SoundId = config.Id
	sound.SoundGroup = getGroup()
	sound.Volume = config.Volume * (if options and options.Volume then options.Volume else 1)
	local jitter = config.SpeedJitter
	sound.PlaybackSpeed = if options and options.PlaybackSpeed
		then options.PlaybackSpeed
		elseif jitter then rng:NextNumber(jitter[1], jitter[2])
		else 1
	if parent and config.RollOffMaxDistance then
		sound.RollOffMaxDistance = config.RollOffMaxDistance
	end
	playing[slot] = (playing[slot] or 0) + 1
	local released = false
	local function release()
		if not released then
			released = true
			playing[slot] = math.max(0, (playing[slot] or 1) - 1)
		end
	end
	sound.Ended:Once(release)
	sound.Destroying:Once(release)
	sound.Parent = parent or SoundService
	sound:Play()
	Debris:AddItem(sound, if options and options.Lifetime then options.Lifetime else DEFAULT_LIFETIME)
	return sound
end

-- Positional at `position` (a temporary Attachment in Terrain).
function SoundKit.PlayAt(slot: string, position: Vector3, options: PlayOptions?): Sound?
	local attachment = Instance.new("Attachment")
	attachment.Name = "SoundAt_" .. slot
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	local sound = SoundKit.Play(slot, attachment, options)
	Debris:AddItem(attachment, if options and options.Lifetime then options.Lifetime else DEFAULT_LIFETIME)
	if not sound then
		attachment:Destroy()
	end
	return sound
end

-- Client: the player's sound-effects volume (0..1; 0 = muted).
function SoundKit.SetVolume(volume: number)
	sfxVolume = math.clamp(if volume == volume then volume else 1, 0, 1)
	for _, child in SoundService:GetChildren() do
		if child:IsA("SoundGroup") and child.Name == SoundConfig.GroupName then
			child.Volume = sfxVolume
		end
	end
end

-- Studio /selftest (client, yields): loads every slot's sound now and
-- returns the slots whose id failed ("" ids are silent on purpose, skipped).
function SoundKit.CheckAll(): { string }
	local failed: { string } = {}
	local slotsById: { [string]: { string } } = {}
	local assets: { Sound } = {}
	for slot, config in SoundConfig.Slots do
		if config.Id ~= "" then
			if not slotsById[config.Id] then
				slotsById[config.Id] = {}
				local probe = Instance.new("Sound")
				probe.SoundId = config.Id
				table.insert(assets, probe)
			end
			table.insert(slotsById[config.Id], slot)
		end
	end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(assets, function(contentId: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Failure then
				local slots = slotsById[contentId]
				if slots then
					for _, slot in slots do
						table.insert(failed, slot)
					end
				end
			end
		end)
	end)
	if not ok then
		table.insert(failed, "PreloadAsync: " .. tostring(err))
	end
	for _, probe in assets do
		probe:Destroy()
	end
	return failed
end

-- Client only (PreloadAsync does nothing useful on the server).
function SoundKit.Preload()
	if not RunService:IsClient() then
		return
	end
	local slotsById: { [string]: { string } } = {}
	local assets: { Sound } = {}
	for slot, config in SoundConfig.Slots do
		if config.Id ~= "" then
			if not slotsById[config.Id] then
				slotsById[config.Id] = {}
				local probe = Instance.new("Sound")
				probe.SoundId = config.Id
				table.insert(assets, probe)
			end
			table.insert(slotsById[config.Id], slot)
		end
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(assets, function(contentId: string, status: Enum.AssetFetchStatus)
				if status == Enum.AssetFetchStatus.Failure then
					failedIds[contentId] = true
					local slots = slotsById[contentId]
					if slots then
						for _, slot in slots do
							warnOnce(slot, contentId)
						end
					end
				end
			end)
		end)
		if not ok then
			warn(("SoundKit: preload failed (%s)"):format(tostring(err)))
		end
		for _, probe in assets do
			probe:Destroy()
		end
	end)
end

return SoundKit
