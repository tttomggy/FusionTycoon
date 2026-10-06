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
success = next tier, fail = keep your best input) → your best 4 items go on
the pedestals **by themselves** for passive income → Multiplier Pad
multiplies ALL income → Rebirth (the bottom bar's REBIRTH button or the
Portal, back-right corner) → hunt Secrets, mutations and the Index.

### Economy rules

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
  $/s is `TycoonConfig.GetStackCashPerSecond(item)` (=
  `GetItemCashPerSecond(tier, MutationConfig.List(base, events))`).
- Every service syncs the client with `PlayerDataService.SyncTycoon(player)`.
  Do not hand-build SyncTycoon payloads.
- Each plot builds its own Fusion Machine (`FusionMachineService.Build`,
  called from `TycoonService.createPlotForPlayer`).
- **Monetization "never" list** (details in `docs/systems/monetization.md`):
  no fake discounts or countdowns, no pressure copy, no purchase prompt
  after a loss, no Robux price typed into the UI (live prices only), and
  nothing sold that helps a thief or protects a lab (weapons and power-ups
  are earned, never sold).
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

## System docs (read the one your task touches)

| System | Doc | Main code |
|---|---|---|
| Items, fusion, mutations (stacking), auto-display, rebirth, Index, reveal settings, odds board, MAX upgrades | `docs/systems/items-and-fusion.md` | FusionService, ItemService, RebirthService, MutationConfig, FusionConfig |
| 2nd floor | `docs/systems/second-floor.md` | FloorKit, PlotLayout.Floor2 |
| Quests & power-ups | `docs/systems/quests.md` | QuestService, QuestConfig |
| Combat | `docs/systems/combat.md` | CombatService, CombatConfig, CombatController |
| Tutorial 2 (banner, dotted path, hand, progressive HUD) | `docs/systems/tutorial.md` | TutorialService, TutorialConfig, TutorialController, HudGate |
| Saves & offline earnings | `docs/systems/saves-and-offline.md` | PlayerDataService, OfflineService |
| Studio commands, `/trailer`, `/selftest` | `docs/systems/studio-commands.md` | DebugService, TrailerController |
| Events | `docs/systems/events.md` | EventService, EventConfig, EventController |
| Sounds | `docs/systems/sounds.md` | SoundConfig, SoundKit |
| Monetization (shop, deals, offers, receipts) | `docs/systems/monetization.md` | MonetizationService, ShopConfig, ShopController |
| Daily rewards & playtime gifts | `docs/systems/rewards.md` | RewardService, DailyConfig, GiftConfig |
| Leaderboards, analytics, Admin Abuse | `docs/systems/leaderboards-analytics-admin.md` | LeaderboardService, AnalyticsKit, AdminService |
| Heist, LOCK, shields | `docs/systems/heist.md` | HeistService, HeistConfig, HeistController |
| File tree | `docs/systems/file-layout.md` | |
| Service table, remote list | `docs/systems/architecture.md` | |

When you change a system, update its doc (not this file) unless a rule here changes.

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
- **Pills:** `UIKit.Pill` always builds a fill Frame (layout props,
  colour or gradient, corner, stroke) with the clear TextLabel inside, and
  returns the label (set `.Text` on it). Show / hide / lay out / parent a
  hit area to the pill through `UIKit.PillRoot(pill)` or
  `UIKit.SetPillVisible(pill, visible)`; never `pill.Visible` or
  `pill.Parent` from the caller's side of the pill. `UIKit.MutationPill`
  returns the fill Frame. (Plain-colour pills used to BE the label, so
  hiding `.Parent` hid the SHOP button and the whole SHOP / GIFTS row.)
- **Contrast rule:** on any gold, yellow or orange fill, text is **white**
  with the ink stroke (the UPGRADES / ITEMS / INDEX look), never dark brown
  or gold-on-gold. `UITheme.IsWarm` / `IsWarmPair` / `TextOn` decide it;
  `UIKit.Button` / `SetButton` / `Pill` and BillboardKit's `Pad` / `Chip`
  pills apply it by themselves (a warm Style ignores `TextColor3`). A
  hand-built label on a warm fill uses `UITheme.WarmText` +
  `WarmTextStroke`. There is no dark "gold text" token.
- **Selected state:** a tab / chip / segment row's selected item is the
  UPGRADES green with white text, the rest the muted panel colour:
  `UIKit.SetSelected(button, selected)` for a UIKit.Button,
  `UIKit.SetSelectedFill(gui, selected, unselected?)` for a plain frame (or
  a Pill with `Gradient = Gradients[UIKit.SELECTED_STYLE]`). A tap calls
  `UIKit.SelectFeedback(gui)` (UIScale 0.94 → 1 + the Toast sound).
- **Card placement:** every `UIKit.Modal` and centred card lives in the
  band from `UIKit.GetCardTop()` (top bar 58 + 8; on a phone also past the
  170 × 60 Roblox buttons after the 0.8 scale: 79 logical) down to the
  HUD's bottom row (`UIKit.GetCardBottom()`: 99 / 95 logical), never over
  it, and is **centred in that band** (`UIKit.GetCardY(visualHeight)`,
  where visualHeight is what you SEE: the panel plus its shadow, after the
  size cap and the fit scale; the UIScale shrinks about the top-centre
  anchor, so the top stays put): a short card on a 1080p screen sits
  mid-screen; a card that fills the band, as on phones, starts at
  GetCardTop and shrinks to fit. The math is pure and viewport-explicit
  (`GetCardYFor`, `PlanModalFor` used by every Modal's placeRoot,
  `PlanCardFor` used by `FitHeight`), so `/selftest`'s "cards centred"
  runs it at 1920×1080, 1366×768 and 844×390 and measures the live
  cards (`CheckCardPlacement`: centre within 2 px, inside the band).
  The event info card is centred too (FitHeight, re-placed when its
  height changes); side cards (offer, Starter, deal) and the bottom fail
  card stay where they are. Horizontally centred. The desktop
  chat (`UIKit.CHAT_WIDTH` 400 px) only slides a card right when its left
  edge overlaps it and there's room (`GetCardShift`); never down.
  `FitContent` modals (Fuse, Daily, Rebirth, How to Heist, welcome-back)
  keep their design height and shrink as a whole; centred result cards do
  the same through `UIKit.FitHeight`. Every modal's DisplayOrder is above
  the HUD's (`/selftest` checks it).
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

### Type checker

`luau-lsp analyze` has 2 known pre-existing errors in `Shared/VFX/SparkleEmitter.lua` (lines 17, 35). Leave them alone unless asked; a clean run means no errors in the files you touched. Details: `docs/systems/architecture.md`.

### Remotes

`ReplicatedStorage.Shared.Network.RemoteEvents` is the only place remotes are
created; it builds the container folder (named `RemoteEvents`) on the server
and makes the client `WaitForChild` it. Never call `Instance.new("RemoteEvent")`
in a service. To add one: add the name to `REMOTE_EVENT_NAMES` with a comment
stating direction, then connect it in `:Init()`.

The full remote list (names, directions, payloads) is in `docs/systems/architecture.md`.

### Sync hooks

`PlayerDataService.OnSync(callback)` registers a function that runs
synchronously at the start of every `SyncTycoon`, before the snapshot is
built, so whatever it changes ships in that snapshot (GoalService uses it to
pay goals and publish `GoalProgress`). Hooks must not call `SyncTycoon`
themselves. It is a plain callback list on purpose: a BindableEvent handler
would run deferred, after the snapshot was already sent.

### Server authority

Remote handlers validate numbers with `RemoteGuard.Int` (a NaN or ±inf
passes `math.floor` + a range check) and rate-limit anything that syncs
or loops with `RemoteGuard.Allow`. Cash only moves through
`PlayerDataService.AddCash` / `SpendCash`, which refuse non-finite and
negative amounts and keep cash in [0, 1e300]; the leaderstats Cash column
is a StringValue (an IntValue overflows past int64).

Services never trust client-supplied ownership, tiers, or instance references.
Resolve everything server-side from the requesting `Player` and validate before
mutating (see `HeistService`'s `onRequestSteal`, `FusionService.onFusionRequest`).

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
- **Pedestal prompts:** the client handles UnlockPrompts through
  `ProximityPromptService` (PromptTriggered/PromptShown), never by looping a
  folder's children once; server containers are built complete and parented
  last.
- **Prompts:** stations 7, pedestals 6, machine 10; all
  `RequiresLineOfSight = false`, `Exclusivity = OnePerButton`. Owner-only
  prompts carry `OwnerOnly = true` and are disabled on other clients by
  WorldLabelController.
- **Hover animation:** tag a Part or Model `FT_Hover`
  (`PartKit.SetHover`, called once it's built at its final position); clients
  animate it. The server never tweens these. **The rest pose is the
  `HoverBase` attribute** (a world CFrame `SetHover` stamps;
  `PartKit.SetHoverBase` re-stamps after a move), never a "first seen"
  pose: with streaming a Model arrives before its parts, its pivot was
  the origin, and orbs / cores were dragged to (0, y, 0), the middle of
  the street. WorldAnimationController places each part relative to
  HoverBase from the CFrame it arrived with (late or re-streamed parts
  land right; satellites are the orbit step's), one BulkMoveTo per frame.
  `/selftest` checks every target sits within its bob of HoverBase and
  inside a plot slot, before the fuzz and after a pedestal rebuild.
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

## Working style

- Change files with targeted edits; never rewrite a whole file to change a few lines.
- Keep replies short: what changed, what to test, nothing else.
