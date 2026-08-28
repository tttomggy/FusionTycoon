local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

local InventoryController = {}

-- Local cache of the server's authoritative inventory; never mutated optimistically.
local inventory: { any } = {}

local inventoryChanged = Instance.new("BindableEvent")
InventoryController.InventoryChanged = inventoryChanged.Event

function InventoryController.GetInventory(): { any }
	return inventory
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
		if not item.InUse then
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
