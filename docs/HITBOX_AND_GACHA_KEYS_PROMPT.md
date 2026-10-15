# Server hitbox (end-to-end tested) + Gacha card size and E / R / T keys (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 10 lines or fewer.

---

Harris tested `600635f` on Oct 15 with 2 players, both monkey avatars at
Rebirth 3 from the Studio start, standing side by side on the street.

- **The launch works:**
  - `/selftest combat` passes the Bat (≥ 12 studs) and the Glove (≥ 20),
    **measured on Player2's own client**, and the get-up passes too.
  - That test calls `CombatService.ApplyHit` directly, so the mover is
    proven.
- **In real play, nothing reaches it:**
  - Player1 swings the Bat and the Glove at Player2, point-blank, many
    times. The trails play.
  - No BONK, no 🛡 pop, no "Refused" toast, and Player2 never moves.
  - So the **hit is lost before `ApplyHit`**, silently, somewhere in this
    chain: the client's `meleeTarget` pick, then `TargetUserId`, then the
    server's range and angle checks (those return with no message).
- The "real swing → real hit" path has **never been tested end to end**.
  Every selftest skips it.

Harris asked whether redesigning the mechanic would fix it. Yes: move hit
detection to the server, the way most Roblox combat games do it.

## 1. Server-side hitbox, with a verdict line for every swing

**Client:**
- Sends only `RequestHit { Weapon }` for melee, with no `TargetUserId`.
- Delete `meleeTarget`.
- Keep the swing animation, trail and sound on click, as now.

**Server:**
- After the usual checks (cooldown, `whyCantSwing`), wait
  `CombatConfig.MeleeHitDelay` (0.15 s, about the clip's `Hit` marker).
- Then run `Workspace:GetPartBoundsInBox` on a box in front of the
  attacker's root:
  - `CombatConfig.MeleeBox = Vector3.new(6, 6, 7)`, centred 3.5 studs
    forward;
  - `OverlapParams` excluding the attacker's character.
- Collect the distinct characters, map each to a player, and take the
  nearest one that `WhyNotHittable` allows. It gets `ApplyHit`.
- Every candidate the box found but couldn't hit gets the attacker-only 🛡
  pop with its reason.
- The Glove can hit **every** valid player in the box (a slap sweep).
  The Bat hits the nearest only.

**Studio log, one line per swing:**

```
[Combat] Player1 Bat: box found [Player2 3.2 studs] -> HIT Player2
[Combat] Player1 Bat: box found [] -> MISS
[Combat] Player1 Bat: box found [Player2] -> Player2 Immune
```

- Print it while `RunService:IsStudio()`, until Harris says the combat
  feel is final.
- `/combat box` toggles drawing the box: a red transparent part, for
  0.2 s, on every swing. Studio only.

Ranged and Peel stay as they are.

## 2. The end-to-end selftest that was missing

Add to `/selftest combat` (2 players):

1. **Set up:**
   - Teleport Player2 to 3 studs in front of Player1, both facing each
     other.
   - Clear immunity and spawn-protect.
   - Equip the Bat on Player1 **through the real tool**.
2. **Swing for real:** tell **Player1's client** to activate the Bat
   through `CombatController`, the same function a click calls. Don't call
   `ApplyHit` from the test.
3. **Measure on Player2's client,** as the launch probe already does. The
   server log line for that swing must say `HIT Player2`.
4. **Repeat with the Glove.**
5. **Repeat with Player2 5 studs to Player1's side, out of the box:** the
   line says `MISS`, and Player2 doesn't move.

**This must FAIL on today's code.** Run it before your change and quote
it.

**The 3 FAILs from this run:**
- `held weapon clear 0.86`, `peak 1.15`, `peak 1.33` on the small monkey
  avatar.
- Scale those thresholds by the character's height: needs = (current
  needs) × (height / 5.0), clamped to 0.6–1.0. **Don't change the clips.**

## 3. Gacha card: smaller, and keys that actually show

**Size:**
- In Harris's clip the card covers the top half of the screen.
- Make it 7 × 4.8 studs.
- Keep it **at most 38% of the viewport height**: each frame, compute its
  on-screen height from the camera distance and clamp it with a `UIScale`.
  That's on top of the pop scale.
- Shift it 2 studs back, away from the walkway, with
  `StudsOffsetWorldSpace`, so it never sits over your character.

**Buttons:**
- They never appeared. The selftest says `PromptShown for []`, so the card
  must not depend on `ProximityPrompt` UI at all.
- While the card is open, show **one key bar** under it:
  - **[E] Pull · $285**
  - **[R] ×10 · $3.5K**
  - **[T] Auto · OFF / ON**
  - Desktop shows the keycaps, a controller shows the glyphs (X / Y /
    RB), and touch shows round tap buttons ≥ 44 px.
- Bind E, R and T with `ContextActionService` **only while the card is
  open**. Unbind when it pops out.
- Add remotes `RequestGachaPull { Count = 1 | 10 }` and
  `SetAutoPull { On }`, in `REMOTE_EVENT_NAMES` with comments.
  - The server validates: data loaded, the pad is the player's own, the
    root is within `PromptDistance + 3` studs of it, not Carrying,
    rate-limited with `RemoteGuard.Allow`.
  - Then it runs the **same function** the prompts' `Triggered` handlers
    call (factor it out). Never a second copy of the pull code.
- Disable the old Pull / Pull ×10 / Help `ProximityPrompt`s. "How it
  works" moves to the card's (i) panel, as a first section.
- The tutorial's big green PULL button still works through the same
  shared function.

**Auto pull (T), new and free:**
- Server-side. While it's on, the server pulls one single pull every
  `GachaConfig.AutoPullSeconds` (1.2 s).
- It stops by itself when:
  - you can't afford it;
  - you walk more than `PromptDistance + 3` studs from the pad;
  - you start carrying, die or leave;
  - you press T again.
- Each auto pull follows the **reveal rule**, like Auto-Fuse: no big card
  for every Common, only the small skipped line.
- The card's T button shows ON in green while it runs. A toast says why
  it stopped, e.g. "Auto pull stopped: need $285".
- Not sold, no pass. It's a convenience every player gets. Put it in the
  monetization doc's "earned, never sold" list.

**Selftest (`/selftest gacha`):**
- Standing on the pad with the card open:
  - the key bar shows 3 buttons, each ≥ 44 px, read from the tree;
  - E, R and T are bound (`ContextActionService:GetAllBoundActionInfo`).
- 25 studs away, they're unbound.
- `RequestGachaPull` from 25 studs is refused.
- Auto pull at $0 stops at once, with the reason.
- The card's on-screen height is ≤ 38% at 1366 × 768 and 844 × 390.

## Check

- `luau-lsp analyze` shows no new errors.
- **`/selftest combat` (2 players):** the new end-to-end checks failed
  before (quote) and pass after. No FAILs.
- **`/selftest gacha`:** no FAILs.
- Give Harris this list:
  1. With 2 players, swing at Player2: Player2 flies, and the Output shows
     `HIT Player2`. If not, paste that line; it says why.
  2. Walk to the pad: a smaller card with **[E] Pull · [R] ×10 · [T]
     Auto** under it. Press each one. T keeps pulling until you press T,
     walk away or run out of cash.
- Update `docs/systems/combat.md`, `items-and-fusion.md`,
  `architecture.md` (remotes), `monetization.md` and UI_TEST.
- Say which branch you pushed to.
