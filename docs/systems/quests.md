# Quests and power-ups

Moved out of CLAUDE.md (verbatim). Read this file when a task touches this system.

- **Quests & power-ups** (`QuestConfig` numbers + copy, `QuestService`,
  `UI/QuestsPanel`). **Daily:** 3 per UTC day drawn by a hash of the day
  (`EventConfig.Hash32`), Rebirth-1+ ones (Steal 1, Knock 3) skipped for
  newer players: Pull 20, Fuse 5, Get a Golden, Collect 15 Golden Rain
  coins, Upgrade 25 levels, Reach $X/s (2× base income at hand-out).
  **Lab chain** (endless, one at a time; claiming #n starts #n+1): Own 10
  Rares · the Common page (every Common item found) · Fuse a Mythic (🖐
  Slap Glove) · Own 4 Legendaries · Rebirth 2 · 30 Index entries (🍌
  Banana Peel) · the Rare page · Own a Secret · Rebirth 3, then Rebirth N
  / Fuse 50k alternating with bigger stacks (`GetChainQuest`). **Progress
  is server-side only**: `PlayerData.Stats` (Pulls, Goldens, RainCoins,
  UpgradeLevels, Knocks, Fused_<Tier>; bumped at the real sources via
  `PlayerDataService.AddStat`), TotalFusions, TotalSteals, the inventory,
  the Index, rebirths, base income; counted kinds measure growth from a
  Base taken when the quest started. An OnSync hook hands out, measures,
  latches `Done` and publishes the status (`SetQuestStatus` → snapshot
  `Quests`, plus `PowerUps` and `Armed`). `PlayerData.Quests = { UtcDay,
  Daily = { { Id, Target, Base, Done, Claimed } }, Chain, ChainBase,
  ChainDone }`, sanitised. Remotes `ClaimQuest { Id }` / `UsePowerUp
  { Key }` (C→S, rate-limited, re-checked: complete and unclaimed; count
  and condition) → `QuestResult` / `PowerUpResult`. **Power-ups**
  (`PlayerData.PowerUps` counts, cap 99; **never sold, not in the
  shop**): 💸 Cash Burst +5 min in the ×2 income bank, 🍀 Lucky Charm +10
  min ×2 luck (refused at a full 3 h bank), 👟 Speed Boots ×1.5 for 2 min
  (Player attribute `SpeedBootsUntil`; a server loop lifts only a
  normal-speed humanoid, carry / chase / freeze win; refused while
  carrying), ⚗️ Fusion Spark (armed: +10 points on the next fusion, shown
  in the Fuse panel's %, spent success or fail), 🧲 Coin Magnet (armed:
  EventService collects every Golden Rain coin you may take within 20
  studs through the same path as a touch, then disarms at that rain's
  end). **HUD:** the amber 📜 QUESTS button under SHOP / GIFTS (green ready
  badge + bounce), the power-up row beside it (only what you own, count
  badges, ✓ armed, Speed Boots seconds), a tracker under NEXT GOAL (the
  nearest unfinished quest; tap opens the panel). Analytics
  `QuestClaimed` (id), `PowerUpUsed` (key). Sim (`--quests`, 3 dailies
  per 2 h session-day at 10 / 20 / 30 min, bursts used at once): free
  Rebirth 1 0:59:01 vs 1:04:17 (−8.2%, within ±10%).
