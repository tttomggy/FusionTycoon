# The first-time tutorial

**Studio skips it on join:** `DebugConfig.SkipTutorialInStudio = true`
(Shared/Config/DebugConfig.lua) marks the tutorial Done for every player who
joins in Studio (Player1, Player2 …) on their first sync
(`TutorialService.check`, once per join): the full HUD, no banner, cards or
hand. Only the Done state changes (no rewards, free pulls untouched).
`TutorialService.ShouldSkipOnJoin(isStudio)` is false on a live server
(`/selftest` asserts it). `/tutorial reset` and Settings' "Replay tutorial"
still run it afterwards in that session, and `runTutorialSelfTest` swaps the
tutorial state as before so it still drives every step.

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Tutorial 2** (mandatory, first time; `TutorialConfig` steps + HUD
  table + help copy, `TutorialService` server, `TutorialController` +
  `UI/TutorialBanner` + `UI/TutorialHand` + `UI/HudGate` +
  `Effects/TutorialPath` client). Built like the egg games' tutorials (Harris:
  "super confusing, it needs a redo" about Tutorial 1's OK cards, yellow
  rings and rails): **one instruction at a time**; Tutorial 3 brought back one big **explain card** before each step that introduces something. 11 steps:
  Claim · Upgrade · Pull · Pull one more · Pedestals (OK ends it) · Fuse
  (first one always succeeds) · Index (OK ends it) · Multiplier Pad · Lab
  weather · Rebirth · You're ready (3 s). Banners (≤ 6 words, `· 24m` live distance added while there
  is a world target): "Claim your lab", "Upgrade your generator", "Pull an
  orb" (sub "Your first 2 are free!"), "Pull one more!", "Your orbs make
  money!", "Fuse 2 orbs", "Make more money" (sub "Come back with $X" while
  it's out of reach, skipped after 3 s), "Lab weather!" (sub "Every 15 min.
  Tap it to see what to do"), "Reach $15M to Rebirth", "You're ready!".
  **Pieces:** the **objective bar** (`TutorialBanner`: a solid dark panel with a lime border, top centre just under the Roblox top bar, 600 px wide (`ObjectiveWidth`; phone: full width minus 16 px margins), a 48 px step icon (`Step.Icon`), the instruction in 36 px white display text (28 on a phone), a lime "24m" pill on the right, "3 / 11" (+ the sub line) under it, a pulse on each change; a green ✓ + the Step sound on completion, the next one 0.4 s later; a replay adds a SKIP chip) · the **explain card** (`UI/TutorialExplain`, `Step.Card`: shown before each step that introduces something, never the claim: a ViewportFrame clone of the real generator / Gacha Pad / pedestal / pad (`Card.Model` = a GoalMarkerController target), tier orbs for Fuse, else the icon; title; 1-2 sentences at ≥ 22 px; a big green OK, ✕ / tap outside count as OK; then the banner, path and hand take over. `CardEnds` steps (Pedestals, Index) end on OK; `CardDelay` waits after INDEX pops in) · the **arrow path**
  (`TutorialPath`: ≤ 40 small flat lime `World.TutorialPath` ">" arrows, one size only (no big chevrons at the target),
  two thin Neon bars each (1.2 × 0.25 studs; `PathArrowSize`), one every 3
  studs along PathfindingService waypoints (straight line fallback), 0.2
  above the floor, each pointing along the path toward the target and
  brightening / fading in turn so they flow to it, a fixed pool of 80 parts
  moved every 0.3 s; spacing widens past 120 studs; hidden within 6 studs) +
  the goal arrow's bouncing pill and floor ring (`GoalMarkerController.
  SetTutorialTarget`; heist > tutorial > event > goal) · **one hand 👆**
  (`TutorialHand`, a glyph with a shadow ABOVE its target: the fingertip is ~6 px over the target's top edge, centred, bobbing down toward it (5 px), and the hand's box never overlaps the target, so it never covers the label; a target too near the top of the screen for that gets a 👆 below it. `GetTip` / `GetRect` are checked by `/selftest` (no overlap, tip within 12 px of the edge centre); above every modal; never a rectangle; the top-bar inset (`GuiService:GetGuiInset`) is added back to the target's `AbsolutePosition`, it tracks the target every frame and hides when the target is off screen or scrolled out) on the exact thing to press: the big button;
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
  at the Index step (after the first fusion) (note "New orbs fill your Index!"), the event
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
  clock) and `Open` (the event card / Rebirth panel: done when the player CLOSES
  it (✕, a tap outside, or the "OK, got it" button the event card shows
  while the "Lab weather!" step runs); the card stays open until then and
  nothing in the tutorial closes it; `Seconds` is only a fallback for a
  player who never opens it; the server can't watch a UI, so any time is
  allowed) through remote
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

## TopStack (the top-centre of the screen)

`UI/TopStack` is the only thing that places anything at top centre. Slots,
top to bottom: **objective** (the tutorial bar; `TutorialBanner` registers
its height), **chip** (the event chip; `EventController` registers it),
**announce** (one line, queued), **status** (the heist bars hang below
whatever the announcement uses). Owners ask `TopStack.GetY(slot)` and
re-place on `TopStack.OnChanged`; without an objective bar the chip keeps
its old place (y 12) and the line sits under it.

The announcement line: `TopStack.Announce({ Key?, Priority?, Seconds?, Height,
Show(y), Hide(cut), Move?, Valid? })`. 2.5 s each (`Seconds` overrides: the
big server banners hold 4), the queue capped at 4 (the oldest lowest-priority
item goes), a `Priority > 0` item (your own fusion success, an event start)
goes to the front and cuts a lower one that is showing, an item with the
same `Key` replaces its queued twin, `Valid` skips a stale item at its turn.
`AnnouncementController` (banners, goals, fusion, rebirth, heist feed) and
`EventController` (event start) feed it. The welcome splash waits with
`TopStack.WhenIdle`.

The HUD's left column is one stack too: NEXT GOAL, the quest tracker, then
the cash card (desktop; it never sits above y 274 and follows the goal card
and tracker down), SHOP / GIFTS (the timed pills are a row beside GIFTS on
desktop, a stack on a phone), QUESTS, LOCK, the deal badge.
`HudController.SelfTestLeftColumn` checks the rects do not overlap, at both
layouts.


## Tutorial 4: pacing, the dim screen, the objective bar

**One step at a time, in order** (`TutorialController` runner). The
server's step moves the moment the real action happens, so it can be several
steps ahead of what the player has been shown; the client plays
`lastPlayed + 1` regardless (a resume starts at the server's step):

1. the explain card, on a quiet screen (no panel, result card, event info or
   help card open; `CardDelay` first, so INDEX has popped in);
2. the banner / path / hand until the step is done (server step > index, or
   the tutorial ended);
3. the hand and path go at once; the instruction stays up at least
   `BannerMinSeconds` (3 s), then **"✓ Nice!"** for `NiceSeconds` (1.2 s) and
   the bar slides out;
4. the pause: whatever the step opened must be closed, the welcome splash
   is over, then `SettleSeconds` (0.8 s) with nothing new on screen. Only
   then the next step's card.

A step the player already did early (the Multiplier bought during the Index
step) still gets its card; then the bar shows its instruction and completes
at once with **"Already done ✓"** (`AlreadyDoneText`). Never several steps
in one go. Steps only `sendAdvance` when they are the server's current step.
`TutorialConfig.Steps[].HoldSeconds` (Pedestals, 4 s): after OK the banner,
path and "+$X/s" stay up at least that long, and Timed/Hold steps wait for
any open card. "Ready" is 4 s. The server stamps `enteredAt` when a step
begins, so a Timed step is timed from there (the client's own timer starts
later and never beats it).

The explain card's OK is grey with a fill bar for `CardReadSeconds` (1.5 s);
✕ and a tap outside are ignored for that time too (`UIKit.Modal`'s
`CanClose`); `PressOk` (selftest) skips it. `HudGate.SetStepSource`: the HUD
reveals up to the step the player has been **shown** (`begun`), not the
server's.

**The dim screen with nothing on it** had two causes. (1) `UIKit.PopIn` set
`GroupTransparency = 0` but did not cancel the fade a `PopOut` was still
running on the same CanvasGroup, so a card re-opened within 0.12 s of closing
faded to invisible while its backdrop stayed. `PopIn` now cancels it. (2) A
watchdog in every `UIKit.Modal`: 0.5 s after opening, if the root is not
shown / faded out / off screen, it warns, closes the backdrop at once and
runs `OnClose` (so the tutorial moves on). The rule: **a backdrop only
exists as part of a visible card**; `UIKit.GetDimProblems()` lists modals
that break it (`/selftest` asks per tutorial step).

**The objective bar "pushed off the top"**: it was the bar *slid out* (its
resting state between steps, behind an explain card) with a fixed 110 px
offset, which left its bottom 45 px (the "4 / 11" line) on screen. The slide
is now a 0-1 fraction of `GetCardTop + bar + shadow + 12 px`, so out is out
at any layout, and every slide snaps to its target after its time (a
cancelled tween can no longer leave the bar part way). `TopStack.PlanFor`
is the pure slot math; with the bar empty the chip keeps y 12 beside the top
bar, so `/selftest` orders the **occupied** slots (plan at both layouts with
all four, live slots on the real stack) instead of the raw Ys.

**The giant LOCKED bar and lock disc** were the heist's world billboards
(the gate sign and the lock icon, sized in studs) seen from the gate: 160 px
and 230 px on a 1080p screen. They now carry `DistanceLowerLimit =
PlotLayout.ShieldFence.GateSignMinDistance` (40 studs): closer than that
they stop growing (sign ~230 x 46 px). The HUD LOCK chip is a 44 px chip
and was never a lock button.

Smaller: `EventInfoCard` re-centres once its PopIn is over (the PopIn
tween made AbsoluteSize lag PopScale by a frame: a 3-7 px error baked into
its position); the shop tiles' Main line has two lines (`TILE_HEIGHT` 288,
`FitText`), the Rebirth panel's YOU KEEP / YOU RESET lines auto-size.
