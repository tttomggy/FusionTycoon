# Selftest triage 2: 33 → 77 FAILs after 444c410 (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 10 lines, one per group: FIXED or WHY-NOT.

---

Harris ran `/selftest` on **444c410** (your triage commit) and got 289 passed,
**77 failed**. Before it, 33 failed. Every FAIL / WARN line is in
`docs/selftest_logs/2026-10-21_444c410_fails.txt`, so read it first.

You can't run Studio, so you are fixing blind. **Read each failing probe's
code and the code it measures before changing anything.** Prefer small,
proven fixes. When a FAIL comes from the test environment rather than the
game, make the **test** robust to it (don't hide it), and say so.

Two things were different in this run:
- **It ran just after 00:00 UTC.** The daily reward and gifts had reset
  (the log shows `DailyClaimed` during the remote fuzz).
- **Harris's Studio viewport is now about 2346 px wide** (it was 1891 ×
  852 before) and probably shorter. Every probe that measures the live
  screen must use the real viewport, or the explicit-viewport math
  (`PlanModalFor`, etc.).

## 1. Weapons lost their hold animations (top priority: gameplay)

LaserGun, FreezeRay and BananaPeel show `no hold track (C0 fallback)`,
`anim nil`, and only the Idle/Core tracks. The switch Bat → SlapGlove
shows the same. The Glove's action track plays, but `Hit fired 0 x`. Before
444c410 these passed (only the switch line failed). Prime suspects:
- `WeaponAnimator.Hold` now calls `stopRig(rig)` **unconditionally**. Check
  that it can't stop or destroy the track it's about to start, or clear the
  rig's loaded clips / registered sequences.
- `CombatController.reconcileHeld`: check that `GetHeldPoseWeapon` and
  `Release` ordering can't release the weapon that was just added
  (Add/Remove fire in either order during a slot switch).
- The Glove's `Hit` marker: check that the marker connection isn't lost
  when the track is restarted.

Fix it so every weapon holds, swings, and switches cleanly, with the old
tracks stopped and the new ones playing. Go back to the pre-444c410
`WeaponAnimator` if that's the honest fix, and solve the switch leftovers in
`reconcileHeld` only.

## 2. Tutorial probes collapsed

- The explain cards measure as `drawn 364x-204`: a **negative** height.
- The objective bar shows "bottom 151 of 125".
- The multiplier step gets "no report from the client".
- In the rebirth and multiplier steps the banner text is the previous
  step's.
- Find why. Was the card mid-PopIn when it was measured, did the probe
  measure the wrong instance, or did a step not advance after a FAIL?
- Make the probes wait for the card to settle (`UIKit.SettleCard`) and
  measure the visual rect.
- If a step really didn't advance, that's a game bug: fix it.

## 3. Card placement: "taller than the band but starts at 70, not 66" (desktop) / 82 vs 79 (phone)

This is every tall panel. The rule says a card taller than the band starts
at `GetCardTop()`. Something now adds 4 px (the event card centring change,
or the shop last-chip tail?). Fix the placement, not the test.

## 4. Text that no longer fits

- **SettingsPanel notes**, **GiftsPanel footer** "Gifts reset at 00:00
  UTC; time adds up…", **RebirthPanel** Keep / Reset lines, **ShopPanel
  footer** (phone).
- These passed at 1891 px. Likely the wider or shorter viewport changes the
  fit scale.
- Make these labels wrap (`TextWrapped` with an auto height) or `FitText`
  them. **Nothing under 13 px.**
- **Shop "under 13 px: Box.Amount 8" (×6):** your `UIKit.FitText(amount,
  13, 8)` breaks the 13 px rule. Shorten the tile text instead ("20 min",
  "Cash", "1 h") and keep it ≥ 13 px.

## 5. Shop chips

- Featured −10.4 / Passes −48.2 px (desktop) and Featured −23.8 (phone):
  the chip scroll overshoots.
- Your "last-chip tail" change probably shifted the canvas. Each chip must
  put its section header at the top within ±2 px.

## 6. Gacha card rates swapped between the two luck runs

- "Luck as is" drew the ×3 numbers, and "luck ×3 event" drew the as-is
  numbers. The (i) panel sums are swapped the same way, and the mutation
  line misses Golden / Diamond / Rainbow.
- So the card shows rates from the **previous** luck.
- Real game bug: when luck changes (an event starts or ends, a potion is
  used), the card and the (i) panel must redraw. Hook them to every luck
  change.

## 7. Auto pull didn't stop

- "9 cycles, stop none (still running), pulls 0 -> 90" with cash for 20
  pulls.
- Either the test's cash cap didn't hold (passive income, Golden Rain or the
  new day's daily reward adding cash), or the stop check is broken.
- Make the test zero the income sources for its duration. If the server
  stop check is wrong, fix it.

## 8. Remote fuzz: "no state change"

Past 00:00 UTC, a fuzzed claim remote made a legitimate daily claim. Have
the fuzz exclude legitimate claims (or claim the daily first), so a real
change still FAILs.

## 9. Tutorial OK timing / hand

- index: "OK on at 1.9 s false"; multiplier: "off at 0.4 s false".
- events / rebirth: "no hand".
- Re-check these after group 2. They are probably the same root cause.

## Check

- `luau-lsp analyze` shows no new errors.
- **List every group with FIXED or WHY-NOT** (one line each).
- Harris: run `/selftest` in a **fresh** Play session, without touching
  anything until it says `done`, and paste only the FAIL lines.
- Say which branch you pushed to.
