# Effects-tray tooltip: drawn on top, opens to the right (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines. **Only these edits.**

---

Harris says Polish 12 is all good except one thing. Hovering a tray icon
(bottom-left) opens the tooltip **above** the icon, so it lands on the HUD
left column (the deal tile's timer and the UNLOCKED / ? row). It's drawn
**under** them, so the text is covered and unreadable.

There are two causes in `UI/EffectsTray.lua`:
- The tooltip lives in the tray's own ScreenGui, `UIKit.Screen("EffectsTray", 39)`,
  whose DisplayOrder is below the HUD's.
- `placeTooltip` puts it above the icon, where the left column is.

## Edits

1. **Own layer:**
   - Move the tooltip, its arrow and its arrow cover into a separate
     ScreenGui, `UIKit.Screen("EffectsTooltip", <HUD's DisplayOrder + 5>)`.
   - Read the HUD's DisplayOrder; don't hard-code it.
   - Keep it below every `UIKit.Modal`.
2. **Open to the RIGHT of the icon:**
   - The tooltip's left edge sits at the circle's right edge +
     `TOOLTIP_GAP`.
   - It's vertically centred on the circle.
   - The arrow points **left** at the circle's centre.
   - Clamp it inside the viewport.
   - Fallback: if it would run past the right edge, open above as
     today.
   - The area right of the tray is empty floor in Harris's screenshots.
3. **Selftest:**
   - grant a Luck Potion, fire `MouseEnter` on its cell;
   - check the tooltip's rect overlaps no HUD rect (left column, bottom
     row, weapon bar, deal tile) at 1366 × 768 and 844 × 390;
   - check its ScreenGui DisplayOrder is above the HUD's.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs.
- Harris: hover the 🍀 icon. The tooltip opens to its right, fully
  readable, with nothing covering it.
- Say which branch you pushed to.
