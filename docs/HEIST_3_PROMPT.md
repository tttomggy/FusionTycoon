# Fusion Tycoon — Heist 3: real scenes in HOW TO HEIST, LOCK only at your lab, a clear steal timer (build prompt for Claude Code)

Paste into Claude Code on `world-redesign` (`git pull` first). Same open PR
#6. Don't merge.

---

Read CLAUDE.md and follow it: UITheme for every colour and font, UIKit for
screens, HeistConfig for numbers, server authority, and `luau-lsp analyze`.
Run the type check after each phase and commit each phase on its own. The
canvas board **"Heist 3 · real scenes, LOCK at your lab, steal timer"** shows
the design.

## What the playtest showed

1. **The HOW TO HEIST pictures look bad.** Slide 1's "lab" is a triangle on a
   box, and the players are orange blobs. It looks cheap next to the actual
   game.
2. **The HUD LOCK LAB button is too easy.** Locking from anywhere in your lab
   with one tap means you never have to run home. Locking should mean
   **getting to your LOCK console**.
3. **"Lay low for 60s" means nothing to a kid.** The thief cooldown has to say
   what it is and show how long is left.

## Phase 1 — LOCK only at the console

- **Remove the HUD LOCK LAB button** and the `RequestLock` remote, and update
  its comment line in RemoteEvents and CLAUDE.md. The console prompt, already
  answered server-side through ProximityPromptService, is the only way to
  lock.
- **`HeistService.TryLock`:** replace `NotHome` with **`TooFar`**: the
  player's root must be within `PlotLayout.LockConsole` prompt distance + 2
  studs of their own console. Keep the other reasons (Protected, Carrying,
  AlreadyLocked, Recharging).
- **In the button's slot, a status chip that is not a lock button.** Build it
  with UIKit, at least 44 px tall:

  | State | Look | Text |
  |---|---|---|
  | Unlocked | muted, amber text | "🔓 UNLOCKED" |
  | Locked | teal | "🛡 LOCKED · 42s" |
  | Recharging | muted | "RECHARGING · 12s" |
  | Alarm: lock ready and a non-owner's root is inside your walls | red, pulsing | "🚨 SOMEONE'S IN YOUR LAB · RUN TO LOCK" |

  - Hidden at Rebirth 0, as now.
  - **Tapping the chip** points the goal arrow at your LOCK console for 8 s
    (`GoalMarkerController.SetOverride`, then clear it), with the toast "Your
    LOCK button is just inside your gate".
- **Strings:**
  - Intruder tip: "Someone's in your lab! Stand by your items or run to your
    LOCK button!"
  - `lockAfterLoss`: "Tip: hit the LOCK button inside your gate before you
    leave your lab."
  - Slide 4: "Run to the LOCK button inside your gate. Nobody gets in for
    60s."

  Grep for any other "LOCK LAB button" / HUD-lock wording and fix it.
- **The `first_shield` goal** keeps its text and its console target. Only the
  console counts now.

## Phase 2 — The steal timer

- **Server:** publish the thief cooldown as a Player attribute,
  `HeistCooldownUntil` (server time). Set it when the cooldown starts, and
  clear it on `/heistcd 0`.
- **Toasts:**
  - Replace "Lay low for %ds" with "You can steal again in %ds".
  - After a delivered steal, the same line goes on the HEIST COMPLETE card's
    sub-line.
- **HUD chip** next to the LOCK chip, only while the cooldown is above 0:
  "🫳 NEXT STEAL IN 42s" (muted, amber text). When it reaches 0 it shows
  "🫳 STEAL READY!" (amber gradient) for 2 s, then hides.
- **Prompt:** add a `Cooldown` mode to WorldLabelController's StealPrompt
  modes:
  - ActionText "Steal in 42s", ObjectText the item label.
  - It's a no-hold tap that only shows the toast, like Locked and Guarded.
  - Precedence: Hidden > Locked > **Cooldown** > Guarded > Steal.
  - The red hand markers stay on while you're on cooldown, so you can still
    plan your next target.

## Phase 3 — Real scenes in HOW TO HEIST

Rebuild the picture area of `UI/HowToHeistPanel` as a **ViewportFrame with a
WorldModel**, so rigs render and animate. Each slide is a tiny 3D scene built
from the game's own pieces, looping a ~3 s clip of its rule.

**Card**
- 640 × 480; on a phone it fits 390 px tall after the scale.
- Scene: 600 × 250.
- Below the scene: a pink number badge plus the title in `Fonts.Display` 26,
  and the line in 16 px.
- Keep the ◀ / dots / NEXT ▶ row; the last slide says GOT IT.

**Set (shared by all slides)**
- A 40 × 40 floor slab in the lab floor colour, with the walkway strip.
- Camera fixed at the game's usual 3/4 angle, about 22 studs out.
- ViewportFrame `Ambient` / `LightColor` / `LightDirection` from new UITheme
  tokens, tuned so it reads like the lab.
- Pieces:
  - the real pedestal and orb from **PedestalVisuals**, a Golden Mythic with
    its shell and satellites;
  - the real **LockKit** console;
  - one plot wall section with the gate gap;
  - flat pink panels for the shield. ForceField doesn't render in viewports,
    so use transparent `World.Shield` SmoothPlastic.
- Floor rings are thin transparent SmoothPlastic cylinders. The no-flat-Neon
  rule is about Neon bloom in the world; in here, just don't use Neon for
  them.

**Actors**
- **YOU:** a clone of `LocalPlayer.Character`.
  - Set Archivable just for the clone, strip every script, sound and
    BillboardGui, and anchor the root.
  - Fallback: a rig from `Players:CreateHumanoidModelFromDescription(HumanoidDescription.new(), R15)`.
- **The other player:** a default R15 rig with red body colours (a UITheme
  token).
- Moves are CFrame lerps on RenderStepped. Play the run and idle animations
  using the ids read from the local character's `Animate` script, so they
  always load.
- **Labels are 2D:** BillboardGuis don't render in a ViewportFrame. Lay
  UIKit pills over the scene, positioned each frame from
  `camera:WorldToViewportPoint` scaled to the frame's size. Pill texts:
  "YOU", "THIEF" / "OWNER", item label, GUARDED, CAUGHT!, LOCKED · 60s.

**The four clips**

| # | Clip |
|---|---|
| 1 GRAB | YOU walk to an enemy pedestal; a 2D "E" hold ring fills over 1.5 s; the orb lifts above your head (red beam as a thin red part); you run off toward a blue "🏠 YOUR LAB" gate at the side. |
| 2 GUARD | The owner stands beside their pedestal on a teal ring with a "🛡 GUARDED" pill; the thief walks up, a red "✋ Owner is guarding" pill pops, and the thief backs away. |
| 3 CATCH | The thief runs with the orb over their head; YOU chase and touch them; a white ring flash and "CAUGHT!"; the orb arcs back onto the pedestal (the same Bezier as the real catch). |
| 4 LOCK | YOU run to the LOCK console and press; the button turns teal, the pink wall panels rise, a "🔒 LOCKED · 60s" pill shows, and the other player walks into the wall and is pushed back. |

**Performance**
- Build the scenes when the card opens and destroy them on close.
- Only the slide on screen ticks.
- No lights (viewports ignore them anyway), no Highlights.

The card text keeps reading numbers from HeistConfig.

## Phase 4 — Docs and checks

- **CLAUDE.md:**
  - LOCK is console-only (`TooFar`), with the status chip and its
    tap-to-point.
  - `HeistCooldownUntil` and the Cooldown prompt mode.
  - HowToHeistPanel's viewport scenes.
  - Remove `RequestLock`.
- **UI_TEST §16:** replace the HUD-lock cases with these:
  - the chip doesn't lock, and tapping it points the arrow at the console
  - the console from more than 10 studs away is rejected (exploit check:
    fire the prompt from far away via the command bar if it's reachable)
  - the alarm state
  - the cooldown chip, the prompt's "Steal in 42s", and STEAL READY!
  - all four scenes animate with your own avatar, on desktop and phone
- `luau-lsp analyze`: no new errors. Commit per phase, push, and add a section
  to PR #6's summary.
