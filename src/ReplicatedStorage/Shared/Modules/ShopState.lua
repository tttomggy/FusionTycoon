--!strict
--[[
	ShopState
	---------
	Server-wide shop state both sides read from workspace attributes
	(MonetizationService writes them):

	  OverclockUntil   server time the Server Overclock ends (0 = none)
	  OverclockBy      display name of whoever bought the latest one

	and the real sale windows (ShopConfig.Sales): "AdminAbuse" is live while
	EventState.GetAdminAbuseWindowEnd says so. One reader, so the server's
	refusal and the shop's "SALE" tag can't disagree.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)

local ShopState = {}

-- Seconds of Server Overclock left (0 when none).
function ShopState.GetOverclockSeconds(): number
	local untilTime = Workspace:GetAttribute("OverclockUntil")
	if typeof(untilTime) ~= "number" then
		return 0
	end
	return math.max(0, untilTime - Workspace:GetServerTimeNow())
end

function ShopState.GetOverclockMultiplier(): number
	return if ShopState.GetOverclockSeconds() > 0 then ShopConfig.OverclockMultiplier else 1
end

function ShopState.GetOverclockBy(): string?
	local by = Workspace:GetAttribute("OverclockBy")
	return if typeof(by) == "string" and by ~= "" then by else nil
end

-- When `window` ends (server time) if it's live right now, else nil.
function ShopState.GetWindowEnd(window: string): number?
	if window == "AdminAbuse" then
		return EventState.GetAdminAbuseWindowEnd()
	end
	return nil
end

-- The live sale for normal product `key` (its sale entry and end time), or nil.
function ShopState.GetLiveSaleFor(key: string): (ShopConfig.Sale?, number?)
	local sale = ShopConfig.GetSaleFor(key)
	if not sale then
		return nil, nil
	end
	local ends = ShopState.GetWindowEnd(sale.Window)
	if not ends then
		return nil, nil
	end
	return sale, ends
end

-- Is sale product `saleKey` sellable right now?
function ShopState.IsSaleLive(saleKey: string): boolean
	local sale = ShopConfig.GetSaleBySaleKey(saleKey)
	return sale ~= nil and ShopState.GetWindowEnd(sale.Window) ~= nil
end

-- Any sale live right now (the HUD SHOP button's red SALE tag).
function ShopState.AnySaleLive(): boolean
	for _, sale in ShopConfig.Sales do
		if ShopState.GetWindowEnd(sale.Window) then
			return true
		end
	end
	return false
end

return ShopState
