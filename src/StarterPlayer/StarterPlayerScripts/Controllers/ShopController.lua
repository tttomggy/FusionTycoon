--!strict
--[[
	ShopController
	--------------
	The client side of the shop (everything is granted by the server's
	MonetizationService; this only shows and asks):

	  ShopController.IsAvailable(key)   is it offered to you right now?
	                                    (ShopConfig.IsOffered + a live sale
	                                    window for sale products + not owned)
	  ShopController.Buy(key)           RequestShopPurchase { Key }: the server
	                                    checks again, then prompts Roblox's
	                                    purchase dialog
	  ShopController.Purchased          fires (payload) on every ShopPurchased

	Also: refusals toast; the VIP chat prefix (TextChatService, from the
	Player attribute "VIP"); the Server Overclock banner (ShopAnnouncement).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ShopState = require(ReplicatedStorage.Shared.Modules.ShopState)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonController = require(script.Parent.TycoonController)
local ToastController = require(script.Parent.ToastController)
local AnnouncementController = require(script.Parent.AnnouncementController)

local ShopController = {}

local purchased = Instance.new("BindableEvent")
ShopController.Purchased = purchased.Event

local REFUSAL_TOASTS: { [string]: string } = {
	Restricted = "That item isn't available for your account",
	NotSetUp = "Coming soon!",
	Owned = "You already have that",
	SaleOver = "That sale just ended",
	NothingToDouble = "Nothing to double right now",
	NotLoaded = "Your lab is still loading, try again",
	Unknown = "Couldn't do that, try again",
}

function ShopController.IsAvailable(key: string): boolean
	local shop = TycoonController.GetShop()
	if not ShopConfig.IsOffered(key, shop.Restricted, RunService:IsStudio(), shop.StarterPackBought) then
		return false
	end
	local item = ShopConfig.GetItem(key) :: ShopConfig.Item
	if item.SaleOf and not ShopState.IsSaleLive(key) then
		return false
	end
	if key == "OfflineDouble" and shop.OfflineDoubleAmount <= 0 then
		return false
	end
	return true
end

-- Owned pass (shows "✓ OWNED"); products are never "owned".
function ShopController.IsOwned(key: string): boolean
	local item = ShopConfig.GetItem(key)
	if not item then
		return false
	end
	if item.Kind == "Pass" then
		return TycoonController.OwnsPass(key)
	end
	return key == "StarterPack" and TycoonController.GetShop().StarterPackBought
end

function ShopController.Buy(key: string)
	RemoteEvents.RequestShopPurchase:FireServer({ Key = key })
end

local function onPurchased(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Result == "Refused" then
		local reason = if typeof(payload.Reason) == "string" then payload.Reason else "Unknown"
		ToastController.Show(REFUSAL_TOASTS[reason] or REFUSAL_TOASTS.Unknown, "Error")
	end
	purchased:Fire(payload)
end

local function onAnnouncement(payload: any)
	if typeof(payload) ~= "table" or payload.Kind ~= "Overclock" or typeof(payload.PlayerName) ~= "string" then
		return
	end
	local seconds = if typeof(payload.Seconds) == "number" then payload.Seconds else ShopConfig.OverclockSeconds
	AnnouncementController.ShowOverclock(payload.PlayerName, seconds)
end

-- "[VIP]" in gold before a VIP's name in chat.
local function onIncomingMessage(message: TextChatMessage): TextChatMessageProperties?
	local source = message.TextSource
	local speaker = source and Players:GetPlayerByUserId(source.UserId)
	if not speaker or speaker:GetAttribute("VIP") ~= true then
		return nil
	end
	local properties = Instance.new("TextChatMessageProperties")
	properties.PrefixText = ('<font color="%s">[VIP]</font> %s'):format(UITheme.ToHex(UITheme.World.VipGold), message.PrefixText)
	return properties
end

function ShopController.Init()
	RemoteEvents.ShopPurchased.OnClientEvent:Connect(onPurchased)
	RemoteEvents.ShopAnnouncement.OnClientEvent:Connect(onAnnouncement)
	TextChatService.OnIncomingMessage = onIncomingMessage
end

return ShopController
