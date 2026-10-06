# The first-time tutorial

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Tutorial** (mandatory, first time; `TutorialConfig` steps + copy,
  `TutorialService` server, `TutorialController` + `UI/TutorialCards` +
  `Effects/TutorialPath` client). 14 steps: Welcome · Claim · Upgrade ·
  Pull (2 free plain Commons) · Pedestals · Fuse (first one always
  succeeds) · Index · Multiplier Pad · Lab weather · Free gifts · LOCK (at
  the console) · Stealing · Rebirth · You're ready. Each step: a small
  centred card (icon, title, ≤ 2 sentences, OK; dims the game) → the goal
  arrow's tutorial layer (`GoalMarkerController.SetTutorialTarget`; heist >
  tutorial > event > goal) with its pulsing SurfaceGui ring, the lit path
  (Beams along PathfindingService waypoints, straight-line fallback,
  rebuilt every 0.3 s) and a coach ring on the HUD element (in the Fuse
  panel: AUTO-FILL → odds chips → FUSE) → done → "✓ Nice!" + sound → next
  card 0.6 s later. **Kinds:** `Action` steps complete ONLY on the real
  server action (an OnSync predicate: claimed, a generator level, 2 pulls,
  a fusion, Multiplier level 1); `Card` / `Open` (Index / Rebirth panel
  opened) / `Arrive` (within 14 studs of the LOCK console, server-checked)
  through remote `TutorialAdvance { Step }` (C→S, re-checked: current step
  and kind; Multiplier on OK only while level 1 is unaffordable). **Data:**
  `PlayerData.Tutorial = { Step, Done, FreeFuse, FreePulls, PullsGranted,
  Base, Replay, ReplayHint }` (sanitised, in the snapshot); saved as each
  step completes, so a rejoin resumes; satisfied steps are skipped. Step 0
  is decided on the first sync: Rebirth ≥ 1 or > 20 pulls → Done + a
  one-time "replay it in ⚙ Settings" toast (tip `tutorialReplay`). Free
  pulls: the pad takes them first (`TycoonService.TutorialPull` →
  `GrantFreePulls(..., forcedTier)`, pad price unmoved, label "FREE"); the
  guaranteed fusion: `PlayerDataService.TakeTutorialFreeFuse` (once per
  account). **Guards:** while `TycoonController.IsTutorialActive()` shop
  side cards / Starter / deals (`offerBlocked` "Tutorial"), the Daily card
  and big tips (held, `ToastController.SetBigHold` / `FlushHeld`) wait;
  the tutorial never sells. **Help:** a round "?" (`UIKit.AddHelpButton`)
  in Fuse / Upgrades / Index / Rebirth, and an owner-only "How it works"
  (H) prompt on the LOCK console and Gacha Pad, open
  `TutorialConfig.Help[topic]` as a slideshow. Settings: ▶ REPLAY TUTORIAL
  (`TutorialAdvance { Replay = true }`: every step as an OK-card, no free
  pulls / fusion again). After it, the lit path follows the current goal;
  the goal card's 👣 toggles it (`Settings.GoalPath` Auto / On / Off; Auto
  = on for the first 2 sessions). Analytics `TutorialStep` (n),
  `TutorialDone`. Studio `/tutorial reset`, `/tutorial step <n>`.
