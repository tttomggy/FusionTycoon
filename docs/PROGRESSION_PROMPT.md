# Fusion Tycoon: more to work toward (build prompt for Claude Code)

`git pull` on `world-redesign` first. Commit per phase, push, open a PR →
`main`. Don't merge. This is **part 4 of 4**: run it after combat.

---

Read CLAUDE.md and follow it. Harris: **"the game is too boring, I should
unlock more things, more purpose than just orbs."** This prompt adds three
things to chase:
1. Mutations that **stack**, like Grow a Garden.
2. A **second floor** of pedestals.
3. **Quests** that pay **power-ups** and weapons.

Every new number goes in config. Re-run `tools/econ_sim.py` at the end.

## Phase 1: Stacking mutations

**Today** an item has one mutation. **New:** an item has one **base**
mutation (none / Golden / Diamond / Rainbow) **plus any set of event
mutations** (Charged, Void, Celestial) on top. Example: a Rainbow
Legendary struck by Power Surge becomes **Rainbow + Charged**.

- **Data.**
  - `Item.Mutation` stays the base mutation.
  - Add `Item.EventMutations = { "Charged", "Celestial" }`: a sorted set,
    sanitised in `reconcile`.
  - Old saves: a Charged / Void / Celestial base moves into the set, with
    the base becoming none.
  - Round-trip it in `/selftest`.
- **Multiplier.** Additive, like Grow a Garden:
  `1 + Σ (mult − 1)` over every mutation the item has.
  - Rainbow (12) + Celestial (20) = **31×**, not 240×.
  - It all goes through `TycoonConfig.GetItemCashPerSecond(tier,
    mutations)`. Update every call site and display.
- **Sources add instead of replacing:**
  - a Power Surge strike adds Charged;
  - a Void Moon fusion adds Void;
  - a meteor core rolls Celestial on top of its normal roll;
  - a pull's event roll adds on top of its base roll.

  The same event mutation never stacks twice.
- **Fusion rules.**
  - Success: keeps the lowest **base** (as today) **and only the event
    mutations every input shares** (the intersection), then may roll.
  - Fail: keeps the best input untouched.

  The Fuse panel's prediction line covers both, for example "✨ Keeps
  GOLDEN + CHARGED".
- **Index.** A stacked item fills the entry for **each** mutation it has.
  The entry count is unchanged.
- **Visuals.**
  - Pills stack side by side: "RAINBOW · CHARGED".
  - Orbit satellites mix the colours.
  - The reveal card shows "+ CHARGED (stacked!)".
- **Economy.** Run `tools/econ_sim.py 30 12 --events` (teach the sim the
  stacking). **Target: events still speed Rebirth 1–3 by ≤ 15%.** If
  stacking pushes it over, cut event frequency or chances, not the
  stacking. Report the table.

## Phase 2: The second floor (Rebirth 2)

- **Layout.** A mezzanine over the back half of the lab with **4 more
  pedestals**, reached by neon stairs or a jump pad inside the walls.
  - Geometry goes in `PlotLayout`, extending the assertion block: no
    overlaps, inside the walls, headroom over the ground-floor stations.
  - Neon railings, using the materials rule.
- **Before unlock.** Every lab builds it. Under Rebirth 2 it's dim, with
  an owner-only label "🔒 2ND FLOOR · Rebirth 2" and no prompts.
- **Auto-display** (from part 1) fills ground floor 1 → 4 (5–6 with the
  pass), then floor 2.
- **Heists.** Floor-2 pedestals can be stolen like any other (thieves
  take the stairs). LOCK, the shield fence and the eject loop cover the
  whole floor.
- **Rebirth panel.** "Rebirth 2: unlocks the 2nd floor (+4 pedestals) and
  the Laser Gun."
- **Economy.** The sim gains the 4 extra slots from Rebirth 2. Rebirth 3
  should still land within ±10% of today's free time (2:45:59). If it's
  faster, raise `RebirthConfig` cost growth slightly. Report.

## Phase 3: Quests and power-ups

- **Daily quests.** 3 per UTC day, deterministic from the day like the
  event clock, from a pool such as:
  - Pull 20 times;
  - Fuse 5 times;
  - Get a Golden mutation;
  - Collect 15 Golden Rain coins;
  - Upgrade generators 25 levels;
  - Reach $X/s (scaled to the player);
  - Rebirth 1+ only: Steal 1 orb;
  - Rebirth 1+ only: Knock 3 thieves with a weapon.
- **Lab quest chain.** An endless numbered chain of harder milestones (#1,
  #2, …):
  - own 10 Rares;
  - complete the Common page of the Index;
  - fuse a Mythic;
  - …

  Chain rewards include the **Slap Glove** and **Banana Peel** (part 3),
  and bigger power-up stacks.
- **Power-ups.** Quest rewards are power-ups, stored in
  `PlayerData.PowerUps` with counts, and activated whenever the player
  wants from a HUD power-up row:

  | Power-up | Effect |
  |---|---|
  | 💸 Cash Burst | ×2 income, 5 min (stacks into the boost bank) |
  | 🍀 Lucky Charm | ×2 luck, 10 min |
  | 👟 Speed Boots | ×1.5 walk speed, 2 min (not usable while carrying) |
  | ⚗️ Fusion Spark | your next fusion gets +10 points |
  | 🧲 Coin Magnet | Golden Rain coins in 20 studs come to you, for one event |

  **Never sold for Robux**, and not in the shop. They're the free reward
  loop.
- **UI.**
  - A **QUESTS** button (📜) on the left column under GIFTS, with a
    ready badge.
  - `UI/QuestsPanel`: the daily 3, each with a progress bar and a CLAIM
    button, then the chain's current quest.
  - A small tracker under the NEXT GOAL card shows the nearest unfinished
    quest.
- **Server.**
  - Progress is counted server-side from the real events, never from the
    client.
  - `ClaimQuest { Id }` (C→S) re-checks that the quest is complete and
    unclaimed.
  - `UsePowerUp { Key }` (C→S) re-checks the count and conditions.
  - Add both to `RemoteEvents`.
  - Analytics: `QuestClaimed` and `PowerUpUsed`.
- **Studio.** `/quest complete <id>`, `/quest reset`,
  `/powerup <key> <n>`.
- **Economy.** The sim gets an average-player quest model: the 3 dailies
  per session-day, Cash Burst used at once. Free Rebirth 1 should stay
  **≈ 1:04 ± 10%**. Tune quest rewards, not the base economy.

## Check

- **`/selftest`:**
  - stacking round trip;
  - fusion intersection;
  - floor-2 assertions;
  - quest claim refused when not complete;
  - power-up refused at 0;
  - junk fuzz on the new remotes.
- `luau-lsp analyze` reports no new errors.
- **UI_TEST:** "Stacking", "2nd floor" and "Quests" sections.
- **CLAUDE.md:** entries for stacking, the 2nd floor, quests and
  power-ups.
- **Report:** the econ_sim tables (events %, Rebirth 1 / 3 times) and every
  number you had to tune.
