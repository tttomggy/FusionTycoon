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
