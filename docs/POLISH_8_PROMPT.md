# Fusion Tycoon — Polish 8: pop-up settings, fuse chips that fit, no surprise mutation loss (build prompt for Claude Code)

Paste into Claude Code on `world-redesign` after POLISH_7 (`git pull` first).
Same open PR #6. Don't merge.

---

Read CLAUDE.md and follow it: UITheme, UIKit, server authority, saved data
through PlayerDataService, and `luau-lsp analyze`. Commit each phase on its
own. The canvas board **"Polish 8 · pop-up settings, fuse chips, mixed
mutations"** shows the design.

## Phase 1 — Settings: choose your big reveal cards

**Saved data**
- `PlayerData.Settings = { RevealRule = { Common = "Never", Rare = "Diamond", Epic = "Always", Legendary = "Always", Mythic = "Always" } }`.
- Values are `"Never" | "Golden" | "Diamond" | "Rainbow" | "Always"`, where
  "Golden" means Golden **or any mutation ranked above it**
  (`MutationConfig.GetRank`).
- **Defaults reproduce today's `FusionConfig.IsMajorReveal`**
  (`MajorRevealTiers` / `MajorRevealMutationRank`). Derive them from those
  values, don't hard-code. If today's rule shows a tier's card always, that
  tier's default is `Always`; otherwise use the mutation threshold.
- Migrate old saves with no Settings to the defaults.
- New remote `SetSetting` (C→S `{ Key = "RevealRule", Tier, Value }`). The
  server whitelists the tier and the value, saves, and syncs `Settings` in the
  snapshot.

**The rule**
- `ResultController.ShowsBigCardFor(tier, mutation)` reads the player's
  `RevealRule`.
- **Secret and event-only mutations (Charged / Void / Celestial) always show**
  their card. Players can't turn those off.
- This applies to single pulls, the Pull ×10 "BEST OF 10" card, and fusion
  successes.
- Fusion **fail** cards and the Fuse All summary are unchanged.
- **When a card is skipped:**
  - Show a small line above the bottom bar for 2.5 s: an orb dot, "+ Plasma
    Orb", the tier, and "+$94.5/s". Golden etc. go in their mutation colour.
  - Stack at most 3; older lines fade.
  - The item goes to the inventory as now. Sounds still play (RevealMinor).

**UI**
- A new **⚙** square button (56 px) at the right end of the bottom bar,
  after INDEX.
- It opens `UI/SettingsPanel` (UIKit Modal, about 620 wide; on a phone it
  scrolls).
- **Section "Big reveal card":**
  - The line "Pick when a pull or fusion gets the big card. Everything else
    just pops a small line."
  - One row per tier, Common → Mythic: the tier name in its colour plus a
    5-option segmented control: Never / Golden+ / Diamond+ / Rainbow+ /
    Always.
  - A locked Secret row: "🔒 Always shows. So do ⚡ Charged, 🌙 Void and ☄
    Celestial."
- Changes apply immediately (optimistic), then save.
- Leave room in SettingsPanel for future sections (music / sound volume
  later); don't build those now.

## Phase 2 — Fuse panel chips fit in one row

- The five count chips (2–6 orbs) sit in **one row** at equal widths: a
  UIGridLayout or UIListLayout with scale widths, 6 px gaps. There is never a
  second row.
- The top line is "6 orbs" (11 px); the % below uses TextScaled with a
  `UITextSizeConstraint` max of 18. "100%" must fit at the narrowest phone
  width.
- Keep the current-count highlight and the Void Moon tint.

## Phase 3 — Mixed mutations: say it before you fuse

The rule stays as it is: a success keeps the **lowest** mutation of the
inputs, then may roll a better one. Harris fused 4 Golden Rares with 1 plain
Rare and couldn't tell what would happen. With one plain orb the Epic comes out
**plain**, unless it rolls a fresh mutation. The panel must say this **before**
FUSE.

- **Prediction line** under the "5 Rare → EPIC" line (pure function
  `FusionConfig.PredictMutation(inputs)` = the lowest input mutation):
  - Every input the same mutation: "✨ Keeps GOLDEN ×2, might roll better", in
    the mutation colour.
  - Mixed: a red warning box: "⚠ 1 plain orb mixed in: the Epic comes out
    plain, not Golden. Use only Golden orbs to keep Golden." Name the count
    and the mutation that will be lost.
  - Every input plain: no line.
- The orb(s) dragging the mutation down get a red ring in the chamber.
- **AUTO-FILL** only adds orbs with the **same mutation as the first orb in
  the chamber**. With an empty chamber it fills plain orbs first, as now.
- **On fail,** the card says which orb was kept, including its mutation
  ("Kept your Golden Rare").
- **Success card** (normal fusion result and the big card):
  - Always show the MutationPill when the result has a mutation.
  - Add a line: "GOLDEN kept" when the mutation carried over from the inputs,
    or "GOLDEN rolled!" when it's newly rolled.
  - The server already knows which happened, so send `MutationSource =
    "Kept" | "Rolled"` in the fusion result.

## Phase 4 — Docs and checks

- **CLAUDE.md:**
  - Settings and RevealRule (defaults derived from IsMajorReveal, Secret and
    event-only always shown),
  - `SetSetting`,
  - SettingsPanel and ⚙,
  - the skipped-card line,
  - the fuse chip row,
  - `PredictMutation` and the mixed warning,
  - AUTO-FILL by mutation,
  - `MutationSource`.
- **UI_TEST:** add a case for each of these:
  - every RevealRule option for a pull and a fusion
  - Secret and `/eventmut` always show
  - the skipped line
  - "100%" visible at phone size
  - 4 Golden + 1 plain shows the warning and the result is plain
    (`/give rare_item golden` ×4)
  - 5 Golden shows "Keeps GOLDEN"
  - AUTO-FILL keeps the mutation
  - the success card shows the pill and "kept" / "rolled"
- `luau-lsp analyze`: no new errors. Commit per phase, push, and add a section
  to PR #6.
