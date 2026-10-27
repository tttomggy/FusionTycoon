# Triage 12: GachaOnPad probe timeout (it poisons the phone checks), phone card clamp (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines, one per group: FIXED or WHY-NOT. Run the Luau parser,
`tools/theme_token_check.py` and `luau-lsp analyze` (if it runs) before pushing.

---

Harris ran 7fe522c on PC (1920 x 1080) and in the phone emulator. Both show:

```
FAIL tutorial GachaOnPad: no report from the client
```

and then the phone gacha checks fail:

- **On PC (forced phone layout):** `% text 11.5 px`, `Text "🍀 Luck ×" 5.7 px`,
  `(i) hit 29.3 px`, `Caption "Pull" 7.3 px`, `top 54.5 is above ... 56`.
  Those are the DESKTOP variant's sizes (PERCENT_SIZE 22 x 0.523), not the
  phone's 25.
- **In the phone emulator (real 844 x 390 window):** `card x 347..504 y 39..213,
  stack bottom 51 ... top 39.2 is above the stack's bottom 51 + 4 = 56`
  (live drawn top 37), tester `2.3 studs from the anchor`.

## 1. The desktop GachaOnPad probe outlives its 10 s timeout and un-forces the phone layout

`DebugService` runs `GachaOnPad` twice (Phone=false, then Phone=true) with
`SELFTEST_PROBE_TIMEOUT = 10`. The desktop probe is slow now (4 yaws + 3
zooms + 2 view sizes + `gachaToastTops()` waits for a toast, quiet and up,
once per size), so the server gives up at 10 s and fires the phone probe
while the desktop one is still running. When the desktop one finishes it
calls `UIKit.SetForcedPhone(nil)` **in the middle of the phone probe**, so
the phone checks measure the desktop card. That explains every number
above on PC. (In the phone emulator the window is genuinely phone-sized, so
only the timeout line and the tester-offset fail show.)

- Give `GachaOnPad` its own timeout (≥ 40 s, a named constant like
  `SELFTEST_EFFECTS_TIMEOUT`).
- Run `gachaToastTops()` **once per probe** (cache the pair), not per size.
- Stale probes must not leak: the client probe carries its `ProbeId`; every
  `UIKit.SetForcedPhone` / camera restore at the end of a probe only runs if
  that probe is still the current one, and a new probe start restores the
  previous probe's camera first. A probe that times out must never touch
  the layout of the next one.
- Selftest: `/selftest` shows no "no report from the client" for any gacha
  probe; if one does time out, the next probe still sees its own layout
  (assert `UIKit.IsPhone()` equals the probe's `Phone` at its start).

## 2. The phone card must clear the chip row wherever you stand on the pad

On the real phone the card's top landed at 37-39, **under the chip row
(bottom 51)**. `PhoneScaleFor` assumes you stand at the pad's centre at the
default camera (`G.PhoneAnchorY`); the tester stood 2.3 studs off-centre
(a pad is wide; so will players), which moved the anchor on screen and the
card with it. Group 3 of TRIAGE_11 made the phone unclamped to stop toasts
moving it; with the stable bottom that reason is gone.

- **Clamp on phone too**, with the same `StackShiftFor`, the **stable**
  bottom (`TopStack.GetStableBottom() * PhoneScale`) and `G.PhoneTopGapPx`
  as the air, applied as `SizeOffset.Y` only (keep X). Cap the slide so the
  card's bottom never goes below the weapon bar top / bottom row top
  (`GetCardBottomFor`, as the phone fit test already computes). If both
  can't be met (tall card, tiny screen) the top wins and the card shrinks:
  lower the phone `UIScale` just enough (never below `G.PhoneScaleMin`).
  Toasts still never move it.
- Don't remove the "tester stands N studs from the anchor" readout; use it.
- Selftest (phone): assert on the live drawn card when the window is
  phone-sized, and use the pure `StackShiftFor` at 844 x 390 and 896 x 414
  when it isn't (the projection onto a size that is not the window is
  meaningless: `drawn top 164` vs `projected 54` on PC is exactly that).
  Run the live check with the tester at the pad centre AND 3 studs off to
  each side; in every case top ≥ stable bottom + gap and bottom ≤ the bar.

## 3. Docs

`items-and-fusion.md`: phone clamp restored (stable bottom, bottom cap).
`docs/systems/studio-commands.md`: the GachaOnPad probe's timeout and the
probe-id guard.
