# Triage 13: phone card two-sided clamp, desktop 4 px, fuzz fingerprint (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines, one per group: FIXED or WHY-NOT (with the numbers you measured).
Run the Luau parser, `tools/theme_token_check.py` and `luau-lsp analyze` (if
it runs) before pushing.

---

Harris ran accc959. The probe timeout is gone and the layouts are right.
What's left (PC window with forced phone, then the real phone emulator):

```
FAIL gacha card (phone 844x390): ... projected centre y 57..231; 3 studs right 57..231;
  3 studs left 57..231; toward the camera 56..230; 3 studs away from the camera y 93..267
  | 3 studs away from the camera: bottom 267 is below the weapon bar at 256
FAIL gacha card (phone 896x414): ... 3 studs away: bottom 284 is below the weapon bar at 280
FAIL gacha card (desktop 1920x1080): stack bottom 64 ... live top 64 no toast (min 68), live top 64 toast up (min 68)
FAIL gacha card (desktop 1366x768): same, live top 64 (min 68)
FAIL remote fuzz: no state change   (once, on the phone run)
```

## 1. Phone: clamp BOTH ways

The top is now right in four of five positions (57, 56, 57, 57 vs min 56).
Standing 3 studs "away from the camera" the anchor projects lower and the
card's bottom lands under the weapon bar (267 vs 256; 284 vs 280). The card
(174 px at 844 x 390) fits the band (56..256 = 200 px), so both limits can
always be met:

- The phone slide target is `top = clamp(naturalTop, minTop, floor - height)`
  (minTop = ceil(stable bottom) + PhoneTopGapPx, floor = weapon bar top, or
  the bottom row's top when there's no bar, from `GetCardBottomFor` /
  `combat.GetBarRectFor`, in screen px). So it can slide UP as well as down
  (negative shift = a SizeOffset.Y above 0.5), never leaves the band, and
  only when the card is taller than the band does the top win (and the
  phone UIScale shrinks, `G.PhoneScaleMin` floor).
- `StackShiftFor` grows a floor argument and becomes two-sided; keep the old
  call working for desktop (floor = view height, so nothing changes there).
- Selftest: the five projected positions must all pass top ≥ min AND
  bottom ≤ floor at 844 x 390 and 896 x 414 (this is the existing check,
  unchanged). Pure check with `StackShiftFor`, live check in the real phone
  window.

## 2. Desktop: the live card sits at 64, the rule says 68

The pure placement passes (anchor y 324 -> top 68, 108 -> 68). The LIVE card
is drawn at exactly 64 = stable bottom 64 + 0 px of gap, with and without a
toast, in both desktop windows (the number never changes, so it isn't the
camera). The clamp must land on `ceil(stable bottom) + StackGapPx` = 68, and
doesn't. Find out why, do not guess:

- Add a one-shot debug print (behind the existing selftest debug flag, not
  always on) of: the `stackBottom` and `minTop` the clamp used, the anchor y,
  `drawnHeight`, `shift`, `SizeOffset.Y` after the write, `GetDrawnTop()`.
- Candidates: `GetDrawnTop` and the clamp disagree about the billboard's
  pixel height (stroke/shadow padding, `Size.Y.Offset` vs the drawn height);
  the SizeOffset write is a frame late; `TopStack.GetStableBottom()` changes
  value between the clamp's frame and the check's (60 vs 64); the clamp runs
  before the camera updates.
- Fix the root cause, then report the numbers before/after. Don't loosen the
  4 px.

## 3. Remote fuzz "no state change"

Once, on the phone run, `PlayerDataService.SelfTestFingerprint` differed
before/after the fuzz. Make the failure say WHAT changed: have the
fingerprint be a table of named fields (or return a diff), and print the
field(s) that differ in the FAIL detail. If it is something that ticks by
itself (passive cash, play seconds, the friend multiplier, rival steal
counters, a tip timer), exclude it from the fingerprint with a comment, not
from the fuzz. If a junk call really changed state, fix that remote's
validation.

## 4. Docs

`items-and-fusion.md`: the phone card clamp is two-sided (band top = chip row,
band bottom = weapon bar). Nothing else.
