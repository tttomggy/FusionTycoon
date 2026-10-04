# UI redesign — Studio test checklist

Run these in Studio after syncing with `rojo serve`. Each section starts from
**Play** unless it says otherwise. Plots and the Fusion Machine are built once
per session, so stop and restart Play between sections that change the world.

Handy Studio chat commands: `/wipe` (fresh save, kicks you — press Play
again), `/cash <amount>`, `/resetmultiplier`.

## 1. New save: goals 1 → 6 complete in order and pay out

1. Type `/wipe`, then press Play again.
2. The goal tracker sits at the top-left, below the Roblox top bar, and reads
   **NEXT GOAL · +$50 · Claim your base**.
3. Step on the green CLAIM pad. Check for:
   - [ ] A **Goal complete! +$50** banner.
   - [ ] The tracker border flashes gold and pops.
   - [ ] The tracker switches to **Upgrade your Basic Generator · +$60**.
   - [ ] The cash card goes up by $50.
4. Continue in order and confirm each goal pays and advances only after the
   previous one:
   - [ ] Upgrade your Basic Generator to LV 2 (+$60)
   - [ ] Get Basic Generator to LV 5 (+$100), with a **n / 5 Basic LV**
     count line
   - [ ] Pull at the Gacha Pad (+$150)
   - [ ] Put an item on a pedestal (+$200)
   - [ ] Fuse at your Fusion Machine (+$300); `/cash 5000` and pull until you
     have a pair.
5. Goal 7 (**Own a Rare item**) shows a **0 / 1 Rare** count line under the
   bar.
6. Rejoin (stop and Play) with saving enabled. The tracker resumes at the
   same goal and no reward is paid twice.

## 2. Inventory: grouping, DISPLAY, ALL SHOWN

1. `/cash 50000` and pull until you own two or more copies of the same item.
2. Press **ITEMS** at the bottom of the screen.
   - [ ] The title is **YOUR ITEMS** and there is no footer.
   - [ ] Identical items show as **one** card with an **xN** count, never
     several identical cards.
   - [ ] Cards are sorted best tier first, then by name.
   - [ ] Filter chips read **All N**, then one chip per owned tier (Mythic
     first). Tapping a chip filters the grid.
   - [ ] With fewer than 8 cards, the last cell is the dashed **Pull at the
     Gacha Pad** card.
3. Walk to an empty pedestal and press **E**.
   - [ ] The title is **PICK AN ITEM** with **For Pedestal N · best items
     first** under it.
   - [ ] Tapping a card gives it a white outline and a slight pop. The footer
     shows the item, **Earns $X/s with your xM · Pedestals n / 4 used**, and
     a green **DISPLAY** button.
   - [ ] DISPLAY puts that item on the pedestal and closes the panel.
4. Open the picker on another empty pedestal and select the same item.
   - [ ] Its card shows **ON PEDESTAL** while DISPLAY is still enabled (one
     copy is free).
5. Display copies until every copy is on a pedestal, then open the picker
   again and select it.
   - [ ] The button reads **ALL SHOWN** and is disabled.

## 3. Epic+ fusion shows the big card; DISPLAY IT fills a pedestal

1. `/cash 5000000`, then pull and fuse until a fusion succeeds into Epic or
   higher. Fusing Rares is fastest.
2. Check for:
   - [ ] The big card appears only **after** the machine's reveal animation
     finishes. It shows **FUSION SUCCESS**, the tier name (e.g. **EPIC!**), a
     spinning sunburst, a large orb, the item name, and **2x Rare → Epic ·
     earns $X/s on a pedestal**.
   - [ ] No top banner appears for the same fusion.
3. Press **DISPLAY IT** with at least one empty pedestal.
   - [ ] The item appears on the lowest-numbered empty pedestal.
4. Fill all 4 pedestals, get another Epic+ result, and press DISPLAY IT.
   - [ ] The inventory opens with the toast **Pedestals full · remove one
     first**.
5. Pull an Epic+ item from the Gacha Pad.
   - [ ] The big card reads **YOU PULLED** without the "2x … →" part.
6. Mythic only: the camera shakes when the card appears.

## 4. A failed fusion shows the AGAIN row

1. Fuse until a fusion fails. Lower odds such as Legendary make this
   quicker.
2. Check for:
   - [ ] A bottom row above the HUD buttons with a faded orb, **So close…**
     and **Fusion failed · you kept 1 <Tier> (<item>)**.
   - [ ] It stays for about 3 s.
3. **AGAIN**
   - [ ] It is violet and enabled only while you stand at your machine and
     still have another pair.
   - [ ] Walking away, or running out of pairs, greys it out.
   - [ ] Pressing it starts another fusion.
4. A Common or Rare gacha pull (default settings) pops a small skipped-card
   line above the bottom bar (Polish 8, §19); several stack, at most 3.

## 5. Phone layout (Device emulator: iPhone 14, landscape)

- [ ] All UI is scaled to 0.8.
- [ ] The cash card is above the goal tracker at the top-left. Nothing
  overlaps the Roblox top bar.
- [ ] The goal tracker is narrower, hides the reward, and uses a thinner bar.
- [ ] The bottom buttons are compact (84×60) with the label under the icon.
- [ ] The Upgrades and Inventory panels fill about 92% of the width, and the
  inventory grid has 3 columns.
- [ ] Every button is comfortably tappable (44 px or more).

## 6. Two-player visibility (Test → Clients and Servers → 2 players)

As Player 2, look at Player 1's plot:

- [ ] You **cannot** see Player 1's CLAIM label (before Player 1 claims) or
  their **EMPTY** pedestal labels.
- [ ] You **can** see Player 1's filled pedestal labels (tier, item, +$X/s).
- [ ] You **can** see Player 1's plot sign: **FREE LAB / Step on the green
  pad** before they claim, then **<NAME>'S LAB / $X/s · best: <tier>**. It
  updates within about 5 s.
- [ ] Player 1 removing an item makes the label disappear for Player 2,
  without an EMPTY label appearing for Player 2.

## 7. Spot checks

- [ ] Pad labels (GACHA, MULTIPLIER, COLLECTOR) are no longer visible
  through walls, and fade out beyond about 26 studs.
- [ ] GACHA's detail line reads **Common 78% · Rare 18% · Epic 3.5%**.
- [ ] MULTIPLIER reads **x1 → x1.5** and **$5K · press E**, then **x12.5
  MAX** with no detail line at the cap.
- [ ] Cash balls reaching the collector float a **+$X** over it (§11).
- [ ] UPGRADES shows a red badge with the number of affordable upgrades, and
  the button pulses while that number is above 0.
- [ ] Tapping an unaffordable upgrade shows the red **Need $X** toast.
- [ ] Pulling with too little cash shows **Need $X for a pull** as a toast,
  not a banner.
- [ ] A Legendary or Mythic display or fusion by anyone shows the server
  banner. Mythic uses the taller red **SERVER · MYTHIC** variant.

## 8. World (world redesign)

Studio setup first (scripts can't do these):

- [ ] Set **Lighting → Technology** to **Future**.
- [ ] Delete **Workspace → Baseplate**. WorldService also removes it at
  runtime, but it shouldn't be saved in the place.
- [ ] Set **Game Settings → Max Players** to **12** (one per plot slot).

Then press Play:

- [ ] **Spawn** lands on the street in front of your own gate (the purple
  sign reads FREE LAB, then your name once claimed). Respawning (reset)
  puts you back there.
- [ ] **Layout.** Everything in the plan is within a short walk of the gate:
  the claim pad straight ahead, the factory line (five generators, the belt
  and the collector) along the left wall, the gacha and multiplier stations
  on the right, four pedestals across the middle, the Fusion Machine at the
  back, and an empty back-right corner (reserved). Nothing overlaps, and
  nothing clips through the walls.
- [ ] **Gate ramp.** Walking from the street onto the floor goes up the
  ramp. If it's backwards (a step instead of a slope), flip the 180° in
  `PlotKit.BuildGateRamp`.
- [ ] **Stations.** Each pad glows in its colour with a floating hologram:
  the gacha capsule spins and bobs, the multiplier chevrons rise and snap
  back, and the claim arrow bobs and disappears after claiming. The E
  prompt appears at about 7
  studs, and only the nearest prompt shows.
- [ ] **Factory line.** See §11 (the droppers were removed in Polish 3).
- [ ] **Pedestal orbs.** Display an item: the cap lights up in the tier
  colour and a glass orb (bigger for higher tiers) floats above it,
  spinning and bobbing. The label sits above the orb. Removing the item
  clears it.
- [ ] **Labels shrink with distance.** Walk away from a pad or pedestal
  label: it gets smaller like a real sign and never fills the screen up
  close (within 7 studs of the camera it hides, §11). Pad labels vanish
  past about 90 studs, filled pedestal labels past 70, and EMPTY labels
  past 25.
- [ ] **Fusion Machine.** A round platform with a violet rim, four leaning
  pylons and a floating core. The camera doesn't end up inside it. Fusing
  still plays the charge-up and reveal on the core. The odds board beside
  it is a real board facing the gate, angled toward the walkway.
- [ ] **Fuse All with 40 Commons.** `/cash 50000000`, pull until you have
  about 40 Commons, then stand at the machine:
  - [ ] The Fuse panel's **FUSE ALL** button shows 20 fusions.
  - [ ] Pressing it plays a 3 s charge-up, then **one** summary card (N
    fusions, upgraded/failed, tier chips with "−40 COMMON", BEST row).
  - [ ] DISPLAY BEST puts the best item on a pedestal.
  - [ ] With no pair of normal items, FUSE ALL only toasts **Nothing to fuse**.
  - [ ] Legendaries are never consumed.
- [ ] **Goal marker on a fresh save.** `/wipe` → Play → claim. A gold
  marker labelled **UPGRADE YOUR BASIC GENERATOR** floats over the Basic
  Generator at the front of the factory line (visible through walls), with
  a live "N studs" line and a pulsing gold ring on the floor. It hides
  within 8 studs. The output shows no "goal target … not found" warning.
- [ ] **Two players** (Test → Clients and Servers → 2 players): the two labs
  face each other across the street, with gates on the street. Empty slots
  show FREE LAB foundations, and a slot's foundation disappears when a
  player's lab is built there and returns when they leave.
- [ ] **Lighting.** Late-afternoon warm light with a soft violet haze. Only
  Neon parts bloom, and nothing looks washed out.

## 9. Polish 1

- [ ] **Pedestal prompt with 0 items.** `/wipe` → Play → claim, then walk
  to an empty pedestal. **E · Display / Pedestal N** shows, and pressing it
  opens the picker on its "Pull at the Gacha Pad" empty state. With items,
  it opens the picker as usual. With an item on the pedestal, it reads
  **Remove** and picks it up.
- [ ] **Two players** (2-player local server): you can't see, and can't
  trigger, the other player's pedestal prompts or EMPTY pills. You do see
  their filled pedestal labels.
- [ ] **Pads.** Each station pad shows a clean accent ring, a soft centre
  glow and its word (PULL / BOOST / BUY / CLAIM) with no triangle slices,
  readable walking in from the gate. If a word reads upside-down, the Face
  needs a 180° yaw in `BillboardKit.BuildPadFace`. After claiming, the
  claim pad goes grey and reads **YOURS**. The machine platform shows a
  violet ring, and the station and machine rims are thin bands on the side.
- [ ] **Less purple.** Pedestal caps are matte, with a thin glowing lip only
  when filled. The collector is matte gold with thin glowing edges.
  Wall strips are thin. Grass reads as grass, and the floor isn't
  black.
- [ ] **EMPTY pill.** Empty pedestals show a small "⊕ EMPTY" pill about 5
  studs up (owner only, hidden past about 20 studs). Filled labels sit
  above the orb.
- [ ] **Speed belts.** Standing on the green (south, −Z) belt with no input
  carries you toward +X at about 28 studs/s, and walking with the flow is
  about 44 studs/s. The blue belt goes −X. Ride each belt end to end: the
  rollers at the ends don't trap you, and chevrons slide along both belts.
- [ ] ~~Cash balls never ride a belt.~~ Superseded: cash balls are
  client-side and never use physics (Polish 3).
- [ ] **Spawn.** You still spawn on the street in front of your gate, and
  the spawn pad's edge doesn't snag you while riding the belt past it.

## 10. Polish 2

- [ ] **Pedestals 1, 3 and 4 (sparse displays).** `/cash 50000`, pull
  until you have 3 or more items, then display on pedestals 1, 3 and 4 and
  leave 2 empty. Then check:
  - [ ] In the client command bar,
    `require(game.Players.LocalPlayer.PlayerScripts.Controllers.TycoonController).GetPedestalDisplays()`
    lists all three (keys 1, 3, 4).
  - [ ] The picker footer reads **Pedestals 3 / 4 used**.
  - [ ] **DISPLAY IT** on an Epic+ result fills pedestal **2**
    (PlaceOnFirstEmpty).
- [ ] **Forced rejection.** With pedestal 1 filled, run this in the client
  command bar:
  `game.ReplicatedStorage.RemoteEvents.RequestPlaceItem:FireServer("<uid>", 1)`,
  where `<uid>` is another item you own (any `Uid` from
  `require(game.Players.LocalPlayer.PlayerScripts.Controllers.InventoryController).GetInventory()`). Then check:
  - [ ] A red toast reads **That pedestal is already in use**.
  - [ ] Pressing E on that pedestal afterwards still works (Remove), and
    the empty pedestals still open the picker.
- [ ] **Every toast is readable.** White text on red for errors
  (**Need $X**, **Need $X for a pull**, **Pedestals full · remove one
  first**, the rejection toasts). White text on grey for neutral ones
  (**Nothing to fuse**, **+$X/s**). None is blank.
- [ ] **Generators** (positions changed in Polish 3, see §11). After
  claiming, Basic Generator is already LV 1. The rest are faint ghosts
  with a lock on their screens and **LOCKED / <Required> LV N**, and
  Ember Forge becomes a tier-coloured ghost with **BUY / $400** at
  Basic LV 5.
- [ ] **Upgrading in the world.** Walk to the Basic Generator and press
  **E · Upgrade / LV 1 → 2 · $28**. Then check:
  - [ ] Its screen reads **LV 2** with **$8/s** under it (×1).
  - [ ] There's a burst at the orb and the body bumps briefly.
  - [ ] A grey **+$2/s** toast shows (scaled by your multiplier).
  - [ ] The prompt now reads **Upgrade / LV 2 → 3 · $X**.
  - [ ] Without enough cash, the prompt shows the red **Need $X** toast.
  - [ ] Buying from the UPGRADES panel gives the same toast and
    animation.
- [ ] **Unlocks and max.** `/cash 5000000`. Basic LV 5 unlocks Ember
  Forge (it becomes a BUY ghost). The band turns Neon at LV 10. At LV 25
  the screen reads **MAX**, the band glows with a light, and the prompt is
  gone.
- [ ] ~~Income pops over each generator.~~ Replaced by the collector pops
  (§11).
- [ ] **Upgrades panel.** Under the title: **Generators earn every second.
  They're the machines along the left wall of your lab.** The
  total generator income/s is on the right. The tabs and list sit below
  it without overlap (desktop and phone).
- [ ] **Goal marker.** On a fresh save, the two Basic Generator goals
  point at the Basic Generator. The "Unlock the Ember Forge" goal
  points at the Ember Forge.
- [ ] **Two players** (2-player local server): as Player 2 you can see
  Player 1's generators but **not** their BUY/LOCKED labels or their
  Buy/Upgrade prompts, and you can't trigger them.

## 11. Factory line (Polish 3)

Start each item from a fresh save (`/wipe`, then Play) unless it says
otherwise.

- [ ] **Layout.** Along the left wall, the five generators stand in a row:
  Basic (front, nearest the gate), Ember Forge, Flare Reactor, Core Engine,
  then Singularity Core (back).
  - [ ] Each faces the belt with a Spout halfway up its belt side. The
    Spout has a lip glowing in the tier colour. Locked and buy ghosts show
    the Spout as a ghost too.
  - [ ] The dark belt with gold edge strips runs from the front to the
    gold Collector in the back-left corner. The Collector has glowing
    edges and a warm light.
  - [ ] The back-right corner is empty.
  - [ ] You can walk on the belt, and it doesn't carry you.
- [ ] **Balls from the start.** Within 2 s of claiming, Basic Generator
  (LV 1) drops a grey ball from its Spout in a short arc onto the belt.
  - [ ] The ball rides to the Collector, drops in, shrinks away and pops
    a green **+$X**.
  - [ ] The generator's screen reads **LV 1** with **$2/s** under it.
- [ ] **Upgrading speeds it up.** `/cash 5000`, then upgrade Basic a few
  levels: its balls come visibly faster (one every 2 s at LV 1, one every
  0.5 s at LV 25). Higher-tier generators drop bigger, brighter balls.
  Legendary and Mythic balls light the belt.
- [ ] **Collector pops match generator income.** With **no items on
  pedestals**, watch the Collector for about 10 s.
  - [ ] Its pops (one every 0.5 s) add up to roughly the HUD's **$X/s**
    × 10.
  - [ ] The COLLECTOR label's **+$X/s** shows generator income only (the
    balls' total). The HUD shows the full total.
- [ ] **Pedestal pops.** Display items. Every 2 s each filled pedestal of
  yours within about 60 studs floats one **+$X** over its orb, in the
  item's tier light colour (pedestal income × multiplier × 2). Other
  players don't see them.
- [ ] **Collector + pedestal pops match the HUD.** With items displayed,
  stand where you can see the collector and the pedestals for about 10 s.
  The collector pops plus the pedestal pops together add up to roughly the
  HUD's **$X/s** × 10.
- [ ] **Cash still comes from the server.** The HUD cash keeps counting up
  every second at the same rate whether or not you're watching the balls,
  including from more than 120 studs away.
- [ ] **Labels too close.** Display an item, then walk so the camera is
  right up against its pedestal label (the big tier bar).
  - [ ] Within about 7 studs the label disappears.
  - [ ] Back off past about 8 studs and it returns, with no flicker at
    the edge.
  - [ ] The same works for the GACHA, MULTIPLIER and COLLECTOR labels.
- [ ] **Two players** (2-player local server):
  - [ ] From your lab you see balls running on the other lab's belt.
  - [ ] You see no "+$X" pops over their Collector and no COLLECTOR
    label.
  - [ ] Their pops still show on their own client.
- [ ] **Frame rate with everything maxed.** `/cash 1e12`, then buy and max
  all five generators (UPGRADES panel). Stand by the belt with the
  MicroProfiler or Shift+F5 open.
  - [ ] It stays smooth.
  - [ ] Live balls stay under 60 per plot (`#workspace.FactoryBalls:
    GetChildren()` is the pool size).
- [ ] **No droppers left.** No Dropper 1, Dropper 2 slot, old gold
  collector strip or DROPPER 2 label anywhere on the plot.

## 12. Rebirth + scale (Polish 4)

- [ ] **No more growing generators.** `/cash 1e12`, then press E on the
  Singularity Core's Upgrade prompt as fast as it allows, 20+ times.
  - [ ] Its body bumps each time but always settles back to 5 × 5 × 8.
    It never pokes through the fence, and its orb stays the same size.
  - [ ] Repeat for the Core Engine (4 × 4 × 6).
  - [ ] The Output window shows no "has drifted from its PlotLayout size"
    warning (the Studio guard checks 1 s after every bump).
  - [ ] Overlapping Fuse All charge-ups never leave the machine core
    bigger.
- [ ] **Multiplier Pad.** The pad label pill reads **x1 · LV 0/15**, then
  **x1.25 · LV 1/15**, with the next value and cost on the detail line.
  The UPGRADES footer pill matches. It climbs by +0.25 per level up to
  **x4.5 · LV 14/15**, then reads **x5 MAX** with the prompt gone.
- [ ] **Portal ready.** `/rebirthready` (sets cash to the cost):
  - [ ] The back-right portal's swirl turns opaque and spins.
  - [ ] Its base ring pulses and its light brightens.
  - [ ] Its owner-only label reads **READY · x1 → x1.5**, with a full bar
    and **$15M / $15M**.
  - [ ] Before that, the swirl is translucent and still, and the pill reads
    **REBIRTH · $15M**.
- [ ] **Panel and two-step confirm.** Hold E at the portal (0.5 s), or tap
  the HUD pill once you have a rebirth.
  - [ ] **REBIRTH n** shows the INCOME and LUCK cards, YOU KEEP / YOU
    RESET, the bar and the caption.
  - [ ] Not ready: the button reads **Earn $X more** and does nothing.
  - [ ] Ready: **REBIRTH** opens **ARE YOU SURE?**. **Cancel** closes it
    with nothing sent. **REBIRTH** there rebirths.
  - [ ] On a phone (iPhone 14 landscape) the panel fits, scrolls if
    needed, and every button is at least 44 px.
- [ ] **After a rebirth.**
  - [ ] There's an orange flash and a **REBIRTH 1!** card with **Income
    x1.5 · Luck +5%**.
  - [ ] Cash is $0.
  - [ ] Basic Generator is LV 1, and the other generators are locked
    ghosts again.
  - [ ] The pad is x1 · LV 0/15, and the gacha is **$250 / pull**.
  - [ ] Every item and every pedestal is intact.
  - [ ] Pedestal labels and generator screens show the new ×1.5.
  - [ ] The "Rebirth for the first time" goal pays $25,000 into the new run.
- [ ] **Shows everywhere.**
  - [ ] The HUD shows an orange **⟳ 1 · x1.5** pill beside the Multiplier
    pill (hidden at 0).
  - [ ] The leaderboard has **Rebirths** as its first column.
  - [ ] Everyone gets the **SERVER · REBIRTH** banner, "<Name> reached
    Rebirth 1!", including you.
- [ ] **Rejoin** with saving enabled: Rebirths, the HUD pill and the portal's
  next cost ($48M for Rebirth 2) persist.
- [ ] **Two players:**
  - [ ] Player 2 sees Player 1's rebirth banner.
  - [ ] Player 2 does **not** see Player 1's portal label or its Rebirth
    prompt.
  - [ ] Player 2 does see Player 1's portal itself.

## 13. Depth (Secret tier, mutations, Index, Pull ×10)

Studio shortcut: `/give <itemId> [mutation]`, for example
`/give legendary_core golden` or `/give secret_horizon`. It makes all of this
testable without luck.

- [ ] **Pull ×10.** `/cash 1e9`, then stand on the gacha pad.
  - [ ] A second prompt, **R · Pull ×10**, sits under the E prompt without
    overlapping it.
  - [ ] Its object text shows a cost. Pressing it charges exactly that
    amount (watch the cash card).
  - [ ] Ten cards pop in quickly. The best one has a gold outline, and if
    it's Epic+ or Diamond/Rainbow, the big **BEST OF 10** card follows.
  - [ ] The pad price rises by ten pulls.
  - [ ] With too little cash: a red **Need $X for 10 pulls** toast, and
    nothing is charged.
- [ ] **Golden on a pedestal.** `/give legendary_core golden`, then display
  it.
  - [ ] The orb keeps its Legendary colour inside a gold glass shell, with
    gold sparkles.
  - [ ] The label reads **GOLDEN · LEGENDARY** in gold, with the name
    **Golden Star Core**.
  - [ ] Its $/s, and the HUD income contribution, are ×2 a normal Star
    Core's.
  - [ ] `/give legendary_core rainbow`: the shell cycles through the rainbow
    on the client, and the label's top line is rainbow-tinted.
- [ ] **Fusion keeps mutations safe.** `/give epic_flare golden` plus
  `/give epic_prism`, then fuse that pair at the machine (normal items pair
  first, so have no other Epics).
  - [ ] On success the Legendary is normal, or rarely a fresh mutation.
  - [ ] On a fail you keep the **Golden** Epic (same item), and only the
    normal one is gone.
- [ ] **Fuse All leaves mutated items alone.** Own 20+ Commons, one of
  them Golden (`/give common_spark golden`). Fuse All. The Golden Common is
  still there afterwards.
- [ ] **Mythic → Secret gate.** `/give mythic_rift` twice.
  - [ ] At 0 rebirths, the Fuse panel's Mythic tab reads **🔒 Mythic**, the
    chamber shows **🔒 Rebirth 1 to fuse Mythics**, and tapping the tab
    only toasts that.
  - [ ] The odds board's row reads **Mythic → Secret (R1)** with 7% under
    2 orbs.
  - [ ] After `/rebirths 1` the tab unlocks and 2 Mythics show **7%**.
  - [ ] A Secret result shows the dark orb (VoidShell glass, mint core)
    and the **SERVER · SECRET** banner.
- [ ] **Index.** Press **INDEX** (the teal button; the three bottom buttons
  fit at 844 × 390).
  - [ ] The header pill shows the bonus, and the line under INDEX reads
    **n / 119 found · every find +1% income · a full page +5%**.
  - [ ] The tabs show per-tier counts (Secret x/8).
  - [ ] Pull or `/give` something new: the toast **NEW IN INDEX · Golden
    Star Core · +1%** shows, and the cell fills.
  - [ ] Completing a page toasts **+5% · <Tier> page complete!**.
  - [ ] The HUD income rises by exactly the Index bonus (×1.01 per entry).
- [ ] **Odds after a rebirth.**
  - [ ] The gacha pad lists all six tiers and a mutation line.
  - [ ] After `/rebirths 2` (or a real rebirth) it reads **Common 77.9 ·
    Rare 18 · Epic 3.5 · Legendary 0.50 · Mythic 0.055 · Secret 0.0022%**
    / **Golden 4.4% · Diamond 0.88% · Rainbow 0.11%**.
  - [ ] The machine board's mutation line scales too.
- [ ] **Rejoin** with saving enabled: mutated items keep their mutation and
  the Index keeps every entry. An old save gets Index credit for what it
  already owns.
- [ ] **Two players:**
  - [ ] Player 2 sees Player 1's mutation shells and the
    **SERVER · RAINBOW** / **SERVER · SECRET** banners.
  - [ ] Player 2 does not see Player 1's owner-only labels or prompts.

## 14. Polish 5 (Fuse panel, cash rebirth, mutation marks, pad price)

- [ ] **Pad price.** On a fresh plot the Multiplier Pad shows its price
  pill and, while you can't afford it, a **Need $X more** caption.
  Pressing it short toasts **Need $X** and charges nothing.
- [ ] **Cash rebirth.** `/cash 2e7`:
  - [ ] The portal turns READY and the pulsing orange **REBIRTH!** button
    appears above the bottom row.
  - [ ] Rebirthing takes the cash (cash → $0) and the next cost reads $48M.
- [ ] **Fuse panel.** Press F at the machine.
  - [ ] Four Commons in the chamber show **78%**; six always succeed
    (**100%**). The count chips match the odds board's columns.
  - [ ] A fail keeps the best input (a mutated one if present, same item)
    and the card reads **Kept <name>, lost <n>**.
  - [ ] All-Golden inputs give a Golden result; mixed inputs give a normal
    item or a fresh roll.
  - [ ] AUTO-FILL into an empty chamber never takes mutated items (with a
    mutated orb in, it adds only that mutation, §19).
  - [ ] The Mythic tab is locked before Rebirth 1 (§13).
- [ ] **Mutation marks.**
  - [ ] `/give legendary_core golden`: the card and inventory show
    **GOLDEN ×2** with the orb ring and card outline. Displayed, the
    pedestal gets 2 orbiting satellites and the label's mutation chip.
  - [ ] Diamond: 4 satellites with trails. Rainbow: 6, cycling colours.
- [ ] **Phone layout** (iPhone 14 landscape): the Fuse panel fits, its
  tabs, grid and buttons are all ≥ 44 px, and nothing covers the top-left
  Roblox bar.

## 15. Polish 6 (lighting, Fuse panel fit, HUD, offline earnings)

- [ ] **Floor keeps its colour.** `/give mythic_rift Rainbow` four times and
  display all four. The walkway between the pedestals still reads as the
  Floor colour, not pink-white; the orbs carry the glow.
- [ ] **Fuse tabs fit.** At 1920 × 1080 all five tier tabs (Common …
  Mythic) show in one row with the count under each name, and Mythic shows
  🔒 before Rebirth 1. The same on a phone (iPhone 14 landscape). Nothing
  in the panel is smaller than 12 px.
- [ ] **Toasts never cover REBIRTH!.** `/cash 2e7` so REBIRTH! shows, then
  upgrade a generator (**+$X/s**), find a new Index entry, and try an
  unaffordable buy (**Need $X**). Every toast sits above REBIRTH!, and the
  toasts sit at the same height with REBIRTH! hidden.
- [ ] **Pull ×10 always shows.** At the Gacha Pad, **R · Pull ×10** shows
  whenever **E · Pull** does: with cash, without cash (pressing it toasts
  **Need $X for 10 pulls**), and while a pull card is up. Check on the
  touch emulator too.
- [ ] **Offline earnings.** Note your $/s, then `/offline 180`:
  - [ ] The **WELCOME BACK!** card reads **You were away 3h 0m** and
    **+$X**, where X = 0.25 × income × 10,800.
  - [ ] **Your lab earned 25% while you were gone**, a green **COLLECT**
    button, and no COLLECT ×2.
  - [ ] COLLECT bursts coins and adds X once; pressing again or
    re-syncing doesn't pay again.
  - [ ] `/offline 300` reads **4h+** and pays 0.25 × income × 14,400.
  - [ ] Close the card with ✕ instead: about 30 s later the cash jumps by
    X on its own.
  - [ ] `/offline 1` (under 2 min) shows no card.
- [ ] **Rejoin doesn't pay twice** (with saving enabled): leave, wait 3+
  minutes, rejoin. The card shows once; collect it, rejoin straight away,
  and there's no second card.
- [ ] **Stacks of the same item fill every pedestal.** `/give mythic_rift
  rainbow` five times.
  - [ ] Display a copy on pedestals 1, 2, 3 and 4 in turn from the picker's
    single stack card. Every place succeeds (none says **That item is
    already on display**), and the card counts the displayed copies.
  - [ ] Remove the one on pedestal 2, then put it back from the stack.
  - [ ] With 3 displayed (2 free), open the Fuse panel on Mythic
    (`/rebirths 1` first): it lists exactly the 2 free copies, AUTO-FILL
    takes only those, and fusing them succeeds. The 3 on pedestals are
    untouched.

## 16. Heist (stealing + lab shield)

Test → Clients and Servers, **2 players** (A and B). Both run
`/rebirths 1`, then `/give mythic_rift golden` and display it.

- [ ] **Protected at Rebirth 0.** Before `/rebirths 1`: A's sign shows the
  teal **🛡 PROTECTED · NEW LAB** pill, B sees no Steal prompt on A's
  pedestals, A's HUD has no LOCK chip or "?" button, and A's LOCK console
  label reads **🛡 PROTECTED · NEW LAB** with the prompt off. After
  `/rebirths 1` (wait ~5 s for the sign) the pill goes and the buttons
  appear.
- [ ] **Shield + eject.** On claim the shield is up 60 s: a pink ForceField
  fence round A's walls and a line across the gate, seen by both players.
  B walking in is moved to the street in front of A's gate.
- [ ] **The YOURS pad does nothing now.** Walking over it, or standing on it
  after `/shield 0`, never raises the shield.
- [ ] **Console lock.** The LOCK console stands inside the gate, right of
  the walkway, between the claim pad and the Gacha Pad, facing you as you
  walk in. Ready: label **🔒 LOCK LAB / READY · 60s shield** (pink pill),
  pink button, E prompt **Lock lab / 60s shield** within 8 studs (only A
  sees label and prompt). Pressing it: the fence goes up, the pill turns
  teal **LOCKED · 42s**, the button glows teal and the prompt is gone.
- [ ] **The HUD chip doesn't lock.** Under the cash card (beside it on a
  phone) A's chip reads **🔓 UNLOCKED** (muted, amber text). Tapping it
  never raises the shield: it toasts **Your LOCK button is just inside your
  gate** and the goal arrow points at A's LOCK console for 8 s, then goes
  back to the goal. Locked at the console it reads **🛡 LOCKED · 42s**
  (teal). There is no RequestLock remote any more.
- [ ] **Console reach (exploit check).** A presses the console from right
  in front of it: it locks. From A's client command bar, set the console
  prompt's `MaxActivationDistance = 100` and press it from more than 10
  studs away (e.g. by the gate): if the engine passes the trigger, the
  server refuses with **Get to your LOCK button inside your gate!** and the
  shield stays down (TryLock `TooFar`).
- [ ] **Recharge countdown on both.** When the shield ends (or `/shield 5`
  and wait), the console pill reads **RECHARGING · 20s** (muted, dim
  button, prompt off) and the HUD chip **RECHARGING · 20s** (muted). B can
  grab in that window. At 0 both return to ready. `/shield 0` skips the
  recharge. The claim shield and the 120 s shield after a loss go up
  regardless.
- [ ] **Alarm.** A unlocked and LOCK ready: B walks inside A's walls; A's
  chip turns red and pulses **🚨 RUN TO LOCK!** until B leaves or A locks
  at the console. While recharging it stays RECHARGING (no alarm).
- [ ] **The LOCK chip fits its text.** "🔓 UNLOCKED" sits in a pill just
  wider than the words (14 px each side, 44 px tall), not a 340 px bar;
  the chip grows and shrinks as the text changes (LOCKED · 42s, RECHARGING
  · 12s, 🚨 RUN TO LOCK!). The round "?" stays 8 px to its right through
  every change, on desktop and phone.
- [ ] **Steal and deliver.** Shield down, A more than 6 studs from the
  pedestal: B holds E on A's pedestal (**Steal**, ObjectText = the item's
  name and its +$/s, 1.5 s).
  - [ ] B's own screen: a full-width orange **🫳 YOU GRABBED <ITEM>! RUN
    HOME!** banner for 1.5 s, a pickup blip and a quick FOV punch, then
    the **RUN!** banner (2 s) turning into **GET HOME!** with a draining
    bar, and the arrow on B's gate.
  - [ ] **B sees the orb on B's own screen** over B's head (Golden shell
    and 2 satellites), with the red beam and the big **<item> · 45s** chip
    under THIEF; it follows B's jumps, and stays visible zoomed into first
    person. A sees the same. B walks slower (12), A faster (18).
  - [ ] A: the pedestal shows a red ghost ring and **STOLEN!** +$0/s, A's
    income drops by that item, a red **THIEF IN YOUR LAB!** banner reading
    **Catch them in 2…1…** then the distance, a red **THIEF!** arrow
    following B, and the alarm. A's speed is back to 16 when it ends.
  - [ ] B reaches home: **HEIST COMPLETE!** for B, the item (still Golden)
    in B's inventory with a new Uid; A gets the stolen card (shield up
    2 min), the pedestal is empty, and A's shield auto-raises for 120 s.
  - [ ] Server banner (Legendary+): **B stole a Golden <item> from A!** (Golden in its colour)
- [ ] **Grace window.** A stands 7 studs from the pedestal (just outside
  the guard radius) and B grabs: A walks straight into B, but nothing
  happens for 2 s; after that the touch saves it.
- [ ] **Guarded pedestal.** A stands right next to the pedestal (within
  6 studs): B's prompt reads **Owner is guarding** with no hold, and
  tapping it only toasts **The owner is guarding it!**. A steps away and
  it turns back into **Steal**.
- [ ] **Steal and tag.** B grabs, A touches B (within 5 studs): A gets
  **SAVED! You got your … back**, B **Caught!**, the item is back on the
  pedestal, the banner reads **A caught B!**. Both see a white flash ring
  at B, **CAUGHT!** over B's head, and the orb fly back onto the pedestal.
- [ ] **Timeout.** B grabs and waits 45 s: **Too slow!**, the item returns.
- [ ] **Steal timer (no HUD chip).** Right after any grab there is **no**
  steal timer chip on B's HUD. B's prompts on other filled enemy pedestals
  read **Steal in 42s** (the item label under it, no hold); tapping one
  toasts **You can steal again in 42s**. The red hand markers stay on. At 0
  the prompts read **Steal** again. After a delivered steal the HEIST
  COMPLETE card's sub-line reads **You can steal again in …s**. `/heistcd
  0` clears the timer.
- [ ] **Loss cap.** With A's shield dropped (`/shield 0`) after each loss,
  B steals 3 items in under 10 min: the 4th grab says **This lab has been
  robbed enough for now**.
- [ ] **Two thieves, one pedestal** (3 players): both hold E on the same
  pedestal at once; one carries it, the other is told **Someone's already
  carrying that**.
- [ ] **Owner can't remove mid-carry.** While B carries A's item, A's
  pedestal shows no Display/Remove prompt; a forced remove request is
  rejected (**A thief has it!**).
- [ ] **Owner can't rebirth mid-carry:** A's rebirth toasts **A thief has
  one of your items! Get it back first**.
- [ ] **Thief hands full.** While carrying, B's pull, Pull ×10, generator
  upgrade, Multiplier Pad and rebirth all toast **Get home with that item
  first!**; the Fuse panel's FUSE / FUSE ALL do too (no charge-up); B's
  own LOCK console toasts **Not while carrying!**.
- [ ] **Victim /wipe mid-carry:** A's `/wipe` kicks A; B gets **The heist
  was called off** and nothing is added to B.
- [ ] **Thief leaves mid-carry:** B leaves; the item is back on A's
  pedestal at once, and B's save (with saving on) doesn't have it.
- [ ] **Victim leaves mid-carry:** A leaves; B's carry ends (**The heist
  was called off**). With saving on, A rejoins still owning the item on
  its pedestal (the fail runs in `OnRelease`, before A's save).
- [ ] **Shutdown mid-carry** (saving on, close the server while B carries):
  both rejoin with the item still A's.
- [ ] **Thief dies mid-carry** (reset): **You dropped it!**, the item
  returns.
- [ ] **Exploit requests** (Studio command bar on B's client,
  `game.ReplicatedStorage.RemoteEvents.RequestSteal:FireServer({ OwnerUserId = …, PedestalIndex = 1 })`):
  a far pedestal, B's own pedestal, a shielded lab, an empty pedestal and
  a Rebirth-0 owner are all rejected, each with a `HeistService: rejected
  steal …` warning in the server output.
- [ ] **Locked teaser at Rebirth 0.** A at Rebirth 1 with a displayed item
  and the shield down; B at Rebirth 0 walks up to it: the prompt reads
  **🔒 Steal** / **Unlocks at Rebirth 1** at the normal distance, and
  tapping it only toasts **Stealing unlocks at Rebirth 1**. No hand marker.
- [ ] **Unlock line.** Before rebirthing, the Rebirth panel's unlock row
  reads **Stealing + Mythic → Secret fusion**. After the first rebirth the
  REBIRTH 1! card has **🫳 STEALING UNLOCKED: grab items off other labs'
  pedestals and run them home!** (the card is taller; LET'S GO below it).
  Later rebirth cards don't.
- [ ] **New goals.** After "Rebirth for the first time": **Lock your lab
  with the LOCK button** ($10,000; the goal arrow points at the LOCK
  console; only the console counts, not the claim shield or `/shield`),
  then
  **Steal an item from another lab** ($50,000; the marker points at the
  nearest grabbable enemy pedestal and moves as that changes). Delivering
  a steal completes it.
- [ ] **Hand markers.** At Rebirth 1+, every filled, unshielded, unguarded
  enemy pedestal has a red 🫳 marker above its label, from up to 60 studs.
  It goes when the lab's shield goes up, the owner guards it, or the item
  goes; all of them hide while you carry.
- [ ] **One-time tip.** The first time (this session) a Rebirth 1+ player
  walks inside a lab with something to steal: **Hold E on their pedestal to
  steal it!**. Walking into another one doesn't repeat it.
- [ ] **GUARDED chip.** A walks up to their pedestal: within 6 studs, B sees
  a teal **🛡 GUARDED** pill over it (above the label), B's red hand marker
  for it goes, and B's prompt reads **Owner is guarding**. A walks away and
  it's gone.
- [ ] **Guard ring.** While A is inside A's walls, each filled pedestal has
  a faint teal floor ring (6 studs), seen by both; the one A guards is
  stronger. A leaves the lab and the rings go. A Rebirth-0 lab shows none.
- [ ] **HOW TO HEIST card.** A real first rebirth (`/rebirthready`, then
  REBIRTH! at Rebirth 0; `/rebirths 1` skips the result card, so it won't
  trigger): pressing LET'S GO on the REBIRTH 1! card opens HOW TO HEIST.
  Four slides (GRAB 45s, GUARD, CATCH, LOCK 60s), ◀ NEXT ▶ and dots, GOT
  IT on the last. It doesn't auto-open again (rejoin with saving on, or
  rebirth again) until `/tips reset`. The round **?** button beside the
  LOCK chip always opens it.
- [ ] **3D scenes.** Each slide is a live 3D scene in the lab's look
  (floor, walkway, a wall with its gate gap) with **your own avatar** as
  YOU, animated (run / idle), looping every ~5 s:
  - [ ] **1 GRAB**: you walk to a Golden Mythic pedestal (shell and
    satellites), an **E** ring fills over 1.5 s, the orb lifts over your
    head with a red beam and you run to the blue **🏠 YOUR LAB** gate.
  - [ ] **2 GUARD**: you stand on the teal ring by your pedestal
    (**🛡 GUARDED**); a red thief walks up, **✋ Owner is guarding** pops,
    and they back away.
  - [ ] **3 CATCH**: the red thief runs with the orb; you chase and touch
    them: a white ring flash, **CAUGHT!**, the orb arcs back onto the
    pedestal.
  - [ ] **4 LOCK**: you run to the LOCK console and press; its button turns
    teal, the pink panels rise along the wall, **🔒 LOCKED · 60s** shows,
    and the thief walks into the wall and is pushed back.
  - [ ] The pills ("YOU", "THIEF", the item, GUARDED, CAUGHT!, LOCKED)
    track the actors. Only the slide on screen animates; closing the card
    removes the scenes (Explorer: no leftover ViewportFrames). With no
    character loaded yet, YOU is a default rig.
  - [ ] On a phone (Device emulator, ~390 px tall after the scale) the card
    fits: the scene shrinks, title, line and ◀ / NEXT ▶ stay on screen.
- [ ] **Each tip fires once** (then `/tips reset` to see them again):
  - [ ] **intruder**: B walks into A's unlocked lab; A gets **Someone's in
    your lab! Stand by your items or run to your LOCK button!**.
  - [ ] **guarded**: B stands at a pedestal A is guarding: **They're
    guarding it. Wait for them to walk away.**
  - [ ] **stealHowTo**: B's first walk into a robbable lab: **Hold E on
    their pedestal to steal it!**
  - [ ] **catch**: A's first time as a victim: the banner has a big **TOUCH
    THEM!** line and the red arrow throbs; the next steal doesn't.
  - [ ] **lockAfterLoss**: after A's first real loss card: **Tip: hit the
    LOCK button inside your gate before you leave your lab.**

## 17. Events (lab weather + Admin Abuse)

Plots are built once per session: restart Play after layout changes. Studio
profiles never save, so the Next Admin Abuse DataStore write needs a
published place with API access (otherwise it toasts "DataStore save
failed").

- [ ] **Each `/event <id>`** (GoldenRain, PowerSurge, MeteorShower,
  RainbowStorm, Night, VoidMoon): the start banner appears **at once** (no
  3-2-1 countdown) with one ping: the icon, name and one line on the
  event's gradient, gone after ~2.5 s;
  the HUD chip turns that gradient with a live timer
  ("⚡ POWER SURGE · 4:58"); the sky changes (gold tint + gold sparkles /
  storm tint + denser haze + generator bands flicker / dusk to midnight /
  midnight + purple tint + purple moon / slow rainbow tint + sparkles).
- [ ] **Exact restore.** Note Lighting.ClockTime (17.2), the
  ColorCorrection TintColor/Brightness and Atmosphere Density/Color before
  an event; `/event off` (or let it run out): a toast "<icon> <NAME> is
  over", the sky tweens back and every value matches the noted ones. The
  generator bands are solid again.
- [ ] **Golden Rain coins.** Gold coins (edge-on, spinning, bobbing) appear
  in your lab on open floor, never inside a station or pedestal, one every
  10 s, max 30, each gone after 20 s. Touching one pays **3 s of your
  income** (cash jumps by income × 3) with a green "+$X" pop (the full
  amount, 24 px). A second player can't pick up yours.
- [ ] **Surge income.** `/event PowerSurge`: the collector pill's generator
  income (and the HUD's income/s, generator share only) reads ×1.25 of what
  it was; back to normal when it ends. Pedestal rates don't change.
- [ ] **Lightning Charge.** `/event PowerSurge`, display a plain item: every
  20 s a white-blue bolt hits a displayed item somewhere with a flash (the
  Thunder slot is empty until a sound is chosen). When yours turns Charged:
  the event mutation reveal card (below), the pedestal orb gets 3 cyan
  satellites with a trail, the label and inventory show Charged, the Index
  gains the Charged cell; everyone sees the SERVER banner. An item being
  carried in a heist is never hit.
- [ ] **Meteor race (2 players).** `/event MeteorShower`: glowing rocks fall
  onto the street (never a belt, never a plot); each leaves a dark crater
  with orange crack strips and a glowing core. Both players hold **Grab
  Meteor Core** (2 s): only the first to finish gets the ☄ METEOR CORE
  card (Epic+ item, sometimes Celestial); the other gets **Too slow!**. A
  Rebirth 0 player can grab. Unclaimed craters vanish after 60 s.
- [ ] **Void Moon.** `/event VoidMoon`, open the Fuse panel: the success
  chance reads 5 points higher (2 Commons 55% → 60%) and the chips turn
  purple; the machine's odds board cells turn Void purple with the same
  boosted numbers, and go back at the end. About 1 success in 20 comes out
  Void. The banner line reads "Fuse as much as you can before the moon
  sets!".
- [ ] **Rainbow Storm odds.** `/event RainbowStorm`: the gacha pad's
  mutation line shows ×5 numbers (Golden 4% → 20%); the big SERVER · EVENT
  rainbow banner plays once.
- [ ] **Index.** The Index shows 7 variant columns (Normal + Golden,
  Charged, Diamond, Void, Rainbow, Celestial); unfound Charged / Void /
  Celestial cells show their event icon (⚡ 🌙 ☄), never a clock. It fits
  on a phone (the page scrolls).
- [ ] **`/eventclock`.** `/eventclock 0`, then step `/eventclock 15`, `30`,
  `45`, `60`: hh:00 is always Night or Void Moon, the others a weather; the
  HUD chip, the info card's NEXT rows and both street Event Boards agree at
  every step. Between events the chip is muted: "NEXT · ☄ METEOR SHOWER in
  8:40". The same weather three slots in a row should be rare (chance).
- [ ] **Street Event Boards.** The two boards past the street ends show NOW
  / NEXT / THEN with timers and the Admin Abuse line, ticking every second,
  and block no belt or gate.
- [ ] **`/admin`.** In Play Solo (your own account = the owner) `/admin`
  opens ADMIN ABUSE: start each event at ×1/×2/×3 for 5/10/15 min (the
  banner blurb says "ADMIN x3"), END EVENT, gift everyone (each player gets
  the 🎁 ADMIN GIFT card), LUCK ×3 (odds displays rise for 10 min),
  broadcast (≤ 80 chars, the counter stops at 80; everyone sees the
  SERVER · ADMIN banner, filtered), set next Admin Abuse (the chip card and
  boards count down to it in your local time). Every action prints a warn
  with who and what.
- [ ] **Non-admin.** In a 2-player local server (ids −1/−2, never admins)
  `/admin` does nothing for either player, and firing AdminAction from the
  command bar prints **SUSPICIOUS AdminAction** on the server and changes
  nothing.
- [ ] **All servers.** An ALL SERVERS action can only be fully tested in a
  live game with 2 servers: the second server applies it too and logs
  "FT_Admin from <id>". In Studio it toasts that it applied on this server
  only if MessagingService isn't available.

### 17b. Events 2 (every event explains itself)

- [ ] **Schedule check.** `luau tools/event_schedule_check.luau` (repo root)
  prints every event's share within 2 points of its target (they land
  within 0.3), the "next weather repeats" shares near each weather's own
  share, a longest run around 9, and **OK**.
- [ ] **Info card: tap.** Tap the event chip during any event: a card under
  it on the event's gradient with the icon, name, live timer ("3:12 left")
  and "Lab weather · every server"; WHAT'S HAPPENING (the numbers match
  EventConfig: e.g. Power Surge "×1.25", "every 20s", "1 in 4"), WHAT TO
  DO, "Can give:" mutation pills, NEXT (2 events + the Admin Abuse line).
  The X or the chip closes it. On a phone it's 90% of the width.
- [ ] **Info card: between events.** With nothing on, the chip opens the
  same card for the NEXT event, "Starts in 8:40". When that event starts
  with the card open, it switches to "… left".
- [ ] **No pop-up; the chip pulses instead.** After `/tips reset`, `/event
  GoldenRain`: the card does **not** open by itself, and there is **no**
  separate tag beside the chip. The chip itself pulses (a gentle scale
  bounce with a gold glow behind it). Tap anywhere on it once (the text or
  the ⓘ): the card opens and the pulse stops for good (end Golden Rain and
  start it again: no pulse). A different event type pulses once too.
- [ ] **ⓘ inside the chip.** A small ⓘ sits inside the chip's right end in
  every state (running event, muted NEXT); the chip text stays centred and
  never runs under it, on desktop and on a phone. Tapping the ⓘ or the
  text both open the card.
- [ ] **Info card closes.** With the card open: tapping anywhere outside it
  (the world, another HUD button) closes it; tapping the chip toggles it;
  ✕ closes it. When the running event ends, the open card closes itself.
- [ ] **Arrows per event.** Rainbow Storm: the goal arrow points at your
  Gacha Pad ("PULL HERE"); step on the pad and it moves to your Fusion
  Machine ("THEN FUSE"). Night / Void Moon: the machine ("FUSE NOW").
  Meteor Shower: the nearest unclaimed crater. Golden Rain: the nearest
  street coin. A heist arrow wins while it lasts; every event arrow clears
  at the end. Pills: "🌈 MUTATIONS ×5 · PULL NOW" over your pad in a
  Rainbow Storm, "🌙 FUSE NOW" over your machine at night.
- [ ] **Surge chips + strike warning.** `/event PowerSurge`: a "⚡ ×1.25"
  chip over every running generator in every lab (from up to 80 studs);
  cash balls on the factory lines run faster and look brighter. 3 s before
  each bolt a cyan ring under the target pedestal and a red "⚡ STRIKE IN
  3·2·1" over it, seen by everyone; then "CHARGED!" (cyan) or "MISSED"
  (muted) pops for 1.5 s. With two labs, one with 4 items and one with 1,
  both get struck about as often.
- [ ] **BIG + street coins and the tally.** `/event GoldenRain`: about 1 in
  8 lab coins is double size; it pays 20 s of income with a big gold "BIG
  +$X". Every 15 s a coin lands on the street (off the belts, never in a
  plot, at most 8); either player can grab it and it pays the grabber 6 s
  of their own income. The chip shows "💰 +$X this rain" and the end toast
  "… is over · you earned +$X".
- [ ] **Meteor warnings.** `/event MeteorShower`: a red "☄ INCOMING" ring
  and pill where each meteor lands, ~2 s before it hits; craters show
  "Hold E · free item".
- [ ] **Cleanup after `/event off` (every event).** Start each event, let it
  make things (coins, chips, rings, craters, the moon), then `/event off`:
  Workspace.EventObjects.<Id> is empty on the server (Explorer, Server view)
  and on the client (Client view); no coin, crater, prompt, ring, chip or
  pill is left in the world, and no pedestal keeps LightningTarget.
- [ ] **Event mutation reveal.** `/eventmut void`, `/eventmut charged`,
  `/eventmut celestial`: each opens the reveal card: mutation-colour
  background, "EVENT-ONLY MUTATION", "VOID!" (CHARGED! / CELESTIAL!), the
  orb in its shell, the item, "VOID ×8 income", the how-you-got-it box
  (Void: "1 in 20 fusions"), "Index +1 · Void 1 / 17" the first time
  (no "+1" for a repeat), a shake, DISPLAY / OK. Everyone sees the SERVER ·
  EVENT MUTATION banner ("… got a VOID … under the Void Moon!", "…got
  CHARGED by lightning!", "…found a CELESTIAL … in a meteor!"). A meteor
  core that rolls Celestial and a Void Moon Void fusion use the same card.
- [ ] **Index how-to-get.** (Polish 7: the headings are no longer tap
  targets; the info strip replaced the boxes, see §18.) Tap any Void orb:
  the strip reads "<Item> · Void ×8" in purple, "Only from fusing during a
  Void Moon (1 in 20 fusions). …". Golden / Diamond / Rainbow mention
  Rainbow Storm ×5 and Golden Rain ×3; Charged lightning; Celestial "15%".
- [ ] **Odds board.** At desktop distance from the machine the board reads
  as a table: "FUSE → TIER UP", "more orbs = better odds", ORBS IN 2–6,
  one row per recipe with an orb dot, every % in its own cell, 100% cells
  teal, the footer. No mutation line. At Rebirth 0 the Mythic → Secret row
  reads R1 in every cell; after `/rebirths 1` the numbers show. On a phone
  (Device emulator) the cells are still legible from the walkway. The Fuse
  panel's chips are one two-line chip per count with a gap; the count in
  the chamber is highlighted.
- [ ] **Sounds.** No bell loops near Mythic / Secret pedestals any more. Put
  a nonsense id (`rbxassetid://1`) in one SoundConfig slot: the output
  shows one "SoundKit: <slot> failed to load …" warning at start and that
  sound is simply silent afterwards; empty slots (Thunder, CoinPickup, …)
  play nothing with no errors.

## 18. Polish 7 (Index book, MAX upgrades, smaller HUD)

The HUD cases (LOCK chip fits its text, no steal chip, no event pop-up,
the chip's ⓘ and first-time pulse, the card closing) live in §16 / §17b.

- [ ] **Index orbs.** Open INDEX on a fresh save, `/give` a few items with
  `[mutation]`. Found cells are the real orb in that variant: Normal the
  tier orb, Golden gold, Charged cyan with a glow, Diamond pale with a
  faceted sweep, Void deep purple, Rainbow hue-cycling, Celestial
  white-blue with a soft glow. Missing cells are dark dashed circles with a
  muted "?". No check marks or clocks anywhere.
- [ ] **Event icons.** The CHARGED / VOID / CELESTIAL headings carry ⚡ 🌙 ☄
  and their missing cells show the same icon instead of "?". Tapping a
  heading does nothing.
- [ ] **Tabs.** Every tab shows its tier name in the tier colour, "x / N"
  and a thin bar; only the selected one shows "+5% at N".
- [ ] **Complete row.** `/give` one item in all 7 variants: its row card
  gets a gold stroke and a soft gold glow, the sub-line reads "★ COMPLETE
  7/7 · $X/s" in gold. The tab count and the header line go up.
- [ ] **Info strip.** Tap a found Golden orb: the strip reads "<Item> ·
  Golden ×2", the how-to-get line and "✦ found". Tap a missing one: "not
  found yet". Tap a Normal orb: "Any pull, or a fusion without a mutation."
- [ ] **Phone scroll.** Device emulator (iPhone 14 landscape): the rows
  scroll, orbs are ~40 px, every orb is still easy to tap (the cell is the
  target), the info strip stays visible at the bottom.
- [ ] **MAX ×N exact.** `/cash 5000000`, open UPGRADES. Note a row's "MAX ×N
  / $X" and your cash. Press it: the generator goes up exactly N levels,
  cash drops by exactly $X, one toast "+N levels · <Generator> LV L" and
  one bump on that generator.
- [ ] **MAX ALL.** "⚡ MAX ALL · $X / +N levels" under the list: press it.
  Exactly N levels across the generators, $X spent, toast "+N levels
  across K generators", one bump per generator that changed. A generator
  that unlocks during the run gets levels too.
- [ ] **need $X.** With too little cash for even one level, the row's button
  is muted "MAX / need $X" (X = that generator's next price) and MAX ALL
  reads "need $X" (the cheapest next level). Pressing either toasts "Need
  $X" and buys nothing. A maxed generator shows MAXED and no MAX button.
- [ ] **MAX while carrying.** Steal an item (two players, Rebirth 1) and
  press MAX / MAX ALL while carrying (or fire
  `RequestUpgradeMax:FireServer({ All = true })` from the command bar):
  "Get home with that item first!", no level, no cash spent.
- [ ] **Refresh rate.** With UPGRADES open and income ticking, the MAX labels
  follow your cash (N and $X grow) without flicker.

## 19. Polish 8 (reveal settings, fuse chips, mixed mutations)

- [ ] **Defaults.** Fresh save, open ⚙ (right end of the bottom bar, after
  INDEX): Common Diamond+, Rare Diamond+, Epic / Legendary / Mythic Always
  (today's big-card rule), plus the locked Secret row "🔒 Always shows. So
  do ⚡ Charged, 🌙 Void and ☄ Celestial."
- [ ] **Every option, pull.** For Rare, try each segment and pull until a
  Rare lands (`/give` doesn't pull): Never → a small line; Golden+ → the big
  card only for Golden or better; Diamond+ / Rainbow+ likewise; Always →
  every Rare gets the big card. The choice sticks across a rejoin in a
  live test place (Studio profiles never save).
- [ ] **Every option, fusion.** Set Epic to Never and fuse Rares → Epic:
  no big card and **no small line**, only the top banner "FUSION SUCCESS!
  → EPIC …" (a Golden result adds "· GOLDEN kept / rolled!"; a long line
  shrinks to fit instead of cutting off). Set Always: the big card and no
  banner. A second player sees only the server-wide banner, for
  Legendary+ / Rainbow results.
  Pull ×10 with Epic Never: the grid shows, no BEST OF 10 card, a small
  line for the best. Fail cards and the Fuse All summary are unchanged.
- [ ] **Always shown.** Set every tier to Never: a Secret (`/give` won't
  pull; use the gacha with luck or fuse Mythics) and `/eventmut void` /
  `charged` / `celestial` still get their cards.
- [ ] **Skipped line.** Pull several Commons fast: each pops "◉ + Plasma
  Orb  COMMON  +$X/s" above the bottom bar for 2.5 s; at most 3 stack,
  older ones dimmer; a Golden one names it in gold. RevealMinor plays.
- [ ] **Fuse chips at phone size.** Device emulator (iPhone SE landscape):
  the five chips stay in one row, equal widths, "100%" (e.g. Common ×6)
  fully visible, the current count highlighted, purple during a Void Moon.
- [ ] **Mixed warning.** `/give <rare item id> golden` ×4 plus one plain
  Rare; put all five in: a red box "⚠ 1 plain orb mixed in: the Epic comes
  out plain, not Golden. Use only Golden orbs to keep Golden." and a red
  ring on the plain orb. FUSE until a success: the Epic is plain (unless
  it rolled one: the card then says "GOLDEN rolled!").
- [ ] **Keeps GOLDEN.** Five Golden Rares: "✨ Keeps GOLDEN ×2, might roll
  better" in gold, no red rings. A success: the card shows the GOLDEN ×2
  pill and "GOLDEN kept".
- [ ] **AUTO-FILL keeps the mutation.** Put one Golden Rare in, AUTO-FILL:
  only Golden Rares are added. Empty chamber + AUTO-FILL: plain Rares only.
- [ ] **Fail card.** A failed fusion with a Golden in: "Kept your Golden
  Rare (Golden …), lost N".

## 20. Sounds (every slot filled, volume, play cap)

- [ ] **Preload.** Play in Studio and check the Output: no "SoundKit: <slot>
  failed to load …" warning. Any that appears names a slot to re-pick.
- [ ] **Every slot audible once.** Each should be clearly different:
  - EventStart: `/event GoldenRain` (once, as the banner shows).
  - EventEnd: `/event off`.
  - CoinPickup / BigCoin: grab Golden Rain coins.
  - Thunder: `/event PowerSurge`, wait for a strike; it's louder near the
    target and fades by ~150 studs.
  - MeteorImpact: `/event MeteorShower`; it plays at the crater and fades
    with distance.
  - EventReveal: `/eventmut void`.
  - Grab / Alarm: a two-player heist (thief / victim; the alarm is three
    quick high blips).
  - RevealMajor / RevealMinor: fuse to Epic / to Rare.
  - Toast: any top banner.
  - Station: buy on the Multiplier Pad or the Gacha Pad.
- [ ] **Volume slider.** ⚙ → Sound effects: it starts at 80%. Drag it to
  20%: the number follows the knob and a click plays at the new level on
  release; every sound above, and the other player's Station purchases near
  you, are quieter. 0% is silent. The value survives a rejoin in a live
  test place (Studio profiles never save).
- [ ] **Mute.** Tap 🔊: it turns red 🔇, the slider greys, and nothing plays,
  including server sounds (Station). Tap again: sound returns at the slider
  level.
- [ ] **No stacking on a coin streak.** `/event GoldenRain` and run through a
  line of coins fast (or Pull ×10 for RevealMinor): at most 6 of one sound
  overlap, and the coin pitch varies slightly from coin to coin.

## 21. Monetization (shop, passes, boosts, offers, real sales)

All ShopConfig ids are 0 until Harris pastes them, so in Studio every item
shows a "TEST" price and tapping it (or `/shop grant <key>`) runs the real
grant path for free. Live-game checks need real ids (docs/SHOP_SETUP.md).

- [ ] **Every product through `/shop grant`.** For each key, `/shop grant
  <key>` shows the THANK YOU card (gold sunburst, RevealMajor, "(Studio test
  grant)") with the right lines, and:
  - DoubleCash: the HUD income doubles; tap the multiplier pill: "Passes
    ×2".
  - VIP: income ×1.25 more; a gold 👑 VIP tag over your head; `[VIP]` in
    gold before your chat messages; gold sign border and wall trims.
  - ExtraPedestals: spots 5–6 turn solid, their lock label becomes EMPTY,
    you can display there and income counts them.
  - AutoFuse: the Fuse panel shows "🔁 Auto-Fuse"; switch it on, pull:
    ~1.5 s later a Fuse All summary appears by itself (mutated items never
    touched).
  - LabStyle: wall and sign strips turn Neon Pink; your cash balls are
    pink. Nothing else changes.
  - Lucky / LuckPotion: see "odds" below. QuickBoost / Boost: "⚡ 2× ·
    15:00 / 1:00:00" pill by the SHOP button, income ×2; a second grant
    adds time (cap 3 h).
  - PocketCash / CashCrate / CashVault: cash goes up by the amount the
    tile showed (20 min / 2 h / 8 h of base income, floors $5k / $50k /
    $250k).
  - Overclock: see below. SafeFusion1 / 5: "OWNED 1 / 6" on the tiles.
  - StarterPack: Neon Pink + a 1 h boost + Pocket Cash; it disappears from
    the shop afterwards. OfflineDouble: `/offline 120`, then COLLECT ×2 on
    the welcome-back card pays twice the amount.
- [ ] **Restricted player.** In `MonetizationService`, temporarily force
  `restricted = true` (or play from a region where paid random items are
  restricted): the shop shows only 2× Cash, VIP, +2 Pedestals, Auto-Fuse
  and Neon Pink Lab; no cash, boost, luck, Safe Fusion, Starter Pack or
  COLLECT ×2; `/shop grant boost` still works in Studio (test only), but
  `RequestShopPurchase { Key = "Boost" }` from the command bar is refused
  ("not available for your account"). Gacha and fusion work as before.
- [ ] **Odds with the Luck Potion.** Note the Gacha Pad's Legendary / Mythic
  % and the mutation line. `/shop grant luckpotion`: the pad's numbers rise
  at once (×2 luck); when the 15 min run out (or `/shop grant` Lucky for
  ×1.5 permanently) they update again. The Fusion Machine's success
  board doesn't change (luck never touches fusion success).
- [ ] **Contextual offer timing.** On a profile in its 2nd+ session (a live
  test place; Studio profiles are always session 1, so in Studio wait 10
  min first):
  - Tap an upgrade you can't afford: one side card bottom-right ("You
    tapped: Core Engine LV 7 · $8.2M", "Need $3.4M more?", the smallest
    covering pack with its amount, Not now, the price, "or wait ~N min").
  - Tap again at once: no card (5 min cooldown); toasts still show.
  - Within the first 10 min of a first session: never.
  - Fail a fusion (or get robbed, or get caught stealing), then tap
    something unaffordable within 60 s: no card. After 60 s (and the
    cooldown): it may show.
  - With the welcome-back card, a result card or the shop open: no card.
  - A gap no pack covers: it offers the Boost instead.
- [ ] **Starter Pack in session 2 only.** Session 1: never offered by a
  card. Session 2: 3 min after joining a "Welcome back! 🎁 Starter Pack"
  side card, once; dismiss it and it doesn't come back (it stays in the
  shop's featured banner until bought). Session 3: no card.
- [ ] **A sale only inside its window.** No Admin Abuse: no SALE tag, no
  BoostSale tile, the featured banner isn't a sale. Admin panel → start an
  event (or schedule Admin Abuse to now): the red SALE tag appears on the
  SHOP button; the banner shows "normally <Boost price> · today <sale
  price> (−N%)" (live prices) and "Ends when Admin Abuse ends · m:ss"
  counting the real time. End the event: everything sale-related goes, and
  `RequestShopPurchase { Key = "BoostSale" }` is refused ("That sale just
  ended").
- [ ] **Pedestals 5–6 locked / unlocked.** Without the pass: two dim plinths
  behind the front row, owner-only "🔒 +2 PEDESTALS"; their prompt reads
  "Unlock" and asks for the pass (Studio: a test grant). Another player
  sees no prompt. DISPLAY IT never targets them. After the grant they work
  like the others.
- [ ] **Safe Fusion returns the orbs.** `/shop grant safefusion5`. In the
  Fuse panel arm "🛡 Safe Fusion (5)" (it reads ON) and fuse a low-chance
  set until one fails: the fail card says "🛡 Safe Fusion · every orb came
  back", the inventory still has every input, tokens 4, and the toggle is
  OFF again. A success also spends the token. The fail card never offers
  Safe Fusion; AGAIN fuses without it.
- [ ] **Overclock for the whole server.** Two players: one runs `/shop grant
  overclock`. Both see the "SERVER · OVERCLOCK" banner "⚡ <name>
  overclocked the server! ×2 income for everyone", both HUD incomes double,
  both show "⚡ SERVER 2× · 15:00"; another grant extends it (cap 60 min);
  it ends for everyone together, and a rejoin after it ended shows none.
- [ ] **Phone layout.** Device emulator (iPhone 14 landscape): the SHOP
  button sits beside the cash card with the LOCK chip under it (top-left
  170 × 60 still clear); the shop fills the screen and scrolls; tiles are 2
  per row; every button is easy to tap; the side cards don't cover the
  bottom buttons.


## 22. Save safety (ProfileStore, Launch 1)

Saves now go through ProfileStore (`Packages/ProfileStore.lua`) in the store
`FT_Live_1`, with a session lock: one server holds a profile at a time.
Plain Studio Play uses the mock store (a blank profile every Play, never
saved). To test persistence in Studio, set the attribute
**`FT_StudioSaves = true`** on ServerScriptService (edit mode) and turn on
Game Settings → Security → **Enable Studio Access to API Services**: saves
then go to the separate store `FT_StudioTest_1`, never the live one.
Two Studio test servers can't share a profile, so the lock is tested in a
published place.

- [ ] **Blank Studio profile.** No attribute: Play, earn cash, Stop, Play:
  a fresh save every time, no errors in Output.
- [ ] **Data version.** With `FT_StudioSaves`, Play once, then in the
  command bar (server) read the profile: `Version = 1`; every template
  field is present (Reconcile fills fields added later).
- [ ] **A grant survives an instant leave.** With `FT_StudioSaves`: Play,
  `/shop grant boost` (or `safefusion5`), then Stop straight away (within a
  second). Play again: the boost / tokens are still there.
- [ ] **A steal survives a shutdown.** Published place, 2 players at
  Rebirth 1+. A steals from B and delivers. Straight away shut the server
  down (Creator Dashboard → Shut down all servers, or the place's Server
  menu). Rejoin both: the item is in A's inventory and gone from B's (never
  in both, never in neither). Repeat, shutting down DURING the carry: the
  item is back on B's pedestal and A has nothing.
- [ ] **The session lock (2 servers).** Published place with Max Players
  low enough that a second server starts (or a private server + a public
  one). Join server 1, pull a few items, note your cash. Without leaving,
  join the same place's server 2 from a second device/session on the same
  account (or teleport there). Server 2 waits for the lock (up to
  ProfileStore's steal timeout, ~40 s if server 1 doesn't let go) and then
  loads the SAME items and cash; server 1 kicks you with "Your save was
  opened in another server, please rejoin". Anything done in server 1
  after the kick never shows up in a later join.
- [ ] **Quick server hop.** Leave server 1 and join server 2 at once:
  server 2 loads the data you left with (it waits for server 1's final
  save instead of loading stale data).
- [ ] **Failed load.** In a live game, a DataStore outage kicks the player
  with the "couldn't load your save" message; the save is never
  overwritten.
- [ ] **Receipts.** Live purchase of a cash pack: granted once; Developer
  Console shows no repeat grant on rejoin. A purchase while the profile is
  not active (the brief window while server 2 waits for the lock) is
  granted only after the profile loads (Roblox retries the receipt).
