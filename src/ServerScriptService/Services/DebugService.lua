-- STUDIO-ONLY debug commands for testing balance changes that a saved
-- player profile would otherwise hide (e.g. a carried-over Multiplier Pad
-- level blocking you from ever seeing Level 1's real cost again). Gated by
-- RunService:IsStudio() so this is structurally inert in a published game -
-- not a toggle to remember to flip off, it simply never runs there. Not a
-- player-facing feature; delete this file if it's no longer needed.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local PlayerDataService = require(script.Parent.PlayerDataService)

local DebugService = {}

local RESET_MULTIPLIER_COMMAND = "/resetmultiplier"

-- Mirrors TycoonService's own syncTycoon payload shape so the client's cash/
-- multiplier state actually reflects the reset immediately, rather than only
-- on the next unrelated sync.
local function syncTycoon(player: Player)
	RemoteEvents.SyncTycoon:FireClient(player, {
		Cash = PlayerDataService.GetCash(player),
		Generators = PlayerDataService.GetGenerators(player) or {},
		CashMultiplierLevel = PlayerDataService.GetCashMultiplierLevel(player),
		PedestalDisplays = PlayerDataService.GetPedestalDisplays(player),
	})
end

local function onPlayerChatted(player: Player, message: string)
	if message:lower() ~= RESET_MULTIPLIER_COMMAND then
		return
	end
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end

	PlayerDataService.SetCashMultiplierLevel(player, 0)
	syncTycoon(player)

	-- The Multiplier Pad's own billboard only refreshes on the next
	-- purchase attempt, not on an external data change like this - it'll
	-- show stale text (e.g. "MAX LEVEL") until you touch it once, at which
	-- point the purchase (and its price) will correctly reflect level 0.
	print(("DebugService: reset %s's Multiplier Pad level to 0 (pad billboard updates on next touch)"):format(player.Name))
end

local function connectPlayer(player: Player)
	player.Chatted:Connect(function(message: string)
		onPlayerChatted(player, message)
	end)
end

function DebugService.Init()
	if not RunService:IsStudio() then
		return
	end

	for _, player in Players:GetPlayers() do
		connectPlayer(player)
	end
	Players.PlayerAdded:Connect(connectPlayer)

	print(("DebugService: Studio debug commands active (%s)"):format(RESET_MULTIPLIER_COMMAND))
end

return DebugService
