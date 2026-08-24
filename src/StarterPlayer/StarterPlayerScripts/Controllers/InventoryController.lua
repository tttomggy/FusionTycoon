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

local function onSyncInventory(newInventory: { any })
	inventory = newInventory
	inventoryChanged:Fire(inventory)
end

function InventoryController.Init()
	RemoteEvents.SyncInventory.OnClientEvent:Connect(onSyncInventory)
end

return InventoryController
