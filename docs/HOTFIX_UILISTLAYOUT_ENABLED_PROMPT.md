# HOTFIX: the HUD doesn't build: `Enabled is not a valid member of UIListLayout` (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines. **Only these edits. Do this first, before anything else.**

---

Since bf3f161 the client crashes at boot, and the whole HUD is broken (an
empty cash card, no buttons, a bare weapon bar). Studio output:

```
Enabled is not a valid member of UIListLayout "UIListLayout"
Script 'Players.ILIKESIMULATORGG.PlayerScripts.UI.UIKit', Line 1852 - function Modal
Script '...UI.UpgradesPanel', Line 706 - function build
Script '...UI.UpgradesPanel', Line 832 - function Init
Script '...Controllers.HudController', Line 2805 - function Init
Script '...Bootstrap', Line 49
```

`UIListLayout` (like every UI layout) has **no `Enabled` property**.
`UIKit.Modal` sets `titleLayout.Enabled = false` (line ~1852) and
`titleLayout.Enabled = compact` (~1927).

## Fix

- Toggle the title row's layout by **parenting**:
  - `titleLayout.Parent = if compact then titleRow else nil`;
  - keep the reference;
  - start it unparented on desktop.
- Make sure the desktop title keeps its own size / position when the layout
  is unparented, and that the compact phone header still lays out.
- **Grep everything bf3f161 and 3805067 touched** for other property sets
  that don't exist on the class (`.Enabled` on any `UI*Layout`, `UIPadding`,
  `UIScale`, `UISizeConstraint`, `UIAspectRatioConstraint`, `UIStroke` is
  OK; `.Visible` on non-GuiObjects; etc.) and fix them the same way.
- **Why `luau-lsp` missed it:**
  - Check the `globalTypes.d.luau` you analyze with. If `UIListLayout`
    is typed loosely (any / indexer), say so in one line.
  - Add one require-time guard in `UIKit`: build a throwaway `Modal` in
    `pcall` at `/selftest` start and FAIL with the error text, so a boot
    crash in `Modal` is a FAIL line, not a silent blank HUD.

## Check

- `luau-lsp analyze` shows no new errors.
- Harris: Play (desktop and iPhone XR). The HUD builds, Output has no red
  errors, and opening Upgrades / Shop works. Then `/selftest`.
- Say which branch you pushed to.
