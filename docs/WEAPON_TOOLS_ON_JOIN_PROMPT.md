# Weapons can't be equipped in the live game (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 4 lines. **Only these edits.**

---

## The bug

In the **live** game, Harris (Rebirth 3, all quests done) sees all 5 weapons
in the bar, but pressing 1–5 or clicking a slot does nothing. It works in
Studio.

The cause is in `CombatService`:
- `onCharacterAdded` → `task.defer` → calls `giveTools` **only if
  `PlayerDataService.IsDataLoaded(player)`**.
- On a live server, the character spawns **before** the DataStore load
  finishes, so `giveTools` is skipped.
- Nothing calls it again once the data loads: `grantByRebirths` only calls
  `giveTools` when it grants something **new**.
- So the Backpack stays empty until the player respawns.
- Studio loads data instantly, which hides it.

On the client, `CombatController.toggleEquip` silently returns when
`findTool` finds nothing, so there's no feedback either.

## Fix

1. **Give the tools when the data finishes loading.**
   - In `onCharacterAdded`, if the data isn't loaded yet, wait for it
     (`PlayerDataService`'s loaded signal, or poll `IsDataLoaded` every
     0.25 s for up to 30 s), then `giveTools` if `player.Character` is still
     that character.
2. **Make the sync hook self-healing.** In `grantByRebirths` (the
   `OnSync` hook), also call `giveTools(player)` when any owned weapon is
   missing from both the Backpack and the character. Cheap check first:
   `giveTools` itself stays idempotent.
3. **Client fallback:**
   - If `toggleEquip` finds no tool for an **owned** weapon, show the toast
     "Getting your weapons…".
   - Fire a new remote `RequestWeaponTools` (client → server, no payload,
     `RemoteGuard.Allow` rate limit, in `REMOTE_EVENT_NAMES` with a comment),
     whose handler calls `giveTools`.
   - Then retry the equip once after 0.5 s.
4. **Selftest:**
   - destroy every weapon Tool in your Backpack and character, then fire a
     `SyncTycoon`: all owned tools are back within 1 s;
   - call the `RequestWeaponTools` handler: no duplicates.
5. **Studio repro:** add `/data slowload <seconds>`, which delays the next
   join's data load in Studio so the bug can be reproduced. Optional, but
   only if it's small.

## Part 2: AUTO-FILL does nothing when only mutated orbs are left

Harris's live screenshot shows the Common tab at **60**, and every card is
mutated: Golden Spark Cell, Golden Copper Bolt, Golden Glass Shard (Golden
Rain gives a lot of these). With an empty chamber, `FusePanel.matchingUids`
→ `FusionController.GetAutoFill` takes **unmutated items only**. It finds
none, so the button silently does nothing. The rule (never drag a mutation
down) is right; the dead button is wrong.

Fix, in `FusePanel.autoFill` with an empty chamber:
1. Unmutated items exist → no change.
2. None, but mutated items of this tier exist → group them by stack
   (`MutationConfig.SameStack`, not carried, not displayed). Fill with the
   **largest group** (ties: the lower mutation value first, so the rarest
   stack is kept). Up to `MaxFusionInputs`, and only if that group has ≥ 2.
   - Toast: "Filled with GOLDEN orbs (they keep their mutation)".
3. No group has ≥ 2 → toast "Not enough matching orbs to fuse", and pulse
   the tab count. Never a silent no-op.
4. Don't change `FusionController.GetAutoFill` itself: AGAIN and FUSE ALL
   keep skipping mutated items.
5. **Selftest:** give 6 Golden Commons and 0 plain Commons, then press
   AUTO-FILL on Common: 6 selected, all the same stack, and the toast shown.
   Give 1 Golden and 1 Rainbow only: 0 selected, and the "not enough" toast.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs.
- Update `docs/systems/combat.md`, `items-and-fusion.md` (auto-fill rule)
  and `architecture.md` (remote).
- Harris: open Fuse → Common with only Golden orbs, press AUTO-FILL, and it
  fills with 6 Golden ones.
- Harris, in the **live** game after publishing: join, and pressing 1 equips
  the Bat right away, without a reset.
- Say which branch you pushed to.
