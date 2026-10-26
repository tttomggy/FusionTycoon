# Owned passes in the effects tray + the Fuse panel's mutation tip (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines, one per group: DONE or WHY-NOT. Run the Luau parser over `src/`
before pushing.

---

Harris: "if people bought a gamepass it doesn't show anywhere". A buyer
should see what they paid for working, every session.

## 1. One 🎟 PASSES circle in the effects tray

- **One** circle for all owned passes, not one per pass (the phone tray is
  one row; six more circles won't fit). Shown only when the player owns
  ≥ 1 pass (`TycoonController.OwnsPass`, the live `OwnedPasses` from the
  snapshot). Hidden for a player with none: no ad, no "buy" circle.
- Look: the 🎟 icon, the tray's normal circle size and rules, Blue gradient
  (the shop's Passes colour), a small count badge when 2+ (`3`). Label
  under it like the others: the cash multiplier the passes give (`x2.5`
  for 2x Cash + VIP), or `ON` if none of the owned passes touch cash.
- Order: just left of Friends (`Order = 1`), shift the others by one.
  Permanent, so no timer ring.
- Tooltip (same tooltip rules as the rest): bold `Your passes`, then one
  line per owned pass from `ShopConfig` (names and numbers from the config,
  never typed):
  - `💰 2x Cash: x2 income`
  - `👑 VIP: x1.25 income`
  - `🍀 Lucky: x1.5 luck`
  - `⚙ Auto Fuse: on`
  - `🏛 Extra Pedestals: +N`
  - `🎨 Lab Style: on`
- Tap = pin the tooltip (as the other circles). No purchase prompt.
- Updates live: a purchase mid-session adds it at once (with the tray's
  existing pop-in).
- Selftest: with a stubbed owned set: none → no circle; {DoubleCash} →
  circle, label `x2`, tooltip 1 line; {DoubleCash, VIP, Lucky} → badge 3,
  label `x2.5`, 3 lines; the phone tray still fits on one row at 844 × 390
  with Friends + Passes + 3 timed effects (no overlap, tap targets ≥ 44 px).

## 2. Fuse panel tip: how to fuse mutated orbs

AUTO-FILL fills plain orbs into an empty chamber and only matches a
mutation when the first orb in the chamber has it. Players won't find that.

- When the chamber is **empty** and the selected tier has **no plain orbs to
  fill but 2+ orbs sharing one mutation stack** (or plain AND such a group),
  show one muted line under the AUTO-FILL button:
  `Tip: put a GOLDEN orb in first, then AUTO-FILL fills GOLDEN.`
  (the mutation name from `MutationConfig`, the largest group's top
  mutation). Gone as soon as any orb is in the chamber.
- No change to AUTO-FILL, AGAIN or FUSE ALL behaviour.
- Selftest: empty chamber + 3 Golden Epics → the tip names GOLDEN; one orb
  in → no tip; only plain orbs → no tip.

## 3. Docs

`docs/systems/monetization.md` (the passes circle) and
`docs/systems/items-and-fusion.md` (the tip). Update the EffectsTray
header comment's cell list.
