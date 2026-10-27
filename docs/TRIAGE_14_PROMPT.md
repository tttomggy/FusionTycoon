# Triage 14: the gacha card won't reopen on PC, the 64-vs-68 is a test artifact, run the selftest yourself (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.**
**Line 2: whether you could run `/selftest` in Studio yourself (see group 0).**
Then one line per group: FIXED or WHY-NOT. Run the Luau parser,
`tools/theme_token_check.py` and `luau-lsp analyze` (if it runs) before pushing.

---

## 0. Stop shipping selftest fixes blind

Four triages in a row fixed one gacha check and broke or exposed another,
because nobody ran `/selftest` before pushing. If your session has the
Roblox Studio MCP tools (`start_stop_play`, `execute_luau`,
`get_console_output`, `screen_capture`), use them:
start Play, run `/selftest` (or call DebugService's runner from
`execute_luau`), read the `[SelfTest] FAIL` lines from the console, fix, and
repeat **until 0 FAIL in a desktop-sized window** before you push. Put the
final FAIL count (and any FAIL lines left) in your reply. If you can't reach
Studio, say so on line 2 and be extra careful with group 1.

## 1. PC: after the GachaOnPad probe the card never opens again (REAL BUG?)

Harris ran 17a785f on PC (1891 x 852 window). After the phone probes, every
later gacha probe finds the card shut:

```
FAIL gacha card (phone 844x390): every text >= 13 px ...: scale 0.523, 0 texts, (i) hit 46.0 px
FAIL gacha card (phone 896x414): ... 0 texts
FAIL gacha card (desktop layout, 1891 x 852 window): 8 studs in front of the pad ... | the card is not open
FAIL gacha card (desktop layout ...): with the camera straight above the pad ... | the card is not open
FAIL gacha card (phone layout ...): ... | the card is not open   (x2)
FAIL gacha card: walking back to the pad opens it again (shown, UIScale 1): shown false, PopScale 0.850, label Enabled false
FAIL gacha card: walking back to the pad binds E, R and T again: bound []
```

None of these failed on 7fe522c. "0 texts" means the text check found
nothing drawn, i.e. the card was already shut during the phone probe's
second half. So something from accc959 / 17a785f leaves the card unable to
open: the two-sided `PhonePlanFor` (it writes the `PhoneScale` UIScale every
frame; does a 0 / NaN / tiny scale or an off-screen slide stick after the
layout goes back to desktop?), the probe-id `restoreProbe` path, the tester
left at a "3 studs away" spot, `view.Near` stuck, or `popIn` interrupted
(`PopScale 0.850` = a pop-in tween that never finished).

- When a gacha check finds the card shut, its FAIL detail must say why:
  `GetBlockReason()`, `view.Near`, `view.Open`, the tester's distance to the
  pad, `PopRoot.Visible`, PopScale, the PhoneScale UIScale's value,
  `SizeOffset`.
- Find the root cause and fix it in the game code if it can happen to a
  player (walk on, off, on the pad, switch layout by rotating a phone or
  resizing a window); fix it in the probe if it can't.
- After every probe that moves the tester, put the tester back on the pad
  centre and the camera back to Custom before the next probe starts.

## 2. Desktop "live top 64 (min 68)": a test artifact, not a bug

Your clamp trace solved it: `anchorY 239.8 drawnHeight 324.0 shift 148.21`,
and 239.8 + 148.21 = 388.0 = the window's height. That run was in the
**phone emulator** (388 px tall), with the desktop layout forced: a 324 px
card plus a 68 px top needs 392 px, so the "keep the key bar on screen" cap
correctly wins. The clamp is right.

- The LIVE desktop check only runs when the real window is tall enough
  (`viewHeight >= minTop + drawnHeight`); otherwise it prints
  `PASS ... (skipped: window N px tall, the desktop card needs M)`. The pure
  1920 x 1080 / 1366 x 768 checks stay as they are.
- Keep the clamp trace (it just paid for itself), behind the debug flag.

## 3. Card POSITION checks become WARN, not FAIL

Launch is gated on 0 FAIL; a card a few px off its ideal spot isn't a
launch blocker. Through the existing WARN path (printed, never counted):

- WARN: gacha card phone fit (`standing on the pad ... whole card on screen,
  under the event chip row and over the weapon bar`), desktop stack
  (`card's top is >= the stack's bottom + 4 px`), and the "centred on the
  pad / covers the capsule ball" geometry lines.
- Stay FAIL: the card opens, closes, reopens, binds E/R/T, text ≥ 13 px,
  tap targets ≥ 44 px, "the anchor never changes", the probe runs in its own
  layout, "a toast never moves the card".

## 4. Docs

`docs/systems/studio-commands.md`: which gacha lines are WARN, the live
desktop skip rule, and the "card shut" diagnostics.
