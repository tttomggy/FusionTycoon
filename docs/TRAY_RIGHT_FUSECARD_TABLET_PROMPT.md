# Desktop tray bottom-RIGHT, Fuse All card placement, tablets, tutorial weather overlap, FUSE NOW pointer (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 7 lines, one per group: FIXED or WHY-NOT.

---

Harris tested 607de1e + 5737cb2 in Studio, on desktop and on the iPhone XR
emulator. The phone layout looks good. Everything below is still broken.

## 1. Desktop effects tray: bottom-RIGHT, not bottom-left

- Bottom-left is taken by the desktop left column (cash card, quest row,
  deal tile, LOCK row, ?). Every desktop plan FAILs (touches CashCard,
  QuestTracker, DealBadge, LockRow), and in Studio at 1920 × 1080 the tray
  is **hidden behind the deal tile**. Stop fighting the left column.
- **Desktop:** one row in the **bottom-right corner**, right of the ⚙
  button. Keep 16 px from the right and bottom edges, and end ≥ 12 px right
  of `BottomRow`'s right edge. On desktop the right side of the screen is
  empty.
  - If it doesn't fit, shrink to 48 px.
  - If it still doesn't fit, sit **directly above** the bottom row's
    right end, right-aligned to the edge.
- Tooltips (desktop): above, then above-left, then left.
- **Phone:** unchanged (top-right row).
- **Selftest:** stop planning the *desktop* layout at 844 × 390 / 896 ×
  414. Under 500 px tall the game uses the phone layout, so those cases
  can't happen. Desktop plans run at 1251 × 666, 1366 × 768 and 1920 ×
  1080, with 3 and 5 effects.

## 2. Tablets (iPad): desktop layout + a jump button

Harris asked whether iPads will lay out right. Today they won't:
- An iPad landscape is ≥ 500 px tall, so it gets the **desktop** layout.
- But it's **touch**, so Roblox draws the **jump button** bottom-right,
  exactly where group 1 puts the tray.

Fix:
- Whenever `UserInputService.TouchEnabled` (and the jump button is
  showing), the jump rect (`JumpRectFor`, at the tablet's size) is an
  obstacle for **every** HUD placement that uses the bottom-right: the
  tray, its tooltips, and anything else there.
- If the tray can't sit bottom-right on a tablet, it sits above the jump
  button, right-aligned.
- Check the rest of the desktop HUD on a tablet: the bottom row and weapon
  bar must clear the jump button, and tap targets must be ≥ 44 px.
- **Selftest:** add tablet cases to the tray plan, the bottom row and the
  weapon bar checks: 1024 × 768, 1180 × 820 and 1366 × 1024, desktop layout
  **with** the jump rect.
- Answer in one line: can the iPad layout be checked in Studio's device
  emulator (iPad), and which preset?

## 3. The Fuse All card ("40 fusions") sits too low and runs off the bottom

- On desktop, the OK button is under the bottom row. On the phone, the
  card's bottom half is off screen.
- Output shows `UIKit.SettleCard: …Results.FuseAllSummary did not settle in
  30 frames`.
- Cause: `ResultController.showFuseAllCard` places the panel at `Position
  = (0.5, 0.5)`, `AnchorPoint (0.5, 0.5)`, with `AutomaticSize.Y`. It's
  centred on the **screen**, not in the card band, and nothing caps its
  height.
- Fix:
  - Place it like every other centred result card: in the band from
    `GetCardTop()` to `GetCardBottom()`, centred, with `UIKit.FitHeight`
    (shrink to fit, never past the band).
  - If the tier list is long (6+ lines), use two columns, as it already
    does, and cap the rows.
- Check every other card in `ResultController` (and any card built with
  `AnchorPoint (0.5, 0.5)` at screen centre) for the same mistake.
- **Selftest:**
  - add `FuseAllSummary` to "cards centred" (desktop and phone, live and
    at the 3 explicit sizes), with an 8-tier result (the worst case);
  - its OK button must be fully inside the band.

## 4. Tutorial: the "Lab weather!" banner covers the event card

- In the tutorial's **events** step on the phone, the objective banner
  ("Lab weather! 9 / 11 · Every 15 min. Tap it to see what to do") is drawn
  **over** the EventInfoCard. It hides the card's title and its first
  lines.
- **Rule:** a modal / centred card and the tutorial objective bar never
  overlap.
  - While a card is up, the card's top must be ≥ the objective bar's bottom
    + 8 px (the band starts below TopStack's objective slot when it
    shows).
  - Or hide the bar while the card is open, and bring it back after.
  - Pick one, apply it everywhere, and say which.
- **Selftest:** in the tutorial events step, with the event card open, the
  objective bar and the card don't overlap (phone and desktop).

## 5. After the tutorial: "FUSE NOW" points at the machine "for no reason"

- Harris finished the tutorial, and a big **FUSE NOW** pill and pointer
  appeared over the Fusion Machine.
- It comes from `EventController.refreshGuidance` during **Night /
  VoidMoon**. The player doesn't see why, and it shows even with nothing to
  fuse.
- Fix:
  - Show the Night / VoidMoon pointer only when the player has something
    fusable: ≥ 2 unmutated items of one tier, not carried
    (`FusionController.GetAutoFill` or the same rule).
  - Say why: "🌙 NIGHT: FUSIONS MUTATE MORE · FUSE NOW".
  - Same idea for Rainbow Storm's "PULL NOW / THEN FUSE": only point at
    the pad if they can afford a pull.
  - No event pointer until 30 s after `TutorialDone`, so the end of the
    tutorial isn't followed by a new arrow.
- **Selftest:** Night with nothing fusable shows no pointer; Night with a
  fusable pair shows it with the reason text.

## 6. Leave alone

- The "selftest window 801 x 413" FAIL (environment).
- The `EventInfoCard did not settle` warning, unless group 4 fixes it.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs, apart
  from the window line in a small view.
- Update `docs/UI_TEST.md` (tray per layout, tablets, Fuse All card, the
  tutorial bar vs card rule) and `docs/systems/events.md` (pointer rule).
- Harris:
  - **Desktop:** effects sit bottom-right beside ⚙, and Fuse All's OK is
    fully visible.
  - **iPhone XR:** the Fuse All card fits.
  - **iPad emulator:** the tray clears the jump button.
  - `/tutorial reset`: the weather step shows the card fully, and after the
    tutorial there's no FUSE NOW unless you have a pair.
- Say which branch you pushed to.
