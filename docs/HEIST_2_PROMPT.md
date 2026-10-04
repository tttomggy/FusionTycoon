# Fusion Tycoon — Heist 2: a real LOCK button + teaching every rule (build prompt for Claude Code)

Paste into Claude Code on `world-redesign` (`git pull` first). Same open PR
#6. Don't merge. Run this **before** `EVENTS_PROMPT.md`.

---

Read CLAUDE.md and follow it: HeistConfig for numbers, UITheme for every
colour and font, UIKit for screens, BillboardKit for world labels, PlotLayout
for every position, server authority, and `luau-lsp analyze`. Run the type
check after each phase and commit each phase on its own. The canvas board
**"Heist 2 · LOCK button + teaching"** shows the design.

## What the playtest showed

The shield, the eject loop, the guard and the re-arm all work. Two problems
remain:

1. **The YOURS pad is a hidden switch.** Nothing tells a kid that stepping on
   the claim pad locks the lab. It also fires by accident when you walk home.
2. **Nobody can learn the rules.** Guarding (stand next to your item), catching
   (touch the thief) and locking aren't shown anywhere. The only teaching is
   one toast for thieves.

The fix: the shield becomes a **LOCK button** you press on purpose, and the
four rules (GRAB, GUARD, CATCH, LOCK) are taught on screen and in the world.

**The numbers don't change:** shield 60 s, re-arm 20 s, claim shield 60 s,
victim shield 120 s, guard radius 6, tag grace 2 s, tag radius 5.

## Phase 1 — The LOCK replaces the YOURS pad

**The YOURS pad goes back to being decorative.**
- Delete the pad check in HeistService (`onPadCheck`, `state.onPad`) and the
  owner-only `ShieldPadLabel` over the claim pad (`refreshPadLabel`,
  `state.padLabels` / `padLabelText`).
- The pad face keeps "YOURS".

**One server entry point for locking:** `HeistService.TryLock(player): (boolean, string?)`.
- Rejected with a Reason, in this order:
  1. `Protected` (Rebirth 0).
  2. `Carrying`.
  3. `AlreadyLocked`.
  4. `Recharging`, with the seconds left.
  5. `NotHome`: the player's root isn't inside their own walls
     (`PlotLayout.IsInsidePlot`).
- On success: `RaiseShield(player, HeistConfig.ShieldSeconds)`,
  `PlayerDataService.IncrementShieldRaises`, then `SyncTycoon` (this pays the
  goal).
- New remote `RequestLock` (C→S, no payload). A rejection fires the existing
  toast path with these texts:
  - `NotHome`: "Get back to your lab to lock it!"
  - `Recharging`: "Lock recharging · 12s"
  - `Carrying`: "Not while carrying!"

**LOCK console (world).**
- New `PlotLayout.LOCK_CONSOLE = v3(10, 0, 27)`: inside the gate, right of the
  walkway, between the claim pad and the Gacha Pad. Facing +Z toward the gate,
  so you see it as you walk in.
- Add its footprint (3 × 3) to the PlotLayout assertion block. If the
  assertions say it overlaps something, slide it along x and keep it inside the
  gate on the right.
- Build it in a new `StationKit.BuildLockConsole` (or a small `LockKit` if
  StationKit is crowded):
  - a 2 × 4.5 × 2 SmoothPlastic post (`World` panel colour),
  - a tilted 3.5 × 0.6 × 2.5 top,
  - a round **pink button** on the top: a thin Neon cylinder seen from the side
    (CLAUDE.md's no-flat-Neon-circles rule), or a SurfaceGui disc via
    BillboardKit; your choice.
- **Prompt:**
  - ActionText "Lock lab", ObjectText "60s shield".
  - KeyCode E, HoldDuration 0, MaxActivationDistance **8**.
  - `RequiresLineOfSight = false`, `Exclusivity = OnePerButton`, `OwnerOnly = true`.
  - Triggering it calls `TryLock`. It's the same rules as the HUD button, but the
    distance already proves you're home.
- **Label** (BillboardKit, owner-only, MaxDistance 60): title "🔒 LOCK LAB",
  plus a pill, all driven by the plot attributes already published
  (`ShieldUntil`, `ShieldRearmAt`, `Protected`) so it runs on the client without
  a remote.

  | State | Pill | Button | Prompt |
  |---|---|---|---|
  | Ready | "READY · 60s shield" (pink, `Gradients` token for the shield pink) | pink | on |
  | Locked | "LOCKED · 42s" (teal) | glows teal | off |
  | Recharging | "RECHARGING · 12s" (muted) | dim | off |
  | Rebirth 0 | "🛡 PROTECTED · NEW LAB" (teal) | — | off |

  The client recolours the button. The server builds it once.

**HUD LOCK button.**
- It replaces the shield chip under the cash card, in the same slot. Build it
  with `UIKit.Button` at 200 × 52 (≥ 44 px after the phone scale).
- States:

  | State | Look | Text |
  |---|---|---|
  | Ready | pink gradient | "🔒 LOCK LAB" |
  | Locked | teal | "🛡 LOCKED · 42s" |
  | Recharging | muted, still tappable (tap → toast) | "RECHARGING · 12s" |

- Hidden at Rebirth 0.
- Tapping it fires `RequestLock`. The server decides; if you're outside your
  walls you get the `NotHome` toast.
- **Pulse it** (the old amber pulse, now pink) while it's ready **and** a
  non-owner is inside your walls. That's the moment it matters.

**Goals.** `first_shield` becomes "Lock your lab with the LOCK button", target
`LockConsole`. Add that target resolver in GoalService and GoalMarker. The
counter it reads (shield raises) is unchanged.

**Strings.** Grep for every "YOURS" and "step on" in shield-related strings,
comments and docs, and update them. The welcome/claim flow still says YOURS on
the pad, and that's fine.

## Phase 2 — GUARDED is visible

Guarding already works (`OwnerBlockRadius`, `GuardedByOwner`). Now everyone
can see it.

- **GUARDED chip:** above every filled pedestal whose `GuardedByOwner` is true,
  a teal pill "🛡 GUARDED".
  - Client-side, every viewer, MaxDistance 60, `AlwaysOnTop = false`.
  - It sits above the existing pedestal label and the red hand marker; when
    guarded, the hand marker hides.
- **Guard ring:** while the owner is inside their walls, each filled pedestal
  gets a faint teal ring on the floor, radius `OwnerBlockRadius`.
  - Make it a SurfaceGui ring face (`BillboardKit.BuildPadFace` style), not a
    Neon disc.
  - Alpha ~0.25; ~0.6 while that pedestal is GUARDED.
  - Client-only. Skip it for labs at Rebirth 0.
- **Light check:** neither adds a light or a Highlight.

## Phase 3 — The HOW TO HEIST card

A UIKit Modal with **4 slides**, one at a time, with ◀ ▶ arrows, dots, and a
"GOT IT" button on the last. Each slide has a picture area, a title and one
line:

| # | Title | Line | Picture |
|---|---|---|---|
| 1 | **GRAB** | "Hold E on someone's pedestal. Run it home in 45s and it's yours." | orb over a player, arrow to a house |
| 2 | **GUARD** | "Stand next to your item. Nobody can steal it while you're there." | orb, owner beside it, the teal GUARDED pill |
| 3 | **CATCH** | "A thief has your item? Touch them and it flies back." | two players, "CAUGHT!" |
| 4 | **LOCK** | "Press LOCK LAB. Nobody gets in for 60s. Then it recharges." | pink fence outline with 🔒 |

- **Pictures:** build them from UIKit pieces (TierOrb, small rounded frames as
  players, UITheme colours). No image assets.
- **Read numbers from HeistConfig** (`CarrySeconds`, `ShieldSeconds`), never
  hard-coded.
- **When it opens:**
  - automatically, once, right after the first-rebirth result card closes,
    which is the moment stealing unlocks,
  - and from a new round **"?" HUD button** (44 px), next to the LOCK button,
    visible from Rebirth 1.
- Remember "seen" in a new `PlayerData.Tips` table (`{ [string]: boolean }`,
  saved), keyed `howToHeist`, so it only auto-opens once per account.
  - New remote `MarkTipSeen` (C→S, `{ Id }`). The server whitelists the ids in a
    new `Shared/Config/TipConfig.lua`.
  - Include `Tips` in the snapshot.
  - At Rebirth 0, the locked-teaser prompt's ObjectText stays "Unlocks at
    Rebirth 1".
- **Phone:** the slides stack the picture over the text. The card fits in
  390 px tall after the scale.

## Phase 4 — One-time tips in the moment

Use the same `Tips` table and `MarkTipSeen`, so they don't repeat across
sessions. Replace the session-only `tipShown` in HeistController with the saved
one: id `stealHowTo`, same text as now. Each tip is a **big neutral toast**
(4 s), or the banner where noted.

| Id | When | Text |
|---|---|---|
| `intruder` | Rebirth 1+, a non-owner's root enters your walls while you're unlocked | "Someone's in your lab! Stand by your items or LOCK your lab!" and the HUD LOCK pulse |
| `guarded` | you're within prompt distance of a pedestal whose `GuardedByOwner` is true | "They're guarding it. Wait for them to walk away." |
| `catch` | the first time you're a victim | the victim banner gets an extra big line for that carry, "TOUCH THEM!", and the red arrow pulses |
| `lockAfterLoss` | the first time you lose an item for real | after the loss card: "Tip: press LOCK LAB when you leave your lab." |

## Phase 5 — Docs and checks

- **CLAUDE.md:**
  - The Shield bullet: the LOCK console and HUD button replace the YOURS pad,
    `TryLock` and its reasons, `RequestLock`.
  - The GUARDED chip and ring.
  - The HOW TO HEIST card.
  - `PlayerData.Tips` + `TipConfig` + `MarkTipSeen`.
  - `LOCK_CONSOLE` in the layout notes.
  - The new remotes in the Heist remotes line.
- **`docs/UI_TEST.md` §16:** replace the YOURS pad cases. Add:
  - console lock / prompt off while locked or recharging
  - HUD lock from inside / "Get back to your lab" from outside
  - recharge countdown on both
  - Rebirth 0 shows PROTECTED, no HUD button
  - the HUD button pulses when an intruder is in
  - the GUARDED chip appears for the other player as the owner walks up
  - the guard ring
  - the HOW TO HEIST card auto-opens once after a real first rebirth
    (`/rebirthready`, then REBIRTH! at Rebirth 0; `/rebirths 1` skips the
    result card, so it won't trigger), not again after `/tips reset`-less
    replays, and always from "?"
  - each tip fires once
  - the first_shield goal arrow points at the console
- **Debug:** add `/tips reset` (clears `Tips`) so the card and tips can be
  re-tested in Studio.
- `luau-lsp analyze`: no new errors. PlotLayout assertions pass. Commit per
  phase, push, and add a section to PR #6's summary.
