# Street leaderboards, analytics, Admin Abuse

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Street leaderboards** (`LeaderboardService`, spots in
  `StreetLayout.Leaderboard`): 💰 BEST INCOME /s (`PlayerData.BestIncome`,
  the highest BASE income reached), 🏆 MOST REBIRTHS, 📖 INDEX FOUND; past
  the street's ends flanking the Event Boards (StreetLayout asserts: off
  the street, past the last plot, clear of the Event Boards, on the
  ground). OrderedDataStores `LB_Income_1` (stored as
  floor(log10(1 + $/s) × 1e12)), `LB_Rebirths_1`, `LB_Index_1`; writes at
  most every 2 min per player (only changed values), on leave (OnRelease)
  and on BindToClose; reads the top 10 every 2 min. Rows: rank (1 / 2 / 3
  tinted `RankGold` / `RankSilver` / `RankBronze`), cached headshot
  (`GetUserThumbnailAsync`), display name (UserService, cached), value
  (NumberFormat). `BillboardKit.LeaderboardSurface` / `SetLeaderboard`.
  Studio: fake "TestPlayer1…10" rows, no DataStore calls.
- **Analytics** (`ServerScriptService/Modules/AnalyticsKit`, the ONE
  wrapper round AnalyticsService; every call in a pcall; in Studio it
  prints `[Analytics] …` and sends nothing). `Funnel(player, step)`:
  `LogOnboardingFunnelStepEvent` once per player ever (`PlayerData.Funnel`,
  via `SetFunnelStore` from PlayerDataService): Join, ClaimLab,
  FirstUpgrade, FirstPull, FirstDisplay, FirstFuse, FirstRivalSteal,
  FirstMultiplier, FirstEvent, FirstRebirth, FirstSteal, FirstOrbRush
  (ORB RUSH; APPENDED at the end so the live funnel's indices do not move),
  Day2Return (the first join on a later UTC day than the first join,
  `RetentionConfig.OnJoin`; APPENDED too)
  (FirstRivalSteal went
  in after FirstFuse with the rival labs, so every later step moved up one;
  fine pre-launch, and `PlayerData.Funnel` is keyed by name). `Source` / `Sink` →
  `LogEconomyEvent` ("Cash"): passive income summed per minute
  (`AddIncome`, flushed on leave too), coins, cash packs (IAP), daily and
  gift cash (TimedReward); upgrades (a MAX is ONE event), pulls, the pad,
  rebirth. `Custom`: ShopOpened, OfferShown / OfferAccepted /
  OfferDismissed (client → remote `ShopAnalytics`, whitelisted,
  rate-limited), NotifyOptInShown / NotifyOptInClosed (client → remote
  `NotifyOptInAnalytics`, whitelisted, rate-limited), Purchase (key), DailyClaimed (day), GiftClaimed (index),
  StealStarted / StealDelivered / StealSaved, RivalStealDelivered /
  RivalStealTagged (the guard's touch or a weapon hit) / RivalStealTimeout
  (field: the orb's tier), RivalGuardHit (weapon), OrbRushQueued /
  OrbRushPlayed (value = humans in the round) / OrbRushPlace (value = place) /
  OrbRushPrize (field = tier), QuestClaimed (id),
  PowerUpUsed (key). Never call AnalyticsService
  directly.
  **The first 5 minutes** (retention fix, `docs/RETENTION_FIX_REPORT.md`):
  | Event | When | Value / field |
  |---|---|---|
  | `SessionMinutes` | 2, 5 and 10 minutes of each visit's play (`RewardService` tick, `RetentionConfig.CrossedMarks`) | minutes / `FirstSession` or `Returning` |
  | `FirstRivalStealStarted` | a grab on a save's first rival steal (no FirstRivalSteal mark yet) | the lab's rank (1 Easy, 2 Medium) / difficulty |
  | `FirstRivalStealDelivered` | that carry delivered (the funnel's FirstRivalSteal fires with it) | - / difficulty |
  | `FirstRivalStealFailed` | that carry ended any other way | - / `Tagged` (a guard's touch), `Knocked`, `Timeout`, `Died`, `Failed` (the lab went / data); a player who leaves mid-carry logs nothing |
  | `ComeBackShown` | the come-back card opened (server re-checked) | minutes played / `DailyClaimed` or `NoDaily` |
  | `ReturnVisit` | the first join of each later UTC day | days since the first join / `NextDay` or `Later` |
  | funnel `Day2Return` | the first such join ever (appended step 13) | |
  Reading them: FirstRivalStealStarted / FirstRivalSteal (by user) is "found and
  grabbed" vs "got home"; FirstRivalStealFailed's field says why; SessionMinutes
  `FirstSession` 2 / 5 / 10 is the first-session length curve; ReturnVisit
  `NextDay` over Join (by first day) is our own D1.
- **Admin Abuse** (`AdminService`, numbers in `AdminConfig`): admins are
  `AdminConfig.AdminUserIds` plus the place owner (creator, or the group's
  owner). `/admin` opens the panel by sending `AdminOpen` to admins only;
  the client never builds it otherwise. Every `AdminAction` is re-checked
  (non-admins get a SUSPICIOUS warn) and every arg whitelisted. Start event,
  end event, gift everyone (EventReward "🎁 ADMIN GIFT"), luck ×3 for 10
  min, broadcast (≤ 80 chars, `TextService:FilterStringAsync` broadcast
  string, dropped if filtering fails), set next Admin Abuse (DataStore
  `GlobalEvents` key `NextAdminAbuse`, UTC, read on start and every 5 min).
  "All servers" publishes `{ Action, Args, SenderUserId }` on
  MessagingService topic **`FT_Admin`**; every receiver re-checks the sender
  and re-validates. Every action is logged with `warn`.
  **Players section** (top of the panel): everyone in THIS server, you
  first ("(you)"), headshot + name + Rebirths + cash; tap to select.
  `RestartTutorial { UserId }` = `TutorialService.DebugReset` + sync (only
  `PlayerData.Tutorial` changes). `ResetPlayer { UserId }` = fail the
  target's heist carries (as `/wipe`), `PlayerDataService.ResetToNew`
  (session data becomes the `DEFAULT_DATA` template; **keeps `Receipts`,
  `Funnel`, `Sessions`**; Cosmetics and everything else go; gamepasses live
  on Roblox), `TycoonService.ResetPlot` (unclaimed plot, as for a new
  player), sync, save. The panel asks first: red "Reset <name> to zero?
  This can't be undone." and a 2 s hold button (`AdminConfig.ResetHoldSeconds`).
  Both: target must be in this server, 1 per 5 s per admin
  (`PlayerActionCooldownSeconds`), `warn` log of who did what to whom, never
  sent on `FT_Admin` (a received one is ignored), Scope is ignored.
  `/selftest` fuzzes both as a non-admin (SUSPICIOUS warn, fingerprint
  unchanged).
