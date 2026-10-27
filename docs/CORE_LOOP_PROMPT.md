# Core loop: always show the next step of Pull → Fuse → Earn → Upgrade (+ Steal) (build prompt for Claude Code)

**Do `docs/GOAL_STEPS_PROMPT.md` first** (this builds on its next-action
line). Run `git pull` on `world-redesign`, then commit and push to
`world-redesign`. **If your session forces another branch, say so in the
FIRST line.** **Line 2: did you run `/selftest` in Studio yourself (Studio
MCP)? If yes, the FAIL count of your last run; if not, write "untested in
Studio" (and in the commit message).** Then one line per group: DONE or
WHY-NOT. Run the Luau parser, `tools/theme_token_check.py` and `luau-lsp
analyze` (if it runs) before pushing.

---

Harris: players don't get the core loop. **Pull** orbs at the Gacha Pad →
**Fuse** them into better orbs → better orbs on the pedestals **Earn** more
cash → **Upgrade** generators / Multiplier for more cash → pull more. And
**Steal** from other labs for free orbs. Kids don't read: show it with
icons and always point at the one thing to do now.

## 1. One "do this now" coach (server, shared with GOAL_STEPS)

Extend GOAL_STEPS' next-action logic into a `LoopCoach` module (shared
rules in `Shared/Config`, computed server-side in GoalService on every
SyncTycoon, published with `GoalProgress`). It returns `{ Step, Line,
Target }`, Step ∈ `Pull | Fuse | Earn | Upgrade | Steal`. Priority:

1. **Fuse** if any tier the player may fuse has ≥ 2 orbs (`CanFuseTierFor`)
   → `Fuse your 3 Rares: 57%` → Fusion Machine.
2. **Pull** if cash ≥ the next pull price → `Pull from the Gacha ($X)` →
   Gacha Pad.
3. **Upgrade** if cash ≥ the cheapest generator / Multiplier upgrade →
   `Upgrade your Ember Forge: +$X/s` → that station (or the UPGRADES hand).
4. **Steal** if a rival lab with an orb exists and the player is under
   `StealsPerHour` → `Steal a free orb from Dr. Fizz!` → that rival's best
   pedestal.
5. **Earn** otherwise → `Your orbs earn $X/s: next pull in 0:42` (seconds
   from the current income and the gap to the next pull price) → nothing.

- The goal tracker keeps the goal as its title; its 2nd line and the arrow
  come from the coach when the goal's own step isn't doable right now
  (GOAL_STEPS' rules stay for tier goals, they're the Fuse/Pull rows of this
  table). One arrow on screen, ever.
- Never during the tutorial; tips (`tipRival` etc.) take the arrow while
  they run, then the coach gets it back.
- Hysteresis: the step changes at most once per 3 s (cash ticking past a
  price mustn't make the arrow flicker between Pull and Upgrade).

## 2. The loop strip (HUD, icons only)

A small row in the goal tracker, above the goal text: `🎰 → 🔮 → 💰 → ⬆`
with a separate `🏃` after a gap (Steal is a side road). The coach's current
Step is lit (the `UIKit.SetSelectedFill` selected look, a light pulse);
the others muted. Tap an icon = a one-line TopStack.Announce of what it is
(`Fuse 2+ same orbs into a better one`). Tap targets ≥ 44 px, fits the
tracker at 844 x 390 without making it taller than now + 20 px, colours
from UITheme. Shown after the tutorial only.

## 3. Close the loop at the moments it happens

One TopStack.Announce each (2.5 s, existing queue), once per session per
kind, never during the tutorial:
- after a fuse succeeds and the new orb goes on a pedestal:
  `Your new orb earns $X/s more!`
- the first time a pull is affordable again after a fuse:
  `More cash = more pulls = more fusions!`
- after the first rival steal is delivered: `Free orb! Fuse it with yours.`

## 4. Selftest + docs

- Server (stubbed state): each coach step from its situation, the priority
  order (fuse beats pull beats upgrade beats steal beats earn), no step
  change within 3 s, nothing during the tutorial, a tip owns the arrow
  while up.
- Client: the strip fits and lights the right icon at 1920 x 1080 and
  844 x 390, no overlap with the left-column stack (the existing check),
  taps ≥ 44 px.
- Docs: `docs/systems/quests.md` or wherever goals live (the coach),
  `docs/systems/tutorial.md` (after-tutorial guidance), architecture.md if a
  remote payload changes.
