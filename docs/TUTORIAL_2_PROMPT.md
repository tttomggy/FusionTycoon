# Fusion Tycoon: Tutorial 2, rebuilt like the hit games (build prompt for Claude Code)

`git pull` on `world-redesign` first. Commit per phase, push, open a PR →
`main`. Don't merge.

---

Read CLAUDE.md and follow it. Harris played the tutorial from PR #16 (Oct 6
video). His verdict: **"super confusing, it needs a redo."** He sent a clip
of a popular pet/egg game whose tutorial works. **Copy that structure.**

## What went wrong (from the video)

1. **The Welcome card opened before he had claimed a lab.**
2. **Yellow rectangle "coach rings"** sat around things with no meaning to
   a new player. In the Fuse panel the ring sat on the odds chips (2 orbs
   55% / 3 orbs 68%) for **45 seconds** while he tried to work out what to
   press. The two Commons were in the list, the chamber was empty, and
   nothing said "tap AUTO-FILL" or "tap the orbs".
3. **The path** is two thick yellow neon rails running across the floor. It
   reads as part of the level, not "walk here".
4. **Too many OK cards with small text.** Players stop reading by card 3.
5. **The screen is full from second one:**
   - SHOP, GIFTS, QUESTS, the deal badge and the goal card;
   - the weapon bar with three greyed R1 / R2 / R3 slots;
   - REBIRTH and the event chip.

   A new player doesn't know where to look.
6. **A single gacha pull shows no reveal.** The default reveal rule hides
   Commons, so the first orb a player ever gets just appears. Harris wants
   the big centred card: **"You got a COMMON orb!"**

## What the reference game does (copy this)

- **One instruction at a time, as a big banner at the top centre:** a short
  imperative plus the live distance, for example
  - "Go To Gear Shop **188m Away**"
  - "Find Rare Egg **5m Away**"
  - "Click To Place Pet On Plot"

  It changes the moment the step is done. **No OK cards.**
- **A thin dotted line** from the player to the target, floating just
  above the ground. Bright green against the green world, so it can't be
  mistaken for the level.
- **Big chevron arrows on the ground** at the target, pointing in.
- **A pointing hand 👆** on the exact button to press (a UI button or the
  world button), bobbing. Only one at a time. Never a rectangle.
- **A big contextual button** near the bottom centre when you're at the
  target ("Ride Pet", "Use Radar"), so nobody needs to know about E.
- **The HUD builds up as you go.** At the start: money and the banner only.
  Rebirth / Index / Shop **pop in** when they're introduced, with a bounce.

## Build

### 1. The objective banner (replaces the tutorial cards)

- **Placement:** top centre (where the event chip is; the chip is hidden
  until the events step).
- **Text:** large white `Fonts.Display` with the ink stroke, ≤ 6 words,
  plus "· 24m" while there's a world target. Distance is studs ÷ 1
  ("24m"), rounded.
- **Behaviour:**
  - it slides in, and when the step completes it shows a ✓ and plays the
    Step sound;
  - the next instruction slides in 0.4 s later;
  - an optional tiny second line, in muted text, is for the "why" (one
    short sentence at most).
- **The only card left** is a **welcome splash after claiming**: big
  centred text "WELCOME TO YOUR LAB!" with the lab name. It auto-fades
  after 2 s with no button. Nothing shows before the claim except the claim
  banner and path.

### 2. The path (replaces the yellow rails)

- **Dots, not rails:** small round dots (about 0.5 studs) every 2 studs
  along `PathfindingService` waypoints, falling back to a straight line.
  - They float 0.5 studs up and flow toward the target: each dot pulses
    in sequence.
  - At most 60 dots, client-only, rebuilt every 0.3 s.
  - **Lime** (a new `UITheme.World.TutorialPath` token), because no other
    colour in the lab is lime.
  - Make them as small `Ball` parts, **not** flat Neon circles. They're
    spheres, so the pizza-slice problem doesn't apply.
- **At the target:**
  - 3 big chevrons on the floor pointing in (SurfaceGui faces or thin
    parts, following the materials rule);
  - the existing bouncing goal arrow over it.
- **Remove** the old two-rail Beam path and the yellow coach rectangles
  everywhere (`TutorialPath`, the coach-ring code).

### 3. The pointing hand (replaces every coach rectangle)

- **One hand 👆** for the whole UI: a big glyph (or a drawn hand from
  `UIKit`) with a drop shadow.
  - It sits just below-right of its target and bobs toward it.
  - Its target can be a HUD button, a panel button (AUTO-FILL, FUSE,
    CLAIM…) or the contextual button.
- **World prompts:** when the target is a world prompt and the player is
  in range, show a **big green contextual button** above the bottom bar,
  labelled with the action: "PULL", "UPGRADE", "FUSE". Put the hand on
  it. Tapping it triggers that prompt (`ProximityPrompt:InputHoldBegin()`
  / `InputHoldEnd()` on the client) and goes through the real server path.

### 4. Progressive HUD

New players (`Tutorial.Done == false`) start with **only** the cash card
and the banner. Each element pops in (scale 0 → 1.15 → 1, a sparkle and a
small "NEW!" pill for 3 s) **when its step introduces it**:

| Element | Appears |
|---|---|
| UPGRADES | at the upgrade step |
| ITEMS | after the first pull |
| INDEX | after the first fusion |
| REBIRTH | at the rebirth step |
| Event chip | at the events step |
| NEXT GOAL card + quest tracker | when the tutorial ends |
| SHOP, GIFTS, QUESTS, deal badge | when the tutorial ends |
| Weapon bar | **only at Rebirth 1+**, not greyed before |

Old saves, `Done == true` and replays show everything as now.

### 5. Single pulls always get the big reveal

- **Every single pull** shows the centred big card, at every tier and
  for every player, not just in the tutorial:
  - "YOU GOT A **COMMON** ORB!" in the tier colour, with the orb
    (mutation look), its name and +$X/s.
  - For Common / Rare: it auto-closes after 2 s, or on a tap.
  - Higher tiers keep today's longer reveal.
- **The Settings reveal rule** now only covers ×10 / BEST OF 10,
  Auto-Fuse and fusion results. Update its copy and
  `ResultController.ShowsBigCardFor`.

### 6. The new step list (shorter; everything else is just-in-time)

| # | Banner | Hand / path | Done when |
|---|---|---|---|
| 1 | "Claim a lab · 12m" | path to the nearest FREE LAB | claimed → welcome splash 2 s |
| 2 | "Upgrade your generator · 8m" | path to the Basic Generator → contextual UPGRADE (UPGRADES pops in too) | 1 upgrade |
| 3 | "Pull an orb · 15m" (sub: "Your first 2 are free!") | path to the Gacha Pad → contextual PULL | 1st pull (big card) |
| 4 | "Pull one more!" | hand on the contextual PULL | 2nd pull; ITEMS pops in |
| 5 | "Your orbs make money!" (3 s, automatic) | path to the pedestals, a floating "+$X/s" over each orb | automatic |
| 6 | "Fuse 2 orbs · 10m" | path to the machine → contextual FUSE → in the panel the hand goes **AUTO-FILL → FUSE** (2 taps; the odds are not part of the tutorial) | fusion done (guaranteed success, as now); RARE big card; INDEX pops in with "New orbs fill your Index!" |
| 7 | "Make more money · 12m" | path to the Multiplier Pad → contextual BUY when affordable; else the sub-line "Come back with $X" and skip after 3 s | bought, or skipped |
| 8 | "Lab weather!" (event chip pops in; sub: "Every 15 min. Tap it to see what to do") | hand on the chip | chip tapped, or 6 s |
| 9 | "Reach $15M to Rebirth" (REBIRTH pops in) | hand on REBIRTH | panel opened, or 6 s |
| 10 | — | everything else pops in one by one, then the goal card | tutorial done |

**Introduced later, when they matter (just-in-time):**
- **Gifts:** the first time one is ready, the GIFTS button bounces and the
  hand appears once.
- **Quests:** the first claimable quest, the same way.
- **LOCK and stealing:** stays at Rebirth 1 (the existing How to Heist
  auto-open and the `first_shield` goal).
- **Weapons:** at Rebirth 1, the existing unlock card.

**Keep from PR #16:**
- the saved step, resume, old-save migration and Replay in Settings;
- the ? help slideshows (those are where the details live);
- the guaranteed free pulls and fusion;
- the pop-up guards (no shop, deal, Daily or tip while `Done == false`);
- the analytics per step.

Update `TutorialConfig`. Card-only steps are gone, so check what's left
of `TutorialAdvance`: keep it for the timed / skip steps, re-checked on
the server.

## Check

- **`/selftest`:**
  - the tutorial drive runs the new steps in order;
  - no card shows before the claim;
  - the HUD element set per step matches the table;
  - a single pull of a Common opens the big card.
- **UI_TEST "Tutorial 2":**
  - a brand-new player at 1920×1080 and on the phone emulator, from spawn
    to done, without reading anything but the banner;
  - **Harris's test:** a friend who's never seen the game finishes it
    without asking a question.
- `luau-lsp analyze` reports no new errors. Update CLAUDE.md's Tutorial
  entry.
- **Report:**
  - the final banner text for every step;
  - how the hand finds its targets;
  - the dot count and performance on the phone.
