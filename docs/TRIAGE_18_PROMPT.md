# TRIAGE 18: selftest after FUSE_LADDER + RIVAL_ORBS (+ the three earlier untested prompts)

Harris ran `/selftest` on `46c8407`: PC 21 FAIL, phone 8 FAIL. Everything from
`9feeca7` on (FUSE_CARD_FIX, STEAL_BANNER, LOOP_NUDGE, FUSE_LADDER, RIVAL_ORBS)
was pushed untested, so this is the first run of all of it. The planner read
both logs. Fix the list below, no feature work.

You have no Studio, so you cannot run the test. That makes careful reading the
whole job: for every probe you change, re-read the code it measures and work
the numbers out by hand at 936x485 (the phone emulator Harris uses) and at
1920x1080 before you push. Push to `triage18-check` (the planner runs
`compile_check.py` and moves `world-redesign`). Do not add top-level locals to
`SelfTestController.lua` (166 now, the compiler stops at 200): put new probe
helpers in a table or a new module.

## 0. The PC log is incomplete (read this first)

On PC the client half never reported: `FAIL client half: no report from the
client` (`DebugService` waits `SELFTEST_REPORT_TIMEOUT` = 90 s; the fuzz ended
13:21:23 and the wait gave up at 13:22:59, 96 s later; the phone run did the same
work in 47 s). So PC never ran the client's loop nudge / steal mission / fuse
ladder / panel sections. **Every phone FAIL below may also be a PC FAIL.**

- Find what makes the client half slow on PC. Print one line per client stage
  with its seconds (`[SelfTest] client stage <name> took N s`) so the next log
  shows it. Likely suspects: a probe waiting its full timeout because its
  target never shows (the "no hand" probes in 4 and the 30 s banner wait in 2).
- Fix the cause. Raising the 90 s timeout is the last resort, not the fix.

## 1. rivals: "a rotation sets the next one ~150 s out" (test bug, flaky half the time)

`DebugService` (the `rivals:` block near line 3285) reads `before` BEFORE
`SelfTestMakeRotationDue`, then requires `after > before`. The jitter is +-30 s,
so a lab whose first interval was long gives `before` > `after` even though the
new interval (147.4 s) is right. Take `before` after `SelfTestMakeRotationDue`
(or compare `after` to `fakeNow`). Keep the delta bounds.

## 2. tutorial finish: "its banner shows: never presented" (PC and phone, 30 s wait)

New since the last green run, so it comes from one of the five untested
prompts. Prime suspect: FUSE_LADDER's fusion result card no longer auto-closes
(it has a GO TO RARE button now). The tutorial's `fuse` step ends on that card,
and the presenter (`TutorialController`, `GetPresentedStep`) probably waits for
no modal / no card before presenting `finish`, so it never does. Confirm by
reading the presenter. Then fix the behaviour, not the probe: while the
tutorial is running the card must act as before (auto-close, no GO TO RARE
button), or the presenter must not wait on it. A real new player must get the
finish banner without having to find a close button. Also check the new
`tipRival` / MissionBanner change in `startTip`/`endTip` cannot leave the
presenter waiting.

## 3. combat (PC only, 16 FAIL): Studio could not load the animations

Not code. The diff since the last green run touches nothing in combat. All seven
`AnimationIds` report `no length after 5 s (not loadable by this place?)`, every
track has length 0.00 s, and every hand pose fails as a result. The Output also
shows `ContentId: rbxassetid://203785492 failed due to: Asset type does not
match requested type` (grep finds no such id in `src/`, so it is not ours).
Changes:

- If EVERY AnimationId fails to load in the same run, print ONE FAIL line
  (`combat animation ids`, keep it) and skip the pose / track / swing checks
  with a single `WARN combat poses skipped: animations did not load this
  session`. A run where some ids load and a pose still fails stays a FAIL.
- Do not touch `CombatController` / `CombatService`.

Harris will rerun `/selftest combat` once; if the animations load that run is
green.

## 4. loop nudge (phone run: 4 FAIL)

- `loop nudge: a pair and cash: the two-step line, the Fusion Machine first`
  got `Fuse your 2 <font color="#d27bff">Epics</font>, then pull more orbs for
  the next fuse!`. The line carries rich-text tags now; the check compares the
  plain string. Compare the line with tags stripped (the target check stays).
- `1920x1080: the best row's button sits inside the scroll view | button y
  193+52` and `1920x1080: the hand's fingertip ... | no hand`, plus
  `844x390 phone: the hand's fingertip ... | no hand`. The hand is missing in
  both layouts, and at 1920x1080 the best row is also outside the scroll view.
  Read `UpgradeGuide.lua` / `UpgradesPanel.lua` and the probe (~line 2400) and
  decide which it is: (a) the real panel does not scroll the best row into view
  or does not show the hand (a real bug: fix it, a new player must see the
  arrow above the Upgrade button), or (b) the probe measures before layout /
  before the hand's first frame (wait for it, then measure). If it is (a)
  say so in the commit.

## 5. steal mission box on the phone (2 FAIL)

`the box is inside the screen | x 221-716 of 936, y -8+93 of 485` and
`the box sits at TopStack's Mission y | y -8.5, slot 64.0`. The box is 72 px above
where TopStack says it should be, hanging off the top of the screen. On
desktop it is fine (Harris's screenshot). The probe waits 0.6 s for the
slide-in, so either the slide-in tween is slower than that / never finishes on
the phone layout (UIScale 0.8, `UIKit.LayoutChanged`), or the body's position is
set from a stale slot. Read `MissionBanner.lua` and `TopStack.Place` and find out
which. If the box really ends at -8 on a phone that is a real bug (the main
steal instruction is off-screen): fix the box. If it is only the animation,
wait for the tween's end (not a fixed 0.6 s).

## 6. fuse ladder (phone run: 1 FAIL)

`1920x1080: the ladder strip is shown, Rare lit, 'Next: Epic' | false Rare Epic
'Next: Epic'`: Best/Aim/NextText are right, `StripShown` is false. The strip
hides when the fuse column is under 420x250, and the probe forces a 1920x1080
layout while the real window is the 936x485 phone emulator, so the column is
small. Decide the strip from the logical viewport the probe forces
(`UIKit.GetLogicalViewport`), the same way the other layout plans do, so the
probe measures what it claims. If that cannot be done, make the 1920x1080 strip
check a WARN when the real window is under 1000x600 (as the position checks do).

## Done when

The planner's checks pass and you have walked each fix by hand for both sizes.
In your report, per item: root cause in one line, test bug or real bug, file.
Say plainly which items you could only reason about and not verify.
