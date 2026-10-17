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
  (a daily id or `chain`; the warning lists today's) / `/quest reset`,
  `/powerup <key> <n>`,
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
  **13. effects tray**: a Luck Potion and 2 Safe Fusion tokens are granted,
  the client reports a luck circle with a timer and a Safe Fusion circle with
  `×2`, ≥ 44 px tap targets, no HUD overlap at both layouts and no old effect
  pills; client checks also assert every `Plain`, and the deal / Starter
  cards' tile + YOU GET + worth values;
  `/selftest combat` also walks the real swing chain (a click on the
  attacker's client → the server's box → HIT → the target flies, measured on
  its own client; then out of the box → MISS) and the combat section ends with
  the held-weapon checks scaled by avatar height;
  `/combat box` toggles drawing each melee swing's server hitbox (red,
  0.2 s);
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
