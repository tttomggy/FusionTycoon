# Loop nudges: never leave the player idle, and guide the upgrade INTO the panel (build prompt for Claude Code)

Run `git pull` on `world-redesign` (after `CORE_LOOP`, `FUSE_CARD_FIX` and
`STEAL_BANNER` are in), then commit and push to `world-redesign` (or a side
branch `triage20-check` if you can't run `tools/compile_check.py`).
**Line 1: the branch. Line 2: "untested in Studio" (also in the commit
message).** Then one line per group: DONE or WHY-NOT. Run
`tools/theme_token_check.py` and `luau-lsp analyze` before pushing.

---

Harris, live build with the LoopCoach (screenshots: $35.5K cash, NEXT GOAL
`Fuse Epics into a Legendary / Fuse your 2 Epics: 35%`, Gacha at $273 a
pull; then the UPGRADES panel with 3 buyable rows): "right here the player
loses purpose. It should keep telling them to pull to get more orbs to fuse
and make more money. And the arrow that points at UPGRADES should lead INTO
the panel, with an arrow right above the upgrade button in there."

Two problems: (a) with cash to burn and one fuse available, nothing tells
the player to keep pulling, so they stand around; (b) the upgrade guidance
stops at the UPGRADES button.

## 1. Idle nudge: pull more orbs, with the why

`LoopCoach` (server, already ships `{ Step, Line, Target }`) gets an **idle
nudge**, client-timed in the same controller that shows the loop-closing
lines:

- Idle = no pull, fuse, upgrade, steal or Multiplier purchase for **40 s**,
  the tutorial is done, no modal open, and the player can afford
  `>= 3` x10-or-single pulls' worth: `cash >= pullPrice`.
- Then, once per idle spell (and again after another 90 s idle, max 3 per
  session): one `TopStack.Announce` line
  `Pull more orbs! More orbs → fuse them → more cash every second.`
  AND the hand on the Gacha Pad (the existing `GoalMarkerController`
  arrow, `PlanGoalArrow`'s one arrow, pointed at `GachaStation`, even when
  the coach's step is Fuse), cleared by the next pull.
- If the player has a fusable pair AND cash for pulls, the line says both:
  `Fuse your 2 Epics, then pull more orbs for the next fuse!` (arrow on the
  Fusion Machine first, then the Gacha after the fuse).
- If cash < pull price and nothing to fuse: `Your orbs earn $X/s: next pull
  in 0:42` (the Earn step; no nudge spam).
- Mission box (STEAL_BANNER) and tips keep priority: no nudge while a tip,
  the steal box, or a tutorial step is up.
- Never the same line twice in a row.

## 2. Upgrade guidance leads INTO the panel

Coach step `Upgrade` today lights the UPGRADES button. Extend it:

1. **Hand on the UPGRADES button** (as now) with the badge number.
2. When `UpgradesPanel` is open and the coach step is Upgrade: **hand + a
   small arrow just above the best upgrade button in the list** (not the
   first row). Best = the affordable upgrade with the highest income gain
   per cost (the server already knows the incomes; have `LoopCoach` publish
   `UpgradeTarget = { StationId, Kind = "Upgrade" | "Max10" ... }` with the
   coach). Label under the hand: `+$13.3/s` (the row's own "next" number).
   `TutorialHand` already points at a GuiObject (`SetTarget`): give
   `UpgradesPanel` a `GetButtonFor(stationId)` that returns that row's
   buy button (or the MAX ×N one when the coach says so).
3. The hand follows the list when it scrolls (the panel has a scroll list;
   the row can be below the fold: scroll it into view first, then point).
4. After the buy, the hand goes away and the coach moves on (Pull / Fuse /
   Earn). If the panel closes, the hand goes back to the UPGRADES button.
5. Phone: the panel is a BigPanel with a one-row header; the hand stays
   inside the panel's rect and doesn't cover the row's income text.

## 3. Selftest + docs

- Idle nudge: with a stubbed clock, no actions for 40 s + cash → one
  announce and the Gacha arrow; an action resets it; max 3 per session;
  none during a tip / mission box / modal / tutorial; fusable pair + cash →
  the two-step line.
- Upgrade hand: with the coach on Upgrade and the panel open, the hand's
  target is the best row's button (rect inside the panel's scroll view,
  hand tip within 6 px above it); closing the panel puts it back on
  UPGRADES; at 1920 x 1080 and 844 x 390.
- Docs: `docs/systems/tutorial.md` (nudges and the upgrade hand),
  `docs/systems/items-and-fusion.md` or wherever LoopCoach is documented.
