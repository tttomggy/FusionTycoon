local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "RemoteEvents"

local REMOTE_EVENT_NAMES = {
	"RequestFusion", -- client -> server: fuse 2-6 owned same-tier items; { Uids = { string } }
	"FusionResult", -- server -> client: validated outcome of a fusion attempt
	"SyncInventory", -- server -> client: authoritative full inventory snapshot
	"RequestUpgrade", -- client -> server: attempt to upgrade a generator
	"UpgradeResult", -- server -> client: validated outcome of an upgrade attempt
	"RequestUpgradeMax", -- client -> server: { GeneratorId } or { All = true }: buy every level cash allows
	"UpgradeMaxResult", -- server -> client: { Success, Levels, Spent, PerGenerator, NewLevels, Reason?, NextCost? }
	"SyncTycoon", -- server -> client: authoritative cash + generator-level snapshot
	"RequestPlaceItem", -- client -> server: attempt to display an owned item (by Uid) on one of the player's own pedestals
	"PlaceItemResult", -- server -> client: validated outcome of a place-item or remove-item attempt
	"RequestRemoveItem", -- client -> server: attempt to pick an item back up off one of the player's own pedestals
	"RareFusionAnnouncement", -- server -> all clients: a Legendary/Mythic item was just displayed
	"MultiplierUpgraded", -- server -> client: a Multiplier Pad purchase; {Success = true, OldMultiplier, NewMultiplier} or {Success = false, Reason, Cost}
	"GachaPullResult", -- server -> client: validated outcome of a gacha pull, fired when the pad's Touched handler resolves one (new item or rejection)
	"GoalCompleted", -- server -> client: the player's current goal was met and paid; {Index, Reward}
	"RequestFuseAll", -- client -> server: fuse every Common/Rare/Epic pair (cascading) in one go
	"RequestSync", -- client -> server: ask for a fresh SyncTycoon after a rejection (rate-limited to 1 per 2 s)
	"FuseAllResult", -- server -> client: summary of a Fuse All; {Count, Upgraded, Gained, Consumed, Best} or {Count = 0}
	"GachaMultiPullResult", -- server -> client: outcome of a Pull x10; {Success, Items, NewIndexItems, IndexTiersCompleted} or {Success = false, Reason, Cost?}
	"RequestRebirth", -- client -> server: rebirth now (no args); validated by RebirthService
	"RebirthResult", -- server -> client: outcome of a rebirth request; {Success, Rebirths?, Reason?}
	"RebirthAnnouncement", -- server -> all clients: a player just rebirthed; {Name, Rebirths}
	"ClaimOffline", -- client -> server: collect the pending offline earnings (no args; the server knows the amount)
	"EventFx", -- server -> clients: an event's world moment; { Kind = "StrikeWarning", Pedestal, Position, Seconds } | { Kind = "Lightning", Position, Result = "Charged"|"Missed" } | { Kind = "Meteor", From, To, Seconds } | { Kind = "Coin", Position, Amount, Big } (coin: the collector only)
	"EventNotice", -- server -> client: an event toast for one player; { Text, Big? } ("⚡ Your <item> got CHARGED!", "Too slow!")
	"EventReward", -- server -> client: an item granted by an event or an admin gift; { Caption, Item, NewIndex? } (shown as a result card)
	"MarkTipSeen", -- client -> server: a one-time tip/card was shown; { Id } (TipConfig ids only)
	"SetSetting", -- client -> server: { Key = "RevealRule", Tier, Value } | { Key = "SfxVolume", Value } | { Key = "SfxMuted", Value } (SettingsConfig-validated; the next snapshot carries Settings)
	"RequestShopPurchase", -- client -> server: { Key } (ShopConfig key; the server checks policy, sale window, one-time, then prompts)
	"ShopPurchased", -- server -> client: { Key, Result = "Granted" | "Refused", Reason?, Lines?, Test? } (the THANK YOU card / a refusal toast)
	"ClaimDaily", -- client -> server: no payload (RewardService decides the day and the reward)
	"DailyResult", -- server -> client: { Result = "Granted" | "Refused", Day?, Streak?, Reward?, Lines?, Reason? } (the daily card's reveal)
	"ShopAnnouncement", -- server -> all: { Kind = "Overclock", PlayerName, Seconds } (the Server Overclock banner)
	"RequestSteal", -- client -> server: grab the item on an enemy pedestal; { OwnerUserId, PedestalIndex } (the server resolves the rest)
	"HeistStarted", -- server -> thief and victim: a carry began; { Role = "Thief"|"Victim", Item, OtherName, OtherUserId, EndsAt, GraceEndsAt (server times) }
	"HeistEnded", -- server -> thief and victim: a carry ended; { Role, Outcome = "Delivered"|"Saved"|"Timeout"|"Left"|"Died", Item, OtherName }
	"HeistFeed", -- server -> all clients: Legendary+ heist banner; { Kind = "Grab"|"Stole"|"Caught", Thief, Victim, Tier, Mutation?, ItemName, ItemId }
	"AdminOpen", -- server -> one admin: open the Admin panel (sent only after AdminService re-checked AdminConfig; non-admins never get it)
	"AdminAction", -- client -> server: an Admin panel action; { Action, Args, Scope = "Server"|"All" } (AdminService validates the sender and every arg)
	"AdminResult", -- server -> one admin: outcome of an AdminAction; { Ok, Text }
	"AdminBroadcast", -- server -> all clients: a filtered admin banner; { Text }
}

local function getOrCreateFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

local function getOrCreateRemoteEvent(folder: Folder, name: string): RemoteEvent
	local remote = folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	return remote :: RemoteEvent
end

-- Populated once at require-time: the server creates each RemoteEvent, the
-- client waits for the server to have created it. Either side then references
-- the events directly, e.g. RemoteEvents.RequestFusion:FireServer({ Uids = uids }).
local RemoteEvents: { [string]: RemoteEvent } = {}

local folder = getOrCreateFolder()
local isServer = RunService:IsServer()

for _, name in REMOTE_EVENT_NAMES do
	if isServer then
		RemoteEvents[name] = getOrCreateRemoteEvent(folder, name)
	else
		RemoteEvents[name] = folder:WaitForChild(name) :: RemoteEvent
	end
end

return RemoteEvents
