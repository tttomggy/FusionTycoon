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
- **Notify opt-in** (`NotifyOptInController`, client only): once per session,
  right after the daily card closes from a granted claim (`DailyCard`'s
  `OnRevealClosed` handler), it calls Roblox's
  `ExperienceNotificationService:PromptOptIn()`. The modal text is Roblox's;
  we show no card of ours. Guards: no tutorial; no UIKit overlay or shop side
  card (waits up to 20 s, then gives up for the session); no failed fusion or
  purchase prompt in the last second; not `/selftest`-suppressed
  (`SelfTestSuppress`, set by `clearScreen`); and `CanPromptOptInAsync()` in a
  `pcall` must return true (Roblox enforces under-13, already opted in and the
  30-day cooldown; we save nothing). Logs `NotifyOptInShown` /
  `NotifyOptInClosed` (`OptInPromptClosed`) through remote
  `NotifyOptInAnalytics { Event = "Shown" | "Closed" }` → `RewardService` →
  `AnalyticsKit.Custom` (`RemoteGuard.Allow`, whitelisted). `/selftest` swaps
  a stub in with `SetServiceForTest(stub, tutorialProbe)` (tutorial active →
  not called; bare screen → once, a second close still once; erroring
  `CanPromptOptInAsync` → not called, no error) and restores the real service.
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
