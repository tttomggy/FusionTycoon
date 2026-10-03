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
   - [ ] The tracker switches to **Buy Dropper 2 · +$60**.
   - [ ] The cash card goes up by $50.
4. Continue in order and confirm each goal pays and advances only after the
   previous one:
   - [ ] Buy Dropper 2 (+$60)
   - [ ] Buy a Basic Generator from UPGRADES (+$100)
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

- [ ] Pad labels (GACHA, MULTIPLIER, DROPPER 2) are no longer visible
  through walls, and fade out beyond about 26 studs.
- [ ] GACHA's detail line reads **Common 78% · Rare 18% · Epic 3.5%**.
- [ ] MULTIPLIER reads **x1 → x1.5** and **$5K · press E**, then **x12.5
  MAX** with no detail line at the cap.
- [ ] Collecting dropper cash floats a green **+$X** from the Collector.
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
  the claim pad straight ahead, Dropper 1 and the Dropper 2 slot on the
  left with the gold collector strip, the gacha and multiplier stations on
  the right, four pedestals across the middle, and the Fusion Machine at
  the back. Nothing overlaps, and nothing clips through the walls.
- [ ] **Gate ramp.** Walking from the street onto the floor goes up the
  ramp. If it's backwards (a step instead of a slope), flip the 180° in
  `PlotKit.BuildGateRamp`.
- [ ] **Stations.** Each pad glows in its colour with a floating hologram:
  the gacha capsule spins and bobs, the multiplier chevrons rise and snap
  back, the claim arrow bobs and disappears after claiming, and Dropper 2
  shows a translucent ghost until bought. The E prompt appears at about 7
  studs, and only the nearest prompt shows.
- [ ] **Droppers.** Green balls leave the spout on Dropper 1 (and Dropper 2
  once bought) and roll onto the gold strip. A "+$X" pops over the strip.
- [ ] **Pedestal orbs.** Display an item: the cap lights up in the tier
  colour and a glass orb (bigger for higher tiers) floats above it,
  spinning and bobbing. The label sits above the orb. Removing the item
  clears it.
- [ ] **Labels shrink with distance.** Walk away from a pad or pedestal
  label: it gets smaller like a real sign and never fills the screen up
  close. Pad labels vanish past about 90 studs, filled pedestal labels past
  70, and EMPTY labels past 25.
- [ ] **Fusion Machine.** A round platform with a violet rim, four leaning
  pylons and a floating core. The camera doesn't end up inside it. Fusing
  still plays the charge-up and reveal on the core. The odds board beside
  it is a real board facing the gate, angled toward the walkway.
- [ ] **Fuse All with 40 Commons.** `/cash 50000000`, pull until you have
  about 40 Commons, then stand at the machine:
  - [ ] **Hold F · Fuse All (N)** shows N = 20.
  - [ ] Holding it plays a 3 s charge-up, then **one** summary card (N
    fusions, upgraded/failed, tier chips with "−40 COMMON", BEST row).
  - [ ] DISPLAY BEST puts the best item on a pedestal.
  - [ ] With fewer than 2 pairs, the F prompt is hidden.
  - [ ] Legendaries are never consumed.
- [ ] **Goal marker on a fresh save.** `/wipe` → Play → claim. A gold
  marker labelled **BUY DROPPER 2** floats over the Dropper 2 slot (visible
  through walls), with a live "N studs" line and a pulsing gold ring on the
  floor. It hides within 8 studs. At the "Buy a Basic Generator" goal it
  points at the Basic Generator in the back-left bay (Polish 2).
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
  when filled. The collector is matte gold with two thin glowing edges.
  Wall strips are thin. Grass reads as grass, and the floor isn't
  black.
- [ ] **EMPTY pill.** Empty pedestals show a small "⊕ EMPTY" pill about 5
  studs up (owner only, hidden past about 20 studs). Filled labels sit
  above the orb.
- [ ] **Speed belts.** Standing on the green (south, −Z) belt with no input
  carries you toward +X at about 28 studs/s, and walking with the flow is
  about 44 studs/s. The blue belt goes −X. Ride each belt end to end: the
  rollers at the ends don't trap you, and chevrons slide along both belts.
- [ ] **Cash balls never ride a belt.** Belts don't collide with cash balls,
  which stay on the plots anyway.
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
- [ ] **Generator bays.** After claiming, the back-left bay holds three
  generators (Basic, Ember Forge, Flare Reactor) and the back-right bay
  two (Core Engine, Singularity Core), all facing the lab centre.
  - [ ] Basic Generator is a ghost in its tier colour with a **BUY /
    $25** label. The rest are faint ghosts with a lock on their screens
    and **LOCKED / <Required> LV N**.
- [ ] **Buying in the world.** Walk to the Basic Generator and press **E ·
  Buy / Basic Generator · $25**. Then check:
  - [ ] It turns into the real machine: dark body, tier band and a
    hovering orb, with **LV 1** on its screen.
  - [ ] There's a burst at the orb and the body bumps briefly.
  - [ ] A grey **+$1/s** toast shows (scaled by your multiplier).
  - [ ] The prompt now reads **Upgrade / LV 1 → 2 · $X**.
  - [ ] Without enough cash, the prompt shows the red **Need $X** toast.
  - [ ] Buying from the UPGRADES panel gives the same toast and
    animation.
- [ ] **Unlocks and max.** `/cash 5000000`. Basic LV 5 unlocks Ember
  Forge (it becomes a BUY ghost). The band turns Neon at LV 10. At LV 25
  the screen reads **MAX**, the band glows with a light, and the prompt is
  gone.
- [ ] **Income pops.** Each owned generator floats a **+$X** in its tier's
  light colour above its orb once a second (its income/s with the
  multiplier). There's one pop per generator, never stacked, and none
  when you're more than about 60 studs away.
- [ ] **Upgrades panel.** Under the title: **Generators earn every second,
  even while you're away. Find them in the back corners of your lab.** The
  total generator income/s is on the right. The tabs and list sit below
  it without overlap (desktop and phone).
- [ ] **Goal marker.** On a fresh save, the "Buy a Basic Generator" goal
  marker points at the Basic Generator. The "Unlock the Ember Forge" goal
  points at the Ember Forge.
- [ ] **Two players** (2-player local server): as Player 2 you can see
  Player 1's generators but **not** their BUY/LOCKED labels or their
  Buy/Upgrade prompts, and you can't trigger them.
