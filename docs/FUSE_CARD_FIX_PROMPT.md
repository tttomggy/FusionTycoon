# Fuse card diagram is scrambled: "+ → ⚪ ⚪ 🔵" instead of "⚪ + ⚪ → 🔵" (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`
(or `triage18-check` if you can't run `tools/compile_check.py`, as before).
**Line 1: the branch. Line 2: "untested in Studio" (also in the commit
message).** Then one line per group: FIXED or WHY-NOT. Run
`tools/theme_token_check.py` and `luau-lsp analyze` before pushing.

---

Harris (screenshot of the tutorial's `Fusing` card): the diagram reads
`+ →` and then three orbs, `⚪ ⚪ 🔵`. It must read
`⚪ + ⚪ → 🔵` (orb plus orb gives a Rare orb). `TutorialConfig` has the right
data: `Orbs = { "Common", "+", "Common", "→", "Rare" }`.

## 1. Cause and fix

`TutorialExplain.buildImage` builds the row with a `UIListLayout` and sets
`LayoutOrder = index` on every orb and symbol, but never sets
`layout.SortOrder = Enum.SortOrder.LayoutOrder`. The default sorts by
**Name**, so the two `Symbol` labels (name "Symbol") sort before the orbs
(their names start later), exactly what the screenshot shows.

- Set `layout.SortOrder = Enum.SortOrder.LayoutOrder` there.
- Grep every other `Instance.new("UIListLayout")` / `UIKit` list layout in
  `src/` that sets `LayoutOrder` on its children but not `SortOrder`; fix
  each the same way (add a `UIKit` helper if there's an obvious spot) and
  list the ones you changed in your reply.

## 2. Make the card say it at a glance

Under the diagram, replace the sentence with two short lines (big, kid-readable):

- `2 orbs + 2 orbs of the same tier...` is too wordy. Use:
  `Fuse 2 same orbs → 1 better orb!` and, smaller, `More orbs in = better odds.`
- Keep the diagram: `⚪ + ⚪ → 🔵`. The orbs use the tier colours (Common is
  the grey one, Rare the blue one, from `UITheme.TierOrb`).

## 3. Selftest

For the tutorial fuse card (and any card with `Orbs`): the row's children,
sorted by `AbsolutePosition.X`, equal the order of `card.Orbs` (orb, symbol,
orb, symbol, orb). Both layouts (1920 x 1080, 844 x 390).
