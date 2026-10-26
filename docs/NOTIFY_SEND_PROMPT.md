# Notify send: daily streak, Admin Abuse and full-lab notifications (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 5 lines, one per group: DONE or WHY-NOT, plus the exact setup steps
Harris must do (group 5). Run the Luau parser over `src/` before pushing.

---

The opt-in ask is live (NotifyOptInController). This prompt sends the
actual notifications. It's **inert until the game has 100+ visits** (a
Roblox rule) and until Harris fills in the string ids, so ship it safe.

Roblox's limits (design around them):
- **one notification per user per day per experience**, delivery not
  guaranteed; only 13+ opted-in users receive it;
- each send targets ONE user id (no broadcast);
- strings are made in Creator Hub (Engagement → Notifications), ≤ 99 chars,
  each has an asset id;
- they must be personal and actionable, no fake urgency, no ads.

## 1. Sending (server only, new `NotifyService`)

- Open Cloud `POST https://apis.roblox.com/cloud/v2/users/{userId}/notifications`
  via `HttpService:RequestAsync`, header `x-api-key` from
  `HttpService:GetSecret("OpenCloudNotify")` (pcall'd: no secret = disabled,
  one `warn` at start, nothing else). Body:
  ```json
  { "source": { "universe": "universes/<game.GameId>" },
    "payload": { "message_id": "<asset id>", "type": "MOMENT",
                 "parameters": { "day": { "string_value": "4" } } },
    "join_experience": { "launch_data": "daily" },
    "analytics_data": { "category": "DailyStreak" } }
  ```
- Off in Studio (`RunService:IsStudio()`), off if `HttpService.HttpEnabled`
  is false, off for any type whose string id is `""`.
- Every send: pcall, log status code once per type per server, never
  retry a 4xx; back off 60 s after a 429.

## 2. What we send (new `NotifyConfig`, one string id per type, priority order)

| Type | When | Text Harris will create (example) |
|---|---|---|
| `AdminAbuse` | when an admin STARTS Admin Abuse from the panel (AdminService's start-event / luck action; only the server that received the action queues it, so it's not queued once per server) | `Admin Abuse is LIVE in {experienceName}: x{luck} luck for {minutes} min!` |
| `DailyStreak` | the next UTC day after their last daily claim, if not claimed yet, ~3 h after 00:00 UTC | `Your Day {day} reward is ready. Keep your {streak}-day streak!` |
| `LabFull` | `OfflineConfig.MaxSeconds` (4 h) after they left, if they haven't returned | `Your lab is full: {cash} is waiting for you.` |

- Highest priority wins for a user that day; never send a second one the
  same UTC day (we track it ourselves too, so we don't waste calls).
- Never to someone who's in the game right now (any server: check the
  presence entry below).
- Parameters come from their saved data at queue time (`NumberFormat.Money`
  for cash). Text is Roblox-filtered; keep parameters to numbers.

## 3. Queue (MemoryStore, works across servers)

- Sorted map `NotifyQueue`: key = userId, value `{ Type, DueAt, Params }`,
  sort key = DueAt. On PlayerRemoving, queue `LabFull` and `DailyStreak`
  (the earlier-due/higher-priority one kept per user). On PlayerAdded,
  remove their entry (and write a presence key with a short TTL, refreshed
  while they're in).
- Sorted map `RecentPlayers`: userId → last seen, TTL 7 days (MemoryStore
  max is 45 days; 7 is enough). Admin Abuse queues everyone in it who isn't
  present, capped at `NotifyConfig.AdminAbuseMaxRecipients = 2000`.
- A worker on every server every 30 s: `GetRangeAsync` the due entries
  (batch 50), claim each with `UpdateAsync` (so two servers never send the
  same one), send, delete. Stay well inside MemoryStore limits; one worker
  loop per server, spawned in `:Start()`.

## 4. Launch data on join

- `player:GetJoinData().LaunchData`: `"daily"` → open the daily card once
  the HUD is up (after the tutorial guard); `"admin"` → nothing extra (the
  event is already visible); `"lab"` → nothing extra (the welcome-back card
  already shows). Whitelist the strings.

## 5. Harris's setup (put these exact steps in your reply)

1. Game Settings → Security → **Allow HTTP Requests** on.
2. Creator Hub → API Keys → create a key with the **user notifications
   write** permission for this experience; Creator Hub → the experience →
   **Secrets** → add it as `OpenCloudNotify`.
3. Creator Hub → the experience → Engagement → **Notifications**: create the
   3 strings above, paste their ids into `NotifyConfig`.
4. Nothing sends before 100 visits; then check Notifications → Analytics.

Also: selftest the pure parts (priority pick, same-day dedupe, due-time
maths for DailyStreak/LabFull, launch-data whitelist) with an injected
clock and a fake sender; no real HTTP in Studio. Docs: a "Notifications"
section in `docs/systems/rewards.md`, the services in `architecture.md`.
