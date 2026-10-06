# Service table, type-checker findings, remote list

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

## Service migration table

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
| `RewardService` | `:Init()` `:Start()` | `PlayerDataService`, `TycoonService` | `--!strict` |
| `LeaderboardService` | `:Init()` `:Start()` | `PlayerDataService` | `--!strict` |
| `TutorialService` | `:Init()` `:Start()` | `PlayerDataService`, `TycoonService` | `--!strict` |
| `CombatService` | `:Init()` `:Start()` | `PlayerDataService`, `HeistService`, `TycoonService` | `--!strict` |
| `QuestService` | `:Init()` `:Start()` | `PlayerDataService`, `CombatService` | `--!strict` |

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

### Remote list

Heist remotes: `RequestSteal` (C→S `{ OwnerUserId, PedestalIndex }`),
`MarkTipSeen` (C→S `{ Id }`), `MarkDealPopup` (C→S `{ Slot }`),
`TutorialAdvance` (C→S `{ Step }` / `{ Replay = true }`), `RequestHit` (C→S),
`HitReceived` (S→target), `HitFx` (S→all), `WeaponUnlocked` (S→C),
`ClaimQuest` (C→S `{ Id }`) / `QuestResult` (S→C), `UsePowerUp` (C→S
`{ Key }`) / `PowerUpResult` (S→C) (no lock remote: LOCK is the console
prompt only), `SetSetting` (C→S `{ Key, Tier?, Value }`: RevealRule,
SfxVolume, SfxMuted, AutoFuse; SettingsConfig), `RequestShopPurchase` (C→S
`{ Key }`), `ShopPurchased` (S→C), `ShopAnnouncement` (S→all, Overclock),
`ShopAnalytics` (C→S `{ Event, Key? }`, analytics only), `ClaimDaily`
(C→S, no payload) / `DailyResult` (S→C), `ClaimGift` (C→S `{ Index }`) /
`GiftResult` (S→C), `SelfTest` / `SelfTestReport` (Studio `/selftest`
only),
`TrailerStart` (S→one admin, `/trailer`),
`HeistStarted` / `HeistEnded` (S→thief and victim; a rejected grab is
`HeistEnded { Outcome = "Rejected", Reason }`), `HeistFeed` (S→all,
Legendary+).
