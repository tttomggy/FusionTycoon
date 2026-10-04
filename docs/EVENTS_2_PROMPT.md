# Fusion Tycoon — Events 2: every event explains itself (build prompt for Claude Code)

Paste into Claude Code on `world-redesign` (`git pull` first), after
HEIST_3 if that isn't done yet. Same open PR #6. Don't merge.

---

Read CLAUDE.md and follow it: EventConfig for every number, UITheme for every
colour and font, UIKit for screens, BillboardKit for world labels, PlotLayout /
StreetLayout for positions, the light caps, server authority, and `luau-lsp
analyze`. Run the type check after each phase and commit each phase on its own.
The canvas board **"Events 2 · explain every event, odds board, event mutation
reveal"** shows the design.

## What the playtest showed

1. **Nobody can tell what Power Surge does.** With `/event PowerSurge` running,
   nothing on screen changes except the chip.
2. **Golden Rain coins feel tiny** ("+$3.8K" when you have $2M). There are no
   coins on the street, only in your lab.
3. **Leftovers.** Coins and craters stay after the event ends.
4. **A Void has no moment.** Fusing one under the Void Moon gives the normal
   result card, with nothing saying it's rare or how you got it.
5. **Rainbow Storm doesn't say what to do.** Kids don't know that mutations
   come from pulling and fusing.
6. **The event chip only shows a schedule.** Tapping it should explain the
   event.
7. **Some sounds are bugged.** Mythic and Secret pedestals loop
   `rbxasset://sounds/bell.wav` forever (RarityVisuals `AmbientSoundId`), and
   Events reuses one sound slowed down for thunder.
8. **The machine's odds board is crammed.** The % values run together
   ("60%73%83%95%100%").
9. **Schedule bug (found on the video):** the schedule card listed POWER SURGE
   for :15, :30 and :45 in a row. `GetEventForSlot` seeds `Random.new(start)`
   with slot times only 900 apart, and Luau's Random gives correlated first
   draws for nearby seeds.

## Phase 1 — Schedule seed + cleanup

- **Seed.** Hash the slot start before seeding. For example
  `local seed = (start * 2654435761 + 0x9E3779B9) % 2^31`, then discard the
  first two `NextNumber()` draws. Keep it a pure function of the slot time, so
  every server still agrees.
- **Verify the distribution.** Add `tools/event_schedule_check.lua` (or a
  Python port of the same function) that walks 10,000 consecutive slots and
  prints:
  - the counts per event (they must land within 2 points of the weights /
    VoidMoonChance),
  - the longest run of the same weather.

  Put the numbers in your summary.
- **Cleanup at event end.** When an event ends (timeout, `/event off`, an admin
  end, or an override replacing it), destroy everything it made:
  - Server: lab coins, street coins, falling meteors, craters, their prompts.
  - Client: lightning rings, generator chips, the moon disc, sparkles, pops.

  Put each event's instances in one folder per event (`workspace.EventObjects.<EventId>`),
  so the end is a single `:ClearAllChildren()`. Add a check to UI_TEST: after
  `/event off`, `EventObjects` is empty on the server and the client.

## Phase 2 — Every event explains itself

**Event info card (tap the chip).** Replace the chip's schedule card with an
info card. Build it with UIKit at 400 px wide; on a phone, 90% of the width.

- **Header:** the event gradient, the icon and name, the live timer, and the
  line "Lab weather · every server".
- **WHAT'S HAPPENING:** 2 bullets.
- **WHAT TO DO:** 1 bullet.
- **"Can give:"** pills for the mutations this event affects.
- **NEXT:** the next 2 events with timers, plus the Admin Abuse line.
- **Between events:** the chip opens the same card for the NEXT event, with
  "Starts in 8:40".
- **Opens automatically**, once per event type per account (saved Tips id
  `event_<EventId>`), 1 s after the start banner, the first time a player sees
  that event.

**Copy.** Build every number from EventConfig so the text and the numbers
can't drift.

| Event | What's happening | What to do | Can give |
|---|---|---|---|
| Golden Rain | "Gold coins fall in your lab and on the street. Each pays {CoinIncomeSeconds}s of your income. BIG coins pay {BigCoinIncomeSeconds}s." / "Golden mutations are ×{GoldenRainGoldenOdds} more likely on pulls and fusions." | "Run and grab coins! Street coins go to whoever gets there first." | Golden (more often) |
| Power Surge | "Your generators make ×{1+SurgeGeneratorBonus} cash." / "Lightning strikes a displayed item every {LightningIntervalSeconds}s. 1 in {1/LightningChargeChance} strikes turns it CHARGED ×3." | "Put your best plain items on pedestals. Mutated items can't be charged." | Charged |
| Meteor Shower | "Meteors crash onto the street. Each one leaves a glowing core." / "Hold E on a crater for {MeteorGrabSeconds}s. First player wins a free Epic or better item, sometimes CELESTIAL ×20." | "Get to the street and race!" | Celestial |
| Night | "Fusions are ×{NightFusionMutationOdds} more likely to mutate." | "Fuse at your Fusion Machine now." | every mutation from fusing |
| Void Moon | "Every fusion is +{VoidMoonFusionBonus×100}% more likely to succeed (the odds board turns purple)." / "1 in {1/VoidChance} successful fusions comes out VOID ×8." | "Fuse as much as you can before the moon sets!" | Void |
| Rainbow Storm | "Every mutation is ×{RainbowStormOdds} more likely on pulls and fusions." | "Pull at your Gacha Pad and fuse. The arrow shows you where." | Golden, Diamond, Rainbow |

The start banner's one-line blurb (`EventConfig.Blurbs`) is the first "what to
do" sentence.

**Point the way.** While an event runs, the goal arrow
(`GoalMarkerController.SetOverride`, below any heist override) points at:
- Rainbow Storm: your Gacha Pad, and your Fusion Machine once you're standing
  on the pad.
- Night / Void Moon: your Fusion Machine.
- Meteor Shower: the nearest unclaimed crater.
- Golden Rain: the nearest street coin while any exist.

Clear the override at event end. On the Gacha Pad label during Rainbow Storm,
add a pill "🌈 MUTATIONS ×5 · PULL NOW". During Night / Void Moon, add a pill
on the machine's label: "🌙 FUSE NOW".

## Phase 3 — See it working

**Power Surge**
- A "⚡ ×1.25" chip over every generator in every lab. BillboardKit, client,
  MaxDistance 80; the number comes from the formula.
- The factory line's cash balls run 25% faster and brighter while it lasts.
- **Strike warning:** the server picks the target 3 s before the bolt and
  publishes it (attribute `LightningTarget` on the pedestal, set and cleared
  by EventService). Every client shows a cyan ring under that pedestal and a
  red pill "⚡ STRIKE IN 3·2·1" over it.
- After the bolt: "CHARGED!" (cyan) or "MISSED" (muted) pops over it for
  1.5 s.
- Your own items are targeted at least as often as anyone's: weight the pick
  by plot, then by pedestal, so one rich lab doesn't hog the strikes.

**Golden Rain**
- **Value stays based on your income, on purpose.** It's seconds of your
  income, so it grows as you grow. Don't base it on cash: that rewards hoarding
  and breaks rebirth saving.
- What changes is how it feels:
  - **BIG coin:** 1 in `BigCoinChance` (8) is double size, worth
    `BigCoinIncomeSeconds` (20) s, with a big gold "BIG +$126K" pop.
  - **Street coins:** every `StreetCoinIntervalSeconds` (6) s a coin lands on
    the street median, max `StreetCoinMaxLive` (8). Inside
    `StreetLayout.MeteorBounds`: off the belts, not on a plot.
    - Anyone can grab one, first come.
    - It pays the **grabber's** `StreetCoinIncomeSeconds` (6) s of income.
  - The event chip shows a running tally while it lasts, "💰 +$412K this
    rain" (session-only, per player). The end toast says "Golden Rain is over ·
    you earned +$412K".
  - Coin pops always show the full formatted amount
    (`NumberFormat.Money`), 22 px+, green; BIG ones gold and larger.
- **Balance:** re-run `econ_sim.py 30 12 --events` with the street and BIG
  coins modelled. Rebirth 1–3 must stay ≤ 15% faster. If it goes over, lower
  the coin **frequency** (CoinIntervalSeconds, StreetCoinIntervalSeconds), not
  the coin size: fewer, bigger coins feel better. Report the table.

**Meteor Shower**
- A red "☄ INCOMING" ring on the street where each meteor will land, 2 s
  before it hits.
- Craters show a pill "Hold E · free item".

## Phase 4 — Event mutation reveal

When a pull, fusion, lightning strike or meteor core produces an
**event-only mutation** (`MutationConfig.IsEventOnly`: Charged, Void,
Celestial), replace the normal result with a **special reveal card**. It also
appears on the lightning hit, which today is only a toast.

- **Look:** a radial background in the mutation colour, a small line "EVENT-ONLY
  MUTATION", a giant mutation word ("VOID!" / "CHARGED!" / "CELESTIAL!") in
  `Fonts.Display` 44, the item orb with its mutation shell (TierOrb +
  MutationPill), the item name, and a pill "VOID ×8 income".
- **"How you got it" box:**
  - Void: "🌙 You fused during a Void Moon. Only 1 in {1/VoidChance}
    fusions come out Void, and Void Moons are rare."
  - Charged: "⚡ Lightning hit it during a Power Surge."
  - Celestial: "☄ You found it in a meteor core."
- **Footer:** "Index +1 · Void 3 / 17" (`IndexConfig` counts).
- **Effects:** the major reveal effect, and a SERVER banner for everyone at any
  tier: "Player1 got a VOID Nova Heart under the Void Moon!".
- **Buttons:** DISPLAY / OK, like the normal card.

## Phase 5 — Index "how to get it"

Make each mutation column header in the Index tappable. A tap opens a small
box under the header row, the same UIKit style as the board:
- the name and multiplier in the mutation colour,
- one line on how to get it,
- "You have X / 17".

Lines:
- **Golden / Diamond / Rainbow:** "Any pull or fusion. Rainbow Storm makes it
  ×{RainbowStormOdds} more likely (Golden Rain: Golden ×{GoldenRainGoldenOdds})."
- **Charged:** "Only from lightning during a Power Surge."
- **Void:** "Only from fusing during a Void Moon (1 in {1/VoidChance} fusions).
  Void Moons come at :00 some hours, and on Admin Abuse Saturdays."
- **Celestial:** "Only from meteor cores ({MeteorCelestialChance×100}%)."

Event columns keep their 🕐 until found.

## Phase 6 — Odds board redo

Rebuild the machine's odds board SurfaceGui (FusionMachineService
`buildOddsBoard` and its TycoonService refresh) as a real table:

- **Board:** `PlotLayout.Machine.OddsBoardSize` → **9 × 6** studs; the
  assertion block decides whether it fits. If it overlaps, keep 9 wide and nudge
  `ODDS_BOARD` along x. SurfaceGui PixelsPerStud ~60.
- **Title:** "FUSE → TIER UP" (Display 28 equivalent) and, on the right, "more
  orbs = better odds".
- **Grid:** a UIGridLayout or one Frame per cell, 170 px label column + 5 equal
  columns.
  - Header row "ORBS IN 2 3 4 5 6".
  - One row per tier: an orb dot plus "Common → Rare" in tier colours.
  - Each % in **its own rounded cell** (Panel colour, 17 px+ bold, centred).
  - A 100% cell is teal.
  - The Mythic → Secret row says "R1" until you have Rebirth 1.
- **Footer:** "❌ Fail = keep your best orb, lose the rest · Secret needs
  Rebirth 1".
- **Move the mutation odds line off this board.** It stays on the Gacha Pad and
  in the Index.
- **During Void Moon** every cell turns the Void purple and shows the boosted
  number (through `FusionConfig.FormatOdds` as now). It goes back at the end.
- **Fuse panel:** apply the same treatment to the small chance chips under the
  chamber ("2 · 50%  3 · 62% …"). Give each count its own chip with a gap, and
  highlight the count matching how many orbs are in the chamber.

## Phase 7 — Sounds

- **New `Shared/Config/SoundConfig.lua`:** named slots, each
  `{ Id: string, Volume: number }`. Slots: `EventStart`, `EventEnd`,
  `CoinPickup`, `BigCoin`, `Thunder`, `MeteorImpact`, `EventReveal`, `Grab`,
  `Alarm`, `RevealMajor`, `RevealMinor`, `Toast`.
- **New `Shared/Modules/SoundKit`:**
  - `SoundKit.Play(name, parent?)`. An empty Id plays nothing.
  - Ids are preloaded through `ContentProvider:PreloadAsync` with a status
    callback. A failed Id warns **once** ("SoundKit: <slot> failed to load
    <id>") and then stays silent.
  - Sounds are created per play, parented to SoundService or the given part,
    and `Debris`-cleaned.
- **Route every existing sound** (HeistController, EventController,
  AnnouncementController, RevealEffects, TycoonService) through SoundKit.
  Move today's working ids into the matching slots. Leave a slot empty rather
  than reusing one sound for everything.
- **Delete the pedestal ambient loop** (`RarityVisuals.AmbientSoundId` and its
  PedestalVisuals code). Four Mythics ringing a bell forever is the "bugged
  music".
- **Add `docs/SOUNDS.md`:** a table of every slot, what it should sound like
  (e.g. "CoinPickup: short bright coin blip, < 0.5 s"), and where it plays.
  Harris fills the ids from the Creator Store.

## Phase 8 — Docs and checks

- **CLAUDE.md:**
  - the hashed seed,
  - `EventObjects` cleanup,
  - the info card plus the `event_<Id>` tips,
  - event arrows,
  - LightningTarget,
  - street / BIG coins,
  - the event mutation reveal,
  - the Index headers,
  - the odds board,
  - SoundConfig / SoundKit (no more ambient loop).
- **UI_TEST §17:** add a case for each of these:
  - the info card (tap, auto once, between events)
  - the arrows per event
  - surge chips and the strike warning
  - BIG and street coins and the tally
  - cleanup after `/event off` for every event
  - the Void / Charged / Celestial reveal (`/give` can't make one, so add
    `/eventmut <Charged|Void|Celestial>`, which gives a random Epic with that
    mutation through the real reveal path)
  - the Index headers
  - the odds board at desktop distance and on a phone
  - the schedule check output
  - an empty sound slot is silent with no errors
- **Checks:** `luau-lsp analyze` reports no new errors and the PlotLayout
  assertions pass. Commit per phase, push, and add a section to PR #6.
