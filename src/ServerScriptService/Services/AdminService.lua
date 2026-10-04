--!strict
--[[
	AdminService
	------------
	Admin Abuse: the /admin panel's server side. Every number and the admin
	list are in AdminConfig.

	  /admin (chat, live servers too)  opens the panel, for admins only:
	        AdminOpen goes to that one player. Non-admins get nothing, and
	        the client never builds the panel without it.
	  AdminAction { Action, Args, Scope }  every field validated here:
	        StartEvent { Id, Strength, Minutes }  EventService.ForceEvent
	                   (EventConfig clamps strength x3: coins <= 15 s of
	                   income, generators <= x3, mutation odds <= x15)
	        EndEvent   {}
	        Gift       { Tier, Mutation? }  a random item of that tier to
	                   every loaded player (EventReward "🎁 ADMIN GIFT")
	        Luck       {}  workspace AdminLuck x3 until now + 10 min
	        Broadcast  { Text }  <= 80 chars, TextService:FilterStringAsync
	                   for broadcast on the sender's server; dropped if the
	                   filter fails
	        SetNextAdminAbuse { Unix }  DataStore GlobalEvents/NextAdminAbuse
	                   (UTC), then every server (0 clears)
	  A non-admin firing AdminAction gets a suspicious warn and nothing else.

	Scope "All" publishes { Action, Args, SenderUserId } on MessagingService
	topic FT_Admin; every server (this one included, via its own
	subscription) re-checks SenderUserId against AdminConfig and re-validates
	the args before applying. Every action is logged with warn: who and what.

	The next Admin Abuse is read from the DataStore on start and every
	AdminConfig.PollSeconds and published as the workspace attribute
	NextAdminAbuse (EventState.GetAdminAbuseText).

	Follows ServiceTemplate:
	  :Init()   remote + chat handlers (no other service, no yields).
	  :Start()  resolves EventService and PlayerDataService; resolves the
	            place owner, subscribes FT_Admin and starts the DataStore
	            poll, each on its own thread (they yield).
]]
local DataStoreService = game:GetService("DataStoreService")
local GroupService = game:GetService("GroupService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type EventServiceModule = typeof(require(script.Parent.EventService))

type Args = { [string]: any }

type State = {
	ownerUserId: number?,
	subscribed: boolean,
	lastActionAt: { [number]: number },
	connections: { RBXScriptConnection },
	running: boolean,
}

local state: State = {
	ownerUserId = nil,
	subscribed = false,
	lastActionAt = {},
	connections = {},
	running = false,
}

local GIFT_CAPTION = "🎁 ADMIN GIFT"

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule
local EventService: EventServiceModule

local AdminService = {}

AdminService.Name = "AdminService"

--[[ Helpers ------------------------------------------------------------- ]]

local function isAdmin(userId: number): boolean
	return AdminConfig.IsAdmin(userId, state.ownerUserId)
end

local function reply(player: Player, ok: boolean, text: string)
	RemoteEvents.AdminResult:FireClient(player, { Ok = ok, Text = text })
end

local function describe(action: string, args: Args): string
	local parts = {}
	for key, value in args do
		table.insert(parts, ("%s=%s"):format(key, tostring(value)))
	end
	table.sort(parts)
	return ("%s {%s}"):format(action, table.concat(parts, ", "))
end

-- The args of `action`, sanitised to exactly what apply() reads, or nil
-- and why. Runs for the panel's request AND for every FT_Admin message.
local function validate(action: unknown, raw: unknown): (string?, Args?, string?)
	if typeof(action) ~= "string" or not AdminConfig.Actions[action] then
		return nil, nil, "unknown action"
	end
	local args: Args = if typeof(raw) == "table" then raw :: Args else {}
	if action == "StartEvent" then
		local id, strength, minutes = args.Id, args.Strength, args.Minutes
		if typeof(id) ~= "string" or not table.find(EventConfig.Order, id) then
			return nil, nil, "bad event"
		end
		if typeof(strength) ~= "number" or not table.find(AdminConfig.Strengths, strength) then
			return nil, nil, "bad strength"
		end
		if typeof(minutes) ~= "number" or not table.find(AdminConfig.DurationMinutes, minutes) then
			return nil, nil, "bad duration"
		end
		return action, { Id = id, Strength = strength, Minutes = minutes }, nil
	elseif action == "Gift" then
		local tier, mutation = args.Tier, args.Mutation
		if typeof(tier) ~= "string" or not table.find(AdminConfig.GiftTiers, tier) then
			return nil, nil, "bad tier"
		end
		if mutation == "" then
			mutation = nil
		end
		if mutation ~= nil and not MutationConfig.IsValid(mutation) then
			return nil, nil, "bad mutation"
		end
		return action, { Tier = tier, Mutation = mutation or "" }, nil
	elseif action == "Broadcast" then
		local text = args.Text
		if typeof(text) ~= "string" then
			return nil, nil, "no text"
		end
		local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
		local length = utf8.len(trimmed)
		if not length or length == 0 or length > AdminConfig.BroadcastMaxChars then
			return nil, nil, ("text must be 1-%d characters"):format(AdminConfig.BroadcastMaxChars)
		end
		return action, { Text = trimmed }, nil
	elseif action == "SetNextAdminAbuse" then
		local unix = args.Unix
		if typeof(unix) ~= "number" or unix ~= unix then
			return nil, nil, "bad time"
		end
		unix = math.floor(unix)
		local now = os.time()
		if
			unix ~= 0
			and (unix < now - AdminConfig.MaxScheduleBehindSeconds or unix > now + AdminConfig.MaxScheduleAheadSeconds)
		then
			return nil, nil, "time out of range"
		end
		return action, { Unix = unix }, nil
	end
	-- Luck, EndEvent: no args.
	return action, {}, nil
end

local function syncEveryone()
	for _, player in Players:GetPlayers() do
		if PlayerDataService.IsDataLoaded(player) then
			PlayerDataService.SyncTycoon(player)
		end
	end
end

local function giftPlayer(player: Player, tier: string, mutation: string?)
	local def = ItemConfig.PickRandomOfTier(tier)
	if not def or not PlayerDataService.IsDataLoaded(player) then
		return
	end
	local entry, isNew = PlayerDataService.AddItem(player, def.Id, tier, mutation)
	if not entry then
		return
	end
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	PlayerDataService.SyncTycoon(player)
	RemoteEvents.EventReward:FireClient(player, { Caption = GIFT_CAPTION, Item = entry, NewIndex = isNew })
end

-- Applies a validated action on THIS server.
-- Admin Abuse is "running" while an admin's event or luck is on: the shop's
-- real sales (ShopConfig.Sales) read this window (EventState).
local function extendAdminAbuse(seconds: number)
	local now = Workspace:GetServerTimeNow()
	local current = Workspace:GetAttribute("AdminAbuseUntil")
	local base = if typeof(current) == "number" and current > now then current else now
	Workspace:SetAttribute("AdminAbuseUntil", math.max(base, now + seconds))
end

local function apply(action: string, args: Args)
	if action == "StartEvent" then
		EventService.ForceEvent(args.Id, args.Minutes * 60, args.Strength)
		extendAdminAbuse(args.Minutes * 60)
	elseif action == "EndEvent" then
		EventService.EndEvent()
		-- Ending the event ends the window, unless admin luck is still on.
		local luckUntil = Workspace:GetAttribute("AdminLuckUntil")
		local now = Workspace:GetServerTimeNow()
		Workspace:SetAttribute("AdminAbuseUntil", if typeof(luckUntil) == "number" and luckUntil > now then luckUntil else 0)
	elseif action == "Gift" then
		local mutation = if args.Mutation ~= "" then args.Mutation else nil
		for _, player in Players:GetPlayers() do
			giftPlayer(player, args.Tier, mutation)
		end
	elseif action == "Luck" then
		Workspace:SetAttribute("AdminLuck", AdminConfig.LuckMultiplier)
		Workspace:SetAttribute("AdminLuckUntil", Workspace:GetServerTimeNow() + AdminConfig.LuckSeconds)
		extendAdminAbuse(AdminConfig.LuckSeconds)
		syncEveryone()
		-- Odds displays drop back when it runs out.
		task.delay(AdminConfig.LuckSeconds + 1, syncEveryone)
	elseif action == "Broadcast" then
		RemoteEvents.AdminBroadcast:FireAllClients({ Text = args.Text })
	elseif action == "SetNextAdminAbuse" then
		Workspace:SetAttribute("NextAdminAbuse", args.Unix)
	end
end

-- Filtered for everyone (broadcast context), or nil if the filter failed.
local function filterBroadcast(text: string, fromUserId: number): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, fromUserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and typeof(result) == "string" then
		return result
	end
	warn(("AdminService: broadcast filter failed (%s); message dropped"):format(tostring(result)))
	return nil
end

local function saveNextAdminAbuse(unix: number): boolean
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(AdminConfig.DataStoreName):SetAsync(AdminConfig.NextAdminAbuseKey, unix)
	end)
	if not ok then
		warn(("AdminService: saving %s/%s failed: %s"):format(AdminConfig.DataStoreName, AdminConfig.NextAdminAbuseKey, tostring(err)))
	end
	return ok
end

local function loadNextAdminAbuse()
	local ok, value = pcall(function()
		return DataStoreService:GetDataStore(AdminConfig.DataStoreName):GetAsync(AdminConfig.NextAdminAbuseKey)
	end)
	if ok and typeof(value) == "number" then
		Workspace:SetAttribute("NextAdminAbuse", math.floor(value))
	elseif not ok then
		warn(("AdminService: reading %s/%s failed: %s"):format(AdminConfig.DataStoreName, AdminConfig.NextAdminAbuseKey, tostring(value)))
	end
end

--[[ Handlers ------------------------------------------------------------- ]]

local function onAdminAction(player: Player, payload: unknown)
	if not isAdmin(player.UserId) then
		warn(("AdminService: SUSPICIOUS AdminAction from non-admin %s (%d)"):format(player.Name, player.UserId))
		return
	end
	local now = os.clock()
	local last = state.lastActionAt[player.UserId]
	if last and now - last < AdminConfig.ActionCooldownSeconds then
		reply(player, false, "Slow down: one action every 2 s")
		return
	end
	state.lastActionAt[player.UserId] = now
	local data: Args = if typeof(payload) == "table" then payload :: Args else {}
	local action, args, reason = validate(data.Action, data.Args)
	if not action or not args then
		reply(player, false, "Rejected: " .. tostring(reason))
		return
	end
	-- Next Admin Abuse lives in the DataStore and is global by nature.
	local allServers = data.Scope == "All" or action == "SetNextAdminAbuse"
	if action == "Broadcast" then
		local filtered = filterBroadcast(args.Text, player.UserId)
		if not filtered then
			reply(player, false, "Filter failed: message not sent")
			return
		end
		args.Text = filtered
	elseif action == "SetNextAdminAbuse" then
		if not saveNextAdminAbuse(args.Unix) then
			reply(player, false, "DataStore save failed")
			return
		end
	end
	warn(("AdminService: %s (%d) %s [%s]"):format(player.Name, player.UserId, describe(action, args), if allServers then "all servers" else "this server"))
	if allServers and state.subscribed then
		local ok, err = pcall(function()
			MessagingService:PublishAsync(AdminConfig.MessagingTopic, {
				Action = action,
				Args = args,
				SenderUserId = player.UserId,
			})
		end)
		if ok then
			-- This server applies it from its own subscription, like the rest.
			reply(player, true, "Sent to all servers: " .. action)
			return
		end
		warn(("AdminService: FT_Admin publish failed (%s); applying here only"):format(tostring(err)))
		apply(action, args)
		reply(player, false, "All-servers publish failed: applied on this server only")
		return
	end
	apply(action, args)
	reply(player, true, if allServers then action .. " applied here (no cross-server link)" else action .. " applied")
end

local function onMessage(message: any)
	local data = if typeof(message) == "table" then message.Data else nil
	if typeof(data) ~= "table" then
		return
	end
	local sender = data.SenderUserId
	if typeof(sender) ~= "number" or not isAdmin(sender) then
		warn(("AdminService: SUSPICIOUS FT_Admin message from non-admin %s"):format(tostring(sender)))
		return
	end
	local action, args, reason = validate(data.Action, data.Args)
	if not action or not args then
		warn(("AdminService: FT_Admin message from %d rejected: %s"):format(sender, tostring(reason)))
		return
	end
	warn(("AdminService: FT_Admin from %d: %s"):format(sender, describe(action, args)))
	apply(action, args)
end

local function onChatted(player: Player, message: string)
	if message:lower():match("^%s*/admin%s*$") == nil then
		return
	end
	if isAdmin(player.UserId) then
		warn(("AdminService: %s (%d) opened the Admin panel"):format(player.Name, player.UserId))
		RemoteEvents.AdminOpen:FireClient(player, {
			NextAdminAbuse = Workspace:GetAttribute("NextAdminAbuse"),
		})
	end
end

local function connectPlayer(player: Player)
	table.insert(
		state.connections,
		player.Chatted:Connect(function(message: string)
			onChatted(player, message)
		end)
	)
end

local function resolveOwner()
	if game.CreatorType == Enum.CreatorType.User then
		state.ownerUserId = game.CreatorId
	elseif game.CreatorType == Enum.CreatorType.Group and game.CreatorId > 0 then
		local ok, info = pcall(function()
			return GroupService:GetGroupInfoAsync(game.CreatorId)
		end)
		if ok and typeof(info) == "table" and typeof(info.Owner) == "table" and typeof(info.Owner.Id) == "number" then
			state.ownerUserId = info.Owner.Id
		else
			warn("AdminService: couldn't look up the group owner; only AdminConfig.AdminUserIds are admins")
		end
	end
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function AdminService:Init()
	RemoteEvents.AdminAction.OnServerEvent:Connect(onAdminAction)
	for _, player in Players:GetPlayers() do
		connectPlayer(player)
	end
	table.insert(state.connections, Players.PlayerAdded:Connect(connectPlayer))
	table.insert(
		state.connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			state.lastActionAt[player.UserId] = nil
		end)
	)
end

function AdminService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	EventService = require(script.Parent.EventService)
	state.running = true
	task.spawn(resolveOwner)
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(AdminConfig.MessagingTopic, onMessage)
		end)
		state.subscribed = ok
		if not ok then
			warn(("AdminService: FT_Admin subscribe failed (%s); all-servers actions apply here only"):format(tostring(err)))
		end
	end)
	task.spawn(function()
		while state.running do
			loadNextAdminAbuse()
			task.wait(AdminConfig.PollSeconds)
		end
	end)
end

return AdminService
