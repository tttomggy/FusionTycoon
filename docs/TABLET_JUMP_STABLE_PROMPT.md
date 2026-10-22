# Tablet: the tray and the bottom row jump around when the jump button shows or hides (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines. **Only these edits.**

---

Harris tested in Studio's **iPad Air 5th Generation** emulator.
- Roblox shows the touch jump button only some of the time. It hides when
  the last input was the mouse or keyboard, and comes back on touch.
- `UIKit.JumpButtonShowing()` follows that live, so the effects tray
  **bounces**: bottom-right corner ↔ above the jump button.
- The bottom row and the weapon bar slide left and back too (UPGRADES moves
  ~10 px between his two screenshots).

## Fix

- On a **touch device** (`UserInputService.TouchEnabled`), always plan as
  if the jump button is showing.
  - The tray sits above the jump rect, and the bottom row and weapon bar
    keep their slide, **whether or not the button is visible right now**.
  - Decide once per layout change (`UIKit.LayoutChanged` / a viewport
    resize), never on TouchGui visibility.
- Non-touch desktop: no jump rect, as now.
- Phone: unchanged (the phone layout already always reserves it).
- **Selftest:**
  - with the tablet case (1180 × 820, touch), toggling the jump button's
    visibility doesn't move the tray, the bottom row or the weapon bar
    (same rects, ±0 px);
  - keep the existing tablet clearance checks.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs.
- Harris: iPad Air emulator. Click around with the mouse, then tap. The
  effects stay put above the jump button, and the bottom buttons don't
  move.
- Say which branch you pushed to.
