# Hotfix: HudController doesn't compile (over 200 locals) — 18 selftest FAILs are this one bug (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines: what you moved, the `tools/compile_check.py` result, the
`luau-lsp analyze` result.

---

Harris ran 1bc04bb on PC and phone: 18 FAIL each, and most of the client is
dead. The first red line in the log:

```
HudController:2396: Out of local registers when trying to allocate placeColumnFor: exceeded limit 200
[Bootstrap] HudController failed: Requested module experienced an error while loading
```

Luau allows at most **200 locals alive in one function**, and a module's top
level is one function. The loop strip (1bc04bb) pushed `HudController`'s top
level past it (266 top-level `local` lines; ec79d5b still compiled). Roblox
refuses the module, so everything that requires it fails: GoalMarker,
Factory, Heist, Event, Tutorial, FusePanel, EffectsTray, QuestBadge... and
every "FAIL probe ... Requested module experienced an error while loading",
`FusePanel:1291 index nil with 'Visible'`, `EffectsTray:1227 index nil with
'Enabled'`, "client half: no report", the stuck tutorial, the fuse odds /
tip / AUTO-FILL lines all come from it. **`luau-lsp analyze` can't see this;
only the real compiler can.**

## 1. Fix (no behaviour change)

- Move the goal tracker (incl. GOAL_STEPS' lines and the loop strip) out of
  `HudController` into its own module `UI/GoalTracker.lua`, with a small
  API HudController calls (build, update from the snapshot / GoalProgress,
  GetFrame / rects for the left-column stack). Keep every name the selftest
  reaches for working (re-export from HudController if a probe uses it).
- If that doesn't bring HudController's top level to **≤ 170** live locals
  (headroom), also group related constants / helper functions into tables
  (e.g. `local Layout = {}` with fields) rather than one local each.
- No other changes. Same look, same layout, same selftest names.

## 2. Check

- `python3 tools/compile_check.py <path to luau-compile>` must report 0
  files with compile errors (get `luau-compile` from
  https://github.com/luau-lang/luau/releases, `luau-ubuntu.zip`; it's what
  caught this). Then `luau-lsp analyze` (no new diagnostics) and
  `tools/theme_token_check.py`.
- From now on run `compile_check.py` before **every** push, next to the
  other two (CLAUDE.md Gotchas says so now).
