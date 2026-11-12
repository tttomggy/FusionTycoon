# Retention fix report (Day-1 retention and first-session length)

Branch `world-redesign`. Scheduled, unattended run; nothing was published.

## The data this answers

Live ad test, Nov 3-10 (~365 new users, 95% Sponsored Ads): Day 1 retention
1.9-2.1% (genre band ~5-15%), Day 7 0%, average playtime 4.6-4.7 min. Funnel by
user (367 joins): ClaimLab 89.4% → FirstUpgrade 86.3% → FirstPull 99.3% →
FirstDisplay 100% → FirstFuse 80.8% → **FirstRivalSteal 70.0% (30% churn, the
biggest early drop)** → FirstMultiplier 84.3% → FirstEvent 56.7% →
FirstRebirth 7.9%.

Three parts, smallest safe changes. No economy number changed.

## 1. FirstRivalSteal (the 30% drop)

### What made the first steal fail

Measured with the real `RivalConfig.SimulateEscape` (Luau CLI, every one of the
132 slot-to-slot routes, carrier at 12 studs/s) and the real slot rules:

1. **The steal arrow sent new players to the Medium lab, whose guard outruns
   them.** Labs spawn Insane, Hard, Medium, Easy, and each took the nearest free
   slot, so the Easy lab always got the farthest of the four. `tipRival`, the
   mission box and the coach point at the *nearest* lab with a grabbable orb.
   For a player in **any of the 12 slots, Medium was nearer than Easy** (Easy
   ~112 studs gate to gate on average, Medium ~53). Medium's guard runs 13, a
   carrier 12: with the guard 6 studs behind at the grab, **0 of 132 routes get
   home**; with it right on the thief, 0; only a 10-stud head start works.
2. **Even on Easy, a guard met head-on catches you.** The guard patrols between
   the pedestals and the gate. The model with the guard 10 or 20 studs *ahead*
   (between the pedestal and the exit): **0 of 132 routes** get home on Easy,
   because the tag grace is only 2 s.
3. The run itself was long (the Easy lab was the farthest one), inside the 3-min
   mission window and a 4.6-min average session.

Hold time (1.5 s), the prompt, weapons / ragdoll (Rebirth 0 players can't be
hit) and the 3-min window were not the cause, so they are unchanged.

### What changed (`RivalConfig.FirstSteal`, `heist.md`)

- **The Easy lab spawns nearest the players.** Slots are measured gate to gate
  (`PlotLayout.GetSlotGatePosition`: across the street is nearest);
  `RivalConfig.SlotPickIndex` makes each lab leave one nearer slot per lower
  difficulty still to spawn. Easy is now across the street from the player
  (36 studs gate to gate) in every slot, Medium next door, Hard / Insane
  farther. The despawn order is unchanged.
- **A joining player's plot goes next to the Easy lab**
  (`TycoonService.SetSlotAnchor(RivalService.GetEasyGate)`: the free slot
  nearest its gate; the lowest free slot without an Easy lab, as before).
- **Until the first delivery the arrow picks the Easy lab.** `GoalMarkerController`
  (`NearestRivalPedestal`: tipRival's arrows, the mission box title) and
  `GoalService.nearestRivalWithOrb` (the coach line) prefer the lowest difficulty
  with a grabbable orb, then the nearest (`RivalConfig.BetterTargetLab`); after
  the first delivery, the nearest as before. The client reads the save's state
  from the snapshot's new `RivalStealDone`.
- **A save's first rival steal is forgiving** (no `FirstRivalSteal` funnel mark
  yet, `PlayerDataService.HasFunnelStep`): no guard tag for 10 s
  (`FirstSteal.TagGraceSeconds`, was 2 s) and the chasers run at most 11
  (`FirstSteal.MaxGuardSpeed`, below the carrier). 10 s at 12 studs/s = 120
  studs, past Easy's and Medium's leash, so the guard has given up or fallen
  behind before it may tag. The guard still chases (the tension stays), the
  "RUN!" banner lasts the grace.
- Later steals, the hold, the 45 s carry, the hourly pools, the orbs and the
  economy are unchanged.

Model result (`/selftest retention`, same numbers in the Luau CLI): a first steal
from Easy **or** Medium gets home on **132 / 132** routes with the guard 6 / 6
behind, on the thief, 10 ahead or 25 ahead (later steals: Easy 132 / 132 behind,
0 / 132 ahead; Medium 0 / 132 unless 10+ studs ahead of the guard).

### /selftest coverage (section 18, `/selftest retention`; `Modules/RetentionSelfTest`)

- The escape model above over every pair of slots, Easy and Medium, four gap sets.
- Later steals keep the 2 s grace and every guard speed; first-steal chasers are
  slower than a carrier; the grace outruns Medium's leash.
- Placement: the four labs spawned around a player in each of the 12 slots put
  Easy nearest; a joining player lands no farther from Easy than the old rule
  (printed: average gate distance new vs old); `SlotPickIndex` clamps when slots
  are short.
- The arrow rule (`BetterTargetLab`) before / after the first delivery.
- Live: a grab from the Easy lab with the tester's mark cleared is a first steal
  (10 s grace, chasers <= 11); with the mark set it is a normal one (2 s). The
  tester's mark, hourly pools and position are put back.
- Section 16 (rival labs) now marks the tester as having delivered a rival steal
  while it runs, so its existing checks keep testing the later-steal rules.

## 2. A reason to come back tomorrow

### The come-back card (`ComeBackController`, `UI/ComeBackCard`, `RetentionConfig.ComeBack`, `rewards.md`)

ONE card, once per account, in the first session, never during the tutorial:

- From 150 s of this visit's play, at the first natural pause: a big fusion /
  pull card or the x10 card closing, the daily reveal closing, a delivered rival
  steal. From 240 s (~4 min; the average first session was 4.6 min) the next
  time the screen is quiet. Never over another card / panel / shop side card,
  never while carrying, ragdolled or frozen. Pure rule:
  `RetentionConfig.ShouldShowComeBack`.
- A `UIKit.Modal` centred in the card band (`FitContent`, the daily card's
  layer), three rows of real numbers (`RetentionConfig.PlanComeBack`):
  - TOMORROW · DAY 2: x2 income for 15 min; "Then Day 3: 3 free pulls · Day 7:
    1 Epic+ item" (the `DailyConfig` ladder).
  - WHILE YOU'RE AWAY: "Your lab earns up to $X" (X = the server's
    `OfflineConfig.Compute(base income, 4 h)`, new snapshot field `OfflineMax`),
    "25% of your income, for up to 4 h".
  - TODAY'S REWARD IS READY (if Day 1 is unclaimed; the button then reads CLAIM
    TODAY'S REWARD and opens the daily card) or EVERY VISIT · 6 playtime gifts.
- No countdown, no pressure copy, nothing sold. Opening sends `ComeBackShown`;
  the server re-checks it (`CanMarkComeBack`: first session, not seen, tutorial
  done, 150 s in), saves the `comeBack` tip and logs it.

### Are Day 1-2 rewards and offline earnings worth coming back for?

Checked, **not changed**: every daily amount is seconds of the player's *own*
base income, so none is trivial at any income. A greedy player's base income
(`tools/econ_sim.py` probe, median of 20 seeds) is ~$131/s at 4 min and ~$290/s
at 5 min (~$1,156/s at 10 min). Day 1 (10 min of income, floor $2,500) is then
~$79k-174k; Day 2 (x2 income for 15 min) is another 15 minutes of income; a
night away (25% of income for up to 4 h = 1 h of income) is ~$0.5-1.0M, against
a $5,000 first Multiplier level and ~$15M for Rebirth 1. Since no economy number
changed, `tools/econ_sim.py` was not re-run for a before / after (a full
`30 12 --rivals` run did not finish in this session's 2-minute command limit;
the first-steal grace changes no economy number and the sim's rival model
already assumes Easy steals land).

### /selftest coverage

The client probe "ComeBack" (part of section 18): the rule case by case (pause
before / after 150 s, the 240 s fallback, never over a card, while busy, during
the tutorial, twice, in a later session), a Day 1 player's plan (tomorrow Day 2,
then Day 3 and 7), the real card opened with a plan: the real offline number and
tomorrow's reward shown, the claim button, every line fits, centred in the card
band (`UIKit.CheckCardPlacement`), closes; GOT IT once today's is claimed. The
server half: `ComeBackShown` refused at 0 s, accepted once eligible, never twice.
The remote fuzz sends junk `ComeBackShown` payloads.

## 3. Measuring the first 5 minutes (`leaderboards-analytics-admin.md`)

All through `AnalyticsKit` (prints `[Analytics] …` in Studio, sends live). The
funnel order is untouched: `Day2Return` is **appended** (step 13, after
FirstOrbRush).

| Event | When | Value / field |
|---|---|---|
| `SessionMinutes` | 2, 5, 10 minutes of each visit's play | minutes / `FirstSession` or `Returning` |
| `FirstRivalStealStarted` | a grab on a save's first rival steal | lab rank / difficulty |
| `FirstRivalStealDelivered` | that carry delivered | - / difficulty |
| `FirstRivalStealFailed` | that carry failed | - / `Tagged`, `Knocked`, `Timeout`, `Died`, `Failed` |
| `ComeBackShown` | the come-back card opened (server re-checked) | minutes played / `DailyClaimed` or `NoDaily` |
| `ReturnVisit` | the first join of each later UTC day | days since the first join / `NextDay` or `Later` |
| funnel `Day2Return` | the first such join, once per player ever | |

`Day2Return` / `ReturnVisit` come from two new saved numbers,
`PlayerData.FirstUtcDay` / `LastJoinUtcDay` (`RetentionConfig.OnJoin`): a new
save starts its first day today; an old save with exactly one earlier session
(the ad-test players) is dated by its last save, so their returns count too;
older saves are unknown (-1) and never counted. `SessionMinutes` ticks on
`RewardService`'s existing per-second play clock.

What to read after the next test: FirstRivalStealStarted vs FirstRivalSteal (did
they find the lab and grab?) and FirstRivalStealFailed's field (why the carry
failed); SessionMinutes FirstSession 2 / 5 / 10 (first-session length);
ComeBackShown over SessionMinutes 5 (how many saw the card); ReturnVisit NextDay
and the Day2Return funnel step over Join (our own D1, by cohort).

## Checks before push

- `python3 tools/compile_check.py luau-compile` (luau-lang release, 2026-11-07):
  159 files, 0 errors.
- `python3 tools/theme_token_check.py`: clean.
- `luau-lsp analyze` 1.70.1 with the current `globalTypes.d.luau`, diffed as a
  distinct set (line numbers stripped) against the base commit `d0300eb`: **the
  same set**, the 6 known errors (SparkleEmitter x2, BillboardKit
  `DistanceLowerLimit`, NotifyService `pcall`, TopStack x2), nothing new.
- The open-paren grep: no new code line starts with `(`.

## Not verified without Studio

- Nothing here ran in Studio: `/selftest retention` (and the full `/selftest`)
  have not been run. The pure rules were run in the Luau CLI (the escape model,
  the slot placement, `PlanComeBack`, `OnJoin`, `CrossedMarks`).
- The guards' real pathing on a first steal (the model is straight-line; the
  live check only reads the chaser's WalkSpeed and the grace).
- That the Easy lab really ends up across the street in a live server (the
  placement rule is pure and checked; the spawn timing with several players
  joining at once is not).
- The come-back card's look on desktop and phone, its timing against the daily
  card, the notification opt-in and ORB RUSH (it does not check the arena
  explicitly; a modal waits for a quiet screen), and that `TextFits` holds at
  the phone scale.
- The analytics events reaching the Creator Hub dashboard (Studio only prints).
- Day 2 return logging needs a real next-day join (Studio saves are mock).
