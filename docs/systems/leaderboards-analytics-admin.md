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
  FirstUpgrade, FirstPull, FirstDisplay, FirstFuse, FirstMultiplier,
  FirstEvent, FirstRebirth, FirstSteal. `Source` / `Sink` →
  `LogEconomyEvent` ("Cash"): passive income summed per minute
  (`AddIncome`, flushed on leave too), coins, cash packs (IAP), daily and
  gift cash (TimedReward); upgrades (a MAX is ONE event), pulls, the pad,
  rebirth. `Custom`: ShopOpened, OfferShown / OfferAccepted /
  OfferDismissed (client → remote `ShopAnalytics`, whitelisted,
  rate-limited), Purchase (key), DailyClaimed (day), GiftClaimed (index),
  StealStarted / StealDelivered / StealSaved, QuestClaimed (id),
  PowerUpUsed (key). Never call AnalyticsService
  directly.
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
