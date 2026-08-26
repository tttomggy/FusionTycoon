local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "RemoteEvents"

local REMOTE_EVENT_NAMES = {
	"RequestFusion", -- client -> server: attempt to fuse two owned items (by Uid)
	"FusionResult", -- server -> client: validated outcome of a fusion attempt
	"SyncInventory", -- server -> client: authoritative full inventory snapshot
	"RequestUpgrade", -- client -> server: attempt to upgrade a generator
	"UpgradeResult", -- server -> client: validated outcome of an upgrade attempt
	"SyncTycoon", -- server -> client: authoritative cash + generator-level snapshot
	"RequestPlaceItem", -- client -> server: attempt to display an owned item (by Uid) on one of the player's own pedestals
	"PlaceItemResult", -- server -> client: validated outcome of a place-item attempt
	"RareFusionAnnouncement", -- server -> all clients: a Legendary/Mythic item was just displayed
	"MultiplierUpgraded", -- server -> client: the local player's cash multiplier purchase succeeded
}

local function getOrCreateFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

local function getOrCreateRemoteEvent(folder: Folder, name: string): RemoteEvent
	local remote = folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	return remote :: RemoteEvent
end

-- Populated once at require-time: the server creates each RemoteEvent, the
-- client waits for the server to have created it. Either side then references
-- the events directly, e.g. RemoteEvents.RequestFusion:FireServer(tier).
local RemoteEvents: { [string]: RemoteEvent } = {}

local folder = getOrCreateFolder()
local isServer = RunService:IsServer()

for _, name in REMOTE_EVENT_NAMES do
	if isServer then
		RemoteEvents[name] = getOrCreateRemoteEvent(folder, name)
	else
		RemoteEvents[name] = folder:WaitForChild(name) :: RemoteEvent
	end
end

return RemoteEvents
