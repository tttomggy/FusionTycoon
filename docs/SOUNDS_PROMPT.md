# Fusion Tycoon — fill every sound slot (build prompt for Claude Code)

Paste into Claude Code on `world-redesign` (`git pull` first). Small pass, so
one commit. Don't merge.

---

Harris doesn't want to pick sounds himself, so I picked one for every
`SoundConfig` slot. Every id below is uploaded by the **Roblox account
(creator id 1)** and listed as a public Creator Store sound effect, so it will
load in any experience. I looked them up through the Creator Store API by name
and length but couldn't listen to them, so Harris will flag any that sound
wrong in the playtest.

| Slot | Asset id | Creator Store name | Volume | Notes |
|---|---|---|---|---|
| `EventStart` | 15675043410 | Roblox_UI_Tonal_Stinger (1 s) | 0.6 | plays once when the banner shows |
| `EventEnd` | 15675081158 | Roblox_UI_Cute_Goodbye | 0.5 | |
| `CoinPickup` | 16480580213 | Roblox_Pinball_8Bit_Blip_01 | 0.45 | randomise PlaybackSpeed 0.95–1.1 per play so a stream of coins doesn't drone |
| `BigCoin` | 127645268874265 | CoinTransfer_01 (2 s) | 0.6 | |
| `Thunder` | 12222030 | HalloweenThunder.wav (4 s) | 0.55 | positional at the struck pedestal, RollOffMaxDistance 150 |
| `MeteorImpact` | 3149249837 | Cannon_Explode | 0.5 | positional at the crater, RollOffMaxDistance 200 |
| `EventReveal` | 16480577565 | Roblox_Pinball_8Bit_Riser_04 (3 s) | 0.6 | the Charged / Void / Celestial reveal card |
| `Grab` | 15675024286 | Roblox_UI_Whoosh_01 | 0.6 | |
| `Alarm` | 16480579431 | Roblox_Pinball_8Bit_Blip_05 | 0.5 | keep the 3× play, PlaybackSpeed 1.3 |
| `RevealMajor` | 12222253 | victory.wav | 0.6 | |
| `RevealMinor` | 15675055424 | Roblox_UI_Cute_Pop | 0.45 | |
| `Toast` | 15675059323 | Roblox_UI_Bright_Click | 0.35 | |
| `Station` | 10066947742 | RBLX UI Purchase (SFX) | 0.5 | Multiplier Pad / gacha purchase |

Write each as `rbxassetid://<id>`. **Replace every `electronicpingshort`
placeholder:** no slot reuses another's sound.

## Also

- **A volume setting:** add a "Sound effects" slider (0–100%, default 80%) to
  SettingsPanel under the big-card section.
  - Saved in `PlayerData.Settings.SfxVolume` through `SetSetting`, with the
    server clamping it to 0–1.
  - SoundKit multiplies every slot's Volume by it.
  - A mute toggle sits next to it.
- **A SoundKit play cap:** at most 6 of the same slot playing at once (a Golden
  Rain coin streak, Pull ×10). Drop extra plays rather than stacking them.
- **Preload:** `SoundKit.Preload` warns once for any id that fails. Run Play in
  Studio, then paste the Output warnings (if any) in your summary.
- **Docs:** update `docs/SOUNDS.md` (the id, name and "picked by Claude"
  for each slot) and CLAUDE.md (the SfxVolume setting and the play cap). Add
  UI_TEST cases: every slot audible once, the volume slider, mute, and no
  stacking on a coin streak.

`luau-lsp analyze`: no new errors. Commit, push, and add a section to the open
PR (or open one from `world-redesign` if none is open).
