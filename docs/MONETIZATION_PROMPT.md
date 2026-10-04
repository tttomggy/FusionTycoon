# Fusion Tycoon — Monetization: shop, passes, boosts, cash, real deals (build prompt for Claude Code)

Paste into Claude Code on `world-redesign` (`git pull` first, after the
sounds pass). Open a new PR → `main` if none is open. Don't merge.

---

Read CLAUDE.md and follow it: one formula per number (income goes through
`IncomeInputs`), config tables for numbers, UITheme / UIKit, server authority,
saved data through PlayerDataService, and `luau-lsp analyze`. Commit each phase
on its own. The canvas board **"Shop · passes, boosts, cash, real deals"**
shows the design.

**The shop should look loud and exciting to kids. The deals must be real.**
Roblox's own creator rules forbid fake discounts, permanent "sales", countdown
timers that aren't real, and pressure copy like "LAST CHANCE". Prompting a
purchase right after a loss is the pattern regulators are looking at in
children's games right now. Harris wants big "SAVE 60%"-style deals; we get
them honestly:
- A bundle's "SAVE %" is computed from the **live** prices of its parts.
- A sale is a separate cheaper product, sold only inside a real scheduled
  window, with the real normal price struck through.

## Phase 1 — Compliance plumbing (before anything is sold)

- **`MonetizationService`** (new, `--!strict`, ServiceTemplate):
  - At join, call `PolicyService:GetPolicyInfoForPlayerAsync` and store
    `ArePaidRandomItemsRestricted` per player.
  - For those players, hide and refuse every product that adds **cash or luck**
    (cash packs, boosts, Overclock, Luck Potion, Lucky pass, Starter Pack). They
    can still buy cosmetics, +2 Pedestals, Auto-Fuse, VIP and 2× Cash (2× Cash
    is a permanent multiplier on earned income; keep it allowed). The gacha and
    fusion stay fully usable with earned cash.
  - If the policy call fails, treat the player as restricted.
- **Prices are never typed into the UI.** Every Robux price comes from
  `MarketplaceService:GetProductInfo`, cached for 10 minutes. Every "save %" is
  computed from those live prices.
- **Odds stay visible before every pull and fuse.** They already are: the
  Gacha Pad label and the odds board. Make sure any luck boost (the potion,
  the pass, Server Luck) feeds the same `FusionConfig.FormatOdds`, so the
  displayed odds update live while a boost is active.
- **Purchases are safe:**
  - `ProcessReceipt` is idempotent. Store granted `PurchaseId`s in
    `PlayerData.Receipts` (keep the last 200), grant, `SaveNow`, and only then
    return `PurchaseGranted`.
  - Return `NotProcessedYet` if the profile isn't loaded or the save fails.
  - Passes: `UserOwnsGamePassAsync` at join, plus
    `PromptGamePassPurchaseFinished`.
  - Everything is resolved server-side from the player.
- **IDs:** new `Shared/Config/ShopConfig.lua` holds every pass and product
  with `Id = 0` placeholders. An item with Id 0 is hidden in live games.
- **Studio testing:**
  - In Studio, a `/shop grant <key>` debug command runs the real grant path
    without Robux.
  - Write `docs/SHOP_SETUP.md` for Harris: one line per item with the exact
    name, price, description and type (Pass or Developer Product) to create in
    Creator Hub, and where to paste each Id.

## Phase 2 — What we sell

**Gamepasses** (permanent):

| Key | Price | Effect |
|---|---|---|
| `DoubleCash` | 199 | ×2 all income, forever (`IncomeInputs.PassMultiplier`) |
| `ExtraPedestals` | 399 | 6 pedestals instead of 4 (see below) |
| `VIP` | 349 | +25% income; a gold "VIP" tag over the head and in chat (TextChatService `OnIncomingMessage` prefix); a gold trim on your lab's sign and walls |
| `AutoFuse` | 149 | A toggle in the Fuse panel: automatically Fuse All (pairs, Common–Epic, never mutated, the same rules as Fuse All) whenever new items arrive |
| `LabStyle` | 99 | Cosmetic "Neon Pink" theme for your own lab's accents, with a pink cash-ball skin. No power |
| `Lucky` | 299 | ×1.5 luck (stacks with rebirth luck); the odds displays include it |

**Developer products** (repeatable):

| Key | Price | Effect |
|---|---|---|
| `QuickBoost` | 29 | ×2 income for 15 min (stacking extends the time, max 3 h banked) |
| `Boost` | 79 | ×2 income for 1 h (same pool as QuickBoost) |
| `PocketCash` | 49 | Cash = 20 min of your **base** passive income (without timed boosts), with a floor of $5,000 |
| `CashCrate` | 199 | 2 h of base income, floor $50,000 |
| `CashVault` | 599 | 8 h of base income, floor $250,000 ("BEST VALUE") |
| `Overclock` | 149 | **Everyone in the server** gets ×2 income for 15 min, buys extend it up to 60 min; a banner "⚡ Harris overclocked the server! ×2 income for everyone" |
| `LuckPotion` | 49 | ×2 luck for 15 min (extends) |
| `SafeFusion1` / `SafeFusion5` | 25 / 99 | Safe Fusion tokens (saved count) |
| `StarterPack` | 99 | One-time: the LabStyle cosmetic plus a 1 h Boost plus PocketCash. Hidden once bought |
| `OfflineDouble` | 25 | The welcome-back card's COLLECT ×2 slot: doubles that pending payout |

**Effects plumbing**
- **Income:** every income effect lives in `IncomeInputs` and
  `TycoonConfig.GetIncomeMultiplier`: pass ×2, VIP ×1.25, boost ×2, Overclock
  ×2. The HUD multiplier pill shows the total and gets a small breakdown on
  tap.
- **Timed effects** are saved as **remaining seconds**, so they pause while
  you're offline, and they tick only while you're in game. Server-wide
  Overclock is session-only, on the server.
- **Offline earnings** ignore timed boosts (base income only).
- **Steal value is never raised by purchases:** the item's value is the item
  itself. Nothing sold protects a lab from theft, and nothing sold helps a
  thief.

**Extra pedestals**
- Add pedestal spots 5 and 6 to PlotLayout: a second row behind the current
  one, or flanking it. Use your choice of geometry, but the assertion block
  must pass.
- Every lab builds all 6.
- For non-owners of the pass, spots 5–6 are a dim plinth with a 🔒 label "+2
  PEDESTALS". Its prompt "Unlock" opens the pass purchase. This is the one
  in-world contextual sell.
- `GetIncomeInputs` counts up to 6 displays when the pass is owned.

**Safe Fusion**
- The Fuse panel gets a "🛡 Safe Fusion (3)" toggle, off by default, visible
  only when you own at least one token.
- While armed, a fusion consumes one token. If it **fails, every input
  orb comes back**; on success it's just used.
- **Never** offer Safe Fusion on the fail card.

## Phase 3 — The shop UI

**HUD SHOP button**
- A big gold "🛒 SHOP" button on the left edge, above the LOCK chip, at least
  56 px tall.
- A gentle wiggle every 20 s.
- A red "SALE" tag only while a real sale is live.
- Active timed effects show as small pills next to it: "⚡ 2× · 12:41", "🍀 2×
  luck · 3:10", "⚡ SERVER 2× · 8:02".

**Shop panel** (UIKit Modal, about 820 wide; on a phone it fills the screen and
scrolls):
- **Header:** a gold "🛒 SHOP" and ✕, on a radial violet glow.
- **Featured banner:**
  - The Starter Pack until it's bought, then the live sale if there is one,
    then the best-value item.
  - A warm gradient with a diagonal **shine sweep**, a client tween every ~3 s.
  - A big product art orb, the title, "Worth ~~227~~ R$ if bought one by one",
    a "SAVE 56%" pill, and a big green Robux price button.
  - All the numbers are computed from live prices.
- **Tabs:** 🔥 Deals · ⚡ Boosts · 💰 Cash · 🎟 Passes · 🍀 Luck.
- **Tiles** in a 4-column grid on desktop, 2 on phone. Each tile has:
  - its own glossy gradient and the shine sweep,
  - a big round icon that bobs,
  - the title, a one-line effect,
  - a green price button with the Robux glyph.
- **Ribbons:** POPULAR (Boost), BEST VALUE (Cash Vault), VIP. Owned passes
  show "✓ OWNED"; Safe Fusion shows "OWNED 3" plus the buy button.
- **Cash tiles show the actual amount you'd get right now** ("+$4.1M · 20 min
  of your income"), updating every few seconds.
- **Footer:** "Prices read live from Roblox · odds are always shown at the
  Gacha Pad and the Fusion Machine".
- **After a purchase:** a celebratory card "THANK YOU!" with what you got,
  using the existing reveal effects and the `RevealMajor` sound.

**Contextual offer** (the "pops up when you need money" part, done right)
- **When:** only when the player **taps** something they can't afford: an
  upgrade or MAX, a pull or Pull ×10, the Multiplier Pad, REBIRTH!.
- **What:** one card: "You tapped: Core Engine LV 7 · $8.2M", then "Need $3.4M
  more?", then the **smallest** cash pack that covers the gap, then "Not now"
  and the price button, then "or wait ~4 min with your income" (honest).
- **Limits:**
  - At most once per 5 min.
  - Never during the first 10 min of a player's first session.
  - Never stacked with another modal.
  - **Never** within 60 s after a failed fusion, a theft, or a caught steal.
- If no pack covers the gap, offer the Boost instead.

**Starter Pack offer:** once, in the player's **2nd session** (count
`PlayerData.Sessions`), 3 min after joining, as a dismissible side card ("Welcome
back! Starter Pack"). After that it only lives in the shop's featured slot
until bought.

**Real sales**
- `ShopConfig.Sales = { { Key = "Boost", SaleKey = "BoostSale", Window = "AdminAbuse" } }`.
  A sale product is a **separate developer product at a lower price**,
  sellable **only** while that window is live. Admin Abuse is running when
  AdminService's event override is active, or during a scheduled Admin Abuse
  time.
- The tile and the banner show "normally ~~79~~ R$ · today 49 R$ (−38%)",
  both live prices, and "Ends when Admin Abuse ends · 1:12:40" with the real
  end.
- The server refuses a sale product outside its window.
- No sale is ever shown outside a window.

## Phase 4 — Balance check

Run `econ_sim.py 30 12` for three players: free, 2× Cash + VIP + Extra
Pedestals, and the same with one Boost per hour. Report the time to each
milestone and to Rebirth 1–3.

**Don't change the prices or the base economy.** Harris and I decide from the
table. Note how much faster the payer is; a payer reaching Rebirth 1 in about
half the free time is the expected shape.

## Phase 5 — Docs and checks

- **CLAUDE.md:**
  - MonetizationService, the receipt rules, PolicyService handling,
  - ShopConfig, the live prices,
  - the income inputs added,
  - timed effects,
  - Extra Pedestals, Safe Fusion,
  - the contextual offer rules, the Starter Pack, real sales,
  - the "never" list: no fake discounts, no loss prompts, no protection or
    thief power for sale, no hard-coded prices.
- **UI_TEST:** add a case for each of these:
  - every product through `/shop grant`
  - a restricted-policy player sees no cash or luck products
  - the odds update with the Luck Potion
  - the contextual offer timing rules (including after a failed fusion)
  - the Starter Pack in session 2 only
  - a sale only inside the window
  - pedestals 5–6 locked and unlocked
  - Safe Fusion returns the orbs
  - Overclock for the whole server
  - a phone layout check
- **Checks:** `luau-lsp analyze` reports no new errors and the PlotLayout
  assertions pass. Commit per phase, push, and open or update the PR.
