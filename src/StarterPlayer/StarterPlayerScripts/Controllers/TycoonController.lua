local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
local FriendConfig = require(ReplicatedStorage.Shared.Config.FriendConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local SettingsConfig = require(ReplicatedStorage.Shared.Config.SettingsConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local ShopState = require(ReplicatedStorage.Shared.Modules.ShopState)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local InventoryController = require(script.Parent.InventoryController)

local TycoonController = {}

-- Local cache of the server-authoritative tycoon state; never mutated optimistically.
local cash = 0
local generatorLevels: { [string]: number } = {}
local pedestalDisplays: { [number]: string } = {}
local cashMultiplierLevel = 0
local gachaPulls = 0
local secretPity = 0 -- the server's Secret pity meter (snapshot SecretPity)
local luckBase = 1 -- the server's luck without the admin-luck event (snapshot LuckBase)
local serverLuck = 1 -- the server's whole luck at the last sync (snapshot Luck)
local goalIndex: number? = nil
local goalProgress: { Current: number, Target: number }? = nil
local hasSynced = false
local rebirths = 0
local indexFound: { [string]: boolean } = {}
local indexMultiplier = 1
local friendCount = 0 -- Roblox friends in this server (the server's count, the snapshot's Friends)
local pendingOffline = 0
-- Uids of displayed items a thief is carrying: they earn nothing meanwhile.
local carriedUids: { [string]: boolean } = {}
-- One-time tips/cards already seen (saved; TipConfig ids).
local tipsSeen: { [string]: boolean } = {}
-- The first-time tutorial (snapshot Tutorial; TutorialService owns it).
-- PullsDone: pulls since the current step began (the pull step's "0/2").
export type TutorialView = { Step: number, Done: boolean, FreePulls: number, PullsDone: number, Replay: boolean, ReplayHint: boolean }
local tutorial: TutorialView = { Step = 0, Done = false, FreePulls = 0, PullsDone = 0, Replay = false, ReplayHint = false }
-- os.clock() when this client watched the tutorial finish (nil: it was not
-- running when the player joined, or it is running again after a reset).
local tutorialDoneAt: number? = nil
-- Earned weapon ids (snapshot Weapons; CombatService grants them).
local weapons: { string } = {}
-- Quests (QuestService's status), power-up counts and armed power-ups.
local quests: any = nil
local powerUps: { [string]: number } = {}
local armed: { [string]: boolean } = {}
-- Marked here but not yet echoed back by a snapshot.
local pendingTipMarks: { [string]: boolean } = {}
local awaySeconds = 0
-- The shop's view of this player (snapshot Shop). Timed boosts count down
-- locally from the moment the snapshot arrived.
type ShopView = {
	OwnedPasses: { [string]: boolean },
	Restricted: boolean,
	IncomeBoostSeconds: number,
	LuckBoostSeconds: number,
	SafeFusionTokens: number,
	StarterPackBought: boolean,
	Cosmetics: { [string]: boolean },
	Sessions: number,
	DealPopupSlot: number, -- the deal slot whose "New deal!" card showed (saved)
	OfflineDoubleAmount: number,
	ReceivedAt: number, -- os.clock()
}
local shop: ShopView = {
	OwnedPasses = {},
	Restricted = true,
	IncomeBoostSeconds = 0,
	LuckBoostSeconds = 0,
	SafeFusionTokens = 0,
	StarterPackBought = false,
	Cosmetics = {},
	Sessions = 0,
	DealPopupSlot = 0,
	OfflineDoubleAmount = 0,
	ReceivedAt = 0,
}
-- The daily reward (snapshot Daily: DailyConfig.GetStatus on the server).
export type DailyView = {
	CanClaim: boolean,
	Day: number,
	Streak: number,
	Skips: number,
	UsesSkip: boolean,
	Resets: boolean,
	LastDay: number,
}
local daily: DailyView = { CanClaim = false, Day = 1, Streak = 0, Skips = 1, UsesSkip = false, Resets = false, LastDay = 0 }
-- This visit's playtime gifts (snapshot Gifts); play time counts on locally
-- from the moment the snapshot arrived.
local giftPlaySeconds = 0
local giftReceivedAt = os.clock()
local giftClaimed: { number } = {}
-- Settings (SettingsConfig): the server's copy plus local changes it hasn't
-- echoed yet (optimistic: they apply at once).
local revealRule: SettingsConfig.RevealRule = SettingsConfig.GetDefaultRevealRule()
local pendingReveal: { [string]: string } = {}
local sfxVolume = SettingsConfig.DefaultSfxVolume
local sfxMuted = false
local musicVolume = SettingsConfig.DefaultMusicVolume
local musicOn = true
-- Local sound changes not echoed yet (nil = none pending).
local pendingSfxVolume: number? = nil
local pendingSfxMuted: boolean? = nil
local pendingMusicVolume: number? = nil
local pendingMusicOn: boolean? = nil
-- The Auto-Fuse pass's toggle (Settings.AutoFuse), optimistic like the rest.
local autoFuse = false
local pendingAutoFuse: boolean? = nil
-- The goal path's setting (Settings.GoalPath), optimistic like the rest.
local goalPath: string = "Auto"
local pendingGoalPath: string? = nil

local function applySfx()
	SoundKit.SetVolume(if sfxMuted then 0 else sfxVolume)
end
applySfx()

local tycoonChanged = Instance.new("BindableEvent")
TycoonController.TycoonChanged = tycoonChanged.Event

-- Fires only once the server has validated the purchase attempt.
local upgradeResolved = Instance.new("BindableEvent")
TycoonController.UpgradeResolved = upgradeResolved.Event
local upgradeMaxResolved = Instance.new("BindableEvent")
-- Fires (result) for every UpgradeMaxResult (MAX ×N and MAX ALL).
TycoonController.UpgradeMaxResolved = upgradeMaxResolved.Event

-- Guards per-generator so a pending purchase on one doesn't block clicks on another.
local pendingUpgrades: { [string]: boolean } = {}
local pendingMax = false -- one MAX request in flight at a time

function TycoonController.GetCash(): number
	return cash
end

function TycoonController.GetGeneratorLevel(generatorId: string): number
	return generatorLevels[generatorId] or 0
end

function TycoonController.IsUpgradePending(generatorId: string): boolean
	return pendingUpgrades[generatorId] == true
end

function TycoonController.GetGeneratorLevels(): { [string]: number }
	return generatorLevels
end

function TycoonController.GetCashMultiplierLevel(): number
	return cashMultiplierLevel
end

function TycoonController.GetGachaPulls(): number
	return gachaPulls
end

-- The Secret pity meter as of the last sync (FusionConfig.SecretPityFull is full).
function TycoonController.GetSecretPity(): number
	return secretPity
end

-- The luck the server rolls with, as of now: its luck without the event
-- (every sync) times the live event value (replicated by itself, so an event
-- starting or ending updates it without waiting for a sync). The Gacha Pad
-- card shows odds at exactly this.
function TycoonController.GetLuck(): number
	return luckBase * EventState.GetLuckMultiplier()
end

-- The luck as of the last sync (what the server sent).
function TycoonController.GetServerLuck(): number
	return serverLuck
end

-- Index into GoalConfig.Goals of the current goal (nil before the first
-- snapshot), and the server-computed progress toward it (nil once all done).
function TycoonController.GetGoalIndex(): number?
	return goalIndex
end

function TycoonController.GetGoalProgress(): { Current: number, Target: number }?
	return goalProgress
end

function TycoonController.GetRebirths(): number
	return rebirths
end

-- Roblox friends here (0..FriendConfig.MaxFriends), as the server counted.
function TycoonController.GetFriendCount(): number
	return friendCount
end

-- Cash price of the next rebirth.
function TycoonController.GetRebirthCost(): number
	return RebirthConfig.GetCost(rebirths)
end

-- True while the player can afford the next rebirth.
function TycoonController.IsRebirthReady(): boolean
	return hasSynced and cash >= TycoonController.GetRebirthCost()
end

-- Found Index entries ("<itemId>|<Mutation or Normal>" -> true).
function TycoonController.GetIndex(): { [string]: boolean }
	return indexFound
end

-- False until the first snapshot arrives (so the HUD doesn't flash $0).
-- Uncollected offline earnings (0 = none) and the away time they cover.
function TycoonController.GetPendingOffline(): (number, number)
	return pendingOffline, awaySeconds
end

function TycoonController.HasSynced(): boolean
	return hasSynced
end

function TycoonController.GetPedestalDisplays(): { [number]: string }
	return pedestalDisplays
end

-- Uid of the item displayed on `pedestalIndex`, or nil if it's empty.
function TycoonController.GetPedestalDisplay(pedestalIndex: number): string?
	return pedestalDisplays[pedestalIndex]
end

-- A one-time tip/card was already shown to this account.
function TycoonController.GetWeapons(): { string }
	return weapons
end

-- The server's quest status (QuestService.QuestStatus), nil before the
-- first sync.
function TycoonController.GetQuests(): any
	return quests
end

function TycoonController.GetPowerUpCount(key: string): number
	return powerUps[key] or 0
end

-- A one-shot power-up (FusionSpark, CoinMagnet) waiting for its moment.
function TycoonController.IsArmed(key: string): boolean
	return armed[key] == true
end

function TycoonController.GetTutorial(): TutorialView
	return tutorial
end

-- The tutorial is running: shop side cards, deal pop-ups, the Daily card
-- and one-time tips wait (TutorialController holds them).
function TycoonController.IsTutorialActive(): boolean
	return hasSynced and not tutorial.Done
end

-- Can the player pay for a Gacha pull right now (a free tutorial pull or
-- the cash for the next one)? Drives the Rainbow Storm pointer.
function TycoonController.CanAffordPull(): boolean
	if tutorial.FreePulls > 0 then
		return true
	end
	return TycoonController.GetCash() >= TycoonConfig.GetGachaPullCost(TycoonController.GetGachaPulls(), TycoonController.GetSteadyIncomePerSecond())
end

-- Seconds since the tutorial ended in front of this player; math.huge when
-- it was already over at the join (and while it is running: use
-- IsTutorialActive for that).
function TycoonController.GetSecondsSinceTutorialDone(): number
	local doneAt = tutorialDoneAt
	return if doneAt then os.clock() - doneAt else math.huge
end

function TycoonController.HasSeenTip(id: string): boolean
	return tipsSeen[id] == true
end

-- Marks a one-time tip seen: locally at once (so it can't show twice before
-- the next snapshot) and on the server (saved in PlayerData.Tips).
function TycoonController.MarkTipSeen(id: string)
	if tipsSeen[id] then
		return
	end
	tipsSeen[id] = true
	pendingTipMarks[id] = true
	RemoteEvents.MarkTipSeen:FireServer({ Id = id })
end

-- Which tiers / mutations get the big reveal card (SettingsConfig).
function TycoonController.GetRevealRule(): SettingsConfig.RevealRule
	return revealRule
end

-- Changes one tier's reveal rule now and saves it on the server.
function TycoonController.SetRevealRule(tier: string, value: string)
	if not SettingsConfig.IsRevealTier(tier) or not SettingsConfig.IsRevealValue(value) then
		return
	end
	revealRule[tier] = value
	pendingReveal[tier] = value
	RemoteEvents.SetSetting:FireServer({ Key = "RevealRule", Tier = tier, Value = value })
end

-- Sound effects volume (0..1) and mute (SettingsConfig).
function TycoonController.GetSfxVolume(): number
	return sfxVolume
end

function TycoonController.IsSfxMuted(): boolean
	return sfxMuted
end

-- Applies at once. `save` false while dragging the slider (local only);
-- true on release sends it to the server.
function TycoonController.SetSfxVolume(volume: number, save: boolean)
	sfxVolume = SettingsConfig.SanitizeSfxVolume(volume)
	-- Pending even mid-drag, so a snapshot can't snap the slider back.
	pendingSfxVolume = sfxVolume
	applySfx()
	if save then
		RemoteEvents.SetSetting:FireServer({ Key = "SfxVolume", Value = sfxVolume })
	end
end

function TycoonController.SetSfxMuted(muted: boolean)
	sfxMuted = muted
	pendingSfxMuted = muted
	applySfx()
	RemoteEvents.SetSetting:FireServer({ Key = "SfxMuted", Value = muted })
end

-- Background music on / off and volume (SettingsConfig MusicOn / MusicVolume).
function TycoonController.GetMusicVolume(): number
	return musicVolume
end

function TycoonController.IsMusicOn(): boolean
	return musicOn
end

-- Applies at once. `save` false while dragging the slider; true on release.
function TycoonController.SetMusicVolume(volume: number, save: boolean)
	musicVolume = SettingsConfig.SanitizeMusicVolume(volume)
	pendingMusicVolume = musicVolume
	if save then
		RemoteEvents.SetSetting:FireServer({ Key = "MusicVolume", Value = musicVolume })
	end
end

function TycoonController.SetMusicOn(on: boolean)
	musicOn = on
	pendingMusicOn = on
	RemoteEvents.SetSetting:FireServer({ Key = "MusicOn", Value = on })
end

-- The lit path to the current goal: the 👣 toggle, else on for the first
-- TutorialConfig.GoalPathSessions sessions.
function TycoonController.IsGoalPathOn(): boolean
	if goalPath == "On" then
		return true
	elseif goalPath == "Off" then
		return false
	end
	return shop.Sessions <= TutorialConfig.GoalPathSessions
end

function TycoonController.SetGoalPath(on: boolean)
	goalPath = if on then "On" else "Off"
	pendingGoalPath = goalPath
	RemoteEvents.SetSetting:FireServer({ Key = "GoalPath", Value = goalPath })
	tycoonChanged:Fire()
end

function TycoonController.IsAutoFuseOn(): boolean
	return autoFuse
end

function TycoonController.SetAutoFuse(on: boolean)
	autoFuse = on
	pendingAutoFuse = on
	RemoteEvents.SetSetting:FireServer({ Key = "AutoFuse", Value = on })
end

-- One of this player's displayed items is being carried off by a thief.
function TycoonController.IsItemCarried(uid: string): boolean
	return carriedUids[uid] == true
end

-- Tier and mutation of the items on this player's pedestals (from the
-- inventory cache), minus any being carried off (same as the server).
function TycoonController.GetDisplayedItems(): { TycoonConfig.PedestalItem }
	local byUid: { [string]: any } = {}
	for _, item in InventoryController.GetInventory() do
		byUid[item.Uid] = item
	end
	local items = {}
	local order = TycoonController.GetPedestalOrder()
	for index, uid in pedestalDisplays do
		local item = byUid[uid]
		if item and table.find(order, index) and not carriedUids[uid] then
			table.insert(items, { Tier = item.Tier, Mutation = item.Mutation, EventMutations = item.EventMutations })
		end
	end
	return items
end

-- The one place the client builds TycoonConfig.IncomeInputs.
function TycoonController.GetIncomeInputs(): TycoonConfig.IncomeInputs
	return {
		GeneratorLevels = generatorLevels,
		PedestalItems = TycoonController.GetDisplayedItems(),
		CashMultiplierLevel = cashMultiplierLevel,
		Rebirths = rebirths,
		IndexMultiplier = indexMultiplier,
		EventGeneratorMultiplier = EventState.GetGeneratorMultiplier(),
		PassMultiplier = ShopConfig.GetPassIncomeMultiplier(shop.OwnedPasses),
		BoostMultiplier = if TycoonController.GetBoostSecondsLeft("Income") > 0 then ShopConfig.BoostMultiplier else 1,
		OverclockMultiplier = ShopState.GetOverclockMultiplier(),
		FriendMultiplier = FriendConfig.GetMultiplier(friendCount),
	}
end

-- The gacha price cap's base, from the client's own state (the server charges
-- its own; a mismatch lasts until the next sync).
function TycoonController.GetSteadyIncomePerSecond(): number
	return TycoonConfig.GetSteadyIncomePerSecond(TycoonController.GetIncomeInputs())
end

--[[ Shop (read-only view of the server's state) ]]

function TycoonController.GetShop(): ShopView
	return shop
end

-- This visit's play time (seconds, counting on between snapshots) and the
-- claimed gift indices.
function TycoonController.GetGiftPlaySeconds(): number
	return giftPlaySeconds + (os.clock() - giftReceivedAt)
end

function TycoonController.GetClaimedGifts(): { number }
	return giftClaimed
end

function TycoonController.GetDaily(): DailyView
	return daily
end

function TycoonController.OwnsPass(key: string): boolean
	return shop.OwnedPasses[key] == true
end

-- Seconds left on a timed boost ("Income" | "Luck"), counted down locally.
function TycoonController.GetBoostSecondsLeft(kind: "Income" | "Luck"): number
	local base = if kind == "Income" then shop.IncomeBoostSeconds else shop.LuckBoostSeconds
	return math.max(0, base - (os.clock() - shop.ReceivedAt))
end

-- The shop's luck multiplier (Lucky pass x an active Luck Potion), for
-- displays; the server's PlayerDataService.GetLuck is what rolls use.
function TycoonController.GetShopLuckMultiplier(): number
	return ShopConfig.GetLuckMultiplier(shop.OwnedPasses, TycoonController.GetBoostSecondsLeft("Luck"))
end

-- The pedestals you can use, in auto-display's fill order (the server's
-- PlayerDataService.GetPedestalOrder): 1-4, 5-6 with the pass, 7-10 from
-- Rebirth 2.
function TycoonController.GetPedestalOrder(): { number }
	return PlotLayout.GetPedestalOrder(
		ShopConfig.GetPedestalCount(shop.OwnedPasses) > ShopConfig.BasePedestals,
		RebirthConfig.HasSecondFloor(rebirths)
	)
end

-- 4 / 6 / 8 / 10.
function TycoonController.GetPedestalCount(): number
	return #TycoonController.GetPedestalOrder()
end

-- Pad x rebirth: the multiplier every per-generator/per-item number shows.
function TycoonController.GetIncomeMultiplier(): number
	return TycoonConfig.GetIncomeMultiplier(TycoonController.GetIncomeInputs())
end

-- Called by UI when the player clicks the upgrade button for `generatorId`.
-- Fire-and-forget: does not yield, and returns immediately.
function TycoonController.RequestUpgrade(generatorId: string): boolean
	if pendingUpgrades[generatorId] then
		return false
	end

	pendingUpgrades[generatorId] = true
	RemoteEvents.RequestUpgrade:FireServer(generatorId)
	return true
end

-- MAX ×N (`generatorId`) or MAX ALL (nil). Fire-and-forget; false while a
-- previous MAX hasn't answered yet.
function TycoonController.RequestUpgradeMax(generatorId: string?): boolean
	if pendingMax then
		return false
	end
	pendingMax = true
	RemoteEvents.RequestUpgradeMax:FireServer(if generatorId then { GeneratorId = generatorId } else { All = true })
	return true
end

local function onSyncTycoon(snapshot: any)
	cash = snapshot.Cash
	generatorLevels = snapshot.Generators or {}
	cashMultiplierLevel = snapshot.CashMultiplierLevel or 0
	gachaPulls = snapshot.GachaPulls or 0
	secretPity = if typeof(snapshot.SecretPity) == "number" then snapshot.SecretPity else 0
	serverLuck = if typeof(snapshot.Luck) == "number" then snapshot.Luck else 1
	luckBase = if typeof(snapshot.LuckBase) == "number" then snapshot.LuckBase else serverLuck
	rebirths = if typeof(snapshot.Rebirths) == "number" then snapshot.Rebirths else 0
	friendCount = if typeof(snapshot.Friends) == "number" then FriendConfig.ClampCount(snapshot.Friends) else 0
	indexFound = {}
	if typeof(snapshot.IndexKeys) == "table" then
		for _, key in snapshot.IndexKeys do
			if typeof(key) == "string" then
				indexFound[key] = true
			end
		end
	end
	indexMultiplier = IndexConfig.GetMultiplier(indexFound)
	goalIndex = if typeof(snapshot.GoalIndex) == "number" then snapshot.GoalIndex else nil
	local progress = snapshot.GoalProgress
	goalProgress = if typeof(progress) == "table"
			and typeof(progress.Current) == "number"
			and typeof(progress.Target) == "number"
		then { Current = progress.Current, Target = progress.Target }
		else nil
	-- Remote tables with numeric keys can arrive keyed by strings; normalise.
	pedestalDisplays = {}
	local displayedUids: { [string]: boolean } = {}
	for key, uid in snapshot.PedestalDisplays or {} do
		local index = tonumber(key)
		if index then
			pedestalDisplays[index] = uid
			displayedUids[uid] = true
		end
	end
	InventoryController.SetDisplayedUids(displayedUids)
	if typeof(snapshot.TipKeys) == "table" then
		-- The server's set, plus marks it hasn't echoed yet (so a snapshot
		-- already in flight can't make a tip show twice). /tips reset sends
		-- an empty set, which clears everything already confirmed.
		local fresh: { [string]: boolean } = {}
		for _, id in snapshot.TipKeys do
			if typeof(id) == "string" then
				fresh[id] = true
			end
		end
		for id in pendingTipMarks do
			if fresh[id] then
				pendingTipMarks[id] = nil
			else
				fresh[id] = true
			end
		end
		tipsSeen = fresh
	end
	if typeof(snapshot.Weapons) == "table" then
		local fresh: { string } = {}
		for _, id in snapshot.Weapons do
			if typeof(id) == "string" then
				table.insert(fresh, id)
			end
		end
		table.sort(fresh)
		weapons = fresh
	end
	if typeof(snapshot.Quests) == "table" then
		quests = snapshot.Quests
	end
	if typeof(snapshot.PowerUps) == "table" then
		local fresh: { [string]: number } = {}
		for key, count in snapshot.PowerUps do
			if typeof(key) == "string" and typeof(count) == "number" then
				fresh[key] = count
			end
		end
		powerUps = fresh
	end
	if typeof(snapshot.Armed) == "table" then
		local fresh: { [string]: boolean } = {}
		for _, key in snapshot.Armed do
			if typeof(key) == "string" then
				fresh[key] = true
			end
		end
		armed = fresh
	end
	local rawTutorial = snapshot.Tutorial
	if typeof(rawTutorial) == "table" then
		local wasActive = hasSynced and not tutorial.Done
		if rawTutorial.Done == true then
			if wasActive then
				tutorialDoneAt = os.clock()
			end
		else
			tutorialDoneAt = nil
		end
		tutorial = {
			Step = if typeof(rawTutorial.Step) == "number" then rawTutorial.Step else 0,
			Done = rawTutorial.Done == true,
			FreePulls = if typeof(rawTutorial.FreePulls) == "number" then rawTutorial.FreePulls else 0,
			PullsDone = if typeof(rawTutorial.PullsDone) == "number" then rawTutorial.PullsDone else 0,
			Replay = rawTutorial.Replay == true,
			ReplayHint = rawTutorial.ReplayHint == true,
		}
	end
	carriedUids = {}
	if typeof(snapshot.CarriedUids) == "table" then
		for _, uid in snapshot.CarriedUids do
			if typeof(uid) == "string" then
				carriedUids[uid] = true
			end
		end
	end
	InventoryController.SetCarriedUids(carriedUids)
	local settings = SettingsConfig.Sanitize(snapshot.Settings)
	local rule = settings.RevealRule
	for tier, value in pendingReveal do
		if rule[tier] == value then
			pendingReveal[tier] = nil
		else
			rule[tier] = value -- not echoed yet: keep the local choice
		end
	end
	revealRule = rule
	-- Sound: keep a local change until the snapshot echoes it.
	if pendingSfxVolume ~= nil and math.abs(settings.SfxVolume - pendingSfxVolume) < 1e-4 then
		pendingSfxVolume = nil
	end
	if pendingSfxMuted ~= nil and settings.SfxMuted == pendingSfxMuted then
		pendingSfxMuted = nil
	end
	if pendingMusicVolume ~= nil and math.abs(settings.MusicVolume - pendingMusicVolume) < 1e-4 then
		pendingMusicVolume = nil
	end
	if pendingMusicOn ~= nil and settings.MusicOn == pendingMusicOn then
		pendingMusicOn = nil
	end
	if pendingAutoFuse ~= nil and settings.AutoFuse == pendingAutoFuse then
		pendingAutoFuse = nil
	end
	if pendingGoalPath ~= nil and settings.GoalPath == pendingGoalPath then
		pendingGoalPath = nil
	end
	goalPath = pendingGoalPath or settings.GoalPath
	if pendingAutoFuse ~= nil then
		autoFuse = pendingAutoFuse
	else
		autoFuse = settings.AutoFuse
	end
	sfxVolume = if pendingSfxVolume ~= nil then pendingSfxVolume else settings.SfxVolume
	if pendingSfxMuted ~= nil then
		sfxMuted = pendingSfxMuted
	else
		sfxMuted = settings.SfxMuted
	end
	applySfx()
	musicVolume = if pendingMusicVolume ~= nil then pendingMusicVolume else settings.MusicVolume
	musicOn = if pendingMusicOn ~= nil then pendingMusicOn else settings.MusicOn
	pendingOffline = if typeof(snapshot.PendingOffline) == "number" then snapshot.PendingOffline else 0
	awaySeconds = if typeof(snapshot.AwaySeconds) == "number" then snapshot.AwaySeconds else 0
	local rawShop = snapshot.Shop
	if typeof(rawShop) == "table" then
		local owned: { [string]: boolean } = {}
		for _, key in (if typeof(rawShop.OwnedPasses) == "table" then rawShop.OwnedPasses else {}) do
			if typeof(key) == "string" then
				owned[key] = true
			end
		end
		local cosmetics: { [string]: boolean } = {}
		for _, key in (if typeof(rawShop.Cosmetics) == "table" then rawShop.Cosmetics else {}) do
			if typeof(key) == "string" then
				cosmetics[key] = true
			end
		end
		local function number(value: any): number
			return if typeof(value) == "number" then value else 0
		end
		shop = {
			OwnedPasses = owned,
			Restricted = rawShop.Restricted ~= false,
			IncomeBoostSeconds = number(rawShop.IncomeBoostSeconds),
			LuckBoostSeconds = number(rawShop.LuckBoostSeconds),
			SafeFusionTokens = number(rawShop.SafeFusionTokens),
			StarterPackBought = rawShop.StarterPackBought == true,
			Cosmetics = cosmetics,
			Sessions = number(rawShop.Sessions),
			DealPopupSlot = number(rawShop.DealPopupSlot),
			OfflineDoubleAmount = number(rawShop.OfflineDoubleAmount),
			ReceivedAt = os.clock(),
		}
	end
	local rawGifts = snapshot.Gifts
	if typeof(rawGifts) == "table" then
		giftPlaySeconds = if typeof(rawGifts.PlaySeconds) == "number" then rawGifts.PlaySeconds else 0
		giftReceivedAt = os.clock()
		giftClaimed = {}
		for _, index in (if typeof(rawGifts.Claimed) == "table" then rawGifts.Claimed else {}) do
			if typeof(index) == "number" then
				table.insert(giftClaimed, index)
			end
		end
	end
	local rawDaily = snapshot.Daily
	if typeof(rawDaily) == "table" then
		local function int(value: any, fallback: number): number
			return if typeof(value) == "number" then value else fallback
		end
		daily = {
			CanClaim = rawDaily.CanClaim == true,
			Day = int(rawDaily.Day, 1),
			Streak = int(rawDaily.Streak, 0),
			Skips = int(rawDaily.Skips, 0),
			UsesSkip = rawDaily.UsesSkip == true,
			Resets = rawDaily.Resets == true,
			LastDay = int(rawDaily.LastDay, 0),
		}
	end
	hasSynced = true
	tycoonChanged:Fire(cash, generatorLevels)
end

local function onUpgradeResult(result: any)
	if result.GeneratorId then
		pendingUpgrades[result.GeneratorId] = nil
	end
	upgradeResolved:Fire(result)
end

function TycoonController.Init()
	RemoteEvents.SyncTycoon.OnClientEvent:Connect(onSyncTycoon)
	RemoteEvents.UpgradeResult.OnClientEvent:Connect(onUpgradeResult)
	RemoteEvents.UpgradeMaxResult.OnClientEvent:Connect(function(result: any)
		pendingMax = false
		upgradeMaxResolved:Fire(result)
	end)
end

return TycoonController
