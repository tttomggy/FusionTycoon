# Swing fix: make the arm actually move (build prompt for Claude Code)

`git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 8 lines or fewer.

---

Harris tested `f014813` on Oct 12 with his avatar (the small monkey). In
the video:
- the swing **trail and sparks play**, so `CombatController` →
  `WeaponPose.Swing` → `HitFx` all run;
- but **the arm never moves**: it hangs straight down while the bat is out,
  and stays down through every swing;
- the bat itself is hard to see at all (hidden against the body).

`/selftest` still passed "the right arm is raised" and "the shoulder moves
during the swing", because those checks read back
`motor.C0 * motor.Transform`, **the value we just wrote**. They measure our
own write, not what Roblox draws. Fix the checks first so they can fail.

## Why the pose doesn't show (likely)

`WeaponPose` writes `Motor6D.Transform` at RenderStepped / Stepped /
Heartbeat. That stopped working in 2026:
- With `Workspace` fixed simulation / Server Authority (the
  `UseFixedSimulation` rollout), Roblox ignores client writes to
  `Motor6D.Transform` / `AnimationConstraint.Transform` while an animation is
  playing. Roblox staff confirmed this on the DevForum and said a new API is
  coming; there's no workaround in the thread.
- Avatars on the **Avatar Joint Upgrade** may drive the shoulder through an
  `AnimationConstraint`, with the `RightShoulder` Motor6D gone or disabled.

First, log (Studio only, once) for the local character:
- whether `RightUpperArm.RightShoulder` exists and is enabled;
- whether an `AnimationConstraint` connects `UpperTorso` and
  `RightUpperArm`;
- the place's Workspace simulation / authority settings.

Put what you find in `docs/systems/combat.md`.

## 1. Drive the shoulder through C0, not Transform

The Animator never touches `C0`, so a `C0` write always shows.

- **Base value:** on `Hold`, store the shoulder's base `C0` (a `BaseC0`
  attribute on the motor, the same idea as the `BaseSize` rule). Every frame
  set `C0 = BaseC0 * pose`, keeping the joint position. **Never build the
  pose from the live C0**, or it compounds.
- **Release / respawn / weapon switch:** restore `C0 = BaseC0` and clear the
  attribute. If the Humanoid rescales the rig (`BaseC0` no longer matches the
  rig's scale), re-read it while not holding.
- **Stop writing `Transform` entirely.** The Animator keeps it, so walk and
  idle still add their small arm sway on top of our pose. That's fine.
- **`toolnone`:** Animate's tool-hold animation also raises the arm in
  `Transform`, so with our C0 pose the arm would double-raise. While we hold
  a weapon, stop Animate's `toolnone` track (fade 0.1), or make our hold pitch
  relative to it. Pick whichever looks right **by eye**.
- **Avatar Joint Upgrade rigs:** if the shoulder is an `AnimationConstraint`,
  apply the same pose to its `Attachment0.CFrame` (with a stored
  `BaseCFrame`, restored on release).
- **Plan B, only if C0 and the attachment both fail on Harris's avatar:**
  - build the hold, swing, slap, recoil and toss as `KeyframeSequence`s in
    code;
  - register them at runtime with
    `KeyframeSequenceProvider:RegisterKeyframeSequence`;
  - play them on the Animator at `Action4`.

  If that only works in Studio, say so in your reply; Harris can publish
  the sequences as Animation assets.
- **Other players' characters:** the same C0 path runs on every client for
  every holder (it's local), driven by `HitFx`, as now.

## 2. Make the swing read from third person

- **Bat swing:** start from the raised hold, cock back over the right
  shoulder, then a big arc down and across to the left (≥ 120° of hand
  travel, about 0.35 s), then settle. **SlapGlove:** a wide flat backhand at
  shoulder height.
- **Visible weapon:** while held, the bat's tip must be ≥ 1.5 studs from the
  UpperTorso surface, so it isn't hidden against a small body. Check this on
  Harris's monkey avatar and a blocky R15. If the monkey's tiny arm hides
  the bat, scale the bat model by the character's body height (clamped
  0.8–1.2), not the grip.

## 3. `/selftest`: measure what's drawn

Replace `GetArmDirection` / `GetRestDirection` with **rendered** positions.
Read `RightHand.Position` in `UpperTorso.CFrame` space after the joints
solve (sample on `PostSimulation` / Heartbeat). Do not read the motor
values we wrote.

- **Held:** the hand is ≥ 1 stud forward of where it hangs with no weapon
  (measure the rest pose before equipping).
- **Swing:** the hand travels ≥ 2 studs during the Bat swing and the Slap.
- **Guns:** the hand is raised to about shoulder height while aiming.
- **Release:** after unequip, the hand is back within 0.3 studs of rest.
  `BaseC0` is restored, and no attribute is left behind.

These must **FAIL on today's code**. Run them once before your fix and
quote the failing numbers in your reply.

## 4. Two small selftest items

- **cards centred (EventInfoCard, phone live): centre 231 vs band
  centre 233.**
  - Measure after the card's layout settles (the next frame after
    `AbsoluteSize` changes), and re-place on that change.
  - Round the same way in the plan and the measurement.
  - The tolerance stays 2 px.
- **`GeneratorController: Generator_basic_generator has drifted (body
  3.187…, core 1.65…)`.** 3.187 = 3 × 1.0625, partway through a 1.08
  bump, so the check probably ran mid-pulse of a later upgrade (MAX ×N fires
  many). Make the check run 1 s after the **last** bump (cancel the
  earlier delayed checks).
  - If the body is still oversized 3 s after the last upgrade, it's a real
    compounding bug. Fix it in `PartKit.Pulse` / `TweenSize`: the stored
    base, a new pulse cancels the old tween, and the size is restored on
    cancel.

## 5. Quick check from the same video

On the Fuse explain card, Harris's cursor sat on the green OK for about
5 s after its fill bar finished before the card closed. Make sure the
first click after the 1.5 s fill closes it; clicks before the fill
finishes don't count. If a click during the fill is swallowed silently,
give it a small shake so he knows to wait.

## Check

- `luau-lsp analyze` shows no new errors.
- `/selftest` has no FAILs, and the new arm checks fail before the fix
  (quote the numbers).
- `/weapons all`, then in third person: equip the Bat and swing 3 times;
  the same for the Slap Glove. Do this on Harris's avatar **and** a blocky
  R15. Give Harris this exact list to look at.
- Update `docs/systems/combat.md` (C0, not Transform, and why) and
  UI_TEST.
- Say which branch you pushed to.
