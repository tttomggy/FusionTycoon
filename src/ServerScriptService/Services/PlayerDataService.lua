--!strict
--[[
	PlayerDataService
	-----------------
	Owns the authoritative, in-memory copy of every in-session player's saved
	data, and is the only module that talks to the DataStore. Every other
	service reads and mutates player state exclusively through the public API
	below - nothing else may touch the session cache.

	Backend: ProfileStore (Packages/ProfileStore, session-locked), store
	FT_Live_1. A profile is held by ONE server: a second server waits for the
	lock and steals it after ProfileStore's timeout, after which the first
	server's writes are refused and that player is kicked ("Your save was
	opened in another server, please rejoin"). The session cache keeps the
	in-memory shape (numeric pedestal keys); every save hands ProfileStore a
	fresh disk copy (string keys, LastOnline, Version) from OnSave /
	OnLastSave. Studio plays on ProfileStore's mock store: a blank profile
	that is never saved.

	Follows the ServiceTemplate contract: :Init() is self-contained (it
	connects only to Players and its own remotes), so it has no :Start().
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
local OfflineConfig = require(ReplicatedStorage.Shared.Config.OfflineConfig)
local TipConfig = require(ReplicatedStorage.Shared.Config.TipConfig)
local SettingsConfig = require(ReplicatedStorage.Shared.Config.SettingsConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local DailyConfig = require(ReplicatedStorage.Shared.Config.DailyConfig)
local GiftConfig = require(ReplicatedStorage.Shared.Config.GiftConfig)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local ShopState = require(ReplicatedStorage.Shared.Modules.ShopState)
local DealConfig = require(ReplicatedStorage.Shared.Config.DealConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local DealState = require(ReplicatedStorage.Shared.Modules.DealState)
local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)

--[[ Types ---------------------------------------------------------------- ]]

-- Exported so other services stop typing inventory entries as `any`.
export type InventoryItem = {
	Uid: string,
	ItemId: string,
	Tier: string,
	InUse: boolean,
	-- The BASE mutation (MutationConfig: Golden / Diamond / Rainbow); nil =
	-- normal.
	Mutation: string?,
	-- Stacked event mutations (Charged / Void / Celestial), sorted by rank,
	-- each at most once; nil = none (MutationConfig.SanitizeEvents).
	EventMutations: { string }?,
}

export type TutorialState = {
	Step: number, -- TutorialConfig.Steps index; 0 = not decided yet
	Done: boolean,
	FreeFuse: boolean, -- the once-per-account guaranteed fusion was used
	FreePulls: number, -- tutorial pulls left (free, plain Commons)
	PullsGranted: boolean, -- the 2 free pulls were granted (once per account)
	Base: number, -- the counter (pulls / fusions) when the step started
	Replay: boolean, -- replayed from Settings: every step is done on OK
	ReplayHint: boolean, -- an old save skipped it: "replay it in ⚙" once
}

export type PlayerData = {
	Cash: number,
	Inventory: { InventoryItem },
	Generators: { [string]: number },
	-- Multiplier Pad level; see TycoonConfig.GetCashMultiplierValue.
	CashMultiplierLevel: number,
	-- Map of pedestalIndex -> displayed item's Uid. The value type is
	-- optional because assigning nil is the intentional way to clear a
	-- pedestal slot (see SetPedestalDisplay) - Luau treats key removal as an
	-- assignment of nil, so `{ [number]: string }` would reject it.
	PedestalDisplays: { [number]: string? },
	-- How many Gacha pulls this player has made; drives the pull price.
	GachaPulls: number,
	-- Legacy (the droppers are gone): still loaded and saved so old saves
	-- round-trip unchanged, but nothing reads it.
	HasDropper2: boolean,
	-- 1-based index into GoalConfig.Goals of the goal currently being
	-- worked on; past the end means every goal is done.
	GoalIndex: number,
	-- Every resolved fusion attempt, success or fail (drives a goal).
	TotalFusions: number,
	-- Heist: items delivered home, and shields raised with LOCK (the console)
	-- (drive the first_steal / first_shield goals).
	TotalSteals: number,
	ShieldRaises: number,
	-- One-time tips/cards already shown (TipConfig ids -> true).
	Tips: { [string]: boolean },
	-- Player settings (SettingsConfig): RevealRule = which tiers / mutations
	-- get the big reveal card. Old saves get the defaults.
	Settings: SettingsConfig.Settings,
	-- How many times the player has rebirthed (RebirthConfig).
	Rebirths: number,
	-- Index entries found ("<itemId>|<Mutation or Normal>" -> true). Kept
	-- through rebirths; see IndexConfig.
	Index: { [string]: boolean },
	-- os.time() when this profile was last saved (every autosave and on
	-- leaving) or loaded. nil on old saves: no offline payout the first time.
	LastOnline: number?,
	-- Shop (MonetizationService): granted PurchaseIds, newest last (the
	-- last ShopConfig.MaxReceipts), so ProcessReceipt never grants twice.
	Receipts: { string },
	-- Timed boosts as REMAINING seconds (they pause while offline).
	Boosts: { Income: number, Luck: number },
	SafeFusionTokens: number,
	StarterPackBought: boolean,
	-- Cosmetics owned through a product (the Starter Pack's LabStyle);
	-- passes are checked with Roblox at join instead.
	Cosmetics: { [string]: boolean },
	-- Times this profile has loaded (the Starter Pack offer: session 2).
	Sessions: number,
	-- The deal slot (DealConfig slot start, UTC) whose "New deal!" card
	-- already showed: once per deal, across rejoins. 0 = none yet.
	DealPopupSlot: number,
	-- The first-time tutorial (TutorialConfig / TutorialService).
	Tutorial: TutorialState,
	-- Earned weapons (CombatConfig ids -> true; CombatService grants them).
	Weapons: { [string]: boolean },
	-- The daily reward streak (DailyConfig; RewardService claims it).
	Daily: DailyConfig.State,
	-- Today's playtime gifts (GiftConfig; RewardService ticks and claims).
	Gifts: GiftConfig.State,
	-- The highest base income ($/s, no timed boosts) this save has reached:
	-- the street's BEST INCOME board (LeaderboardService).
	BestIncome: number,
	-- Free pulls taken (daily / gift rewards). Kept apart from GachaPulls,
	-- which sets the pad price; both count for the first-pull goal.
	FreePulls: number,
	-- Onboarding funnel steps already logged (AnalyticsKit.FunnelSteps), so
	-- each is sent once per player ever.
	Funnel: { [string]: boolean },
	-- Save format version (DATA_VERSION); migrations key off it.
	Version: number,
}

-- Offline earnings waiting to be collected (session only, never saved).
export type PendingOffline = {
	Amount: number,
	AwaySeconds: number,
	Since: number, -- os.clock() when it was computed (auto-claim timer)
}

-- Server-computed progress toward the current goal, sent with the snapshot.
export type GoalProgress = {
	Current: number,
	Target: number,
}

-- What SyncTycoon sends to the client. One builder (GetTycoonSnapshot) so the
-- four services that sync no longer each hand-copy the payload shape.
export type TycoonSnapshot = {
	Cash: number,
	Generators: { [string]: number },
	CashMultiplierLevel: number,
	-- String keys ("1".."4") on the wire, like on disk: a RemoteEvent drops
	-- entries after a gap in a sparse numeric table ({[1]=a, [3]=b, [4]=c}),
	-- which made the client think occupied pedestals were empty.
	PedestalDisplays: { [string]: string },
	GachaPulls: number,
	GoalIndex: number,
	GoalProgress: GoalProgress?,
	Rebirths: number,
	-- Found Index keys as a dense list (the client builds the set and
	-- computes the Index multiplier).
	IndexKeys: { string },
	-- Offline earnings not yet collected (0 = none) and the away time they
	-- cover, for the welcome-back card.
	PendingOffline: number,
	AwaySeconds: number,
	-- Uids of this player's displayed items a thief is carrying right now:
	-- they earn nothing until back (the client's income skips them too).
	CarriedUids: { string },
	-- One-time tips already seen (TipConfig ids), as a dense list.
	TipKeys: { string },
	-- The player's settings (SettingsConfig), a copy.
	Settings: SettingsConfig.Settings,
	-- The shop's view of this player (MonetizationService).
	Shop: ShopSnapshot,
	-- The daily reward: what the next claim gives (DailyConfig.GetStatus at
	-- the server's UTC day) and the cycle day of the last claim.
	Daily: DailyConfig.Status & { LastDay: number },
	-- Today's playtime gifts (GiftConfig): the client counts PlaySeconds on
	-- from when the snapshot arrived.
	Gifts: { PlaySeconds: number, Claimed: { number } },
}

export type ShopSnapshot = {
	OwnedPasses: { string }, -- pass keys owned (Roblox check at join + purchases)
	Restricted: boolean, -- PolicyService: no cash / luck products
	IncomeBoostSeconds: number,
	LuckBoostSeconds: number,
	SafeFusionTokens: number,
	StarterPackBought: boolean,
	Cosmetics: { string },
	Sessions: number,
	DealPopupSlot: number,
	-- Offline cash the welcome-back card's COLLECT x2 can still double.
	OfflineDoubleAmount: number,
}

-- What MonetizationService tells this service at join (session only).
export type ShopSession = {
	OwnedPasses: { [string]: boolean },
	Restricted: boolean,
}

type State = {
	-- In-memory cache keyed by UserId; the source of truth while a player is
	-- in-session. Private: never exposed on the service table.
	sessionCache: { [number]: PlayerData },
	-- The ProfileStore profile behind each session (session-locked).
	profiles: { [number]: any },
	-- Players being released on purpose (leaving): their session ending is
	-- expected, not a lost lock.
	releasing: { [number]: boolean },
	-- Session-only: GoalService's latest progress readout per UserId.
	goalProgress: { [number]: GoalProgress? },
	-- Session-only: offline earnings computed on load, until claimed.
	pendingOffline: { [number]: PendingOffline },
	-- Session-only heist flags HeistService sets (it owns the heist state;
	-- these are the parts income, sync and other services' guards need):
	-- each owner's displayed Uids being carried, and who is carrying.
	carriedUids: { [number]: { [string]: boolean } },
	carrying: { [number]: boolean },
	-- Called synchronously before a player's data is saved and released
	-- (leaving, or the server closing). See OnRelease.
	releaseHooks: { (Player) -> () },
	-- Called synchronously at the start of every SyncTycoon (see OnSync).
	syncHooks: { (Player) -> () },
	-- os.clock() of each player's last honoured RequestSync.
	lastSyncRequest: { [number]: number },
	-- A settings change already has a sync scheduled (SetSetting).
	settingsSyncQueued: { [number]: boolean },
	-- Session-only shop state per UserId (MonetizationService sets it).
	shop: { [number]: ShopSession },
	-- The last offline payout collected this session (OfflineDouble can
	-- still double it once), per UserId.
	lastOfflinePaid: { [number]: number },
	connections: { RBXScriptConnection },
}

--[[ Constants ------------------------------------------------------------ ]]

-- The live store. A NEW name on purpose: it is also the save wipe. The old
-- store "PlayerData_v1" (plain GetAsync / SetAsync, no session lock) is
-- abandoned with every Studio and test save in it, and never read again.
local STORE_NAME = "FT_Live_1"
-- Studio's opt-in real store (ServerScriptService attribute
-- FT_StudioSaves = true + "Enable Studio Access to API Services"): lets
-- Studio test that saves persist (a /shop grant then an instant leave)
-- without ever touching the live store.
local STUDIO_STORE_NAME = "FT_StudioTest_1"
local STUDIO_SAVES_ATTRIBUTE = "FT_StudioSaves"
local PROFILE_KEY_PREFIX = "Player_"
local DATA_VERSION = 1
local AUTOSAVE_INTERVAL_SECONDS = 120 -- ProfileStore's AUTO_SAVE_PERIOD
-- A load that can't get the profile (DataStore down, or the lock never
-- frees) gives up after this long and kicks; nothing is overwritten.
local LOAD_TIMEOUT_SECONDS = 90
-- SaveNowAsync waits this long for the save to land (ProcessReceipt).
local SAVE_WAIT_TIMEOUT_SECONDS = 20
local RELEASE_FLAG_SECONDS = 15
local LOST_LOCK_MESSAGE = "Your save was opened in another server, please rejoin"
local LOAD_FAILED_MESSAGE =
	"Couldn't load your save (Roblox data servers are having trouble). Your progress is safe - please rejoin in a minute."
local SYNC_REQUEST_COOLDOWN_SECONDS = 2
local SETTINGS_SYNC_DELAY_SECONDS = 0.25 -- a burst of SetSettings syncs once

ProfileStore.SetConstant("AUTO_SAVE_PERIOD", AUTOSAVE_INTERVAL_SECONDS)

-- The tutorial's saved state (TutorialConfig): Step 0 = not decided yet.
local function sanitizeTutorial(raw: unknown): TutorialState
	local t = if typeof(raw) == "table" then raw :: any else {}
	local function whole(value: unknown, max: number): number
		if typeof(value) == "number" and value == value and value >= 0 and value < math.huge then
			return math.min(math.floor(value), max)
		end
		return 0
	end
	return {
		Step = whole(t.Step, 1000),
		Done = t.Done == true,
		FreeFuse = t.FreeFuse == true,
		FreePulls = whole(t.FreePulls, 10),
		PullsGranted = t.PullsGranted == true,
		Base = whole(t.Base, 2 ^ 40),
		Replay = t.Replay == true,
		ReplayHint = t.ReplayHint == true,
	}
end

local DEFAULT_DATA: PlayerData = {
	Cash = 0,
	Inventory = {},
	Generators = {},
	CashMultiplierLevel = 0,
	PedestalDisplays = {},
	GachaPulls = 0,
	HasDropper2 = false,
	GoalIndex = 1,
	TotalFusions = 0,
	TotalSteals = 0,
	ShieldRaises = 0,
	Tips = {},
	Settings = SettingsConfig.GetDefaultSettings(),
	Rebirths = 0,
	Index = {},
	Receipts = {},
	Boosts = { Income = 0, Luck = 0 },
	SafeFusionTokens = 0,
	StarterPackBought = false,
	Cosmetics = {},
	Sessions = 0,
	DealPopupSlot = 0,
	Weapons = {},
	Tutorial = {
		Step = 0,
		Done = false,
		FreeFuse = false,
		FreePulls = 0,
		PullsGranted = false,
		Base = 0,
		Replay = false,
		ReplayHint = false,
	},
	Daily = DailyConfig.Default(),
	Gifts = GiftConfig.Default(-1),
	BestIncome = 0,
	FreePulls = 0,
	Funnel = {},
	Version = DATA_VERSION,
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	sessionCache = {},
	profiles = {},
	releasing = {},
	goalProgress = {},
	pendingOffline = {},
	carriedUids = {},
	carrying = {},
	releaseHooks = {},
	syncHooks = {},
	lastSyncRequest = {},
	settingsSyncQueued = {},
	shop = {},
	lastOfflinePaid = {},
	connections = {},
}

local PlayerDataService = {}

PlayerDataService.Name = "PlayerDataService"

--[[ Private helpers ------------------------------------------------------ ]]

local function deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end

	local copy: { [any]: any } = {}
	for key, nested in (value :: any) :: { [any]: any } do
		copy[key] = deepCopy(nested)
	end
	return (copy :: any) :: T
end

-- DataStores serialize numeric keys with gaps ({[2] = uid}) unreliably: they
-- can come back as string keys ("2"), and the next SetPedestalDisplay(2, ...)
-- then makes a mixed string/number table that DataStores refuse to save at
-- all - silently losing every bit of progress after it. So pedestal slots are
-- stored on disk with string keys and converted back to numbers on load.
local function pedestalDisplaysToDisk(displays: { [number]: string? }): { [string]: string }
	local out: { [string]: string } = {}
	for index, uid in displays do
		if uid then
			out[tostring(index)] = uid
		end
	end
	return out
end

local function pedestalDisplaysFromDisk(raw: any): { [number]: string? }
	local out: { [number]: string? } = {}
	if typeof(raw) ~= "table" then
		return out
	end
	for key, uid in raw do
		local index = tonumber(key)
		if index and typeof(uid) == "string" then
			out[math.floor(index)] = uid
		end
	end
	return out
end

-- Fills any field missing from an older save with its default, so new
-- features never index nil on an old profile.
-- Marks the Index entry of EVERY mutation an item has (a stacked Rainbow +
-- Charged fills both columns; a plain item fills Normal). Returns whether
-- any entry was new.
local function markIndex(data: PlayerData, item: InventoryItem): boolean
	local isNew = false
	local list = MutationConfig.List(item.Mutation, item.EventMutations)
	if #list == 0 then
		list = { "" }
	end
	for _, mutation in list do
		local key = IndexConfig.GetKey(item.ItemId, if mutation == "" then nil else mutation)
		if not data.Index[key] then
			isNew = true
			data.Index[key] = true
		end
	end
	return isNew
end

local function reconcile(raw: any): PlayerData
	local data = deepCopy(DEFAULT_DATA)
	if typeof(raw) ~= "table" then
		return data
	end
	if typeof(raw.Cash) == "number" and raw.Cash == raw.Cash and raw.Cash ~= math.huge then
		data.Cash = math.clamp(raw.Cash, 0, 1e300)
	end
	if typeof(raw.Inventory) == "table" then
		data.Inventory = raw.Inventory
	end
	if typeof(raw.Generators) == "table" then
		data.Generators = raw.Generators
	end
	if typeof(raw.CashMultiplierLevel) == "number" then
		data.CashMultiplierLevel = raw.CashMultiplierLevel
	end
	data.PedestalDisplays = pedestalDisplaysFromDisk(raw.PedestalDisplays)
	if typeof(raw.GachaPulls) == "number" then
		data.GachaPulls = raw.GachaPulls
	end
	if typeof(raw.HasDropper2) == "boolean" then
		data.HasDropper2 = raw.HasDropper2
	end
	if typeof(raw.GoalIndex) == "number" and raw.GoalIndex >= 1 then
		data.GoalIndex = math.floor(raw.GoalIndex)
	end
	if typeof(raw.TotalFusions) == "number" then
		data.TotalFusions = raw.TotalFusions
	end
	if typeof(raw.TotalSteals) == "number" then
		data.TotalSteals = raw.TotalSteals
	end
	if typeof(raw.ShieldRaises) == "number" then
		data.ShieldRaises = raw.ShieldRaises
	end
	if typeof(raw.Tips) == "table" then
		for id, seen in raw.Tips do
			if seen == true and TipConfig.IsValid(id) then
				data.Tips[id] = true
			end
		end
	end
	data.Settings = SettingsConfig.Sanitize(raw.Settings)
	if typeof(raw.Rebirths) == "number" and raw.Rebirths >= 0 then
		data.Rebirths = math.floor(raw.Rebirths)
	end
	if typeof(raw.LastOnline) == "number" then
		data.LastOnline = raw.LastOnline
	end
	if typeof(raw.Index) == "table" then
		for key, found in raw.Index do
			if found == true and IndexConfig.IsValidKey(key) then
				data.Index[key] = true
			end
		end
	end

	-- Shop fields (old saves: none bought).
	if typeof(raw.Receipts) == "table" then
		for _, id in raw.Receipts do
			if typeof(id) == "string" then
				table.insert(data.Receipts, id)
			end
		end
	end
	if typeof(raw.Boosts) == "table" then
		local income, luck = raw.Boosts.Income, raw.Boosts.Luck
		data.Boosts.Income = if typeof(income) == "number" then math.clamp(income, 0, ShopConfig.MaxBoostBankSeconds) else 0
		data.Boosts.Luck = if typeof(luck) == "number" then math.clamp(luck, 0, ShopConfig.MaxLuckBankSeconds) else 0
	end
	if typeof(raw.SafeFusionTokens) == "number" and raw.SafeFusionTokens >= 0 then
		data.SafeFusionTokens = math.floor(raw.SafeFusionTokens)
	end
	data.StarterPackBought = raw.StarterPackBought == true
	if typeof(raw.Cosmetics) == "table" then
		for key, owned in raw.Cosmetics do
			if owned == true and typeof(key) == "string" and ShopConfig.GetItem(key) then
				data.Cosmetics[key] = true
			end
		end
	end
	if typeof(raw.Sessions) == "number" and raw.Sessions >= 0 then
		data.Sessions = math.floor(raw.Sessions)
	end
	data.Tutorial = sanitizeTutorial(raw.Tutorial)
	if typeof(raw.Weapons) == "table" then
		for id, owned in raw.Weapons do
			if owned == true and CombatConfig.GetWeapon(id) then
				data.Weapons[id] = true
			end
		end
	end
	-- A slot start: a finite whole number of seconds (NaN fails >= 0).
	if typeof(raw.DealPopupSlot) == "number" and raw.DealPopupSlot >= 0 and raw.DealPopupSlot < math.huge then
		data.DealPopupSlot = math.floor(raw.DealPopupSlot)
	end
	data.Daily = DailyConfig.Sanitize(raw.Daily)
	if typeof(raw.FreePulls) == "number" and raw.FreePulls >= 0 then
		data.FreePulls = math.floor(raw.FreePulls)
	end
	if typeof(raw.Funnel) == "table" then
		for step, done in raw.Funnel do
			if done == true and table.find(AnalyticsKit.FunnelSteps, step) then
				data.Funnel[step] = true
			end
		end
	end
	if typeof(raw.BestIncome) == "number" and raw.BestIncome == raw.BestIncome and raw.BestIncome >= 0 then
		data.BestIncome = raw.BestIncome
	end
	data.Gifts = GiftConfig.Sanitize(raw.Gifts, RewardConfig.GetUtcDay(os.time()))
	-- Version 1 is the first FT_Live_1 format; later versions migrate here
	-- (raw.Version < DATA_VERSION) before the stamp below.
	data.Version = DATA_VERSION

	-- Any item flagged InUse that isn't actually on a pedestal (e.g. the save
	-- happened mid-change) would be stuck forever: unfusable and undisplayable.
	local displayed: { [string]: boolean } = {}
	for _, uid in data.PedestalDisplays do
		if uid then
			displayed[uid] = true
		end
	end
	for _, item in data.Inventory do
		item.InUse = displayed[item.Uid] == true
		-- Old saves have no mutation; an unknown one (renamed/removed) is
		-- dropped rather than left to break lookups. Stacking: an event-only
		-- base (pre-stacking saves) moves into EventMutations.
		item.Mutation, item.EventMutations = MutationConfig.Normalize(item.Mutation, item.EventMutations)
		-- Backfill: everything already owned counts as found.
		markIndex(data, item)
	end
	return data
end

-- The template ProfileStore reconciles new profiles against (disk shape).
local function toDisk(data: PlayerData): any
	local copy = deepCopy(data) :: any
	copy.PedestalDisplays = pedestalDisplaysToDisk(data.PedestalDisplays)
	copy.LastOnline = os.time()
	copy.Version = DATA_VERSION
	return copy
end

-- Live games: FT_Live_1. Studio: ProfileStore's mock store (in memory,
-- never written), a blank profile every Play as before, unless the
-- FT_StudioSaves opt-in picks the separate Studio test store.
local isStudio = RunService:IsStudio()
local studioSaves = isStudio and ServerScriptService:GetAttribute(STUDIO_SAVES_ATTRIBUTE) == true
local profileStore = ProfileStore.New(if studioSaves then STUDIO_STORE_NAME else STORE_NAME, toDisk(DEFAULT_DATA))
local store = if isStudio and not studioSaves then profileStore.Mock else profileStore

--[[ /selftest support (DebugService, Studio only) -------------------------- ]]

-- Which store this server's profiles live in: "Mock" (plain Studio),
-- "StudioTest" (FT_StudioSaves) or "Live". /selftest refuses "Live".
function PlayerDataService.GetStoreKind(): string
	if isStudio and not studioSaves then
		return "Mock"
	end
	return if studioSaves then "StudioTest" else "Live"
end

-- A canonical string of any plain value: sorted keys, exact numbers, so
-- two equal tables always print the same.
local function canonical(value: any, skip: { [string]: boolean }?): string
	local kind = typeof(value)
	if kind == "table" then
		local keys = {}
		for key in value do
			if not (skip and skip[tostring(key)]) then
				table.insert(keys, key)
			end
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, key in keys do
			table.insert(parts, ("%s=%s"):format(tostring(key), canonical(value[key])))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif kind == "number" then
		return ("%.17g"):format(value)
	end
	return kind .. ":" .. tostring(value)
end

-- Disk -> session -> disk must be lossless: toDisk(data), reconcile it back,
-- toDisk again, compare (LastOnline is stamped per call, so skipped). In
-- memory only: no profile is read or written.
-- /selftest: a save that left mid-tutorial resumes at its saved step
-- (disk copy -> reconcile keeps the whole Tutorial state).
function PlayerDataService.SelfTestTutorialRoundTrip(player: Player): (boolean, string?)
	local data = state.sessionCache[player.UserId]
	if not data then
		return false, "no data loaded"
	end
	local before = canonical(data.Tutorial)
	local after = canonical(reconcile(deepCopy(toDisk(data))).Tutorial)
	return before == after, if before == after then nil else ("%s became %s"):format(before, after)
end

-- /selftest saves and restores the tester's own tutorial state around the
-- drive.
function PlayerDataService.SelfTestSwapTutorial(player: Player, tutorial: TutorialState?): TutorialState?
	local data = state.sessionCache[player.UserId]
	if not data then
		return nil
	end
	local old = deepCopy(data.Tutorial)
	if tutorial then
		data.Tutorial = deepCopy(tutorial)
	end
	return old
end

function PlayerDataService.SelfTestRoundTrip(player: Player): (boolean, string?)
	local data = state.sessionCache[player.UserId]
	if not data then
		return false, "no data loaded"
	end
	local skip = { LastOnline = true }
	local first = toDisk(data)
	local second = toDisk(reconcile(deepCopy(first)))
	local a, b = canonical(first, skip), canonical(second, skip)
	if a == b then
		return true, nil
	end
	-- Name the first top-level field that differs.
	for key in first do
		if key ~= "LastOnline" and canonical(first[key]) ~= canonical(second[key]) then
			return false, ("field %s changed"):format(tostring(key))
		end
	end
	return false, "a field was added"
end

-- Everything a bad remote must NOT change (cash is checked separately: the
-- income tick only ever raises it). Gifts.PlaySeconds and Boosts tick.
function PlayerDataService.SelfTestFingerprint(player: Player): string
	local data = state.sessionCache[player.UserId]
	if not data then
		return ""
	end
	return canonical({
		Inventory = data.Inventory,
		PedestalDisplays = pedestalDisplaysToDisk(data.PedestalDisplays),
		Generators = data.Generators,
		CashMultiplierLevel = data.CashMultiplierLevel,
		Rebirths = data.Rebirths,
		GachaPulls = data.GachaPulls,
		FreePulls = data.FreePulls,
		Settings = data.Settings,
		Tips = data.Tips,
		Daily = data.Daily,
		GiftsClaimed = data.Gifts.Claimed,
		SafeFusionTokens = data.SafeFusionTokens,
		Receipts = data.Receipts,
		Index = data.Index,
		Cosmetics = data.Cosmetics,
		DealPopupSlot = data.DealPopupSlot,
		Tutorial = data.Tutorial,
		Weapons = data.Weapons,
	})
end

-- Pays offline earnings still pending into the save (leaving, shutdown):
-- never lost.
local function payPendingOffline(userId: number)
	local data = state.sessionCache[userId]
	local pending = state.pendingOffline[userId]
	if data and pending then
		data.Cash += pending.Amount
	end
	state.pendingOffline[userId] = nil
end

local runReleaseHooks: (player: Player) -> ()

-- Starts the player's session (yields; waits for another server's lock up to
-- ProfileStore's steal timeout). Returns true once the data is ready; on
-- failure kicks in a live game (nothing is overwritten).
local function loadData(player: Player): boolean
	local userId = player.UserId
	local started = os.clock()
	local profile = store:StartSessionAsync(PROFILE_KEY_PREFIX .. userId, {
		Cancel = function()
			return player.Parent ~= Players or os.clock() - started > LOAD_TIMEOUT_SECONDS
		end,
	})
	if not profile then
		if player.Parent == Players then
			warn(("PlayerDataService: couldn't start %s's session (%d)"):format(player.Name, userId))
			player:Kick(LOAD_FAILED_MESSAGE)
		end
		return false
	end
	if player.Parent ~= Players then
		-- Left while the profile was loading.
		profile:EndSession()
		return false
	end
	profile:AddUserId(userId) -- GDPR: ties the key to the user
	profile:Reconcile()
	local data = reconcile(profile.Data)
	data.Sessions += 1
	state.sessionCache[userId] = data
	state.profiles[userId] = profile

	-- Every save writes a fresh disk copy of the session cache.
	profile.OnSave:Connect(function()
		local current = state.sessionCache[userId]
		if current and state.profiles[userId] == profile then
			profile.Data = toDisk(current)
		end
	end)
	-- The server is closing: steals resolve and pending offline cash is paid
	-- BEFORE the final copy is taken.
	profile.OnLastSave:Connect(function(reason: string)
		if reason ~= "Shutdown" or state.releasing[userId] then
			return
		end
		local inGame = Players:GetPlayerByUserId(userId)
		if inGame then
			runReleaseHooks(inGame)
		end
		payPendingOffline(userId)
		local current = state.sessionCache[userId]
		if current then
			profile.Data = toDisk(current)
		end
	end)
	-- The session ended without us asking: another server took the lock.
	-- This server's copy is no longer saved, so the player must rejoin.
	profile.OnSessionEnd:Connect(function()
		if state.profiles[userId] == profile then
			state.profiles[userId] = nil
		end
		if state.releasing[userId] or ProfileStore.IsClosing then
			return
		end
		state.sessionCache[userId] = nil
		if player.Parent == Players then
			warn(("PlayerDataService: lost %s's session lock (%d)"):format(player.Name, userId))
			player:Kick(LOST_LOCK_MESSAGE)
		end
	end)
	return true
end

-- Saves `player`'s data now (ProfileStore's save, on its own thread; never
-- yields the caller). RebirthService and heist delivery call it.
function PlayerDataService.SaveNow(player: Player)
	local profile = state.profiles[player.UserId]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

-- Saves `player`'s data and WAITS until the write lands (yields). True only
-- if a save completed while the profile was still this server's.
-- ProcessReceipt grants and records the receipt, then calls this.
function PlayerDataService.SaveNowAsync(player: Player): boolean
	local profile = state.profiles[player.UserId]
	if not profile or not profile:IsActive() then
		return false
	end
	local saved = false
	local connection = profile.OnAfterSave:Connect(function()
		-- OnAfterSave also fires when the save found another server's lock.
		saved = profile:IsActive()
	end)
	profile:Save()
	local started = os.clock()
	while not saved and profile:IsActive() and os.clock() - started < SAVE_WAIT_TIMEOUT_SECONDS do
		task.wait(0.1)
	end
	connection:Disconnect()
	return saved
end

-- The profile is held by this server right now (ProcessReceipt only grants
-- while it is).
function PlayerDataService.IsProfileActive(player: Player): boolean
	local profile = state.profiles[player.UserId]
	return profile ~= nil and profile:IsActive() == true
end

-- `purchaseId` is in the last successfully SAVED copy (not just in memory).
function PlayerDataService.IsReceiptSaved(player: Player, purchaseId: string): boolean
	local profile = state.profiles[player.UserId]
	local saved = profile and profile.LastSavedData
	local receipts = saved and saved.Receipts
	return typeof(receipts) == "table" and table.find(receipts, purchaseId) ~= nil
end

--[[ Public API: data ----------------------------------------------------- ]]

function PlayerDataService.IsDataLoaded(player: Player): boolean
	return state.sessionCache[player.UserId] ~= nil
end

function PlayerDataService.GetData(player: Player): PlayerData?
	return state.sessionCache[player.UserId]
end

--[[ Public API: cash ----------------------------------------------------- ]]

function PlayerDataService.GetCash(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.Cash else 0
end

-- Mirrors the authoritative Cash value onto the player's leaderstats display.
-- A StringValue ("$1.2Qa"), not an IntValue: late-game cash passes the
-- int64 range (~9.2e18), and assigning that to an IntValue would break the
-- income tick for every player after this one.
local function updateLeaderstatsCash(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local cashValue = leaderstats and leaderstats:FindFirstChild("Cash")
	if cashValue and cashValue:IsA("StringValue") then
		cashValue.Value = NumberFormat.Money(PlayerDataService.GetCash(player))
	end
end

-- Cash stays finite and saveable: a DataStore can't hold inf / NaN, and
-- NumberFormat reads up to 1e300.
local MAX_CASH = 1e300

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function updateLeaderstatsRebirths(player: Player)
	local data = state.sessionCache[player.UserId]
	local leaderstats = player:FindFirstChild("leaderstats")
	local rebirthsValue = leaderstats and leaderstats:FindFirstChild("Rebirths")
	if data and rebirthsValue and rebirthsValue:IsA("IntValue") then
		rebirthsValue.Value = data.Rebirths
	end
end

function PlayerDataService.AddCash(player: Player, amount: number)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	-- A NaN amount used to zero the cash (math.max(0, NaN) is 0) and an
	-- inf one made every later save fail. Refuse both, loudly.
	if not isFinite(amount) then
		warn(("PlayerDataService: refused non-finite AddCash(%s) for %s"):format(tostring(amount), player.Name))
		return
	end
	data.Cash = math.clamp(data.Cash + amount, 0, MAX_CASH)
	updateLeaderstatsCash(player)
end

-- Atomically checks-and-deducts; fails (no mutation) if funds are insufficient.
function PlayerDataService.SpendCash(player: Player, amount: number): boolean
	local data = state.sessionCache[player.UserId]
	-- A NaN cost turned cash into NaN; a negative one added money.
	if not data or not isFinite(amount) or amount < 0 or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	updateLeaderstatsCash(player)
	return true
end

--[[ Public API: generators ----------------------------------------------- ]]

function PlayerDataService.GetGenerators(player: Player): { [string]: number }?
	local data = state.sessionCache[player.UserId]
	return if data then data.Generators else nil
end

function PlayerDataService.GetGeneratorLevel(player: Player, generatorId: string): number
	local generators = PlayerDataService.GetGenerators(player)
	return if generators then generators[generatorId] or 0 else 0
end

function PlayerDataService.SetGeneratorLevel(player: Player, generatorId: string, level: number)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	data.Generators[generatorId] = level
end

--[[ Public API: cash multiplier ------------------------------------------ ]]

-- Falls back to 0 so saves from before the Multiplier Pad existed still work.
function PlayerDataService.GetCashMultiplierLevel(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.CashMultiplierLevel or 0 else 0
end

function PlayerDataService.SetCashMultiplierLevel(player: Player, level: number)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	data.CashMultiplierLevel = level
end

--[[ Public API: inventory ------------------------------------------------ ]]

function PlayerDataService.GetInventory(player: Player): { InventoryItem }?
	local data = state.sessionCache[player.UserId]
	return if data then data.Inventory else nil
end

-- Looks up a single inventory entry by its Uid, or nil if the player doesn't
-- currently own an item with that Uid (already consumed, never owned, etc).
function PlayerDataService.GetItemByUid(player: Player, uid: string): InventoryItem?
	local inventory = PlayerDataService.GetInventory(player)
	if not inventory then
		return nil
	end
	for _, item in inventory do
		if item.Uid == uid then
			return item
		end
	end
	return nil
end

-- Atomically removes the exact items named by `uids`. Fails (no mutation) if
-- any uid isn't currently in the player's inventory - e.g. it was already
-- consumed by an earlier request.
function PlayerDataService.RemoveItemsByUid(player: Player, uids: { string }): (boolean, { InventoryItem })
	local inventory = PlayerDataService.GetInventory(player)
	if not inventory then
		return false, {}
	end

	for _, uid in uids do
		if not PlayerDataService.GetItemByUid(player, uid) then
			return false, {}
		end
	end

	local removedEntries: { InventoryItem } = {}
	for _, uid in uids do
		for index = #inventory, 1, -1 do
			if inventory[index].Uid == uid then
				table.insert(removedEntries, inventory[index])
				table.remove(inventory, index)
				break
			end
		end
	end

	return true, removedEntries
end

-- Adds an item and marks its Index entry. Returns (entry, isNewIndexEntry).
function PlayerDataService.AddItem(
	player: Player,
	itemId: string,
	tier: string,
	mutation: string?,
	eventMutations: { string }?
): (InventoryItem?, boolean)
	local data = state.sessionCache[player.UserId]
	if not data then
		return nil, false
	end

	-- An event-only `mutation` lands in the set (callers may hand one name).
	local base, events = MutationConfig.Normalize(mutation, eventMutations)
	local entry: InventoryItem = {
		Uid = HttpService:GenerateGUID(false),
		ItemId = itemId,
		Tier = tier,
		InUse = false,
		Mutation = base,
		EventMutations = events,
	}
	table.insert(data.Inventory, entry)
	local isNew = markIndex(data, entry)
	return entry, isNew
end

function PlayerDataService.GetIndex(player: Player): { [string]: boolean }
	local data = state.sessionCache[player.UserId]
	return if data then data.Index else {}
end

-- Marks/unmarks an inventory item as "in use" (e.g. currently displayed on a
-- pedestal) so other systems - fusion in particular - can refuse to consume
-- an item that's doing something else elsewhere. Returns false if the uid
-- isn't currently owned.
function PlayerDataService.SetItemInUse(player: Player, uid: string, inUse: boolean): boolean
	local item = PlayerDataService.GetItemByUid(player, uid)
	if not item then
		return false
	end
	item.InUse = inUse
	return true
end

--[[ Public API: pedestal displays ---------------------------------------- ]]

-- Lazily initializes PedestalDisplays so saves from before the Pedestal
-- Showcase existed still work.
function PlayerDataService.GetPedestalDisplays(player: Player): { [number]: string? }
	local data = state.sessionCache[player.UserId]
	if not data then
		return {}
	end
	data.PedestalDisplays = data.PedestalDisplays or {}
	return data.PedestalDisplays
end

-- Sets pedestalIndex's displayed item Uid, or clears it if uid is nil.
function PlayerDataService.SetPedestalDisplay(player: Player, pedestalIndex: number, uid: string?)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	data.PedestalDisplays = data.PedestalDisplays or {}
	data.PedestalDisplays[pedestalIndex] = uid
end

--[[ Public API: gacha ---------------------------------------------------- ]]

function PlayerDataService.GetGachaPulls(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.GachaPulls else 0
end

-- A free pull (daily / gift): counts for the first-pull goal, never for
-- the pad price.
function PlayerDataService.IncrementFreePulls(player: Player, count: number)
	local data = state.sessionCache[player.UserId]
	if data then
		data.FreePulls += count
	end
end

function PlayerDataService.IncrementGachaPulls(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.GachaPulls += 1
	end
end

--[[ Public API: rebirth -------------------------------------------------- ]]

function PlayerDataService.GetRebirths(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.Rebirths else 0
end

-- Studio debug (/rebirths <n>).
function PlayerDataService.SetRebirths(player: Player, rebirths: number)
	local data = state.sessionCache[player.UserId]
	if data then
		data.Rebirths = math.max(0, math.floor(rebirths))
		updateLeaderstatsRebirths(player)
	end
end

-- Applies a rebirth in one go, with no yields: RebirthService validates
-- first (cash >= RebirthConfig.GetCost), then calls this. Resets the run:
-- cash to 0 (which pays the price), generators to Basic at
-- `startingBasicLevel`, the Multiplier Pad and the gacha price; adds a
-- rebirth. Inventory, pedestals, goals and everything else stay.
-- Returns the new rebirth count.
function PlayerDataService.ApplyRebirth(player: Player, startingBasicLevel: number): number
	local data = state.sessionCache[player.UserId]
	if not data then
		return 0
	end
	data.Cash = 0
	data.Generators = { basic_generator = startingBasicLevel }
	data.CashMultiplierLevel = 0
	data.GachaPulls = 0
	data.Rebirths += 1
	updateLeaderstatsCash(player)
	updateLeaderstatsRebirths(player)
	return data.Rebirths
end

--[[ Public API: goals ---------------------------------------------------- ]]

function PlayerDataService.GetGoalIndex(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.GoalIndex else 1
end

function PlayerDataService.SetGoalIndex(player: Player, index: number)
	local data = state.sessionCache[player.UserId]
	if data then
		data.GoalIndex = index
	end
end

function PlayerDataService.GetTotalFusions(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.TotalFusions else 0
end

function PlayerDataService.IncrementTotalFusions(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.TotalFusions += 1
	end
end

-- Changes an owned item's base mutation in place (same Uid; /give, tests)
-- and marks its Index entries. An event-only name is ADDED to the stack
-- instead (AddItemEventMutation). Returns whether an Index entry is new.
-- The caller re-syncs and restyles.
function PlayerDataService.SetItemMutation(player: Player, uid: string, mutation: string?): boolean
	if mutation ~= nil and MutationConfig.IsEventOnly(mutation) then
		local _, isNew = PlayerDataService.AddItemEventMutation(player, uid, mutation)
		return isNew
	end
	local data = state.sessionCache[player.UserId]
	local item = PlayerDataService.GetItemByUid(player, uid)
	if not data or not item or (mutation ~= nil and not MutationConfig.IsValid(mutation)) then
		return false
	end
	item.Mutation = mutation
	return markIndex(data, item)
end

-- Stacks an event mutation onto an owned item in place (same Uid; a Power
-- Surge strike adds Charged). The same one never stacks twice. Returns
-- (added, isNewIndexEntry).
function PlayerDataService.AddItemEventMutation(player: Player, uid: string, mutation: string): (boolean, boolean)
	local data = state.sessionCache[player.UserId]
	local item = PlayerDataService.GetItemByUid(player, uid)
	if not data or not item then
		return false, false
	end
	local events, added = MutationConfig.AddEvent(item.EventMutations, mutation)
	if not added then
		return false, false
	end
	item.EventMutations = events
	return true, markIndex(data, item)
end

-- Marks a one-time tip seen (TipConfig ids only).
function PlayerDataService.MarkTipSeen(player: Player, id: string)
	local data = state.sessionCache[player.UserId]
	if data and TipConfig.IsValid(id) then
		data.Tips[id] = true
	end
end

-- SetSetting RevealRule: one tier's value (SettingsConfig-validated).
function PlayerDataService.SetRevealRule(player: Player, tier: string, value: string): boolean
	local data = state.sessionCache[player.UserId]
	if not data or not SettingsConfig.IsRevealTier(tier) or not SettingsConfig.IsRevealValue(value) then
		return false
	end
	data.Settings.RevealRule[tier] = value
	return true
end

-- SetSetting SfxVolume / SfxMuted (clamped / coerced server-side).
function PlayerDataService.SetSfx(player: Player, volume: number?, muted: boolean?): boolean
	local data = state.sessionCache[player.UserId]
	if not data then
		return false
	end
	if volume ~= nil then
		data.Settings.SfxVolume = SettingsConfig.SanitizeSfxVolume(volume)
	end
	if muted ~= nil then
		data.Settings.SfxMuted = muted
	end
	return true
end

-- Studio /tips reset.
function PlayerDataService.ResetTips(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.Tips = {}
	end
end

-- A heist delivered (HeistService).
function PlayerDataService.IncrementTotalSteals(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.TotalSteals += 1
	end
end

-- A shield raised with LOCK (HeistService.TryLock).
function PlayerDataService.IncrementShieldRaises(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.ShieldRaises += 1
	end
end

-- Session-only progress readout for the current goal (nil once every goal is
-- done). Not saved: GoalService recomputes it on every sync.
function PlayerDataService.SetGoalProgress(player: Player, progress: GoalProgress?)
	state.goalProgress[player.UserId] = progress
end

--[[ Public API: income + sync -------------------------------------------- ]]

-- Tiers of the items currently on this player's pedestals.
-- Tier and mutation of every item on the player's pedestals.
function PlayerDataService.GetDisplayedItems(player: Player): { TycoonConfig.PedestalItem }
	local items = {}
	local carried = state.carriedUids[player.UserId]
	local count = PlayerDataService.GetPedestalCount(player)
	for index, uid in PlayerDataService.GetPedestalDisplays(player) do
		-- A pedestal whose item is being carried off earns nothing; spots 5-6
		-- count only with the +2 Pedestals pass.
		if uid and index <= count and not (carried and carried[uid]) then
			local item = PlayerDataService.GetItemByUid(player, uid)
			if item then
				table.insert(items, { Tier = item.Tier, Mutation = item.Mutation, EventMutations = item.EventMutations })
			end
		end
	end
	return items
end

-- The one place the server builds TycoonConfig.IncomeInputs. nil until the
-- player's data has loaded. `baseOnly`: without the timed boosts (a Boost,
-- the Server Overclock): what offline earnings and cash packs use.
function PlayerDataService.GetIncomeInputs(player: Player, baseOnly: boolean?): TycoonConfig.IncomeInputs?
	local data = state.sessionCache[player.UserId]
	if not data then
		return nil
	end
	return {
		GeneratorLevels = data.Generators,
		PedestalItems = PlayerDataService.GetDisplayedItems(player),
		CashMultiplierLevel = data.CashMultiplierLevel,
		Rebirths = data.Rebirths,
		IndexMultiplier = IndexConfig.GetMultiplier(data.Index),
		EventGeneratorMultiplier = EventState.GetGeneratorMultiplier(),
		PassMultiplier = ShopConfig.GetPassIncomeMultiplier(PlayerDataService.GetOwnedPasses(player)),
		BoostMultiplier = if not baseOnly and data.Boosts.Income > 0 then ShopConfig.BoostMultiplier else 1,
		OverclockMultiplier = if baseOnly then 1 else ShopState.GetOverclockMultiplier(),
	}
end

-- Income per second without timed boosts (offline earnings, cash packs).
function PlayerDataService.GetBasePassiveCashPerSecond(player: Player): number
	local inputs = PlayerDataService.GetIncomeInputs(player, true)
	return if inputs then TycoonConfig.GetPassiveCashPerSecond(inputs) else 0
end

-- The ONE luck number every roll and every odds display uses: rebirth luck
-- x the admin luck boost x the shop (Lucky pass, Luck Potion).
function PlayerDataService.GetLuck(player: Player): number
	local data = state.sessionCache[player.UserId]
	if not data then
		return 1
	end
	return RebirthConfig.GetLuck(data.Rebirths)
		* EventState.GetLuckMultiplier()
		* ShopConfig.GetLuckMultiplier(PlayerDataService.GetOwnedPasses(player), data.Boosts.Luck)
end

--[[ Public API: shop (MonetizationService is the only writer) ------------- ]]

function PlayerDataService.SetShopSession(player: Player, session: ShopSession)
	state.shop[player.UserId] = session
end

local NO_PASSES: { [string]: boolean } = table.freeze({})

-- Pass keys this player owns (empty until MonetizationService has checked).
function PlayerDataService.GetOwnedPasses(player: Player): { [string]: boolean }
	local session = state.shop[player.UserId]
	return if session then session.OwnedPasses else NO_PASSES
end

function PlayerDataService.OwnsPass(player: Player, key: string): boolean
	return PlayerDataService.GetOwnedPasses(player)[key] == true
end

-- PolicyService: no cash / luck products. True until checked (and when the
-- check failed).
function PlayerDataService.IsPolicyRestricted(player: Player): boolean
	local session = state.shop[player.UserId]
	return session == nil or session.Restricted
end

-- 4, or 6 with the +2 Pedestals pass.
function PlayerDataService.GetPedestalCount(player: Player): number
	return ShopConfig.GetPedestalCount(PlayerDataService.GetOwnedPasses(player))
end

function PlayerDataService.HasReceipt(player: Player, purchaseId: string): boolean
	local data = state.sessionCache[player.UserId]
	return data ~= nil and table.find(data.Receipts, purchaseId) ~= nil
end

function PlayerDataService.AddReceipt(player: Player, purchaseId: string)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > ShopConfig.MaxReceipts do
		table.remove(data.Receipts, 1)
	end
end

-- Banked timed boost seconds ("Income" | "Luck").
function PlayerDataService.GetBoostSeconds(player: Player, kind: "Income" | "Luck"): number
	local data = state.sessionCache[player.UserId]
	return if data then data.Boosts[kind] else 0
end

function PlayerDataService.AddBoostSeconds(player: Player, kind: "Income" | "Luck", seconds: number)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	local cap = if kind == "Income" then ShopConfig.MaxBoostBankSeconds else ShopConfig.MaxLuckBankSeconds
	data.Boosts[kind] = ShopConfig.AddBanked(data.Boosts[kind], seconds, cap)
end

-- Ticks this player's timed boosts down by `dt` (in game only). Returns
-- true when one ran out (the caller re-syncs).
function PlayerDataService.TickBoosts(player: Player, dt: number): boolean
	local data = state.sessionCache[player.UserId]
	if not data then
		return false
	end
	local ended = false
	for _, kind in { "Income", "Luck" } do
		local before = data.Boosts[kind]
		if before > 0 then
			data.Boosts[kind] = math.max(0, before - dt)
			ended = ended or data.Boosts[kind] <= 0
		end
	end
	return ended
end

-- Raises BestIncome to `income` if higher; returns the best so far.
function PlayerDataService.RecordBestIncome(player: Player, income: number): number
	local data = state.sessionCache[player.UserId]
	if not data then
		return 0
	end
	if income == income and income > data.BestIncome and income < math.huge then
		data.BestIncome = income
	end
	return data.BestIncome
end

function PlayerDataService.GetSafeFusionTokens(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.SafeFusionTokens else 0
end

function PlayerDataService.AddSafeFusionTokens(player: Player, count: number)
	local data = state.sessionCache[player.UserId]
	if data then
		data.SafeFusionTokens = math.max(0, data.SafeFusionTokens + count)
	end
end

-- Spends one token; false if there were none.
function PlayerDataService.UseSafeFusionToken(player: Player): boolean
	local data = state.sessionCache[player.UserId]
	if not data or data.SafeFusionTokens <= 0 then
		return false
	end
	data.SafeFusionTokens -= 1
	return true
end

function PlayerDataService.IsStarterPackBought(player: Player): boolean
	local data = state.sessionCache[player.UserId]
	return data ~= nil and data.StarterPackBought
end

function PlayerDataService.SetStarterPackBought(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.StarterPackBought = true
	end
end

-- A cosmetic owned through a product or its pass (LabStyle).
function PlayerDataService.HasCosmetic(player: Player, key: string): boolean
	local data = state.sessionCache[player.UserId]
	return PlayerDataService.OwnsPass(player, key) or (data ~= nil and data.Cosmetics[key] == true)
end

function PlayerDataService.GrantCosmetic(player: Player, key: string)
	local data = state.sessionCache[player.UserId]
	if data then
		data.Cosmetics[key] = true
	end
end

-- The "New deal!" card showed for `slot`: stored so a rejoin in the same
-- slot never shows it again. Only the current slot (or the one just
-- before it, for a card shown on the boundary) is accepted.
function PlayerDataService.MarkDealPopup(player: Player, slot: number): boolean
	local data = state.sessionCache[player.UserId]
	if not data then
		return false
	end
	local _, current = DealState.GetCurrent()
	if slot ~= current and slot ~= current - DealConfig.SlotSeconds then
		return false
	end
	data.DealPopupSlot = slot
	return true
end

-- CombatService: the earned weapons, and granting one (true if it's new).
function PlayerDataService.GetWeapons(player: Player): { [string]: boolean }
	local data = state.sessionCache[player.UserId]
	return if data then data.Weapons else {}
end

function PlayerDataService.GrantWeapon(player: Player, id: string): boolean
	local data = state.sessionCache[player.UserId]
	if not data or not CombatConfig.GetWeapon(id) or data.Weapons[id] then
		return false
	end
	data.Weapons[id] = true
	return true
end

function PlayerDataService.ResetWeapons(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.Weapons = {}
	end
end

-- The pad's free tutorial pull (TycoonService): takes one if any are left.
function PlayerDataService.TakeTutorialFreePull(player: Player): boolean
	local data = state.sessionCache[player.UserId]
	if not data or data.Tutorial.Done or data.Tutorial.FreePulls <= 0 then
		return false
	end
	data.Tutorial.FreePulls -= 1
	return true
end

function PlayerDataService.RefundTutorialFreePull(player: Player)
	local data = state.sessionCache[player.UserId]
	if data then
		data.Tutorial.FreePulls += 1
	end
end

function PlayerDataService.GetTutorialFreePulls(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data and not data.Tutorial.Done then data.Tutorial.FreePulls else 0
end

-- FusionService: the tutorial's first fusion always succeeds (once per
-- account, only on its Fuse step). True = this fusion is the free one.
function PlayerDataService.TakeTutorialFreeFuse(player: Player, fuseStep: number): boolean
	local data = state.sessionCache[player.UserId]
	local t = data and data.Tutorial
	if not t or t.Done or t.Replay or t.FreeFuse or t.Step ~= fuseStep then
		return false
	end
	t.FreeFuse = true
	return true
end

function PlayerDataService.GetSessions(player: Player): number
	local data = state.sessionCache[player.UserId]
	return if data then data.Sessions else 0
end

-- OfflineDouble: doubles the offline payout once. Pending (not collected
-- yet): pays it twice over now. Already collected this session: pays the
-- same amount again. Returns the extra cash paid (0 = nothing to double).
function PlayerDataService.DoubleOfflinePayout(player: Player): number
	local data = state.sessionCache[player.UserId]
	if not data then
		return 0
	end
	local pending = state.pendingOffline[player.UserId]
	if pending and pending.Amount > 0 then
		local amount = pending.Amount
		state.pendingOffline[player.UserId] = nil
		PlayerDataService.AddCash(player, amount * 2)
		return amount
	end
	local paid = state.lastOfflinePaid[player.UserId]
	if paid and paid > 0 then
		state.lastOfflinePaid[player.UserId] = nil
		PlayerDataService.AddCash(player, paid)
		return paid
	end
	return 0
end

-- What COLLECT x2 would still double (pending, or collected this session).
function PlayerDataService.GetOfflineDoubleAmount(player: Player): number
	local pending = state.pendingOffline[player.UserId]
	if pending and pending.Amount > 0 then
		return pending.Amount
	end
	return state.lastOfflinePaid[player.UserId] or 0
end

-- Pad x rebirth: the multiplier every per-generator/per-item number shows.
function PlayerDataService.GetIncomeMultiplier(player: Player): number
	local inputs = PlayerDataService.GetIncomeInputs(player)
	return if inputs then TycoonConfig.GetIncomeMultiplier(inputs) else 1
end

-- Generators + pedestals, multiplier applied: all of a player's income.
function PlayerDataService.GetPassiveCashPerSecond(player: Player): number
	local inputs = PlayerDataService.GetIncomeInputs(player)
	return if inputs then TycoonConfig.GetPassiveCashPerSecond(inputs) else 0
end

local function indexKeys(index: { [string]: boolean }): { string }
	local keys = {}
	for key in index do
		table.insert(keys, key)
	end
	return keys
end

local function dailySnapshot(data: PlayerData?): DailyConfig.Status & { LastDay: number }
	local daily = if data then data.Daily else DailyConfig.Default()
	local status = DailyConfig.GetStatus(daily, RewardConfig.GetUtcDay(os.time()))
	return {
		CanClaim = status.CanClaim and data ~= nil,
		Day = status.Day,
		Streak = status.Streak,
		Skips = status.Skips,
		UsesSkip = status.UsesSkip,
		Resets = status.Resets,
		LastDay = daily.Day,
	}
end

function PlayerDataService.GetTycoonSnapshot(player: Player): TycoonSnapshot
	local pending = state.pendingOffline[player.UserId]
	local data = state.sessionCache[player.UserId]
	return {
		Cash = PlayerDataService.GetCash(player),
		Generators = PlayerDataService.GetGenerators(player) or {},
		CashMultiplierLevel = PlayerDataService.GetCashMultiplierLevel(player),
		PedestalDisplays = pedestalDisplaysToDisk(PlayerDataService.GetPedestalDisplays(player)),
		GachaPulls = PlayerDataService.GetGachaPulls(player),
		GoalIndex = PlayerDataService.GetGoalIndex(player),
		GoalProgress = state.goalProgress[player.UserId],
		Rebirths = PlayerDataService.GetRebirths(player),
		IndexKeys = indexKeys(PlayerDataService.GetIndex(player)),
		PendingOffline = if pending then pending.Amount else 0,
		AwaySeconds = if pending then pending.AwaySeconds else 0,
		CarriedUids = indexKeys(state.carriedUids[player.UserId] or {}),
		TipKeys = indexKeys(data and data.Tips or {}),
		Weapons = indexKeys(data and data.Weapons or {}),
		Tutorial = if data
			then {
				Step = data.Tutorial.Step,
				Done = data.Tutorial.Done,
				FreePulls = data.Tutorial.FreePulls,
				Replay = data.Tutorial.Replay,
				ReplayHint = data.Tutorial.ReplayHint,
			}
			else nil,
		Settings = SettingsConfig.Sanitize(data and data.Settings or nil),
		Shop = {
			OwnedPasses = indexKeys(PlayerDataService.GetOwnedPasses(player)),
			Restricted = PlayerDataService.IsPolicyRestricted(player),
			IncomeBoostSeconds = if data then data.Boosts.Income else 0,
			LuckBoostSeconds = if data then data.Boosts.Luck else 0,
			SafeFusionTokens = if data then data.SafeFusionTokens else 0,
			StarterPackBought = data ~= nil and data.StarterPackBought,
			Cosmetics = indexKeys(if data then data.Cosmetics else {}),
			Sessions = if data then data.Sessions else 0,
			DealPopupSlot = if data then data.DealPopupSlot else 0,
			OfflineDoubleAmount = PlayerDataService.GetOfflineDoubleAmount(player),
		},
		Daily = dailySnapshot(data),
		Gifts = {
			PlaySeconds = if data then data.Gifts.PlaySeconds else 0,
			Claimed = if data then table.clone(data.Gifts.Claimed) else {},
		},
	}
end

--[[ Public API: heist flags ---------------------------------------------- ]]
-- HeistService owns the heist; these flags are what the rest of the server
-- needs to see of it without referencing HeistService (income, sync, and
-- the "not while carrying / being stolen" guards in other services).

-- Marks one of `owner`'s displayed items as being carried off (or not).
function PlayerDataService.SetItemCarried(owner: Player, uid: string, carried: boolean)
	local set = state.carriedUids[owner.UserId]
	if carried then
		if not set then
			set = {}
			state.carriedUids[owner.UserId] = set
		end
		set[uid] = true
	elseif set then
		set[uid] = nil
		if next(set) == nil then
			state.carriedUids[owner.UserId] = nil
		end
	end
end

function PlayerDataService.IsItemCarried(owner: Player, uid: string): boolean
	local set = state.carriedUids[owner.UserId]
	return set ~= nil and set[uid] == true
end

-- Any of `owner`'s items is being carried right now.
function PlayerDataService.HasCarriedItems(owner: Player): boolean
	return state.carriedUids[owner.UserId] ~= nil
end

-- `player` is carrying a stolen item (can't pull, fuse, upgrade or rebirth).
function PlayerDataService.SetCarrying(player: Player, carrying: boolean)
	if carrying then
		state.carrying[player.UserId] = true
	else
		state.carrying[player.UserId] = nil
	end
end

function PlayerDataService.IsCarrying(player: Player): boolean
	return state.carrying[player.UserId] == true
end

-- Registers `callback(player)` to run synchronously before `player`'s data
-- is saved and released: at the start of PlayerRemoving, and for every
-- loaded player when the server closes. HeistService fails active carries
-- here, so a save never races a half-finished steal.
function PlayerDataService.OnRelease(callback: (Player) -> ())
	table.insert(state.releaseHooks, callback)
end

runReleaseHooks = function(player: Player)
	for _, hook in state.releaseHooks do
		xpcall(hook, function(err)
			warn(("PlayerDataService: OnRelease hook failed for %s: %s"):format(player.Name, tostring(err)))
		end, player)
	end
end

--[[ Public API: offline earnings ------------------------------------------ ]]

-- Uncollected offline earnings, or nil.
function PlayerDataService.GetPendingOffline(player: Player): PendingOffline?
	return state.pendingOffline[player.UserId]
end

-- Replaces the pending offline earnings (0 clears them). /offline uses it.
function PlayerDataService.SetPendingOffline(player: Player, amount: number, awaySeconds: number)
	if amount > 0 then
		state.pendingOffline[player.UserId] = { Amount = amount, AwaySeconds = awaySeconds, Since = os.clock() }
	else
		state.pendingOffline[player.UserId] = nil
	end
end

-- Re-prices still-unclaimed offline earnings from the CURRENT base income.
-- The payout is computed on load, before MonetizationService's async pass
-- check has run, so 2x Cash / VIP owners were paid at the no-pass rate.
-- MonetizationService calls this once passes are known; never lowers it.
function PlayerDataService.RecomputePendingOffline(player: Player)
	local pending = state.pendingOffline[player.UserId]
	if not pending then
		return
	end
	local amount = OfflineConfig.Compute(PlayerDataService.GetBasePassiveCashPerSecond(player), pending.AwaySeconds)
	if amount > pending.Amount then
		pending.Amount = amount
	end
end

-- Clears the pending offline earnings and returns the amount (0 if none).
-- The caller pays it; taking and paying happen with no yield between them.
function PlayerDataService.TakePendingOffline(player: Player): number
	local pending = state.pendingOffline[player.UserId]
	state.pendingOffline[player.UserId] = nil
	local amount = if pending then pending.Amount else 0
	if amount > 0 then
		-- COLLECT x2 (OfflineDouble) can still double it this session.
		state.lastOfflinePaid[player.UserId] = amount
	end
	return amount
end

-- On load: what the lab earned while away, at the income the player left
-- with. LastOnline moves to now straight away (and is saved), so a rejoin
-- can't claim the same time twice.
local function computeOfflineEarnings(player: Player)
	local data = state.sessionCache[player.UserId]
	if not data then
		return
	end
	local lastOnline = data.LastOnline
	data.LastOnline = os.time()
	if not lastOnline then
		return
	end
	local away = math.max(0, os.time() - lastOnline)
	-- Base income: timed boosts are paused offline.
	local amount = OfflineConfig.Compute(PlayerDataService.GetBasePassiveCashPerSecond(player), away)
	PlayerDataService.SetPendingOffline(player, amount, away)
	if amount > 0 then
		PlayerDataService.SaveNow(player)
	end
end

-- Registers `callback(player)` to run synchronously at the start of every
-- SyncTycoon, BEFORE the snapshot is built - so anything it changes (a goal
-- reward, the next goal's progress) goes out in that same snapshot. A plain
-- callback rather than a BindableEvent on purpose: under deferred signal
-- behaviour a BindableEvent handler would run after the snapshot was sent.
-- Callbacks must not call SyncTycoon themselves.
function PlayerDataService.OnSync(callback: (Player) -> ())
	table.insert(state.syncHooks, callback)
end

-- The one way every service pushes cash/upgrade state to a client.
function PlayerDataService.SyncTycoon(player: Player)
	if not state.sessionCache[player.UserId] then
		return
	end
	for _, hook in state.syncHooks do
		-- A failing hook must never stop the snapshot from going out.
		xpcall(hook, function(err)
			warn(("PlayerDataService: OnSync hook failed for %s: %s"):format(player.Name, tostring(err)))
		end, player)
	end
	RemoteEvents.SyncTycoon:FireClient(player, PlayerDataService.GetTycoonSnapshot(player))
end

--[[ Player lifecycle ----------------------------------------------------- ]]

local function createLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	-- Created before Cash so it's the first leaderboard column.
	local rebirthsValue = Instance.new("IntValue")
	rebirthsValue.Name = "Rebirths"
	rebirthsValue.Value = 0
	rebirthsValue.Parent = leaderstats

	local cashValue = Instance.new("StringValue")
	cashValue.Name = "Cash"
	cashValue.Value = NumberFormat.Money(0)
	cashValue.Parent = leaderstats

	leaderstats.Parent = player
end

local dataLoaded = Instance.new("BindableEvent")
-- Fires (player) once a player's data is in the session cache. TycoonService
-- waits on this before restoring saved pedestals on claim.
PlayerDataService.DataLoaded = dataLoaded.Event

local function onPlayerAdded(player: Player)
	if not loadData(player) then
		return
	end
	createLeaderstats(player)
	updateLeaderstatsCash(player)
	updateLeaderstatsRebirths(player)
	computeOfflineEarnings(player)

	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	PlayerDataService.SyncTycoon(player)
	AnalyticsKit.Funnel(player, "Join")
	dataLoaded:Fire(player)
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	state.releasing[userId] = true
	-- Before anything is saved: active steals on either side resolve first.
	runReleaseHooks(player)
	AnalyticsKit.Release(player)
	state.carriedUids[userId] = nil
	state.carrying[userId] = nil
	-- Left before collecting (or before the auto-claim): pay it, never lose it.
	payPendingOffline(userId)
	local profile = state.profiles[userId]
	local data = state.sessionCache[userId]
	if profile and profile:IsActive() then
		-- The final copy, then release the lock (ProfileStore writes it).
		if data then
			profile.Data = toDisk(data)
		end
		profile:EndSession()
	end
	state.sessionCache[userId] = nil
	state.profiles[userId] = nil
	state.goalProgress[userId] = nil
	state.lastSyncRequest[userId] = nil
	state.shop[userId] = nil
	state.lastOfflinePaid[userId] = nil
	task.delay(RELEASE_FLAG_SECONDS, function()
		if not Players:GetPlayerByUserId(userId) then
			state.releasing[userId] = nil
		end
	end)
end

-- A client asking for a fresh snapshot (it just had a request rejected and
-- its view may be stale): the inventory too, since InUse lives there. At
-- most once per SYNC_REQUEST_COOLDOWN_SECONDS.
local function onRequestSync(player: Player)
	local now = os.clock()
	local last = state.lastSyncRequest[player.UserId]
	if last and now - last < SYNC_REQUEST_COOLDOWN_SECONDS then
		return
	end
	state.lastSyncRequest[player.UserId] = now
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	PlayerDataService.SyncTycoon(player)
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function PlayerDataService:Init()
	-- Funnel steps are saved in the profile; the cash balance rides along
	-- on economy events.
	AnalyticsKit.SetFunnelStore({
		Mark = function(player: Player, step: string): boolean
			local data = state.sessionCache[player.UserId]
			if not data or data.Funnel[step] then
				return false
			end
			data.Funnel[step] = true
			return true
		end,
		GetBalance = function(player: Player): number
			return PlayerDataService.GetCash(player)
		end,
	})
	table.insert(state.connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	table.insert(state.connections, RemoteEvents.RequestSync.OnServerEvent:Connect(onRequestSync))
	-- MarkTipSeen { Id }: only TipConfig ids are stored; no reply needed (the
	-- client marks it locally too, and the next snapshot carries it).
	table.insert(
		state.connections,
		RemoteEvents.MarkTipSeen.OnServerEvent:Connect(function(player: Player, payload: unknown)
			local id = typeof(payload) == "table" and (payload :: any).Id or nil
			if TipConfig.IsValid(id) then
				PlayerDataService.MarkTipSeen(player, id :: string)
			end
		end)
	)

	-- MarkDealPopup { Slot }: the "New deal!" card showed for that slot
	-- (the current one only); saved, no reply (the client keeps it too).
	table.insert(
		state.connections,
		RemoteEvents.MarkDealPopup.OnServerEvent:Connect(function(player: Player, payload: unknown)
			local slot = typeof(payload) == "table" and (payload :: any).Slot or nil
			if typeof(slot) == "number" and slot == slot and slot >= 0 and slot < math.huge and slot % 1 == 0 then
				PlayerDataService.MarkDealPopup(player, slot)
			end
		end)
	)

	-- SetSetting { Key = "RevealRule", Tier, Value } (tier and value
	-- whitelisted), { Key = "SfxVolume", Value } (clamped 0..1) or
	-- { Key = "SfxMuted", Value } (a boolean) (SettingsConfig); stored in the saved profile, then one
	-- (coalesced) sync carries Settings back.
	table.insert(
		state.connections,
		RemoteEvents.SetSetting.OnServerEvent:Connect(function(player: Player, payload: unknown)
			if typeof(payload) ~= "table" then
				return
			end
			local request = payload :: any
			local changed = false
			if request.Key == "RevealRule" then
				changed = PlayerDataService.SetRevealRule(player, request.Tier, request.Value)
			-- Finite numbers only: SanitizeSfxVolume maps NaN / inf to the
			-- default, so a junk value silently reset the player's volume.
			elseif
				request.Key == "SfxVolume"
				and typeof(request.Value) == "number"
				and request.Value == request.Value
				and math.abs(request.Value) ~= math.huge
			then
				changed = PlayerDataService.SetSfx(player, request.Value, nil)
			elseif request.Key == "SfxMuted" and typeof(request.Value) == "boolean" then
				changed = PlayerDataService.SetSfx(player, nil, request.Value)
			elseif request.Key == "GoalPath" and SettingsConfig.IsGoalPathValue(request.Value) then
				local data = state.sessionCache[player.UserId]
				if data then
					data.Settings.GoalPath = request.Value
					changed = true
				end
			elseif request.Key == "AutoFuse" and typeof(request.Value) == "boolean" then
				local data = state.sessionCache[player.UserId]
				if data then
					data.Settings.AutoFuse = request.Value
					changed = true
				end
			end
			if not changed then
				return
			end
			if not state.settingsSyncQueued[player.UserId] then
				state.settingsSyncQueued[player.UserId] = true
				task.delay(SETTINGS_SYNC_DELAY_SECONDS, function()
					state.settingsSyncQueued[player.UserId] = nil
					if player.Parent and state.sessionCache[player.UserId] then
						PlayerDataService.SyncTycoon(player)
					end
				end)
			end
		end)
	)

	-- Covers anyone who joined before this service finished initialising.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Autosave (AUTO_SAVE_PERIOD) and the shutdown save are ProfileStore's;
	-- each profile's OnLastSave runs the release hooks first (loadData).
end

return PlayerDataService
