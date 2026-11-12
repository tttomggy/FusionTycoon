# Daily rewards and playtime gifts

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Daily rewards** (`DailyConfig`, granted by `RewardService`): a 7-day
  cycle, every amount scaled to the player in seconds of BASE income:
  10 min of income / ×2 income 15 min (the shop's boost bank) / 3 free
  pulls / ×2 luck 15 min (the Luck Potion bank) / 1 Safe Fusion token /
  ×2 income 1 h / an item (Epic 70 / Legendary 25 / Mythic 5, the normal
  mutation roll). `PlayerData.Daily = { Day, LastClaimUtcDay, Skips,
  Streak }`; one claim per UTC day (`RewardConfig.GetUtcDay`); missing
  exactly one day spends the free skip, more resets to Day 1 with the skip
  back; after Day 7 comes Day 1 (the streak keeps counting). Remote
  `ClaimDaily` (C→S, no payload: the server picks the day and reward;
  record + grant with no yield) → `DailyResult`. The snapshot's `Daily`
  is `DailyConfig.GetStatus` at the server's UTC day. Region-restricted
  players get every free reward. **Free pulls and reward items** go
  through `TycoonService.GrantFreePulls` / `GrantRewardItem`: the plot's
  real pull path (VFX, Index, banners, the pull card with the reward's
  caption) and they **don't raise the pad price** (`PlayerData.FreePulls`,
  not `GachaPulls`); they do count for the `gacha_pull` goal and the
  FirstPull funnel step (the Day 7 / gift item does not).
  Client: `DailyController` opens `UI/DailyCard` once per session when
  claimable, 2 s after the first sync and only when no other card is open
  (UIKit overlays, shop side cards), so never over the welcome-back card;
  the 7-tile row (claimed: 50% dim + a small green ✓ badge top-right,
  today gold glowing "TODAY", Day 7 purple),
  "🔥 N-day streak", "CLAIM DAY N", the reveal, the footer (skip rule + Day
  7 odds). Pull days close the card for the real pull card.
- **Notifications** (`NotifyService`, server; numbers and pure rules in
  `NotifyConfig`): the three Roblox experience notifications, sent through
  Open Cloud `POST /cloud/v2/users/{id}/notifications` (`HttpService:
  RequestAsync`, `x-api-key` from `HttpService:GetSecret("OpenCloudNotify")`).
  Roblox allows ONE per user per day per experience, 13+ opted-in users only,
  one user per call, string ids made in Creator Hub (<= 99 chars).
  **Inert until it can work:** off in Studio, off if `HttpEnabled` is false,
  off without the secret (one `warn` at start), and a type whose
  `NotifyConfig.StringIds` entry is `""` is never queued or sent.
  | Type | Queued | Params |
  |---|---|---|
  | `AdminAbuse` | `AdminService` on a Luck or StartEvent action, **only by the server that got the action** (`NotifyService.QueueAdminAbuse(luck, minutes)`; an event + luck within 10 min queue once). Everyone in `RecentPlayers` not in that server, newest first, `AdminAbuseMaxRecipients = 2000`, paced 10/s | `luck`, `minutes` |
  | `DailyStreak` | player leaves; due the next UTC day after their last claim + 3 h (a reward already claimable waits 3 h from leaving; never for someone with no streak) | `day`, `streak` |
  | `LabFull` | player leaves; due `OfflineConfig.MaxSeconds` (4 h) later, only if the lab would earn something | `cash` (`NumberFormat.Money` of the full offline pay) |
  Per user at most one queue entry. A leaver keeps the earlier-due of
  DailyStreak / LabFull (`NotifyConfig.PickEntry`); an entry replaces a queued
  one unless the queued one is a higher type (`Merge`, priority AdminAbuse >
  DailyStreak > LabFull). One send per user per UTC day: `NotifySent` (hash
  map) is checked before every send and written after; a 429/4xx/5xx never
  uses the day up. **MemoryStore:** sorted map `NotifyQueue` (userId →
  `{ Type, DueAt, Params }`, sort key `DueAt`), sorted map `RecentPlayers`
  (7 days), hash maps `NotifyPresence` (90 s, refreshed by every server's
  worker while the player is in ANY server) and `NotifySent` (2 days).
  PlayerAdded removes the entry and writes presence; the release hook
  (`PlayerDataService.OnRelease`) queues. **Worker** on every server every
  30 s: `GetRangeAsync` the due entries (50), claim each with `UpdateAsync`
  (`ClaimedUntil` +120 s, so two servers never send the same one),
  `NotifyService.Process`, then delete. `Process(userId, entry, deps)` is the
  decision with its world injected (clock, string id, presence, sent day,
  sender): `Disabled` / `Stale` (due > 24 h ago) / `Present` / `AlreadySent` /
  `Sent` / `Backoff` (429: the whole worker waits 60 s, the entry stays) /
  `Drop` (other 4xx: never retried) / `Retry` (5xx, no answer, or a failed
  MemoryStore read: due again in 5 min, 3 tries). The status code of the
  first send of each type per server is logged. **Launch data on join:**
  `Player:GetJoinData().LaunchData` is whitelisted (`daily` / `admin` /
  `lab`, `NotifyConfig.ParseLaunchData`) and set as the player attribute
  `LaunchAction`; `DailyController` opens the daily card at once for `daily`
  (still after the tutorial / overlay guards; nothing if already claimed);
  `admin` and `lab` need nothing (the event and the welcome-back card are
  already visible). **Setup (Harris):** Game Settings → Security → Allow HTTP
  Requests; Creator Hub → API Keys → a key with the user notifications write
  permission for this experience, added under the experience's Secrets as
  `OpenCloudNotify`; Creator Hub → Engagement → Notifications → create the
  3 strings and paste their **UUIDs** (not asset numbers; sent as-is as
  `message_id`) into `NotifyConfig.StringIds`; nothing sends
  before 100 visits, then check Notifications → Analytics. `{experienceName}`
  is not sent (the title is the game's name); `NotifyConfig.Placeholders` lists
  each type's parameters (/selftest checks them). Strings:
  `Admin Abuse is LIVE: x{luck} luck for {minutes}
  min!` / `Your Day {day} reward is ready. Keep your {streak}-day streak!` /
  `Your lab is full: {cash} is waiting for you.`
- **Notify opt-in** (`NotifyOptInController`, client only): once per session
  it calls Roblox's `ExperienceNotificationService:PromptOptIn()`. The modal
  text is Roblox's; we show no card of ours. **Never on join** (the daily card
  auto-opens on join, so "after the daily reveal" used to mean "on join").
  Numbers in `NotifyConfig`: `MinSessionSeconds = 300`, `FallbackSeconds =
  480`, `MinPullTier = "Epic"`. Earliest = 5 min of this session's play
  (`clock()` from Init) AND the tutorial done. After that, the first high
  moment (`OnMoment(kind, tier)`) starts the ask: a successful fusion's big
  result card closing (`ResultController`, `Moment = "Fusion"`), a pull of
  Epic or better closing (a manual single pull's big card, or the ×10 card
  by its best tier; Auto pulls never count), or the daily reveal closing
  (`DailyCard`'s `OnRevealClosed`; counts only after the 5 min). A moment
  before 5 min or during the tutorial is lost. **Fallback:** once a second
  `Tick()` checks `FallbackSeconds`; at 8 min with no ask yet it asks the
  next time no overlay is open. Guards on every path: no tutorial; no UIKit
  overlay or shop side card (waits up to 20 s, then gives up for the
  session); no failed fusion or purchase prompt in the last second; not
  `/selftest`-suppressed (`SelfTestSuppress`, set by `clearScreen`); and
  `CanPromptOptInAsync()` in a `pcall` must return true (Roblox enforces
  under-13, already opted in and the 30-day cooldown; we save nothing).
  Logs `NotifyOptInShown` / `NotifyOptInClosed` (`OptInPromptClosed`)
  through remote `NotifyOptInAnalytics { Event = "Shown" | "Closed" }` →
  `RewardService` → `AnalyticsKit.Custom` (`RemoteGuard.Allow`,
  whitelisted). `/selftest` swaps in a stub service, a tutorial probe and a
  fake clock (`SetServiceForTest(stub, tutorialProbe, clock)`): tutorial
  active → not called; before 5 min a reveal or fusion close → not called;
  after 5 min a Rare pull → not called, a fusion success close → once; at the
  fallback time with no moment → once; a second moment → still once;
  erroring `CanPromptOptInAsync` → not called, no error.
- **Playtime gifts** (`GiftConfig`, `RewardService`): six gifts at 5 / 10
  / 15 / 25 / 40 / 60 minutes played **in this visit**: every visit starts
  fresh (0 s, nothing claimed), leaving loses the unclaimed ones
  (5 min income / 1 free pull / ×2 income 10 min / 15 min income / ×2
  luck 10 min / an item Rare 60, Epic 35, Legendary 5).
  The visit's `{ PlaySeconds, Claimed }` lives in `RewardService` memory only
  (created on join, dropped on leave, nothing saved; `PlayerData.Gifts` is
  gone and an old save's table is ignored), ticked once a second on the
  server while the player's data is loaded; the snapshot and the fuzz
  fingerprint read it through `PlayerDataService.SetGiftStateProvider`. The
  daily reward is unchanged (once per UTC day).
  Remote `ClaimGift { Index }` (server checks this visit's play time and
  claimed) →
  `GiftResult`. HUD: the pink "🎁 GIFTS" button right of SHOP (green ready
  badge + bounce, else a "next in 3:12" pill); `UI/GiftsPanel` (3 × 2
  boxes: claimed dim ✓ / ready green glow "OPEN!" / locked "25 min" with a
  bar, a "This visit: 29:45" line, the footer "Gifts restart every time you
  join. Stay to open them all!" and a daily-reward strip on top). The client counts play time on
  from the snapshot (`TycoonController.GetGiftPlaySeconds`).
- **The come-back card** (retention fix; `RetentionConfig.ComeBack`,
  `ComeBackController` + `UI/ComeBackCard`; `docs/RETENTION_FIX_REPORT.md`). The
  live Day 1 retention was ~2% with a 4.6-minute average session, and nothing in
  the first session said what coming back gives. ONE card, **once per account,
  in the first session** (`Shop.Sessions == 1`), never during the tutorial:
  from `MinSeconds` (150 s) of this visit's play at the first natural pause (a
  big fusion / pull card or the ×10 card closing: `ResultController.
  SetMomentHook`; the daily reveal closing: `DailyController.OnRevealClosed`; a
  delivered rival steal: `HeistController.SetDeliveryHook`), and from
  `FallbackSeconds` (240 s) the next time the screen is quiet (no UIKit overlay
  or shop side card, not carrying, not ragdolled / frozen). The pure rule is
  `RetentionConfig.ShouldShowComeBack`. A `UIKit.Modal` (`FitContent`, 560 ×
  392, the daily card's layer 125), centred in the card band: three rows from
  `RetentionConfig.PlanComeBack` - "TOMORROW · DAY 2 / ×2 income for 15 min /
  Then Day 3: 3 free pulls · Day 7: 1 Epic+ item" (the `DailyConfig` ladder,
  `RewardConfig.GetTitle`), "WHILE YOU'RE AWAY / Your lab earns up to $X / 25%
  of your income, for up to 4 h" (X = the snapshot's `OfflineMax`, the server's
  `OfflineConfig.Compute(base income, MaxSeconds)`), and either "TODAY'S REWARD
  IS READY / Day 1 · …" (the button then reads CLAIM TODAY'S REWARD and opens
  the daily card) or "EVERY VISIT / 6 playtime gifts". No countdown, no pressure
  copy, nothing sold. Opening fires `ComeBackShown { Event = "Shown" }`;
  `RewardService.MarkComeBackShown` re-checks (`CanMarkComeBack`: first
  session, not seen, tutorial done, `MinSeconds` of play), saves the
  `comeBack` tip and logs `ComeBackShown` (value = minutes played, field
  `DailyClaimed` / `NoDaily`). `/selftest` suppresses it with the daily card.
- **Day 1-2 values checked, unchanged** (retention fix): every daily amount is
  seconds of the player's own base income, so none is trivial at any income.
  At a greedy player's ~4-5 minute income ($130-290/s, `tools/econ_sim.py`),
  Day 1 (10 min of income, at least $2,500) is ~$78k-174k and Day 2's ×2
  income for 15 min is worth another 15 min of income; offline earnings for a
  night away (25% for 4 h = 1 h of income) are ~$0.5-1M, against a $5,000
  first Multiplier level. No economy number changed.
- **SessionMinutes** (analytics): `RewardService`'s play tick logs
  `SessionMinutes` at 2, 5 and 10 minutes of each visit
  (`RetentionConfig.CrossedMarks`; value = minutes, field `FirstSession` /
  `Returning`).
