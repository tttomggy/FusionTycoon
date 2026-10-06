# Fusion Tycoon: weapons and ragdoll (build prompt for Claude Code)

`git pull` on `world-redesign` first. Commit per phase, push, open a PR →
`main`. Don't merge. This is **part 3 of 4**: run it after the tutorial.

---

Read CLAUDE.md and follow it. Harris wants **weapons: hit another player
and they ragdoll and get knocked away.** It's the missing half of the
heist: you can now fight a thief off, or knock an owner away from their
pedestal.

## Rules (kid audience: cartoon bonks, never damage)

- **No health, no damage, no deaths.**
  - A hit **ragdolls** the target for `RagdollSeconds` (1.5) with a
    knockback impulse, then they stand back up.
  - They are immune for `GetUpImmuneSeconds` (3) after standing up, shown
    as a faint shimmer.
- **Who can fight:** only **Rebirth 1+ vs Rebirth 1+**, the same gate as
  stealing.
  - Rebirth-0 players can't be hit and can't hit anyone.
  - Their weapons are greyed out with "Unlocks at Rebirth 1".
- **No hits for `SpawnProtectSeconds` (5)** after a player spawns.
- **Hitting a carrying thief makes them drop the orb.** It goes straight
  back to its pedestal, through HeistService's normal "it goes back" path,
  with a SAVED banner for the owner. This is the main use of weapons.
- A thief can knock an owner out of `OwnerBlockRadius`. The guard check
  happens when the hold completes, so a well-timed bonk opens the steal.
- **Not sold for Robux, ever.** CLAUDE.md's monetization "never" list
  rules this out: nothing sold helps a thief or protects a lab.
  - Weapons are **earned**: Rebirth milestones, plus quests in part 4.
  - Cosmetic skins could be sold later, but not in this prompt.

## Weapons (all numbers in a new `CombatConfig`)

| Weapon | Unlock | Use |
|---|---|---|
| 🏏 **Bat** | Rebirth 1 (free) | melee, range 7 studs, 1.2 s cooldown, knockback 60 |
| 🔫 **Laser Gun** | Rebirth 2 | ranged hitscan 60 studs, 3 s cooldown, knockback 35, a neon beam (thin cylinder seen from the side, not a flat Neon circle) |
| 🥶 **Freeze Ray** | Rebirth 3 | ranged 40 studs, 6 s cooldown, no ragdoll: the target moves at 40% speed for 3 s and turns icy blue |
| 🖐 **Slap Glove** | Part 4 quest reward | melee 6 studs, 2.5 s cooldown, huge knockback 120 |
| 🍌 **Banana Peel** | Part 4 quest reward | place on the ground (max 1 out, 10 s cooldown, lasts 20 s); first enemy to step on it ragdolls |

**Equipping:**
- Use Roblox `Tool`s in the Backpack: number keys, plus the mobile tool
  bar. Kids already know this.
- Give the earned tools on every spawn.
- Unlocks are saved in `PlayerData.Weapons` (a set), sanitised in
  `reconcile`.
- No tool is usable while carrying a stolen orb. Hands are full.

## Server authority (CLAUDE.md "Server authority")

- **Hits.** The client only sends `RequestHit { Weapon, TargetUserId?,
  Origin, Direction }`. The server re-checks:
  - the weapon is owned and equipped;
  - its cooldown;
  - both players' eligibility (rebirth, spawn protection, immunity);
  - range from the server's own root positions, plus a small lag slack;
  - for ranged weapons, a server raycast with line of sight.

  Use `RemoteGuard` for numbers and the rate limit. Add the remote to
  `RemoteEvents`, with a direction comment.
- **Ragdoll.** Characters are owned by their own client. On a valid hit,
  the server:
  1. sets the target's `Ragdolled` attribute (with the until-time);
  2. fires `HitReceived { Impulse, Seconds }` to the target, whose client
     ragdolls (Motor6D → BallSocketConstraints, `Humanoid` state
     Physical) and applies the impulse;
  3. restores the joints after the time.

  Every client plays the bonk VFX: "BONK!" pop text, stars and the hit
  sound through new `SoundConfig` slots.
- **During a ragdoll:** no stealing, no carrying, no LOCK and no prompts.
- **Exploit guard:** if a ragdolled client doesn't move, nothing breaks.
  The server owns the until-time and the immunity.
- **Analytics:** `Custom` events `Hit` (weapon), `ThiefKnocked` and
  `GuardKnocked`.

## UI

- **Tool icons:** a simple glyph in a circle for each weapon, built from
  `UITheme` (no new image uploads), plus the cooldown sweep on the tool.
- **First tutorial-style card** when a weapon unlocks (reuse the
  tutorial's card component): "🏏 You got a Bat! Hit a thief to make them
  drop your orb."
- **Rebirth panel:** the unlock list shows weapons per rebirth.

## Check

- **`/selftest`:**
  - a junk `RequestHit` fuzz: no error and no state change;
  - a Rebirth-0 target is never ragdolled;
  - a hit on a carrying thief returns the orb, with both inventories
    unchanged;
  - the cooldown is enforced server-side.
- **Two-player test (Studio, Test → 2 players):** bat a thief mid-carry,
  laser a runner, freeze, banana peel. Laser and freeze ray need Rebirth
  2–3 (use `/rebirths`).
- `luau-lsp analyze` reports no new errors. UI_TEST gets a "Combat"
  section, and CLAUDE.md a "Combat" entry.
- **Tell Harris:** update the game's **maturity questionnaire** in
  Creator Hub once combat is live. Answer **Violence: mild / cartoon**:
  no blood, no realistic weapons, no deaths.
