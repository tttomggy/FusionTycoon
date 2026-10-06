local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)

local InventoryController = {}

-- Local cache of the server's authoritative inventory; never mutated optimistically.
local inventory: { any } = {}
-- Uids on a pedestal per the latest tycoon snapshot (TycoonController feeds
-- it). IsInUse trusts either source, so a stale item.InUse can never offer
-- a displayed copy.
local displayedUids: { [string]: boolean } = {}
-- Uids a thief is carrying right now (snapshot CarriedUids): the only
-- items that can't go into the machine (displayed ones can: the pedestals
-- re-arrange themselves after the fusion).
local carriedUids: { [string]: boolean } = {}

local inventoryChanged = Instance.new("BindableEvent")
InventoryController.InventoryChanged = inventoryChanged.Event

function InventoryController.GetInventory(): { any }
	return inventory
end

-- On a pedestal: the inventory's InUse flag OR the snapshot's PedestalDisplays.
-- Every client check for "free" goes through this, never item.InUse alone.
function InventoryController.IsInUse(item: any): boolean
	return item.InUse == true or displayedUids[item.Uid] == true
end

function InventoryController.IsCarried(item: any): boolean
	return carriedUids[item.Uid] == true
end

function InventoryController.SetCarriedUids(uids: { [string]: boolean })
	carriedUids = uids
end

-- Called by TycoonController with the snapshot's displayed Uids; fires
-- InventoryChanged when the set changes so open pickers refresh.
function InventoryController.SetDisplayedUids(uids: { [string]: boolean })
	local changed = false
	for uid in uids do
		if not displayedUids[uid] then
			changed = true
		end
	end
	for uid in displayedUids do
		if not uids[uid] then
			changed = true
		end
	end
	displayedUids = uids
	if changed then
		inventoryChanged:Fire(inventory)
	end
end

function InventoryController.GetItemsByTier(tier: string): { any }
	local results = {}
	for _, item in inventory do
		if item.Tier == tier then
			table.insert(results, item)
		end
	end
	return results
end

-- Items of `tier` that can go into the Fusion Machine: anything a thief
-- isn't carrying (displayed items too: the pedestals re-fill themselves).
-- Sorted normal first, then by mutation rank, so the machine pairs plain
-- items before it touches a mutated one; spare copies before displayed ones.
function InventoryController.GetFusableItemsByTier(tier: string): { any }
	local results = {}
	for _, item in inventory do
		if item.Tier == tier and not InventoryController.IsCarried(item) then
			table.insert(results, item)
		end
	end
	table.sort(results, function(a, b)
		local rankA, rankB = MutationConfig.GetRank(a.Mutation), MutationConfig.GetRank(b.Mutation)
		if rankA ~= rankB then
			return rankA < rankB
		end
		local shownA, shownB = InventoryController.IsInUse(a), InventoryController.IsInUse(b)
		if shownA ~= shownB then
			return shownB
		end
		return a.Uid < b.Uid
	end)
	return results
end

-- Fusable items Fuse All may use: unmutated only (mutated items are never
-- auto-fused).
function InventoryController.GetFuseAllItemsByTier(tier: string): { any }
	local results = {}
	for _, item in InventoryController.GetFusableItemsByTier(tier) do
		if item.Mutation == nil then
			table.insert(results, item)
		end
	end
	return results
end

function InventoryController.CountItemsOfTier(tier: string): number
	local count = 0
	for _, item in inventory do
		if item.Tier == tier then
			count += 1
		end
	end
	return count
end

-- Every item not currently displayed on a pedestal (or otherwise in use) -
-- the candidate list both the pedestal item picker and the persistent
-- Inventory button's browse view draw from.
function InventoryController.GetDisplayableItems(): { any }
	local displayable = {}
	for _, item in inventory do
		if not InventoryController.IsInUse(item) then
			table.insert(displayable, item)
		end
	end
	return displayable
end

local function onSyncInventory(newInventory: { any })
	inventory = newInventory
	inventoryChanged:Fire(inventory)
end

function InventoryController.Init()
	RemoteEvents.SyncInventory.OnClientEvent:Connect(onSyncInventory)
end

return InventoryController
