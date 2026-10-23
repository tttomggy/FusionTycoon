# Notify opt-in: ask for notifications at the daily-reward high point (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines, one per group: DONE or WHY-NOT.

---

Why: since June 2026 Roblox ranks games on play days and playtime across
D1, D2–7 and D8–28. The game already gives players reasons to come back
(the 7-day daily streak, offline earnings), but nothing reminds them
outside the game. Roblox's experience notifications do that, and players
can only get them after opting in. Players we don't ask before launch are
opt-ins we lose. Sending notifications comes later (Roblox requires 100+
visits); this prompt is only the ask.

## 1. The opt-in prompt (client only)

- New `NotifyOptInController` (or a small section in `DailyController`, your
  call; keep it out of `TutorialController`).
- **When:** right after the player **closes the daily reveal** that follows a
  successful claim (`DailyCard.ShowReveal` → its close). This is the moment
  they've just seen "come back tomorrow for Day N+1".
- **Guards, all must pass:**
  - `TycoonController.IsTutorialActive()` is false;
  - no other overlay is open (`UIKit.IsOverlayOpen()`, `ShopCards.IsSideOpen()`);
    if one is, wait for it like `tryAutoOpen` does, max 20 s, then give up
    for this session;
  - not suppressed by `/selftest` (same pattern as
    `DailyController.SelfTestSuppress`);
  - at most **once per session**;
  - `ExperienceNotificationService:CanPromptOptInAsync()` inside `pcall`
    returns true. Roblox already enforces under-13, already-opted-in and the
    30-day cooldown; don't add our own save field for that.
- **Then:** `pcall(ExperienceNotificationService.PromptOptIn, ...)`. The modal
  text is Roblox's; don't add a card of ours before it.
- Never call it after a purchase prompt or a failed fusion in the same
  second (the monetization "never" list's spirit: no asks after a loss).
- Log `NotifyOptInShown` and `NotifyOptInClosed` (from
  `OptInPromptClosed`) through `AnalyticsKit`, the way the other custom
  events go (a client → server remote only if AnalyticsKit is server-side;
  add it to `REMOTE_EVENT_NAMES` and rate-limit it with `RemoteGuard.Allow`).
- Add a short "Notify opt-in" section to `docs/systems/rewards.md`.

## 2. Selftest

- Make the service calls injectable (a `SetServiceForTest` that swaps in a
  stub with `CanPromptOptInAsync` / `PromptOptIn`), and in `/selftest`:
  - tutorial active + reveal closed → the stub's `PromptOptIn` is **not**
    called;
  - tutorial done, no overlay, reveal closed → called **once**; a second
    reveal close in the same session → still once;
  - stub `CanPromptOptInAsync` errors → no client error, not called.
- Restore the real service after the section.

## 3. `marketing/README.md`

- The "Home Recommendations" / "Thumbnail Performance" lines still say
  QPTR. Roblox removed QPTR; it's now **play-through rate (PTR)** and
  **first-play bounce rate**, measured only for players who came from Home
  recommendations. Update the wording; keep the thumbnail order as it is
  (FUSE TO SECRET first, stealing's R1 bounce warning stays).
