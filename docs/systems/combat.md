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
  hook grants rebirth weapons + `WeaponUnlocked` (the tutorial-style card);
  Roblox `Tool`s in the Backpack, given on every spawn; the default Backpack
  bar is replaced by the weapon bar (below). **Rules:** only Rebirth 1+ vs Rebirth 1+; no hits for 5 s after
  spawning; a hit ragdolls 1.5 s with knockback (+ an upward kick), then 3 s
  immune (a shimmer). **Server authority:** `RequestHit { Weapon,
  TargetUserId?, Origin, Direction }` (C→S) is re-checked: owned AND
  equipped, the server cooldown (`TakeCooldown`), both sides' eligibility
  (`WhyNotHittable`), the attacker not carrying / ragdolled, melee range
  from the server roots + `RangeSlack` and in front, ranged by a server
  raycast; `RemoteGuard` numbers and rate limit. The server owns Player
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
  in-code clips (and a live server needs them).
- **Knockback v2 (PlatformStand + velocity):** the first server launch
  (`humanoid:ChangeState(Physics)` on the server plus `ApplyImpulse`) moved the
  Bat target 0.1 studs: a player's Humanoid state is not the server's to set,
  so the Humanoid stayed in Running and its ground controller braked the
  horizontal velocity to almost nothing within a few frames, and the old
  owner's client could overwrite the velocity for a frame or two after
  `SetNetworkOwner(nil)`. Now (`CombatService.launch`): 1. `PlatformStand =
  true` on the server (replicates, the ground controller is off; the client
  keeps its own `ChangeState(Physics)`), 2. `SetNetworkOwner(nil)` (pcall),
  3. `AssemblyLinearVelocity = launch velocity` SET on every part (not an
  impulse), 4. for the next 3 server Heartbeats it is set again, only while
  the root's flat speed is under 60% of the target, so it never adds speed
  twice. Get-up (`endLaunch`, also on respawn and on leaving): `PlatformStand
  = false`, ownership back to the player, `GettingUp`. The client fallback (only
  when ownership could not be taken) does the same on its side. The first
  attempt's speed log ("10 Heartbeats of the target's flat speed") is printed
  by `CombatService.SetLaunchLogging(true)` during `/selftest combat`; the
  measured before/after numbers are Harris's to quote from that run. Final
  numbers live in `CombatConfig` (Bat 60 + hop 25, Glove 120 + hop 25), with a
  comment: tune them in the 2-player test toward Bat 15-20 / Glove 25-30
  studs. `/selftest combat` needs the server-measured Bat >= 12 and Glove
  >= 20 studs in 0.6 s, and "standing (not PlatformStand), owned by the
  player again" after `RagdollSeconds`.
- **Hits launch the target (server-owned), first version:** before, `onHitReceived` did a
  client `root:ApplyImpulse(impulse * AssemblyMass)`. The server had just
  swapped the Motor6Ds for BallSockets (so `AssemblyMass` is only the root's
  assembly) and under fixed simulation / Server Authority a client impulse
  on your own character can be corrected away: Player2 never flew.
  `CombatService.launch` now takes `SetNetworkOwner(nil)` on the target's
  root (pcall), sets the server Humanoid to Physics, applies
  `impulse * part.Mass` to EVERY BasePart (the whole character's mass in
  total) plus the spin (`CombatConfig.SpinImpulse`; Peel AND Slap Glove), and
  hands ownership back with `GettingUp` after `RagdollSeconds`. `HitReceived`
  carries `ServerLaunch = true`; the client applies the impulse itself only
  when it is false (ownership failed), never both. `/selftest combat` with 2
  players hits the other player with the Bat and Glove and the SERVER
  measures the root's flat travel 0.6 s later (Bat ≥ 10, Glove ≥ 15 studs).
  Knockback numbers are unchanged (Bat 60, Glove 120, + hop 25): tune them
  against that check once Studio has run it.
- **Landed-hit feel (every client):** attacker's swing track at speed 0 for
  0.06 s (hit-stop); camera shake 0.15 s for the attacker, 0.3 s for the
  target; the target flashes white 0.1 s; a bigger `BONK!` / `SLAP!` pop; the
  Bonk sound slot is wired (empty). A hit on an immune / spawn-protected
  target pops "🛡 IMMUNE" for the attacker only (`HitFx { Kind = "Immune",
  Reason }` sent with `FireClient`); a target under Rebirth 1 pops "🛡 NEW
  LAB" (`Reason = "NeedsRebirth"`), a spawn-protected one "🛡 SPAWN SAFE".
- **No silent swings:** under Rebirth 1 with a weapon in hand (Studio
  `/weapons all`, the quest Slap Glove) a click toasts "Fighting unlocks at
  Rebirth 1" (at most once per 3 s) and sends nothing. `meleeTarget` no
  longer filters out Rebirth-0 players, so the server can answer the swing.
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
