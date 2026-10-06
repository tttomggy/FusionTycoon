# Studio chat commands, /trailer and /selftest

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- Studio chat commands (DebugService): `/cash <amount>`, `/resetmultiplier`,
  `/rebirthready` (sets cash to the next rebirth's price),
  `/rebirths <n>`, `/give <itemId> [mutation]`, `/offline <minutes>`
  (pending offline earnings as if away that long, then re-sync: the only
  way to test the welcome-back card, since Studio profiles never save),
  `/shield <s>` (0 drops it),
  `/stealable` (toggles your lab stealable at Rebirth 0, for heist tests),
  `/tips reset` (clears your seen one-time tips), `/tutorial reset` /
  `/tutorial step <n>`, `/weapons all | reset`, `/quest complete <id>`
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
  their plot, auto-display order) and prints PASS / FAIL lines;
  it refuses unless saves go to the mock store or `FT_StudioTest_1`. Its
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
