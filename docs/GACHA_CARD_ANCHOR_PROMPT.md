# Gacha card: the real position bug, as exact code (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines. **Make only these edits. Change nothing else in the card.**

---

## The bug

The card is adorned to the gacha `Pad`. That pad is a **cylinder turned
90° about Z** (`StationKit` line ~165):
- `Size = (PadHeight 1, PadDiameter 8, PadDiameter 8)`;
- `CFrame = padCenter * CFrame.Angles(0, 0, math.rad(90))`.

`BillboardGui.StudsOffsetWorldSpace` is applied **in the adornee's own
axes**. The pad's local +Y points **sideways**, not up. So
`StudsOffsetWorldSpace = (0, Pad.Size.Y / 2 + 5.8, 0)` = (0, 9.8, 0)
pushes the card **9.8 studs sideways** off the pad, on the ground plane.
That's why it has been beside the pad, below it, and in front of it, and
never on top of the ball. (`Pad.Size.Y` is also the diameter 8, not the
height.)

## The fix: adorn to an Attachment at an exact world point

In `GachaBoardController.lua`:

1. Replace `setUpStuds` with:

```lua
-- The card's anchor: a world point straight above the pad's centre, `up`
-- studs over the pad's top. An Attachment (not the rotated cylinder) so no
-- offset is ever applied in the pad's own axes.
local function setUpStuds(view: CardView, up: number)
	view.UpStuds = up
	local pad = view.Pad
	local topY = pad.Position.Y + pad.ExtentsSize.Y / 2 -- world-axis top, whatever the pad's rotation
	view.Anchor.WorldCFrame = CFrame.new(pad.Position.X, topY + up, pad.Position.Z)
end
```

2. In `buildCard(pad)`, **before** the billboard, add:

```lua
	local anchor = Instance.new("Attachment")
	anchor.Name = "GachaCardAnchor"
	anchor.Parent = pad
```

   Then set `billboard.Adornee = anchor` instead of `pad`. Set
   `billboard.StudsOffset = Vector3.zero` and
   `billboard.StudsOffsetWorldSpace = Vector3.zero`, and never write either
   again anywhere in the file. Keep `SizeOffset = Vector2.new(0, 0.5)`.

3. Add `Anchor: Attachment` to the `CardView` type, and set
   `Anchor = anchor` where the view table is built. Destroy the anchor
   when the card is destroyed.

4. `PlotLayout.Gacha.AnchorUpStuds` stays at 5.8 (the ball's top + 0.7
   from the pad top).

## Selftest (`/selftest gacha`), replacing the old position checks

At the approach position (8 studs in front of the pad, default camera)
**and** with the camera straight above (top-down), at 1366 × 768:

- Project `GachaCardAnchor.WorldPosition` and the pad's centre. The flat
  (XZ) distance between the anchor's world position and the pad's centre
  must be **< 0.1 studs**. That's the bug check, and it fails today with
  about 9.8.
- The card's bottom edge on screen (`AbsolutePosition.Y +
  AbsoluteSize.Y` of the button row) is **above** the `CapsuleTop` ball's
  projected top (a smaller Y), at the approach position.
- The card's horizontal centre on screen is within 30 px of the pad's
  projected centre X.

Run the first check before the fix and quote the number.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest gacha` has no FAILs.
- Harris: walk up to the pad. The card pops up **directly above the
  yellow ball**, centred on it, from any side and any camera angle.
- Say which branch you pushed to.
