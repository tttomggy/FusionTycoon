# Triage 15: the panel leak check fails on a shrink (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 1 line: FIXED or WHY-NOT. Run the Luau parser and
`tools/theme_token_check.py` before pushing.

---

Harris ran 2d62649 on PC: the only FAIL left is

```
FAIL panel IndexPanel (phone): -2 instances after a second open/close
```

`testPanels` (SelfTestController ~757) counts every modal Gui's descendants
after the first and second close and fails on ANY difference. It is a leak
check: a leak only ever GROWS the count. A shrink (here −2) is the Index
dropping something it no longer needs after the first open (most likely the
NEW tags on entries the first open marked as seen, or a one-time tip), which
is correct behaviour.

- Fail only when `counts[2] > counts[1]` (a growth). A shrink prints nothing.
- Confirm what the 2 instances were (print the names once, then remove the
  print) and say it in your reply. If it is anything other than seen-state
  badges / a one-time tip / a fading toast, it's a real bug: say so instead
  of fixing the check.
