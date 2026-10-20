# Music playlist: orchestral Morning Mood, add Minute Waltz and The Happy Farmer (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 4 lines. **Only these edits.**

---

Harris wants the original orchestral Morning Mood, not the Kalimba cover.
Clair de Lune and Canon stay. He also wants Chopin's Minute Waltz and
Schumann's The Happy Farmer added. All the ids below are APMOfficial
Creator Store tracks, which are licensed for Roblox use.

## 1. `MusicConfig.Tracks`

Replace the list with this:

```lua
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
} :: { Track }
```

- Remove the Kalimba id `81929495044985` everywhere it appears (config,
  docs, selftest).
- Nothing else in MusicController changes. It still shuffles with no
  immediate repeat.

## 2. Studio commands

- **`/music next`:** fades to the next track now and prints its name.
- **`/music list`:** prints each track with its name, id, `IsLoaded` and
  `TimeLength`.
- Add both to `studio-commands.md`.

## 3. Selftest

Every track in `MusicConfig.Tracks` loads within `LoadTimeoutSeconds`. On a
FAIL, print the track's name and id.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs.
- Update `docs/systems/sounds.md` with the track list.
- Harris: run `/music list`, which should show 5 tracks all loaded. Then run
  `/music next` a few times: Morning Mood is the full orchestra.
- Say which branch you pushed to.
