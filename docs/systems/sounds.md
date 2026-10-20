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
  ("Music", SoundService, not in the SFX group) plays Morning Mood, Clair
  de Lune and Canon in D shuffled with no immediate repeat (a shuffled bag
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
  15 s is skipped (warn, not retried). `/selftest`: every track loads, the
  playlist plays, a sting ducks it, the toggle stops it and turning it back
  on resumes it.
