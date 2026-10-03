--!strict
--[[
	RebirthService
	--------------
	Handles RequestRebirth. A rebirth costs cash: once the player holds
	RebirthConfig.GetCost(Rebirths), they can reset:

	  * Cash -> 0 (which pays the price), generators -> Basic at TycoonConfig's starting level,
	    Multiplier Pad -> 0, gacha pulls (price) -> 0
	  * Rebirths += 1 (income x(1 + 0.5n), luck x(1 + 0.05n))
	  * KEPT: inventory, pedestals, goals and everything else.

	The check and every write happen with no yield between them
	(PlayerDataService.ApplyRebirth). SyncTycoon then refreshes the whole plot
	through TycoonService's OnSync hook (generator states, pad and gacha
	labels, collector, portal, pedestal labels), and GoalService's hook pays
	"first_rebirth" into the new run.

	Follows ServiceTemplate:
	  :Init()   connects RequestRebirth and PlayerRemoving.
	  :Start()  resolves PlayerDataService and TycoonService.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))

type State = {
	connections: { RBXScriptConnection },
	-- os.clock() of each player's last rebirth request.
	lastRequest: { [number]: number },
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	connections = {},
	lastRequest = {},
}

local DEBOUNCE_SECONDS = 2

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule

local RebirthService = {}

RebirthService.Name = "RebirthService"

--[[ Private helpers ------------------------------------------------------ ]]

local function reject(player: Player, reason: string)
	RemoteEvents.RebirthResult:FireClient(player, { Success = false, Reason = reason })
end

local function onRequestRebirth(player: Player)
	local now = os.clock()
	local last = state.lastRequest[player.UserId]
	if last and now - last < DEBOUNCE_SECONDS then
		reject(player, "TooFast")
		return
	end
	state.lastRequest[player.UserId] = now

	if not PlayerDataService.IsDataLoaded(player) then
		reject(player, "DataNotLoaded")
		return
	end
	local plot = TycoonService.GetPlotForPlayer(player)
	if not plot or plot:GetAttribute("Claimed") ~= true then
		reject(player, "NoPlot")
		return
	end
	local cost = RebirthConfig.GetCost(PlayerDataService.GetRebirths(player))
	if PlayerDataService.GetCash(player) < cost then
		reject(player, "NotReady")
		return
	end

	-- No yields from the checks above to the last write in ApplyRebirth.
	local rebirths = PlayerDataService.ApplyRebirth(player, TycoonConfig.StartingBasicGeneratorLevel)

	-- The OnSync hooks restyle the plot and pay first_rebirth.
	PlayerDataService.SyncTycoon(player)
	RemoteEvents.RebirthResult:FireClient(player, { Success = true, Rebirths = rebirths })
	RemoteEvents.RebirthAnnouncement:FireAllClients({ Name = player.DisplayName, Rebirths = rebirths })
	PlayerDataService.SaveNow(player)
end

local function onPlayerRemoving(player: Player)
	state.lastRequest[player.UserId] = nil
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function RebirthService:Init()
	table.insert(state.connections, RemoteEvents.RequestRebirth.OnServerEvent:Connect(onRequestRebirth))
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

function RebirthService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)
end

function RebirthService:Stop()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
	table.clear(state.lastRequest)
end

return RebirthService
