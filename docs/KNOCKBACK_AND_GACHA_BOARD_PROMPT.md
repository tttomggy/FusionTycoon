# Knockback that works, plus the Gacha card as a real board (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 10 lines or fewer.

---

Harris tested `d9e4aae` + `8cd0f40` on Oct 13 with 2 players.

- **Animations:** Harris says they're **good now**. Don't change the clips.
- **Knockback:** in the clip, `BONK!` pops and then Player2 barely moves.
  Hits "don't knock them or anything". `/selftest combat` says the same:
  - `FAIL combat launch: the Bat launches the target >= 10 studs in 0.6 s: 0.1 studs`
  - The Glove passed ≥ 15. That's probably only because the spin topples
    the target.
  - `physics: … target root network owner: Player2`, so this place uses
    classic client ownership, not Server Authority. Put that in
    `combat.md`'s Rig diagnosis.
- **Gacha card:**
  - It only appears when the camera is zoomed in close: `MaxDistance` is
    measured from the **camera**, and 26 studs is closer than a normal
    3rd-person camera sits.
  - Close up, the card is a **black empty box** running off the top of the
    screen. Only "$250 / pull" shows. The tiles never render, most likely
    because of the `CanvasGroup` inside a BillboardGui (the fader).
  - Harris: "need better design, looks plain."
- The E / R / ? button row works, but floats mid-screen.

## 1. Knockback: make the launch actually move them

**Likely cause:**
- `launch()` takes ownership and calls `humanoid:ChangeState(Physics)`
  **on the server**. A player's Humanoid state isn't the server's to set,
  so the Humanoid stays in Running.
- Its ground controller then brakes the horizontal velocity to almost
  nothing within a few frames.
- There's also an ownership-handoff race: the old owner's client can
  overwrite the velocity for a frame or two after `SetNetworkOwner(nil)`.

**Fix:**

- **Log first:** after a Bat hit, print the target root's horizontal speed
  on the server for 10 Heartbeats. Quote it before and after the fix.
- On the server, at launch:
  1. `humanoid.PlatformStand = true`. It replicates and turns the ground
     controller off. Keep the client's own `ChangeState(Physics)` as it is.
  2. Take ownership: `SetNetworkOwner(nil)` with `pcall`, as now.
  3. **Set** `AssemblyLinearVelocity = impulse` on every part, rather than
     an impulse.
  4. Re-assert it on the next 3 server Heartbeats, but only while the
     root's horizontal speed is still below 60% of the target. That
     covers the handoff race and never adds speed twice.
- **Get-up:** `PlatformStand = false`, ownership back to the player, then
  `GettingUp`. This must also happen on respawn and on leave mid-ragdoll,
  so no one is left platform-standing.
- Keep the client fallback only for when ownership can't be taken. It
  uses the same `PlatformStand` + velocity approach, on every part.
- **Selftest:** the launch checks need ≥ 12 studs for the Bat and ≥ 20 for
  the Glove, server-measured. Add "the target is standing (not
  PlatformStand) 0.5 s after `RagdollSeconds`, and the network owner is
  the player again".
- Then tune by eye in the 2-player test: the Bat throws the target about
  15–20 studs, and the Glove about 25–30 with a spin. Put the final
  numbers in `CombatConfig` with a comment.

## 2. Selftest: match the approved animations

Harris approved the look, so fix the checks, not the clips:

- **Melee and Peel hold:** drop the "forward ≥ 0.5" part, because the bat
  sits on the shoulder. The check is now: the hand is ≥ 1 stud from rest
  and the hold track is looping.
- **Swing peak:** needs ≥ 1.5 studs (today it's 1.85).
- **Visible:** needs ≥ 0.4 s (today it's 0.47 / 0.45).
- **Live fallback:** the forced "no id, not Studio" path still used the
  track (`track used true`). The test hook must also skip the Studio
  `RegisterKeyframeSequence` path. The check expects the C0 pose to run and
  no track.

## 3. Gacha: a physical display board, not a billboard

Replace the BillboardGui card, `CanvasGroup` included, with a **board in
the world**, like the Fusion Machine's odds board. That board already
reads well from across the lab, never clips the screen, and doesn't
depend on camera zoom.

**Geometry (server, `TycoonService.createGachaStation`):**

- A display board on two slim posts, on the far side of the Gacha Pad from
  where the player walks up. When you stand on the pad, the camera behind
  you looks straight at it over your head.
- About 10 × 7.5 studs, bottom edge at about 4.5 studs, tilted back about
  10°.
- Put every number in `PlotLayout.Gacha` and add its footprint to the
  assertion block, clear of the LOCK console, the walls and the walkway.
- Materials: SmoothPlastic, plus a Neon rim (thin bands only, per
  CLAUDE.md).
- Remove the old `GachaLabel` billboard. The board carries the title and
  the price.

**SurfaceGui (client, `GachaCardController` → rename it
`GachaBoardController`):**

- Build it for **every** plot's board:
  - your own: silhouettes from your Index;
  - others: no silhouettes, at that owner's odds from the pad attributes.
- 60 px/stud, `LightInfluence 0`, `MaxDistance` ≥ 80.
- **No CanvasGroup anywhere.** Fade nothing. The board is always there.

**Design: make it pop, and stop it looking plain.** The references are Pet
Sim 99's egg card and Bubble Gum Sim's egg card.

- **Frame:** a thick gold rim (the GACHA gold) with a soft inner glow.
- **Panel:** deep violet glass with a subtle diagonal stripe pattern, the
  same Fusion Lab look as the HUD panels.
- **Header banner:**
  - A gold gradient ribbon across the top with a capsule icon and
    "GACHA PAD" in the display font, white with the ink stroke.
  - On the right, the `🍀 Luck ×N` pill when luck is above 1, and the event
    chip during an event.
- **6 tiles (3 × 2), the main thing:**
  - Background: the tier's gradient, from the tier colour down to dark,
    with a white 2 px stroke and rounded corners.
  - A **spinning 3D orb** in a `ViewportFrame`. Use the tier's
    representative item, built by the same builder as the pedestal orbs
    (`PedestalVisuals`), slowly rotating. Animate it only while the board
    is within 60 studs of the camera.
  - The % is **huge**, about 0.7 studs tall: white with a thick stroke in
    the tier colour.
  - A tier-name ribbon along the bottom of the tile.
  - **Unfound tier:** the orb is a black silhouette (`ViewportFrame`
    `ImageColor3` black, plus a "?"), and the % is still shown.
  - **Secret tile:** an animated rainbow stroke and a sparkle.
- **Mutation strip:** pill chips in the mutation colours, e.g.
  `✨ Golden 6.9%`, plus event chips while an event runs.
- **Price:** a big gold pill under the tiles: `$285 / pull` · `×10 $3.5K`,
  or `FREE · 2 left`.
- **(i):** a round button in the header. A SurfaceGui button can be
  clicked when the board is on your own plot (`SurfaceGui.Adornee` +
  `Active`; set it up so it does). It opens the per-orb odds panel you
  already built, as a screen `UIKit.Modal`.
- **Readable:** the %s and tier names must read from the far side of the
  lab (about 40 studs) at 1366 × 768. Use `TextScaled` with
  `UITextSizeConstraint`s, not fixed small sizes.
- Keep the numbers from `FusionConfig.GetGachaOddsRows` at the server's
  luck, as now. The compliance rules from GACHA_CARD_PROMPT still hold:
  every outcome's % is visible before you pull, and silhouettes never hide
  a %.

**The button row (E Pull · R ×10 · ?):**

- Keep the custom prompt buttons, but draw them as a **BillboardGui with
  pixel size**, attached to the board's bottom edge, so they sit just
  under the board in the world instead of floating mid-screen.
- No CanvasGroup. `AlwaysOnTop = false`. Each button is ≥ 44 px on phone.

## Check

- `luau-lsp analyze` shows no new errors.
- **`/selftest combat` with 2 players:** quote the before/after speed
  logs. Both launch checks and the get-up check pass. No FAILs.
- **`/selftest gacha`:**
  - "board: 6 tiles, each `ViewportFrame` has an orb";
  - "board: % text ≥ 0.5 studs tall";
  - "board: no CanvasGroup under it";
  - "board: `MaxDistance` ≥ 80";
  - "board: footprint inside the plot and clear (PlotLayout assertions)";
  - "button row: on screen at the default camera while standing on the
    pad";
  - the existing odds / sum / silhouette checks.
- Give Harris this list:
  1. With 2 players: bat → Player2 flies about 15–20 studs; glove → about
     25–30 with a spin; Player2 stands up normally after.
  2. At normal camera zoom, walk into your lab: the gacha board is visible
     from the gate, colourful, the orbs spin, and the %s are readable.
     Standing on the pad, E / R / ? sit under the board.
  3. Phone emulator: the buttons can be tapped.
- Update `docs/systems/combat.md` (Rig diagnosis, knockback),
  `items-and-fusion.md` (gacha board) and UI_TEST.
- Say which branch you pushed to.
