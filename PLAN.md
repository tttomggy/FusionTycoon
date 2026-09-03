# Service Lifecycle Migration — Verification & Plan

Status date: 2026-09-03

## TL;DR

Two findings change what this plan needs to be:

1. **The four services are already migrated.** `ItemService`,
   `FusionMachineService`, `LightingService`, and `DebugService` were converted
   to the `:Init()`/`:Start()` lifecycle earlier in this session. There is no
   migration code left to write.
2. **No circular dependency ever existed.** Verified by cycle detection against
   the pre-migration commit. `ItemService → TycoonService` was a
   *one-directional* edge, i.e. a latent risk, not a cycle.

What remains is three decisions, listed at the bottom, one of which is a
conflict with the instructions in this request.

---

## Verification 1 — require() chain analysis

### Method

Extracted every module-scope (column-0) `require(script.Parent.*)` from all
seven services at commit `4eadb20` (pre-migration) and in the current working
tree, then ran cycle detection over the resulting graph.

Only top-level requires are counted, because those are the only ones that
execute at module-load time and can therefore deadlock. A `require` inside a
function body (e.g. in `:Start()`) runs later and cannot participate in a
load-time cycle.

### The exact lines in question

At `4eadb20`, `src/ServerScriptService/Services/ItemService.lua`:

```lua
 9: local PlayerDataService = require(script.Parent.PlayerDataService)
10: local TycoonService = require(script.Parent.TycoonService)
```

At `4eadb20`, `src/ServerScriptService/Services/TycoonService.lua`:

```lua
18: local PlayerDataService = require(script.Parent.PlayerDataService)
```

`TycoonService` contained **no** `require` of `ItemService` — it referenced
`ItemService` only in four comments (lines 173, 1115, 1118, 1197), which are
inert.

### Original graph

```
ItemService  ──> PlayerDataService
ItemService  ──> TycoonService ──> PlayerDataService
FusionService ──> PlayerDataService
DebugService  ──> PlayerDataService
PlayerDataService ──> (nothing)
LightingService / FusionMachineService ──> (nothing)
```

`CYCLES DETECTED: NONE`

### Conclusion

**A top-level circular dependency did not exist.** The graph was a DAG rooted
at `PlayerDataService`, which requires no services at all.

`ItemService → TycoonService` was a *latent hazard*: it was one line away from
becoming a genuine deadlock, because nothing structurally prevented someone
from later adding `require(script.Parent.ItemService)` to `TycoonService`. That
is a real reason to move the require into `:Start()` — but it is a preventative
change, not a bug fix.

> Correction to my own earlier statements: in previous turns I described this
> as "the exact circular-dependency hazard" and "the actual cycle hazard."
> "Hazard" was accurate; any implication that a cycle was *present* was not.
> There was never a deadlock in this codebase.

### Current graph

```
(no top-level service → service edges)
CYCLES DETECTED: NONE
```

All cross-service references now resolve inside `:Start()`.

---

## Verification 2 — current migration state

| Service | Mode | Lifecycle | Top-level service requires |
| --- | --- | --- | --- |
| `ItemService` | `--!strict` | `:Init()` `:Start()` | 0 |
| `FusionMachineService` | `--!nonstrict` | `:Init()` | 0 |
| `LightingService` | `--!strict` | `:Init()` | 0 |
| `DebugService` | `--!strict` | `:Init()` `:Start()` | 0 |
| `TycoonService` | `--!nonstrict` | `:Init()` `:Start()` | 0 |

What was done per service:

- **ItemService** — `:Init()` connects its two remote handlers; `:Start()`
  resolves `PlayerDataService` *and* `TycoonService`. Private `state` table for
  connections. This is the change that removed the latent hazard above.
- **DebugService** — `:Init()` (Studio-gated) wires chat connections;
  `:Start()` resolves `PlayerDataService`. Connections now tracked in `state`.
- **LightingService** — `:Init()` only; no cross-service refs. One real
  strict-mode bug fixed: `FindFirstChildOfClass("Sky") or Instance.new("Sky")`
  types as `Instance` (no `StarCount`), now cast to `Sky`.
- **FusionMachineService** — `:Init()` only. No cross-service refs, no
  connections or loops, so no `:Start()` and no connection tracking needed.

Constraint compliance:

- **Dot-notation for public APIs — preserved.** No public method was converted
  to colon. `Service.Method(p)` throughout; colon is used strictly for
  `:Init()` / `:Start()` / `:Stop()`. This was deliberate: converting ~55
  public call sites with no type checker installed risks silent `self`
  shadowing that nothing would catch.
- **Registration in `ServiceManager`** — no change was required. All four were
  already in `INIT_ORDER`, and the auto-discovery pass would have loaded them
  regardless.

---

## Open decisions — need your call before anything else happens

### Decision 1 — `--!nonstrict` for legacy files (conflict with this request)

This request says to *"keep legacy files as `--!nonstrict`."* That conflicts
with the current tree: **`ItemService`, `LightingService`, and `DebugService`
are currently `--!strict`.** I made them strict in the earlier migration pass
because they were small and tractable; only `FusionMachineService` was left
`--!nonstrict` (dense Instance construction, same rationale as
`TycoonService`).

Options:

- **A.** Revert those three to `--!nonstrict`, matching the instruction
  literally. Cost: loses type checking on ~290 lines that are now annotated.
- **B.** Keep them `--!strict`. They are annotated but **unverified** — no Luau
  type checker is installed, so nothing has ever checked them.
- **C.** Install the checker first (`aftman install`, then the three commands
  in `aftman.toml`), run `luau-lsp analyze`, and decide per-file on evidence.

Recommended: **C**, then B for whatever passes clean. Strict annotations that
have never been checked are the worst of both worlds.

### Decision 2 — `TycoonService` was already modified

Your standing constraint: do not modify `TycoonService` beyond what's strictly
required to resolve the circular dependency, and stop and explain if the fix
requires changing it.

**The fix required zero changes to `TycoonService`.** It was resolved entirely
inside `ItemService`. So under your rule, `TycoonService` should not have been
touched for this.

It was nonetheless modified earlier in the session, under the separate request
to *"refactor... consistently across PlayerDataService, TycoonService, and
FusionService."* Those edits are on disk now:

| Line | Change |
| --- | --- |
| 1 | `--!nonstrict` + header comment |
| 39–40 | `require` replaced by type alias + unassigned typed declaration |
| 44 | `TycoonService.Name` added |
| 214–224 | 3 bare state locals → `type State` + `local state: State` |
| (11 sites) | `plotByUserId[…]` → `state.plotByUserId[…]`, etc. |
| 1382 | `.Init()` → `:Init()` |
| 1401 | `:Start()` added |

Options:

- **A.** Revert all of it. Safe — `PlayerDataService` requires no services
  (verified leaf), so restoring the module-scope require reintroduces no cycle,
  and `ServiceManager` handles a dot-`Init()` fine. Constraint: lines 39–40 and
  1401 must revert together, or `PlayerDataService` stays nil forever.
- **B.** Keep it. `TycoonService` then matches the documented pattern like
  every other service.

This is the item I flagged last turn and is still unanswered.

### Decision 3 — strict-mode conversion of the two remaining files

`TycoonService` (~1400 lines) and `FusionMachineService` (~370 lines) are
`--!nonstrict`. Both are dense Instance construction. Converting either
without a type checker installed would ship an unknown number of errors nobody
can see locally. Blocked on Decision 1C.

---

## If approved, the only remaining work

1. Install the type checker: `aftman install` (needs an interactive trust
   prompt on first run), then generate the sourcemap and run `luau-lsp
   analyze` per the commands in `aftman.toml`.
2. Act on Decisions 1 and 2 above.
3. Convert the two `--!nonstrict` files one at a time, each as its own
   reviewable pass, only once the checker can verify the result.

Note: `rojo build` is **not** verification. It exits 0 on broken Luau and
embeds it verbatim (tested directly). Nothing in this codebase has ever been
type-checked or syntax-checked.
