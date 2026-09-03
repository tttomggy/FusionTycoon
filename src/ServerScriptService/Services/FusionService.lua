--!strict
--[[
	FusionService
	-------------
	Server-authoritative fusion: validates a two-item fusion request against
	the player's real inventory, consumes the inputs, rolls a result tier, and
	grants the reward.

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
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))

type RewardItem = {
	Id: string,
	Name: string,
	Tier: string,
}

type State = {
	-- Ephemeral, session-only cooldown tracking; not persisted with player data.
	lastFusionAt: { [number]: number },
	connections: { RBXScriptConnection },
}

--[[ Constants ------------------------------------------------------------ ]]

local FUSION_COOLDOWN_SECONDS = 1.5

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	lastFusionAt = {},
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

local function pickRewardItem(tier: string): RewardItem?
	local itemsOfTier = ItemConfig.GetItemsByTier(tier)
	if #itemsOfTier == 0 then
		return nil
	end
	return itemsOfTier[math.random(1, #itemsOfTier)] :: RewardItem
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

	state.lastFusionAt[player.UserId] = os.clock()
	local consumedTier = itemA.Tier

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

local function onPlayerRemoving(player: Player)
	state.lastFusionAt[player.UserId] = nil
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function FusionService:Init()
	table.insert(state.connections, RemoteEvents.RequestFusion.OnServerEvent:Connect(onFusionRequest))
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

function FusionService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
end

return FusionService
