local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
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

local tycoonChanged = Instance.new("BindableEvent")
TycoonController.TycoonChanged = tycoonChanged.Event

-- Fires only once the server has validated the purchase attempt.
local upgradeResolved = Instance.new("BindableEvent")
TycoonController.UpgradeResolved = upgradeResolved.Event

-- Guards per-generator so a pending purchase on one doesn't block clicks on another.
local pendingUpgrades: { [string]: boolean } = {}

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

-- False until the first snapshot arrives (so the HUD doesn't flash $0).
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

-- Tiers of the items on this player's pedestals (from the inventory cache).
function TycoonController.GetDisplayedTiers(): { string }
	local byUid: { [string]: any } = {}
	for _, item in InventoryController.GetInventory() do
		byUid[item.Uid] = item
	end
	local tiers = {}
	for _, uid in pedestalDisplays do
		local item = byUid[uid]
		if item then
			table.insert(tiers, item.Tier)
		end
	end
	return tiers
end

-- The one place the client builds TycoonConfig.IncomeInputs.
function TycoonController.GetIncomeInputs(): TycoonConfig.IncomeInputs
	return {
		GeneratorLevels = generatorLevels,
		PedestalTiers = TycoonController.GetDisplayedTiers(),
		CashMultiplierLevel = cashMultiplierLevel,
		Rebirths = 0, -- Rebirth data lands with RebirthService
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

local function onSyncTycoon(snapshot: any)
	cash = snapshot.Cash
	generatorLevels = snapshot.Generators or {}
	cashMultiplierLevel = snapshot.CashMultiplierLevel or 0
	gachaPulls = snapshot.GachaPulls or 0
	goalIndex = if typeof(snapshot.GoalIndex) == "number" then snapshot.GoalIndex else nil
	local progress = snapshot.GoalProgress
	goalProgress = if typeof(progress) == "table"
			and typeof(progress.Current) == "number"
			and typeof(progress.Target) == "number"
		then { Current = progress.Current, Target = progress.Target }
		else nil
	-- Remote tables with numeric keys can arrive keyed by strings; normalise.
	pedestalDisplays = {}
	for key, uid in snapshot.PedestalDisplays or {} do
		local index = tonumber(key)
		if index then
			pedestalDisplays[index] = uid
		end
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
end

return TycoonController
