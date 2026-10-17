# Polish 9: the deal badge becomes a Pet Sim 99-style pack tile (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 5 lines.

---

Harris is happy with the gacha card. Final polish starts with the HUD
deal badge: today it's a flat pink pill reading `🔥 −23% · 4:08:48`, and
he says it looks boring. PS99 and similar games show a **picture of the
pack** with a glow behind it, a sale ribbon and the timer underneath.

The deal is real: `DealConfig` runs 6-hour UTC slots, `MinSavePercent`
is 15, and the live price comes from `ShopPrices`. So showing the % and the
countdown is allowed. The monetization never list still applies, so read
the rules below.

## 1. The tile (`HudController.buildDealBadge` / `refreshDealBadge`)

Replace the pill with a tile in the same HUD slot, under SHOP / GIFTS, and
heading the status stack on a phone.

```
 ┌───────────────┐
 │  ✦ rays ✦     │  92 x 92 square: Deal-pink gradient, 16 px corners, 3 px white stroke
 │   [ PACK ]    │  the pack art (72 px), slowly rotating light rays behind it
 │  ╲  −23%  ╲   │  a diagonal gold ribbon across the top-right corner: "−23%"
 └───────────────┘
   🔥 4:08:48      timer pill under the tile: white text, ink stroke, dark pill
```

- **Pack art:** the current deal product's **live icon**, the
  `IconImageAssetId` that `ShopPrices` already fetches through
  GetProductInfo. That's the PNG Harris sets on the product in Creator Hub
  (`marketing/shop_icons/DealPowerHour.png`, `DealFusionKit.png`,
  `DealRichLab.png`).
  - If there's no icon yet, fall back to the deal's emoji at 48 px, so it
    never looks broken.
  - Never upload images from code.
- **Rays:** one `ImageLabel` behind the art, rotated slowly (360° per 12 s)
  while the badge is on screen.
  - Build the ray look with a UIGradient with hard stops on a square
    frame. No asset upload needed.
  - Transparency 0.6, in `UITheme` tokens.
- **Shine:** a white diagonal UIGradient sweep across the tile **once
  every 6 s**: 0.5 s sweep, then rest.
- **Ribbon:** gold (`Gradients.Gold`), white text with the ink stroke (the
  contrast rule), rotated 45° across the corner. It shows
  `−{deal.Save}%` from the live saving. If the saving is unknown, it shows
  `DEAL`.
- **Timer:** the real `deal.SecondsLeft` through `EventState.FormatTimer`,
  the same as now.
- **Tap:** the whole tile and timer open `ShopPanel.Open("Deal")`. Use a
  `UIKit.SelectFeedback` press. The hit area is ≥ 44 px.
- **New slot:** keep the existing one-time pulse, and add the shine sweep
  at once.
- On a phone, the tile is 76 × 76 plus the timer, keeping the status-stack
  rules.

## 2. Never-list guardrails (don't break these)

- **No flashing or blinking.** The idle motion is only the slow rays and
  the 6-second shine.
- **No red urgency timer**, no "LAST CHANCE", "HURRY" or "ENDING SOON",
  and no extra effects in the final hour. The timer looks the same at 5:59
  and at 0:30.
- **Still hidden** for policy-restricted players, during the tutorial,
  while Carrying or being stolen from, and after a loss or theft, exactly
  as the pill is today.
- No Robux price on the tile.

## 3. The pull "skipped line" overlaps the cash panel

In Harris's screenshot, an auto-pull skipped line (`COMMON · Spark Cell ·
+$19.7/s`) sits on top of the money panel's right edge, mid-left of the
screen.
- Skipped lines must stack **above the weapon bar, centred**, as the doc
  says, never over the HUD left column.
- Find what's placing them there and fix it.

## Check

- `luau-lsp analyze` shows no new errors. All colours come from UITheme.
- **New `/selftest` lines:**
  - "deal tile: art or fallback drawn (`AbsoluteSize > 0`), ribbon text =
    the live saving, timer = `SecondsLeft`";
  - "deal tile: no overlap with the HUD left column or the bottom row",
    at 1366 × 768 and 844 × 390;
  - "skipped lines never overlap any HUD rect" (show 3 at once, then
    measure);
  - "deal tile hidden for restricted, tutorial and Carrying".
- Harris: the 🔥 badge is now a pack picture with rays, a −23% ribbon and
  the timer under it; tapping it opens the deal. Auto pull lines appear
  above the weapon bar, not over the cash.
- Update `docs/systems/monetization.md` and UI_TEST.
- Say which branch you pushed to.
