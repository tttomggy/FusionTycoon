--!strict
--[[
	DealConfig
	----------
	Real rotating deals. A deal is a BUNDLE sold as its own developer product
	(ShopConfig items with `Deal = true` and `Parts`), always priced below its
	parts at live prices. One deal per 6-hour UTC slot, deterministic from the
	slot start (the same lowbias32 hash as the event clock: EventConfig.Hash32),
	so every server and client shows the same deal with no messaging, and the
	countdown is the real time to the next slot.

	  GetSlotStart(now)          the slot `now` falls in (UTC seconds)
	  GetDealForSlot(slotStart)  the deal key; never the same deal two slots
	                             running (each slot steps 1..n-1 places on
	                             from the last, by the hash)

	The rest of the rules live where they act: a deal shows only while its
	LIVE saving is >= MinSavePercent and never to policy-restricted players
	(ShopController); the server refuses a deal key that isn't the current
	slot's, honouring a receipt for ReceiptGraceSeconds after a prompt made
	inside the slot (MonetizationService).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)

local DealConfig = {}

DealConfig.SlotSeconds = 6 * 60 * 60
DealConfig.Deals = { "DealPowerHour", "DealFusionKit", "DealRichLab" }
DealConfig.MinSavePercent = 15
DealConfig.ReceiptGraceSeconds = 10 * 60
-- The rotation's anchor (2026-01-01 00:00 UTC, a slot boundary): slots from
-- here on step from the previous one, so no deal repeats back to back.
DealConfig.EpochSlot = 1767225600

function DealConfig.GetSlotStart(now: number): number
	return (math.floor(now) // DealConfig.SlotSeconds) * DealConfig.SlotSeconds
end

local function draw(slotStart: number): number
	return EventConfig.Hash32(bit32.band(slotStart, 0xFFFFFFFF))
end

-- Memo of the last walked slot, so consecutive calls are O(1).
local memoSlot: number? = nil
local memoIndex = 0

local function indexForSlot(slotStart: number): number
	local n = #DealConfig.Deals
	local epoch = DealConfig.EpochSlot
	if slotStart < epoch or n < 2 then
		return draw(slotStart) % math.max(n, 1) + 1
	end
	local slot, index
	local memo = memoSlot
	if memo and memo <= slotStart then
		slot, index = memo, memoIndex
	else
		slot, index = epoch, draw(epoch) % n
	end
	while slot < slotStart do
		slot += DealConfig.SlotSeconds
		-- 1..n-1 places on: never the previous slot's deal.
		index = (index + 1 + draw(slot) % (n - 1)) % n
	end
	memoSlot, memoIndex = slot, index
	return index + 1
end

function DealConfig.GetDealForSlot(slotStart: number): string
	return DealConfig.Deals[indexForSlot(DealConfig.GetSlotStart(slotStart))]
end

function DealConfig.IsDeal(key: string): boolean
	return table.find(DealConfig.Deals, key) ~= nil
end

return DealConfig
