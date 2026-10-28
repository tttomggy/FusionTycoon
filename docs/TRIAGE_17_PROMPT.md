# Triage 17: loop strip growth rule, tracker 3-lines regression, Bat swing timing (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.**
**Line 2: "untested in Studio" (also in the commit message) unless you could
run `/selftest`.** Then one line per group: FIXED or WHY-NOT. Run
`tools/compile_check.py` (a path to `luau-compile`, or tell the planner it
isn't available and push to a side branch as last time), `luau-lsp analyze`
and `tools/theme_token_check.py` before pushing.

---

Harris ran 7538000 on PC and phone (the 18 cascade FAILs are gone):

PC:
```
FAIL hud loop strip (phone): card grew 34.0 px for the strip (max 20)
FAIL hud loop strip (desktop): card grew 58.0 px for the strip (max 20)
FAIL combat Bat: the swing stays visible for >= 0.4 s: 0.37 s away from the held pose
```
Phone:
```
FAIL hud goal tracker 3 lines (phone): Step hidden; Hint hidden
FAIL hud goal tracker 3 lines (desktop): Step hidden; Hint hidden
```

## 1. Loop strip growth: my spec contradicted itself

CORE_LOOP_PROMPT said "tap targets ≥ 44 px" AND "the card grows by at most
20 px". Five cells ≥ 44 px can't add only 20 px. The 44 px tap rule wins.
New limits (`STRIP_GROWTH` per layout): **desktop ≤ 62 px, phone ≤ 40 px**,
as long as the existing left-column fit and overlap checks pass at 1920 x
1080, 1366 x 768 and 844 x 390. Better if you can keep the visible chips
small and let each cell's hit area extend over the card's padding to stay
near the old limit, but don't spend a rewrite on it. Update the comment at
GoalTracker ~75 and the docs.

## 2. "hud goal tracker shows 3 lines": Step and Hint are hidden (REGRESSION?)

`GoalTracker.SelfTestGoalLines` shows a stubbed view with `Lines` set and
finds `goalStepLabel` / `goalHintLabel` not Visible, on both layouts. It
passed at ec79d5b (goal steps). Since then: the LoopCoach commit (the coach
"takes the 2nd line") and the refactor into `GoalTracker.lua`.

- Find out whether this is the TEST (e.g. `SelfTestView()` no longer carries
  `Lines`, or `SetGoal` now takes the lines from the coach / the strip state
  and the stub has `StripLit = nil`) or the GAME (a real goal with a tier
  action no longer shows its 2nd and 3rd lines). **A real "Fuse Epics into a
  Legendary" goal must show title, action line and odds hint**, with the
  strip below; verify that by reading the code path from `GoalProgress` to
  `SetGoal`, and say which one it was.
- Fix it where it's broken. The test must put the stub into a state where
  all 3 lines are expected (Lines set, coach not taking the line).

## 3. Combat Bat: 0.37 s vs 0.4 s

"The swing stays visible ≥ 0.4 s" measured 0.37 s: that's a frame-timing
margin (a couple of frames at 60 fps), not a gameplay problem. Measure it in
a way that's robust to frame jitter: require ≥ 0.4 s of swing OR the
animation's own length minus 0.05 s, whichever is smaller, and report the
measured value in the PASS line. Do not change the swing animation.

## 4. Docs

`items-and-fusion.md` / `UI_TEST.md`: the strip growth limits (62 / 40) and
why (44 px tap cells).
