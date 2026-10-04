local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local SettingsConfig = require(ReplicatedStorage.Shared.Config.SettingsConfig)
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
local goalIndex: number? = nil
local goalProgress: { Current: number, Target: number }? = nil
local hasSynced = false
local rebirths = 0
local indexFound: { [string]: boolean } = {}
local indexMultiplier = 1
local pendingOffline = 0
-- Uids of displayed items a thief is carrying: they earn nothing meanwhile.
local carriedUids: { [string]: boolean } = {}
-- One-time tips/cards already seen (saved; TipConfig ids).
local tipsSeen: { [string]: boolean } = {}
-- Marked here but not yet echoed back by a snapshot.
local pendingTipMarks: { [string]: boolean } = {}
local awaySeconds = 0
-- Settings (SettingsConfig): the server's copy plus local changes it hasn't
-- echoed yet (optimistic: they apply at once).
local revealRule: SettingsConfig.RevealRule = SettingsConfig.GetDefaultRevealRule()
local pendingReveal: { [string]: string } = {}
local sfxVolume = SettingsConfig.DefaultSfxVolume
local sfxMuted = false
-- Local sound changes not echoed yet (nil = none pending).
local pendingSfxVolume: number? = nil
local pendingSfxMuted: boolean? = nil

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
	for _, uid in pedestalDisplays do
		local item = byUid[uid]
		if item and not carriedUids[uid] then
			table.insert(items, { Tier = item.Tier, Mutation = item.Mutation })
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
	}
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
	rebirths = if typeof(snapshot.Rebirths) == "number" then snapshot.Rebirths else 0
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
	carriedUids = {}
	if typeof(snapshot.CarriedUids) == "table" then
		for _, uid in snapshot.CarriedUids do
			if typeof(uid) == "string" then
				carriedUids[uid] = true
			end
		end
	end
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
	sfxVolume = if pendingSfxVolume ~= nil then pendingSfxVolume else settings.SfxVolume
	if pendingSfxMuted ~= nil then
		sfxMuted = pendingSfxMuted
	else
		sfxMuted = settings.SfxMuted
	end
	applySfx()
	pendingOffline = if typeof(snapshot.PendingOffline) == "number" then snapshot.PendingOffline else 0
	awaySeconds = if typeof(snapshot.AwaySeconds) == "number" then snapshot.AwaySeconds else 0
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
