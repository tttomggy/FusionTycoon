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
local Players = game:GetService("Players")
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
-- /music next: the chosen next track and when the fade-out of this one began.
local skipTo: number? = nil
local skipAt = 0
local SKIP_FADE_SECONDS = 1

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
	local index = skipTo or nextIndex()
	skipTo = nil
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
	-- /music next: this track fades out over SKIP_FADE_SECONDS, then the next starts.
	if skipTo then
		local left = 1 - (os.clock() - skipAt) / SKIP_FADE_SECONDS
		if left <= 0 then
			playNext()
			return
		end
		fade = math.min(fade, left)
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
	if RunService:IsStudio() then
		-- Studio chat: /music next | list (client side, the Sound is here).
		Players.LocalPlayer.Chatted:Connect(function(message: string)
			local command, argument = message:lower():match("^(%S+)%s*(.*)$")
			if command ~= "/music" then
				return
			end
			if argument == "next" then
				local name = MusicController.Next()
				print(if name then ("MusicController: next -> %s"):format(name) else "MusicController: no track left to play")
			elseif argument:sub(1, 5) == "play " then
				local name = MusicController.Play(argument:sub(6))
				if name then
					print(("MusicController: playing %s"):format(name))
				else
					warn("MusicController: no track matches; the tracks are:")
					for _, line in MusicController.List() do
						print(line)
					end
				end
			elseif argument == "list" then
				for _, line in MusicController.List() do
					print(line)
				end
			else
				warn("MusicController: /music next | /music list | /music play <name>")
			end
		end)
	end
	RunService.Heartbeat:Connect(step)
	started = true
	playNext()
end

-- Studio /music next: fades this track out and starts the next one (the
-- shuffle's pick); returns its name, nil when every track failed.
function MusicController.Next(): string?
	local index = nextIndex()
	if not index then
		return nil
	end
	skipTo = index
	skipAt = os.clock()
	return MusicConfig.Tracks[index].Name
end

-- Studio /music play <name>: fades to the first track whose name contains
-- `query` (case-insensitive); returns its name, nil when none matches.
function MusicController.Play(query: string): string?
	local needle = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if needle == "" then
		return nil
	end
	for index, track in MusicConfig.Tracks do
		if track.Name:lower():find(needle, 1, true) then
			skipTo = index
			skipAt = os.clock()
			return track.Name
		end
	end
	return nil
end

-- Studio /music list: each track's name, id, IsLoaded and TimeLength (the
-- playing one from the playlist Sound, the rest from a probe Sound).
function MusicController.List(): { string }
	local lines: { string } = {}
	local probes: { Sound } = {}
	for index, track in MusicConfig.Tracks do
		local music = sound
		local source: Sound
		if music and current == index then
			source = music
		else
			source = Instance.new("Sound")
			source.SoundId = track.Id
			source.Parent = SoundService
			table.insert(probes, source)
		end
		local waited = 0
		while not source.IsLoaded and waited < 3 do
			task.wait(0.25)
			waited += 0.25
		end
		table.insert(lines, ("%d. %s  %s  IsLoaded %s  TimeLength %.1f s%s"):format(
			index,
			track.Name,
			track.Id,
			tostring(source.IsLoaded),
			source.TimeLength,
			if current == index then "  (playing)" else ""
		))
	end
	for _, probe in probes do
		probe:Destroy()
	end
	return lines
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
	-- Each track must also report IsLoaded within LoadTimeoutSeconds (the same
	-- limit the playlist skips a track at).
	local deadline = os.clock() + MusicConfig.LoadTimeoutSeconds
	for _, probe in probes do
		probe.Parent = SoundService
	end
	for index, probe in probes do
		while not probe.IsLoaded and os.clock() < deadline do
			task.wait(0.25)
		end
		if not probe.IsLoaded then
			local track = MusicConfig.Tracks[index]
			local entry = ("%s %s"):format(track.Name, track.Id)
			if not table.find(problems, entry) then
				table.insert(problems, entry .. " (not loaded in time)")
			end
		end
	end
	for _, probe in probes do
		probe:Destroy()
	end
	return problems
end

return MusicController
