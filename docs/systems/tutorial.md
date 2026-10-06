# The first-time tutorial

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Tutorial 2** (mandatory, first time; `TutorialConfig` steps + HUD
  table + help copy, `TutorialService` server, `TutorialController` +
  `UI/TutorialBanner` + `UI/TutorialHand` + `UI/HudGate` +
  `Effects/TutorialPath` client). Built like the egg games' tutorials (Harris:
  "super confusing, it needs a redo" about Tutorial 1's OK cards, yellow
  rings and rails): **one instruction at a time, no OK cards**. 10 steps:
  Claim · Upgrade · Pull · Pull one more · Pedestals (3 s) · Fuse (first
  one always succeeds) · Multiplier Pad · Lab weather · Rebirth · You're
  ready (3 s). Banners (≤ 6 words, `· 24m` live distance added while there
  is a world target): "Claim your lab", "Upgrade your generator", "Pull an
  orb" (sub "Your first 2 are free!"), "Pull one more!", "Your orbs make
  money!", "Fuse 2 orbs", "Make more money" (sub "Come back with $X" while
  it's out of reach, skipped after 3 s), "Lab weather!" (sub "Every 15 min.
  Tap it to see what to do"), "Reach $15M to Rebirth", "You're ready!".
  **Pieces:** the banner (`TutorialBanner`, top centre where the event chip
  is; slides in, a green ✓ + the Step sound on completion, the next one
  0.4 s later; a replay adds a SKIP chip) · the **arrow path**
  (`TutorialPath`: ≤ 40 small flat lime `World.TutorialPath` ">" chevrons,
  two thin Neon bars each (1.2 × 0.25 studs; `PathArrowSize`), one every 3
  studs along PathfindingService waypoints (straight line fallback), 0.2
  above the floor, each pointing along the path toward the target and
  brightening / fading in turn so they flow to it, a fixed pool of 80 parts
  moved every 0.3 s; spacing widens past 120 studs; 3 bigger chevrons (two thin Neon bars each)
  on the floor in front of the target, pointing in; hidden within 6 studs) +
  the goal arrow's bouncing pill and floor ring (`GoalMarkerController.
  SetTutorialTarget`; heist > tutorial > event > goal) · **one hand 👆**
  (`TutorialHand`, a glyph with a shadow, below-right of its target and
  bobbing toward it, 👇 above on the lower half of the screen, above every
  modal; never a rectangle) on the exact thing to press: the big button;
  AUTO-FILL then FUSE in the Fuse panel (2 taps, the odds aren't part of
  it); the event chip; REBIRTH · the **contextual button** (a big green
  "UPGRADE" / "PULL" / "FUSE" / "BUY" above the bottom bar, shown at a
  world target whose prompt (`Step.PromptName`) is in reach; tapping it
  runs `prompt:InputHoldBegin()` / `InputHoldEnd()` so the real client
  handler and server path run) · "+$X/s" over each pedestal's orb while the
  pedestals step runs · the **welcome splash** after the claim, the only
  card left: "WELCOME TO YOUR LAB!" + "<NAME>'S LAB", fades by itself after 2
  s, no button; nothing shows before the claim but its banner and path.
  **Progressive HUD** (`UI/HudGate`, `TutorialConfig.HudReveal` +
  `IsHudShown`): a new player sees the cash card and the banner only;
  UPGRADES pops in at the upgrade step, ITEMS at "Pull one more", INDEX
  after the first fusion (note "New orbs fill your Index!"), the event
  chip at the weather step, REBIRTH at the rebirth step, and at the end
  ⚙, SHOP / GIFTS / QUESTS / the deal badge / power-ups, then NEXT GOAL +
  the quest tracker, one by one (`HudRevealDelay`). Each pops (0 → 1.15 →
  1, sparkles, a "NEW!" pill for 3 s). The gate runs at the end of the
  render step and forces a hidden key's roots `Visible = false`, because
  their owners (HudController, EventController) keep setting their own
  Visible; on reveal a root is shown or its owner's `OnShow` refreshes
  it. `Done`, an old save and a replay show everything silently. The
  **weapon bar** (`CombatController`) is off entirely before Rebirth 1 (no
  greyed R1 / R2 / R3). **Just-in-time hands:** the first time a gift is
  ready (GIFTS) and the first claimable quest (QUESTS) the hand shows once
  (tips `giftHand`, `questHand`). **Kinds:** `Action` steps complete ONLY
  on the real server action (an OnSync predicate: claimed, a generator
  level, each of the 2 pulls, a fusion, Multiplier level 1; a replay too);
  `Timed` (the client asks after `Seconds`, the server re-checks its own
  clock) and `Open` (event card / Rebirth panel opened, or after `Seconds`;
  the server can't watch a UI, so any time is allowed) through remote
  `TutorialAdvance { Step }` (C→S, re-checked: current step; the Multiplier
  Pad's skip only while level 1 is unaffordable and after 3 s). **Data:**
  `PlayerData.Tutorial = { Ver, Step, Done, FreeFuse, FreePulls,
  PullsGranted, Base, Replay, ReplayHint }` (sanitised, in the snapshot);
  saved as each step completes, so a rejoin resumes; satisfied steps are
  skipped. A Tutorial 1 save (no `Ver`, 14 steps) is mapped to the nearest
  step (`TutorialConfig.MigrateStep`; the template's `Ver` is 0 so
  ProfileStore's Reconcile can't fake it). Step 0 is decided on the first
  sync: Rebirth ≥ 1 or > 20 pulls → Done + a one-time "replay it in ⚙
  Settings" toast (tip `tutorialReplay`). Free pulls: the pad takes them
  first (`TycoonService.TutorialPull` → `GrantFreePulls(..., forcedTier)`,
  pad price unmoved, label "FREE"); the guaranteed fusion:
  `PlayerDataService.TakeTutorialFreeFuse` (once per account).
  **Guards:** while `TycoonController.IsTutorialActive()` shop side cards /
  Starter / deals (`offerBlocked` "Tutorial"), the Daily card and big tips
  (held, `ToastController.SetBigHold` / `FlushHeld`) wait; the tutorial
  never sells. **Help:** a round "?" (`UIKit.AddHelpButton`) in Fuse /
  Upgrades / Index / Rebirth, and an owner-only "How it works" (H) prompt on
  the LOCK console and Gacha Pad, open `TutorialConfig.Help[topic]` as a
  slideshow (the details live there; `UI/TutorialCards` is only that and
  the weapon unlock card now). LOCK and stealing are taught at Rebirth 1
  (How to Heist, the `first_shield` goal), weapons by their unlock card.
  Settings: ▶ REPLAY TUTORIAL (`TutorialAdvance { Replay = true }`: the same
  banners with a SKIP, no free pulls / fusion again). After it, the lit
  path follows the current goal; the goal card's 👣 toggles it
  (`Settings.GoalPath` Auto / On / Off; Auto = on for the first 2
  sessions). **Single pulls:** every single pull gets the centred big card
  at every tier and for every player ("YOU GOT A COMMON ORB!" in the tier
  colour, `BigCardInfo.Headline`; Common / Rare close after 2 s or on a
  tap, higher tiers keep today's reveal); the ⚙ reveal rule now only
  covers BEST OF 10 / ×10, Auto-Fuse and fusions
  (`ResultController.ShowsBigCardFor`). Analytics `TutorialStep` (n),
  `TutorialDone`. Studio `/tutorial reset`, `/tutorial step <n>`.
  `/selftest` drives every step in order on the real handlers and asks
  the real client (`SelfTestController` probe) per step: the banner text,
  no card before the claim, exactly the table's HUD set, no weapon bar at
  Rebirth 0, and that a single Common pull opens the "COMMON ORB!" card;
  plus the Timed refusals, the Multiplier skip, the Tutorial 1 migration and
  the mid-way resume.
