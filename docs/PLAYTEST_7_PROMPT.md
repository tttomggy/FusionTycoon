# Fusion Tycoon: Playtest 7 fixes (build prompt for Claude Code)

`git pull` on `world-redesign` first. Commit per numbered item, push, open
a PR → `main`. Don't merge. This is **part 1 of 4**. The others are
`TUTORIAL_PROMPT.md`, `COMBAT_PROMPT.md` and `PROGRESSION_PROMPT.md`.
Run them in that order.

---

Read CLAUDE.md and follow it. Harris played the live game on Oct 6.
Players don't know what to do, a bad bug moves things into the street, and
he wants heists to be faster and easier to read.

## 1. BUG: holograms and orbs jump to the middle of the street

The Gacha Pad hologram orb, pedestal orbs, the light on top of the
Multiplier Pad and other `FT_Hover` / `FT_Orbit` things sometimes appear
floating in the **middle of the street**, which is about world (0, y, 0).
Harris has a screenshot of a gacha hologram orb hovering on the street
next to the speed belt.

**Likely cause.** `WorldAnimationController` captures each target's
resting CFrame "when it's first seen" and animates relative to it from
then on. If it sees a part before the server has moved it to its slot,
the cached base is wrong and the part gets driven back there every frame.
Ways that can happen:
- the part is created at the origin and then pivoted;
- it streams in (StreamingEnabled) at an early position;
- the plot is rebuilt or moved by claim, rebirth or a player leaving.

**Fix it properly.** Never trust a first-seen cache. Store the resting
pose relative to its plot (for example a `HoverBase` attribute, a CFrame
in plot-local space set by the server), or re-capture it whenever the
server moves the part. Drop targets that leave and re-enter streaming,
and re-read them.

**Reproduce before fixing.** Try each of these:
- join, then claim;
- rebirth;
- reset your character;
- walk far away and back (streaming);
- a second player joins or leaves;
- `/event` changes.

Report which one triggers it.

**`/selftest`:** after 10 s, every `FT_Hover` / `FT_Orbit` target sits
inside its own plot's bounds (`PlotLayout.IsInsidePlot`), or on its
street spot for street objects. Run the check again after a forced plot
rebuild.

## 2. How to Heist: sentences cut off

On other players' screens, some lines in `HowToHeistPanel` are cut off.
- Every text label in that panel must wrap, and must not truncate, at
  1920×1080, 1366×768, 1280×720 and the phone size.
- Use `TextWrapped`, `AutomaticSize` Y, or a `TextScaled` with a min/max
  size, and grow the slide if needed.
- **`/selftest`:** every TextLabel in every panel reports `TextFits`
  after the panel builds, at both scales. List any that don't.

## 3. A REBIRTH button that's always there

Add a purple **REBIRTH** button to the bottom bar (UPGRADES · ITEMS ·
INDEX · **REBIRTH** · ⚙).

- It always shows, with a progress fill of cash against the next rebirth
  cost and the text "$2.1M / $15M".
- When the player can afford it, it glows and pulses.
- Tapping it opens `RebirthPanel` from anywhere. The panel shows what you
  keep, what you get (income and luck, plus unlocks such as stealing,
  combat and the 2nd floor) and either "Need $12.9M more" or the REBIRTH
  button.
- The Portal stays too.
- Phone: it must fit the bar (shrink the buttons evenly, keep taps ≥ 44 px).

## 4. Heist tuning

- `ThiefCooldownSeconds` 60 → **0**. Remove the "Steal in 42s" prompt mode
  and the cooldown toast.
- Keep a **request** rate limit on `RequestSteal` (`RemoteGuard.Allow`,
  about 1 per second) so exploits can't spam it. That isn't a gameplay
  cooldown.
- `VictimShieldSeconds` 120 → **60**. Every shield is now 60 s at most:
  claim, LOCK and after a loss.
- Keep the 3-losses-per-10-min cap. It's what stops someone being
  farmed now that there's no cooldown.

## 5. Make LOCK obvious to everyone

- **Barrier:** the shield fence must be impossible to miss.
  - Full wall height, a brighter `World.Shield` colour, and a glowing top
    edge.
  - A pulsing pink lock icon over the gate.
  - It fades in over 0.3 s when the lock starts and flashes when it's
    about to drop (last 5 s).
- **Timer for everyone:** a big billboard over every lab's gate that all
  players see (MaxDistance ~150), in one of three states:
  - "🛡 LOCKED · 0:42" (pink)
  - "🔓 OPEN" (red-ish, a thief's invitation)
  - "🔓 OPEN · can re-lock in 12s"

  A thief can then wait outside for the lock to drop.
- An enemy pedestal's prompt in a locked lab reads "Locked · 0:42".
- These labels come from `ShieldState`, so the client counts down from
  `ShieldUntil` with no extra remotes.
- Rebirth-0 labs show "🛡 PROTECTED".

## 6. Pedestals show your best orbs automatically

Players never choose. The pedestals always show the player's best items,
**highest $/s first** (`TycoonConfig.GetItemCashPerSecond`), filling
spots 1 → 4 (→ 6 with the pass).

- **Re-arrange on every change:** pull, fusion, Fuse All / Auto-Fuse,
  delivery, theft, event mutation, rebirth, reward item, `/give`. The
  re-arrange is one server function in ItemService, and it runs inside
  the sync.
- **During a theft:** a carried item stays on its pedestal marked
  `BeingStolen` until the heist ends. Don't re-arrange that pedestal while
  it's carried. On delivery, refill it.
- **Remove** the pedestal place / remove prompts and the pedestal picker.
  ITEMS stays as the inventory view, with "ON DISPLAY" tags.
- The `FirstDisplay` funnel step and the display goal fire on the first
  automatic display.
- Update the goals copy ("Put an orb on a pedestal" goes, or becomes
  automatic).
- **`/selftest`:**
  - after `/give` of 6 random items, the pedestals hold the top 4 by $/s
    in order;
  - after a fusion that makes a better item, it is on pedestal 1 in the
    same sync.

## Check

- `luau-lsp analyze` reports no new errors.
- `/selftest` passes three runs in a row.
- UI_TEST gets lines for each item above.
- CLAUDE.md is updated for: Heist (cooldown 0, 60 s shields, the gate
  billboard), the REBIRTH button, auto-display, and the hover fix.

**Report:**
- the cause of item 1 and which repro triggered it;
- the before and after for each heist number.
