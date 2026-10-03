--!nonstrict
-- STUDIO-ONLY debug commands for testing balance changes that a saved
-- player profile would otherwise hide (e.g. a carried-over Multiplier Pad
-- level blocking you from ever seeing Level 1's real cost again). Gated by
-- RunService:IsStudio() so this is structurally inert in a published game -
-- not a toggle to remember to flip off, it simply never runs there. Not a
-- player-facing feature; delete this file if it's no longer needed.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local OfflineConfig = require(ReplicatedStorage.Shared.Config.OfflineConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)


--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))

type State = {
	connections: { RBXScriptConnection },
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	connections = {},
}

-- Resolved in :Start(), not at module scope. Identifier name unchanged, so
-- call sites below read exactly as before.
local PlayerDataService: PlayerDataServiceModule

local DebugService = {}

DebugService.Name = "DebugService"

local RESET_MULTIPLIER_COMMAND = "/resetmultiplier"
-- "/cash 50000" adds $50,000. Handy for testing late-game balance without
-- grinding. Studio only.
local CASH_COMMAND = "/cash"
-- "/wipe" resets your whole profile to a fresh save (Studio only).
local WIPE_COMMAND = "/wipe"
-- "/rebirthready" sets cash to the next rebirth's price.
local REBIRTH_READY_COMMAND = "/rebirthready"
-- "/rebirths 3" sets the rebirth count.
local REBIRTHS_COMMAND = "/rebirths"
-- "/give legendary_core golden" adds an item (optionally mutated) without
-- needing the luck: mutations, Secrets and the Index are testable.
local GIVE_COMMAND = "/give"
-- "/offline 180" pretends you were away 180 minutes: sets the pending
-- offline earnings and re-sends the snapshot, so the welcome-back card can
-- be tested (Studio profiles never save, so a real absence can't be).
local OFFLINE_COMMAND = "/offline"

local function onPlayerChatted(player: Player, message: string)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	local lower = message:lower()
	local command, argument = lower:match("^(%S+)%s*(.*)$")

	if command == RESET_MULTIPLIER_COMMAND then
		PlayerDataService.SetCashMultiplierLevel(player, 0)
		PlayerDataService.SyncTycoon(player)
		print(("DebugService: reset %s's Multiplier Pad level to 0 (pad label updates on next touch)"):format(player.Name))
	elseif command == CASH_COMMAND then
		local amount = tonumber(argument) or 1000000
		PlayerDataService.AddCash(player, amount)
		PlayerDataService.SyncTycoon(player)
		print(("DebugService: gave %s $%s"):format(player.Name, tostring(amount)))
	elseif command == REBIRTH_READY_COMMAND then
		local cost = RebirthConfig.GetCost(PlayerDataService.GetRebirths(player))
		PlayerDataService.AddCash(player, cost - PlayerDataService.GetCash(player))
		PlayerDataService.SyncTycoon(player)
		print(("DebugService: %s's cash set to %s (rebirth ready)"):format(player.Name, tostring(cost)))
	elseif command == REBIRTHS_COMMAND then
		local count = tonumber(argument)
		if count then
			PlayerDataService.SetRebirths(player, count)
			PlayerDataService.SyncTycoon(player)
			print(("DebugService: %s's rebirths set to %d"):format(player.Name, math.floor(count)))
		end
	elseif command == GIVE_COMMAND then
		local itemId, rawMutation = argument:match("^(%S+)%s*(%S*)$")
		local def = itemId and ItemConfig.GetItemById(itemId)
		if not def then
			warn(("DebugService: /give: unknown item id %q"):format(tostring(itemId)))
			return
		end
		-- Chat is lowercased above; mutations are "Golden", "Diamond", "Rainbow".
		local mutation = if rawMutation ~= "" then rawMutation:sub(1, 1):upper() .. rawMutation:sub(2) else nil
		if mutation and not MutationConfig.IsValid(mutation) then
			warn(("DebugService: /give: unknown mutation %q"):format(rawMutation))
			return
		end
		PlayerDataService.AddItem(player, def.Id, def.Tier, mutation)
		RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
		PlayerDataService.SyncTycoon(player)
		print(("DebugService: gave %s a %s"):format(player.Name, MutationConfig.GetDisplayName(def.Name, mutation)))
	elseif command == OFFLINE_COMMAND then
		local minutes = tonumber(argument) or 180
		local awaySeconds = math.max(0, math.floor(minutes * 60))
		local amount = OfflineConfig.Compute(PlayerDataService.GetPassiveCashPerSecond(player), awaySeconds)
		PlayerDataService.SetPendingOffline(player, amount, awaySeconds)
		PlayerDataService.SyncTycoon(player)
		print(("DebugService: %s away %d min -> pending %s"):format(player.Name, math.floor(minutes), tostring(amount)))
	elseif command == WIPE_COMMAND then
		local data = PlayerDataService.GetData(player)
		if data then
			data.Cash = 0
			data.Inventory = {}
			data.Generators = {}
			data.CashMultiplierLevel = 0
			data.PedestalDisplays = {}
			data.GachaPulls = 0
			data.GoalIndex = 1
			data.TotalFusions = 0
			data.Rebirths = 0
			data.Index = {}
			data.LastOnline = nil
		end
		PlayerDataService.SetPendingOffline(player, 0, 0)
		player:Kick("Profile wiped (Studio debug). Press Play again.")
	end
end

local function connectPlayer(player: Player)
	table.insert(
		state.connections,
		player.Chatted:Connect(function(message: string)
			onPlayerChatted(player, message)
		end)
	)
end

function DebugService:Init()
	if not RunService:IsStudio() then
		return
	end

	for _, player in Players:GetPlayers() do
		connectPlayer(player)
	end
	table.insert(state.connections, Players.PlayerAdded:Connect(connectPlayer))

	print("DebugService: Studio commands active: /cash <amount>, /resetmultiplier, /rebirthready, /rebirths <n>, /give <itemId> [mutation], /offline <minutes>, /wipe")
end

function DebugService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
end

return DebugService
