--!strict
--[[
	HeistService
	------------
	Stealing displayed items, and the lab shield (numbers in HeistConfig).

	Shield
	  * Per player, until a server time (workspace:GetServerTimeNow()). It is
	    published as the plot attribute ShieldUntil so every client renders
	    the fence without a remote.
	  * Raised for ClaimShieldSeconds on claim, VictimShieldSeconds after
	    losing an item, and ShieldSeconds when the owner LOCKs on purpose:
	    TryLock, only from the LOCK console's prompt (LockKit, built on
	    claim), checked server-side to be within reach of that console.
	    There is no remote for it: you have to run home to lock.
	  * After any shield ends (timeout or a drop) LOCK recharges for
	    ShieldRearmSeconds: the thieves' window. Published as the plot
	    attribute ShieldRearmAt (server time); clients drive the console's
	    label, button and prompt and the HUD status chip from ShieldUntil /
	    ShieldRearmAt / Protected. The claim and victim shields ignore the
	    recharge; /shield 0 clears it.
	  * While up, a loop every EjectTickSeconds moves any non-owner whose
	    root is inside the plot's walls to the street in front of its gate.

	Protection
	  * A lab whose owner is under HeistConfig.MinRebirths can't be stolen
	    from at all (plot attribute Protected; the sign shows a PROTECTED
	    pill). /stealable lifts it in Studio for testing.

	The steal: NO DUPLICATION, NO LOSS
	  * Grab (RequestSteal) only records a carry in session state and flags
	    it (PlayerDataService.SetItemCarried / SetCarrying, the pedestal's
	    BeingStolen attribute). Neither inventory changes: the item stays in
	    the victim's inventory, on its pedestal, the whole carry. A save at
	    any moment of a carry therefore writes the victim still owning it.
	  * Deliver is the ONLY place inventories change, in one synchronous
	    block with no yields: clear the victim's pedestal, remove the item
	    from the victim, AddItem the same ItemId/tier/mutation to the thief
	    (a new Uid). Nothing can interleave with it.
	  * Every other ending (tagged, timeout, death, either side leaving, the
	    victim's plot gone, server shutdown, /wipe) is a fail: drop the carry
	    and the flags; the item never left. PlayerDataService runs the
	    OnRelease hook before any save on leave and on shutdown.
	  * Fairness: the owner standing within OwnerBlockRadius of the pedestal
	    guards it (grab rejected; pedestal attribute GuardedByOwner tells the
	    client). The owner can't tag for TagGraceSeconds after a grab, and
	    runs at OwnerChaseWalkSpeed while any of their items is carried.
	  * The item can be in at most one carry (carriedItems), and a thief in
	    at most one; server events run one at a time, so two grabs of the
	    same pedestal in one frame resolve as one win, one reject.

	Follows ServiceTemplate:
	  :Init()   own state, RequestSteal, the LOCK prompt and
	            PlayerRemoving.
	  :Start()  resolves PlayerDataService and TycoonService, registers the
	            OnRelease hook, starts the shield loop and the carry loop.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local LockKit = require(ReplicatedStorage.Shared.Modules.LockKit)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)
local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))

-- "Knocked": a weapon hit the carrying thief (CombatService): it goes back,
-- the owner sees SAVED.
export type Outcome = "Delivered" | "Saved" | "Knocked" | "Timeout" | "Left" | "Died" | "Failed"

-- What a client needs to show the item (the orb, the name).
type ItemInfo = {
	ItemId: string,
	Tier: string,
	Mutation: string?,
	Name: string,
}

type Carry = {
	ThiefUserId: number,
	VictimUserId: number,
	PedestalIndex: number,
	ItemUid: string,
	StartedAt: number, -- os.clock()
	EndsAt: number, -- server time (GetServerTimeNow), for clients' timers
	Item: ItemInfo,
	ThiefName: string,
	VictimName: string,
	DiedConnection: RBXScriptConnection?,
}

type State = {
	connections: { RBXScriptConnection },
	-- Server time (GetServerTimeNow) each player's shield is up until.
	shieldUntil: { [number]: number },
	-- os.clock() of each victim's recent losses (pruned to LossWindowSeconds).
	recentLosses: { [number]: { number } },
	-- Plots seen claimed (the claim shield is raised once, on the change).
	claimSeen: { [number]: boolean },
	-- Server time each player's pad may raise the shield again (re-arm).
	rearmAt: { [number]: number },
	-- os.clock() of each player's last lock request (the console prompt).
	lastLockRequest: { [number]: number },
	-- Studio /stealable: lab stealable even under MinRebirths.
	debugStealable: { [number]: boolean },
	-- Active carries by thief UserId, and the Uid -> thief index that keeps
	-- an item in at most one carry.
	carries: { [number]: Carry },
	carriedItems: { [string]: number },
	carryAccumulator: number,
	running: boolean,
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	connections = {},
	shieldUntil = {},
	recentLosses = {},
	claimSeen = {},
	rearmAt = {},
	lastLockRequest = {},
	debugStealable = {},
	carries = {},
	carriedItems = {},
	carryAccumulator = 0,
	running = false,
}

-- Rejections an honest client can't produce (its prompt is hidden then).
local SUSPICIOUS_REASONS = {
	InvalidArguments = true,
	OwnLab = true,
	TooFar = true,
	Shielded = true,
	Empty = true,
	NeedsRebirth = true,
	Protected = true,
	NoVictim = true,
}

-- Player attributes the clients read to draw the carried orb and the
-- THIEF pill on every screen (no remote needed for bystanders).
local CARRY_ATTRIBUTES = { "HeistTier", "HeistMutation", "HeistItemName", "HeistEndsAt", "HeistVictimUserId" }

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule

local HeistService = {}

HeistService.Name = "HeistService"

--[[ Private helpers ------------------------------------------------------ ]]

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- The player's claimed plot and its origin, or nil.
local function getClaimedPlot(player: Player): (Model?, CFrame?)
	local plot = TycoonService.GetPlotForPlayer(player)
	if not plot or plot.Parent == nil or plot:GetAttribute("Claimed") ~= true then
		return nil, nil
	end
	local origin = plot.PrimaryPart
	if not origin then
		return nil, nil
	end
	return plot, origin.CFrame
end

local function getPedestal(plot: Model, index: number): BasePart?
	local folder = plot:FindFirstChild("Pedestals")
	local pedestal = folder and folder:FindFirstChild("Pedestal" .. index)
	return if pedestal and pedestal:IsA("BasePart") then pedestal else nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- The owner is standing guard at this pedestal (within OwnerBlockRadius).
-- A ragdolled player (CombatService, Player attribute RagdollUntil, server
-- time) can't steal, LOCK or guard.
local function isRagdolled(player: Player): boolean
	local untilTime = player:GetAttribute("RagdollUntil")
	return typeof(untilTime) == "number" and untilTime > serverNow()
end

local function isGuarded(owner: Player, pedestal: BasePart): boolean
	if isRagdolled(owner) then
		return false
	end
	local root = getRoot(owner)
	return root ~= nil and flatDistance(root.Position, pedestal.Position) <= HeistConfig.OwnerBlockRadius
end

local function isInsidePlot(origin: CFrame, position: Vector3): boolean
	return PlotLayout.IsInsidePlot(origin:PointToObjectSpace(position))
end

-- The street in front of the plot's gate (its SpawnLocation), plus clearance.
local function getEjectCFrame(plot: Model): CFrame?
	local spawn = plot:FindFirstChildWhichIsA("SpawnLocation", true)
	if not spawn then
		return nil
	end
	return spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + PlotLayout.SPAWN_CHARACTER_CLEARANCE, 0)
end

local function pruneLosses(userId: number)
	local losses = state.recentLosses[userId]
	if not losses then
		return
	end
	local cutoff = os.clock() - HeistConfig.LossWindowSeconds
	for index = #losses, 1, -1 do
		if losses[index] < cutoff then
			table.remove(losses, index)
		end
	end
end

local function isFeedTier(tier: string): boolean
	return (ItemConfig.Tiers[tier] or 0) >= (ItemConfig.Tiers[HeistConfig.FeedMinTier] or math.huge)
end

local function syncBoth(a: Player?, b: Player?, inventory: boolean)
	for _, player in { a, b } do
		if player and PlayerDataService.IsDataLoaded(player) then
			if inventory then
				RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
			end
			PlayerDataService.SyncTycoon(player)
		end
	end
end

--[[ Public API: shield and protection ------------------------------------ ]]

local function publishShield(player: Player)
	local plot = TycoonService.GetPlotForPlayer(player)
	if plot then
		plot:SetAttribute("ShieldUntil", state.shieldUntil[player.UserId] or 0)
		plot:SetAttribute("ShieldRearmAt", state.rearmAt[player.UserId] or 0)
	end
end

-- Raises `player`'s shield for `seconds` from now (0 drops it). Either way
-- the pad's re-arm lock runs from the moment this shield ends. Callers that
-- aren't the pad (claim, victim, /shield) aren't subject to the lock.
function HeistService.RaiseShield(player: Player, seconds: number)
	local now = serverNow()
	local untilTime = if seconds > 0 then now + seconds else 0
	state.shieldUntil[player.UserId] = untilTime
	state.rearmAt[player.UserId] = (if seconds > 0 then untilTime else now) + HeistConfig.ShieldRearmSeconds
	publishShield(player)
end

-- Studio /shield 0: also lifts the pad's re-arm lock.
function HeistService.ClearRearm(player: Player)
	state.rearmAt[player.UserId] = nil
	publishShield(player)
end

function HeistService.IsShielded(player: Player): boolean
	return (state.shieldUntil[player.UserId] or 0) > serverNow()
end

-- Under MinRebirths (and not /stealable): nobody can steal from this lab.
function HeistService.IsProtected(player: Player): boolean
	if state.debugStealable[player.UserId] then
		return false
	end
	return PlayerDataService.GetRebirths(player) < HeistConfig.MinRebirths
end

-- The 10-minute loss cap is hit: unstealable until a loss ages out.
function HeistService.IsLossCapped(player: Player): boolean
	pruneLosses(player.UserId)
	local losses = state.recentLosses[player.UserId]
	return losses ~= nil and #losses >= HeistConfig.LossCap
end

-- Studio /stealable: toggles stealable-at-Rebirth-0 for this player's lab.
function HeistService.SetDebugStealable(player: Player, stealable: boolean)
	if stealable then
		state.debugStealable[player.UserId] = true
	else
		state.debugStealable[player.UserId] = nil
	end
end

--[[ Carry: end (fail or deliver) ------------------------------------------ ]]

local function clearThiefAttributes(thief: Player)
	for _, name in CARRY_ATTRIBUTES do
		thief:SetAttribute(name, nil)
	end
end

-- Puts the victim's pedestal back the way the data says it is.
local function restorePedestal(victim: Player, carry: Carry)
	local plot = TycoonService.GetPlotForPlayer(victim)
	local pedestal = plot and getPedestal(plot, carry.PedestalIndex)
	if not pedestal then
		return
	end
	pedestal:SetAttribute("BeingStolen", false)
	local uid = PlayerDataService.GetPedestalDisplays(victim)[carry.PedestalIndex]
	local item = uid and PlayerDataService.GetItemByUid(victim, uid)
	if item then
		PedestalVisuals.Apply(pedestal, item.Tier, item.Mutation)
	else
		PedestalVisuals.Clear(pedestal)
	end
	TycoonService.RefreshPedestalLabels(victim)
end

-- The one block that moves an item between inventories. Synchronous, no
-- yields: re-finds the item, clears the pedestal, removes it from the
-- victim, adds a copy (new Uid) to the thief. Returns false (and touches
-- nothing) if the item isn't where the carry says it is.
local function transferItem(thief: Player, victim: Player, carry: Carry): boolean
	if not PlayerDataService.IsDataLoaded(thief) or not PlayerDataService.IsDataLoaded(victim) then
		return false
	end
	local item = PlayerDataService.GetItemByUid(victim, carry.ItemUid)
	local displays = PlayerDataService.GetPedestalDisplays(victim)
	if not item or displays[carry.PedestalIndex] ~= carry.ItemUid then
		warn(("HeistService: %s's carried item %s is no longer on pedestal %d; returning"):format(
			victim.Name,
			carry.ItemUid,
			carry.PedestalIndex
		))
		return false
	end
	PlayerDataService.SetPedestalDisplay(victim, carry.PedestalIndex, nil)
	PlayerDataService.SetItemInUse(victim, carry.ItemUid, false)
	local removed = PlayerDataService.RemoveItemsByUid(victim, { carry.ItemUid })
	if not removed then
		-- Can't happen (found above, no yield since); put the display back.
		PlayerDataService.SetPedestalDisplay(victim, carry.PedestalIndex, carry.ItemUid)
		PlayerDataService.SetItemInUse(victim, carry.ItemUid, true)
		return false
	end
	PlayerDataService.AddItem(thief, item.ItemId, item.Tier, item.Mutation)
	return true
end

-- Ends `thiefUserId`'s carry with `outcome`. Safe to call for a carry that
-- already ended (no-op), from any of the ending paths.
local function endCarry(thiefUserId: number, outcome: Outcome)
	local carry = state.carries[thiefUserId]
	if not carry then
		return
	end
	-- Drop the carry first: nothing below can re-enter it.
	state.carries[thiefUserId] = nil
	state.carriedItems[carry.ItemUid] = nil
	if carry.DiedConnection then
		carry.DiedConnection:Disconnect()
	end

	local thief = Players:GetPlayerByUserId(carry.ThiefUserId)
	local victim = Players:GetPlayerByUserId(carry.VictimUserId)
	if victim then
		PlayerDataService.SetItemCarried(victim, carry.ItemUid, false)
		-- The chase boost lasts while any of their items is out.
		local humanoid = getHumanoid(victim)
		if humanoid and not PlayerDataService.HasCarriedItems(victim) then
			humanoid.WalkSpeed = HeistConfig.NormalWalkSpeed
		end
	end
	if thief then
		PlayerDataService.SetCarrying(thief, false)
		-- For every client's cosmetic ending (the catch: flash, CAUGHT!, the
		-- orb flying home). Set before the Heist* attributes clear.
		thief:SetAttribute("HeistOutcome", outcome)
		local victimPlot = victim and TycoonService.GetPlotForPlayer(victim)
		local pedestal = victimPlot and getPedestal(victimPlot, carry.PedestalIndex)
		thief:SetAttribute("HeistReturnTo", if pedestal then pedestal.Position else nil)
		clearThiefAttributes(thief)
		local humanoid = getHumanoid(thief)
		if humanoid then
			humanoid.WalkSpeed = HeistConfig.NormalWalkSpeed
		end
	end

	if outcome == "Delivered" then
		-- Both sessions must still be this server's (ProfileStore lock), so
		-- both writes go through their own profiles; otherwise it goes back.
		local bothActive = thief ~= nil
			and victim ~= nil
			and PlayerDataService.IsProfileActive(thief)
			and PlayerDataService.IsProfileActive(victim)
		if thief and victim and bothActive and transferItem(thief, victim, carry) then
			PlayerDataService.IncrementTotalSteals(thief) -- first_steal goal (paid by the sync below)
			local losses = state.recentLosses[victim.UserId] or {}
			table.insert(losses, os.clock())
			state.recentLosses[victim.UserId] = losses
			HeistService.RaiseShield(victim, HeistConfig.VictimShieldSeconds)
			local plot = TycoonService.GetPlotForPlayer(victim)
			local pedestal = plot and getPedestal(plot, carry.PedestalIndex)
			if pedestal then
				pedestal:SetAttribute("BeingStolen", false)
				PedestalVisuals.Clear(pedestal)
			end
			TycoonService.RefreshPedestalLabels(victim)
			syncBoth(thief, victim, true)
			PlayerDataService.SaveNow(thief)
			PlayerDataService.SaveNow(victim)
		else
			outcome = "Failed"
		end
	end
	if outcome ~= "Delivered" then
		if victim then
			restorePedestal(victim, carry)
		end
		syncBoth(thief, victim, false)
	end

	if thief then
		RemoteEvents.HeistEnded:FireClient(thief, {
			Role = "Thief",
			Outcome = outcome,
			Item = carry.Item,
			OtherName = carry.VictimName,
		})
	end
	if victim then
		RemoteEvents.HeistEnded:FireClient(victim, {
			Role = "Victim",
			Outcome = outcome,
			Item = carry.Item,
			OtherName = carry.ThiefName,
		})
	end
	if outcome == "Delivered" and thief then
		AnalyticsKit.Funnel(thief, "FirstSteal")
		AnalyticsKit.Custom(thief, "StealDelivered", nil, carry.Item.Tier)
	elseif (outcome == "Saved" or outcome == "Knocked") and victim then
		AnalyticsKit.Custom(victim, "StealSaved", nil, carry.Item.Tier)
	end
	if isFeedTier(carry.Item.Tier) and (outcome == "Delivered" or outcome == "Saved" or outcome == "Knocked") then
		RemoteEvents.HeistFeed:FireAllClients({
			Kind = if outcome == "Delivered" then "Stole" else "Caught",
			Thief = carry.ThiefName,
			Victim = carry.VictimName,
			Tier = carry.Item.Tier,
			Mutation = carry.Item.Mutation,
			ItemName = carry.Item.Name,
			ItemId = carry.Item.ItemId,
		})
	end
end

-- Fails every carry `player` is part of, as thief or victim. Used on
-- leaving and shutdown (OnRelease) and by /wipe, always before any save.
-- Defined below (onRequestSteal's recording step).
local startCarry: (Player, Player, BasePart, number, string, any, Humanoid) -> ()

-- A weapon hit the carrying thief (CombatService): the orb goes straight
-- back through the normal "it goes back" path. True if they were carrying.
function HeistService.KnockCarrier(thief: Player): boolean
	if not state.carries[thief.UserId] then
		return false
	end
	endCarry(thief.UserId, "Knocked")
	return true
end

-- /selftest: `thief` grabs `victim`'s first displayed item with none of
-- the steal checks (shields, protection, range), so a two-player test can
-- knock the carry. Returns the item's Uid, or nil.
function HeistService.SelfTestCarry(thief: Player, victim: Player): string?
	local plot = getClaimedPlot(victim)
	local humanoid = getHumanoid(thief)
	if not plot or not humanoid or state.carries[thief.UserId] then
		return nil
	end
	for index, uid in PlayerDataService.GetPedestalDisplays(victim) do
		local pedestal = getPedestal(plot, index)
		local itemUid = uid :: string
		local item = PlayerDataService.GetItemByUid(victim, itemUid)
		if pedestal and item and not state.carriedItems[itemUid] then
			startCarry(thief, victim, pedestal, index, itemUid, item, humanoid)
			return itemUid
		end
	end
	return nil
end

function HeistService.FailCarriesFor(player: Player, outcome: Outcome)
	endCarry(player.UserId, outcome)
	for thiefUserId, carry in table.clone(state.carries) do
		if carry.VictimUserId == player.UserId then
			endCarry(thiefUserId, outcome)
		end
	end
end

-- `player` is carrying a stolen item right now.
function HeistService.IsCarrying(player: Player): boolean
	return state.carries[player.UserId] ~= nil
end

--[[ Grab ------------------------------------------------------------------ ]]

local function reject(thief: Player, reason: string, extra: { [string]: any }?)
	if SUSPICIOUS_REASONS[reason] then
		warn(("HeistService: rejected steal from %s (%s)"):format(thief.Name, reason))
	end
	local payload: { [string]: any } = { Role = "Thief", Outcome = "Rejected", Reason = reason }
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	RemoteEvents.HeistEnded:FireClient(thief, payload)
end

-- Records a carry and tells both sides (onRequestSteal, after every check;
-- /selftest's SelfTestCarry). Neither inventory changes until delivery.
startCarry = function(
	thief: Player,
	victim: Player,
	pedestal: BasePart,
	pedestalIndex: number,
	uid: string,
	item: any,
	humanoid: Humanoid
)
	local def = ItemConfig.GetItemById(item.ItemId)
	local info: ItemInfo = {
		ItemId = item.ItemId,
		Tier = item.Tier,
		Mutation = item.Mutation,
		Name = MutationConfig.GetDisplayName(def and def.Name or item.ItemId, item.Mutation),
	}
	local carry: Carry = {
		ThiefUserId = thief.UserId,
		VictimUserId = victim.UserId,
		PedestalIndex = pedestalIndex,
		ItemUid = uid,
		StartedAt = os.clock(),
		EndsAt = serverNow() + HeistConfig.CarrySeconds,
		Item = info,
		ThiefName = thief.DisplayName,
		VictimName = victim.DisplayName,
		DiedConnection = nil,
	}
	state.carries[thief.UserId] = carry
	state.carriedItems[uid] = thief.UserId
	PlayerDataService.SetItemCarried(victim, uid, true)
	PlayerDataService.SetCarrying(thief, true)

	carry.DiedConnection = humanoid.Died:Connect(function()
		endCarry(thief.UserId, "Died")
	end)
	humanoid.WalkSpeed = HeistConfig.CarryWalkSpeed
	local victimHumanoid = getHumanoid(victim)
	if victimHumanoid then
		victimHumanoid.WalkSpeed = HeistConfig.OwnerChaseWalkSpeed
	end

	thief:SetAttribute("HeistTier", info.Tier)
	thief:SetAttribute("HeistMutation", info.Mutation)
	thief:SetAttribute("HeistItemName", info.Name)
	thief:SetAttribute("HeistEndsAt", carry.EndsAt)
	thief:SetAttribute("HeistVictimUserId", victim.UserId)

	pedestal:SetAttribute("BeingStolen", true)
	PedestalVisuals.SetStolen(pedestal)
	TycoonService.RefreshPedestalLabels(victim)
	syncBoth(thief, victim, false) -- the victim's income drops the pedestal
	AnalyticsKit.Custom(thief, "StealStarted", nil, carry.Item.Tier)

	RemoteEvents.HeistStarted:FireClient(thief, {
		Role = "Thief",
		Item = info,
		OtherName = victim.DisplayName,
		OtherUserId = victim.UserId,
		EndsAt = carry.EndsAt,
		GraceEndsAt = carry.EndsAt - HeistConfig.CarrySeconds + HeistConfig.TagGraceSeconds,
	})
	RemoteEvents.HeistStarted:FireClient(victim, {
		Role = "Victim",
		Item = info,
		OtherName = thief.DisplayName,
		OtherUserId = thief.UserId,
		EndsAt = carry.EndsAt,
		GraceEndsAt = carry.EndsAt - HeistConfig.CarrySeconds + HeistConfig.TagGraceSeconds,
	})
	if isFeedTier(info.Tier) then
		RemoteEvents.HeistFeed:FireAllClients({
			Kind = "Grab",
			Thief = thief.DisplayName,
			Victim = victim.DisplayName,
			Tier = info.Tier,
			Mutation = info.Mutation,
			ItemName = info.Name,
			ItemId = info.ItemId,
		})
	end
end

local STEAL_REQUESTS_PER_SECOND = 1
local STEAL_REQUEST_BURST = 2

local function onRequestSteal(thief: Player, rawPayload: unknown)
	-- Shape first: the client sends only which pedestal; the server resolves
	-- the victim, the item and everything else from its own state.
	if typeof(rawPayload) ~= "table" then
		reject(thief, "InvalidArguments")
		return
	end
	-- A request rate limit (~1 a second), not a gameplay cooldown: the prompt
	-- is a 1.5 s hold, so honest grabs never hit it; spam is dropped.
	if not RemoteGuard.Allow(thief, "RequestSteal", STEAL_REQUESTS_PER_SECOND, STEAL_REQUEST_BURST) then
		return
	end
	local payload = rawPayload :: { [string]: unknown }
	-- Whole, finite numbers only: NaN / ±inf / 1.5 would slip past a range
	-- check, and GetPlayerByUserId errors on a value it can't cast.
	local ownerUserId = RemoteGuard.Int(payload.OwnerUserId, 1, 2 ^ 53)
	local pedestalIndex = RemoteGuard.Int(payload.PedestalIndex, 1, PlotLayout.PEDESTAL_COUNT)
	if not ownerUserId or not pedestalIndex then
		reject(thief, "InvalidArguments")
		return
	end
	local victim = Players:GetPlayerByUserId(ownerUserId)
	if not victim then
		reject(thief, "NoVictim")
		return
	end
	if victim == thief then
		reject(thief, "OwnLab")
		return
	end

	-- 1. Data loaded for both.
	if not PlayerDataService.IsDataLoaded(thief) or not PlayerDataService.IsDataLoaded(victim) then
		reject(thief, "DataNotLoaded")
		return
	end
	if isRagdolled(thief) then
		reject(thief, "Ragdolled")
		return
	end
	-- 2. Not already carrying (there is no thief cooldown: the victim's
	-- shield after a loss and LossCap stop a lab being farmed).
	if state.carries[thief.UserId] then
		reject(thief, "AlreadyCarrying")
		return
	end
	-- 3. Both at MinRebirths (or the victim /stealable in Studio).
	if PlayerDataService.GetRebirths(thief) < HeistConfig.MinRebirths then
		reject(thief, "NeedsRebirth")
		return
	end
	if HeistService.IsProtected(victim) then
		reject(thief, "Protected")
		return
	end
	-- 4. Shield down, loss cap not hit.
	if HeistService.IsShielded(victim) then
		reject(thief, "Shielded")
		return
	end
	if HeistService.IsLossCapped(victim) then
		reject(thief, "LabCapped")
		return
	end
	-- 5. Pedestal filled with an item the victim owns, InUse.
	local plot = getClaimedPlot(victim)
	local pedestal = plot and getPedestal(plot, pedestalIndex)
	if not pedestal then
		reject(thief, "Empty")
		return
	end
	local uid = PlayerDataService.GetPedestalDisplays(victim)[pedestalIndex]
	local item = uid and PlayerDataService.GetItemByUid(victim, uid)
	if not uid or not item or not item.InUse then
		reject(thief, "Empty")
		return
	end
	-- 6. Close enough (prompt distance plus slack), and alive.
	local root = getRoot(thief)
	local humanoid = getHumanoid(thief)
	if not root or not humanoid or humanoid.Health <= 0 then
		reject(thief, "NoCharacter")
		return
	end
	if (root.Position - pedestal.Position).Magnitude > HeistConfig.PromptDistance + HeistConfig.GrabRangeSlack then
		reject(thief, "TooFar")
		return
	end
	-- The owner standing guard at it blocks the grab (readable defence).
	if isGuarded(victim, pedestal) then
		reject(thief, "Guarded")
		return
	end
	-- 7. Not already being carried.
	if state.carriedItems[uid] then
		reject(thief, "AlreadyStolen")
		return
	end

	startCarry(thief, victim, pedestal, pedestalIndex, uid, item, humanoid)
end

--[[ Carry loop -------------------------------------------------------------- ]]

local function stepCarries()
	local now = serverNow()
	for thiefUserId, carry in table.clone(state.carries) do
		local thief = Players:GetPlayerByUserId(thiefUserId)
		local victim = Players:GetPlayerByUserId(carry.VictimUserId)
		local victimPlot = victim and getClaimedPlot(victim)
		if not thief or not victim or not victimPlot then
			endCarry(thiefUserId, "Left")
			continue
		end
		local thiefRoot = getRoot(thief)
		if thiefRoot then
			-- No tag in the grace window: the thief gets to see the grab land.
			local graceOver = os.clock() - carry.StartedAt >= HeistConfig.TagGraceSeconds
			local victimRoot = getRoot(victim)
			if graceOver and victimRoot and (victimRoot.Position - thiefRoot.Position).Magnitude <= HeistConfig.TagDistance then
				endCarry(thiefUserId, "Saved")
				continue
			end
			local _, origin = getClaimedPlot(thief)
			if origin and isInsidePlot(origin, thiefRoot.Position) then
				endCarry(thiefUserId, "Delivered")
				continue
			end
		end
		if now >= carry.EndsAt then
			endCarry(thiefUserId, "Timeout")
		end
	end
end

--[[ Shield loop: claim shield, protection, guard flags, eject ------------- ]]

--[[ LOCK: the one way an owner raises their shield on purpose ----------- ]]

export type LockReason = "Protected" | "Carrying" | "Ragdolled" | "AlreadyLocked" | "Recharging" | "TooFar"

-- Is `player`'s root within reach of their own LOCK console (prompt
-- distance + LockReachSlack, flat)? A client can fire a prompt from
-- anywhere with an exploit, so the server measures it.
local function isAtConsole(player: Player): boolean
	local _, origin = getClaimedPlot(player)
	local root = getRoot(player)
	if not origin or not root then
		return false
	end
	local console = origin:PointToWorldSpace(PlotLayout.LOCK_CONSOLE)
	local offset = root.Position - console
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return flat <= PlotLayout.LockConsole.PromptDistance + HeistConfig.LockReachSlack
end

-- Raises `player`'s shield for ShieldSeconds if every rule allows it, in
-- this order: Protected (Rebirth 0), Carrying, AlreadyLocked, Recharging
-- (the re-arm lock; also returns the seconds left), TooFar (not at their
-- own LOCK console). The console's prompt is the only way in.
function HeistService.TryLock(player: Player): (boolean, LockReason?, number?)
	if HeistService.IsProtected(player) then
		return false, "Protected"
	end
	if state.carries[player.UserId] then
		return false, "Carrying"
	end
	if isRagdolled(player) then
		return false, "Ragdolled"
	end
	if HeistService.IsShielded(player) then
		return false, "AlreadyLocked"
	end
	local rearmLeft = (state.rearmAt[player.UserId] or 0) - serverNow()
	if rearmLeft > 0 then
		return false, "Recharging", math.ceil(rearmLeft)
	end
	if not isAtConsole(player) then
		return false, "TooFar"
	end
	HeistService.RaiseShield(player, HeistConfig.ShieldSeconds)
	PlayerDataService.IncrementShieldRaises(player)
	PlayerDataService.SyncTycoon(player) -- pays the first_shield goal
	return true, nil
end

-- The console prompt: rejections come back on the heist toast path
-- (HeistEnded Rejected, Role "Lock").
local function requestLock(player: Player)
	local now = os.clock()
	local last = state.lastLockRequest[player.UserId]
	if last and now - last < HeistConfig.LockRequestDebounceSeconds then
		return
	end
	state.lastLockRequest[player.UserId] = now
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	local ok, reason, seconds = HeistService.TryLock(player)
	if not ok then
		RemoteEvents.HeistEnded:FireClient(player, {
			Role = "Lock",
			Outcome = "Rejected",
			Reason = reason,
			Seconds = seconds,
		})
	end
end

-- The console's prompt is owner-only on clients; the server still checks
-- the prompt is on the player's own plot.
local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	if prompt.Name ~= LockKit.PROMPT_NAME then
		return
	end
	local plot = TycoonService.GetPlotForPlayer(player)
	if plot and prompt:IsDescendantOf(plot) then
		requestLock(player)
	end
end

local function ejectIntruders(owner: Player, plot: Model, origin: CFrame)
	local target: CFrame? = nil
	for _, other in Players:GetPlayers() do
		if other ~= owner then
			local root = getRoot(other)
			if root and isInsidePlot(origin, root.Position) then
				target = target or getEjectCFrame(plot)
				local character = other.Character
				if target and character then
					character:PivotTo(target)
				end
			end
		end
	end
end

local function shieldTick()
	for _, player in Players:GetPlayers() do
		if PlayerDataService.IsDataLoaded(player) then
			local plot, origin = getClaimedPlot(player)
			if plot and origin then
				if not state.claimSeen[player.UserId] then
					state.claimSeen[player.UserId] = true
					HeistService.RaiseShield(player, HeistConfig.ClaimShieldSeconds)
				end
				local protected = HeistService.IsProtected(player)
				if plot:GetAttribute("Protected") ~= protected then
					plot:SetAttribute("Protected", protected)
				end
				-- GuardedByOwner: clients show the steal prompt as "Owner is guarding".
				local pedestals = plot:FindFirstChild("Pedestals")
				if pedestals then
					for _, pedestal in pedestals:GetChildren() do
						if pedestal:IsA("BasePart") then
							local guarded = isGuarded(player, pedestal)
							if pedestal:GetAttribute("GuardedByOwner") ~= guarded then
								pedestal:SetAttribute("GuardedByOwner", guarded)
							end
						end
					end
				end
				-- A protected lab needs no eject: nothing there can be stolen.
				if not protected and HeistService.IsShielded(player) then
					ejectIntruders(player, plot, origin)
				end
			end
		end
	end
end

local function onPlayerRemoving(player: Player)
	-- Carries were already failed by the OnRelease hook (before the save).
	local userId = player.UserId
	state.shieldUntil[userId] = nil
	state.recentLosses[userId] = nil
	state.claimSeen[userId] = nil
	state.rearmAt[userId] = nil
	state.lastLockRequest[userId] = nil
	state.debugStealable[userId] = nil
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function HeistService:Init()
	table.insert(state.connections, RemoteEvents.RequestSteal.OnServerEvent:Connect(onRequestSteal))
	table.insert(state.connections, ProximityPromptService.PromptTriggered:Connect(onPromptTriggered))
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	table.insert(
		state.connections,
		RunService.Heartbeat:Connect(function(dt: number)
			-- No carries before :Start() (RequestSteal needs it), so this
			-- never touches an unresolved service.
			if next(state.carries) == nil then
				return
			end
			state.carryAccumulator += dt
			if state.carryAccumulator >= HeistConfig.CarryTickSeconds then
				state.carryAccumulator = 0
				stepCarries()
			end
		end)
	)
end

function HeistService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)

	-- A victim who respawns mid-heist keeps the chase speed: the new
	-- Humanoid starts at the default, and nothing else re-applies it.
	local function watchRespawn(player: Player)
		table.insert(state.connections, player.CharacterAdded:Connect(function(character: Model)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid and humanoid:IsA("Humanoid") and PlayerDataService.HasCarriedItems(player) then
				humanoid.WalkSpeed = HeistConfig.OwnerChaseWalkSpeed
			end
		end))
	end
	table.insert(state.connections, Players.PlayerAdded:Connect(watchRespawn))
	for _, player in Players:GetPlayers() do
		watchRespawn(player)
	end

	-- Leaving or shutdown: fail this player's carries (either side) before
	-- PlayerDataService saves anything.
	PlayerDataService.OnRelease(function(player: Player)
		HeistService.FailCarriesFor(player, "Left")
	end)

	state.running = true
	task.spawn(function()
		while state.running do
			task.wait(HeistConfig.EjectTickSeconds)
			shieldTick()
		end
	end)
end

function HeistService:Stop()
	state.running = false
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
end

return HeistService
