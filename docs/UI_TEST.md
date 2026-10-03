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
4. A Common or Rare gacha pull shows the smaller **PULLED** row with **next
   pull $X**, and a new pull replaces it.

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
  - [ ] The header pill shows the bonus, and the count line reads **n / 68
    found · +1% each · +5% per full tier page**.
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
  - [ ] AUTO-FILL never takes mutated items.
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
  pedestals, and A's HUD has no shield chip. After `/rebirths 1` (wait
  ~5 s for the sign) the pill goes and the chip appears.
- [ ] **Shield + eject.** On claim the shield is up 60 s: a pink ForceField
  fence round A's walls and a line across the gate, seen by both players.
  A's chip reads **🛡 SHIELD · 42s**. B walking in is moved to the street in
  front of A's gate. When it ends the fence fades and the chip reads
  **SHIELD RECHARGING · 20s** (muted, counting down) while A's pad label
  (owner-only) shows **READY IN 20s**; then the chip pulses amber **SHIELD
  DOWN · step on YOURS**, the pad reads **SHIELD READY**, and A stepping onto the
  YOURS pad raises it for 60 s.
- [ ] **Standing on the pad doesn't re-raise.** A stands still on the YOURS
  pad and runs `/shield 0`: the fence drops and stays down while A stands
  there. Stepping off and back on raises it again (`/shield 0` lifts the
  re-arm lock, so it works straight away).
- [ ] **20 s re-arm.** Let A's shield time out (or `/shield 5`, wait 5 s).
  For 20 s, stepping off and onto the pad does nothing and the pad counts
  **READY IN …**; B can grab in that window. After 20 s, stepping
  onto the pad raises it. The claim shield and the 120 s shield after a
  loss go up regardless of the lock.
- [ ] **Steal and deliver.** Shield down: B holds E on A's pedestal
  (**Steal**, the item's name, 1.5 s).
  - [ ] B: the orb over B's head (Golden shell and 2 satellites), a red
    beam, **THIEF · 45s** (A sees them too), B walks slower, an orange
    **GET HOME!** banner with a draining bar, and the arrow on B's gate.
  - [ ] A: the pedestal shows a red ghost ring and **STOLEN!** +$0/s, A's
    income drops by that item, a red **THIEF IN YOUR LAB!** banner with
    the distance, a red **THIEF!** arrow following B, and the alarm.
  - [ ] B reaches home: **HEIST COMPLETE!** for B, the item (still Golden)
    in B's inventory with a new Uid; A gets the stolen card (shield up
    2 min), the pedestal is empty, and A's shield auto-raises for 120 s.
  - [ ] Server banner (Legendary+): **B stole a Golden <item> from A!** (Golden in its colour)
- [ ] **Steal and tag.** B grabs, A touches B (within 5 studs): A gets
  **SAVED! You got your … back**, B **Caught!**, the item is back on the
  pedestal, the banner reads **A caught B!**.
- [ ] **Timeout.** B grabs and waits 45 s: **Too slow!**, the item returns.
- [ ] **Cooldown.** Right after any attempt B gets **Lay low for 60s**;
  `/heistcd 0` clears it.
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
  first!**; the Fuse panel's FUSE / FUSE ALL do too (no charge-up); B
  stepping on their YOURS pad doesn't raise B's shield.
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
