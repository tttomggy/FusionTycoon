# Fuse path: players loop Common → Rare and never find Rare → Epic (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`
(or a side branch `triage21-check` if you can't run
`tools/compile_check.py`, as before; the planner moves it).
**Line 1: the branch. Line 2: "untested in Studio" (also in the commit
message).** Then one line per group: DONE or WHY-NOT. Run
`tools/theme_token_check.py` and `luau-lsp analyze` before pushing.

---

Harris watched a real player: got through the tutorial, knows how to pull,
upgrade and heist (steal) — and then **keeps fusing Common into Rare and
never goes further**. They don't know there's a next tier, and they don't
know they can switch the Fuse panel to the RARE tab to fuse Rares into
Epics. They also don't realise that BOTH the generators and the orbs on the
pedestals make money.

Cause: `FusePanel` always opens on the first tab (`selectedTier =
FusionConfig.TierOrder[1]`, Common), the tabs are five small equal boxes
(name over count, ~50 px) with nothing saying "you can fuse here now", and
after a fuse the result card just says OK.

Decision: **keep the tabs** (one scrolling list of every tier would bury the
chamber and the odds, and the panel is already full). Make the next step
obvious instead.

## 1. The panel opens on the best tier you can fuse

- On open: `selectedTier` = the **highest tier with ≥ 2 fusable orbs** the
  player may fuse (`CanFuseTierFor`), not Common. If a fusable tier was just
  used (the player came from a fuse), stay on the tab they were on unless
  the next tier up now has ≥ 2.
- Switching tab by hand still works and still clears the chamber.

## 2. Tabs say where the action is

- Every tab with ≥ 2 fusable orbs shows a small pulsing **FUSE!** pip (or
  the Selected look's glow) on its top edge; the best one (the highest) pulses
  and the rest are steady. Tabs with 0-1 orbs are dimmed (count in the muted
  colour). Mythic stays locked before Rebirth 1 with its 🔒.
- Tab count text shows `2 → 1` style? No: keep `name` over `count`, but add
  the arrow on the strip (group 3). All colours from `UITheme`, tap targets
  ≥ 44 px, `UIKit.SetSelected` for the selected one.
- Never animate with a Highlight; use a UIStroke / gradient pulse.

## 3. A path strip over the tabs: where this goes

A thin row above the tab row: `⚪ → 🔵 → 🟣 → 🟡 → 🔴 → ★ SECRET` (the tier
orbs from `UITheme.TierOrb` and the tier order from `FusionConfig`; never
typed). The player's best tier orb is lit, tiers above it muted, and the
last one is the Secret star. One caption: `Fuse up to reach SECRET!`. It
does not scroll and fits at 844 x 390 (drop the caption on phone).

## 4. After a fuse, point at the next one

On a successful fuse (the result card / reveal), when the player now has
≥ 2 of the **new** tier (e.g. 2 Rares): the card's button row gets a second
big button **`FUSE RARES →`** (the existing AGAIN stays); tapping it closes
the card, switches the panel to that tab and auto-fills the chamber. If they
don't tap it, the panel's tab still pulses (group 2). If they have < 2 of
the new tier: the card line says `Get 1 more Rare to fuse into an Epic!`
(tier names from config).

First time only (`TipConfig` id `tipFusePath`, saved like the others): when
the panel opens with ≥ 2 of a tier above Common and the player hasn't
switched tabs by hand yet, put the hand on that tab with the TopStack line
`You can fuse Rares into Epics! Tap RARE.` (names from config). One time per
account, never during the tutorial.

## 5. Generators AND orbs earn money (say it once, then show it)

- Tapping the HUD cash pill / the `+$X/s` line opens a small tooltip (the
  tray's tooltip rules): `⚙ Generators $A/s · 🔮 Orbs $B/s · ×C multiplier`.
  The server/client already compute both parts (`GetPassiveCashPerSecond`
  pieces; no second formula: add the split to the same function's breakdown,
  `GetIncomeBreakdown`).
- One-time announce `tipEarn` (once per account, after the tutorial, the
  first time the player owns ≥ 1 orb on a pedestal AND has bought a
  generator upgrade): `Generators AND orbs earn cash. Better orbs = more $/s!`

## 6. Selftest + docs

- Stubbed inventories: {3 Common, 2 Rare} → panel opens on RARE and the RARE
  tab pulses; {5 Common} → COMMON; {1 Rare} → COMMON; after a Common fuse
  that leaves 2 Rares → `FUSE RARES →` shows and switches the tab;
  `tipFusePath` fires once and never in the tutorial.
- The path strip lights the right tier and fits at 1920 x 1080 and 844 x 390;
  tab tap targets ≥ 44 px; the income tooltip shows the split and the two
  parts sum to the pill's number (±1%).
- Docs: `docs/systems/items-and-fusion.md` (the panel's default tab, pips,
  path strip, the post-fuse button) and `docs/systems/tutorial.md`
  (`tipFusePath`, `tipEarn`).
