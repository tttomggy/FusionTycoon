# Selftest triage: 33 FAILs after 5264754 (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 10 lines: one line per group below, FIXED or WHY-NOT.

---

Harris's `/selftest` on 5264754 gave 345 passed and 33 failed. Fix the real
bugs first. For a FAIL that is only a test that's out of date, update the
**test**, and say so. Never loosen a test just to make it pass when the game
is actually wrong.

## A. Real bugs (gameplay)

1. **`CombatService:613: attempt to call a nil value`.**
   `CombatService.SelfTestRequestWeaponTools` calls `onRequestWeaponTools`,
   but that's a `local function` declared further down (line ~1032). At line
   613 the name resolves to a nil global. This crash aborted the rest of
   section 10.
   - Forward-declare it, or move the function above.
   - Check luau-lsp for any other use-before-declare in the files you
     touched in 5264754.
2. **AUTO-FILL fallback picks 0 orbs.**
   - `FusePanel.largestMutatedGroup` skips
     `InventoryController.IsInUse(item)` (displayed items). The rest of the
     panel lets displayed items be fused (`GetFusableItemsByTier` only sorts
     them last), and the selftest's Golden items were auto-displayed.
   - Match the panel: allow displayed items, but take non-displayed ones
     first.
3. **Weapon switch leaves the old tracks playing.** `combat switch
   SlapGlove -> Bat` shows `GloveHold` and `PeelThrow` still playing, with
   pose `BananaPeel`.
   - On every equip, stop **all** weapon tracks (hold and action) from the
     previous weapon before starting the new one.
   - Re-run the switch checks.
4. **The gacha card doesn't open the first time you step on the pad.**
   - The first probes show `shown false, PopScale 0.85` and "opened after
     181 frames".
   - Later, "walking back to the pad opens it again" PASSES.
   - Something is gating the first open: a leftover modal from the Fuse
     section, an equipped weapon, the aborted combat section, or a tutorial
     flag.
   - Find the real gate. If players can hit it (e.g. holding a weapon or
     walking up right after closing a panel), fix it in the game.
   - The 1-frame open check, the luck pill, the black orbs and the PS99 face
     all fail only because the card isn't open. Re-check them once it opens.
5. **Effects tray tooltip (desktop) overlaps `LockRow`.**
   - Opening to the right still hits the left column's LOCK row at Harris's
     1891 × 852 window.
   - Place it to avoid **every** HUD rect: try right, then above-right, then
     above. Pick the first candidate that overlaps nothing and stays on
     screen.

## B. Probably out-of-date tests (confirm, then fix the test or the game)

6. **Gacha keys: "Auto pull at $0 stops at once".**
   - It stopped correctly (`InsufficientCash`), but the test still expects
     the ×1 price (250); auto is ×10 now (cost 3069).
   - Expect the ×10 cost.
7. **"a single pull of a Common opens the big card".** Harris's rule: a
   single **fusion** shows the big card. Check what the reveal rule says for
   a single **pull** of a Common, then make the game and the test agree. Say
   which way you went.
8. **"tutorial: the Multiplier Pad can't be skipped at once".** Find out
   whether the step really can be skipped (a game bug) or the probe is stale.
9. **Bat reach** (0.86 / 1.14 studs vs 1.18 needed). Harris approved the
   Bat by eye. Turn these two into `WARN` lines (printed, not counted as
   FAIL) for the Bat only. Leave the Glove's checks as they are.

## C. Small UI misses

10. **The Pocket Cash tile text "20 min cash" doesn't fit** (shop Featured,
    desktop and phone). Use `TextScaled` with a max, or a shorter label like
    "Cash".
11. **`EventInfoCard` is 3 px off centre** (tolerance 2). Fix the placement
    (it's probably measuring before the last height change), not the
    tolerance.
12. **The Safe chip on phone: header 32.5 px from the top.** Scroll the
    section header to the top like the other chips do.

## Check

- `luau-lsp analyze` shows no new errors.
- Run `/selftest` yourself if you can. List any FAIL still left and why.
- Harris: run `/selftest` and paste the `FAIL` lines only (or "0 failed").
- Say which branch you pushed to.
