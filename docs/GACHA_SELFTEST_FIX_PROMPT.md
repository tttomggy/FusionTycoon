# Two gacha selftest FAILs: exact fixes (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines. **Only these edits.**

---

Harris ran `/selftest gacha` on `b890d88`:

```
FAIL gacha keys: RequestGachaPull from 25 studs is refused (TooFar) and costs nothing: ok false, reason TooFar, cash 9039.125 -> 9090.125
FAIL gacha card: while it is open the pad's GACHA label and your VIP chip are hidden: label Enabled false, VIP chip Enabled true
```

## 1. "costs nothing": the test is wrong, not the game

The refusal works (`TooFar`). Cash went **up** by $51 because passive
income ticked during the wait. Comparing cash for equality can't pass.

In `SelfTestController`, for this check:
- record the **gacha pull count** (`TycoonController` / the synced data)
  and the **inventory count** before and after;
- pass when the reason is `TooFar`, both counts are unchanged, and cash
  after ≥ cash before;
- the Detail prints all three before → after.

## 2. VIP chip: the hide only runs once

`GachaBoardController.hideVipTag(view, true)` only runs when
`view.VipTag` is nil, at open or after a respawn. Once it has stored a
tag, anything that turns the chip back on stays on while the card is open.
The selftest does exactly that (`chip.Enabled = true`), and a server-side
VIP re-apply would too.

**Fix:** enforce it rather than doing it once. In the per-step refresh
where `if view.Open and not view.VipTag then hideVipTag(view, true) end`
sits, replace that with:

```lua
if view.Open then
	hideVipTag(view, true) -- enforce every step: anything that re-enables the chip is undone
end
```

`hideVipTag(view, true)` already re-finds the tag on the current head and
sets `Enabled = false`, so this is safe to call every step. Closing still
restores it through `hideVipTag(view, false)`.

In the selftest's `probeGachaCovers`, after `chip.Enabled = true`, wait
**two** Heartbeats after `Board.RefreshNow()` before reading. Don't change
anything else in the probe.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest gacha` has no FAILs.
- Say which branch you pushed to.
