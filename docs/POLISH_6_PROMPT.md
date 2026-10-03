# Fusion Tycoon — Polish 6: playtest fixes + offline earnings (build prompt for Claude Code)

Paste everything below into Claude Code, opened on the `world-redesign` branch.

---

The Polish 5 playtest was mostly clean. Fuse panel, Golden fusion, mutation
marks, satellites, cash rebirth and the pad price all worked. This pass fixes
the five rough edges it showed and adds offline earnings, the reason to come
back tomorrow.

Read `CLAUDE.md` first and follow it: config tables for numbers, UITheme for
every colour and font, UIKit for screens, `SyncTycoon`, RemoteEvents, server
authority, and `luau-lsp analyze`. After each phase, run the type check, fix
every new error in files you touched, and commit the phase on its own.

## Phase 1 — Lab lighting washes out pink

With a Mythic or a Rainbow item on a pedestal, the whole lab floor goes
blown-out pink-white. The cause is the pedestal lights in `RarityVisuals`:
Mythic and Secret are Brightness 12 with Range 32, and Legendary is 8 / 22.
Four of them flood the plot. Tone them down so the floor keeps its colour and
the orbs themselves carry the glow.

| Tier | LightBrightness | LightRange |
|---|---|---|
| Common | 0.8 | 8 |
| Rare | 1.0 | 9 |
| Epic | 1.2 | 10 |
| Legendary | 1.4 | 11 |
| Mythic | 1.6 | 12 |
| Secret | 1.6 | 12 |

- `PlotLayout.Pedestal.OrbLightBrightness`: 2 → **1**.
- Every pedestal, orb and satellite light has `Shadows = false`.
- **Check:** `/give mythic_rift Rainbow` on all four pedestals. The walkway
  between them must still read as the Floor colour, not white. Add it to
  UI_TEST.

## Phase 2 — Fuse panel fit and legibility

On a 1080p screen the panel reads tiny, and the tier tabs overflow: Legendary
and Mythic sit off the right edge.

- **Desktop size: 860 × 520.** Phone stays fitted to 844 × 390 after the
  UIScale.
- **Tabs:** all five tier tabs fit in one row with no scrolling. Use equal
  widths, the tier name on top and the count under it in smaller text. The
  Mythic lock shows as an icon in the tab.
- **Chamber:**
  - Slots ≥ 64 px.
  - Next-tier silhouette ≥ 96 px.
  - Chance number Display 48.
  - "2 Common → RARE" at ≥ 18.
  - Count chips ≥ 14 px text with ≥ 28 px chip height.
  - The fail line ≥ 13.
- **Picker cards ≥ 84 × 96**, name ≥ 12. The mutation pill stays legible.
- Nothing in the panel under 12 px text.

## Phase 3 — HUD collisions and prompt check

- **Toasts sit on the REBIRTH! button.** The "+$15/s" upgrade toasts stack
  right on top of it. ToastController's bottom offset must clear the REBIRTH!
  button's slot **whether or not it's showing**, so toasts don't jump when it
  appears. Check the generator upgrade toasts, the Index toasts and the "Need
  $X" toasts.
- **Pull ×10 prompt.** In one clip only the E "Pull" prompt showed on the Gacha
  Pad. Check what hides the R "Pull ×10" prompt: the result card, a debounce,
  Exclusivity, or the prompt's `Enabled`. It should show whenever the single
  pull does. If affordability hides it, show it anyway and toast "Need $X",
  like everything else.

## Phase 4 — Offline earnings

**Rule:** while you're away you earn **25% of your passive income per
second**, for at most **4 hours** of away time. The away time counts only when
it's at least 2 minutes.

**`Shared/Config/OfflineConfig.lua`** (new):
- `Rate = 0.25`
- `MaxSeconds = 4 * 3600`
- `MinSeconds = 120`
- `Compute(incomePerSecond, awaySeconds)` returns the amount, or 0 below the
  minimum.

**Data**
- `PlayerData.LastOnline: number` (`os.time()`), written every autosave and on
  PlayerRemoving. Missing on old saves means no offline payout the first time.

**Server**
- On load, if `LastOnline` exists:
  - `away = os.time() - LastOnline`.
  - Compute with `GetPassiveCashPerSecond(GetIncomeInputs(player))` as it is at
    load. That's the income they left with.
  - Store the result as `PendingOffline` in session state (not saved).
  - Set `LastOnline = os.time()` straight away, so rejoining can't claim twice.
- The snapshot carries `PendingOffline`, and `AwaySeconds` for the card.
- New remote `ClaimOffline` (client → server): pays `PendingOffline` once with
  `AddCash`, zeroes it, and syncs. It's validated server-side and the client
  never sends an amount.
- If the player never presses Collect (closes the card, leaves), pay it
  automatically on the first payout tick after 30 s. They should never lose it.

**Client: welcome-back card**
- A ResultController modal shown once after the first sync with
  `PendingOffline > 0`:
  - Title "WELCOME BACK!"
  - Caption "You were away 3h 12m" (cap the text at "4h+").
  - The amount in big Cash Display text: "+$1.24M".
  - A small line: "Your lab earned 25% while you were gone".
  - A green **COLLECT** button.
- Leave room for a second button, "COLLECT ×2", which the monetization pass
  will hook to a Developer Product. **Don't build it now**, only the layout slot
  (hidden).
- Coin-burst VFX on collect, reusing the existing cash/coin effect if there is
  one.

**Debug:** `/offline <minutes>` (Studio only) sets `PendingOffline` as if you'd
been away that long and re-sends the snapshot, so the card can be tested.
Studio profiles never save, so this is the only way to test it.

**Sim:** add offline earnings to `tools/econ_sim.py` as an option,
`--sessions=N`. It plays N sessions of 45 min with 8 h away between them.
Report how much offline earnings speeds up Rebirth 1–3 for a 3-session
player. Don't change any numbers; this is information for the next design
pass.

## Phase 5 — Docs, PR housekeeping, checks

- CLAUDE.md: add offline earnings (rule, `OfflineConfig`, `ClaimOffline`,
  `/offline`) and the lighting caps.
- **`docs/UI_TEST.md` §15 "Polish 6":**
  - The 4-Rainbow-Mythic floor check.
  - All five Fuse tabs visible at 1080p and on phone.
  - Toasts never cover REBIRTH!.
  - Pull ×10 is always shown.
  - `/offline 180` shows "away 3h 0m" with the right amount (25% × income ×
    10800 s), and COLLECT pays it once.
  - Rejoining doesn't pay twice.
- **PR housekeeping.** PR #2 was merged into `playable-loop`, so PR #4's base
  branch (`claude/upbeat-tesla-bfro6p`) is stale. Retarget PR #4 to
  `playable-loop` with the REST API
  (`PATCH /repos/tttomggy/FusionTycoon/pulls/4` with `{"base":"playable-loop"}`).
  Check it shows no conflicts, and say so in your summary. **Don't merge
  anything.**
- `luau-lsp analyze`: no new errors. PlotLayout assertions pass.
- Commit per phase, push `world-redesign`, and comment a summary on PR #4.
