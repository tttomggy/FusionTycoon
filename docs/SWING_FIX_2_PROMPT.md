# Swing fix 2: weapon switch, a swing you can see, the fuse card, selftest wiring (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 10 lines or fewer.

---

Harris tested `f6b49cc` on Oct 13 (his monkey avatar, `/weapons all`,
3rd person). From his clip and `/selftest`:

- **Bat:** C0 works. The bat is held raised and the arm moves, but the
  swing is a quick flick you barely see.
- **Laser Gun → Freeze Ray → Slap Glove, switched slot to slot:** the Freeze
  Ray and the Slap Glove hang **straight down** (the glove points at the
  floor). No hold pose, and no slap (no trail either).
- **`/selftest`:** no `combat Bat / SlapGlove …` lines at all, even after
  `/weapons all` and `/rebirths 3`.
- **EventInfoCard centring got worse:** desktop 386 vs 389 (3 px), phone
  475 vs 499 (24 px; it was 2 px). Night was running.

Do these in order. Item 1 first, because it is why every arm check so far
proved nothing.

## 1. `/selftest`: make the probes actually run

**Likely cause** (confirm it): `DebugService.runSelfTest` sets
`selfTestReports[player.UserId] = nil` right after step 7 (around line
665). Steps 9 (tutorial) and 10 (combat) then call `tutorialProbe`. But
`SelfTestReport.OnServerEvent` drops every report when the queue is nil,
so each probe waits the full `SELFTEST_REPORT_TIMEOUT` (90 s). The tutorial
section alone is then 10+ minutes of timeouts before combat starts. Harris
copied the output long before that.

- Keep the queue until the very end of `runSelfTest`, and clear it on every
  return path. The fix must also work if the code errors partway: wrap
  each section in `pcall` and print a FAIL with the error.
- Give each probe its own timeout of 10 s. A missing report is a FAIL
  named after its probe, e.g. `combat SlapGlove: no report from the client`.
- Print a section header before each section (`[SelfTest] == 10. combat ==`)
  so a missing section is obvious. The `done: N passed, M failed` line must
  always print.
- **`/selftest combat`** runs only the combat section, and
  **`/selftest cards`** runs only the card-placement checks. Harris will use
  these to iterate. Add them to `docs/systems/studio-commands.md`.
- Combat probe:
  - Sample the **rest hand** explicitly: `UnequipTools`, wait 0.3 s, then
    sample. Don't rely on the Heartbeat sampler.
  - The probe may only say "skipped: not an R15 rig" when `RightHand` or
    `UpperTorso` really is missing. Otherwise a missing rest sample is a
    FAIL.
- Tell Harris in your reply that the tutorial probe lines may show **new
  FAILs**, because they have probably never reported before either.

## 2. Weapon switch wipes the new pose (the glove and Freeze Ray bug)

`CombatController.onToolRemoved` calls `WeaponPose.Release(character)`, and
that release doesn't care which weapon it was. When Harris switches slot to
slot, Roblox fires the new tool's `ChildAdded` **before** the old tool's
`ChildRemoved`, so the old tool's release wipes the new weapon's pose.
Before fixing, log the event order once in Studio to confirm it. Put the
finding in `docs/systems/combat.md`.

- Change it to `Release(character, weaponId)`. Do nothing if the held state
  is a different weapon.
- After any release, if a weapon `Tool` is still parented to the character,
  `Hold` it. This makes the pose correct whatever order the events fire in.
- **Selftest:** add switch probes that don't call `UnequipTools` in between:
  Bat → SlapGlove, LaserGun → FreezeRay, SlapGlove → Bat. Each one measures
  that the new weapon's hand is held (the same rendered-hand check as the
  normal probe). **They must FAIL on today's code.** Run them before the
  fix and quote the numbers. The current probe destroys each tool before
  equipping the next, which is why it can't catch this.

## 3. A swing you can read from 3rd person

The Bat's swing is 0.35 s in total, with a 0.1 s wind-up (3 frames at
30 fps), and only the shoulder moves. Make the whole body sell it:

- **Bat:**
  - Wind-up: 0.18 s, the bat cocked back over the right shoulder.
  - Hold at the top for 0.06 s.
  - Arc: 0.14 s, a big sweep down and across to the left.
  - Follow-through past the left hip: 0.1 s.
  - Settle: 0.2 s.
  - About 0.7 s in total. The cooldown is 1.2 s, so that fits.
- **Slap Glove:** a wide, flat slap at shoulder height with the same
  wind / hold / arc / settle shape.
- **Waist twist:** pose the `Waist` Motor6D (`UpperTorso`) as well.
  - Twist about 0.5 rad to the right on the wind-up and about 0.6 rad to the
    left through the arc.
  - Use the same `BaseC0` rules as the shoulder: store on Hold, never build
    from the live C0, restore and clear on Release. On an AJU rig, use the
    `AnimationConstraint` path.
- **Elbow:** bend `RightElbow` about 0.6 rad on the wind-up and snap it
  straight at impact, with the same base rules.
- **Selftest:**
  - Replace the "travelled ≥ 2 studs" path-length check, which jitter can
    pass. Instead, the hand's **peak distance from its held position**
    during the swing must be ≥ 2.5 studs for both the Bat and the Glove.
  - The swing must also stay visible for ≥ 0.5 s.
  - After release, `Waist` and `RightElbow` are back at base, with no
    attribute left behind.
- Check by eye on Harris's monkey and on a blocky R15. Plan B
  (KeyframeSequences) stays parked: C0 works, so this is shape and timing,
  not the API.

## 4. Every single fuse gets the big card

Harris wants the same big pop-up a single pull gets (see the BEST OF 10
"EPIC!" card) after **every successful single fusion**, at every tier,
showing what he got.

- In `ResultController.onFusionResolved`, for a success that isn't an event
  mutation:
  - **Always** show `showBigCard`, whatever the reveal rule says.
  - Caption: `FUSION SUCCESS`.
  - Headline: `<TIER> ORB!`.
  - Keep the kept / rolled source line.
  - Description: `2x Common → Rare · earns $X/s on a pedestal`.
  - Auto-close Rare after `SINGLE_PULL_AUTO_CLOSE_SECONDS`, like a single
    pull.
  - The event-mutation card path stays as it is.
- `FusionBannerShows` returns false for single fusions, so there's no
  banner as well as the card. The skipped line goes too.
- The fail card is unchanged.
- **Fuse All and Auto-Fuse** keep the reveal rule. Update the ⚙ note in
  `SettingsPanel` (line ~398) and the `ResultController.ShowsBigCardFor`
  comment so they say the rule covers BEST OF 10 and Auto-Fuse only.
- **Tutorial `fuse` step:** the card now opens after the tutorial fusion.
  - Make sure the step flow waits for it the same way it waits for the
    pull step's "COMMON ORB!" card: no stuck step and no hand pointing
    under the card.
  - Add a `BigCard` probe after the fuse step in `runTutorialSelfTest`, with
    the headline of whatever tier the tutorial fusion gives.
- **Selftest (client):**
  - Feed `onFusionResolved` a fake Common×2 → Rare success. Check that the
    big card opens with "RARE ORB!" and that `FusionBannerShows` is false.
  - Then feed it a Fuse All result. Check that it still follows the reveal
    rule.
- Update `docs/systems/items-and-fusion.md` (reveal settings).

## 5. EventInfoCard centring: stop measuring through its own scale

**Likely cause:**
- `place()` computes height as
  `AbsoluteSize.Y / EffectiveScale(frame)`, and `EffectiveScale` includes
  the card's own PopScale.
- `FitHeight` then changes that PopScale, and `AbsoluteSize` catches up one
  frame later.
- The `AbsoluteSize` handler therefore reads a stale size against the new
  scale, re-places with the wrong height, and stores it in `lastHeight`.
- On a phone the card fills the band, so a wrong fit leaves it short and
  off-centre: 24 px.
- `/selftest` also measures 0.4 s after `Show`. That is barely after the
  0.3 s settle pass, so it's a race.

Log height, PopScale and AbsoluteSize for the first 10 frames after `Show`
on phone, put them in your reply, then fix it:

- Add one settle loop in UIKit: `UIKit.SettleCard(holder, place)`.
  - After any change (Show, content rebuild, `LayoutChanged`, an
    `AbsoluteSize` change), run `place()` once per Heartbeat.
  - **Skip** any frame where the PopScale changed since the previous
    frame, because the size is stale then.
  - Stop after two frames in a row agree within 0.5 px and the drawn centre
    is within 1 px of the plan, or after 30 frames (warn if it gets there).
  - The `AbsoluteSize` handler only kicks this loop. It never places
    directly.
- While the loop runs, set the attribute `Settling = true` on the holder.
  `/selftest`'s `measurePlacedCards` waits for `Settling` to be false (up to
  1 s) instead of using fixed waits.
- Use it for the EventInfoCard and for `FitHeight` result cards.
- Test with the **running** event (Night) as well as GoldenRain, with the
  tutorial OK row on and off.
- The tolerance stays 2 px.

## Check

- `luau-lsp analyze` shows no new errors.
- `/selftest`:
  - the section headers and the `done` line print;
  - every `combat …` line appears (normal and switch probes);
  - the switch probes and the 2.5-stud peak check failed before the fix
    (quote both);
  - no FAILs after the fix.
- `/selftest cards` passes on desktop and phone.
- Give Harris this list to look at in Studio, in 3rd person:
  - `/weapons all`, then switch slot to slot Bat → Laser → Freeze →
    Glove → Banana: every weapon is held up, none hangs.
  - 3 Bat swings and 3 slaps: you can see the twist and the follow-through.
  - Fuse 2 Commons: the big "RARE ORB!" card appears.
- Update `docs/systems/combat.md`, `items-and-fusion.md`,
  `studio-commands.md` and UI_TEST.
- Say which branch you pushed to.
