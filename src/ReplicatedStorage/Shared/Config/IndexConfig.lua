--!strict
--[[
	IndexConfig
	-----------
	The collection book. One entry per ItemConfig item x { Normal, Golden,
	Diamond, Rainbow } (17 items x 4 = 68). Every entry found adds
	BonusPerEntry to income, and a tier page with every item in every
	variant adds BonusPerCompletedTier on top. The Index survives rebirths.

	Keys are "<itemId>|<Mutation or Normal>", e.g. "legendary_core|Golden".
	Mirrored in tools/econ_sim.py (INDEX_*); change both together.
]]
local ItemConfig = require(script.Parent.ItemConfig)
local FusionConfig = require(script.Parent.FusionConfig)
local MutationConfig = require(script.Parent.MutationConfig)

local IndexConfig = {}

IndexConfig.BonusPerEntry = 0.01 -- +1% income per entry found
IndexConfig.BonusPerCompletedTier = 0.05 -- +5% per tier page with every item x variant

IndexConfig.NORMAL = "Normal"

-- Column order on an Index page.
IndexConfig.Variants = { IndexConfig.NORMAL, table.unpack(MutationConfig.Order) }

function IndexConfig.GetKey(itemId: string, mutation: string?): string
	return ("%s|%s"):format(itemId, mutation or IndexConfig.NORMAL)
end

-- True if `key` names a real item and variant (sanitises saved data).
function IndexConfig.IsValidKey(key: any): boolean
	if typeof(key) ~= "string" then
		return false
	end
	local itemId, variant = string.match(key, "^(.+)|(%a+)$")
	if not itemId or not variant or not ItemConfig.GetItemById(itemId) then
		return false
	end
	return variant == IndexConfig.NORMAL or MutationConfig.IsValid(variant)
end

function IndexConfig.GetTotalEntries(): number
	return #ItemConfig.Items * #IndexConfig.Variants
end

function IndexConfig.CountFound(found: { [string]: boolean }): number
	local count = 0
	for key, isFound in found do
		if isFound and IndexConfig.IsValidKey(key) then
			count += 1
		end
	end
	return count
end

-- (found, total) entries for one tier page.
function IndexConfig.GetTierProgress(found: { [string]: boolean }, tier: string): (number, number)
	local have, total = 0, 0
	for _, item in ItemConfig.GetItemsByTier(tier) do
		for _, variant in IndexConfig.Variants do
			total += 1
			if found[("%s|%s"):format(item.Id, variant)] then
				have += 1
			end
		end
	end
	return have, total
end

function IndexConfig.IsTierComplete(found: { [string]: boolean }, tier: string): boolean
	local have, total = IndexConfig.GetTierProgress(found, tier)
	return total > 0 and have == total
end

function IndexConfig.CountCompletedTiers(found: { [string]: boolean }): number
	local count = 0
	for _, tier in FusionConfig.TierOrder do
		if IndexConfig.IsTierComplete(found, tier) then
			count += 1
		end
	end
	return count
end

-- 1 + 1% per entry + 5% per completed tier page.
function IndexConfig.GetMultiplier(found: { [string]: boolean }): number
	return 1
		+ IndexConfig.BonusPerEntry * IndexConfig.CountFound(found)
		+ IndexConfig.BonusPerCompletedTier * IndexConfig.CountCompletedTiers(found)
end

return IndexConfig
