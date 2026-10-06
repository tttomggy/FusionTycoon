# Events (lab weather)

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Events** (`EventService`, every number in `EventConfig`): lab weather
  on a shared UTC clock. **The schedule is deterministic from the UTC slot
  time, never random at runtime:** `EventConfig.GetEventForSlot(slotStart)`
  draws from a **lowbias32 hash of the slot start** (bit32 only; two draws
  discarded), so every server and client computes the same lineup with no
  messaging. Not `Random.new(slotStart)`: slots 900 s apart gave correlated
  first draws (three POWER SURGEs in a row). `luau
  tools/event_schedule_check.luau` runs the real EventConfig over 10,000
  slots (shares within 0.3 pts, repeats at each weather's own share). hh:00 Night 10 min (15% Void Moon);
  hh:15/:30/:45 one weather by weight (Golden Rain 40 / Power Surge 35 /
  Meteor Shower 20 / Rainbow Storm 5). An override (`/event`, admin) replaces
  the scheduled event until it ends, then the clock resumes.
  - EventService publishes workspace attributes `EventId`, `EventEndsAt`
    (server time), `EventStrength` (+ `EventClockOffset`, `AdminLuck`,
    `AdminLuckUntil`, `NextAdminAbuse`). Clients and leaf services read
    them through `Shared/Modules/EventState`; the effect formulas are pure
    functions in EventConfig, so a roll and its display always agree.
  - **Effect hooks** (no globals): `EventService.GetMutationOddsMultiplier
    (mutation, source)`, `GetFusionSuccessBonus()`,
    `GetGeneratorMultiplier()`, `GetFusionEventMutation()`. Wired as a
    multipliers table into `MutationConfig.Roll` / `GetChance` (shared
    config never requires EventService), a bonus into
    `FusionConfig.GetFusionChance`, and `IncomeInputs.EventGeneratorMultiplier`
    (generator income only). `FusionConfig.FormatOdds(luck, event)` shows the
    boosted numbers; every event change re-syncs players so labels refresh.
  - Strength ×1–×3 (admin) is clamped: coin ≤ 15 s of income, generators
    ≤ ×3, mutation odds ≤ ×15.
  - `tools/econ_sim.py <seeds> <hours> --events` runs the clock and compares
    with the same seeds without it. **Target: events speed Rebirth 1–3 by
    ≤ 15%.** The first spec numbers gave 20–27% (Void Moon the biggest
    part, coins minor), so they were cut: Void Moon 30% → 15% of nights,
    fusion bonus +10 → +5 points, Void roll 10% → 5%, coin 5 s → 3 s of
    income, Surge ×1.5 → ×1.25. Events 2 added BIG + street coins
    (modelled: 1 in 6 street coins per player) and lowered the coin
    FREQUENCY, not the size: lab coins every 4 → 10 s, street coins every
    6 → 15 s. Now +10.4% / +14.4% / +10.3% (30 seeds, 12 h). Any change to
    an event number: re-run and keep it ≤ 15%.
  - Rewards are server-side (EventService):
    - **Golden Rain:** lab coins (owner-only, touch + distance check, 3 s of
      income; 1 in `BigCoinChance` (8) is a **BIG** coin worth 20 s) and
      **street coins** (in `MeteorBounds`, max 8, anyone grabs, pays the
      GRABBER 6 s). Value is seconds of income on purpose (never cash).
      Per-player tally: Player attribute `GoldenRainTally` (chip "💰 +$X
      this rain", the end toast).
    - **Power Surge:** generators ×1.25; lightning every 20 s on a target
      picked by lab, then pedestal, marked `LightningWarningSeconds` (3)
      early (pedestal attribute `LightningTarget` + EventFx StrikeWarning);
      25% of a displayed item not yet Charged gets Charged STACKED on
      (carried items skipped; inventory, Index, pedestal visuals/labels,
      SyncInventory; "+ CHARGED (stacked!)" when it had a mutation).
    - **Meteor Shower:** craters on the street (`StreetLayout.MeteorBounds`;
      first finished hold wins a core: Epic 60 / Legendary 30 / Mythic 9 /
      Secret 1, the normal pull roll for the base and 15% Celestial on
      top; a "Hold E · free item" pill).
    - **Void Moon:** fusion +5 points, 5% Void replacing the normal roll.
  - **Cleanup:** every object an event makes lives in
    `Workspace.EventObjects.<EventId>` (EventService builds the folders at
    Init): server coins, craters and prompts; each client's own FX (sky,
    moon, lightning, meteors, rings, chips, pops, station pills). Any end
    (timeout, `/event off`, admin, an override) is one `ClearAllChildren`
    on each side; a meteor still falling leaves no crater.
  - **Event-only mutations** (Charged / Void / Celestial) from a pull,
    fusion, strike, core or `/eventmut` get the **reveal card**
    (ResultController: "EVENT-ONLY MUTATION", the giant word, how you got
    it, "Index +1 · Void 3 / 17") and a SERVER banner at any tier
    (`EventService.AnnounceEventMutation`, RareFusionAnnouncement Verb
    "event").
  - Visuals are client-side (`EventController`): start banner (straight away, 2.5 s, no countdown),
    end toast, sky from a captured Lighting baseline restored exactly
    (never raise a light: Night just darkens), band flicker through
    `LocalTransparencyModifier`, EventFx cues (strike warnings, lightning +
    CHARGED!/MISSED, meteors + ☄ INCOMING rings, coin pops: full
    `NumberFormat.Money`, BIG in gold), "⚡ ×1.25" chips over generators
    (`BillboardKit.Chip`), faster/brighter factory balls, the two street
    Event Boards (`StreetLayout.EventBoard`, built by WorldService).
  - **Every event explains itself:** the top-centre HUD chip opens the
    **info card** (`UI/EventInfoCard`, centred in the card band like
    every card, copy from `EventConfig.GetInfo`,
    built from the config numbers; `EventConfig.Blurbs` = the first "what to
    do" sentence). It **never opens itself**: a small ⓘ sits inside the chip's
    right end, and the first time a player sees each event type the chip
    itself pulses (UIScale bounce + a gold glow behind it) until they tap
    it once (that tap marks Tips `event_<EventId>`, TipConfig). A tap
    anywhere on the chip opens it; ✕, a tap outside it or the event ending closes it.
    Between events it explains the next one. **Event arrows:**
    `GoalMarkerController.SetEventOverride` (heist > event > goal): Rainbow
    Storm → your Gacha Pad (then the machine once you're on it), Night /
    Void Moon → your machine, Meteor Shower → the nearest crater, Golden
    Rain → the nearest street coin. Station pills: "🌈 MUTATIONS ×5 · PULL
    NOW" on your pad, "🌙 FUSE NOW" on your machine.
