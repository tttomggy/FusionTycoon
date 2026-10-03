# Fusion Tycoon — Polish 4: Scale bug, harder economy, Rebirth (build prompt for Claude Code)

Paste everything below into Claude Code, opened on the `world-redesign` branch.
Run `docs/DEPTH_1_PROMPT.md` straight after this one; it builds on the
`IncomeInputs` table and `RebirthConfig` added here.

---

This pass fixes the generator that grows until it covers the lab, makes the
Multiplier Pad a long climb instead of a quick max, and adds Rebirth: the loop
that keeps a player coming back after the first couple of hours. The design is
fixed. The canvas board **"Polish 4 · rebirth"** shows it, and every number you
need is in this file.

Read `CLAUDE.md` first and follow it: PlotLayout for every position, UITheme
for every colour and font, UIKit for every screen, `PlayerDataService.SyncTycoon`
for syncing, RemoteEvents for remotes, the Init/Start service contract, and
`luau-lsp analyze` as the check. After each phase, run the type check, fix every
new error in files you touched, and commit the phase on its own.

## What the playtest showed

- **The Singularity Core grows huge.** After a run of quick upgrades, its body
  (and the orb next to it) swells far past its 5 × 5 × 8 size and pokes out
  through the fence.
- **The Multiplier Pad maxes too fast.** ×12.5 for $4B is cheap next to late
  income, and it multiplies everything, so it trivialises the generators.
- **The game can be "finished".** Once the generators are maxed and four
  Mythics are on pedestals there is nothing left to do, and pedestal items stop
  mattering. A Mythic pays $1K/s next to $2.4M/s of generators.

---

## Phase 1 — Fix the compounding scale bug

**Root cause (already diagnosed, confirm it):** `GeneratorController.bump`
reads `body.Size` live as its "base". When a second upgrade lands while the
first bump is still mid-tween, the new tween's base is already scaled up, and
its `Completed` restores that scaled size. Every rapid upgrade compounds the
size by up to 1.08×.

**Fix it once, for everything:**
- Add `PartKit.Pulse(part: BasePart, scale: number, seconds: number)` (PartKit
  is shared, but only clients call it):
  - On first use, store the part's size in a `BaseSize` attribute. Never
    overwrite it after that.
  - Cancel any pulse already running on that part (a weak-keyed table of active
    tweens), and set `Size = BaseSize` before starting.
  - Tween to `BaseSize * scale` and back (reverses = true). On `Completed`,
    **whatever the playback state**, set `Size = BaseSize`.
- Use it for the generator upgrade bump. Grep for every other runtime `Size`
  tween or `Size =` assignment on world parts (`RevealEffects` charge core,
  `PedestalVisuals` pulse, generator cores, the gacha hologram, station pads) and
  move each onto the same rule: a stored base, never the live size.
- Harris also saw "the orbs" next to the fence grow. Reproduce it: `/cash 1e12`,
  then upgrade the Singularity Core and the Core Engine as fast as the prompt
  allows, 20+ times each. If anything still grows after the bump fix, find that
  second root cause and fix it too. Name it in your summary.
- **Studio-only guard:** in `GeneratorController`, when running in Studio, check
  1 s after each bump that the body's size still matches its PlotLayout spot
  (Footprint × Height × Footprint) within 1%. If not, `warn` once with the
  generator id.

## Phase 2 — Income inputs and the new numbers

**One income formula, one input table.** Change
`TycoonConfig.GetPassiveCashPerSecond` to take a single table:

```lua
export type IncomeInputs = {
	GeneratorLevels: { [string]: number },
	PedestalTiers: { string },
	CashMultiplierLevel: number,
	Rebirths: number,
}
```

Income = (generators + pedestals) × Multiplier Pad value × rebirth multiplier.

- Add `TycoonConfig.GetIncomeMultiplier(inputs)` → pad × rebirth. This is
  "the multiplier" anywhere the game shows a per-generator or per-item number:
  generator screens, Upgrades panel rows, item picker, pedestal labels, result
  cards, factory ball values, collector label, HUD. Grep every call to
  `GetCashMultiplierValue`. Keep that function only where you mean the pad
  itself (the pad label and its Upgrades row).
- Build `IncomeInputs` in one place on each side:
  `PlayerDataService.GetIncomeInputs(player)` on the server and
  `TycoonController.GetIncomeInputs()` on the client. Depth 1 adds fields to
  this table, so nothing else should assemble one by hand.

**Multiplier Pad: 15 levels, +0.25 each, and the last level jumps to ×5**

| LV | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| Cost | $5K | $30K | $150K | $750K | $3.5M | $15M | $60M | $250M |
| ×  | 1.25 | 1.5 | 1.75 | 2 | 2.25 | 2.5 | 2.75 | 3 |

| LV | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|
| Cost | $1B | $4B | $15B | $50B | $150B | $500B | $1.5T |
| ×  | 3.25 | 3.5 | 3.75 | 4 | 4.25 | 4.5 | **5** |

Write the table out literally in `CashMultiplierLevels` (no formula). Saves keep
their level number, so a save at the old LV 10 becomes ×3.5. That's intended.

- Pad label pill: `"x2.25 · LV 5/15"`, at max `"x5 MAX"`. Upgrades panel
  multiplier row shows `LV 5/15` too.

**Pedestal income** (`TycoonConfig.PedestalCashPerSecond`): Common 3, Rare 12,
Epic 50, **Legendary 300, Mythic 3000**. Top tiers jump so displayed items stay
worth having late.

**Goals**
- `multiplier_x3` becomes **`multiplier_x2`**: "Reach a x2 multiplier", done at
  pad LV ≥ 4. Same reward and position.
- Append **`first_rebirth`**: "Rebirth for the first time", reward $25,000,
  Unit none, Target `RebirthPortal`. It's checked after the rebirth, so its
  reward lands in the new run.

## Phase 3 — Rebirth: config, data and service

**`Shared/Config/RebirthConfig.lua`** (new, `--!strict`):

```lua
RebirthConfig.BaseRequirement = 30_000_000 -- run earnings for the 1st rebirth
RebirthConfig.RequirementGrowth = 3.2      -- each rebirth needs 3.2x the last
RebirthConfig.IncomePerRebirth = 0.5       -- income x(1 + 0.5 * rebirths)
RebirthConfig.LuckPerRebirth = 0.05        -- luck x(1 + 0.05 * rebirths)
RebirthConfig.Unlocks = {} :: { [number]: string } -- filled by Depth 1

function RebirthConfig.GetRequirement(rebirths: number): number   -- floor(Base * Growth ^ rebirths)
function RebirthConfig.GetIncomeMultiplier(rebirths: number): number
function RebirthConfig.GetLuck(rebirths: number): number
```

**Luck** multiplies the Legendary and Mythic gacha rates; Common absorbs the
difference so the table still sums to 1. Add
`FusionConfig.GetGachaRates(luck: number)` returning the effective table, and
make `RollGachaTier(rng, luck)` use it. Every odds display uses the same
function with the player's luck (Phase 5 and the pad label).

**Data** (`PlayerDataService`)
- New fields `Rebirths: number` and `RunEarnings: number`, both default 0.
  Load/save them; old saves get 0.
- `RunEarnings` grows by exactly what the passive payout tick pays. Goal
  rewards and `/cash` don't count.
- Add both, plus `RebirthRequirement`, to the SyncTycoon snapshot through
  `SyncTycoon`.
- `leaderstats` gets an IntValue **`Rebirths`**, created before `Cash` so it's
  the first column. Keep it in step like Cash.

**`RebirthService`** (new, follows `ServiceTemplate.lua`, `--!strict`)
- Remotes: `RequestRebirth` (client → server, no args) and `RebirthResult`
  (server → client: `{ Success, Rebirths?, Reason? }`), plus
  `RebirthAnnouncement` (server → all clients: `{ Name, Rebirths }`).
- Validate: data loaded, plot claimed, `RunEarnings >= GetRequirement(Rebirths)`,
  and a 2 s per-player debounce. Reject with a reason string the client can
  toast.
- Then apply it with no yields between the check and the last write:
  - Cash = 0
  - Generators = `{ basic_generator = StartingBasicGeneratorLevel }`
  - CashMultiplierLevel = 0, GachaPulls = 0, RunEarnings = 0
  - Rebirths += 1
  - **Keep** Inventory, PedestalDisplays, GoalIndex and everything else.
- Refresh the plot the same way an upgrade does (generator states, pad label,
  gacha price label, collector), call `SyncTycoon`, fire `RebirthResult` and
  `RebirthAnnouncement`, and request an immediate save if PlayerDataService has
  one.
- **DebugService (Studio):** `/rebirthready` sets RunEarnings to the current
  requirement. `/rebirths <n>` sets the count. `/wipe` also resets Rebirths and
  RunEarnings.

## Phase 4 — Rebirth Portal (world)

It replaces the reserved 10 × 10 footprint at (24, −24) in `PlotLayout`. Keep
that footprint in the overlap assertions, now named `RebirthPortal`. Add a
`PlotLayout.RebirthPortal` table with every size below.

| Part | Size (studs) | Notes |
|---|---|---|
| Base | cylinder 8 dia × 0.4 | Structure. Its top is a `BillboardKit.BuildPadFace` ring in AccentRebirth (no flat Neon circle) |
| Pillars | 2 × (1.2 × 9 × 1.2) | StructureLight, at x ±3.4 from the portal centre |
| Beam | 8 × 1.2 × 1.2 | StructureLight, on top of the pillars |
| Edge strips | 0.25 wide, Neon | AccentRebirth, the inner face of each pillar |
| Portal sheet | 5.6 × 7.6 × 0.2 | Transparency 1. A SurfaceGui on **both** faces: a Frame with a UIGradient through the three `RebirthPortal` stops, rotation animated client-side |
| Light | PointLight | AccentRebirth, Range 14 |

- The portal faces +Z, toward the plot's centre.
- **Two states.** "Not ready": swirl Frame at 0.65 transparency and still,
  light Brightness 0.5. "Ready": swirl opaque and rotating 40°/s, pad ring
  pulsing, light Brightness 1.5.
  - The server sets a `Ready` attribute on the portal model.
  - The client animates it. Tag the sheet `FT_PortalSwirl` and handle it in
    `WorldAnimationController`, client-only like `FT_Hover`.
- **Label** (`BillboardKit` pad label, owner-only, MaxDistance 80,
  `AlwaysOnTop = false`, `LightInfluence = 0`):
  - Title `REBIRTH` in the Rebirth colour.
  - An orange pill `x1.0 → x1.5 income`, which becomes `READY · x1.0 → x1.5`
    when ready.
  - A progress bar.
  - A caption `$12.4M / $30M this run`.
  - The server updates it on each payout tick for the owner: text and bar size
    only, no rebuilds. Add a bar helper to BillboardKit if it doesn't have one.
- **Prompt:** `ProximityPrompt` "Rebirth", ObjectText "Portal",
  HoldDuration 0.5, distance 8, owner-only, `RequiresLineOfSight = false`,
  `Exclusivity = OnePerButton`. It does not call the server. The client opens
  the Rebirth panel through `ProximityPromptService.PromptTriggered`.
- `GoalMarkerController`: make sure `RebirthPortal` resolves.

**New UITheme tokens.** Every colour named in Phases 4 and 5 is one of these;
add them instead of using RGB literals.
- `Colors.Rebirth` `#FF8A3D`
- `Colors.RebirthLabel` `#FFD9B8`
- `Colors.RebirthBannerLeft` `#7A2A00`
- `World.AccentRebirth` `#FF8A3D`
- `Gradients.Orange` `{ Top = #FFB066, Bottom = #F06A1F }`
- `RebirthPortal` stops: `#FF8A3D`, `#FFD566`, `#FF4F7A`

## Phase 5 — Rebirth UI

**`UI/RebirthPanel.lua`** (UIKit constructors, per the board):
- **Header** `REBIRTH <next number>`, with the close button.
- **Two stat cards:**
  - INCOME `x1.0 → x1.5`, from `RebirthConfig.GetIncomeMultiplier`.
  - LUCK `+0% → +5%`.
- **Unlock row**, shown only when `RebirthConfig.Unlocks[next]` exists.
- **YOU KEEP:** "Every item · your pedestals · Index · goals · rebirths".
  Drop "Index" if Depth 1 isn't in yet.
- **YOU RESET:** "Cash → $0 · Generators → Basic LV 1 · Multiplier → x1 ·
  Gacha price → $250".
- **Progress:** a bar and the caption `$12.4M / $30M earned this run`.
- **Button:**
  - Not ready: Disabled style, `Earn $17.6M more`.
  - Ready: Orange `REBIRTH`. Tapping it opens a second-step `UIKit.Modal`:
    "Are you sure? Cash, generators and the Multiplier reset. Items stay."
    [Cancel] [REBIRTH]. Only that second button fires `RequestRebirth`.
- **On success:**
  - Close the panel.
  - Play a 0.4 s full-screen orange flash.
  - Show a ResultController card "REBIRTH 3!" with "Income x2.5 · Luck +15%".
- **On failure:** a toast with the reason.
- **Phone:** the panel fits 844 × 390 after the 0.8 UIScale. Keep every tap
  target ≥ 44 px and react to `UIKit.LayoutChanged`.

**Other UI**
- **HUD:** an orange pill `⟳ 3 · x2.5` next to the multiplier pill, hidden at 0
  rebirths. Tapping it opens the Rebirth panel. Its hit area is ≥ 44 px even
  though the pill is small.
- **AnnouncementController:** a banner for `RebirthAnnouncement` using the
  Mythic banner kit, gradient `RebirthBannerLeft` → Rebirth, label
  `SERVER · REBIRTH`, text `<Name> reached Rebirth 3!`. Show it to everyone,
  including the player who rebirthed.
- **Money:** every amount goes through `NumberFormat.Money`, and every
  multiplier through `NumberFormat.Multiplier`.

## Phase 6 — Sim, docs, checks

- `tools/econ_sim.py` is already in the repo with this design. Run
  `python3 tools/econ_sim.py 30 12 --no-depth` (Polish 4 alone) and paste the
  output into your summary.
- **Check its tunables against your Lua configs line by line:** multiplier
  table, pedestal values, RebirthConfig numbers, gacha rates and luck.
- Expected medians. If yours differ by more than 20%, stop and say so:
  - first Gacha pull ~1:10
  - first Legendary ~6 min
  - first Mythic ~27 min (wide spread)
  - Rebirth 1 ~1:03
  - Rebirth 2 ~1:50
  - Rebirth 3 ~2:48
  - Singularity Core ~2:45
  - Multiplier max: never in 12 h
- Update TycoonConfig's milestone header with these numbers, noting that Depth 1
  changes them.
- **CLAUDE.md:**
  - The game loop gains "→ Rebirth (Portal, back-right corner)", with a line
    on what resets and what stays.
  - Add `RebirthService` to the service table.
  - Add `RebirthConfig` to the Config list.
  - Add the new Studio commands (`/rebirthready`, `/rebirths <n>`).
  - Add: "Every income display uses `TycoonConfig.GetIncomeMultiplier`;
    `GetCashMultiplierValue` is the pad only."
- **`docs/UI_TEST.md`:** add a section **"Rebirth + scale"**:
  - Spam-upgrade Singularity Core 20× and its size doesn't change. Same for
    Core Engine.
  - The pad shows `LV n/15` and stops at ×5.
  - `/rebirthready` lights the portal: the swirl spins and the label reads
    READY.
  - The panel's two-step confirm works.
  - After a rebirth: cash $0, Basic LV 1, others locked, pad ×1, gacha $250,
    items and pedestals intact.
  - The HUD pill, leaderstats Rebirths and the banner all show.
  - Rejoining keeps Rebirths.
  - A 2-player test: the other player sees the banner, but not your portal
    label or prompt.
- `luau-lsp analyze`: no new errors (the 2 SparkleEmitter ones stay). PlotLayout
  assertions pass.
- Commit per phase, push `world-redesign`, and comment a summary on PR #4.
