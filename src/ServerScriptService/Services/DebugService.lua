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
local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)


--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type HeistServiceModule = typeof(require(script.Parent.HeistService))
type EventServiceModule = typeof(require(script.Parent.EventService))
type MonetizationServiceModule = typeof(require(script.Parent.MonetizationService))

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
local HeistService: HeistServiceModule
local EventService: EventServiceModule
local MonetizationService: MonetizationServiceModule

-- /stealable is a toggle; remembers each player's current setting.
local stealableToggles: { [number]: boolean } = {}

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
-- "/shield 30" raises your shield for 30 s; "/shield 0" drops it.
local SHIELD_COMMAND = "/shield"
-- "/heistcd 0" clears your thief cooldown.
local HEIST_COOLDOWN_COMMAND = "/heistcd"
-- "/stealable" toggles your lab stealable even at Rebirth 0 (heist testing).
local STEALABLE_COMMAND = "/stealable"
-- "/event powersurge 3" forces an event for 3 min (default its normal
-- length); "/event off" ends what's on. "/eventclock 15" shifts the event
-- clock 15 min ahead so the schedule can be walked through.
local EVENT_COMMAND = "/event"
local EVENT_CLOCK_COMMAND = "/eventclock"
-- "/eventmut void" gives a random Epic with an event-only mutation (Charged,
-- Void, Celestial) through the real reward path, so the reveal card and the
-- banner can be tested (/give skips them).
local EVENT_MUTATION_COMMAND = "/eventmut"
-- "/tips reset" clears your seen one-time tips (TipConfig), so HOW TO HEIST
-- and the heist tips can be re-tested.
local TIPS_COMMAND = "/tips"
-- "/offline 180" pretends you were away 180 minutes: sets the pending
-- offline earnings and re-sends the snapshot, so the welcome-back card can
-- be tested (Studio profiles never save, so a real absence can't be).
local OFFLINE_COMMAND = "/offline"
-- "/shop grant boost" runs the real grant path (MonetizationService) for a
-- ShopConfig key without Robux; "/shop" lists the keys.
local SHOP_COMMAND = "/shop"

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
		-- Chat is lowercased above; mutations are MutationConfig names ("Golden",
		-- "Charged", "Diamond", "Void", "Rainbow", "Celestial").
		local mutation = if rawMutation ~= "" then rawMutation:sub(1, 1):upper() .. rawMutation:sub(2) else nil
		if mutation and not MutationConfig.IsValid(mutation) then
			warn(("DebugService: /give: unknown mutation %q"):format(rawMutation))
			return
		end
		PlayerDataService.AddItem(player, def.Id, def.Tier, mutation)
		RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
		PlayerDataService.SyncTycoon(player)
		print(("DebugService: gave %s a %s"):format(player.Name, MutationConfig.GetDisplayName(def.Name, mutation)))
	elseif command == SHIELD_COMMAND then
		local seconds = tonumber(argument) or HeistConfig.ShieldSeconds
		HeistService.RaiseShield(player, math.max(0, seconds))
		if seconds <= 0 then
			-- /shield 0 also lifts the pad's 20 s re-arm lock, for testing.
			HeistService.ClearRearm(player)
		end
		print(("DebugService: %s's shield set to %s s"):format(player.Name, tostring(seconds)))
	elseif command == HEIST_COOLDOWN_COMMAND then
		HeistService.ClearCooldown(player)
		print(("DebugService: cleared %s's thief cooldown"):format(player.Name))
	elseif command == STEALABLE_COMMAND then
		local stealable = not stealableToggles[player.UserId]
		stealableToggles[player.UserId] = stealable
		HeistService.SetDebugStealable(player, stealable)
		print(("DebugService: %s's lab is %s"):format(player.Name, if stealable then "stealable" else "protected again"))
	elseif command == EVENT_COMMAND then
		local name, rawMinutes = argument:match("^(%S+)%s*(%S*)$")
		if name == "off" then
			EventService.EndEvent()
			print("DebugService: event ended")
			return
		end
		-- Chat is lowercased; match the id case-insensitively.
		local id: string? = nil
		for _, candidate in EventConfig.Order do
			if candidate:lower() == name then
				id = candidate
			end
		end
		if not id then
			warn(("DebugService: /event: unknown event %q (try %s)"):format(tostring(name), table.concat(EventConfig.Order, ", ")))
			return
		end
		local minutes = tonumber(rawMinutes)
		local seconds = if minutes then minutes * 60 else EventConfig.Durations[id]
		EventService.ForceEvent(id, seconds)
		print(("DebugService: forced %s for %d s"):format(id, seconds))
	elseif command == EVENT_CLOCK_COMMAND then
		local minutes = tonumber(argument) or 0
		EventService.SetClockOffset(minutes)
		print(("DebugService: event clock offset %d min"):format(minutes))
	elseif command == EVENT_MUTATION_COMMAND then
		-- The message was lowercased: match the mutation's real name.
		local mutation: string? = nil
		for _, name in MutationConfig.Order do
			if name:lower() == argument and MutationConfig.IsEventOnly(name) then
				mutation = name
			end
		end
		if mutation and EventService.GrantEventMutationItem(player, mutation) then
			print(("DebugService: gave %s a %s Epic"):format(player.Name, mutation))
		else
			warn("DebugService: /eventmut <charged|void|celestial>")
		end
	elseif command == TIPS_COMMAND then
		if argument == "reset" then
			PlayerDataService.ResetTips(player)
			PlayerDataService.SyncTycoon(player)
			print(("DebugService: cleared %s's one-time tips"):format(player.Name))
		end
	elseif command == OFFLINE_COMMAND then
		local minutes = tonumber(argument) or 180
		local awaySeconds = math.max(0, math.floor(minutes * 60))
		local amount = OfflineConfig.Compute(PlayerDataService.GetPassiveCashPerSecond(player), awaySeconds)
		PlayerDataService.SetPendingOffline(player, amount, awaySeconds)
		PlayerDataService.SyncTycoon(player)
		print(("DebugService: %s away %d min -> pending %s"):format(player.Name, math.floor(minutes), tostring(amount)))
	elseif command == SHOP_COMMAND then
		local verb, rawKey = argument:match("^(%S+)%s*(%S*)$")
		-- Chat is lowercased: match the ShopConfig key case-insensitively.
		local key: string? = nil
		for candidate in ShopConfig.Items do
			if candidate:lower() == rawKey then
				key = candidate
			end
		end
		if verb ~= "grant" or not key then
			local keys = {}
			for _, candidate in ShopConfig.Order do
				table.insert(keys, candidate)
			end
			warn(("DebugService: /shop grant <key> (%s)"):format(table.concat(keys, ", ")))
			return
		end
		local ok, reason = MonetizationService.GrantForTest(player, key)
		if ok then
			print(("DebugService: granted %s to %s"):format(key, player.Name))
		else
			warn(("DebugService: /shop grant %s refused (%s)"):format(key, tostring(reason)))
		end
	elseif command == WIPE_COMMAND then
		-- Any steal this player is part of resolves (returns) before the wipe.
		HeistService.FailCarriesFor(player, "Left")
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
			data.TotalSteals = 0
			data.ShieldRaises = 0
			data.Tips = {}
			data.Rebirths = 0
			data.Index = {}
			data.LastOnline = nil
			data.Boosts = { Income = 0, Luck = 0 }
			data.SafeFusionTokens = 0
			data.StarterPackBought = false
			data.Cosmetics = {}
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

	print("DebugService: Studio commands active: /cash <amount>, /resetmultiplier, /rebirthready, /rebirths <n>, /give <itemId> [mutation], /offline <minutes>, /shield <s>, /heistcd 0, /stealable, /tips reset, /event <id> [min] | off, /eventclock <min>, /eventmut <charged|void|celestial>, /shop grant <key>, /wipe")
end

function DebugService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	HeistService = require(script.Parent.HeistService)
	EventService = require(script.Parent.EventService)
	MonetizationService = require(script.Parent.MonetizationService)
end

return DebugService
