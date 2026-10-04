# Fusion Tycoon — Heist fix: shield pad, grab grace, thief feedback, discoverability (build prompt for Claude Code)

Paste into Claude Code on `world-redesign`, after Events is done (or after
Heist if Events hasn't started). Same open PR. Don't merge.

---

The first two-player playtest of Heist showed four problems. Read CLAUDE.md
and follow it. Run the type check after each phase and commit each phase on
its own.

## What the playtest showed

1. **The shield never stays down.** The YOURS pad raises the shield on every
   tick the owner stands on it.
   - `/shield 0` does nothing while you stand there.
   - The pad sits right inside the gate, so the owner re-shields every time
     they walk home.
   - Worst: an AFK player standing on the pad has a permanent shield.
2. **Instant catch.** The owner was standing next to their pedestal when the
   thief grabbed. The tag (5 studs) fired on the first carry tick: "THIEF IN
   YOUR LAB!" and "SAVED!" in the same second. The thief never even saw the
   orb, so it looked like nothing happened.
3. **The thief can't tell they're holding anything.** Make the carry
   unmistakable on the thief's own screen.
4. **Nobody knows stealing exists.** There's nothing in the game that teaches
   it.

## Phase 1 — Shield pad

- **Edge-triggered.** The pad raises the shield only on the tick the owner
  goes from outside the pad to inside it. Standing on it does nothing.
- **`HeistConfig.ShieldRearmSeconds = 20`.** After a shield ends (timeout or
  `/shield 0`), the pad can't raise it again for 20 s. That gap is the
  thieves' window.
  - The pad face shows "READY IN 12s" (BillboardKit pad label, owner-only)
    while recharging, and "SHIELD READY" when it's ready.
  - The HUD chip states:
    - "🛡 SHIELD · 42s" (teal) while up
    - "SHIELD RECHARGING · 12s" (muted) while recharging
    - "SHIELD DOWN · step on YOURS" (amber, pulsing) while it's ready but down
- The claim shield (60 s) and the victim shield (120 s) ignore the re-arm
  timer.
- `/shield 0` also clears the re-arm timer, so the next step on the pad works
  for testing.

## Phase 2 — Grab grace and the catch

- **`HeistConfig.TagGraceSeconds = 2`.** For the first 2 s of a carry the owner
  **can't** tag. After that the 5-stud tag works as now.
  - Show the grace to both players. The thief's banner reads "RUN!"; the owner's
    banner reads "Catch them in 2…1…".
- **`HeistConfig.OwnerBlockRadius = 6`.** If the owner's root is within 6 studs
  of the pedestal when the grab **starts** (when the hold completes), reject it
  with "The owner is guarding it!".
  - Add a `GuardedByOwner` attribute the client reads, so it can show the
    prompt as disabled with "Owner is guarding" text instead of letting the
    thief waste the hold.
  - Guarding your own pedestal is a real defence, and it's readable.
- The owner gets a little help: while one of their items is being carried, the
  owner's WalkSpeed is **18** (normal 16; the thief has 12). Reset it when the
  carry ends.
- The tag effect: a quick white flash ring at the thief, a "CAUGHT!" pop above
  the thief's head, and the orb flies back to its pedestal with a short Bezier
  tween. All client-side, cosmetic only.

## Phase 3 — Thief feedback

- **On a successful grab, on the thief's screen:**
  - A full-width banner for 1.5 s: "🫳 YOU GRABBED <item>! RUN HOME!", then the
    normal GET HOME! bar.
  - A grab sound: a whoosh or pickup from the free Roblox library. Say which
    id; it has to load.
  - A camera FOV punch of +8 for 0.3 s.
  - A big floating chip above the carried orb, visible to everyone:
    "<item name> · 45s".
- **Verify the carried orb shows on the thief's own client.** It sits above the
  head with its mutation shell and satellites, plus the red beam. If it's only
  built for other clients, fix that.
  - Weld the orb group to the head, or use RigidConstraint/AlignPosition, so it
    follows animation and jumps.
  - Make it LocalTransparencyModifier-safe so first-person or zoomed-in cameras
    still show it.
- **The thief's prompt.** When the thief stands at an enemy pedestal, the
  prompt's ActionText is "Steal" and the ObjectText is the item name and its
  $/s, so the value is clear before grabbing.

## Phase 4 — Teach stealing

1. **Teaser at Rebirth 0.** Enemy pedestals show a **locked** prompt:
   ActionText "🔒 Steal", ObjectText "Unlocks at Rebirth 1". It's disabled, but
   visible at the normal distance. Players learn stealing exists before they can
   do it.
2. **Unlock moment.** After the first rebirth, the REBIRTH result card adds a
   line: "🫳 STEALING UNLOCKED: grab items off other labs' pedestals and run
   them home!". Add `RebirthConfig.Unlocks[1]` = "Stealing + Mythic → Secret
   fusion", so the Rebirth panel's unlock row says it before they rebirth.
3. **Goals.** Append two goals to GoalConfig after `first_rebirth`:
   - `first_steal`: "Steal an item from another lab", reward $50,000, target
     the nearest enemy pedestal that's filled and unshielded. Add a target
     resolver for that.
   - `first_shield`: "Raise your shield on the YOURS pad", reward $10,000,
     target `ClaimStation`.

   Order: `first_shield` first, then `first_steal`.
4. **Enemy pedestal marker.** For a Rebirth-1+ viewer, a filled, unshielded,
   unguarded enemy pedestal gets a small red hand icon BillboardGui above its
   label:
   - MaxDistance 60, AlwaysOnTop false, client-side only.
   - It's a reason to walk into other labs.
   - Hide it while the viewer is carrying.
5. **First-time tip.** The first time a Rebirth-1+ player walks into an enemy
   lab with a stealable item, a one-time toast: "Hold E on their pedestal to
   steal it!". Remember it for the session only.

## Phase 5 — Docs and checks

- **CLAUDE.md:** the rearm, grace, guard and owner-speed rules, plus the
  teaching flow.
- **UI_TEST §16:** add cases for each of these:
  - standing on the pad doesn't re-raise
  - the 20 s re-arm
  - the grace window (owner adjacent; no tag for 2 s)
  - a guarded pedestal can't be grabbed
  - the thief sees the orb on their own screen
  - the locked teaser prompt at Rebirth 0
  - the unlock line
  - both new goals
  - the hand markers
  - the one-time tip
- `luau-lsp analyze`: no new errors. Commit per phase, push, and update the
  PR summary.
