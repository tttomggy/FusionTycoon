# Fusion Tycoon — Heist: stealing displayed items + lab shield (build prompt for Claude Code)

Paste everything below into Claude Code.

---

**Branch:** PRs #3 and #4 are merged, so `main` has everything.
1. Check out `world-redesign`, run `git pull`, then `git merge origin/main`. This should fast-forward over the two merge commits.
2. Work there.
3. At the end, open a **new PR `world-redesign` → `main`**. Don't merge it.

This pass adds the multiplayer hook: from Rebirth 1, items **on pedestals** can
be stolen by other players, and each lab has a shield. The design is fixed. The
canvas board **"Heist · stealing + shield"** shows it, and every number is in
this file.

Read `CLAUDE.md` first and follow it: config tables for numbers, UITheme for
every colour and font, UIKit for screens, `SyncTycoon` + `SyncInventory`,
RemoteEvents, the service lifecycle, server authority, and `luau-lsp analyze`.
After each phase, run the type check, fix every new error in files you touched,
and commit the phase on its own.

**The prime directive of this pass: no duplication, no loss.**
- An item is in exactly one player's inventory at every moment.
- A failed or interrupted steal always puts it back.
- Write the transfer so a crash, a leave, or two requests in the same frame
  can't break that.

---

## The rules

| Rule | Value |
|---|---|
| Who can steal / be stolen from | both players need **Rebirth ≥ 1** (`HeistConfig.MinRebirths = 1`) |
| What | only items currently **on a pedestal**; inventory items are never at risk |
| Grab | hold E **1.5 s** at an enemy pedestal; prompt distance 7; victim's shield must be down |
| Carry time | **45 s** to get home |
| Carry speed | WalkSpeed **12** (normal 16); JumpPower unchanged |
| While carrying | can't pull, fuse, upgrade, rebirth, use the shield pad, or start a second steal |
| Deliver | the thief's character root enters **their own** plot bounds (inside the walls) |
| Tag (owner saves it) | the **owner** gets within **5 studs** of the thief |
| Fail → item returns | tagged, timeout, thief dies or leaves, victim leaves, or the victim's plot is removed |
| Thief cooldown | **60 s** after any attempt (success or fail) |
| Victim protection | after losing an item: auto-shield **120 s**; at most **3 items lost per 10 min** (after that, the lab is unstealable for the rest of the window) |
| Shield | **60 s** per activation; re-arm by stepping on your **YOURS** pad once it's down; auto 60 s on claim |
| Shielded lab | any non-owner whose root is inside the plot bounds is moved to the street in front of the gate (`PlotLayout.SPAWN_POSITION` + clearance) |
| Income | a pedestal whose item is being carried earns nothing until it's back or gone |

Put every number in **`Shared/Config/HeistConfig.lua`** (new, `--!strict`).

## Phase 1 — HeistConfig, shield state, protection

- **HeistService** (new, `--!strict`, follows ServiceTemplate). It owns all
  heist state in a private session table:
  - shield-until time per player
  - the thief's cooldown-until time
  - the victim's recent-loss timestamps
  - active carries: `thief UserId → { VictimUserId, PedestalIndex, ItemUid, StartedAt }`
- **Shield:**
  - `HeistService.RaiseShield(player, seconds)` and
    `HeistService.IsShielded(player)`.
  - The **YOURS pad** (the claimed claim-station pad at
    `PlotLayout.CLAIM_STATION`) raises the shield when its owner steps on it
    while the shield is down. Use a touch/region check on the server, debounced.
  - Auto 60 s on claim.
  - Expose the shield state as a plot attribute, `ShieldUntil` (server time),
    so every client can render it without a remote.
- **Eject loop:** every 0.25 s, for every shielded plot, move any non-owner
  whose HumanoidRootPart is inside the plot bounds to the street in front of
  that gate. Use `PlotLayout`'s plot bounds and inner wall, not a new copy.
- **Protection:**
  - A Rebirth-0 owner's lab is permanently protected: no prompts, no eject
    needed.
  - The plot sign adds a teal pill `🛡 PROTECTED · NEW LAB` while the owner
    has 0 rebirths.
- **Debug (Studio):**
  - `/shield <seconds>` (0 drops it).
  - `/heistcd 0` clears your thief cooldown.
  - `/stealable` makes your own lab stealable even at Rebirth 0, for testing.

## Phase 2 — The steal transaction

**Prompt.** Each pedestal gets a second ProximityPrompt, `StealPrompt`:
- ActionText "Steal", ObjectText = the item's display name.
- HoldDuration 1.5, MaxActivationDistance 7.
- `RequiresLineOfSight = false`, `Exclusivity = OnePerButton`.
- The server marks it with the attribute `EnemyOnly = true` and `OwnerUserId`.
- On each client, **WorldLabelController** enables it only when:
  - the viewer isn't the owner,
  - both are Rebirth ≥ 1 (read rebirths from leaderstats),
  - the pedestal is filled,
  - the plot isn't shielded.

  The server re-checks everything anyway.

**Grab** (`RequestSteal`: client → server, payload `{ OwnerUserId, PedestalIndex }`;
the server resolves everything else). Validate:
1. Data is loaded for both players.
2. The thief isn't already carrying and isn't on cooldown.
3. Both players are at Rebirth ≥ `MinRebirths` (or the victim has `/stealable`
   in Studio).
4. The victim's shield is down and the victim's 10-minute loss cap isn't hit.
5. The pedestal is filled and its item exists in the victim's inventory, InUse.
6. The thief's root is within 9 studs of the pedestal (the prompt distance plus
   slack).
7. The item isn't already being carried.

Then:
- Record the carry in session state. **Don't touch either inventory yet.**
- Set pedestal attribute `BeingStolen = true`. PedestalVisuals hides the orb
  and shows a dim ghost ring; the label reads "STOLEN!" in Danger.
- Income for that pedestal stops: `GetIncomeInputs` skips pedestals with an
  active carry.
- Set the thief's WalkSpeed to 12.
- Start the thief cooldown.
- Fire `HeistStarted` to the thief and the victim, plus a server feed for
  Legendary and up.

**Carry loop** (Heartbeat, ~10 Hz, per active carry):
- Tagged when the owner's root is within 5 studs of the thief's root → **fail
  (saved)**.
- Timeout → **fail**.
- The thief's root inside the thief's own plot bounds → **deliver**.

**Deliver** — one synchronous block, no yields:
1. Re-find the item by Uid in the victim's inventory. If it's missing, fail
   cleanly and warn.
2. Clear the victim's pedestal display, then remove the item from the victim's
   inventory.
3. Add a new item to the thief with the same ItemId, tier and mutation:
   `AddItem`, so it gets a new Uid and the Index entry.
4. Record the victim's loss timestamp and raise their shield for 120 s.
5. Then: SyncTycoon and SyncInventory for **both** players, refresh the victim's
   pedestal visuals and labels, `SaveNow` for both, and fire the results.

**Fail** (any reason):
- Clear `BeingStolen`; the pedestal shows the item again (it never left the
  inventory).
- Restore the thief's WalkSpeed.
- Sync both and fire the results with the reason.
- This must also run from:
  - **PlayerRemoving** for either side; on the victim's side, before the
    victim's save,
  - **thief death** (`Humanoid.Died`),
  - and when the victim's plot is removed.

**Remotes** (add to RemoteEvents with direction comments):
- `RequestSteal` (C→S)
- `HeistStarted` (S→C: role, item, other player, endsAt)
- `HeistEnded` (S→C: role, outcome `Delivered | Saved | Timeout | Left | Died`,
  item)
- `HeistFeed` (S→all: text parts for the banner)

## Phase 3 — Visuals and HUD

**Shield fence.** Built once per plot, hidden while down:
- 10-stud-tall panels just outside all four walls, Material **ForceField**
  (the one allowed exception to the materials rule; note it in CLAUDE.md),
  colour `World.Shield` `#FF4FD8`.
- Plus a 0.3-stud Neon line across the gate gap at y 0.5.
- The client shows and hides them from `ShieldUntil`, with a quick fade.
- Remote players see your shield too.

**Thief:**
- The carried orb floats 3 studs above the head, attached with a weld or
  AlignPosition on the **client of every player**. It's a cosmetic clone of the
  pedestal orb, mutation shell included.
- A red light beam goes up from it: Beam, Danger colour, 40 studs.
- A pill above the head: `THIEF · 31s`.

**Thief HUD:**
- An orange top-centre banner, "GET HOME!", with the item name and seconds, and
  a draining bar.
- The GoalMarker arrow points at your own gate while carrying.

**Victim HUD:**
- A red banner, "THIEF IN YOUR LAB! <name> grabbed your <item> · Touch them to
  get it back".
- A live distance readout.
- A red arrow locked on the thief, reusing GoalMarkerController's arrow with a
  Danger tint.
- An alarm sound: use an existing station sound or a free Roblox library sound
  id. Say which in your summary.

**Results:**
- Thief success: a result card "HEIST COMPLETE!" with the item orb.
- Thief fail: a toast "Caught!" / "Too slow!".
- Victim saved: "SAVED! You got your <item> back".
- Victim lost: a card "<name> stole your <item>". Its sub-line says the shield
  is up for 2 min.

**Shield HUD chip** under the cash card:
- Teal while up: "🛡 SHIELD · 42s".
- Pulsing amber "SHIELD DOWN · step on YOURS" while down and the player is
  Rebirth ≥ 1.
- Hidden at Rebirth 0, where the plot sign says PROTECTED instead.

**Server feed:** AnnouncementController, for Legendary and up only, with mutation
words coloured as usual:
- "Har stole a Golden Rift Engine from Bob!"
- "Bob caught Har!"

**New tokens:**
- `World.Shield`
- `Colors.ShieldTeal` `#1FB49A`
- `Colors.ShieldAmber` `#FFBE28`
- `Gradients.Heist` (Danger → `#6E0F24`)

All on-screen text follows the 12 px / 44 px tap rules.

## Phase 4 — Hardening

Each of these needs a short test note in UI_TEST:
- Two thieves grab the same pedestal in the same frame: one wins, the other is
  rejected.
- The owner removes the item from the pedestal mid-carry. **Block it:** the
  remove prompt is disabled while `BeingStolen`, and the server rejects it too.
- The owner rebirths mid-carry: rebirth is blocked while one of your items is
  being carried, with a toast.
- The thief rebirths, fuses or pulls mid-carry: blocked.
- The victim's `/wipe` mid-carry: fail first, then wipe.
- The thief leaves mid-carry: the item returns and nothing is saved to the
  thief.
- The victim leaves mid-carry: the item returns before the victim's save runs.
  Verify the order.
- A server shutdown (`BindToClose`) with active carries: every carry fails
  (returns) before the saves.
- An exploit client fires `RequestSteal` for a far pedestal, its own pedestal, a
  shielded lab, an empty pedestal, or a Rebirth-0 player: all rejected, with a
  `warn` for the suspicious ones.

## Phase 5 — Docs and checks

- **CLAUDE.md:**
  - Heist rules and HeistConfig.
  - HeistService in the service table.
  - The transaction order (carry state first, inventories only on delivery).
  - The eject loop.
  - The ForceField exception.
  - The new remotes and debug commands.
- **`docs/UI_TEST.md` §16 "Heist":** test with Studio's **Test → Clients and
  Servers, 2 players**:
  - Both players run `/rebirths 1`.
  - Player A shields; player B gets ejected.
  - Steal and deliver: the item moves and keeps its mutation, and A's shield
    auto-raises for 120 s.
  - Steal and get tagged: the item returns.
  - Steal and time out.
  - The Rebirth-0 PROTECTED sign and no prompts.
  - The 3-per-10-min cap.
  - Every Phase 4 case.
- `luau-lsp analyze`: no new errors. PlotLayout assertions pass.
- Commit per phase, push `world-redesign`, open the **new PR → `main`**, and
  post the summary on it. **Don't merge.**
