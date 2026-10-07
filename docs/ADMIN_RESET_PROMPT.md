# Admin panel: reset a player (build prompt for Claude Code)

`git pull` on `world-redesign`, then commit and push to `world-redesign`.
Small job; reply in 5 lines.

---

Harris wants to test the tutorial in the **live game**, and to be able to
wipe a player. Add a **Players** section to the `/admin` panel
(`AdminService` + `UI/AdminPanel`).

**UI:**
- A list of every player in **this server**, with **you first, labelled
  "(you)"**. Each row has the avatar headshot, display name, Rebirths and
  cash.
- Tapping a row selects it.
- Two buttons below the list:
  1. **↺ RESTART TUTORIAL**: resets only the selected player's
     `PlayerData.Tutorial`, the same as `/tutorial reset`. It rebuilds their
     HUD state and re-syncs them, so the tutorial starts again without
     rejoining. Nothing else changes.
  2. **⚠ RESET TO ZERO**: wipes the selected player's save back to a brand
     new player. The tutorial starts again as well.
- **Confirmation for RESET TO ZERO:** a second step with the red text
  "Reset <name> to zero? This can't be undone." and a 2 s **hold** button.

**Server (every rule from CLAUDE.md "Server authority" / Admin Abuse):**
- **New actions:** `AdminAction` gains `RestartTutorial { UserId }` and
  `ResetPlayer { UserId }`.
  - Re-check the sender is an admin.
  - The target must be in this server.
  - Rate limit 1 per 5 s.
  - Log every use with `warn`, including who reset whom.
- **What ResetPlayer does:**
  - fails the target's active carries first, the same way `/wipe` does;
  - resets their profile data to the template through PlayerDataService,
    with one new function such as `ResetToNew(player)`;
  - rebuilds their plot (unclaimed, as for a new player);
  - re-syncs them, then saves.
- **What ResetPlayer keeps:**
  - the `Receipts` list, so Roblox never re-grants an old purchase;
  - the `Funnel`, so analytics doesn't count them as new again.

  Gamepasses live on Roblox and stay owned.
- **Not across servers:** only players in this server, no `FT_Admin`
  broadcast for these two actions.

**Check:**
- `luau-lsp analyze` shows no new errors.
- A non-admin firing either action gets the SUSPICIOUS warn and nothing
  changes. Add that to the `/selftest` fuzz.
- Update `docs/systems/leaderboards-analytics-admin.md`.
