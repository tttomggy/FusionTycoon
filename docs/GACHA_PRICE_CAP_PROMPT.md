# Gacha pull price: cap it to income (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 6 lines. **Only these edits.**

---

## The problem

- Harris played a run to the end: **one pull cost $18.7B** while his income
  was **$24M/s**. That's 13 minutes of income for ONE pull, and a ×10 auto
  pull is over 2 hours.
- The price is `250 × 1.045 ^ pulls`, which goes ×9 every 50 pulls. With
  Auto pull ×10, a run hits ~400 pulls fast, and from there income can never
  catch up.
- The price resets on rebirth, but late in a run the pad is dead. Players
  stop pulling, so the fusion path to Mythics and Secrets starves.

## The fix: an income cap (Harris approved)

The price still climbs as now early in a run, but one pull never costs more
than **`GachaMaxIncomeSeconds` (start at 15) seconds of steady income**.

```lua
-- steady = income without anything temporary or bought
price(pulls) = math.floor(math.min(
	250 * 1.045 ^ pulls,
	math.max(250, GachaMaxIncomeSeconds * steadyIncomePerSecond)
))
```

- **Steady income** is `GetPassiveCashPerSecond` with
  `EventGeneratorMultiplier`, `BoostMultiplier`, `OverclockMultiplier` **and
  `PassMultiplier`** forced to 1.
  - A timed boost, an event or a bought 2× Cash / VIP pass must **never**
    raise the pull price. Buyers would be punished.
  - Add `TycoonConfig.GetSteadyIncomePerSecond(inputs)` for this, built
    from the same `IncomeInputs`. No second formula.
- **One function for everyone:** `GetGachaPullCost(pulls, steadyIncome)`
  and `GetGachaMultiPullCost(pulls, count, steadyIncome)` (the sum of the
  next `count` prices).
  - Update every caller: `TycoonService` (prompts + the charge at ~621 /
    625 / 686), `GachaBoardController` (~283), `RebirthPanel` (~173: pull
    0, so the cap doesn't matter there), and the selftest.
  - The **server's number is the one charged.** The client shows its own
    `GetIncomeInputs` version, and the card / pad label refresh on every
    sync, so a mismatch lasts at most one sync.
- Update the header comment above `GachaBasePullCost` to describe the cap.

## Tune with the sim (required)

- Add the cap to `tools/econ_sim.py`, with the same steady income and the
  same formula.
- Try `GachaMaxIncomeSeconds` at 10, 15, 20 and 30 with
  `python3 tools/econ_sim.py 30 12 --fuse=2` and `--fuse=3`. Pick the value
  that meets:
  - The early milestones (first pull, first Legendary, first Mythic, Rebirth
    1) are within ±10% of today's header table. The early game isn't the
    problem.
  - The **first Secret** median clearly beats today's ~8:30 (`--fuse=2`)
    and happens within 12 h on `--fuse=3`. Aim for roughly 3–5 h.
  - **Late in a run** (the last 30 min before each rebirth), a ×10 pull
    costs ≤ about 3 minutes of steady income.
  - Rebirth still comes before maxing everything else: pulling mustn't
    become so cheap that it replaces upgrades.
- Update the TycoonConfig header table with the new medians, and say which
  value you picked and why, in one line.

## Selftest

- `GetGachaPullCost(1000, 1e6)` equals `15 × 1e6` (or the cap you picked),
  and `GetGachaPullCost(0, 1e9)` is 250.
- A timed boost or a 2× Cash pass doesn't change the price (compare steady
  income with and without them).
- The pad card and the server charge the same price for the same pulls and
  income.
- Keep the existing gacha key checks. Update any that hard-code the old
  price with the new formula.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs.
- Update `docs/systems/items-and-fusion.md` (the gacha price rule).
- Harris: on a late-run save (`/rebirths 3`, then play or `/cash`), a single
  pull costs at most about 15 s of your $/s, and ×10 at most about 2.5 min.
- Say which branch you pushed to.
