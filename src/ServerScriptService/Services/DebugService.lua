--!nonstrict
-- STUDIO-ONLY debug commands for testing balance changes that a saved
-- player profile would otherwise hide (e.g. a carried-over Multiplier Pad
-- level blocking you from ever seeing Level 1's real cost again). Gated by
-- RunService:IsStudio() so this is structurally inert in a published game -
-- not a toggle to remember to flip off, it simply never runs there. Not a
-- player-facing feature; delete this file if it's no longer needed.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local WeaponKit = require(ReplicatedStorage.Shared.Modules.WeaponKit)
local WeaponAnims = require(ReplicatedStorage.Shared.Anim.WeaponAnims)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local DebugConfig = require(ReplicatedStorage.Shared.Config.DebugConfig)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
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

-- The Studio test start (DebugConfig.StudioStartRebirths / StudioGrantAllWeapons):
-- only in Studio AND only on the Mock store. The Live store, a live server
-- and the FT_StudioSaves test store never get it.
function DebugService.ShouldApplyStudioStart(isStudio: boolean, storeKind: string): boolean
	return isStudio and storeKind == "Mock"
end

-- Once per join: rebirths raised (never lowered) and every weapon, the way
-- /rebirths <n> and /weapons all do it. Returns whether it ran.
function DebugService.ApplyStudioStart(player: Player): boolean
	if not DebugService.ShouldApplyStudioStart(RunService:IsStudio(), PlayerDataService.GetStoreKind()) then
		return false
	end
	if not PlayerDataService.IsDataLoaded(player) then
		return false
	end
	local rebirths = DebugConfig.StudioStartRebirths
	if rebirths > PlayerDataService.GetRebirths(player) then
		PlayerDataService.SetRebirths(player, rebirths)
	end
	if DebugConfig.StudioGrantAllWeapons then
		CombatService.DebugSetAll(player, true)
	end
	PlayerDataService.SyncTycoon(player)
	return true
end

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
local ANIM_COMMAND = "/anim"
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
local SELFTEST_REPORT_TIMEOUT = 90 -- the client's big stages (Fuzz, Done)
local SELFTEST_PROBE_TIMEOUT = 10 -- one tutorial / combat probe
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

local function waitForReport(player: Player, stage: string, timeout: number?): any?
	local started = os.clock()
	local limit = timeout or SELFTEST_REPORT_TIMEOUT
	while os.clock() - started < limit and player.Parent do
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

-- Asks the client what it shows right now (SelfTestController's probe) and
-- turns each line it reports into a result.
local function tutorialProbe(player: Player, payload: { [string]: any }, result: (boolean, string, string?) -> ())
	payload.Stage = "TutorialProbe"
	RemoteEvents.SelfTest:FireClient(player, payload)
	local report = waitForReport(player, "TutorialProbe", SELFTEST_PROBE_TIMEOUT)
	if not report or typeof(report.Lines) ~= "table" then
		local which = if payload.Kind == "Weapon" or payload.Kind == "Switch" then "combat " .. tostring(payload.Weapon or payload.To or "")
			elseif payload.Kind == "WeaponReleased" then "combat release"
			else "tutorial " .. tostring(payload.StepId or payload.Kind)
		result(false, which, "no report from the client")
		return
	end
	for _, line in report.Lines do
		result(line.Ok == true, tostring(line.Name), line.Detail)
	end
end

local runLaunchSelfTest: (Player, (boolean, string, string?) -> ()) -> ()

-- Prints once per run: the physics / authority settings and who owns the
-- target's root (Studio shows the 2026 names that exist on this build).
local function printPhysicsSettings(targetRoot: BasePart)
	local found: { string } = {}
	for _, name in { "UseFixedSimulation", "PhysicsSteppingMethod", "ModelStreamingBehavior", "StreamingEnabled", "SignalBehavior", "AuthorityMode", "ServerAuthority", "InterpolationThrottling", "PhysicsAuthority" } do
		local ok, value = pcall(function()
			return (Workspace :: any)[name]
		end)
		if ok then
			table.insert(found, ("%s=%s"):format(name, tostring(value)))
		end
	end
	local ok, owner = pcall(targetRoot.GetNetworkOwner, targetRoot)
	print(("[SelfTest] physics: Workspace {%s}; target root network owner: %s"):format(table.concat(found, ", "), if ok then tostring(owner) else "error " .. tostring(owner)))
end

-- Asks `target`'s OWN client (it simulates its character) a combat probe and
-- returns its report (nil when it never answers). The report queue for that
-- player exists only for the call if it was not already there.
local function askClient(target: Player, payload: { [string]: any }): any?
	local had = selfTestReports[target.UserId] ~= nil
	if not had then
		selfTestReports[target.UserId] = {}
	end
	payload.Stage = "TutorialProbe"
	RemoteEvents.SelfTest:FireClient(target, payload)
	local report = waitForReport(target, "TutorialProbe", SELFTEST_PROBE_TIMEOUT)
	if not had then
		selfTestReports[target.UserId] = nil
	end
	return report
end

-- 2 players (Test -> 2 players): the attacker hits the other player through
-- CombatService.ApplyHit and the distance is measured ON THE TARGET'S OWN
-- CLIENT (its root position just before the hit and 0.6 s after), because
-- the server reading back its own velocity writes proved nothing. The
-- server-side distance is printed next to it. The Bat must move the target
-- >= 12 studs, the Glove >= 20; 0.5 s after the ragdoll ends the target's
-- client must be standing (state not Physics, PlatformStand off, no mover).
function runLaunchSelfTest(player: Player, result: (boolean, string, string?) -> ())
	local target: Player? = nil
	for _, candidate in Players:GetPlayers() do
		if candidate ~= player and PlayerDataService.IsDataLoaded(candidate) and candidate.Character then
			target = candidate
		end
	end
	if not target then
		result(true, "combat launch: a hit launches the target (skipped: needs a second player, Test -> 2 players)")
		return
	end
	local victim = target :: Player
	local attackerData, victimData = PlayerDataService.GetData(player), PlayerDataService.GetData(victim)
	local victimRoot = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
	if not attackerData or not victimData or not victimRoot or not victimRoot:IsA("BasePart") then
		result(true, "combat launch: a hit launches the target (skipped: no data or character)")
		return
	end
	local savedRebirths = { attackerData.Rebirths, victimData.Rebirths }
	attackerData.Rebirths = math.max(1, attackerData.Rebirths)
	victimData.Rebirths = math.max(1, victimData.Rebirths)
	local attributes = { "ImmuneUntil", "SpawnProtectUntil", "RagdollUntil", "FrozenUntil" }
	local saved: { [string]: any } = {}
	for _, name in attributes do
		saved[name] = victim:GetAttribute(name)
	end
	printPhysicsSettings(victimRoot)
	CombatService.SetLaunchLogging(true)
	local function clientPosition(): Vector3?
		local report = askClient(victim, { Kind = "RootPos" })
		if report and typeof(report.Lines) == "table" then
			for _, line in report.Lines do
				result(line.Ok == true, tostring(line.Name), line.Detail)
			end
		end
		local data = report and report.Data
		return if typeof(data) == "table" and typeof(data.Pos) == "Vector3" then data.Pos else nil
	end
	for _, spec in { { "Bat", 12 }, { "SlapGlove", 20 } } do
		local weapon = CombatConfig.GetWeapon(spec[1] :: string) :: CombatConfig.Weapon
		for _, name in attributes do
			victim:SetAttribute(name, nil)
		end
		local home = victimRoot.CFrame
		local before = clientPosition()
		local serverBefore = victimRoot.Position
		if before then
			CombatService.ApplyHit(player, victim, weapon, serverBefore - Vector3.new(0, 0, 3))
			task.wait(0.6)
			local after = clientPosition()
			local serverMoved = (Vector3.new(victimRoot.Position.X, 0, victimRoot.Position.Z) - Vector3.new(serverBefore.X, 0, serverBefore.Z)).Magnitude
			if after then
				local moved = (Vector3.new(after.X, 0, after.Z) - Vector3.new(before.X, 0, before.Z)).Magnitude
				result(
					moved >= (spec[2] :: number),
					("combat launch: the %s launches the target >= %d studs in 0.6 s (measured on the TARGET's client)"):format(weapon.Name, spec[2] :: number),
					("target client %.1f studs, server view %.1f studs"):format(moved, serverMoved)
				)
			else
				result(false, ("combat launch: the %s launch is measured on the target's client"):format(weapon.Name), ("the target client did not answer; server view %.1f studs"):format(serverMoved))
			end
		else
			result(false, ("combat launch: the %s launch is measured on the target's client"):format(weapon.Name), "the target client did not answer before the hit")
		end
		-- 0.5 s after the ragdoll ends: standing again, on the target's client.
		task.wait(math.max(0, CombatConfig.RagdollSeconds - 0.6) + 0.5)
		local report = askClient(victim, { Kind = "GetUp" })
		if report and typeof(report.Lines) == "table" then
			for _, line in report.Lines do
				result(line.Ok == true, tostring(line.Name):gsub("combat launch:", ("combat launch (%s):"):format(weapon.Name)), line.Detail)
			end
		else
			result(false, ("combat launch (%s): after the get-up the target client is standing"):format(weapon.Name), "the target client did not answer")
		end
		local humanoid = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
		result(
			humanoid ~= nil and not humanoid.PlatformStand,
			("combat launch: after the %s the server's view of the target has PlatformStand off"):format(weapon.Name),
			("PlatformStand %s"):format(tostring(humanoid and humanoid.PlatformStand))
		)
		for _, name in attributes do
			victim:SetAttribute(name, nil)
		end
		local character = victim.Character
		if character then
			character:PivotTo(home)
			victimRoot.AssemblyLinearVelocity = Vector3.zero
		end
		task.wait(0.2)
	end
	CombatService.SetLaunchLogging(false)
	for _, name in attributes do
		victim:SetAttribute(name, saved[name])
	end
	attackerData.Rebirths, victimData.Rebirths = savedRebirths[1], savedRebirths[2]
end

local function runCombatSelfTest(player: Player, result: (boolean, string, string?) -> ())
	-- The Studio test start (Rebirths 3 + every weapon) never reaches a live
	-- server, the Live store or the Studio test store.
	local live = DebugService.ShouldApplyStudioStart(false, "Mock")
	local liveStore = DebugService.ShouldApplyStudioStart(true, "Live")
	local testStore = DebugService.ShouldApplyStudioStart(true, "StudioTest")
	local mock = DebugService.ShouldApplyStudioStart(true, "Mock")
	result(
		not live and not liveStore and not testStore and mock,
		"debug: the Studio start (Rebirths + weapons) runs only in Studio on the Mock store",
		("live server %s, Live store %s, test store %s, Studio Mock %s"):format(tostring(live), tostring(liveStore), tostring(testStore), tostring(mock))
	)
	-- Every weapon is a Handle plus parts welded to it: massless, nothing
	-- collides, and it fits a 4.5-stud box.
	for _, weapon in CombatConfig.Weapons do
		local tool = WeaponKit.Build(weapon.Id)
		local why = WeaponKit.Validate(tool)
		local extent = WeaponKit.GetExtent(tool)
		tool:Destroy()
		result(why == nil, ("combat: the %s model has a Handle, every part welded + massless, fits %.1f studs"):format(weapon.Name, WeaponKit.MAX_EXTENT), why or tostring(extent))
	end
	local placed = WeaponKit.BuildPlaced()
	local hitbox = placed:FindFirstChild("Hitbox")
	local petals = 0
	for _, child in placed:GetChildren() do
		if child.Name:sub(1, 5) == "Petal" then
			petals += 1
		end
	end
	result(hitbox ~= nil and hitbox:IsA("BasePart") and hitbox.CanTouch and petals == 9, "combat: the placed Banana Peel is 3 petals (3 segments each) round a touch hitbox", ("hitbox %s, %d petal parts"):format(tostring(hitbox), petals))
	placed:Destroy()

	local data = PlayerDataService.GetData(player)
	if data then
		local rebirths = data.Rebirths
		data.Rebirths = 0
		local why = CombatService.WhyNotHittable(player)
		data.Rebirths = rebirths
		result(why == "NeedsRebirth", "combat: a Rebirth-0 player can't be hit", tostring(why))
	end

	-- Each weapon, equipped through the server on the tester: the RightGrip
	-- weld exists, the Handle is within 1.5 studs of RightHand, and (the
	-- client measures it) the arm is out while held and moves in a swing /
	-- kick / toss. The tool is destroyed afterwards.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and humanoid.Health > 0 then
		local function sampleRest()
			humanoid:UnequipTools()
			task.wait(0.3)
			tutorialProbe(player, { Kind = "SampleRest" }, result)
		end
		for _, weapon in CombatConfig.Weapons do
			sampleRest()
			local tool = WeaponKit.Build(weapon.Id)
			humanoid:EquipTool(tool)
			task.wait(0.4)
			local problem = if tool.Parent == character then CombatService.GetGripProblem(character, tool) else "the tool did not equip"
			result(problem == nil, ("combat: the %s is held (RightGrip weld, Handle within 1.5 studs of RightHand)"):format(weapon.Name), problem)
			if tool.Parent == character then
				tutorialProbe(player, { Kind = "Weapon", Weapon = weapon.Id }, result)
			end
			tool:Destroy()
			task.wait(0.1)
		end
		-- Switches without an UnequipTools in between: EquipTool of the second
		-- tool takes the first out of the hand the way a slot press does.
		for _, pair in { { "Bat", "SlapGlove" }, { "LaserGun", "FreezeRay" }, { "SlapGlove", "Bat" } } do
			sampleRest()
			local first, second = WeaponKit.Build(pair[1]), WeaponKit.Build(pair[2])
			humanoid:EquipTool(first)
			task.wait(0.5)
			humanoid:EquipTool(second)
			task.wait(0.5)
			if second.Parent == character then
				tutorialProbe(player, { Kind = "Switch", From = pair[1], To = pair[2], Weapon = pair[2] }, result)
			else
				result(false, ("combat switch %s -> %s"):format(pair[1], pair[2]), "the second tool did not equip")
			end
			first:Destroy()
			second:Destroy()
			task.wait(0.1)
		end
		sampleRest()
		tutorialProbe(player, { Kind = "WeaponReleased" }, result)
		tutorialProbe(player, { Kind = "Fallback" }, result)
	else
		result(true, "combat: weapons are held (skipped: no living character)")
	end

	runLaunchSelfTest(player, result)

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
	result(not TutorialService.ShouldSkipOnJoin(false), "tutorial: a live server (not Studio) never skips the tutorial on join")
	-- No lab yet: claim one through the real claim path, release it after.
	local claimState, releaseClaim = TycoonService.SelfTestClaim(player)
	if claimState == "Skip" then
		print("[SelfTest] SKIP tutorial drive: no free lab slot to claim")
		return
	end
	local saved = PlayerDataService.SelfTestSwapTutorial(player, nil)
	local popups = 0
	local watch = RemoteEvents.ShopAnalytics.OnServerEvent:Connect(function(sender: Player, payload: unknown)
		local event = typeof(payload) == "table" and (payload :: any).Event
		if sender == player and (event == "OfferShown" or event == "DealShown") then
			popups += 1
		end
	end)

	-- A save from Tutorial 1 (its 14 steps, no Ver) resumes at the matching step.
	local function migrates(oldId: number, newId: string): boolean
		local step = PlayerDataService.SelfTestMigrateTutorial({ Step = oldId, Done = false })
		return step == TutorialConfig.IndexOf(newId)
	end
	result(
		migrates(2, "claim") and migrates(4, "pull") and migrates(6, "fuse") and migrates(8, "multiplier") and migrates(13, "rebirth") and migrates(14, "finish"),
		"tutorial: a Tutorial 1 save resumes at the matching step"
	)
	local doneStep = PlayerDataService.SelfTestMigrateTutorial({ Step = 9, Done = true })
	result(doneStep == 9, "tutorial: a finished Tutorial 1 save stays finished")

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
		if step.Kind == "Timed" then
			-- The server's clock: refused before its Seconds, allowed after.
			result(not TutorialService.Advance(player, index), ("tutorial: %s is refused before its %ds"):format(step.Id, step.Seconds or 0))
		end
		-- What the real client shows for this step: the banner, no card, the
		-- HUD set of the table, the weapon bar off at Rebirth 0.
		tutorialProbe(player, { Kind = "Step", StepIndex = index, StepId = step.Id }, result)
		if step.Id == "upgrade" then
			PlayerDataService.AddCash(player, 1e6)
			TycoonService.HandleUpgradeRequest(player, "basic_generator")
		elseif step.Id == "pull" or step.Id == "pull2" then
			TycoonService.TutorialPull(player)
			if step.Id == "pull" then
				-- A single pull of a Common opens the big card ("COMMON ORB!").
				tutorialProbe(player, { Kind = "BigCard", Expect = "COMMON ORB!" }, result)
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
			-- The tutorial fusion (Common x2 -> Rare) now opens the big card too:
			-- the step flow waits for it like the pull's. (The server-driven
			-- fusion has no client request, so the client feeds the same
			-- result through ResultController.)
			tutorialProbe(player, { Kind = "BigCard", Expect = "RARE ORB!", FakeFusion = true }, result)
		elseif step.Id == "multiplier" then
			-- The "come back with $X" branch: the skip after SkipSeconds.
			PlayerDataService.SpendCash(player, PlayerDataService.GetCash(player))
			result(not TutorialService.Advance(player, index), "tutorial: the Multiplier Pad can't be skipped at once")
			TutorialService.DebugBackdate(player, 10)
			TutorialService.Advance(player, index)
		elseif step.Kind == "Action" then
			-- claim: only reached on an unclaimed plot (claimed skips it).
			stuck = step.Id .. " (needs a claimed lab)"
			break
		else
			TutorialService.DebugBackdate(player, 10)
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
	if releaseClaim then
		releaseClaim()
	end
end

-- Progression: stacking (helpers, a live stacked item, an old save's
-- migration), the fusion intersection, the 2nd floor's assertions and
-- build, a quest claim refused while incomplete, a power-up refused at 0.
-- The tester's items, quests and power-ups are put back after.
local function runProgressionSelfTest(player: Player, result: (boolean, string, string?) -> ())
	-- Stacking helpers.
	local base, events = MutationConfig.Normalize("Void", nil)
	result(base == nil and events ~= nil and events[1] == "Void", "stacking: an event-only base moves into the set")
	local _, added = MutationConfig.AddEvent({ "Charged" }, "Charged")
	result(not added, "stacking: the same event mutation never stacks twice")
	result(MutationConfig.GetStackedMultiplier("Rainbow", { "Celestial" }) == 31, "stacking: Rainbow + Celestial = x31 (additive)")
	local epic = ItemConfig.PickRandomOfTier("Epic")
	if epic then
		local oldBase, oldEvents = PlayerDataService.SelfTestMigrateItem(epic.Id, "Epic", "Celestial")
		result(oldBase == nil and oldEvents ~= nil and oldEvents[1] == "Celestial", "stacking: an old Celestial save migrates into EventMutations")
		local entry = PlayerDataService.AddItem(player, epic.Id, "Epic", "Rainbow", { "Charged" })
		if entry then
			local again = PlayerDataService.AddItemEventMutation(player, entry.Uid, "Charged")
			local void = PlayerDataService.AddItemEventMutation(player, entry.Uid, "Void")
			local index = PlayerDataService.GetIndex(player)
			result(not again and void, "stacking: Charged refused twice, Void stacks on")
			result(
				index[IndexConfig.GetKey(epic.Id, "Rainbow")] == true
					and index[IndexConfig.GetKey(epic.Id, "Charged")] == true
					and index[IndexConfig.GetKey(epic.Id, "Void")] == true,
				"stacking: a stacked item fills each of its Index entries"
			)
			result(
				TycoonConfig.GetStackCashPerSecond(entry) == TycoonConfig.GetPedestalCashPerSecond("Epic") * (1 + 11 + 2 + 7),
				"stacking: Rainbow + Charged + Void earns x21"
			)
			local roundOk, roundDetail = PlayerDataService.SelfTestRoundTrip(player)
			result(roundOk, "stacking round trip (a stacked item through toDisk -> reconcile)", roundDetail)
			PlayerDataService.RemoveItemsByUid(player, { entry.Uid })
		end
	end

	-- Fusion intersection.
	local inputs = {
		{ Mutation = "Golden", EventMutations = { "Charged", "Void" } },
		{ Mutation = "Diamond", EventMutations = { "Charged" } },
	}
	local kept = FusionConfig.PredictEventMutations(inputs)
	result(
		FusionConfig.PredictMutation(inputs) == "Golden" and kept ~= nil and #kept == 1 and kept[1] == "Charged",
		"fusion intersection: keeps the lowest base and the shared event mutations"
	)
	local mix = FusionConfig.GetMutationMix(inputs)
	result(
		mix.Mixed and FusionConfig.IsDragging(mix, inputs[2]) and not FusionConfig.IsDragging(mix, { Mutation = "Diamond", EventMutations = { "Charged", "Void" } }),
		"fusion intersection: the Fuse panel flags the orb missing Void"
	)
	result(FusionConfig.PredictEventMutations({ inputs[1], {} }) == nil, "fusion intersection: a plain input keeps no event mutation")

	-- 2nd floor.
	local floorOk, floorError = pcall(PlotLayout.CheckFloor2)
	result(floorOk, "2nd floor: PlotLayout.CheckFloor2", if floorOk then nil else tostring(floorError))
	local order = PlotLayout.GetPedestalOrder(true, true)
	result(#PlotLayout.GetPedestalOrder(false, false) == 4 and #order == 10 and order[7] == 7, "2nd floor: fill order 1-4, 5-6, then 7-10")
	local plot = TycoonService.GetPlotForPlayer(player)
	local pedestals = plot and plot:FindFirstChild("Pedestals")
	local floor7 = pedestals and pedestals:FindFirstChild("Pedestal7")
	local origin = plot and plot.PrimaryPart
	if floor7 and floor7:IsA("BasePart") and origin then
		local localY = origin.CFrame:PointToObjectSpace(floor7.Position).Y
		result(
			plot:FindFirstChild("SecondFloor") ~= nil and math.abs(localY - (PlotLayout.Floor2.TopY + PlotLayout.Pedestal.ColumnSize.Y / 2)) < 0.1,
			"2nd floor: built, pedestal 7 stands on the deck",
			("local y %.2f"):format(localY)
		)
	end
	local rebirths = PlayerDataService.GetRebirths(player)
	result(
		PlayerDataService.IsPedestalUnlocked(player, 7) == RebirthConfig.HasSecondFloor(rebirths),
		("2nd floor: pedestal 7 unlocked exactly from Rebirth %d"):format(RebirthConfig.SecondFloorRebirths)
	)

	-- Quests and power-ups (state saved and put back).
	local saved = PlayerDataService.SelfTestSnapshotQuests(player)
	local quests = PlayerDataService.GetQuestState(player)
	QuestService.GetDailyIds(player)
	if quests and #quests.Daily > 0 then
		local entry = quests.Daily[1]
		entry.Done = false
		entry.Claimed = false
		entry.Target = 1e15 -- unreachable
		result(QuestService.WhyNotClaim(player, entry.Id) == "NotComplete", "quests: a claim is refused while incomplete")
		local ok = QuestService.Claim(player, entry.Id)
		result(not ok and not entry.Claimed, "quests: the refused claim paid nothing")
		result(QuestService.WhyNotClaim(player, "nope") == "Unknown", "quests: an unknown quest is refused")
	else
		result(false, "quests: today's dailies were handed out")
	end
	local have = PlayerDataService.GetPowerUpCount(player, "CashBurst")
	PlayerDataService.AddPowerUp(player, "CashBurst", -have)
	local boostBefore = PlayerDataService.GetBoostSeconds(player, "Income")
	local used = QuestService.Use(player, "CashBurst")
	result(
		not used and QuestService.WhyNotUse(player, "CashBurst") == "NoneLeft" and PlayerDataService.GetBoostSeconds(player, "Income") == boostBefore,
		"power-ups: refused at 0, nothing banked"
	)
	PlayerDataService.SelfTestRestoreQuests(player, saved)
	PlayerDataService.SyncTycoon(player)
end

local function runAutoDisplaySelfTest(player: Player, result: (boolean, string, string?) -> ())
	-- Auto-display: 6 random items -> the pedestals hold the best by $/s,
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
end

-- One section of the run: a header, then the body in a pcall so an error is
-- a FAIL line and the next section still runs.
local function runSection(title: string, result: (boolean, string, string?) -> (), body: () -> ())
	print(("[SelfTest] == %s =="):format(title))
	local ok, err = pcall(body)
	if not ok then
		result(false, title .. " (errored)", tostring(err))
	end
end

-- The Gacha Pad card (client-built, own pad): its numbers against the
-- server's luck now and under an admin-luck event (no persistent state is
-- touched: Workspace attributes, restored), then its buttons.
local function runGachaCardSelfTest(player: Player, result: (boolean, string, string?) -> ())
	-- The card only exists for a claimed lab.
	local claimState, releaseClaim = TycoonService.SelfTestClaim(player)
	if claimState == "Skip" then
		result(false, "gacha card: a claimed lab to test on", "could not claim a lab for the tester (no free slot or no character)")
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local plot = TycoonService.GetPlotForPlayer(player)
	local station = plot and plot:FindFirstChild("GachaStation")
	local pad = station and station:FindFirstChild("Pad")
	if not (root and root:IsA("BasePart") and plot and pad and pad:IsA("BasePart")) then
		result(false, "gacha card: standing next to the pad", ("root %s, plot %s, pad %s"):format(tostring(root), tostring(plot), tostring(pad)))
		if releaseClaim then
			releaseClaim()
		end
		return
	end
	local home = root.CFrame
	local onPad = pad.CFrame + Vector3.new(0, pad.Size.Y / 2 + 3, 0)
	-- 25 studs from the pad, toward the middle of the lab.
	local toward = plot:GetPivot().Position - pad.Position
	local flat = Vector3.new(toward.X, 0, toward.Z)
	flat = if flat.Magnitude > 1 then flat.Unit else Vector3.new(-1, 0, 0)
	local away = CFrame.new(pad.Position + flat * 25 + Vector3.new(0, pad.Size.Y / 2 + 3, 0))

	-- Next to the pad: wait 0.4 s, then everything is read from the card's tree.
	root.CFrame = onPad
	task.wait(0.4)
	tutorialProbe(player, { Kind = "GachaCard", Label = "luck as is", Luck = PlayerDataService.GetLuck(player) }, result)
	local oldLuck, oldUntil = Workspace:GetAttribute("AdminLuck"), Workspace:GetAttribute("AdminLuckUntil")
	Workspace:SetAttribute("AdminLuck", 3)
	Workspace:SetAttribute("AdminLuckUntil", Workspace:GetServerTimeNow() + 120)
	PlayerDataService.SyncTycoon(player)
	task.wait(0.6)
	tutorialProbe(player, { Kind = "GachaCard", Label = "luck x3 event", Luck = PlayerDataService.GetLuck(player) }, result)
	Workspace:SetAttribute("AdminLuck", oldLuck)
	Workspace:SetAttribute("AdminLuckUntil", oldUntil)
	PlayerDataService.SyncTycoon(player)
	tutorialProbe(player, { Kind = "GachaButtons" }, result)

	-- 25 studs away: the card pops out and the small GACHA label shows.
	root.CFrame = away
	task.wait(0.6)
	tutorialProbe(player, { Kind = "GachaFar" }, result)
	-- Back on the pad: it pops in again.
	root.CFrame = onPad
	task.wait(0.5)
	tutorialProbe(player, { Kind = "GachaBack" }, result)

	root.CFrame = home
	if releaseClaim then
		releaseClaim()
	end
end

local function runSelfTestBody(player: Player, result: (boolean, string, string?) -> (), only: string?)
	print(("[SelfTest] running for %s"):format(player.Name))
	if only == "combat" then
		print("[SelfTest] == 10. combat ==")
		runCombatSelfTest(player, result)
		return
	elseif only == "gacha" then
		print("[SelfTest] == 12. gacha card ==")
		runGachaCardSelfTest(player, result)
		return
	elseif only == "cards" then
		print("[SelfTest] == cards ==")
		RemoteEvents.SelfTest:FireClient(player, { Only = "cards" })
		local done = waitForReport(player, "Done")
		if not done then
			result(false, "cards", "no report from the client")
		else
			for _, line in (if typeof(done.Panels) == "table" then done.Panels else {}) do
				if typeof(line) == "string" then
					result(line:sub(1, 4) == "PASS", line:sub(6))
				end
			end
		end
		return
	end
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

	-- 8. Auto-display (see runAutoDisplaySelfTest).
	runSection("8. auto-display", result, function()
		runAutoDisplaySelfTest(player, result)
	end)

	-- 9. The tutorial, driven step by step on the real paths (the remote's
	-- own handlers): every step completes in order, no shop / deal pop-up
	-- while it runs, and a save left mid-way resumes at its step. The
	-- tester's own tutorial state is restored after.
	runSection("9. tutorial", result, function()
		runTutorialSelfTest(player, result)
	end)

	-- 10. Combat: a Rebirth-0 player is never hittable; the cooldown is the
	-- server's; a hit on a carrying thief sends the orb home with both
	-- inventories unchanged (needs a second player: Test -> 2 players).
	runSection("10. combat", result, function()
		runCombatSelfTest(player, result)
	end)

	-- 11. Progression: stacking, the fusion intersection, the 2nd floor,
	-- quest / power-up refusals (the junk fuzz above covered their remotes).
	runSection("11. progression", result, function()
		runProgressionSelfTest(player, result)
	end)

	-- 12. The Gacha Pad card: odds against the server's luck, silhouettes,
	-- the (i) panel, the custom buttons.
	runSection("12. gacha card", result, function()
		runGachaCardSelfTest(player, result)
	end)
end

local function runSelfTest(player: Player, only: string?)
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
	print(("[SelfTest] store: %s%s"):format(storeKind, if only then ", only: " .. only else ""))
	-- The report queue lives for the WHOLE run (every probe's report needs it)
	-- and is cleared on every way out.
	selfTestReports[player.UserId] = {}
	local ok, err = pcall(runSelfTestBody, player, result, only)
	if not ok then
		result(false, "self-test aborted", tostring(err))
	end
	selfTestReports[player.UserId] = nil
	print(("[SelfTest] done: %d passed, %d failed"):format(passed, failed))
end

local function onPlayerChatted(player: Player, message: string)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	local lower = message:lower()
	local command, argument = lower:match("^(%S+)%s*(.*)$")
	if command == SELFTEST_COMMAND then
		task.spawn(runSelfTest, player, if argument ~= "" then argument else nil)
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
	elseif command == ANIM_COMMAND then
		if argument == "export" then
			-- Every weapon clip as a KeyframeSequence in
			-- ServerStorage.WeaponAnimExports: right-click each -> Save to
			-- Roblox, then paste the ids into CombatConfig.AnimationIds.
			local old = ServerStorage:FindFirstChild("WeaponAnimExports")
			if old then
				old:Destroy()
			end
			local folder = Instance.new("Folder")
			folder.Name = "WeaponAnimExports"
			for _, name in WeaponAnims.Names do
				local sequence = WeaponAnims.Build(name)
				if sequence then
					sequence.Parent = folder
				end
			end
			folder.Parent = ServerStorage
			print(("DebugService: %d weapon clips in ServerStorage.WeaponAnimExports (right-click each -> Save to Roblox, paste the ids into CombatConfig.AnimationIds)"):format(#folder:GetChildren()))
		else
			warn("DebugService: /anim export")
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

	print("DebugService: Studio commands active: /cash <amount>, /resetmultiplier, /rebirthready, /rebirths <n>, /give <itemId> [mutation], /offline <minutes>, /shield <s>, /stealable, /tips reset, /tutorial reset|step <n>, /weapons all|reset, /anim export, /quest complete <id>|reset, /powerup <key> <n>, /event <id> [min] | off, /eventclock <min>, /eventmut <charged|void|celestial>, /shop grant <key>, /deal slot <h> | pop, /daily day|miss|reset, /gifts time|reset, /selftest, /wipe")
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

	if DebugService.ShouldApplyStudioStart(RunService:IsStudio(), PlayerDataService.GetStoreKind()) then
		local applied: { [number]: boolean } = {}
		local function apply(player: Player)
			if not applied[player.UserId] and DebugService.ApplyStudioStart(player) then
				applied[player.UserId] = true
				print(("DebugService: Studio start for %s: Rebirths >= %d%s"):format(player.Name, DebugConfig.StudioStartRebirths, if DebugConfig.StudioGrantAllWeapons then ", all weapons" else ""))
			end
		end
		PlayerDataService.DataLoaded:Connect(apply)
		for _, player in Players:GetPlayers() do
			apply(player)
		end
		Players.PlayerRemoving:Connect(function(player: Player)
			applied[player.UserId] = nil
		end)
	end
end

return DebugService
