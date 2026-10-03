--[[
	WorldLabelController
	--------------------
	Hides world labels and prompts that only a plot's owner should see - the
	CLAIM label, the EMPTY pedestal labels and the pedestal DisplayPrompts
	(all marked OwnerOnly) - on every plot that isn't the local player's.

	The server toggles the EMPTY label's Enabled as items are placed and
	removed, which would replicate over a one-off local change, so this keeps
	re-disabling it whenever Enabled flips back on.

	Heist StealPrompts (EnemyOnly) start disabled everywhere and are enabled
	here, re-checked every STEAL_CHECK_SECONDS, only when: the viewer isn't
	the owner, the viewer has HeistConfig.MinRebirths (leaderstats), the lab
	isn't Protected (owner under MinRebirths) or shielded (ShieldUntil), the
	pedestal is Filled and not BeingStolen, and the viewer isn't already
	carrying. A pedestal the owner is guarding (GuardedByOwner) shows "Owner
	is guarding" instead of a hold. The server re-checks all of it on
	RequestSteal.

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
local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)

local WorldLabelController = {}

local HIDE_NEAR_STUDS = 7
local SHOW_FAR_STUDS = 8
local STEAL_CHECK_SECONDS = 0.25

local localPlayer = Players.LocalPlayer
local localUserId = localPlayer.UserId
local watched: { [Instance]: boolean } = {}
-- Every plot BillboardGui -> whether it's currently hidden for being close.
local proximityLabels: { [BillboardGui]: boolean } = {}
-- Every pedestal StealPrompt (EnemyOnly) on any plot.
local stealPrompts: { [ProximityPrompt]: boolean } = {}
-- This player's own pedestal DisplayPrompts: off while a thief carries that
-- pedestal's item (BeingStolen), so it can't be picked up mid-heist.
local ownDisplayPrompts: { [ProximityPrompt]: boolean } = {}
local stealCheckAccumulator = 0

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

local function getLocalRebirths(): number
	local leaderstats = localPlayer:FindFirstChild("leaderstats")
	local value = leaderstats and leaderstats:FindFirstChild("Rebirths")
	return if value and value:IsA("IntValue") then value.Value else 0
end

local function findPlot(instance: Instance): Instance?
	local current: Instance? = instance
	while current and current.Parent do
		if current:GetAttribute("SlotIndex") ~= nil then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- What a StealPrompt shows on this client (the prompt's local "Mode"
-- attribute; HeistController reads it on trigger):
--   Hidden   not stealable for this viewer (own lab, empty, shielded, ...)
--   Guarded  the owner is standing guard: "Owner is guarding", instant tap
--            that only toasts, so the thief doesn't waste the 1.5 s hold
--   Steal    "Steal" / item, hold to grab
export type StealMode = "Hidden" | "Guarded" | "Steal"

local function stealMode(prompt: ProximityPrompt, viewerRebirths: number, viewerCarrying: boolean): StealMode
	local owner = prompt:GetAttribute("OwnerUserId")
	if owner == localUserId or viewerCarrying or viewerRebirths < HeistConfig.MinRebirths then
		return "Hidden"
	end
	local pedestal = prompt.Parent
	if not pedestal or pedestal:GetAttribute("Filled") ~= true or pedestal:GetAttribute("BeingStolen") == true then
		return "Hidden"
	end
	local plot = findPlot(prompt)
	if not plot or plot:GetAttribute("Protected") ~= false then
		return "Hidden"
	end
	local shieldUntil = plot:GetAttribute("ShieldUntil")
	if typeof(shieldUntil) == "number" and shieldUntil > Workspace:GetServerTimeNow() then
		return "Hidden"
	end
	if pedestal:GetAttribute("GuardedByOwner") == true then
		return "Guarded"
	end
	return "Steal"
end

local function applyStealMode(prompt: ProximityPrompt, mode: StealMode)
	if prompt:GetAttribute("Mode") == mode then
		return
	end
	prompt:SetAttribute("Mode", mode)
	prompt.Enabled = mode ~= "Hidden"
	if mode == "Guarded" then
		prompt.ActionText = "Owner is guarding"
		prompt.HoldDuration = 0
	else
		prompt.ActionText = "Steal"
		prompt.HoldDuration = HeistConfig.GrabHoldSeconds
	end
end

local function updateStealPrompts()
	local rebirths = getLocalRebirths()
	local carrying = localPlayer:GetAttribute("HeistTier") ~= nil
	for prompt in stealPrompts do
		applyStealMode(prompt, stealMode(prompt, rebirths, carrying))
	end
	for prompt in ownDisplayPrompts do
		local pedestal = prompt.Parent
		local enabled = not (pedestal and pedestal:GetAttribute("BeingStolen") == true)
		if prompt.Enabled ~= enabled then
			prompt.Enabled = enabled
		end
	end
end

local function trackStealPrompt(prompt: ProximityPrompt)
	if stealPrompts[prompt] ~= nil then
		return
	end
	stealPrompts[prompt] = true
	prompt.Enabled = false
	prompt:SetAttribute("Mode", "Hidden")
	prompt.Destroying:Connect(function()
		stealPrompts[prompt] = nil
	end)
end

-- Owner-only labels and prompts on someone else's plot are hidden here; the
-- server can't hide them per player.
local function consider(instance: Instance)
	if instance:IsA("ProximityPrompt") and instance:GetAttribute("EnemyOnly") == true then
		trackStealPrompt(instance)
		return
	end
	if instance:IsA("ProximityPrompt") and instance.Name == "DisplayPrompt" and getOwnerUserId(instance) == localUserId then
		local prompt = instance
		ownDisplayPrompts[prompt] = true
		prompt.Destroying:Connect(function()
			ownDisplayPrompts[prompt] = nil
		end)
	end
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
	RunService.Heartbeat:Connect(function(dt: number)
		stealCheckAccumulator += dt
		if stealCheckAccumulator >= STEAL_CHECK_SECONDS then
			stealCheckAccumulator = 0
			updateStealPrompts()
		end
	end)
end

return WorldLabelController
