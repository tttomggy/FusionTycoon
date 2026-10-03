# Fusion Tycoon — Events: lab weather on a shared clock + Admin Abuse (build prompt for Claude Code)

Paste everything below into Claude Code **after `docs/HEIST_PROMPT.md` is
done**. Same branch (`world-redesign`), same open PR to `main`. Don't merge.

---

This pass adds what made Grow a Garden and Steal a Brainrot explode:
- **events on a global clock**, so every server gets the same one at the same
  minute,
- weather you can **see** in the sky,
- **event-only mutations**, so there's always a reason to be online for the
  next one,
- a weekly **Admin Abuse** that the owner runs live.

The design is fixed. The canvas board **"Events · weather on a shared clock +
Admin Abuse"** shows it, and every number is in this file.

Read `CLAUDE.md` first and follow it: config tables for numbers, UITheme for
every colour and font, UIKit for screens, `SyncTycoon`, RemoteEvents, the
service lifecycle, server authority, the light caps, no new Highlights, and
`luau-lsp analyze`. After each phase, run the type check, fix every new error
in files you touched, and commit the phase on its own.

---

## Phase 1 — The clock and EventService

**`Shared/Config/EventConfig.lua`** (new, `--!strict`) holds every number below.

**The schedule is UTC wall-clock, and deterministic, so all servers agree with
no messaging:**

| Slot | Event |
|---|---|
| every hh:00 | **Night**, 10 min. 30% of nights are a **Void Moon** instead |
| every hh:15, hh:30, hh:45 | one **weather**, picked by weight: Golden Rain 40, Power Surge 35, Meteor Shower 20, Rainbow Storm 5 |

- The pick for a slot is a pure function of the slot's start time:
  `EventConfig.GetEventForSlot(slotStartUnix)` uses
  `Random.new(slotStartUnix)`. Every server, and every client, computes the
  same lineup.
- `EventConfig.GetSchedule(nowUnix, count)` returns now, next and then, for the
  board and HUD.
- Durations: Golden Rain 5 min, Power Surge 5 min, Meteor Shower 3 min, Rainbow
  Storm 5 min, Night / Void Moon 10 min.
- **EventService** (new, `--!strict`):
  - Every second, it works out which event should be active now from
    `os.time()` and starts or ends it.
  - It publishes `workspace` attributes `EventId`, `EventEndsAt` and
    `EventStrength` (default 1). Clients render everything from those.
  - An admin override (Phase 5) can force an event: it replaces the scheduled
    one until it ends, then the clock resumes.
- **Effect hooks** other code reads; there are no globals sprinkled around:
  - `EventService.GetMutationOddsMultiplier(mutation, source)`
  - `EventService.GetFusionSuccessBonus()`
  - `EventService.GetGeneratorMultiplier()`
  - `EventService.GetFusionEventMutation()`

  Wire them into `MutationConfig.Roll` (pass a multiplier in; don't require
  EventService from shared config), into the fusion chance, and into
  `IncomeInputs` as `EventGeneratorMultiplier`. It applies to generator income
  only.
- **Debug (Studio):**
  - `/event <id> [minutes]` forces an event.
  - `/event off` ends it.
  - `/eventclock <offsetMinutes>` shifts the clock so the schedule can be
    tested.

## Phase 2 — Event-only mutations and the Index

**MutationConfig gains three mutations, and ranks are now ordered by
multiplier.**

| Mutation | Rank | Income × | Source |
|---|---|---|---|
| Golden | 1 | 2 | pulls / fusions (as now) |
| **Charged** | 2 | 3 | Power Surge lightning only |
| Diamond | 3 | 5 | pulls / fusions |
| **Void** | 4 | 8 | Void Moon fusions only |
| Rainbow | 5 | 12 | pulls / fusions |
| **Celestial** | 6 | 20 | Meteor Shower cores only |

- Saves store the mutation **name**, so changing ranks is safe. Check the
  fusion rules (lowest rank kept, best input kept) still read right with the
  new order.
- Event mutations have **0** normal pull/fusion chance. Only their event grants
  them.
- **Colours:**
  - `Mutation.Charged` `#7DF9FF`, satellites 3, a lightning-blue Trail.
  - `Mutation.Void` `#A47BFF`, satellites 5, a dark core shell.
  - `Mutation.Celestial` `#C9F0FF`, satellites 6, white with a star sparkle.
  - Pills, card strokes and orb rings follow the Polish 5 rules.
- **Index:** IndexConfig builds from MutationConfig, giving 17 items × 7
  variants = **119 entries**.
  - The panel grid gets 7 columns; fit them, and keep the phone layout.
  - Event columns show a small clock icon in unfound cells.
  - The page-complete bonus needs all 7 variants. That's fine; it's the
    long-term chase.
- **`/give`** accepts the new mutation names.

## Phase 3 — The five events

All visuals are client-side from the workspace attributes. All rewards are
server-side.

1. **Golden Rain** (5 min)
   - **Sky:** a warm gold tint (Lighting `ColorCorrection` TintColor lerp, and
     restore it after) and falling gold coin particles around the camera.
   - **Coins:** the server spawns a collectible coin in each **claimed** plot
     every 4 s, at a random spot on the walkable floor that's not inside a
     station or pedestal footprint. Use PlotLayout; add a helper if needed.
     - Max 30 live per plot. A coin despawns after 20 s.
     - Only the plot owner can collect: touch, checked on the server by
       distance.
     - Each coin pays **5 s of the owner's passive income** and shows a "+$X"
       pop.
     - Coins are Neon gold cylinders seen from the side; spin and bob them with
       FT_Hover.
   - **Odds:** Golden mutation odds ×3 on pulls and fusions.
2. **Power Surge** (5 min)
   - **Sky:** dark blue storm (tint, plus Atmosphere density up a little, then
     restored).
   - **Generators:** income ×1.5; GeneratorKit's band flickers.
   - **Lightning:** every 20 s, a strike hits **one random displayed item in
     the server**, on any plot.
     - Effect: a white-blue Beam from the sky, a flash and a thunder sound.
     - If the item has **no mutation**, 25% it becomes **Charged**.
     - The owner gets a toast "⚡ Your <item> got CHARGED!". The server feed
       shows it for Legendary and up.
     - Changing a displayed item's mutation must update the inventory, the
       pedestal visuals and labels, and the Index, then SyncInventory.
     - Skip items that are being carried in a heist.
3. **Meteor Shower** (3 min)
   - **Meteors:** 6 meteors at random times inside the window, each landing at
     a random point on the **street**, never inside a plot. Put spawn bounds in
     StreetLayout and keep them clear of the belts' edges.
     - Visual: a glowing rock falling diagonally, then a crater part with
       orange Neon cracks, as thin strips (no flat Neon circles).
   - **Crater prompt:** "Grab Meteor Core", hold 2 s, distance 8.
     - **First player to finish wins.** The server takes the first valid
       completion; everyone else gets "Too slow!".
     - The core gives one random item: Epic 60%, Legendary 30%, Mythic 9%,
       Secret 1%, with a **15% chance of Celestial**.
     - It uses the normal AddItem, Index and result-card flow.
     - Rebirth 0 players can grab too.
     - A crater disappears 60 s after landing whether claimed or not.
4. **Night / Void Moon** (10 min at hh:00)
   - **Night:**
     - Lighting `ClockTime` tweens to 0 and back after (store and restore the
       LightingService values).
     - Pedestal orbs and generator cores look brighter just from the
       darkness. **Don't raise any light above the light caps.**
     - Fusion mutation odds ×2.
   - **Void Moon** (30% of nights):
     - A purple moon and a purple tint.
     - Fusion success +10 percentage points, capped at 100%.
     - Every successful fusion has a 10% chance to come out **Void**; a Void
       roll replaces the normal fusion mutation roll.
5. **Rainbow Storm** (5 min, 5%)
   - **Sky:** slow hue-cycling sky tint and rainbow particles.
   - **Odds:** every normal mutation chance ×5 on pulls and fusions.
   - **Hype:** a server-wide banner when it starts.

**For every event:**
- A start banner (3-2-1 countdown, event name, one line of what it does).
- A sound.
- An end toast.
- Odds displays (FormatOdds) must show the event-boosted numbers while it's on.
  It's the same function, given the event multiplier.

## Phase 4 — HUD and the Event Board

- **HUD chip, top-centre:**
  - While an event runs: the event gradient, icon, name and live timer, e.g.
    "⚡ POWER SURGE · 3:12".
  - Otherwise a muted chip: "NEXT · ☄ METEOR SHOWER in 8:40".
  - Keep it clear of the Roblox top bar and the goal tracker.
  - Tapping it opens a small schedule card showing now, next, then, and Admin
    Abuse.
- **Event Board:** two big SurfaceGui boards on the street, one near each end,
  facing the plots. Add their positions to StreetLayout, with an assertion that
  they block no belt or gate. Each shows:
  - NOW, NEXT and THEN, with timers.
  - The Admin Abuse countdown line (Phase 5).
  - It updates every second on the client.
- **New tokens** per the board: `Gradients.GoldRain`, `Gradients.Surge`,
  `Gradients.Meteor`, `Gradients.Night`, `Gradients.VoidMoon`,
  `Gradients.Rainbow` (reuse the RainbowStops).

## Phase 5 — Admin Abuse

**`Shared/Config/AdminConfig.lua`:**
- `AdminUserIds = {}`.
- The place owner (`game.CreatorId` when `CreatorType` is User; the group owner
  when it's a Group) is always an admin.
- Add a comment telling Harris to put his UserId in the list too.

**`/admin`** (admins only, live servers too) opens the **Admin panel**
(UIKit):
- **Start event:** pick any of the 6 (including Void Moon), strength ×1/×2/×3,
  duration 5/10/15 min, and target **This server** or **All servers**.
  - Strength multiplies that event's effect: coin rate and value, surge
    multiplier, lightning rate, meteor count, mutation multipliers.
  - **Clamp everything** so ×3 can't break the economy:
    - coin value at most 15 s of income,
    - generator ×3 at most,
    - mutation odds ×15 at most.
- **Gift everyone:** a random item of a chosen tier (Common to Secret, with an
  optional mutation) to every player in this server or all servers. Each
  receiver gets a result card "🎁 ADMIN GIFT".
- **Luck ×3 for 10 min:** this server or all servers. It stacks with rebirth
  luck.
- **Broadcast:** a banner text, max 80 chars, through `TextService:FilterStringAsync`
  for the broadcast context; drop the message if filtering fails.
- **Set next Admin Abuse:** a date/time picker in the admin's local time,
  stored as UTC in a DataStore key `GlobalEvents/NextAdminAbuse`. Every server
  reads it on start and every 5 min, and the Event Board and schedule card show
  the countdown.

**All-servers** uses `MessagingService` topic `FT_Admin`:
- The payload carries the action, args and the sending admin's UserId. Every
  receiving server **re-checks** that UserId against AdminConfig.
- Respect the MessagingService limits.
- Log every admin action (warn, with who and what).

**Security:** every admin remote is validated server-side against AdminConfig.
Non-admins firing them get a suspicious-warn and nothing happens. The panel UI
is never created for non-admins.

## Phase 6 — Sim, docs, checks

- **`tools/econ_sim.py`:** add the event clock as an option, `--events`.
  - Golden Rain coins at 70% pickup efficiency.
  - Surge ×1.5 on generators.
  - Meteor cores: the player gets 1 of 6 per shower, assuming 6 players
    competing.
  - Night/Void fusion bonuses and the mutation odds multipliers.
  - Event-only mutations in the Index.
- Run `30 12` and `30 12 --events`, and paste both. **Target:** events speed
  Rebirth 1–3 by **no more than 15%**. If they do more, scale the coin value
  down (not the frequency) until it's ≤15%, and say what you changed.
- **CLAUDE.md:**
  - EventService and the clock rule ("deterministic from UTC slot time, never
    random at runtime").
  - The effect hooks.
  - Event mutations and the 119-entry Index.
  - Admin Abuse: AdminConfig, MessagingService topic, DataStore key, filtering.
  - The new debug commands.
- **`docs/UI_TEST.md` §17 "Events":**
  - Each `/event <id>` shows its sky, HUD chip and banner, then restores the
    lighting exactly after.
  - Coins pay 5 s of income.
  - Lightning can Charge a displayed item, and its pedestal visual updates.
  - Meteor race with 2 players: only one wins.
  - Void Moon shows +10% on the Fuse panel chance.
  - The Rainbow Storm odds board shows ×5 numbers.
  - The Index has 7 columns.
  - `/eventclock` walks through a full hour of the schedule.
  - `/admin` works for you and doesn't open for a second, non-admin test
    player.
  - An all-servers event: note it can only be fully tested in a live game with
    2 servers.
- `luau-lsp analyze`: no new errors. PlotLayout and StreetLayout assertions
  pass.
- Commit per phase, push `world-redesign`, and update the open PR's summary.
  **Don't merge.**
