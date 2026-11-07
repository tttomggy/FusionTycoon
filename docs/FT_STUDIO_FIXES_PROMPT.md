# Fusion Tycoon: fixes from the first real Studio `/selftest` of Orb Rush + rival tiers

Branch `world-redesign`. Read CLAUDE.md first (UI rules, HudLayout / TopStack,
card placement, Working style). Do NOT publish anything. Studio is not
available to you: the planner runs `/selftest` after your push and sends back
what is left.

## What the planner ran

The `world-redesign` build (code as of `72d4543`) in Studio, mock store,
`/selftest`, run alone (no other player, nothing else going on):
**865 passed, 5 failed** (a second clean run: 864 / 6, see the flakes below).
Everything in sections 16 (rival labs) and most of 17 (ORB RUSH) passes.

Also fixed already, pushed as `72d4543`: `Bootstrap.client.lua` read
`script.Parent.Controllers` / `.UI` without waiting and a fresh Studio Play
died with `Controllers is not a valid member of PlayerScripts` (no HUD at
all). Now `WaitForChild`. Leave it.

## The failures (stable ones first)

1. **`orb rush hud (phone)`**: `OrbRushPill overlaps HUD PhoneStatus;
   OrbRushPill overlaps HUD PhoneGrid; OrbRushPill overlaps HUD DealBadge;
   OrbRushList overlaps HUD PhoneGrid`
2. **`orb rush hud (desktop)`**: `OrbRushPill overlaps HUD LockRow;
   OrbRushList overlaps HUD LockRow`
   These are real layout bugs (ORB RUSH's JOIN pill and its list collide with
   the HUD's left group). Fix in the HUD layout / the controller's placement
   (HudLayout rects, TopStack slot rules in CLAUDE.md), not with magic
   numbers, at 1920x1080, 1366x768, 844x390 and 896x414. Keep >= 44 px tap
   targets, the top-left 170x60 clear, no text under 13 px.
3. **`hovering things stay home` (before and after a pedestal rebuild)**:
   `Workspace.OrbRushArena.Debris outside every plot at ...` (a dozen entries,
   y 217-299, z 790-1080). The arena is deliberately outside every plot. The
   arena debris is tagged FT_Hover; decide which is right: the check skips
   the arena folder (preferred: the arena is not a plot object) or the debris
   is not tagged. Keep the check strict for everything else.
4. **`remote fuzz: no state change: changed field(s): Tips: {} ->
   {tipRival=boolean:true}`** (seen in one of three runs). The tutorial tip
   fired by itself during the fuzz window, which is not the fuzz changing
   state. Make the check robust (snapshot after the tip logic is quiet, or
   exclude TipConfig ids from the diff when the change comes from the tip
   service); do not weaken it for anything else.
5. **Scheduled ORB RUSH rounds run into the selftest.** The real schedule
   (hh:07 / :22 / :37 / :52, a 60 s call window) fired while the selftest was
   running and left an `OrbRushResults` overlay open: in that run the
   gacha-card checks failed with `the card is shut: block overlays
   OrbRushResults` at every phone size (and two section-17 checks failed:
   `with 4 placement prizes already this hour, the next 1st place pays cash
   and no orb: award nil, items 23 -> 23` and `an AFK player (under 10 points)
   gets no award: no orb, no cash: award nil`). `/selftest` already says "run
   it outside events": give ORB RUSH the same treatment. While a selftest
   runs (a server flag set by DebugService's runSelfTest, cleared at the end,
   even on error) the scheduler does not open a call window, and a round that
   is already running is aborted at the start. Then check why the two
   section-17 awards were `nil` in that run and make those two checks
   deterministic (they use `/orbrush`-style forced rounds; a stray scheduled
   round or a stale queue must not matter).

## Do

- Fix 1 to 5, targeted edits only. Update `docs/systems/minigames.md` and
  `docs/UI_TEST.md` where the HUD placement or the selftest flag changes.
- Pre-push: the checks in CLAUDE.md (compile_check.py, theme_token_check.py,
  luau-lsp analyze: the type-checker baseline is 6 known errors, no new ones,
  the `(` grep). If an economy number changes, tools/econ_sim.py.
- Commit messages end with:
  `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01Up5kWTFPca82NxZV9RScyP`
- Push to `world-redesign`. Report (docs/FT_STUDIO_FIXES_REPORT.md, first line:
  the branch): what changed per item, the HUD rects before / after at the four
  viewports, and what you could not verify without Studio.
