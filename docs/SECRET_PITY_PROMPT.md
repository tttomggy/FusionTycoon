# Secret pity meter: failed Mythic fusions build toward a sure Secret (build prompt for Claude Code)

Run `git pull` on `world-redesign`, then commit and push to `world-redesign`.
**If your session forces another branch, say so in the FIRST line.** Reply
in 6 lines. **Only these edits.**

---

## Why

The gacha price cap (f902366, 15 s) fixed the late-run price, but your sim
shows the first Secret still takes **12 h+** at both `--fuse=2` and
`--fuse=3`.

- Harris played to the end of a run and "it's impossible to hit a Secret".
  As you said, the cap isn't the lever. The Mythic → Secret odds are: 7–15%
  (2–6 inputs), and a fail eats all but the best input.
- So a player can feed in dozens of Mythics and walk away with nothing to
  show for it.
- Harris wants **progress you can feel**.

## The fix: a pity meter on Mythic → Secret

- **Each failed Mythic → Secret fusion adds charge** to a per-player
  `SecretPity` counter (saved). Weight it by inputs used: a 6-input fail
  adds more than a 2-input fail, so the meter never favours spamming pairs.
  For example, add the input count, and full = `SecretPityFull` points.
- **When the meter is full, the next Mythic → Secret fusion is a sure
  success.** The meter resets on any Secret from fusion (pity or lucky).
- A Secret from a gacha pull doesn't touch the meter.
- **Server-authoritative:**
  - `FusionService` reads and writes the meter.
  - It ships in `SyncTycoon`.
  - A rebirth does **not** reset it.
  - It goes through `PlayerDataService` (default 0, `toDisk` / `reconcile`
    round-trip).
- **Fuse panel:** when the chamber holds Mythics, show a slim "SECRET
  METER" bar under the success %.
  - The bar fills with the meter. At full it reads "NEXT FUSE IS A SURE
    SECRET!" in the Secret mint colour, and the success % shows 100%.
  - After a fail, the bar animates up (the fail card can say "Secret meter
    +6").
  - Colours from `UITheme`, text ≥ 13 px.
- Before Rebirth `SecretFusionRebirths` (Mythic fusion is locked) the meter
  is hidden.

## Tune it with the sim

- Add the meter to `tools/econ_sim.py` with the same rule, then sweep
  `SecretPityFull`.
- Targets, with the gacha cap at 15 and the share-limited pull policy as
  now:
  - **first Secret median 3–5 h** at `--fuse=2`;
  - within 12 h at `--fuse=3`;
  - a second Secret not sooner than ~1 h after the first (Secrets must stay
    special).
- Pick the value and give the reason in one line. Update the TycoonConfig /
  FusionConfig header table (first Secret, and add "second Secret").
- Don't change the 7–15% odds or any other tier.

## Selftest

- A failed 6-input Mythic fusion adds 6 points; a 2-input fail adds 2.
- At full, the next Mythic fusion succeeds 100% (force the roll to the
  worst value) and the meter resets to 0.
- The meter survives a `toDisk` → `reconcile` round trip and a rebirth.
- A remote fuzz can't change the meter.
- The Fuse panel bar shows the server's value, and at full the % reads 100.

## Check

- `luau-lsp analyze` shows no new errors (the known SparkleEmitter /
  TopStack ones are fine).
- Update `docs/systems/items-and-fusion.md` (pity rule) and
  `saves-and-offline.md` (the new save field).
- Harris: `/rebirths 1`, `/give` yourself Mythics, fail a few fusions, and
  watch the meter fill. At full, the next fuse is a Secret.
- Say which branch you pushed to.
