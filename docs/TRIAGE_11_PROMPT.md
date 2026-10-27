# Triage 11: gacha card clamp follows toasts, rival light budget test (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines, one per group: FIXED or WHY-NOT. Run the Luau parser,
`tools/theme_token_check.py` and `luau-lsp analyze` (if it runs) before pushing.

---

Harris ran ec30ac8 on PC (1920 x 1080) and the phone emulator. Fails:

```
FAIL rivals: a rival lab's lights stay within one claimed player lab's: floor 6 vs 7, orb lights 8 (max 4)
FAIL gacha card (phone 844x390): ... card x -15..142 y 130..304, stack bottom 51, weapon bar top 256 | x -15..142 is off the 844 px width; bottom 304 is below the weapon bar at 256
FAIL gacha card (phone 896x414): ... x -17..152 y 135..323, stack bottom 51, weapon bar top 280 | x off the 896 px width; bottom 323 is below the weapon bar at 280
FAIL gacha card (desktop 1920x1080): ... live top 64 (min 157) | live card top 64.0 is above the stack's bottom + 4 = 157
FAIL gacha card (desktop 1366x768): ... live top 64 (min 157) | live card top 64.0 is above the stack's bottom + 4 = 157
```

## 1. Gacha card: clamp to the STABLE stack bottom, not the toast

Root cause (all four gacha fails, desktop and phone): the clamp
(`GachaBoardController.stackBottomPx`) and the live selftest check use
`TopStack.GetBottom()`, which includes the **announcement line's height
while a toast is up** (here 157 vs the stable 64). So:
- on phone, a toast makes the clamp slide the card ~80 px down, past the
  weapon bar (the phone's own `PhoneScaleFor` placement was already right
  before TRIAGE_10, so group 3 broke it);
- on desktop, the card jumps down and up with every toast (2.5 s each), and
  the live check disagrees with the pure check (which uses
  `PlanFor(...).Announce` = the stable bottom, 64).

Decision: a transient toast must **never move the card**. The card clears the
**chip row** (Objective + Chip), and toasts draw over it for 2.5 s (a
ScreenGui is above a BillboardGui; fine).

- Add `TopStack.GetStableBottom()` = `TopStack.GetY("Announce")` (the
  announce line's top = the chip row's bottom, in logical px; the caller
  scales for phone). Use it in `stackBottomPx()`, in the live selftest
  check (desktop AND phone), everywhere the card compares to the stack.
  Keep `GetBottom()` for whoever needs the full height.
- `clampToStack`: on **phone, don't clamp** (`PhoneScaleFor` owns phone
  placement: top = chip row + `PhoneTopGapPx`, which already satisfies the
  rule); keep the pure function for the selftest only. On desktop, set only
  `SizeOffset.Y` and **preserve `SizeOffset.X`** (build `want` from the
  current X, not `Vector2.new(0, ...)`).
- The phone fails also say the card is `x -15..142` (off the left edge).
  Check whether that predates ec30ac8 (run the 844 x 390 check on 835d372
  mentally / by reading the code: nothing in TRIAGE_10 touches X except the
  `Vector2.new(0, ...)` above). If it's older, say so and fix it too:
  the card must be fully on screen (±0) at 844 and 896.
- Selftest: the live check must be **independent of toasts**: run it once
  with no announcement and once with `TopStack.Announce` showing; the drawn
  top is the same in both (±1 px) and ≥ stable bottom + 4. Both desktop
  sizes and both phone sizes pass.

## 2. Rival light budget: the test counts wrong

`DebugService` ~2558-2562: `rivalOrbs <= RivalConfig.PedestalCount` (4)
assumes ONE light per pedestal, but a pedestal has two (the `RarityVisuals`
pedestal light and the orb light), so a full lab is 8. The rival lab's 8 is
exactly what a fully filled player lab adds (4 pedestals x 2); the check is
what's wrong. The rival floor lights are 6 vs the player's 7, correct.

- Define the budget in the check as what a **fully filled player lab** adds:
  `2 * RivalConfig.PedestalCount` pedestal lights (a constant next to
  `RivalConfig.PedestalCount`, with a comment), and assert it.
- Also assert every rival light obeys the CLAUDE.md caps: Brightness
  0.8-1.6 (orb light 1), Range 8-12, `Shadows = false`.
- Don't reduce the rival visuals to fit the old number.

## 3. Docs

`docs/systems/items-and-fusion.md` / `tutorial.md` where the gacha clamp is
described: the card clears the chip row (stable bottom), toasts never move
it, phone is not clamped. `heist.md` rival light budget line.
