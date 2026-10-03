--!strict
--[[
	OfflineService
	--------------
	Pays offline earnings. PlayerDataService computes them on load
	(OfflineConfig: 25% of passive income for up to 4 h away, nothing under
	2 min) and ships them in the snapshot; the welcome-back card's COLLECT
	fires ClaimOffline. The client never sends an amount: the server pays
	whatever is pending, once.

	Never lost: if the player closes the card or ignores it, the first sync
	(every payout tick syncs) after OfflineConfig.AutoClaimSeconds pays it,
	and leaving before that pays it on PlayerRemoving (PlayerDataService).

	Follows ServiceTemplate:
	  :Init()   connects ClaimOffline and PlayerRemoving.
	  :Start()  resolves PlayerDataService, registers the auto-claim OnSync hook.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OfflineConfig = require(ReplicatedStorage.Shared.Config.OfflineConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))

type State = {
	connections: { RBXScriptConnection },
	-- os.clock() of each player's last ClaimOffline.
	lastRequest: { [number]: number },
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	connections = {},
	lastRequest = {},
}

local DEBOUNCE_SECONDS = 1

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule

local OfflineService = {}

OfflineService.Name = "OfflineService"

--[[ Private helpers ------------------------------------------------------ ]]

local function onClaimOffline(player: Player)
	local now = os.clock()
	local last = state.lastRequest[player.UserId]
	if last and now - last < DEBOUNCE_SECONDS then
		return
	end
	state.lastRequest[player.UserId] = now
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	-- Take and pay with no yield between them: a second claim finds 0.
	local amount = PlayerDataService.TakePendingOffline(player)
	if amount <= 0 then
		return
	end
	PlayerDataService.AddCash(player, amount)
	PlayerDataService.SyncTycoon(player)
end

-- OnSync hook: runs before the snapshot is built, so the payout ships in it.
local function autoClaim(player: Player)
	local pending = PlayerDataService.GetPendingOffline(player)
	if pending and os.clock() - pending.Since >= OfflineConfig.AutoClaimSeconds then
		PlayerDataService.AddCash(player, PlayerDataService.TakePendingOffline(player))
	end
end

local function onPlayerRemoving(player: Player)
	state.lastRequest[player.UserId] = nil
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function OfflineService:Init()
	table.insert(state.connections, RemoteEvents.ClaimOffline.OnServerEvent:Connect(onClaimOffline))
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

function OfflineService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	PlayerDataService.OnSync(autoClaim)
end

function OfflineService:Stop()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
	table.clear(state.lastRequest)
end

return OfflineService
