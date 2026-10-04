--!strict
--[[
	MonetizationService
	-------------------
	Everything that is sold (ShopConfig), granted only here and only
	server-side, resolved from the requesting Player.

	Compliance (CLAUDE.md "Monetization"):
	  * PolicyService at join: ArePaidRandomItemsRestricted players never see
	    or get a ShopConfig.PolicyRestricted item (cash, luck, boosts,
	    Overclock, Safe Fusion, the Starter Pack, Double Offline Cash). A
	    failed policy call counts as restricted. The gacha and fusion stay
	    fully playable with earned cash.
	  * ProcessReceipt is idempotent: a PurchaseId already in
	    PlayerData.Receipts returns PurchaseGranted without granting again;
	    otherwise check -> grant -> record -> SaveNowAsync, and only a
	    successful save returns PurchaseGranted. A profile that isn't loaded,
	    a refused item or a failed save returns NotProcessedYet (Roblox
	    retries it).
	  * Passes: UserOwnsGamePassAsync at join (every pass with an Id), plus
	    PromptGamePassPurchaseFinished.
	  * Purchases start from RequestShopPurchase { Key }: the server checks the
	    item (set up, policy, one-time, a live sale window, something to
	    double) and only then prompts. A sale product is refused outside its
	    window (ShopState), at the prompt and again at the receipt unless the
	    server prompted it inside the window shortly before.
	  * Studio: an item with Id 0 is granted straight away on request (a test
	    grant, marked as such), and `/shop grant <key>` (DebugService) runs
	    the same grant path. Passes granted that way last the session.

	Timed boosts tick here once a second for players in game (they are saved
	as remaining seconds, so they pause offline). The Server Overclock is
	session-only: workspace attributes OverclockUntil / OverclockBy
	(ShopState reads them on both sides).
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ShopState = require(ReplicatedStorage.Shared.Modules.ShopState)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))
local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule

--[[ Private state -------------------------------------------------------- ]]

type State = {
	connections: { RBXScriptConnection },
	-- Pass keys owned (Roblox check + purchases + Studio test grants).
	owned: { [number]: { [string]: boolean } },
	restricted: { [number]: boolean },
	-- When the server last prompted a sale product for a player, per key
	-- (a receipt for it is honoured shortly after the window closes).
	salePromptedAt: { [number]: { [string]: number } },
	-- Called after a player's passes / cosmetics change (VIP tag, lab trim,
	-- LabStyle), and after any grant (AutoFuse etc.). Registered in Start by
	-- this service's own effect code.
	passHooks: { (Player) -> () },
	tickAccumulator: number,
	overclockWasOn: boolean,
}

local state: State = {
	connections = {},
	owned = {},
	restricted = {},
	salePromptedAt = {},
	passHooks = {},
	tickAccumulator = 0,
	overclockWasOn = false,
}

-- A sale receipt is honoured this long after the server prompted it (the
-- purchase dialog may still be open when the window closes).
local SALE_RECEIPT_GRACE_SECONDS = 10 * 60
local TICK_SECONDS = 1
local VIP_TAG_NAME = "VipTag"
local VIP_TAG_STUDS = Vector2.new(3.6, 1.1)
local VIP_TAG_OFFSET = Vector3.new(0, 2.4, 0)
local VIP_TAG_MAX_DISTANCE = 70

local MonetizationService = {}
local watchCharacter: (Player) -> () -- defined with the pass effects

MonetizationService.Name = "MonetizationService"

--[[ Helpers -------------------------------------------------------------- ]]

local function publishSession(player: Player)
	local owned = state.owned[player.UserId] or {}
	PlayerDataService.SetShopSession(player, {
		OwnedPasses = owned,
		Restricted = state.restricted[player.UserId] ~= false,
	})
end

local function runPassHooks(player: Player)
	for _, hook in state.passHooks do
		task.spawn(hook, player)
	end
end

local function syncPlayer(player: Player)
	if PlayerDataService.IsDataLoaded(player) then
		PlayerDataService.SyncTycoon(player)
	end
end

local function syncEveryone()
	for _, player in Players:GetPlayers() do
		syncPlayer(player)
	end
end

-- Why `key` can't be sold to `player` right now, or nil if it can.
-- `atReceipt`: a receipt is being processed (a sale prompted inside its
-- window is honoured for a grace period).
local function refusal(player: Player, key: string, atReceipt: boolean?): string?
	local item = ShopConfig.GetItem(key)
	if not item then
		return "Unknown"
	end
	if not PlayerDataService.IsDataLoaded(player) then
		return "NotLoaded"
	end
	if item.Id == 0 and not RunService:IsStudio() then
		return "NotSetUp"
	end
	if item.PolicyRestricted and PlayerDataService.IsPolicyRestricted(player) then
		return "Restricted"
	end
	if item.Kind == "Pass" and PlayerDataService.OwnsPass(player, key) then
		return "Owned"
	end
	if item.OneTime and key == "StarterPack" and PlayerDataService.IsStarterPackBought(player) then
		return "Owned"
	end
	if item.SaleOf and not ShopState.IsSaleLive(key) then
		local prompted = state.salePromptedAt[player.UserId]
		local at = prompted and prompted[key]
		if not (atReceipt and at and os.clock() - at <= SALE_RECEIPT_GRACE_SECONDS) then
			return "SaleOver"
		end
	end
	if key == "OfflineDouble" and PlayerDataService.GetOfflineDoubleAmount(player) <= 0 then
		return "NothingToDouble"
	end
	return nil
end

--[[ Grants ---------------------------------------------------------------
	Each grant is synchronous (no yields), so ProcessReceipt's check, grant
	and record can't interleave with another request. Returns the lines for
	the THANK YOU card.
]]

local function grantBoost(player: Player, seconds: number): string
	PlayerDataService.AddBoostSeconds(player, "Income", seconds)
	local banked = PlayerDataService.GetBoostSeconds(player, "Income")
	return ("⚡ ×%d income · %d min banked"):format(ShopConfig.BoostMultiplier, math.floor(banked / 60))
end

local function grantCash(player: Player, packKey: string): string
	local amount = ShopConfig.GetCashPackAmount(packKey, PlayerDataService.GetBasePassiveCashPerSecond(player))
	PlayerDataService.AddCash(player, amount)
	return ("💰 +%s cash"):format(NumberFormat.Money(amount))
end

local function grantOverclock(player: Player): string
	local now = Workspace:GetServerTimeNow()
	local current = ShopState.GetOverclockSeconds()
	local seconds = math.min(ShopConfig.MaxOverclockSeconds, current + ShopConfig.OverclockSeconds)
	Workspace:SetAttribute("OverclockUntil", now + seconds)
	Workspace:SetAttribute("OverclockBy", player.DisplayName)
	state.overclockWasOn = true
	RemoteEvents.ShopAnnouncement:FireAllClients({
		Kind = "Overclock",
		PlayerName = player.DisplayName,
		Seconds = seconds,
	})
	-- Everyone's income just changed.
	syncEveryone()
	return ("🌐 Server Overclock · ×%d income for everyone · %d min"):format(
		ShopConfig.OverclockMultiplier,
		math.floor(seconds / 60)
	)
end

local GRANTS: { [string]: (Player) -> { string } } = {
	QuickBoost = function(player)
		return { grantBoost(player, ShopConfig.BoostSeconds.QuickBoost) }
	end,
	Boost = function(player)
		return { grantBoost(player, ShopConfig.BoostSeconds.Boost) }
	end,
	BoostSale = function(player)
		return { grantBoost(player, ShopConfig.BoostSeconds.BoostSale) }
	end,
	PocketCash = function(player)
		return { grantCash(player, "PocketCash") }
	end,
	CashCrate = function(player)
		return { grantCash(player, "CashCrate") }
	end,
	CashVault = function(player)
		return { grantCash(player, "CashVault") }
	end,
	Overclock = function(player)
		return { grantOverclock(player) }
	end,
	LuckPotion = function(player)
		PlayerDataService.AddBoostSeconds(player, "Luck", ShopConfig.LuckPotionSeconds)
		local banked = PlayerDataService.GetBoostSeconds(player, "Luck")
		return { ("🧪 ×%d luck · %d min banked"):format(ShopConfig.LuckPotionMultiplier, math.floor(banked / 60)) }
	end,
	SafeFusion1 = function(player)
		PlayerDataService.AddSafeFusionTokens(player, ShopConfig.SafeFusionTokens.SafeFusion1)
		return { ("🛡 Safe Fusion · you have %d"):format(PlayerDataService.GetSafeFusionTokens(player)) }
	end,
	SafeFusion5 = function(player)
		PlayerDataService.AddSafeFusionTokens(player, ShopConfig.SafeFusionTokens.SafeFusion5)
		return { ("🛡 +5 Safe Fusion · you have %d"):format(PlayerDataService.GetSafeFusionTokens(player)) }
	end,
	StarterPack = function(player)
		PlayerDataService.SetStarterPackBought(player)
		PlayerDataService.GrantCosmetic(player, "LabStyle")
		return {
			"🎨 Neon Pink Lab",
			grantBoost(player, ShopConfig.BoostSeconds.StarterPack),
			grantCash(player, "PocketCash"),
		}
	end,
	OfflineDouble = function(player)
		local extra = PlayerDataService.DoubleOfflinePayout(player)
		return { ("🌙 Offline cash doubled · +%s"):format(NumberFormat.Money(extra)) }
	end,
}

-- Grants `key` (already checked) and tells the client. Synchronous.
local function grant(player: Player, key: string, test: boolean?): { string }
	local item = ShopConfig.GetItem(key) :: ShopConfig.Item
	local lines: { string }
	if item.Kind == "Pass" then
		local owned = state.owned[player.UserId] or {}
		owned[key] = true
		state.owned[player.UserId] = owned
		publishSession(player)
		lines = { ("%s %s · %s"):format(item.Icon, item.Name, item.Effect) }
	else
		local handler = GRANTS[key]
		lines = if handler then handler(player) else {}
	end
	warn(("MonetizationService: granted %s to %s (%d)%s"):format(key, player.Name, player.UserId, if test then " [STUDIO TEST]" else ""))
	runPassHooks(player)
	syncPlayer(player)
	RemoteEvents.ShopPurchased:FireClient(player, { Key = key, Result = "Granted", Lines = lines, Test = test == true })
	return lines
end

--[[ Join: policy + passes ------------------------------------------------- ]]

local function checkPlayer(player: Player)
	local restricted = true
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if ok and typeof(info) == "table" then
		restricted = (info :: any).ArePaidRandomItemsRestricted ~= false
	else
		warn(("MonetizationService: policy check failed for %s, treating as restricted (%s)"):format(player.Name, tostring(info)))
	end
	if not player.Parent then
		return
	end
	state.restricted[player.UserId] = restricted

	local owned = state.owned[player.UserId] or {}
	for key, item in ShopConfig.Items do
		if item.Kind == "Pass" and item.Id ~= 0 and not owned[key] then
			local passOk, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, item.Id)
			end)
			if passOk and has == true then
				owned[key] = true
			end
		end
	end
	if not player.Parent then
		return
	end
	state.owned[player.UserId] = owned
	publishSession(player)
	runPassHooks(player)
	syncPlayer(player)
end

--[[ Purchases -------------------------------------------------------------- ]]

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player or not PlayerDataService.IsDataLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if PlayerDataService.HasReceipt(player, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local item = ShopConfig.GetItemById("Product", receipt.ProductId)
	if not item then
		warn(("MonetizationService: receipt for unknown product %s from %s"):format(tostring(receipt.ProductId), player.Name))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local reason = refusal(player, item.Key, true)
	if reason then
		warn(("MonetizationService: receipt %s for %s refused (%s)"):format(purchaseId, item.Key, reason))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Grant and record together (no yield between them), then save.
	grant(player, item.Key)
	PlayerDataService.AddReceipt(player, purchaseId)
	if not PlayerDataService.SaveNowAsync(player) then
		-- The grant stays in the session; the retry finds the receipt.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function onPassPurchaseFinished(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	local item = ShopConfig.GetItemById("Pass", passId)
	if item and not PlayerDataService.OwnsPass(player, item.Key) then
		grant(player, item.Key)
	end
end

local function refuse(player: Player, key: string, reason: string)
	RemoteEvents.ShopPurchased:FireClient(player, { Key = key, Result = "Refused", Reason = reason })
end

local function onRequestShopPurchase(player: Player, payload: unknown)
	local key = if typeof(payload) == "table" then (payload :: any).Key else nil
	if typeof(key) ~= "string" then
		return
	end
	local reason = refusal(player, key)
	if reason then
		refuse(player, key, reason)
		return
	end
	local item = ShopConfig.GetItem(key) :: ShopConfig.Item
	if item.Id == 0 then
		-- Studio only (refusal blocks Id 0 in live games): a test grant.
		grant(player, key, true)
		return
	end
	if item.SaleOf then
		local prompted = state.salePromptedAt[player.UserId] or {}
		prompted[key] = os.clock()
		state.salePromptedAt[player.UserId] = prompted
	end
	if item.Kind == "Pass" then
		MarketplaceService:PromptGamePassPurchase(player, item.Id)
	else
		MarketplaceService:PromptProductPurchase(player, item.Id)
	end
end

--[[ Timed boosts ------------------------------------------------------------ ]]

local function onHeartbeat(dt: number)
	state.tickAccumulator += dt
	if state.tickAccumulator < TICK_SECONDS then
		return
	end
	local step = state.tickAccumulator
	state.tickAccumulator = 0
	for _, player in Players:GetPlayers() do
		if PlayerDataService.IsDataLoaded(player) and PlayerDataService.TickBoosts(player, step) then
			-- A boost ran out: income and odds displays change.
			syncPlayer(player)
		end
	end
	local overclockOn = ShopState.GetOverclockSeconds() > 0
	if state.overclockWasOn and not overclockOn then
		Workspace:SetAttribute("OverclockBy", "")
		syncEveryone()
	end
	state.overclockWasOn = overclockOn
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	state.owned[userId] = nil
	state.restricted[userId] = nil
	state.salePromptedAt[userId] = nil
end

--[[ Pass effects -------------------------------------------------------------
	Run after a join check, a pass purchase or any grant: the pedestal spots
	(+2 Pedestals), the lab look (VIP trim, Neon Pink), the VIP head tag and
	the Player attribute "VIP" (clients prefix that player's chat).
]]

local function applyVipTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local existing = head:FindFirstChild(VIP_TAG_NAME)
	local vip = PlayerDataService.OwnsPass(player, "VIP")
	if vip and not existing then
		BillboardKit.Chip(head, {
			Name = VIP_TAG_NAME,
			Text = "👑 VIP",
			Gradient = UITheme.Gradients.Gold,
			TextColor = UITheme.Colors.GoldText,
			Studs = VIP_TAG_STUDS,
			StudsOffset = VIP_TAG_OFFSET,
			MaxDistance = VIP_TAG_MAX_DISTANCE,
		})
	elseif not vip and existing then
		existing:Destroy()
	end
end

-- The VIP tag goes back on every respawn.
function watchCharacter(player: Player)
	table.insert(state.connections, player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Head", 10)
		applyVipTag(player)
	end))
end

local function applyPassEffects(player: Player)
	if not player.Parent then
		return
	end
	player:SetAttribute("VIP", PlayerDataService.OwnsPass(player, "VIP"))
	applyVipTag(player)
	TycoonService.RefreshPedestalLabels(player)
	TycoonService.ApplyLabLook(player)
end

--[[ Public API -------------------------------------------------------------- ]]

-- Studio: runs the real grant path without Robux (`/shop grant <key>`).
-- Returns false (and why) when the item can't be granted.
function MonetizationService.GrantForTest(player: Player, key: string): (boolean, string?)
	if not RunService:IsStudio() then
		return false, "StudioOnly"
	end
	local item = ShopConfig.GetItem(key)
	if not item then
		return false, "Unknown"
	end
	local reason = refusal(player, key)
	-- A test grant skips "not set up" / sale window / policy, but never
	-- double-grants a pass or the one-time pack.
	if reason == "Owned" or reason == "NotLoaded" or reason == "NothingToDouble" then
		return false, reason
	end
	grant(player, key, true)
	return true, nil
end

-- Registers a callback run after a player's passes or grants change.
function MonetizationService.OnPassesChanged(callback: (Player) -> ())
	table.insert(state.passHooks, callback)
end

--[[ Lifecycle ---------------------------------------------------------------- ]]

function MonetizationService:Init()
	MarketplaceService.ProcessReceipt = processReceipt
	table.insert(state.connections, MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchaseFinished))
	table.insert(state.connections, RemoteEvents.RequestShopPurchase.OnServerEvent:Connect(onRequestShopPurchase))
	table.insert(state.connections, Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(checkPlayer, player)
		watchCharacter(player)
	end))
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	table.insert(state.connections, RunService.Heartbeat:Connect(onHeartbeat))
	Workspace:SetAttribute("OverclockUntil", 0)
	Workspace:SetAttribute("OverclockBy", "")
end

function MonetizationService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)
	MonetizationService.OnPassesChanged(applyPassEffects)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPlayer, player)
		watchCharacter(player)
	end
end

function MonetizationService:Stop()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
end

return MonetizationService
