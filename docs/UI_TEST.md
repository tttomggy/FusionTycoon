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
  <key>` shows the purchase celebration (see §33; "(Studio test
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

## 23. Daily rewards (DailyConfig)

- [ ] **First join.** Fresh Studio profile: about 2 s after the first sync
  the DAILY REWARD card opens (never over the welcome-back card: run
  `/offline 60`, rejoin, and the daily card waits until COLLECT closes it).
  7 tiles: Day 1 gold, glowing, "TODAY"; Day 7 purple; the rest dark.
  "🔥 1-day streak" pill, "1 free skip" chip, "Day 1 · 10 min of income
  +$X", the green "CLAIM DAY 1" button and the footer (skip rule + "Day 7:
  Epic 70% · Legendary 25% · Mythic 5%").
- [ ] **Claim.** CLAIM: Day 1's tile pops a green ✓ and dims, the line turns
  green ("💰 +$2.5K"), cash goes up, the button reads NICE. A second
  `ClaimDaily` (e.g. a fast double tap) is refused: "Already claimed
  today". Rejoin: no card.
- [ ] **Every day's reward.** `/daily day <n>` (the card reopens) then
  CLAIM for each n:
  1: cash · 2: "⚡ ×2 income · 15 min banked" and the HUD boost chip ·
  3: the card closes and the "🎁 DAY 3 · FREE PULLS" pull card shows 3
  pulls (pad price unchanged; on a fresh profile the "Pull from the Gacha
  Pad" goal completes and Output prints `funnel 4 FirstPull`) · 4: "🍀 ×2 luck", the pad odds rise ·
  5: Safe Fusion tokens +1 in the Fuse panel · 6: ×2 income 60 min ·
  7: the "🎁 DAY 7 REWARD" reveal of an Epic / Legendary / Mythic item
  (can be mutated), RevealMajor.
- [ ] **Skip rule.** Claim, then `/daily miss 1`: the card reopens with
  "You missed a day: your free skip kept the streak going!", the next day
  in the cycle, the streak +1, and after CLAIM the chip reads "0 free
  skips". `/daily miss 1` again (no skip left): Day 1, "Your streak
  ended…", streak 1, the skip back. `/daily miss 3` with a skip: Day 1
  too (more than one missed day). After Day 7 the next claim is Day 1 and
  the streak keeps counting (8, 9, …).
- [ ] **Restricted accounts** (PolicyService paid random items restricted;
  in Studio force `Restricted`): the card and every reward still work.
- [ ] **Phone.** Device emulator: the card fits at 92% width, the 7 tiles
  stay in one row, CLAIM ≥ 44 px.

## 24. Playtime gifts (GiftConfig)

- [ ] **HUD.** A pink "🎁 GIFTS" button sits right of SHOP. On a fresh
  profile a small "next in 4:59" pill sits beside it and counts down.
  At 5:00 the pill goes, a green "1" badge appears and the button bounces.
- [ ] **Panel.** GIFTS opens the panel: the daily strip on top ("📅 Daily
  reward ready · Day N" + OPEN, which closes this and opens the daily
  card; once claimed "next in 7:12:03" to 00:00 UTC), "Played today:
  5:02", six boxes: ready = green with a pulsing glow and "OPEN!",
  locked = "10 min" etc. with a thin progress bar, claimed = dim with ✓.
  Footer: "Rare 60% · Epic 35% · Legendary 5%".
- [ ] **Every gift.** `/gifts time 60` (all six ready, badge 6). Open each:
  5 min: the box shows "💰 +$X" for a moment then ✓; 10 min: the panel
  closes and the "🎁 GIFT · FREE PULL" card shows one pull; 15 min: ×2
  income 10 min (HUD boost pill); 25 min: cash; 40 min: ×2 luck 10 min;
  60 min: the "🎁 PLAYTIME GIFT" item reveal (Rare / Epic / Legendary).
  The badge counts down and the bounce stops at 0; with all six open the
  next pill stays hidden.
- [ ] **Server checks.** `/gifts time 7`: only the first gift is ready; a
  forged `ClaimGift { Index = 3 }` (command bar) is refused "Not open
  yet"; a second claim of gift 1 is refused "Already opened".
- [ ] **Sums across sessions.** With `FT_StudioSaves`: play 6 min, leave,
  rejoin: "Played today" carries on from ~6:00 and gift 1 is still ready
  (or still claimed). `/gifts reset` locks them all again.
- [ ] **Phone.** Device emulator: SHOP and GIFTS fit beside the cash card
  without covering the top-centre event chip; the panel's boxes stay 3 per
  row and each is easy to tap.

## 25. Street leaderboards

- [ ] **Placement.** Play in Studio and walk to each end of the street:
  at the west end the 💰 BEST INCOME /s board stands left of the LAB
  WEATHER Event Board and 🏆 MOST REBIRTHS right of it; at the east end
  📖 INDEX FOUND stands on the Event Board's -z side. Each faces down the
  street, on two posts with a gold strip on top; none touches a belt, a
  gate, a plot wall or an Event Board, and each is readable from the
  middle of the street.
- [ ] **Studio fake rows.** Every board shows ten rows "TestPlayer1…10":
  #1 gold, #2 silver, #3 bronze tints, the rest dark; a blank round
  headshot well, the name, and the value (income "$1T/s"…, rebirths,
  "112 / 119"…). No DataStore warnings in Output.
- [ ] **Live (published place).** Play a few minutes with 2 accounts,
  wait ≥ 2 min: both appear on the boards with their headshot and display
  name; BEST INCOME is your highest base income (a running Boost doesn't
  raise it). Rebirth, wait ≤ 2 min more: MOST REBIRTHS updates. Leave and
  rejoin a fresh server: your rows are still there. Shut a server down:
  the last values written on close show in the next server.

## 26. Analytics (AnalyticsKit, Studio prints)

In Studio nothing is sent: every call prints `[Analytics] …` in Output.

- [ ] **Funnel, in order, once each.** Fresh profile: `funnel 1 Join`;
  step on CLAIM: `funnel 2 ClaimLab`; buy an upgrade: `funnel 3
  FirstUpgrade`; pull: `funnel 4 FirstPull`; display an item: `funnel 5
  FirstDisplay`; fuse: `funnel 6 FirstFuse`; Multiplier Pad: `funnel 7
  FirstMultiplier`; `/event goldenrain`: `funnel 8 FirstEvent`;
  `/rebirthready` + rebirth: `funnel 9 FirstRebirth`; deliver a steal:
  `funnel 10 FirstSteal`. Doing any of them again prints no funnel line
  (with `FT_StudioSaves`, not even after a rejoin).
- [ ] **Economy.** Sinks print on an upgrade (`Upgrade`), a MAX
  (`UpgradeMax`, ONE line for all levels), a pull / ×10 (`Pull` /
  `Pull10`), the pad (`MultiplierPad`) and a rebirth (`Rebirth`, the cash
  held). Sources: `PassiveIncome` once a minute (and on leave), Golden
  Rain coins (`Coin` / `BigCoin`), a cash pack (`/shop grant pocketcash`:
  IAP `PocketCash`), the daily / gift cash days (TimedReward `Daily` /
  `Gift`).
- [ ] **Custom events.** Open the shop: `ShopOpened`; a contextual offer
  (tap an upgrade you can't afford, after the quiet period): `OfferShown
  [PocketCash]`, then `OfferAccepted` or `OfferDismissed`; the same for
  the Starter Pack card; any grant: `Purchase [Key]`; daily claim:
  `DailyClaimed = 3`; gift: `GiftClaimed = 2`; a grab:
  `StealStarted [Epic]`, then `StealDelivered` or (owner tags) `StealSaved`.

## 27. Launch 1 playtest fixes

- [ ] **Reward items reveal (bug 1).** `/daily day 7` and CLAIM: the daily
  card shows the reveal line, closes itself, and THEN the item reveals
  through the normal pull path: the big card ("🎁 DAY 7 REWARD", the item's
  tier and mutation) when your ⚙ reveal rule shows that tier/mutation,
  else the small skipped line above the bottom bar. Set the Epic rule to
  "Always" to see the big card every time. Same for the 60-min gift
  (`/gifts time 60`, open the last box: the panel closes, then "🎁
  PLAYTIME GIFT"), and for free pulls (Day 3, the 10-min gift).
- [ ] **GIFTS button stays (bug 2).** `/gifts time 15`: SHOP and GIFTS both
  stay visible; GIFTS bounces with a green "3" badge and the "next in"
  pill hides. Open all three: the bounce stops, the badge hides, the
  "next in 9:59" pill comes back. No sale live: SHOP stays visible with no
  SALE tag (a solid-colour pill's `.Parent` used to be hidden, which was
  the whole row / the SHOP button).
- [ ] **Goal markers stay in your lab (bug 3).** Fresh profile, claim:
  the "UPGRADE YOUR BASIC GENERATOR" marker sits right over your own Basic
  Generator (distance a few studs from the generator, not ~54), and its
  floor ring is round the generator. Walk far down the street and come
  back (parts stream out and in): the marker re-settles on the generator.
  Step through the goals (`/cash`, pulls, …): every marker (Gacha Pad,
  first empty pedestal, Fusion Machine, Multiplier Pad, Portal, LOCK
  console) is inside your walls; never over the street, a leaderboard, an
  event object or another lab. Only "Steal an item from another lab"
  points at an enemy pedestal. Output shows no "outside your plot" warning
  (it names the offending instance if one ever appears).
- [ ] **Daily claimed tiles (bug 4).** `/daily day 5`: Days 1–4 are dimmed
  to half with their DAY / icon / label still readable, and each has a
  small green round ✓ badge in its top-right corner (no big ✓ over the
  text). CLAIM: Day 5 pops and gets the same badge.
- [ ] **Phone HUD at 844 × 390 (bug 5).** Device emulator, custom 844 ×
  390 landscape (0.8 UI scale → a 1055 × 487.5 canvas). Force an event you
  haven't tapped (`/tips reset`, `/event powersurge`) so the top chip
  pulses, and `/gifts time 15` so GIFTS bounces with its badge. Check:
  the GIFTS badge and the SHOP SALE tag stay below the chip's glow (the
  SHOP / GIFTS row now starts 8 px lower than the cash card, at y 84
  logical); the SALE tag no longer touches the bouncing GIFTS (row gap
  8 → 14); the NEXT GOAL tracker sits under the cash card (y 184, it used
  to cover the card's bottom 22 px); the LOCK row stays under SHOP; the
  effect pills end well short of the right edge; the top-left Roblox bar
  area stays clear. Computed: no overlaps among top bar, event chip (with
  pulse + glow), cash card, goal tracker, SHOP, SALE, GIFTS (bounce),
  badge, next pill, effect pills, LOCK row.
- [ ] **Pills always own their fill (SHOP / GIFTS root cause).** Every
  `UIKit.Pill` is now a fill Frame with the label inside, colour or
  gradient alike. Desktop and phone (844 × 390), no sale running: the
  SHOP button shows, with no SALE tag. `/gifts time 15`: SHOP and GIFTS
  both stay, GIFTS bounces with its badge, the "next in" pill hides and
  comes back once all ready gifts are open. Also check every plain-colour
  pill still looks the same: the HUD multiplier pill (tap it: the income
  breakdown opens, the tap area is the pill's own ≥ 44 px), Upgrades
  panel LV pills (hidden on locked generators), the Inventory filter chips
  (tap each), mutation pills on result cards / inventory cards / the
  event info card (in their list order), "OWNED 3" on Safe Fusion tiles,
  the daily card's skip chip, and the HOW TO HEIST scene labels (they
  follow the 3D scene and hide when off-screen).

## 28. Bug Hunt 1

- [ ] **/selftest.** Plain Studio Play, no event running (`/event off`):
  `/selftest`. Output: "[SelfTest] running for … (store: Mock)", every
  line PASS, "done: N passed, 0 failed". The panels flash open and shut at
  desktop then phone scale while it runs (~30 s). With `FT_StudioSaves`
  it says "store: StudioTest"; it never runs against the live store.
- [ ] **Live shop with no ids.** Published place with every ShopConfig id
  still 0: no SHOP button (GIFTS sits where it was); the locked pedestal
  spots read "Locked · +2 Pedestals · coming soon" and only toast. Studio
  still shows SHOP with TEST tiles.
- [ ] **Leaderboard Cash column.** The player list shows Cash as "$1.2M"
  (text). `/cash 1e20`: still shows ("$100Qi"), income keeps ticking, no
  error in Output.
- [ ] **NumberFormat.** `/cash 1e40`: the HUD reads "$1.00e40", nothing
  breaks.
- [ ] **Gifts panel fits.** Desktop and phone: both box rows are fully
  visible or scroll into view; the footer sits under the boxes, never over
  them.
- [ ] **Event card on a phone.** 844 × 390, `/eventmut void`: the whole
  event card (title to OK) is on screen, scaled down.
- [ ] **Offline with passes.** Own 2× Cash (`/shop grant doublecash` in a
  FT_StudioSaves session), leave, `/offline 60` on rejoin: the payout
  counts the 2× pass.
- [ ] **Spam.** Hold the Upgrades panel's upgrade button / mash a pedestal
  prompt: it works at human speed; a script firing 50 / s gets "Slow down
  a little" and nothing else happens.

## 29. Reset and respawn

Reset your character (Esc → Reset) in the middle of each of these, and check
nothing sticks or breaks afterwards:

- [ ] **Each panel / card open** (Upgrades, Shop, Gifts, Daily, Index,
  Settings, Fuse, Rebirth, HOW TO HEIST, a pull / fusion / event result
  card): it stays usable or closes cleanly; reopening works; HUD intact.
- [ ] **During a pull and a fusion:** the result card still shows; the item
  is in the inventory once.
- [ ] **During a heist, as the thief:** the carry ends (death = it goes
  back), the orb leaves your head, walk speed is normal after respawn.
- [ ] **During a heist, as the owner:** after respawning you still run at
  the chase speed (18) until the carry ends, then normal.
- [ ] **During each event** (`/event <id>`): coins / craters / strikes
  keep working; the goal / event arrow points from your new character;
  pedestal and station prompts still work.
- [ ] **After respawn:** goal arrow distance counts from the new character;
  the GIFTS bounce / next pill and SHOP are unchanged.

## 30. Contrast rule (white on gold) and the selected state

Look at every gold, yellow or orange surface on desktop AND at phone scale.
The text on each one must be **white with the ink stroke**, never dark
brown and never gold-on-gold.

- [ ] **HUD:** 🛒 SHOP button; the orange rebirth pill; the gold Overclock
  pill (`/shop grant overclock`); the event chip during Golden Rain and
  Meteor Shower (`/event GoldenRain`, `/event MeteorShower`).
- [ ] **World:** the goal marker ("CLAIM YOUR BASE" on a new lab, then the
  next goals); the Gacha Pad price pill; the Collector "+$X/s" pill; the
  Multiplier Pad's gold price pill; the REBIRTH portal pill; the 👑 VIP head
  tag (`/shop grant vip`); the meteor crater "Hold E · free item" chip; both
  Event Boards during a Golden Rain / Meteor Shower row.
- [ ] **Cards:** Daily card TODAY tile (DAY N, the reward line, "TODAY"),
  the orange streak pill; Gifts panel OPEN; every Gold / Orange button
  (Upgrades MAX ALL, rebirth buttons, result-card AWESOME / NICE, the THANK
  YOU card); the heist banners (GET HOME!, YOU GRABBED …); the Overclock
  server banner caption ("SERVER · OVERCLOCK" in white).
- [ ] **Shop:** BEST VALUE and SAVE N% tags, the featured banner caption,
  title and detail.
- [ ] **Selected = green, white text, everywhere:** shop chips, Index tier
  tabs (the tier name keeps its colour on the green pill), Settings
  5-segment rows, Fuse count chip (the chamber's count) and Fuse tier tabs,
  the item picker's filter chips, the Upgrades "Generators" tab, the admin
  panel pickers. Unselected stay the muted panel colour.
- [ ] **Tap feedback:** tapping any of those bounces it (0.94 → 1) and plays
  the Toast sound.
- [ ] **Chat overlap (desktop, chat window open):** open Daily, Shop, Index,
  Upgrades, Settings and a result card (`/offline 120`): every title sits
  BELOW the chat window, nothing under it. With the chat window off
  (TextChatService → ChatWindowConfiguration.Enabled = false) the cards sit
  just under the top bar. Phone (844×390) layouts are unchanged.

## 31. Shop 2 (one scrolling shop)

Studio: every id is 0, so every item shows with a "TEST" button; there are
no live prices, so no BEST VALUE tag (it needs live prices) and the
featured banner is the Starter Pack.

- [ ] **One page:** the header (title + ✕) and the chip bar stay put while
  the page scrolls. Sections in order: ⭐ Featured, 🎟 Passes, ⚡ Boosts,
  💰 Cash, 🍀 Luck, 🛡 Safe Fusion, then the footer line. Each has a big
  header row (icon, title, coloured divider).
- [ ] **Every chip jumps to its section** with a smooth scroll (never
  filters); the section's header lands at the top of the page (the last
  sections stop at the end of the page).
- [ ] **The active chip follows the scroll:** drag / wheel through the page;
  the chip of the section on screen turns green, the last one at the very
  bottom.
- [ ] **Every buy button opens the right prompt** (in Studio: TEST → the
  purchase celebration for that exact item). Tapping a tile outside its button
  does nothing.
- [ ] **Owned passes sort last:** `/shop grant doublecash`, `/shop grant
  vip`: both move to the end of Passes with a grey "OWNED ✓" button.
- [ ] **Cash amounts match `/cash`:** note "+$X" on Pocket Cash, `/shop
  grant pocketcash`: cash rises by exactly that. Change income (upgrade):
  the tile updates within 2 s.
- [ ] **Boost banks:** Quick Boost reads "+15 min · you have 0:00"; grant a
  Boost: "you have 1:00:00" counting down; at 3 h "Bank full (3 h)".
  Overclock reads "server has …"; Luck Potion its own bank.
- [ ] **Sale:** start Admin Abuse (`/admin` → event): Boost is replaced by
  "Boost · SALE" with "normally ~~N~~ · today M (−X%)" (live prices only)
  and the featured banner shows the sale with its real end time; after the
  window the normal Boost is back.
- [ ] **Contextual offer:** tap an upgrade you can't afford (after the
  first-session quiet time): the side card has "See all in the shop ›",
  which opens the shop scrolled to Cash (or Boosts when it offered the
  Boost).
- [ ] **Hover / press:** hovering a tile grows it a little (1.03); pressing
  its button bounces it.
- [ ] **Icons:** with ids set, each tile shows the store page's icon (the
  one uploaded with the pass / product); without one, the emoji in a
  circle.
- [ ] **Restricted player** (force `restricted = true`): only Passes (2×
  Cash, VIP, +2 Pedestals, Auto-Fuse, Neon Pink) and its chip; no Boosts,
  Cash, Luck, Safe, Lucky or Starter Pack, and no empty headers.
- [ ] **Phone 844×390:** 2 tiles per row; the chip bar scrolls sideways
  and the active chip scrolls into view; every chip and button ≥ 44 px;
  the whole page is reachable down to the footer.
- [ ] **Narrow desktop window (< 600 px wide):** 2 tiles per row, 1 pass
  card per row, the featured banner stacks (icon, text, a full-width buy
  button).
- [ ] `/selftest`: PASS for ShopPanel at both scales.

## 32. Trailer (/trailer, admins only)

`/trailer` plays the ~30 s cinematic on YOUR client only (TrailerController).
Admins are `AdminConfig.AdminUserIds` plus the place owner. Record from a
built-up lab (generators running), with no event live (the HUD chip says
NEXT), so no live coins or craters wander into the shots.

- [ ] **Non-admin:** a non-admin's `/trailer` does nothing at all.
- [ ] **Full run:** black + "3 2 1", then night → pull → fuse → heist →
  void moon → hold, each joined by a quick fade through black. Every
  pedestal (all 6, the +2 spots solid) shows the lineup's glowing mutated
  orbs. The pull shows the real pad burst and the Rainbow Legendary card;
  the fuse shows the machine's real charge-up and reveal, a Secret and the
  "FUSION SUCCESS!" banner; the heist shows the hold ring, the carry orb,
  RUN!, CAUGHT! and the whip-pan; the void moon shows the purple moon,
  then the Void reveal with the event-mutation card; the hold is a still
  wide shot with the Secret on pedestal 1. No HUD, chat, player list,
  prompts or characters in any frame.
- [ ] **Twice in a row:** run it again straight after: identical.
- [ ] **One shot:** `/trailer heist` (and each of night, pull, fuse,
  voidmoon, hold) plays just that shot after the countdown.
- [ ] **Stop mid-shot:** press F8 (the chat bar is hidden during the run,
  so F8 is the in-trailer stop; `/trailer stop` works whenever chat is
  reachable): everything is back at once.
- [ ] **Reset mid-shot:** Esc → Reset during a shot: it stops cleanly.
- [ ] **2-player server:** the other player sees NOTHING change: no orbs,
  NPCs, cards, banners, sky or sounds; your character stays where it was;
  your pedestals still show your real items.
- [ ] **Everything restored afterwards:** HUD and every gui as before, the
  CoreGui (chat, player list, backpack), prompts work, the camera follows
  you again at the normal FOV, your character visible, the Lighting exactly
  as before (and a live event's sky comes back if one started meanwhile),
  your pedestals show your own items and labels, the machine core visible,
  nothing left in Workspace.TrailerLocal.

## 33. Shop 3 (placement, purchase celebration, real deals)

**Placement** (desktop 1920×1080 and 1366×768, the iPhone emulator; every
card: Shop, Gifts, Daily, Index, Upgrades, Settings, Fuse, Rebirth, How to
Heist, the result cards, the celebration):

- [ ] Each card's top sits just under the Roblox top bar (not at the
  bottom of the screen); its bottom stops above the HUD's bottom button
  row, never over it.
- [ ] Desktop with chat open: a card whose left edge would sit under the
  chat window slides right if there's room; otherwise it overlaps chat
  (collapse chat to read it). Never pushed down.
- [ ] Phone: every card's title row clears the ☰ / chat buttons (starts
  below 60 px). The SHOP / GIFTS / timed-pill row sits in the left column
  under the cash card, then LOCK, then the goal tracker; nothing overlaps
  at 844×390 (event chip, goal arrow, bottom row, REBIRTH!).
- [ ] With any card open on the phone, no HUD button draws on top of it.
- [ ] Fuse, Daily, Rebirth, How to Heist and the welcome-back card keep
  their layout and shrink as a whole on a phone.

**Chip jumps**

- [ ] Every chip puts its section's header right under the chip bar; the
  last sections stop at the end of the page. Same at phone scale.
- [ ] The contextual offer's "See all in the shop ›" lands on Cash /
  Boosts exactly.

**Purchase celebration** (`/shop grant <key>` for each):

- [ ] PocketCash / CashCrate / CashVault: "+$X" counts up, coins fly into
  the HUD cash counter, which holds, then ticks up and bounces; the amount
  matches the tile.
- [ ] QuickBoost / Boost / LuckPotion / Overclock: "+15 min" / "+1 h" flies
  into its HUD pill, which pops; with no boost running, the $/s line counts
  up green (not for Luck).
- [ ] DoubleCash / VIP: "✓ ACTIVE" stamp + shake; $/s counts up.
  ExtraPedestals: the two back plinths sparkle and turn solid. LabStyle:
  the lab sparkles pink. AutoFuse: the line points at the Fuse toggle.
- [ ] SafeFusion1 / SafeFusion5: shields drop into "🛡 Safe Fusion (N)".
- [ ] StarterPack and each deal: every content plays one after another.
- [ ] A tap after 0.6 s skips; AWESOME! (or a tap once done) closes; the
  shop is still open with the tile updated (OWNED ✓, banked time).
- [ ] Muted SFX: no sound. No second purchase prompt ever follows.

**Deals**

- [ ] The shop opens with 🔥 DEAL first: the parts' icons, the price line
  (Studio: TEST + "live prices appear once the product is set up") and
  "New deal in h:mm:ss" counting down; the 🔥 Deal chip is first.
- [ ] `/deal slot 6`, `/deal slot 12`, …: the deal changes each slot and
  never repeats back to back; the countdown jumps to match; `/deal slot 0`
  restores.
- [ ] HUD 🔥 badge under SHOP / GIFTS on its own line (phone too) with
  the saving and countdown; it pulses once on a new slot; tapping it opens
  the shop at the deal.
- [ ] `/deal pop`: the "New deal!" side card (icons, saving, Not now / See
  deal). See deal opens the shop at the deal; Not now hides it until the
  next slot. Not in a first session's first 10 min, not over another card,
  not within 60 s of a loss, not while carrying or being stolen from, and
  at most one shop pop-up per 5 min (shared with the contextual offer).
- [ ] Buying a deal outside its slot (command bar, an old key) is refused
  ("That deal just ended").
- [ ] Restricted player (`restricted = true`): no deal anywhere.
- [ ] Look: vivid section tiles (Passes blue, Boosts orange, Cash green,
  Luck teal, Safe indigo, Deal pink) with white text, big icons, hover
  1.04 + white glow, header shine; "NEW!" on the deals until 7 days after
  2026-10-05, nowhere else.
- [ ] `/selftest`: PASS for hud below modals, every chip at both scales,
  the deal schedule (repeatable, no repeats, client matches server) and
  each non-current deal refused.

## 34. Shop 3 fixes

**Phone deal badge (844 × 390 emulator)**

- [ ] The 🔥 DEAL badge sits in the left column on its own line under
  SHOP / GIFTS, never right of the "next in" pill or near the centre.
- [ ] "next in 4:22" and the timed pills ("⚡ 2× · 59:47", luck, SERVER)
  stack under the badge in the left column; the LOCK row and the goal
  tracker move down to make room and back up when a pill goes.
- [ ] Desktop unchanged: badge under SHOP / GIFTS, pills right of GIFTS.

**/deal pop**

- [ ] `/deal pop` shows the "New deal!" card at once, desktop and phone,
  in a first session's first minute, right after another offer, with a
  panel open, and after Not now in the same slot.
- [ ] Studio with no live prices: the card shows the contents, "Studio
  test…" and a "TEST" button; no saving.
- [ ] With the guards past (second session, 10 min in, no offer in the
  last 5 min) the card shows by itself once per slot.

**Once per deal (saved)**

- [ ] With `FT_StudioSaves`: see the card, leave, rejoin in the same slot:
  no card. `/deal slot 6` (next slot): it shows again.

**/selftest**

- [ ] PASS "hud left column (phone…)" and "deal real path".
- [ ] Three runs in a row with no "panel X: ±N instances" FAIL, one during
  a Golden Rain (`/event GoldenRain`) and one with a boost running
  (`/shop grant Boost`).

## 35. Cards centred (full screen)

- [ ] 1920×1080 full screen: SHOP opens in the middle, equal space above
  and below.
- [ ] Same for UPGRADES, ITEMS, INDEX, GIFTS, ⚙ Settings, the Daily card,
  Fuse, Rebirth (+ its confirm), How to Heist, the welcome-back card
  (`/offline 30`), a pull's big card, the EVENT-ONLY reveal (`/eventmut
  void`), a purchase celebration (`/shop grant PocketCash`) and the event
  info card (tap the event chip): centred between the top bar and the
  bottom buttons.
- [ ] 1366×768 window: the same; a card taller than the space starts just
  under the top bar and shrinks, never covering the bottom buttons.
- [ ] Phone (844×390 emulator): cards and the HUD's left column look as
  before (most cards fill the space and start under the top bar).
- [ ] Side cards (offer, Starter, New deal!) and the fail card stay at the
  bottom right / bottom.
- [ ] `/selftest`: every "cards centred" line PASSes (three viewports by
  the plan, plus each live card at this window's size), three runs in a
  row.
- [ ] `/trailer pull`: the Gacha Pad puller is the yellow / blue noob (not
  your avatar); no mouse cursor during the run, and it's back after.

## 36. Playtest 7 fixes

**Hovering things stay home (#1)**

- [ ] Join, then claim: the Gacha Pad capsule, Multiplier chevrons,
  generator cores and pedestal orbs float over their own stations; nothing
  hangs over the middle of the street.
- [ ] Rebirth; reset your character; walk far down the street and back
  (streaming); a second player joins and leaves; `/event GoldenRain`,
  `/event off`: still nothing in the street.
- [ ] `/selftest`: PASS "hovering things stay home" before and after the
  pedestal rebuild.

**How to Heist text (#2)**

- [ ] 1920×1080, 1366×768, 1280×720 and the phone emulator: every slide's
  title and line show in full (long lines shrink, never cut off); the
  number badge sits just left of the title.
- [ ] `/selftest`: every "text fits" line PASSes (any miss is listed by
  path).

**REBIRTH button (#3)**

- [ ] The bottom bar reads UPGRADES · ITEMS · INDEX · REBIRTH · ⚙; REBIRTH
  is purple with a fill and "$2.1M / $15M" that grows with your cash.
- [ ] `/rebirthready`: it glows and pulses; a tap opens the Rebirth panel
  (keep, income and luck, unlocks, REBIRTH). Without the cash: "Need $X
  more". The Portal still opens it.
- [ ] Phone: the bar fits, every button ≥ 44 px.

**Heist tuning (#4)**

- [ ] Steal, deliver, and steal again at once: no "Steal in 42s", no
  cooldown toast, no HEIST COMPLETE timer.
- [ ] Spam the steal remote from the command bar: dropped, no errors.
- [ ] Lose an item: your shield is 60 s; claim / LOCK shields are 60 s.

**LOCK for everyone (#5)**

- [ ] LOCK: the fence fades in tall and bright with a glowing top edge, a
  pink 🔒 pulses in the gate, and it blinks in the last 5 s.
- [ ] From the street, every lab's gate sign reads "🛡 LOCKED · 0:42" (pink),
  "🔓 OPEN" (red), "🔓 OPEN · can re-lock in 12s" or "🛡 PROTECTED"
  (Rebirth 0), visible from ~150 studs.
- [ ] An enemy pedestal in a locked lab reads "Locked · 0:42"; tapping it
  toasts.

**Auto-display (#6)**

- [ ] Pull: the item lands on a pedestal by itself; better items take
  spot 1 and push the rest along; 4 spots (6 with the pass).
- [ ] Fuse into a better item: it's on pedestal 1 as the result shows.
- [ ] No Display / Remove prompt on pedestals; the locked spots 5-6 still
  offer Unlock. Result cards show NICE! / OK only.
- [ ] ITEMS shows ON DISPLAY tags; displayed items can be fused.
- [ ] A thief carries one of yours: that pedestal stays BeingStolen; after
  the delivery it refills with your next best.
- [ ] `/selftest`: PASS both "auto-display" lines.

## 37. Tutorial

**New player, 1920×1080** (`/tutorial reset`, or a fresh Studio profile)

- [ ] Welcome card: icon, title, 2 short sentences, green OK; the game is
  dimmed behind it. Nothing else pops up (no shop / deal / Starter / Daily
  card, no tips) until the end.
- [ ] Claim: after OK a glowing path runs from your feet to your lab's
  claim pad (it follows you as you move), the arrow and the pulsing floor
  ring mark it; claiming completes it ("✓ Nice!" + sound, next card 0.6 s
  later).
- [ ] Upgrade: path to the Basic Generator, UPGRADES ringed; an upgrade
  from the world prompt OR the panel completes it.
- [ ] Pull: the pad reads "FREE · 2 left"; two pulls give two plain
  Commons, the pad price doesn't move; done after the second.
- [ ] Pedestals: path to pedestal 1 and the $/s line ringed while the card
  is up; OK completes it.
- [ ] Fuse: path to the machine; in the Fuse panel the ring walks
  AUTO-FILL → the odds chips → FUSE; the fusion succeeds (a Rare, big card,
  then it goes on display); the next card waits for the big card.
- [ ] Index: INDEX ringed; opening it completes the step.
- [ ] Multiplier: without the cash the card says "Come back when you have
  $X" and OK completes it; with the cash, buying level 1 does.
- [ ] Lab weather (event chip ringed) and Free gifts (GIFTS ringed): OK.
  No shop step, no shop mention anywhere.
- [ ] LOCK: path to the console; standing at it completes it; then the
  Stealing card. Rebirth: REBIRTH ringed; opening the panel completes it.
- [ ] You're ready: LET'S GO! ends it; held tips show now; the path now
  follows the current goal; 👣 on the goal card turns it off / on.

**Phone (iPhone emulator)**

- [ ] Cards fit above the bottom bar; coach rings wrap the phone buttons;
  the path is visible from the phone camera.

**Leave and rejoin**

- [ ] Leave mid-way (e.g. at Fuse) with `FT_StudioSaves`: rejoining shows
  the same step's card; steps already done (claimed, upgraded) are skipped.
- [ ] An old save with Rebirth 1+ (or > 20 pulls): no tutorial, one toast
  "New: replay the tutorial in ⚙ Settings".

**Replay and help**

- [ ] ⚙ Settings → ▶ REPLAY TUTORIAL: every step again as an OK-card, no
  free pulls.
- [ ] "?" in Fuse (6 cards: same tier, 2–6 orbs + odds, a fail keeps your
  best, mutations, Secret at Rebirth 1), Upgrades, Index and Rebirth;
  "How it works" (H) at the LOCK console and the Gacha Pad: ◀ ▶ and OK.
- [ ] `/selftest`: PASS "tutorial: every step completes in order", "no shop
  or deal pop-up while it runs", "a save left mid-way resumes at its step".

## 38. Combat

Studio: Test → 2 players. `/rebirths 3` on both (Laser and Freeze Ray need
Rebirth 2–3), `/weapons all` for the Slap Glove and Banana Peel.

- [ ] Rebirth 0: the weapon bar shows 🏏 🔫 🥶 greyed with R1 / R2 / R3; a
  tap says "Unlocks at Rebirth N". Nobody can hit you and you can't hit.
- [ ] Rebirth 1: the card "🏏 You got a Bat!" (after the tutorial); 1 / a
  tap equips it, again unequips; the equipped circle has a gold ring.
- [ ] Bat a player in front of you: they ragdoll with a hop and a
  "💫 BONK! 💫", stand up after 1.5 s, shimmer for 3 s (can't be hit). The
  cooldown wipe empties over 1.2 s; spamming does nothing extra.
- [ ] Right after spawning (5 s) nobody can hit you.
- [ ] Laser Gun: aim (mouse / screen centre on touch) at a runner 30+
  studs away: a thin red beam, they ragdoll; through a wall: no hit.
- [ ] Freeze Ray: the target turns icy blue and walks at 40% for 3 s.
- [ ] Banana Peel: it lands in front of you; the first enemy to step on
  it slips (SLIP!); one out at a time, gone after 20 s.
- [ ] Bat a thief mid-carry: the orb flies home, the owner sees "SAVED!",
  the thief "BONK! You dropped it!"; both inventories unchanged.
- [ ] Knock an owner off their pedestal: GUARDED drops, the steal works.
- [ ] While carrying: the bar is greyed, swings say "Hands full".
- [ ] While ragdolled: no prompts, LOCK says "Get up first!", a steal is
  refused.
- [ ] The Rebirth panel's unlock line lists 🏏 Bat / 🔫 Laser Gun / 🥶 Freeze
  Ray at Rebirth 1 / 2 / 3.
- [ ] `/selftest`: PASS "a Rebirth-0 player can't be hit", "the cooldown is
  enforced on the server", "knocking a thief returns the orb" (2 players),
  and the junk-remote fuzz (RequestHit) with no error or change.
