# Fuse ladder: they fuse Common → Rare and stop; more early goals; "both earn money" (build prompt for Claude Code)

Run `git pull` on `world-redesign` (after `LOOP_NUDGE` is in), then commit and
push to `world-redesign` (or a side branch `triage21-check` if you can't run
`tools/compile_check.py`).
**Line 1: the branch. Line 2: "untested in Studio" (also in the commit
message).** Then one line per group: DONE or WHY-NOT. Run
`tools/theme_token_check.py`, `luau-lsp analyze` and `tools/econ_sim.py`
(goal rewards are cash) before pushing.

---

Harris watched a real player for 5 minutes: good pace, understood the
tutorial, pulling, upgrading, even did a steal. Then they got stuck on
fusing: they keep fusing Common → Rare and **don't realise they can switch
the tab to Rare and fuse Rares into Epics**, and so on up. Also: they don't
know that BOTH the generators (machines) and the orbs make money.

Decision: **keep the tier tabs** (one long scroll of every tier would be
worse: ~100 cards), and make the next tier impossible to miss.

## 1. The Fuse panel leads you up the ladder

(`UI/FusePanel.lua`; tabs already show the fusable count.)

- **Auto-jump:** when the panel opens, and right after a fuse finishes (the
  result card closes), select the **highest tier that has ≥ 2 fusable
  orbs**, unless the player picked a tab themselves in this open (then
  respect it until the panel closes). The chamber starts empty on the new
  tab; the existing "more orbs = better odds" line stays.
- **Ready dots:** a tab with ≥ 2 fusable orbs and that isn't selected gets a
  small pulsing dot and its count in white; tabs with < 2 are muted.
  (UITheme tokens, no Highlight instances; keep each tab ≥ 44 px tall on
  phone.)
- **The ladder strip** above the tabs (one line, icons): `⚪ → 🔵 → 🟣 → 🟡
  → 🔴 → 🌈`, the tiers from `UITheme.TierOrb`; the player's highest owned
  tier lit, the NEXT tier to aim for pulsing with a small label
  `Next: Epic`. Tap a tier = jump to its tab. Hidden if it doesn't fit on
  phone (the dots and auto-jump still work).
- **Result card:** after a successful fuse, under `NEW ORB!` add one line
  with a button: `Fuse 2 Rares → Epic next` / `GO TO RARE` (jumps the
  panel's tab and closes the card), only when the player owns ≥ 2 of the new
  tier. Otherwise `Pull more orbs, then fuse 2 of these!` with the Gacha
  arrow.
- The goal tracker's tier goal already says "Fuse your 2 Rares: 57%": make
  sure its arrow/target plus these panel changes agree (the panel opens on
  Rare when the goal is "Fuse Rares into an Epic").
- Selftest: owning 3 Commons + 2 Rares → opens on Rare; after a fuse that
  leaves 1 Common + 3 Rares (stub) → Rare stays; owning nothing fusable →
  opens on Common; a manual tab pick survives until close; the ready dot
  shows on a tab with ≥ 2 and not with 1; tab tap targets ≥ 44 px at
  844 x 390.

## 2. More early goals (the goal list is the player's to-do list)

`GoalConfig` has gaps right where this player stalled (after "Own a Rare"
you get Multiplier, then Epic). Add, as real goals with rewards that follow
the economy (run `econ_sim.py`; they must not move the Rebirth-1 target
milestone by more than ~1 min):

- `Max your Basic Generator (LV 25)` (Unit `Basic LV`, Target the
  generator, Loop `Upgrade`) right after `basic_lv5`... or wherever it
  fits the money curve; `Unlock the Flare Reactor`; `Own 3 Rares at once`;
  `Fill all 4 pedestals`; `Reach x1.5 multiplier`; `Own 2 Epics`.
  Pick ~6 from these (or better ones from the economy), ordered by when a
  new player can afford them.
- **Saved progress:** `GoalIndex` is an index; inserting in the middle
  shifts every saved player. Migrate: bump `DataVersion`, map the old index
  to the old goal **Id** (keep a frozen list of the old ids in the
  migration) and to its new index; a player past a new goal's slot gets it
  marked done without paying its reward (or pays it, your call, say which).
  Selftest each: a save at each old index lands on the same goal Id.
- The loop strip's `Loop` field stays correct for each new goal.

## 3. "Orbs AND generators both make money", said once, plainly

- One-time TopStack announce the first time the player owns a displayed orb
  AND has upgraded a generator: `Machines AND orbs both earn cash!`
- Tooltips: the loop strip's 💰 icon text becomes `Orbs on pedestals and
  generators both earn $/s`; the HUD income line's tap (if it has one) or
  the cash pill's tooltip says the same, with the split when known
  (`Generators $X/s · Orbs $Y/s`, from `GetPassiveCashPerSecond`'s parts,
  never a second formula).
- Selftest: the announce fires once, not during the tutorial; the strings
  come from config.

## 4. Docs

`items-and-fusion.md` (the ladder, auto-jump, dots, result-card line),
`tutorial.md` (the goal list and migration), `file-layout.md` if a file is
added.
