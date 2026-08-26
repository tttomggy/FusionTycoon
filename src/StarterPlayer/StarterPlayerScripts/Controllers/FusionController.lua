local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local RevealEffects = require(script.Parent.Parent.Effects.RevealEffects)
local InventoryController = require(script.Parent.InventoryController)

local FusionController = {}

local MACHINE_NAME = "FusionMachine"
local CHARGE_DURATION_SECONDS = 2.2

-- Guards against double-firing while a request is in flight; the server is
-- still the final authority (it has its own cooldown check independently).
local isRequestPending = false

-- Set only by onFusionResult; the request loop below polls it instead of
-- holding its own one-shot connection, so a stray/duplicate FusionResult
-- can never leave a dangling listener.
local pendingResult: any = nil

local fusionResolved = Instance.new("BindableEvent")
-- Fires only once the server has validated the attempt AND the reveal effect
-- (if any) has finished playing. UI code should hook this, never react at
-- the moment a fuse is requested.
FusionController.FusionResolved = fusionResolved.Event

local core: BasePart? = nil
local ring: BasePart? = nil
local prompt: ProximityPrompt? = nil
local oddsBillboard: BillboardGui? = nil

-- A BillboardGui's on-screen position depends on camera angle, not just
-- where it sits in 3D - repositioning it further (as done last turn) helps
-- for typical angles but can't guarantee it never overlaps Roblox's default
-- PlayerList (top-right corner) from every possible viewpoint. This checks
-- its actual projected screen position every frame instead, and hides it
-- outright when it would land in that corner. The zone is a conservative
-- approximation (the PlayerList's real bounds vary with player count/
-- resolution) - erring on the side of hiding a little early rather than
-- risking a real overlap.
local RESERVED_ZONE_WIDTH_FRACTION = 0.22
local RESERVED_ZONE_HEIGHT_FRACTION = 0.35

local function updateOddsBillboardVisibility()
	if not oddsBillboard then
		return
	end
	local base = oddsBillboard.Parent
	if not base or not base:IsA("BasePart") then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local anchorPosition = (base :: BasePart).Position + oddsBillboard.StudsOffset
	local screenPoint, isOnScreen = camera:WorldToScreenPoint(anchorPosition)
	if not isOnScreen then
		oddsBillboard.Enabled = true
		return
	end

	local viewportSize = camera.ViewportSize
	local isInReservedZone = screenPoint.X > viewportSize.X * (1 - RESERVED_ZONE_WIDTH_FRACTION)
		and screenPoint.Y < viewportSize.Y * RESERVED_ZONE_HEIGHT_FRACTION

	oddsBillboard.Enabled = not isInReservedZone
end

-- Picks the highest tier the player currently has at least two of, so
-- there's no separate tier-picker UI to build: walking up and pressing Fuse
-- always offers your best available pair.
local function getBestAvailableTier(): string?
	for index = #FusionConfig.TierOrder, 1, -1 do
		local tier = FusionConfig.TierOrder[index]
		if InventoryController.CountItemsOfTier(tier) >= FusionConfig.ItemsRequiredPerFusion then
			return tier
		end
	end
	return nil
end

local function updatePromptState()
	if not prompt then
		return
	end
	local tier = getBestAvailableTier()
	prompt.Enabled = tier ~= nil
	if tier then
		prompt.ObjectText = ("Fuse 2x %s"):format(tier)
	end
end

function FusionController.IsRequestPending(): boolean
	return isRequestPending
end

-- Fire-and-forget: does not return until the full request/animation cycle
-- resolves, so run it in task.spawn if the caller needs to keep going.
local function requestFusion()
	if isRequestPending then
		return
	end

	local tier = getBestAvailableTier()
	if not tier then
		return
	end

	local items = InventoryController.GetItemsByTier(tier)
	if #items < FusionConfig.ItemsRequiredPerFusion then
		return
	end

	isRequestPending = true
	pendingResult = nil
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
			IsMajor = FusionConfig.MajorRevealTiers[resultTier] == true,
		})
	end

	isRequestPending = false
	updatePromptState()
	fusionResolved:Fire(result)
end

local function onFusionResult(payload: any)
	pendingResult = payload
end

function FusionController.Init()
	RemoteEvents.FusionResult.OnClientEvent:Connect(onFusionResult)

	local machine = Workspace:WaitForChild(MACHINE_NAME) :: Model
	core = machine:WaitForChild("Core") :: BasePart
	ring = machine:FindFirstChild("Ring") :: BasePart?
	prompt = (core :: BasePart):WaitForChild("FusePrompt") :: ProximityPrompt

	local base = machine:WaitForChild("Base") :: BasePart
	oddsBillboard = base:WaitForChild("FusionOddsBillboard") :: BillboardGui
	RunService.RenderStepped:Connect(updateOddsBillboardVisibility)

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
	updatePromptState()
end

return FusionController
