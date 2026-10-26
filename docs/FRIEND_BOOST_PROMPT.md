# Friend boost: +15% income per friend in your server, max +60% (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 4 lines, one per group: DONE or WHY-NOT. Run the Luau parser over `src/`
before pushing (CLAUDE.md Gotchas).

---

Why: Roblox's ranking now counts **intentional co-play days** (days players
come back with friends). A friend boost plus an invite button is the
standard simulator way to drive it.

## 1. The rule (server-authoritative)

- New `FriendConfig` (Shared/Config): `PercentPerFriend = 15`,
  `MaxFriends = 4` (so +60% max), `RecheckSeconds = 60`.
- A "friend" = a **Roblox friend in the same server** (`Player:IsFriendsWith`,
  pcall'd, it yields). Compute server-side only:
  - on PlayerAdded / PlayerRemoving, recheck the pairs that involve that
    player (spawned, never in Init);
  - cache results per pair; recheck every `RecheckSeconds` at most;
  - a failed call counts as not friends (no retry spam).
- Store each player's count where the income inputs can read it, and add
  `FriendMultiplier: number?` to `TycoonConfig.IncomeInputs`
  (`1 + 0.15 × min(count, 4)`), built only in
  `PlayerDataService.GetIncomeInputs` / `TycoonController.GetIncomeInputs`
  like the other multipliers. Multiply it in `GetIncomeMultiplier`, add a
  "Friends" row to `GetIncomeBreakdown`.
- It's a **boost**, so:
  - NOT in `GetSteadyIncomePerSecond` (the gacha price ignores boosts);
  - NOT in offline earnings (your friends aren't with you while you're away);
  - the econ sim stays solo (add `FriendMultiplier` to `tools/econ_sim.py`'s
    inputs as 1, nothing else).
- Sync: the count ships in the normal `SyncTycoon` snapshot; when a friend
  joins/leaves, sync both players.

## 2. HUD: a friends chip with an invite button

- An effects-tray entry **always shown** (even at 0): 👥 icon + `+30%` (or
  `+0%`). Same tray rules, sizes and phone/PC/tablet placement as the other
  tray circles (EffectsTray, the jump-button rule on touch).
- Tooltip: `Friends in this server: +15% income each (max +60%)`.
- Tap/click → `SocialService:PromptGameInvite(LocalPlayer)` behind
  `CanSendGameInviteAsync` (pcall'd). If it can't invite, the tooltip only.
- When a friend joins: a `TopStack.Announce` line `👥 <DisplayName> joined:
  +15% income!` (to both players). When one leaves: no banner, the chip
  just updates.

## 3. Rules that must hold

- No Robux, no pressure copy, no fake numbers: the chip shows the live
  multiplier from the server snapshot.
- Players under the Kids/Select tiers may have friends/invites restricted by
  Roblox; that's Roblox's job (CanSendGameInviteAsync), don't add our own.
- Docs: add a "Friend boost" section to `docs/systems/items-and-fusion.md`
  (where income lives) and the remote/field to `docs/systems/architecture.md`.

## 4. Selftest

- Make the friendship check injectable (a stub `IsFriends(a, b)`), then:
  - 0 friends → multiplier 1, chip `+0%`;
  - 2 friends → 1.30, chip `+30%`, breakdown has a Friends row = 1.3;
  - 6 friends → capped at 1.60;
  - steady income and offline earnings unchanged by friends;
  - the stub errors → treated as not friends, no server error.
- Restore the real check after the section.
