# Triage 9: the rival steal is the first thing a new player is pointed at (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines, one per group: FIXED or WHY-NOT. Run the Luau parser and
`tools/theme_token_check.py` before pushing.

---

Harris (8b98f2a): rival labs work (guard upright, `back in 1:21`, a
delivered Epic). But after `/tutorial reset` he was led to "Upgrade your
Basic Generator" (the NEXT GOAL path arrows + the `tipUpgrade` hand on
UPGRADES, both on screen at once), never to a rival lab.

His account had already delivered a rival steal, so `tipRival` was seen;
that part is expected. But on a fresh account the order is still wrong:
`tipUpgrade` fires the moment cash covers an upgrade (right after the
tutorial), the one-tip-at-a-time rule then holds `tipRival` back, and the
goal path (on for the first `GoalPathSessions` sessions) draws its own
arrows over everything.

## 1. Priority: the steal comes first

- After Tutorial 5's Done, `tipRival` is the **first** tip, ~20 s after
  "You're ready!" as now. Every other tip (`tipUpgrade`, `tipMultiplier`,
  `tipIndex`, `tipEvent`, `tipRebirth`, gift/quest hands) waits until
  `tipRival` is finished (delivered, or its 3 min ran out) plus the usual
  20 s.
- While `tipRival` is active, the **NEXT GOAL path arrows are hidden** (the
  goal card itself stays), so only one set of arrows is ever on screen.
  Generalise it: any active tip with its own path suppresses the goal
  path.
- If the server has no rival lab at that moment (full server), skip
  `tipRival` for this session (don't mark it seen) and let the others run.

## 2. Studio testing

- `/tutorial reset` (Studio only) also clears the tutorial-flow tips:
  `tipRival`, `tipUpgrade`, `tipMultiplier`, `tipIndex`, `tipEvent`,
  `tipRebirth`, and the `RivalSteals` hourly counter, so a reset replays
  the whole first-minutes experience. `/tips reset` stays as it is.
- Update `docs/systems/studio-commands.md`.

## 3. Selftest

- Fresh save, tutorial Done, cash ≥ the cheapest upgrade, a rival lab
  present: the first tip shown is `tipRival`; the goal path is hidden while
  it runs; `tipUpgrade` comes only after `tipRival` ends + 20 s.
- No rival lab present: `tipRival` is skipped and not marked seen.
- `/tutorial reset` clears the listed tips and the counter.
