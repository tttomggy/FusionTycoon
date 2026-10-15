# Gacha card, done the Pet Sim 99 / Bubble Gum Sim way (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 8 lines or fewer.

---

Harris tested `9658b10` on Oct 15. **Combat works now**: the Bat and the
Glove launch players. Leave combat alone.

The gacha card is still wrong. From his screenshots:

- **Too big and too high:** a huge orange-rimmed card fills the top of the
  screen above the pad. At normal zoom you only see its bottom row (the
  LEGENDARY / SECRET % and the mutation chips) poking out at the top edge.
- **It renders in pieces:** walking up, it first shows only the Rare and
  Secret tiles, then "zooms in" and shows everything.
  - That's three nested UIScales (Pop, Clamp, Fit) recomputed from the
    card's own on-screen size, which is a feedback loop.
  - On top of that, six 3D ViewportFrames render lazily.
- The default prompt "H · How it works" still shows next to the pad.

**Why the references work.** Pet Sim 99's and Bubble Gum Sim's egg cards
are **fixed-size on screen** (pixel-sized BillboardGuis). They're the same
size at any zoom: small, never off-screen, always readable. They sit just
above the egg, and they're compact.

Bubble Gum Sim's card, from top to bottom:
- the egg name top-left and an (i) top-right;
- a 3 × 2 grid of pet icons, each with its % underneath in the rarity
  colour;
- a price pill at the bottom-right corner;
- **under the card**, a row of 3 round buttons (`1 Hatch`, `E Multi`,
  `R Auto`).

Copy that structure.

## 1. Rebuild the card as a fixed pixel-size billboard

**Delete:**
- the studs-sized canvas;
- the Clamp and Fit UIScales and the on-screen size math;
- `MaxScreenShare`;
- the 3D ViewportFrame orbs and their spinner;
- the 0.6 → 1 pop.

**Keep:**
- the character-distance trigger (in at 16 studs, out at 19);
- the odds source (`GetGachaOddsRows` at the server's luck);
- silhouettes;
- the (i) panel;
- the key bar's actions (E / R / T, `RequestGachaPull`, `SetAutoPull`);
- the small far-away `GachaLabel`.

**The billboard:**
- `Size = UDim2.fromOffset(300, 268)`: a 300 × 204 card plus a 64 px
  button row. Fixed pixels, like PS99.
- On a phone (`UIKit.IsPhone()`), one UIScale of 0.8, set once on
  `LayoutChanged`. That's the **only** sizing UIScale.
- Anchor it with `StudsOffset` so the **card's bottom edge** (without the
  button row) sits about 1 stud above your character's head while you
  stand on the pad. Measure from the character's actual height, not a
  constant, because the monkey avatar is short.
  - Use `SizeOffset = Vector2.new(0, 0.5)`, so the billboard grows upward
    from its anchor.
  - Shift it 2.5 studs toward the pad's far side
    (`StudsOffsetWorldSpace`), so the card is above and slightly behind
    you, never over you.
- `AlwaysOnTop = false`, `LightInfluence = 0`, `MaxDistance = 150`,
  `ResetOnSpawn = false`, `ClipsDescendants = false`. No CanvasGroup.
- **Pop:** one extra UIScale, 0.85 → 1 over 0.12 s (Quad-Out) when it
  opens; it closes the same way, in reverse. **Build the card's content
  once**, while hidden, before the first open. A refresh only updates
  text and colours, never rebuilds, so nothing ever shows half-built.

**Layout (design px, inside the 300 × 204 card):**

```
┌──────────────────────────────────────┐  card: dark violet (Panel), 3 px gold
│ 🔮 GACHA PAD          🍀×1.15   (i)  │  stroke, 16 px corners
│ ┌──────┐ ┌──────┐ ┌──────┐           │  header 28 px: title white + ink stroke,
│ │  ●   │ │  ●   │ │  ●   │           │  luck pill only when luck > 1
│ │77.9% │ │ 18%  │ │ 3.5% │           │  tiles 88 × 58, gap 6, centred:
│ └COMMON┘ └RARE──┘ └EPIC──┘           │   tier-gradient rounded square,
│ ┌──────┐ ┌──────┐ ┌──────┐           │   2D orb (UIKit.TierOrb, 26 px) top,
│ │  ●   │ │  ?   │ │  ?   │           │   % 18 px white with a tier-colour
│ │0.52% │ │0.058%│ │0.0023│           │   stroke, the tier name 9 px in the
│ └LEGEND┘ └MYTHIC┘ └SECRET┘           │   bottom ribbon
│ ✨13.8%  💎0.92%  🌈0.12%    [$285]  │  mutation chips 16 px tall, left;
└──────────────────────────────────────┘  the price pill, gold, bottom-right
      (E)        (R)        (T)          button row: 48 px circles, 8 px below
     Pull       ×10       Auto OFF       the card, captions 11 px
```

- **Orbs:** 2D `UIKit.TierOrb`, no ViewportFrames. An unfound tier is a
  black orb with a "?", and its % still shows.
- **Secret tile:** the rainbow stroke, animated by rotating its
  UIGradient. That's cheap, so keep it.
- **Text sizes:** fixed pixel sizes, no TextScaled. Run every label
  through the text-fits check.
- **Buttons:** keycap letters on desktop, gamepad glyphs on a controller,
  and touch shows the same circles as tap targets. At 0.8 they measure
  ≥ 44 px on a phone, so keep the circles at 56 px design if needed. T
  turns green, showing "Auto ON", while auto pull runs.

## 2. Leftovers

- Disable the gacha's `HelpPrompt`, and any remaining `PullPrompt` /
  `Pull10Prompt` UI, so no default "How it works" or "Pull" prompt shows
  near the pad. "How it works" lives in the (i) panel.
- Leave the LOCK console's own prompt alone.

## Check

- `luau-lsp analyze` shows no new errors.
- **`/selftest gacha`, read from the instance tree:**
  - "card opens fully in one frame": the frame after it opens, all 6 tiles
    have `AbsoluteSize > 0` and their % has `TextBounds.Y > 0`;
  - "the card's on-screen size is the same at camera distance 8 and 30
    (±2 px)";
  - "the whole card + button row is on screen with the character on the
    pad", at 1366 × 768 and 844 × 390, at the default zoom and at max
    zoom-out;
  - "no ViewportFrame, no CanvasGroup, exactly 1 UIScale besides the phone
    one";
  - "no gacha ProximityPrompt draws UI";
  - the existing odds / silhouette / luck / keys / auto-pull checks.
- Give Harris this list:
  1. Walk to the pad: a compact card pops up just above your head, all 6
     tiles at once.
  2. Zoom in and out: the card stays the same size on screen.
  3. E, R and T are under it; T says Auto ON / OFF.
  4. On a phone the buttons can be tapped.
- Update `docs/systems/items-and-fusion.md` and UI_TEST.
- Say which branch you pushed to.
