local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local RevealEffects = require(script.Parent.Parent.Effects.RevealEffects)
local InventoryController = require(script.Parent.InventoryController)
local TycoonController = require(script.Parent.TycoonController)
local ToastController = require(script.Parent.ToastController)

local FusionController = {}

local MACHINE_NAME = "FusionMachine"
local CHARGE_DURATION_SECONDS = 2.2
local FUSE_ALL_CHARGE_SECONDS = 3

-- Guards against double-firing while a request is in flight; the server is
-- still the final authority (it has its own cooldown check independently).
local isRequestPending = false

-- Set only by onFusionResult; the request loop below polls it instead of
-- holding its own one-shot connection, so a stray/duplicate FusionResult
-- can never leave a dangling listener.
local pendingResult: any = nil

-- Set only by onFuseAllResult; RequestFuseAll waits on it the same way.
local pendingFuseAllResult: any = nil

local fuseAllResolved = Instance.new("BindableEvent")
-- Fires (summary) once a Fuse All has resolved and its charge-up finished.
FusionController.FuseAllResolved = fuseAllResolved.Event

local fusionResolved = Instance.new("BindableEvent")
-- Fires only once the server has validated the attempt AND the reveal effect
-- (if any) has finished playing. UI code should hook this, never react at
-- the moment a fuse is requested.
FusionController.FusionResolved = fusionResolved.Event

local core: BasePart? = nil
local ring: BasePart? = nil
local prompt: ProximityPrompt? = nil
-- The prompts live here (platform centre), not on the Core up in the air.
local promptAnchor: BasePart? = nil

-- The last fusion asked for, so the fail card's AGAIN can repeat it.
local lastTier: string? = nil
local lastCount = 0

-- Up to `count` (default MaxFusionInputs) unmutated, not-displayed items
-- of `tier`, as Uids: what AUTO-FILL and AGAIN put in. Never mutated ones.
function FusionController.GetAutoFill(tier: string, count: number?): { string }
	local wanted = count or FusionConfig.MaxFusionInputs
	local uids = {}
	for _, item in InventoryController.GetFuseAllItemsByTier(tier) do
		if #uids >= wanted then
			break
		end
		table.insert(uids, item.Uid)
	end
	return uids
end

function FusionController.IsRequestPending(): boolean
	return isRequestPending
end

-- True while the last fusion could be repeated right now: nothing in
-- flight, enough unmutated items of that tier for the same count, and the
-- local character within the machine prompt's reach. Drives the fail
-- card's AGAIN button.
function FusionController.CanRequestFusion(): boolean
	local tier = lastTier
	if isRequestPending or not core or not prompt or not tier then
		return false
	end
	if not FusionConfig.CanFuseTierFor(tier, TycoonController.GetRebirths()) then
		return false
	end
	if #FusionController.GetAutoFill(tier, lastCount) < lastCount then
		return false
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local reach = (prompt :: ProximityPrompt).MaxActivationDistance
	local anchor = promptAnchor or core :: BasePart
	return (root.Position - anchor.Position).Magnitude <= reach
end

-- Fuses `uids` (2-6 same-tier items; the server validates everything),
-- or with no argument repeats the last fusion's tier and count with
-- unmutated items (AGAIN). Plays the machine's charge-up and reveal, then
-- fires FusionResolved. Yields for the whole cycle; call it with task.spawn.
-- Carrying a stolen item (HeistService sets Heist* attributes): hands full.
-- The server rejects it too; this just skips the charge-up.
local function blockedByHeist(): boolean
	if Players.LocalPlayer:GetAttribute("HeistTier") ~= nil then
		ToastController.Show("Get home with that item first!", "Neutral")
		return true
	end
	return false
end

local function requestFusion(uids: { string }?)
	if isRequestPending or blockedByHeist() then
		return
	end
	local inputs = uids
	if not inputs then
		local tier = lastTier
		if not tier or lastCount < FusionConfig.MinFusionInputs then
			return
		end
		inputs = FusionController.GetAutoFill(tier, lastCount)
	end
	local chosen = inputs :: { string }
	if #chosen < FusionConfig.MinFusionInputs or #chosen > FusionConfig.MaxFusionInputs then
		return
	end
	local first = nil
	for _, item in InventoryController.GetInventory() do
		if item.Uid == chosen[1] then
			first = item
		end
	end
	lastTier = if first then first.Tier else lastTier
	lastCount = #chosen

	isRequestPending = true
	pendingResult = nil

	-- The client only ever plays this generic shell - it has no idea what
	-- the outcome will be, and never will until FusionResult arrives below.
	local handles = { Core = core :: BasePart, Ring = ring }
	task.spawn(function()
		RevealEffects.PlayChargeUp(handles, CHARGE_DURATION_SECONDS)
	end)

	local startTime = os.clock()
	RemoteEvents.RequestFusion:FireServer({ Uids = chosen })

	repeat
		task.wait()
	until pendingResult ~= nil

	local result = pendingResult
	pendingResult = nil

	-- Never reveal before the charge-up has had its full, fixed duration to
	-- play out, no matter how fast the server actually responded.
	local elapsed = os.clock() - startTime
	if elapsed < CHARGE_DURATION_SECONDS then
		task.wait(CHARGE_DURATION_SECONDS - elapsed)
	end

	if result.Success then
		local resultTier = result.NewItem.Tier
		RevealEffects.PlayReveal(handles, {
			AccentColor = FusionConfig.TierAccentColors[resultTier] or Color3.new(1, 1, 1),
			-- A failed roll never gets the big treatment, even on a high tier.
			IsMajor = result.Upgraded == true and FusionConfig.IsMajorReveal(resultTier, result.NewItem.Mutation),
		})
	end

	isRequestPending = false
	fusionResolved:Fire(result)
end

-- Public entry point (the Fuse panel's FUSE and the fail card's AGAIN).
FusionController.RequestFusion = requestFusion

-- Fuse every Common/Rare/Epic pair in one go: plays the charge-up for 3 s,
-- then fires FuseAllResolved with the server's summary. Yields; call it
-- with task.spawn.
function FusionController.RequestFuseAll()
	if isRequestPending or not core or blockedByHeist() then
		return
	end
	isRequestPending = true
	pendingFuseAllResult = nil

	local handles = { Core = core :: BasePart, Ring = ring }
	task.spawn(function()
		RevealEffects.PlayChargeUp(handles, FUSE_ALL_CHARGE_SECONDS)
	end)

	local startTime = os.clock()
	RemoteEvents.RequestFuseAll:FireServer()
	repeat
		task.wait()
	until pendingFuseAllResult ~= nil
	local result = pendingFuseAllResult
	pendingFuseAllResult = nil

	local elapsed = os.clock() - startTime
	if elapsed < FUSE_ALL_CHARGE_SECONDS then
		task.wait(FUSE_ALL_CHARGE_SECONDS - elapsed)
	end

	isRequestPending = false
	fuseAllResolved:Fire(result)
end

local function onFusionResult(payload: any)
	pendingResult = payload
end

function FusionController.Init()
	RemoteEvents.FusionResult.OnClientEvent:Connect(onFusionResult)
	RemoteEvents.FuseAllResult.OnClientEvent:Connect(function(payload: any)
		pendingFuseAllResult = if typeof(payload) == "table" then payload else { Count = 0 }
	end)

	-- Each plot has its own machine now; only ours is ever enabled for us.
	local plotsFolder = Workspace:WaitForChild(PlotNaming.PlotsFolderName)
	local plot = plotsFolder:WaitForChild(PlotNaming.GetPlotName(Players.LocalPlayer.UserId))
	local machine = plot:WaitForChild(MACHINE_NAME) :: Model
	core = machine:WaitForChild("Core") :: BasePart
	ring = machine:FindFirstChild("Ring") :: BasePart?
	local anchor = machine:WaitForChild("PromptAnchor") :: BasePart
	promptAnchor = anchor
	prompt = anchor:WaitForChild("FusePrompt") :: ProximityPrompt
	-- The prompt itself opens the Fuse panel (FusePanel, through
	-- ProximityPromptService); this controller only runs the requests.
end

return FusionController
