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

local function onFusionRequest(player: Player, tier: unknown)
	if typeof(tier) ~= "string" or not FusionConfig.DropRates[tier] then
		RemoteEvents.FusionResult:FireClient(player, { Success = false, Reason = "InvalidTier" })
		return
	end

	if not PlayerDataService.IsDataLoaded(player) then
		RemoteEvents.FusionResult:FireClient(player, { Success = false, Reason = "DataNotLoaded" })
		return
	end

	if isOnCooldown(player.UserId) then
		RemoteEvents.FusionResult:FireClient(player, { Success = false, Reason = "OnCooldown" })
		return
	end

	local nextTier = FusionConfig.GetNextTier(tier)
	local requiredCount = FusionConfig.ItemsRequiredForFusion[tier]
	if not nextTier or not requiredCount then
		RemoteEvents.FusionResult:FireClient(player, { Success = false, Reason = "TierNotFusible" })
		return
	end

	if PlayerDataService.CountItemsOfTier(player, tier) < requiredCount then
		RemoteEvents.FusionResult:FireClient(player, { Success = false, Reason = "InsufficientItems" })
		return
	end

	lastFusionAt[player.UserId] = os.clock()

	local removed, removedUids = PlayerDataService.RemoveItemsOfTier(player, tier, requiredCount)
	if not removed then
		RemoteEvents.FusionResult:FireClient(player, { Success = false, Reason = "InsufficientItems" })
		return
	end

	-- Inputs are consumed before the roll: fusion is a gamble, failure loses the items.
	local succeeded, resolvedNextTier = FusionConfig.AttemptFusion(tier)
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))

	if not succeeded then
		RemoteEvents.FusionResult:FireClient(player, {
			Success = false,
			Reason = "FusionFailed",
			ConsumedUids = removedUids,
		})
		return
	end

	local rewardItem = pickRewardItem(resolvedNextTier :: string)
	if not rewardItem then
		warn(("FusionService: no ItemConfig entry found for tier %s"):format(resolvedNextTier :: string))
		RemoteEvents.FusionResult:FireClient(player, {
			Success = false,
			Reason = "MissingRewardItem",
			ConsumedUids = removedUids,
		})
		return
	end

	local newEntry = PlayerDataService.AddItem(player, rewardItem.Id, rewardItem.Tier)
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))

	RemoteEvents.FusionResult:FireClient(player, {
		Success = true,
		ConsumedUids = removedUids,
		NewItem = newEntry,
	})
end

function FusionService.Init()
	RemoteEvents.RequestFusion.OnServerEvent:Connect(onFusionRequest)
end

return FusionService
