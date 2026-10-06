# Monetization: shop, passes, products, deals, offers

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Monetization** (`MonetizationService`, every item and number in
  `ShopConfig`). **The deals must be real.** The "never" list: no fake
  discounts or permanent "sales", no countdowns that aren't real, no
  pressure copy ("LAST CHANCE"), no purchase prompt after a loss, nothing
  sold that protects a lab from theft or helps a thief (an item's steal
  value is the item itself), and **no Robux price typed into the UI**.
  - **Prices are live:** `ShopPrices.Get(key)` reads
    `MarketplaceService:GetProductInfo` (cached 10 min); every "SAVE %",
    "Worth ~~N~~ R$" and sale "(−38%)" is computed from those live prices
    (`ShopConfig.GetSavePercent`). `ShopConfig.Price` is the PLANNED price,
    only for `docs/SHOP_SETUP.md` (what Harris creates in Creator Hub). An
    item with `Id = 0` is hidden in live games; in Studio it shows with a
    "TEST" button that runs a test grant.
  - **PolicyService:** at join, `GetPolicyInfoForPlayerAsync`; a player with
    `ArePaidRandomItemsRestricted` (or a failed call) never sees or gets a
    `PolicyRestricted` item (cash packs, boosts, Overclock, Luck Potion,
    Lucky, Safe Fusion, Starter Pack, Double Offline Cash). 2× Cash, VIP,
    +2 Pedestals, Auto-Fuse and the cosmetic stay. The gacha and fusion
    stay fully playable with earned cash.
  - **Receipts (the receipt rule):** `ProcessReceipt` grants **only while
    this server holds the player's profile** (`IsProfileActive`), and
    answers `PurchaseGranted` only once the PurchaseId is in a SAVED copy
    (`IsReceiptSaved` reads `profile.LastSavedData`). The `Receipts` list
    (the last 200) lives in the profile, so a grant and its receipt land
    in the same write. A PurchaseId already granted this session →
    granted once that write has landed (else save, re-check); new → check
    (`refusal`) → grant (synchronous) → record → `SaveNowAsync` → saved?
    → `PurchaseGranted`. Not loaded, profile not active, a refused item or
    an unsaved receipt → `NotProcessedYet` (Roblox retries). Passes: `UserOwnsGamePassAsync` at
    join + `PromptGamePassPurchaseFinished` (session state, pushed into
    `PlayerDataService.SetShopSession`). Purchases start with remote
    `RequestShopPurchase { Key }`: the server re-checks (set up, policy,
    owned, one-time, sale window, something to double) and only then
    prompts; `ShopPurchased { Key, Result, Reason?, Lines?, Test? }` comes
    back (the purchase celebration or a refusal toast). Studio: `/shop grant <key>`
    runs the real grant path without Robux.
  - **One luck number:** `PlayerDataService.GetLuck(player)` = rebirth ×
    admin luck × `ShopConfig.GetLuckMultiplier` (Lucky ×1.5, Luck Potion
    ×2). Every roll and the Gacha Pad's `FusionConfig.FormatOdds` use it,
    so the displayed odds change while a boost runs.
  - **Income inputs added:** `PassMultiplier` (2× Cash × VIP ×1.25),
    `BoostMultiplier` (a Quick Boost / Boost: ×2), `OverclockMultiplier`
    (the Server Overclock: ×2 for everyone here), all inside
    `TycoonConfig.GetIncomeMultiplier`; `GetIncomeBreakdown` feeds the HUD
    pill's tap breakdown. `GetIncomeInputs(player, baseOnly)` drops the
    timed ones: offline earnings and cash packs use base income.
  - **Timed effects** are saved as REMAINING seconds (`PlayerData.Boosts =
    { Income, Luck }`, banked up to 3 h) and tick only in game
    (MonetizationService, 1 s); the client counts down from the snapshot
    (`TycoonController.GetBoostSecondsLeft`). The Server Overclock is
    session-only: workspace `OverclockUntil` / `OverclockBy` (`ShopState`),
    up to 60 min, with a server banner (`ShopAnnouncement`).
  - **+2 Pedestals:** `PlotLayout` spots 5–6 (a second row at z −10, x
    ±11.5). Every lab builds all 6; without the pass 5–6 are a dim plinth
    (`LockedPedestalTransparency`) with an owner-only "🔒 +2 PEDESTALS"
    label whose prompt reads "Unlock" and asks for the pass (the one
    in-world sell, on the owner's own tap). ItemService refuses them
    (`PedestalLocked`); `GetDisplayedItems` counts them only with the pass.
  - **Safe Fusion:** tokens (`PlayerData.SafeFusionTokens`); the Fuse
    panel's "🛡 Safe Fusion (3)" toggle (only with tokens, off by default,
    disarms after each fusion) sends `RequestFusion { Safe = true }`; the
    token is spent on that fusion, and a fail keeps every orb. **Never**
    offered on the fail card.
  - **Auto-Fuse:** the pass + `Settings.AutoFuse` (Fuse panel toggle);
    after a pull (`TycoonService.OnPull`) FusionService runs Fuse All with
    the same rules and sends `FuseAllResult { Auto = true }`.
  - **VIP:** a gold "👑 VIP" head tag, `[VIP]` chat prefix
    (`TextChatService.OnIncomingMessage`, Player attribute `VIP`), the gold
    sign border and wall trims (`PlotKit.ApplyLabLook`). **Neon Pink
    Lab** (`LabStyle` pass or the Starter Pack's cosmetic): pink wall/sign
    strips and pink cash balls (plot attribute `LabStyle`). Looks only.
  - **Shop UI:** the HUD's gold "🛒 SHOP" button (left, above the LOCK
    chip; wiggles every 20 s; red SALE tag only while a real sale is live;
    timed-effect pills beside it) opens `UI/ShopPanel`: **one scrolling
    page** (Shop 2). Sticky header + a sticky chip bar (sideways-scrolling)
    of `ShopConfig.Sections`: ⭐ Featured (one banner with a shine sweep:
    Starter Pack until bought, then the live sale, then the best value),
    🎟 Passes (big cards; an owned pass is a grey "OWNED ✓" and sorts
    last), ⚡ Boosts (BoostSale replaces Boost while live; "+1 h · you have
    0:42" from the real bank), 💰 Cash (what you'd get right now; "BEST
    VALUE" = most $ per Robux, `ShopConfig.GetBestValueKey`, live prices
    only, else no tag), 🍀 Luck, 🛡 Safe ("SAVE N%" live); empty sections and
    their chips are left out; the honest footer. A chip tweens the scroll
    (never filters); the chip of the section on screen is green. Tiles 4
    per row (2 on phones / under 560 px), the section's colour, a green
    buy button with the live price, hover 1.03, press bounce. Icons: the
    store page's `IconImageAssetId` (`ShopPrices.GetIcon`, same cached
    `GetProductInfo`), else the emoji in a circle; art in
    `marketing/shop_icons/<Key>.png` (never uploaded from code). No fake
    ribbons: no "POPULAR", no hard-coded "BEST VALUE". The offer card's
    "See all in the shop ›" opens it at Cash / Boosts
    (`ShopController.OpenShop`). Shop 3 look: each section its own vivid
    gradient (Passes blue, Boosts orange, Cash green, Luck teal, Safe
    indigo, Deal pink), 120 px icons on 272 px tiles, hover 1.04 + a white
    glow stroke, a coloured pill behind each section icon, a header shine;
    "NEW!" only within `ShopConfig.NewForDays` (7) of an item's
    `AddedUtcDay`. No server-wide "X bought Y" messages.
  - **Purchase celebration** (`UI/PurchaseCelebration`, replaces the THANK
    YOU card): on `ShopPurchased` Granted, client-side: dim + rays + glow +
    ~60 confetti + RevealMajor, the store icon pops in (260 / 180 px),
    "THANK YOU!" + the name, then each of the server's structured
    `Effects` in turn (Cash: count-up + 15 coins into the HUD counter;
    Boost / Luck / Overclock: the time flies into its HUD pill, $/s counts
    up if it just switched on; Pass: "✓ ACTIVE" stamp + its live change;
    Tokens: shields drop into the count). Skippable after 0.6 s; AWESOME!
    closes. HUD hooks come in through `PurchaseCelebration.SetHud`.
  - **Rotating deals** (`DealConfig`, `DealState`): bundles sold as their
    own products (`Deal = true`, `Parts`: DealPowerHour / DealFusionKit /
    DealRichLab), one per 6-hour UTC slot, deterministic from the slot
    start (`EventConfig.Hash32`; each slot steps 1..n-1 from the last, so
    no back-to-back repeat). Shown only while the LIVE saving is ≥ 15%
    (`ShopController.GetDeal`), never to restricted players. The server
    refuses a non-current deal (`DealOver`; a receipt is honoured 10 min
    after a prompt made inside the slot) and grants its parts through
    their own grants. Shop: a 🔥 DEAL banner + chip first ("normally
    ~~128~~ · now 99 (−23%)", "New deal in 3:12:05"); HUD: a 🔥 badge under
    SHOP / GIFTS on its own line, desktop and phone (on a phone it heads
    the left-column status stack, "next in" and the timed pills under it,
    never toward the centre; pulses on a new slot, opens the shop at the
    deal); a "New deal!" side card once per deal under the contextual
    offer's guards and shared 5-min limit, never while carrying or being
    stolen from. Once per deal is saved: `PlayerData.DealPopupSlot` (the
    slot start, sanitised in `reconcile`, snapshot `Shop.DealPopupSlot`),
    set by remote `MarkDealPopup { Slot }` (C→S, current slot only), so a
    rejoin in the same slot never shows it again. Analytics DealShown /
    DealOpened / DealDismissed. Studio: `/deal slot <offsetHours>`
    (Workspace `DealClockOffset`), `/deal pop` (bypasses EVERY guard and
    the saving / policy gate, not saved; an Id 0 deal shows "TEST").
  - **Contextual offer** (`ShopController.OfferForShortfall`): ONLY when
    the player taps something they can't afford (upgrade / MAX, pull /
    ×10, Multiplier Pad, Rebirth). One non-modal side card: what they
    tapped, "Need $X more?", the smallest covering cash pack (or the
    Boost), "Not now", the price, and "or wait ~4 min with your income".
    At most once per 5 min; never in a first session's first 10 min;
    never over another card (`UIKit.IsOverlayOpen`); never within 60 s of
    a failed fusion, a theft or a caught steal.
  - **Starter Pack:** a one-time product; a dismissible side card once, 3
    min into the player's 2nd session (`PlayerData.Sessions`); after that
    only the shop's featured slot, until bought.
  - **Real sales** (`ShopConfig.Sales`): a separate, cheaper developer
    product (`BoostSale`) sellable ONLY while its window is live
    (`ShopState`; "AdminAbuse" = an admin's panel event / luck via the
    `AdminAbuseUntil` attribute, or the scheduled Admin Abuse hour). The
    tile and banner show "normally ~~79~~ R$ · today 49 R$ (−38%)" and the
    real end time. The server refuses it outside the window (a receipt is
    honoured for 10 min after a prompt it made inside the window).
  - Balance (`tools/econ_sim.py 30 12 --monetization`, median of 30 seeds,
    12 h, no events; prices and the base economy unchanged): Rebirth 1 at
    1:04:17 free / 0:28:44 with 2× Cash + VIP + Extra Pedestals (45%) /
    0:22:41 with those plus a Boost every hour (35%); Rebirth 3 at 2:45:59
    / 1:20:28 (48%) / 1:01:35 (37%); rebirths after 12 h 7 / 8 / 10.
    Harris decides any change from that table; re-run it after touching a
    shop multiplier (keep the sim's shop block in sync with ShopConfig).
