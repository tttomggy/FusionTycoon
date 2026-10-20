# Sounds

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Sounds** (`SoundConfig` slots + `SoundKit.Play(slot, parent?)`): every
  sound goes through a slot; an empty Id is silent, a failed Id warns once
  (client `SoundKit.Preload` at boot). Every slot holds a Roblox-owned
  (creator id 1) Creator Store SFX, no two alike. **Volume:**
  `PlayerData.Settings.SfxVolume` (0–1, default 0.8, server-clamped) and
  `SfxMuted`, via `SetSetting { Key = "SfxVolume" | "SfxMuted", Value }`;
  every sound plays through the `SFX` SoundGroup, whose Volume each client
  sets locally (`SoundKit.SetVolume`, from TycoonController), so it covers
  server-played sounds too. SettingsPanel's "Sound effects" row: slider
  (saves on release) + mute toggle. **Play cap:** at most
  `SoundConfig.MaxConcurrentPerSlot` (6) of one slot at once; extra plays
  are dropped. Per slot: `SpeedJitter` (CoinPickup 0.95–1.1) and
  `RollOffMaxDistance` (Thunder 150, MeteorImpact 200 via
  `SoundKit.PlayAt`). No looping ambient sounds (the pedestal bell loop is
  gone). `docs/SOUNDS.md` lists every slot with its id and name.
  **Combat sounds (Polish 12):** every combat slot has an id: `Swing`
  (Bat / Glove swing), `Bonk` (Bat hit), **`Slap`** (Glove hit; the
  CombatController `Bonk` HitFx plays `Slap` for `SlapGlove`), `Shoot`
  (Laser Gun / Freeze Ray fire), `Laser` (the same clip at a fixed
  `PlaybackSpeed` 1.3, via the slot's `PlaybackSpeed` field), `Freeze`,
  `Slip`, `Equip`. Studio **`/sound <slot>`** plays a slot at your
  character (no argument lists them). `SoundKit.CheckAll` (in `/selftest`)
  loads every slot and the FAIL names each failing `<slot> <id>`.
  **Music** (`MusicConfig`, client `MusicController`): one `Sound`
  ("Music", SoundService, not in the SFX group) plays eleven tracks, all APM (Morning Mood: Grieg's orchestral "Morning" 1839900634; Clair de Lune 1838457617; Canon in D 1846764081; Chopin's Minute Waltz 1837532334; Schumann's The Happy Farmer 1837532258; Mozart's Eine kleine Nachtmusik 1837488321 and Rondo alla Turca 1836330848; Brahms' Hungarian Dance No. 5 1842150470; Strauss' Radetzky March 1844280451; Tchaikovsky's Waltz of the Flowers 117798839485945; Bach's Brandenburg Concerto No. 3 1842163801) shuffled with no immediate repeat (a shuffled bag
  whose first track is never the last one played), not looped; the next
  track starts when one ends, each fading in over 2 s and out over its last
  2 s (`MusicConfig.FadeSeconds`). Level = `MusicVolume` × fade × duck, set
  every frame. **Settings** `MusicOn` (default true) and `MusicVolume`
  (0–1, default 0.25, server-clamped), via `SetSetting { Key = "MusicOn" |
  "MusicVolume", Value }`; ⚙ Settings has a **Music** section (the same
  slider + toggle row as Sound effects). Off = the Sound is paused and
  resumes where it was; silent until the first snapshot (a saved "off"
  never blips on at boot). **Ducking:** a slot with `DucksMusic`
  (`RevealMajor`, `EventReveal`: the big reveal stings) tells
  `MusicController` through `SoundKit.SetDuckHandler`, and the music dips
  to 40% for 2 s (`MusicConfig.Duck*`). A track that has not loaded after
  15 s is skipped (warn, not retried). Studio `/music play <name>` (fades to the first track whose name contains it, case-insensitive; no match prints the list), `/music next` (fades to the shuffle's next track and prints it) and `/music list` (name, id, `IsLoaded`, `TimeLength`). `/selftest`: every track loads (`IsLoaded` within `LoadTimeoutSeconds`; a FAIL names the track and id), the
  playlist plays, a sting ducks it, the toggle stops it and turning it back
  on resumes it.
