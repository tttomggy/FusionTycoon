Branch: world-redesign

# Studio /selftest fixes report

Not verified in Studio (none available). Checked: `compile_check.py` (155 files, 0 errors), `theme_token_check.py` (clean), `luau-lsp analyze` distinct set vs the base commit (identical; one line-number shift only), no new lines starting with `(`.

## 1 + 2. ORB RUSH pill / list vs the HUD
Cause: `MinigameController.hudRects` used `HudController.GetObstacleRectsFor`, whose rects have the top-bar inset added back (screen space), while the OrbRush gui's `Position` / `AbsolutePosition` sit below that inset. Placement and the selftest compared two different spaces, off by the inset (about 36-58 px), which put the pill inside the LockRow / PhoneStatus / PhoneGrid / DealBadge rects. Fix: `hudRects` subtracts the inset (in logical px) from every rect, so placement and measurement share a space. Also, `placeColumn` now adds the pill's rect before placing the list, so the list can no longer sit on the pill.
HUD rects before / after at 1920x1080, 1366x768, 844x390, 896x414: the HUD itself is unchanged; only the ORB RUSH positions move (up by the inset, i.e. directly below the lowest column rect instead of overlapping it). Exact pixel rects need Studio and are not measured.

## 3. Hover check vs arena debris
`testHover` skips the "inside a plot slot" test for targets under `Workspace.OrbRushArena`; the rest-pose (HoverBase / bob) test still applies to them. Everything else stays strict.

## 4. Fuzz Tips flake
`PlayerDataService.SelfTestFingerprintFields` now fingerprints only Tips ids that are not valid TipConfig ids (the tutorial's own tips like tipRival are the game, not a junk remote). An invalid id appearing still fails.

## 5. Scheduled rounds vs /selftest
`MinigameService.SetSelfTest(on)`: the scheduler opens no call while on, a scheduled call already open is aborted, and a running round is aborted when it is switched on. `DebugService.runSelfTest` sets it before the run and clears it right after the pcall (so also on error). The two nil-award checks: `DebugStartNow` returns false when a round is already running, so the results were stale/nil. Section 17 now uses `startForcedRound` (abort, start, retry once after waiting for Idle) and both checks require that the round started.

## Could not verify without Studio
The four-viewport HUD overlap numbers, the hover/fuzz/section-17 results, and that a results overlay already open on the client before /selftest starts closes (the abort sends no Results message).
