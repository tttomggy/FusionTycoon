# Notify ids, phone window guard, friend recheck (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines, one per group: DONE or WHY-NOT. Run the Luau parser over `src/`
before pushing.

---

## 1. The three notification string ids

Harris created the strings in Creator Hub (Engagement → Notifications). The
ids are **UUIDs**, not asset numbers. Put them in `NotifyConfig.StringIds`
exactly as below:

```lua
NotifyConfig.StringIds = {
	AdminAbuse = "a951a5cd-b76b-8642-9854-b00b979e3224", -- Admin Abuse is LIVE: x{luck} luck for {minutes} min!
	DailyStreak = "723f39b7-ec59-b247-8974-f952865a812d", -- Your Day {day} reward is ready. Keep your {streak}-day streak!
	LabFull = "f8502273-b1a4-9442-ba36-b11fa7e8509c", -- Your lab is full: {cash} is waiting for you.
}
```

- Check that `message_id` in the request body takes these strings as-is (no
  `tonumber`, no asset-id validation that rejects a UUID). If anything
  assumes digits, fix it; update the selftest's fake id (`"999"`) to a UUID
  shape too.
- Fix the comment above `StringIds` ("paste each asset id") to say the
  strings' **UUIDs**, and that `{experienceName}` is not sent (the title is
  the game's name).
- Parameters sent must be exactly `{luck}` `{minutes}` / `{day}` `{streak}` /
  `{cash}`: confirm, and assert it in the selftest (each type's Params keys
  equal the placeholders in its comment).

## 2. The window guard on an emulated phone

On Studio's device emulator (iPhone 13: 749 × 388) the run always ends with
`FAIL selftest window: the game view is 749 x 388 ...`, although every phone
check passed. A phone-sized view is the point of that run.

- In `windowProblem` / where its FAIL is reported: when the view is
  **phone-sized** (`UIKit.IsPhone()`, or touch enabled with no keyboard),
  report it as `PASS selftest window: phone view 749 x 388, desktop-only
  live-screen checks skipped` (still skip the same desktop-only checks).
- A small **desktop** view (no touch) keeps the FAIL as it is today.

## 3. Friends made mid-session

`FriendService` only rechecks pairs on join/leave, so two players who become
Roblox friends while in the same server get no boost until one rejoins.

- Every `FriendConfig.RecheckSeconds` (60), recheck the pairs whose cache has
  expired, **one pair per ~0.5 s** (spread out, never a burst), from one
  loop spawned in `:Start()`. Sync only the players whose count changed;
  a count that grows here shows `👥 You and <DisplayName> are friends: +15% income!` (not the "joined" text; they were already here).
- Selftest: with the stub, flip a pair to friends, advance the injected
  clock past RecheckSeconds, run one recheck step → both counts +1.
