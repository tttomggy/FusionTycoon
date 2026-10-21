# Effects tray: move to the right edge (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 4 lines. **Only these edits.**

---

Harris's phone screenshot (landscape, Rebirth 3, all weapons): the effects
tray (cash burst, Safe Fusion x2, Speed Boots) sits **behind the weapon bar**.
The weapon icons (1-5) cover the circles, and the weapon names ("Bat",
"Laser Gun") print over the tray's timers ("1:42", "READY"). It is unreadable
and the circles are hard to tap. `/selftest` didn't catch it because the
weapon bar isn't one of its HUD rects.

## 1. Move the tray to the right edge

- Both layouts: a **vertical column on the right edge** of the screen,
  stacked downward from about 35% of the screen height, with the same icon
  size, spacing and tap targets as now (>= 44 px).
- Phone: keep clear of the jump button (bottom right) with at least 12 px of
  margin, and of the Roblox top bar. The column must fit above the jump
  button even with all 3 circles and a 4th added later (compute from
  `UIKit.GetLogicalViewport()`; if it doesn't fit, wrap into a second column
  to the left).
- Desktop: same column on the right edge, clear of the chat's side and of
  any right-side HUD rect.
- Circles keep their timers and badges. Timer text >= 13 px.

## 2. Tooltips

The tooltip opens to the **left** of the circle first (the column is on the
right edge), then above-left, then below-left, on screen and overlapping no
HUD rect (the four-sided search from triage 3, with the sides mirrored).

## 3. Selftest

- Add the **weapon bar** (the 5 slots with their names) to the HUD rect list
  that "no overlap with any HUD rect" uses, for the tray, its tooltip and the
  deal tile.
- Change the old "in the bottom-left quarter" check to "on the right edge,
  clear of the jump button" at 1251 x 666, 1366 x 768 and 844 x 390, in both
  layouts. Run it with the weapon bar showing (`/weapons all`).
- Keep every other check.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs.
- Update `docs/UI_TEST.md` and any doc that says the tray sits bottom left.
- Harris: Play with the phone emulator (and the desktop view), with
  `/weapons all`. The tray is a column on the right, nothing overlaps the
  weapon bar, and the tooltips open to the left.
- Say which branch you pushed to.
