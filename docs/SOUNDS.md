# Sounds

Every sound in Fusion Tycoon goes through one slot in
`src/ReplicatedStorage/Shared/Config/SoundConfig.lua`, played with
`SoundKit.Play(slot, parent?)` (or `SoundKit.PlayAt(slot, position)` for a
world point). To change a sound, put a Creator Store id
(`rbxassetid://123…`) in that slot's `Id` and tune `Volume`. Nothing else
needs to change.

- **Every slot is filled** with a public Creator Store sound effect
  uploaded by the **Roblox account (creator id 1)**, so it loads in any
  experience. They were **picked by Claude** from the store's names and
  lengths, without listening: flag any that sound wrong in a playtest. No
  slot reuses another's sound (the old `electronicpingshort` placeholder is
  gone).
- **An empty Id is silent** and raises no error.
- **A bad Id warns once** at startup (`SoundKit: <slot> failed to load
  <id>`, from `SoundKit.Preload` in `Bootstrap.client.lua`), then that slot
  stays silent.
- **Player volume:** Settings → Sound effects (0–100%, default 80%, plus a
  mute toggle), saved as `PlayerData.Settings.SfxVolume` / `SfxMuted`. Every
  sound plays through the `SFX` SoundGroup, whose Volume each client sets
  locally, so it scales every slot, including sounds the server plays
  (`Station`).
- **Play cap:** at most 6 sounds of one slot at once
  (`SoundConfig.MaxConcurrentPerSlot`); extra plays are dropped, not
  stacked (a Golden Rain coin streak, Pull ×10).
- Per-slot extras in SoundConfig: `SpeedJitter` (random PlaybackSpeed per
  play) and `RollOffMaxDistance` (positional plays).
- **There is no looping ambient sound.** The Mythic/Secret pedestal bell
  loop was removed.

| Slot | Asset id | Creator Store name | Volume | Plays when / where | Notes |
|---|---|---|---|---|---|
| `EventStart` | 15675043410 | Roblox_UI_Tonal_Stinger (1 s) | 0.6 | Event start banner, once as it appears (EventController) | picked by Claude |
| `EventEnd` | 15675081158 | Roblox_UI_Cute_Goodbye | 0.5 | "<Event> is over" toast | picked by Claude |
| `CoinPickup` | 16480580213 | Roblox_Pinball_8Bit_Blip_01 | 0.45 | You collect a Golden Rain coin, lab or street (EventController) | PlaybackSpeed random 0.95–1.1; picked by Claude |
| `BigCoin` | 127645268874265 | CoinTransfer_01 (2 s) | 0.6 | You collect a BIG coin | picked by Claude |
| `Thunder` | 12222030 | HalloweenThunder.wav (4 s) | 0.55 | A Power Surge bolt, at the struck target (EventController) | positional, RollOffMaxDistance 150; picked by Claude |
| `MeteorImpact` | 3149249837 | Cannon_Explode | 0.5 | A meteor lands, at the crater (EventController, `PlayAt`) | positional, RollOffMaxDistance 200; picked by Claude |
| `EventReveal` | 16480577565 | Roblox_Pinball_8Bit_Riser_04 (3 s) | 0.6 | The event-only mutation reveal card: Charged / Void / Celestial (ResultController) | picked by Claude |
| `Grab` | 15675024286 | Roblox_UI_Whoosh_01 | 0.6 | You grab an item off an enemy pedestal (HeistController) | picked by Claude |
| `Alarm` | 16480579431 | Roblox_Pinball_8Bit_Blip_05 | 0.5 | Your item is being stolen (HeistController) | played 3×, PlaybackSpeed 1.3; picked by Claude |
| `RevealMajor` | 12222253 | victory.wav | 0.6 | A big fusion reveal at the machine (RevealEffects) | picked by Claude |
| `RevealMinor` | 15675055424 | Roblox_UI_Cute_Pop | 0.45 | Other fusion reveals (RevealEffects), skipped-card pulls (ResultController) | picked by Claude |
| `Toast` | 15675059323 | Roblox_UI_Bright_Click | 0.35 | Top announcement banners (AnnouncementController); the Settings volume preview | picked by Claude |
| `Station` | 10066947742 | RBLX UI Purchase (SFX) | 0.5 | A station purchase: Multiplier Pad, gacha (TycoonService, at the pad) | server-played, still follows each player's volume; picked by Claude |
| `Bonk` | **empty** | (pick: a cartoon bonk, a short hollow "bonk" / wooden thunk with a boing, 0.3–0.6 s) | 0.6 | A Bat / Slap Glove / Laser hit lands, at the target (CombatController, `PlayAt`) | positional, RollOffMaxDistance 120, PlaybackSpeed 0.9–1.1; silent until an id is set |
| `Laser` | **empty** | (pick: a short sci-fi laser zap, a bright "pew", 0.2–0.5 s) | 0.5 | A Laser Gun shot, at the muzzle | positional, RollOffMaxDistance 150; silent until an id is set |
| `Freeze` | **empty** | (pick: an ice crackle: a glassy freeze-over "shhk" with crystal tinkles, 0.5–1 s) | 0.5 | A Freeze Ray shot (at the muzzle) and the freeze landing (at the target) | positional, RollOffMaxDistance 120; silent until an id is set |
| `Slip` | **empty** | (pick: a cartoon slip: a rising slide-whistle "wheeeee" or a squeaky skid, 0.4–0.8 s) | 0.6 | Someone steps on a Banana Peel | positional, RollOffMaxDistance 120; silent until an id is set |
| `Swing` | **empty** | (pick: a quick whoosh, airy and short, 0.2–0.35 s; it plays at the start of every Bat / Slap Glove swing, hit or miss) | 0.5 | A melee swing starts, at the swinger (yours the moment you click, others from `HitFx` Swing) | positional, RollOffMaxDistance 90, PlaybackSpeed 0.95–1.1; silent until an id is set |
| `Shoot` | **empty** | (pick: a soft mechanical trigger click plus a small air thump, 0.1–0.25 s; layered under Laser / Freeze) | 0.45 | A gun fires, at the shooter (Freeze Ray plays it at 0.8 speed) | positional, RollOffMaxDistance 120; silent until an id is set |
| `Equip` | **empty** | (pick: a light metallic "shink" / holster slide, 0.15–0.3 s) | 0.4 | A weapon comes up in someone's hand, at them | positional, RollOffMaxDistance 60; silent until an id is set |

> **For Harris:** the seven combat slots above are still empty. I couldn't
> look up Creator Store ids from the build environment, so none are picked;
> each row says what it should sound like. Search the Creator Store
> (Audio → Sound effects) for the creator "Roblox", put the numeric id
> into the slot in `SoundConfig.lua`, and tune `Volume`.
