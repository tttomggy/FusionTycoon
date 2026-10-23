# Selftest triage 5: sub-pixel jump-button check, auto-pull test vs the income cap (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines. **Only these edits.** (Run this after `PHONE_LIVE_FIXES_PROMPT`
if that one is in progress. Don't mix them.)

---

Harris ran `/selftest` on beeaf4c and got 4 FAILs. **Both causes are in
the tests, not the game.**

## 1. "jump button (1180 x 820, tablet): showing or hiding it moves …" (1 FAIL)

The rects differ by **under 1 px**: `537.18, 586.75 → 537.5, 587` and
`816.64, 69.25 → 816, 69`. Nothing visibly moves. The layout lands on
fractional pixels in one state and on whole ones in the other.

- **Snap** the tray, bottom row and weapon bar positions to whole pixels
  (`math.floor(x + 0.5)`) in their placement code. Fractional positions
  also blur text.
- Then compare with a **±1 px** tolerance.

## 2. Auto pull: "ran exactly 2 cycles" → 1 cycle; the gap and card checks fail with it (3 FAILs)

- The test funds exactly 2 ×10 cycles, priced with `steady0` (the steady
  income before the run) plus a 2% buffer.
- But the first 10 pulls land on the pedestals (auto-display). That
  **raises steady income**, and with the gacha price cap (15 s of steady
  income) the second cycle now costs more than the cash left. So
  `InsufficientCash` after 1 cycle is correct game behaviour.
- Fix the **test**: hold the price inputs still for its duration.
  - Either pause auto-display for the tester during the auto-pull block
    (restore it after, and re-run auto-display once),
  - or fund cycle 2 from the steady income measured **after** cycle 1, via
    a small selftest-only hook.
  - Pick whichever is less code, and say which.
- Don't change the game's pricing.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs (big
  window, then iPad Air).
- Say which branch you pushed to.
