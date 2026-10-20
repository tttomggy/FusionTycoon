# Music playlist 2: more joyful classical (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines. **Only these edits.**

---

Harris loves The Happy Farmer's bouncy, joyful vibe and wants more like it.
These are all APMOfficial tracks, licensed for Roblox.

## 1. Append to `MusicConfig.Tracks`

Keep the 5 tracks that are there now and add these after them:

```lua
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
```

## 2. `/music play <name>` (Studio)

- Fades to the track whose name contains `<name>`, case-insensitive. For
  example, `/music play radetzky`.
- If nothing matches, it prints the track list.
- Add it to `studio-commands.md`.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs (every
  track loads).
- Update the track list in `docs/systems/sounds.md`.
- Harris: `/music list` shows 11 tracks, all loaded. Try each with
  `/music play <name>`.
- Say which branch you pushed to.
