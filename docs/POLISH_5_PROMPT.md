# Fusion Tycoon — Polish 5: Fuse panel, cash rebirth, mutation marks, pad price (build prompt for Claude Code)

Paste everything below into Claude Code, opened on the `world-redesign` branch.

---

Playtest feedback on Polish 4 + Depth 1, and the fixes. The design is fixed.
The canvas board **"Polish 5 · fuse panel, mutation marks, pad price"** shows
it, and every number is in this file.

Read `CLAUDE.md` first and follow it: config tables for numbers, UITheme for
every colour and font, UIKit for screens, `SyncTycoon`, RemoteEvents, server
authority, and `luau-lsp analyze`. After each phase, run the type check, fix
every new error in files you touched, and commit the phase on its own.

## What the playtest showed

- **The Multiplier Pad hides its price.** It's only in the tiny detail line.
  Harris got stuck at LV 14/15 holding $1.28T against a $1.5T price, with no
  feedback: the server silently returns when you can't afford it.
- **Rebirth by "run earnings" doesn't read for kids.** Harris had $1.28T but
  the portal wasn't ready, because `/cash` and goal money don't count. Players
  understand "Rebirth costs $15M". They don't understand an invisible earnings
  counter.
- **Golden on a Legendary is invisible.** A gold shell on a gold orb and a gold
  "×2" pill on a gold card. Rare Golden items read fine; same-colour tiers
  don't.
- **Fusing is a blind "Fuse 2x Common" prompt.** Harris wants a fuse screen
  where you choose how many orbs go in: more orbs, better odds, up to 6.

---

## Phase 1 — Multiplier Pad shows its price

- **Pad label** (`createMultiplierStation`), per the board:
  - Title `MULTIPLIER`.
  - Violet pill `x4.5 → x5 · LV 14/15`.
  - A **second pill** in the Gold gradient with the price, `$1.5T`, the same
    style as the Gacha's `$483 / pull` pill. BillboardKit may need a
    second-pill option.
  - A caption under it: `Need $220B more` (MythicBannerLabel colour) when you
    can't afford it, nothing when you can.
  - At max: one pill, `x5 MAX`, and no price pill.
- **Prompt:** ActionText `Upgrade`, ObjectText = the price (`$1.5T`).
- **Can't afford:** fire `MultiplierUpgraded` with
  `{ Success = false, Reason = "InsufficientCash", Cost = cost }` instead of
  returning silently. The client shows the red toast `Need $1.5T`, the same
  toast the generators use.
- **Upkeep:**
  - The caption needs the owner's live cash, so refresh it on the payout tick
    (text only).
  - Check every other station prompt for the same silent `return` on "can't
    afford" and give each the same toast.

## Phase 2 — Rebirth costs cash

Replace the RunEarnings requirement with a cash price.

- **`RebirthConfig`:**
  - `BaseCost = 15_000_000`.
  - `CostGrowth = 3.2`.
  - `GetCost(rebirths) = floor(BaseCost * CostGrowth ^ rebirths)`.
  - Remove `GetRequirement`, or rename it to this.
  - Prices: R1 $15M, R2 $48M, R3 $154M, R4 $492M, …
- **`RebirthService`:**
  - Ready = `Cash >= GetCost(Rebirths)`.
  - Apply stays atomic. Cash goes to 0 as before, which pays the price.
- **RunEarnings:** delete the field and every use, and drop it from the
  snapshot. Old saves that still have it just ignore it.
  - `/rebirthready` now sets cash to the cost.
  - `/cash` works for testing rebirth naturally.
- **Portal label:**
  - Pill `REBIRTH · $15M`.
  - The bar shows cash / cost.
  - The caption: `$9.2M / $15M`.
  - When ready, the pill reads `READY · x1 → x1.5`. The Ready attribute,
    swirl and light are unchanged.
- **Rebirth panel:**
  - The progress caption becomes `You have $9.2M of $15M`.
  - The button says `Need $5.8M more` / `REBIRTH · $15M`.
  - The YOU RESET line starts with `Cash (pays the $15M)`.
- **Make it hard to miss.** While `Cash >= cost`, show a pulsing **orange
  `REBIRTH!` button** centred above the UPGRADES / ITEMS / INDEX row
  (Gradients.Orange, ≥ 44 px tall). It opens the Rebirth panel. Hide it when
  not ready.
- **Goal marker:** it already points at the portal for `first_rebirth`. Keep it.
- **`tools/econ_sim.py`** already models this: the player stops spending
  10 min of income before the price, then rebirths. Mirror its numbers.

## Phase 3 — The Fuse panel (2–6 orbs, chance by count)

**New rule.** Put 2 to 6 items of one tier in.
- **Success:** 1 random item of the next tier.
- **Fail:** you keep your best input (highest mutation rank; on a tie, the
  first) and lose the rest.
- **More inputs = higher chance.**

**`FusionConfig.SuccessChanceByCount`.** It replaces `SuccessChance`; grep
every use, including the client's prompt text and the odds formatter.

| Tier → next | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|
| Common → Rare | 55% | 68% | 78% | 90% | 100% |
| Rare → Epic | 45% | 57% | 66% | 74% | 80% |
| Epic → Legendary | 35% | 45% | 53% | 60% | 66% |
| Legendary → Mythic | 20% | 27% | 33% | 39% | 45% |
| Mythic → Secret (Rebirth 1+) | 7% | 9% | 11% | 13% | 15% |

- `FusionConfig.MinFusionInputs = 2`, `MaxFusionInputs = 6`, and
  `GetFusionChance(tier, count)`.

**Mutations with N inputs**
- **Success:**
  1. `base` = the lowest mutation rank among **all** inputs, so every input
     must share a mutation for it to carry.
  2. Then the usual fusion roll.
  3. The result takes the higher of the two.
- **Fail:** keep the best input, as above.

**Server** (`FusionService`)
- `RequestFusion` now takes one table: `{ Uids = { string } }`.
- Validate:
  - 2–6 unique Uids, every one owned and not InUse
  - all the same tier
  - the tier can be fused, with the Rebirth gate for Mythic
  - the cooldown
- Roll before mutating, so no yields in between.
- The result payload adds `Count` and `Chance`; on a fail it adds `KeptUid` and
  `LostCount`.
- **Fuse All** stays: pairs (count 2) of normal items, Common–Epic, using the
  count-2 chance.

**Client: new `UI/FusePanel.lua`** (UIKit), per the board, about 760 × 470.
- **Opening it:** the Fusion Machine's prompt becomes ActionText `Fuse`,
  ObjectText `Fusion Machine`, and opens the panel through
  `ProximityPromptService` (owner-only, as now). The old
  "Fuse 2x <tier>" / "Fuse All (n)" prompts go away; Fuse All moves into the
  panel.
- **Left: the chamber.**
  - 6 slots in a hexagon round a dim silhouette of the next tier's orb.
  - Under it, the **chance** in big Display text, coloured Cash ≥ 75%,
    Gold 40–74%, Danger < 40%.
  - `4 Common → RARE` in the next tier's colour.
  - A row of count chips (2 · 55%, 3 · 68% …), with the current count
    highlighted.
  - `Fail: keep your best orb, lose the rest` in Faint.
  - **When any selected item is mutated**, one more line:
    - all inputs share the mutation → `All Golden → result stays Golden`
    - otherwise → `Mixed mutations → result is normal (can still roll one)`
- **Right: the item picker.**
  - Tier tabs with counts of fusable items (not InUse). Mythic shows a lock
    before Rebirth 1, and Secret has no tab.
  - A scrolling grid of that tier's items. Normal items come first; mutated
    items are marked (Phase 4) and sorted last.
  - Tap to add or remove. Selected cards dim and show a ✓.
  - Switching tab clears the chamber.
- **Buttons:**
  - `AUTO-FILL` (Blue): fills up to 6 with normal items, never mutated ones.
  - `CLEAR`.
  - A big `FUSE` (Violet), disabled under 2.
  - `FUSE ALL` (small, "pairs · skips mutated"), which runs the existing Fuse
    All flow and its summary card.
- **After FUSE:**
  - Tween the slot orbs into the centre (0.35 s, client-only).
  - Then the existing ResultController reveal. The fail card reads
    `So close… kept <name>, lost <n>`.
  - The panel stays open on the same tab, chamber cleared, so you can go again.
- **Fit and feel:** fits 844 × 390 after the 0.8 UIScale (stack the columns
  or shrink the slots; react to `LayoutChanged`). Tap targets ≥ 44 px.
- **Machine odds board:** becomes the table above (tiers down, counts across),
  plus the fusion mutation line. Use `FusionConfig.FormatOdds`, or a sibling
  formatter, so the board and the rolls can't disagree.
- **Goals:** `first_fusion` still completes on any fusion. Rename any goal text
  that says "Fuse 2 …" to "Fuse at your Fusion Machine".

## Phase 4 — Mutation marks that read on every tier

**UI cards** (inventory, picker, Fuse panel, result cards, Index cells)
- The mutation pill becomes an **Ink-filled pill** with a 2 px outline and text
  in the mutation colour, and it says the word: `GOLDEN ×2`, `DIAMOND ×5`,
  `RAINBOW ×12`. Rainbow is white text under the rainbow UIGradient, with a
  gradient outline.
- The card gets a 3 px UIStroke in the mutation colour. Rainbow gets a
  UIGradient on the stroke, slowly rotated client-side.
- `UIKit.TierOrb` gains a `mutation` option: a ring round the orb made of a
  2 px Ink gap and then a 3 px ring in the mutation colour. The Ink gap is what
  keeps gold-on-gold readable.

**World pedestals**
- Keep the glass shell. **Add orbiting satellites:**
  - Neon balls 0.35 studs across, CanCollide/CanQuery/CanTouch false.
  - Orbit radius = orb radius + 0.7, tilted 20°.

  | Mutation | Satellites | Period | Trail | Colour |
  |---|---|---|---|---|
  | Golden | 2 | 2.4 s | none | Golden |
  | Diamond | 4 | 1.8 s | yes, Lifetime 0.25 | Diamond |
  | Rainbow | 6 | 1.5 s | yes | one RainbowStops hue each |

- The server builds them in the OrbGroup; tag the group `FT_Orbit` with
  attributes `Count`, `Radius`, `Period`. `WorldAnimationController` moves them
  with one `BulkMoveTo` per frame, client-only like `FT_Hover`. Skip plots
  > 120 studs from the camera, as the factory balls do.
- **Pedestal label:** add the same Ink chip (`GOLDEN ×2`) above the item name,
  so the label reads on any tier.

## Phase 5 — Sim, docs, checks

- Run `python3 tools/econ_sim.py 30 12 --fuse=2` and `--fuse=3`, and paste both.
  The tunables (fusion chance table, rebirth cost and saving) are already in the
  repo; check them against your Lua line by line. Expected medians:

  | Milestone | `--fuse=2` | `--fuse=3` |
  |---|---|---|
  | First pull | ~1:10 | ~1:10 |
  | First Legendary | ~6 min | ~13 min |
  | First Mythic | ~1:05 | ~2:10 |
  | Rebirth 1 | ~1:04 | ~1:10 |
  | Rebirth 2 | ~1:46 | ~2:13 |
  | Rebirth 3 | ~2:46 | ~3:15 |
  | Singularity Core | ~2:37 | ~3:05 |
  | First Secret | ~8:30 (huge spread) | not in 12 h |
  | Index after 12 h | ~38/68 | ~34/68 |

  If yours differ by more than 20%, stop and say so.
- Update TycoonConfig's milestone header.
- **CLAUDE.md:**
  - The game loop's fusion line becomes "fuse 2–6 same-tier items in the Fuse
    panel (more = better chance; success = next tier, fail = keep your best
    input)".
  - Rebirth "costs cash (`RebirthConfig.GetCost`)".
  - Add FusePanel to UI.
  - Add the `FT_Orbit` tag.
- **`docs/UI_TEST.md` §14 "Polish 5":**
  - The pad shows its price, and the "need" caption updates as cash grows.
  - A failed pad buy toasts "Need $X".
  - `/cash 2e7` makes the portal READY and shows the REBIRTH! button.
  - Rebirthing takes the cash.
  - The Fuse panel: 4 Commons show 78%; 6 Commons always succeed.
  - A fail keeps the best (mutated) input.
  - All-Golden inputs give a Golden result; mixed inputs give normal or a fresh
    roll.
  - AUTO-FILL never takes mutated items.
  - The Mythic tab is locked before Rebirth 1.
  - `/give legendary_core Golden`: the card shows `GOLDEN ×2` with a gold ring
    and outline, and the pedestal has 2 orbiting satellites plus the chip.
  - Diamond shows 4 with trails, Rainbow 6.
  - Phone layout of the Fuse panel.
- `luau-lsp analyze`: no new errors. PlotLayout assertions pass.
- Commit per phase, push `world-redesign`, and comment a summary on PR #4.
