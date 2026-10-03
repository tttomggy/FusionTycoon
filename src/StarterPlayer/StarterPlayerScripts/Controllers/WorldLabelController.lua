--[[
	WorldLabelController
	--------------------
	Hides world labels and prompts that only a plot's owner should see - the
	CLAIM label, the EMPTY pedestal labels and the pedestal DisplayPrompts
	(all marked OwnerOnly) - on every plot that isn't the local player's.

	The server toggles the EMPTY label's Enabled as items are placed and
	removed, which would replicate over a one-off local change, so this keeps
	re-disabling it whenever Enabled flips back on.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)

local WorldLabelController = {}

local localUserId = Players.LocalPlayer.UserId
local watched: { [Instance]: boolean } = {}

local function getOwnerUserId(instance: Instance): number?
	local current: Instance? = instance
	while current do
		local owner = current:GetAttribute("OwnerUserId")
		if typeof(owner) == "number" then
			return owner
		end
		current = current.Parent
	end
	return nil
end

-- Keeps `target.Enabled` false on this client, even when the server flips
-- it back on (the EMPTY label toggles as items come and go).
local function keepDisabled(target: any) -- a BillboardGui or ProximityPrompt
	watched[target] = true
	target.Enabled = false
	target:GetPropertyChangedSignal("Enabled"):Connect(function()
		if target.Enabled then
			target.Enabled = false
		end
	end)
	target.Destroying:Connect(function()
		watched[target] = nil
	end)
end

-- Owner-only labels and prompts on someone else's plot are hidden here; the
-- server can't hide them per player.
local function consider(instance: Instance)
	if watched[instance] or not (instance:IsA("BillboardGui") or instance:IsA("ProximityPrompt")) then
		return
	end
	if instance:GetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE) ~= true then
		return
	end
	local owner = getOwnerUserId(instance)
	if owner == nil or owner == localUserId then
		return
	end
	keepDisabled(instance)
end

function WorldLabelController.Init()
	local plots = Workspace:WaitForChild(PlotNaming.PlotsFolderName)
	for _, descendant in plots:GetDescendants() do
		consider(descendant)
	end
	plots.DescendantAdded:Connect(consider)
end

return WorldLabelController
