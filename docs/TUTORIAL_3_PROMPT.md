# Tutorial 3 + top-of-screen cleanup (build prompt for Claude Code)

`git pull` on `world-redesign`, then commit per part and push to
`world-redesign`. Reply in 10 lines or fewer.

---

Harris played Tutorial 2 with arrows (Oct 7, 3 clips). The path is good
now. Fix the rest.

## Part A: Tutorial

1. **The hand points at the wrong place. It's always too high.**
   - In the Fuse panel it sits on the "2 orbs 55%" chip instead of
     AUTO-FILL.
   - On the REBIRTH step it floats up by the "Goal complete!" toast.
   - It's about 50–60 px too high everywhere, the same top-bar inset bug
     as `/selftest`'s live card check: `AbsolutePosition` is measured below
     the Roblox top bar, but the hand's gui uses `IgnoreGuiInset`.
   - **Fix:** add `GuiService:GetGuiInset()` Y, convert to the hand gui's
     logical px (its `UIScale`), and track the target every frame so it
     follows panel pop-ins and scrolling.
   - **Hide** the hand when its target isn't visible on screen.
   - **`/selftest`:** for each hand step, the hand's tip lies inside the
     target button's rect.
2. **One arrow size.** The path has small arrows, plus 3 big chevrons at
   the target. Remove the big chevrons and keep only the small arrows
   right up to the target. The bouncing goal arrow over the target stays.
3. **Bring back explain cards, then the banner.** Harris: "some
   instructions are confusing, add back press OK and explain what each
   thing does."
   - Every step that introduces something new opens a **big, simple card
     first**, then the banner, path and hand take over:
     - a large icon;
     - a title;
     - **one or two short sentences saying what the thing is for**, at
       ≥ 22 px text;
     - a big green **OK**.
   - Never before the claim. The claim step stays banner-only, then the
     welcome splash.
   - Card copy (keep it this short):

     | Step | Card |
     |---|---|
     | Upgrade | "⚡ **Generators** make your money. Upgrading them makes more." |
     | Pull | "🎰 **The Gacha Pad** gives you orbs. Rarer orbs earn way more!" |
     | Pedestals | "🏛 **Pedestals** show your best orbs. Every orb on display earns cash every second." (OK ends this step) |
     | Fuse | "🔮 **Fusing** turns 2 orbs of the same tier into 1 better orb. Common + Common → Rare!" |
     | Index | "📖 **The Index** collects every orb you find. Each new one boosts your income forever." (show it right after INDEX pops in; OK ends it) |
     | Multiplier | "✖️ **The Multiplier Pad** multiplies ALL your money." |
     | Weather | "🌦 **Lab weather** changes every 15 min. Each one gives a bonus. Tap the top chip to see it." |
     | Rebirth | "♻️ **Rebirth** at $15M: you keep your orbs and earn faster forever." |

   - Each card has an **image of the real thing** where possible: a
     ViewportFrame with the real generator / pad / orb / machine model, or
     `UIKit.TierOrb`. Use an icon only when there's no model.
   - Don't stack cards: one card, then the action, then the next card.
4. **A banner everyone sees.** Today it's small text that collides with
   "Goal complete!", "LAB WEATHER", the welcome splash and "FUSION
   SUCCESS!". Make it the **objective bar**:
   - a solid dark panel with a lime border, top centre, just under the
     Roblox top bar, **width 520–640 px**;
   - a 48 px step icon on the left;
   - the instruction in **36 px** white display text, with the distance as
     a lime pill on the right ("24m");
   - a small step counter "3 / 10" under it;
   - it gently pulses when it changes.

   It **owns the top-centre slot** while the tutorial runs (see Part B).
   Phone: full width minus 16 px margins, 28 px text, still above
   everything.

## Part B: One queue for the top of the screen

Several things draw in the same top-centre spot and overlap:
- the objective banner;
- "Goal complete! +$50";
- the event start banner and the event chip;
- "FUSION SUCCESS!" / server banners;
- "WELCOME TO YOUR LAB!";
- quest and power-up toasts.

1. **One `TopStack` manager** (client) with fixed slots, top to bottom:
   1. **objective bar** (tutorial, else hidden);
   2. **event chip**;
   3. **one announcement line**: banners and toasts **queued**, one at a
      time (2.5 s each, the queue capped at 4, oldest dropped). A
      higher-priority item (your own big success, an event start) goes to
      the front.

   Everything that draws at the top goes through it. No other code places
   anything at top centre.
2. **The welcome splash** waits for the queue, so it never overlaps the
   banner.
3. **Left column:** the NEXT GOAL card, the quest tracker and
   SHOP / GIFTS / QUESTS / deal / power-ups must never overlap, at
   1920×1080, 1366×768 and the phone size. Stack them with a layout, not
   fixed offsets. Add a `/selftest` overlap check of the left column's
   rects.

## Part C: Polish (from the same playtest)

- **World label clutter.** Pedestal item labels ("Spark Cell +$7.6/s"),
  the big "⊕ EMPTY" labels and conveyor orb labels pile up across the lab.
  - Item labels: MaxDistance 45, and they shrink with distance (a scale
    cap, not `SizeByDistance` pixel jumps).
  - "EMPTY" labels: only for the owner, within 25 studs, half their
    current size.
  - Factory balls: no text at all.
  - The VIP head tag sits 1.5 studs higher, clear of the "[E]" prompts.
- **Fuse panel.**
  - 12 px gap between the odds chips and the AUTO-FILL / CLEAR / FUSE row.
  - AUTO-FILL with nothing to fill: the button greys out, and a tap gives
    a small shake and a "Nothing to fill" toast.
- **Single-pull Common / Rare card:** fade in over 0.15 s. It must
  **not block movement** (no modal input sink), so the player can walk
  while it shows. It closes after 2 s or on a tap.
- **Daily card:** the reward tiles get equal padding, and their text is
  vertically centred.
- **Rebirth panel:** the "Need $X more" line is ≥ 20 px bold.

## Check

- `luau-lsp analyze` shows no new errors.
- `/selftest` passes the new hand, top-stack and left-column checks.
- UI_TEST gets a "Tutorial 3" section.
- Update `docs/systems/tutorial.md` and add a TopStack line to
  CLAUDE.md's UI rules ("only TopStack draws at top centre").
