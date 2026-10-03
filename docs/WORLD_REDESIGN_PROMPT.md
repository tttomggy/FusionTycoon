# Fusion Tycoon — World Redesign (build prompt for Claude Code)

Paste everything below into Claude Code, opened on the `claude/upbeat-tesla-bfro6p` branch (the UI redesign). Create a new branch `world-redesign` from it first.

---

You are rebuilding the 3D world of this Roblox game to a finished design. The design is fixed: every position, size, colour and material you need is in this file. Don't restyle or invent; where something isn't specified, keep it simple and say so in your final summary. Game logic and economy numbers don't change unless a phase says so.

Read `CLAUDE.md` first and follow it. That means: the service lifecycle rules, `RemoteEvents.lua` as the only place remotes are made, server authority, `PlayerDataService.SyncTycoon` for syncing, all UI colours from `UITheme`, and `luau-lsp analyze` (not `rojo build`) as the check that code is valid.

After each phase:
- Run the type check and fix every new error in files you touched.
- Commit that phase on its own.

## What's wrong today (from the playtest)

- Each plot is a 107-stud-long row of small dark tiles on a white void.
- Pads are unlabelled until you're 26 studs away.
- Pedestals look empty even when an item is on them.
- The Fusion Machine is a giant purple rock slab the camera ends up inside.
- The plot sign is a fixed-pixel billboard that fills the screen up close.
- Bloom and haze wash everything out.
- Fusing 40 Commons takes 20 separate presses.

## Coordinate system (read this first)

Every plot is built in **plot-local space**:
- The origin is `PlotOrigin`, moved to the **centre of the plot** at floor-top height (y = 0).
- **+X** is the plot's right side and **+Z** is the front, where the gate is.
- All world positions are `PlotOrigin.CFrame:PointToWorldSpace(localPos)`. All facings are relative to `PlotOrigin.CFrame`.

Put every number below into `PlotLayout.lua` as named constants. Delete the old row constants (`GACHA_PAD_ROW_OFFSET_STUDS`, the `PEDESTAL_SHOWCASE_*` ones, `GetFloorRow*`, `PLOT_SIGN_*`, `MULTIPLIER_PAD_*` in TycoonService) and their comments. **No position may be hard-coded in a service.**

`TycoonTemplate.rbxm` still provides `Floor`, `Dropper1`, `ClaimButton`, `PlotOrigin` and `SpawnLocation`. Reposition, resize and restyle them in code as specified; build everything else in code.

### Materials and colours

- Every solid part is **SmoothPlastic**. Accents are **Neon**. No Basalt, Slate, Metal or Plastic anywhere.
- Add the world colours to `UITheme`, in a new `World` table, and read them from there:

| Token | Hex | Used for |
|---|---|---|
| Grass | `#4E7F5E` | ground (Grass material is the one exception) |
| Street | `#34305E` | street |
| Floor | `#2B2752` | plot floor |
| Walkway | `#3A3566` | walkway inlay |
| Structure | `#221E42` | walls, pads, pedestal columns, dropper bodies, machine platform |
| StructureLight | `#2D2856` | pylons, posts, locked/unclaimed trim |
| AccentViolet | `#8B5CFF` | wall strips, machine rim, multiplier |
| AccentGreen | `#3BEB7E` | claim, droppers, Dropper 2 |
| AccentGold | `#FFBE28` | gacha, collector |
| Unclaimed | `#3A3560` | wall strip before claiming |

Tier colours come from `FusionConfig.TierAccentColors` as today.

---

## Phase 1 — Plot layout (the big one)

Build each plot to this plan. The canvas board "World · plot plan" shows it. All sizes are in studs.

| Element | Local position (x, z) | Size / shape | Notes |
|---|---|---|---|
| Floor | (0, 0), top at y 0 | 64 × 1 × 64 | resize/recentre the template Floor; colour Floor |
| Walkway inlay | x 0, z from −10 to +32 | 8 wide, 0.05 thick, top flush +0.02 | Walkway colour, CanCollide false |
| Rim walls | along all 4 edges, inside the floor | 1 thick × 1.5 tall | Structure colour; front wall has a 14-wide gap, x −7 to +7 |
| Wall strip | on top of every wall | 0.25 tall × 1 wide, Neon | AccentViolet when claimed, Unclaimed before |
| Gate ramp | outside the gap, z +32 to +35 | WedgePart 14 wide, 1 tall, 3 long | Structure; rises from street level to the floor |
| Claim station | (0, +24) | station pad (Phase 2), green | moves `ClaimButton`; see Phase 2 |
| Dropper 1 | (−25, +8) | dropper (Phase 3) | template `Dropper1`, faces +X |
| Dropper 2 slot | (−25, +20) | ghost + green station | becomes Dropper 2 when bought |
| Collector | (−16, +14) | 6 × 0.4 × 18 strip, Neon AccentGold, top at y 0.2 | replaces the old 6×6 square |
| Gacha station | (+20, +22) | station pad, gold | |
| Multiplier station | (+20, +8) | station pad, violet | |
| Pedestals 1–4 | z −2; x −17, −6, +6, +17 | pedestal (Phase 4) | face +Z (the gate); clear of the walkway |
| Fusion Machine | (0, −19) | machine (Phase 5) | |
| Odds board | (+13, −19) | board on a post (Phase 5) | rotated to face the gate, yawed 30° toward the walkway |
| Plot sign gate | posts at (±9, +32) | Phase 6 | the board spans the gate |
| SpawnLocation | (0, +40) | 6 × 1 × 6, Transparency 1, no decal | on the street in front of the gate |
| Generator bays | (±24, −24) | **leave empty** | reserved for a later feature; put nothing there |

**Spawning**
- Set `player.RespawnLocation` to the player's own plot SpawnLocation.
- On plot creation, if the character already exists, `PivotTo` it there.
- Leave the plot SpawnLocations enabled. RespawnLocation decides where each player spawns.

**Prompt ranges** (keep them short so the right prompt shows):
- Station prompts: `MaxActivationDistance = 7`.
- Pedestal prompts: 6.
- Machine prompts: 10 (Phase 5).
- All of them: `RequiresLineOfSight = false` and `Exclusivity = OnePerButton` (the default), so where ranges overlap only the nearest E prompt shows.

Remove everything the new layout replaces:
- The connector walkway.
- The claim pod riser and its orb.
- PadStyler's floating orbs on pads.
- The old 4×4 pads.
- The old plot sign billboard.

Keep `PadStyler.lua` only if something still uses it; otherwise delete it and remove its entry from CLAUDE.md's known-errors list.

## Phase 2 — Station pads

Create `src/ReplicatedStorage/Shared/Modules/StationKit.lua` with `StationKit.Build(originCFrame, localPos, accent: Color3, hologram: "Capsule" | "Chevrons" | "Arrow" | "Ghost", parent): Model`. A station Model contains:

**Parts**
- `Pad`: cylinder, 8 diameter × 1 tall, Structure colour, top at y 1.
  - This is the part that holds the ProximityPrompt and the label.
  - For the claim station, `ClaimButton` becomes the Pad.
- `Rim`: cylinder, 8.4 diameter × 0.6, Neon in the accent colour, centred 0.3 below the Pad top. It shows as a glowing ring around the pad.
- `Glow`: cylinder, 5 diameter × 0.05, Neon accent at Transparency 0.55, sitting on top of the pad.
- A `PointLight` on the Glow: accent colour, Brightness 1.5, Range 10.

**Hologram** (all parts anchored, CanCollide false, CanQuery false; tag `FT_Hover`, Phase 7):
- **Capsule** (gacha): two half-spheres stacked, making a 2.6-diameter ball at y 4.5. The top half is gold Neon, the bottom half white `#F4F1FF` SmoothPlastic. Use two Ball parts clipped by a thin Structure-coloured band cylinder at the equator, which is visually enough. Spin 60°/s, bob 0.3 every 2 s.
- **Chevrons** (multiplier): two up-chevrons stacked (each made of two WedgeParts, 3 wide × 1.2 tall), violet Neon, at y 4 and 5. Every 1.2 s they rise 1 stud and snap back.
- **Arrow** (claim): a down-pointing arrow (WedgeParts) in green Neon at y 5, bobbing 0.5 every 1.2 s. Remove the arrow once the plot is claimed. The station then stays as a plain green pad that does nothing.
- **Ghost** (Dropper 2 slot): a copy of the dropper model (Phase 3), every part ForceField material, green, Transparency 0.5. When Dropper 2 is bought, replace the ghost with the real dropper and remove the station.

**Labels**
- Every station keeps its existing BillboardKit pad label, now resized (Phase 6). Labels sit at StudsOffset (0, 8, 0).
- Station text stays exactly as today: GACHA / price pill / odds line, MULTIPLIER / "x2 → x2.5" / "$150K · press E", DROPPER 2 / $60 / "Doubles your drops", and CLAIM.

## Phase 3 — Droppers and the collector

The dropper model (Dropper 1 reuses the template part as `Body`; Dropper 2 is built):
- `Body`: 4 × 6 × 4, Structure colour, bottom at y 0.
- `Hopper`: a 5 × 2 × 5 trapezoid on top, made of 4 WedgeParts, Structure. Add a 0.3-tall green Neon lip around its top edge.
- `Belt`: a 0.3-tall green Neon band around the Body at y 3.
- `Spout`: a 1.4 × 1.4 × 1.4 block, StructureLight colour, on the Body's +X face at y 4.5.
- Spawn cash balls at the Spout's outer face, moving +X at the current speed. Balls are 1.2-diameter green Neon spheres.

Delete the per-drop pop's sparkle size scaling if it makes the balls hard to see; the pop sound stays.

The collector is now the 6 × 0.4 × 18 gold strip from the plan. Cash balls from both droppers roll onto it. The `+$X` cash pop from the UI redesign stays and should appear over the strip.

## Phase 4 — Pedestals that actually show the item

The part named `Pedestal<i>` stays the BasePart that ItemService, PedestalVisuals and BillboardKit already use. Restyle and add to it:

**Pedestal parts**
- `Pedestal<i>`: 3.2 × 3.5 × 3.2 column, Structure colour, bottom at y 0.
- `Cap`: a 3.6 × 0.4 × 3.6 plate on top.
  - Empty: StructureLight colour.
  - Filled: Neon in the item's tier colour.
- `Orb`, created in `PedestalVisuals.Apply` and destroyed in `PedestalVisuals.Clear`:
  - A Ball whose diameter depends on the tier: Common 1.6, Rare 1.9, Epic 2.2, Legendary 2.6, Mythic 3.0. Its centre is at y 5.8 above the pedestal's bottom.
  - Material Glass, tier colour, Transparency 0.15.
  - Add an inner Neon ball, 65% of the size, in the tier colour.
  - Add a PointLight in the tier colour (Range 8 + 2 × tier rank, Brightness 2).
  - Tag `FT_Hover`: spin 45°/s, bob 0.25 every 2.4 s.
- The existing per-tier effects (glow, particles, rotating ring, beam) still apply. Re-anchor them to the Orb where that makes sense: particles from the Orb, beam from the Orb upward. The rotating ring stays at the cap.

**Pedestal label**: StudsOffset (0, 9, 0) above the pedestal's bottom, so it sits above the orb. Everyone sees filled labels (MaxDistance 70); empty labels stay owner-only.

## Phase 5 — Fusion Machine

Rewrite `FusionMachineService.Build(originCFrame, localPos, parent)` to this design.

**Parts**
- `Base`: cylinder platform, 18 diameter × 1.2 tall, Structure colour, bottom at y 0.
- `Rim`: cylinder, 18.6 diameter × 0.4, AccentViolet Neon, centred 0.2 below the Base top.
- Four `Pylon`s, each 1 × 9 × 1, StructureLight colour, at radius 6 and angles 45°, 135°, 225° and 315°. Each leans 8° toward the centre. Give each one a 0.25-wide AccentViolet Neon strip on its inward face.
- `Core`: a 4-diameter Neon ball, AccentViolet, centred at y 9.5. Keep the name. RevealEffects tweens its Size.
- `Ring`: the existing spinning ring, centred on the Core. Keep the name and its orbit sparkles.
- `FloorGlow`: a 6-diameter Neon disc at Transparency 0.6 on the Base top.

**Prompts**
- Add `PromptAnchor`: a 1 × 1 × 1 part, Transparency 1, CanCollide false, at the platform centre, y 3.
- Move `FusePrompt` onto it (MaxActivationDistance 10). Update `FusionController` to find it there instead of on `Core`.

**Odds board**
- A real board, not a billboard: a `Post` (0.6 × 6 × 0.6, StructureLight) and a `Board` (7 × 5 × 0.4, Structure) at the top of the post.
- Put a `SurfaceGui` on the Board's front face (PixelsPerStud 40, LightInfluence 0) showing the current odds-board content. Reuse BillboardKit's odds rows, laid out inside the SurfaceGui.
- Position and rotation as in the plan table.

Delete the old Basalt base, the connector walkway, and anything that made the machine a slab.

## Phase 6 — Plot sign gate and label sizing

**Plot sign gate**
- Two `Post`s, 1 × 14 × 1, StructureLight colour, at (±9, +32), bottom at y 0.
- `SignBoard`: 20 × 4.5 × 0.8, Structure colour, centred at (0, 14.25, +32).
- A `SignBorder` behind the board: 20.6 × 5.1 × 0.6, colour Ink `#0B0A1A`.
- A 20 × 0.3 × 0.9 AccentViolet Neon strip under the board.
- SurfaceGuis on **both** the Front and Back faces of the board (PixelsPerStud 40, LightInfluence 0) showing:
  - The background: a Violet gradient, the same as the UI button gradient.
  - "<DISPLAYNAME>'S LAB": Display font, white, with a UIStroke.
  - "$4.36K/s · best: Legendary": Body font, `#EDE3FF`.
  - Before the plot is claimed: "FREE LAB" and "Step on the green pad".
- Updated every 5 s by the server, as today.

**Billboard sizing (fixes "huge up close")**
- Change BillboardKit so every BillboardGui is sized **in studs** with `UDim2.fromScale(w, h)`:
  - Pad labels: 9 × 3.4.
  - Pedestal labels: 6.5 × 2.6.
  - The goal marker: Phase 9.
- Rebuild their contents with scale-based sizes and `TextScaled = true`, each with a `UITextSizeConstraint` (MaxTextSize 64), so they shrink with distance like real signs.
- MaxDistance values:
  - Pads: 90.
  - Filled pedestals: 70.
  - Empty pedestals: 25.
- Keep `AlwaysOnTop = false` and keep the owner-only logic.

## Phase 7 — Hover animation (client)

New `WorldAnimationController`. Every frame, it animates anchored parts tagged `FT_Hover` (CollectionService), using these attributes:
- `SpinDegPerSec`: number.
- `BobStuds`: number.
- `BobPeriod`: number.
- `Mode`: `"Bob"` or `"Rise"`. Rise moves up by BobStuds over the period, then snaps back; it's for the chevrons.

How it works:
- Store each part's base CFrame when it's first seen (handle `GetInstanceAddedSignal` and `GetInstanceRemovedSignal`), and set `CFrame` locally every frame.
- Only animate parts within 150 studs of the camera.
- A hologram made of several parts moves as one group: tag the group's Model instead and use `PivotTo`.

This is client-side only, so other players see it smoothly and the server never tweens.

## Phase 8 — World, street and lighting

New `WorldService` builds this once at server start.

**Plot slots**
- `MAX_PLOT_SLOTS` becomes **12**. Tell the human in your summary to set the place's Max Players to 12 in Game Settings.
- Slot `i` (1-based):
  - column `c = (i - 1) // 2`, row `r = (i - 1) % 2`
  - plot centre x = `(c - 2.5) * 80`
  - row 0: z = −50, facing +Z
  - row 1: z = +50, rotated 180° about Y, so its gate also faces the street
- Put this in `PlotLayout.GetSlotCFrame(i)` and use it in `createPlotForPlayer` instead of the current single row.

**Ground and street**
- `Ground`: 900 × 1 × 600, Grass material, Grass colour, top at y −1. The plot floors sit 1 stud above the grass, and the gate ramp covers the step.
- `Street`: 520 × 0.1 × 36, centred at z 0, top at y −0.95, Street colour.
- `LaneDashes`: a row of 8 × 0.05 × 0.6 AccentViolet Neon dashes, Transparency 0.45, every 16 studs along the street's centre line.
- Destroy `Workspace.Baseplate` at runtime if it exists. Also tell the human to delete it in Studio.

**Empty slots**
- For every slot with no player, build a placeholder foundation:
  - The 64 × 1 × 64 floor.
  - The walls with the Unclaimed strip.
  - The sign gate reading "FREE LAB".
- Hide it (or destroy and rebuild it) when a player takes that slot; show it again when they leave.

**Lighting**
Rewrite `LightingService` to set exactly these values. Create `Atmosphere`, `BloomEffect`, `ColorCorrectionEffect` and `SunRaysEffect` under Lighting if they're missing, and remove any other post effects.

- **Lighting**
  - ClockTime 17.2, GeographicLatitude 25, Brightness 2.4.
  - Ambient (70, 62, 110), OutdoorAmbient (120, 110, 160).
  - ColorShift_Top (255, 180, 120), ColorShift_Bottom (60, 40, 100).
  - EnvironmentDiffuseScale 0.5, EnvironmentSpecularScale 0.4, GlobalShadows true.
- **Atmosphere**
  - Density 0.28, Offset 0.25, Glare 0.15, Haze 1.
  - Color (190, 170, 255), Decay (90, 70, 150).
- **Bloom**: Intensity 0.7, Size 28, Threshold 1.4. With this threshold only Neon blooms.
- **ColorCorrection**: Brightness 0.02, Contrast 0.12, Saturation 0.12, TintColor (255, 248, 255).
- **SunRays**: Intensity 0.06, Spread 0.6.
- `Lighting.Technology` can't be set from a script. Tell the human to set it to **Future** in Studio.
- Replace the old comments in LightingService with one short header listing the mood.

## Phase 9 — Goal marker

Add a `Target` field to each goal in `GoalConfig`. A world target is the name of a part or model inside the player's own plot; a UI target is prefixed `ui:`.

| Goal Id | Target |
|---|---|
| claim_base | `ClaimStation` |
| buy_dropper2 | `Dropper2Station` |
| buy_basic_generator | `ui:Upgrades` |
| gacha_pull | `GachaStation` |
| display_item | `FirstEmptyPedestal` (special: resolve to the lowest-index empty pedestal) |
| first_fusion, own_rare, own_epic, own_legendary, own_mythic | `FusionMachine` |
| upgrade_multiplier, multiplier_x3 | `MultiplierStation` |
| unlock_ember_forge | `ui:Upgrades` |

New `GoalMarkerController` (client) shows a marker on the current goal's target.

**World target**
- A BillboardGui on the target with AlwaysOnTop **true** (this one should be seen through walls) and Size `fromOffset(170, 80)`, so it keeps a constant screen size; it's a guide, not a sign.
- StudsOffset 3 studs above the target's top.
- Contents:
  - A Gold-gradient pill with the goal text in caps, e.g. "BUY DROPPER 2" (Display 20, text `#3B2300`, Ink stroke 3).
  - A gold down-triangle under it.
  - A live distance line, "24 studs", in Body 13, `#FFD566`.
- The marker bobs 6 px every 1 s.
- Hide it when the player is within 8 studs of the target.
- Add a floor ring at the target: a Neon gold cylinder, 0.1 tall, whose diameter is the target's footprint + 2. It pulses transparency 0.2 ↔ 0.7 every 1.2 s. It's client-only.

**UI target**
- Give the named HUD button a pulsing 4 px Gold UIStroke until the goal changes.

Update the marker on every goal change. Remove it after the last goal.

## Phase 10 — Fuse All

**Config**: in `FusionConfig`, add `FuseAllMaxTier = "Epic"`. Fuse All fuses Common, Rare and Epic pairs only, never Legendary: a failed Legendary fusion costs a Legendary, so that stays a manual choice.

**Server** (`FusionService`):
- Refactor the single-fusion body into a local `fuseOnce(player, itemA, itemB)`. It does the roll, the removal, the add and the `TotalFusions` increment, and returns `(upgraded, newEntry)` without firing remotes.
- Rebuild the existing single-fusion handler on top of it. Its behaviour must not change.
- Add remotes `RequestFuseAll` (client → server) and `FuseAllResult` (server → client).
- Handler:
  - 3 s cooldown.
  - Loop: find the lowest tier ≤ `FuseAllMaxTier` that has ≥ 2 items not on a pedestal; fuse the first two; repeat. This cascades: new Rares can pair again.
  - Stop when no pair is left or after 500 fusions.
  - Then send one `SyncInventory` and one `SyncTycoon`, and fire `FuseAllResult`:
    ```
    {Count, Upgraded,
     Gained: {[tier]: n},
     Consumed: {[tier]: n},
     Best: InventoryItem?}
    ```
    `Best` is the highest-tier item created.
  - If `Count == 0`, fire `{Count = 0}`.
- Server-wide announcement: only for the single best result, and only if it's Legendary or higher.

**Machine prompts** (on `PromptAnchor`):
- `FusePrompt`: as today, key E, tap.
- `FuseAllPrompt`:
  - Key F (gamepad ButtonY), HoldDuration 0.6.
  - ActionText "Fuse All (N)", where N is the number of fusions possible right now without cascading. ObjectText "Hold · Common, Rare, Epic".
  - Enabled only when N ≥ 2.

**Client**
- `FusionController.RequestFuseAll()`: plays the existing charge-up for 3 s, then shows the summary card in `ResultController`.
- The summary card follows the canvas board "Fuse All + goal marker":
  - The panel gradient goes from `#3A1F6E` at the top to Panel at 40%.
  - Top to bottom:
    - "FUSE ALL", Body Heavy 13, `#C9A9FF`.
    - "26 fusions", Display 44.
    - "18 upgraded · 8 failed", with the upgraded part in Cash colour.
    - A 2-column grid of tier chips: orb + "+1 LEGENDARY", etc. Gains come first, highest tier first. The Common consumption line is shown as "−40" in Muted.
    - A BEST row: orb + tier + name.
  - Buttons: **DISPLAY BEST** (Green; uses `ItemController.PlaceOnFirstEmpty`) and **OK**.
  - If Best is Legendary or higher, play the camera shake.
- `Count == 0` shows the toast "Nothing to fuse".

## Acceptance check (do all of these before saying you're done)

1. `luau-lsp analyze`: no new errors. Only the known ones listed in CLAUDE.md are allowed.
2. `grep` finds no hard-coded positions or offsets in `TycoonService`, `FusionMachineService` or `WorldService`. Every number comes from `PlotLayout`.
3. `grep` finds no Basalt, Slate or Metal material anywhere in `src/`.
4. Every ProximityPrompt's MaxActivationDistance and Exclusivity match this file: stations 7, pedestals 6, machine 10, all OnePerButton. Add an assertion block at the bottom of `PlotLayout.lua` that checks, from its own numbers, that no two footprints in the plan overlap and that everything sits inside the walls. It runs at require time, so a future edit that breaks the layout errors loudly.
5. Add to `docs/UI_TEST.md` a "World" section for the human to run in Studio:
   - Spawn lands on the street in front of your own gate.
   - Everything in the plan is within a short walk of the gate.
   - The pedestal orbs show and spin.
   - Labels shrink with distance.
   - Fuse All with 40 Commons gives one summary.
   - The goal marker points at Dropper 2 on a fresh save.
   - In a 2-player local server, both labs face each other across the street.
   - Set Technology = Future and delete the Baseplate in Studio.
6. Update CLAUDE.md:
   - Replace the "Shared layout math" section with the new plot-local coordinate system and the slot grid.
   - Add StationKit, WorldService, WorldAnimationController and GoalMarkerController to Layout.
   - Remove the gotchas that no longer apply.
7. Commit per phase, push `world-redesign`, and open a PR into `claude/upbeat-tesla-bfro6p`.
