--!strict
--[[
	FusionService
	-------------
	Server-authoritative fusion: validates a two-item fusion request against
	the player's real inventory, consumes the inputs, and rolls for an upgrade.

	Two items of tier N -> success: one item of tier N+1
	                    -> fail:    one item of tier N back
	Odds per tier live in FusionConfig.SuccessChance.

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
local RarityVisuals = require(Config.RarityVisuals)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))

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
local function reject(player: Player, reason: string, isSuspicious: boolean?)
	if isSuspicious then
		warn(("FusionService: rejected fusion request from %s (%s)"):format(player.Name, reason))
	end
	RemoteEvents.FusionResult:FireClient(player, { Success = false, Reason = reason })
end

type InventoryItem = { Uid: string, ItemId: string, Tier: string, InUse: boolean }

-- Fuses two already-validated, same-tier, not-in-use items: rolls, picks the
-- result item, removes both inputs, adds the result and counts the fusion.
-- Fires no remotes. Returns (upgraded, newEntry), or (false, nil, reason)
-- if nothing changed. Synchronous (no yields), so callers stay atomic.
local function fuseOnce(player: Player, itemA: InventoryItem, itemB: InventoryItem): (boolean, InventoryItem?, string?)
	local consumedTier = itemA.Tier
	local nextTier = FusionConfig.GetNextTier(consumedTier)
	local successChance = FusionConfig.SuccessChance[consumedTier]
	if not nextTier or not successChance then
		return false, nil, "MaxTier"
	end

	-- Roll and pick the result item BEFORE touching the inventory, so a
	-- config gap can never eat the player's two items.
	local upgraded = rng:NextNumber() < successChance
	local resultTier = if upgraded then nextTier else consumedTier
	local rewardItem = ItemConfig.PickRandomOfTier(resultTier, rng)
	if not rewardItem then
		warn(("FusionService: no ItemConfig entry found for tier %s"):format(resultTier))
		return false, nil, "MissingRewardItem"
	end

	local removed = PlayerDataService.RemoveItemsByUid(player, { itemA.Uid, itemB.Uid })
	if not removed then
		return false, nil, "ItemNotOwned"
	end

	local newEntry = PlayerDataService.AddItem(player, rewardItem.Id, rewardItem.Tier)
	PlayerDataService.IncrementTotalFusions(player)
	return upgraded, newEntry, nil
end

-- Server-wide brag for a Legendary/Mythic/Secret result: the moment everyone else
-- in the server sees and wants for themselves.
local function announce(player: Player, item: InventoryItem)
	local visual = RarityVisuals.Tiers[item.Tier]
	if not visual or not visual.AnnounceServerWide then
		return
	end
	local def = ItemConfig.GetItemById(item.ItemId)
	local itemName = if def then def.Name else item.ItemId
	RemoteEvents.RareFusionAnnouncement:FireAllClients({
		Message = ("%s fused a %s %s!"):format(player.DisplayName, item.Tier:upper(), itemName),
		Tier = item.Tier,
		-- Parts, so the client can colour the tier word.
		PlayerName = player.DisplayName,
		Verb = "fused",
		ItemName = itemName,
	})
end

-- Validates and resolves a fusion attempt entirely synchronously (no yields
-- between the ownership check and the inventory mutation), so two requests
-- from the same player can never both pass validation against the same items.
local function onFusionRequest(player: Player, rawUidA: unknown, rawUidB: unknown)
	if typeof(rawUidA) ~= "string" or typeof(rawUidB) ~= "string" then
		reject(player, "InvalidItems", true)
		return
	end
	local uidA, uidB = rawUidA :: string, rawUidB :: string

	if uidA == uidB then
		reject(player, "DuplicateItem", true)
		return
	end

	if not PlayerDataService.IsDataLoaded(player) then
		reject(player, "DataNotLoaded")
		return
	end

	if isOnCooldown(player.UserId) then
		reject(player, "OnCooldown")
		return
	end

	-- Never trust client-supplied tiers/ownership: look both items up fresh
	-- from the player's authoritative server-side inventory.
	local itemA = PlayerDataService.GetItemByUid(player, uidA)
	local itemB = PlayerDataService.GetItemByUid(player, uidB)
	if not itemA or not itemB then
		reject(player, "ItemNotOwned", true)
		return
	end

	if itemA.Tier ~= itemB.Tier then
		reject(player, "TierMismatch", true)
		return
	end

	-- An item on a pedestal can't also be fused away - the pedestal would be
	-- left showing an item that no longer exists.
	if itemA.InUse or itemB.InUse then
		reject(player, "ItemInUse", true)
		return
	end

	-- Secret (top tier) can't be fused; the client never offers it, so a
	-- request for it is a modified client.
	if not FusionConfig.CanFuseTier(itemA.Tier) then
		reject(player, "MaxTier", true)
		return
	end
	-- Mythic -> Secret needs RebirthConfig.SecretFusionRebirths. The client
	-- shows a lock instead, but its rebirth count could be a sync behind.
	if not FusionConfig.CanFuseTierFor(itemA.Tier, PlayerDataService.GetRebirths(player)) then
		reject(player, "NeedsRebirth")
		return
	end

	local consumedTier = itemA.Tier
	state.lastFusionAt[player.UserId] = os.clock()
	local upgraded, newEntry, failure = fuseOnce(player, itemA, itemB)
	if not newEntry then
		reject(player, failure or "ItemNotOwned")
		return
	end

	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	RemoteEvents.FusionResult:FireClient(player, {
		Success = true,
		Upgraded = upgraded,
		ConsumedUids = { uidA, uidB },
		ConsumedTier = consumedTier,
		NewItem = newEntry,
	})
	-- Fusions change goal progress (TotalFusions, tiers owned). Sent after
	-- the result so a goal banner never lands ahead of the fusion itself.
	PlayerDataService.SyncTycoon(player)

	if upgraded then
		announce(player, newEntry)
	end
end

-- The lowest Fuse All tier with at least two items not on a pedestal, and
-- the first two of them.
local function findFuseAllPair(player: Player): (InventoryItem?, InventoryItem?)
	local inventory = PlayerDataService.GetInventory(player)
	if not inventory then
		return nil, nil
	end
	for _, tier in FusionConfig.GetFuseAllTiers() do
		local first: InventoryItem? = nil
		for _, item in inventory do
			if item.Tier == tier and not item.InUse then
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
-- then sends ONE inventory sync, ONE tycoon sync and one summary.
local function onFuseAllRequest(player: Player)
	if not PlayerDataService.IsDataLoaded(player) then
		RemoteEvents.FuseAllResult:FireClient(player, { Count = 0 })
		return
	end
	local last = state.lastFuseAllAt[player.UserId]
	if last and os.clock() - last < FUSE_ALL_COOLDOWN_SECONDS then
		RemoteEvents.FuseAllResult:FireClient(player, { Count = 0, Reason = "OnCooldown" })
		return
	end
	state.lastFuseAllAt[player.UserId] = os.clock()

	local count, upgradedCount = 0, 0
	local gained: { [string]: number } = {}
	local consumed: { [string]: number } = {}
	local best: InventoryItem? = nil

	while count < FusionConfig.FuseAllMaxFusions do
		local itemA, itemB = findFuseAllPair(player)
		if not itemA or not itemB then
			break
		end
		local consumedTier = itemA.Tier
		local upgraded, newEntry = fuseOnce(player, itemA, itemB)
		if not newEntry then
			break
		end
		count += 1
		if upgraded then
			upgradedCount += 1
		end
		consumed[consumedTier] = (consumed[consumedTier] or 0) + FusionConfig.ItemsRequiredPerFusion
		gained[newEntry.Tier] = (gained[newEntry.Tier] or 0) + 1
		if not best or (ItemConfig.Tiers[newEntry.Tier] or 0) > (ItemConfig.Tiers[best.Tier] or 0) then
			best = newEntry
		end
	end

	if count == 0 then
		RemoteEvents.FuseAllResult:FireClient(player, { Count = 0 })
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
	})

	-- Only the single best result is announced, and only if it's Legendary+.
	if best then
		announce(player, best)
	end
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

function FusionService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
end

return FusionService
