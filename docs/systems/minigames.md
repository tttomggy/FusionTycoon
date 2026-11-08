# ORB RUSH (minigame)

Read this file when a task touches ORB RUSH. Code: `MinigameService` (server),
`MinigameController` (client), `MinigameConfig` (every number), `ArenaLayout`
(the arena's geometry), `StreetLayout.RushPortal` (the street portal).

A 90-second arena round every 15 minutes at **hh:07, :22, :37, :52** (UTC,
deterministic from the clock like `EventConfig`; events start at :00 / :15 /
:30 / :45, so a round never shares a start minute with one; `/selftest` checks
48 h). Orbs rain from the sky, you walk through them for points, a weapon hit
steals a share of someone's points, and the top three win an orb.

## The loop

1. **Call (60 s).** `Workspace` attributes `OrbRushPhase` ("Idle" | "Call" |
   "Countdown" | "Play" | "Results"), `OrbRushCallAt`, `OrbRushStartAt`,
   `OrbRushNextAt`, `OrbRushQueued`, `OrbRushMax` carry the schedule, so a late
   joiner sees the same call. The street portal (`StreetLayout.RushPortal`, on
   the plain street at x = 0, footprint in StreetLayout's assertion block) turns
   on: pink ring, `ORB RUSH · JOIN`, a `3 / 8` counter chip. TopStack announces
   `ORB RUSH in 1:00 · win an Epic+ orb!` (a new player still in the tutorial,
   before the SHOP row opens, sees neither the line nor the pill). The HUD pill
   `ORB RUSH 0:45 / JOIN` queues you (`MinigameQueue { Action = "Join" }`, the
   server walks you to the portal); tapping again leaves. Walking into the portal
   queues too and **fails a carry in progress** (`HeistService.FailCarriesFor`,
   `Failed`); the pill refuses a carrier (`Carrying`). `WhyCantQueue` also says
   `NoCall`, `Full`, `InArena`, `NoCharacter`, `DataNotLoaded`.
2. **Fill.** At `StartAt` the queued humans (max 8) play; fewer than `FillTo` (4)
   get **bots** up to 4 (`MinigameConfig.BotSkill`); nobody queued = no round.
3. **Round.** Everyone is teleported to the arena (a spawn each; `RespawnLocation`
   becomes the arena spawn, `Player.RequestStreamAroundAsync` first), frozen for
   a `3 · 2 · 1 · GO!` countdown (sound per number), then 90 s of waves
   (`OrbsPerWave` 5 every `WaveSeconds` 2.4). Cosmetic orb tiers: white 1,
   blue 2, purple 3, gold 5 (weights 60 / 22 / 12 / 6). The server takes an orb
   when the character root is within `PickupRadius` (4.2 studs, flat), at most
   `PickupsPerTick` (6) per player per 0.1 s tick. **No pickup remote** (the
   client only renders and the one queue remote is rate limited with
   `RemoteGuard.Allow`).
4. **Steal.** A weapon hit (the existing `CombatService` tools, same cooldowns,
   `CombatService.ApplyHit` / `ApplyBotHit`) knocks `ScatterFraction` (30%, at
   least 1) of the target's points out as orbs that scatter round them
   (`MinigameConfig.SplitPoints`: they add up to exactly that), free to grab after
   0.5 s; the target is immune for 2 s (also written to the server-time
   `ImmuneUntil` attribute CombatService reads). In the arena
   `whyCantFight` skips the Rebirth gate (no plots, no Protected labs; a weapon
   must still be owned) and nobody swings during the countdown.
5. **Last 15 s: GOLDEN WAVE.** Gold orbs only, waves twice as fast
   (`GoldenWaveRateMultiplier`); a TopStack line, a riser sound and a light FOV
   punch.
6. **Results.** Everyone goes home (their saved `RespawnLocation`), the server
   sends `MinigameState { Kind = "Results", Podium, Place, Points, Prize?, Cash?,
   Capped?, NextAt }`: a centred `UIKit.Modal` card (`OrbRushResults`, FitContent,
   so the card rule centres it in the band) with the 1st / 2nd / 3rd podium
   (avatars from `rbxthumb://`, bots with a gear face and a `BOT` chip),
   confetti for 1st, your place and points, the prize line, `NEXT ORB RUSH at
   :22` and CLOSE. No purchase prompt, ever. The prize orb itself pops out through
   the normal pull card (`TycoonService.GrantRewardItem`, with the normal pull
   mutation roll); `ResultController` holds a reward reveal while the
   `OrbRushResults` card is open (up to 40 s).

## Prizes (`MinigameConfig`)

| Place | Prize |
|---|---|
| 1st | one orb: Epic 60, Legendary 35, Mythic 4.5, Secret 0.5 |
| 2nd | one orb: Rare 50, Epic 45, Legendary 5 |
| 3rd | one orb: Rare 80, Epic 20 |
| everyone else | cash = `ParticipationIncomeSeconds` (90) of their own passive income (`GetPassiveCashPerSecond`) |

- Orbs go through `PlayerDataService.AddItem` (via `GrantRewardItem`), cash only
  through `AddCash`.
- **Anti-farm.** A human needs `MinPointsToPlace` (10) points for ANY award (AFK
  gets nothing, not even the cash). At most `PlacementPrizesPerHour` (4)
  placement orbs per player per rolling hour (`state.prizeLog`, in memory: a
  round every 15 minutes can never exceed it in real time); the 5th pays the
  cash (`Capped`). A bot's place awards nothing and pushes nobody up (a human's
  prize is for their own place: a bot 1st means the best human gets the 2nd
  prize, not the 1st). Leaving mid-round forfeits. `MinigameService.PlanAwards` is
  the pure planner.
- **Economy** (`tools/econ_sim.py 60 4 --minigame`: the player joins every round,
  1st 35% / 2nd 25% / 3rd 20% / rest cash). 60 seeds, 4 h, median Rebirth 1 / 2 /
  3: 0:48:46 / 1:27:11 / 2:08:42 vs none 0:49:33 / 1:27:14 / 2:08:31, i.e.
  **+1.6% / +0.1% / -0.1%** sooner; fastest decile Rebirth 1 0:41:38 (target >=
  0:35:00). The rule was "if any milestone moves more than 10% earlier, lower the
  1st-place Legendary / Mythic weights": the first 20-seed run showed Rebirth 2 at
  +11.9%, but 30 and 60 seeds give +2.3% and +0.1%, and swapping the 1st-place
  weights for Epic only did not move it (+0.9%), so that spike was the median of 20
  seeds jumping a step, not the prize table; the weights stand. A heavier player
  (all five orbs a night at 1st place) would move it more: the sim joins every
  round and the cap is 4 orbs an hour.

## Bots (they can win)

Server NPC rigs (`CreateHumanoidModelFromDescription`), a name from
`BotNames` with a `NAME · BOT` chip, rolled Weak 40 / Normal 45 / Strong 15%. One
loop (`BotThinkSeconds` 0.2 s) for all: after its `Reaction` it picks the orb
with the best `MinigameConfig.ScoreOrb(Greed, value, distance)` within
`BotReachStuds` and `Humanoid:MoveTo`s it at its `Speed` (14 / 15.5 / 16 against a
player's 16). They never swing a weapon, but can be hit like anyone (scatter, 2 s
immunity, `BotHitStunSeconds` stand-still). `MinigameConfig.SimulateRound` is a
headless model (flat disc, idealised walking, no weapons) and `/selftest` runs it
with a seeded LCG: against 4 bots an "average player" (speed 16, 0.35 s decision,
nearest orb) wins **33 of 100** seeded rounds (38.2% of 1 000; target 30-50%),
and ~41% head to head against a Strong bot (a Strong bot beats an average player
about 59% of the time).

## Rules that keep it clean

- Entering the arena sets `PlayerDataService.SetInMinigame` (and the player
  attribute `InOrbRush`): `WhyBusy` says `InArena`, so pulls, fusing, upgrades, the
  Multiplier Pad, rebirth and stealing (both paths) refuse; passive income keeps
  paying and the HUD cash ticks.
- The arena has invisible walls (`ArenaLayout.WALL_*`) and a kill height
  (`FALL_BELOW`): falling off, or any reset, puts you back on your arena spawn with
  your points intact (death reloads the character at once; the arena
  `SpawnLocation`s are only enabled while a round runs).
- A player who leaves mid-round: their points scatter as orbs and they forfeit
  (`PlayerDataService.OnRelease` / `PlayerRemoving`).
- Server authority: the server owns every orb (spawn, pickup, scores, results);
  the client animates the fall (`FromPos` / `DropSeconds` / `Arc` attributes,
  local position changes only), plays sounds and draws the HUD.

## Geometry and look (`ArenaLayout`)

A floating disc (`FLOOR_RADIUS` 58) at `CENTER` (0, 260, 900), 500+ studs from
every plot slot (asserted at require time), SmoothPlastic with a thin Neon rim
band seen from the side and three SurfaceGui rings (the pad face's PointLight is
removed: the arena has no lights), 8 spawn points on a ring, invisible walls, a
score tower in the middle with four SurfaceGui faces showing the live top 3,
26 floating lab debris parts (client-bobbed with `FT_Hover`) and 60 far "stars".
All colours are `UITheme.World` tokens (`Arena*`, `Orb*`, `RushPortal`).

## HUD (client)

- The JOIN pill is a `UIKit.Button` (`Gradients.OrbRush`) at 52 px (58 on a
  phone, 46 px after the 0.8 UIScale, over the 44 px tap rule); the live top 3 is
  a small `UIKit.Panel`. Both go in the HUD's left column, **below the lowest
  column rect** (`HudController.GetObstacleRectsFor`), else beside its foot, else
  above the bottom row: the first spot inside the screen that overlaps no HUD
  rect and not the Roblox top-left buttons, else (phone, no room) the right edge just
  under the top bar. The HUD rects and this IgnoreGuiInset gui's `Position` offsets share
  ONE space (inset added back, `Abs + inset`), so no shift is applied (round 1's inset
  subtraction was the bug); `/selftest` measures `(AbsolutePosition + inset) / scale`.
  The pill and list are **HUD column items**: `HudController.SetColumnItem` registers
  them, `GetObstacleRects` reports their rects like every element, and
  `HudController.ColumnChanged` (fired after every column re-place) makes
  MinigameController re-place them; the list is placed with the pill's rect in the set.
  `/selftest` ("orb rush hud") checks pill vs HUD, list vs HUD and pill vs list.
- **/selftest flag:** `DebugService.runSelfTest` calls `MinigameService.SetSelfTest(true)`
  (cleared after the run, even on error): the scheduler opens no call, and a call or
  round already running is aborted. Forced rounds still work; section 17 starts them
  through `startForcedRound` (abort, start, retry once) and fails the check if no round started.
- TopStack's mission slot carries `ORB RUSH 1:12 · You 34 · #2` (key `OrbRush`;
  `GOLDEN WAVE ...` in the last 15 s).
- Pickups: a pop (`RushPop`) pitched up 7% per pickup in a 1 s streak, a `+5`
  floater in the orb's colour (`HudController.FloatPop`), an FOV punch on gold.
- Sounds (`SoundConfig`): `RushCall`, `RushPop`, `RushTick`, `RushGo`,
  `RushGolden`, `RushResults`; all reuse existing Creator Store ids at other
  speeds and were not auditioned (`/sound <slot>`).

## Analytics

`Custom`: `OrbRushQueued`, `OrbRushPlayed` (value = humans in the round),
`OrbRushPlace` (value = place), `OrbRushPrize` (field = tier). Funnel step
`FirstOrbRush`, appended at the **end** of `AnalyticsKit.FunnelSteps` (the live
funnel is numbered by index: inserting after `FirstFuse` would have moved every
later step).

## Studio

`/orbrush now [seconds]` queues you and starts a round at once (3 bots fill it);
`/orbrush call [seconds]` opens a call window; `/orbrush abort` ends it and sends
you home. `/selftest orbrush` (section 17 of the full run): the schedule over 48
h, 10 000 prize rolls per place, the award planner (bot slide-down, AFK, the cap
on the 5th), the bot win-rate model, the arena's geometry, a real 5-second round
with the tester and three bots (queue, teleport, a pickup, a fall, results, the
orb in the inventory, the hourly cap paying cash, an AFK round paying nothing),
and the carry that fails on entering the portal. The client half (results card
at 1920×1080, 1366×768 and 844×390 with every other modal; the HUD rects) is in
the normal `/selftest` cards and left-column checks.
