# Compact phone HUD, Bubble Gum Simulator style (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 6 lines. **Run this AFTER `EFFECTS_TRAY_TOP_RIGHT_PROMPT` and
`GACHA_PRICE_CAP_PROMPT` are done.**

---

## Why

On a phone (iPhone XR landscape, 896 × 414) our HUD eats the screen.
- The left side is a stack of big text pills: the cash panel, then 🛒 SHOP
  132 × 56 and 🎁 GIFTS 124 × 56, then QUESTS with its power-up row, then
  the deal tile, then LOCK.
- The bottom row is five wide pills.
- The player and the lab are squeezed into the middle.

Harris compared it with **Bubble Gum Simulator Infinity** on the same phone.
Its HUD covers maybe half as much, and still has more buttons:
- **Icon buttons** (a picture with a small word under it, about 56 px), in a
  tight **grid**, instead of wide text pills.
- **Currency bars** are slim: icon + number, one line each.
- Buttons are split by role: **left** = utility (rewards, quests, settings),
  **right** = store / collection (Shop, Items, Index) in a column.
- Effects are small icons with the timer right under each (ours is the
  top-right row from the previous prompt).

**Scope: phone layout only** (`UIKit` phone layout, < 500 px tall). Desktop
is unchanged.

## 1. Left side: a utility grid

- SHOP, GIFTS and QUESTS become **icon buttons**: the existing glyph (🛒 /
  🎁 / 📜) at about 30 px with the word under it at 13 px, on a square 56 ×
  56 card in each button's current colour.
  - Lay them out in a grid with the power-up buttons (the purple 12 / 1
    ones), up to 3 per row, 6 px gaps.
  - Keep every badge (GIFTS count, QUESTS red !, SALE tag) on the card's
    corner.
- The cash panel gets slimmer:
  - one line for cash (icon + number) and one small line for $/s +
    multiplier pills;
  - target about 60% of today's height;
  - the cash number stays the largest text on the HUD.
- The deal tile and LOCK chip shrink to the same 56 px card size and join
  the grid's last row if they fit. Otherwise they go under it.

## 2. Bottom row: icon buttons

- UPGRADES, ITEMS, INDEX, REBIRTH and ⚙ become 56 px icon buttons (glyph +
  13 px word).
- REBIRTH keeps its progress fill along the card's bottom edge.
- Keep them centred under the weapon bar, never under the jump button.
- If a glyph doesn't exist yet, use an emoji (⬆️ upgrades, 🎒 items, 📖
  index, 🔁 rebirth). Don't use Roblox catalog images.

## 3. Rules that still hold (from CLAUDE.md)

- Colours from `UITheme`.
- Tap targets ≥ 44 px, text ≥ 13 px.
- White text with an ink stroke on warm fills.
- Top-left 170 × 60 px stays clear.
- TopStack owns top centre.
- The weapon bar and the jump button stay unblocked.
- Every button still works and opens the same panel.
- Wiggle / bounce animations stay (smaller amplitude is fine).
- The tutorial's progressive HUD (`HudGate`) must still reveal the same
  buttons in the same steps.

## 4. Selftest

- Add **phone HUD coverage**: the total area of all HUD rects (the union,
  not the sum) is **≤ 20%** of the viewport at 844 × 390 and 896 × 414.
  - Print the % so we can see the before / after.
  - Also measure today's layout first and put that number in your reply.
- Existing checks stay:
  - left column overlap;
  - no overlap with the weapon bar, the jump button and the tray row;
  - tap targets, text sizes;
  - HudGate steps;
  - the tutorial hand pointing at the right buttons (update its targets if
    they moved).
- Desktop checks must be unchanged and still pass.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs.
- Update `docs/UI_TEST.md` (phone HUD) and `docs/systems/tutorial.md` if any
  hand target moved.
- Harris: iPhone XR emulator, with `/weapons all`, a few power-ups, and a
  deal running. The left side is a neat icon grid, the bottom is a row of
  icon buttons, and you can see your lab.
- Say which branch you pushed to.
