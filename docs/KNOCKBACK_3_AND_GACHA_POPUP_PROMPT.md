# Knockback 3 (a body mover, measured on the target's screen) + Gacha pop-up card (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 10 lines or fewer.

---

Harris tested `1bde6e3` on Oct 13 with 2 players, both at Rebirth 3 (the
Studio start works).

- **Knockback still doesn't happen.** In the clip, Player1 bats and slaps
  Player2 at point-blank range. The hit flash plays on Player2, then Player2
  just stands there. `/selftest combat` now says
  `FAIL combat launch: the Bat launches the target >= 12 studs in 0.6 s (server-measured): 6.7 studs`.
  The run before that passed with 60 studs/s held flat for 10 Heartbeats.
  - That's the tell: a velocity that sits at exactly 60.0 for 10 frames
    is the **server reading back its own write**. The server-side numbers
    come and go between runs while nothing ever moves on the target's
    screen.
  - The `SetNetworkOwner(nil)` handoff on a player character isn't
    reliable here. The target's client keeps simulating its own character,
    and the server's velocity writes never reach what the target sees.
- **Gacha:** the board now draws properly; Harris likes the tiles. But he
  doesn't want a **board**. He wants the Pet Sim 99 / Bubble Gum Sim
  behaviour: **a card that pops up above the pad when you walk close.**
- The C0 live-fallback check says `shoulder: no Motor6D`. On that rig the
  shoulder is an AnimationConstraint, and moving its attachment doesn't
  move the hand.

## 1. Knockback: a server-made body mover, the standard Roblox pattern

Stop fighting over ownership. **Delete the `SetNetworkOwner` path, the
velocity writes and the 3-Heartbeat re-assert.** Instead:

- **Server, on a hit (`ragdoll`):**
  - Create a `LinearVelocity` on the target's `HumanoidRootPart`:
    - its own Attachment at the root's centre;
    - `RelativeTo = World`, `VelocityConstraintMode = Vector`;
    - `VectorVelocity` = the launch (flat direction × knockback +
      `UpwardKick`);
    - `MaxForce = math.huge`.
    - Name it `KnockbackMover`.
  - Destroy it after `CombatConfig.LaunchSeconds` = 0.2 s.
  - For the Glove spin, add an `AngularVelocity`
    (`MaxTorque = math.huge`) for the same 0.2 s.
  - Set `humanoid.PlatformStand = true` for `RagdollSeconds`, then back to
    false, as now.
  - **Why this works:** a constraint the server creates replicates to
    every client, and **whoever owns the assembly (the target's client)
    simulates it**. No ownership change is needed, and it works whatever
    the ownership.
- **Client (`onHitReceived`):** keep `ChangeState(Physics)`,
  `UnequipTools`, the prompts off, and `GettingUp` at the end. **Remove**
  every velocity/impulse write and the `ServerLaunch` branch. The mover
  does the launch.
- **Clean-up:** on get-up, respawn, leave and a second hit, destroy any
  `KnockbackMover` / spin mover left behind, and always reset
  `PlatformStand`. No stacking: a new hit replaces the old mover.
- **Ragdoll joints:** keep the BallSocket swap, but the mover goes on the
  root. If the limbs drag the root back (more than 40% speed lost in
  0.2 s), add the mover to `UpperTorso` too, not to every part.

**Measure on the target's screen, not on the server.** Rewrite the launch
selftest:

- The server asks **Player2's client** for its own root position just
  before the hit and 0.6 s after, through a SelfTest probe aimed at that
  player. The test fails if the second client doesn't answer.
- Needs: Bat ≥ 12 studs, Glove ≥ 20, as the **target client** measured
  it. Also print the server-side distance next to it, for comparison.
- **Get-up check:** 0.5 s after `RagdollSeconds`, on the target's client:
  standing (state not Physics), `PlatformStand` false, no `KnockbackMover`
  under the character.
- Run it before your change too, and quote both numbers. The client-side
  one should be near 0 today.

Then tune `CombatConfig` knockback values until the 2-player clip shows
the Bat throwing about 15–20 studs and the Glove about 25–30 with a spin.

## 2. Gacha: the pop-up card (no board)

**Remove the physical board:**
- the `GachaBoard` model and its posts;
- `PlotLayout.Gacha`'s board geometry, and its footprint from the
  assertion block.

**Keep the tile design exactly as it is now.** Move the same layout:

- gold rim and gold header ribbon;
- 3 × 2 tier tiles with spinning ViewportFrame orbs, the huge %, and the
  name ribbon;
- silhouettes;
- mutation chips;
- the price pill;
- (i).

Put it into a **BillboardGui** that pops up **above your own pad when your
character walks near it**.

This is the third try at this card. The first one failed for three
specific reasons, so avoid all three:

1. **Size it in studs, not pixels**, so it scales with zoom like a
   world object and never runs off the top of the screen.
   - Use `Size = UDim2.new(11, 0, 7.5, 0)`, i.e. 11 × 7.5 studs, with the
     inner layout in Scale or a `UIScale` from a 600 × 410 design canvas.
   - `StudsOffset` puts its bottom edge about 1.5 studs above your
     character's head while you stand on the pad. That's roughly 8 studs
     above the pad top. Tune it so the card never covers your character.
2. **Visibility follows the CHARACTER, not the camera.**
   - Each frame, measure the distance from your `HumanoidRootPart` to the
     pad.
   - Inside 16 studs it pops **in**: `Enabled = true`, then a `UIScale`
     from 0.6 to 1 over 0.2 s with Back-Out easing, like PS99.
   - Beyond 19 studs it pops **out**: 1 to 0.6 over 0.12 s, then
     `Enabled = false`.
   - The 3-stud gap stops flicker at the edge.
   - `MaxDistance` = 150, so the camera's zoom never hides it.
3. **No CanvasGroup anywhere.** Pop with a `UIScale` only.

**Other settings:**
- `AlwaysOnTop = false`, `LightInfluence = 0`, `ResetOnSpawn = false`.
- Only on your own pad.
- Spin the orbs only while the card is open.

**Far away (> 19 studs) and on other players' pads:** show the small
`GACHA` title and price pill billboard that was there before the card work.
Restore the server `GachaLabel` with no odds lines. PS99 does the same:
the egg's name and price far off, the card up close.

**Buttons:** the E Pull · R ×10 · ? row sits **inside the same
billboard**, under the price pill, and pops with it. Keep the custom
prompt handling, the ≥ 44 px tap targets, and `InputHoldBegin` / `End`.
**(i)** opens the per-orb panel as now; a BillboardGui with
`Active = true` is clickable.

**Selftest (`/selftest gacha`), all read from the instance tree:**

- Teleport your character next to the pad, wait 0.4 s, then check:
  - the card is `Enabled`;
  - its `UIScale` is 1;
  - all 6 tiles have `AbsoluteSize > 0` and `TextBounds.Y > 0` on their %;
  - each tile's ViewportFrame holds an orb;
  - the 3 buttons are each ≥ 44 px.
- Teleport 25 studs away: the card is not `Enabled`, and the small
  `GACHA` label shows.
- Teleport back: it pops in again.
- At 1366 × 768 and 844 × 390, with your character on the pad at the
  default camera, the card's whole screen rect is on screen. Project its
  four corners.
- Keep the odds / sum / silhouette / luck-pill checks.
- No `GachaBoard` in the workspace, and no CanvasGroup under the card.

## 3. C0 fallback on AnimationConstraint rigs

The fallback only matters on a live server with no animation ids, and
Harris will publish the ids before launch. So:

- When the shoulder has no Motor6D, the live-fallback check says
  `skipped: AnimationConstraint rig`, with a PASS.
- Add "publish the weapon animations (`/anim export` → Save to Roblox →
  `CombatConfig.AnimationIds`)" to the launch checklist in
  `docs/LAUNCH_1_PROMPT.md`, or wherever that list lives now.
- Leave the fallback code alone.

## Check

- `luau-lsp analyze` shows no new errors.
- **`/selftest combat` with 2 players:** quote the before and after
  numbers measured on the target client. The launch and get-up checks
  pass. No FAILs.
- **`/selftest gacha`:** no FAILs.
- Give Harris this list:
  1. With 2 players: Player1 bats Player2, and **on Player2's own screen**
     Player2 flies about 15–20 studs. The Glove throws about 25–30 with a
     spin. Player2 stands back up and walks normally.
  2. Walk toward your Gacha Pad: the card pops up above the pad at
     about 16 studs, at any camera zoom. Walk away: it pops down and the
     small GACHA price label shows.
  3. E / R / ? / (i) all work.
- Update `docs/systems/combat.md`, `items-and-fusion.md` and UI_TEST.
- Say which branch you pushed to.
