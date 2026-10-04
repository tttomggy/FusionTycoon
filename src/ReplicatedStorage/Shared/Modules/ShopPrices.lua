--!strict
--[[
	ShopPrices
	----------
	Every Robux price the game shows, read live from
	MarketplaceService:GetProductInfo and cached for
	ShopConfig.PriceCacheSeconds (10 min). Never typed into the UI.

	  ShopPrices.Get(key) -> number?   the cached price, or nil while it
	                                   loads / for an Id 0 item; a stale or
	                                   missing entry starts a background fetch
	  ShopPrices.GetPartsTotal(key)    a bundle's parts bought one by one
	                                   (nil until every part's price is in)
	  ShopPrices.Changed               fires (key) when a price arrives
	  ShopPrices.Prefetch()            fetches every set-up item

	Works on both sides (the shop UI is the main reader).
]]
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)

local ShopPrices = {}

type Entry = { Price: number?, FetchedAt: number, Fetching: boolean }

local cache: { [string]: Entry } = {}
local changed = Instance.new("BindableEvent")
ShopPrices.Changed = changed.Event

local function fetch(key: string)
	local item = ShopConfig.GetItem(key)
	if not item or item.Id == 0 then
		return
	end
	local entry = cache[key]
	if entry and entry.Fetching then
		return
	end
	local now = os.clock()
	if entry and entry.Price ~= nil and now - entry.FetchedAt < ShopConfig.PriceCacheSeconds then
		return
	end
	local fresh: Entry = { Price = if entry then entry.Price else nil, FetchedAt = now, Fetching = true }
	cache[key] = fresh
	task.spawn(function()
		local infoType = if item.Kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(item.Id, infoType)
		end)
		fresh.Fetching = false
		fresh.FetchedAt = os.clock()
		if ok and typeof(info) == "table" and typeof((info :: any).PriceInRobux) == "number" then
			local price = (info :: any).PriceInRobux :: number
			local before = fresh.Price
			fresh.Price = price
			if before ~= price then
				changed:Fire(key)
			end
		else
			-- Retry on the next read after a short back-off.
			fresh.FetchedAt = os.clock() - ShopConfig.PriceCacheSeconds + 30
		end
	end)
end

function ShopPrices.Get(key: string): number?
	fetch(key)
	local entry = cache[key]
	return if entry then entry.Price else nil
end

-- A bundle's parts bought one by one (live prices), or nil until all are in.
function ShopPrices.GetPartsTotal(key: string): number?
	local item = ShopConfig.GetItem(key)
	if not item or not item.Parts then
		return nil
	end
	local total = 0
	for _, part in item.Parts do
		local price = ShopPrices.Get(part)
		if not price then
			return nil
		end
		total += price
	end
	return total
end

function ShopPrices.Prefetch()
	for key in ShopConfig.Items do
		fetch(key)
	end
end

return ShopPrices
