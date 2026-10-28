# Items, fusion, mutations, auto-display, rebirth, Index, settings

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

Rebirth (`RebirthService`, numbers in `RebirthConfig`) costs cash
(`RebirthConfig.GetCost`: $15M ×3.2 each time); cash going to 0 pays it. It
resets cash, generators (Basic back to LV 1), the Multiplier Pad and the
gacha price; it keeps every item, the pedestals, the Index, goals and the
rebirth count, and gives
income ×(1 + 0.5 n) and luck ×(1 + 0.05 n) (luck raises Legendary/Mythic
gacha odds via `FusionConfig.GetGachaRates`, and every mutation chance).

**Gacha price rule** (`TycoonConfig.GetGachaPullCost(pulls, steadyIncome)`):
`floor(min(250 × 1.045^pulls, max(250, GachaMaxIncomeSeconds × steadyIncome)))`,
so the price climbs as before early in a run but one pull never costs more than
`GachaMaxIncomeSeconds` (15) seconds of **steady** income. Steady income is
`TycoonConfig.GetSteadyIncomePerSecond(inputs)`: the same `IncomeInputs` and
`GetPassiveCashPerSecond` with the event generator boost, Boost, Overclock **and
passes** forced to 1, so a timed boost or a bought 2× Cash / VIP never raises
the price. `GetGachaMultiPullCost(pulls, count, steady)` is the sum of the next
`count` prices. The server charges with `PlayerDataService.GetSteadyIncomePerSecond`;
the pad card and Rebirth panel use `TycoonController.GetSteadyIncomePerSecond`
(a mismatch lasts until the next sync). `tools/econ_sim.py` mirrors it
(`GACHA_MAX_INCOME_SECONDS`, `--cap=N`; its player spends at most `PULL_SHARE`,
25%, of income on pulls only the cap makes cheap, `--share=N`). Cap 15 keeps a
×10 pull at 150 s of steady income late in a run (uncapped 5–12 min); it does
not bring the first Secret in (see the TycoonConfig header table).

**Friend boost** (`FriendConfig`, `FriendService`): every Roblox friend in your
server adds +15% to ALL your income, at most 4 friends (+60%). It is a boost,
like the Overclock:
- `TycoonConfig.IncomeInputs.FriendMultiplier` (`1 + 0.15 × min(count, 4)`) is
  multiplied in `GetIncomeMultiplier` and has a "Friends" row in
  `GetIncomeBreakdown` (the HUD pill hides it at ×1). It is built only in
  `PlayerDataService.GetIncomeInputs` (1 when `baseOnly`) and
  `TycoonController.GetIncomeInputs`.
- It is NOT in `GetSteadyIncomePerSecond` (the gacha price ignores boosts), and
  not in offline earnings, cash packs or quest targets (all `baseOnly`;
  `ShopController.GetBaseIncome` sets it to 1 on the client). `tools/econ_sim.py`
  stays solo (`FRIEND_MULT = 1`).
- The count is server-side only. `FriendService` asks
  `Player:IsFriendsWithAsync` (pcall'd; a failure is "not friends"), caches each
  pair for `FriendConfig.RecheckSeconds` (60), and recounts on PlayerAdded (the
  pairs with the new player) and PlayerRemoving (no banner). It stores the
  count with `PlayerDataService.SetFriendCount`; the snapshot ships it as
  `SyncTycoon.Friends`. A join syncs both players; the `FriendJoined` remote
  (`{ Name, Percent }`) makes both clients show "👥 <DisplayName> joined: +15%
  income!" (TopStack announcement), only to a player whose boost really grew.
- **Friends made mid-session:** a loop spawned in `:Start()` calls
  `FriendService.RecheckStep` every 0.5 s: it re-asks the ONE pair with the
  oldest answer past `RecheckSeconds` (never a burst), and if the answer changed
  recounts both players from the cache and syncs only those whose count moved.
  A count that grew sends `FriendJoined` with `Friended = true`: "👥 You and
  <DisplayName> are friends: +15% income!".
- HUD: the **Friends** chip is the always-on, rightmost cell of `UI/EffectsTray`
  (👥, "+30%", "+0%" with no friends; tooltip "Friends in this server: +15%
  income each (max +60%)"). A tap asks `SocialService:PromptGameInvite` when
  `CanSendGameInviteAsync` (pcall'd, cached 60 s) allows it, else it only pins the
  tooltip. Roblox's own age/privacy rules decide who can invite.
- `/selftest` section 14 (`/selftest friends`): `FriendService.SetCheck(stub)` +
  `Recount(player, fakePeers)` give 0, 2, 6 friends and a throwing call;
  `SetCheck(nil)` restores the real check. `SetClock(fake)` + `RecheckStep(peers)`
  flip a pair to friends and age it past 60 s: both counts +1, one call;
  `SetClock(nil)` restores `os.clock`. A client probe (`FriendChip`) checks the chip.

Items (Depth 1): six tiers up to **Secret** (gacha 0.002%, or fuse Mythics
at 7–15% once you have Rebirth 1 — `FusionConfig.CanFuseTierFor`).

**Secret pity meter** (`FusionConfig.SecretPityFull`, 12; `PlayerData.SecretPity`,
saved, in the snapshot, kept through rebirths). A **failed** Mythic → Secret
fusion adds its input count (`GetPityCharge`: 6 inputs +6, 2 inputs +2; the
meter stops at full). At full the next Mythic fusion is a sure success
(`GetFusionChanceWithPity` → 100%, so the Fuse panel's %, the chips and the
roll agree); a Secret from a fusion, lucky or pity, resets it to 0; a Secret
from the gacha doesn't touch it; other tiers never charge it. `FusionService`
is the only writer (`PlayerDataService.Get/SetSecretPity`); the fusion result
carries `Pity`, `PityGained` and `SurePity`. Safe Fusion still charges it (it
only keeps the orbs). Fuse panel: on the Mythic tab, once Mythic fusion is
unlocked, a slim "SECRET METER n / 12" bar under the success % (mint fill, 14 px
text); at full it reads "NEXT FUSE IS A SURE SECRET!" and the % and chips show
100%. The fail card adds "Secret meter +n". Chosen with `tools/econ_sim.py
--pity=N` (the TycoonConfig header table has the sweep): 12 is a deliberate
long chase (first Secret ~7:23 at `--fuse=2`; two failed 6-orb fusions or six
failed pairs fill it). 4 would land in 3–5 h but one failed 4+ orb fusion filled
it, and Harris wanted Secrets to stay the long chase. `--fuse=3` stays out of
reach because that player never has spare Mythics (Mythic supply, not odds).
Odds in this paragraph (7–15%) are unchanged. Any pull or
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
carried (displayed ones allowed, spare copies first), needing 2+, ties to the lower stacked value, toast
"Filled with GOLDEN orbs (they keep their mutation)", else "Not enough
matching orbs to fuse" + a tab pulse; `FusionController.GetAutoFill`, AGAIN
and FUSE ALL still skip mutated items). Players won't guess that, so with an
**empty chamber** and a group of 2+ orbs sharing one stack on the selected tab
(`largestMutatedGroup`, with or without plain orbs too) the Fuse panel shows
one muted line (`MutationTip`, last in the chamber column):
"Tip: put a GOLDEN orb in first, then AUTO-FILL fills GOLDEN." (the largest
group's top mutation). It is gone as soon as any orb is in the chamber, on a
rebirth-locked tab, and with only plain orbs. No change to AUTO-FILL, AGAIN or
FUSE ALL. The fusion
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
  **Stack clamp (desktop and phone):** every frame the card is up its top is held
  >= `TopStack.GetStableBottom()` (the objective bar + event chip rows, i.e. where
  the announcement line starts; x `PhoneScale` on a phone) + the air
  (`PlotLayout.Gacha.StackGapPx` / `PhoneTopGapPx`, 4 px) by sliding `SizeOffset.Y`
  below 0.5 (`GachaBoardController.StackShiftFor`, pure; `SizeOffset.X` is kept).
  **A toast never moves the card**: it uses the stable bottom, not `GetBottom()`
  (which includes the 2.5 s announcement line), and the toast draws over the card.
  **Phone:** `PhoneScaleFor` assumes you stand at the pad's centre at the default
  camera; standing off-centre moves the anchor on screen, so the phone clamps too.
  The phone clamp is **two-sided** (`PhonePlanFor`, pure, through `StackShiftFor`
  with its `floor` argument): the card's top is `clamp(natural top, minTop, floor
  - height)`, where the band's top is the chip row (`ceil(stable bottom) +
  PhoneTopGapPx`) and its bottom the **floor** (the weapon bar's top, else the HUD
  bottom row's top: `GetCardBottomFor`). So it slides up as well as down (a
  negative slide, a `SizeOffset.Y` above 0.5) and never leaves the band; only a
  card taller than the band lowers its `PhoneScale` (never below `PhoneScaleMin`),
  and at the minimum the top wins. Without `floor` `StackShiftFor` stays
  one-sided, which is what the desktop uses. The anchor and `StudsOffset` still
  never change; the card may leave its anchor, it stays clamped (the NIGHT chip
  once hid the first row of orbs on PC). `/selftest` measures the drawn top with
  no announcement and with one showing (equal within 1 px, once per probe), and
  on a phone stands the tester at the pad's centre and 3 studs off each side
  (the probe says how far from the anchor it started): top >= stable bottom + gap
  and bottom <= the floor, at 844 x 390 and 896 x 414. When the window is not
  that size the pure `PhonePlanFor` is asserted on the projected anchor (a
  projection says nothing about the live drawn card). A failing desktop line
  appends `GachaBoardController.GetClampTrace()` (what the last clamp frame used:
  stack bottom, minTop, anchor y, drawn height, shift, `SizeOffset.Y`, top), and
  the probe turns on `SetClampDebug` (a `[GachaCard]` print every 30 frames).
  **Phone variant** (`applyVariant`, `PlotLayout.Gacha.Phone*`): not the desktop
  card shrunk evenly. No mutation line (the (i) panel has it); the %, the pills,
  the (i) mark and the key captions are 25-26 px so they read >= 13 px at
  `PhoneScaleMin` (0.52); the (i) hit area is 88 px and each key's holder 88 wide
  (`PhoneButtonSpacingPx` 90), both >= 44 after the scale; the billboard is 300 ×
  `GachaBoardController.PhoneFullHeight` (50 + 184 + 99). `PhoneScaleFor` puts the
  card's top at `ceil(TopStack's chip row bottom) + PhoneTopGapPx` (56 px after the
  0.8) in whole px. A phone % label never shrinks for a long value
  (`PlanPercent`: full size, slid inward to stay on the card); the odds text is
  never rounded.
  Captions on a phone: Pull / ×10 / Auto (Auto ON). `/selftest` measures every
  text and the hit area at 844 × 390 and 896 × 414.
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

- **Goal steps ("own a tier" goals):** `own_rare` / `own_epic` /
  `own_legendary` / `own_mythic` (`GoalConfig` `Kind = "OwnTier", Tier`) say
  what to do NEXT instead of only pointing at the Fusion Machine. The pure
  rules are `Shared/Modules/GoalSteps.Compute` (goal tier G, input tier I =
  the one below it, same rules as FusionService: `CanFuseTierFor`,
  `GetFusionChance` with the event + Fusion Spark bonus, fuse max 6, orbs a
  thief carries don't count); `GoalService.ComputeStep` feeds it the player's
  inventory on every sync (the `OnSync` hook) and ships the result as
  `GoalProgress.Step`. The HUD tracker renders `GoalSteps.Format(step)` as a
  2nd line (the action) and a small 3rd line (the odds hint) under the goal
  text, and `GoalMarkerController` points at `Step.Target`:

  | Situation | 2nd line | Arrow |
  |---|---|---|
  | >= 2 of I | `Fuse your N Epics: 45%` (N = min(owned, 6)); 3rd line `More Epics = better odds (6 → 66%)` while N < 6 and chance < 100% | Fusion Machine |
  | < 2 of I, >= 2 of a lower tier (highest first) | `Fuse Rares to make Epics (1 / 2 Epic)` | Fusion Machine |
  | nothing to fuse, a pull is affordable (or a free pull is left) | `Pull from the Gacha for more orbs (1 / 2 Epic)` | Gacha Pad |
  | nothing to fuse, no pull affordable | `Earn cash for your next pull ($X)` | UPGRADES button (`ui:Upgrades` outline) |

  Goal texts say the verb (`Fuse Epics into a Legendary`); rewards are
  unchanged. Tier names are coloured by `UITheme.GetTierLight`, money goes
  through `NumberFormat.Money`. The tracker's card grows with the lines
  (`AutomaticSize`), on a phone they sit under the one-line pill (12 px).
- **Fuse panel odds line:** a chamber of 2-5 same-tier orbs with more of that
  tier in the inventory shows one muted line in the mutation-tip slot:
  `Add more Epics for better odds: 3 → 45%, 6 → 66%` (next count, and
  min(owned, 6) when that is further). Gone at 6 orbs, when nothing more of
  the tier is owned, and on a sure (pity-full) fusion. It wins over the
  mutation tip (the tip needs an empty chamber, so they never collide);
  AUTO-FILL is unchanged.
- `/selftest`: "goal steps" (server, stubbed inventories through
  `GoalService.ComputeStep`: Gacha / Fuse lower / Fuse N + hint / no hint at 6 /
  earn cash, one case for each other tier goal), "fuse odds line" (client
  probe `FuseOdds`), and "hud goal tracker shows 3 lines" (no clipping,
  on screen, 👣 toggle >= 44 px, at the desktop and phone layouts).

#### Loop coach (always one "do this now")

Pull -> Fuse -> Earn -> Upgrade (+ Steal on the side road) as ONE next step,
under every goal, after the tutorial. Rules and text are
`Shared/Config/LoopCoach.lua` (pure; `/selftest` and the HUD read it too);
`GoalService.BuildCoach` runs it on every sync (the `OnSync` hook) and
ships `GoalProgress.Coach = { Step, Target, <the numbers its line needs>,
Takes, Lit }` inside the `SyncTycoon` snapshot (no new remote;
`TycoonController.sanitizeCoach` validates it). Absent while
`TutorialService.IsActive`.

| Priority | Step | Doable when | 2nd line | Arrow |
|---|---|---|---|---|
| 1 | Fuse | a tier the player may fuse (`CanFuseTierFor`) has >= 2 orbs (highest tier, N = min(owned, 6)) | `Fuse your 3 Rares: 57%` | Fusion Machine |
| 2 | Pull | cash >= the next pull price | `Pull from the Gacha ($250)` | Gacha Pad |
| 3 | Upgrade | cash >= a generator / Multiplier level (`LoopCoach.PickUpgrade`: the most +$/s per $) | `Upgrade your Ember Forge: +$12/s` | that station (`Generator_<id>` / `MultiplierStation`) |
| 4 | Steal | a rival lab holds an orb and `HeistService.GetRivalStealsLeft` > 0 | `Steal a free orb from Dr. Fizz!` | `NearestRivalPedestal` (client picks the lab's best pedestal) |
| 5 | Earn | otherwise | `Your orbs earn $10/s: next pull in 0:42` (no income: `Earn cash for your next pull ($250)`) | none |

- **Hold (hysteresis):** `LoopCoach.Resolve` keeps the shown step for
  `HoldSeconds` (3) per player; a switch inside the window is refused while
  the held step is still doable, and a held step that is gone (the pair was
  fused, the cash was spent) is dropped at once. Cash ticking past a price
  can't flicker the arrow.
- **Who owns the 2nd line and the arrow (`Takes`):** the goal keeps its
  title. "Own a tier" goals keep GOAL_STEPS' lines (they are the Fuse /
  Pull rows above) until their step is `Earn`; any other goal hands over
  when `LoopCoach.GoalBlocked` says it can't be done now (no cash for the
  generator / Multiplier / pull / Rebirth it needs, nothing to fuse for
  `first_fusion`). `GoalMarkerController.PlanGoalArrow` is the one place
  that picks the arrow: coach (when `Takes`) > the goal's step > the goal's
  `Target`; a running tip (`SetTipActive`, TutorialController) takes the
  coach's arrow and gives it back when it ends. One arrow, ever.
- **Loop strip** (HudController, top of the goal card): `🎰 → 🔮 → 💰 →
  ⬆️` and `🏃` after a gap; `Lit` is the step to light (the coach's, or the
  goal's own while the goal points: `GoalConfig.Goals[i].Loop`, a tier
  goal's Fuse / Pull). Five cells >= 44 px wide and tall (the track is as
  wide as the card; the green chips are 22 / 18 px tall). The cells are the
  44 px tap rule, which five cells can't meet inside the old "+20 px" spec, so
  the card may grow by **at most 62 px on desktop / 40 px on the phone**
  (`STRIP_GROWTH` in GoalTracker; the card's vertical padding gives some
  back), tap =
  `AnnouncementController.ShowLine(LoopCoach.Explain[step])`. Shown after
  the tutorial only (a coach exists).
- **Loop-closing lines** (`LoopCoachController`, once per session per kind,
  never during the tutorial, through `AnnouncementController.ShowLine` =
  TopStack): a fusion that raised the pedestal income (`Your new orb earns
  $X/s more!`), the first affordable pull after being broke after a fuse
  (`More cash = more pulls = more fusions!`), the first delivered rival
  steal (`Free orb! Fuse it with yours.`).
- `/selftest`: "loop coach" (server, stubbed `LoopCoach.Input` through
  `GoalService.BuildCoach`: every step's line and target, the priority
  order, the 3 s hold, nothing during the tutorial, `Takes` / `Lit` per
  goal, `PickUpgrade`), "goal arrow" (client: coach / tip / goal step /
  goal target), "loop moments" (client planners), "hud loop strip" (client,
  both layouts: each step lights its own chip, 5 cells >= 44 px inside the
  card and clear of each other, the card grows <= 62 px desktop / 40 px phone); the strip is also
  in the left-column overlap and fit checks.

*Board bug fixed (Oct 13), kept for the lesson:* `buildTile` / `buildChip`
returned their frames but never parented them, so the first board drew only
its header and price pill. The selftest read the controller's own table and
passed anyway; every card / button check now reads the instance tree
(`gui:GetDescendants()`, `AbsoluteSize` > 0 on both axes, `Visible` up the
chain, `TextBounds.Y` > 0) and every FAIL carries its measurements in `Detail`.
