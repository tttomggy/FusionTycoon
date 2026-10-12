# Weapons redesign (build prompt for Claude Code)

`git pull` on `world-redesign`, then commit per phase and push to
`world-redesign`. Reply in 10 lines or fewer.

---

Harris: **"the weapons are poorly designed, I need a complete
redesign."** He's right. In his screenshots:
- every weapon is **one plain block** (`CombatService.buildTool`'s
  `HANDLES` table: the Bat is a 0.5 × 0.5 × 4 wood brick);
- it's held flat **across the chest**, not in the hand;
- there's no swing or aim pose;
- the bar shows small emoji circles.

Rules unchanged: no damage or deaths, earned and never sold, server
authority. Only the **looks and feel** change. Keep `CombatConfig`
numbers.

## Phase 1: Real models (`Shared/Modules/WeaponKit.lua`, new)

**Build rules:**
- Each weapon is a small model built from parts, welded to a small
  `Handle`. The Handle is the grip, about 0.4 × 1 × 0.4 studs.
- `WeaponKit.Build(weaponId): Tool` is used by `CombatService` (it
  replaces `HANDLES` / `buildTool`) and by the bar icons and unlock card
  (`WeaponKit.BuildModel(weaponId)` for viewports).
- Materials rule: SmoothPlastic bodies plus thin Neon accents, colours
  from `UITheme.World`.
- No flat Neon circles.
- `Massless`; `CanCollide`, `CanQuery` and `CanTouch` all false.
- About 4 studs long at most, so it reads well at Roblox scale.

| Weapon | Model |
|---|---|
| 🏏 **Bat** | a tapered cylinder barrel (thin at the grip, fat at the end), a black grip wrap, a knob at the bottom, two lime Neon stripe bands, a dented "pro" look |
| 🔫 **Laser Gun** | a chunky sci-fi blaster: body, barrel with 2 cooling rings, a glowing cyan core (Neon) in the side window, grip, trigger guard, a small scope fin |
| 🥶 **Freeze Ray** | the blaster shape in white / ice blue, a coiled barrel (3 thin rings), a frosted glass tank (Glass, transparency 0.4) with a light-blue Neon core |
| 🖐 **Slap Glove** | a big red cartoon glove (palm, 4 fingers, thumb as rounded parts), a white cuff |
| 🍌 **Banana Peel** | a banana in the hand; the placed version is 3 curved yellow petals splayed on the floor with a brown stem |

**Hold it right:**
- Set `Tool.GripForward` / `GripRight` / `GripUp` / `GripPos` per weapon,
  so it sits **in the right hand**:
  - the bat points up and forward;
  - the guns point straight forward from the hand;
  - the glove sits *on* the hand.
- Check every weapon in Studio from the front and the side at R15
  scale.

## Phase 2: Feel (client, `CombatController`)

No animation uploads. Use procedural poses through
`Motor6D.Transform` on RenderStepped, like `TrailerController` does.

**Poses:**
- **Equip:** a quick 0.15 s raise plus the equip sound.
- **Bat / Glove swing:** wind back, then a fast arc across, about 0.35 s.
  - A white `Trail` on the bat tip (glove: a red one) during the swing
    only.
  - On a hit: a white flash ring and the existing BONK! pop.
- **Guns:** while equipped, the right arm is raised forward in an aim
  pose; the camera stays free.
- **Firing a gun:**
  - a 0.1 s recoil kick and a muzzle flash (PointLight + a small neon
    burst);
  - **Laser:** a cyan beam (a thin neon cylinder seen from the side) for
    0.12 s;
  - **Freeze:** an icy cone of snowflake particles plus a light blue
    beam.
- **Freeze on the target:** blue tint, frost particles and an ice-crack
  sound for the freeze time.
- **Peel:** a throw arc, then it lands splayed. On a slip: the SLIP! pop
  and a spin.
- **Every pose is local.** Other players see the swing through the same
  `HitFx` (add `Swing = true` for misses, so swings show even without a
  hit; rate-limited).
- **Sounds:** fill the empty Bonk / Laser / Freeze / Slip slots, and add
  Swing, Equip and Shoot. Use Roblox-made Creator Store SFX (creator id
  1), as `docs/SOUNDS.md` says. If you can't look up ids from where you
  run, leave them empty and list what each one should sound like in
  SOUNDS.md for Harris.

## Phase 3: The weapon bar

Replace the small emoji circles.
- **Slots:**
  - 64 px rounded-square slots (52 on phone) with a dark panel fill;
  - inside each, a **ViewportFrame** with the real `WeaponKit` model,
    slowly turning, lit with `UITheme`;
  - the key number badge top-left;
  - the weapon name under it (12 px).
- **States:**
  - **Equipped:** a lime ring plus a lift of 4 px.
  - **Cooldown:** a dark radial sweep plus the seconds left.
  - **Locked (not yet earned):** a dim model with 🔒 and "R2" / "R3" /
    "Quest".
  - **While carrying a stolen orb:** the whole bar dims.
- **Placement:** centred above the bottom buttons with a 12 px gap.
  Check that it never overlaps the bottom bar or the tutorial
  contextual button.
- **Unlock card** ("🏏 You got a Bat!"): the big turning model instead of
  the emoji.

## Check

- `luau-lsp analyze` shows no new errors.
- `/selftest` combat checks still pass.
- **New check:** every `WeaponKit.Build` tool has a Handle, every part
  is welded to it and massless, and it fits a 4.5-stud box.
- UI_TEST "Weapons 2" section: each weapon held in third person, a swing,
  a shot, freeze, peel, the bar at 1920×1080 and phone.
- Update `docs/systems/combat.md`.
- Send Harris a screenshot list of what to look at.
