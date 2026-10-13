# Combat feel: real swing animations, hits that launch, Studio skips the tutorial (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 10 lines or fewer.

---

Harris tested `e75ddb3` on Oct 13: a solo clip on his monkey avatar, plus
a 2-player Studio test.

- **Bat:** the hold and the swing show, but it's still a small wrist flick
  on a small avatar. The waist twist can't be seen at all. Harris: "not
  sure that's the animation I'm looking for".
- **Glove:** it's held out now, but the slap is a tiny wiggle.
- **2-player test:** Player1 stands next to Player2 and swings the Bat and
  the Glove again and again.
  - `BONK!` pops at least once, and `FROZEN!` / `SLIP!` show too, so the
    hits register.
  - But **Player2 never flies**. To Harris it "doesn't do anything to that
    player".
- Harris wants the tutorial skipped every time in Studio. He's happy with
  it now.

The procedural C0 pose was the right way to prove the arm *can* move. But
three joints driven from code will never look like a real swing. Move to
real animation tracks.

## 0. Studio skips the tutorial

- Add `DebugConfig.SkipTutorialInStudio = true`. When it's on, in Studio
  only (`RunService:IsStudio()`), every player who joins (Player1, Player2
  …) gets the tutorial marked Done on load. The full HUD shows, and no
  banner, cards or hand appear.
  - Don't grant the tutorial's rewards and don't touch free pulls. Only
    the Done state changes.
  - It's in-memory only: never write it to a save as anything but Done.
- `/tutorial reset` and Settings' "Replay tutorial" still run it in that
  session. Skipping only happens on join.
- A live server never skips. Assert `not IsStudio() → no skip` in
  `/selftest`. `runTutorialSelfTest` swaps the tutorial state as it does
  now, so it still drives every step.
- Document it in `docs/systems/tutorial.md` and `studio-commands.md`.

## 1. Hits must launch the target

**Prove it first.** Add a 2-player `/selftest combat` check, which needs
Test → 2 players. The selftest's Player1 hits Player2 through
`CombatService.ApplyHit` with the Bat. On the **server**, measure how far
Player2's `HumanoidRootPart` has moved 0.6 s later.

- Needs ≥ 10 studs for the Bat and ≥ 15 for the Glove (knockback 120).
- Clear `ImmuneUntil` / `SpawnProtectUntil` first, and restore them after.
- **This must FAIL on today's code.** Quote the numbers.

Also print, once, in that check: the Workspace physics/authority settings
(the fixed-simulation / Server Authority properties, whatever their 2026
names are) and `root:GetNetworkOwner()` for Player2. Put the answers in
`docs/systems/combat.md`. The "Rig diagnosis" item there is still empty;
fill it in too.

**Likely cause:** the impulse is applied only on the target's client
(`onHitReceived` → `root:ApplyImpulse`). Meanwhile the server has just
swapped the Motor6Ds for BallSockets, so `AssemblyMass` is now only the
root's assembly, and with fixed simulation / Server Authority a
client-side impulse on your own character can be corrected away.

**Fix, so it works whichever mode the place is in:**

- **Server-owned launch:** on the server, during the ragdoll:
  1. `pcall(root.SetNetworkOwner, root, nil)`;
  2. apply the impulse on the server, using the **whole character's
     mass**: the sum of every BasePart's `Mass`, not `AssemblyMass`;
  3. on get-up, give ownership back to the player with `pcall`.
- Keep the client impulse only as a fallback when `SetNetworkOwner`
  fails. Never apply both.
- Tune for a launch you can read: Bat ≈ 15–20 studs plus a hop, Glove
  ≈ 25–30 studs with a spin. Banana slip stays as it is. Check these
  against the selftest numbers.
- **Feel on a landed hit, for both players:**
  - Hit-stop: the attacker's swing track at speed 0 for 0.06 s.
  - Camera shake: 0.15 s for the attacker, 0.3 s for the target.
  - The target flashes white for 0.1 s.
  - A bigger `BONK!` / `SLAP!` pop.
  - Sounds: the Bonk slot (it's empty for now, so wire it and leave it
    silent).
- **Immune or spawn-protected targets:** a hit on one is still silent
  today. Pop a small "🛡" (or "IMMUNE") on the target, for the attacker
  only, so a hit that does nothing never looks like a bug.

## 2. Real animation tracks for every weapon

Play them on the Animator (Animator tracks replicate and are not
affected by the Transform rule). C0 stays only as a fallback.

**Build the clips in code.** Make a new
`ReplicatedStorage/Shared/Anim/WeaponAnims.lua`:

- Each clip is R15 keyframes (joint name → CFrame per keyframe, with an
  easing style per pose).
- `WeaponAnims.Build(name)` returns a `KeyframeSequence`.
- Key **only** the joints a clip needs, so walk and run still drive the
  rest.

| Clip | Priority | What it looks like |
|---|---|---|
| `BatHold` (looped) | Action | Bat up on the right shoulder, elbow out, slight crouch. |
| `BatSwing` (~0.55 s) | Action2 | A big **horizontal baseball swing**. **Load** 0.18 s: bat back behind the head, torso twisted ~70° right, weight on the back leg. **Whip** 0.1 s: front foot steps, hips and torso snap ~140° left, arm fully extended. **Follow-through** 0.12 s: bat wraps around past the left shoulder. **Recover** 0.15 s. |
| `GloveHold` (looped) | Action | Glove raised beside the head, palm forward, ready. |
| `GloveSlap` (~0.5 s) | Action2 | A **huge open-palm slap**. **Wind-up** 0.2 s: arm pulled far back and out, torso turned away, a lean back. **Slap** 0.08 s: a wide flat arc across at head height, lunging forward a step. **Follow-through** 0.1 s: arm across the body. **Recover** 0.12 s. |
| `GunAim` (looped) | Action | Both arms forward, left hand under the gun, slight lean. |
| `GunRecoil` (0.12 s) | Action2 | Kick up and back. |
| `PeelThrow` (0.35 s) | Action2 | Overhand toss with a step. |

Make these exaggerated, the cartoon kind that kids' Roblox combat games
use, so it reads from 30 studs on a small avatar. Copy the *motion*, not
anyone's assets.

**Ids:** add `CombatConfig.AnimationIds = { BatSwing = "", … }`, filled in
by Harris after he publishes.

- An id is set → `Animation.AnimationId` = it.
- Empty and in Studio → `KeyframeSequenceProvider:RegisterKeyframeSequence`
  (a temporary id; Studio only).
- Empty and live → fall back to today's C0 `WeaponPose`, and warn once.

**Export command:** `/anim export` puts every clip as a `KeyframeSequence`
in `ServerStorage.WeaponAnimExports`. Harris then right-clicks each one →
**Save to Roblox** → pastes the ids. Write those exact steps in
`docs/systems/combat.md` and in your reply.

**Playing:**

- New `Effects/WeaponAnimator`, local, for every character, driven by the
  same `onToolAdded` / `onToolRemoved` / `performFor` paths `WeaponPose`
  uses now: hold track on equip, action track on use, stop on release.
- Keep the switch-order fix: release by weapon id, then re-hold whatever
  tool is still in the hand.
- Load tracks once per character and Animator, and cache them.
- Stop Animate's `toolnone` while a hold track plays.
- When tracks are playing, `WeaponPose` writes **nothing** (no C0, no
  attributes), so there's no double pose.
- The trail and the hit window follow the track: fire the trail from a
  `GetMarkerReachedSignal("Hit")` marker at the whip/slap keyframe, not
  from a fixed time.
- **Bigger weapons on small avatars:** if the monkey's arm still hides the
  bat, scale the tool by the character's height (clamped 0.9–1.3), as
  SWING_FIX planned. Check the ≥ 1.5-stud clearance on the monkey and on
  a blocky R15.

**Selftest:** keep the rendered-hand checks. Measure them on the
track-driven pose, and lift the swing-peak needs to Bat ≥ 3 studs and
Glove ≥ 3 studs. Add:

- **"the swing track plays":** `IsPlaying`, its length is ≥ 0.4 s, and the
  `Hit` marker fires once;
- **"held weapon → hold track looping"**;
- **"release → no weapon track left playing, and no BaseC0 left"**;
- **"live fallback":** force the "no id, not Studio" path and check that
  the C0 pose still runs.

## Check

- `luau-lsp analyze` shows no new errors.
- `/selftest combat` with 2 players: the launch check failed before the
  fix (quote it) and passes after. Every `combat …` line passes.
- `/selftest`: no FAILs.
- The tutorial is skipped on join in Studio, and `/tutorial reset` still
  runs it.
- Give Harris this list:
  1. Studio, 2 players: Player1 bats Player2, and Player2 flies
     15+ studs. Glove: 25+ studs and a spin.
  2. Hitting during the get-up shows 🛡.
  3. In 3rd person, the bat swing and the slap read from across the
     street.
  4. `/anim export` → Save to Roblox → paste the ids → restart → still
     works.
- Update `docs/systems/combat.md`, `tutorial.md`, `studio-commands.md` and
  UI_TEST.
- Say which branch you pushed to.
