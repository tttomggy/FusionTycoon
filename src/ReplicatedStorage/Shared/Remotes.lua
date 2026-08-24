local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local function getOrCreateFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

-- Server creates RemoteEvents on demand; clients wait for the server to create them.
function Remotes.Get(name: string): RemoteEvent
	local folder = getOrCreateFolder()

	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		return remote :: RemoteEvent
	end

	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
