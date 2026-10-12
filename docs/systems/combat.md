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
- **Rig diagnosis (not yet logged):** the prompt asked for a one-off Studio
  log of whether `RightUpperArm.RightShoulder` exists/enabled, whether an
  `AnimationConstraint` joins `UpperTorso` and `RightUpperArm`, and the
  place's Workspace simulation settings. That needs Studio; `findJoint`
  handles both cases, so nothing depends on the answer. Add what Harris's
  monkey shows here.
- **/selftest measures what is drawn:** `RightHand.Position` in `UpperTorso`
  space on Heartbeat (`WeaponPose.GetHandOffset`), never the joint values.
  Held: >= 1 stud (and >= 0.5 forward) from the rest pose sampled before
  equip; guns: about shoulder height; swing: >= 2 studs of hand travel;
  released: within 0.3 studs of rest and no `BaseC0` left; Bat: tool parts
  reach >= 1.5 studs clear of the UpperTorso.
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
