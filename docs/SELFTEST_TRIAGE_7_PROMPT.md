# Selftest triage 7: gacha card at phone scale, opt-in timing, admin id, stray TutorialCard (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 4 lines, one per group: FIXED or WHY-NOT. Run the Luau parser over `src/`
before pushing (CLAUDE.md Gotchas).

---

Harris ran `/selftest` on 04c5754 (PC and iPhone 13). The auto pull FAILs
are gone. Left: 3 gacha card FAILs (same on both runs) plus the items below.

## 1. Gacha card at phone scale (3 FAILs)

```
FAIL gacha card (phone 844x390): ... top 50 is above the stack's bottom 51
FAIL gacha card (phone 844x390): every text >= 13 px ... Percent "0.0035%" 12.1 px
FAIL gacha card (phone 896x414): ... top 49 is above the stack's bottom 51
```

- **Top:** the card's top lands 1–2 px above `TopStack`'s bottom. Place it
  at `math.ceil(stack bottom) + 4` (screen px, after the scale), and snap to
  whole px (as triage 5 did for the HUD). If that pushes the bottom past the
  weapon bar top, shrink the scale to fit; don't overlap either edge.
- **Long % labels:** short odds pass, `0.0035%` drops to 12.1 px, so the %
  label is shrinking to fit its tile (TextScaled or a fit loop). On the phone
  variant, no text on the card may shrink below 13 px after the scale:
  widen the % column / tile for long values, or drop the "%" outline size
  last. **Never round or reformat the odds** (they must stay exact).
- Keep: (i) hit area >= 44 px, the PHONE_LIVE_FIXES group 2 screen rules.

## 2. Notification opt-in: not on join

Live, Harris got the opt-in the moment he joined: the daily card
auto-opens on join, so "after the daily reveal closes" = "on join". Change
the trigger in `NotifyOptInController`:

- **Earliest:** 5 min of this session's play (`os.clock()` from Init), and
  the tutorial done.
- **Then** fire at the first high moment after that, whichever comes first:
  - a successful fusion's result card closes;
  - an Epic-or-better pull reveal closes;
  - the daily reveal closes (only counts once the 5 min have passed).
- **Fallback:** at 8 min, if none happened, ask the next time no overlay is
  open (keep the 20 s give-up).
- Still once per session, all the existing guards (no tutorial, no overlay,
  no ask within 1 s of a loss or purchase prompt, `/selftest` suppress,
  `CanPromptOptInAsync`). Roblox enforces the 30-day cooldown itself.
- Put the numbers in a config (`RewardConfig` or a new `NotifyConfig`):
  `MinSessionSeconds = 300`, `FallbackSeconds = 480`, `MinPullTier = "Epic"`.
- Update the selftest section from NOTIFY_OPTIN (inject a clock so it
  doesn't wait 5 real minutes): before 5 min a reveal close → not called;
  after 5 min a fusion success close → called once; at the fallback time
  with no moment → called once; a second moment → still once.
- Update the "Notify opt-in" section in `docs/systems/rewards.md`.

## 3. Harris as a listed admin

The fuzz logs `SUSPICIOUS AdminAction from non-admin ILIKESIMULATORGG
(1599938767)` in Studio (the owner lookup fails on an unpublished /
Team Create place). Put `1599938767` in `AdminConfig.AdminUserIds` so
`/trailer` and `/admin` work for him everywhere. The fuzz must still prove a
non-admin is refused: use a fake negative id for that check, not his.

## 4. `[UIKit] modal TutorialCard opened without a card on screen` (x5 on join)

It shows on a save with Rebirths >= 3 whose tutorial is Done. Find who
opens the TutorialCard modal for a finished tutorial and stop it: no card,
no backdrop, no warning when `Tutorial.Done`. Selftest: join-state with
`Done = true` → the TutorialCard modal never opens in the first 10 s.
