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
  3 strings and paste their ids into `NotifyConfig.StringIds`; nothing sends
  before 100 visits, then check Notifications → Analytics. Strings (examples):
  `Admin Abuse is LIVE in {experienceName}: x{luck} luck for {minutes}
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
