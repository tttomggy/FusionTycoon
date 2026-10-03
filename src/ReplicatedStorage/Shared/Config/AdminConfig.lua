--!strict
--[[
	AdminConfig
	-----------
	Who may run Admin Abuse (the /admin panel), and every number the panel
	uses. AdminService (server) is the only thing that decides; the client
	never learns this list beyond "the server opened the panel for you".

	Admins are AdminUserIds plus the place owner, always: game.CreatorId
	when the place belongs to a user, the group's owner when it belongs to a
	group (AdminService looks that up once at start). Every admin remote and
	every cross-server FT_Admin message is re-checked against IsAdmin.

	Studio: Play Solo runs as your real account (the owner check works);
	local-server test players have negative ids and are never admins, which
	is how the "non-admin can't open it" check is done.
]]
local AdminConfig = {}

-- Harris: put your Roblox UserId in this list (e.g. { 123456789 }) so you're
-- an admin even if the place moves to a group you don't own. Add co-admins
-- the same way. The place owner is always an admin without being listed.
AdminConfig.AdminUserIds = {} :: { number }

AdminConfig.Strengths = { 1, 2, 3 }
AdminConfig.DurationMinutes = { 5, 10, 15 }

-- Luck x3 for 10 minutes (stacks with rebirth luck; EventState reads it).
AdminConfig.LuckMultiplier = 3
AdminConfig.LuckSeconds = 10 * 60

AdminConfig.BroadcastMaxChars = 80
-- Seconds between two actions from one admin (keeps MessagingService well
-- inside its publish budget: 150 + 60 x players per minute per server).
AdminConfig.ActionCooldownSeconds = 2

-- All-servers actions travel on this MessagingService topic: { Action,
-- Args, SenderUserId }. Payloads stay far under the 1 KB message limit.
AdminConfig.MessagingTopic = "FT_Admin"

-- The next Admin Abuse, as unix seconds (UTC), in DataStore GlobalEvents
-- under key NextAdminAbuse. Every server reads it on start and every
-- PollSeconds, and publishes it as the workspace attribute NextAdminAbuse.
AdminConfig.DataStoreName = "GlobalEvents"
AdminConfig.NextAdminAbuseKey = "NextAdminAbuse"
AdminConfig.PollSeconds = 5 * 60
-- How far ahead "Set next Admin Abuse" accepts (and how far back, to clear
-- a just-finished one).
AdminConfig.MaxScheduleAheadSeconds = 90 * 24 * 60 * 60
AdminConfig.MaxScheduleBehindSeconds = 24 * 60 * 60

-- What the gift picker offers (Common..Secret; mutation optional).
AdminConfig.GiftTiers = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

AdminConfig.Actions = {
	StartEvent = true, -- { Id, Strength, Minutes }
	Gift = true, -- { Tier, Mutation? }
	Luck = true, -- {}
	Broadcast = true, -- { Text } (filtered on the sender's server)
	SetNextAdminAbuse = true, -- { Unix } (0 clears)
	EndEvent = true, -- {}
} :: { [string]: boolean }

-- `ownerUserId` is the place owner AdminService resolved (nil until known).
function AdminConfig.IsAdmin(userId: number, ownerUserId: number?): boolean
	if userId <= 0 then
		return false
	end
	if ownerUserId and ownerUserId > 0 and userId == ownerUserId then
		return true
	end
	return table.find(AdminConfig.AdminUserIds, userId) ~= nil
end

return AdminConfig
