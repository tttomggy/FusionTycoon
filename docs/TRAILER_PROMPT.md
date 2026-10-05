# Fusion Tycoon: Trailer director (build prompt for Claude Code)

Run `git pull` on `world-redesign` first. Commit per phase, then open a PR
into `main`. Don't merge it.

---

Read CLAUDE.md and follow it. Build a `/trailer` command that plays the same
~30-second cinematic every time. Harris records it with Win+Alt+R in the real
Roblox player at full-screen 1080p, and Claude edits it into the game's video
thumbnail.

## Video rules (Roblox video thumbnail policy: the trailer must pass)

- Real gameplay only, using the real game visuals.
- **Allowed:**
  - camera moves;
  - curated sequences;
  - in-game UI text;
  - the logo, which Claude adds in editing, not you.
- **Not allowed:**
  - graphics beyond what players see (no extra bloom, ColorCorrection or
    effects that the game doesn't have);
  - claims or offer text;
  - a fake UI.

## How it works

- **Who can run it:** admins only (`AdminConfig` admins plus the place owner),
  in Studio and in live games. A non-admin's `/trailer` does nothing.
  - The server checks the sender (the AdminService pattern) and replies with a
    new S→C remote, `TrailerStart`, to that admin only.
  - Every arg is whitelisted.
- **Client-only.** The trailer changes nothing on the server: no cash, items,
  events, saves, analytics or banners for other players. Everything it shows is
  built locally on the admin's client and destroyed at the end. That's what
  makes it safe to run in a live server. Build it as:
  - client-built orbs (`PedestalVisuals.BuildCarryOrb` / `.Apply` on local
    clones);
  - local NPC rigs (blocky R15 from a HumanoidDescription, Animator run and
    idle animations; poses through `Motor6D`/`AnimationConstraint.Transform`);
  - the event sky and FX: refactor EventController so its visuals can be
    started for an id **locally** (`EventController.PreviewLocal(id)` /
    `StopPreview()`), without touching the workspace attributes;
  - ResultController cards fed a fake local payload.
- **Clean frame.** Hide every ScreenGui and the CoreGui (except the cards a
  shot needs), hide your own character (`LocalTransparencyModifier`), and set
  the camera to `Scriptable`.
  - On end or `/trailer stop`, restore all of it exactly: the GUI enabled
    state, CoreGui, camera type, the character, and the Lighting baseline.
    Resetting your character mid-trailer stops it cleanly.
- **Camera.** Each shot is a list of keyframes `{ pos, lookAt, fov, t,
  easing }` in **plot-local space** (`PlotLayout`), so it works from any slot.
  Put them in `TrailerConfig.lua` (a shared config), never hard-coded in the
  controller.
  - Tween with `TweenService` on a CFrame value plus `RenderStepped`. Keep the
    motion slow and smooth: no snap cuts inside a shot.
  - Cuts between shots are a 0.25 s fade to black, using a full-screen Frame
    in its own ScreenGui with DisplayOrder max.
- **Commands:** `/trailer` (the whole thing), `/trailer <shot>` (one shot,
  for retakes), `/trailer stop`.
  - A 3-second "3 2 1" countdown plays before shot 1 so Harris can start
    recording. The countdown is not in the video: it ends on the black before
    shot 1.

## Shots (≈ 30 s total; tune the timings)

1. **Lab at night (4 s).** `PreviewLocal("Night")`. A slow push-in from the
   gate across a full lab: all six pedestals with glowing mutated orbs (a
   Rainbow Mythic, a Golden Legendary, a Diamond Epic and so on), the factory
   belt running, and the Fusion Machine glowing at the back.
2. **Pull (5 s).** The camera arcs round the Gacha Pad as a local NPC pulls
   it. The real pull VFX plays, then the big reveal card for a **Rainbow
   Legendary** through ResultController's normal card path.
3. **Fuse to Secret (7 s).** A low angle on the Fusion Machine. Two **Mythic**
   orbs float in and merge, then a **Secret** burst plays (the real fusion
   VFX), followed by the own-player "FUSION SUCCESS!" banner. End on a slow
   orbit round the Secret orb.
4. **Heist (7 s).** A masked red NPC thief grabs an orb from a neighbour's
   pedestal: the hold-E prompt fill shows. He runs out of the gate with the
   carry orb over his head, and a yellow/blue NPC owner chases him: "RUN!",
   then the catch. Camera: low tracking from the side, then a whip-pan to the
   owner.
5. **Void Moon (5 s).** `PreviewLocal("VoidMoon")`. Tilt up from the machine
   to the purple moon, then down to a **Void** orb revealing at the machine
   with the event-mutation card.
6. **Hold (2 s).** A wide hero shot of the lab with the Secret orb on a
   pedestal, held still. Claude adds the logo over it in editing.

Every number and name comes from the configs (tiers, mutations, colours), so
the trailer always matches the live game.

## Check

- **UI_TEST:** add a "Trailer" section:
  - run it twice in a row;
  - stop it mid-shot;
  - reset mid-shot;
  - run it in a 2-player server, where the other player must see nothing
    change;
  - confirm everything is restored afterwards.
- **CLAUDE.md:** add one line for `/trailer`, `TrailerConfig` and the
  `TrailerStart` remote.
- `luau-lsp analyze` reports no new errors, and the layout assertions pass.

**Report:** list the shot timings, any shot you had to simplify, and the
exact steps Harris follows to record:
1. Publish.
2. Join the live game on PC.
3. Go full screen (F11) at 1920×1080 with graphics quality at max.
4. Type `/trailer`.
5. Press Win+Alt+R during the countdown.
