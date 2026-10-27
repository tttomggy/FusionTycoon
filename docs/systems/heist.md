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

- **The rule** (`HeistConfig`): `MinRebirthsVsPlayers = 1` (both thief and
  victim, unchanged; `MinRebirths` is kept as an alias for the older
  readers) and `MinRebirthsVsRivals = 0`. The one pure check is
  `HeistService.WhyCantSteal(thiefRebirths, fromRival)`, used by both grab
  paths and `/selftest`. New players are still never robbed by veterans
  (their lab stays `Protected`).
- **Labs.** Up to `MaxRivals = 3`, in the free slots nearest the real
  players' labs (`RivalService.Step`, every `FillSeconds`). Built by
  `TycoonService.BuildRivalPlot` = the player plot's code (`buildShell`,
  walls, `PlotKit.BuildSignGate`, `createPedestals`; no generators,
  stations, Fusion Machine, claim button or spawn): plot name
  `PlotNaming.GetRivalPlotName` (`Rival_<id>`), attributes `Rival`,
  `RivalId`, `RivalName`, `SlotIndex`, **no** `OwnerUserId` / `Claimed`, so
  FactoryController and the shield code ignore it. Pedestals 1-4 only
  (`RivalConfig.PedestalCount`), no `UnlockPrompt`; the `StealPrompt` carries
  `RivalId` instead of `OwnerUserId`. The gate sign reads `RIVAL LAB` /
  `steal me!` with the lab's name in the pill, in `World.AccentRival` /
  `Gradients.Rival` (wall strips and the sign strip too).
- **Slots are shared.** `TycoonService` owns `occupiedSlots`
  (`GetFreeSlots`, `ReserveSlot`, `ReleaseSlot`). A real player always gets a
  plot: `takeSlot` asks the registered reclaimer when none is free
  (`RivalService.DespawnFarthest`), and the rival lab **farthest from every
  player's lab** (slot centres; ties go to the newest) goes first. A carry
  from a despawning lab fails cleanly first (`RivalService.OnDespawn` hook,
  `HeistService.FailRivalCarries`: the orb is "back", outcome `Failed`).
- **Orbs** are server objects. Each is rolled from `RivalConfig.TierWeights[band]`
  with band = the **lowest Rebirth count among the real players** (clamped to
  `MaxBand`), plain, except one `GoldenChance` (5%) Golden; **never**
  `BannedTiers` (Mythic, Secret; `PickTier` skips them even if a band lists
  one, and `TryRivalSteal` refuses one at grab time). If the lowest count
  drops (a newcomer joins) the orbs rolled for a higher band are re-rolled;
  they are never re-rolled upward. A stolen orb is back `RespawnSeconds`
  (90) after **delivery** (a failed carry puts it back at once). The
  respawn clock and the hourly limit read `RivalService.Now()` (unix seconds),
  injectable (`SetClock`) for `/selftest`; the guard runs on `os.clock()`.
- **Stealing.** `RequestSteal { RivalId, PedestalIndex }` (client:
  `WorldLabelController.stealMode` gives a rival prompt `Steal` for everyone
  while the pedestal is `Filled` and not `BeingStolen`). `HeistService.
  TryRivalSteal` resolves the lab, pedestal, orb and distance itself and
  rejects with the usual reasons plus `RivalGone` and `RivalAlert` (+
  `Seconds`). A rival carry is a `Carry` with `RivalId` set, `VictimUserId`
  0 and `ItemUid` `"rival:<id>:<index>"`: same hold, 45 s, WalkSpeed 12,
  deliver = root inside your own walls. **The orb is created for the thief
  on delivery** (`AddItem`, then sync + `SaveNow`); nothing belonged to a
  saved player, so there is nothing to remove or duplicate, and every
  other ending just hands the orb back. No victim shield, no loss cap, no
  `TotalSteals` (the `first_steal` goal and its marker stay PvP), no
  `HeistFeed`. The thief's `HeistEnded` carries `Rival = true`.
- **Limit.** `StealsPerHour = 12` **delivered** rival steals per rolling
  hour per player (`HeistService.GetRivalStealsLeft`); past it the grab is
  refused with `RivalAlert` and the client toasts "The rivals are on alert.
  Try again in N min". Counted at delivery, so being tagged costs nothing.
  The times are **saved** (`PlayerData.RivalSteals`, unix seconds, newest
  last, pruned to the hour on use, 64 kept): leaving and rejoining, or hopping
  servers, does not reset it. Hence `RivalService.Now()` is the wall clock.
- **The guard.** One blocky R15 NPC per lab (`HumanoidDescription` rig in
  `World.AccentRival` / `CapsuleWhite` / `Structure`, name "Lab Guard",
  server-owned, default locomotion clips). Patrols the stops in
  `RivalConfig.PatrolPoints`. A grab (`RivalService.BeginCarry`) sends it
  after the thief at `GuardSpeed` (13 vs the carrier's 12): PathfindingService
  paths recomputed at most every `GuardPathSeconds` (0.5 s) in a task, so the
  one guard loop (`GuardTickSeconds`, 0.1 s, all labs) never yields. Gives
  up `GuardLeash` (60) studs past its gate and walks home. **The tag is
  HeistService's**: after `TagGraceSeconds`, the guard's root within
  `TagDistance` of the carrier ends the carry `Saved` (the thief's toast:
  "The lab guard got you!"). Weapons work on it
  (`CombatService.ApplyGuardHit`, melee box or ranged ray): it falls over for
  `GuardStunSeconds`, can't tag while down and loses the chase, so a friend
  can cover you (Rebirth 1+, like all weapons). It has no health.
- **Teaching.** `tipRival` (`tutorial.md`). The red hand markers on
  grabbable pedestals work on rival pedestals too; `stealHowTo` and the
  `first_steal` marker skip them.
- **Safety.** Rivals are not `Player`s: never in leaderboards, friend counts,
  the notification queue or analytics player counts, and they never take
  anything from anyone. No new lights or `Highlight`s (the standard
  `PedestalVisuals`); the owner-only EMPTY pill is disabled on a rival
  pedestal (it has no owner to hide it from). The remote fuzz sends junk
  `RivalId` payloads.
- **Analytics.** Funnel `FirstRivalSteal` right after `FirstFuse` (the later
  steps renumbered; pre-launch); custom `RivalStealDelivered` /
  `RivalStealTagged` (guard tag or a weapon knock) / `RivalStealTimeout`
  (field: tier), `RivalGuardHit` (weapon).
- **Economy** (`tools/econ_sim.py 30 12 --fuse=2 --rivals`; numbers in
  TycoonConfig's header): neutral. Rebirth 1 ~0:51 with vs ~0:50 without
  (-3%, seed noise), Rebirth 2 +1%, Rebirth 3 -1%; fastest decile Rebirth 1
  ~0:41 (target >= 0:35). It does NOT come sooner: a rival orb is a Common /
  Rare / Epic the gacha gives anyway; the value is the steal in minute 3.
- **`/selftest rivals`** (also section 16 of the full run): a solo server
  fills its labs (ownerless, 4 steal pedestals, no Fusion Machine, the RIVAL
  LAB sign, only Common / Rare / Epic at Rebirth 0); a stand-in player joining
  a full server displaces the farthest rival and gets its slot (stand-ins via
  `TycoonService.SelfTestCreatePlot`); the Rebirth rule; a Rebirth 0 steal end
  to end (grab, second grab refused, delivery creates the orb, the 90 s timer,
  the respawn on an injected clock); the guard's tag returns the orb and
  creates nothing (skipped if the guard rig did not build); a weapon stun;
  `StealsPerHour` and the hour later; a despawn mid-carry with no error and
  nothing created; 10 000 draws per band with no Mythic / Secret and ~5%
  Golden; `PickTier` skipping a listed banned tier. Run it in Studio: the
  steal parts need the tester's character and a claimed lab.
- **Not covered by code in this repo's checks**: the guard's pathing and
  animation and the client visuals were not run in Studio when this was
  written (`luau-lsp analyze` is clean and the pure rules were run in the
  Luau CLI). Check `docs/UI_TEST.md`-style: walk to a rival lab at Rebirth 0,
  hold E, run home, get tagged once, wait 90 s.
