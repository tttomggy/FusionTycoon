# Rival orbs worth stealing, and they rotate (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`
(or a side branch `triage22-check` if you can't run
`tools/compile_check.py`; the planner moves it).
**Line 1: the branch. Line 2: "untested in Studio" (also in the commit
message).** Then one line per group: DONE or WHY-NOT. Run
`tools/theme_token_check.py`, `luau-lsp analyze` and `tools/econ_sim.py`
(rival steals feed it) before pushing.

---

Harris: "sometimes the rival orbs are trash, I can literally pull them for
100 bucks. Change the rivals' orbs every couple of minutes."

Today (`RivalConfig.TierWeights`, band = lowest Rebirth count): at Rebirth 0
a rival lab's orbs are 60% Common, 30% Rare, 10% Epic, rolled once and kept
until stolen. A player who already owns Epics runs 90 s across the street
and carries home a Common. Stealing is the hook; the prize has to be worth
the run (and the guard).

## 1. Quality: worth more than a cheap pull

Replace the "band by Rebirth count" with a **target tier from progress**:

- For each rival lab, compute `floorTier` = (the best tier owned by the
  **least advanced real player in the server**, i.e. the one who can least
  afford to be bored; from their inventory, not Rebirth) **minus nothing,
  and plus one at most for one pedestal** (never above Legendary; `BannedTiers`
  Mythic / Secret stay banned).
- Each lab always has: **1 pedestal at `floorTier + 1`** (capped at
  Legendary), **1 at `floorTier`**, and the other 2 from the existing
  weights **with Common removed** unless `floorTier` is Common. So a lab
  never shows 4 Commons to someone who owns Rares.
- A brand-new player (best tier Common): labs show Common/Rare/Epic as
  today (a first steal must be doable AND exciting: at least one Rare).
- The goldens chance (`GoldenChance`) stays; a Golden is shown with its
  glow like any orb.
- Put the numbers in `RivalConfig` (`PlusOneTierPedestals = 1`, etc.), not
  in the service. The sign's `best: Epic` line keeps working.

## 2. Rotation

- Every `RivalConfig.RotateSeconds = 150` (jitter ±30 s, **staggered** so
  the 3 labs never rotate on the same second) a lab re-rolls its
  pedestals' orbs by the rules above, but:
  - never a pedestal being carried from, never while its guard is chasing
    (wait for the next tick), never during the 10 s before the player
    in the lab's range is about to grab (skip if a `StealPrompt` is being
    held by anyone);
  - a pedestal that is mid-respawn (`back in 1:12`) rolls its new orb when it
    comes back, no extra timer.
- The swap is visible and fair: a quick pop on the old orb, the new one
  scales in, one TopStack-free world cue (no announce). A small label on the
  gate sign or the lab's name board: `fresh orbs in 1:48`, from a
  `NextRotateAt` attribute (client-side countdown, like `RespawnAt`).
- When the least advanced player's best tier goes up (they fused an Epic),
  the NEXT rotation uses it; don't re-roll immediately.

## 3. Economy + selftest + docs

- `tools/econ_sim.py`: its rival-steal income line uses the band weights;
  update it to the new rule (a new player at Common sees ~Rare average) and
  report how Rebirth 1 time moves (target still ≥ 35 min; if it falls under,
  lower `StealsPerHour` or the plus-one count, say which).
- `/selftest rivals`: with stubbed players (best Common / best Rare / best
  Epic) each lab has the right floor and plus-one pedestal and **no Mythic or
  Secret over 10 000 rolls**; no 4-Common lab for a Rare owner; rotations are
  staggered (no two labs within 5 s); a carried-from pedestal is never
  re-rolled; the countdown attribute advances.
- Docs: `docs/systems/heist.md` (rival labs: orb quality and rotation),
  `RivalConfig` header.
