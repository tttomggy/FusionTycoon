# Saves (ProfileStore) and offline earnings

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Saves (ProfileStore, session-locked):** PlayerDataService's backend is
  the vendored `Packages/ProfileStore.lua` (MadStudioRoblox, commit
  45c9847) in the store **`FT_Live_1`**, which is also the save wipe:
  every save in the old `PlayerData_v1` (plain GetAsync / SetAsync) is
  abandoned and never read again. A profile is held by ONE server: a
  second server waits for the lock and steals it after ProfileStore's
  standard timeout (~40 s), so the old server's later writes are refused;
  that old server kicks the player ("Your save was opened in another
  server, please rejoin") from `OnSessionEnd` while they're still in game.
  A load that fails (or takes over 90 s) kicks in live games and never
  overwrites the save. The session cache stays separate from
  `profile.Data` (sparse numeric pedestal keys can't be stored):
  `OnSave` writes a fresh disk copy (`toDisk`), `OnLastSave("Shutdown")`
  runs the release hooks and pays pending offline cash first, leaving
  writes the final copy then `EndSession`. Autosave every 120 s
  (`AUTO_SAVE_PERIOD`); ProfileStore owns BindToClose. `SaveNow` =
  `profile:Save()`; `SaveNowAsync` waits for `OnAfterSave` while the
  profile is still active. `PlayerData.Version = 1` + `profile:Reconcile`
  against the template, then `reconcile()` sanitises every field.
  Public API unchanged (plus `IsProfileActive`, `IsReceiptSaved`).
  **Studio:** ProfileStore's mock store (a blank profile every Play, never
  saved), unless ServerScriptService has the attribute `FT_StudioSaves =
  true` (and API access), which uses the separate store `FT_StudioTest_1`
  to test persistence. PedestalDisplays are stored with string keys on disk.
- **Offline earnings** (`OfflineConfig`): away time earns 25% of passive
  income per second, for at most 4 h, and nothing under 2 min.
  - `PlayerData.LastOnline` (`os.time()`) is written on every save. On load,
    `PlayerDataService` computes the payout from the income the player left
    with, moves `LastOnline` to now (and saves), and holds the payout as
    session-only pending earnings. The snapshot carries `PendingOffline`
    and `AwaySeconds`.
  - `OfflineService` pays it once on `ClaimOffline` (the client never sends
    an amount). If it's unclaimed, the first sync 30 s after load pays it,
    and leaving pays it on PlayerRemoving, so it's never lost.
  - Client: ResultController's welcome-back card (COLLECT; a hidden
    COLLECT ×2 slot for the monetization pass).
