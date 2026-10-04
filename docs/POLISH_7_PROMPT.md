# Fusion Tycoon — Polish 7: Index book, MAX upgrades, a smaller HUD (build prompt for Claude Code)

Paste into Claude Code on `world-redesign` (`git pull` first). Same open PR
#6. Don't merge.

---

Read CLAUDE.md and follow it: UITheme for every colour and font, UIKit for
screens, NumberFormat for money, server authority, one formula per number, and
`luau-lsp analyze`. Run the type check after each phase and commit each phase
on its own. The canvas board **"Polish 7 · Index book, MAX upgrades, smaller
HUD"** shows the design.

## What the playtest showed

1. **The LOCK status chip is far too wide.** "🔓 UNLOCKED" sits in a bar about
   340 px wide.
2. **The steal timer chip is clutter.** Enemy pedestals already say "Steal in
   42s".
3. **The event info card opens itself.** Harris has to close it with ✕ for
   every event (Studio never saves Tips, so it happens every session).
4. **The Index looks cheap.** It's a grid of check marks, clocks and "?"
   boxes, and a lot of the panel is empty.
5. **Upgrades are one level per tap.** Players want a button that buys as many
   levels as their cash allows.

## Phase 1 — HUD trim

- **LOCK chip:**
  - Size it to its text: `AutomaticSize = X`, 44 px tall, 14 px side padding,
    and a minimum width of 0.
  - The "?" button sits 8 px to its right.
  - Shorten the alarm text to "🚨 RUN TO LOCK!".
  - States and colours are unchanged.
- **Steal timer chip:** delete it from HudController, together with its
  STEAL READY flash. Keep `HeistCooldownUntil`, the prompt's "Steal in 42s"
  mode and the toast.
- **Event info card:**
  - Never auto-open it. Remove the `event_<Id>` auto-open.
  - Instead, the first time a player sees each event type, the HUD event chip
    gets a small gold "ⓘ TAP" tag beside it. It bounces gently until the
    player taps the chip once. That tap marks the tip `event_<Id>` as seen,
    with the same Tips ids.
  - The card still opens on every tap and still closes on ✕.
  - Also close it on a tap anywhere outside it.
  - It closes itself when the event ends.
- **Tidy up:** update UI_TEST §16 / §17, and remove the timer-chip cases.

## Phase 2 — The Index as a collection book

Rebuild `UI/IndexPanel`'s page content. Keep the data, the counts and the
income rules exactly as they are (`IndexConfig`).

**Header**
- "INDEX" (Display 30) and under it "18 / 119 found · every find +1% income ·
  a full page +5%".
- The green "+18% income" pill and ✕ on the right.

**Tier tabs:** one per tier, Common → Secret. Each tab shows:
- the tier name in its tier colour,
- "8 / 21",
- a thin progress bar in the tier colour,
- "+5% at 21" on the selected tab.

**Column header:** the seven variant names in their mutation colours.
Charged, Void and Celestial carry their event icons (⚡ 🌙 ☄). These headers
are no longer tap targets.

**One row card per item**
- The item name (Fredoka 17).
- Under the name: "3 / 7" and its base $/s.
- Then seven **orb cells**, 54 px:
  - **Found:** the real orb in that variant. Use `UIKit.TierOrb` with that
    mutation's look (the same colours and shell as the pedestal and
    MutationPill): Golden is gold, Charged cyan with a glow, Diamond pale
    faceted (a UIGradient sweep), Void deep purple, Rainbow a hue-cycling
    UIGradient (client-only, like `FT_Rainbow`), Celestial white-blue with a
    soft glow.
  - **Not found:** a dark circle with a dashed-look stroke in the Panel
    colour, holding a muted "?". Event-only variants show their event icon
    instead of "?".
  - **No check marks or clocks anywhere.**
- **Complete row (7/7):** a gold stroke and a soft gold glow (UIStroke plus a
  Shadow tint, no Highlight), and the sub-line "★ COMPLETE 7/7" in gold.

**Info strip at the bottom of the panel**
- Tapping any orb shows "<Item> · <Variant ×N>", then the how-to-get line (the
  text EventConfig / Events 2 already wrote for the column boxes), then "found"
  or "not found yet".
- This replaces the ⓘ header boxes.

**Size:** 720 wide on desktop. On a phone the rows scroll and the orbs shrink
to 40 px; the tap targets stay ≥ 44 px because the cell is the target, not the
orb.

**Performance:** build only the selected tier's rows. Rebuild on tab change and
on a SyncInventory that changes the Index.

## Phase 3 — MAX upgrades

**Server**
- New remote `RequestUpgradeMax` (C→S `{ GeneratorId: string }`, or
  `{ All = true }`). Add it to RemoteEvents with a direction comment.
- In TycoonService, loop "buy one level" through the **same** code path as
  `onRequestUpgrade`: same cost function (`TycoonConfig.GetUpgradeCost`), same
  unlock rules, same max level, same Carrying refusal. Stop when cash < the
  next cost, the level is maxed, or after 500 iterations.
- `All` buys the **cheapest available level across every unlocked
  generator**, one at a time, and re-checks unlocks each step. A newly unlocked
  generator joins the loop.
- **One** SyncTycoon at the end, plus one result event:
  `UpgradeMaxResult { Levels, Spent, PerGenerator = { [id] = levels } }`.
  Nothing is spent if zero levels are bought.

**Client: UpgradesPanel rows**
- Next to the existing +1 button, add a gold **MAX ×N** button with the total
  under it ("$104M").
  - N and the total come from a shared pure function
    `TycoonConfig.GetMaxAffordable(generator, level, cash)`, so the label and
    the server agree.
  - Muted "MAX / need $321M" when not even one level is affordable.
  - Hidden when maxed: the row shows the existing MAXED.
- **⚡ MAX ALL · $X** at the bottom of the generators list, built with
  `TycoonConfig.GetMaxAllPlan(levels, cash)`, which the server also uses.
- **After a MAX:** the existing upgrade toast becomes "+9 levels · Core Engine
  LV 15", or for MAX ALL "+23 levels across 3 generators". The world bump plays
  once per generator that changed.
- Labels refresh with cash, at most ~4×/s.
- **Economy:** nothing changes (same prices, same caps), so the sim doesn't
  need a re-run. Say so in the summary.

## Phase 4 — Docs and checks

- **CLAUDE.md:**
  - the LOCK chip sizing,
  - no steal chip,
  - the event chip's "ⓘ TAP" and no auto-open,
  - the Index book,
  - `RequestUpgradeMax` with `GetMaxAffordable` / `GetMaxAllPlan`.
- **UI_TEST:** add a case for each of these:
  - the chip fits its text
  - there's no steal chip
  - an event doesn't pop the card, and the TAP tag disappears after one tap
  - Index orbs found and not found, the event icons, a complete row, the info
    strip, and the phone scroll
  - MAX ×N buys exactly N levels and spends exactly the shown total
  - MAX ALL
  - the "need $X" state
  - MAX while carrying is refused
- `luau-lsp analyze`: no new errors. Commit per phase, push, and add a section
  to PR #6.
