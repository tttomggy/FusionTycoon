# Fusion Tycoon: Bug Hunt 1 (build prompt for Claude Code)

Before you start, run `git pull` on `world-redesign`, and commit each fix
separately.

---

Read CLAUDE.md and follow it. This pass adds no features. Its job is to find
and fix as many real bugs as possible before launch, and to leave a self-test
behind so the same bugs can't come back unnoticed.

## Already known (don't re-investigate)

- **Not bugs:** the "teleported to the sky", "invisible character", "all UI
  gone after reset" and "camera jumped to the lab" in Harris's video of
  Oct 5. Claude was staging thumbnail shots in his Play session at the same
  time.
- **Already fixed:** the Gifts panel showed 2 columns and a cut-off third row
  that couldn't be scrolled to. A grid cell size of exactly 1/3 width rounded
  past the row width and wrapped to 2 columns.
  - The fix (in commit "Grids: 1 px slack…") is `-1` px slack plus
    `FillDirectionMaxCells`, in GiftsPanel, ShopPanel and ItemPickerUI.
  - Check that it holds, and look for the same pattern anywhere else.

## Phase 1: Static sweep (read the code; don't guess)

Go through every file under `StarterPlayerScripts/UI`, `Controllers` and
`Services`. For each bug you find, record the file, the line, what goes
wrong, the fix, and its severity (P0 to P2).

1. **Layout that can't fit.**
   - Find every fixed-size panel or card whose rows can add up to more than
     its height. Work it out from the constants, at the default size and under
     the 0.8 phone `UIScale`.
   - Each one must either fit or scroll, using a ScrollingFrame with
     `AutomaticCanvasSize`.
   - Check footers and bottom labels that sit on top of content.
   - Check text that can overflow: long item names, `NumberFormat` up to
     1e300, and long display names.
2. **Grids and lists.** Find UIGridLayout or UIListLayout setups that wrap,
   clip or exceed their parent at 844×390, 1366×768 and 1920×1080.
3. **Overlays.**
   - Two cards open at once.
   - A card opening over the welcome-back, daily or shop card.
   - Closing with ✕ or a tap outside.
   - Opening the same panel twice.
   - A panel whose state is wrong after it closes and reopens.
4. **Respawn and death.** Check every client controller after
   `CharacterAdded`:
   - Anything still holding the old character, Humanoid or root.
   - Walk speed not restored after a heist.
   - A carry orb welded to a dead head.
   - Goal arrows pointing from the old root.
   - Prompts that stop working.
5. **Leaks.**
   - Connections, RenderStepped loops, tweens or spawned threads that never
     end when a panel closes, an event ends or a player leaves.
   - Instances that pile up: toasts, pops, EventObjects, pull cards.
   - Server tables keyed by Player that aren't cleared on PlayerRemoving.
6. **Remotes.** For every `OnServerEvent`:
   - Wrong types, NaN, ±inf, huge numbers, negative numbers, missing fields.
   - Another player's ids.
   - Spamming it 50 times a second.
   - Firing it before the data has loaded.
   - Firing it while `Carrying`.
   - Make sure each of these is rejected cleanly, with no error in Output and
     no state change.
7. **Economy invariants.**
   - Cash never goes negative, NaN or inf.
   - MAX and MAX ALL with exactly enough cash, and with $0.
   - Rebirth exactly at the cost.
   - Offline payout at the 4 h cap.
   - Free pulls never raise the pad price.
8. **Events.**
   - An override during an override.
   - `/event off` while the info card is open.
   - An event ending mid-coin-grab or mid-crater-hold.
   - Rebirthing during an event.
   - A strike landing on a pedestal while the item is being carried.
9. **Live versus Studio.**
   - Debug commands, fake leaderboard rows and test grants must be off in live
     games.
   - **In a live game with no product IDs set yet** (true right now), the
     SHOP button and panel must not look broken. If every tile is hidden, the
     panel needs a proper empty state, or the button must hide until at least
     one item is set up. Decide which, implement it, and say which you chose.

## Phase 2: Run it

1. Use Studio's **Test → Local Server with 2 players**. In each player, go
   through `docs/UI_TEST.md` from top to bottom. Also:
   - Reset your character in the middle of every panel or card, and during a
     heist, a fusion, a pull and each event.
   - Resize the window to a phone shape using Studio's device emulator
     (iPhone 14 landscape).
2. Collect **every** error and warning in Output, from the server and both
   clients. Fix each one, or explain why it's expected.
3. Leave a client running for 15 minutes with an event cycle
   (`/eventclock`). Check memory and instance counts at the start and the end,
   and report any that keep growing.

## Phase 3: `/selftest` (Studio only, in DebugService)

Add a `/selftest` command that runs the invariants from Phase 1 against the
real services and prints PASS or FAIL lines:

- Fuzz every remote with bad arguments; there must be no errors and no state
  change.
- A data round trip through `toDisk` and back, after `reconcile()`.
- The `PlotLayout` and `StreetLayout` assertions.
- Every SoundConfig slot resolves.
- Every UI panel builds and destroys cleanly at both scales, with no leftover
  instances.
- NumberFormat edge cases.
- Event schedule determinism.

It must never touch a live save. It runs only on the mock profile or in
`FT_StudioTest_1`.

## Phase 4: Report

- CLAUDE.md gets one line about `/selftest`, and UI_TEST gets a "Reset and
  respawn" section.
- `luau-lsp analyze` reports no new errors.
- End with a table of every bug found: severity, what it was, and fixed or
  left open with the reason. Put anything that's a design call rather than a
  bug in a separate list for Harris and Claude. Push and open a PR into
  `main`. Don't merge it.
