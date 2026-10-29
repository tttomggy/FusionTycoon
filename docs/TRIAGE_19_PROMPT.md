# TRIAGE 19: the last two selftest fails (PC 2, phone 4)

`e2dedc1` is live on `world-redesign` and Harris's Studio runs it (FAIL lines say
`DebugService:3721`, the `client stage` lines print). The client half now
finishes on PC (slowest stages: panels 24 s, notify opt-in 21 s, placed cards
11 s, phone panels 11 s; fine). What is left, all in the client half:

PC:
- `loop nudge: 1920x1080: the hand's fingertip is within 12 px above the button
  ... | no hand: no target`
- `loop nudge: 844x390 phone: the hand's fingertip ... | no hand: no target`

Phone (the 844x390 hand line again, plus three that are NEW and passed before
your triage-18 change to the mission probe):
- `steal mission: the box shows for an owner | shown false`
- `steal mission: hidden while a modal is open, back when it closes | hidden true, back false`
- `steal mission: hidden in a tutorial step and while ragdolled, back after | tutorial true, down true, back false`
(the last two follow from the first: the box never came back up.)

You still cannot run Studio. So this round is as much about making the NEXT log
tell us the cause as about the fix. Push to `triage19-check`.

## 1. The hand: target is nil one second after the probe set it

The probe (`SelfTestController` ~line 2400) calls `TutorialHand.SetTarget(button)`
and `SetCaption`, waits for the hand's first frame (<= 1 s), and then
`GetBlocker()` says `no target`. The caption check right after still passes, so
the target was cleared by someone while the caption stayed. `TutorialHand` never
clears it by itself (the only `target = nil` is inside `SetTarget(nil)`). The
callers of `SetTarget(nil)` are `UpgradeGuide.release`,
`TutorialController.stopGuidance` and `TutorialController.endTip`, plus the probe
itself at the end.

Find which one runs during the probe. Suspects, in order:
1. `TutorialController.endTip` (it clears the hand unconditionally when a tip
   was showing). In Harris's live test save the tutorial is done and `tipRival` /
   other tips can be running or ending while the selftest runs; one ending in
   the 1 s window kills the probe's hand.
2. `UpgradeGuide.frame` -> `release()` when `owned` is the same button the
   probe picked (it clears a target it thinks it owns once its plan goes to
   None).
3. `TutorialController.stopGuidance` from a sync during the wait.

Do:
- Make the probe independent of live state: before the loop-nudge stage
  starts, end any running tip and pause the guide (add a `UpgradeGuide.SetPaused`
  and a `TutorialController` test hook if needed; un-pause in a `restoreProbe`
  style cleanup even when a check errors).
- On failure, name the clearer: have `TutorialHand` record `lastClearedBy`
  (`debug.traceback` first useful line, test builds only / cheap) and print it
  in the `no hand:` detail.
- Real-game question to answer in your report, in one line: can `endTip` or
  `stopGuidance` also clear the UPGRADES hand in a real session while the
  upgrade guide owns it? If yes that is a real bug (the new player loses the
  arrow): make the guide re-assert its target (its frame runs every 0.1 s, so
  it should already; say why not if it does not).

## 2. The steal mission box did not show on the phone

`TopStack.IsMissionShown()` was false for 2.6 s after
`MissionBanner.SetTestState({ Owner = true, Done = false, ... })`. The same probe
passed on the phone before triage 18 and passes on PC now, so something around
it changed. Differences to check: the probe is now run through `stage(...)`
(so the state it starts in changed: which overlay / forced layout / tip is left
over from the stage before it, "top stack"?), and your slide-wait loop. Things
that keep the box down in `TopStack` / `MissionBanner.frame`: `TopStack.SetMission`
refused or queued behind an announcement, a modal/overlay open
(`UIKit.IsOverlayOpen`), the HUD hidden, `registered` stuck, `wanted` false.

Do:
- On a failed `shows for an owner`, print the reason in the detail: `registered`,
  `TopStack.IsMissionShown`, `UIKit.IsOverlayOpen()`, `MissionBanner.PlanShow(state)`
  for the test state, `holder.Visible`, and what TopStack currently has in each
  slot. Add a small `MissionBanner.GetBlocker()` like `TutorialHand.GetBlocker()`.
- Fix the cause once you find it by reading. If it is leftover state from
  the previous stage, close it (and make `stage()` assert / report "left a
  modal open" so it can never silently poison the next stage).
- Do not add a longer wait as the fix.

## 3. Housekeeping

- Both `loop nudge ... no hand` lines must stay FAIL on a window >= 1000x600 (and
  the phone layout line is always FAIL): they guard a real new-player arrow.
- `SelfTestController.lua` is at 166 top-level locals. No new top-level locals;
  hang helpers on an existing table.
- Report per item: cause (found / not found), test bug or real bug, file.
  Say which parts you could not verify.

## 4. NEW on the PC run: gacha card "a toast moved the card" (1920x1080 and 1366x768)

Same code (`e2dedc1`) passed this check on the previous PC run, so it is
timing / state, not the code:

`a toast moved the card: top 198.0 quiet, 200.2 with an announcement; clamp
#207: stackBottom 64.0 minTop 68.0 anchorY 524.2 drawnHeight 324.0 shift 0.00
... top 200.2, stable bottom now 64.0`

The clamp's shift is 0.00 in the toast sample (the card is unclamped, the stack
bottom did not move: 64.0), so the clamp did not move the card. The 2.2 px is
most likely the standing player's anchor (character / camera sway) drifting
between the two samples. Check by reading `GachaBoardController` and the probe
(`gachaDesktopStack`): is the card's top, when `shift == 0`, a pure function of
the anchor? If so compare the clamp output (shift, or the top minus the
anchor-derived part) between the two samples, not the raw top, or take both
samples in the same frame. If instead the toast really moves an unclamped card,
that is a real bug (the card jumps when an announcement shows): fix it. Keep
the real guarantee: the card's top is >= stack bottom + 4 px with and without a
toast.

## 5. The flakiness itself

The mission-box fails (3 on phone before, 3 on PC now) and the hand fail move
between runs of identical code. After the cause is found for 1 and 2, add one
line at the start of the client half's loop nudge / mission stages that prints
the live state they depend on (tip showing, coach step, overlay open, forced
layout, `UpgradeGuide` owned) so any later flake explains itself in the log.
