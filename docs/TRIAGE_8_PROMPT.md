# Triage 8: friend banner nil colour, theme-token check, phone tray rows (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines, one per group: FIXED or WHY-NOT. Run the Luau parser over `src/`
before pushing.

---

Harris's `/selftest` on PC and iPhone 13 (3b0ba77): one FAIL each, plus a
client error on phone:
```
Unable to assign property BackgroundColor3. Color3 expected, got nil
FAIL passes circle: the phone tray (844 x 390) holds Friends + Passes + 3 timed effects on one row ... : 2 rows, 48 px icons, touches:
```

## 1. The nil colour: the friend banner never shows

`AnnouncementController.ShowFriendJoined` (~line 614) uses
`Colors.AccentGreen`, but `AccentGreen` lives in **`UITheme.World`**, not
`UITheme.Colors`, so `AccentColor` is nil and the banner errors at
`bar.BackgroundColor3 = announcement.AccentColor` (~192). Every
"👥 Bob joined" / "You and Bob are friends" banner has been dying since
74ed31a.

- Add a proper UI token to `UITheme.Colors` (e.g. `Friend` or `Success`,
  the same green `#3BEB7E`) and use it. Don't point UI code at
  `UITheme.World` (world part colours).
- Make `enqueue` defensive: a nil `AccentColor` falls back to `Colors.Text`
  and `warn`s once with the caller's text, instead of erroring.

## 2. A static theme-token check (so this class of bug can't ship again)

`tools/theme_token_check.py` (I committed it) scans `src/` for
`UITheme.<Table>.<Key>` and local aliases (`local Colors = UITheme.Colors`
then `Colors.X`) whose key isn't defined in that UITheme table. On this
tree it reports `Colors.AccentGreen` (real) and 4 `pair.Top/Bottom` in
UIKit ~100–104 (false positives: `pair` is a gradient pair, not a table
key).

- Teach it to skip those false positives (only flag aliases assigned
  directly from a UITheme table; `pair` isn't).
- Make it exit non-zero when it finds anything, run it before every push
  (next to the Luau parser) and add that line to CLAUDE.md's Gotchas.

## 3. The phone tray test: two rows are fine

At 844 × 390 the space right of TopStack fits 4 cells of 48 px, so 5 cells
wrap to 2 rows. The plan already picks that and touches nothing
(`touches:` is empty). My earlier prompt asked for one row; that was too
strict.

- Change the check to: ≤ 2 rows, touches nothing (HUD, TopStack, jump
  button), every tap target ≥ 44 px, all on screen. Same at 896 × 414.
- No layout change.
