--!strict
--[[
	QuestConfig
	-----------
	Daily quests, the lab quest chain and the power-ups they pay
	(QuestService on the server; QuestsPanel, the HUD power-up row and the
	goal card's tracker on the client).

	DAILY: 3 per UTC day (RewardConfig.GetUtcDay), drawn from DailyPool by
	a hash of the day (EventConfig.Hash32, like the event clock), so every
	server agrees with no messaging. Entries with MinRebirths are skipped for
	a player under it (the next eligible one in the day's order takes the
	slot). Counted kinds measure the counter's growth since the day's quests
	were handed out (a Base snapshot); "Income" is the player's BASE income
	reaching a target scaled to them when the day started.

	CHAIN: an endless numbered list (#1, #2, ...). Chain[n] while it lasts,
	then GetChainQuest makes harder ones forever. One at a time: claim #n
	and #n+1 starts (its counters from that moment).

	POWER-UPS: quest rewards only. **Never sold for Robux and not in the
	shop** (they're the free reward loop). Stored as counts
	(PlayerData.PowerUps), used from the HUD's power-up row whenever the
	player wants (remote UsePowerUp, re-checked by the server).

	Kinds (what the server counts, never the client):
	  Pull        pulls (paid, free and reward pulls)    Stats.Pulls
	  Fuse        fusions (success or fail)              TotalFusions
	  Golden      new items with a Golden base           Stats.Goldens
	  RainCoin    Golden Rain coins collected            Stats.RainCoins
	  Upgrade     generator levels bought                Stats.UpgradeLevels
	  Steal       orbs delivered home                    TotalSteals
	  Knock       carrying thieves knocked with a weapon Stats.Knocks
	  FuseInto    successful fusions into `Tier`         Stats["Fused_<Tier>"]
	  Income      base income reaches Target             (state)
	  OwnTier     own Target items of `Tier`             (state)
	  IndexItems  every `Tier` item found in the Index   (state)
	  IndexEntries  Target Index entries found           (state)
	  Rebirths    Target rebirths                        (state)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)

local QuestConfig = {}

--[[ Power-ups ------------------------------------------------------------------ ]]

export type PowerUpDef = {
	Key: string,
	Name: string,
	Glyph: string,
	Blurb: string,
	Seconds: number?, -- timed ones
	SpeedMultiplier: number?, -- Speed Boots
	FusionBonus: number?, -- Fusion Spark: added to the next fusion's chance (0.10 = +10 points)
	Radius: number?, -- Coin Magnet: studs
}

QuestConfig.PowerUps = {
	CashBurst = {
		Key = "CashBurst",
		Name = "Cash Burst",
		Glyph = "💸",
		Blurb = "×2 income for 5 min (adds to your boost time)",
		Seconds = 5 * 60, -- into the income boost bank (ShopConfig.BoostMultiplier)
	},
	LuckyCharm = {
		Key = "LuckyCharm",
		Name = "Lucky Charm",
		Glyph = "🍀",
		Blurb = "×2 luck for 10 min",
		Seconds = 10 * 60, -- into the luck bank (ShopConfig.LuckPotionMultiplier)
	},
	SpeedBoots = {
		Key = "SpeedBoots",
		Name = "Speed Boots",
		Glyph = "👟",
		Blurb = "×1.5 walk speed for 2 min",
		Seconds = 2 * 60,
		SpeedMultiplier = 1.5,
	},
	FusionSpark = {
		Key = "FusionSpark",
		Name = "Fusion Spark",
		Glyph = "⚗️",
		Blurb = "Your next fusion gets +10 points",
		FusionBonus = 0.10,
	},
	CoinMagnet = {
		Key = "CoinMagnet",
		Name = "Coin Magnet",
		Glyph = "🧲",
		Blurb = "Golden Rain coins within 20 studs come to you, for one rain",
		Radius = 20,
	},
} :: { [string]: PowerUpDef }

QuestConfig.PowerUpOrder = { "CashBurst", "LuckyCharm", "SpeedBoots", "FusionSpark", "CoinMagnet" }
QuestConfig.MaxPowerUpStack = 99
QuestConfig.MagnetIntervalSeconds = 0.25 -- how often a live magnet pulls coins in

function QuestConfig.GetPowerUp(key: unknown): PowerUpDef?
	if typeof(key) ~= "string" then
		return nil
	end
	return QuestConfig.PowerUps[key]
end

--[[ Rewards ---------------------------------------------------------------------- ]]

-- One part of a quest's reward: a power-up stack or a weapon (CombatConfig
-- id; the chain's Slap Glove and Banana Peel).
export type RewardPart = { PowerUp: string?, Count: number?, Weapon: string? }

local function pu(key: string, count: number): RewardPart
	return { PowerUp = key, Count = count }
end

-- "💸 ×2 · 🖐 Slap Glove"
function QuestConfig.FormatReward(reward: { RewardPart }, weaponName: ((string) -> string)?): string
	local parts = {}
	for _, part in reward do
		if part.PowerUp then
			local def = QuestConfig.PowerUps[part.PowerUp]
			if def then
				table.insert(parts, ("%s ×%d"):format(def.Glyph, part.Count or 1))
			end
		elseif part.Weapon then
			table.insert(parts, if weaponName then weaponName(part.Weapon) else part.Weapon)
		end
	end
	return table.concat(parts, " · ")
end

--[[ Daily quests ------------------------------------------------------------------ ]]

export type QuestDef = {
	Id: string,
	Kind: string,
	Target: number, -- 0 for Income (scaled when handed out)
	Text: string, -- "%s" gets the target (formatted)
	Tier: string?,
	MinRebirths: number?,
	Reward: { RewardPart },
}

QuestConfig.DailyCount = 3
-- "Reach $X/s": X = base income when the day's quests are handed out x this
-- (at least IncomeQuestMin), rounded to 2 significant figures.
QuestConfig.IncomeQuestFactor = 2
QuestConfig.IncomeQuestMin = 50

QuestConfig.DailyPool = {
	{ Id = "pull20", Kind = "Pull", Target = 20, Text = "Pull %s times", Reward = { pu("CashBurst", 1) } },
	{ Id = "fuse5", Kind = "Fuse", Target = 5, Text = "Fuse %s times", Reward = { pu("FusionSpark", 1) } },
	{ Id = "golden1", Kind = "Golden", Target = 1, Text = "Get a Golden mutation", Reward = { pu("LuckyCharm", 1) } },
	{ Id = "coins15", Kind = "RainCoin", Target = 15, Text = "Collect %s Golden Rain coins", Reward = { pu("CoinMagnet", 1) } },
	{ Id = "upgrade25", Kind = "Upgrade", Target = 25, Text = "Upgrade generators %s levels", Reward = { pu("SpeedBoots", 1) } },
	{ Id = "income", Kind = "Income", Target = 0, Text = "Reach %s/s", Reward = { pu("CashBurst", 1) } },
	{ Id = "steal1", Kind = "Steal", Target = 1, MinRebirths = 1, Text = "Steal %s orb", Reward = { pu("SpeedBoots", 2) } },
	{ Id = "knock3", Kind = "Knock", Target = 3, MinRebirths = 1, Text = "Knock %s thieves with a weapon", Reward = { pu("LuckyCharm", 2) } },
} :: { QuestDef }

function QuestConfig.GetDaily(id: unknown): QuestDef?
	for _, def in QuestConfig.DailyPool do
		if def.Id == id then
			return def
		end
	end
	return nil
end

-- The day's draw order over the pool (a hash of the UTC day per entry,
-- sorted), the same on every server.
local function dayOrder(utcDay: number): { QuestDef }
	local keyed = {}
	for index, def in QuestConfig.DailyPool do
		local seed = bit32.band(utcDay * 977 + index * 7919, 0xFFFFFFFF)
		table.insert(keyed, { Def = def, Key = EventConfig.Hash32(seed) })
	end
	table.sort(keyed, function(a, b)
		return a.Key < b.Key
	end)
	local order = {}
	for _, entry in keyed do
		table.insert(order, entry.Def)
	end
	return order
end

-- The day's DailyCount quests for a player with `rebirths`.
function QuestConfig.GetDailyDefs(utcDay: number, rebirths: number): { QuestDef }
	local picked = {}
	for _, def in dayOrder(utcDay) do
		if #picked >= QuestConfig.DailyCount then
			break
		end
		if rebirths >= (def.MinRebirths or 0) then
			table.insert(picked, def)
		end
	end
	return picked
end

-- 1234 -> 1200; at least IncomeQuestMin.
function QuestConfig.GetIncomeTarget(baseIncome: number): number
	local raw = math.max(QuestConfig.IncomeQuestMin, baseIncome * QuestConfig.IncomeQuestFactor)
	local digits = math.floor(math.log10(raw))
	local unit = 10 ^ math.max(0, digits - 1)
	return math.ceil(raw / unit) * unit
end

--[[ Lab quest chain ------------------------------------------------------------------ ]]

QuestConfig.Chain = {
	{ Id = "chain", Kind = "OwnTier", Tier = "Rare", Target = 10, Text = "Own %s Rares", Reward = { pu("CashBurst", 2) } },
	{
		Id = "chain",
		Kind = "IndexItems",
		Tier = "Common",
		Target = 1,
		Text = "Complete the Common page: find every Common item",
		Reward = { pu("LuckyCharm", 2) },
	},
	{
		Id = "chain",
		Kind = "FuseInto",
		Tier = "Mythic",
		Target = 1,
		Text = "Fuse a Mythic",
		Reward = { { Weapon = "SlapGlove" }, pu("FusionSpark", 2) },
	},
	{
		Id = "chain",
		Kind = "OwnTier",
		Tier = "Legendary",
		Target = 4,
		Text = "Own %s Legendaries",
		Reward = { pu("SpeedBoots", 2), pu("CashBurst", 1) },
	},
	{ Id = "chain", Kind = "Rebirths", Target = 2, Text = "Reach Rebirth %s", Reward = { pu("CashBurst", 3) } },
	{
		Id = "chain",
		Kind = "IndexEntries",
		Target = 30,
		Text = "Find %s Index entries",
		Reward = { { Weapon = "BananaPeel" }, pu("CoinMagnet", 2) },
	},
	{
		Id = "chain",
		Kind = "IndexItems",
		Tier = "Rare",
		Target = 1,
		Text = "Complete the Rare page: find every Rare item",
		Reward = { pu("LuckyCharm", 3) },
	},
	{ Id = "chain", Kind = "OwnTier", Tier = "Secret", Target = 1, Text = "Own a Secret", Reward = { pu("FusionSpark", 3), pu("CashBurst", 2) } },
	{ Id = "chain", Kind = "Rebirths", Target = 3, Text = "Reach Rebirth %s", Reward = { pu("CashBurst", 4) } },
} :: { QuestDef }

-- Chain quest #n: the list while it lasts, then endless, alternating
-- "Reach Rebirth N" and "Fuse N times" with bigger stacks each time.
function QuestConfig.GetChainQuest(n: number): QuestDef
	local listed = QuestConfig.Chain[n]
	if listed then
		return listed
	end
	local k = n - #QuestConfig.Chain -- 1, 2, 3, ...
	local step = (k + 1) // 2
	if k % 2 == 1 then
		return {
			Id = "chain",
			Kind = "Rebirths",
			Target = 3 + step,
			Text = "Reach Rebirth %s",
			Reward = { pu("CashBurst", 3 + step), pu("LuckyCharm", 1 + step // 2) },
		}
	end
	return {
		Id = "chain",
		Kind = "Fuse",
		Target = 50 * step,
		Text = "Fuse %s times",
		Reward = { pu("FusionSpark", 2 + step), pu("SpeedBoots", 1 + step // 2) },
	}
end

-- The text with its target filled in ("Reach $12K/s", "Own 10 Rares").
function QuestConfig.FormatText(def: QuestDef, target: number): string
	if not string.find(def.Text, "%%s") then
		return def.Text
	end
	local value = if def.Kind == "Income" then NumberFormat.Money(target) else NumberFormat.Short(target)
	return (def.Text:format(value))
end

-- Counted kinds (progress = counter now - counter when the quest started).
QuestConfig.CountedKinds = {
	Pull = true,
	Fuse = true,
	Golden = true,
	RainCoin = true,
	Upgrade = true,
	Steal = true,
	Knock = true,
	FuseInto = true,
} :: { [string]: boolean }

-- The Stats keys the server keeps (PlayerData.Stats), whitelisted.
local statKeys: { string } = { "Pulls", "Goldens", "RainCoins", "UpgradeLevels", "Knocks" }
for tier in ItemConfig.Tiers :: { [string]: number } do
	table.insert(statKeys, "Fused_" .. tier)
end
QuestConfig.StatKeys = statKeys

function QuestConfig.IsStatKey(key: unknown): boolean
	if typeof(key) ~= "string" then
		return false
	end
	local name: string = key
	return table.find(QuestConfig.StatKeys, name) ~= nil
end

--[[ Saved state (PlayerData.Quests; QuestService mutates it) ---------------------- ]]

-- One handed-out quest: its counter's value when it started (counted
-- kinds), its target, and the latches.
export type QuestEntry = {
	Id: string,
	Target: number,
	Base: number,
	Done: boolean,
	Claimed: boolean,
}

export type QuestState = {
	UtcDay: number, -- the day Daily was handed out (-1 = never)
	Daily: { QuestEntry },
	Chain: number, -- the chain quest in progress (#1, #2, ...)
	ChainBase: number, -- its counter's value when it started
	ChainDone: boolean,
}

return QuestConfig
