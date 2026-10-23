# Phone, live game: portrait on join, gacha card too big, panels too cramped (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 6 lines, one per group: FIXED or WHY-NOT.

---

Harris played the **live** game on his phone (landscape phone,
~2000 × 924 screenshots). These problems don't show in the Studio
emulator.

## 1. The game opens in portrait

- On first join the screen is **vertical**: the HUD is cut off, and the
  Roblox top bar overlaps the event chip and the objective bar.
- Nothing in `src/` sets `ScreenOrientation`.
- Fix:
  - Set `StarterGui.ScreenOrientation = LandscapeSensor` in
    `default.project.json` (StarterGui properties).
  - **Also** set `PlayerGui.ScreenOrientation = LandscapeSensor` from the
    client at boot (the first thing `HudController`, or a tiny init,
    does), so an old place file can't override it.
- Selftest: `PlayerGui.ScreenOrientation` is `LandscapeSensor`.

## 2. The gacha card is far too big on a phone

- Standing on the pad, the card fills the top-centre of the screen. Its
  tier orbs and % run off the top behind the event chip, and you have to
  tilt the camera up to read it.
- It's a pixel-size `BillboardGui`, so on a phone it's huge compared with
  the screen.
- Fix:
  - On the **phone layout**, scale the card down so that at the default
    camera zoom and pitch, standing on the pad, the **whole card** (title,
    6 orbs with %, mutation line, price, E / R / T) sits on screen
    **below** TopStack's lowest slot and above the weapon bar. Use one
    scale factor computed from `UIKit.GetLogicalViewport()` and the card
    size (clamped 0.55–1.0).
  - Desktop unchanged.
- Selftest: with the phone layout, at 844 × 390 and 896 × 414, standing on
  the pad at the default camera, the card's screen rect is fully on screen,
  below `TopStack`'s bottom and above the weapon bar; the % text is still
  ≥ 12 px.

## 3. Phone panels are too cramped: learn from Tap Simulator

- **Upgrades** shows **one** generator row at a time. The header, the tabs
  and the multiplier footer eat the height, and the band stops above our
  bottom row.
- **Shop** shows half of one card.
- Harris's reference is **Tap Simulator** (the phone screenshots he sent):
  - **On a phone a panel takes nearly the whole screen.** The HUD (left
    column, bottom row, weapon bar, tray) **hides while a panel is open**.
  - **The header is one compact row:** the title on the left, the
    tabs / chips in the same row, and the ✕ on the right.
  - The content gets all the height that's left. Cards are big and
    readable: icon, name, price and button at a glance.
- **Phone layout only (desktop unchanged):**
  - **While a modal panel is open** (Upgrades, Shop, Items/Fuse, Index,
    Gifts, Quests, Rebirth, Settings), hide the HUD and the weapon bar.
    Bring them back on close. Through one place (`UIKit.Modal` open / close
    → `HudController.SetPhoneHudHidden`), not per panel.
  - **Phone band:** from just below the Roblox top bar (`GetCardTop()` on
    phone) to **8 px** above the screen bottom (not above our bottom row,
    which is hidden now). Update `GetCardBottom()` for phone + modal and
    the explicit-viewport maths (`PlanModalFor`) so the selftest still
    tests it.
  - **Compact phone header:** the title (24 px) and the tabs / chips in
    **one row**, the ✕ on the right, and the subtitle line dropped or put
    in the (?) help. The header should be ≤ 56 px.
  - **Don't shrink the content below readable sizes:** a list row ≥ 64 px
    tall, its name text ≥ 18 px, the button ≥ 44 px.
    - Upgrades must show **at least 3 generator rows** at 844 × 390.
    - The Upgrades multiplier footer becomes one slim line (or a row in
      the list).
    - The Shop must show at least one whole card.
  - Small centred result cards (big reveal, Fuse All, daily, event info)
    keep their current behaviour. This is for the big panels.
- **Selftest:**
  - phone panels: the HUD is hidden while open and restored after;
  - the panel's bottom is ≤ viewport − 8;
  - the header is ≤ 56 px;
  - Upgrades shows ≥ 3 full rows at 844 × 390;
  - every text in the panel is ≥ 13 px;
  - the existing "cards centred" maths is updated for the new phone band.

## 4. Update the rule

The CLAUDE.md card-placement rule says modals never go over the HUD bottom
row. Add the phone exception in one line: on the phone layout, big panels
hide the HUD and use the band down to 8 px above the screen bottom.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs (big
  window and iPhone XR).
- Update `docs/UI_TEST.md`.
- Harris, in the iPhone XR emulator **and** on his real phone after
  publishing:
  - the game starts in landscape;
  - the gacha card is fully visible from the pad;
  - Upgrades shows 3+ generators;
  - the Shop shows whole cards, with no HUD behind the panels.
- Say which branch you pushed to.
