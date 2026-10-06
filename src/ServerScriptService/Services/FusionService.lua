--!strict
--[[
	FusionService
	-------------
	Server-authoritative fusion: validates a two-item fusion request against
	the player's real inventory, consumes the inputs, and rolls for an upgrade.

	Two items of tier N -> success: one item of tier N+1
	                    -> fail:    one item of tier N back
	Odds per tier and input count live in FusionConfig.SuccessChanceByCount.

	Follows the ServiceTemplate contract:
	  :Init()   connects its own remote handler and nothing else.
	  :Start()  resolves PlayerDataService. That reference used to be a
	            module-scope `require`, which runs at load time and is the
	            thing that deadlocks if two services ever require each other.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local FusionConfig = require(Config.FusionConfig)
local ItemConfig = require(Config.ItemConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
local RarityVisuals = require(Config.RarityVisuals)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type EventServiceModule = typeof(require(script.Parent.EventService))

type State = {
	-- Ephemeral, session-only cooldown tracking; not persisted with player data.
	lastFusionAt: { [number]: number },
	lastFuseAllAt: { [number]: number },
	connections: { RBXScriptConnection },
}

--[[ Constants ------------------------------------------------------------ ]]

local FUSION_COOLDOWN_SECONDS = 1.5
local FUSE_ALL_COOLDOWN_SECONDS = 3

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	lastFusionAt = {},
	lastFuseAllAt = {},
	connections = {},
}

-- Resolved in :Start(), never at module scope - see the header. Declared with
-- a type annotation but no value: the identifier keeps its original name, so
-- every call site below reads exactly as it did when this was a module-scope
-- require, while the actual resolution has moved into the Start phase.
--
-- ServiceManager runs Init across all services and then Start across all
-- services with no yield in between, so this is assigned before any remote
-- handler connected in Init can actually be resumed.
local PlayerDataService: PlayerDataServiceModule
local EventService: EventServiceModule

local FusionService = {}

FusionService.Name = "FusionService"

--[[ Private helpers ------------------------------------------------------ ]]

local function isOnCooldown(userId: number): boolean
	local lastTime = state.lastFusionAt[userId]
	return lastTime ~= nil and (os.clock() - lastTime) < FUSION_COOLDOWN_SECONDS
end

local rng = Random.new()

-- Every reject path fires a (Success = false) FusionResult so the client's
-- pending-request flag always resolves. `isSuspicious` marks rejections that
-- indicate a modified/exploited client rather than an ordinary race (e.g. two
-- rapid clicks) - those get a server-side warn so they're visible in logs
-- without telling the client anything it could use to probe further.
-- Rejections that mean the client's inventory is stale: re-send it.
local STALE_INVENTORY_REASONS = { ItemInUse = true, ItemNotOwned = true, TierMismatch = true }

local function reject(player: Player, reason: string, isSuspicious: boolean?)
	if isSuspicious then
		warn(("FusionService: rejected fusion request from %s (%s)"):format(player.Name, reason))
	end
	if STALE_INVENTORY_REASONS[reason] and PlayerDataService.IsDataLoaded(player) then
		RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	end
	RemoteEvents.FusionResult:FireClient(player, { Success = false, Reason = reason })
end

type InventoryItem = { Uid: string, ItemId: string, Tier: string, InUse: boolean, Mutation: string? }

type FuseOutcome = {
	Upgraded: boolean,
	Entry: InventoryItem, -- the new item, or on a fail the kept input
	ConsumedUids: { string },
	IsNewIndex: boolean,
	Chance: number,
	KeptUid: string?, -- fail only
	-- A Safe Fusion token was used: on a fail every input stayed.
	Safe: boolean,
	-- Success with a mutation: "Kept" (carried over from the inputs) or
	-- "Rolled" (a fresh fusion roll beat it). nil otherwise.
	MutationSource: string?,
}

-- Fuses 2-6 already-validated, same-tier, not-in-use items. Fires no
-- remotes and never yields, so callers stay atomic.
--   success: every input goes; the result (next tier) gets the better of
--            (the LOWEST mutation among all inputs - so every input must
--            share a mutation for it to carry) and a fresh fusion roll at
--            the player's luck.
--   fail:    the input with the highest mutation rank (the first on a tie)
--            stays untouched, same Uid; all the others go. With `safe` (a
--            Safe Fusion token, spent by the caller) nothing goes.
-- Returns the outcome, or (nil, reason) if nothing changed.
local function fuseOnce(player: Player, items: { InventoryItem }, safe: boolean?): (FuseOutcome?, string?)
	local count = #items
	local consumedTier = items[1].Tier
	local nextTier = FusionConfig.GetNextTier(consumedTier)
	-- Void Moon adds a success bonus (EventService hook; capped at 100%).
	local chance = FusionConfig.GetFusionChance(consumedTier, count, EventService.GetFusionSuccessBonus())
	if not nextTier or chance <= 0 then
		return nil, "MaxTier"
	end

	-- Roll before touching the inventory.
	local upgraded = rng:NextNumber() < chance
	if not upgraded then
		local keep = items[1]
		for _, item in items do
			if MutationConfig.GetRank(item.Mutation) > MutationConfig.GetRank(keep.Mutation) then
				keep = item
			end
		end
		local lost = {}
		if not safe then
			for _, item in items do
				if item ~= keep then
					table.insert(lost, item.Uid)
				end
			end
		end
		if #lost > 0 and not PlayerDataService.RemoveItemsByUid(player, lost) then
			return nil, "ItemNotOwned"
		end
		PlayerDataService.IncrementTotalFusions(player)
		AnalyticsKit.Funnel(player, "FirstFuse")
		return {
			Upgraded = false,
			Entry = keep,
			ConsumedUids = lost,
			IsNewIndex = false,
			Chance = chance,
			KeptUid = keep.Uid,
			Safe = safe == true,
		},
			nil
	end

	-- Pick the result BEFORE touching the inventory, so a config gap can
	-- never eat the player's items.
	local rewardItem = ItemConfig.PickRandomOfTier(nextTier, rng)
	if not rewardItem then
		warn(("FusionService: no ItemConfig entry found for tier %s"):format(nextTier))
		return nil, "MissingRewardItem"
	end
	-- The lowest input mutation carries (FusionConfig.PredictMutation, the
	-- same function the Fuse panel's prediction line shows).
	local base = FusionConfig.PredictMutation(items)
	local uids = {}
	for _, item in items do
		table.insert(uids, item.Uid)
	end
	local luck = PlayerDataService.GetLuck(player)
	-- An event mutation (Void Moon: Void) replaces the normal fusion roll
	-- when it hits; otherwise the normal roll at the event's odds.
	local rolled: string?
	local eventMutation, eventChance = EventService.GetFusionEventMutation()
	if eventMutation and rng:NextNumber() < eventChance then
		rolled = eventMutation
	else
		local multipliers: { [string]: number } = {}
		for _, name in MutationConfig.Order do
			multipliers[name] = EventService.GetMutationOddsMultiplier(name, "Fusion")
		end
		rolled = MutationConfig.Roll(rng, luck, "Fusion", multipliers)
	end
	local mutation = MutationConfig.Better(base, rolled)

	if not PlayerDataService.RemoveItemsByUid(player, uids) then
		return nil, "ItemNotOwned"
	end
	local newEntry, isNewIndex = PlayerDataService.AddItem(player, rewardItem.Id, rewardItem.Tier, mutation)
	if not newEntry then
		return nil, "DataNotLoaded"
	end
	PlayerDataService.IncrementTotalFusions(player)
	AnalyticsKit.Funnel(player, "FirstFuse")
	return {
		Upgraded = true,
		Entry = newEntry,
		ConsumedUids = uids,
		IsNewIndex = isNewIndex,
		Chance = chance,
		KeptUid = nil,
		MutationSource = if mutation == nil then nil elseif mutation == base then "Kept" else "Rolled",
		Safe = safe == true,
	},
		nil
end

-- The tier whose Index page `item` just completed, if it was a new entry.
local function completedTier(player: Player, item: InventoryItem, isNewIndex: boolean): string?
	if isNewIndex and IndexConfig.IsTierComplete(PlayerDataService.GetIndex(player), item.Tier) then
		return item.Tier
	end
	return nil
end

-- Server-wide brag for a Legendary+ result, or any Rainbow: the moment
-- everyone else in the server sees and wants for themselves.
local function announce(player: Player, item: InventoryItem)
	-- An event-only mutation (a Void from the Void Moon) is a server moment
	-- at any tier, with its own line.
	if MutationConfig.IsEventOnly(item.Mutation) then
		EventService.AnnounceEventMutation(player, item, "VoidMoon")
		return
	end
	local visual = RarityVisuals.Tiers[item.Tier]
	local rainbow = item.Mutation == "Rainbow"
	if not rainbow and (not visual or not visual.AnnounceServerWide) then
		return
	end
	local def = ItemConfig.GetItemById(item.ItemId)
	local itemName = if def then def.Name else item.ItemId
	RemoteEvents.RareFusionAnnouncement:FireAllClients({
		Message = ("%s fused a %s %s!"):format(player.DisplayName, item.Tier:upper(), itemName),
		Tier = item.Tier,
		Mutation = item.Mutation,
		-- Parts, so the client can colour the tier word.
		PlayerName = player.DisplayName,
		Verb = "fused",
		ItemName = itemName,
	})
end

-- Validates and resolves a fusion attempt entirely synchronously (no yields
-- between the ownership check and the inventory mutation), so two requests
-- from the same player can never both pass validation against the same items.
-- RequestFusion: { Uids = { string } } with 2-6 unique Uids of one tier.
-- Validates and resolves entirely synchronously (no yields between the
-- ownership check and the inventory mutation), so two requests can never
-- both pass validation against the same items.
local function onFusionRequest(player: Player, rawPayload: unknown)
	-- Hands full: no fusing while carrying a stolen item (HeistService).
	if PlayerDataService.IsDataLoaded(player) and PlayerDataService.IsCarrying(player) then
		reject(player, "Carrying")
		return
	end
	if typeof(rawPayload) ~= "table" or typeof((rawPayload :: any).Uids) ~= "table" then
		reject(player, "InvalidItems", true)
		return
	end
	local rawUids = (rawPayload :: any).Uids
	local uids: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, uid in rawUids do
		if typeof(uid) ~= "string" then
			reject(player, "InvalidItems", true)
			return
		end
		if seen[uid] then
			reject(player, "DuplicateItem", true)
			return
		end
		seen[uid] = true
		table.insert(uids, uid)
	end
	if #uids < FusionConfig.MinFusionInputs or #uids > FusionConfig.MaxFusionInputs then
		reject(player, "BadCount", true)
		return
	end
	-- Safe Fusion (a shop token): armed in the Fuse panel; a fail keeps every orb.
	local safe = (rawPayload :: any).Safe == true

	if not PlayerDataService.IsDataLoaded(player) then
		reject(player, "DataNotLoaded")
		return
	end

	if isOnCooldown(player.UserId) then
		reject(player, "OnCooldown")
		return
	end

	-- Never trust client-supplied tiers/ownership: look every item up fresh
	-- from the player's authoritative server-side inventory.
	local items: { InventoryItem } = {}
	for _, uid in uids do
		local item = PlayerDataService.GetItemByUid(player, uid)
		if not item then
			reject(player, "ItemNotOwned", true)
			return
		end
		-- A displayed item can be fused (the pedestals re-arrange in the
		-- sync that follows); one a thief is carrying can't.
		if PlayerDataService.IsItemCarried(player, uid) then
			reject(player, "ItemCarried", true)
			return
		end
		if items[1] and item.Tier ~= items[1].Tier then
			reject(player, "TierMismatch", true)
			return
		end
		table.insert(items, item)
	end
	local tier = items[1].Tier

	-- Secret (top tier) can't be fused; the client never offers it.
	if not FusionConfig.CanFuseTier(tier) then
		reject(player, "MaxTier", true)
		return
	end
	-- Mythic -> Secret needs RebirthConfig.SecretFusionRebirths. The client
	-- shows a lock instead, but its rebirth count could be a sync behind.
	if not FusionConfig.CanFuseTierFor(tier, PlayerDataService.GetRebirths(player)) then
		reject(player, "NeedsRebirth")
		return
	end

	if safe and PlayerDataService.GetSafeFusionTokens(player) < 1 then
		reject(player, "NoSafeFusion")
		return
	end

	state.lastFusionAt[player.UserId] = os.clock()
	-- The token is spent on any armed fusion (success or fail), after every
	-- check passed and before the roll; a fusion that changes nothing
	-- (fuseOnce returns nil) gives it back.
	if safe then
		PlayerDataService.UseSafeFusionToken(player)
	end
	local outcome, failure = fuseOnce(player, items, safe)
	if not outcome and safe then
		PlayerDataService.AddSafeFusionTokens(player, 1)
	end
	if not outcome then
		reject(player, failure or "ItemNotOwned")
		return
	end

	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	RemoteEvents.FusionResult:FireClient(player, {
		Success = true,
		Upgraded = outcome.Upgraded,
		Count = #items,
		Chance = outcome.Chance,
		ConsumedUids = outcome.ConsumedUids,
		ConsumedTier = tier,
		NewItem = outcome.Entry,
		KeptUid = outcome.KeptUid,
		MutationSource = outcome.MutationSource,
		LostCount = if outcome.Upgraded then nil else #outcome.ConsumedUids,
		Safe = outcome.Safe,
		NewIndex = outcome.IsNewIndex,
		IndexTierComplete = completedTier(player, outcome.Entry, outcome.IsNewIndex),
	})
	-- Fusions change goal progress (TotalFusions, tiers owned). Sent after
	-- the result so a goal banner never lands ahead of the fusion itself.
	PlayerDataService.SyncTycoon(player)

	if outcome.Upgraded then
		announce(player, outcome.Entry)
	end
end

-- The lowest Fuse All tier with at least two items no thief is carrying and
-- not mutated, and the first two of them. Mutated items are never
-- auto-fused.
local function findFuseAllPair(player: Player): (InventoryItem?, InventoryItem?)
	local inventory = PlayerDataService.GetInventory(player)
	if not inventory then
		return nil, nil
	end
	for _, tier in FusionConfig.GetFuseAllTiers() do
		local first: InventoryItem? = nil
		for _, item in inventory do
			if item.Tier == tier and not PlayerDataService.IsItemCarried(player, item.Uid) and item.Mutation == nil then
				if first then
					return first, item
				end
				first = item
			end
		end
	end
	return nil, nil
end

-- Fuses every Common/Rare/Epic pair, cascading (new Rares pair up again),
-- then sends ONE inventory sync, ONE tycoon sync and one summary. `auto`:
-- the Auto-Fuse pass ran it (same rules; no cooldown; the summary carries
-- Auto = true and nothing is sent when there was no pair).
local function runFuseAll(player: Player, auto: boolean)
	if not PlayerDataService.IsDataLoaded(player) then
		if not auto then
			RemoteEvents.FuseAllResult:FireClient(player, { Count = 0 })
		end
		return
	end
	if PlayerDataService.IsCarrying(player) then
		if not auto then
			RemoteEvents.FuseAllResult:FireClient(player, { Count = 0, Reason = "Carrying" })
		end
		return
	end
	if not auto then
		local last = state.lastFuseAllAt[player.UserId]
		if last and os.clock() - last < FUSE_ALL_COOLDOWN_SECONDS then
			RemoteEvents.FuseAllResult:FireClient(player, { Count = 0, Reason = "OnCooldown" })
			return
		end
		state.lastFuseAllAt[player.UserId] = os.clock()
	end

	local count, upgradedCount = 0, 0
	local gained: { [string]: number } = {}
	local consumed: { [string]: number } = {}
	local best: InventoryItem? = nil
	local newIndexItems: { InventoryItem } = {}
	local tiersCompleted: { string } = {}

	while count < FusionConfig.FuseAllMaxFusions do
		local itemA, itemB = findFuseAllPair(player)
		if not itemA or not itemB then
			break
		end
		local consumedTier = itemA.Tier
		-- Always a pair (count 2) of unmutated items, at the count-2 chance.
		local outcome = fuseOnce(player, { itemA, itemB })
		if not outcome then
			break
		end
		-- On a fail Entry is the kept input: one of the two consumed counts
		-- back, so the summary's net change is the same either way.
		local newEntry = outcome.Entry
		count += 1
		if outcome.Upgraded then
			upgradedCount += 1
		end
		if outcome.IsNewIndex then
			table.insert(newIndexItems, newEntry)
			local tier = completedTier(player, newEntry, true)
			if tier then
				table.insert(tiersCompleted, tier)
			end
		end
		consumed[consumedTier] = (consumed[consumedTier] or 0) + FusionConfig.MinFusionInputs
		gained[newEntry.Tier] = (gained[newEntry.Tier] or 0) + 1
		if not best or (ItemConfig.Tiers[newEntry.Tier] or 0) > (ItemConfig.Tiers[best.Tier] or 0) then
			best = newEntry
		end
	end

	if count == 0 then
		if not auto then
			RemoteEvents.FuseAllResult:FireClient(player, { Count = 0 })
		end
		return
	end

	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	PlayerDataService.SyncTycoon(player)
	RemoteEvents.FuseAllResult:FireClient(player, {
		Count = count,
		Upgraded = upgradedCount,
		Gained = gained,
		Consumed = consumed,
		Best = best,
		NewIndexItems = newIndexItems,
		IndexTiersCompleted = tiersCompleted,
		Auto = auto,
	})

	-- Only the single best result is announced, and only if it's Legendary+.
	if best then
		announce(player, best)
	end
end

local function onFuseAllRequest(player: Player)
	runFuseAll(player, false)
end

--[[ Public ------------------------------------------------------------- ]]

-- Auto-Fuse (the pass, toggled in the Fuse panel): Fuse All by itself when
-- new items arrive (TycoonService calls it after a pull). Same rules as
-- Fuse All: pairs, Common-Epic, never mutated, never a carried item.
function FusionService.RunAutoFuse(player: Player)
	if not PlayerDataService.IsDataLoaded(player) or not PlayerDataService.OwnsPass(player, "AutoFuse") then
		return
	end
	local data = PlayerDataService.GetData(player)
	if not data or not data.Settings.AutoFuse then
		return
	end
	runFuseAll(player, true)
end

local function onPlayerRemoving(player: Player)
	state.lastFusionAt[player.UserId] = nil
	state.lastFuseAllAt[player.UserId] = nil
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function FusionService:Init()
	table.insert(state.connections, RemoteEvents.RequestFusion.OnServerEvent:Connect(onFusionRequest))
	table.insert(state.connections, RemoteEvents.RequestFuseAll.OnServerEvent:Connect(onFuseAllRequest))
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

-- Auto-Fuse runs this long after a pull, so the pull's own reveal shows first.
local AUTO_FUSE_DELAY_SECONDS = 1.5

function FusionService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	EventService = require(script.Parent.EventService)
	local TycoonService = require(script.Parent.TycoonService)
	TycoonService.OnPull(function(player: Player)
		task.delay(AUTO_FUSE_DELAY_SECONDS, FusionService.RunAutoFuse, player)
	end)
end

return FusionService
