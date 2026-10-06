# Fusion Tycoon: first-time tutorial (build prompt for Claude Code)

`git pull` on `world-redesign` first. Commit per phase, push, open a PR →
`main`. Don't merge. This is **part 2 of 4**: run it after
`PLAYTEST_7_PROMPT.md`, which adds auto-display and the REBIRTH button
that this tutorial uses.

---

Read CLAUDE.md and follow it. Harris's playtest feedback: **"no clue how
to play, players don't understand the point, nothing tells them what to
do next."** The goal list (`GoalConfig`) and the goal arrow aren't
enough. Every new player gets a **mandatory, step-by-step tutorial** that
introduces each system one at a time. Each step has:
- an **OK** card;
- a **glowing path on the ground** to where they need to go;
- completion only when they actually **do** the thing.

## How a step works

1. **Card.** A small centred card (`UIKit.Modal`, `FitContent`, through
   the card-placement rule). It has:
   - a big icon;
   - a title;
   - **at most 2 short sentences**, written for a 9-year-old;
   - a green **OK** button (≥ 44 px).

   The game behind is dimmed while it's open. Nothing else pops up during
   the tutorial: shop side cards, deal pop-ups, the Daily card and tips
   all wait until it's done.
2. **Lit path.** After OK, a glowing path runs from the player's feet to
   the target.
   - Use a chain of `Beam`s with a scrolling chevron texture, laid along
     the walkway. Use `PathfindingService` waypoints, falling back to a
     straight line. Rebuild it every 0.3 s as the player moves.
   - Add a pulsing ring around the target, as a SurfaceGui face
     (`BillboardKit.BuildPadFace`). **No Highlights, no flat Neon
     circles** (CLAUDE.md).
   - Add the existing goal arrow.
   - When the action is a **UI button** (UPGRADES, INDEX, REBIRTH…), show
     a pulsing coach ring around that button. Other buttons stay usable.
3. **Done.** The step completes on the real, server-confirmed action,
   never just on arrival. Then:
   - a quick ✓ "Nice!" toast and the step sound;
   - the next card opens after 0.6 s.

## Steps

1. **Welcome** (card only): "Welcome to your Fusion Lab! Pull glowing
   orbs, fuse them into rarer ones, and get rich." (OK)
2. **Claim your lab:** path to the nearest FREE LAB. Done when the claim
   succeeds.
3. **Upgrade a generator:** "Generators make your cash. Upgrade the Basic
   Generator." Path to it. Done on the first upgrade, from either the
   world prompt or the UPGRADES panel.
4. **Pull an orb:** "Use the Gacha Pad to get orbs."
   - Grant **2 free tutorial pulls**, guaranteed **Common** and plain,
     through `TycoonService.GrantFreePulls`, so they don't raise the pad
     price.
   - Path to the pad. Done after both pulls.
5. **Pedestals** (card + path to the pedestals): "Your best orbs go on
   display by themselves and make money every second." Point at the $/s
   on the cash card. Done on OK.
6. **Fuse:** "Put 2 orbs of the same tier in the Fusion Machine to make a
   better one."
   - Path to the machine. When the Fuse panel opens, coach-mark:
     AUTO-FILL (or the 2 Commons), then the odds chip, then **FUSE**.
   - The **first tutorial fusion always succeeds**: a once-per-account
     server flag, `PlayerData.Tutorial.FreeFuse`.
   - Done when the Rare is made, which shows the big card and then
     auto-displays it.
7. **Index** (coach-mark INDEX): "Every new orb and mutation fills your
   Index and boosts your income forever." Done when the Index opens.
8. **Multiplier Pad:** "This multiplies ALL your money." Path to the pad.
   - If they can afford level 1, done on the purchase.
   - If not, done on OK with "Come back when you have $X".
9. **Events** (card, point at the top event chip): "Every 15 minutes the
   lab weather changes: Golden Rain, Meteors, Void Moon… Tap the chip to
   see what to do." Done on OK.
10. **Free gifts** (coach-mark GIFTS): "Play to unlock free gifts." Done
    on OK. **No shop step and no shop mention.** The tutorial never sells
    anything.
11. **LOCK and stealing:** path to the LOCK console. "At Rebirth 1 other
    players can steal your displayed orbs, and you can steal theirs. LOCK
    your lab to keep thieves out for 60 s."
    - Rebirth 0 players are protected, so this is done on OK at the
      console.
    - Then a second card: "Hold E on an enemy pedestal to grab an orb,
      run it home. Catch thieves by touching them."
12. **Rebirth** (coach-mark the REBIRTH button): "Get to $15M and Rebirth.
    You keep your orbs, and every rebirth makes you earn faster and
    unlocks new things." Done when the Rebirth panel opens.
13. **Finish** card: "You're ready! Your goal is on the top left. Follow
    the glowing path anytime." Done on OK.

After the tutorial, the normal **GoalConfig** goals carry on, and the
**lit path now follows the current goal too**. The goal card has a 👣
toggle to hide the path, which is on by default for the first 2 sessions.

## Saves, replays and help

- **Saves.** `PlayerData.Tutorial = { Step, Done, FreeFuse }`, sanitised
  in `reconcile` and sent in the snapshot.
  - The step is saved as it completes, so a player who leaves mid-way
    resumes at that step.
  - Steps already satisfied are skipped (for example, a lab already
    claimed).
- **Old saves.**
  - With real progress (Rebirth ≥ 1, or more than 20 pulls): set
    `Done = true`, plus a one-time toast "New: replay the tutorial in ⚙
    Settings".
  - Without that progress: they get it.
- **Remote.** `TutorialAdvance` (C→S `{ Step }`) is only for card-only
  steps. The server re-checks that the step matches and that it is a
  card-only step. Action steps are completed by the server from the real
  events. Add it to `RemoteEvents` with its direction.
- **"?" help buttons.** A round **?** (44 px) in the header of:
  - the Fuse panel;
  - Upgrades;
  - Index;
  - Rebirth;
  - the LOCK console label's prompt card;
  - the Gacha Pad (a small "?" pill on its billboard that opens the
    card).

  Each one re-opens that topic's tutorial card(s) as a mini slideshow
  (◀ ▶, OK).

  **The Fuse ? must explain:**
  - same tier only;
  - 2–6 orbs, where more orbs means better odds;
  - a fail keeps your best orb;
  - matching mutations are kept;
  - Mythic → Secret needs Rebirth 1.
- **Settings:** a "Replay tutorial" button.
- **Studio:** `/tutorial reset` and `/tutorial step <n>`.
- **Analytics.** `AnalyticsKit.Custom("TutorialStep", n)` on each step,
  and `"TutorialDone"` at the end, so Harris can see where players drop.

## Phone

Cards fit and stay above the bottom bar. Coach rings wrap the phone-sized
buttons. The path is visible from the phone camera height. Check it on
the iPhone emulator.

## Check

- **`/selftest`:**
  - drive a fresh mock profile through every step with the real remotes
    and the guaranteed pulls and fusion;
  - every step completes in order;
  - no shop or deal pop-up appears while `Done == false`;
  - a resumed save starts at its saved step.
- `luau-lsp analyze` reports no new errors.
- **UI_TEST:** "Tutorial" section: a new player at 1920×1080 and on the
  phone, leave mid-way and rejoin, replay from Settings, every ? button.
- **CLAUDE.md:** a Tutorial entry (steps, data, remote, guards).
- **Report:** the step list as built, anything simplified, and the copy
  of every card so Harris can read it.
