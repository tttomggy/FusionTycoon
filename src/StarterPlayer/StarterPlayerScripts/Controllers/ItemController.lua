--[[
	ItemController
	--------------
	Pedestals fill themselves with your best items (ItemService.Arrange on
	the server, every sync): there is no place / remove any more. All that's
	left here is the locked spots 5-6: their owner-only "Unlock" prompt
	(enabled by WorldLabelController on a locked spot) asks for the +2
	Pedestals pass, the one in-world sell, only on the owner's own tap.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local ShopController = require(script.Parent.ShopController)
local ToastController = require(script.Parent.ToastController)

local ItemController = {}

local UNLOCK_PROMPT_NAME = "UnlockPrompt"

-- A locked spot's prompt in the local player's own plot.
local function isOwnUnlockPrompt(prompt: ProximityPrompt): boolean
	if prompt.Name ~= UNLOCK_PROMPT_NAME then
		return false
	end
	local current: Instance? = prompt
	while current do
		local owner = current:GetAttribute("OwnerUserId")
		if typeof(owner) == "number" then
			return owner == Players.LocalPlayer.UserId
		end
		current = current.Parent
	end
	return false
end

function ItemController.Init()
	local localPlayer = Players.LocalPlayer
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, triggeringPlayer: Player)
		if triggeringPlayer ~= localPlayer or not isOwnUnlockPrompt(prompt) then
			return
		end
		-- Only once the pass is really for sale (no id yet: no prompt).
		if ShopController.IsAvailable("ExtraPedestals") then
			ShopController.Buy("ExtraPedestals")
		else
			ToastController.Show("Coming soon!", "Neutral")
		end
	end)
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if isOwnUnlockPrompt(prompt) then
			local forSale = ShopController.IsAvailable("ExtraPedestals")
			prompt.ActionText = if forSale then "Unlock" else "Locked"
			prompt.ObjectText = if forSale then "+2 Pedestals" else "+2 Pedestals · coming soon"
		end
	end)
end

return ItemController
