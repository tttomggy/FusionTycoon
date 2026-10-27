# Rival labs 2: look like a lab worth robbing, guards stay on their feet (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 4 lines, one per group: FIXED or WHY-NOT. Run the Luau parser and
`tools/theme_token_check.py` before pushing.

---

Harris's first Play with rival labs (top-down screenshot, 065216c): the
labs and guards spawn, but:

- **The rival labs look abandoned.** `BuildRivalPlot` builds the shell,
  wall strips, sign and pedestals only. Next to a player's lab (stations,
  Fusion Machine, factory line, glow) they read as empty plots with a few
  boxes. Nobody wants to rob an empty lab.
- **The guards look like they're lying on their side.** All three red rigs
  appear horizontal. (Harris will confirm with a close-up; fix it anyway.)

## 1. A rival lab looks like a real, rich lab

Reuse the real builders (no second copy of any geometry, PlotLayout stays
the source of truth), in **decoration mode**: models and visuals only, no
ProximityPrompts, no remotes, no owner-only labels, no cash.

- Fusion Machine (`FusionMachineService.Build`), the Gacha station and the
  Multiplier station (`createGachaStation` / `createMultiplierStation`),
  the factory line (`createFactoryLine`, its client animation running like
  a player's) and the rebirth portal. Add a `decorative: boolean` (or a nil
  player) path to each builder that skips prompts/handlers; don't fork them.
- Labels on those stations show the rival's name or nothing (no "$X / pull"
  prices, no player numbers).
- **All 4 rival pedestals always look full:** a stolen orb's pedestal shows
  the normal empty-cap state with a small `back in 1:12` countdown label
  (client-side from a `RespawnAt` attribute), never just a bare block.
- Orbs on rival pedestals use the exact player pedestal visuals (same size,
  glow, light caps, no Highlights), so they read from the street.
- Light budget: rivals add at most what one claimed player lab adds.

## 2. Guards stay upright

- On the guard's Humanoid: `SetStateEnabled` false for `FallingDown`,
  `Ragdoll`, `Physics` and `Seated`; `BreakJointsOnDeath = false`;
  `RequiresNeck = false`; set `HipHeight` from the rig (HumanoidDescription
  rigs can come in with a wrong one); root `Anchored = false`,
  `SetNetworkOwner(nil)` as now.
- The stun (`PlatformStand = true`, ~line 705) must always end with
  `PlatformStand = false` + `GettingUp`, including when the stun is
  interrupted (lab despawn, a second hit). Check every path.
- Self-heal: each guard tick, if the root's up-vector is more than 45° off
  vertical for > 1 s and the guard isn't stunned, stand it up
  (`ChangeState(GettingUp)`, and if still down after 1 s, pivot it upright
  at its position).
- Selftest: after spawn, after a chase across a speed belt, and after a
  stun, every guard's root up-vector is within 20° of vertical.

## 3. Readable from the street

- The guard's "Lab Guard" label: the rival's name instead (`Dr. Fizz`),
  with the rival accent, MaxDistance 60 (world-label rules).
- The gate sign must stand upright facing the street like a player's
  (verify the sign's CFrame against a player plot's in the selftest: same
  orientation relative to the slot).

## 4. Selftest

- A rival lab has a Fusion Machine, Gacha station, Multiplier station,
  factory line and portal models, and **zero** ProximityPrompts outside its
  4 steal prompts.
- The guard-upright checks from group 2, the sign orientation from group 3.
