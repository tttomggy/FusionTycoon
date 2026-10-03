--[[
	WorldLabelController
	--------------------
	Hides world labels and prompts that only a plot's owner should see - the
	CLAIM label, the EMPTY pedestal labels and the pedestal DisplayPrompts
	(all marked OwnerOnly) - on every plot that isn't the local player's.

	The server toggles the EMPTY label's Enabled as items are placed and
	removed, which would replicate over a one-off local change, so this keeps
	re-disabling it whenever Enabled flips back on.

	It also hides every plot BillboardGui (pedestal and pad labels) drawn
	within HIDE_NEAR_STUDS of the camera, showing it again past
	SHOW_FAR_STUDS (the gap stops flicker), so a label can't fill the screen
	up close. That uses PlayerToHideFrom, set locally: the server never
	touches it, so it can't fight the Enabled toggling above.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)

local WorldLabelController = {}

local HIDE_NEAR_STUDS = 7
local SHOW_FAR_STUDS = 8

local localPlayer = Players.LocalPlayer
local localUserId = localPlayer.UserId
local watched: { [Instance]: boolean } = {}
-- Every plot BillboardGui -> whether it's currently hidden for being close.
local proximityLabels: { [BillboardGui]: boolean } = {}

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

-- Where the label is drawn: its adornee (Adornee, or the part/attachment
-- it's parented to) plus its studs offset. Measuring to the label rather
-- than the bare part matters for pedestal labels, which float 8+ studs up.
local function getAnchorPosition(gui: BillboardGui): Vector3?
	local anchor = gui.Adornee or gui.Parent
	local base: Vector3
	if anchor and anchor:IsA("BasePart") then
		base = anchor.Position
	elseif anchor and anchor:IsA("Attachment") then
		base = anchor.WorldPosition
	else
		return nil
	end
	return base + gui.StudsOffsetWorldSpace + gui.StudsOffset
end

local function trackProximity(gui: BillboardGui)
	if proximityLabels[gui] ~= nil then
		return
	end
	proximityLabels[gui] = false
	gui.Destroying:Connect(function()
		proximityLabels[gui] = nil
	end)
end

local function updateProximity()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	for gui, hidden in proximityLabels do
		local position = getAnchorPosition(gui)
		if position then
			local distance = (position - cameraPosition).Magnitude
			local hide = if hidden then distance <= SHOW_FAR_STUDS else distance < HIDE_NEAR_STUDS
			if hide ~= hidden then
				proximityLabels[gui] = hide
				gui.PlayerToHideFrom = if hide then localPlayer else nil
			end
		end
	end
end

-- Owner-only labels and prompts on someone else's plot are hidden here; the
-- server can't hide them per player.
local function consider(instance: Instance)
	if instance:IsA("BillboardGui") then
		trackProximity(instance)
	end
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
	RunService.Heartbeat:Connect(updateProximity)
end

return WorldLabelController
