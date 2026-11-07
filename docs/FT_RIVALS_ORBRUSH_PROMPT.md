# Fusion Tycoon: Rival Lab Tiers + ORB RUSH minigame

Branch `world-redesign`. Read CLAUDE.md, `docs/systems/heist.md` (rival labs
section), `docs/systems/combat.md`, `docs/systems/events.md` and
`docs/systems/architecture.md` before writing code. Every CLAUDE.md rule
applies (UITheme only, UIKit constructors, TopStack for top centre, card
placement, PlotLayout as the geometry source, RemoteGuard, no new
Highlights, light caps, compile_check + theme_token_check + luau-lsp before
every push).

**Do NOT publish.** An ad test is running on the live build until ~Nov 10.
Commit and push to `world-redesign` only. Harris publishes after he has read
the ad results.

## Why

This is real player feedback from the live game (a Rebirth 1 player):
- "make the bots harder, it's been easy to steal." The config agrees: the guard
  chases at 13 while the carrier walks at 12, it leashes at 60 studs, and every
  lab plays by the same rules.
- "make some mini games, like fights or races, getting skills/orbs from the
  mini game."

This is the update that gives the game a second chance after the ad test, so
the bar is shippable polish, not a prototype. Every new screen, sound and
state has to look like it belonged in the game from day one.

---

## Part 1: Rival lab difficulty tiers

### 1.1 The tiers (all numbers in `RivalConfig`, nowhere else)

Every rival lab has a `Difficulty`: `Easy`, `Medium`, `Hard`, `Insane`.
Raise `MaxRivals` to 4 and fill **one lab per difficulty**. When slots are
short, they despawn in this order: Easy first, then Medium, Hard, Insane.
Insane is the showpiece and goes last. Keep the "farthest from every player"
rule as the tiebreak within a difficulty. A real player still always gets a
plot.

| | Easy | Medium | Hard | Insane |
|---|---|---|---|---|
| Orb tiers (weights) | Common 65, Rare 35 | Rare 60, Epic 40 | Epic 65, Legendary 35 | Legendary 85, Mythic 14.5, Secret 0.5 |
| Guards | 1 | 1 | 2 | 3 |
| Guard chase speed | 11 | 13 | 14 | 15 |
| Leash (studs past gate) | 40 | 60 | 90 | none (chases to your gate) |
| Stun from a weapon hit | 3 s | 3 s | 2 s | 1.2 s |
| Steal unlock (thief Rebirths) | 0 | 0 | 2 | 4 |
| Delivered steals / rolling hour / player | shared 12 | shared 12 | 4 | 2 |
| Respawn after a steal | 60 s | 90 s | 150 s | 300 s |
| GoldenChance | 5% | 5% | 5% | 8% |

- `BannedTiers` becomes per-difficulty. Only Insane may roll Mythic/Secret.
  `TryRivalSteal` re-checks the tier at grab time against **that lab's**
  allowed set, as it does today.
- **Replace the floor/role system** (`GetFloor`, `PlanRoles`, PlusOne/Floor
  pedestals, `TierWeights` bands) with the table above. Difficulty now decides
  the tiers. Delete the dead code and its selftest checks. Don't leave two
  systems behind. Keep rotation, `RespawnAt` chips, the despawn hook and
  `FailRivalCarries` exactly as they are.
- **Locked labs are a teaser, not a wall.** Anyone can see and walk into a Hard
  or Insane lab. The StealPrompt on a locked lab reads `Rebirth 4 to rob`
  (`HeistService.WhyCantSteal` gains the difficulty) and triggers nothing. The
  guards still patrol, so a new player sees the threat.
- **Insane must be beatable, but only with effort.** At 15 vs 12, you only get
  home with a Freeze Ray/Bat stun plus the speed power-up, or with a friend.
  That's intended. Prove it in 1.4.

### 1.2 Multiple guards

`Rival.Guard` becomes `Rival.Guards: { Guard }`. Each guard runs the existing
patrol/chase/home/heal code. Guards spread over the patrol points with
different start indices, so they never stack. At most **two** guards chase one
carrier; the third holds the gate (stands at `GuardHome` facing the gate). Any
guard's tag sends the orb back. A weapon stun affects one guard only.
`ApplyGuardHit` takes the guard (attribute `RivalGuard` = rival id, plus a new
`GuardIndex`). Stay inside the guard loop's budget: one loop for every guard,
path requests still throttled per guard.

### 1.3 Reading the difficulty at a glance

- **Gate sign:** the pill shows the lab's name plus a difficulty chip: `EASY`
  green, `MEDIUM` blue, `HARD` orange, `INSANE` red with a slow pulse. Add
  UITheme tokens (`World.Difficulty*`, `Gradients.Difficulty*`). Warm fills get
  white text with the ink stroke (contrast rule).
- **Insane lab extras, inside the light caps:** red Neon trim bands on the
  walls (thin bands only, no flat Neon), the gate sign reading
  `INSANE LAB · steal if you dare`, and a low red ambient sound inside the gate
  (`SoundConfig`, distance-attenuated).
- **Guards look tougher by tier:** Easy is the current look; Medium is bigger
  (scale 1.1); Hard is 1.2 with a helmet accessory; Insane is 1.35 in black and
  red with a glowing visor (Neon accent, a part, not a Highlight). Use
  HumanoidDescription and accessories only, no new Highlights.
- **Spotted cue:** when a guard starts chasing, play an alarm one-shot and show
  a red `!` billboard over that guard for 1.5 s, visible to the carrier only.
- **Odds board:** each rival lab's sign (or a small board by its gate) lists its
  tier odds in the same format as the Gacha odds board, via
  `FusionConfig.FormatPercent`.

### 1.4 Tests (add to `/selftest`)

- Each difficulty only ever rolls its own tiers: 5,000 rolls per difficulty
  through `RivalService.RollOrb`, with no tier outside the set and Mythic and
  Secret only on Insane.
- Steal gates: Rebirth 0 can rob Easy/Medium and is refused on Hard/Insane with
  the right reason; Rebirth 4 can rob all four; the per-difficulty hourly limits
  hold.
- Despawn order is Easy → Medium → Hard → Insane.
- Guard count per lab is 1/1/2/3, all upright, with at most 2 chasing one
  carrier.
- **Insane escape check:** a scripted carry from an Insane pedestal with
  (a) no help is caught; (b) a Freeze Ray stun on the chasers plus the 1.5×
  speed power-up reaches the plot. If (b) fails, tune the numbers in
  `RivalConfig` and report what you changed.
- Light budget per rival lab is unchanged (`MaxPedestalLights`). Insane trim is
  Neon parts, not lights.

---

## Part 2: ORB RUSH (minigame)

### 2.1 The loop

Every 15 minutes at **hh:07, :22, :37, :52** (deterministic on the UTC clock
like `EventConfig`, and never on an event's start minute), an Orb Rush round
runs:

1. **Call (60 s):** TopStack announces `ORB RUSH in 1:00 · win an Epic+ orb!`.
   A glowing ORB RUSH portal turns on at a fixed street spot. Add it to
   `StreetLayout` with its footprint in the assertion block. The HUD gets one
   `ORB RUSH 0:45 JOIN` pill in the left column stack, which teleports you to
   the portal. Walking into the portal (or tapping JOIN) puts you in the lobby
   queue, with a counter over the portal: `3 / 8`.
2. **Fill:** at 0:00 the round starts with everyone queued, up to 8. Fewer than
   4 humans get **bots up to 4 players**. With 0 humans queued, the round
   doesn't run.
3. **Round (90 s):** everyone teleports into the **Orb Rush arena**, a
   separate floating platform far from the plots (geometry in a new
   `Shared/Config/ArenaLayout.lua`, same rules as PlotLayout: single source and
   a require-time assertion block). Orbs rain from the sky in waves (coloured
   by a cosmetic tier: mostly white, some blue/purple/gold; gold is worth 5,
   purple 3, blue 2, white 1). Walk through one to collect it. Score = points.
4. **Steal:** a weapon hit (existing `CombatService` tools, same cooldowns)
   knocks **30% of the target's points** out as orbs that scatter around them,
   free to grab. A 2 s hit immunity follows. This is the fight part and the
   player's "steal most orbs" idea. Weapon use in the arena ignores the
   plot/Protected rules but nothing else.
5. **Last 15 s:** `GOLDEN WAVE`: only gold orbs, double drop rate, music
   intensifies. This creates a comeback window so the lead isn't decided at
   30 s.
6. **Results:** everyone is teleported back to their own plot. A centred
   results card (UIKit.Modal, FitHeight, centred in the band) shows the podium
   (1st/2nd/3rd with avatars, bots marked `BOT`) and each player's prize
   reveal, reusing the existing pull reveal so the orb pops out the same way a
   gacha pull does.

### 2.2 Prizes (all in a new `MinigameConfig`)

| Place | Prize |
|---|---|
| 1st | one orb: Epic 60, Legendary 35, Mythic 4.5, Secret 0.5 |
| 2nd | one orb: Rare 50, Epic 45, Legendary 5 |
| 3rd | one orb: Rare 80, Epic 20 |
| everyone else | cash = 90 s of their own passive income (`GetPassiveCashPerSecond` × 90) |

- Prize orbs go through `PlayerDataService.AddItem` (plain, with the normal
  pull-mutation roll if `MutationConfig` has one for pulls, otherwise plain)
  and show up in Items/Index like any other orb. Cash goes through `AddCash`
  only.
- **Anti-farm:** placement prizes are capped at **4 per player per rolling
  hour** (one per round anyway). Leaving mid-round forfeits. The round needs at
  least 10 points to place, so AFK in the arena gets nothing. A bot 1st place
  awards nothing. Prizes slide down: if a bot wins, the best human gets the
  2nd-place prize, not the 1st.
- Mirror `MinigameConfig` in `tools/econ_sim.py` (`--minigame`: a greedy player
  joins every round, wins 1st 35% of the time) and report how much it moves
  the TycoonConfig header milestones. **If any milestone moves more than 10%
  earlier, lower the 1st-place Legendary/Mythic weights until it doesn't,** and
  report the final numbers.

### 2.3 Bots (they must be able to win)

Server NPCs built like guards (`CreateHumanoidModelFromDescription`, with a
random friendly name from a list in `MinigameConfig`). One loop for all bots.
They path to the highest-value orb within reach, with a reaction delay and
skill per bot, and are rolled each round from `MinigameConfig.BotSkill`: Weak
40%, Normal 45%, Strong 15%. A Strong bot should beat an average new player
about half the time. Bots don't use weapons on players, but they can be hit and
drop orbs like anyone. Verify the bot win rate with a headless sim in
`/selftest` (100 simulated rounds of 4 bots vs a scripted "average player"
pathing to the nearest orb): the player should win 30–50% of rounds.

### 2.4 Rules that keep it clean

- You can't queue while carrying a stolen orb. A carry in progress fails if
  the player enters the portal (`HeistService.FailCarriesFor`, outcome
  `Failed`).
- No stealing, gacha, fusing or upgrading while in the arena. Passive income
  keeps paying (it's server-side), and the HUD cash ticks as normal.
- Falling off the arena respawns you on the arena's spawn ring with your points
  intact. The arena has invisible walls.
- Death or reset in the arena puts you back on the arena spawn, not your plot.
- If a player leaves the game mid-round, their orbs scatter.
- Server authority: the server owns every orb (spawn, pickup by distance check
  against the character root, scores, results). The client only renders. Rate
  limit pickups with `RemoteGuard.Allow`. New remotes go in `REMOTE_EVENT_NAMES`
  with direction comments: `MinigameQueue` (C→S), `MinigameState` (S→C).

### 2.5 Feel (this is what sells it)

- **Arena look:** a neon-ringed floating disc in the Fusion Lab palette
  (UITheme.World tokens, SmoothPlastic + Neon accents, no flat Neon circles:
  rings are SurfaceGui faces per the CLAUDE.md rule), a starry skybox-feel
  backdrop of floating lab debris, and a big score tower in the middle showing
  the top 3 live (SurfaceGui).
- **Pickup:** a pop sound pitched up with each pickup in a 1 s streak, a tiny
  `+5` floater in the orb's colour, and a light camera FOV punch on gold.
- **Hit/steal:** existing weapon hit FX, plus orbs bursting out of the victim
  in an arc.
- **Round HUD:** a TopStack slot `ORB RUSH 1:12 · You 34 · #2`, plus a compact
  live top-3 list in the left stack (not overlapping, `/selftest` checks the
  rects).
- **Countdown:** a big `3 · 2 · 1 · GO!` centre text with sound, and nobody
  moves until GO.
- **Results:** a podium animation, confetti for 1st, and the prize reveal. Then
  a `NEXT ORB RUSH at :22` line and a CLOSE button. No purchase prompt on this
  card, ever. The monetization never-list covers a loss.
- **Phone:** everything works at 844×390 (the JOIN pill, round HUD and results
  card in the band). Tap targets are ≥ 44 px.

### 2.6 Analytics

`AnalyticsKit.Custom` events: `OrbRushQueued`, `OrbRushPlayed` (value =
humans in the round), `OrbRushPlace` (value = place), `OrbRushPrize` (field =
tier). Add funnel step `FirstOrbRush` after `FirstFuse` (append only, by name).

### 2.7 Tests (add to `/selftest`)

- Schedule: `MinigameConfig.GetRoundForSlot` is deterministic and never shares
  a start minute with an `EventConfig` slot over 48 h.
- Prize roll: 10,000 rolls per place match the weights within 1.5%, and nothing
  below the floor of each place.
- A full scripted round with 1 human + 3 bots: queue → teleport → points →
  results → back on own plot. Then check the prize is in inventory, a bot 1st
  slides the prize down, and the hourly cap holds on round 5.
- The carry-fail-on-queue path works.
- Arena layout assertions pass, and the arena is ≥ 500 studs from every plot
  slot.
- Card placement check covers the results card at 1920×1080, 1366×768 and
  844×390.
- The bot-vs-average-player sim lands in 30–50%.

---

## Done means

1. `/selftest` shows 0 FAIL on PC layout and phone layout. Paste the summary
   line.
2. compile_check, theme_token_check and `luau-lsp analyze` are clean (only the
   2 known SparkleEmitter errors). Grep confirms no new line starts with `(`.
3. `tools/econ_sim.py --minigame` output is pasted, with milestone shifts.
4. Insane escape check results are pasted (caught without help; escaped with
   stun + speed).
5. Docs are updated: `heist.md` (difficulties replace floor/roles), a new
   `docs/systems/minigames.md` (with a row in CLAUDE.md's system table, since
   that's a new system), `architecture.md` remotes, and `UI_TEST.md` steps for
   both features.
6. You played one Orb Rush round yourself in Studio Play (`/orbrush now` debug
   command in DebugService to start a round immediately) and did one steal from
   each difficulty with `/rebirths 4`. Report anything that felt off, even if
   tests pass.
7. Pushed to `world-redesign`. **Not published.**

Report format: what changed, the numbers you tuned and why, what Harris should
test by hand. Keep it short.
