# Fusion Tycoon — Launch 1: save safety, daily rewards, playtime gifts, leaderboards, analytics (build prompt for Claude Code)

Paste into Claude Code on `world-redesign` (`git pull` first). Open a new PR →
`main`. Don't merge.

---

Read CLAUDE.md and follow it. Commit each phase on its own. The canvas board
**"Retention · daily rewards, playtime gifts, leaderboards"** shows the UI.
**Phase 1 is the most important thing in this file.** The game now sells
things for Robux, and the save layer is `GetAsync` / `SetAsync` with no
session lock.

## Phase 1 — Save safety (blocker for launch)

**The problem**
- A player who leaves server A and joins server B before A's save lands loads
  stale data in B, and whichever save lands last wins.
- With stealing and real purchases, that means duplicated items and
  overwritten Robux purchases.
- `SetAsync` also never merges.

**The fix:** move PlayerDataService's backend to **ProfileStore**
(MadStudioRoblox/ProfileStore, MIT).
- Vendor the single module under `src/ServerScriptService/Packages/`,
  note its commit hash in a header comment, and add it to the Layout section of
  CLAUDE.md.
- **Session locking:** a profile is held by one server. A second server waits
  for the lock and steals it after ProfileStore's standard timeout, so the old
  server's later writes are refused.
- **Store name:** a new store, `FT_Live_1`. This also serves as the **save
  wipe**: every Studio and test save so far is abandoned on purpose. Leave the
  old store name in a comment and never read it again.
- **Keep PlayerDataService's public API exactly the same.** Only the
  load/save internals change: the session cache, `SaveNow`, the autosave,
  `OnRelease`, BindToClose, and the "failed load kicks in live / blank
  profile in Studio" behaviour.
- **On a lost lock** (`OnSessionEnd` while still in game), kick: "Your
  save was opened in another server, please rejoin".
- **`ProcessReceipt` only grants while the profile is active** for that
  player. The `Receipts` list stays inside the profile, so a grant and its
  receipt land in the same write.
- **Heist delivery** keeps its one synchronous block. Both profiles are
  active, so both writes go through their own sessions. `SaveNow` → the
  ProfileStore save call.
- **Data version:** `PlayerData.Version = 1`, plus a `Reconcile` with the
  template for missing fields.
- **Studio** keeps using a blank, never-saved profile (ProfileStore's mock
  mode), as now.
- **Tests (UI_TEST):** two Studio servers can't share a profile, so explain
  how to test the lock in a published place with 2 servers. Also test that a
  steal survives a server shutdown, and that a Studio purchase grant
  (`/shop grant`) followed by an immediate leave is still there on rejoin.

## Phase 2 — Daily rewards

**Config:** `DailyConfig`, 7 days. Every amount scales with the player, in
seconds of base income, like the shop's cash packs:

| Day | Reward |
|---|---|
| 1 | 10 min of income |
| 2 | ×2 income 15 min (the shop's boost pool) |
| 3 | 3 free gacha pulls (pulls at the current price, paid by the game, real pull animation) |
| 4 | ×2 luck 15 min |
| 5 | 1 Safe Fusion token |
| 6 | ×2 income 1 h |
| 7 | 1 item: Epic 70% / Legendary 25% / Mythic 5% (odds printed on the card), with the normal mutation roll |

**Streak rules**
- `PlayerData.Daily = { Day = 1..7, LastClaimUtcDay, Skips = 1 }`.
- A claim is allowed once per UTC day.
- Missing exactly one day uses the free skip (the streak continues). Missing
  more resets to Day 1 and restores the skip.
- After Day 7 the next claim is Day 1 again.

**Card**
- Shown once per UTC day on the first join, after the offline welcome-back
  card closes, and never stacked on another card.
- A 7-tile row: claimed tiles dimmed with ✓; today's tile gold, glowing,
  "TODAY"; Day 7 purple.
- A big green "CLAIM DAY 4" button; claiming plays the reward reveal.
- A "🔥 4-day streak" pill and the footer line with the skip rule and the Day 7
  odds.
- **Remote:** `ClaimDaily` (C→S, no payload). The server decides the day and
  the reward.
- Region-restricted players (MonetizationService policy) still get daily
  rewards: they're free.

## Phase 3 — Playtime gifts

**Config:** `GiftConfig`. The gifts open at **5 / 10 / 15 / 25 / 40 / 60
minutes of play today** (UTC day, summed across sessions, so rejoining doesn't
reset them):

| Minute | Gift |
|---|---|
| 5 | 5 min of income |
| 10 | 1 free pull |
| 15 | ×2 income 10 min |
| 25 | 15 min of income |
| 40 | ×2 luck 10 min |
| 60 | 1 item: Rare 60 / Epic 35 / Legendary 5 (odds shown) |

`PlayerData.Gifts = { UtcDay, PlaySeconds, Claimed = {} }`. Play seconds
tick on the server while the player is in game.

**HUD:** a pink "🎁 GIFTS" button next to SHOP.
- A green count badge shows how many gifts are ready, and the button bounces
  while any are.
- When none are ready, a small "next in 3:12" pill sits beside it.

**Panel:** six gift boxes:
- claimed: dim, with ✓,
- ready: green glow, "OPEN!",
- locked: shows "25 min".

Tapping a ready gift claims it. **Remote:** `ClaimGift { Index }`; the server
validates the time and that it wasn't already claimed.

## Phase 4 — Street leaderboards

- **Three boards** in StreetLayout: 💰 BEST INCOME /s (the player's
  highest-ever passive income, `PlayerData.BestIncome`), 🏆 MOST REBIRTHS, and
  📖 INDEX FOUND. Each is a big SurfaceGui board from BillboardKit, readable
  from the street, placed clear of belts, gates and the Event Boards (the
  StreetLayout assertions decide).
- **Data:** each stat is an OrderedDataStore (`LB_Income_1`, `LB_Rebirths_1`,
  `LB_Index_1`).
- **Writes:** at most every 2 min per player, on leave and on BindToClose.
- **Reads:** the top 10 every 2 min.
- **Each row:** the rank (1/2/3 in gold/silver/bronze row tints), the avatar
  headshot (`GetUserThumbnailAsync`, cached), the display name, and the value
  (`NumberFormat`).
- **Studio:** fill the boards with obvious fake rows ("TestPlayer1…"), so the
  layout can be checked without DataStore access.

## Phase 5 — Analytics

**Onboarding funnel:**
`AnalyticsService:LogOnboardingFunnelStepEvent`, once per player, for these
steps:

1. join
2. claim lab
3. first upgrade
4. first pull
5. first display
6. first fuse
7. first Multiplier Pad
8. first event seen
9. first rebirth
10. first steal

**Economy:** `LogEconomyEvent` for:
- cash sources: income ticks summed per minute, coins, cash packs, daily and
  gifts;
- cash sinks: upgrades, pulls, the pad, rebirth.

**Custom events:**
- shop opened,
- offer shown / accepted / dismissed,
- each product purchase (key),
- daily claimed (day),
- gift claimed (index),
- steal started / delivered / saved.

Keep the calls in one `AnalyticsKit` wrapper so a failure never breaks
gameplay. Wrap each call in pcall and send nothing in Studio.

## Phase 6 — Docs and checks

- **CLAUDE.md:** ProfileStore and the session lock, `FT_Live_1`
  (the wipe), the receipt rule, DailyConfig / GiftConfig, the leaderboards,
  AnalyticsKit, and the new remotes.
- **UI_TEST:** add cases for the daily card (claim; the skip rule via a
  `/daily day <n>` / `/daily miss <days>` debug command), gifts
  (`/gifts time <min>`), the boards' fake rows in Studio, and the analytics
  calls logging in Output (Studio only, as print).
- **Checks:** `luau-lsp analyze` reports no new errors, and the
  PlotLayout / StreetLayout assertions pass. Commit per phase, push, and open
  the PR.
