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
`RequestUpgrade`) →
Gacha Pad pulls → fuse 2 same-tier items at your plot's Fusion Machine
(success = next tier, fail = 1 item of the same tier back) → display the best
4 items on pedestals for passive income → Multiplier Pad multiplies ALL income.

- All economy numbers live in `TycoonConfig.lua` (costs, pedestal income,
  multiplier levels, gacha price curve) and `FusionConfig.lua` (fusion success
  odds, gacha drop rates). They were tuned with a greedy-player simulation
  of a brand-new save; the target milestones are in TycoonConfig's header.
  Re-run `tools/econ_sim.py` after changing any economy number; keep its
  tunables in sync with TycoonConfig/FusionConfig.
- Passive income has ONE formula: `TycoonConfig.GetPassiveCashPerSecond`,
  used by the server payout tick and the client HUD. It is all income: the
  factory line's cash balls are a client-side picture of it and never pay.
- Every service syncs the client with `PlayerDataService.SyncTycoon(player)`.
  Do not hand-build SyncTycoon payloads.
- Each plot builds its own Fusion Machine (`FusionMachineService.Build`,
  called from `TycoonService.createPlotForPlayer`).
- Saves: a failed DataStore load kicks the player in live games (never
  overwrites the real save); in Studio it plays on a blank profile that is
  never saved. PedestalDisplays are stored with string keys on disk.
- Studio chat commands (DebugService): `/cash <amount>`, `/resetmultiplier`,
  `/wipe`.

## Layout

```
src/ReplicatedStorage/Shared/
    Config/      shared config tables (PlotLayout, StreetLayout — the street
                 and speed belts, TycoonConfig, FusionConfig, GoalConfig — the
                 ordered onboarding goals, …)
    Modules/     shared runtime modules: UITheme (every UI colour/font token
                 and the World part colours), BillboardKit (world labels and
                 SurfaceGuis), PartKit (part/cylinder helpers, FT_Hover
                 tagging), PlotKit (plot shell + sign gate), StationKit
                 (station pads + holograms), DropperKit (dropper model),
                 GeneratorKit (the five factory-line generators + their
                 states), FactoryKit (factory belt + collector, and the
                 ball path), PedestalVisuals, NumberFormat
    Network/     RemoteEvents.lua — single source of truth for remotes
    VFX/         SparkleEmitter, ImportedEffects, imported *.rbxm VFX assets
src/ServerScriptService/
    Bootstrap.server.lua   entry point; hands Services/ to ServiceManager
    ServiceManager.lua     loading + Init/Start lifecycle
    Services/              one ModuleScript per service (GoalService pays
                           and advances goals from PlayerDataService.OnSync;
                           WorldService builds ground, street and FREE LAB
                           placeholders)
src/StarterPlayer/StarterPlayerScripts/
    Controllers/  client controllers (one per domain): HudController,
                  ToastController (error/neutral toasts), ResultController
                  (fusion/gacha result cards), AnnouncementController
                  (banners), WorldLabelController (hides owner-only labels,
                  and any label within 7 studs of the camera),
                  WorldAnimationController (FT_Hover spin/bob, client-only),
                  GoalMarkerController (points at the current goal),
                  BeltController (client-only belt chevrons),
                  GeneratorController (world Buy/Upgrade prompts, upgrade
                  toast + bump), FactoryController (client-only cash balls
                  on every nearby factory line, collector pops)…
    Effects/      RevealEffects
    UI/           UIKit (Panel/Button/Pill/Badge/TierOrb/ProgressBar/
                  Shadow/PopIn/PopOut/Modal), UpgradesPanel, ItemPickerUI
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
| `FusionService` | `:Init()` `:Start()` | `PlayerDataService` | `--!strict` |
| `ItemService` | `:Init()` `:Start()` | `PlayerDataService`, `TycoonService` | `--!strict` |
| `LightingService` | `:Init()` | — | `--!strict` |
| `DebugService` | `:Init()` `:Start()` | `PlayerDataService` | `--!strict` |
| `GoalService` | `:Init()` `:Start()` | `PlayerDataService`, `TycoonService` | `--!strict` |
| `TycoonService` | `:Init()` `:Start()` | `PlayerDataService` (module scope, leaf), `FusionMachineService`, `WorldService` (Start) | `--!nonstrict` ⚠ |
| `FusionMachineService` | `:Init()` | — | `--!nonstrict` ⚠ |
| `WorldService` | `:Init()` | — | `--!strict` |

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
  from `UITheme.World`); the ground's Grass is the one exception. No Basalt,
  Slate, Metal or Plastic. **No flat Neon circles:** Roblox draws a cylinder
  top as a fan of triangles that bloom unevenly ("pizza slices"). Glowing
  rings on flat surfaces are SurfaceGui faces (`BillboardKit.BuildPadFace`);
  Neon cylinders are only thin bands seen from the side (station/machine
  rims).
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
