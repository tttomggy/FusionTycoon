# Tutorial path: small arrows instead of dots (build prompt for Claude Code)

`git pull` on `world-redesign`, then commit and push to `world-redesign`. This
is a small change.

---

Harris wants the tutorial path (and the goal path) to be **small arrows**
pointing the way, not dots.

**Arrows** (in `Effects/TutorialPath.lua`, numbers in `TutorialConfig`):
- **Shape and placement:**
  - Replace each dot with a small flat chevron **">"**. Build it the same
    way as the existing target chevrons: two thin lime Neon bars, about
    1.2 studs long and 0.25 thick.
  - Lie it flat, 0.2 studs above the floor.
  - Point it along the path's direction at that spot, toward the target.
- **Spacing and count:**
  - One arrow every 3 studs.
  - At most 40 arrows (80 parts), in the same fixed pool moved every 0.3 s.
  - Past 120 studs the spacing widens, as now.
- **Animation:**
  - Keep the pulse running toward the target: each arrow brightens and
    then fades in sequence, so the arrows look like they're flowing.
  - Keep the 3 bigger chevrons at the target.
- **Colours and tokens:**
  - Keep `World.TutorialPath` lime.
  - Rename the config keys, for example `PathArrowSpacing`,
    `PathMaxArrows` and `PathArrowSize`.
  - Update `GetDotCount` → `GetArrowCount` and its `/selftest` use.
- **Rules:** thin bars only, no flat Neon circles. `CanCollide`,
  `CanQuery` and `CanTouch` are all false, and `CastShadow` is false.

**Check:** `luau-lsp analyze` shows no new errors, and the `/selftest`
tutorial drive still passes. Update the path line in
`docs/systems/tutorial.md`. Reply in 3 lines.
