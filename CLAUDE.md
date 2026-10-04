# FusionTycoon

Roblox tycoon game. Rojo project — source of truth is the filesystem under
`src/`, synced into Studio. Toolchain is managed by Aftman (`aftman.toml`).

## Commands

```sh
rojo serve default.project.json     # live-sync into Studio
rojo build -o build.rbxl default.project.json

# Type checking (requires `aftman install` first — needs an interactive
# trust prompt the first time luau-lsp is fetched):
rojo sourcemap default.project.json -o sourcemap.json
curl -sL https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau -o globalTypes.d.luau
luau-lsp analyze --sourcemap=sourcemap.json --defs=globalTypes.d.luau src/
```

**`rojo build` does not validate Luau.** Verified: it exits 0 on outright
broken syntax and embeds it verbatim. It checks project/file structure only.
A green `rojo build` is *not* evidence that code compiles — use `luau-lsp
analyze` for that.

## Game loop & economy (read before balancing)

Claim plot (Basic Generator starts at LV 1) → upgrade Generators (on the
factory line along the left wall or in the UPGRADES panel; both fire
`RequestUpgrade`; the panel's MAX ×N / MAX ALL fire `RequestUpgradeMax`) →
Gacha Pad pulls → fuse 2–6 same-tier items in the Fuse panel at your plot's
Fusion Machine (more = better chance, `FusionConfig.SuccessChanceByCount`;
success = next tier, fail = keep your best input) → display the best
4 items on pedestals for passive income → Multiplier Pad multiplies ALL income
→ Rebirth (Portal, back-right corner) → hunt Secrets, mutations and the Index.

Rebirth (`RebirthService`, numbers in `RebirthConfig`) costs cash
(`RebirthConfig.GetCost`: $15M ×3.2 each time); cash going to 0 pays it. It
resets cash, generators (Basic back to LV 1), the Multiplier Pad and the
gacha price; it keeps every item, the pedestals, the Index, goals and the
rebirth count, and gives
income ×(1 + 0.5 n) and luck ×(1 + 0.05 n) (luck raises Legendary/Mythic
gacha odds via `FusionConfig.GetGachaRates`, and every mutation chance).

Items (Depth 1): six tiers up to **Secret** (gacha 0.002%, or fuse 2 Mythics
at 8% once you have Rebirth 1 — `FusionConfig.CanFuseTierFor`). Any pull or
successful fusion can roll a **mutation** (`MutationConfig`, ranked by
multiplier: Golden ×2, Charged ×3, Diamond ×5, Void ×8, Rainbow ×12,
Celestial ×20; Charged / Void / Celestial are **event-only**, 0 normal
chance, `MutationConfig.IsEventOnly`). Fusion rules: a success keeps the *lowest*
mutation among all inputs (so every input must share it), then may roll a
better one; a fail keeps the best input untouched (same Uid) and removes
the rest; Fuse All (pairs, Common–Epic) never touches mutated items.
`FusionConfig.PredictMutation(inputs)` (the lowest input mutation) is what
FusionService carries and what the Fuse panel predicts **before** FUSE
(`GetMutationMix`): every orb the same mutation → "✨ Keeps GOLDEN ×2, might
roll better"; mixed → a red warning box naming how many lower orbs are in
and what is lost ("⚠ 1 plain orb mixed in: the Epic comes out plain, not
Golden…"), those orbs ringed red; all plain → no line. AUTO-FILL only adds
the first orb's mutation (an empty chamber fills plain orbs). The fusion
result carries `MutationSource = "Kept" | "Rolled"`: the big card shows
the pill and "GOLDEN kept" / "GOLDEN rolled!" (without a big card, your own
"FUSION SUCCESS!" banner says it);
the fail card says "Kept your Golden Rare (…)". The five count chips sit in
**one row** (non-wrapping list, scale widths, 6 px gaps; the % TextScaled
with a max of 18). The **Index** (`IndexConfig`, 119 entries =
17 items × 7 variants, built from `MutationConfig.Order`) pays +1% income per entry and +5% per full tier page, and
survives rebirths. Every odds display goes through `FusionConfig.FormatOdds`
(the same functions the rolls use).

- All economy numbers live in `TycoonConfig.lua` (costs, pedestal income,
  multiplier levels, gacha price curve) and `FusionConfig.lua` (fusion success
  odds, gacha drop rates). They were tuned with a greedy-player simulation
  of a brand-new save; the target milestones are in TycoonConfig's header.
  Re-run `tools/econ_sim.py` after changing any economy number; keep its
  tunables in sync with TycoonConfig/FusionConfig.
- Passive income has ONE formula: `TycoonConfig.GetPassiveCashPerSecond`,
  used by the server payout tick and the client HUD. It is all income: the
  factory line's cash balls are a client-side picture of it and never pay.
  It takes one `IncomeInputs` table, built only by
  `PlayerDataService.GetIncomeInputs` (server) and
  `TycoonController.GetIncomeInputs` (client).
- Every income display uses `TycoonConfig.GetIncomeMultiplier` (pad ×
  rebirth × Index); `GetCashMultiplierValue` is the pad only. An item's
  $/s is `TycoonConfig.GetItemCashPerSecond(tier, mutation)`.
- Every service syncs the client with `PlayerDataService.SyncTycoon(player)`.
  Do not hand-build SyncTycoon payloads.
- Each plot builds its own Fusion Machine (`FusionMachineService.Build`,
  called from `TycoonService.createPlotForPlayer`).
- **Settings** (`SettingsConfig`, saved as `PlayerData.Settings`, sent as
  `Settings` in the snapshot): `RevealRule = { [tier] = "Never" | "Golden"
  | "Diamond" | "Rainbow" | "Always" }` for Common → Mythic; "Golden" =
  Golden or any higher-ranked mutation (`MutationConfig.GetRank`). The
  defaults are **derived** from `FusionConfig.IsMajorReveal` (a
  `MajorRevealTiers` tier → Always, else the lowest threshold reaching
  `MajorRevealMutationRank`, i.e. Diamond); old saves get them. **Secret and
  the event-only mutations always show** (`SettingsConfig.ShowsBigCard`).
  Remote `SetSetting` (C→S `{ Key = "RevealRule", Tier, Value }`,
  tier/value whitelisted; a coalesced sync 0.25 s later echoes it).
  `ResultController.ShowsBigCardFor` reads the rule for single pulls,
  BEST OF 10 and fusion successes (fail cards and Fuse All unchanged); a
  skipped card pops a **small line** above the bottom bar for 2.5 s (orb
  dot, "+ Golden Plasma Orb" in the mutation colour, the tier, "+$X/s";
  max 3, older ones fade) — except your own fusions: their top "FUSION
  SUCCESS!" banner already shows the result, so they get no line
  (`ResultController.FusionBannerShows` decides both; other players still
  see the server-wide banner). The client applies a change at once
  (`TycoonController.SetRevealRule`, kept until the snapshot echoes it).
  UI: the **⚙** 56 px button after INDEX opens `UI/SettingsPanel` (620
  wide, one scrolling list of sections: "Big reveal card" (one 5-segment
  row per tier + a locked Secret row) and "Sound effects" (see Sounds)).
- Saves: a failed DataStore load kicks the player in live games (never
  overwrites the real save); in Studio it plays on a blank profile that is
  never saved. PedestalDisplays are stored with string keys on disk.
- **Offline earnings** (`OfflineConfig`): away time earns 25% of passive
  income per second, for at most 4 h, and nothing under 2 min.
  - `PlayerData.LastOnline` (`os.time()`) is written on every save. On load,
    `PlayerDataService` computes the payout from the income the player left
    with, moves `LastOnline` to now (and saves), and holds the payout as
    session-only pending earnings. The snapshot carries `PendingOffline`
    and `AwaySeconds`.
  - `OfflineService` pays it once on `ClaimOffline` (the client never sends
    an amount). If it's unclaimed, the first sync 30 s after load pays it,
    and leaving pays it on PlayerRemoving, so it's never lost.
  - Client: ResultController's welcome-back card (COLLECT; a hidden
    COLLECT ×2 slot for the monetization pass).
- Studio chat commands (DebugService): `/cash <amount>`, `/resetmultiplier`,
  `/rebirthready` (sets cash to the next rebirth's price),
  `/rebirths <n>`, `/give <itemId> [mutation]`, `/offline <minutes>`
  (pending offline earnings as if away that long, then re-sync: the only
  way to test the welcome-back card, since Studio profiles never save),
  `/shield <s>` (0 drops it), `/heistcd 0` (clears your thief cooldown),
  `/stealable` (toggles your lab stealable at Rebirth 0, for heist tests),
  `/tips reset` (clears your seen one-time tips),
  `/event <id> [minutes]` (forces an event: GoldenRain, PowerSurge,
  MeteorShower, RainbowStorm, Night, VoidMoon), `/event off`,
  `/shop grant <key>` (any ShopConfig key, the real grant path, no Robux),
  `/eventclock <offsetMinutes>` (shifts the event clock to walk the
  schedule; clients read the same offset), `/eventmut
  <charged|void|celestial>` (a random Epic with that event-only mutation
  through the real reward path: the reveal card + the banner),
  `/wipe` (fails your active steals first).
- **Events** (`EventService`, every number in `EventConfig`): lab weather
  on a shared UTC clock. **The schedule is deterministic from the UTC slot
  time, never random at runtime:** `EventConfig.GetEventForSlot(slotStart)`
  draws from a **lowbias32 hash of the slot start** (bit32 only; two draws
  discarded), so every server and client computes the same lineup with no
  messaging. Not `Random.new(slotStart)`: slots 900 s apart gave correlated
  first draws (three POWER SURGEs in a row). `luau
  tools/event_schedule_check.luau` runs the real EventConfig over 10,000
  slots (shares within 0.3 pts, repeats at each weather's own share). hh:00 Night 10 min (15% Void Moon);
  hh:15/:30/:45 one weather by weight (Golden Rain 40 / Power Surge 35 /
  Meteor Shower 20 / Rainbow Storm 5). An override (`/event`, admin) replaces
  the scheduled event until it ends, then the clock resumes.
  - EventService publishes workspace attributes `EventId`, `EventEndsAt`
    (server time), `EventStrength` (+ `EventClockOffset`, `AdminLuck`,
    `AdminLuckUntil`, `NextAdminAbuse`). Clients and leaf services read
    them through `Shared/Modules/EventState`; the effect formulas are pure
    functions in EventConfig, so a roll and its display always agree.
  - **Effect hooks** (no globals): `EventService.GetMutationOddsMultiplier
    (mutation, source)`, `GetFusionSuccessBonus()`,
    `GetGeneratorMultiplier()`, `GetFusionEventMutation()`. Wired as a
    multipliers table into `MutationConfig.Roll` / `GetChance` (shared
    config never requires EventService), a bonus into
    `FusionConfig.GetFusionChance`, and `IncomeInputs.EventGeneratorMultiplier`
    (generator income only). `FusionConfig.FormatOdds(luck, event)` shows the
    boosted numbers; every event change re-syncs players so labels refresh.
  - Strength ×1–×3 (admin) is clamped: coin ≤ 15 s of income, generators
    ≤ ×3, mutation odds ≤ ×15.
  - `tools/econ_sim.py <seeds> <hours> --events` runs the clock and compares
    with the same seeds without it. **Target: events speed Rebirth 1–3 by
    ≤ 15%.** The first spec numbers gave 20–27% (Void Moon the biggest
    part, coins minor), so they were cut: Void Moon 30% → 15% of nights,
    fusion bonus +10 → +5 points, Void roll 10% → 5%, coin 5 s → 3 s of
    income, Surge ×1.5 → ×1.25. Events 2 added BIG + street coins
    (modelled: 1 in 6 street coins per player) and lowered the coin
    FREQUENCY, not the size: lab coins every 4 → 10 s, street coins every
    6 → 15 s. Now +10.4% / +14.4% / +10.3% (30 seeds, 12 h). Any change to
    an event number: re-run and keep it ≤ 15%.
  - Rewards are server-side (EventService):
    - **Golden Rain:** lab coins (owner-only, touch + distance check, 3 s of
      income; 1 in `BigCoinChance` (8) is a **BIG** coin worth 20 s) and
      **street coins** (in `MeteorBounds`, max 8, anyone grabs, pays the
      GRABBER 6 s). Value is seconds of income on purpose (never cash).
      Per-player tally: Player attribute `GoldenRainTally` (chip "💰 +$X
      this rain", the end toast).
    - **Power Surge:** generators ×1.25; lightning every 20 s on a target
      picked by lab, then pedestal, marked `LightningWarningSeconds` (3)
      early (pedestal attribute `LightningTarget` + EventFx StrikeWarning);
      25% of a plain displayed item turns Charged (carried items skipped;
      inventory, Index, pedestal visuals/labels, SyncInventory).
    - **Meteor Shower:** craters on the street (`StreetLayout.MeteorBounds`;
      first finished hold wins a core: Epic 60 / Legendary 30 / Mythic 9 /
      Secret 1, 15% Celestial; a "Hold E · free item" pill).
    - **Void Moon:** fusion +5 points, 5% Void replacing the normal roll.
  - **Cleanup:** every object an event makes lives in
    `Workspace.EventObjects.<EventId>` (EventService builds the folders at
    Init): server coins, craters and prompts; each client's own FX (sky,
    moon, lightning, meteors, rings, chips, pops, station pills). Any end
    (timeout, `/event off`, admin, an override) is one `ClearAllChildren`
    on each side; a meteor still falling leaves no crater.
  - **Event-only mutations** (Charged / Void / Celestial) from a pull,
    fusion, strike, core or `/eventmut` get the **reveal card**
    (ResultController: "EVENT-ONLY MUTATION", the giant word, how you got
    it, "Index +1 · Void 3 / 17") and a SERVER banner at any tier
    (`EventService.AnnounceEventMutation`, RareFusionAnnouncement Verb
    "event").
  - Visuals are client-side (`EventController`): start banner (straight away, 2.5 s, no countdown),
    end toast, sky from a captured Lighting baseline restored exactly
    (never raise a light: Night just darkens), band flicker through
    `LocalTransparencyModifier`, EventFx cues (strike warnings, lightning +
    CHARGED!/MISSED, meteors + ☄ INCOMING rings, coin pops: full
    `NumberFormat.Money`, BIG in gold), "⚡ ×1.25" chips over generators
    (`BillboardKit.Chip`), faster/brighter factory balls, the two street
    Event Boards (`StreetLayout.EventBoard`, built by WorldService).
  - **Every event explains itself:** the top-centre HUD chip opens the
    **info card** (`UI/EventInfoCard`, copy from `EventConfig.GetInfo`,
    built from the config numbers; `EventConfig.Blurbs` = the first "what to
    do" sentence). It **never opens itself**: a small ⓘ sits inside the chip's
    right end, and the first time a player sees each event type the chip
    itself pulses (UIScale bounce + a gold glow behind it) until they tap
    it once (that tap marks Tips `event_<EventId>`, TipConfig). A tap
    anywhere on the chip opens it; ✕, a tap outside it or the event ending closes it.
    Between events it explains the next one. **Event arrows:**
    `GoalMarkerController.SetEventOverride` (heist > event > goal): Rainbow
    Storm → your Gacha Pad (then the machine once you're on it), Night /
    Void Moon → your machine, Meteor Shower → the nearest crater, Golden
    Rain → the nearest street coin. Station pills: "🌈 MUTATIONS ×5 · PULL
    NOW" on your pad, "🌙 FUSE NOW" on your machine.
- **Odds board** (FusionMachineService + `BillboardKit.OddsSurface`): 9 × 6
  studs at 60 px/stud, a real table (one rounded cell per %, 100% teal),
  no mutation line (the pad and Index have it). `SetOddsChances(gui, rows,
  { Rebirths, Boosted })` on every sync: the Mythic → Secret row reads "R1"
  until the owner has Rebirth 1, a Void Moon turns every cell purple with
  the boosted number. The Fuse panel's chips are one two-line chip per
  count, the chamber's count highlighted.
- **Index book** (`UI/IndexPanel`, 720 wide): tier tabs (name in the tier
  colour, "8 / 21", a thin bar, "+5% at 21" on the selected one); column
  headings in the mutation colours, event-only ones with ⚡ 🌙 ☄ (not
  tappable); one row card per item (name, "3 / 7 · $/s", seven orb cells:
  found = `UIKit.TierOrb` + the mutation's look, Rainbow hue-cycling only
  while open; missing = a dark dashed well with "?" or the event icon). A
  7/7 row gets a gold stroke + glow and "★ COMPLETE 7/7". Tapping an orb
  fills the bottom **info strip** ("<Item> · <Variant ×N>", how to get it,
  found / not found yet). Only the selected tier is built; it rebuilds on
  a tab change, an Index change or a phone switch (orbs 54 → 40 px, the
  cell stays the ≥ 44 px target). No check marks or clocks.
- **MAX upgrades:** `RequestUpgradeMax` (C→S `{ GeneratorId }` or
  `{ All = true }`) loops TycoonService's `buyOneLevel`, the same path as
  `RequestUpgrade` (cost, unlocks, cap, Carrying), up to
  `TycoonConfig.MaxUpgradeSteps` (500); All buys the cheapest available
  level each step (`GetCheapestUpgrade`, unlocks re-checked). One sync and
  one `UpgradeMaxResult { Levels, Spent, PerGenerator, NewLevels }`;
  nothing is spent if no level was bought. The panel's "MAX ×N / $X",
  "MAX / need $X" and "⚡ MAX ALL · $X" come from
  `TycoonConfig.GetMaxAffordable(generator, level, cash)` and
  `GetMaxAllPlan(levels, cash)`, so labels and server agree. Toast "+9
  levels · Core Engine LV 15" / "+23 levels across 3 generators", one
  bump per changed generator; the panel refreshes at most 4×/s.
- **Sounds** (`SoundConfig` slots + `SoundKit.Play(slot, parent?)`): every
  sound goes through a slot; an empty Id is silent, a failed Id warns once
  (client `SoundKit.Preload` at boot). Every slot holds a Roblox-owned
  (creator id 1) Creator Store SFX, no two alike. **Volume:**
  `PlayerData.Settings.SfxVolume` (0–1, default 0.8, server-clamped) and
  `SfxMuted`, via `SetSetting { Key = "SfxVolume" | "SfxMuted", Value }`;
  every sound plays through the `SFX` SoundGroup, whose Volume each client
  sets locally (`SoundKit.SetVolume`, from TycoonController), so it covers
  server-played sounds too. SettingsPanel's "Sound effects" row: slider
  (saves on release) + mute toggle. **Play cap:** at most
  `SoundConfig.MaxConcurrentPerSlot` (6) of one slot at once; extra plays
  are dropped. Per slot: `SpeedJitter` (CoinPickup 0.95–1.1) and
  `RollOffMaxDistance` (Thunder 150, MeteorImpact 200 via
  `SoundKit.PlayAt`). No looping ambient sounds (the pedestal bell loop is
  gone). `docs/SOUNDS.md` lists every slot with its id and name.
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
  - **Receipts:** `ProcessReceipt` is idempotent: a PurchaseId already in
    `PlayerData.Receipts` (the last 200) → `PurchaseGranted`; else check
    (`refusal`) → grant (synchronous) → record → `PlayerDataService.
    SaveNowAsync` → `PurchaseGranted`. Not loaded, a refused item or a
    failed save → `NotProcessedYet`. Passes: `UserOwnsGamePassAsync` at
    join + `PromptGamePassPurchaseFinished` (session state, pushed into
    `PlayerDataService.SetShopSession`). Purchases start with remote
    `RequestShopPurchase { Key }`: the server re-checks (set up, policy,
    owned, one-time, sale window, something to double) and only then
    prompts; `ShopPurchased { Key, Result, Reason?, Lines?, Test? }` comes
    back (THANK YOU card or a refusal toast). Studio: `/shop grant <key>`
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
    timed-effect pills beside it) opens `UI/ShopPanel` (featured banner
    with a shine sweep: Starter Pack until bought, then the live sale,
    then the best value; tabs; 4 / 2 column tiles; cash tiles show what
    you'd get right now; the honest footer).
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
- **Admin Abuse** (`AdminService`, numbers in `AdminConfig`): admins are
  `AdminConfig.AdminUserIds` plus the place owner (creator, or the group's
  owner). `/admin` opens the panel by sending `AdminOpen` to admins only;
  the client never builds it otherwise. Every `AdminAction` is re-checked
  (non-admins get a SUSPICIOUS warn) and every arg whitelisted. Start event,
  end event, gift everyone (EventReward "🎁 ADMIN GIFT"), luck ×3 for 10
  min, broadcast (≤ 80 chars, `TextService:FilterStringAsync` broadcast
  string, dropped if filtering fails), set next Admin Abuse (DataStore
  `GlobalEvents` key `NextAdminAbuse`, UTC, read on start and every 5 min).
  "All servers" publishes `{ Action, Args, SenderUserId }` on
  MessagingService topic **`FT_Admin`**; every receiver re-checks the sender
  and re-validates. Every action is logged with `warn`.
- **Heist** (`HeistService`, every number in `HeistConfig`): from Rebirth 1,
  items **on pedestals** can be stolen by another Rebirth 1+ player;
  inventory items never are. Hold E 1.5 s on an enemy pedestal's
  `StealPrompt` (victim's shield down) → carry it home within 45 s at
  WalkSpeed 12. Delivered = the thief's root inside their own walls;
  saved = the owner within 5 studs; timeout, thief death, either side
  leaving, the victim's plot going, shutdown or `/wipe` = it goes back.
  Thief cooldown 60 s after any attempt (published as the Player attribute
  `HeistCooldownUntil`, server time; `/heistcd 0` clears it); a victim gets a 120 s auto-shield
  per loss and loses at most 3 per 10 min. **Fairness:** the owner within
  `OwnerBlockRadius` (6) of the pedestal when the hold completes guards it
  (rejected `Guarded`; pedestal attribute `GuardedByOwner`, the prompt
  reads "Owner is guarding"); no tag for `TagGraceSeconds` (2) after a grab
  (RUN! / "Catch them in 2…1…"); the owner runs at `OwnerChaseWalkSpeed`
  (18) while any of their items is carried. A catch plays client-side
  from the thief's `HeistOutcome` / `HeistReturnTo` attributes. While carrying: no pulls,
  fusing, upgrades, Multiplier Pad, rebirth, shield pad or second steal
  (Reason `Carrying`); the owner can't remove a carried item or rebirth
  (`BeingStolen` / `ItemBeingStolen`). A carried pedestal earns nothing.
  - **Transaction order (no duplication, no loss):** a grab only records
    the carry in HeistService and flags it (`PlayerDataService.SetItemCarried`
    / `SetCarrying`, pedestal attribute `BeingStolen`). Neither inventory
    changes until **delivery**, which is one synchronous block: clear the
    victim's pedestal, remove the item from the victim, `AddItem` the same
    item to the thief (new Uid), then syncs and `SaveNow` for both. Every
    other ending just drops the carry: the item never left. An item is in
    at most one carry and a thief in at most one.
  - **`PlayerDataService.OnRelease(callback)`** runs before a player's save
    on PlayerRemoving and for everyone before `saveAll` on BindToClose;
    HeistService fails that player's carries (either side) there.
  - **Shield / LOCK:** per player until a server time, published as the
    plot attribute `ShieldUntil`. Raised 60 s on claim, 120 s after a loss,
    and 60 s when the owner **LOCKs on purpose**: the one entry point is
    `HeistService.TryLock(player)`, rejected in order `Protected`,
    `Carrying`, `AlreadyLocked`, `Recharging` (+ seconds) or `TooFar` (root
    more than `LockConsole.PromptDistance` + `HeistConfig.LockReachSlack`
    = 10 studs, flat, from your own console: an exploit firing the prompt
    from afar is refused); success pays `ShieldRaises` (first_shield).
    **LOCK is console-only** (you have to run home): the **LOCK console**
    (`LockKit`, `PlotLayout.LOCK_CONSOLE`, built on claim; owner-only
    prompt "Lock lab" answered server-side via ProximityPromptService,
    owner-only "🔒 LOCK LAB" label) is the one way in; there is no lock
    remote. Rejections toast via `HeistEnded { Role = "Lock", Outcome =
    "Rejected" }`. The YOURS pad
    is decorative. After any shield ends LOCK recharges for
    `ShieldRearmSeconds` (20 s, plot attribute `ShieldRearmAt`); the claim
    and victim shields ignore it, `/shield 0` clears it. Clients read
    `ShieldUntil` / `ShieldRearmAt` / `Protected` through `ShieldState` for
    the console (pill, pink/teal/dim button, prompt on only when Ready) and
    the HUD **LOCK status chip**, which never locks: muted "🔓 UNLOCKED"
    (amber text) / teal "🛡 LOCKED · 42s" / muted "RECHARGING · 12s" / red
    pulsing "🚨 RUN TO LOCK!" (lock ready and a non-owner's root inside
    your walls). It is sized to its text (`AutomaticSize = X`, 44 px tall,
    14 px side padding), the "?" button 8 px to its right. Tapping it points the goal arrow
    at your console for 8 s ("Your LOCK button is just inside your gate";
    `HudController.SetLockChipHandler`, answered by HeistController). There
    is **no steal timer chip**: the cooldown shows on enemy pedestals'
    prompts ("Steal in 42s") and in the toast. While up, a
    0.25 s **eject loop** moves any non-owner whose root is inside the walls
    (`PlotLayout.IsInsidePlot`) to the street spawn in front of the gate.
    Owners under Rebirth 1 are **protected** (plot attribute `Protected`,
    the sign's teal PROTECTED pill): no StealPrompt, no eject needed.
  - **Teaching flow:** Rebirth-0 viewers see a locked "🔒 Steal / Unlocks at
    Rebirth 1" teaser on stealable enemy pedestals; the Rebirth 1 card and
    `RebirthConfig.Unlocks[1]` announce stealing; goals `first_shield`
    (LOCK, `ShieldRaises`, target `LockConsole`) then `first_steal`
    (deliveries, `TotalSteals`; marker target `NearestEnemyPedestal`); red
    hand markers over grabbable enemy pedestals. **GUARDED is visible:** a
    teal "🛡 GUARDED" chip over every guarded pedestal (every viewer) and,
    while an owner is home, a faint teal floor ring of `OwnerBlockRadius`
    round each of their filled pedestals (client-only SurfaceGui faces, no
    lights). **HOW TO HEIST** (`UI/HowToHeistPanel`, 640 × 480): four
    slides (GRAB, GUARD, CATCH, LOCK), each a live 3D scene
    (`UI/HeistScenes`: ViewportFrame + WorldModel with the real pedestal /
    orb, LockKit console, a wall with its gate gap, flat pink World.Shield
    panels since ForceField doesn't render in viewports; YOU = a stripped
    clone of your character, the thief a red R15 rig; your own Animate run
    / idle ids; labels are 2D pills projected through the scene camera;
    lighting from `UITheme.HeistScene`). Built on open, destroyed on close,
    only the visible slide ticks. Auto-opened once per account after the
    first-rebirth card, and from the HUD's "?" button.
  - **One-time tips:** `PlayerData.Tips` (saved set), ids whitelisted in
    `TipConfig` (`howToHeist`, `stealHowTo`, `intruder`, `guarded`,
    `catch`, `lockAfterLoss`), marked with remote `MarkTipSeen { Id }`,
    sent as `TipKeys` in the snapshot (`TycoonController.HasSeenTip` /
    `MarkTipSeen`). Tips are big 4 s toasts (`ToastController.Show(text,
    kind, { Big = true })`). `/tips reset` clears them.
  - Client: WorldLabelController sets each StealPrompt's local `Mode`
    (precedence Hidden > Locked > Cooldown > Guarded > Steal; Locked,
    Cooldown ("Steal in 42s") and Guarded are no-hold taps that only toast,
    since Roblox hides disabled prompts; red hand markers stay on during
    the cooldown); HeistController draws every carrier's orb (`PedestalVisuals.
    BuildCarryOrb`, attributes `Heist*` on the Player), the thief/victim
    banners, arrows (`GoalMarkerController.SetOverride`) and fades every
    plot's shield fence, drives your LOCK console and shows GUARDED;
    HudController shows the LOCK status chip and the "?" button.
- **Light caps.** Pedestal lights (`RarityVisuals`) stay at Brightness
  0.8–1.6 and Range 8–12, the orb light at `OrbLightBrightness` 1, all with
  `Shadows = false`. Four Mythics at the old 12 / 32 washed the lab floor
  out pink-white; the orbs carry the glow, not the floor.
- **No new `Highlight`s on world objects.** Roblox renders at most 31 per
  client, and 12 plots × 4 pedestals can reach 48 (outlines silently
  vanish). Pedestals mark "filled" with the cap lip glow instead.
- Runtime `Size` animation on world parts goes through `PartKit.Pulse` /
  `TweenSize` (a stored `BaseSize`, never the live size): reading the live
  size compounded the generator upgrade bump until it poked through walls.

## Layout

```
src/ReplicatedStorage/Shared/
    Config/      shared config tables (PlotLayout, StreetLayout — the street
                 and speed belts, TycoonConfig, FusionConfig, RebirthConfig —
                 rebirth requirement/income/luck, MutationConfig — Golden/
                 Diamond/Rainbow, IndexConfig — the collection book,
                 OfflineConfig — offline earnings rate/cap,
                 EventConfig — the event clock, effects and info-card copy,
                 SoundConfig — every sound slot, AdminConfig —
                 admins and the Admin Abuse panel,
                 HeistConfig — stealing and the lab shield,
                 GoalConfig — the ordered onboarding goals,
                 SettingsConfig — the player's reveal-card rules,
                 ShopConfig — every pass / product and shop number, …)
    Modules/     shared runtime modules: UITheme (every UI colour/font token
                 and the World part colours), BillboardKit (world labels and
                 SurfaceGuis), PartKit (part/cylinder helpers, FT_Hover
                 tagging), PlotKit (plot shell + sign gate), StationKit
                 (station pads + holograms), GeneratorKit (the five factory-line generators + their
                 states), FactoryKit (factory belt + collector, and the
                 ball path), PortalKit (the Rebirth Portal), PedestalVisuals,
                 SoundKit (every sound, by SoundConfig slot),
                 ShopPrices (live Robux prices), ShopState (Server
                 Overclock, real sale windows),
                 NumberFormat
    Network/     RemoteEvents.lua — single source of truth for remotes
    VFX/         SparkleEmitter, ImportedEffects, imported *.rbxm VFX assets
src/ServerScriptService/
    Bootstrap.server.lua   entry point; hands Services/ to ServiceManager
    ServiceManager.lua     loading + Init/Start lifecycle
    Services/              one ModuleScript per service (GoalService pays
                           and advances goals from PlayerDataService.OnSync;
                           WorldService builds ground, street, Event Boards
                           and FREE LAB placeholders; EventService runs the
                           event clock; AdminService runs Admin Abuse)
src/StarterPlayer/StarterPlayerScripts/
    Controllers/  client controllers (one per domain): HudController,
                  ToastController (error/neutral toasts), ResultController
                  (fusion/gacha result cards), AnnouncementController
                  (banners), WorldLabelController (hides owner-only labels,
                  and any label within 7 studs of the camera),
                  WorldAnimationController (FT_Hover spin/bob, client-only),
                  GoalMarkerController (points at the current goal, or
                  a heist override), HeistController (steal prompt, carried
                  orbs, heist banners, shield fences),
                  BeltController (client-only belt chevrons),
                  GeneratorController (world Buy/Upgrade prompts, upgrade
                  toast + bump), FactoryController (client-only cash balls
                  on every nearby factory line, collector pops),
                  EventController (event banners, sky, FX, HUD chip, Event
                  Boards), AdminController (admin panel + broadcasts)…
    Effects/      RevealEffects
    UI/           UIKit (Panel/Button/Pill/Badge/TierOrb/ProgressBar/
                  Shadow/PopIn/PopOut/Modal/MutationPill), UpgradesPanel,
                  ItemPickerUI, RebirthPanel, IndexPanel, FusePanel (2–6
                  orb fusion chamber + picker, opened by the machine prompt),
                  AdminPanel (built only on the server's AdminOpen),
                  SettingsPanel (the ⚙ button: reveal-card rules),
                  ShopPanel + ShopCards (the shop, the offer / Starter /
                  THANK YOU cards),
                  HowToHeistPanel + HeistScenes (the 3D heist clips),
                  EventInfoCard (what the HUD event chip opens)
```

### UI rules ("Fusion Lab" design — spec in `docs/UI_REDESIGN_PROMPT.md`)

- **All UI colours come from `UITheme`.** No `Color3.fromRGB`/`fromHex` in
  any UI file other than `UITheme.lua`; add a token instead. Fonts too
  (`UITheme.Fonts`). This covers server-built BillboardGuis (`BillboardKit`).
- Build screens from `UIKit` constructors. Panel/Button return
  `(body, holder)`: position/parent the holder (it also hosts the sibling
  `Shadow`), style the body. Restyle buttons with `UIKit.SetButton`.
- Every ScreenGui comes from `UIKit.Screen`, which adds the single mobile
  `UIScale` (0.8 under 500 px tall). Phone layouts react to
  `UIKit.LayoutChanged`. Keep the top-left 170×60 px clear (Roblox top bar)
  **after** that scale, and every tap target ≥ 44 px.
- Money/multipliers always go through `NumberFormat.Money`/`.Multiplier`.
- World labels: `AlwaysOnTop = false`, `LightInfluence = 0`, a MaxDistance.
  Owner-only labels set the `OwnerOnly` attribute; don't toggle them per
  player on the server.
- Studio checklist for UI changes: `docs/UI_TEST.md`.

## Architecture

### Service Lifecycle Rules

- All services in `src/ServerScriptService/Services/` must follow
  `ServiceTemplate.lua`.
- `ServiceManager.lua` executes `:Init()` sequentially across services, then
  `:Start()`.
- Cross-service requires must occur inside `:Start()`, **never** at top-level
  module load.
- Maintain static dot-notation for public APIs (`Service.Method(p)`) and keep
  colon-notation strictly for lifecycle calls (`:Init()`, `:Start()`).

Supporting detail:

- `:Init()` is self-contained setup only — own state, own remote handlers, own
  connections. It must not touch another service, and must not depend on Init
  order.
- `:Start()` is where cross-service references are resolved. By then every
  service has finished Init.
- The idiom for a cross-service reference keeps the identifier name so call
  sites read unchanged:
  ```lua
  type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
  local PlayerDataService: PlayerDataServiceModule   -- declared, not assigned

  function MyService:Start()
      PlayerDataService = require(script.Parent.PlayerDataService)
  end
  ```
  `typeof(require(…))` is a type-level reference only — it does not require the
  module at runtime, so it cannot create a load-time cycle.
- **Never yield in `:Init()`.** Init and Start run back-to-back with no yield
  between them, which is what makes the "declared but not yet assigned" window
  unreachable. A yielding Init breaks that guarantee.
- Modules named `*Template` are skipped by `ServiceManager` and never loaded.
- `ServiceManager.INIT_ORDER` is an explicit, temporary boot order preserved
  from the pre-refactor Bootstrap. It is load-bearing only until every service
  honours the Init/Start contract; do not add ordering dependencies to it.

**Migration status — lifecycle migration is complete.** Every service uses
colon lifecycle methods, private state tables, and resolve every cross-service
reference inside `:Start()`. There are zero top-level `require(script.Parent.*)`
calls left in `Services/`.

| Service | Lifecycle | Cross-service refs | Mode |
| --- | --- | --- | --- |
| `PlayerDataService` | `:Init()` | — (leaf) | `--!strict` |
| `FusionService` | `:Init()` `:Start()` | `PlayerDataService`, `EventService` | `--!strict` |
| `ItemService` | `:Init()` `:Start()` | `PlayerDataService`, `TycoonService` | `--!strict` |
| `LightingService` | `:Init()` | — | `--!strict` |
| `DebugService` | `:Init()` `:Start()` | `PlayerDataService`, `HeistService`, `EventService` | `--!strict` |
| `GoalService` | `:Init()` `:Start()` | `PlayerDataService`, `TycoonService` | `--!strict` |
| `TycoonService` | `:Init()` `:Start()` | `PlayerDataService` (module scope, leaf), `FusionMachineService`, `WorldService` (Start) | `--!nonstrict` ⚠ |
| `FusionMachineService` | `:Init()` | — | `--!nonstrict` ⚠ |
| `WorldService` | `:Init()` | — | `--!strict` |
| `RebirthService` | `:Init()` `:Start()` | `PlayerDataService`, `TycoonService` | `--!strict` |
| `OfflineService` | `:Init()` `:Start()` | `PlayerDataService` | `--!strict` |
| `HeistService` | `:Init()` `:Start()` | `PlayerDataService`, `TycoonService` | `--!strict` |
| `EventService` | `:Init()` `:Start()` | `PlayerDataService`, `TycoonService` | `--!strict` |
| `AdminService` | `:Init()` `:Start()` | `PlayerDataService`, `EventService` | `--!strict` |
| `MonetizationService` | `:Init()` `:Start()` | `PlayerDataService`, `TycoonService` | `--!strict` |

⚠ **Strict-mode conversion is the one thing still outstanding.** Both flagged
files are dense Instance construction, and there is still no Luau type checker
installed, so flipping them blind would ship an unknown number of type errors
nobody can see locally. Install the checker (see `aftman.toml`) and convert
each as its own reviewable pass. Everything else about them already follows the
pattern.

`ServiceManager` calls `service:Init()`, which also works for a legacy
`function Service.Init()` definition (it ignores the extra `self`) — that
compatibility is what allowed the migration to happen service-by-service, and
it is retained so future additions can do the same.

### Known type-checker findings (unfixed, tracked)

`luau-lsp analyze` currently reports **2 pre-existing errors in one shared
module**. They predate the service-lifecycle work, are unrelated to it, and
were deliberately left alone rather than fixed opportunistically. The file is
unannotated (default nonstrict). Do not "clean these up" as a drive-by — they
deserve their own reviewed change. (`PadStyler.lua`, which owned 13 more, was
deleted in the world redesign.)

**`Shared/VFX/SparkleEmitter.lua` — 2 errors**

- Lines 17, 35: `Value of type 'SparkleEmitterOptions?' could be nil`. The
  `options = options or {}` idiom does not narrow the optional parameter for
  the checker; the fix is a narrowed local (`local style = options or {}`).

Note these are reported whenever you analyze any module that transitively
requires it (most of `Services/`), so a "clean" run means *no errors owned by
the file under test* — check the path on each reported line.

### Remotes

`ReplicatedStorage.Shared.Network.RemoteEvents` is the only place remotes are
created; it builds the container folder (named `RemoteEvents`) on the server
and makes the client `WaitForChild` it. Never call `Instance.new("RemoteEvent")`
in a service. To add one: add the name to `REMOTE_EVENT_NAMES` with a comment
stating direction, then connect it in `:Init()`.

Heist remotes: `RequestSteal` (C→S `{ OwnerUserId, PedestalIndex }`),
`MarkTipSeen` (C→S `{ Id }`) (no lock remote: LOCK is the console
prompt only), `SetSetting` (C→S `{ Key, Tier?, Value }`: RevealRule,
SfxVolume, SfxMuted, AutoFuse; SettingsConfig), `RequestShopPurchase` (C→S
`{ Key }`), `ShopPurchased` (S→C), `ShopAnnouncement` (S→all, Overclock),
`HeistStarted` / `HeistEnded` (S→thief and victim; a rejected grab is
`HeistEnded { Outcome = "Rejected", Reason }`), `HeistFeed` (S→all,
Legendary+).

### Sync hooks

`PlayerDataService.OnSync(callback)` registers a function that runs
synchronously at the start of every `SyncTycoon`, before the snapshot is
built, so whatever it changes ships in that snapshot (GoalService uses it to
pay goals and publish `GoalProgress`). Hooks must not call `SyncTycoon`
themselves. It is a plain callback list on purpose: a BindableEvent handler
would run deferred, after the snapshot was already sent.

### Server authority

Services never trust client-supplied ownership, tiers, or instance references.
Resolve everything server-side from the requesting `Player` and validate before
mutating (see `ItemService.onRequestPlaceItem`, `FusionService.onFusionRequest`).

### World layout (plot-local space and the slot grid)

`Shared/Config/PlotLayout.lua` is the single source of truth for plot
geometry: every position, offset and size on a plot, the station / dropper /
pedestal / machine / gate dimensions and the slot grid.
`Shared/Config/StreetLayout.lua` does the same for the street and its speed
belts. No service
may hard-code a second copy — that class of duplicated assumption caused most
of this project's layout bugs. A require-time assertion block in PlotLayout
checks that no footprints overlap and everything sits inside the walls.

- **Plot-local space:** origin = `PlotOrigin`, at the centre of the plot at
  floor-top height (y = 0). +X is the plot's right, +Z its front (the gate,
  facing the street). World position = `origin:PointToWorldSpace(localPos)`
  (`PartKit.At(origin, localPos, y)`); facings are relative to the origin.
- **Slot grid:** 12 slots (`MAX_PLOT_SLOTS`; set the place's Max Players to
  12). Slot i: column `(i - 1) // 2`, row `(i - 1) % 2`; x = `(column - 2.5) *
  80`; row 0 at z = −50 facing +Z, row 1 at z = +50 turned 180°, so both rows'
  gates face the street at z = 0. `PlotLayout.GetSlotCFrame(i)`.
- **Materials:** every solid part is SmoothPlastic, accents Neon (colours
  from `UITheme.World`); the ground's Grass and the lab shield fence's
  **ForceField** (`PlotKit.BuildShieldFence`, `World.Shield`) are the only
  exceptions. No Basalt, Slate, Metal or Plastic. **No flat Neon circles:** Roblox draws a cylinder
  top as a fan of triangles that bloom unevenly ("pizza slices"). Glowing
  rings on flat surfaces are SurfaceGui faces (`BillboardKit.BuildPadFace`);
  Neon cylinders are only thin bands seen from the side (station/machine
  rims).
- **LOCK console:** `PlotLayout.LOCK_CONSOLE` (10, 0, 27), inside the gate
  right of the walkway, facing the gate; 3 × 3 footprint in the assertion
  block; geometry in `PlotLayout.LockConsole`, prompt distance 8.
- **Pedestal prompts:** the client handles DisplayPrompts through
  `ProximityPromptService` (PromptTriggered/PromptShown), never by looping a
  folder's children once; server containers are built complete and parented
  last.
- **Prompts:** stations 7, pedestals 6, machine 10; all
  `RequiresLineOfSight = false`, `Exclusivity = OnePerButton`. Owner-only
  prompts carry `OwnerOnly = true` and are disabled on other clients by
  WorldLabelController.
- **Hover animation:** tag a Part or Model `FT_Hover`
  (`PartKit.SetHover`); clients animate it. The server never tweens these.
  Likewise client-only: `FT_Orbit` (mutation satellites round a pedestal
  orb; attributes Count/Radius/Period/Tilt, one BulkMoveTo per frame),
  `FT_Rainbow` (hue-cycling shells) and `FT_PortalSwirl`.

## Gotchas

- **Plots are built once per player per server session** (on join), each
  with its own Fusion Machine. Layout/pad changes do not appear in an
  already-running session — stop and restart Play.
- **Studio setup the scripts can't do:** set `Lighting.Technology` to Future,
  delete `Workspace.Baseplate` (WorldService also removes it at runtime), and
  set Max Players to 12 in Game Settings.
- **Binary assets are `.rbxm` under a blanket `.gitignore` exclusion** with
  explicit carve-outs (`!TycoonTemplate.rbxm`,
  `!src/ReplicatedStorage/Shared/VFX/*.rbxm`). A new `.rbxm` added elsewhere
  will be silently untracked.
- `.rbxm` files inside a `$path`-mapped folder are auto-synced by Rojo and named
  after the filename (descendants keep their authored names). Only assets
  outside such a folder — e.g. root-level `TycoonTemplate.rbxm` — need their own
  `default.project.json` entry.
- A line starting with `(` directly after a statement ending in an expression is
  parsed as a call spanning both lines. Route casts through a local
  (`local x = y :: T`) instead of inline `(y :: T).Field = …`.
