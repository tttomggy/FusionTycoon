--!strict
--[[
	MusicConfig
	-----------
	The background music (MusicController, client). A chill classical
	playlist, shuffled with no immediate repeat, one Sound in SoundService,
	not looped: when a track ends the next starts. Tracks fade in and out
	over FadeSeconds. The player's on / off and volume are Settings
	(SettingsConfig MusicOn / MusicVolume, default on at 0.25).

	Ids picked from the Creator Store by name (DistroKid / APM, licensed for
	Roblox); audition with the Studio /selftest ("every music track loads").
	Swap any that fail or sound wrong.

	Ducking: a slot with DucksMusic (SoundConfig: the big reveal stings)
	takes the music down to DuckFraction of its level for DuckSeconds.
]]
local MusicConfig = {}

export type Track = { Name: string, Id: string }

local function asset(id: number): string
	return ("rbxassetid://%d"):format(id)
end

MusicConfig.Tracks = {
	-- Grieg, "Morning" from Peer Gynt (orchestra), APM.
	{ Name = "Morning Mood", Id = asset(1839900634) },
	-- Debussy, "Clair de Lune" (solo piano), APM.
	{ Name = "Clair de Lune", Id = asset(1838457617) },
	-- Pachelbel, "Canon in D", APM.
	{ Name = "Canon in D", Id = asset(1846764081) },
	-- Chopin, "Minute Waltz" Op. 64 No. 1, APM.
	{ Name = "Minute Waltz", Id = asset(1837532334) },
	-- Schumann, "The Happy Farmer" (Album for the Young), APM.
	{ Name = "The Happy Farmer", Id = asset(1837532258) },
	-- Mozart, "Eine kleine Nachtmusik" 1st mvt Allegro, APM.
	{ Name = "Eine kleine Nachtmusik", Id = asset(1837488321) },
	-- Mozart, "Rondo alla Turca" (Turkish March), APM.
	{ Name = "Rondo alla Turca", Id = asset(1836330848) },
	-- Brahms, "Hungarian Dance No. 5" (orchestra), APM.
	{ Name = "Hungarian Dance No. 5", Id = asset(1842150470) },
	-- J. Strauss I, "Radetzky March" (orchestra), APM.
	{ Name = "Radetzky March", Id = asset(1844280451) },
	-- Tchaikovsky, "Waltz of the Flowers", APM.
	{ Name = "Waltz of the Flowers", Id = asset(117798839485945) },
	-- Bach, "Brandenburg Concerto No. 3" 1st mvt, APM.
	{ Name = "Brandenburg Concerto No. 3", Id = asset(1842163801) },
} :: { Track }

MusicConfig.FadeSeconds = 2 -- in at the start of a track, out at its end
MusicConfig.DuckFraction = 0.4 -- of the music level while a big sting plays
MusicConfig.DuckSeconds = 2
MusicConfig.DuckRampSeconds = 0.25 -- how fast it dips and comes back
MusicConfig.LoadTimeoutSeconds = 15 -- a track that has not loaded by then is skipped

return MusicConfig
