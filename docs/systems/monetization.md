# Monetization: shop, passes, products, deals, offers

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Monetization** (`MonetizationService`, every item and number in
  `ShopConfig`). **The deals must be real.** The "never" list: no fake
  discounts or permanent "sales", no countdowns that aren't real, no
  pressure copy ("LAST CHANCE"), no purchase prompt after a loss, nothing
  sold that protects a lab from theft or helps a thief (an item's steal
  value is the item itself), and **no Robux price typed into the UI**.
  **Earned or free, never sold:** weapons and power-ups, and Auto pull (the
  Gacha card's T key = Auto ×10, `GachaConfig.AutoPull*`): a convenience every
  player gets, not a pass, not a product.
  - **Owned passes show up (the 🎟 PASSES circle):** `UI/EffectsTray` has ONE
    circle for every owned gamepass (the phone tray is one row), only when
    `TycoonController.OwnsPass` is true for 1+ (the live `OwnedPasses` of the
    snapshot; a purchase mid-session pops it in). `LayoutOrder 1`, just left
    of Friends; Blue gradient (the shop's Passes colour); permanent, so no
    timer ring; a count badge at 2+; the label under it is the cash
    multiplier the owned passes give (`ShopConfig.GetPassIncomeMultiplier`,
    `x2.5` for 2x Cash + VIP) or `ON` when none touch cash. Its tooltip (the
    tray's usual rules; a tap pins it) is bold "Your passes" and one line per
    owned pass, names and numbers from `ShopConfig`: "💰 2x Cash: x2 income",
    "👑 VIP: x1.25 income", "🍀 Lucky: x1.5 luck", "⚙ Auto-Fuse: on",
    "🏛 +2 Pedestals: +2", "🎨 Neon Pink Lab: on". No purchase prompt, no
    "buy" circle for a player with none. `/selftest` section 13b stubs the
    owned set (`EffectsTray.SetTestOwned`).
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
    chip; wiggles every 20 s; red SALE tag only while a real sale is live)
    opens `UI/ShopPanel`: **one scrolling
    page** (Shop 2). Sticky header + a sticky chip bar (sideways-scrolling)
    of `ShopConfig.Sections`: ⭐ Featured (one banner: the Starter Pack
    until bought (then it stays in place, dimmed, a grey "OWNED ✓", so the
    page does not jump), a live sale in between, else the best value; only
    its buy button gets a gentle shine sweep, every 5 s),
    🎟 Passes (big cards; an owned pass is a grey "OWNED ✓" and sorts
    last), ⚡ Boosts (BoostSale replaces Boost while live; "+1 h · you have
    0:42" from the real bank), 💰 Cash (what you'd get right now; "BEST
    VALUE" = most $ per Robux, `ShopConfig.GetBestValueKey`, live prices
    only, else no tag), 🍀 Luck, 🛡 Safe ("SAVE N%" live); empty sections and
    their chips are left out; the honest footer. A chip tweens the scroll
    (never filters); the chip of the section on screen is green. A blank tail after the footer is sized so the LAST chip can put its header at the top too. Tiles 4
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
  - **Shop 4 / Polish 11 "premium" pass** (`UI/ShopPanel`, tokens
    `Colors.ShopHighlight / ShopRay / ShopArtWell / ShopScrollbar`): every
    card has a lighter-top vertical gradient, a 1 px highlight line along
    its top edge, a 3 px ink outline and a 6 px drop shadow (no flat
    fills). Every item sits in an **art box** (120 px on banners, 96 on
    tiles and pass cards): the live product icon (emoji fallback) over a
    three-disc radial glow in the card's colour; slowly turning rays
    behind the art on the Featured and Deal banners only. **Three text
    sizes per card**: the name 30 (Display, 3 px ink stroke; a long one
    shrinks to fit), lines 16 (BodyHeavy, 1.5 px stroke) and small labels
    13 (pills: ONE TIME ONLY, the deal timer, NEW!, BEST VALUE). Nothing
    smaller than 13 (`/selftest` reads every shop text from the tree).
    Buy button 160 × 64, the live price at 28 px, a 0.12 s press-in. A
    bought pass or one-time item turns its button into grey "OWNED ✓" and
    the whole card dims to 70% in place. Section headers: coloured icon
    chip + name + a 2 px rule with 24 px above; a thin scrollbar and 12 px
    padding all round. Never-list unchanged: live prices only, real timers
    only, no urgency words, no flashing; `PolicyRestricted` items stay
    hidden from restricted players.
  - **Every bundle shows its contents** (any item with `Parts`: the Starter
    Pack, every deal, Safe Fusion x5): the ⭐ Featured banner, the 🔥 Deal
    banner, a grid tile and the Starter / "New deal!" side cards all draw
    one `DealParts` tile per DISTINCT part and one ✓ YOU GET line per part
    (`Plain` text) plus "Worth R$ N if bought separately" (live
    `ShopPrices`; the old "if bought one by one" is gone) and the live
    SAVE %. A cash part's line carries the amount it pays THIS player right
    now ("A pile of cash (+$1.2M)": `ShopController` installs
    `DealParts.SetPlainResolver`; the same formula the grant uses, and the
    banner re-reads it every second). `/selftest` walks the shop tree and
    the side cards and counts tiles and lines per container.
  - **Purchase celebration** (`UI/PurchaseCelebration`, replaces the THANK
    YOU card): on `ShopPurchased` Granted, client-side: dim + rays + glow +
    ~60 confetti + RevealMajor, the store icon pops in (260 / 180 px),
    "THANK YOU!" + the name, then each of the server's structured
    `Effects` in turn (Cash: count-up + 15 coins into the HUD counter;
    Boost / Luck / Overclock: the time flies into its effects-tray icon, $/s counts
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
    their own grants. Shop: a 🔥 DEAL banner + chip first that says
    **what's inside** (Polish 10, `UI/DealParts`): "🔥 DEAL · ends in 3:49:28",
    one tile per DISTINCT part (72 px on side cards, 64 on banners; the part product's live icon, else its
    emoji; its amount on the tile, `ShopConfig.Tile`; its name under it; a
    "×3" badge when the same part repeats), a "YOU GET:" list with one ✓
    line per part from its **`Plain`** text (`ShopConfig` / `QuestConfig.
    PowerUps`: one line a 7-year-old understands, asserted non-empty by
    `/selftest`) and "Worth R$ 128 if bought separately"
    (`ShopController.GetWorthLine`: the parts' LIVE `ShopPrices` sum, hidden
    until every price is in, never typed). The Starter Pack and "New deal!"
    side cards (`ShopCards`, `SideCard.Parts`) use the same tiles + YOU GET
    list; on a phone with no room the YOU GET list drops out and the tiles
    stay. No urgency words. HUD: the **deal tile**
    (`HudController.buildDealBadge`) under SHOP / GIFTS on its own line,
    desktop and phone (on a phone it heads the left-column status stack,
    "next in" under it, never toward the centre). A 92 px
    (phone 56, the same card size as the utility grid) Deal-pink square, 16 px corners, 3 px white stroke: the deal
    product's LIVE icon (`ShopPrices.GetIcon` = the Creator Hub
    `IconImageAssetId`; none yet → the deal's emoji; never uploaded from
    code; 66% of the tile so a dark strip of the parts' glyphs, "⚡ 🧪", fits
    along the bottom edge), slow rays behind it (6 bars = 12 rays, 360° per 12 s,
    `UITheme.Colors.DealRay` at 0.6), a gold `−{Save}%` ribbon across the
    top-right (`DEAL` when the saving is unknown; white text + ink stroke), a
    white shine sweep (0.5 s every 6 s) and a dark timer pill under it
    (`🔥 h:mm:ss`, the real `SecondsLeft`). The whole tile + timer is one tap
    (`ShopPanel.Open("Deal")`, `UIKit.SelectFeedback`); a new slot pulses it
    once and plays the shine at once. Idle motion is ONLY the rays and the
    shine: no flashing, no red or urgent timer, no "last chance" copy and no
    extra effect in the final hour; no Robux price on the tile. Hidden for
    policy-restricted players (no `GetDeal`), during the tutorial, while a
    heist has your hands full (`ShopController.IsDealTileQuiet`: you carry, or
    yours is carried off) and for `AfterLossQuietSeconds` after a loss; a "New deal!" side card once per deal under the contextual
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
