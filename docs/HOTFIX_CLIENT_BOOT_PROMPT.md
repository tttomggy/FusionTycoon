# HOTFIX: the live client never boots (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines, one per group: FIXED or WHY-NOT.

---

The live game (published from 0d8d19f) has **no HUD, no weapon bar, no
tutorial**, and Roblox's default hotbar shows. The live client's F9 log:

```
SelfTestController:1875: Ambiguous syntax: this looks like an argument list
for a function call, but could also be a start of new statement; use ';' to
separate statements
Requested module experienced an error while loading
Script 'Players.ILIKESIMULATORGG.PlayerScripts.Bootstrap', Line 33
```

## 1. The syntax error (0d8d19f, the notify opt-in commit)

`SelfTestController.lua` ~1874–1875: two lines that both start with `(`,
the exact gotcha in CLAUDE.md. Line 1875 is parsed as a call on line 1874's
result.

- Route both through locals:
  ```lua
  local DailyController = require(script.Parent.DailyController) :: any
  local NotifyOptInController = require(script.Parent.NotifyOptInController) :: any
  DailyController.SelfTestSuppress(suppressDaily)
  NotifyOptInController.SelfTestSuppress(suppressDaily)
  ```
- **Grep all of `src/` for any other line that starts with `(` (after
  whitespace)** and fix each the same way. Report how many you found.

## 2. One broken controller must never kill the whole client

`Bootstrap.client.lua` requires and Inits ~28 controllers in one script, so
any error in any of them (here: a Studio-only test file) leaves the player
with nothing.

- Require and Init each controller through a small helper that wraps it in
  `pcall` / `xpcall` and `warn`s `"[Bootstrap] <Name> failed: <err>"` plus
  the traceback, then carries on with the next.
- Keep the order exactly as it is. The `task.spawn(... .Init)` ones stay
  spawned (wrap the function they run).
- `SelfTestController` and `TrailerController`: required **last**, after
  every gameplay controller has Init'ed, so they can never block gameplay
  even if the pcall is removed later. SelfTestController only Inits in
  Studio (`RunService:IsStudio()`); TrailerController stays as it is (admins
  use it live).
- If a controller fails, the rest of the HUD must still come up; a missing
  dependency should fail that controller, not the boot.

## 3. Prove it parses before pushing

- Run `luau-lsp analyze` (CLAUDE.md commands) over `src/` and paste the
  error count. Only the 2 known SparkleEmitter errors (and the 2 known
  TopStack ones) are allowed. If luau-lsp can't run in your session, say so
  in your reply, and instead run any Luau parser you can (e.g. `luau
  --compile` / `luau-analyze`) over every `.lua` file in `src/`.
- Add one line to the "Gotchas" section of CLAUDE.md: "Studio may accept
  code the live client rejects (ambiguous `(` syntax). A file that doesn't
  parse kills Bootstrap: run the parser before every push."
