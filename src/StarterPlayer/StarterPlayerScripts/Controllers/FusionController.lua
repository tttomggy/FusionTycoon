local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

local FusionController = {}

-- Guards against double-firing while a request is in flight; the server is
-- still the final authority (it has its own cooldown check independently).
local isRequestPending = false

local fusionResolved = Instance.new("BindableEvent")
-- Fires only once the server has validated the attempt. UI/animation code
-- should hook this event, never react at the moment RequestFusion is sent.
FusionController.FusionResolved = fusionResolved.Event

-- Called by UI when the player confirms a fusion attempt for `tier`.
-- Fire-and-forget: does not yield, and returns immediately.
function FusionController.RequestFusion(tier: string): boolean
	if isRequestPending then
		return false
	end

	isRequestPending = true
	RemoteEvents.RequestFusion:FireServer(tier)
	return true
end

function FusionController.IsRequestPending(): boolean
	return isRequestPending
end

local function onFusionResult(result: any)
	isRequestPending = false
	fusionResolved:Fire(result)
end

function FusionController.Init()
	RemoteEvents.FusionResult.OnClientEvent:Connect(onFusionResult)
end

return FusionController
