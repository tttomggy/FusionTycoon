# Studio chat commands, /trailer and /selftest

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Studio test start** (`DebugConfig.StudioStartRebirths = 3`,
  `StudioGrantAllWeapons = true`): on join, in Studio and ONLY on the Mock
  store (`DebugService.ShouldApplyStudioStart`), every player gets Rebirths
  raised to 3 (never lowered) and every weapon, the way `/rebirths 3` and
  `/weapons all` do it, once per join, next to `SkipTutorialInStudio`: Test →
  2 players can fight with no commands typed. The Live store, live servers
  and the `FT_StudioSaves` test store never get it (`/selftest combat` asserts
  it). `/rebirths 0` still works to test Rebirth-0 flows during a session.
- Studio chat commands (DebugService): `/cash <amount>`, `/resetmultiplier`,
  `/rebirthready` (sets cash to the next rebirth's price),
  `/rebirths <n>`, `/give <itemId> [mutation]`, `/offline <minutes>`
  (pending offline earnings as if away that long, then re-sync: the only
  way to test the welcome-back card, since Studio profiles never save),
  `/shield <s>` (0 drops it),
  `/stealable` (toggles your lab stealable at Rebirth 0, for heist tests),
  `/tips reset` (clears your seen one-time tips), `/tutorial reset` /
  `/tutorial step <n>`, `/weapons all | reset`, `/anim export` (every weapon clip as a KeyframeSequence in `ServerStorage.WeaponAnimExports`; see combat.md for Save to Roblox), `/quest complete <id>`
  (a daily id or `chain`; the warning lists today's) / `/quest reset` /
  **`/quest status`** (each quest's kind, counter base, progress, Done /
  Claimed and your `Fused_*` stats: why a quest isn't done),
  `/powerup <key> <n>`, **`/music play <name>`** (fades to the track whose name contains `<name>`, case-insensitive, e.g. `/music play radetzky`; no match prints the track list) / **`/music next`** (fades to the next playlist track now and prints its name) / **`/music list`** (each track's name, id, `IsLoaded`, `TimeLength`; both run on the client and print to its Output), **`/sound <slot>`** (plays that SoundConfig slot at
  your character, any case; no argument lists the slots; swap ids in
  `SoundConfig.lua`),
  `/event <id> [minutes]` (forces an event: GoldenRain, PowerSurge,
  MeteorShower, RainbowStorm, Night, VoidMoon), `/event off`,
  `/shop grant <key>` (any ShopConfig key, the real grant path, no Robux),
  `/eventclock <offsetMinutes>` (shifts the event clock to walk the
  schedule; clients read the same offset), `/eventmut
  <charged|void|celestial>` (a random Epic with that event-only mutation
  through the real reward path: the reveal card + the banner),
  `/daily day <1-7>` (your next daily claim is that day, claimable now),
  `/daily miss <days>` (as if you missed that many days: 1 = the free
  skip, 2+ = back to Day 1), `/daily reset`, `/gifts time <minutes>`
  (today's play time), `/gifts reset`,
  `/wipe` (fails your active steals first). **`/trailer`** (admins, live
  servers too; AdminService → S→C `TrailerStart { Shot?, Stop? }`):
  TrailerController plays the ~30 s video-thumbnail cinematic on that
  client only (local orbs / NPC rigs / cards / `EventController.PreviewLocal`
  skies, clean frame, everything restored), shots and plot-local camera
  keyframes in `TrailerConfig`; `/trailer <shot>`, `/trailer stop` or F8. **`/selftest`** runs the Bug 
  Hunt invariants (layouts, NumberFormat, sounds, event schedule, data
  round trip, a junk-remote fuzz with no error / state change, every panel
  at both scales with no leftover instances in the panels' own modal guis,
  the phone HUD's left group inside the left 40%, the real deal pop-up
  path, every panel label's `TextFits` at both scales, hovering things on
  their plot, auto-display order, the TopStack plan at both layouts (slots
  rise strictly, objective bar clear of the top bar), the gate sign / lock
  billboards' size cap, and per tutorial step: no dim backdrop without a
  card on screen, the card's read-time OK, the objective bar fully on
  screen) and prints PASS / FAIL lines;
  it refuses unless saves go to the mock store or `FT_StudioTest_1`.
  **The report queue lives for the whole run** (it used to be cleared after
  step 7, so every later client probe waited the full 90 s and combat never
  ran). Each section prints a `[SelfTest] == N. name ==` header and runs in
  a `pcall` (an error is a FAIL line, the next section still runs); each
  tutorial / combat probe has its own 10 s timeout and a missing report is a
  FAIL named after it (`combat SlapGlove: no report from the client`); the
  `done: N passed, M failed` line always prints. **`/selftest combat`** runs
  only the combat section (weapon probes, slot-to-slot switch probes,
  release); **`/selftest gacha`** only the Gacha pop-up card (claims a lab if needed; starts 25 studs away so the card is closed, then the client steps onto the pad and checks the frame after the card opens; reads the card from the instance tree; every FAIL carries its measurements):
  the card opens fully in one frame (all 6 orb cells `AbsoluteSize` > 0, their % `TextBounds.Y` > 0); no gacha `ProximityPrompt` draws UI (all off, none shown);
  the billboard is adorned to the `GachaCardAnchor` Attachment (pixel size,
  `SizeOffset` (0, 0.5), `StudsOffset` (0, 0, 2), `StudsOffsetWorldSpace` zero, `AlwaysOnTop` off, `MaxDistance`
  150) whose flat (XZ) distance to the pad's centre is < 0.1 studs and which sits
  2.2 studs over the pad top, the ball's base (the old sideways bug showed ~9.8); with the
  character 8 studs in front of the pad (default camera) and with the camera
  straight above the pad, the card's horizontal centre is within 30 px of the
  pad's projected centre, and at the approach view the capsule's projected
  centre is inside the card's rect (it covers the ball); the capsule parts have
  `LocalTransparencyModifier` 1 while the card is open and 0 once it closes; the anchor never changes over 4 camera yaws or
  zoom 6 / 12.5 / 40; the GACHA label
  and your VIP chip are hidden while it is open and the chip is back when it
  closes (each for the desktop and phone HUD layout via `UIKit.SetForcedPhone`;
  the window itself can't be resized from a script);
  tier %s vs `GetGachaRates` at the server's luck and under an admin-luck
  event, the luck pill, solid black (no "?") orbs, the (i) panel sums; all 6 cells drawn
  with a % ≥ 12 px tall; the PS99 face (white paper + light rim, the 26 px title
  and the (i) centred on the top edge, bare cells with no tile background or
  ribbon, ONE mutation line holding every mutation's %, a coin + price that
  matches the pull cost or `FREE` centred on the bottom edge); no `ViewportFrame`, no `CanvasGroup`, only
  `PopScale` besides the phone's `PhoneScale`, no `GachaBoard`;
  a modal (the (i) panel) hides the card and it comes back; the key bar's 3
  round buttons (E / R / T, R bigger, captions `Pull` / `×10` / `Auto ×10`) each ≥ 44 px (sides 56 design px on the phone layout), drawn, and E / R / T bound through
  `ContextActionService` (unbound 25 studs away, bound again back on the pad);
  text fits;
  server side: `RequestGachaPull` from 25 studs is refused (TooFar) and costs
  nothing, Auto pull from 25 studs does not start, and at $0 a pull is refused
  and Auto pull stops at once with the reason and the price; with cash for 20
  pulls Auto pull runs exactly 2 ×10 cycles (≥ 3 s apart, the client showing
  the 10-pull card each time) and stops for cash — this one really pulls 20
  items on the Mock store; cash is given back);
  **13. effects tray**: a Luck Potion, Speed Boots and 2 Safe Fusion tokens
  are granted, the client reports a luck circle with a timer, a Speed Boots
  circle and a Safe Fusion circle with `×2`, all on the right edge of
  the window, the Luck and Speed Boots timers reading the live seconds, ≥ 44 px
  tap targets, no HUD overlap at both layouts and no old effect pills; client
  checks also assert every `Plain`, the deal / Starter cards' tile + YOU GET +
  worth values, "shop bundles" (every item with `Parts`, in the Deal and
  Featured banners, grid tiles and side cards, shows one tile and one YOU GET
  line per distinct part; Pocket Cash's line carries the real amount; no
  "one by one"; every shop text ≥ 13 px);
  `/selftest combat` also walks the real swing chain (a click on the
  attacker's client → the server's box → HIT → the target flies, measured on
  its own client; then out of the box → MISS) and the combat section ends with
  the held-weapon checks scaled by avatar height;
  `/combat box` toggles drawing each melee swing's server hitbox (red,
  0.2 s, that weapon's box size);
  Polish 12 checks (the tooltip opens left of the icon in its own layer above the HUD, overlapping no HUD rect or the weapon bar): **music** (every track loads, plays, a sting ducks it,
  the toggle stops and resumes it), the **effects tray** cartoon badges and
  tooltips (hover shows name / Plain / time, leave hides, a tap closes after
  3 s), the **unlock card** (Rebirth 0 mentions Rebirth 1), the **QUESTS
  badge** and the "Fuse a Mythic" chain step (complete at once with
  `Fused_Mythic = 1`, the claim grants the Slap Glove), and the swing test
  with the victim 6 studs in front and 3 to the side (must HIT);
  **`/selftest cards`** only the card-placement checks (desktop +
  phone, next and running events, tutorial OK row on/off). Its
  last part drives a reset tutorial through every step on the real
  handlers (upgrade, tutorial pulls, fusion, `TutorialService.Advance`),
  checks no shop / deal pop-up showed and that a mid-way save resumes, then
  restores the tester's own tutorial state. Then combat: a Rebirth-0
  player can't be hit, the server cooldown, and (with a second player) a
  knocked carry returns the orb with both inventories unchanged. Last,
  progression: the stacking helpers, an old save's migration, a live
  stacked item (refused twice, Void stacks on, each Index entry, ×21, a
  round trip), the fusion intersection, `PlotLayout.CheckFloor2` + the
  built floor, a quest claim refused while incomplete and a power-up
  refused at 0 (the tester's state put back); the fuzz covers ClaimQuest /
  UsePowerUp.

## /selftest notes (triage after 5264754)

- A probe line may carry `Warn = true`: a miss prints `[SelfTest] WARN …` and
  counts as a PASS (used for the Bat's two reach lines only, approved by eye).
- The gacha card probes print `blocked by: …` (`GachaBoardController.GetBlockReason`:
  open overlays, ragdoll, carrying) so a card that stays shut names its gate.
- The tutorial `multiplier` skip check backdates the step to "now" first (the
  client probe before it takes longer than the 2.5 s skip window).

## /selftest notes (triage after 444c410: 33 → 77 FAILs)

Most of the 77 were the TEST, not the game:
- **Probe replies are matched to their request** (`ProbeId`): a tutorial step probe
  that ran past its timeout used to leave a late report in the queue, and every
  later request (combat weapons, gacha, auto pull) took the one before it, so
  the server destroyed a weapon while the client was still measuring it. A step
  probe now has 75 s (`SELFTEST_STEP_TIMEOUT`); a stale report is dropped.
- **Window guard.** The client refuses to measure the live screen in a game view
  under 1000 × 600 (a 2346 × 125 window gave cards negative heights and ~60 FAILs):
  ONE `FAIL selftest window: …` replaces card placement, text fits, shop chips and
  the tutorial bar / hand geometry. Enlarge the Studio game window and run again.
- The explain card's "OK turns on after 1.5 s" reads the card's own clock
  (`TutorialExplain.GetReadTimes`), not a race against `task.wait`.
- Auto pull test: passive income is paused (`TycoonService.SelfTestFreezeIncome`)
  and cash set to exactly two cycles, or a rich save paid for 90 pulls.
- The remote fuzz parks the daily claim and the gift clock first (a junk
  `ClaimDaily` is a real claim after 00:00 UTC).
- A failing weapon line prints `rig weapon …, tracks […*=playing]` and
  `trace:` (the last hold / release decisions of `CombatController`).
- The gacha card and the (i) panel also redraw on `AdminLuck` / `EventId`
  attribute changes (not only the 0.5 s poll); the probe waits for the tiles to
  show the server's luck, and says so when the client's luck never matches.

## /selftest notes (triage after 7dcb467: 77 → 37 FAILs)

- **The leaks were the test's own cards.** The DailyReward card (claimable after
  00:00 UTC) sat open from the start and the tutorial presenter waits for
  `UIKit.IsOverlayOpen` (any card) before each explain card, so section 9 stalled
  behind it; and section 11's "Fuse a Mythic" claim grants the Slap Glove, whose
  real unlock card (a `TutorialCard`) was still up for section 12 ("blocked by:
  overlays TutorialCard", ~28 FAILs). Fix: a `ClearScreen` probe
  (`SelfTestController.clearScreen`) closes the tutorial / explain / daily / event /
  side / result cards and the queued unlock cards, and
  `DailyController.SelfTestSuppress` keeps the daily from opening by itself. It
  runs before and after section 9, after section 11, before the deal path, and
  releases the suppression after section 13. Section 12 starts with ONE line,
  "no overlay open before the gacha card: open: …", naming what it found.
  No real-player hole found: a card that registers but is off screen is closed by
  the Modal watchdog (0.5 s), and the daily only auto-opens with no tutorial active.
- The explain-card line's Detail now says `open`, `text matches` and the first 30
  characters of the text shown; the card body has a minimum height (no negative size).
- "deal real path" names the cards blocking it.
- The effects tray placement and tooltip are pure functions
  (`EffectsTray.PlanTrayFor` / `PlanTooltipFor`, logical px in screen space) and
  `/selftest` runs them against the real HUD rects and the weapon bar
  (`CombatController.GetBarRectFor`, needs `/weapons all`) at 1251 × 666,
  1366 × 768 and 844 × 390, in both layouts (`effects tray plan (…)`). The
  tray is a column on the right edge from 35% of the height; on a phone it
  stops 12 px above the jump button (`EffectsTray.JumpRectFor`) and wraps left;
  the tooltip tries left, above-left, below-left, above, below, right, then
  narrows to 140 px. The old code compared screen-space tray rects with obstacle
  rects shifted by the top-bar inset; both are in one space now.
- The effects-tray position checks skip in a too-small window like the others.


## /selftest notes (triage after f95f220)

- `TycoonService.SelfTestClaim` claims the lab by calling the claim itself
  (`claimPlot`, the same function the pad's `Touched` runs): no teleport, no
  physics (a server-side CFrame move does not reliably fire `Touched`). A "Skip"
  now says why (no plot, no ClaimButton, save not loaded).
- The effects-tray probe has its own 30 s timeout (`SELFTEST_EFFECTS_TIMEOUT`); a
  probe that errors on the client reports `probe <Kind> errored on the client`.
