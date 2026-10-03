# Fusion Tycoon — Polish 3: Factory Line (build prompt for Claude Code)

Paste everything below into Claude Code, opened on the `world-redesign` branch.

---

This pass makes the five generators the centre of the lab instead of two $50 droppers. The design is fixed. The canvas board "Polish 3 · factory line" shows it, and every number you need is in this file.

Read `CLAUDE.md` first and follow it: PlotLayout for every position, UITheme for every colour, `PlayerDataService.SyncTycoon` for syncing, and `luau-lsp analyze` as the check. After each phase, run the type check, fix every new error in files you touched, and commit the phase on its own.

## What the playtest showed

- **The droppers are pointless late game.** The two droppers at the front pay a flat "+$50" forever. By the end that's nothing next to $400K/s.
- **The real money is hidden.** The generators that actually earn (thousands to millions a second) are small machines tucked into the back corners, so players don't notice them or connect them to their income.
- **Pedestal labels can fill the screen.** When the camera gets very close to a pedestal label, it covers the bottom of the screen (a giant "LEGENDARY" bar).

## The new model in one paragraph

Delete the droppers and the old collector. All five generators stand in one row along the left wall, cheapest at the front near the gate and Singularity Core at the back. Each owned generator visibly drops cash balls onto one conveyor running to a collector in the back-left corner. A higher level means more balls per second, and a higher tier means bigger, brighter balls. When a ball reaches the collector, it pops its value. **The money itself is still paid by the existing server tick** (`TycoonConfig.GetPassiveCashPerSecond`). The balls are a client-side picture of that income, so nothing is lost to physics and the server does no ball work at all. New saves start with Basic Generator at LV 1, so a new player sees balls flowing immediately.

---

## Phase 1 — Economy and data

- **TycoonConfig**
  - Basic Generator `BaseCashPerSecond` 1 → **2**.
  - Remove `DropperCashValue`, `DropperIntervalSeconds`, `Dropper2Cost`, and `GetDropperCashPerSecond`, plus everything that calls them.
  - The HUD income line becomes just the passive income.
  - Update TycoonConfig's milestone header to the numbers below.
- **Starting level:** when a plot is claimed, if `basic_generator` is at level 0, set it to **1**. This covers new saves and old saves.
- **HasDropper2:** keep the saved field so old saves still load, but nothing reads it anymore. Remove `SetHasDropper2` and its callers, and drop it from the snapshot.
- **Economy sim:** it now lives in the repo at `tools/econ_sim.py`, already set to these values. Run `python3 tools/econ_sim.py` and paste the output into your summary. These are the expected medians; if yours differ by more than 20%, stop and say so:
  - first Gacha pull ~1:10
  - first Legendary ~7 min
  - first Mythic ~30 min
  - Singularity Core ~1:43
  - Multiplier maxed ~3:53
- **Also add to CLAUDE.md:** "Re-run `tools/econ_sim.py` after changing any economy number; keep its tunables in sync with TycoonConfig/FusionConfig."
- **GoalConfig / GoalService**
  - `buy_dropper2` becomes **`upgrade_basic`**: "Upgrade your Basic Generator", done at basic LV ≥ 2, reward $60, target `Generator_basic_generator`.
  - `buy_basic_generator` becomes **`basic_lv5`**: "Get Basic Generator to LV 5", done at LV ≥ 5, reward $100, Unit "Basic LV", target `Generator_basic_generator`.
  - Keep each goal's position in the list. A save already past these goals keeps its `GoalIndex`.

## Phase 2 — Layout

In `PlotLayout`:
- **Delete:** `DROPPER1`, `DROPPER2`, `COLLECTOR*`, `GENERATOR_BAYS`, `GENERATOR_BAY_SIZE`, the Dropper 2 station, and their footprints.
- **Delete `DropperKit.lua`.**
- **Remove the server collector, the cash-ball physics and the `CashParts` collision group.** Keep the belts' own collision group only if Polish 1 still needs it.
- **Remove the `CashCollected` remote**; the client makes its own pops now.
- **The right back corner is now free.** Leave it empty; it's reserved for the rebirth machine. Add it to PlotLayout as a reserved 10 × 10 footprint at (24, −24) so nothing else is built there.

**New plot-local layout.** Generators face **+X** (toward the conveyor); everything else faces +Z as before.

| Element | Local centre (x, z) | Size | Notes |
|---|---|---|---|
| basic_generator | (−27, +22) | 3 × 3, 3 tall | |
| ember_forge | (−27, +14) | 3 × 3, 4 tall | |
| flare_reactor | (−27, +6) | 3 × 3, 5 tall | |
| core_engine | (−27, −3) | 4 × 4, 6 tall | |
| singularity_core | (−27, −13) | 5 × 5, 8 tall | |
| FactoryBelt | x −21, z from +27 to −21 | 3 wide × 0.4 tall, length 48 | runs toward −Z (the back) |
| Collector | (−21, −24) | 6 × 6, top at y 0.4 | |
| Rebirth reserve | (24, −24) | 10 × 10 | build nothing |

Update the overlap assertions. Every footprint must still clear the pedestals at z −2 (pedestal 1 is at x −17), the machine, the walkway and the walls.

## Phase 3 — Generators on the line

`GeneratorKit` keeps its three states from Polish 2 (locked ghost, buy ghost, owned), its prompts, its screen and its band rules. Changes:

- **Placement and facing:** use the new positions, and face +X. The **Screen** SurfaceGui moves to the face the player sees walking in from the gate (+Z). Change the line under the level so it shows the generator's own income, e.g. "LV 12 · $3.1K/s".
- **New `Spout` part:**
  - A 1.4 × 1.4 × 1.4 block, StructureLight colour, on the +X face at 70% of body height.
  - A 0.15-wide Neon lip on its opening, in the tier colour.
  - The ghost states show the Spout as a ghost too.
- **Remove the per-generator floating income pops** from `GeneratorController`; the collector pops replace them. Keep the buy and upgrade toast and the bump.

## Phase 4 — Conveyor and collector (server parts)

Build these with PartKit and PlotLayout constants:

- **`FactoryBelt`:** SmoothPlastic, `UITheme.World.Belt`. Add two Neon edge strips along both long sides, 0.12 tall × 0.25 wide, AccentGold. It's decorative: anchored and CanCollide true. Players can walk on it; it has no velocity.
- **`Collector`:** 6 × 0.4 × 6, SmoothPlastic AccentGold. Neon edge strips on all four sides, 0.12 × 0.25. A `PointLight` in gold, Range 10, Brightness 1.
- **A `BillboardKit` pad label above the collector:** title "COLLECTOR", pill "+$X/s", where X is the owner's live passive income including the multiplier. Owner-only, MaxDistance 60. Update it on every sync.

## Phase 5 — Cash balls (client, new `FactoryController`)

For **every** plot within 120 studs of the camera (yours and other players', so the street looks alive), animate balls for each **owned** generator.

**Spawning**
- **Interval:** `lerp(2.0, 0.5, (level - 1) / 24)` seconds. So LV 1 drops one ball every 2.0 s and LV 25 one every 0.5 s.
- **Ball:**
  - A Ball part, CanCollide, CanQuery and CanTouch all false, Anchored, Neon, in the tier colour (`FusionConfig.TierAccentColors`).
  - Diameter by tier: Common 0.9, Rare 1.05, Epic 1.2, Legendary 1.4, Mythic 1.6.
  - Legendary and Mythic balls get a small PointLight (Range 4).

**Path** (CFrame only; never physics)
1. Leave the Spout in a short arc onto the belt's centre line: 0.35 s, rising 1 stud then landing at belt height.
2. Ride the belt toward −Z at **10 studs/s** to the collector.
3. Drop into the collector centre: 0.2 s, shrinking to 0.

**Value and pops**
- Each ball is worth `generatorIncomePerSecond × multiplier × interval`, computed client-side from TycoonConfig, the snapshot's generator levels and the multiplier.
- **Pops are for your own plot only.** When a ball arrives, add its value to a running total. Every 0.5 s, show one "+$X" pop above the collector:
  - Display font, Cash colour, Ink stroke.
  - Use the tier light colour of the highest-tier ball in that window.
  - It floats up 3 studs and fades over 0.8 s.
  - Use `NumberFormat.Money`.
- Other players' plots show balls but no pops.

**Performance**
- At most **60 live balls per plot**. If a generator would spawn past the cap, skip that ball; the pops still sum the full value.
- Pool and reuse ball parts; don't create and destroy them.
- Move everything with one `workspace:BulkMoveTo` per frame.
- Stop all work for a plot when it's more than 120 studs from the camera.

**Server truth stays server-side:** the balls never touch money. The HUD cash number keeps counting up from the server tick exactly as it does now.

## Phase 6 — Labels and text

- **Labels too close to the camera:** in `WorldLabelController`, hide any pedestal or pad BillboardGui whose adornee is within **7 studs** of the camera. Show it again past 8 studs to avoid flicker. This fixes the screen-filling "LEGENDARY" bar.
- **Upgrades panel intro line:** "Generators earn every second. They're the machines along the left wall of your lab."
- **Goal marker:** the old `Dropper2Station` target is gone. Check that every GoalConfig target resolves to a real part, and add an assertion in GoalMarkerController that warns once for any target it can't find.

## Acceptance check (do all of these before saying you're done)

1. `luau-lsp analyze`: no new errors. PlotLayout assertions pass.
2. `tools/econ_sim.py` output is in your summary and matches the expected medians within 20%.
3. `grep` finds no references to `Dropper1`, `Dropper2`, `DropperKit`, `CashCollected`, `CashParts` or `DropperCashValue` left in `src/`.
4. Add a "Factory line" section to `docs/UI_TEST.md`:
   - A fresh save shows Basic Generator LV 1 dropping balls within 2 s of claiming.
   - Upgrading a generator visibly speeds up its balls.
   - Collector pops match the HUD income over ~10 s, roughly.
   - Walking within 7 studs of a pedestal label hides it.
   - In a 2-player test, you see the other lab's balls but not its pops.
   - Frame rate stays smooth with all five generators maxed (`/cash 1e12`, then buy everything).
5. Commit per phase, push `world-redesign`, and comment a summary on PR #4.
