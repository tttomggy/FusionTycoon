# Fusion Tycoon — Depth 1: Secret tier, mutations, Index, Pull ×10 (build prompt for Claude Code)

Paste everything below into Claude Code, opened on the `world-redesign` branch,
**after `docs/POLISH_4_PROMPT.md` is done** (this pass uses its `IncomeInputs`,
`RebirthConfig` and luck).

---

Harris's playtest: "if you can just fuse that easy to make the best one there's
no point after that in the gacha." Right now Mythic is the ceiling and fusion
gets you there in ~30 min. This pass makes the item chase open-ended:

- a 6th tier above Mythic,
- mutations that every pull and fusion can roll,
- an Index that pays for collecting,
- Pull ×10, so the Gacha is worth hammering at the start of every rebirth run.

The design is fixed. The canvas board **"Depth 1 · Secret, mutations, Index"**
shows it, and every number is in this file.

Read `CLAUDE.md` first and follow it: config tables in `Shared/Config`, UITheme
for every colour and font, UIKit for screens, `SyncTycoon` for syncing,
RemoteEvents for remotes, server authority, and `luau-lsp analyze` as the check.
After each phase, run the type check, fix every new error in files you touched,
and commit the phase on its own.

---

## Phase 1 — Secret tier

- **`FusionConfig`**
  - `TierOrder` gains `"Secret"` after Mythic.
  - `SuccessChance.Mythic = 0.08`. A fail keeps 1 Mythic (Phase 2's fail rule).
  - Secret can't be fused.
- **Mythic fusion needs Rebirth 1.**
  - Add `RebirthConfig.SecretFusionRebirths = 1` and
    `FusionConfig.CanFuseTierFor(tier, rebirths)`.
  - `FusionService` checks it server-side and rejects with `"NeedsRebirth"`.
  - The client shows a lock instead of the fuse button: "Rebirth 1 to fuse
    Mythics".
  - Set `RebirthConfig.Unlocks = { [1] = "Mythic fusion → Secret" }` so the
    Rebirth panel shows it.
- **Gacha rates** (must sum to 1; `GetGachaRates(luck)` from Polish 4 now
  multiplies Legendary, Mythic **and Secret** by luck):

  | Common | Rare | Epic | Legendary | Mythic | Secret |
  |---|---|---|---|---|---|
  | 0.77998 | 0.18 | 0.035 | 0.0045 | 0.0005 | 0.00002 |

- **`ItemConfig`:**
  - `Tiers.Secret = 6`.
  - New items `secret_horizon` "Event Horizon" and `secret_prism`
    "Eternity Prism", both Secret.
- **`TycoonConfig.PedestalCashPerSecond.Secret = 50000`.**
- **Colours.** Add these tokens; `FusionConfig.TierAccentColors.Secret` is the
  same mint.
  - `UITheme.Tier.Secret` `#3DFFD0`
  - `TierGradient.Secret` `{ Light = #D6FFF5, Mid = #1FE0B4, Dark = #06574A }`
  - `World.VoidShell` `#0B0A1A`
- **`RarityVisuals.Secret`:** the Mythic entry's structure, mint glow, server-wide
  announce.
- **`MajorRevealTiers.Secret = true`.**
- **Secret orb** (`PedestalVisuals`): the only dark orb, so it reads instantly.
  - `PlotLayout.Pedestal.OrbDiameter.Secret` = Mythic + 0.2.
  - Glass shell in `VoidShell` at 0.35 transparency.
  - A mint Neon core and a slow mint sparkle.
- **Odds boards:** the Fusion Machine board gains "2 Mythic → Secret 8%
  (Rebirth 1)", and the gacha label and odds include Secret.
- **Sweep for hard-coded tier lists.** `grep -rn "Mythic"` and check every
  tier list or loop handles 6 tiers:
  - inventory sort and filters
  - item picker
  - Fuse All tier list
  - goal checks
  - result cards and RevealEffects
  - plot sign "best item"
  - announcements
  - number-to-tier maps

## Phase 2 — Mutations: data and rules

**`Shared/Config/MutationConfig.lua`** (new, `--!strict`):

| Mutation | Rank | Income × | Pull chance | Fusion-success chance |
|---|---|---|---|---|
| (none) | 0 | 1 | — | — |
| Golden | 1 | 2 | 4% | 2% |
| Diamond | 2 | 5 | 0.8% | 0.4% |
| Rainbow | 3 | 12 | 0.1% | 0.05% |

- `MutationConfig.Roll(rng, luck, source: "Pull" | "Fusion"): string?` rolls one
  number against the cumulative chances, rarest first. Each chance is × luck.
- Also add `GetMultiplier(mutation?)`, `GetRank(mutation?)` and
  `GetDisplayName(itemName, mutation?)`, which returns "Golden Star Core".

**Data**
- `InventoryItem` gains `Mutation: string?`. nil means normal.
- On load, an unknown mutation string becomes nil. Old saves just have none.
- `PlayerDataService.AddItem(player, itemId, tier, mutation?)`.

**Gacha pull** (TycoonService gacha handler): roll the tier with luck, then
`MutationConfig.Roll(rng, luck, "Pull")`. The result payload carries the item
with its `Mutation`.

**Fusion** (`FusionService.fuseOnce`). Inputs still need the same tier.
- **Success:**
  1. `base` = the lower-ranked of the two inputs' mutations, so any normal
     input makes it nil.
  2. Roll `MutationConfig.Roll(rng, luck, "Fusion")`.
  3. The result gets the higher-ranked of `base` and the roll.
- **Fail:** keep the input with the higher mutation rank (the first on a tie)
  untouched, with the same Uid. Remove only the other. This replaces "remove
  both, add a random same-tier item", so a fail never loses a mutation.
- **Fuse All only uses items with no mutation.** Mutated items are never
  auto-fused.

**Income**
- `IncomeInputs.PedestalTiers` becomes
  `PedestalItems: { { Tier: string, Mutation: string? } }`.
- Add `TycoonConfig.GetItemCashPerSecond(tier, mutation?)` =
  `PedestalCashPerSecond[tier] × MutationConfig.GetMultiplier(mutation)`.
- Use it everywhere an item's $/s is shown or paid: pedestal labels, picker,
  inventory cards, result cards, the collector's pedestal pops.

**Luck** = `RebirthConfig.GetLuck(rebirths)`, for both pulls and fusion
mutation rolls.

## Phase 3 — Mutation visuals

**Tokens**
- `Mutation.Golden` `#FFD23F`
- `Mutation.Diamond` `#BFF4FF`
- `Mutation.RainbowStops`: `#FF5470`, `#FFBE28`, `#4CF08A`, `#4FB3FF`,
  `#A47BFF`

**Pedestal orb.** The orb keeps its tier colour. A mutation adds a **shell**:
a second Glass ball at 1.15× the orb diameter, 0.6 transparency, in the mutation
colour, plus a sparkle emitter in that colour. Golden gets Rate 6; Diamond
Rate 12 with smaller, faster particles.
- **Rainbow:** tag the shell `FT_Rainbow`. `WorldAnimationController` cycles its
  Color through the hue wheel every 3 s, client-only.
- **No new `Highlight`s.** Roblox caps them at 31 per client, and 12 plots × 4
  pedestals already reach that.
- **Check the existing per-pedestal Highlight against that cap.** If 48 filled
  pedestals can exist, replace it with something cheaper, such as the cap lip
  glow you already have.

**Pedestal label.** The top line becomes `GOLDEN · MYTHIC` in the mutation
colour.
- Rainbow uses a UIGradient over white text. That's intended tinting; the
  "gradient tints text" gotcha is only a problem when the text isn't white.
- The name line uses `GetDisplayName`, and the $/s line uses
  `GetItemCashPerSecond`.

**Inventory, picker, result cards**
- **Inventory:** a mutation tag pill on the card's top-right (×2 / ×5 / ×12,
  Rainbow with the gradient), and the name includes the mutation. Mutated and
  normal items of the same id are separate stacks.
- **Item picker:** sorts by `GetItemCashPerSecond`, highest first.
- **Result cards:**
  - Show the mutation pill.
  - Diamond and Rainbow results always get the major reveal, whatever the tier.
  - A Rainbow result, or any Secret, fires a server banner:
    - Secret: `SERVER · SECRET` (mint gradient) — "Har found Event Horizon!"
    - Rainbow: `SERVER · RAINBOW` (rainbow gradient) — "Har pulled a Rainbow
      Star Core!"

## Phase 4 — Index

**`Shared/Config/IndexConfig.lua`** (new, `--!strict`):
- Entries are every ItemConfig item × { Normal, Golden, Diamond, Rainbow }:
  17 items × 4 = **68 entries**. The key is `"<itemId>|<Mutation or Normal>"`.
- `BonusPerEntry = 0.01` (+1% income each).
- `BonusPerCompletedTier = 0.05` (+5% for a tier with every item in every
  mutation).
- `IndexConfig.GetMultiplier(found: { [string]: boolean }): number` returns
  1 + bonuses.

**Data**
- `PlayerData.Index: { [string]: boolean }`, saved with string keys (they
  already are).
- **Backfill on load** from the current Inventory.
- `AddItem` marks the entry and returns whether it was new, so the gacha and
  fusion results carry `NewIndex = true`.
- **Rebirth keeps the Index.** Add "Index" to the panel's YOU KEEP line.
- The snapshot carries the found keys; the client computes the multiplier.

**Income:** `IncomeInputs.IndexMultiplier`. Income = (generators + pedestals)
× pad × rebirth × Index, and `GetIncomeMultiplier` includes it.

**UI**
- **New `UI/IndexPanel.lua`**, per the board:
  - Header `INDEX` and a green pill with the bonus (`+42% income`).
  - A count line: "37 / 68 found · +1% each · +5% per full tier page".
  - Tier tabs with counts (Legendary 9/12). Secret is 2 items × 4 = 8.
  - Each page is a grid: one row per item, columns Normal / Golden / Diamond /
    Rainbow. A found cell is filled in the tier or mutation colour (Rainbow
    uses the gradient); a missing one is a `?` well in Panel2 with Faint text.
  - Phone fit and the ≥ 44 px rules apply.
- **A third HUD button `INDEX`**, next to UPGRADES and ITEMS, using a new
  `Gradients.Teal` `{ Top = #5CF2D6, Bottom = #1FB49A }`. Check the mobile
  layout still clears the top-left 170 × 60 and that all three buttons fit at
  844 × 390.
- **A toast when an entry is new:** `NEW IN INDEX · Golden Star Core · +1%`, or
  `+5% · Legendary page complete!` when that happens.

## Phase 5 — Pull ×10 and odds disclosure

**Pull ×10**
- A second ProximityPrompt on the gacha pad:
  - ActionText `Pull ×10`, KeyboardKeyCode **R**, GamepadKeyCode **ButtonY**.
  - A `UIOffset` so it doesn't overlap the E prompt.
  - ObjectText = the cost of the next 10 pulls. Add
    `TycoonConfig.GetGachaMultiPullCost(pullsSoFar, count)`, the sum of the
    next `count` single prices.
- **Server:**
  - Check cash ≥ the total.
  - Roll all 10 before charging; a config gap never charges.
  - Charge once, then add 10 items, each with its tier and mutation roll, and
    add 10 to the pull count.
  - Sync once and send one result `{ Success, Items = { … } }`.
  - Share the single-pull debounce.
- **Client:** a 10-card result grid (ResultController). The best item, by
  `GetItemCashPerSecond`, gets the big card and the major reveal if it qualifies.
  The others pop in quickly, 0.06 s apart. Show the Index and banner rules
  (Phase 4, Phase 3) per item.

**Odds disclosure** (Roblox policy needs it for any random reward, and we'll
sell luck boosts later):
- The gacha pad label shows all six tier rates at the owner's luck, plus a
  mutation line.
  - Format: `Common 77.9 · Rare 18 · Epic 3.5 · Legendary 0.50 · Mythic 0.055
    · Secret 0.0022%` (the values at Rebirth 2), then
    `Golden 4.4% · Diamond 0.88% · Rainbow 0.11%`.
  - Use 2 significant figures, never 0.
  - The server rebuilds the text on claim and on rebirth.
- The Fusion Machine odds board lists each fusion's success rate and the fusion
  mutation chances.
- Write one helper, `FusionConfig.FormatOdds(luck)`, and use it for both, so a
  future paid boost can't show different numbers from what's rolled.

## Phase 6 — Sim, docs, checks

- Run `python3 tools/econ_sim.py 30 12` (full design) and paste the output.
- **Check its tunables against your Lua configs line by line:** Secret rate and
  fusion chance, mutation chances and multipliers, Index bonuses, Secret
  pedestal value.
- Expected medians. If yours differ by more than 20%, stop and say so; the
  Secret and Rainbow lines have huge spreads, so judge those by order of
  magnitude:
  - first pull ~1:10
  - first Golden ~4 min
  - first Legendary ~6 min
  - first Diamond ~14 min
  - first Mythic ~51 min
  - Rebirth 1 ~1:00
  - Rebirth 2 ~1:41
  - Rainbow ~1:45
  - Rebirth 3 ~2:29
  - Singularity Core ~2:40
  - first Secret ~4:00
  - Rebirth 7 ~8:00
  - Index ~39/68 after 12 h
- Update TycoonConfig's milestone header to these numbers.
- **CLAUDE.md:**
  - The loop now ends "… → Rebirth → hunt Secrets, mutations and the Index".
  - Add MutationConfig and IndexConfig to Config.
  - The fusion rules: success keeps the lower mutation then may roll; a fail
    keeps the better input; Fuse All skips mutated items.
  - Note the Highlight cap.
- **`docs/UI_TEST.md`:** add a section **"Depth"**:
  - Pull ×10 charges the shown amount and shows 10 cards.
  - A Golden pull shows the gold shell on the pedestal, and income goes up ×2
    for that item.
  - Fusing Golden + normal on success gives normal or a fresh roll; a fail
    keeps the Golden.
  - Fuse All leaves mutated items alone.
  - Mythic fusion is locked before Rebirth 1 and works after.
  - The Index fills and its toast fires. The HUD income matches the Index
    bonus.
  - Odds on the pad change after a rebirth.
  - Rejoining keeps mutations and the Index.
  - Studio shortcut: a `/give <itemId> [mutation]` DebugService command,
    Studio-only, makes these testable without luck.
- `luau-lsp analyze`: no new errors. PlotLayout assertions pass.
- Commit per phase, push `world-redesign`, and comment a summary on PR #4.
