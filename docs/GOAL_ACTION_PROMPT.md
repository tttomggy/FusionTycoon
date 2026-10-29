# GOAL_ACTION: every goal must say what to DO, and the arrow must lead there

Harris, looking at the live game (5.63K cash, Gacha Pad $250/pull, 2 of 4
pedestals full): the goal reads "Fill all 4 pedestals" with the arrow on an
empty pedestal. A new player cannot know how: pedestals fill BY THEMSELVES
(auto-display puts your best 4 orbs on them), so standing at an empty pedestal
does nothing. The way to fill them is to PULL more orbs, and the game should
keep telling the player to pull whenever they can afford it.

Root cause: the six goals added in FUSE_LADDER copied `display_item`'s pattern.
`fill_pedestals` in `GoalConfig.lua` has `Target = "FirstEmptyPedestal"` and no
`Loop`, so the goal arrow and the loop strip's lit step point at a pedestal
instead of the Gacha Pad.

## 1. Fix fill_pedestals

- Text: `Pull orbs to fill your 4 pedestals` (keep it under the HUD's one-line
  width at 844x390; shorten if it wraps, e.g. `Pull orbs: fill 4 pedestals`).
- `Target = "GachaStation"`, `Loop = "Pull"` (same as `gacha_pull`).
- Keep the Unit / count and the saved-progress migration (ids do not change).

## 2. Audit every goal in `GoalConfig.lua` with one question

"If I am a 10-year-old who has never seen this game, what do I physically do,
and does the arrow lead to the place where I do it?"

- A goal whose result happens by itself (an auto effect, a count that rises
  as a side effect) must point at the ACTION that causes it, not the result.
  `display_item` ("Your best orb goes on a pedestal", Target
  `FirstEmptyPedestal`) is fine only while it truly completes by itself right
  after the first pull; if there is any case where the player stands there
  waiting, give it `Loop = "Pull"` and the Gacha Pad target too.
- Every goal needs a `Target` that is where the action happens AND a `Loop`
  (Pull / Fuse / Upgrade / Steal) that lights the matching loop-strip step.
  `max_basic`, `own_3_rares`, `own_2_epics`, `multiplier_x1_5`,
  `unlock_flare_reactor` already have both: verify the Target is the right
  place (own_3_rares / own_2_epics: if the player does not own two of the tier
  below, the action is PULL / FUSE the lower tier, check `GoalSteps` covers
  that) and say in your report if any is wrong.
- Wording: start with a verb the player does (Pull, Fuse, Upgrade, Steal,
  Reach), never a state ("Fill", "Own") unless the next words name the action.

## 3. "Keep telling them to pull whenever they can"

When the goal is blocked or its action is not doable, the coach already owns the
2nd line and the arrow (LoopCoach, `GoalBlocked`). Check the case from the
screenshot: cash >= the pull price, no fusable pair, goal `fill_pedestals` (and
generally ANY goal not about upgrading or stealing). Required: the tracker shows
the goal title, the 2nd line / loop strip lights Pull, and the arrow is on the
Gacha Pad. If any of the three is not true after the fix, fix it.

## 4. Tests (/selftest)

- A pure test over `GoalConfig.List`: every goal has `Target` and `Loop`, and
  the Loop is one of the four steps; `fill_pedestals` is `Pull` / `GachaStation`.
  A new goal without these fails the test (this stops the next copy-paste).
- A coach case: cash 5630, pull price 250, 2 of 4 pedestals full, no fusable
  pair, goal `fill_pedestals` -> lit step Pull, arrow target Gacha.
- Keep `/selftest` at 0 FAIL on both layouts; `SelfTestController.lua` is at 166
  top-level locals, add none.

Push to `goal-action-check`. Do not change economy numbers; this is text and
targets only (the econ sim should be unchanged: say so).
