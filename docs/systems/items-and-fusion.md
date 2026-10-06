# Items, fusion, mutations, auto-display, rebirth, Index, settings

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

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
chance, `MutationConfig.IsEventOnly`; they STACK on top of a base, see
**Stacking mutations**). Fusion rules: a success keeps the *lowest*
base mutation among all inputs (so every input must share it), then may roll a
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


- **Auto-display** (Playtest 7): players never choose. `ItemService.Arrange
  (player)`, the ONE re-arrange, is a `PlayerDataService.OnSync` hook, so
  every change (pull, fusion, Fuse All / Auto-Fuse, delivery, theft, event
  mutation, rebirth, reward item, `/give`) lands on the pedestals in the
  same sync: the unlocked spots in fill order
  (`PlayerDataService.GetPedestalOrder` / `PlotLayout.GetPedestalOrder`:
  1 → 4, 5 → 6 with the pass, then the 2nd floor's 7 → 10 from Rebirth 2)
  hold the highest `TycoonConfig.GetStackCashPerSecond` (ties: tier,
  what's already up, Uid); a new unlock restyles the spots even when
  nothing moves. A carried item's pedestal is left alone (`BeingStolen`) until the
  heist ends. It sets `InUse`, re-applies only changed pedestals, sends
  `SyncInventory` when ON DISPLAY tags change, announces a newly displayed
  Legendary+ and fires `FirstDisplay`. No place / remove remotes, no
  Display prompt, no pedestal picker, no DISPLAY IT; ITEMS is the
  inventory view (ON DISPLAY tags); the owner prompt left on a pedestal is
  the locked spots' `UnlockPrompt`. Displayed items can be fused (spare
  copies first); only a carried one can't (`ItemCarried`).
- **Stacking mutations** (`MutationConfig`; like Grow a Garden). An item
  has ONE base mutation (`Item.Mutation`: none / Golden / Diamond /
  Rainbow) plus a set of event mutations (`Item.EventMutations`: Charged /
  Void / Celestial, sorted by rank, each at most once,
  `MutationConfig.SanitizeEvents` in `reconcile`; an old save's
  event-only base moves into the set, `Normalize`). The multiplier is
  **additive**, `1 + Σ(mult − 1)` (`GetStackedMultiplier`: Rainbow +
  Celestial = ×31, not ×240), through `TycoonConfig.GetItemCashPerSecond
  (tier, mutations)` / `GetStackCashPerSecond(item)` everywhere. Sources
  ADD (`AddEvent`, `PlayerDataService.AddItemEventMutation`): a Power
  Surge strike stacks Charged on any item not yet Charged, a Void Moon
  fusion stacks Void on what was kept, a meteor core rolls the normal base
  then Celestial on top, a pull rolls the base then the event roll
  (`MutationConfig.RollEvents`; 0 outside events). Fusion success keeps
  the lowest base AND the event mutations every input shares
  (`FusionConfig.PredictEventMutations`, the intersection); a fail keeps
  the input with the best stacked multiplier; Fuse All skips anything
  mutated. The Fuse panel says "✨ Keeps GOLDEN + CHARGED ×N" or names
  what a mixed chamber loses, red-ringing every orb that drags it
  (`FusionConfig.IsDragging`); AUTO-FILL matches the whole stack
  (`SameStack`). Index: a stacked item fills the entry of EACH mutation
  it has (119 entries unchanged). Looks: `UIKit.MutationPill({ Mutation,
  EventMutations })` is a row of pills side by side + an Ink "×N" total;
  orbs and card strokes use the top mutation (`GetTop`); satellites mix
  every mutation's colour (top's count + 1 per extra); the reveal card
  reads "+ CHARGED (stacked!)" (`EventReward` / `FusionResult` carry
  `Added`, `Stacked`); pedestal chips, banners and heist carries
  (`HeistEventMutations` "Charged,Void") carry the whole stack. Sim:
  events +13.3% / +14.6% / +13.6% sooner for Rebirth 1–3 (≤ 15%).
- **REBIRTH button:** the bottom bar is UPGRADES · ITEMS · INDEX ·
  **REBIRTH** · ⚙. Purple, always there, a fill of cash against
  `GetRebirthCost` and "$2.1M / $15M"; glows and pulses once affordable;
  opens `RebirthPanel` from anywhere (it replaced the floating REBIRTH!).

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
  `ResultController.ShowsBigCardFor` reads the rule for BEST OF 10 and
  fusion successes (fail cards and Fuse All unchanged); a **single pull
  always** gets the big card (Tutorial 2); a
  skipped card pops a **small line** above the bottom bar for 2.5 s (orb
  dot, "+ Golden Plasma Orb" in the mutation colour, the tier, "+$X/s";
  max 3, older ones fade) — except your own fusions: their top "FUSION
  SUCCESS!" banner already shows the result, so they get no line
  (`ResultController.FusionBannerShows` decides both; other players still
  see the server-wide banner). The client applies a change at once
  (`TycoonController.SetRevealRule`, kept until the snapshot echoes it).
  UI: the **⚙** 56 px button after REBIRTH opens `UI/SettingsPanel` (620
  wide, one scrolling list of sections: "Big reveal card" (one 5-segment
  row per tier + a locked Secret row) and "Sound effects" (see Sounds)).
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
