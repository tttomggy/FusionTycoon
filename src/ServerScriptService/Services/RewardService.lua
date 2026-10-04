--!strict
--[[
	RewardService
	-------------
	Free rewards: the 7-day daily reward (DailyConfig) and the playtime
	gifts (GiftConfig). Every reward kind (RewardConfig) is granted here,
	from the server's own config: the client only asks.

	  ClaimDaily (C→S, no payload): today's day and reward come from
	  PlayerData.Daily and the server's UTC day (DailyConfig.GetStatus).
	  The claim is recorded and the reward granted with no yield between,
	  so a double tap finds the day already claimed. DailyResult answers.

	  ClaimGift { Index } (C→S): the gift must be open by today's play time
	  (PlayerData.Gifts.PlaySeconds, ticked here once a second while the
	  player is in game; a new UTC day starts a fresh set) and not claimed.
	  GiftResult answers.

	Free pulls and reward items go through TycoonService.GrantFreePulls /
	GrantRewardItem (the real pull path and reveal). Region-restricted
	players get every reward: they're free, nothing is sold.

	Follows ServiceTemplate:
	  :Init()   connects ClaimDaily, ClaimGift and the play-time tick.
	  :Start()  resolves PlayerDataService and TycoonService.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DailyConfig = require(ReplicatedStorage.Shared.Config.DailyConfig)
local GiftConfig = require(ReplicatedStorage.Shared.Config.GiftConfig)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))

type State = {
	connections: { RBXScriptConnection },
	-- os.clock() of each player's last claim request (any kind).
	lastRequest: { [number]: number },
	rng: Random,
	-- Seconds since the last play-time tick.
	tickElapsed: number,
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	connections = {},
	lastRequest = {},
	rng = Random.new(),
	tickElapsed = 0,
}

local DEBOUNCE_SECONDS = 0.5
local PLAY_TICK_SECONDS = 1

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule

local RewardService = {}

RewardService.Name = "RewardService"

--[[ Private helpers ------------------------------------------------------ ]]

local function debounced(player: Player): boolean
	local now = os.clock()
	local last = state.lastRequest[player.UserId]
	if last and now - last < DEBOUNCE_SECONDS then
		return true
	end
	state.lastRequest[player.UserId] = now
	return false
end

-- Pulls and items need the player's plot (the pull path); everything else
-- can always be given.
local function canGrant(player: Player, reward: RewardConfig.Reward): boolean
	if reward.Kind == "Pulls" or reward.Kind == "Item" then
		return TycoonService.GetPlotForPlayer(player) ~= nil
	end
	return true
end

-- Grants `reward` (checked with canGrant first). `caption` names it on a
-- pull card; `source` ("Daily" / "Gift") tags its analytics. Returns the lines the client shows. Synchronous except that
-- the pull path fires its own result remote.
local function grant(player: Player, reward: RewardConfig.Reward, caption: string, source: string): { string }
	local kind = reward.Kind
	if kind == "Cash" then
		local amount = RewardConfig.GetCashAmount(reward, PlayerDataService.GetBasePassiveCashPerSecond(player))
		PlayerDataService.AddCash(player, amount)
		AnalyticsKit.Source(player, amount, Enum.AnalyticsEconomyTransactionType.TimedReward.Name, source)
		return { ("💰 +%s"):format(NumberFormat.Money(amount)) }
	elseif kind == "IncomeBoost" then
		PlayerDataService.AddBoostSeconds(player, "Income", reward.Seconds or 0)
		local banked = PlayerDataService.GetBoostSeconds(player, "Income")
		return { ("⚡ ×%d income · %d min banked"):format(ShopConfig.BoostMultiplier, math.floor(banked / 60)) }
	elseif kind == "LuckBoost" then
		PlayerDataService.AddBoostSeconds(player, "Luck", reward.Seconds or 0)
		local banked = PlayerDataService.GetBoostSeconds(player, "Luck")
		return { ("🍀 ×%d luck · %d min banked"):format(ShopConfig.LuckPotionMultiplier, math.floor(banked / 60)) }
	elseif kind == "SafeFusion" then
		PlayerDataService.AddSafeFusionTokens(player, reward.Count or 1)
		return { ("🛡 Safe Fusion · you have %d"):format(PlayerDataService.GetSafeFusionTokens(player)) }
	elseif kind == "Pulls" then
		local count = reward.Count or 1
		TycoonService.GrantFreePulls(player, count, caption)
		return { ("🎰 %s"):format(RewardConfig.GetTitle(reward)) }
	end
	local odds = reward.Odds
	if odds then
		local tier = RewardConfig.RollTier(odds, state.rng)
		TycoonService.GrantRewardItem(player, tier, caption)
		return { ("🔮 a %s item"):format(tier) }
	end
	return {}
end

local function refuseDaily(player: Player, reason: string)
	RemoteEvents.DailyResult:FireClient(player, { Result = "Refused", Reason = reason })
end

local function onClaimDaily(player: Player)
	if debounced(player) then
		return
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		refuseDaily(player, "NotLoaded")
		return
	end
	local today = RewardConfig.GetUtcDay(os.time())
	local status = DailyConfig.GetStatus(data.Daily, today)
	if not status.CanClaim then
		refuseDaily(player, "Claimed")
		return
	end
	local reward = DailyConfig.GetReward(status.Day)
	if not canGrant(player, reward) then
		refuseDaily(player, "NotReady")
		return
	end
	-- Record, then grant: no yield between, so a second claim is refused.
	local day = DailyConfig.Apply(data.Daily, today)
	local isPull = reward.Kind == "Pulls" or reward.Kind == "Item"
	local caption = if reward.Kind == "Item" then ("🎁 DAY %d REWARD"):format(day) else ("🎁 DAY %d · FREE PULLS"):format(day)
	local lines = grant(player, reward, caption, "Daily")
	AnalyticsKit.Custom(player, "DailyClaimed", day)
	if not isPull then
		-- The pull path syncs itself.
		PlayerDataService.SyncTycoon(player)
	end
	RemoteEvents.DailyResult:FireClient(player, {
		Result = "Granted",
		Day = day,
		Streak = data.Daily.Streak,
		UsedSkip = status.UsesSkip,
		Kind = reward.Kind,
		Lines = lines,
	})
end

--[[ Playtime gifts ------------------------------------------------------- ]]

-- Today's gifts for `data`, rolled over to a fresh set on a new UTC day.
-- Returns true if it rolled over.
local function rollGiftDay(data: any, today: number): boolean
	if data.Gifts.UtcDay ~= today then
		data.Gifts = GiftConfig.Default(today)
		return true
	end
	return false
end

local function onPlayTick(dt: number)
	state.tickElapsed += dt
	if state.tickElapsed < PLAY_TICK_SECONDS then
		return
	end
	local elapsed = state.tickElapsed
	state.tickElapsed = 0
	local today = RewardConfig.GetUtcDay(os.time())
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService.GetData(player)
		if data then
			local rolled = rollGiftDay(data, today)
			data.Gifts.PlaySeconds += elapsed
			if rolled then
				-- A new day: the client's gift clock starts again.
				PlayerDataService.SyncTycoon(player)
			end
		end
	end
end

local function refuseGift(player: Player, index: number?, reason: string)
	RemoteEvents.GiftResult:FireClient(player, { Result = "Refused", Index = index, Reason = reason })
end

local function onClaimGift(player: Player, payload: unknown)
	if debounced(player) then
		return
	end
	local rawIndex = if typeof(payload) == "table" then (payload :: any).Index else nil
	if typeof(rawIndex) ~= "number" or not GiftConfig.Gifts[rawIndex] then
		return
	end
	local index = rawIndex :: number
	local data = PlayerDataService.GetData(player)
	if not data then
		refuseGift(player, index, "NotLoaded")
		return
	end
	rollGiftDay(data, RewardConfig.GetUtcDay(os.time()))
	local gifts = data.Gifts
	if GiftConfig.IsClaimed(gifts.Claimed, index) then
		refuseGift(player, index, "Claimed")
		return
	end
	if not GiftConfig.IsReady(gifts.PlaySeconds, gifts.Claimed, index) then
		refuseGift(player, index, "NotYet")
		return
	end
	local reward = GiftConfig.Gifts[index].Reward
	if not canGrant(player, reward) then
		refuseGift(player, index, "NotReady")
		return
	end
	-- Record, then grant: no yield between.
	table.insert(gifts.Claimed, index)
	local isPull = reward.Kind == "Pulls" or reward.Kind == "Item"
	local caption = if reward.Kind == "Item" then "🎁 PLAYTIME GIFT" else "🎁 GIFT · FREE PULL"
	local lines = grant(player, reward, caption, "Gift")
	AnalyticsKit.Custom(player, "GiftClaimed", index)
	if not isPull then
		PlayerDataService.SyncTycoon(player)
	end
	RemoteEvents.GiftResult:FireClient(player, {
		Result = "Granted",
		Index = index,
		Kind = reward.Kind,
		Lines = lines,
	})
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function RewardService:Init()
	table.insert(state.connections, RemoteEvents.ClaimDaily.OnServerEvent:Connect(onClaimDaily))
	table.insert(state.connections, RemoteEvents.ClaimGift.OnServerEvent:Connect(onClaimGift))
	table.insert(state.connections, RunService.Heartbeat:Connect(function(dt: number)
		-- Nothing to tick until Start has resolved PlayerDataService.
		if PlayerDataService then
			onPlayTick(dt)
		end
	end))
end

function RewardService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)
end

function RewardService:Stop()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
	table.clear(state.lastRequest)
end

return RewardService
