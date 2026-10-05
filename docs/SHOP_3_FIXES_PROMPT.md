# Fusion Tycoon: Shop 3 fixes (build prompt for Claude Code)

`git pull` on `world-redesign` first. This goes into PR #12, or a new PR if
#12 is merged. Don't merge.

---

Read CLAUDE.md. Harris tested PR #12 in Studio on Oct 5. The trailer worked
well: leave it alone. Fix these four things.

1. **On phones, the 🔥 DEAL badge floats in the middle of the screen.**
   - At 844×390 it sits right of the "next in" pill, in the screen centre.
   - On phones the badge belongs in the **left column**, on its own line under
     the SHOP / GIFTS row, the same as desktop.
   - Timed-effect pills (the "2× · 59:47" boost pill, "next in 4:22") wrap
     under it in the left column, never toward the centre.
   - Add a `/selftest` check: on the phone layout, every HUD element in the
     left group stays inside the left 40% of the screen.
2. **`/deal pop` prints "forcing the New deal! card" but nothing shows**, on
   desktop or phone.
   - Find the guard that's still blocking it: first-session 10 min, the 5 min
     shared cooldown, already-shown-this-slot, `IsOverlayOpen`, or the
     policy/Id = 0 check (in Studio deals have no live price, so make sure
     "no saving" doesn't hide the card).
   - `/deal pop` must bypass **every** guard and show the card. Then make sure
     the real path shows it when the guards allow, and add a selftest case for
     the real path with the clock moved past the guards.
   - In Studio with no live prices, the card shows the contents and "TEST",
     and no saving.
3. **Save "once per deal".** Store the last deal slot the pop-up showed in
   `PlayerData`, as `DealPopupSlot`, a number, sanitised in `reconcile`.
   Rejoining in the same slot then never shows it again.
4. **13 flaky `/selftest` FAILs:** "panel X: ±3 instances after a second
   open/close". The counts swing between +3 and −3 across panels, which looks
   like something else churning (the DEAL badge countdown, timed pills, the
   shop header shine, toasts), not a panel leak.
   - Count only the panel's own subtree, or pause the HUD animators during the
     check.
   - If a panel really does leak, fix it.
   - `/selftest` must pass three runs in a row, during a Golden Rain and with
     a boost running.

**Check:**
- Add UI_TEST lines for each fix.
- `luau-lsp analyze` reports no new errors.
- Report the cause of #2 and #4 in one line each.
