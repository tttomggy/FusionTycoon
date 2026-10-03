# Fusion Tycoon — Polish 2 (build prompt for Claude Code)

Paste everything below into Claude Code, opened on the `world-redesign` branch.

---

This pass fixes two bugs from the Polish 1 playtest and makes generator upgrades visible in the world. The design is fixed: the canvas board "Polish 2 · generator bays" shows it, and every number is in this file.

Read `CLAUDE.md` first and follow it. That means PlotLayout for every position, UITheme for every colour, `PlayerDataService.SyncTycoon` for syncing, and `luau-lsp analyze` as the check. After each phase, run the type check, fix every new error in files you touched, and commit the phase on its own.

## What the playtest showed

1. **A pedestal stopped working.** The player displayed an item, the item didn't show, and after that, pressing E on that pedestal did nothing. Later, a "DISPLAY IT" on a Mythic said the pedestals were full, but one was visibly empty. The picker also said "Pedestals 2 / 4 used" with 3 items on display.
2. **A red toast appeared with no readable text.**
3. **"What do the upgrades even do?"** Generators add passive income, but nothing in the world changes when you buy one. The only visible income is the dropper's flat "+$50" pop. So upgrades feel like they do nothing.

---

## Phase 1 — Pedestal state bugs

There are two likely causes. Confirm both before fixing, and note the evidence in your summary.

**A. The client loses pedestal entries.**
- `GetTycoonSnapshot` sends `PedestalDisplays` as a sparse numeric table, e.g. `{[1]=uid, [3]=uid, [4]=uid}` with 2 empty.
- RemoteEvent arguments don't reliably keep a numeric table with gaps: entries after a nil can be dropped.
- So the client thinks occupied pedestals are empty. The picker count ("2 / 4 used") and `PlaceOnFirstEmpty` both go wrong.

Fix:
- Send `PedestalDisplays` with **string keys** (`{["1"]=uid, ["3"]=uid}`) in the snapshot, the same way it's already saved to disk.
- `TycoonController` already converts keys with `tonumber`, so keep that.
- Update the `TycoonSnapshot` type.
- Check every other remote payload for the same sparse-numeric-table pattern, and list what you checked.

**B. A rejection never clears the pending flag.**
- `ItemService.reject` fires `PlaceItemResult` as `{Success = false, Reason}` with **no `PedestalIndex`**.
- `ItemController.onPlaceItemResult` only clears `pendingPedestals[index]` when `PedestalIndex` is present.
- So one rejected request (e.g. "PedestalOccupied", caused by bug A) locks that pedestal on the client for the rest of the session, and pressing E there silently does nothing.

Fix:
- Every `PlaceItemResult`, success or failure, includes `PedestalIndex` whenever the request had one.
- Also, on the client, clear a pending flag automatically 5 s after it was set, as a safety net.
- Map every rejection reason to a short toast (`ToastController.Show(text, "Error")`). The toast must never be blank:

| Reason | Toast |
|---|---|
| PedestalOccupied | "That pedestal is already in use" |
| PedestalEmpty | "Nothing on that pedestal" |
| ItemInUse | "That item is already on display" |
| ItemNotOwned | "You don't have that item anymore" |
| NoPlot / DataNotLoaded | "Your lab isn't ready yet, try again" |
| anything else | "Couldn't do that, try again" |

- After any rejection, request a fresh sync: add a tiny client→server remote `RequestSync`, rate-limited to once per 2 s per player, that just calls `PlayerDataService.SyncTycoon`. That way the client's view is corrected immediately.

## Phase 2 — Blank toasts (UIGradient tints text)

A `UIGradient` on a TextLabel or TextButton tints the **text** as well as the background. `ToastController` puts the Red/Disabled gradient on the label itself, so the white text turns red on a red background and disappears.

**Fix:**
- In `ToastController`, the toast becomes a background Frame that carries the gradient, corner, stroke and shadow, with a **child** TextLabel (transparent background, white text) for the words.
- Audit every `UIKit.PairGradient` / `UIKit.Gradient` call whose parent is a TextLabel or TextButton (UIKit pills, the goal marker pill, buttons) and apply the same frame + child label split wherever the text is meant to stay its own colour.
- List each place you changed.

## Phase 3 — Generator bays: upgrades you can see

The two reserved bays (`PlotLayout.GENERATOR_BAYS`, 10 × 10 at (±24, −24)) now hold the five generators.

**Layout** (plot-local; add these to PlotLayout and update the overlap assertions):

| Generator | Bay | Local centre (x, z) | Footprint | Body height |
|---|---|---|---|---|
| basic_generator | left | (−27.5, −24) | 3 × 3 | 3 |
| ember_forge | left | (−24, −24) | 3 × 3 | 4 |
| flare_reactor | left | (−20.5, −24) | 3 × 3 | 5 |
| core_engine | right | (21, −24) | 4 × 4 | 6 |
| singularity_core | right | (26.5, −24) | 5 × 5 | 8 |

**Model** (new `GeneratorKit` in Shared/Modules, called by TycoonService). Every generator faces +Z, toward the lab centre:
- **`Body`**: footprint × height, Structure colour, SmoothPlastic, bottom at y 0.
- **`Band`**: a 0.3-tall ring around the Body at 40% of its height, in the tier colour (`FusionConfig.TierAccentColors[generator.Tier]`).
  - Below level 10: SmoothPlastic.
  - Level 10 and up: Neon.
  - Max level: Neon plus a soft PointLight in the tier colour (Range 8).
- **`Core`**: a ball on top. Its diameter is 55% of the footprint width. It uses the tier orb look already used by pedestal orbs (Glass outer plus a Neon inner ball at 65%). Tag it `FT_Hover` with Spin 30°/s and Bob 0.15 every 2 s.
- **`Screen`**: a SurfaceGui on the Body's front (+Z) face, PixelsPerStud 40 and LightInfluence 0.
  - A dark Ink panel showing "LV 12" in Display font, Cash colour.
  - The generator's name above it in Body font, Muted colour.
  - It updates on every sync.

**States** (server-driven from generator levels; rebuild on every change):
- **Locked** (`TycoonConfig.IsUnlocked` false):
  - A ghost: the same Body and Core shapes in ForceField material, Faint colour `#7D77A8`, Transparency 0.6.
  - A lock icon on the screen.
  - A small BillboardKit label with "LOCKED" and "<Required> LV N". Owner-only, MaxDistance 30.
  - No prompt.
- **Unlocked, level 0:**
  - A ghost in the tier colour, Transparency 0.5.
  - A label: "BUY" plus the price in Cash colour. Owner-only, MaxDistance 30.
  - A ProximityPrompt on the Body: "Buy" / "<Name> · $X". Range 7, HoldDuration 0, OnePerButton, `OwnerOnly = true`.
- **Owned:**
  - The real model, as above.
  - Prompt: "Upgrade" / "LV n → n+1 · $X". At max level, the prompt is disabled and the screen reads "MAX".

**Purchases:**
- The world prompt and the Upgrades panel both fire the **same existing `RequestUpgrade` remote**. Don't duplicate any upgrade logic.
- Hook the prompt client-side through `ProximityPromptService.PromptTriggered`, the same pattern Polish 1 used for pedestals.
- **On a successful upgrade:**
  - A small burst at the Core in the tier colour.
  - The Body scales up briefly (1.0 → 1.08 → 1.0 over 0.25 s, client-side).
  - The toast "+$X/s" in the Neutral style, where X is the gain in income per second including the multiplier.

**Income pops** (client, owner-only):
- Once a second, for each owned generator within 60 studs of the camera, float a "+$X" above its Core. X is that generator's income per second including the multiplier. Use the same look as the dropper cash pop, but in the generator's tier light colour, 0.8 s.
- Merge into one pop per generator per second; never stack.

**Upgrades panel:**
- Under the panel title, add one line in Body 13, Muted colour: "Generators earn every second, even while you're away. Find them in the back corners of your lab."
- Show the total generator income on the right of that line, e.g. "$210K/s".

**GoalConfig:**
- The goals `buy_basic_generator` and `unlock_ember_forge` now target the world generator (`Generator_basic_generator`, `Generator_ember_forge`) instead of `ui:Upgrades`, so the goal marker walks the player to the bay.

## Acceptance check (do all of these before saying you're done)

1. `luau-lsp analyze`: no new errors. PlotLayout assertions pass with the five generator footprints inside the bays.
2. Reproduce Phase 1:
   - Display on pedestals 1, 3 and 4 with 2 left empty.
   - The client's `TycoonController.GetPedestalDisplays()` must show all three.
   - `PlaceOnFirstEmpty` must pick 2.
   - Force a rejection (fire RequestPlaceItem for an occupied pedestal from the command bar) and confirm that pedestal still opens the picker afterwards and a readable toast shows.
3. Add to `docs/UI_TEST.md`:
   - The pedestals 1/3/4 test above.
   - Every toast is readable.
   - Buying a generator in the world builds the machine and shows the "+$X/s" toast.
   - Owned generators pop their income every second.
   - A 2-player test where the other player can't see your generator buy prompts.
4. Commit per phase, push `world-redesign`, and comment a summary on PR #4.
