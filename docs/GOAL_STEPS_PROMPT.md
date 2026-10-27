# Goal steps: "Own a Legendary" tells you what to do next (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.**
**Line 2: did you run `/selftest` in Studio yourself (Studio MCP)? If yes,
the FAIL count of your last run; if not, write "untested in Studio" (and in
the commit message).** Then one line per group: DONE or WHY-NOT. Run the
Luau parser, `tools/theme_token_check.py` and `luau-lsp analyze` (if it
runs) before pushing.

---

Harris, live build: the NEXT GOAL tracker says `Own a Legendary`, `1 / 2
Epic`, and the arrow points at the Fusion Machine. With 1 Epic there is
nothing to fuse there. A kid doesn't know they need a 2nd Epic first (pull
more, or fuse Rares into Epics), or that putting 3-6 orbs in raises the
odds (Epic: 2 = 35%, 3 = 45% ... 6 = 66%). They walk to the machine, can't
do anything, and quit.

## 1. Tier goals show the NEXT ACTION, live

Applies to every "own a tier" goal: `own_rare`, `own_epic`,
`own_legendary`, `own_mythic` (`GoalConfig`; add a field like
`Kind = "OwnTier", Tier = "Legendary"` instead of matching ids).

The server computes the next action in `GoalService` (it already publishes
`GoalProgress`) from the player's inventory, using the same rules
`FusionService` uses (`CanFuseTierFor`, stacks, the fuse max of 6):

| Situation (goal tier G, input tier I = the one below G) | Tracker 2nd line | Arrow |
|---|---|---|
| ≥ 2 orbs of I | `Fuse your N Epics: 45%` (N = min(owned, 6), chance from `FusionConfig.GetChance` for N, with the player's luck/events if that's how the Fuse panel shows it) | Fusion Machine |
| ≥ 2 and < 6 of I, and chance < 100% | also a 3rd small line: `More Epics = better odds (6 → 66%)` | — |
| < 2 of I, but ≥ 2 of a lower tier | `Fuse Rares to make Epics (1 / 2 Epic)` (the highest lower tier with ≥ 2) | Fusion Machine |
| < 2 of I, nothing to fuse | `Pull from the Gacha for more orbs (1 / 2 Epic)` | Gacha Pad |
| can't afford a pull and nothing to fuse | `Earn cash for your next pull ($X)` | UPGRADES (hand) or nothing |

- Text sizes, colours and fonts from `UITheme` / `UIKit` as the tracker
  uses now; tier names and colours from the rarity config, never typed;
  money through `NumberFormat.Money`.
- The arrow (goal marker `Target`) follows the action: the goal can return
  a target per state. Re-evaluated on every SyncTycoon (the OnSync hook
  already runs), so it switches the moment a pull lands or a fuse ends.
- Rename the goal texts to say the verb: `Fuse Epics into a Legendary`,
  `Fuse Legendaries into a Mythic` (`own_rare` → `Fuse Commons into a
  Rare`). Rewards unchanged.

## 2. The Fuse panel says it too

When the Fuse panel opens with a chamber of 2-5 same-tier orbs and more of
that tier are in the inventory, one muted line under the odds:
`Add more Epics for better odds: 3 → 45%, 6 → 66%`. AUTO-FILL already
fills up to the max; don't change its behaviour. Gone at 6 or when no more
of that tier are owned. (Keep the mutation tip from PASSES_TRAY working;
if both apply, the odds line wins.)

## 3. Selftest + docs

- `/selftest` (server, stubbed inventories): goal own_legendary with
  {1 Epic, 0 Rare} → Gacha line + GachaStation target; {1 Epic, 3 Rare} →
  "Fuse Rares" + FusionMachine; {3 Epic} → "Fuse your 3 Epics: 45%" + the
  odds line + FusionMachine; {6 Epic} → no odds line; {0 cash, 1 Epic} →
  the earn-cash line. Same for own_rare / own_epic / own_mythic (one case
  each). Client: the tracker renders all 3 lines without clipping at
  1920 x 1080 and 844 x 390, tap targets unchanged.
- Fuse panel: chamber of 2 Epics with 4 more owned → the odds line; 6 in →
  none.
- Docs: `docs/systems/items-and-fusion.md` (goal steps, the Fuse panel
  line) and the GoalConfig header.
