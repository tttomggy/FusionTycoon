# Tutorial 4: pacing, the blank dim screen, last selftest FAILs

`git pull` on `world-redesign`, then commit and push. **If your session forces
another branch, say so in the FIRST line**, because Harris tests
`world-redesign`. Reply in 8 lines or fewer.

---

Harris tested on Oct 12. The hand / Open-step / weapon fix (`f22f4d6`) was
not in his build, so check those again too.

## 1. A dim screen with nothing on it

During the tutorial the game sometimes darkens with **no card, no text and
no button**. In his screenshot:
- the whole screen is dimmed;
- only the "New orbs fill your Index!" note and a NEW! pill show near
  INDEX;
- the player is stuck looking at it.

**Find every path that shows a dim backdrop without its card.** Likely
causes:
- an explain card whose root is hidden by `HudGate` or TopStack;
- a card opened while another closes, which leaves the backdrop on;
- a modal enabled before its content is built;
- a card off-screen.

**The rule from now on:**
- A backdrop only exists as part of a visible card.
- When the card closes, its backdrop goes in the same frame.
- If a card's root isn't on screen 0.5 s after opening, close the
  backdrop and log a warning.

**`/selftest`:** walk the tutorial steps and assert that whenever any dim
backdrop is visible, a card root with text is visible inside the
viewport.

## 2. The tutorial goes too fast

The log shows steps 5 → 6 → 7 in 7 s and 8 → 9 → 10 → 11 in 10 s. Cards and
banners flash past before he can read them.

**Pacing rules:**
- **One step at a time.** The next step never starts until the current
  one is finished **and** the player has closed any card it opened.
- **Settle time:** after a step completes:
  - show "✓ Nice!" for 1.2 s;
  - wait 0.8 s with nothing new on screen;
  - then show the next explain card.
- **Minimum read time:**
  - an explain card's OK button turns on after 1.5 s (a fill bar on the
    button shows it);
  - a banner stays at least 3 s before it can change.
- **No skipping ahead:** if the player already did the next step's action
  early (for example, bought the Multiplier during the Index step), still
  show its explain card. Then complete it at once with "Already done ✓".
  Never chain-complete several steps in one go.
- **Timed steps (Pedestals, Ready):** at least 4 s, and they wait for any
  open card.

## 3. Check again in his build

- **The hand** sits above the button, pointing down, never covering the
  text. This is the `f22f4d6` fix.
- **Event step:** tapping the chip opens the info card. It stays open
  until he closes it ("OK, got it"). Only then does the step finish.
- **Bat and Slap Glove:** a visible swing arc of about 0.35 s from third
  person. The weapon is in the right hand (`RightGrip`, Handle within
  1.5 studs of `RightHand`).
- **Guns:** the aim pose raises the arm.
- Test with a blocky R15 too.

## 4. Remaining `/selftest` FAILs

- **text fits:** ShopPanel Overclock / SafeFusion1 / SafeFusion5 `Main`
  lines, and RebirthPanel `Reset` ("Cash (pays the $491M) · Generators →
  …"). Shorten the copy or wrap it. These have failed twice now, so fix
  them for real.
- **cards centred EventInfoCard:** off by 3 px on desktop and 7 px on
  phone. Re-place after its height settles (the next frame), or measure
  after layout.
- **top stack slots out of order (79 / 12 / 64 / 64):** the slots' Y must
  rise strictly top to bottom. One slot reports 12, probably an unplaced
  default. Fix the order or the measurement.

## Check

- `luau-lsp analyze` shows no new errors.
- `/selftest` has no FAILs.
- Update `docs/systems/tutorial.md`.
- In your reply, say which branch you pushed to.
