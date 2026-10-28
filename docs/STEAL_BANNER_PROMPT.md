# Steal mission banner: a big instruction box at the top, under the event chip (build prompt for Claude Code)

Run `git pull` on `world-redesign` (do `FUSE_CARD_FIX_PROMPT.md` first if it isn't in yet), then commit and push
to `world-redesign` (or a side branch `triage19-check` if you can't run
`tools/compile_check.py`, as before; the planner moves it).
**Line 1: the branch. Line 2: "untested in Studio" (also in the commit
message).** Then one line per group: DONE or WHY-NOT. Run
`tools/theme_token_check.py` and `luau-lsp analyze` before pushing.

---

Harris (screenshot, right after the tutorial): the only instruction to steal
is a small world bubble over a pedestal 74 studs away (`STEAL FROM THE RIVAL
LAB! HOLD E, RUN HOME, DON'T GET CAUGHT!`, tiny text) plus the arrows. Kids
don't see or read it. Stealing is the hook of the game; it needs a **big
text box at the top middle, directly under the event chip**.

## 1. A "Mission" slot in TopStack

`UI/TopStack` owns the top centre. Add a persistent slot
**`Mission`** between `Chip` and `Announce` (Objective, Chip, **Mission**,
Announce, Status). Same rules as the others: a height provider, `GetY`,
`OnChanged`, `GetStableBottom()` includes it (the gacha card and every
modal band already clear the stable bottom; `/selftest` checks the cards
still don't overlap it). It's not queued like Announce: one mission at a
time, shown until its owner hides it.

API: `TopStack.SetMission({ Key, Height, Show(y), Hide(), Move?(y) }?)`
(nil clears). Hidden while any `UIKit.Modal` / centred card is open
(`UIKit.IsOverlayOpen()`), back when it closes, like the tutorial banner's
`IsCovered`.

## 2. The steal mission box (UI/MissionBanner.lua)

A bigger box than the announcement banner (about 560 x 84 logical px on
desktop, full width minus the 170 px Roblox buttons on phone, UITheme
tokens only, UIKit constructors, white text on the warm fill per the
contrast rule):

- Title, big (the display font): `STEAL A FREE ORB!`
- Three icon steps in one row under it, each one short:
  `1 🤚 Hold E at the glowing orb` · `2 🏃 Run home with it` · `3 🛡 Don't get caught!`
  (on phone: the same 3 steps, 12 px minimum text after scale, wrap to 2
  rows if needed; keep the whole box ≤ 100 logical px tall).
- The rival's name in the title when known: `STEAL FROM DR. FIZZ!`.
- A live step highlight: step 1 lit until the player holds a stolen orb
  (`HeistTier` attribute), step 2 lit while carrying, a short `✔` flash on
  delivery.
- No close button: it goes away on its own (below).

## 3. When it shows

- Owner: the existing `tipRival` (TutorialConfig ~354) and the LoopCoach
  `Steal` step. While `tipRival` runs, the mission box is its text (the
  small world bubble keeps a one-word `STEAL!` and the arrows stay).
- Hides when: the first rival steal is **delivered** (and `tipRival` is done
  forever, as now), or 3 minutes pass, or the player is ragdolled/stunned
  (back when they recover), or a tutorial step is running.
- After the first delivery it never shows again by itself. The coach's
  Steal step uses the plain tracker line as before.
- Phone: shown only while the player is in a lab-facing state (no big panel
  open); it must not cover the weapon bar or the goal tracker (it is in the
  top stack, but check the phone left column / top bar fit).

## 4. Selftest + docs

- Stack order and y-positions with the mission up: Objective < Chip <
  Mission < Announce, no rect overlaps, at 1920 x 1080, 1366 x 768,
  844 x 390 (reuse the existing top-stack overlap check).
- The mission box text sizes ≥ 12 px (13 on phone per the existing rule),
  ≤ 100 px tall, inside the screen; hidden while a modal is open and back
  after; gone after a delivered steal; the gacha card clamp still passes.
- `docs/systems/tutorial.md` (tipRival now has the mission box) and the
  UI rules in `docs/systems/architecture.md` (the Mission slot).
