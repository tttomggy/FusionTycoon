# Tutorial hand + weapon holding fixes (build prompt for Claude Code)

`git pull` on `world-redesign`, then commit and push to `world-redesign`. If
your session forces another branch, say so in the first line. Reply in 8
lines or fewer.

---

Harris tested on Oct 12 (3 clips). Fix these.

## 1. The pointing hand sits ON the button. Put it ABOVE.

The 👇 hand covers the middle of UPGRADE / PULL / FUSE and hides the label.

**Placement:**
- The fingertip goes just above the button's top edge, about 6 px above
  and centred horizontally.
- The hand sits above that, pointing down, and bobs down toward the
  button.
- For a button near the top of the screen, put the hand below it,
  pointing up.
- It must never cover the button's text.

**`/selftest`:** the hand's rect doesn't overlap the target's rect, and
the tip is within 12 px of the target's top-centre.

## 2. The event step closes the event card instantly

Banner "Lab weather!" asks him to tap the event chip. The info card opens
for a split second, then closes, before he can read it.

**Cause:** the step is an `Open` kind. It completes the moment the card
opens, and the next step or banner change closes it.

**Fix (all `Open` steps, including Rebirth):**
- The step completes when the player **closes** the card (✕, a tap
  outside, or an "OK, got it" button you add at the bottom of the event
  info card while the tutorial runs).
- The card stays open until then.
- Nothing in the tutorial may close a card the player opened.

## 3. Weapons are not held in the hand, and there's no animation

**What Harris sees:**
- The freeze ray and glove sit in front of his chest.
- The bat is at his body, not in his hand.
- There's no visible swing.

His avatar is the small-bodied monkey with a big head, so check both a
**default blocky R15** and **his avatar**. In Studio: Test → Player with
his avatar, plus a spawned blocky R15 dummy that equips the tool through
the server.

**Checks:**
- **Hold:**
  - The Handle's `RightGrip` weld exists and the Handle is within 1 stud
    of `RightHand` when equipped.
  - Check the `Grip*` values and `GripPos`. A large `GripPos` puts the
    model inside the torso.
  - Make sure every model part is welded to the Handle, so nothing
    welded to the torso or root.
- **Arm pose:**
  - The arm must visibly change while a weapon is out.
  - Roblox's own `Animate` script plays its tool-hold animation
    (`toolnone`) for a Tool with a Handle. Check that it actually plays
    and isn't stopped by our code, and that our pose doesn't fight it.
  - If our procedural pose writes `Motor6D.C0`, confirm it actually moves
    the arm on the client. If the Animator wins, write `Transform` in
    `RunService.Stepped` after the animation step, or use
    `PreSimulation` / `PreRender`, whichever actually works. Verify it
    by eye.
- **Swing:**
  - The bat and glove swing must be clearly visible from third person: a
    big arc, about 0.35 s, with the trail.
  - Other players see the swing too (`HitFx` `Swing`).
- **Guns:** the aim pose raises the right arm straight forward, and the
  gun is in that hand.

**`/selftest`:** for each weapon, equip it on the tester and check:
- `RightGrip` exists;
- the Handle is within 1.5 studs of `RightHand`;
- the RightShoulder angle changes during a swing and while aiming.

The test unequips afterwards.

## Check

- `luau-lsp analyze` shows no new errors.
- Update UI_TEST and `docs/systems/combat.md` / `tutorial.md`.
- List exactly what Harris should look at.
