# Playtime gifts restart every visit (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 4 lines. **Only these edits.**

---

## Change

Today the 6 playtime gifts (5 / 10 / 15 / 25 / 40 / 60 min) count play time
**summed across every visit in one UTC day**. If you rejoin, you're
already at 15 min, and the claims stay claimed until 00:00 UTC.

Harris wants it the way most simulators do it (Bubble Gum Simulator, Pet
Sim 99): **every visit starts fresh**.
- **On join, play time is 0 and no gift is claimed.** The first gift is
  always 5 min away.
- The timer counts **this visit only**. Leaving loses the unclaimed ones.
  That's fine, and it's the reason to stay.
- The rewards and minutes stay exactly as in `GiftConfig.Gifts`.

## How

- `PlayerData.Gifts` no longer needs saving.
  - Keep the session's play time and claims in `RewardService` memory, per
    player, created on join and dropped on leave.
  - Remove the `UtcDay` roll and the `Gifts` save field. `reconcile`
    ignores an old saved `Gifts` table (no error), and `toDisk` stops
    writing it.
- Server-authoritative as now:
  - `ClaimGift { Index }` is refused if this visit's play time is under
    the gift's minutes, or it's already claimed this visit;
  - the rate limit stays.
- AFK: count play time the same way as today (if it currently pauses when
  idle, keep that rule).
- **UI:**
  - **Gifts panel:** "Played today: 29:45" becomes "**This visit: 29:45**".
    The footer becomes "Gifts restart every time you join. Stay to open
    them all!" (keep the last gift's odds line).
  - **The GIFTS button** "next in" chip and badge read the session state.
- **Daily reward** (the 7-day streak) is unchanged: it stays once per UTC
  day.
- Update the `GiftConfig` header comment.

## Selftest

- Replace the "sums across sessions / resets at 00:00 UTC" checks with:
  - a fresh join is 0 s with no claims;
  - a claim before its minutes is refused;
  - after a simulated rejoin (`RewardService.SelfTestRejoin`, which drops
    and re-creates the session state) the time is 0 again and gift 1 can be
    claimed again;
  - an old save with a `Gifts` table loads without error and is ignored.
- Remote fuzz: a junk `ClaimGift` changes nothing.

## Check

- `luau-lsp analyze` shows no new errors.
- Update `docs/systems/rewards.md` and `saves-and-offline.md` (the `Gifts`
  field is gone).
- Harris: join, `/gifts time 6` (make it set **this visit's** time), claim
  the 5-min gift, then stop and Play again. The panel shows "This visit:
  0:0x" and the 5-min gift is open again.
- Say which branch you pushed to.
