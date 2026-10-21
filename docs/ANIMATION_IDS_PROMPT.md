# Weapon animation ids (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 3 lines. **Only these edits.**

---

Harris uploaded the 7 exported clips to Roblox (his account). The live game
uses the C0 fallback because `CombatConfig.AnimationIds` is empty.

## 1. Fill `CombatConfig.AnimationIds`

```lua
CombatConfig.AnimationIds = {
	BatHold = "rbxassetid://110401007589373",
	BatSwing = "rbxassetid://138784586483656",
	GloveHold = "rbxassetid://130217269948133",
	GloveSlap = "rbxassetid://101382817461159",
	GunAim = "rbxassetid://76161756196333",
	GunRecoil = "rbxassetid://140487467838970",
	PeelThrow = "rbxassetid://126595384761881",
} :: { [string]: string }
```

## 2. Check the id path

- Confirm `WeaponAnimator` / `WeaponAnims` use an id as given
  (`Animation.AnimationId = id`) and load it with `Animator:LoadAnimation`.
  The `Hit` marker must still fire (the clips carry the marker; if an
  uploaded clip lost it, fall back to 55% of the clip as today).
- If `/anim export` and the in-code clips are only used when an id is empty,
  leave them as they are.

## 3. Selftest

- Add one line to the combat section: every `AnimationIds` entry is a
  well-formed `rbxassetid://<digits>` string and loads in Studio.
- Don't loosen any existing check.

## Check

- `luau-lsp analyze` shows no new errors. `/selftest` has no FAILs.
- Update the "Publishing the clips" note in `docs/systems/combat.md`: ids
  are set (date 2026-10-21).
- Harris: Play, equip each weapon and swing. It should look the same as
  before. Then publish and check live.
- Say which branch you pushed to.
