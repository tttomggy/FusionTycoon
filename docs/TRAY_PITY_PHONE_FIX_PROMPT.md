# Desktop tray back bottom-left, harder Secret meter, phone left column overflow (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 5 lines. **Only these edits.**

---

Harris checked d62a769 (tray), 0c9359c (pity) and 48748ef (compact phone
HUD) in Studio.

## 1. Desktop effects tray: back to the bottom-left corner

- On desktop the top-right row ended up floating over the lab, beside the
  pedestals, mid-screen right. Harris liked the old desktop spot: a row in
  the **bottom-left corner**, left of UPGRADES.
- **Desktop layout:** one row in the bottom-left corner, 16 px from the
  left and bottom edges, timers under the circles. It must end at least
  12 px left of `BottomRow`'s left edge.
  - If it doesn't fit (the 1251 × 666 case that failed before), shrink the
    circles (the FITS sizes, ≥ 44 px).
  - If it still doesn't fit, put the row **directly above** the bottom-left
    corner (above the bottom row's top edge), still clear of the left
    column's rects.
- **Phone layout:** keep the top-right row from d62a769 exactly as it is.
- Tooltips: desktop opens **above** first (then above-right, right), phone
  keeps below-first.
- Selftest: the plan checks become per layout:
  - desktop = bottom-left, clear of BottomRow / the left column / the
    weapon bar;
  - phone = top-right, as now.
  - Same 4 sizes, 3 and 5 effects.

## 2. Secret meter is too easy: `SecretPityFull` 4 → 12

- With full = 4, **one** failed fusion of 4+ Mythics fills the meter, so
  the next is a sure Secret. Harris: "6 orbs only give 15% and 4 orbs get
  you a Secret pity". Secrets must stay the long chase.
- Set `FusionConfig.SecretPityFull = 12`. Keep the charge = input count, so
  a 6-orb fail = half the meter. It takes about two failed big fusions (or
  six failed pairs) to fill.
- Your sweep already has 12 at a first Secret of ~7:22 (`--fuse=2`). That
  is accepted: a later Secret is the point.
- Update the FusionConfig comment, the TycoonConfig header (first / second
  Secret at 12, and why: the planner and Harris chose a harder chase over
  the 3–5 h target), the sim default, and the selftest's expectations.
- Saves above 12 can't exist (the old cap was 4). The clamp stays.

## 3. Phone: the left column runs off the bottom of the screen

On the iPhone XR emulator the left column (cash panel → icon grid → LOCK /
? → deal tile → NEXT GOAL card → quest tracker) runs past the bottom edge.
"Fuse 5 times · 0/5" is cut off.

- **Phone layout:** the NEXT GOAL card and the quest tracker don't fit, so
  don't stack them under everything else:
  - **NEXT GOAL:** put it as a compact one-line pill (goal text + reward)
    **under the cash panel**, or hide it on phone if it can't fit.
    Tutorial-time goals must still show (the tutorial uses the objective
    bar anyway).
  - **Quest tracker:** hide it on phone. The QUESTS card's red ! badge and
    the panel cover it.
- Selftest: "hud left column (phone)" must check that **every** element's
  bottom is ≤ the viewport bottom − 8 px at 844 × 390 and 896 × 414, not
  only that they don't overlap. Keep the ≤ 20% coverage check.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs.
- Update `docs/UI_TEST.md` (tray per layout, phone left column) and
  `docs/systems/items-and-fusion.md` (meter = 12).
- Harris:
  - **Desktop:** the tray sits in the bottom-left corner beside UPGRADES.
  - **iPhone XR:** the tray stays top right, and nothing on the left is cut
    off.
  - `/rebirths 1` + `/give` Mythics: a failed 6-orb fusion shows "SECRET
    METER 6 / 12".
- Say which branch you pushed to.
