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
