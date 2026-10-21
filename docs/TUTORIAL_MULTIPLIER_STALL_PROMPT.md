# Tutorial stalls at the Multiplier step in a phone-sized window (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 5 lines.

---

Harris ran `/selftest` on **6ed0aeb** with the Studio game view at **801 ×
413**. That's under 500 px tall, so it uses the **phone layout**. The result
was 281 passed, 6 failed. The FAIL / WARN lines and the TutorialStep
analytics are in `docs/selftest_logs/2026-10-21_6ed0aeb_fails.txt`.

## 1. The tutorial: Multiplier → Events → Rebirth → Finish (top priority)

What happened:
- `index` passed: its card opened, and the banner took over after OK.
- Then `TutorialStep = 7` logged, and **`TutorialStep = 8` never logged**.
- The **multiplier** step printed **no probe lines at all**: no card line,
  no banner line.
- `events`, `rebirth` and `finish` each FAIL "its banner shows: never
  presented", after the full 30 s `PRESENT_WAIT`. The server moved the
  steps on anyway (`TutorialStep = 9, 10, 11`, `TutorialDone`).

So the **client presenter got stuck on the multiplier step** and never
presented anything after it.
- On the big-window run (389 passed, 0 failed) every step presented.
- The multiplier step has been the flaky one in every earlier run too:
  "drawn 328x-184", "no report from the client".

Find out why, **in the phone layout**:
- Does the multiplier step's explain card fail to open, or open off screen
  / with a negative size, so its OK never fires?
- Does the presenter wait on something that never happens on a phone (a
  HUD button `HudGate` hasn't revealed yet, a hand target that doesn't
  exist, the pad prompt)?
- Does the server skip the step while the client is still waiting for it?

**If a real phone player can get stuck here, that's a launch blocker.** Most
players are on phones, and they'd lose the tutorial halfway. Fix the game,
not only the probe:
- The presenter must never wait forever. If a step's card or target can't
  show within a few seconds, log a warn and move on to the banner.
- When the server advances past a step, the client must drop what it was
  presenting and present the current step.

Selftest:
- Have the multiplier step print its lines like the others (card, OK, banner,
  objective bar, HUD set).
- Add a line: "the presenter caught up with the server's step after each
  step" (presented id == server step id within 5 s).

## 2. Effects tray plan at 844 × 390 (2 FAILs)

These fails come from the old right-edge column, which
`EFFECTS_TRAY_TOP_RIGHT_PROMPT` replaces. If that's already done, just
confirm they're gone. One detail to keep:
- The phone tooltip measured "card **34 × 532**" at y = −693: an absurdly
  narrow, tall card.
- Give the tooltip a **minimum width of 160 px** (shrink the text, never
  the width below that).
- If no side fits, place it under the row, clamped on screen.

## 3. The window

The run's "selftest window: 801 x 413" FAIL is the environment (the
emulator / a small view). Leave the guard as it is.

## Check

- `luau-lsp analyze` shows no new errors.
- Harris: run `/selftest` **twice**, once with a big window (≥ 1000 × 600)
  and once with the iPhone XR emulator. The tutorial steps all present in
  both. Paste the FAIL lines.
- Then `/tutorial reset` in the iPhone XR emulator and play the tutorial by
  hand through Multiplier → Events → Rebirth → Finish.
- Say which branch you pushed to.
