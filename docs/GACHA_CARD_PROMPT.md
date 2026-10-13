# Gacha Pad odds card, Pet Sim 99 / Bubble Gum Sim style (build prompt for Claude Code)

Do this **after** `COMBAT_FEEL_PROMPT.md`. Run `git pull` on
`world-redesign`, then commit and push to `world-redesign`. **If your
session forces another branch, say so in the FIRST line.** Reply in 8
lines or fewer.

---

## Why

Today the Gacha Pad's label is "GACHA", a price pill, and two lines of tiny
text:

```
Common 77.6 · Rare 18 · Epic 3.5 · Legendary 0.78 · Mythic 0.086 · Secret 0.0035%
Golden 6.9% · Diamond 1.4% · Rainbow 0.1…
```

Below that sit three stacked default prompts: Pull, Pull ×10, and "?".
Harris calls it "a bunch of messy buttons". He sent two references:

- **Pet Simulator 99's egg card:** a rounded card above the egg, with one
  pet icon per pet, each with its %.
- **Bubble Gum Simulator Infinity's egg card:** a title, a 3×2 grid of
  pet tiles with the % in the rarity colour, unfound pets as **black
  silhouettes**, an (i) button, a price pill, and one row of round
  key buttons under it (`1 Hatch` · `E Multi` · `R Auto`).

Build the Fusion Lab version of that: a card that shows **what orbs are
inside** and their odds, plus one clean button row.

## 1. The card (your own pad, when you're near)

**Placement and visibility:**

- A BillboardGui above your own Gacha Pad, built on the **client**, so it
  can read your Index and show silhouettes. Mark it `OwnerOnly`.
- `AlwaysOnTop = false`, `LightInfluence = 0`, a `DistanceLowerLimit`, as
  the world label rules say.
- It fades in within about 22 studs of the pad and out beyond. Far away,
  and on other players' pads, there's only the "GACHA" title and the price
  pill, as now.

**Layout, from the top:**

- **Header:** "GACHA PAD" in the Fusion Lab display font.
  - On the right, an **(i)** button.
  - When your luck is above ×1, a `🍀 Luck ×1.15` pill.
  - During an event that changes pull odds, the event chip
    (e.g. `☄ Meteor Shower`).
- **3 × 2 grid, one tile per tier** (Common … Secret):
  - **Orb:** the tier's orb, in the `UIKit.TierOrb` look, with the tier
    colour and shine.
  - **%:** big, in the tier colour, with the ink stroke. Run it through
    the existing percent formatter: `77.6%`, `0.0035%`.
  - **Tier name:** small, under the %.
  - **A tier you've never found** (no orb of that tier in your Index): a
    dark **silhouette** orb with a "?". **Its % is still shown.** The odds
    disclosure must never hide.
  - A `Secret` tile gets a subtle animated shimmer stroke.
- **Mutation strip:** one row of small chips in the mutation colours, e.g.
  `✨ Golden 6.9%` `💎 Diamond 1.4%` `🌈 Rainbow 0.1%`. During an event,
  add that event's pull mutation chips.
- **Price pill:** gold, `$936 / pull`, or `FREE · 2 left` during the
  tutorial.

**(i) button:** opens a small panel listing every orb in each tier:

- the orb, its name and **its own %** (tier % ÷ number of orbs in the
  tier, which is how `PickRandomOfTier` rolls);
- whether you've found it;
- a line saying luck and events are already included.

Use a `UIKit.Modal`, centred like every card.

**The numbers:**

- They must be exactly what the roll uses. Add
  `FusionConfig.GetGachaOddsRows(luck, event)`, returning per-tier rates
  and pull-mutation rates. Build it on the same `GetGachaRates` /
  mutation functions as the roll and as `FormatOdds`. `FormatOdds` stays
  for other callers, built on the new function.
- The server owns luck. Ship the luck number and the odds event with the
  sync, or as pad attributes, so the client card shows the server's
  numbers. Refresh on every sync (rebirth, luck potion, event start/end),
  the same moments `refreshLabel` runs now.
- Delete the two text lines from the server pad label. They're replaced.

## 2. One button row instead of three prompts

- Set the pad's `PullPrompt`, `Pull10Prompt` and `HelpPrompt` to
  `Style = Custom`. Draw them on the client, through
  `ProximityPromptService.PromptShown` / `PromptHidden`, as **one row of
  round buttons** under the card, BGSI-style:
  - **[E] Pull** with the price;
  - **[R] ×10** with the ×10 price;
  - **[?]**, the help prompt (H).
- Each button:
  - shows its key on desktop and the gamepad glyph on a controller;
  - on touch is a ≥ 44 px tap target that calls `InputHoldBegin` /
    `InputHoldEnd`;
  - presses in when used (`UIKit.SelectFeedback`).
- The prompts, their keys, the server handlers and costs stay exactly as
  they are. Only the look changes. Every other prompt in the game keeps
  the default style.
- **Tutorial:** the `pull` / `pull2` steps' hand and arrow must point at the
  new **[E] Pull** button. Check `TutorialController.handTarget` /
  `GoalMarkerController`. `/selftest`'s tutorial drive must still pass;
  run it with `/tutorial reset`, since Studio now skips the tutorial on
  join.

## 3. Compliance (Paid Random Items)

Cash packs make the gacha Robux-reachable, so:

- Every outcome's numeric odds show **before** pulling, on the card
  itself. A bare (i) is not enough, so the tiles stay visible whenever the
  buttons are.
- The luck pill and the event chip are the live disclosure of active
  modifiers. They update the moment luck or the event changes.
- Silhouettes hide the **orb's look**, never its odds.

## Check

- `luau-lsp analyze` shows no new errors.
- **New `/selftest` lines:**
  - "gacha card: each tier's % equals `GetGachaRates` at the server's
    luck". Read the client's rendered text and compare it at luck ×1 and at
    `/rebirths 3`.
  - "gacha card: the (i) panel's per-orb % sum to each tier's %".
  - "gacha card: an unfound tier is a silhouette and still shows its %".
  - "gacha buttons: the 3 custom buttons are visible near the pad, each
    ≥ 44 px on phone, and none on other players' pads".
  - "text fits" for the card on desktop and phone.
- No FAILs overall.
- Harris looks at it in Studio:
  - walk up to the pad: the card fades in, with tiles, %, the mutation
    strip and price;
  - E pulls, R pulls ×10, ? opens help;
  - `/rebirths 3`: the luck pill appears and the %s change;
  - phone emulator: the buttons are tappable.
- Update `docs/systems/items-and-fusion.md` (the odds disclosure) and
  UI_TEST.
- Say which branch you pushed to.
