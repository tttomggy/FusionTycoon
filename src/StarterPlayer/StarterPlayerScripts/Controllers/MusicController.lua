--!strict
--[[
	MusicController
	---------------
	The background music: ONE Sound in SoundService ("Music", not looped, not
	in the SFX group, so muting sound effects keeps the music) that plays
	MusicConfig.Tracks shuffled with no immediate repeat. A track fades in
	over FadeSeconds and out over the last FadeSeconds, and when it ends the
	next one starts.

	Level = MusicVolume x fade x duck, set every frame:
	  * the player's Settings (TycoonController: MusicOn / MusicVolume);
	  * a big reveal sting (SoundConfig DucksMusic, through
	    SoundKit.SetDuckHandler) ducks the music to DuckFraction for
	    DuckSeconds;
	  * off = the Sound is paused (resumes where it was when turned on).

	A track that has not loaded after LoadTimeoutSeconds, or that ends in
	error, is skipped and not tried again; with every track failed the music
	is silent (nothing loops forever).

	Studio /selftest: MusicController.CheckAll (every track loads) and
	MusicController.GetSound / IsPlaying (the toggle test).
]]
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local MusicConfig = require(ReplicatedStorage.Shared.Config.MusicConfig)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local TycoonController = require(script.Parent.TycoonController)

local MusicController = {}

local sound: Sound? = nil
local started = false
-- Track indexes that failed to load (never played again this session).
local failed: { [number]: boolean } = {}
local current = 0 -- index of the track now loaded (0 = none)
local lastPlayed = 0
local bag: { number } = {}
-- Bumped on every track change: a stale load watchdog does nothing.
local generation = 0
local duckUntil = 0
local duck = 1 -- the current duck factor (1 = none), ramped toward its target
local rng = Random.new()

local function trackCount(): number
	return #MusicConfig.Tracks
end

-- The next track: a shuffled bag of every track that has not failed; the
-- track that just played is never first in a refilled bag (no immediate
-- repeat). nil when every track failed.
local function nextIndex(): number?
	if #bag == 0 then
		for index = 1, trackCount() do
			if not failed[index] then
				table.insert(bag, index)
			end
		end
		for i = #bag, 2, -1 do
			local j = rng:NextInteger(1, i)
			bag[i], bag[j] = bag[j], bag[i]
		end
		if #bag > 1 and bag[1] == lastPlayed then
			bag[1], bag[#bag] = bag[#bag], bag[1]
		end
	end
	while #bag > 0 do
		local index = table.remove(bag, 1) :: number
		if not failed[index] then
			return index
		end
	end
	return nil
end

local playNext: () -> ()

-- Skips a track that never loads or errors.
local function skipFailed(index: number, why: string)
	if failed[index] then
		return
	end
	failed[index] = true
	local track = MusicConfig.Tracks[index]
	warn(("MusicController: %s (%s) %s; skipping it"):format(track.Name, track.Id, why))
	if current == index then
		playNext()
	end
end

playNext = function()
	local music = sound
	if not music then
		return
	end
	local index = nextIndex()
	if not index then
		music:Stop()
		current = 0
		return
	end
	generation += 1
	local mine = generation
	current = index
	lastPlayed = index
	music.SoundId = MusicConfig.Tracks[index].Id
	music.TimePosition = 0
	-- Always Play: while the music is off, step() pauses it on the next frame
	-- (a paused Sound keeps its place and resumes when switched back on).
	music:Play()
	task.delay(MusicConfig.LoadTimeoutSeconds, function()
		if generation == mine and current == index and not music.IsLoaded then
			skipFailed(index, "did not load in time")
		end
	end)
end

-- Every frame: the level, the pause / resume on the toggle.
local function step(dt: number)
	local music = sound
	if not music then
		return
	end
	-- Silent until the first snapshot says what the player chose (a saved "off"
	-- must not blip on at boot).
	local on = TycoonController.IsMusicOn() and TycoonController.HasSynced()
	if not on then
		if music.IsPlaying then
			music:Pause()
		end
		music.Volume = 0
		return
	end
	if music.IsPaused then
		music:Resume()
	end
	-- Duck: ramps to DuckFraction while a sting plays, back up after.
	local target = if os.clock() < duckUntil then MusicConfig.DuckFraction else 1
	local rate = (1 - MusicConfig.DuckFraction) / MusicConfig.DuckRampSeconds
	if duck > target then
		duck = math.max(target, duck - rate * dt)
	else
		duck = math.min(target, duck + rate * dt)
	end
	-- Fade in at the start, out at the end (length unknown until loaded: no fade).
	local fade = 1
	local length = music.TimeLength
	if music.IsLoaded and length > 0 then
		local fadeSeconds = MusicConfig.FadeSeconds
		fade = math.min(1, music.TimePosition / fadeSeconds, (length - music.TimePosition) / fadeSeconds)
		fade = math.clamp(fade, 0, 1)
	end
	music.Volume = TycoonController.GetMusicVolume() * fade * duck
end

-- A big reveal sting plays: dip the music for DuckSeconds.
local function onDuck()
	duckUntil = os.clock() + MusicConfig.DuckSeconds
end

function MusicController.Init()
	local music = Instance.new("Sound")
	music.Name = "Music"
	music.Looped = false
	music.Volume = 0
	sound = music
	music.Parent = SoundService
	music.Ended:Connect(function()
		if started then
			playNext()
		end
	end)
	SoundKit.SetDuckHandler(onDuck)
	RunService.Heartbeat:Connect(step)
	started = true
	playNext()
end

-- Studio /selftest (yields): the Sound the playlist uses.
function MusicController.GetSound(): Sound?
	return sound
end

function MusicController.IsPlaying(): boolean
	return sound ~= nil and sound.IsPlaying
end

-- Studio /selftest (yields): loads every track now; returns
-- "<name> <id>" for each that failed.
function MusicController.CheckAll(): { string }
	local problems: { string } = {}
	local byId: { [string]: string } = {}
	local probes: { Sound } = {}
	for _, track in MusicConfig.Tracks do
		byId[track.Id] = track.Name
		local probe = Instance.new("Sound")
		probe.SoundId = track.Id
		table.insert(probes, probe)
	end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(probes, function(contentId: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Failure then
				table.insert(problems, ("%s %s"):format(byId[contentId] or "?", contentId))
			end
		end)
	end)
	if not ok then
		table.insert(problems, "PreloadAsync: " .. tostring(err))
	end
	for _, probe in probes do
		probe:Destroy()
	end
	return problems
end

return MusicController
