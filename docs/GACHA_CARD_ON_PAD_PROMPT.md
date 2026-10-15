# Gacha card: on top of the pad, in the world (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 5 lines or fewer.

---

Harris tested the docked card on Oct 15. It sits on the right side of the
screen, and **that's not what he wants**. His words: "right on top of the
gacha, when I walk up it pops up". That's Pet Sim 99's egg card: a small
card floating **over the pad in the world**, opening as you approach.

**This is the final placement.** Don't dock it, and don't follow the
camera.

Why the earlier in-world tries failed:
- They were sized in studs, so they grew huge up close.
- They sat "above your head" while you stood **on** the pad, so they went
  off the top of the screen.

Fix both: use pixel size, and anchor the card to the **pad**, not the
player. You pull with E / R / T from up to `PromptDistance + 3` studs, so
you don't need to stand on the pad. Walking up, you stop in front of it
and see the card over it, like a PS99 egg.

## Change

- **Back to a BillboardGui, adorned to the Gacha Pad:**
  - pixel size, the same content and layout as now: the 300 × 204 card
    plus the E / R / T row; 0.8 on a phone;
  - `SizeOffset = (0, 0.5)`, so it grows **upward from the anchor**;
  - **anchor:** pad top + 3 studs, just above the floating capsule orb,
    centred on the pad. No backward shift;
  - `AlwaysOnTop = false`, `LightInfluence = 0`, `MaxDistance = 150`,
    `ResetOnSpawn = false`. No CanvasGroup.
- **Delete** the right-side dock, the ScreenGui card and their placement
  code.
- **Pop:** unchanged. In at 16 studs from your character to the pad, out at
  19. Scale 0.85 → 1 over 0.12 s with one UIScale. Content built once.
- **While the card is open, hide what it would cover:**
  - the pad's small `GACHA` / price label;
  - the floating `VIP` chip above the pad (show it again on close);
  - the gacha's default prompts. They stay off.
- **Standing on the pad with a close camera,** the top could still clip.
  Guard it, and only then:
  - once on open and on a viewport change (**not** every frame), project
    the card's top;
  - if it would be above `TopStack.GetBottom()`, lower the anchor (never
    raise it) until it fits, down to a floor of pad top + 0.5;
  - re-check only when the camera zoom changes by more than 2 studs.
  - It must never slide around while you just turn the camera.
- Everything else stays: the content, the keys only while open, and hiding
  while a modal or the reveal card is open, or while ragdolled or
  Carrying.

## Check

- `luau-lsp analyze` shows no new errors.
- **`/selftest gacha`:**
  1. **Approach position:** the character 8 studs in front of the pad on
     the walkway side, at the default camera, at 1366 × 768 and
     844 × 390.
     - The card is open, **above the pad on screen** (its bottom-centre
       within 40 px of the pad's projected top), and fully on screen.
  2. **On the pad** (default camera): the card is fully on screen and its
     top is below `TopStack`.
  3. **Rotate the camera** 4 yaws at a fixed zoom: the billboard's
     `StudsOffset` doesn't change.
  4. The `VIP` chip and the `GACHA` label are hidden while it's open and
     shown after.

  Remove the dock checks and keep the content, odds and keys checks.
- Give Harris this list:
  1. Walk up to the pad: the card pops up right on top of it.
  2. Stop in front and press E / R / T.
  3. Walk away: it pops down, and the GACHA label and VIP come back.
- Update `docs/systems/items-and-fusion.md` and UI_TEST.
- Say which branch you pushed to.
