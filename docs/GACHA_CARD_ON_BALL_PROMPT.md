# Gacha card: sit ON the ball, PS99-style (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines. **Make exactly these edits. Don't touch the card's look.**

---

Harris likes the card UI from `4d75253`. Only the height is wrong. The
card's bottom (the E / R / T row) sits 5.8 studs above the pad top, over
the ball, so the card floats high and its top hides under the event bar.

He wants it **on the ball**, like Pet Sim 99, where the card and buttons
sit **in front of the egg** and cover it: the buttons' bottom is at the
egg's base, and the card rises from there.

## Edits

1. **`PlotLayout.Gacha.AnchorUpStuds`:** change it to the **ball's
   bottom**:

   ```lua
   -- The card's bottom edge (the E / R / T row) at the capsule ball's base, so the card covers the ball like PS99's egg card.
   AnchorUpStuds = (PlotLayout.Station.CapsuleY - PlotLayout.Station.CapsuleDiameter / 2) - PlotLayout.Station.PadTopY, -- 2.2
   ```

2. **Draw it in front of the ball.** With `AlwaysOnTop = false`, the 3D ball
   would cut through the card. In `GachaBoardController.buildCard`:
   - replace `billboard.StudsOffset = Vector3.zero` with
     `billboard.StudsOffset = Vector3.new(0, 0, 2) -- camera-relative +Z = toward the camera: in front of the ball (radius 1.3)`;
   - keep `StudsOffsetWorldSpace = Vector3.zero`;
   - update the header comment that says StudsOffset stays zero.
3. **While the card is open,** also set `LocalTransparencyModifier = 1` on
   every BasePart of the station's capsule hologram (`CapsuleTop`,
   `CapsuleBottom`, `CapsuleBand`). Set it back to 0 on close. The card
   replaces the ball, as PS99's card hides the egg, and nothing pokes out
   around its edges.
4. **`/selftest gacha`:** replace check (3), "card bottom above
   `CapsuleTop`", with these two:
   - "card covers the ball": at the approach position, the capsule's
     projected centre is inside the card's on-screen rect (card body plus
     button row);
   - "ball hidden while open, shown after close": read the capsule parts'
     `LocalTransparencyModifier`.

   Keep the flat-distance-under-0.1 and "centred on the pad" checks.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest gacha` has no FAILs.
- Harris: walk up to the pad. The card pops up **right on the ball**, with
  the buttons where the ball's base is and the card above them, and the
  whole card below the event bar at the default camera.
- Say which branch you pushed to.
