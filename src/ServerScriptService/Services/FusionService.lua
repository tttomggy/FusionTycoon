local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local FusionConfig = require(Config.FusionConfig)
local ItemConfig = require(Config.ItemConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

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
	local fusionResult = Remotes.Get("FusionResult")

	if typeof(tier) ~= "string" or not FusionConfig.DropRates[tier] then
		fusionResult:FireClient(player, { Success = false, Reason = "InvalidTier" })
		return
	end

	if not PlayerDataService.IsDataLoaded(player) then
		fusionResult:FireClient(player, { Success = false, Reason = "DataNotLoaded" })
		return
	end

	if isOnCooldown(player.UserId) then
		fusionResult:FireClient(player, { Success = false, Reason = "OnCooldown" })
		return
	end

	local nextTier = FusionConfig.GetNextTier(tier)
	local requiredCount = FusionConfig.ItemsRequiredForFusion[tier]
	if not nextTier or not requiredCount then
		fusionResult:FireClient(player, { Success = false, Reason = "TierNotFusible" })
		return
	end

	if PlayerDataService.CountItemsOfTier(player, tier) < requiredCount then
		fusionResult:FireClient(player, { Success = false, Reason = "InsufficientItems" })
		return
	end

	lastFusionAt[player.UserId] = os.clock()

	local removed, removedUids = PlayerDataService.RemoveItemsOfTier(player, tier, requiredCount)
	if not removed then
		fusionResult:FireClient(player, { Success = false, Reason = "InsufficientItems" })
		return
	end

	-- Inputs are consumed before the roll: fusion is a gamble, failure loses the items.
	local succeeded, resolvedNextTier = FusionConfig.AttemptFusion(tier)

	if not succeeded then
		fusionResult:FireClient(player, {
			Success = false,
			Reason = "FusionFailed",
			ConsumedUids = removedUids,
		})
		return
	end

	local rewardItem = pickRewardItem(resolvedNextTier :: string)
	if not rewardItem then
		warn(("FusionService: no ItemConfig entry found for tier %s"):format(resolvedNextTier :: string))
		fusionResult:FireClient(player, {
			Success = false,
			Reason = "MissingRewardItem",
			ConsumedUids = removedUids,
		})
		return
	end

	local newEntry = PlayerDataService.AddItem(player, rewardItem.Id, rewardItem.Tier)

	fusionResult:FireClient(player, {
		Success = true,
		ConsumedUids = removedUids,
		NewItem = newEntry,
	})
end

function FusionService.Init()
	local fusionRequest = Remotes.Get("FusionRequest")
	fusionRequest.OnServerEvent:Connect(onFusionRequest)
end

return FusionService
