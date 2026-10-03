--[[
	HeistController
	---------------
	The client side of stealing (HeistService owns every rule).

	  * Holding E on an enemy pedestal's StealPrompt (enabled only when the
	    steal is allowed, WorldLabelController) fires RequestSteal with just
	    which pedestal: { OwnerUserId, PedestalIndex }.
	  * A rejected grab comes back as HeistEnded { Outcome = "Rejected",
	    Reason } and shows a toast.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local ToastController = require(script.Parent.ToastController)

local HeistController = {}

local localPlayer = Players.LocalPlayer

local STEAL_PROMPT_NAME = "StealPrompt"

-- Rejection reason -> toast. Unlisted reasons (exploit-only) stay silent.
local REJECT_MESSAGES: { [string]: string } = {
	AlreadyCarrying = "You're already carrying something!",
	Shielded = "Their shield is up",
	LabCapped = "This lab has been robbed enough for now",
	AlreadyStolen = "Someone's already carrying that",
	Empty = "Nothing to steal there",
	TooFar = "Get closer",
	NoCharacter = "Can't steal right now",
	DataNotLoaded = "Can't steal right now",
}

local function onPromptTriggered(prompt: ProximityPrompt, triggeringPlayer: Player)
	if triggeringPlayer ~= localPlayer or prompt.Name ~= STEAL_PROMPT_NAME then
		return
	end
	local owner = prompt:GetAttribute("OwnerUserId")
	local pedestal = prompt.Parent
	local index = pedestal and pedestal:GetAttribute("PedestalIndex")
	if typeof(owner) ~= "number" or typeof(index) ~= "number" then
		return
	end
	RemoteEvents.RequestSteal:FireServer({ OwnerUserId = owner, PedestalIndex = index })
end

local function onHeistEnded(payload: any)
	if typeof(payload) ~= "table" or payload.Outcome ~= "Rejected" then
		return
	end
	if payload.Reason == "Cooldown" then
		ToastController.Show(("Lay low for %ds"):format(tonumber(payload.Seconds) or 0), "Neutral")
		return
	end
	local message = REJECT_MESSAGES[payload.Reason]
	if message then
		ToastController.Show(message, "Neutral")
	end
end

function HeistController.Init()
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	RemoteEvents.HeistEnded.OnClientEvent:Connect(onHeistEnded)
end

return HeistController
