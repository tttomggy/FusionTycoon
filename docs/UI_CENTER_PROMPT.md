# Fusion Tycoon: centre every card (build prompt for Claude Code)

`git pull` on `world-redesign` first. Commit per step, push, and open a PR
→ `main`. Don't merge.

---

Read CLAUDE.md and follow it. Harris tested on a 1920×1080 full screen
(Oct 6). **Every card sits too high.** SHOP, ITEMS, GIFTS, Daily, Index,
Upgrades, Settings and the result cards all hug the top bar, with a big
empty gap above the bottom buttons. He wants them **in the middle of the
screen**.

Shop 3 made cards top-anchored at `UIKit.GetCardTop()`. That looked right
in a small Studio window but is wrong on a real full screen.

## What's already done (verify it, don't redo it)

Commit `7317fe4` adds `UIKit.GetCardY(visualHeight)`. It places a card's top
at `GetCardTop() + max(0, (band - visualHeight) / 2)`, where
`band = viewport.Y - GetCardTop() - GetCardBottom()`. It is used in
`UIKit.Modal`'s `placeRoot` and in `UIKit.FitHeight`.

- `visualHeight` is the height after `UISizeConstraint` and the fit scale.
- A card that fills the band (phones) still starts at `GetCardTop()`.

It was tested only in a 615 px tall Studio window and **is not published**.
Check the math, and check that `UIScale` scales from the anchor point, so
that a shrunk card is still centred.

## Do

1. **Find every card the helper doesn't reach.** Grep for cards that
   position themselves: `AnchorPoint` (0.5, 0.5) / (0.5, 0) with a
   hard-coded Y, `GetCardTop`, or `TOP_BAR_HEIGHT`. Check at least these:
   - `PurchaseCelebration`
   - the welcome-back card
   - the EVENT-ONLY reveal
   - `EventInfoCard`
   - `ItemPickerUI`
   - `HowToHeistPanel`
   - the AdminPanel

   Route each one through `GetCardY`, `FitHeight` or `Modal`. Side cards
   (the offer, Starter and deal cards) stay where they are.
2. **The whole card is centred, not the frame.** A Modal's root is sized
   to the band and capped by its `UISizeConstraint`. Centre what you
   actually see: the panel, including its shadow.
3. **`/selftest`: new case "cards centred".** Open every modal and
   centred card, with the viewport forced or simulated at **1920×1080**,
   **1366×768** and **844×390 (phone)**. Pass when, wherever the card fits
   inside the band:
   - its visible centre Y is within 2 px of the band's centre;
   - its top is ≥ `GetCardTop()`;
   - its bottom is ≤ viewport − `GetCardBottom()`.

   A card taller than the band must start at `GetCardTop()` and be shrunk
   to fit. Use the panel's `AbsolutePosition` / `AbsoluteSize`, not its
   `Position` props. If the viewport can't be forced, compute the expected
   placement from `GetCardY` with those sizes and test the function.
4. **Leave the phone layout alone.** On a phone, the cards and the HUD's left
   column look the same as they do today.
5. **CLAUDE.md** already describes `GetCardY` under Card placement. Fix it
   if anything you changed makes it wrong.

## Also in this pull (verify only)

`bb5b69f` changes two things in the trailer:
- the Gacha Pad puller is the generic yellow/blue noob (`makeActor("Owner")`),
  never the player's own avatar;
- the mouse cursor is hidden during `/trailer` and restored after.

Run `/trailer pull` once and confirm both.

## Check

- `/selftest` passes three runs in a row.
- `luau-lsp analyze` reports no new errors.
- Add a UI_TEST line: "1920×1080 full screen: SHOP opens in the middle,
  equal space above and below".

**Report** the card list with the before and after top Y at 1920×1080,
plus anything you couldn't centre and why. Then tell Harris to
**publish (Alt+P)** and join a **new** server, since old servers keep the
old UI.
