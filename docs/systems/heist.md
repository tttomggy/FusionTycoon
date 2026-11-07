# Heist: stealing, LOCK, shields

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Heist** (`HeistService`, every number in `HeistConfig`): from Rebirth 1,
  items **on pedestals** can be stolen by another Rebirth 1+ player;
  inventory items never are. Hold E 1.5 s on an enemy pedestal's
  `StealPrompt` (victim's shield down) → carry it home within 45 s at
  WalkSpeed 12. Delivered = the thief's root inside their own walls;
  saved = the owner within 5 studs; timeout, thief death, either side
  leaving, the victim's plot going, shutdown or `/wipe` = it goes back.
  **No thief cooldown** (Playtest 7; was 60 s): `RequestSteal` only has a
  request rate limit (`RemoteGuard.Allow`, 1 a second, burst 2). A victim
  gets a 60 s auto-shield per loss (was 120: every shield, claim / LOCK /
  loss, is 60 s at most) and loses at most 3 per 10 min (`LossCap`, what
  stops a lab being farmed). **Fairness:** the owner within
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
  - **`PlayerDataService.OnRelease(callback)`** runs before a player's
    final save on PlayerRemoving and, on shutdown, in each profile's
    `OnLastSave("Shutdown")` before its last copy is taken; HeistService
    fails that player's carries (either side) there. Delivery also needs
    both profiles active (`IsProfileActive`), else the item goes back.
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
    `HudController.SetLockChipHandler`, answered by HeistController).
    **LOCK is obvious to everyone** (HeistController, all client-side from
    `ShieldState`, no remote): the fence (`PlotLayout.ShieldFence`, 18 (covers the 2nd floor)
    studs, `World.ShieldBright` ForceField, a glowing Neon top edge per
    panel) fades in over 0.3 s and blinks through its last 5 s; a pulsing
    pink 🔒 hangs in the gate while locked; a **gate sign** every player
    sees (`BillboardKit.Chip` + `SetChipGradient`, MaxDistance 150):
    "🛡 LOCKED · 0:42" pink / "🔓 OPEN" red / "🔓 OPEN · can re-lock in 12s"
    / "🛡 PROTECTED" teal; an enemy pedestal in a locked lab reads "Locked ·
    0:42" (prompt mode `Shielded`). While up, a
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
    (precedence Hidden > Locked > Shielded > Guarded > Steal; Locked,
    Shielded ("Locked · 0:42") and Guarded are no-hold taps that only
    toast, since Roblox hides disabled prompts); HeistController draws every carrier's orb (`PedestalVisuals.
    BuildCarryOrb`, attributes `Heist*` on the Player), the thief/victim
    banners, arrows (`GoalMarkerController.SetOverride`) and fades every
    plot's shield fence, drives your LOCK console and shows GUARDED;
    HudController shows the LOCK status chip and the "?" button.

## Rival labs (NPC labs: steal from minute 3, even in an empty server)

PvP stealing is gated at Rebirth 1 (~50 min) and needs another Rebirth 1+
player, and servers hold 1-3 players, so most players never saw the game's
hook. Empty plot slots therefore hold **rival labs**: NPC-owned labs anyone
can rob from the start. `RivalService` (server) + `RivalConfig` (every
number); the steal itself is `HeistService`'s, same flow.

Rival labs come in four **difficulties**. They replaced the old floor / role
system (the least advanced player's best tier, PlusOne / Floor / Weighted
pedestals, Rebirth bands): difficulty alone decides the orb tiers, so there is
no second system.

| | Easy | Medium | Hard | Insane |
|---|---|---|---|---|
| Orb tiers (weights) | Common 65, Rare 35 | Rare 60, Epic 40 | Epic 65, Legendary 35 | Legendary 85, Mythic 14.5, Secret 0.5 |
| Guards | 1 | 1 | 2 | 3 |
| Guard chase speed | 11 | 13 | 14 | 15 |
| Leash (studs past the gate) | 40 | 60 | 90 | none |
| Stun from a weapon hit | 3 s | 3 s | 2 s | 1.2 s |
| Thief Rebirths to rob | 0 | 0 | 2 | 4 |
| Delivered steals / rolling hour | shared 12 | shared 12 | 4 | 2 |
| Respawn after a steal | 60 s | 90 s | 150 s | 300 s |
| GoldenChance | 5% | 5% | 5% | 8% |

All of it is `RivalConfig.Tiers` (`GetTier`, `IsTierAllowed`, `PickTier`,
`ShareOf`, `FormatOdds`, `SignText`, `WhyCantRob`, `LockedText`); nothing else
holds a number.

- **The rule** (`HeistConfig`): `MinRebirthsVsPlayers = 1` (both thief and
  victim, unchanged) and `MinRebirthsVsRivals = 0` (the floor). The one pure
  check is `HeistService.WhyCantSteal(thiefRebirths, fromRival, difficulty?)`: a
  rival lab needs `max(MinRebirthsVsRivals, tier.MinRebirths)`; used by both
  grab paths, the loop coach and `/selftest`. New players are still never robbed
  by veterans (their lab stays `Protected`).
- **Labs.** `MaxRivals = 4`, **one lab per difficulty**, in the free slots
  nearest the real players' labs (`RivalService.Step`, every `FillSeconds`;
  spawn order Insane, Hard, Medium, Easy, so when slots are short the labs that
  exist are the ones the despawn order keeps). Built by
  `TycoonService.BuildRivalPlot(slot, id, name, difficulty)` = the player plot's
  code (`buildShell`, walls, `PlotKit.BuildSignGate`, `createPedestals`, no claim
  button or spawn) **plus the rest of a lab in decoration mode** (below): plot
  name `PlotNaming.GetRivalPlotName` (`Rival_<id>`), attributes `Rival`,
  `RivalId`, `RivalName`, `RivalDifficulty`, `SlotIndex`, **no** `OwnerUserId` /
  `Claimed`, so FactoryController and the shield code ignore it. Pedestals 1-4
  only (`RivalConfig.PedestalCount`), no `UnlockPrompt`; the `StealPrompt` carries
  `RivalId`, `RivalDifficulty` and `RivalMinRebirths` instead of `OwnerUserId`.
- **Reading the difficulty at a glance.** The gate sign (`PlotKit.
  GetDifficultyStyle`, UITheme `World.Difficulty*` / `Gradients.Difficulty*`):
  the pill holds the lab's name in the difficulty colour, a `DifficultyChip`
  billboard over the board (`EASY` green, `MEDIUM` blue, `HARD` orange, `INSANE`
  red; the Insane chip carries `Pulse = true` and WorldLabelController breathes
  it, ±7% over 2.4 s), the wall and sign strips in the difficulty colour, and an
  `OddsChip` under the board listing the tier odds in the Gacha board's format
  (`Common 65 · Rare 35%`, `FusionConfig.FormatPercent`). Easy / Medium read
  `RIVAL LAB` / `steal me!`, Hard `RIVAL LAB` / `Rebirth 2 to rob`, Insane
  `INSANE LAB` / `steal if you dare`. **Insane extras:** thin red Neon trim
  bands on the inner wall faces (`PlotKit.BuildInsaneTrim`, parts only, no
  lights), and a low hum (`SoundConfig.InsaneHum`, played as a positional
  one-shot every `InsaneHumSeconds` while you are within `InsaneHumStuds` of the
  lab, by WorldLabelController; no looping sounds in this game).
- **A locked lab is a teaser, not a wall.** Anyone can walk into a Hard or
  Insane lab and see its guards. WorldLabelController gives a StealPrompt under
  the lab's `RivalMinRebirths` the mode `Locked` (no hold; the action text reads
  `Rebirth 4 to rob`, `RivalConfig.LockedText`) and the tap only toasts. The
  server refuses a forged grab with `NeedsRebirth`.
- **Decoration mode (a lab worth robbing).** The same builders a player's lab
  uses, with a `decorative` / nil-owner path that skips every prompt, remote,
  owner-only label and cash handler (no second copy of any geometry; PlotLayout
  stays the source): `FusionMachineService.Build(.., decorative)` (no
  FusePrompt; the odds board stays), `createGachaStation` /
  `createMultiplierStation` (owner nil: pad + hologram only, no label, so no
  "$X / pull"), `createFactoryLine` (owner nil: belt, collector and the five
  `GeneratorKit.Build(.., decorative)` generators at
  `RivalConfig.GeneratorLevels`, all below max so no generator light; no
  prompt, no label), `createRebirthPortal` (`PortalKit.Build(.., decorative)`,
  no prompt, no label). `FactoryController` runs a rival plot like a claimed
  one (attribute `Rival`; its balls have Value 0, nothing pops or pays), and a
  Power Surge's chips go over a rival's generators too. A rival lab has **zero
  ProximityPrompts but its 4 steal prompts**, no Highlight, no live owner-only
  label. Lights: a rival adds what a claimed lab's floor has (machine core,
  portal, collector) plus the lights of its 4 pedestals, nothing more: TWO per
  filled pedestal (the `PedestalLight` and the orb's own), so
  `RivalConfig.MaxPedestalLights` = 2 x `PedestalCount` = 8, exactly what a fully
  filled player lab adds. `/selftest` asserts that budget for all four labs and
  that every rival pedestal light obeys the caps (pedestal 0.8-1.6 / range 8-12,
  orb light 1, no shadows).
- **Stolen orb = empty cap + countdown.** A rival pedestal whose orb was
  delivered keeps the normal empty cap and carries the attribute `RespawnAt`
  (`RivalService` clock = unix seconds, set in `showPedestal`, cleared when the
  orb is back). `WorldLabelController` draws a small `back in 1:12` chip
  (`BillboardKit.Chip`, `PlotLayout.Pedestal.RespawnChip*`) over it, counted
  down from `Workspace:GetServerTimeNow()`; a carried (not yet delivered) orb
  shows the red STOLEN! ring as before.
- **Slots are shared.** `TycoonService` owns `occupiedSlots`
  (`GetFreeSlots`, `ReserveSlot`, `ReleaseSlot`). A real player always gets a
  plot: `takeSlot` asks the registered reclaimer when none is free
  (`RivalService.DespawnFarthest`), and the **lowest difficulty** goes first
  (Easy, then Medium, Hard, Insane last; with one lab per difficulty the
  "farthest from every player's lab" rule only breaks a tie). A carry from a
  despawning lab fails cleanly first (`RivalService.OnDespawn` hook,
  `HeistService.FailRivalCarries`: the orb is "back", outcome `Failed`).
- **Orbs** are server objects, plain except one `GoldenChance` Golden.
  `RivalService.RollOrb(difficulty)` picks the tier from the lab's weights
  (`RivalConfig.PickTier`), then `RollOrbOfTier(tier, difficulty)`; only Insane
  can roll Mythic / Secret. `TryRivalSteal` re-checks
  `RivalConfig.IsTierAllowed(lab.Difficulty, orb.Tier)` at grab time. A pedestal
  rolls at spawn, on a rotation and when a stolen pedestal comes back.
- **Rotation.** Every `RotateSeconds` (150, +- `RotateJitterSeconds` 30) a lab
  re-rolls its standing orbs (`RivalService.Step`, every 3 s, on the injectable
  clock). The first rotations of the 1st / 2nd / 3rd / 4th lab are at 0.5 / 0.75
  / 1.0 / 1.25 x the interval, and `RivalConfig.SpaceRotation` keeps any two
  labs `RotateMinGapSeconds` (10) apart. A lab waits for the next tick (the time
  stays due) while any guard is chasing, any `StealPrompt` is held
  (`PromptButtonHoldBegan/Ended`), or a player stands within
  `RotateKeepOutStuds` (14) of a pedestal ("about to grab"); a pedestal being
  carried from is never touched, and one waiting to respawn rolls when it is
  back (no extra timer). The swap cue is world-side only (no announce): a
  flash on the old orb and a shell closing on the new one
  (`RivalConfig.PopSeconds`, transient neon balls). The plot's `NextRotateAt`
  attribute (RivalService clock = unix seconds) feeds the gate sign's
  `fresh orbs in 1:48` chip (`WorldLabelController`, `PlotLayout.Gate.
  RotateChipStuds`; `fresh orbs soon` once due and held back).
- **Respawn and clock.** A stolen orb is back `tier.RespawnSeconds` after
  **delivery** (a failed carry puts it back at once). The respawn clock, the
  rotation and the hourly limit read `RivalService.Now()` (unix seconds),
  injectable (`SetClock`) for `/selftest`; the guards run on `os.clock()`.
- **Stealing.** `RequestSteal { RivalId, PedestalIndex }` (client:
  `WorldLabelController.stealMode` gives a rival prompt `Steal` for everyone
  who meets the lab's Rebirths while the pedestal is `Filled` and not
  `BeingStolen`, else `Locked`). `HeistService.TryRivalSteal` resolves the lab,
  pedestal, orb and distance itself and rejects with the usual reasons plus
  `RivalGone`, `RivalAlert` (+ `Seconds`) and `InArena` (ORB RUSH). A rival carry is a
  `Carry` with `RivalId` set, `VictimUserId` 0 and `ItemUid`
  `"rival:<id>:<index>"`: same hold, 45 s, WalkSpeed 12, deliver = root inside
  your own walls. **Speed Boots count on a rival carry**: the carry loop holds
  `CarryWalkSpeed x SpeedBoots.SpeedMultiplier` (12 -> 18) while the boots are
  on and drops back to 12 when they end (QuestService only lifts a
  normal-speed walker, so the boots never reached a carry before; PvP carries
  are unchanged). **The orb is created for the thief on delivery** (`AddItem`,
  then sync + `SaveNow`); nothing belonged to a saved player, so there is
  nothing to remove or duplicate, and every other ending just hands the orb
  back. No victim shield, no loss cap, no `TotalSteals` (the `first_steal` goal
  and its marker stay PvP), no `HeistFeed`. The thief's `HeistEnded` carries
  `Rival = true`.
- **Limit.** Delivered rival steals per rolling hour per player, **per pool**
  (`HeistService.GetRivalStealsLeft(player, difficulty)`): Easy + Medium share 12,
  Hard has 4, Insane 2; past it the grab is refused with `RivalAlert` and the
  client toasts "The rivals are on alert. Try again in N min". Counted at
  delivery, so being tagged costs nothing. The times are **saved**
  (`PlayerData.RivalSteals` = the shared pool, `PlayerData.RivalStealPools` =
  Hard / Insane; unix seconds, newest last, pruned to the hour on use, 64 kept):
  leaving and rejoining, or hopping servers, does not reset them. Hence
  `RivalService.Now()` is the wall clock. The loop coach (`GoalService.
  nearestRivalWithOrb`) only points a player at a lab they may rob and still
  have steals for.
- **The guards** (`Rival.Guards`, 1 / 1 / 2 / 3 by difficulty). Blocky R15 NPCs
  (`HumanoidDescription` rigs, server-owned, default locomotion clips), named
  after the **rival** (`Dr. Fizz`, `RivalConfig.GetShortName`) as a
  `BillboardKit.Chip` in `Gradients.Rival` (`GuardName` on the Head, MaxDistance
  `GuardNameDistance` 60, lifted with the guard's scale; the stock overhead
  name is off). **Tougher by tier** (`Model:ScaleTo`, accessories and parts
  only, no Highlight): Easy as before, Medium scale 1.1, Hard 1.2 with a helmet
  (`GuardHelmet`), Insane 1.35 in `GuardDark` / `GuardRed` with a dark helmet and
  a glowing Neon visor (`GuardVisor`). Guards spread over the patrol stops from
  different start indices and over `GuardSpread` across x at home, so they never
  stack. One loop (`GuardTickSeconds`, 0.1 s, every guard of every lab); path
  requests are throttled per guard (`GuardPathSeconds`). A grab
  (`RivalService.BeginCarry`) sends **at most `MaxChasers` (2) guards**, the
  nearest free ones, after the thief at the difficulty's `GuardSpeed` (the
  carrier walks at 12; PathfindingService paths recomputed at most every 0.5 s
  in a task, so the loop never yields); any further guard **holds the gate**
  (stands at `GuardHome` facing the gate until the carry ends). Each chaser that
  starts running sends the carrier `RivalSpotted` (an alarm once per grab,
  `SoundConfig.RivalAlarm`, and a red `!` chip over that guard for
  `SpottedSeconds` 1.5; built on the carrier's client only). A chaser gives up
  `tier.Leash` studs past its gate (Insane: never) and walks home. **It stays on
  its feet:** `FallingDown`, `Ragdoll`, `Physics` and `Seated` are disabled on
  its Humanoid, `BreakJointsOnDeath` / `RequiresNeck` off, `HipHeight` taken
  from the rig's legs (root bottom to sole, after the scale), every part
  unanchored, network owner nil. The stun's `PlatformStand` ends in ONE place
  (`recoverGuard`: PlatformStand off, pivoted upright, `GettingUp`), reached
  from the tick once `StunUntil` has passed (a second hit only moves
  `StunUntil`) and from `Despawn` for a lab that goes mid-stun. **Self-heal**
  (`healGuard`, every tick while not stunned): a root more than
  `UprightLimitDegrees` (45) off vertical for > `GuardDownSeconds` (1) gets
  `ChangeState(GettingUp)`; still down a second later, the model is pivoted
  upright where it lies. **The tag is HeistService's**: after
  `TagGraceSeconds`, ANY guard's root (`RivalService.GetGuardRoots`, the ones
  not stunned) within `TagDistance` of the carrier ends the carry `Saved` (the
  thief's toast: "The lab guard got you!"). Weapons work on **one** guard
  (`CombatService.ApplyGuardHit(attacker, rivalId, guardIndex, ...)`; guards carry
  the attributes `RivalGuard` = rival id and `GuardIndex`, melee box or ranged
  ray): it falls over for the difficulty's `StunSeconds`, can't tag while down,
  and **goes back to the chase when it is up** if its carrier is still running
  (`ResumeTarget`): a short Insane stun buys a few strides, not the orb, so the
  stun column of the table means something. It has no health.
- **The Insane check.** At 15 vs the carrier's 12 you only get home with help.
  `RivalConfig.SimulateEscape` is the kinematic model (guards run straight at
  `GuardSpeed`, stand still while stunned, give up at the leash, tag within
  `TagDistance` after the grace) and `/selftest` runs it over every pair of slots
  (pedestal to the thief's gate, +15% for bends): with the two chasers 6 studs
  behind (worst case) or 10 / 14 behind, **no help is caught on every route** and
  **a stun on both chasers at the end of the grace plus Speed Boots (18) gets home
  on every route**. Same model, same gaps: stun only escapes 0 / 132 routes at
  6 / 6 and 32 / 132 at 10 / 14; boots alone (18 > 15) escape 132 / 132. So
  boots beat the chasers on their own in the model, and the gate-holder (it
  only stands at `GuardHome`, 22 studs short of the gate, and the grace window
  has ended by the time a runner is past it) is nearly decoration; if boots alone
  should fail, raise Insane's `GuardSpeed` or move the holder to the gate mouth.
- **Teaching.** `tipRival` (`tutorial.md`). The red hand markers on
  grabbable pedestals work on rival pedestals too (a Locked prompt is not
  grabbable, so no hand); `stealHowTo` and the `first_steal` marker skip them.
- **Safety.** Rivals are not `Player`s: never in leaderboards, friend counts,
  the notification queue or analytics player counts, and they never take
  anything from anyone. No new lights or `Highlight`s (the standard
  `PedestalVisuals`); the owner-only EMPTY pill is disabled on a rival
  pedestal (it has no owner to hide it from). The remote fuzz sends junk
  `RivalId` payloads.
- **Analytics.** Funnel `FirstRivalSteal` right after `FirstFuse`; custom
  `RivalStealDelivered` / `RivalStealTagged` (guard tag or a weapon knock) /
  `RivalStealTimeout` (field: tier), `RivalGuardHit` (weapon).
- **Economy** (`tools/econ_sim.py 30 12 --rivals`, an attempt every 5 minutes
  from minute 3 at the hardest lab the player's Rebirths allow whose hourly pool
  has a steal left; `--rival-success=P` makes Medium / Hard / Insane steals land
  with probability P). 30 seeds, 12 h: Rebirth 1 0:50:30 vs 0:49:48 with no
  rivals (neutral), Rebirth 2 1:23:16 vs 1:30:28 (**8.0%** sooner), Rebirth 3
  2:02:36 vs 2:10:41 (6.2%); fastest decile Rebirth 1 **0:40:17** (target >=
  0:35:00). With only half of the Medium+ attempts landing: Rebirth 2 3.2%,
  Rebirth 3 2.8% sooner. The sim charges no run time and a tag costs nothing, so it
  is an upper bound.
- **`/selftest rivals`** (also section 16 of the full run): a solo server
  fills its labs (one per difficulty; ownerless, 4 steal pedestals, each lab's
  sign text, difficulty chip, odds line and prompt attributes, the Insane trim
  as thin Neon parts only on Insane, the Fusion Machine / Gacha / Multiplier /
  factory line / portal models with the five generators running and zero
  ProximityPrompts but the 4 steal prompts, no Highlight, no live owner-only
  label, none on the stations, the gate sign upright and square to its slot
  like a stand-in player's); every guard (1 / 1 / 2 / 3) within 20 deg of
  vertical after spawn, after a 6 s chase across the speed belts and after a
  stun plus a second hit, a guard laid on its side standing up by itself within
  5 s, the rig flags, the name label, the tier's scale / helmet / visor, no two
  guards stacked; displacement (stand-in players fill the server, then each
  further player takes the labs in the order Easy, Medium, Hard, Insane, and the
  slot); the Rebirth rules per difficulty and live (`TryRivalSteal` at Rebirth 0
  and 4 on all four labs); a Rebirth 0 steal end to end (grab, second grab
  refused, delivery creates the orb, the Easy respawn on an injected clock); the
  guard's tag returns the orb and creates nothing; a weapon stun on one guard;
  the hourly pools (Easy + Medium shared, Hard 4, Insane 2, each pool dry leaves
  the others open, `RivalAlert`); a despawn mid-carry; **orb rolls**: 5 000
  `RollOrb` per difficulty stay in the lab's tier set with weights within 3 points,
  Mythic / Secret only on Insane, Golden at the difficulty's chance; rotation
  spacing, the carried-orb and standing-player holds; on a grab at most 2 guards
  chase and the rest hold; Speed Boots on a carry (18, back to 12); the Insane
  escape model; the light budget of all four labs. Run it in Studio: the steal
  parts need the tester's character and a claimed lab.
- **Not covered by code in this repo's checks**: the guards' pathing and
  animation, the helmet / visor / scale look, the decorated labs' look, the
  difficulty chip and its pulse, the odds line and the hum were not run in
  Studio when this was written (`luau-lsp analyze` is clean and the pure rules
  were run in the Luau CLI). Check `docs/UI_TEST.md` section 46: walk to each lab
  at Rebirth 0, hold E on Easy, run home, get tagged once, wait for the respawn.
