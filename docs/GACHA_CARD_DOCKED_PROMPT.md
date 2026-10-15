# Gacha card: docked in one spot, no following (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 5 lines or fewer.

---

Harris tested the screen-space card on Oct 15. "Better, but weird": it
slides around the screen as the camera turns, because it follows the pad's
projected point. He wants it to **pop up in one fixed place when you walk
close, and stay put**.

## Change

- **Delete the per-frame follow:** the `WorldToViewportPoint`, the
  smoothing and the follow clamp. The card no longer tracks the pad at all.
- **Dock it** at a fixed screen spot: the **right side, vertically
  centred** in the safe band.
  - Anchor `(1, 0.5)`, 24 px from the right edge.
  - The top stays ≥ `TopStack.GetBottom()` + 8, and the bottom ≤ the
    weapon bar's top − 8.
  - Re-place it only on a viewport change or `LayoutChanged`, never per
    frame.
  - On a phone: the same spot at 0.8, still scaled down (minimum 0.7) if
    the band is shorter than the card.
  - It must not overlap the HUD left column, the bottom row, the weapon
    bar or TopStack. The right side is empty in Harris's clips.
- **Pop:** when your character comes within 16 studs of your pad, the card
  slides in from the right (24 px) and scales 0.9 → 1 over 0.15 s,
  Quad-Out. Past 19 studs it slides back out and hides. No CanvasGroup.
  The content is built once, as now.
- **Everything else stays:**
  - the content and layout;
  - the E / R / T row under the card and their key bindings, only while
    it's open;
  - hidden while a modal or the reveal card is open, and while
    ragdolled or Carrying.

## Check

- `luau-lsp analyze` shows no new errors.
- **`/selftest gacha`:** with the character on the pad, rotate the camera
  through 4 yaw angles and 2 zoom levels.
  - The card's `AbsolutePosition` is identical (±1 px) every time.
  - It's fully inside the safe band and overlaps no HUD rect, at
    1366 × 768 and 844 × 390.
  - Remove the follow / clamp checks and keep the rest.
- Give Harris this list:
  1. Walk to the pad: the card slides in on the right.
  2. Turn the camera: it doesn't move.
  3. Walk away: it slides out.
- Update `docs/systems/items-and-fusion.md` and UI_TEST.
- Say which branch you pushed to.
