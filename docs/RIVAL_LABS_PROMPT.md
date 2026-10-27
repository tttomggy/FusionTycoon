# Rival labs: steal from minute 3, even in an empty server (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 6 lines, one per group: DONE or WHY-NOT. Commit per group. Run the Luau
parser and `tools/theme_token_check.py` before every push.

---

## Why

Stealing is the hook (it's on the store art and in the trailer), but a new
player can't steal until Rebirth 1 (~50 min, TycoonConfig header), and only
from another Rebirth 1+ **player**. With today's traffic (1–3 players per
server, 12 slots) there is usually nobody to steal from at all. Players
leave long before they see the thing that makes this game different.

Fix: empty plot slots become **rival labs**: NPC-owned labs a player can rob
from the start. PvP stealing (real players) keeps its Rebirth 1 gate, so new
players are still never robbed by veterans.

## 1. Rival labs fill empty slots (server)

- New `RivalConfig` + `RivalService`. Keep up to
  `RivalConfig.MaxRivals = 3` rival labs in slots no player owns. When a
  real player needs a slot and none is free, the farthest rival lab
  despawns first (any carry from it fails cleanly) and the player gets that
  slot. A real player is never refused a plot because of a rival.
- A rival lab is built by the **same plot builder** as a player's
  (`TycoonService` / `PlotLayout`: no second copy of any geometry), with
  `Owner = "Rival"` and a name from `RivalConfig.Names` ("Dr. Fizz's Lab",
  "Professor Volt's Lab", "Captain Ooze's Lab"...). Its gate sign, pedestals
  and orbs use the normal visuals. No generators/factory animation needed
  beyond what a player's empty lab shows; no Fusion Machine prompt.
- Orbs are server objects (everyone sees the same ones), so pick each
  rival's orbs from the **lowest Rebirth count among real players in the
  server**, using
  `RivalConfig.TierWeights[band]`, so a new player sees Commons/Rares/an Epic,
  never a Mythic. Plain only (no mutations), except a `RivalConfig.GoldenChance
  = 0.05` Golden.
- A stolen orb respawns on that pedestal after `RivalConfig.RespawnSeconds =
  90`.

## 2. Stealing from a rival (reuse HeistService)

- **Any player, Rebirth 0 included**, can steal from a rival lab. The
  `MinRebirths` gate stays for player-vs-player only (both sides). Make the
  rule explicit in `HeistConfig` (`MinRebirthsVsPlayers = 1`,
  `MinRebirthsVsRivals = 0`) and in `onRequestSteal`'s validation.
- Same grab (hold E), carry, deliver-inside-your-walls flow, same speeds and
  CarrySeconds. The item is created for the thief on delivery (it never
  belonged to a saved player, so there's no victim save to touch).
- **The guard:** each rival lab has one NPC guard (a blocky R15 rig from a
  HumanoidDescription, like the trailer's, server-side, no player avatars).
  It patrols inside its lab; when someone grabs an orb it chases the
  carrier at `RivalConfig.GuardSpeed = 13` (the carrier walks at 12, so a
  straight run is close; the speed belts and a head start win it). Touching
  the carrier = the orb goes back (the existing tag rule). It stops chasing
  at its gate + `RivalConfig.GuardLeash = 60` studs and walks home. Use
  `PathfindingService`, recompute at most every 0.5 s, one guard loop per
  server.
- Limits so it can't be farmed: per player, at most
  `RivalConfig.StealsPerHour = 12` rival steals (a toast "The rivals are on
  alert. Try again in N min" past it), and no Mythic/Secret ever from a
  rival. Run `tools/econ_sim.py` with a rival-steal income line (12/h of the
  band's weights) and report how much it moves Rebirth 1 (it should come
  sooner, not break: target Rebirth 1 still ≥ 35 min).
- Combat: players' weapons work on the guard like on a player (stun /
  ragdoll), so a friend can cover you.

## 3. Teach it in the first minutes

- After Tutorial 5 finishes, a one-time tip `tipRival` (TipConfig): ~20 s
  after "You're ready!", path arrows to the nearest rival lab's best
  pedestal and the line `Steal from the rival lab! Hold E, then run home.`
  Hand on the steal prompt when they arrive. Done when they deliver or after
  3 min. No card.
- Gate signs on rival labs read `RIVAL LAB · steal me!` in the rival
  accent colour (a new `UITheme.World` token, plus a UI token if any HUD
  text uses it).
- The existing PvP onboarding (HOW TO HEIST at Rebirth 1, stealHowTo, etc.)
  stays as it is.

## 4. Fairness + safety

- Rivals never steal from players and never appear in leaderboards,
  friend counts, the notification queue or analytics player counts.
- Server authority as always: the server resolves the rival, the pedestal,
  the orb and the distance from the requesting player; nothing from the
  client is trusted.
- Light caps and the no-new-`Highlight` rule apply to rival labs (they're
  plots). Their owner-only prompts/labels don't exist (no owner).

## 5. Analytics

- Funnel: add `FirstRivalSteal` right after `FirstFuse` in
  `AnalyticsKit.FunnelSteps`. (Appending in the middle renumbers later
  steps; that's fine pre-launch, note it in the doc.)
- A custom event per rival steal outcome (`Delivered` / `Tagged` /
  `Timeout`).

## 6. Selftest + docs

- `/selftest rivals`: a server with 1 player gets 3 rivals; a 2nd player
  joining a full server displaces the farthest rival; a Rebirth 0 player can
  steal from a rival and NOT from a Rebirth 1 player; delivery creates the
  item; the guard's tag returns it; respawn after 90 s (injected clock);
  StealsPerHour enforced; no Mythic/Secret in any rival's orb roll over
  10 000 draws; rival despawn mid-carry fails cleanly with no error.
- `docs/systems/heist.md` (a Rival labs section), `architecture.md`,
  `file-layout.md`, `tutorial.md` (tipRival).
