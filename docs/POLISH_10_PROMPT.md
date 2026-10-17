# Polish 10: deals say what's inside, an active-effects tray, Auto pull ×10 (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 8 lines.

---

Harris's feedback on Oct 17:

1. **Deals:** kids can't tell what a deal contains or why they'd want it.
   The shop card says "Boost 1 h + Luck Potion 15 min, normally 128, now
   99 (−23%)". That's jargon, and the two tiny icons explain nothing.
2. **Active effects** (Boost, Luck Potion, Lucky Charm, Speed Boots, Safe
   Fusion tokens, Fusion Spark, Coin Magnet, the server Overclock) should
   show as **round icons with a timer**, like Bubble Gum Simulator's effect
   row. Today they're small pills beside SHOP / GIFTS.
3. **Auto pull** should do **×10 every time**, and show the 10-pull result
   card each time, the same as pressing R.

## 1. Deals explain themselves

**Plain words for every product.** Add a `Plain` field to every
`ShopConfig` product and every `QuestConfig.PowerUps` entry: one short line
a 7-year-old understands, with no units jargon. Use these:

| Key | Plain |
|---|---|
| Boost | Double cash for 1 hour |
| LuckPotion | Rare orbs 2× more likely for 15 minutes |
| SafeFusion1 | A failed fusion keeps ALL your orbs |
| CashBurst | Double cash for 5 minutes |
| LuckyCharm | Rare orbs 2× more likely for 10 minutes |
| SpeedBoots | Run 1.5× faster for 2 minutes |
| FusionSpark | Your next fusion is 10% more likely to work |
| CoinMagnet | Golden Rain coins fly to you |

Write the rest of the products in the same style. `/selftest` asserts every
product and power-up has a non-empty `Plain`.

**Shop deal card, redesigned:**

```
┌───────────────────────────────────────────────────────────────┐
│ 🔥 DEAL · ends in 3:49:28                                     │
│ Power Hour Deal                                               │
│ ┌────────┐  ┌────────┐                                        │
│ │ [icon] │  │ [icon] │      YOU GET:                    [ 99 ]│
│ │  1 h   │  │ 15 min │      ✓ Double cash for 1 hour          │
│ └────────┘  └────────┘      ✓ Rare orbs 2× more likely…      │
│   Boost      Luck Potion    Worth 128 if bought separately    │
└───────────────────────────────────────────────────────────────┘
```

- **One tile per part** (the same part twice becomes one tile with a `×3`
  badge):
  - 72 px, using the part product's live icon (`ShopPrices`), with the
    emoji as a fallback;
  - its duration or count on the tile;
  - its name under it.
- **"YOU GET:" list:** one ✓ line per part, built from its `Plain` text.
- **Value line:** "Worth 128 if bought separately". Both numbers are
  **live** prices: `ShopPrices` for the parts' sum, the deal's own price on
  the button. Never typed.
- Keep the real timer. No urgency words.
- Apply the same tile + "YOU GET" pattern to the **Starter Pack** card and
  to each "New deal!" side card.

**HUD deal tile** (from Polish 9): add a strip of the part glyphs along the
tile's bottom edge (e.g. `💵 🍀`), so the tile itself hints at what's
inside. Tapping it still opens the deal in the shop.

## 2. Active-effects tray, bottom right

- **New `UI/EffectsTray`:** one row of round icons anchored to the
  **bottom-right** corner, 16 px from the right edge.
  - Its bottom lines up with the bottom of the HUD's bottom row.
  - It grows right-to-left and wraps to a second row above after 4.
  - If it would overlap the bottom row (narrow screens and phones), it
    moves up so its bottom sits 8 px above the bottom row's top.
  - (Bubble Gum Sim puts theirs bottom-left. Ours goes bottom-right because
    our left column is full.)
- **Each effect is a 60 px circle** (52 px on phone; the tap target stays
  ≥ 44 px after the 0.8 scale):
  - a UITheme gradient per effect, a 3 px white stroke, a soft ink shadow;
  - the effect's live product icon where it is a shop product (Boost, Luck
    Potion), otherwise its glyph at 30 px;
  - **under it,** a timer label: 16 px, white with an ink stroke, `m:ss`,
    or `h:mm:ss` past an hour;
  - **count effects** (Safe Fusion tokens, Fusion Spark charges) show a
    `×N` badge top-right instead of a timer;
  - **one-shot effects** (Coin Magnet, armed for the next rain) show
    `READY`.
- **The effects:**
  - Income boost (bank timer);
  - Luck (Luck Potion + Lucky Charm bank, showing `×2` on the badge);
  - server Overclock;
  - Speed Boots;
  - Safe Fusion tokens;
  - Fusion Spark;
  - Coin Magnet.
- **Tap or hover:** a small tooltip above the icon, e.g. "Rare orbs 2× more
  likely · 12:41 left". Only one tooltip at a time; tap elsewhere closes
  it.
- Effects pop in with a 0.85 → 1 scale (0.15 s) when gained, and shrink
  out when they end. **No flashing**, including in the last minute.
- **Delete** the effect pills (`effectPills` Income / Luck / Server) from
  the SHOP row and the phone status stack. The `next in m:ss` gifts timer
  stays where it is.
- Every number comes from the synced data the pills use today. No new
  server state.

## 3. Auto pull = ×10, with the result card

- **Each auto cycle is a ×10 pull** at the ×10 price, through the same
  shared function the R key and `RequestGachaPull { Count = 10 }` use. No
  second copy.
- **The client shows the same 10-pull result card** a manual R shows, every
  cycle, with the BEST OF 10 big card following the reveal rule exactly as
  a manual ×10 does (Secrets and event mutations always). During auto pull
  the 10-pull card **closes by itself** after
  `GachaConfig.AutoPullCardSeconds = 2.5`.
- **Pacing:**
  - add a remote `AutoPullReady` (client → server, no payload, in
    `REMOTE_EVENT_NAMES` with a comment);
  - the client fires it when the cycle's cards have closed, so a Secret's
    big card pauses auto pull until the player closes it;
  - the server starts the next ×10 only after that, or after an 8 s
    timeout, and never sooner than `GachaConfig.AutoPullMinSeconds = 3`
    after the previous one;
  - rate-limit it with `RemoteGuard`.
- **It stops** when you can't afford ×10 (toast: "Auto stopped: need
  $3.06K for 10 pulls"), walk away, start carrying, die or leave, or press
  T.
- Auto pull no longer uses the small skipped lines.
- The gacha card's T caption reads `Auto ×10` / `Auto ×10 ON`.
- Still free, no pass. Update the monetization doc line.

## Check

- `luau-lsp analyze` shows no new errors (install it per CLAUDE.md if it's
  missing; last time it wasn't run).
- **`/selftest`:**
  - every product and power-up has `Plain`;
  - the deal card has one tile per distinct part and a "YOU GET" line per
    part, and the worth value equals the live sum of the parts;
  - the effects tray:
    - grant a Luck Potion and 2 Safe Fusion tokens through the Studio
      commands;
    - the tray shows a luck circle with a timer and a Safe Fusion circle
      with `×2`;
    - no overlap with any HUD rect at 1366 × 768 and 844 × 390;
    - the old effect pills are gone;
  - auto pull:
    - start it with enough cash for 20 pulls;
    - exactly 2 ×10 cycles run, each shows the 10-pull card, and it then
      stops with reason `TooPoor`;
    - no cycle starts within 3 s of the previous one.
- **Give Harris this list:**
  1. Open the shop at Deal: tiles show what's inside, a "YOU GET" list in
     plain words, and "Worth … if bought separately".
  2. Use a Lucky Charm and a Safe Fusion: round icons with a timer or ×N
     appear bottom-right; tap one for its tooltip.
  3. Press T at the pad: it pulls 10 at a time, shows the 10-pull card
     each time, and stops when you run out of cash.
- Update `docs/systems/monetization.md`, `items-and-fusion.md`,
  `quests.md`, `architecture.md` (remote) and UI_TEST.
- Say which branch you pushed to.
