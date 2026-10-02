# Fusion Tycoon — UI Redesign (build prompt for Claude Code)

Paste everything below into Claude Code, opened on the `playable-loop` branch.

---

You are implementing a finished UI design for this Roblox game. The design is fixed: do not restyle, rename, or invent new screens. Every colour, size, font and behaviour you need is in this file. Where this file and the current code disagree, this file wins for the UI and the current code wins for game logic.

Read `CLAUDE.md` first and follow it: the service lifecycle rules, `RemoteEvents.lua` as the only place remotes are made, server authority, `PlayerDataService.SyncTycoon` for syncing, and `luau-lsp analyze` (not `rojo build`) as the check that code is valid. Work in the phases below, in order. After each phase, run the type check and fix every new error it reports in files you touched, then commit that phase on its own.

## Design language: "Fusion Lab"

The look is chunky arcade panels: dark violet surfaces, a thick ink-black outline on everything, and top-lit gradient buttons that sit on a solid ink shadow.

### Tokens

Create `src/ReplicatedStorage/Shared/Modules/UITheme.lua` with exactly these values. All UI reads from it. No hard-coded colours anywhere else in UI code.

| Token | Value | Use |
|---|---|---|
| Ink | `#0B0A1A` | every outline and drop shadow |
| Panel | `#17142E` | panel body |
| PanelTop | `#2A2552` | panel header tint (gradient top) |
| Panel2 | `#221E42` | rows, cards, footers |
| Panel3 | `#2D2856` | locked icon wells, pedestal bases |
| Disabled | `#3A3560` | locked/maxed/unaffordable buttons |
| Text | `#FFFFFF` | |
| Muted | `#B3AED6` | secondary text |
| Faint | `#7D77A8` | captions, empty states |
| Cash | `#4CF08A` | every money number |
| Danger | `#FF5470` | badges, error toasts |
| Goal | `#FFBE28` | goal tracker label and bar |

Button gradients (UIGradient, Rotation 90, top colour → bottom colour):

| Name | Top | Bottom | Use |
|---|---|---|---|
| Green | `#3BEB7E` | `#1FB458` | buy, confirm, Upgrades button |
| Blue | `#4FB3FF` | `#2378E0` | Items button, open |
| Violet | `#A47BFF` | `#6A3FE0` | fusion, multiplier |
| Red | `#FF7A8E` | `#E0304E` | close (X) |
| Gold | `#FFD566` | `#F0A100` | gacha |

Tier colours stay exactly as `FusionConfig.TierAccentColors`. For tier text on dark backgrounds use these lighter versions: Common `#DADADA`, Rare `#6CBBFF`, Epic `#D27BFF`, Legendary `#FFBE28`, Mythic `#FF6C82`.

Tier orb: a circle with a UIGradient. Light centre → tier colour → dark edge:
- Common `#FFFFFF` / `#C8C8C8` / `#5A5A5A`
- Rare `#CFE8FF` / `#3CA0FF` / `#12407A`
- Epic `#F0C8FF` / `#BE3CFF` / `#5A1080`
- Legendary `#FFF2C2` / `#FFBE28` / `#8A5A00`
- Mythic `#FFD6DD` / `#FF3C5A` / `#7A0A1E`

Use a radial-looking gradient: a UIGradient with Rotation 135 and a 3-key ColorSequence is enough. Add the 3 px ink outline. Epic and above also get a soft glow: a second, bigger circle behind it in the tier colour at 0.6 transparency.

### Type

- Display font: `Enum.Font.FredokaOne`. Use it for titles, all numbers, and button labels.
- Body font: `Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)`. Use it for labels, details, captions. Use `Enum.FontWeight.Heavy` for small all-caps labels such as NEXT GOAL and tier names.
- Big text gets a "drop" look: a `UIStroke` (Color Ink, Thickness 2, ApplyStrokeMode Contextual) on the TextLabel. Do not use TextStrokeTransparency.

### Shape rules

- Corners: buttons and rows 12–16 px, panels 22 px (UICorner).
- Every panel, row, card and button has a `UIStroke`: Ink, Thickness 3, ApplyStrokeMode Border. Big modals use Thickness 4.
- **Drop shadow:** a sibling Frame named `Shadow`, the same size and corner radius, filled Ink, offset 5 px down (4 px for small elements), ZIndex one below. Build this once in a helper.
- **Button press:** on MouseButton1Down, tween the button 4 px down and the shadow offset to 1 px over 0.06 s. On release, tween both back over 0.12 s with Back ease.
- **Popups:** open from UIScale 0.85 to 1 over 0.18 s with Back ease Out. Close to 0.9 and fade over 0.12 s.
- Numbers always go through `NumberFormat.Money` or `NumberFormat.Multiplier`.
- Every tap target is at least 44 px.
- **Mobile:** add a single `UIScale` on each ScreenGui. Set it to 0.8 when the viewport height is under 500 px, otherwise 1. Update it on ViewportSize change.

### UI kit

Create `src/StarterPlayer/StarterPlayerScripts/UI/UIKit.lua` with these constructors. Everything below is built from them:

- `Panel(props)`
- `Button(props: {Style, Text, Icon?, Size, OnClick})`
- `Pill(props)`
- `Badge(parent, count)`
- `TierOrb(tier, size)`
- `ProgressBar(props)`
- `Shadow(target)`
- `PopIn(gui)`
- `PopOut(gui)`

Icons: buttons take an optional image asset id. Put the ids in `UITheme.Icons` (Upgrades, Items, Close, Lock), set to `""` for now. When an id is `""`, render the label only, never a broken image. The current inventory icon `rbxassetid://18469524765` goes in `UITheme.Icons.Items`.

---

## Phase 1 — HUD (replace the current cash card, inventory button and upgrades button)

Rewrite `HudController.lua` and remove `InventoryButtonController.lua` (move its job into the HUD). Use one ScreenGui `Hud`, IgnoreGuiInset true. Leave the Roblox top bar clear: nothing in the top-left 0–170 px × 0–60 px.

**1. Goal tracker** (new, see Phase 5 for the data)
- Panel 260×auto at (12, 74).
- Contents, top to bottom:
  - A row with "NEXT GOAL" (Body Heavy 12, Goal colour, letter-spaced) on the left and the reward "+$500" (Body 12, Muted) on the right.
  - The goal text (Body 16, Text, wraps).
  - A progress bar: 14 px tall, Ink track with 2 px padding, Goal-gradient fill (`#FFD566` → `#F0A100`).
  - A right-aligned "1 / 2 Rare" line (Body 12, Muted).
- On phone, shrink to 168 px wide: hide the reward line and use a 10 px bar.
- When a goal completes, flash the panel border Goal-coloured, pop it, and swap in the next goal.

**2. Cash card**
- Panel 236×auto at (12, 274). On phone, place it at (10, 54) above the goal tracker instead, and put the goal tracker at (10, 132).
- First row:
  - A 34 px green coin circle: Green gradient, Ink outline, a "$" in Display 18 coloured `#0B3D1E`.
  - The cash amount: Display 34, Cash colour, with UIStroke. Show the number only (e.g. "48.2K"); the coin stands for "$".
- Second row:
  - "+$1.35K" (Body 16, Text) followed by "/s" in Muted.
  - On the right, the multiplier pill "x2": Violet `#6A3FE0` fill, 2 px Ink stroke, Body Heavy 13.
- Keep the current count-up easing on the cash number.

**3. Bottom buttons**
- Centered at the bottom, 22 px margin, 14 px gap.
- **UPGRADES**: Green, 176×64, Display 22. Shows a red Badge with the number of affordable upgrades; hide the badge at 0.
- **ITEMS**: Blue, 176×64. Opens Inventory in browse mode.
- On phone: 84×60 each, with the icon stacked above the label in Display 13.
- Keep the existing "pulse while something is affordable" behaviour on UPGRADES.

**4. Cash pop**
- Add a server→client remote `CashCollected {Amount, Position}`. Fire it from the Collector touch handler in TycoonService, only to the owner.
- The client shows a BillboardGui at the position with "+$24" (Display 26, Cash, with UIStroke). It floats up 4 studs and fades over 0.8 s.
- Throttle: if more than 6 pops are alive, merge new amounts into the newest one.

## Phase 2 — Upgrades panel

A modal of 520×620 max, centered, using UISizeConstraint, and 92% wide on phone. Rewrite the panel part of HudController into `UI/UpgradesPanel.lua`.

**Panel and header**
- Panel body is a gradient from PanelTop (top) to Panel at 22% down. Ink stroke 4, corner 22.
- Header: "UPGRADES" (Display 32, UIStroke) and a Red close button, 44×44, with an X.
- Tabs row:
  - "Generators" pill, selected: white fill, Ink text.
  - "Boosts · soon" pill: Panel2 fill, Muted text, not clickable.
  - Your live cash on the right of the row: Display 22, Cash.

**Generator rows** (84 px tall, Panel2, stroke 3, corner 14), left to right:
- A 10 px tier-colour bar.
- A 52 px rounded-square icon: a TierOrb-style gradient on a square.
- The name (Display 20) plus a level pill: tier fill, Ink text, "LV 11" or "MAX".
- Below the name: "$220/s · +$20/s next". The "+$20/s" part is Cash coloured. All numbers are post-multiplier.
- A buy button, 132×52. Its label is the cost (Display 17) with "UPGRADE" underneath (Body Heavy 11). The first purchase reads "BUY" instead.

**Row states**
- Affordable: Green button.
- Unaffordable: Disabled fill and Muted text, still showing the cost. Tapping it gives an error toast: "Need $13.5K".
- Maxed: Disabled with "MAXED".
- Locked:
  - The icon becomes a lock on Panel3.
  - The sub-line reads "Unlocks at **Flare Reactor LV 15**", with the name in white.
  - Add a 180 px progress bar under it. It shows the current level of the required generator against the required level, filled in that generator's tier colour.
  - The button is Disabled with "LOCKED". Row opacity is 0.92.
- Locked, two or more steps away: show the name as "???" and the sub-line "Unlock <previous> first". Opacity 0.7.

**Footer row** (Panel2):
- The multiplier pill.
- "All income multiplier · raise it at the **purple pad** in your base", with "purple pad" in `#C9A9FF`.

All the logic in the current HudController (RequestUpgrade, affordability checks) stays as-is.

## Phase 3 — Inventory (replaces the list in ItemPickerUI)

Rewrite `UI/ItemPickerUI.lua` as a grid. Keep its public API (`Open(entries, onSelect?, title?)`, `Close()`) so ItemController and the HUD keep working. Extend the entries to include `ItemId` and `InUse`; ItemController and the HUD must pass them.

**Panel and header**
- Modal 680×620 max. Header gradient top colour is `#1F3C78`, which makes it Blue-tinted to tell it apart from Upgrades.
- Header:
  - Title: "PICK AN ITEM" in pedestal mode, "YOUR ITEMS" in browse mode.
  - Subtitle in pedestal mode: "For Pedestal 3 · best items first".
  - Red close button.

**Filter chips**
- "All 14", then one chip per tier, Mythic first. Each shows a count and uses the tier's light text colour.
- The selected chip has a white fill with Ink text.
- Hide tiers with a count of 0, except "All".

**Grid**
- 4 columns (3 on phone), 12 px gap, ScrollingFrame with AutomaticCanvasSize.
- **Group identical ItemIds into one card with a count.** Never show 4 identical cards.
- Card, 178 px tall:
  - Background: a gradient from a dark tint of the tier colour (tier colour lerped 70% toward Ink) at the top to `#2A2140` at 70%.
  - A 74 px TierOrb.
  - Name (Display 16, centred, UIStroke).
  - Tier name (Body Heavy 11, tier light colour).
  - Earn rate "$50/s" (Body 12, Cash): pedestal income × the player's multiplier.
  - The count "x2" top-right (Display 16, UIStroke) when there is more than 1.
  - An "ON PEDESTAL" tag top-left (Cash fill, Ink text, Body Heavy 10) if any copy is on a pedestal.
- Sort: tier descending, then name.
- The last cell is a dashed "Pull at the Gacha Pad" hint card, only when there are fewer than 8 cards.

**Selection footer** (pedestal mode only):
- Tapping a card selects it: a 4 px white outline at offset 2, plus a slight pop.
- The footer row shows:
  - The selected item's orb and name.
  - "Earns **$100/s** with your x2 · Pedestals 3 / 4 used".
  - A Green "DISPLAY" button, 150×52.
- DISPLAY sends the Uid of a copy that is not in use.
- If every copy of the selected item is on pedestals, the button is Disabled and reads "ALL SHOWN".

Browse mode has no footer and nothing to select; cards only show info.

## Phase 4 — Fusion and Gacha results

**Big result card**
- Shown for Epic, Legendary and Mythic fusion successes, and for Epic+ gacha pulls. The card is centred and 420 px tall.
- Background: tier colour lerped 50% toward Ink at the centre, `#2A1550` mid, Panel at the edge. Ink stroke 4, corner 24.
- Behind the content: a slowly rotating sunburst. Use an ImageLabel if `UITheme.Icons.Sunburst` is set. Otherwise use 12 thin white Frames at 0.9 transparency, rotated around the centre, spinning at 20°/s.
- Content, top to bottom:
  - "FUSION SUCCESS" or "YOU PULLED" (Body Heavy 14, letter-spaced, tier light colour).
  - The tier name "EPIC!" (Display 64, tier light colour, UIStroke Thickness 4).
  - A 132 px TierOrb.
  - The item name (Display 28).
  - "2x Rare → Epic · earns $50/s on a pedestal" (Body 15, Muted). For gacha, drop the "2x Rare → Epic ·" part.
  - Buttons: **DISPLAY IT** (Green, 170×52) and **NICE** (Disabled fill, 120×52).
- DISPLAY IT places the new item on the first empty pedestal, using the existing RequestPlaceItem with that Uid and index. If all pedestals are full, it opens the Inventory picker instead, with the toast "Pedestals full · remove one first".
- Show the card after the machine's reveal animation finishes (`FusionController.FusionResolved`). It replaces the banner for these cases; don't show both.
- Mythic adds the existing camera shake.

**Fail card**
- A compact 92 px row at the bottom-centre, above the HUD buttons, for 3 s.
- Contents:
  - The orb at 0.85 opacity.
  - "So close…" (Display 22).
  - "Fusion failed · you kept **1 Rare** (Frost Crystal)" in Body 14, with the tier part in the tier light colour.
  - A Violet "AGAIN" button, 104×46. It is enabled only while the player is still in range of their machine and another pair exists. It calls a new public `FusionController.RequestFusion()` (export the existing local function).

**Small pull card**
- A 74 px row at the same spot, for Common and Rare gacha pulls.
- Contents: "PULLED" (Body Heavy 12, Gold `#FFD566`), a 40 px orb, the name plus the tier word, and "next pull $978" on the right in Muted.
- Each new pull replaces the current card instead of stacking.

**Common and Rare fusion successes** keep the top banner (Phase 6 style).

## Phase 5 — Goals (server-authoritative)

Add `src/ReplicatedStorage/Shared/Config/GoalConfig.lua` with this ordered list. Add a `GoalIndex` number to PlayerData, defaulting to 1, and handle it in `reconcile`. Add a `TotalFusions` number, incremented in FusionService on every fusion.

| # | Text | Done when | Progress shown | Reward |
|---|---|---|---|---|
| 1 | Claim your base | plot Claimed | — | $50 |
| 2 | Buy Dropper 2 | HasDropper2 | — | $60 |
| 3 | Buy a Basic Generator | basic_generator ≥ 1 | — | $100 |
| 4 | Pull from the Gacha Pad | GachaPulls ≥ 1 | — | $150 |
| 5 | Put an item on a pedestal | any pedestal filled | — | $200 |
| 6 | Fuse at your Fusion Machine | TotalFusions ≥ 1 | — | $300 |
| 7 | Own a Rare item | owns tier ≥ Rare | count of Rare / 1 | $400 |
| 8 | Upgrade your Multiplier | CashMultiplierLevel ≥ 1 | — | $1.5K |
| 9 | Fuse 2 Rare items into an Epic | owns tier ≥ Epic | Rare count / 2 | $3K |
| 10 | Unlock the Ember Forge | ember_forge ≥ 1 | Basic level / 5 | $5K |
| 11 | Own a Legendary | owns tier ≥ Legendary | Epic count / 2 | $20K |
| 12 | Reach a x3 multiplier | CashMultiplierLevel ≥ 4 | level / 4 | $100K |
| 13 | Own a Mythic | owns tier ≥ Mythic | Legendary count / 2 | $500K |

How it runs:
- A new `GoalService` checks the current goal whenever `PlayerDataService.SyncTycoon` runs. Expose a hook for this (e.g. `PlayerDataService.OnSync` BindableEvent); do not poll.
- When the current goal is met, the service pays the reward, advances `GoalIndex`, and fires `GoalCompleted {Index, Reward}`.
- The snapshot carries `GoalIndex` plus `GoalProgress {Current, Target}`, computed server-side.
- After goal 13, the tracker hides itself.
- On GoalCompleted, the client shows a Goal-coloured banner: "Goal complete! +$500".

## Phase 6 — Banners and toasts

**Banners**
- Restyle AnnouncementController's banner: 64 px tall, Panel gradient (Panel2 → Panel), Ink stroke 3, corner 18. It has a 10 px colour bar on the left and Display 21 text with UIStroke.
- Coloured words inside the text (tier names, multipliers) use RichText `<font color="…">`.
- **Server Mythic** variant:
  - 84 px tall, background gradient from `#6E0F24` (left) to Panel (right), a 50 px Mythic orb.
  - Two lines: "SERVER · MYTHIC" (Body Heavy 12, `#FF8FA0`), then "Hasan fused a MYTHIC Rift Engine!" (Display 25).
  - Holds 5 s.
- Legendary holds 3.5 s; your own events (multiplier, goals) hold 3.5 s.

**Toasts** (new `ToastController`)
- Small, 44 px tall, above the bottom buttons. Corner 12, stroke 3.
- Error toast: Red gradient fill. Neutral toast: Disabled fill. Text is Body 16.
- Holds 2 s, max 2 visible, no sound.
- Uses:
  - "Need $936 for a pull" (replaces the current banner version)
  - "Need $X" from the Upgrades panel
  - "Pedestals full · remove one first"

## Phase 7 — World labels (BillboardGuis)

Restyle every pad billboard in `TycoonService` and `FusionMachineService` to this pattern:
- **Title**: Display 30, coloured, UIStroke 2.5 Ink.
- **Price pill** under it: gradient fill, Ink stroke 3, Display 22.
- **Optional detail line**: Body 13 white with stroke.
- `LightInfluence = 0`.
- `AlwaysOnTop = false`. The current `true` draws them through walls.
- `MaxDistance` 26 studs.

| Billboard | Title (colour) | Pill | Detail |
|---|---|---|---|
| Gacha Pad | GACHA (`#FFD566`) | Gold gradient: "$936 / pull", text `#3B2300`, no text stroke | "Common 78% · Rare 18% · Epic 3.5%", built from `FusionConfig.GachaRates`, top 3 tiers |
| Multiplier Pad | MULTIPLIER (`#C9A9FF`) | Violet: "x2 → x2.5" | "$150K · press E". At max: pill "x12.5 MAX", no detail |
| Dropper 2 button | DROPPER 2 (`#7CF2A8`) | Green: "$60" | "Doubles your drops" |
| Claim button | CLAIM (white) | Green: "STEP HERE" | Owner sees "This base is yours, <DisplayName>". Other players don't see this billboard at all; set PlayerToHideFrom from the client |

**Pedestals**
- **Filled pedestal** (everyone sees it, MaxDistance 40):
  - A panel, Panel at 0.92 opacity, stroke 3, corner 14.
  - Contents: the tier word (Body Heavy 11, tier light colour), the item name (Display 22), and "+$440/s" (Body 14, Cash). The rate includes the owner's multiplier.
  - The server sets it in ItemService on place/restore and clears it on remove.
- **Empty pedestal** (owner only):
  - A dashed-look panel: Panel at 0.7, stroke `#7D77A8`.
  - Contents: "EMPTY" (Display 18, Muted) and "E to display an item" (Body 12, Faint).
  - Hide it for non-owners on the client.

**Fusion odds board**
- A panel with the title "FUSE 2 → TIER UP" (Display 20, `#C9A9FF`).
- Four rows: "2 Common → Rare" on the left, in the light colour of the tier you're fusing *into*, and "70%" on the right in white.
- Footer: "Fail = keep 1 of the 2" (Body 11, Muted).

**Plot sign** (new)
- A BillboardGui on a thin post at the front-left corner of each plot's Floor, 12 studs up. Use the PlotLayout offset; add constants there, never hardcode them in the service.
- Violet-gradient panel, stroke 4.
- Contents: "<DISPLAYNAME>'S LAB" (Display 28), then "$1.35K/s · best: Legendary" (Body 13, `#EDE3FF`).
- MaxDistance 120. The server updates it every 5 s.
- Before the plot is claimed, it reads "FREE LAB" with "Step on the green pad".

## Acceptance check (do all of these before saying you're done)

1. `luau-lsp analyze` shows no new errors. The pre-existing PadStyler/SparkleEmitter ones listed in CLAUDE.md are allowed.
2. `grep` finds no `Color3.fromRGB` in UI files other than `UITheme.lua`.
3. Nothing in the top-left 170×60 area. Every button is at least 44 px.
4. Write a short `docs/UI_TEST.md` checklist for the human to run in Studio. It must cover:
   - New save: goals 1→6 complete in order and pay out.
   - Inventory: identical items group with a count; DISPLAY works; "ALL SHOWN" appears when it should.
   - An Epic+ fusion shows the big card and DISPLAY IT fills a pedestal.
   - A fail shows the AGAIN row.
   - Phone emulator (iPhone 14 landscape) shows the phone layouts.
   - A second player in a local 2-player test can't see your empty-pedestal or claim labels but does see your filled pedestals and plot sign.
5. Update CLAUDE.md:
   - In the Layout section, add `UITheme`, `UIKit`, `GoalConfig`/`GoalService` and `ToastController`.
   - Add the rule "all UI colours come from UITheme".
6. Commit per phase, then push the branch.
