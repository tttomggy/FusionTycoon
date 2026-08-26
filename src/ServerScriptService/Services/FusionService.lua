local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local FusionConfig = require(Config.FusionConfig)
local ItemConfig = require(Config.ItemConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

local PlayerDataService = require(script.Parent.PlayerDataService)

local FusionService = {}

local FUSION_COOLDOWN_SECONDS = 1.5

-- Ephemeral, session-only cooldown tracking; not persisted with player data.
local lastFusionAt: { [number]: number } = {}

local function isOnCooldown(userId: number): boolean
	local lastTime = lastFusionAt[userId]
	return lastTime ~= nil and (os.clock() - lastTime) < FUSION_COOLDOWN_SECONDS
end

local function pickRewardItem(tier: string)
	local itemsOfTier = ItemConfig.GetItemsByTier(tier)
	if #itemsOfTier == 0 then
		return nil
	end
	return itemsOfTier[math.random(1, #itemsOfTier)]
end

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

	-- An item on display on a Pedestal Showcase can't also be fused away -
	-- otherwise the pedestal would be left showing an item that no longer
	-- exists in the player's inventory.
	if itemA.InUse or itemB.InUse then
		reject(player, "ItemInUse", true)
		return
	end

	lastFusionAt[player.UserId] = os.clock()
	local consumedTier = itemA.Tier :: string

	-- Inputs are consumed before the roll: fusion is a gamble, and a failed
	-- roll still costs the two items.
	local removed = PlayerDataService.RemoveItemsByUid(player, { uidA, uidB })
	if not removed then
		reject(player, "ItemNotOwned")
		return
	end
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))

	local resultTier = FusionConfig.RollResultTier()
	local rewardItem = pickRewardItem(resultTier)
	if not rewardItem then
		warn(("FusionService: no ItemConfig entry found for tier %s"):format(resultTier))
		reject(player, "MissingRewardItem")
		return
	end

	local newEntry = PlayerDataService.AddItem(player, rewardItem.Id, rewardItem.Tier)
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))

	print(("FusionService: %s fused 2x %s into %s (%s)"):format(player.Name, consumedTier, rewardItem.Name, resultTier))

	RemoteEvents.FusionResult:FireClient(player, {
		Success = true,
		ConsumedUids = { uidA, uidB },
		ConsumedTier = consumedTier,
		NewItem = newEntry,
	})
end

function FusionService.Init()
	RemoteEvents.RequestFusion.OnServerEvent:Connect(onFusionRequest)
end

return FusionService
