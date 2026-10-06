# /selftest fixes (build prompt for Claude Code)

`git pull` on `world-redesign`, then commit and push to `world-redesign`.
These are small fixes; reply in 5 lines.

---

Harris's `/selftest` run on Oct 6 had these FAILs. Fix them.

1. **"cards centred … live" is off by exactly the top bar.** Every live
   card failed by the same amount:
   - desktop: centre 268 vs 326, which is 58;
   - phone: 140 vs 213, which is 58 ÷ 0.8.

   The placement is right, as the 1920×1080 / 1366×768 / phone math cases
   pass. The **measurement** is wrong: `AbsolutePosition` is reported below
   the Roblox top-bar inset even in `IgnoreGuiInset` guis. In
   `CheckCardPlacement`, add `GuiService:GetGuiInset()` (Y) back, then
   convert to logical px. "BigResult starts at 8, not 66" is the same bug.
2. **Text that doesn't fit:** wrap it, use `TextScaled` with a minimum
   size, or shorten the copy. Keep the meaning.
   - ShopPanel tiles: Overclock "×2 income for EVERYONE here · 15 min",
     SafeFusion1 / SafeFusion5 "… a failed fusion keeps every orb".
   - GiftsPanel footer: "Gifts reset at 00:00 UTC; time adds up across…".
   - RebirthPanel:
     - the `Reset` line "Cash (pays the $15M) · Generators → B…";
     - the `Unlock` line "Rebirth 1: unlocks stealing, Mythic → …" on
       the phone.
3. **"deal real path: still blocked by Tutorial with the guards
   cleared":** the deal case must also clear the tutorial guard, or
   simulate `Tutorial.Done`, for its run only, and then restore it.
4. **The tutorial drive** stops at "claim" when the tester has no lab. Make
   it claim a free slot for the tester first, through the real claim path,
   and release it after if it wasn't claimed before. If no slot is free,
   print SKIP instead of FAIL.

**Check:** `luau-lsp analyze` shows no new errors. Tell Harris which lines
should now PASS.
