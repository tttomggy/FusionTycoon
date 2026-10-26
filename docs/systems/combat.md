# Combat: weapons, hits, ragdoll

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Combat** (`CombatService`, every number in `CombatConfig`;
  `CombatController` client). Cartoon bonks: **no health, damage or
  deaths**. Weapons are **earned, never sold** (the "never" list): Bat
  (Rebirth 1, melee 7 studs, 1.2 s, knockback 60), Laser Gun (Rebirth 2,
  hitscan 60, 3 s, 35), Freeze Ray (Rebirth 3, 40 studs, 6 s, 40% speed for
  3 s, no ragdoll), Slap Glove (quest: melee 6, 2.5 s, 120) and Banana Peel
  (quest: one out, 10 s, lasts 20 s, the first enemy to step on it slips).
  `PlayerData.Weapons` (a set, sanitised, snapshot `Weapons`); an OnSync
  hook grants rebirth weapons + `WeaponUnlocked` (the tutorial-style card; the
  Studio start's join-time grant is silent, `DebugSetAll(player, true, true)`:
  five cards opened over a loading screen and tripped UIKit's no-card watchdog);
  Roblox `Tool`s in the Backpack, given on every spawn **once the data is
  loaded** (a live server spawns the character first: `onCharacterAdded`
  polls `IsDataLoaded` every 0.25 s, up to 30 s). The OnSync hook also
  refills any owned weapon missing from the Backpack and character, and the
  client's `toggleEquip` shows "Getting your weapons…" and fires
  `RequestWeaponTools` (C→S, no payload, rate-limited; `giveTools` is
  idempotent) then retries the equip once after 0.5 s. Studio:
  `/data slowload <s>` delays the next join's load to reproduce it. The default Backpack
  bar is replaced by the weapon bar (below). **Rules:** only Rebirth 1+ vs Rebirth 1+; no hits for 5 s after
  spawning; a hit ragdolls 1.5 s with knockback (+ an upward kick), then 3 s
  immune (a shimmer). **Server authority:** `RequestHit { Weapon, Origin?,
  Direction? }` (C→S; a melee swing sends only the weapon) is re-checked:
  owned AND equipped, the server cooldown (`TakeCooldown`), both sides'
  eligibility (`WhyNotHittable`), the attacker not carrying / ragdolled,
  melee by the server's hitbox (see "Server hitbox" below), ranged by a
  server raycast; `RemoteGuard` numbers and rate limit. The server owns Player
  attributes `RagdollUntil` / `ImmuneUntil` / `FrozenUntil` /
  `SpawnProtectUntil` (server time), swaps Motor6Ds for
  BallSocketConstraints (replicated) and restores them; `HitReceived
  { Impulse, Seconds, Freeze? }` (S→target: Physics state + impulse, prompts
  off) and `HitFx` (S→all: BONK! / SLIP! / FROZEN! pops, a thin Neon
  cylinder beam, plus `Swing` / `Throw`; every HitFx names the `Attacker`
  UserId, a hit also the `Target`). **Heist:** a hit on a carrying thief →
  `HeistService.KnockCarrier` (outcome `Knocked`: the orb flies home, the
  owner sees SAVED); a ragdolled player can't steal, LOCK (`Ragdolled`) or
  guard, so a bonk can open a steal. Analytics `Hit` (weapon),
  `ThiefKnocked`, `GuardKnocked`. The Rebirth panel lists each rebirth's
  weapons (`RebirthConfig.GetUnlockText`). Studio `/weapons all | reset`.
  Sound slots Bonk / Laser / Freeze / Slip / Swing / Shoot / Equip are empty
  until picked (what each should sound like: `docs/SOUNDS.md`).

## Weapons redesign: models, feel, bar

Looks and feel only: `CombatConfig` numbers, no damage or deaths, earned and
never sold, server authority are unchanged.

- **Models** (`Shared/Modules/WeaponKit`): each weapon is parts welded to a
  small `Handle` (the grip, 0.4 × 1 × 0.4), built in Handle space (+Y up the
  grip, −Z forward). `Build(id)` is the Tool `CombatService.giveTools`
  hands out; `BuildModel(id)` the anchored copy for ViewportFrames;
  `BuildPlaced()` the Banana Peel on the floor (3 curved petals, a brown
  stem, an invisible `Hitbox` the server's `Touched` listens on; the model
  pivot is the floor point). `Validate(tool)` / `GetExtent(tool)` are what
  `/selftest` runs. Rules: SmoothPlastic + thin Neon accents from
  `UITheme.World` (the Freeze tank is Glass), no flat Neon circles, every
  part `Massless` with `CanCollide` / `CanQuery` / `CanTouch` off, welded to
  the Handle by a `Weld` with the offset as `C0`, fits a 4.5-stud box.
  The Handle is invisible on the Glove and the in-hand banana.
- **In the hand:** `Tool.GripForward / Right / Up / Pos` per weapon in
  WeaponKit's `GRIPS`. The Bat tilts 25° forward ("up and forward"); the
  guns point straight forward; the glove sits on the hand. Gun muzzles and
  the Bat / Glove trail points are `Attachment`s on the Handle
  (`Muzzle`, `TrailA`, `TrailB`).
- **Poses** (`Effects/WeaponPose`, client, no animation uploads): the arm
  pose goes through the shoulder's **`C0`, not `Motor6D.Transform`**. Why:
  in 2026 Roblox ignores client writes to `Transform` while an animation
  plays (fixed simulation / Server Authority; staff confirmed it, no
  workaround), which is why the trail played but the arm hung straight down
  (the old /selftest only read back the value it had just written). The
  Animator never touches `C0`, so a `C0` write always shows. On `Hold` the
  joint's base is stored as the `BaseC0` attribute (the `BaseSize` idea);
  every frame `C0 = BaseC0 position * pose rotation * BaseC0 rotation` (the
  pose is in torso axes, so a rotated shoulder still raises the arm
  forward). It is never built from the live C0. `Release`, respawn and a
  weapon switch restore `BaseC0` and clear the attribute; if the Humanoid
  rescales the rig (live position != what we wrote) the base position
  follows it. An Avatar Joint Upgrade rig whose shoulder is an
  `AnimationConstraint` gets the same treatment on `Attachment0.CFrame`
  (`BaseCFrame`). `Transform` is never written, so walk / idle sway adds on
  top, and Animate's `toolnone` track (which also raises the arm) is stopped
  while we hold. Hold = arm raised (guns: straight out, pitched at your aim,
  pitch only, camera free), equip raise 0.15 s, Bat / Glove swing (cock
  back, ~163° of yaw arc across, settle ≈ 0.35 s), 0.1 s recoil, peel toss.
  R15 only. **Plan B** (if C0 and the attachment both fail on an avatar):
  `KeyframeSequence`s built in code, registered with
  `KeyframeSequenceProvider:RegisterKeyframeSequence`, played at `Action4`
  (Studio only until published as assets). Not built.
- **Rig diagnosis:** Harris's 2-player run printed `physics: … target root
  network owner: Player2`, so this place uses **classic client network
  ownership**, not Server Authority / fixed simulation (no property of the
  tried list was reported). That is why the launch had to be rebuilt as below.
  `/selftest combat` still prints the line each run. `WeaponPose.findJoint`
  handles both a Motor6D and an `AnimationConstraint` shoulder, and the
  tracks do not care.
- **Real animation tracks (Combat feel):** the C0 pose proved the arm can
  move, but three joints driven from code never read as a swing. Every
  weapon now plays Animator tracks (`Effects/WeaponAnimator`, local on every
  client for every character, same `onToolAdded` / `onToolRemoved` /
  `performFor` paths as `WeaponPose`; Animator tracks are not affected by
  the Transform rule). The clips are built in code in
  `Shared/Anim/WeaponAnims` (R15 `KeyframeSequence`s, only the joints a clip
  needs so walk / run keep driving the rest): `BatHold` / `GloveHold` /
  `GunAim` (looped, Action), `BatSwing` ~0.55 s (load 0.18, whip to the
  `Hit` marker at 0.28 with the torso snapping ~140° left and a front-foot
  step, follow-through, recover), `GloveSlap` ~0.5 s, `GunRecoil` 0.12 s,
  `PeelThrow` 0.35 s (Action2). Source per clip (`CombatConfig.
  AnimationIds`): an id set = that asset; empty in Studio =
  `KeyframeSequenceProvider:RegisterKeyframeSequence` (temporary id); empty
  live = the C0 `WeaponPose` fallback and one warn. While tracks play
  `WeaponPose` writes nothing (no C0, no attributes), `toolnone` is stopped,
  and the trail starts from the `Hit` marker (fallback: 55% of the clip).
  Gun aim no longer follows your pitch (a track is fixed); the C0 fallback
  still does. Joint signs / angles were authored without Studio: **judge
  them by eye** and adjust the tables at the top of `WeaponAnims`.
- **Publishing the clips:** in Studio run `/anim export`; open
  `ServerStorage.WeaponAnimExports`; for each KeyframeSequence right-click
  → **Save to Roblox**, then copy the asset id from the dialog / Creator
  Hub and paste `rbxassetid://<id>` into `CombatConfig.AnimationIds` under
  the clip's name (BatHold, BatSwing, GloveHold, GloveSlap, GunAim,
  GunRecoil, PeelThrow). Restart Play: the ids are used instead of the
  in-code clips (and a live server needs them). **Ids are set (2026-10-21):**
  all 7 clips are published on Harris's account and filled in
  `CombatConfig.AnimationIds`; the in-code clips and `/anim export` now only
  run for an empty id. `/selftest` (combat, with the live-fallback probe)
  checks each entry is `rbxassetid://<digits>` and loads on the Animator.
- **Knockback v3 (a server-made body mover):** v1 (`ChangeState` + impulse)
  moved the Bat target 0.1 studs; v2 (`PlatformStand`, `SetNetworkOwner(nil)`,
  SET `AssemblyLinearVelocity`, 3-Heartbeat re-assert) showed a velocity of
  exactly 60.0 for 10 Heartbeats in the server log and still nothing moved on
  the target's screen: the server was reading back its own write, and the
  ownership handoff on a player character is not reliable here (the target's
  client keeps simulating its character). v3 stops fighting over ownership.
  `CombatService.launch` (no `SetNetworkOwner` anywhere): `PlatformStand =
  true` on the server, then a `LinearVelocity` named `KnockbackMover` on the
  target's `HumanoidRootPart` (its own Attachment at the root's centre,
  `RelativeTo = World`, `VelocityConstraintMode = Vector`, `VectorVelocity` =
  flat direction × knockback + `UpwardKick`, `MaxForce = math.huge`), destroyed
  after `CombatConfig.LaunchSeconds` = 0.2 s; the Glove / peel add an
  `AngularVelocity` (`KnockbackSpin`, `MaxTorque = math.huge`, the
  `SpinImpulse` rate) for the same 0.2 s. Why it works: a constraint the
  server creates replicates to every client and whoever owns the assembly
  (the target's client) simulates it, whatever the ownership. If the limbs drag
  the root (more than 40% of the speed lost 0.1 s in) the same mover is added
  to `UpperTorso` too (not to every part). Clean-up: `endLaunch` (ragdoll
  timer, respawn, leaving) and a second hit destroy every `KnockbackMover` /
  `KnockbackSpin` / attachment and always reset `PlatformStand`; a new hit
  REPLACES the old mover (a launch token stops the first hit's timers from
  ending the second). The client (`onHitReceived`) keeps `ChangeState(Physics)`,
  `UnequipTools`, prompts off and `GettingUp`; it writes no velocity or impulse
  and has no `ServerLaunch` branch.
  **Measured on the target's screen:** `/selftest combat` asks Player2's OWN
  client (a `RootPos` probe) for its root just before the hit and 0.6 s after;
  the test fails if that client doesn't answer; Bat ≥ 12 studs, Glove ≥ 20, the
  server-side distance is printed next to it for comparison; 0.5 s after the
  ragdoll ends a `GetUp` probe checks, on the target client, state not
  Physics, `PlatformStand` off, no mover left. Numbers: the Bat 30, Glove 42
  (the Laser Gun and peel 20) with `UpwardKick` 25 are computed first guesses
  (speed × (0.2 s + ~0.4 s of air) + a short slide ≈ 18 and ≈ 25 + slide);
  nothing could be run, so the before / after numbers are Harris's to quote
  from `/selftest combat`.
- **Landed-hit feel (every client):** attacker's swing track at speed 0 for
  0.06 s (hit-stop); camera shake 0.15 s for the attacker, 0.3 s for the
  target; the target flashes white 0.1 s; a bigger `BONK!` / `SLAP!` pop; the
  Bonk sound slot is wired (empty). A hit on an immune / spawn-protected
  target pops "🛡 IMMUNE" for the attacker only (`HitFx { Kind = "Immune",
  Reason }` sent with `FireClient`); a target under Rebirth 1 pops "🛡 NEW
  LAB" (`Reason = "NeedsRebirth"`), a spawn-protected one "🛡 SPAWN SAFE".
- **No silent swings:** under Rebirth 1 with a weapon in hand (Studio
  `/weapons all`, the quest Slap Glove) a click toasts "Fighting unlocks at
  Rebirth 1" (at most once per 3 s) and sends nothing. The server answers
  a swing at a Rebirth-0 player with the 🛡 pop (its box finds them).
  When the server refuses a swing (`whyCantSwing`: NeedsRebirth, NotOwned,
  NotEquipped, Carrying, Ragdolled) it tells the attacker with `HitFx { Kind
  = "Refused", Reason }` and the client toasts the reason.
- **Studio test start:** `DebugConfig.StudioStartRebirths = 3` and
  `StudioGrantAllWeapons = true`; see studio-commands.md. Before this every
  Studio Play started both players at Rebirth 0, where the weapon bar is
  hidden and nobody can be hit, so the Bat / Glove "did nothing".
- **Slot switch (Swing fix 2):** Roblox fires the new tool's `ChildAdded`
  BEFORE the old tool's `ChildRemoved`, so the old release used to wipe the
  new weapon's pose (Freeze Ray and Slap Glove hung straight down).
  `WeaponPose.Release(character, weaponId)` now only releases that weapon,
  and `CombatController.onToolRemoved` re-`Hold`s any weapon `Tool` still in
  the hand, so the pose is right in either order. (Studio prints the first 8
  tool events as `[CombatController] tool event: …`; not yet read in Studio.)
- **The swing is ~0.68 s:** wind 0.18 (bat cocked over the right shoulder),
  hold 0.06, arc 0.14 (accelerating, big sweep to the left, elbow snapped
  straight at the end), follow-through 0.1 (past the left hip), settle 0.2.
  The `Waist` Motor6D twists ~0.5 rad right on the wind and ~0.6 left through
  the arc, `RightElbow` bends ~0.6 on the wind: both use the same
  `BaseC0` / `BaseCFrame` rules as the shoulder (stored on Hold, never built
  from the live value, restored and cleared on Release; AJU rigs via the
  AnimationConstraint). Slap Glove: the same shape, flat at shoulder height.
- **/selftest measures what is drawn:** `RightHand.Position` in `UpperTorso`
  space on Heartbeat (`WeaponPose.GetHandOffset`), never the joint values.
  The rest pose is sampled explicitly (server: `UnequipTools`, 0.3 s, then a
  `SampleRest` probe). Held: >= 1 stud (and >= 0.5 forward) from rest; guns:
  about shoulder height; swing: the hand's PEAK distance from its held
  position >= 2.5 studs and away from it (>= 0.3 stud) for >= 0.5 s
  (Bat and Glove); Bat: tool parts reach >= 1.5 studs clear of the
  UpperTorso; slot switches Bat → SlapGlove, LaserGun → FreezeRay,
  SlapGlove → Bat (no unequip between) measure the new weapon's held hand;
  with tracks the peak is Bat / Glove >= 3 studs, plus "a looping hold
  track plays while held", "the action track plays, is >= 0.4 s and its Hit
  marker fires once", "release: no weapon track playing", and "live
  fallback" (no id → the C0 pose still runs and restores);
  released: hand within 0.3 studs of rest, shoulder / Waist / RightElbow at
  their base and no `BaseC0` / `BaseCFrame` left. "Skipped: not an R15 rig"
  only when `RightHand` / `UpperTorso` is really missing.
- **Holding it:** `Humanoid:EquipTool` builds the `RightGrip` weld; the
  server checks it (`CombatService.GetGripProblem`: the weld exists and the
  Handle is within 1.5 studs of RightHand) when a tool is equipped and
  rebuilds the weld the way the engine does if not (with a `warn`). Grip
  values are tiny (|GripPos| ≤ 0.1) and every model part is welded to the
  Handle only.
- **Effects** (`Effects/WeaponFx`, client): swing `Trail` (white Bat, red
  Glove, during the swing only), white flash ring on a hit (BillboardGui
  circle stroke), muzzle flash (PointLight + Neon ball + sparks), cyan
  Laser beam 0.12 s, Freeze beam + sparkle cone, shot impact, frost
  particles on a frozen player (with the existing tint), the peel's thrown
  banana arc (the placed peel is hidden locally until it lands), a peel slip
  adds `Spin` to `HitReceived` (angular impulse).
- **Everyone sees everyone's:** your own pose runs the moment you click;
  the server then fires `HitFx` for every accepted swing (`Swing`, hit or
  miss, rate-limited by the cooldown), shot (`Beam` / `FreezeBeam`) and peel
  (`Throw`) with `Attacker`, and other clients run the same pose + FX on that
  player's character (they skip it when `Attacker` is themselves).
- **Weapon bar** (`CombatController`, `UI/WeaponViewport`): 64 px rounded
  slots (52 on phone), dark panel fill, a ViewportFrame with the real
  `BuildModel` slowly turning (HeistScene lighting tokens), key number
  top-left, name (12 px) under it. Equipped = lime ring + 4 px lift;
  cooldown = a radial clock-wipe (two clipped halves with a hard-edged
  rotating UIGradient) + seconds; not earned = dim model + 🔒 and "R2" /
  "R3" / "Quest" (all five slots show from Rebirth 1, quest ones locked);
  carrying = the whole bar dims. Centred 12 px above the bottom buttons; off
  at Rebirth 0 **and while the tutorial runs** (so it can never sit over the
  tutorial's action button). The unlock card shows the big turning model
  (`TutorialConfig.Card.Weapon`).
- **/selftest:** each weapon's `WeaponKit.Validate` (Handle, every part
  welded + massless, nothing collides, fits 4.5 studs), the placed peel
  (3 petals × 3 segments + a touch hitbox), and each weapon EQUIPPED on the
  tester through the server (a temporary tool, destroyed afterwards):
  `RightGrip` exists, the Handle is within 1.5 studs of RightHand, and the
  client measures the right arm (angle from hanging ≥ 0.8 rad while held;
  the shoulder moves ≥ 0.6 rad in a swing, 0.4 in the toss, 0.15 in a
  shot).

## Hold-pose selftest regression (Oct 13)

`/selftest combat` reported every melee hold "moved 0.01 studs" (and the C0
live fallback 0.03) where the previous build measured 2.38 / 2.57. Cause not
provable without a Studio run, so the probes now say it: every hold / fallback
/ release Detail carries `describeRig` (rest and held hand offsets, every
playing track with priority, current / target weight and time, the shoulder's
C0 against its stored BaseC0, which pose owners are up, whether
`forceFallback` is still on, Humanoid state / PlatformStand / root Anchored).
Candidates it distinguishes: (a) rest sampled while the previous hold track
still fades; (b) the hold track at weight 0 or out-prioritised; (c)
`forceFallback` left on. Fixes made without changing the approved clips: rest
is only sampled once nothing is held, no track plays, no BaseC0 is stored, no
tool is in the character and the hand holds still for two samples
(`waitForRest`; if it never settles that is its own FAIL with the dump);
the fallback probe waits for the same, always switches the force flag back
(pcall around `Hold`) and fails if it is still on; `WeaponPose` is now also
driven from Heartbeat when `RenderStepped` has not run for 50 ms (a Studio
test client in a background window stalls rendering, and the C0 pose with it).

## Server hitbox (melee), with a verdict line per swing

Why: in 2-player Studio tests the Bat and Glove did nothing in real play while
`/selftest combat` passed. The client picked the target (`meleeTarget`) and
sent `TargetUserId` through `RemoteGuard.Int(value, 1, 2^53)`, and **Studio's
local players have NEGATIVE UserIds** (-1, -2), so every melee hit was dropped
before `ApplyHit`, silently. The selftest called `ApplyHit` directly and
never walked the chain. Detection is now the server's, the usual Roblox way.

- **Client:** `RequestHit { Weapon }` and nothing else for melee (no
  `TargetUserId`, `meleeTarget` is gone). The swing animation, trail and sound
  still run on the click. `CombatController.Use(weaponId)` is the function
  `Tool.Activated` calls (and what `/selftest` calls on the attacker's client).
- **Server:** after the usual checks (cooldown, `whyCantSwing`) the swing's
  `Swing` HitFx goes out at once, then `CombatConfig.MeleeHitDelay` (0.15 s,
  about the clip's `Hit` marker) later `resolveMelee` runs
  `Workspace:GetPartBoundsInBox` on the **weapon's** box (Polish 12: Bat
  `MeleeBox` 9 × 8 × 10, forward 4.5; Glove 11 × 8 × 11, forward 5; each in
  its `CombatConfig.Weapons` entry, `CombatConfig.GetMeleeBox(weapon)`), its
  centre `MeleeBoxForward` studs in front of the attacker's root along
  its flat facing, an `OverlapParams` excluding the attacker's character.
  **Lag tolerance:** the service keeps each root's last
  `CombatConfig.HistorySeconds` (0.3 s) of positions (one Heartbeat sample
  per player); a swing stores its request time and its box, and a player
  whose root was inside THAT box at the request time counts too, as well as
  whoever overlaps at the delayed check. **Range check:** nobody further
  than the weapon's `Range` + `RangeSlack` from the attacker is ever hit
  (a sanity limit). The
  distinct characters become players (an accessory or tool part counts), nearest
  first. The **Bat** hits the nearest one `WhyNotHittable` allows; the **Slap
  Glove** every valid one (a sweep). Every other player in the box gets the
  attacker-only 🛡 pop with its reason (`notifyIgnored`: Immune,
  SpawnProtected, NeedsRebirth). Ranged and the Banana Peel are unchanged.
- **Log (Studio, `RunService:IsStudio()`, until the combat feel is final):**
  one line per swing, e.g.
  `[Combat] Player1 Bat: box found [Player2 3.2 studs] -> HIT Player2`,
  `... box found [] -> MISS`, `... box found [Player2 3.0 studs] -> Player2 Immune`.
  `CombatService.GetLastVerdict(player)` keeps the last one (`Seq`, `Found`,
  `Hit`, `Line`) for the selftest. `/combat box` toggles drawing the box (a red
  transparent part for 0.2 s per swing, sized to that weapon's box, Studio only).
- **Selftest (`/selftest combat`, 2 players)** now walks the whole chain:
  Player2 is put 3 studs in front of Player1 (facing each other, immunity
  cleared), the tool is equipped for real, **Player1's client** clicks it
  through `CombatController.Use`, the server's verdict must say `HIT Player2`
  and Player2 must fly (≥ 12 studs Bat, ≥ 20 Glove in 0.6 s, measured on
  Player2's own client). (Polish 12: the hit case is **6 studs in front and 3 to the side**, a near
  miss the old 6 × 6 × 7 box whiffed.) Then Player2 is put out to the side
  beyond the weapon's box (box half-width + 2.5: **7 studs for the Bat**, 8
  for the Glove; an arm reaches 2 in): the verdict is `MISS` and Player2 does not move. The held-weapon
  thresholds (clearance 1.5, swing peak 1.5) scale with the avatar's height
  (× height / 5, clamped 0.6-1.0) so the small monkey avatar passes.

**Pose follows the hand.** `CombatController.reconcileHeld` runs on every tool
Add / Remove: a pose whose Tool left the character is released (all its hold
and action tracks stop), and the weapon actually in hand is held, whatever
order a slot switch's events arrived in. `WeaponAnimator.Hold` always stops
every track of the previous weapon first.
