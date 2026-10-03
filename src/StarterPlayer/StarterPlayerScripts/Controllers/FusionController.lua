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
local fuseAllPrompt: ProximityPrompt? = nil
-- The prompts live here (platform centre), not on the Core up in the air.
local promptAnchor: BasePart? = nil

local function hasPair(tier: string): boolean
	return #InventoryController.GetFusableItemsByTier(tier) >= FusionConfig.ItemsRequiredPerFusion
end

-- Offers the LOWEST tier you have a spare pair of (not counting items on
-- pedestals). Fusing is a climb now (2x Common -> Rare, ...), so working up
-- from the bottom is what you want. Secret can't be fused at all, and
-- Mythic only after RebirthConfig.SecretFusionRebirths.
local function getNextFusableTier(): string?
	local rebirths = TycoonController.GetRebirths()
	for _, tier in FusionConfig.TierOrder do
		if FusionConfig.CanFuseTierFor(tier, rebirths) and hasPair(tier) then
			return tier
		end
	end
	return nil
end

-- A tier you have a pair of but can't fuse yet (Mythic before Rebirth 1),
-- and the rebirths it needs. The prompt shows a lock for it.
local function getLockedTier(): (string?, number)
	local rebirths = TycoonController.GetRebirths()
	for _, tier in FusionConfig.TierOrder do
		local needed = FusionConfig.RebirthGatedTiers[tier]
		if needed and FusionConfig.CanFuseTier(tier) and rebirths < needed and hasPair(tier) then
			return tier, needed
		end
	end
	return nil, 0
end

local function lockText(tier: string, needed: number): string
	return ("Rebirth %d to fuse %ss"):format(needed, tier)
end

-- Fusions possible right now without cascading: pairs per Fuse All tier.
local function countFuseAllPairs(): number
	local pairCount = 0
	for _, tier in FusionConfig.GetFuseAllTiers() do
		pairCount += #InventoryController.GetFusableItemsByTier(tier) // FusionConfig.ItemsRequiredPerFusion
	end
	return pairCount
end

local function updatePromptState()
	if fuseAllPrompt then
		local count = if isRequestPending then 0 else countFuseAllPairs()
		fuseAllPrompt.Enabled = count >= 2
		fuseAllPrompt.ActionText = ("Fuse All (%d)"):format(count)
	end
	if not prompt then
		return
	end
	local tier = if isRequestPending then nil else getNextFusableTier()
	local lockedTier, needed = getLockedTier()
	prompt.Enabled = tier ~= nil or (lockedTier ~= nil and not isRequestPending)
	if tier then
		local nextTier = FusionConfig.GetNextTier(tier) :: string
		local chance = FusionConfig.SuccessChance[tier] or 0
		prompt.ActionText = ("Fuse 2x %s"):format(tier)
		prompt.ObjectText = ("→ %s  (%d%% chance)"):format(nextTier, math.floor(chance * 100 + 0.5))
	elseif lockedTier then
		-- A lock instead of the fuse button: pressing it only explains.
		prompt.ActionText = "🔒 Locked"
		prompt.ObjectText = lockText(lockedTier, needed)
	end
end

function FusionController.IsRequestPending(): boolean
	return isRequestPending
end

-- True while another fuse would be accepted right now: nothing in flight,
-- a spare pair exists, and the local character is within the machine
-- prompt's reach. Drives the fail card's AGAIN button.
function FusionController.CanRequestFusion(): boolean
	if isRequestPending or not core or not prompt or getNextFusableTier() == nil then
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

-- Fire-and-forget: does not return until the full request/animation cycle
-- resolves, so run it in task.spawn if the caller needs to keep going.
local function requestFusion()
	if isRequestPending then
		return
	end

	local tier = getNextFusableTier()
	if not tier then
		local lockedTier, needed = getLockedTier()
		if lockedTier then
			ToastController.Show(lockText(lockedTier, needed), "Neutral")
		end
		return
	end

	local items = InventoryController.GetFusableItemsByTier(tier)
	if #items < FusionConfig.ItemsRequiredPerFusion then
		return
	end

	isRequestPending = true
	pendingResult = nil
	updatePromptState()
	local uidA, uidB = items[1].Uid, items[2].Uid

	-- The client only ever plays this generic shell - it has no idea what
	-- the outcome will be, and never will until FusionResult arrives below.
	local handles = { Core = core :: BasePart, Ring = ring }
	task.spawn(function()
		RevealEffects.PlayChargeUp(handles, CHARGE_DURATION_SECONDS)
	end)

	local startTime = os.clock()
	RemoteEvents.RequestFusion:FireServer(uidA, uidB)

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
			IsMajor = result.Upgraded == true and FusionConfig.MajorRevealTiers[resultTier] == true,
		})
	end

	isRequestPending = false
	updatePromptState()
	fusionResolved:Fire(result)
end

-- Public entry point (the machine prompt and the fail card's AGAIN button).
-- Yields for the whole charge/reveal cycle; call it with task.spawn.
FusionController.RequestFusion = requestFusion

-- Fuse every Common/Rare/Epic pair in one go: plays the charge-up for 3 s,
-- then fires FuseAllResolved with the server's summary. Yields; call it
-- with task.spawn.
function FusionController.RequestFuseAll()
	if isRequestPending or not core then
		return
	end
	isRequestPending = true
	pendingFuseAllResult = nil
	updatePromptState()

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
	updatePromptState()
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
	fuseAllPrompt = anchor:WaitForChild("FuseAllPrompt") :: ProximityPrompt
	local holdPrompt = fuseAllPrompt :: ProximityPrompt
	holdPrompt.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer == Players.LocalPlayer then
			task.spawn(FusionController.RequestFuseAll)
		end
	end)

	-- Same fix as AnnouncementController: a line starting with "(" right
	-- after a statement is ambiguous in Lua (could read as continuing the
	-- previous line's expression as a function call), so this goes through a
	-- local variable instead of an inline `(x :: T).Field` cast.
	local fusePrompt = prompt :: ProximityPrompt
	fusePrompt.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer == Players.LocalPlayer then
			task.spawn(requestFusion)
		end
	end)

	InventoryController.InventoryChanged:Connect(updatePromptState)
	-- A rebirth can unlock Mythic fusion.
	TycoonController.TycoonChanged:Connect(updatePromptState)
	updatePromptState()
end

return FusionController
