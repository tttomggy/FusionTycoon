# Fusion Tycoon: Shop 3 (placement, purchase celebration, real deals) (build prompt for Claude Code)

`git pull` on `world-redesign` first, and commit per phase. If PR #11 is
still open, this goes into it; otherwise open a new PR → `main`. Don't merge.

---

Read CLAUDE.md and follow it. This comes from Harris's Oct 5 playtest
(desktop and the iPhone emulator) and a Pet Simulator 99 reference video. We
copy what makes those games feel exciting to buy from: placement, juice and
recurring deals. **We do not copy dark patterns.** Every rule in the
Monetization "never" list still holds, and for this prompt specifically:

- Every countdown is real: it is the time until a deterministic rotation.
- Every "SAVE %" is computed from live prices.
- There is no fake "POPULAR", no "only N left", and no purchase announcements
  to the server.
- No pop-up appears in the first 10 minutes of a first session, within 60 s
  of a loss, or during a heist.

## Phase 1: Placement (every panel, not just the shop)

1. **Cards sit high.** Shop 2's `TOP_SAFE` (top bar + 180 px chat) put every
   centred card at the bottom of the screen: the SHOP panel started at 340 of
   515 px, and its bottom was cut off.
   - Replace it. Centred modals are **top-anchored** just under the Roblox top
     bar (`TOP_BAR_HEIGHT` + 8), horizontally centred. They use the space down
     to the bottom bar and never cover it.
   - **Chat** only matters if the card's left edge actually overlaps the chat
     window's horizontal span (~400 px from the left on desktop). Only then,
     slide the card right until it clears, if there's room. Otherwise accept
     the overlap: chat is collapsible. Never push cards down for chat.
   - This applies to Shop, Gifts, Daily, Index, Upgrades, Settings, Fuse,
     Rebirth, How to Heist and the result and THANK YOU cards: every
     `UIKit.Modal` and centred card.
2. **Phones.**
   - Each card's title row must keep clear of the Roblox top-left buttons:
     the 170 × 60 rule, after scale. On the iPhone emulator the SHOP title sat
     under the ☰ / chat icons. Start the card below 60 px, or indent its title
     past 170 px.
   - The **SHOP / GIFTS / timed-pill row** must sit in the left column under
     the cash card, as on desktop. On the phone emulator it floated top-centre
     over the CLAIM YOUR BASE arrow.
   - Recheck every HUD element at 844 × 390: nothing overlaps.
3. **The HUD is never drawn over an open card.** On the phone, the SHOP and
   GIFTS buttons rendered on top of the open Gifts panel. Open cards must have
   a higher DisplayOrder than every HUD ScreenGui, plus their dim backdrop.
   Add a check for this to `/selftest`.
4. **Chip jumps land exactly.** Tapping a chip puts that section's **header
   right under the chip bar** (within 2 px). Today it stops partway, with the
   previous section's buttons still showing.
   - Compute the target from the header's position inside the canvas,
     corrected for the effective UIScale.
   - After the tween, verify and nudge once.
   - Clamp to the canvas end: the last section may not be able to reach the
     top, and that's fine.
   - Add a `/selftest` case that jumps to every chip at both scales and checks
     the 2 px rule wherever the canvas allows it.

## Phase 2: Purchase celebration (replaces the plain THANK YOU text)

When a purchase or test grant succeeds (`ShopPurchased`), play a **reveal**
in the style of a big result card. Run it client-side, so it can be skipped
with a tap after 0.6 s.

1. **Burst (0–0.5 s).**
   - The screen dims.
   - Spinning light rays and a radial glow appear behind the centre.
   - A confetti burst plays: 2D particles in the item's section colour plus
     gold, about 60 pieces, using gravity and fade, all in one ScreenGui.
   - Plays the `RevealMajor` sound slot.
2. **The item (0.3–1.2 s).**
   - The item's icon (the live store icon, or the fallback glyph) pops in with
     overshoot to a big size (~260 px desktop / 180 px phone), with a shine
     sweep across it.
   - Its name in big white text with the ink stroke, and "THANK YOU!" above
     it.
3. **What you got, animated per type.**
   - **Cash pack:** "+$250K" counts up from 0 over 0.8 s. Then ~15 coin icons
     fly from the card into the HUD cash counter, which ticks up and bounces
     as they land.
   - **Boost / Luck Potion / Overclock:** the time ("+1 h") flies into its HUD
     timed pill, which pops in or bounces. The HUD income line (or the luck
     line) shows the new multiplier with a brief green flash.
   - **Pass:** a "✓ ACTIVE" stamp hits the card with a little shake. What it
     changes plays live:
     - **2× Cash / VIP:** the HUD $/s number doubles visibly (count-up).
     - **+2 Pedestals:** the two plinths in the lab un-dim with a light pop.
     - **Neon Pink Lab:** the lab trims flash to pink.
     - **Auto-Fuse:** the Fuse panel toggle hint.
   - **Safe Fusion:** shield tokens drop into the "🛡 Safe Fusion (N)" count.
   - **Starter Pack / bundles:** each content line pops in one after another
     with the same per-type effect.
4. **Close.** The "AWESOME!" green button (≥ 44 px) or any tap after the
   sequence closes it. The panel stays open underneath and the item's tile
   updates (OWNED ✓, new banked time and so on).
   - Respect the SFX volume setting.
   - No auto-chain into another purchase prompt.

## Phase 3: Real rotating deals

**What a deal is.** A deal is a **bundle sold as its own developer product**,
always priced below the sum of its parts at live prices. Add the bundles to
ShopConfig with Restricted = yes, and add them to `docs/SHOP_SETUP.md` with
planned prices for Harris:

| Key | Contents | Planned R$ | Parts at planned prices |
|---|---|---|---|
| `DealPowerHour` | Boost (×2 income 1 h) + Luck Potion (×2 luck 15 min) | 99 | 128 (−23%) |
| `DealFusionKit` | 3 Safe Fusion tokens + Luck Potion | 79 | 124 (−36%) |
| `DealRichLab` | Cash Crate + Quick Boost | 179 | 228 (−21%) |

**Rotation.**
- **Deterministic from UTC**, like the event schedule: one deal per 6-hour
  slot, `DealConfig.GetDealForSlot(slotStart)` (lowbias32 hash, no repeat of
  the previous slot's deal). Every server and client agrees with no
  messaging.
- The countdown shown is the real time to the next slot.
- A deal is only shown if its **live** saving is ≥ 15%, and never to
  policy-restricted players.
- The server refuses a deal key that isn't the current slot's deal. Honour
  receipts for 10 minutes after a prompt made inside the slot, like
  `BoostSale`.

**Where deals appear.**
1. **Shop:** a "🔥 DEAL" banner at the very top of the Featured section, above
   the Starter Pack.
   - Contents as mini icons, "normally ~~128~~ R$ · now 99 R$ (−23%)" from
     live prices, and "new deal in 3:12:05".
   - The chip bar gets a 🔥 Deal chip first.
2. **HUD deal badge:** a small badge in the left column under SHOP/GIFTS:
   🔥, the saving ("−23%") and the real countdown.
   - It pulses once when a new slot starts.
   - Tapping it opens the shop at the deal.
3. **"New deal!" pop-up:** at most **once per slot per player**. It's a
   non-modal side card (like the Starter Pack card) showing the deal's icons,
   the real saving, "Not now" and "See deal".
   - Same guards as the contextual offer: never in the first session's first
     10 minutes, never over another card, never within 60 s of a failed
     fusion, a theft or a caught steal, and never while carrying or being
     stolen from.
   - Shared rate limit with the contextual offer: at most one shop pop-up of
     any kind per 5 minutes.
   - "Not now" hides it until the next slot.
   - Analytics: `DealShown` / `DealOpened` / `DealDismissed` (Custom, through
     `ShopAnalytics`).

## Phase 4: Make the shop pop

- **Panel.** A brighter header with the cart icon and a soft animated shine.
  Section headers get a coloured pill behind the icon.
- **Tiles.** Each section gets its own vivid gradient (Passes blue, Boosts
  orange, Cash green, Luck teal, Safe indigo, Deal hot pink). Icons are bigger
  (~45% of tile height).
  - The buy button is chunky green with the Robux glyph and the live price.
  - Hover gives a scale of 1.04 plus a glow stroke; a press bounces.
- **"NEW!" tag:** only on items whose `ShopConfig.AddedUtcDay` is within the
  last 7 days. This is real, so it's allowed.
- **No server-wide "X bought Y" messages** (kids audience; keep the pressure
  low).

## Check

- **UI_TEST, Shop 3 section:**
  - Placement on desktop at 1920×1080 and 1366×768, and on the iPhone
    emulator, for every card.
  - Chip jumps.
  - Each celebration type, through `/shop grant <key>`.
  - Deals: `/deal slot <offsetHours>` (Studio) to walk the rotation, and
    `/deal pop` to force the pop-up once, ignoring the cooldown.
- **`/selftest`** gets these new cases:
  - HUD below modals;
  - chip jumps;
  - deal schedule repeatable, with client and server agreeing;
  - a deal refused outside its slot.
- **CLAUDE.md:** short entries for DealConfig, the celebration and the
  placement rule (replace the `TOP_SAFE` text).
- `luau-lsp analyze` reports no new errors, and the layout assertions pass.
- **Report:** the placement numbers you chose, and anything you simplified.
