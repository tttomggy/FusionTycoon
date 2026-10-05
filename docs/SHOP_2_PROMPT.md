# Fusion Tycoon: Shop 2 + readable gold buttons (build prompt for Claude Code)

`git pull` on `world-redesign` first. Commit per phase. PR → `main`, don't merge.

---

Read CLAUDE.md and follow it. Harris's 2-player playtest (Oct 5) found two
problems.

- **Dark text on gold is unreadable.** This covers the HUD SHOP button, the
  selected shop tab ("Passes" was almost invisible), and the CLAIM YOUR BASE
  sign.
- **The shop is split into tabs that hide everything else.** Big Games' shops
  (Pet Simulator X / 99) put everything on one long scrolling page, which is
  the pattern kids know. We're copying that structure, not their art.

**Every honesty rule in CLAUDE.md's Monetization section still applies.**

- Live prices only.
- No fake discounts, no fake "POPULAR", and no countdowns that aren't real.
- `Id = 0` items are hidden in live games, and the SHOP button stays hidden
  until something is for sale.

## Phase 1: Contrast rule (everywhere, not just the shop)

1. **The rule.** On any gold, yellow or orange fill, text is **white** with the
   ink stroke used by UPGRADES / ITEMS / INDEX (`UITheme` tokens). It is never
   dark brown or gold-on-gold.
   - Put it in UIKit, so a gold Button or Pill picks the right text colour by
     itself.
   - Add the rule to CLAUDE.md's UI rules.
2. **Fix every case.**
   - The HUD SHOP button.
   - The CLAIM YOUR BASE billboard (`BillboardKit`).
   - Gold chips and pills, the daily TODAY tile, and BEST VALUE tags.
   - Grep every gold, yellow and orange gradient or fill token and check the
     text on each one.
3. **Selected state.** Any tab or segment row's *selected* item is **green**
   (the UPGRADES green) with white text, and unselected items stay the muted
   panel colour. This covers:
   - the shop chips;
   - the Index tier tabs (keep the tier-colour name, but make the active pill
     green);
   - the Settings 5-segment rows;
   - the Fuse count chips.

   A tap gives a quick press-bounce (`UIScale` 0.94 → 1) and plays the Toast
   sound slot.
4. **Chat overlap.** On desktop the Roblox chat window sits over the top-left
   of centred cards (the Daily card's title was hidden behind it). Centred
   modals must start below `TOP_SAFE` (Roblox top bar plus chat height, a new
   UIKit constant) on desktop, so their title is never under chat. Phones are
   unchanged.

## Phase 2: One scrolling shop

**Structure.** The ShopPanel becomes **one ScrollingFrame**.

- A sticky header row holds the title and ✕.
- Below it sits a sticky **category chip bar**: ⭐ Featured · 🎟 Passes ·
  ⚡ Boosts · 💰 Cash · 🍀 Luck · 🛡 Safe.
- Tapping a chip **tweens the scroll** to that section; it doesn't filter.
- While the player scrolls, the chip for the section on screen turns green.
- The panel opens at the top. A contextual offer opens it scrolled to Cash
  or Boosts.

**Sections, in order, each with a big header row (icon, title, thin divider):**

1. **⭐ Featured**: one wide banner, keeping today's logic (Starter Pack until
   bought, then a live sale, then the best value), with the shine sweep.
2. **🎟 Passes**: DoubleCash, VIP, ExtraPedestals, AutoFuse, LabStyle, Lucky.
   These are big cards: a large icon, the name, a one-line benefit, and the
   buy button. An owned pass shows a grey "OWNED ✓" button and sorts to the
   end.
3. **⚡ Boosts**: QuickBoost, Boost (or BoostSale while its window is live),
   Overclock. Each tile shows the time that would be banked ("+1 h · you
   have 0:42").
4. **💰 Cash**: PocketCash, CashCrate, CashVault. Each shows **the $ amount
   this player would get right now** (as today). The best $ per R$ gets a
   "BEST VALUE" tag, computed from live prices.
5. **🍀 Luck**: LuckPotion. Keep it its own small section, so the Lucky pass
   stays in Passes.
6. **🛡 Safe Fusion**: SafeFusion1, SafeFusion5, with "SAVE N%" computed from
   live prices.

The honest footer line stays at the bottom. OfflineDouble stays only on the
welcome-back card, as now.

**Tiles.** Use 4 columns on desktop and 2 on phones (with the 1 px grid slack
from Bug Hunt 1).

- Each tile is chunky and colourful, with its own rounded panel and a light
  gradient in its section colour.
- The icon is large. The buy button is **green**, with the Robux glyph and the
  live price in white (or "TEST" in Studio when `Id = 0`).
- Hovering scales the tile to 1.03; pressing bounces it.

**Icons.**

- **Live:** read `IconImageAssetId` from the same `GetProductInfo` call that
  `ShopPrices` already caches (extend it). Harris uploads each icon when he
  creates the pass or product, so the in-game tile always matches the store
  page.
- **Fallback** (Studio, `Id = 0`, or icon not loaded): today's emoji glyph in
  a circle. The art lives in `marketing/shop_icons/<Key>.png` for Harris to
  upload. **Don't** try to upload images from code.

**Phone.** The chip bar scrolls sideways if it doesn't fit. Tap targets are
at least 44 px. Check that the whole page is reachable at 844×390.

## Check

- **UI_TEST, Shop 2 section:**
  - every chip jumps to its section;
  - the active chip follows the scroll;
  - every buy button opens the right prompt (TEST in Studio);
  - owned passes sort last;
  - Cash amounts match `/cash`;
  - phone layout works.
- **UI_TEST, contrast:** look over every gold surface.
- `/selftest` passes, with the ShopPanel builds at both scales.
- `luau-lsp analyze` reports no new errors.
- **Report:** before and after notes for each contrast fix, and the final
  section and tile sizes.
