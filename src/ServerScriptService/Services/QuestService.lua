--!strict
--[[
	QuestService
	------------
	Daily quests, the lab quest chain and quest power-ups (every number and
	the copy in QuestConfig).

	  * A PlayerDataService.OnSync hook hands out the UTC day's 3 dailies
	    (QuestConfig.GetDailyDefs) the first time a sync sees a new day,
	    snapshotting each counted quest's counter (Base); "Income" gets its
	    target from the player's base income then. Every sync measures
	    progress from the SERVER's counters only (PlayerData.Stats,
	    TotalFusions, TotalSteals, the inventory, the Index, rebirths, base
	    income), latches Done, and publishes the status for the snapshot
	    (PlayerDataService.SetQuestStatus). The client never reports progress.
	  * ClaimQuest { Id } (C->S): re-checked (a real quest of today / the
	    current chain step, Done, not Claimed), then it pays the reward
	    (power-ups into PlayerData.PowerUps, a weapon via CombatService) and
	    answers QuestResult. Claiming chain #n starts #n+1.
	  * UsePowerUp { Key } (C->S): re-checked (count > 0 and the power-up's
	    own condition), then:
	      Cash Burst   +Seconds into the income boost bank (refused if full)
	      Lucky Charm  +Seconds into the luck bank (refused if full)
	      Speed Boots  Player attribute SpeedBootsUntil (server time); this
	                   service's loop lifts a NORMAL-speed humanoid to x1.5
	                   (carry / chase / freeze speeds always win). Not while
	                   carrying, not while already on.
	      Fusion Spark arms the next fusion (+FusionBonus; FusionService
	                   spends it). Not while already armed.
	      Coin Magnet  arms the current or next Golden Rain (EventService
	                   pulls coins in and disarms it when that rain ends).
	    PowerUpResult carries the toast. Never sold, not in the shop.
	  * Analytics: QuestClaimed (id), PowerUpUsed (key).

	Follows the ServiceTemplate contract:
	  :Init()   remotes; nothing cross-service.
	  :Start()  resolves PlayerDataService, CombatService, registers the
	            hook, starts the Speed Boots loop.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)
local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type CombatServiceModule = typeof(require(script.Parent.CombatService))
local PlayerDataService: PlayerDataServiceModule
local CombatService: CombatServiceModule

local QuestService = {}

local SPEED_ATTRIBUTE = "SpeedBootsUntil"
local SPEED_LOOP_SECONDS = 0.25
local CLAIM_RATE, CLAIM_BURST = 4, 6
local USE_RATE, USE_BURST = 2, 4

export type QuestView = {
	Id: string,
	Text: string,
	Progress: number,
	Target: number,
	Done: boolean,
	Claimed: boolean,
	Reward: { QuestConfig.RewardPart },
	RewardText: string,
	Chain: number?, -- the chain quest's number
}

export type QuestStatus = {
	UtcDay: number,
	Daily: { QuestView },
	Chain: QuestView,
	Ready: number, -- quests done and not claimed (the QUESTS badge)
	SpeedBootsUntil: number,
}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function weaponName(id: string): string
	local weapon = CombatConfig.GetWeapon(id)
	return if weapon then ("%s %s"):format(weapon.Glyph, weapon.Name) else id
end

--[[ Measuring -------------------------------------------------------------------- ]]

-- The live value of a counted kind's counter.
local function counter(player: Player, def: QuestConfig.QuestDef): number
	local kind = def.Kind
	if kind == "Pull" then
		return PlayerDataService.GetStat(player, "Pulls")
	elseif kind == "Fuse" then
		return PlayerDataService.GetTotalFusions(player)
	elseif kind == "Golden" then
		return PlayerDataService.GetStat(player, "Goldens")
	elseif kind == "RainCoin" then
		return PlayerDataService.GetStat(player, "RainCoins")
	elseif kind == "Upgrade" then
		return PlayerDataService.GetStat(player, "UpgradeLevels")
	elseif kind == "Steal" then
		return PlayerDataService.GetTotalSteals(player)
	elseif kind == "Knock" then
		return PlayerDataService.GetStat(player, "Knocks")
	elseif kind == "FuseInto" then
		return PlayerDataService.GetStat(player, "Fused_" .. tostring(def.Tier))
	end
	return 0
end

-- A state kind's live value (compared against its target).
local function stateValue(player: Player, def: QuestConfig.QuestDef): number
	local kind = def.Kind
	if kind == "Income" then
		return PlayerDataService.GetBasePassiveCashPerSecond(player)
	elseif kind == "OwnTier" then
		local count = 0
		local inventory = PlayerDataService.GetInventory(player)
		if inventory then
			for _, item in inventory do
				if item.Tier == def.Tier then
					count += 1
				end
			end
		end
		return count
	elseif kind == "IndexItems" then
		-- 1 when every item of the tier has at least one entry found.
		local found = PlayerDataService.GetIndex(player)
		for _, item in ItemConfig.GetItemsByTier(def.Tier or "") do
			local any = false
			for _, variant in IndexConfig.Variants do
				if found[IndexConfig.GetKey(item.Id, if variant == IndexConfig.NORMAL then nil else variant)] then
					any = true
					break
				end
			end
			if not any then
				return 0
			end
		end
		return 1
	elseif kind == "IndexEntries" then
		return IndexConfig.CountFound(PlayerDataService.GetIndex(player))
	elseif kind == "Rebirths" then
		return PlayerDataService.GetRebirths(player)
	end
	return 0
end

local function progressOf(player: Player, def: QuestConfig.QuestDef, base: number, target: number): number
	local value = if QuestConfig.CountedKinds[def.Kind] then counter(player, def) - base else stateValue(player, def)
	return math.clamp(value, 0, target)
end

--[[ Handing out --------------------------------------------------------------------- ]]

-- The UTC day's dailies, once per day per player (the first sync that
-- sees the day). Unclaimed rewards of an old day are gone, like the day.
local function ensureDay(player: Player, quests: QuestConfig.QuestState)
	local today = RewardConfig.GetUtcDay(os.time())
	if quests.UtcDay == today and #quests.Daily > 0 then
		return
	end
	quests.UtcDay = today
	quests.Daily = {}
	for _, def in QuestConfig.GetDailyDefs(today, PlayerDataService.GetRebirths(player)) do
		local target = if def.Kind == "Income"
			then QuestConfig.GetIncomeTarget(PlayerDataService.GetBasePassiveCashPerSecond(player))
			else def.Target
		table.insert(quests.Daily, {
			Id = def.Id,
			Target = target,
			Base = if QuestConfig.CountedKinds[def.Kind] then counter(player, def) else 0,
			Done = false,
			Claimed = false,
		})
	end
end

-- Starts chain quest #n (its counter from now).
local function startChain(player: Player, quests: QuestConfig.QuestState, n: number)
	local def = QuestConfig.GetChainQuest(n)
	quests.Chain = n
	quests.ChainDone = false
	quests.ChainBase = if QuestConfig.CountedKinds[def.Kind] then counter(player, def) else 0
end

-- The sync hook: hand out, measure, latch, publish.
local function onSync(player: Player)
	local quests = PlayerDataService.GetQuestState(player)
	if not quests then
		return
	end
	ensureDay(player, quests)
	local daily: { QuestView } = {}
	local ready = 0
	for _, entry in quests.Daily do
		local def = QuestConfig.GetDaily(entry.Id)
		if def then
			local progress = progressOf(player, def, entry.Base, entry.Target)
			if progress >= entry.Target then
				entry.Done = true
			end
			if entry.Done and not entry.Claimed then
				ready += 1
			end
			table.insert(daily, {
				Id = entry.Id,
				Text = QuestConfig.FormatText(def, entry.Target),
				Progress = if entry.Done then entry.Target else progress,
				Target = entry.Target,
				Done = entry.Done,
				Claimed = entry.Claimed,
				Reward = def.Reward,
				RewardText = QuestConfig.FormatReward(def.Reward, weaponName),
			})
		end
	end
	local chainDef = QuestConfig.GetChainQuest(quests.Chain)
	local chainProgress = progressOf(player, chainDef, quests.ChainBase, chainDef.Target)
	if chainProgress >= chainDef.Target then
		quests.ChainDone = true
	end
	if quests.ChainDone then
		ready += 1
	end
	local speedUntil = player:GetAttribute(SPEED_ATTRIBUTE)
	local status: QuestStatus = {
		UtcDay = quests.UtcDay,
		Daily = daily,
		Chain = {
			Id = "chain",
			Text = QuestConfig.FormatText(chainDef, chainDef.Target),
			Progress = if quests.ChainDone then chainDef.Target else chainProgress,
			Target = chainDef.Target,
			Done = quests.ChainDone,
			Claimed = false,
			Reward = chainDef.Reward,
			RewardText = QuestConfig.FormatReward(chainDef.Reward, weaponName),
			Chain = quests.Chain,
		},
		Ready = ready,
		SpeedBootsUntil = if typeof(speedUntil) == "number" then speedUntil else 0,
	}
	PlayerDataService.SetQuestStatus(player, status)
end

--[[ Claiming ------------------------------------------------------------------------- ]]

-- Pays a reward; returns the lines for the client's toast.
local function payReward(player: Player, reward: { QuestConfig.RewardPart }): { string }
	local lines = {}
	for _, part in reward do
		if part.PowerUp then
			local def = QuestConfig.GetPowerUp(part.PowerUp)
			local count = part.Count or 1
			if def then
				PlayerDataService.AddPowerUp(player, def.Key, count)
				table.insert(lines, ("%s %s ×%d"):format(def.Glyph, def.Name, count))
			end
		elseif part.Weapon then
			if CombatService.GrantWeapon(player, part.Weapon) then
				table.insert(lines, weaponName(part.Weapon))
			end
		end
	end
	return lines
end

-- Why `player` can't claim `id` right now, or nil. Synchronous (no yield
-- between this and the claim).
function QuestService.WhyNotClaim(player: Player, id: unknown): string?
	if typeof(id) ~= "string" or #id > 32 then
		return "Unknown"
	end
	local quests = PlayerDataService.GetQuestState(player)
	if not quests then
		return "NotLoaded"
	end
	onSync(player) -- measure now: the client's view may be a tick old
	if id == "chain" then
		return if quests.ChainDone then nil else "NotComplete"
	end
	for _, entry in quests.Daily do
		if entry.Id == id then
			if entry.Claimed then
				return "AlreadyClaimed"
			end
			return if entry.Done then nil else "NotComplete"
		end
	end
	return "Unknown"
end

-- Claims quest `id` (re-checked). Returns (ok, reasonOrNil, lines).
function QuestService.Claim(player: Player, id: unknown): (boolean, string?, { string })
	local reason = QuestService.WhyNotClaim(player, id)
	if reason then
		return false, reason, {}
	end
	local quests = PlayerDataService.GetQuestState(player) :: QuestConfig.QuestState
	local reward: { QuestConfig.RewardPart }
	if id == "chain" then
		reward = QuestConfig.GetChainQuest(quests.Chain).Reward
		startChain(player, quests, quests.Chain + 1)
	else
		reward = {}
		for _, entry in quests.Daily do
			if entry.Id == id then
				entry.Claimed = true
				local def = QuestConfig.GetDaily(id)
				reward = if def then def.Reward else {}
			end
		end
	end
	local lines = payReward(player, reward)
	AnalyticsKit.Custom(player, "QuestClaimed", nil, tostring(id))
	return true, nil, lines
end

local function onClaimQuest(player: Player, payload: unknown)
	if not RemoteGuard.Allow(player, "ClaimQuest", CLAIM_RATE, CLAIM_BURST) then
		return
	end
	local id = if typeof(payload) == "table" then (payload :: any).Id else nil
	local ok, reason, lines = QuestService.Claim(player, id)
	RemoteEvents.QuestResult:FireClient(player, {
		Id = if typeof(id) == "string" and #id <= 32 then id else "",
		Result = if ok then "Claimed" else "Refused",
		Reason = reason,
		Lines = lines,
	})
	if ok then
		PlayerDataService.SyncTycoon(player)
		PlayerDataService.SaveNow(player)
	end
end

--[[ Power-ups ------------------------------------------------------------------------- ]]

local function speedActive(player: Player): boolean
	local untilTime = player:GetAttribute(SPEED_ATTRIBUTE)
	return typeof(untilTime) == "number" and untilTime > serverNow()
end

-- Why `player` can't use power-up `key` right now, or nil.
function QuestService.WhyNotUse(player: Player, key: unknown): string?
	local def = QuestConfig.GetPowerUp(key)
	if not def then
		return "Unknown"
	end
	if not PlayerDataService.IsDataLoaded(player) then
		return "NotLoaded"
	end
	if PlayerDataService.GetPowerUpCount(player, def.Key) <= 0 then
		return "NoneLeft"
	end
	if def.Key == "CashBurst" then
		if PlayerDataService.GetBoostSeconds(player, "Income") >= ShopConfig.MaxBoostBankSeconds then
			return "BankFull"
		end
	elseif def.Key == "LuckyCharm" then
		if PlayerDataService.GetBoostSeconds(player, "Luck") >= ShopConfig.MaxLuckBankSeconds then
			return "BankFull"
		end
	elseif def.Key == "SpeedBoots" then
		if PlayerDataService.IsCarrying(player) then
			return "Carrying"
		end
		if speedActive(player) then
			return "AlreadyOn"
		end
	elseif def.Key == "FusionSpark" or def.Key == "CoinMagnet" then
		if PlayerDataService.IsArmed(player, def.Key) then
			return "AlreadyOn"
		end
	end
	return nil
end

-- Uses one (re-checked). Returns (ok, reasonOrNil, toastText).
function QuestService.Use(player: Player, key: unknown): (boolean, string?, string)
	local reason = QuestService.WhyNotUse(player, key)
	if reason then
		return false, reason, ""
	end
	local def = QuestConfig.GetPowerUp(key) :: QuestConfig.PowerUpDef
	if not PlayerDataService.TakePowerUp(player, def.Key) then
		return false, "NoneLeft", ""
	end
	local seconds = def.Seconds or 0
	if def.Key == "CashBurst" then
		PlayerDataService.AddBoostSeconds(player, "Income", seconds)
	elseif def.Key == "LuckyCharm" then
		PlayerDataService.AddBoostSeconds(player, "Luck", seconds)
	elseif def.Key == "SpeedBoots" then
		player:SetAttribute(SPEED_ATTRIBUTE, serverNow() + seconds)
	elseif def.Key == "FusionSpark" or def.Key == "CoinMagnet" then
		PlayerDataService.SetArmed(player, def.Key, true)
	end
	AnalyticsKit.Custom(player, "PowerUpUsed", nil, def.Key)
	return true, nil, ("%s %s · %s"):format(def.Glyph, def.Name, def.Blurb)
end

local function onUsePowerUp(player: Player, payload: unknown)
	if not RemoteGuard.Allow(player, "UsePowerUp", USE_RATE, USE_BURST) then
		return
	end
	local key = if typeof(payload) == "table" then (payload :: any).Key else nil
	local ok, reason, text = QuestService.Use(player, key)
	RemoteEvents.PowerUpResult:FireClient(player, {
		Key = if QuestConfig.GetPowerUp(key) then key else "",
		Result = if ok then "Used" else "Refused",
		Reason = reason,
		Text = text,
	})
	if ok then
		PlayerDataService.SyncTycoon(player)
	end
end

-- Speed Boots: lift a normal-speed humanoid while on, put it back after.
local function speedStep()
	local normal = HeistConfig.NormalWalkSpeed
	local boosted = normal * (QuestConfig.PowerUps.SpeedBoots.SpeedMultiplier or 1)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local on = speedActive(player) and not PlayerDataService.IsCarrying(player)
			if on and humanoid.WalkSpeed == normal then
				humanoid.WalkSpeed = boosted
			elseif not on and humanoid.WalkSpeed == boosted then
				humanoid.WalkSpeed = normal
			end
		end
		if player:GetAttribute(SPEED_ATTRIBUTE) ~= nil and not speedActive(player) then
			player:SetAttribute(SPEED_ATTRIBUTE, nil)
		end
	end
end

--[[ Studio + selftest ------------------------------------------------------------------- ]]

-- /quest complete <id>: latches a daily (or "chain") Done. Returns ok.
function QuestService.DebugComplete(player: Player, id: string): boolean
	local quests = PlayerDataService.GetQuestState(player)
	if not quests then
		return false
	end
	ensureDay(player, quests)
	if id == "chain" then
		quests.ChainDone = true
		return true
	end
	for _, entry in quests.Daily do
		if entry.Id == id then
			entry.Done = true
			return true
		end
	end
	return false
end

-- /quest reset: today's dailies handed out again, the chain back to #1.
function QuestService.DebugReset(player: Player)
	PlayerDataService.ResetQuests(player)
	local quests = PlayerDataService.GetQuestState(player)
	if quests then
		startChain(player, quests, 1)
	end
end

-- Today's daily ids for `player` (selftest).
function QuestService.GetDailyIds(player: Player): { string }
	local quests = PlayerDataService.GetQuestState(player)
	local ids = {}
	if quests then
		ensureDay(player, quests)
		for _, entry in quests.Daily do
			table.insert(ids, entry.Id)
		end
	end
	return ids
end

function QuestService.IsSpeedActive(player: Player): boolean
	return speedActive(player)
end

function QuestService:Init()
	RemoteEvents.ClaimQuest.OnServerEvent:Connect(onClaimQuest)
	RemoteEvents.UsePowerUp.OnServerEvent:Connect(onUsePowerUp)
end

function QuestService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	CombatService = require(script.Parent.CombatService)
	PlayerDataService.OnSync(onSync)
	task.spawn(function()
		while true do
			task.wait(SPEED_LOOP_SECONDS)
			speedStep()
		end
	end)
end

return QuestService
