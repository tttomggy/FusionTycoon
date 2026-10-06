# The 2nd floor (Rebirth 2)

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **2nd floor** (`PlotLayout.Floor2`, `FloorKit`, Rebirth 2 =
  `RebirthConfig.SecondFloorRebirths`): every lab builds a mezzanine over
  the back-left (deck top y 12 over the collector and the belt's end; the
  Fusion Machine, portal and odds board stay open) with pedestals 7–10
  (2 × 2), three columns, SmoothPlastic posts with Neon top rails round
  every edge but a front gap, and a ⬆ jump pad on the floor in front of
  the gap (SurfaceGui ring face, tag `FT_JumpPad`, world-space
  `LaunchVelocity`): `JumpPadController` launches the LOCAL character
  (not while ragdolled / seated, 0.8 s cooldown); jump off to come down.
  `PlotLayout.CheckFloor2` (at require and in `/selftest`): inside the
  walls, pedestals on the deck clear of rails, each other and the landing,
  the pad in front of the gap, columns / pad clear of every floor
  footprint, headroom over what's under it (belt, collector), the
  machine / portal / odds board never covered, `INSIDE_MAX_Y` and the
  shield fence (now 18 studs) above a character on the deck, so heists,
  LOCK and the eject loop cover it. Under Rebirth 2: dim rails and band
  (`FloorKit.SetLocked`), dim pedestals (attribute `FloorLocked`, owner
  label "REBIRTH 2"), no prompts, an owner-only "🔒 2ND FLOOR · Rebirth 2"
  chip. Rebirth panel: "Rebirth 2: unlocks the 2nd floor (+4 pedestals)
  and the 🔫 Laser Gun." (`RebirthConfig.GetUnlockLine`). Sim: Rebirth 3
  free 2:44:32 (was 2:45:59, −0.9%); cost growth unchanged.
