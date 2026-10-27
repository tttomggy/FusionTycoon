# Triage 10: NEW! pills, oversized world labels up close, gacha card under TopStack on PC, rival tip line (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 4 lines, one per group: FIXED or WHY-NOT. Run the Luau parser and
`tools/theme_token_check.py` before pushing.

---

Harris played 835d372 on PC (1920 × 1080 game view), screenshots:

## 1. HudGate's NEW! pills float too high

When UPGRADES and INDEX pop in (Fuse step), their `NEW!` pill (and the
`New orbs fill your Index!` note) sit ~60–80 px **above** the buttons, in
the middle of the world, not on them.

- The NEW! pill sits **on the button's top edge**, centred, half
  overlapping it (like a badge), measured from the button's visible rect
  (body + shadow, `AbsolutePosition` with the GuiInset rule the selftest's
  `visibleRect` uses). The note pill goes right above the NEW! pill.
- It must follow the button if the bottom row moves (phone, jump button).
- Selftest: for every HudReveal key that shows a NEW! pill, at 1920 × 1080
  and 844 × 390, the pill's bottom is within ±6 px of the button's top
  edge and horizontally centred on it (±4 px).

## 2. Stud-sized world labels fill the screen up close

Standing next to them on PC:
- the pedestal **`+ EMPTY`** pills (`BillboardKit.buildEmptyLabel`,
  `EMPTY_PILL_STUDS` 3.6 × 1.1) are ~300 px wide each, two of them covering
  a third of the screen;
- the **`🔒 LOCK LAB` / `LOCKED · 53s`** console label is ~450 px wide and
  sits over the gacha card.

CLAUDE.md already says a stud-sized billboard people stand next to needs a
`DistanceLowerLimit` (the gate sign has one); these don't.

- Give every stud-sized BillboardGui a player can stand within ~10 studs
  of a `DistanceLowerLimit` so it never grows past its size at that
  distance. Start with: EMPTY pills, LOCK console, pedestal item labels,
  station pads' labels, the Multiplier/Gacha station labels, rival-lab
  labels. Pick each limit so the label is at most ~220 px wide on a 1080p
  screen.
- Put the numbers in `PlotLayout` / `BillboardKit` (no magic numbers in
  the services) and document the rule in `BillboardKit`'s header.
- Selftest: for each of those labels, at 3 studs from its adornee and a
  1920 × 1080 view, the projected width is ≤ 240 px (extend the gate-sign
  check at SelfTestController ~1080 to a list).

## 3. The gacha card slides under the event chip on PC

Third screenshot: standing on the Gacha pad on PC, the card's top row (the
first three orbs and the (i)) is hidden behind the `NIGHT · 5:05` chip. The
phone check already requires "under the event chip row"; desktop doesn't.

- Desktop too: the card's top stays ≥ `TopStack` bottom + 4 px (the same
  clamp as the phone, after the world-anchor placement). If clamping pushes
  it off its pad anchor, keep it clamped; readable beats anchored.
- Selftest: the desktop "standing on the pad" case also asserts top ≥
  stack bottom + 4 at 1920 × 1080 and 1366 × 768.

## 4. The rival tip's line

`TutorialConfig` ~358: change to
`Steal from the rival lab! Hold E, run home, don't get caught!`
(fits the existing two-line marker; keep it under 60 characters).
