# Items, fusion, mutations, auto-display, rebirth, Index, settings

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

Rebirth (`RebirthService`, numbers in `RebirthConfig`) costs cash
(`RebirthConfig.GetCost`: $15M ×3.2 each time); cash going to 0 pays it. It
resets cash, generators (Basic back to LV 1), the Multiplier Pad and the
gacha price; it keeps every item, the pedestals, the Index, goals and the
rebirth count, and gives
income ×(1 + 0.5 n) and luck ×(1 + 0.05 n) (luck raises Legendary/Mythic
gacha odds via `FusionConfig.GetGachaRates`, and every mutation chance).

Items (Depth 1): six tiers up to **Secret** (gacha 0.002%, or fuse 2 Mythics
at 8% once you have Rebirth 1 — `FusionConfig.CanFuseTierFor`). Any pull or
successful fusion can roll a **mutation** (`MutationConfig`, ranked by
multiplier: Golden ×2, Charged ×3, Diamond ×5, Void ×8, Rainbow ×12,
Celestial ×20; Charged / Void / Celestial are **event-only**, 0 normal
chance, `MutationConfig.IsEventOnly`; they STACK on top of a base, see
**Stacking mutations**). Fusion rules: a success keeps the *lowest*
base mutation among all inputs (so every input must share it), then may roll a
better one; a fail keeps the best input untouched (same Uid) and removes
the rest; Fuse All (pairs, Common–Epic) never touches mutated items.
`FusionConfig.PredictMutation(inputs)` (the lowest input mutation) is what
FusionService carries and what the Fuse panel predicts **before** FUSE
(`GetMutationMix`): every orb the same mutation → "✨ Keeps GOLDEN ×2, might
roll better"; mixed → a red warning box naming how many lower orbs are in
and what is lost ("⚠ 1 plain orb mixed in: the Epic comes out plain, not
Golden…"), those orbs ringed red; all plain → no line. AUTO-FILL only adds
the first orb's mutation (an empty chamber fills plain orbs; with NO plain
orb of the tier it fills the largest same-stack group of mutated orbs, not
carried or displayed, needing 2+, ties to the lower stacked value, toast
"Filled with GOLDEN orbs (they keep their mutation)", else "Not enough
matching orbs to fuse" + a tab pulse; `FusionController.GetAutoFill`, AGAIN
and FUSE ALL still skip mutated items). The fusion
result carries `MutationSource = "Kept" | "Rolled"`: the big card shows
the pill and "GOLDEN kept" / "GOLDEN rolled!";
the fail card says "Kept your Golden Rare (…)". The five count chips sit in
**one row** (non-wrapping list, scale widths, 6 px gaps; the % TextScaled
with a max of 18). The **Index** (`IndexConfig`, 119 entries =
17 items × 7 variants, built from `MutationConfig.Order`) pays +1% income per entry and +5% per full tier page, and
survives rebirths. Every odds display goes through `FusionConfig.FormatOdds`
(the same functions the rolls use).

**Gacha pop-up card** (`Controllers/GachaBoardController`, client only): a
**pixel-sized `BillboardGui` adorned to YOUR Gacha Pad**, floating right over
it and opening as you walk up (the Pet Simulator 99 egg card). This is the
final placement: not docked, not following the camera. History: the first
in-world tries were sized in studs (huge up close) and sat "above your head"
while you stand ON the pad (off the top of the screen); a screen-space dock and
a screen-space follower were tried and rejected. Fix: pixel size, anchored to
the PAD (you pull with E / R / T from `PromptDistance` + 3 studs, so you stand
in front of it and see the card over it).
- **Billboard:** `Adornee` = an `Attachment` `GachaCardAnchor` on the pad, `Size`
  = 300 × 324 px (38 px of room above for the title / (i) / event chip + the
  300 × 196 card + the 90 px E / R / T row; 0.8 on a phone through one
  `PhoneScale` UIScale about the bottom line), `SizeOffset` (0, 0.5) so it grows
  upward from the anchor (the captions' bottom edge is on it).
  `StudsOffsetWorldSpace` stays zero; `StudsOffset` is (0, 0, 2) (camera-relative
  +Z = toward the camera, so the card draws in front of the 1.3-radius ball with
  `AlwaysOnTop` off). Neither is written again.
  **Why an Attachment:** the pad is a cylinder turned 90° about Z (StationKit),
  so its local +Y points sideways; an offset on the pad itself (`(0, Size.Y/2 +
  5.8, 0)`) pushed the card ~9.8 studs sideways, never above the ball. The
  Attachment's `WorldCFrame` is set once to straight above the pad's centre,
  `AnchorUpStuds` over its top (world-axis top = centre + the oriented box's
  half-extent on y): pad top + 2.2 studs = the capsule ball's base, centred.
  `AlwaysOnTop` false, `LightInfluence` 0, `MaxDistance` 150, `ResetOnSpawn`
  false, no `CanvasGroup`.
- **Pop:** in at `PopInStuds` (16) from your character to the pad, out at
  `PopOutStuds` (19); one `PopScale` UIScale 0.85 → 1 over 0.12 s (Quad).
- **Covers:** while open it hides the pad's small `GACHA` / price label and your
  own `VipTag` head chip, and **the capsule ball** (`CapsuleTop` / `CapsuleBottom` /
  `CapsuleBand` get `LocalTransparencyModifier` 1, back to 0 on close, so the
  card replaces the ball like PS99's card hides the egg and nothing pokes out);
  all restored on close. The pad's prompts stay off.
- **Anchor never moves:** set once when the card is built, `AnchorUpStuds` =
  (`Station.CapsuleY` − `CapsuleDiameter`/2) − `Station.PadTopY` = 2.2, the
  ball's base, computed from the Station numbers so it can't drift
  (`PlotLayout.Gacha` is defined after `Station`). The card (buttons at the
  ball's base, the card rising above them) covers the ball. (History: 3 = the
  middle of the ball, then 5.8 above the ball, which floated the card high and
  put its top under the event bar; no zoom or camera logic at all.)
- **Hidden** (the pop out, keys unbound) while any overlay is open
  (`UIKit.IsOverlayOpen`: a modal, the reveal / big result card, the (i) panel),
  during a ragdoll and while carrying; back after.
- **Built once, hidden**, as soon as the pad exists. A refresh (every sync and
  0.5 s) only updates text and colours (`updateContent`), never rebuilds. 2D
  orbs (`UIKit.TierOrb`), no `ViewportFrame`, no `CanvasGroup`, no
  `TextScaled`. The only `UIScale`s: `PopScale`
  (0.85 → 1 in 0.12 s Quad-Out, reversed on close) and the phone's `PhoneScale`.
- **Visibility follows the character, not the camera:** the distance from your
  `HumanoidRootPart` to the pad; inside 16 studs it opens, beyond 19 it closes
  (the gap stops flicker).
- **The card (design px) — restyled to match Pet Sim 99's egg card
  (`GACHA_CARD_PS99_STYLE`):** a 300 × 196 **white** card (`UITheme.Colors.CardPaper`
  with a soft `CardPaperShade` diagonal as a UIGradient — no pattern asset —
  and a 3 px `CardPaperStroke` rim, 18 px corners). No dark panel, gold rim or
  header bar. "Gacha Pad" (Display 26, white, ink stroke) is centred on the
  card's top edge at x 10; the `🍀 Luck ×N` pill (only when luck > 1) just right
  of it, the live event chip on its own row above the title. (i): a 34 px
  `Gradients.Blue.Top` circle, 3 px white rim, right edge 6 px inside the
  corner, centre on the top edge, a 56 px hit area (opens the per-orb panel).
  **Orb grid:** 3 × 2 cells of 92 × 82 (gap 4), no tile backgrounds or ribbons:
  a 58 px 2D `UIKit.TierOrb`, its % (22 px Display, tier accent, 2 px ink stroke
  over a 3 px white outline — two labels, `Percent` over `PercentOutline`)
  overlapping the orb's bottom by ~10 px. A never-found tier is a **solid black
  orb**, same size, no "?", and STILL shows its %. Secret has a soft rainbow
  glow behind the orb (no animated stroke). **Mutation odds** (Paid Random
  Items): ONE 12 px rich-text line inside the bottom-left
  (`✨6.9%  💎1.4%  🌈0.17%`, each value in its mutation colour, ink stroke; 10 px
  when more than four). **Price:** a 16 px gold coin + the amount (24 px
  Display, gold, ink stroke; `FREE` during the tutorial pulls) centred on the
  card's bottom edge at the right.
- **The key bar** (10 px under the card): round solid-`Gradients.Blue.Top`
  buttons with a 4 px white rim and a soft ink shadow — E (Pull) and T (Auto)
  52 px, R (×10) 62 px in the centre; on a phone the sides are 56 px so they are
  ≥ 44 px after the 0.8. The key letter inside (Display 28, white, ink stroke; a
  controller shows its glyph; touch uses the same circles as tap targets), a
  white 14 px caption under each: `Pull`, `×10`, `Auto` (T's circle turns green
  and reads `Auto ON` while it runs). Prices are on the card, not the buttons
  (the ×10 price is no longer shown). It does **not** use
  `ProximityPrompt` UI: the pad's Pull / Pull ×10 / Help prompts are disabled
  on the server (still wired to the same function) AND kept off on this client.
  (The "H · How it works" you may still see is the LOCK console's own prompt.)
  While the card is open E / R / T (X / Y / RB) are bound with
  `ContextActionService`, unbound when it closes; out of reach the key is
  passed on. They send `RequestGachaPull { Count = 1 | 10 }` and `SetAutoPull
  { On }` (TycoonService validates: data loaded, your own pad, root within
  `PromptDistance + GachaConfig.RangeSlack` studs, rate-limited) and run the
  **one** pull function `createGachaStation` also gives the prompts. The
  tutorial's big PULL button sends the same remote. "How it works" is the first
  section of the (i) panel.
- **Auto pull (T = "Auto ×10")**, free for everyone (see monetization.md): each
  cycle is a **×10 pull at the ×10 price** through the same `pull(10, true)` the
  R key and `RequestGachaPull { Count = 10 }` run (no second copy), until you
  can't afford ×10, walk more than `PromptDistance + 3` studs away, start
  carrying, die, leave or press T again; `AutoPullState { On, Reason?, Cost? }`
  turns the T button green ("Auto ×10 ON") and toasts why it stopped ("Auto
  stopped: need $3.06K for 10 pulls"; the reason is `InsufficientCash`). The
  client shows the same 10-pull card a manual R shows every cycle
  (`GachaMultiPullResult { Auto = true }`), which **closes itself after
  `GachaConfig.AutoPullCardSeconds` (2.5 s)**; the BEST OF 10 big card follows
  the reveal rule exactly as a manual ×10 (Secrets and event mutations always)
  and waits for the player. Auto pull never uses the small skipped lines.
  **Pacing:** when the cycle's cards have closed the client fires
  `AutoPullReady` (C→S, no payload, `RemoteGuard`-limited); the server starts
  the next ×10 only then, or after `GachaConfig.AutoPullTimeoutSeconds` (8 s),
  and never sooner than `GachaConfig.AutoPullMinSeconds` (3 s) after the
  previous one, so a Secret's big card pauses Auto pull until it is closed.
- **Far away** (and on other players' pads) the small server `GachaLabel` (name
  + price, no odds lines) shows; the controller hides it while the card is up.
- **Selftests** read the instance tree (`AbsoluteSize` > 0 on both axes,
  `Visible` up the chain, `TextBounds.Y` > 0); every FAIL carries its
  measurements. `/selftest gacha`: the card opens fully in one frame; **with the
  character on the pad and the camera at 6 studs, default, max zoom-out,
  top-down and looking away, for the desktop and the phone HUD layout, the card
  + button row is inside the safe rect and overlaps no HUD rect (left column,
  weapon bar, bottom row, TopStack)**; the clamp math at 1366 × 768 and 844 × 390
  (inside the rect, squeezed only when short, min 0.7); a modal hides it and it
  returns; no `ViewportFrame` / `CanvasGroup`, only `PopScale` (+ the phone's `PhoneScale`); no
  gacha prompt draws UI; odds, silhouettes, luck, the (i) sums, keys and auto
  pull.
Odds source: `FusionConfig.GetGachaOddsRows(luck, event)` (built on
`GetGachaRates` and `MutationConfig.GetChance`; `FormatOdds` is built on the
same rows), yours at `TycoonController.GetLuck()` (the server's `LuckBase`
from each `SyncTycoon` × the live admin-luck value). The (i) button opens the
per-orb panel (`UIKit.Modal`, tier % / orbs in the tier because
`PickRandomOfTier` is uniform). `TycoonConfig.MultiPullCount` (10) is shared.
Paid-Random-Items compliance: every outcome's % is on the card before you
pull, luck and the event are the live disclosure, a silhouette hides the
look, never the odds.


- **Auto-display** (Playtest 7): players never choose. `ItemService.Arrange
  (player)`, the ONE re-arrange, is a `PlayerDataService.OnSync` hook, so
  every change (pull, fusion, Fuse All / Auto-Fuse, delivery, theft, event
  mutation, rebirth, reward item, `/give`) lands on the pedestals in the
  same sync: the unlocked spots in fill order
  (`PlayerDataService.GetPedestalOrder` / `PlotLayout.GetPedestalOrder`:
  1 → 4, 5 → 6 with the pass, then the 2nd floor's 7 → 10 from Rebirth 2)
  hold the highest `TycoonConfig.GetStackCashPerSecond` (ties: tier,
  what's already up, Uid); a new unlock restyles the spots even when
  nothing moves. A carried item's pedestal is left alone (`BeingStolen`) until the
  heist ends. It sets `InUse`, re-applies only changed pedestals, sends
  `SyncInventory` when ON DISPLAY tags change, announces a newly displayed
  Legendary+ and fires `FirstDisplay`. No place / remove remotes, no
  Display prompt, no pedestal picker, no DISPLAY IT; ITEMS is the
  inventory view (ON DISPLAY tags); the owner prompt left on a pedestal is
  the locked spots' `UnlockPrompt`. Displayed items can be fused (spare
  copies first); only a carried one can't (`ItemCarried`).
- **Stacking mutations** (`MutationConfig`; like Grow a Garden). An item
  has ONE base mutation (`Item.Mutation`: none / Golden / Diamond /
  Rainbow) plus a set of event mutations (`Item.EventMutations`: Charged /
  Void / Celestial, sorted by rank, each at most once,
  `MutationConfig.SanitizeEvents` in `reconcile`; an old save's
  event-only base moves into the set, `Normalize`). The multiplier is
  **additive**, `1 + Σ(mult − 1)` (`GetStackedMultiplier`: Rainbow +
  Celestial = ×31, not ×240), through `TycoonConfig.GetItemCashPerSecond
  (tier, mutations)` / `GetStackCashPerSecond(item)` everywhere. Sources
  ADD (`AddEvent`, `PlayerDataService.AddItemEventMutation`): a Power
  Surge strike stacks Charged on any item not yet Charged, a Void Moon
  fusion stacks Void on what was kept, a meteor core rolls the normal base
  then Celestial on top, a pull rolls the base then the event roll
  (`MutationConfig.RollEvents`; 0 outside events). Fusion success keeps
  the lowest base AND the event mutations every input shares
  (`FusionConfig.PredictEventMutations`, the intersection); a fail keeps
  the input with the best stacked multiplier; Fuse All skips anything
  mutated. The Fuse panel says "✨ Keeps GOLDEN + CHARGED ×N" or names
  what a mixed chamber loses, red-ringing every orb that drags it
  (`FusionConfig.IsDragging`); AUTO-FILL matches the whole stack
  (`SameStack`). Index: a stacked item fills the entry of EACH mutation
  it has (119 entries unchanged). Looks: `UIKit.MutationPill({ Mutation,
  EventMutations })` is a row of pills side by side + an Ink "×N" total;
  orbs and card strokes use the top mutation (`GetTop`); satellites mix
  every mutation's colour (top's count + 1 per extra); the reveal card
  reads "+ CHARGED (stacked!)" (`EventReward` / `FusionResult` carry
  `Added`, `Stacked`); pedestal chips, banners and heist carries
  (`HeistEventMutations` "Charged,Void") carry the whole stack. Sim:
  events +13.3% / +14.6% / +13.6% sooner for Rebirth 1–3 (≤ 15%).
- **REBIRTH button:** the bottom bar is UPGRADES · ITEMS · INDEX ·
  **REBIRTH** · ⚙. Purple, always there, a fill of cash against
  `GetRebirthCost` and "$2.1M / $15M"; glows and pulses once affordable;
  opens `RebirthPanel` from anywhere (it replaced the floating REBIRTH!).

- **Settings** (`SettingsConfig`, saved as `PlayerData.Settings`, sent as
  `Settings` in the snapshot): `RevealRule = { [tier] = "Never" | "Golden"
  | "Diamond" | "Rainbow" | "Always" }` for Common → Mythic; "Golden" =
  Golden or any higher-ranked mutation (`MutationConfig.GetRank`). The
  defaults are **derived** from `FusionConfig.IsMajorReveal` (a
  `MajorRevealTiers` tier → Always, else the lowest threshold reaching
  `MajorRevealMutationRank`, i.e. Diamond); old saves get them. **Secret and
  the event-only mutations always show** (`SettingsConfig.ShowsBigCard`).
  Remote `SetSetting` (C→S `{ Key = "RevealRule", Tier, Value }`,
  tier/value whitelisted; a coalesced sync 0.25 s later echoes it).
  `ResultController.ShowsBigCardFor` reads the rule for BEST OF 10 and
  Auto-Fuse / Fuse All only (fail cards unchanged); a **single pull always**
  gets the big card (Tutorial 2), and so does **every successful single
  fusion**, at every tier: caption "FUSION SUCCESS", headline "<TIER> ORB!",
  the kept / rolled line, "2x Common → Rare · earns $X/s on a pedestal"
  (a Rare closes after `SINGLE_PULL_AUTO_CLOSE_SECONDS`). Because of that
  your own fusion has no top banner and no small line
  (`ResultController.FusionBannerShows` is always false; other players still
  see the server-wide banner). A skipped card (BEST OF 10 / Auto-Fuse) pops a **small line** above the bottom bar for 2.5 s (orb
  dot, "+ Golden Plasma Orb" in the mutation colour, the tier, "+$X/s";
  max 3, older ones fade; a fixed 720 px box centred at the bottom, raised above the weapon bar when that stands higher, `/selftest` "skipped lines never overlap the HUD"). The tutorial `fuse` step now waits for this card
  like the pull's (`screenQuiet`); /selftest probes "RARE ORB!" after it. The client applies a change at once
  (`TycoonController.SetRevealRule`, kept until the snapshot echoes it).
  UI: the **⚙** 56 px button after REBIRTH opens `UI/SettingsPanel` (620
  wide, one scrolling list of sections: "Big reveal card" (one 5-segment
  row per tier + a locked Secret row), "Sound effects" and "Music" (see
  Sounds: `Settings.MusicOn` / `MusicVolume`, default on at 25%) and a
  tutorial replay).
- **Odds board** (FusionMachineService + `BillboardKit.OddsSurface`): 9 × 6
  studs at 60 px/stud, a real table (one rounded cell per %, 100% teal),
  no mutation line (the pad and Index have it). `SetOddsChances(gui, rows,
  { Rebirths, Boosted })` on every sync: the Mythic → Secret row reads "R1"
  until the owner has Rebirth 1, a Void Moon turns every cell purple with
  the boosted number. The Fuse panel's chips are one two-line chip per
  count, the chamber's count highlighted.
- **Index book** (`UI/IndexPanel`, 720 wide): tier tabs (name in the tier
  colour, "8 / 21", a thin bar, "+5% at 21" on the selected one); column
  headings in the mutation colours, event-only ones with ⚡ 🌙 ☄ (not
  tappable); one row card per item (name, "3 / 7 · $/s", seven orb cells:
  found = `UIKit.TierOrb` + the mutation's look, Rainbow hue-cycling only
  while open; missing = a dark dashed well with "?" or the event icon). A
  7/7 row gets a gold stroke + glow and "★ COMPLETE 7/7". Tapping an orb
  fills the bottom **info strip** ("<Item> · <Variant ×N>", how to get it,
  found / not found yet). Only the selected tier is built; it rebuilds on
  a tab change, an Index change or a phone switch (orbs 54 → 40 px, the
  cell stays the ≥ 44 px target). No check marks or clocks.
- **MAX upgrades:** `RequestUpgradeMax` (C→S `{ GeneratorId }` or
  `{ All = true }`) loops TycoonService's `buyOneLevel`, the same path as
  `RequestUpgrade` (cost, unlocks, cap, Carrying), up to
  `TycoonConfig.MaxUpgradeSteps` (500); All buys the cheapest available
  level each step (`GetCheapestUpgrade`, unlocks re-checked). One sync and
  one `UpgradeMaxResult { Levels, Spent, PerGenerator, NewLevels }`;
  nothing is spent if no level was bought. The panel's "MAX ×N / $X",
  "MAX / need $X" and "⚡ MAX ALL · $X" come from
  `TycoonConfig.GetMaxAffordable(generator, level, cash)` and
  `GetMaxAllPlan(levels, cash)`, so labels and server agree. Toast "+9
  levels · Core Engine LV 15" / "+23 levels across 3 generators", one
  bump per changed generator; the panel refreshes at most 4×/s.

*Board bug fixed (Oct 13), kept for the lesson:* `buildTile` / `buildChip`
returned their frames but never parented them, so the first board drew only
its header and price pill. The selftest read the controller's own table and
passed anyway; every card / button check now reads the instance tree
(`gui:GetDescendants()`, `AbsoluteSize` > 0 on both axes, `Visible` up the
chain, `TextBounds.Y` > 0) and every FAIL carries its measurements in `Detail`.
