# Selftest triage 6: the title-layout parent lock, the gacha card at phone scale, small tablet jumps (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 6 lines, one per group: FIXED or WHY-NOT.

---

Harris ran `/selftest` on **af6f586**. The game view was 749 × 388, so it
used the phone layout. The HUD builds again, but these FAIL:

## 1. `The Parent property of UIListLayout is locked, current parent: NULL, new parent TitleRow` (dozens of times; it also FAILs "no client errors")

```
Script '...UI.UIKit', Line 1926 - function applyChrome
Script '...UI.UIKit', Line 1816 - function placeRoot
```

- "Parent locked" means that `titleLayout` was **destroyed**, and
  something keeps calling that Modal's `placeRoot` → `applyChrome`
  afterwards.
- Prime suspect: your `UIKit.SelfTestModal` throwaway, which is destroyed
  but leaves a `placeRoot` connected (`LayoutChanged`, the camera
  `ViewportSize` hook at ~1474, the dim probe or a TopStack `OnChanged`).
  It could also be any other Modal that's destroyed and rebuilt.
- Fix it properly:
  - **every Modal disconnects all its connections on
    `gui.Destroying`**;
  - `placeRoot` / `applyChrome` return early if the gui has no parent or is
    destroyed;
  - `SelfTestModal` must leave nothing connected.
- Selftest: after `SelfTestModal`, trigger a layout change (toggle
  phone ↔ desktop through the explicit path) and check for no client error.

## 2. `probe GachaOnPad errored on the client: SelfTestController:3098: attempt to iterate over a nil value`

- `for _, tile in card.Tiles` runs while `card.Tiles` is nil: the card
  isn't built yet, or the field is named differently since the phone-scale
  change.
- Guard it, and report "card not built" as a FAIL line with the reason.

## 3. The gacha card at phone scale (2 FAILs + Harris's readability concern)

- "the (i) is off the top edge or its hit area is **31 px**", for both luck
  runs.
- At the 0.56 phone scale, the (i) hit area falls under 44 px. And as you
  said yourself, the **mutation line drops to ~7 px**, which is unreadable.
- **Don't scale the whole card evenly on a phone.** Use a phone variant of
  the card:
  - drop the coloured mutation line (it's in the (i) panel already);
  - make the % labels and the price bigger at the design size, so that after
    the scale they're ≥ 13 px;
  - give the (i) a ≥ 44 px hit area after the scale (like you did for
    E / R / T).
  - It must still fit the screen rules from `PHONE_LIVE_FIXES` group 2.
- Selftest:
  - at both phone sizes, every text on the card is ≥ 13 px after the
    scale;
  - the (i) hit area is ≥ 44 px;
  - the "PS99 face" check doesn't expect the mutation line on phone.

## 4. Tablet jump check still moves things by 2–3 px

- `#2 817.84, 69.72 → 816, 69` and `#5 569, 210.96 → 569, 214`.
- Name the rect in the Detail (tray / bottom row / weapon bar / which
  element), not `#2` / `#5`.
- The `#5` y change of 3 px means **something's vertical placement** still
  depends on the jump button's visibility. Find it and remove that
  dependency (same rule: touch = always reserved).

## 5. "skipped lines (desktop): line 1 over Goal, line 2 over Goal, line 3 over QuestTracker…"

- This passed before on a big window. Was it measured with the **phone**
  HUD rects (the new goal pill under the cash panel) against the desktop
  plan, because the live window was phone-sized?
- If it's a desktop-plan vs live-phone mix-up, make the check use the HUD
  rects of the layout it's planning. If the desktop goal card really
  overlaps the skipped lines, fix the placement.

## 6. Leave alone

The "selftest window 749 x 388" FAIL (the environment).

## Check

- `luau-lsp analyze` shows no new errors.
- Harris:
  - Play, and Output stays free of red errors while you open and close
    panels and switch the emulator between iPhone and desktop.
  - `/selftest` on a big window and on iPhone XR: paste the FAIL lines.
  - Look at the gacha card on iPhone XR: everything readable.
- Say which branch you pushed to.
