# Gacha card height fix: exact edits (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 4 lines or fewer. **Make exactly these edits, nothing else.**

---

In `84f67fb` the card sits **on the capsule ball**, covering it and the
pad, instead of above it. There are two causes, both in our code:

1. **`AnchorUpStuds = 3` is too low.** Pad top is y 1. The capsule's
   centre is `Station.CapsuleY` 4.5, its diameter is 2.6 and it bobs 0.3,
   so the ball's top reaches y 6.1. Pad top + 3 = y 4, which is the
   **middle of the ball**.
2. **The top-of-screen guard (`FitAnchor`) lowers it further,** to the
   0.5 floor. It demands the whole 276 px card sit below TopStack, which
   is almost never true from a normal camera, so it always fires.

## Edits

1. **`PlotLayout.Gacha`:**
   - Replace `AnchorUpStuds = 3` with a value computed from the Station
     numbers, so it can't drift again:
     `AnchorUpStuds = (Station.CapsuleY + Station.CapsuleDiameter / 2 + Station.CapsuleBob + 0.7) - Station.PadTopY`,
     which is 5.8.
     `PlotLayout.Gacha` is defined before `PlotLayout.Station`, so either
     move the `Gacha` table below `Station`, or compute it after both
     exist.
   - Delete `AnchorFloorStuds`, `ZoomRecheckStuds` and `SafeMargin`.
2. **`GachaBoardController`:**
   - Delete `FitAnchor` and everything that calls it (open, layout change,
     the zoom re-check in the per-frame step) and `ZoomAt` / `zoomDistance`.
   - On build, call `setUpStuds(view, G.AnchorUpStuds)` once.
   - The anchor never changes after that.
3. **`/selftest gacha`:**
   - Delete the guard checks.
   - Add "card bottom is above the capsule": project the billboard's
     bottom-centre (the anchor) and the capsule's top (`CapsuleTop` part,
     top surface) at the approach position. The anchor is **above** the
     capsule top on screen (smaller Y).
   - Add "`StudsOffsetWorldSpace.Y` equals pad half-height + 5.8 and never
     changes while the camera turns or zooms".

Everything else stays: the content, the pop, the keys, and hiding the
label and the VIP chip.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest gacha` has no FAILs.
- Harris: walk up to the pad. The card pops up **above the yellow ball**
  with the ball fully visible under it, and it stays there at any camera
  angle or zoom.
- Say which branch you pushed to.
