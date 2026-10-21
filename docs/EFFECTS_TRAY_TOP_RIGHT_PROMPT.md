# Effects tray: one row at the top right (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 4 lines. **Only these edits.**

---

On the iPhone XR emulator, 6ed0aeb's right-edge column looks broken.

- The column starts at 35% of the screen height and must end above the jump
  button, so on a short landscape phone only **2** circles fit.
- The 3rd wraps into a second column to the left, at the **top**.
- So the circles zigzag: Luck sits up-left, the cash burst right, and Safe
  Fusion below. Their timers float between them.

That wrap rule was the planner's mistake, not yours. Replace the layout with
something that can't zigzag.

## 1. Layout: one horizontal row, top right

- **Both layouts:** the circles sit in **one row** in the **top-right
  corner**, right-aligned. The first effect is the rightmost, and new ones
  are added to the left. Each timer sits directly under its own circle.
- **Top:** at `UIKit.GetCardTop()` (the same line the top stack starts
  on), with an 8 px right margin. Top centre belongs to TopStack, so the
  row's left edge must stop at least 12 px short of TopStack's widest slot
  (the objective bar / event chip). If the row would reach it, shrink the
  circles (the FITS sizes you already have, never below 44 px tap targets).
  If it still doesn't fit, wrap into a **second row below the first**,
  still right-aligned. Never a column, and never a zigzag.
- Remove the column, `TOP_FRACTION`, the jump-button wrap and the `Columns`
  plan. Keep `JumpRectFor` for the selftest's obstacle list.
- Check that the row doesn't collide with anything else at the top right
  (the Roblox top-bar items on the right, if any, and any HUD rect there).

## 2. Tooltips

Open **below** the circle first, then below-left, then left, on screen and
overlapping no HUD rect (the same search, re-ordered).

## 3. Selftest

- Replace "on the right edge, clear of the jump button" with:
  - the tray is **one row** (every circle's centre on the same y, ±1 px), or
    two right-aligned rows when it wraps;
  - it sits in the top-right quarter, below `GetCardTop()`;
  - it's clear of TopStack's rects, the weapon bar and the jump button.
- Run it at 1251 × 666, 1366 × 768, 844 × 390 and 896 × 414 (iPhone XR
  landscape), with 3 effects **and** with 5.
- Keep every other check.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs.
- Update the tray description in `docs/UI_TEST.md` and the header of
  `EffectsTray.lua`.
- Harris: iPhone XR emulator, with `/weapons all` and 3 power-ups active.
  The tray is one neat row at the top right, each timer under its circle,
  and nothing overlaps.
- Say which branch you pushed to.
