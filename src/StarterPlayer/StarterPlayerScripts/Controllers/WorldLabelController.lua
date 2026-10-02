--[[
	WorldLabelController
	--------------------
	Hides world labels that only a plot's owner should see - the CLAIM label
	and the EMPTY pedestal labels (BillboardKit marks them OwnerOnly) - on
	every plot that isn't the local player's.

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
local watched: { [BillboardGui]: boolean } = {}

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

local function consider(instance: Instance)
	if not instance:IsA("BillboardGui") or watched[instance] then
		return
	end
	if instance:GetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE) ~= true then
		return
	end
	local owner = getOwnerUserId(instance)
	if owner == nil or owner == localUserId then
		return
	end

	local gui = instance :: BillboardGui
	watched[gui] = true
	gui.Enabled = false
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			gui.Enabled = false
		end
	end)
	gui.Destroying:Connect(function()
		watched[gui] = nil
	end)
end

function WorldLabelController.Init()
	local plots = Workspace:WaitForChild(PlotNaming.PlotsFolderName)
	for _, descendant in plots:GetDescendants() do
		consider(descendant)
	end
	plots.DescendantAdded:Connect(consider)
end

return WorldLabelController
