# Fusion Tycoon — Polish 1 (build prompt for Claude Code)

Paste everything below into Claude Code, opened on the `world-redesign` branch.

---

This pass fixes what the first world playtest showed and adds speed belts to the street. The design is fixed. The canvas boards "Polish · station pads v2…" and "Polish · speed belts" show it, and every number you need is in this file. Don't restyle anything this file doesn't mention.

Read `CLAUDE.md` first and follow it. That covers the service lifecycle, `RemoteEvents.lua` as the only place remotes are made, every position in `PlotLayout`, every colour in `UITheme`, and `luau-lsp analyze` as the check. After each phase, run the type check, fix every new error in files you touched, and commit the phase on its own.

## What the playtest showed

1. **Pressing E at an empty pedestal does nothing.** No prompt even appears when standing right next to one, even with 70+ items owned.
2. **The station pads and the machine floor look like pizza.** They're big Neon cylinders, and Roblox draws a cylinder's top as a fan of triangles. Under Realistic lighting and bloom, each triangle catches the light differently.
3. **The whole lab is purple soup.** Neon pedestal caps, the Neon collector strip and the thick wall strips all bloom, and the purple ambient tints everything else.
4. **Empty pedestal labels are huge** and float 9 studs up, so four of them clutter the middle of the lab and overlap the odds board.
5. **Getting around the 12-lab street is slow.** The player wants moving walkways like other popular games.

---

## Phase 1 — Fix the pedestal prompt (bug)

**Likely cause:** `TycoonService.createPedestals` parents the `Pedestals` folder to the plot **before** creating the pedestals inside it. `ItemController.Init` waits for the folder, then immediately loops over `GetChildren()` once. If the folder replicates before its children (likely, since each pedestal brings a cap, label and prompt), some or all pedestals are never wired. Their prompts then stay at the server default `Enabled = false` forever.

Confirm this before you fix it: add a temporary print of how many pedestals ItemController wired, and note the result in your summary. Then remove the print.

**Fix: remove the race entirely. Don't just reorder lines.**
- **Server:** in `createPedestals`, build the folder and all pedestals **first**, and set `folder.Parent = plot` **last**.
- **Server:** pedestal `DisplayPrompt`s start `Enabled = true`. Give each the attribute `OwnerOnly = true`. Its `ActionText` is "Display" and its `ObjectText` is "Pedestal N".
- **Client, `ItemController`:**
  - Stop wiring each prompt's `Triggered` one by one. Handle `ProximityPromptService.PromptTriggered` once:
    - Act only if `prompt.Name == "DisplayPrompt"`.
    - Its parent must have a numeric `PedestalIndex`.
    - The prompt must be inside the local player's own plot. Check with `IsDescendantOf` on `PlayerTycoons/Tycoon_<UserId>`.
    - Then call `onPedestalTriggered(index)`.
  - Set the prompt's text when it appears: handle `ProximityPromptService.PromptShown` and set `ActionText` to "Remove" or "Display" based on `TycoonController.GetPedestalDisplay(index)`.
  - Delete `waitForNamedChild`, the per-pedestal loop and `updateAllPrompts`. Set `pedestalsReady` from the plot's `Claimed` attribute (watch `GetAttributeChangedSignal`) rather than from finding the folder.
  - With no displayable items, the picker opens and shows its existing "Pull at the Gacha Pad" empty state. **A prompt must never do nothing.**
- **Client, `WorldLabelController`:** the server can't hide prompts per player, so the client does it. For every `ProximityPrompt` with `OwnerOnly = true` that is **not** inside the local player's plot, set `Enabled = false` locally. Catch prompts that arrive later via `DescendantAdded` on the `PlayerTycoons` folder.
- **Audit every other client prompt hookup** (stations, Fusion Machine, Fuse All, claim) for the same "wait for a container, then loop its children once" pattern, and fix any you find the same way. List what you checked in your summary.

## Phase 2 — Station pads v2 and the machine floor (no Neon circles)

Nothing flat and circular may be Neon anymore.

**`StationKit`**
- **Delete `Glow`**, the translucent Neon disc.
- **`Rim`** becomes a thin band on the pad's side only:
  - Diameter = pad diameter + 0.1.
  - Height **0.15**.
  - Centred 0.35 below the pad top.
  - Neon, in the accent colour.
- **`Pad`** stays SmoothPlastic Structure.
- **New `Face` part on top of the pad:**
  - A square part, pad diameter × 0.05 × pad diameter, Transparency 1, CanCollide false, CanQuery false, CanTouch false.
  - Its bottom sits 0.02 above the pad top.
  - Yaw it so text on its Top face reads upright for someone walking in from the plot gate (+Z).
- **A `SurfaceGui` on Face's Top**, with PixelsPerStud 50, LightInfluence 0, Brightness 1.6 and `SizingMode = PixelsPerStud`. It contains:
  - **Ring:** a circle Frame (UICorner scale 0.5) filling the gui, with a transparent background and a UIStroke of 12 px in the accent colour.
  - **Inner glow:** a circle Frame inset 12% on every side. Its fill is the accent colour, and a UIGradient fades its transparency from 0.72 at the centre to 0.94 at the edge. UIGradient can't do radial, so fake it with two stacked circles: an inner one at 0.75 transparency and 55% size, and an outer one at 0.92. That's acceptable.
  - **Word:** centred, Display font, TextScaled, white with an Ink UIStroke 3, about 38% of the face height. Gacha "PULL", Multiplier "BOOST", Dropper 2 "BUY", Claim "CLAIM".
- **The PointLight moves to Face:** accent colour, Brightness 1.2, Range 9.
- **After the plot is claimed,** the claim station's Ring and Word turn the Disabled colour, the Word reads "YOURS", and its light is removed.

**Fusion Machine** (`FusionMachineService`)
- **Delete `FloorGlow`.** Put a Face plus SurfaceGui on the Base top instead, built the same way. Use AccentViolet and no Word, and make it 10 studs across.
- **The machine `Rim`** gets the same treatment: height 0.15, diameter = base + 0.1, Neon, on the side only.

Put every new number in `PlotLayout.Station` / `PlotLayout.Machine`, and update the overlap assertions if any footprint changed.

## Phase 3 — Turn down the purple

- **Pedestal cap**
  - `Cap` is now SmoothPlastic. It's StructureLight when empty and the tier colour when filled, with **no Neon**.
  - Add a `CapLip` under it: (cap size + 0.2) × 0.12 × (cap size + 0.2). It's Neon in the tier colour when filled, and hidden (Transparency 1) when empty.
  - The orb's PointLight range goes down to 6 + 1.5 × tier rank.
- **Collector**
  - The strip is SmoothPlastic AccentGold, not Neon.
  - Add two Neon edge strips, 18 × 0.12 × 0.3, along its long sides.
- **Wall strips** go from 1 × 0.25 to **0.35 wide × 0.12 tall**.
- **UITheme.World**
  - Floor becomes `#3A3668` (a little lighter, so the floor isn't a black hole).
  - Walkway becomes `#4A4580`.
  - Grass becomes `#5E9C63`. The playtest showed it reading as dark water.
- **LightingService**
  - Ambient (58, 54, 82) and OutdoorAmbient (118, 112, 140).
  - ColorShift_Top (255, 200, 150).
  - Bloom: Intensity 0.35, Size 20, Threshold 2.
  - Everything else stays as it is.

## Phase 4 — Labels

**Empty pedestal label** (`BillboardKit`)
- Replace it with a small pill, sized in studs: **3.6 × 1.1**, StudsOffset (0, 5, 0) above the pedestal's bottom.
- Contents: a circled "+" (Display font, Muted, Ink stroke 2) followed by "EMPTY" (Display font, Muted).
- Fill is Panel at 0.15 transparency, with a Faint stroke of 3 and a full-round corner.
- **No** "E to display an item" line.
- MaxDistance 20. Still owner-only.

**Filled pedestal label** stays as it is, but its StudsOffset y becomes 8.5.

## Phase 5 — Speed belts

New module `src/ReplicatedStorage/Shared/Config/StreetLayout.lua`. Move `STREET_*` and `LANE_DASH_*` there from PlotLayout, and **delete the lane dashes**: the belts replace the centre line.

**Layout** (all centred on the street's long axis, which is world X)

| Part | Size (X × Y × Z) | Centre z | Notes |
|---|---|---|---|
| `EastBelt` | (street length − 16) × 0.3 × 7 | −4.5 | moves +X |
| `WestBelt` | same | +4.5 | moves −X |
| `Median` | (street length − 16) × 0.5 × 2 | 0 | StructureLight, SmoothPlastic, CanCollide true |
| `EastRail` | (street length − 16) × 0.12 × 0.3 | −8.15 | Neon AccentGreen, on the belt's outer edge |
| `WestRail` | same | +8.15 | Neon `#4FB3FF` (add it to UITheme.World as `AccentBlue`) |

- Belt tops sit **0.3 above the street top**. Characters step up that height automatically.
- Belts are colour `#1B1834` (add it as `UITheme.World.Belt`), SmoothPlastic, Anchored, CanCollide true.
- **Movement:** set each belt's `AssemblyLinearVelocity` to its direction × `StreetLayout.BELT_SPEED` (**28**). Re-set it once a second from WorldService in case anything resets it. Anchored parts with a velocity carry anything standing on them; that's the standard Roblox conveyor.
- **End caps:** at both ends of each belt, a Cylinder part rotated so its axis runs along Z. It's 7 long, 0.6 in diameter and StructureLight colour, and it reads as a roller.
- **Gacha cash balls and dropped items must not ride the belts.** Put the belts in the `PlotEnvironment` collision group only if that doesn't stop characters. Otherwise give them their own group that doesn't collide with `CashParts`.

**Chevrons** (client, new `BeltController`)
- For each belt, create chevrons every **10 studs**, client-side only.
- Each chevron is two Neon bars, 1.8 × 0.05 × 0.22. The bars are angled ±45° to make a ">" pointing in the belt's direction, and centred on the belt, 0.03 above its top.
- They're in the rail's colour, with CanCollide, CanQuery and CanTouch all false. Parent them to a client folder in Workspace.
- Every frame, move every chevron along its belt by `BELT_SPEED × dt`, wrapping back to the start at the end. Use `workspace:BulkMoveTo` with `Enum.BulkMoveMode.FireCFrameChanged` off. There are about 100 chevrons in total, which is fine.
- Skip updating a lane's chevrons when the camera is more than 260 studs from the street centre.

**Acceptance:** standing on the east belt with no input carries you toward +X at about 28 studs/s. Walking with the flow is about 44 studs/s.

## Acceptance check (do all of these before saying you're done)

1. `luau-lsp analyze`: no new errors.
2. `grep` finds no `Enum.Material.Neon` on any part whose shape is `Cylinder` and whose Y size is under 0.5 (that's the "flat Neon circle" rule). List any remaining Neon cylinders and say why each is OK.
3. The `PlotLayout` and `StreetLayout` assertions pass at require time. Add a check that the belts plus median (16 wide) fit inside the street (36) with at least 8 studs of plain street on each side.
4. Add to `docs/UI_TEST.md`:
   - E at an empty pedestal opens the picker, even with 0 items, and shows the empty state.
   - In a 2-player test, you can't see or trigger the other player's pedestal prompts.
   - The pads show a clean ring and word with no slices.
   - Riding each belt end to end works, and cash balls never travel on a belt.
5. Commit per phase, push `world-redesign`, and post a summary comment on PR #4. Include the Phase 1 wiring print result.
