# Gacha card: restyle to match Pet Sim 99's egg card exactly (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 4 lines.

---

Harris sent a Pet Sim 99 screenshot (the Iceshard Egg card) and wants ours
to look like it. **This is a restyle only.** Don't touch:
- the anchor: the `GachaCardAnchor` Attachment from `09b4871`, the card's
  bottom on the anchor;
- the pop in at 16 studs and out at 19;
- the E / R / T bindings and remotes, auto pull, and the odds source;
- silhouettes and the (i) panel;
- hiding the label and VIP chip.

## What the PS99 card looks like (copy this)

```
 Iceshard Egg                               (i)    <- title sits ON the top-left edge,
┌─────────────────────────────────────────┐            half outside the card; (i) is a
│   🐱        ■■        🐱                 │            blue circle half outside top-right
│  28.2%     23.2%     18.2%              │         <- white card, rounded 18 px,
│                                         │            faint paw/dot pattern, NO tile
│   ■■        ■■        ■■                 │            backgrounds: just big icons
│  12.2%     6.2%      12%                │            with the % overlapping their
└──────────────────────────────🪙 450─────┘            bottom, in rarity colour
     (1)        (E)        (⟳)R                     <- price (coin + number) sits ON
    Hatch      Multi       Auto                        the bottom-right edge
                                                    <- round blue buttons under it,
                                                       the middle one bigger
```

## Our version, exact spec (design px; the phone 0.8 scale as now)

**Card body:** 300 × 196.
- **Fill:** add a `UITheme` token `CardPaper` (near-white, slightly cool)
  with a 3 px `CardPaperStroke` (light blue-grey). 18 px corners.
- **Pattern:** a faint dot or paw tile using one `ImageLabel`,
  `ScaleType = Tile`, transparency 0.92. If there's no asset, use a
  UIGradient with a soft diagonal instead. No dark violet panel, no gold
  rim, no header bar.

**Title:**
- "Gacha Pad" in `Fonts.Display`, 26 px, white with a 3 px ink stroke.
- Left-aligned at x 10, **centred on the card's top edge** (half above it).
- The luck pill, when luck > 1, sits just right of the title, small and
  green.

**(i):**
- A 34 px circle in UITheme blue, with a 3 px white stroke and a white
  "i".
- Its centre is on the card's top-right corner, inset 6 px.
- It opens the existing per-orb panel.

**Orb grid:** 3 × 2, **no tile backgrounds, no tier ribbons.**
- Each cell is 92 × 82, centred, with 4 px gaps.
- **The orb:** a 2D `UIKit.TierOrb` at 58 px, centred in the cell's top
  part.
- **Unfound tier:** a solid black orb silhouette, the same shape, no "?".
  That's how PS99 shows it.
- **The %:** 22 px `Fonts.Display`, bold.
  - Colour: the tier accent.
  - Stroke: a 3 px white outer stroke plus an ink stroke, readable on
    white the way PS99's is.
  - It overlaps the orb's bottom by about 10 px.
- **Secret cell:** a subtle rainbow glow behind the orb (a UIGradient
  circle). No animated stroke.

**Mutation odds (must stay visible: Paid Random Items):** one line of
small text, 12 px, inside the card's bottom-left, above the bottom edge,
e.g. `✨6.9%  💎1.4%  🌈0.17%`. Each value in its mutation colour, ink
stroke. No pill chips.

**Price:**
- A coin-style gold circle (16 px) plus `$285` in 24 px `Fonts.Display`,
  gold with an ink stroke.
- Centred on the card's **bottom edge** at the right (x ≈ 230–290), half
  outside the card, like PS99's "🪙 450".
- During tutorial free pulls it shows `FREE`.

**Buttons:** 10 px under the card, centred.
- Order: **E** (left) · **R** (centre) · **T** (right).
- **Circles:** solid UITheme blue, with a 4 px white stroke and a soft ink
  shadow.
  - Side buttons (E, T): 52 px. Centre button (R): 62 px.
- **Inside each circle:** the key letter, 28 px `Fonts.Display`, white with
  an ink stroke. On a controller, the gamepad glyph instead. On touch, the
  same circles act as the tap targets.
- **Caption** under each, white 14 px with an ink stroke: `Pull`, `×10`,
  `Auto`.
- **Auto ON:** T's circle turns green and the caption reads `Auto ON`.
- On a phone the circles stay ≥ 44 px after the 0.8 scale, so the side
  buttons are 56 px design there.

**Size check:**
- At 1920 × 1080 the whole card plus buttons is about 300 × 290 px on
  screen, roughly the PS99 card's size in Harris's screenshot.
- Because the card's **bottom** (the button row) is on the anchor above
  the ball, the buttons sit just over the ball and the card above them,
  like PS99's buttons over the egg.

Remove the old styling code:
- the violet panel and gold rim;
- the tile gradients and ribbons;
- the mutation pill chips;
- the bottom-right price pill.

## Check

- `luau-lsp analyze` shows no new errors. All colours are UITheme tokens.
- **`/selftest gacha`:**
  - update the content checks for the new tree: 6 orb cells, 6 % labels
    with `TextBounds.Y > 0`, the mutation line, the price and 3 buttons;
  - text fits on desktop and phone;
  - every tap target ≥ 44 px on phone;
  - keep the anchor, odds, silhouette and keys checks as they are.
- Harris: walk up to the pad. The card should look like the PS99 egg card:
  white, the title on the top edge, big orbs with coloured %, the price on
  the bottom edge, and round E / R / T buttons just above the ball.
- Update `docs/systems/items-and-fusion.md` and UI_TEST.
- Say which branch you pushed to.
