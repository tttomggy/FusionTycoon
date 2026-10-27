# Triage 16: Auto pull test finds the tester off the pad, event card vs tutorial bar (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.**
**Line 2: did you run `/selftest` in Studio yourself (Studio MCP)? If yes, the
FAIL count of your last run.** Then one line per group: FIXED or WHY-NOT.
Run the Luau parser, `tools/theme_token_check.py` and `luau-lsp analyze`
(if it runs) before pushing.

---

Harris ran 5a697f8 on PC (1891 x 852 game view) and the phone emulator.
New fails, identical on both:

```
FAIL gacha keys: Auto pull ran exactly 2 x10 cycles with cash for 20 pulls, then stopped (InsufficientCash): 0 cycles, stop TooFar, pulls 0 -> 0
FAIL gacha keys: no Auto pull cycle starts within 3s of the previous one: gap n/a
FAIL auto pull: each x10 cycle showed the 10-pull card: 0 cards shown, 2 cycles ran
```

PC only:

```
FAIL tutorial bar vs card (desktop running +OK): the objective bar (y 66..150) overlaps the card (y 147..536)
```

## 1. Auto pull: the tester is off the pad when Auto starts (test regression from 2d62649)

These passed before Triage 14. `DebugService` ~1918 puts the tester on the
pad (`root.CFrame = onPad`), runs the client probe `AutoReset` (~1942), then
`SetAutoPull(true)`, which stops at once with `TooFar`. Triage 14 made
client probes **teleport the character** (`restoreProbe`: `root.CFrame =
home`, and `probeTutorial` runs a leftover `restoreProbe` at the START of the
next probe). The client owns its character, so a client teleport beats the
server's `onPad`. The 3rd line ("2 cycles ran" vs "0 cycles") also shows the
client and server disagree about what happened.

- Confirm with one print: the tester's flat distance to the pad and its
  position, right before `SetAutoPull(true)`. Report it.
- Rule: **the server test owns the tester's position.** Client probe
  restores put back the camera and the forced layout only, never the
  character. The GachaOnPad probe's own stand-at-centre / 3-studs-off moves
  stay inside that probe, and it ends by putting the tester back where IT
  found them (inside the probe, before it reports), not in a deferred
  restore that runs later.
- Belt and braces: in DebugService, after `AutoReset` returns, set
  `root.CFrame = onPad` again and wait 0.4 s before `SetAutoPull(true)`.
- Make "auto pull: each x10 cycle showed the 10-pull card" use the server's
  cycle count from the same run (it printed "2 cycles ran" while the server
  saw 0).

## 2. Event info card vs the tutorial objective bar (desktop, 852 px tall view)

The tallest event card (running event + the tutorial OK row) is centred in
the band at y 147; the objective bar is still on screen down to y 150 (the
rule needs bar bottom + 8 ≤ card top). The test comment says the bar steps
aside while the card is open; here it didn't (within the 0.5 s wait), or
the bar doesn't step aside for this card at all.

- Find which, and fix the game: while any centred card is open, the
  objective bar is covered (slid out or hidden) **or** the card's band
  starts below the bar. Pick the one that already exists in the code (the
  bar's `IsCovered` path) and make it cover for the event info card too.
- If it's only the slide not finishing in 0.5 s, wait for the bar's tween
  (or `IsCovered()`) instead of a fixed time, max 1.5 s.
- Check at 1920 x 1080, 1366 x 768 and an 852 px tall view.

## 3. Docs

`studio-commands.md`: the server owns the tester's position; client probe
restores are camera + layout only.
