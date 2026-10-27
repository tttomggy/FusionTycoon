# Tutorial 5: under a minute — claim, pull, fuse, play (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 5 lines, one per group: DONE or WHY-NOT, plus the measured time of a
straight run (group 5). Run the Luau parser over `src/` before pushing.

---

Harris: players join and leave during the tutorial. It's 11 steps with 7
explain cards, each with a 1.5 s locked OK, a 1.2 s "Nice!", 0.8 s of
settle and a 3 s minimum banner: several minutes of reading before the
player is free. Roblox's ranking punishes leaving in the first 60 s
(first-play bounce). Kids don't read cards. Show, don't tell.

## 1. The mandatory tutorial: 4 steps

`TutorialConfig.Steps` becomes:

| # | Id | What | Card |
|---|---|---|---|
| 1 | `claim` | Claim your lab (as now) | none |
| 2 | `pull` | `Pull 2 free orbs` with a live `0/2` in the banner; done after the 2nd free pull (merge `pull` + `pull2`) | **none** (the banner + "Your first 2 are free!" is enough) |
| 3 | `fuse` | `Fuse your 2 orbs` at the machine (as now) | keep the Fusing card (the orb diagram is the one card worth reading), but its OK is live at once |
| 4 | `finish` | `You're ready!` 2 s, the HUD finishes popping in | none |

- **Removed as steps:** `upgrade`, `pedestals`, `index`, `multiplier`,
  `events`, `rebirth`. Their teaching moves to group 3.
- **Pedestals without a step:** after the first pull lands on a pedestal,
  the existing cash popup over it plus one `TopStack.Announce`
  `Your orbs earn cash every second!` (2.5 s, non-blocking) while the
  player walks on.
- **Pacing** (`TutorialConfig`): `CardReadSeconds = 0`, `NiceSeconds = 0.6`,
  `SettleSeconds = 0.3`, `BannerMinSeconds = 1.5`. The fuse card's OK can
  also be done by tapping anywhere on the card.
- The 2 free pulls stay guaranteed Commons (so step 3 always works).

## 2. HUD reveal and saves

- `TutorialConfig.HudReveal`: `Items` at `pull`, `Upgrades` + `Index` at
  `fuse`, everything else (`Rebirth`, `Event`, `Settings`, `Shop`, `Goal`)
  at `finish`, keeping the one-by-one delays. Nothing may stay hidden after
  `finish` (HudGate's step lookup must not point at a removed id).
- `DataVersion = 4`. Map saves mid-tutorial: `claim` → `claim`; `upgrade`,
  `pull`, `pull2` → `pull` (if their free pulls are used up → `fuse`);
  `pedestals`, `fuse` → `fuse`; `index` and later → Done. Old Tutorial 1/2
  saves go through the existing MigrateStep then this map.
- Funnel analytics (`AnalyticsKit.FunnelSteps`) are milestones, not tutorial
  steps: leave them as they are (they keep measuring FirstUpgrade,
  FirstMultiplier etc. whenever they happen).

## 3. What the removed steps become: one-time contextual tips

Each fires ONCE per account (`TipConfig.Ids`, saved like the others), only
after the tutorial is Done, only when no card/overlay is open, as the
existing hand + one short TopStack line, never a card:

| Tip id | When | Hand on | Line |
|---|---|---|---|
| `tipUpgrade` | first time cash ≥ the cheapest generator upgrade | UPGRADES | `Upgrade generators to earn faster!` |
| `tipMultiplier` | first time cash ≥ Multiplier Pad level 1 | the Multiplier Pad (path arrows, as the old step) | `The Multiplier Pad multiplies ALL your money!` |
| `tipIndex` | first time a new Index entry is found after the tutorial | INDEX | `New orb! Each one boosts your income forever.` |
| `tipEvent` | the first event chip the player sees after the tutorial | the event chip | `Lab weather! Tap it to see the bonus.` (the existing `event_<Id>` pulse stays) |
| `tipRebirth` | first time rebirth progress ≥ 50% | REBIRTH | `Rebirth when the bar is full: keep your orbs, earn faster forever.` |

- At most one tip on screen; a second one waits until the first is gone
  plus 20 s. The NEXT GOAL tracker stays as it is.
- The "?" help slideshows keep the full explanations (unchanged).

## 4. Check the first 60 seconds

- From spawn, the player must be able to: claim → pull → pull → fuse with
  nothing else in the way. No daily card, offer, gift hand, opt-in or deal
  pop-up during the tutorial (verify each one's tutorial guard; the opt-in
  already waits 5 min).
- Path arrows and the contextual PULL / FUSE button as now.

## 5. Selftest + docs

- Selftest (`/selftest tutorial` alone): a fresh save runs the 4 steps with
  the real predicates (simulated actions), and reports the **total seconds
  from claim to Done** with all waits at their config values (target:
  under 45 s of tutorial time excluding walking; report the number). The
  migration map above, case by case. Each tip fires once and never during
  the tutorial.
- Update `docs/systems/tutorial.md` (the 4 steps, the tips table, pacing).
