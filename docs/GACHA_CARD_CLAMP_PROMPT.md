# Gacha card: follow the pad, clamped to the screen (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 6 lines or fewer.

---

Harris tested `8b81e81` on Oct 15. The card's **look is right** (header,
3 × 2 tiles, chips, price, E / R / T circles). The **placement is wrong**:

- **Standing on the pad, camera close behind him** (the normal view): the
  card is completely above the top of the screen. Only the E / R / T
  circles peek out under the event bar.
- **Zoomed out:** the card floats far above the lab.

**Why:** the player stands **on** the pad, so "1 stud above the head" plus
a 270 px card that grows upward always ends up past the top of the screen
when the camera sits close behind the head. A world-anchored billboard
can't fix that. Pet Sim 99's egg works because you stand in **front** of
the egg and look at it; here you stand on top of it.

The "H · How it works" prompt in his screenshot is the **LOCK console's**
own help prompt (`TycoonService` line ~965). Leave it.

## The mechanic: screen-space card that follows the pad, clamped

Replace the BillboardGui with a **ScreenGui** card (`UIKit.Screen`) that
follows the pad on screen but can never leave the safe area.

- **Same content and pixel layout,** unchanged: a 300 × 204 card plus the
  E / R / T row, 0.8 on a phone, built once, the 0.85 → 1 pop, and the
  character-distance open / close (16 / 19 studs).
- **Anchor point (world):** the pad's top centre + 3 studs up. Each
  `RenderStepped` while open:
  - `camera:WorldToViewportPoint(anchor)`;
  - the card's **bottom-centre** (button row included) goes there, so the
    card sits right above the pad on screen;
  - if the point is behind the camera (Z < 0), use the last good position.
- **Clamp into the safe rect,** then place:
  - top ≥ `TopStack.GetBottom()` + 8 (below the event / announcement bar);
  - bottom ≤ the top of the weapon bar, or of the HUD's bottom row if
    there's no weapon bar, − 8;
  - left ≥ the HUD left column's right edge + 8 (read its live rects, the
    same ones `/selftest` checks), and right ≤ viewport − 8;
  - all in logical px, with the mobile scale and the GUI inset handled the
    same way the card-placement code does.
- **Smoothing:** lerp to the clamped target at `1 - 0.001^dt`, so it glides
  and doesn't jitter when the camera rotates. Snap on open.
- **When the clamp has to squeeze** (the safe rect is shorter than the
  card, as on small phones), scale the whole card down to fit, minimum
  0.7, about its bottom-centre. That's the only time it shrinks.
- `DisplayOrder` is above the HUD but **below** every `UIKit.Modal` and the
  result cards, so the reveal card and the (i) panel cover it. Hide it
  (with the pop) while any modal or big card is open, and bring it back
  after.
- `ResetOnSpawn = false`. Hidden during a ragdoll or while Carrying.

## Check

- `luau-lsp analyze` shows no new errors.
- **`/selftest gacha`:** stand the character on the pad and set the
  camera to each of these in turn:
  1. close behind (6 studs);
  2. default (12.5);
  3. max zoom-out;
  4. top-down;
  5. looking away from the pad.

  At each one, at 1366 × 768 and 844 × 390, the card plus button row is
  fully inside the safe rect and overlaps no HUD rect (left column,
  weapon bar, bottom row, TopStack). Keep the existing content, odds and
  keys checks, and remove the billboard-specific ones.
- Give Harris this list:
  1. Stand on the pad with the camera close behind you: the whole card
     and E / R / T are visible, just above you.
  2. Rotate and zoom: it follows the pad and never leaves the screen or
     covers the HUD.
  3. Pull: the reveal card covers it, and it comes back after.
- Update `docs/systems/items-and-fusion.md` and UI_TEST.
- Say which branch you pushed to.
