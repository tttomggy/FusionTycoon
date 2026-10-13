# Gacha board bug, Studio test-ready start, no silent swings (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 10 lines or fewer.

---

Harris tested `2e30f95` + `4caa0eb` on Oct 13 with 2 players:

- **The weapon bar is gone, and the Bat and Glove "still don't do
  anything".**
  - Both labs show `PROTECTED · NEW LAB` and `$2/s`, and REBIRTH reads
    `$2.67K / $15M`. Both players are **Rebirth 0**: the Mock store starts
    fresh every Play.
  - At Rebirth 0 the weapon bar is hidden by design, `whyCantSwing` refuses
    (`NeedsRebirth`), and nobody can be hit. So every swing is refused
    **silently**.
  - The launch itself works: `/selftest combat` shows 60 and 120 studs/s
    for 10 Heartbeats, and both launch checks pass.
- **Gacha board:** it's an empty violet panel with a header and a price,
  and **no tiles at all**. It's tilted, out by the right wall, inside a
  huge yellow Neon box. Harris: "completely ruined".
- `/selftest combat`: 6 FAILs, all "hand … moved 0.01 studs" plus the live
  fallback (`hand moved 0.03`). The same checks moved 2.38 / 2.57 studs on
  the previous build.
- `/selftest gacha`: FAILs on "% text ≥ 0.5 studs" (with an empty detail)
  and "3 custom buttons visible" (also with an empty detail).

## 1. Gacha board: the tiles are never parented (the real bug)

In `GachaBoardController`, `buildTile(...)` builds the tile and returns
it, and `populate` sets its `LayoutOrder`, but **nothing ever sets
`tile.Parent = tiles`**. `buildChip` is the same: no `chip.Parent`. The
old `GachaCardController` did both, at its lines 334 and 359. So the tiles
and mutation chips are orphans and never draw.

- Parent them.
- **Why the selftest missed it:** "6 tiles, each with a ViewportFrame"
  read the controller's own `view.Tiles` table, not what's drawn. New rule
  for **every** UI selftest, in this file and anywhere else you find the
  pattern:
  - read from the **instance tree** under the gui (`gui:GetDescendants()`);
  - check `AbsoluteSize.X > 0` and `AbsoluteSize.Y > 0`, `Visible` up the
    whole chain, and `TextBounds.Y > 0` for text.
  - Fix the gacha checks this way, and grep `SelfTestController` for other
    checks that read a Lua table instead of the tree.
- An empty `Detail` on a FAIL is not allowed. Every FAIL says what it
  measured (counts, sizes) so Harris's paste is enough to debug.

**Placement and look:** keep the tile design. Harris hasn't seen it drawn
yet. Change only these:

- **Upright** (`TiltBackDegrees = 0`), **directly behind the pad** (about 4
  studs past the pad's far edge, not 8), and **facing the walkway**, where
  you walk up from, so you read it straight on as you approach. Not at an
  angle by the wall.
- About 11 × 7.5 studs, with the bottom edge at about 5.5 studs so it shows
  above your character's head while you stand on the pad.
- **Rim:**
  - Remove the big yellow Neon box.
  - The board's body is a dark SmoothPlastic frame, about 0.4 studs
    thick.
  - Only a **thin** gold Neon strip (about 0.12 studs) runs along the top
    and the two sides, per CLAUDE.md's thin-band rule.
  - The gold rim inside the SurfaceGui stays.
- Update `PlotLayout.Gacha` and the footprint. The assertion block must
  still pass.

**The "3 custom buttons visible" FAIL:** find out why, and make the check
stand the character on the pad and wait for `PromptShown` before it
measures. Its Detail must list each button's `AbsoluteSize` and
`Visible`.

## 2. Studio starts every test ready to fight

- Add `DebugConfig.StudioStartRebirths = 3` and
  `DebugConfig.StudioGrantAllWeapons = true`.
- On join, **in Studio and only on the Mock store**, every player gets
  Rebirths raised to that number (never lowered) and all weapons, the
  same way `/rebirths 3` and `/weapons all` do it. Run it once per join,
  next to `SkipTutorialInStudio`.
- The Live store and live servers never get it. Add a `/selftest` line
  asserting that.
- `/rebirths 0` still works for testing Rebirth-0 flows during a session.
- Document it in `studio-commands.md`.

## 3. No silent swings

- **You're under Rebirth 1 with a weapon in hand** (Studio `/weapons all`,
  or the quest Slap Glove): clicking shows one toast, "Fighting unlocks at
  Rebirth 1", at most once every 3 s, and sends nothing to the server.
- **Your melee target is under Rebirth 1:** pop "🛡 NEW LAB" over them,
  for you only. Use the same pop and attacker-only path as IMMUNE.
  Spawn-protected targets get "🛡" too.
- Tell the client why a hit didn't land. The server already knows
  (`WhyNotHittable`), so add an optional `Reason` to the Swing `HitFx`, or
  a small reply to the attacker. No silent refusals left in combat.

## 4. The hold-pose checks dropped from 2.38 to 0.01 studs

Don't change the clips (Harris approved them).

- Log the rest offset, the held offset, and every playing track's name,
  weight and priority at the moment of measuring.
- Then find which it is:
  - the rest is sampled while a previous hold track is still fading;
  - the hold track's weight is 0, or it's overridden (Animate, or the
    priority);
  - `forceFallback` is left on after the live-fallback probe.
- Fix that. The live-fallback check should also show the C0 pose moving
  the hand ≥ 1 stud.

## Check

- `luau-lsp analyze` shows no new errors.
- `/selftest combat` and `/selftest gacha` show **no FAILs**, and every
  FAIL you saw on the way had a non-empty Detail.
- For Harris, Studio Test → 2 players, **with no commands typed**:
  1. Both players are at Rebirth 3 with the weapon bar.
  2. Player1 bats Player2, and Player2 flies.
  3. The Glove launches further, with a spin.
  4. Then `/rebirths 0` on Player2: the hit shows "🛡 NEW LAB".
  5. The gacha board stands upright behind the pad with 6 coloured tiles
     and spinning orbs, readable as you walk up the walkway.
- Update `docs/systems/combat.md`, `items-and-fusion.md`,
  `studio-commands.md` and UI_TEST.
- Say which branch you pushed to.
