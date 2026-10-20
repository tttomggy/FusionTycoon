# Polish 12: weapon sounds + classical music, a bigger melee hitbox, cartoon effect icons with tooltips, the "Fuse a Mythic" quest bug (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 10 lines. Run `luau-lsp analyze` before pushing.

---

Harris's feedback on Oct 20 (Polish 11 is live and approved):

1. Every weapon is silent. He wants a sound on all of them.
2. He wants background music: chill classical, e.g. "Morning Mood".
3. The melee hitbox is too small: "you have to hit exactly at them".
4. The effects tray icons should be **cartoon icons with effects** (e.g.
   Cash Burst = a cash icon with sparkles), not the product photo (today
   the Boost cell shows the lightning-bolt shop PNG).
5. Hovering or tapping an effect icon must pop up a few words on what it
   does.
6. **Bug:** a friend fused Legendaries into a Mythic, and the lab quest
   "Fuse a Mythic" didn't give her the Slap Glove. It worked for Harris.

## 1. Weapon sounds (`SoundConfig`)

The ids were found in the Creator Store (free). APM, ProSoundEffects and
DistroKid assets are licensed for Roblox use; the rest are short public
SFX.

| Slot | Id | Source | Used for |
|---|---|---|---|
| Swing | `9120972321` | ProSoundEffects "Wood Whoosh Quick Swing" | Bat and Glove swing |
| Bonk | `121015905545694` | "Hit_Fryingpan" | Bat hit |
| **Slap** (new slot) | `9114758204` | ProSoundEffects "Hand Clap 1" | Glove hit (today it uses Bonk) |
| Shoot | `96445944074750` | "eblaster_blast_fire_01" | Laser Gun fire |
| Laser | `96445944074750` at PlaybackSpeed 1.3 | same | Laser hit |
| Freeze | `87971519891129` | "AW Freeze Spreading" | Freeze Ray hit |
| Slip | `97197794979302` | "slide whistle" | Banana Peel slip |
| Equip | `9117509491` | ProSoundEffects "Plastic Flashlight pick up" | Weapon comes out |

- Wire **Slap** into CombatController's hit FX for the Glove. Every other
  slot is already wired.
- **Audition command:** add Studio `/sound <slot>`, which plays that slot
  at your character, so Harris can judge each one by ear and swap ids.
  Add it to `studio-commands.md`.
- `SoundKit.CheckAll` in `/selftest` must load every slot. If one fails
  (moderated or private), print its slot and id in the FAIL.

## 2. Background music: a chill classical playlist

New `MusicConfig` and a client `MusicController`.

**Playlist, shuffled with no immediate repeat:**
- `81929495044985`: Grieg, "Morning Mood" (Kalimba), DistroKid;
- `1838457617`: Debussy, "Clair de Lune" (solo piano), APM;
- `1846764081`: Pachelbel, "Canon in D", APM.

**Playback:**
- one `Sound` in SoundService, `Volume = 0.25`, not looped;
- a 2 s fade between tracks, and the next track starts when one ends.

**Settings:**
- add a **Music** section to `SettingsPanel`: an on/off toggle plus a
  volume slider (0–100%), saved in the player's settings like the
  sound-effects toggle;
- default on at 25%;
- replace the "Music isn't in yet" note.

**Ducking:** while a big reveal card plays its sting, fade the music to
40% of its level for 2 s.

**Selftest:** every track loads; the toggle stops the music and turning it
back on resumes it.

## 3. A more forgiving melee hitbox

- **Per weapon:**
  - **Bat:** `MeleeBox = Vector3.new(9, 8, 10)`, centred
    `MeleeBoxForward = 4.5`.
  - **Glove:** `MeleeBox = Vector3.new(11, 8, 11)`, forward `5`.
  - Move these into each weapon's `CombatConfig` entry.
- **Lag tolerance:** also count a target whose root was inside the box at
  the swing request time, as well as at the delayed check. Keep each
  player's last 0.3 s of root positions server-side.
- **Range check:** keep a sanity limit of weapon range + `RangeSlack`.
- `/combat box` shows the new boxes.
- **Selftest:** the end-to-end swing check with the target **6 studs** in
  front and **3 studs to the side** must HIT for the Bat. The "5 studs to
  the side MISS" check moves to 7 studs to the side.

## 4. Cartoon effect icons (`EffectsTray`)

Stop using shop product PNGs in the tray. Each effect is a **code-built
cartoon badge**:

- a 60 px circle with a bright 2-stop gradient in the effect's colour,
  a 3 px white stroke and a soft ink drop shadow;
- one big cartoon glyph, 34 px, with a 2 px ink outline (UIStroke on the
  label) so it reads like a sticker;
- an **effect layer** behind the glyph, different per effect, animated
  only while the tray is on screen. Never flashing.

| Effect | Glyph | Gradient | Effect layer |
|---|---|---|---|
| Cash Burst / Boost (income) | 💵 | green | 3 small 🪙 orbiting slowly, plus a sparkle twinkle every 2 s |
| Luck (Potion / Charm) | 🍀 | teal | a soft rotating shine ring |
| Speed Boots | 👟 | blue | 3 speed-line streaks sliding left |
| Safe Fusion | 🛡 | violet | a gentle pulse glow (scale 1 → 1.06 every 2 s) |
| Fusion Spark | ⚡ | gold | 2 tiny ✦ sparks drifting up |
| Coin Magnet | 🧲 | red | 2 🪙 drifting toward the magnet |
| Overclock (server) | ⚙️ | orange | slow cog rotation |

The timer under the icon, the `×N` badges and `READY` all stay.

## 5. Tooltip on hover AND tap, every time

- **Desktop:** `MouseEnter` shows the tooltip at once; `MouseLeave` hides
  it.
- **Touch:** a tap shows it for 3 s, or until another tap anywhere.
- **Content:** the effect name in bold, then its `Plain` text (e.g.
  "Double cash for 1 hour"), then "12:41 left" (or "×3 left" /
  "Ready").
- **Look:** a dark pill card with a small arrow pointing at the icon,
  max 220 px wide, 14 px text. It's clamped on screen, and it opens
  **above** the icon because the tray is at the bottom.
- **Selftest:** grant a Luck Potion; fire the cell's `MouseEnter` and check
  the tooltip is visible with the Plain text and a time; fire
  `MouseLeave` and check it's hidden.

## 6. The "Fuse a Mythic" quest bug

Lab chain step 3 is `FuseInto Mythic`. It's a **counted** kind, and
`startChain` sets `ChainBase = counter(...)`. So a Mythic fused **before**
the player reached step 3 never counts, and she must fuse another one.
On top of that, the reward only arrives after pressing **Claim**. And at
Rebirth 0 the weapon bar is hidden, so even a granted glove is invisible.
Fix all three:

1. **Count the past for "achievement" chain steps.** For chain steps with
   kind `FuseInto` (and any future "have you ever…" kind), use base 0:
   the player's lifetime `Fused_<Tier>` stat counts. Daily quests keep
   counting from their start.
2. **Make a ready claim obvious.** When a chain step completes:
   - a toast "Lab quest done! Claim your Slap Glove in QUESTS";
   - a red "!" badge on the QUESTS button until it's claimed;
   - check the badge exists today and covers the chain.
3. **A weapon earned under Rebirth 1:**
   - the unlock card says "You got the Slap Glove! Fighting unlocks at
     Rebirth 1";
   - the weapon is saved (it is already), and the bar appears at
     Rebirth 1 with it in.
4. **Diagnosis:** add Studio `/quest status`, which prints the chain step,
   kind, base, progress, Done/Claimed, and the player's `Fused_*` stats.
5. **Selftest:**
   - put a fresh player on step 3 after setting `Fused_Mythic = 1`: the
     step is complete at once;
   - claim it: the Slap Glove is owned;
   - at Rebirth 0 the unlock card text mentions Rebirth 1.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs.
- Give Harris this list:
  1. Swing, slap, shoot, freeze, slip and equip all make a sound. Use
     `/sound Bonk` etc. to audition, and tell me any to swap.
  2. Music plays (Morning Mood, Clair de Lune, Canon), and Settings →
     Music toggles it and sets the volume.
  3. Hitting is easier: near misses now land, and `/combat box` shows the
     bigger box.
  4. `/shop grant LuckPotion` and `/powerup CashBurst 1`: cartoon
     sticker icons with little animations, and hovering shows what each
     does.
  5. `/quest status` explains any quest.
- Update `docs/systems/combat.md`, `sounds.md`, `quests.md`,
  `items-and-fusion.md`, `studio-commands.md` and UI_TEST.
- Say which branch you pushed to.
