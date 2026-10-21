# Selftest triage 3: a stuck tutorial card + effects tray (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 6 lines, one per group: FIXED or WHY-NOT.

---

Harris ran `/selftest` twice on **7dcb467** in fresh Play sessions. The
FAIL / WARN lines from both runs are in
`docs/selftest_logs/2026-10-21_7dcb467_fails.txt`. Read it first.
- **Run 1** had a game view of 1877 × 100, so the live checks were skipped:
  297 passed, 4 failed.
- **Run 2** had a game view of 1251 × 666: 344 passed, 37 failed.
- Good news: every panel, text-fit, card-top and shop-chip check now PASSES.

Both runs were just after 00:00 UTC, so the daily reward was unclaimed.
You can't run Studio. **Read each failing probe and the code it measures
before changing anything.**

## 1. A TutorialCard stays open after section 9, blocking the gacha card (about 28 FAILs, top priority)

Every section 12 FAIL says `blocked by: overlays TutorialCard`. The card
never opens and nothing binds. Run 1 had the same code and every gacha check
passed, so something in run 2's tutorial section left the card up.

Evidence from run 2:
- `TutorialStep = 2` never logs. Run 1 logged steps 2 → 11.
- The `pull` step's banner reads "Nice!", and the objective bar reads
  "11 / 11".
- `pull2`: "banner never presented".
- "a single pull of a Common opens the big card: headline nil, drawn 0x0".
- At 00:58:59, in the middle of the tutorial section, `DailyClaimed` fired
  (TimedReward Daily).

Find:
- Why the section started out of step. Suspects:
  - state left behind by the "resume at the matching step" and "finished
    save stays finished" probes (`DebugService` ~806);
  - the daily reward opening or claiming mid-section.
- **Which** TutorialCard was left open (an explain card, or a
  `TutorialCards.ShowTopic` card) and why nothing closed it.

Fix:
- **Test:**
  - Section 9 ends by closing every tutorial card.
  - Section 12 starts with one precondition line, "no overlay open:
    <names>", and closes what it finds, so one leak is one FAIL, not 28.
  - Claim or suppress the daily reward before section 9, so the 00:00 UTC
    reset can't interleave.
- **Game:** check whether a real player can end up with a TutorialCard
  overlay registered while nothing is visible on screen: queued behind
  another card, closed without clearing `openOverlays`, or opened while
  hidden.
  - If they can, that silently blocks the gacha pad: a new player can't
    pull, which is the tutorial's second step. Fix it.
  - The overlay registry must match what's actually on screen (the same
    idea as the "dim backdrop only with a visible card" rule).

## 2. The tutorial explain card probe gives no reason

- `multiplier` (run 1): "drawn 328x-184".
- `pull` (run 2): "drawn 410x76, text height 48". That's a positive size,
  yet it still FAILs.

So the failing term is `IsOpen` or `body.Text == step.Card.Body`: it's
showing another step's text.
- Put open / text-match / the shown text's first 30 characters in the
  Detail.
- The negative height means `body`'s Size offset goes below zero in a short
  card. Clamp that layout so it never goes negative.
- Re-check after group 1. It's probably the same out-of-step root cause.

## 3. "deal real path: still blocked by OtherCard with the guards cleared"

Probably the DailyReward card (unclaimed after 00:00 UTC) still up.
- Make the probe close or await the other side card first.
- Name the card in the line.
- If a real deal can be blocked forever by a card the player can't see,
  fix that.

## 4. Effects tray at 1251 × 666 (a real UI bug: a common laptop window)

- **Desktop:** the tray icons overlap `BottomRow`, and the Luck tooltip
  overlaps `ShopRow`.
- **Phone layout:** the tooltip overlaps `QuestTracker`.

Fix:
- The tray sits above the bottom row.
- The tooltip tries right, above-right, above, then left, against **every**
  HUD rect (`ShopRow` and `QuestTracker` included), on screen. If none fits,
  pick the one with the least overlap and shrink its width.
- Add explicit-viewport probes at 1251 × 666, 1366 × 768 and 844 × 390, the
  same way the "cards centred" checks do.

## 5. The window guard misses the effects tray

At 1877 × 100, "effects tray in the bottom-left quarter" still FAILed twice
(y = −20). Like the other live checks, it should SKIP when the
"selftest window" line already failed.

## 6. Leave alone

The Bat reach WARNs are approved by Harris.

## Check

- `luau-lsp analyze` shows no new errors.
- One line per group: FIXED or WHY-NOT. For group 1, say whether it was a
  test-only leak or a real-player bug.
- Harris: rerun `/selftest` in a fresh Play session, with the game view at
  least 1000 × 600, and paste the FAIL lines.
- Say which branch you pushed to.
