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
local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local OfflineConfig = require(ReplicatedStorage.Shared.Config.OfflineConfig)
local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local DealConfig = require(ReplicatedStorage.Shared.Config.DealConfig)
local DealState = require(ReplicatedStorage.Shared.Modules.DealState)
local DailyConfig = require(ReplicatedStorage.Shared.Config.DailyConfig)
local GiftConfig = require(ReplicatedStorage.Shared.Config.GiftConfig)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)
local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)
local LogService = game:GetService("LogService")
local Workspace = game:GetService("Workspace")


--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type HeistServiceModule = typeof(require(script.Parent.HeistService))
type EventServiceModule = typeof(require(script.Parent.EventService))
type MonetizationServiceModule = typeof(require(script.Parent.MonetizationService))
type ItemServiceModule = typeof(require(script.Parent.ItemService))
type TutorialServiceModule = typeof(require(script.Parent.TutorialService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))
type FusionServiceModule = typeof(require(script.Parent.FusionService))
type CombatServiceModule = typeof(require(script.Parent.CombatService))
type QuestServiceModule = typeof(require(script.Parent.QuestService))

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
local ItemService: ItemServiceModule
local TutorialService: TutorialServiceModule
local TycoonService: TycoonServiceModule
local FusionService: FusionServiceModule
local CombatService: CombatServiceModule
local QuestService: QuestServiceModule

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
-- "/stealable" toggles your lab stealable even at Rebirth 0 (heist testing).
local STEALABLE_COMMAND = "/stealable"
-- "/tutorial reset" starts it over (free pulls and fusion again);
-- "/tutorial step <n>" jumps to step n.
local TUTORIAL_COMMAND = "/tutorial"
-- "/weapons all" grants every weapon (quest ones too); "/weapons reset"
-- takes them all (rebirth ones come back on the next sync).
local WEAPONS_COMMAND = "/weapons"
-- "/quest complete <id>" latches a daily ("pull20", ...) or "chain" done;
-- "/quest reset" hands today's dailies out again and restarts the chain.
local QUEST_COMMAND = "/quest"
-- "/powerup <key> <n>" sets a power-up's count (QuestConfig key, any case).
local POWERUP_COMMAND = "/powerup"
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
-- "/deal slot 6" shifts the deal clock 6 h (walk the rotation; clients read
-- the same offset); "/deal pop" forces your "New deal!" card once.
local DEAL_COMMAND = "/deal"
-- "/daily day 4" makes your next claim Day 4 (claimable now); "/daily miss
-- 2" pretends your last claim was 2 missed days before yesterday (miss 1 =
-- the free skip, miss 2+ = back to Day 1);
-- "/daily reset" starts a fresh streak.
local DAILY_COMMAND = "/daily"
-- "/gifts time 24" sets today's play time to 24 min (the playtime gifts);
-- "/gifts reset" also re-locks every gift.
local GIFTS_COMMAND = "/gifts"

--[[ /selftest ------------------------------------------------------------------
	Runs the Bug Hunt invariants against the real services and prints one
	PASS / FAIL line each (server Output; the client half's lines arrive in
	its report). Studio only (this whole service is), and it refuses to run
	unless saves go to the mock store or FT_StudioTest_1: it never touches a
	live save. Run it outside events (a Power Surge strike can legitimately
	change an item mid-fuzz).
]]
local SELFTEST_COMMAND = "/selftest"
local SELFTEST_REPORT_TIMEOUT = 90
local SELFTEST_SLOT_COUNT = 200
local selfTestReports: { [number]: { any } } = {}

local NUMBER_FORMAT_CASES: { { any } } = {
	{ 0, "$0" },
	{ 999, "$999" },
	{ 1000, "$1K" },
	{ 1234567, "$1.23M" },
	{ 1e33, "$1Dc" },
	{ 1e36, "$1.00e36" },
	{ 1e300, "$1.00e300" },
	{ math.huge, "$∞" },
	{ -math.huge, "$-∞" },
	{ 0 / 0, "$0" },
	{ -1234, "$-1.23K" },
}

local function waitForReport(player: Player, stage: string): any?
	local started = os.clock()
	while os.clock() - started < SELFTEST_REPORT_TIMEOUT and player.Parent do
		local queue = selfTestReports[player.UserId]
		if queue then
			for index, report in queue do
				if report.Stage == stage then
					table.remove(queue, index)
					return report
				end
			end
		end
		task.wait(0.2)
	end
	return nil
end

local function runCombatSelfTest(player: Player, result: (boolean, string, string?) -> ())
	local data = PlayerDataService.GetData(player)
	if data then
		local rebirths = data.Rebirths
		data.Rebirths = 0
		local why = CombatService.WhyNotHittable(player)
		data.Rebirths = rebirths
		result(why == "NeedsRebirth", "combat: a Rebirth-0 player can't be hit", tostring(why))
	end

	local bat = CombatConfig.GetWeapon("Bat") :: CombatConfig.Weapon
	CombatService.ResetCooldowns(player)
	local first = CombatService.TakeCooldown(player, bat)
	local second = CombatService.TakeCooldown(player, bat)
	CombatService.ResetCooldowns(player)
	result(first and not second, "combat: the cooldown is enforced on the server", ("first %s, second %s"):format(tostring(first), tostring(second)))

	local other: Player? = nil
	for _, candidate in Players:GetPlayers() do
		if candidate ~= player and PlayerDataService.IsDataLoaded(candidate) then
			other = candidate
		end
	end
	if not other then
		result(true, "combat: knocking a thief returns the orb (skipped: needs a second player)")
		return
	end
	local victim = other :: Player
	local function count(p: Player): number
		local items: { any } = PlayerDataService.GetInventory(p) or {}
		return #items
	end
	local thiefBefore, victimBefore = count(player), count(victim)
	local uid = HeistService.SelfTestCarry(player, victim)
	if not uid then
		result(true, "combat: knocking a thief returns the orb (skipped: the second player has nothing on display)")
		return
	end
	local from = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	CombatService.ApplyHit(victim, player, bat, if from and from:IsA("BasePart") then from.Position + Vector3.new(0, 0, 3) else Vector3.zero)
	local stillCarrying = HeistService.IsCarrying(player)
	local back = PlayerDataService.GetItemByUid(victim, uid) ~= nil
	local unchanged = count(player) == thiefBefore and count(victim) == victimBefore
	result(
		not stillCarrying and back and unchanged,
		"combat: knocking a thief returns the orb, inventories unchanged",
		("carrying %s, back %s, counts %d/%d -> %d/%d"):format(tostring(stillCarrying), tostring(back), thiefBefore, victimBefore, count(player), count(victim))
	)
end

local function runTutorialSelfTest(player: Player, result: (boolean, string, string?) -> ())
	local saved = PlayerDataService.SelfTestSwapTutorial(player, nil)
	local popups = 0
	local watch = RemoteEvents.ShopAnalytics.OnServerEvent:Connect(function(sender: Player, payload: unknown)
		local event = typeof(payload) == "table" and (payload :: any).Event
		if sender == player and (event == "OfferShown" or event == "DealShown") then
			popups += 1
		end
	end)
	TutorialService.DebugReset(player)
	PlayerDataService.SyncTycoon(player)
	local function tutorial(): any
		local data = PlayerDataService.GetData(player)
		return data and data.Tutorial
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local home = if root and root:IsA("BasePart") then root.CFrame else nil
	local order: { string } = {}
	local stuck: string? = nil
	for _ = 1, #TutorialConfig.Steps + 2 do
		local t = tutorial()
		if not t or t.Done then
			break
		end
		local index = t.Step
		local step = TutorialConfig.GetStep(index)
		if not step then
			break
		end
		table.insert(order, step.Id)
		if step.Id == "upgrade" then
			PlayerDataService.AddCash(player, 1e6)
			TycoonService.HandleUpgradeRequest(player, "basic_generator")
		elseif step.Id == "pull" then
			for _ = 1, TutorialConfig.FreePulls do
				TycoonService.TutorialPull(player)
			end
		elseif step.Id == "fuse" then
			local commons = {}
			local owned: { any } = PlayerDataService.GetInventory(player) or {}
			for _, item in owned do
				if item.Tier == TutorialConfig.FreePullTier and #commons < 2 and not PlayerDataService.IsItemCarried(player, item.Uid) then
					table.insert(commons, item.Uid)
				end
			end
			FusionService.HandleFusionRequest(player, { Uids = commons })
		elseif step.Id == "multiplier" then
			-- The "come back when you have $X" branch: OK completes it.
			PlayerDataService.SpendCash(player, PlayerDataService.GetCash(player))
			TutorialService.Advance(player, index)
		elseif step.Kind == "Arrive" then
			local plot = TycoonService.GetPlotForPlayer(player)
			local slot = plot and plot:GetAttribute("SlotIndex")
			if root and root:IsA("BasePart") and typeof(slot) == "number" then
				root.CFrame = CFrame.new(PlotLayout.GetSlotCFrame(slot):PointToWorldSpace(PlotLayout.LOCK_CONSOLE) + Vector3.new(0, 4, 3))
			end
			TutorialService.Advance(player, index)
		elseif step.Kind == "Action" then
			-- claim: only reached on an unclaimed plot (claimed skips it).
			stuck = step.Id .. " (needs a claimed lab)"
			break
		else
			TutorialService.Advance(player, index)
		end
		PlayerDataService.SyncTycoon(player)
		local after = tutorial()
		if after and not after.Done and after.Step == index then
			stuck = step.Id
			break
		end
	end
	if home and root and root:IsA("BasePart") then
		root.CFrame = home
	end
	local t = tutorial()
	result(t ~= nil and t.Done == true and stuck == nil, "tutorial: every step completes in order", ("%s; stuck at %s"):format(table.concat(order, " > "), tostring(stuck)))
	task.wait(1)
	watch:Disconnect()
	result(popups == 0, "tutorial: no shop or deal pop-up while it runs", ("%d shown"):format(popups))

	TutorialService.DebugSetStep(player, 6)
	local resumeOk, resumeDetail = PlayerDataService.SelfTestTutorialRoundTrip(player)
	local resumed = tutorial()
	result(resumeOk and resumed ~= nil and resumed.Step == 6, "tutorial: a save left mid-way resumes at its step", resumeDetail)

	PlayerDataService.SelfTestSwapTutorial(player, saved)
	PlayerDataService.SyncTycoon(player)
end

local function runSelfTest(player: Player)
	local passed, failed = 0, 0
	local function result(ok: boolean, name: string, detail: string?)
		if ok then
			passed += 1
			print(("[SelfTest] PASS %s"):format(name))
		else
			failed += 1
			warn(("[SelfTest] FAIL %s%s"):format(name, if detail then ": " .. detail else ""))
		end
	end
	local storeKind = PlayerDataService.GetStoreKind()
	if storeKind == "Live" then
		warn("[SelfTest] refused: saves go to the LIVE store")
		return
	end
	print(("[SelfTest] running for %s (store: %s)"):format(player.Name, storeKind))
	local eventId = Workspace:GetAttribute("EventId")
	if typeof(eventId) == "string" and eventId ~= "" then
		print(("[SelfTest] note: %s is running; an event can change items during the fuzz"):format(eventId))
	end

	-- 1. Layout assertions (they run at require time).
	for _, name in { "PlotLayout", "StreetLayout" } do
		local ok, err = pcall(require, ReplicatedStorage.Shared.Config:FindFirstChild(name))
		result(ok, name .. " assertions", if ok then nil else tostring(err))
	end

	-- 2. NumberFormat edge cases (never throws, exact text).
	for _, case in NUMBER_FORMAT_CASES do
		local ok, text = pcall(NumberFormat.Money, case[1])
		result(ok and text == case[2], ("NumberFormat.Money(%s)"):format(tostring(case[1])), if ok then ("got %q, want %q"):format(tostring(text), case[2]) else tostring(text))
	end
	local multOk = pcall(NumberFormat.Multiplier, 1e40) and pcall(NumberFormat.Multiplier, math.huge)
	result(multOk, "NumberFormat.Multiplier(1e40 / inf) doesn't throw")

	-- 3. Sound slots: an empty id or an rbxassetid (the client loads them).
	local badIds = {}
	for slot, config in SoundConfig.Slots do
		if config.Id ~= "" and not config.Id:match("^rbxassetid://%d+$") then
			table.insert(badIds, slot)
		end
	end
	result(#badIds == 0, "SoundConfig ids well-formed", table.concat(badIds, ", "))

	-- 4. Event schedule determinism: same slots, same lineup, twice here and
	-- on the client.
	local slots = {}
	local base = (os.time() // EventConfig.SlotSeconds) * EventConfig.SlotSeconds
	for i = 0, SELFTEST_SLOT_COUNT - 1 do
		table.insert(slots, base + i * EventConfig.SlotSeconds)
	end
	local function lineup(): string
		local ids = {}
		for _, slot in slots do
			table.insert(ids, EventConfig.GetEventForSlot(slot).Id)
		end
		return table.concat(ids, ",")
	end
	local serverLineup = lineup()
	result(serverLineup == lineup(), "event schedule repeatable (server)")

	-- 4b. Deal rotation: repeatable, never the same deal two slots running,
	-- and (below) the client agrees; a deal outside its slot is refused.
	local dealSlots = {}
	local dealBase = DealConfig.GetSlotStart(os.time())
	for i = 0, SELFTEST_SLOT_COUNT - 1 do
		table.insert(dealSlots, dealBase + i * DealConfig.SlotSeconds)
	end
	local function dealLineup(): string
		local keys = {}
		for _, slot in dealSlots do
			table.insert(keys, DealConfig.GetDealForSlot(slot))
		end
		return table.concat(keys, ",")
	end
	local serverDeals = dealLineup()
	result(serverDeals == dealLineup(), "deal schedule repeatable (server)")
	local repeats = 0
	for i = 2, #dealSlots do
		if DealConfig.GetDealForSlot(dealSlots[i]) == DealConfig.GetDealForSlot(dealSlots[i - 1]) then
			repeats += 1
		end
	end
	result(repeats == 0, "deal schedule: no deal two slots running", ("%d repeats"):format(repeats))
	local currentDeal = DealState.GetCurrent()
	for _, key in DealConfig.Deals do
		if key ~= currentDeal then
			local reason = MonetizationService.GetRefusal(player, key)
			result(reason == "DealOver" or reason == "Restricted", ("deal %s refused outside its slot"):format(key), tostring(reason))
		end
	end

	-- 5. Data round trip (in memory only).
	local roundOk, roundDetail = PlayerDataService.SelfTestRoundTrip(player)
	result(roundOk, "data round trip (toDisk -> reconcile -> toDisk)", roundDetail)

	-- 6. Remote fuzz (client fires junk): no server error, no state change.
	local other = 1
	for _, p in Players:GetPlayers() do
		if p ~= player then
			other = p.UserId
		end
	end
	selfTestReports[player.UserId] = {}
	RemoteGuard.Reset(player)
	local before = PlayerDataService.SelfTestFingerprint(player)
	local cashBefore = PlayerDataService.GetCash(player)
	local serverErrors = {}
	local logConnection = LogService.MessageOut:Connect(function(message: string, kind: Enum.MessageType)
		if kind == Enum.MessageType.MessageError then
			table.insert(serverErrors, message)
		end
	end)
	RemoteEvents.SelfTest:FireClient(player, { OtherUserId = other, Slots = slots, DealSlots = dealSlots })
	local fuzzReport = waitForReport(player, "Fuzz")
	logConnection:Disconnect()
	if not fuzzReport then
		result(false, "remote fuzz", "no report from the client")
	else
		result(#serverErrors == 0, ("remote fuzz: no server errors (%d junk calls)"):format(fuzzReport.Fired or 0), table.concat(serverErrors, " | "))
		result(PlayerDataService.SelfTestFingerprint(player) == before, "remote fuzz: no state change")
		result(PlayerDataService.GetCash(player) >= cashBefore, "remote fuzz: no cash spent")
	end
	RemoteGuard.Reset(player)
	-- The client checked every hovering thing before the fuzz; rebuild the
	-- pedestal orbs now, and it checks again at the end.
	ItemService.RebuildDisplayVisuals(player)

	-- 7. The client's half: schedule, panels, sounds, client errors.
	local done = waitForReport(player, "Done")
	if not done then
		result(false, "client half", "no report from the client")
	else
		result(done.ScheduleHash == serverLineup, "event schedule: client matches server")
		result(done.DealHash == serverDeals, "deal schedule: client matches server")
		for _, line in (if typeof(done.Panels) == "table" then done.Panels else {}) do
			if typeof(line) == "string" then
				result(line:sub(1, 4) == "PASS", line:sub(6))
			end
		end
		local sounds = if typeof(done.FailedSounds) == "table" then done.FailedSounds else {}
		result(#sounds == 0, "every SoundConfig slot loads", table.concat(sounds, ", "))
		local clientErrors = if typeof(done.ClientErrors) == "table" then done.ClientErrors else {}
		result(#clientErrors == 0, "no client errors during the test", table.concat(clientErrors, " | "))
	end
	selfTestReports[player.UserId] = nil

	-- 8. Auto-display: 6 random items -> the pedestals hold the best by $/s,
	-- in order, in the same sync; then a new best item (what a fusion adds)
	-- lands on pedestal 1 in the same sync. The test items are removed after.
	local added: { string } = {}
	local tiers = { "Common", "Rare", "Epic", "Legendary", "Mythic" }
	local mutations = { nil, "Golden", "Diamond" }
	for _ = 1, 6 do
		local tier = tiers[math.random(1, #tiers)]
		local def = ItemConfig.PickRandomOfTier(tier)
		if def then
			local item = PlayerDataService.AddItem(player, def.Id, tier, mutations[math.random(1, 3)])
			if item then
				table.insert(added, item.Uid)
			end
		end
	end
	PlayerDataService.SyncTycoon(player)
	local function rate(uid: string?): number
		local item = uid and PlayerDataService.GetItemByUid(player, uid)
		return if item then TycoonConfig.GetStackCashPerSecond(item) else -1
	end
	local displays = PlayerDataService.GetPedestalDisplays(player)
	local order = PlayerDataService.GetPedestalOrder(player)
	local count = #order
	local best = -1
	local inventory: { any } = PlayerDataService.GetInventory(player) or {}
	for _, item in inventory do
		if not PlayerDataService.IsItemCarried(player, item.Uid) then
			best = math.max(best, TycoonConfig.GetStackCashPerSecond(item))
		end
	end
	local ordered = rate(displays[1]) == best
	for position = 2, count do
		local index, previous = order[position], order[position - 1]
		if displays[index] and rate(displays[index]) > rate(displays[previous]) then
			ordered = false
		end
	end
	result(ordered, ("auto-display: the %d unlocked pedestals hold the best by $/s, in fill order"):format(count))
	local def = ItemConfig.PickRandomOfTier("Secret")
	local top = def and PlayerDataService.AddItem(player, def.Id, "Secret", "Rainbow")
	if top then
		table.insert(added, top.Uid)
		PlayerDataService.SyncTycoon(player)
		result(PlayerDataService.GetPedestalDisplays(player)[1] == top.Uid, "auto-display: a new best item is on pedestal 1 in the same sync")
	end
	PlayerDataService.RemoveItemsByUid(player, added)
	PlayerDataService.SyncTycoon(player)

	-- 9. The tutorial, driven step by step on the real paths (the remote's
	-- own handlers): every step completes in order, no shop / deal pop-up
	-- while it runs, and a save left mid-way resumes at its step. The
	-- tester's own tutorial state is restored after.
	runTutorialSelfTest(player, result)

	-- 10. Combat: a Rebirth-0 player is never hittable; the cooldown is the
	-- server's; a hit on a carrying thief sends the orb home with both
	-- inventories unchanged (needs a second player: Test -> 2 players).
	runCombatSelfTest(player, result)
	print(("[SelfTest] done: %d passed, %d failed"):format(passed, failed))
end

local function onPlayerChatted(player: Player, message: string)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	local lower = message:lower()
	local command, argument = lower:match("^(%S+)%s*(.*)$")
	if command == SELFTEST_COMMAND then
		task.spawn(runSelfTest, player)
		return
	end

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
	elseif command == QUEST_COMMAND then
		local verb, id = argument:match("^(%S+)%s*(%S*)$")
		if verb == "complete" and id and id ~= "" then
			if QuestService.DebugComplete(player, id) then
				print(("DebugService: %s's quest %s is done"):format(player.Name, id))
			else
				warn(("DebugService: /quest complete: %s isn't one of today's quests (%s) or chain"):format(
					id,
					table.concat(QuestService.GetDailyIds(player), ", ")
				))
			end
		elseif verb == "reset" then
			QuestService.DebugReset(player)
			print(("DebugService: %s's quests reset"):format(player.Name))
		else
			warn("DebugService: /quest complete <id> | /quest reset")
		end
		PlayerDataService.SyncTycoon(player)
	elseif command == POWERUP_COMMAND then
		local rawKey, rawCount = argument:match("^(%S+)%s*(%S*)$")
		local key: string? = nil
		for _, candidate in QuestConfig.PowerUpOrder do
			if rawKey and candidate:lower() == rawKey:lower() then
				key = candidate
			end
		end
		local count = tonumber(rawCount)
		if key and count and count == count then
			PlayerDataService.AddPowerUp(player, key, count - PlayerDataService.GetPowerUpCount(player, key))
			PlayerDataService.SyncTycoon(player)
			print(("DebugService: %s has %d %s"):format(player.Name, PlayerDataService.GetPowerUpCount(player, key), key))
		else
			warn(("DebugService: /powerup <%s> <n>"):format(table.concat(QuestConfig.PowerUpOrder, "|")))
		end
	elseif command == WEAPONS_COMMAND then
		if argument == "all" or argument == "reset" then
			CombatService.DebugSetAll(player, argument == "all")
			PlayerDataService.SyncTycoon(player)
			print(("DebugService: %s's weapons -> %s"):format(player.Name, argument))
		else
			warn("DebugService: /weapons all | /weapons reset")
		end
	elseif command == TUTORIAL_COMMAND then
		local verb, rawStep = argument:match("^(%S+)%s*(%S*)$")
		if verb == "reset" then
			TutorialService.DebugReset(player)
		elseif verb == "step" and tonumber(rawStep) then
			TutorialService.DebugSetStep(player, tonumber(rawStep) :: number)
		else
			warn("DebugService: /tutorial reset | /tutorial step <n>")
			return
		end
		PlayerDataService.SyncTycoon(player)
		print(("DebugService: %s's tutorial -> %s"):format(player.Name, argument))
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
	elseif command == DAILY_COMMAND then
		local data = PlayerDataService.GetData(player)
		if not data then
			return
		end
		local verb, rawNumber = argument:match("^(%S+)%s*(%S*)$")
		local number = tonumber(rawNumber)
		local today = RewardConfig.GetUtcDay(os.time())
		local daily = data.Daily
		if verb == "day" and number then
			local day = math.clamp(math.floor(number), 1, DailyConfig.Cycle)
			daily.Day = day - 1
			daily.Streak = day - 1
			daily.LastClaimUtcDay = if day == 1 then -1 else today - 1
		elseif verb == "miss" and number then
			daily.Day = math.max(1, daily.Day)
			daily.Streak = math.max(1, daily.Streak)
			daily.LastClaimUtcDay = today - 1 - math.max(0, math.floor(number))
		elseif verb == "reset" then
			data.Daily = DailyConfig.Default()
		else
			warn("DebugService: /daily day <1-7> | /daily miss <days> | /daily reset")
			return
		end
		PlayerDataService.SyncTycoon(player)
		local status = DailyConfig.GetStatus(data.Daily, today)
		print(("DebugService: %s daily -> next Day %d, can claim %s, uses skip %s, resets %s, skips %d"):format(
			player.Name, status.Day, tostring(status.CanClaim), tostring(status.UsesSkip), tostring(status.Resets), data.Daily.Skips
		))
	elseif command == GIFTS_COMMAND then
		local data = PlayerDataService.GetData(player)
		if not data then
			return
		end
		local verb, rawNumber = argument:match("^(%S+)%s*(%S*)$")
		local minutes = tonumber(rawNumber)
		local today = RewardConfig.GetUtcDay(os.time())
		if verb == "time" and minutes then
			data.Gifts.UtcDay = today
			data.Gifts.PlaySeconds = math.max(0, minutes * 60)
		elseif verb == "reset" then
			data.Gifts = GiftConfig.Default(today)
		else
			warn("DebugService: /gifts time <minutes> | /gifts reset")
			return
		end
		PlayerDataService.SyncTycoon(player)
		print(("DebugService: %s gifts -> %d s played, %d ready"):format(
			player.Name,
			math.floor(data.Gifts.PlaySeconds),
			GiftConfig.CountReady(data.Gifts.PlaySeconds, data.Gifts.Claimed)
		))
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
	elseif command == DEAL_COMMAND then
		local verb, rawValue = argument:match("^(%S+)%s*(%S*)$")
		if verb == "slot" then
			local hours = tonumber(rawValue) or 0
			Workspace:SetAttribute("DealClockOffset", if hours ~= 0 then hours * 3600 else nil)
			local key, _, left = DealState.GetCurrent()
			print(("DebugService: deal clock +%g h: %s, next in %d s"):format(hours, key, math.floor(left)))
		elseif verb == "pop" then
			local nonce = player:GetAttribute("DealPopNonce")
			player:SetAttribute("DealPopNonce", (if typeof(nonce) == "number" then nonce else 0) + 1)
			print("DebugService: forcing the New deal! card")
		else
			warn("DebugService: /deal slot <offsetHours> | /deal pop")
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
	table.insert(state.connections, RemoteEvents.SelfTestReport.OnServerEvent:Connect(function(player: Player, report: unknown)
		local queue = selfTestReports[player.UserId]
		if queue and typeof(report) == "table" then
			table.insert(queue, report)
		end
	end))

	print("DebugService: Studio commands active: /cash <amount>, /resetmultiplier, /rebirthready, /rebirths <n>, /give <itemId> [mutation], /offline <minutes>, /shield <s>, /stealable, /tips reset, /tutorial reset|step <n>, /weapons all|reset, /quest complete <id>|reset, /powerup <key> <n>, /event <id> [min] | off, /eventclock <min>, /eventmut <charged|void|celestial>, /shop grant <key>, /deal slot <h> | pop, /daily day|miss|reset, /gifts time|reset, /selftest, /wipe")
end

function DebugService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	HeistService = require(script.Parent.HeistService)
	EventService = require(script.Parent.EventService)
	MonetizationService = require(script.Parent.MonetizationService)
	ItemService = require(script.Parent.ItemService)
	TutorialService = require(script.Parent.TutorialService)
	TycoonService = require(script.Parent.TycoonService)
	FusionService = require(script.Parent.FusionService)
	CombatService = require(script.Parent.CombatService)
	QuestService = require(script.Parent.QuestService)
end

return DebugService
