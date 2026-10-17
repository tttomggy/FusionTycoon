# Polish 11: every bundle shows its contents, effects tray bottom-left, premium shop pass (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 8 lines. Run `luau-lsp analyze` before pushing.

---

Harris's feedback on `fd52183`:

1. **Starter Pack:** the shop's Featured banner still only says "Worth 227
   if bought one by one". A kid can't tell what's in it. Polish 10 changed
   only the side card (`ShopPanel.featuredDetail` still returns that
   line).
2. **Effects tray:** move it to the **bottom-left**, exactly where Bubble
   Gum Simulator puts its potion icons with timers, under the HUD's left
   column. Not bottom-right.
3. **Premium quality:** "make everything look like it's 1 billion dollar
   quality". This pass covers the shop. The other screens come next, from
   Harris's screenshots.

## 1. Every bundle shows what's inside, everywhere

**Rule:** any item with `Parts` (Starter Pack, every deal, any future
bundle) is drawn with `DealParts` tiles plus the ✓ "YOU GET" list from the
parts' `Plain` text, wherever it appears:
- the shop Deal banner;
- the shop **Featured** banner;
- its grid tile, if it has one;
- the side cards.

**Featured banner for the Starter Pack:**

```
┌──────────────────────────────────────────────────────────────────────┐
│ ┌───────────┐  🎁 ONE TIME ONLY                                      │
│ │  STARTER  │  Starter Pack                                 ┌──────┐ │
│ │  [art]    │  [tile][tile][tile]   YOU GET:                │  99  │ │
│ └───────────┘  Pink Lab  1 h  Cash  ✓ A glowing pink lab    └──────┘ │
│                                     ✓ Double cash for 1 hour         │
│                                     ✓ A pile of cash (+$N)           │
│                Worth 227 if bought separately   SAVE 56%             │
└──────────────────────────────────────────────────────────────────────┘
```

- **Pocket Cash's line shows the actual amount** it grants for this player
  right now (the same formula the grant uses).
- Delete the "if bought one by one" string. Use "Worth N if bought
  separately", from the live `ShopPrices` sum, everywhere.
- **Selftest:** "every item with `Parts`, in every place it is drawn, shows
  one tile per distinct part and one YOU GET line per part". Walk the shop
  tree and the side cards, read from the instance tree.

## 2. Effects tray: bottom-left, Bubble Gum Sim style

- **Anchor:** bottom-left, 16 px from the left edge. Its bottom is level
  with the bottom of the HUD's bottom row.
  - Icons fill left to right, 4 per row; more rows stack **upward**.
  - It must stay clear of the left column (LOCK / ? row) and of the bottom
    row's left edge. If it would touch either, the icons drop to 48 px. If
    it still touches, it shows 3 per row.
- **Look:** the same circles as now, closer to BGSI's:
  - a 64 px icon (art or glyph);
  - a 2 px white stroke and a soft drop shadow;
  - the **timer under the icon**, 15 px, white with a 2 px ink stroke,
    e.g. `14:55`;
  - the `×N` count badge in the top-right corner of the circle.
- **Phone:** the same corner. If the left column runs that low, the tray
  sits to the right of the left column, still bottom-aligned.
- Tooltip, pop-in and no flashing all stay as they are.
- **Selftest:** grant a Luck Potion, Speed Boots and 2 Safe Fusion. At
  1366 × 768 and 844 × 390:
  - the tray is in the bottom-left quarter of the screen;
  - no HUD rect overlaps it;
  - its timers read the live seconds.

## 3. Premium shop pass

The shop should feel like a top-chart Roblox shop (Pet Sim 99, Bubble Gum
Simulator Infinity): rich, glossy, layered. Apply these rules to every shop
card and tile. All colours go in as new `UITheme` tokens.

- **Depth:**
  - every card gets a 2-stop vertical gradient (lighter top);
  - a 1 px light inner stroke along the top edge (a highlight line);
  - a darker 3 px outer stroke;
  - a soft 6 px drop shadow under it.
  - No flat fills anywhere.
- **Art first:** every item has a big art box on the left: 120 px on
  banners, 96 px on tiles.
  - Inside it: the live product icon, with the emoji as fallback, drawn
    over a radial glow in the card's colour.
  - Slowly turning rays behind the art, on Featured and Deal **only**.
- **Type hierarchy, exactly three sizes per card:**
  - the name: 30 px Display, white, 3 px ink stroke;
  - the YOU GET lines and the plain text: 16 px BodyHeavy, white, 1.5 px
    ink stroke;
  - small labels (ONE TIME ONLY, timers): 13 px, pill-shaped.
  - Nothing smaller than 13 px. Today's deal sub-lines are about 11 px and
    unreadable.
- **Buy button:**
  - the green `UIKit` button, 160 × 64, with the live price at 28 px
    Display and the Robux glyph;
  - a 0.12 s press-in;
  - a gentle shine sweep every 5 s **only on the Featured card**.
- **Owned / bought:** the button turns grey "OWNED ✓", and the card dims to
  70%. A one-time item that's been bought shows that and stays in place, so
  the layout doesn't jump.
- **Section headers:** the coloured icon chip plus the name, a 2 px rule,
  and 24 px of space above each section.
- **Scroll:** a thin rounded scrollbar in UITheme, with 12 px padding all
  round.
- **Never-list unchanged:** live prices only, real timers only, no urgency
  words, no flashing. `PolicyRestricted` items stay hidden from restricted
  players.

## Check

- `luau-lsp analyze` shows no new errors.
- `/selftest` has no FAILs, and every text in the shop has `TextSize ≥ 13`
  (read from the tree).
- Harris:
  1. Shop → Featured: the Starter Pack shows its 3 items and a YOU GET
     list, with Pocket Cash's real amount.
  2. Grant a Luck Potion: its icon and timer appear in the bottom-left
     corner, like Bubble Gum Sim.
  3. The whole shop looks glossy and layered, and nothing is tiny.
- Update `docs/systems/monetization.md` and UI_TEST.
- Say which branch you pushed to.
