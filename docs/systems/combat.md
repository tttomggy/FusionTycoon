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
- **Poses** (`Effects/WeaponPose`, client, no animation uploads): while a
  weapon is in a hand (anyone's) the RightShoulder's `Motor6D.Transform` is
  set to an ABSOLUTE arm pose (hold + swing / recoil / toss), not an offset
  over Animate. Roblox's own `toolnone` plays at Idle priority and the
  idle / run animations override its arm, so an offset on top of it was not
  reliable; now the shoulder is ours while we hold (the Animator keeps the
  elbow and the rest) and when the weapon goes (`Release`) we stop writing
  and the Animator takes the arm back. The Animator rewrites `Transform`
  on its own step, so the same pose is written at RenderStepped, Stepped
  and Heartbeat: whichever lands after the Animator wins, and writing an
  absolute pose three times is harmless. The pitch/yaw are conjugated by the
  shoulder's `C0` rotation, so an avatar with a rotated shoulder still
  raises its arm forward. Nothing of ours stops or replaces the Animate
  script. Hold = arm raised (guns: straight out, pitched at your aim, pitch
  only, camera free), equip raise 0.15 s, Bat / Glove swing (wind back,
  ±75° arc across, settle ≈ 0.35 s), 0.1 s recoil, peel toss. R15 only.
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
