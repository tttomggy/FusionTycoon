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
local TipConfig = require(ReplicatedStorage.Shared.Config.TipConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local GachaConfig = require(ReplicatedStorage.Shared.Config.GachaConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local IndexConfig = require(ReplicatedStorage.Shared.Config.IndexConfig)
local OfflineConfig = require(ReplicatedStorage.Shared.Config.OfflineConfig)
local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local RivalConfig = require(ReplicatedStorage.Shared.Config.RivalConfig)
local StreetLayout = require(ReplicatedStorage.Shared.Config.StreetLayout)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local FactoryKit = require(ReplicatedStorage.Shared.Modules.FactoryKit)
local GeneratorKit = require(ReplicatedStorage.Shared.Modules.GeneratorKit)
local PortalKit = require(ReplicatedStorage.Shared.Modules.PortalKit)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local FriendConfig = require(ReplicatedStorage.Shared.Config.FriendConfig)
local DealConfig = require(ReplicatedStorage.Shared.Config.DealConfig)
local DealState = require(ReplicatedStorage.Shared.Modules.DealState)
local DailyConfig = require(ReplicatedStorage.Shared.Config.DailyConfig)
local GiftConfig = require(ReplicatedStorage.Shared.Config.GiftConfig)
local RewardConfig = require(ReplicatedStorage.Shared.Config.RewardConfig)
local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local GoalSteps = require(ReplicatedStorage.Shared.Modules.GoalSteps)
local GoalConfig = require(ReplicatedStorage.Shared.Config.GoalConfig)
local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
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
type RewardServiceModule = typeof(require(script.Parent.RewardService))
type FriendServiceModule = typeof(require(script.Parent.FriendService))
type NotifyServiceModule = typeof(require(script.Parent.NotifyService))
type RivalServiceModule = typeof(require(script.Parent.RivalService))
type GoalServiceModule = typeof(require(script.Parent.GoalService))

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
local RewardService: RewardServiceModule
local FriendService: FriendServiceModule
local NotifyService: NotifyServiceModule
local RivalService: RivalServiceModule
local GoalService: GoalServiceModule

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
		-- No unlock cards at join: nothing is on screen yet to hold them, and
		-- five stacked TutorialCards each tripped UIKit's no-card watchdog.
		CombatService.DebugSetAll(player, true, true)
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
-- "/data slowload <seconds>" delays the NEXT join's data load (Studio), to
-- reproduce a character that spawns before its data.
local DATA_COMMAND = "/data"
local ANIM_COMMAND = "/anim"
-- "/combat box" toggles drawing each melee swing's server hitbox (a red
-- transparent part for 0.2 s, sized to that weapon's MeleeBox).
local COMBAT_COMMAND = "/combat"
-- "/quest complete <id>" latches a daily ("pull20", ...) or "chain" done;
-- "/quest reset" hands today's dailies out again and restarts the chain;
-- "/quest status" prints each quest's kind, base, progress, Done / Claimed
-- and the Fused_* stats (why a quest isn't done).
local QUEST_COMMAND = "/quest"
-- "/sound <slot>" plays that SoundConfig slot at your character (any case)
-- to judge it by ear; "/sound" alone lists the slots.
local SOUND_COMMAND = "/sound"
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
-- "/gifts time 24" sets THIS VISIT's play time to 24 min (the playtime gifts);
-- "/gifts reset" starts the visit again (0 s, every gift locked and unclaimed).
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
local SELFTEST_PROBE_TIMEOUT = 10 -- one combat / gacha probe
-- The effects tray probe: two layouts x (a 3 s tooltip wait + checks) + three window sizes.
local SELFTEST_EFFECTS_TIMEOUT = 30
-- The gacha-on-pad probe: 4 yaws + 3 zooms, a toast wait, and (phone) five
-- tester spots x two sizes. A timeout here let the next probe start while it
-- still ran, and its late layout restore broke the next probe's.
local SELFTEST_GACHA_PAD_TIMEOUT = 45
local SELFTEST_STEP_TIMEOUT = 75 -- one tutorial step probe: the presenter (30 s cap) + its card, bar, hand and HUD waits
local SELFTEST_SLOT_COUNT = 200
local TUTORIAL_BUDGET_SECONDS = 45 -- Tutorial 5: claim to Done, walking excluded
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

-- `probeId`: only the report that answers THAT request counts. A probe
-- that ran long and answered after its request timed out is dropped, never
-- handed to the next request (that shifted every later tutorial line by one).
local function waitForReport(player: Player, stage: string, timeout: number?, probeId: number?): any?
	local started = os.clock()
	local limit = timeout or SELFTEST_REPORT_TIMEOUT
	while os.clock() - started < limit and player.Parent do
		local queue = selfTestReports[player.UserId]
		if queue then
			for index, report in queue do
				if report.Stage == stage then
					if probeId == nil or report.ProbeId == probeId then
						table.remove(queue, index)
						return report
					elseif typeof(report.ProbeId) == "number" and report.ProbeId < probeId then
						table.remove(queue, index) -- stale: its request already gave up
						break
					end
				end
			end
		end
		task.wait(0.2)
	end
	return nil
end

local probeCounter = 0

-- Asks the client what it shows right now (SelfTestController's probe) and
-- turns each line it reports into a result.
local function tutorialProbe(player: Player, payload: { [string]: any }, result: (boolean, string, string?) -> ())
	payload.Stage = "TutorialProbe"
	probeCounter += 1
	local probeId = probeCounter
	payload.ProbeId = probeId
	RemoteEvents.SelfTest:FireClient(player, payload)
	local report = waitForReport(player, "TutorialProbe", if payload.Kind == "Step" then SELFTEST_STEP_TIMEOUT elseif payload.Kind == "EffectsTray" then SELFTEST_EFFECTS_TIMEOUT elseif payload.Kind == "GachaOnPad" then SELFTEST_GACHA_PAD_TIMEOUT else SELFTEST_PROBE_TIMEOUT, probeId)
	if not report or typeof(report.Lines) ~= "table" then
		local which = if payload.Kind == "Weapon" or payload.Kind == "Switch" then "combat " .. tostring(payload.Weapon or payload.To or "")
			elseif payload.Kind == "WeaponReleased" then "combat release"
			else "tutorial " .. tostring(payload.StepId or payload.Kind)
		result(false, which, "no report from the client")
		return
	end
	for _, line in report.Lines do
		if line.Ok ~= true and line.Warn == true then
			-- A WARN is printed, never counted as a FAIL.
			print(("[SelfTest] WARN %s | %s"):format(tostring(line.Name), tostring(line.Detail)))
			result(true, tostring(line.Name) .. " (WARN)", line.Detail)
		else
			result(line.Ok == true, tostring(line.Name), line.Detail)
		end
	end
end

local runLaunchSelfTest: (Player, (boolean, string, string?) -> ()) -> ()
local runSwingSelfTest: (Player, (boolean, string, string?) -> ()) -> ()

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
	probeCounter += 1
	local probeId = probeCounter
	payload.ProbeId = probeId
	RemoteEvents.SelfTest:FireClient(target, payload)
	local report = waitForReport(target, "TutorialProbe", SELFTEST_PROBE_TIMEOUT, probeId)
	if not had then
		selfTestReports[target.UserId] = nil
	end
	return report
end

-- The tutorial timed run: waits (up to PRESENT_WAIT + slack) for the real
-- presenter to have `stepId`'s banner up. Returns the client's report.
local function askPresented(target: Player, stepId: string): any?
	probeCounter += 1
	local probeId = probeCounter
	RemoteEvents.SelfTest:FireClient(target, { Stage = "TutorialProbe", Kind = "Presented", StepId = stepId, ProbeId = probeId })
	return waitForReport(target, "TutorialProbe", SELFTEST_STEP_TIMEOUT, probeId)
end

-- The root position `target`'s own client sees (nil when it never answers);
-- a problem it reports becomes a result line.
local function askRootPos(target: Player, result: (boolean, string, string?) -> ()): Vector3?
	local report = askClient(target, { Kind = "RootPos" })
	if report and typeof(report.Lines) == "table" then
		for _, line in report.Lines do
			result(line.Ok == true, tostring(line.Name), line.Detail)
		end
	end
	local data = report and report.Data
	return if typeof(data) == "table" and typeof(data.Pos) == "Vector3" then data.Pos else nil
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
		return askRootPos(victim, result)
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

-- 2 players: the REAL chain, which every other combat check skipped (they call
-- ApplyHit). Player2 is put 6 studs in front of Player1 and 3 to the side
-- (a near miss that used to whiff), facing Player1; the
-- Bat is equipped through a real Tool and Player1's CLIENT clicks it
-- (CombatController.Use, what Tool.Activated calls); the server's box must
-- log "HIT Player2" and Player2 must fly, measured on Player2's own client.
-- Then the Glove. Then Player2 out to the side beyond the weapon's box (box
-- half-width + 2.5: 7 studs for the Bat; an avatar is 4 wide, so an arm
-- reaches 2 in): the log says MISS and Player2 does not move.
function runSwingSelfTest(player: Player, result: (boolean, string, string?) -> ())
	local target: Player? = nil
	for _, candidate in Players:GetPlayers() do
		if candidate ~= player and PlayerDataService.IsDataLoaded(candidate) and candidate.Character then
			target = candidate
		end
	end
	if not target then
		result(true, "combat swing: a real swing hits the player in front (skipped: needs a second player, Test -> 2 players)")
		return
	end
	local victim = target :: Player
	local attackerData, victimData = PlayerDataService.GetData(player), PlayerDataService.GetData(victim)
	local attackerCharacter, victimCharacter = player.Character, victim.Character
	local attackerRoot = attackerCharacter and attackerCharacter:FindFirstChild("HumanoidRootPart")
	local victimRoot = victimCharacter and victimCharacter:FindFirstChild("HumanoidRootPart")
	local attackerHumanoid = attackerCharacter and attackerCharacter:FindFirstChildOfClass("Humanoid")
	if not attackerData or not victimData or not attackerCharacter or not victimCharacter or not attackerRoot or not victimRoot or not attackerHumanoid
		or not attackerRoot:IsA("BasePart") or not victimRoot:IsA("BasePart") then
		result(true, "combat swing: a real swing hits the player in front (skipped: no data or character)")
		return
	end
	local savedRebirths = { attackerData.Rebirths, victimData.Rebirths }
	attackerData.Rebirths = math.max(1, attackerData.Rebirths)
	victimData.Rebirths = math.max(1, victimData.Rebirths)
	PlayerDataService.SyncTycoon(player)
	PlayerDataService.SyncTycoon(victim)
	local attributes = { "ImmuneUntil", "SpawnProtectUntil", "RagdollUntil", "FrozenUntil" }
	local savedAttributes: { [string]: any } = {}
	for _, name in attributes do
		savedAttributes[name] = victim:GetAttribute(name)
	end
	local homeAttacker, homeVictim = attackerRoot.CFrame, victimRoot.CFrame
	local look = homeAttacker.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 0.01 then flatLook.Unit else Vector3.new(0, 0, -1)
	local attackerCFrame = CFrame.lookAt(homeAttacker.Position, homeAttacker.Position + flatLook)
	local function clearState()
		for _, name in attributes do
			victim:SetAttribute(name, nil)
		end
		player:SetAttribute("RagdollUntil", nil)
	end
	-- Both on their feet at their spots, facing each other, at rest.
	local function place(localOffset: Vector3)
		clearState()
		attackerCharacter:PivotTo(attackerCFrame)
		local at = attackerCFrame:PointToWorldSpace(localOffset)
		victimCharacter:PivotTo(CFrame.lookAt(at, Vector3.new(attackerCFrame.Position.X, at.Y, attackerCFrame.Position.Z)))
		attackerRoot.AssemblyLinearVelocity = Vector3.zero
		victimRoot.AssemblyLinearVelocity = Vector3.zero
		task.wait(0.5)
	end

	for _, spec in { { "Bat", 12 }, { "SlapGlove", 20 } } do
		local weapon = CombatConfig.GetWeapon(spec[1] :: string) :: CombatConfig.Weapon
		-- The real tool: the one in the Backpack if the player has it, else a
		-- built one (destroyed afterwards).
		attackerHumanoid:UnequipTools()
		-- Owned for the test (the server checks it), taken back afterwards.
		local owned = PlayerDataService.GetWeapons(player)
		local ownedBefore = owned[weapon.Id] == true
		owned[weapon.Id] = true
		local backpack = player:FindFirstChildOfClass("Backpack")
		local tool = (backpack and backpack:FindFirstChild(weapon.Id)) or attackerCharacter:FindFirstChild(weapon.Id)
		local built = false
		if not tool or not tool:IsA("Tool") then
			tool = WeaponKit.Build(weapon.Id)
			built = true
		end
		attackerHumanoid:EquipTool(tool :: Tool)
		task.wait(0.4)
		local equipped = (tool :: Instance).Parent == attackerCharacter
		result(equipped, ("combat swing (%s): the tool is equipped on the attacker"):format(weapon.Name), ("tool parent %s"):format(tostring((tool :: Instance).Parent)))
		if equipped then
			local boxSize = CombatConfig.GetMeleeBox(weapon)
			local missSide = boxSize.X / 2 + 2.5
			for _, case in { { "front", Vector3.new(3, 0, -6) }, { "side", Vector3.new(missSide, 0, 0) } } do
				local label = ("%s, victim %s"):format(
					weapon.Name,
					if case[1] == "front" then "6 studs in front and 3 to the side" else ("%.1f studs to the side, out of the box"):format(missSide)
				)
				place(case[2] :: Vector3)
				CombatService.ResetCooldowns(player)
				local before = askRootPos(victim, result)
				local previous = CombatService.GetLastVerdict(player)
				local seqBefore = if previous then previous.Seq else 0
				local report = askClient(player, { Kind = "Swing", Weapon = weapon.Id })
				if report and typeof(report.Lines) == "table" then
					for _, line in report.Lines do
						result(line.Ok == true, tostring(line.Name), line.Detail)
					end
				else
					result(false, ("combat swing (%s): a click on the attacker's client swings"):format(weapon.Name), "the attacker's client did not answer")
				end
				-- The verdict arrives MeleeHitDelay after the swing.
				local verdict: any = nil
				local waited = os.clock()
				while os.clock() - waited < 2 do
					local latest = CombatService.GetLastVerdict(player)
					if latest and latest.Seq > seqBefore then
						verdict = latest
						break
					end
					task.wait(0.05)
				end
				task.wait(0.6)
				local after = askRootPos(victim, result)
				local moved = if before and after then (Vector3.new(after.X, 0, after.Z) - Vector3.new(before.X, 0, before.Z)).Magnitude else nil
				local line = if verdict then verdict.Line else "no verdict within 2 s of the click (the server never resolved a swing)"
				if case[1] == "front" then
					result(verdict ~= nil and #verdict.Hit == 1 and verdict.Hit[1] == victim.Name, ("combat swing (%s): the server log says HIT %s"):format(label, victim.Name), line)
					result(
						moved ~= nil and moved >= (spec[2] :: number),
						("combat swing (%s): a real swing launches the target >= %d studs in 0.6 s (measured on the TARGET's client)"):format(label, spec[2] :: number),
						if moved then ("target client %.1f studs"):format(moved) else "the target client did not answer"
					)
				else
					result(verdict ~= nil and #verdict.Found == 0 and #verdict.Hit == 0 and line:find("MISS", 1, true) ~= nil, ("combat swing (%s): the server log says MISS"):format(label), line)
					result(moved ~= nil and moved < 1, ("combat swing (%s): the target does not move"):format(label), if moved then ("target client moved %.1f studs"):format(moved) else "the target client did not answer")
				end
				-- Let a ragdoll end before the next case.
				task.wait(CombatConfig.RagdollSeconds + 0.4)
				clearState()
				victimCharacter:PivotTo(homeVictim)
				attackerCharacter:PivotTo(homeAttacker)
				victimRoot.AssemblyLinearVelocity = Vector3.zero
				task.wait(0.3)
			end
		end
		attackerHumanoid:UnequipTools()
		if built then
			local builtTool = tool :: Instance
			builtTool:Destroy()
		end
		if not ownedBefore then
			owned[weapon.Id] = nil
		end
		task.wait(0.1)
	end
	clearState()
	for _, name in attributes do
		victim:SetAttribute(name, savedAttributes[name])
	end
	attackerCharacter:PivotTo(homeAttacker)
	victimCharacter:PivotTo(homeVictim)
	attackerData.Rebirths, victimData.Rebirths = savedRebirths[1], savedRebirths[2]
	PlayerDataService.SyncTycoon(player)
	PlayerDataService.SyncTycoon(victim)
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

		-- The Studio start grants every weapon at join with no unlock card (a
		-- card there opens over a loading screen: UIKit's "opened without a
		-- card on screen" x5). Silent grant: weapons owned, zero cards sent.
		local ownedBefore = table.clone(data.Weapons)
		PlayerDataService.ResetWeapons(player)
		local cardsBefore = CombatService.GetUnlockCardsSent(player)
		CombatService.DebugSetAll(player, true, true)
		local cardsSent = CombatService.GetUnlockCardsSent(player) - cardsBefore
		local owned = 0
		for _ in data.Weapons do
			owned += 1
		end
		data.Weapons = ownedBefore
		CombatService.RefreshTools(player)
		result(
			cardsSent == 0 and owned == #CombatConfig.Weapons,
			"combat: the join-time weapon grant (Studio start) sends no unlock card",
			("%d cards sent, %d/%d weapons granted"):format(cardsSent, owned, #CombatConfig.Weapons)
		)
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

	-- Tools after a live-server spawn that beat the data load: wipe every
	-- weapon Tool, fire a sync, and all owned ones are back within 1 s; then
	-- the RequestWeaponTools handler adds no duplicates.
	local function countTools(): ({ [string]: number }, number)
		local counts: { [string]: number } = {}
		local total = 0
		local backpack = player:FindFirstChildOfClass("Backpack")
		for _, container in { backpack, player.Character } do
			if container then
				for _, child in container:GetChildren() do
					if child:IsA("Tool") and child:GetAttribute("Weapon") then
						counts[child.Name] = (counts[child.Name] or 0) + 1
						total += 1
					end
				end
			end
		end
		return counts, total
	end
	if player.Character and player:FindFirstChildOfClass("Backpack") then
		local owned = PlayerDataService.GetWeapons(player)
		local ownedCount = 0
		for _ in owned do
			ownedCount += 1
		end
		local backpack = player:FindFirstChildOfClass("Backpack") :: Backpack
		for _, container in { backpack, player.Character :: Instance } do
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("Weapon") then
					child:Destroy()
				end
			end
		end
		local _, afterWipe = countTools()
		PlayerDataService.SyncTycoon(player)
		local deadline = os.clock() + 1
		local counts, total = countTools()
		while total < ownedCount and os.clock() < deadline do
			task.wait(0.1)
			counts, total = countTools()
		end
		local allBack = true
		for id in owned do
			if counts[id] ~= 1 then
				allBack = false
			end
		end
		result(
			afterWipe == 0 and allBack and total == ownedCount,
			"combat: with every weapon Tool destroyed, a SyncTycoon gives all owned ones back within 1 s",
			("owned %d, wiped to %d, back %d"):format(ownedCount, afterWipe, total)
		)
		CombatService.SelfTestRequestWeaponTools(player)
		local countsAgain, totalAgain = countTools()
		local duplicates = false
		for _, n in countsAgain do
			if n > 1 then
				duplicates = true
			end
		end
		result(
			not duplicates and totalAgain == ownedCount,
			"combat: the RequestWeaponTools handler adds no duplicates",
			("owned %d, tools %d"):format(ownedCount, totalAgain)
		)
	else
		result(true, "combat: weapon Tools come back after a wipe (skipped: no character / Backpack)")
	end

	runLaunchSelfTest(player, result)
	runSwingSelfTest(player, result)

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

-- The saved layouts of the older tutorials, case by case, through the same
-- sanitiser a load uses (PlayerDataService.SelfTestMigrateTutorial).
local function runTutorialMigrationSelfTest(result: (boolean, string, string?) -> ())
	local function migrate(raw: { [string]: any }, pulls: number?, fusions: number?): any
		return PlayerDataService.SelfTestMigrateTutorial(raw, pulls, fusions)
	end
	local function lands(label: string, state: any, id: string?, detail: string?)
		local ok: boolean
		if id == nil then
			ok = state.Done == true
		else
			ok = state.Done == false and state.Step == TutorialConfig.IndexOf(id)
		end
		result(ok, "tutorial migration: " .. label .. " -> " .. (id or "Done"), ("%sstep %d, done %s, Ver %d"):format(if detail then detail .. "; " else "", state.Step, tostring(state.Done), state.Ver))
	end

	-- Tutorial 1 (no Ver, 14 steps).
	lands("Tutorial 1 claim", migrate({ Step = 2 }), "claim")
	lands("Tutorial 1 pull", migrate({ Step = 4 }), "pull")
	lands("Tutorial 1 fuse", migrate({ Step = 6 }), "fuse")
	lands("Tutorial 1 multiplier", migrate({ Step = 8 }), nil)
	lands("Tutorial 1 last step", migrate({ Step = 14 }), nil)
	-- Tutorial 2 (Ver 2, 10 steps).
	lands("Tutorial 2 upgrade", migrate({ Ver = 2, Step = 2 }), "pull")
	lands("Tutorial 2 pull2", migrate({ Ver = 2, Step = 4 }), "pull")
	lands("Tutorial 2 pedestals", migrate({ Ver = 2, Step = 5 }), "fuse")
	lands("Tutorial 2 fuse", migrate({ Ver = 2, Step = 6 }), "fuse")
	lands("Tutorial 2 multiplier", migrate({ Ver = 2, Step = 7 }), nil)
	-- Tutorial 3 (Ver 3, 11 steps), every step.
	lands("v3 claim", migrate({ Ver = 3, Step = 1 }), "claim")
	local upgrade = migrate({ Ver = 3, Step = 2, Base = 7 }, 5, 0)
	lands("v3 upgrade", upgrade, "pull")
	result(upgrade.Base == 5, "tutorial migration: v3 upgrade -> the pull step counts from the save's pull counter", ("Base %d, save has 5 pulls"):format(upgrade.Base))
	local pull = migrate({ Ver = 3, Step = 3, Base = 4, PullsGranted = true, FreePulls = 2 }, 4, 0)
	lands("v3 pull (2 free pulls left)", pull, "pull")
	result(pull.Base == 4 and pull.FreePulls == 2, "tutorial migration: v3 pull keeps its base and its 2 free pulls", ("Base %d, free %d"):format(pull.Base, pull.FreePulls))
	local pull2 = migrate({ Ver = 3, Step = 4, Base = 5, PullsGranted = true, FreePulls = 1 }, 5, 0)
	lands("v3 pull2 (1 free pull left)", pull2, "pull")
	result(pull2.Base == 4, "tutorial migration: v3 pull2 counts the pull already made (2 pulls from the step's start)", ("Base %d, want 4"):format(pull2.Base))
	local usedUp = migrate({ Ver = 3, Step = 4, Base = 5, PullsGranted = true, FreePulls = 0 }, 6, 3)
	lands("v3 pull2 (free pulls used up)", usedUp, "fuse")
	result(usedUp.Base == 3, "tutorial migration: ... and the fuse counts from the save's fusions", ("Base %d, save has 3 fusions"):format(usedUp.Base))
	lands("v3 pull (free pulls used up)", migrate({ Ver = 3, Step = 3, PullsGranted = true, FreePulls = 0 }), "fuse")
	lands("v3 pedestals", migrate({ Ver = 3, Step = 5 }), "fuse")
	local fuse = migrate({ Ver = 3, Step = 6, Base = 2 }, 9, 5)
	lands("v3 fuse", fuse, "fuse")
	result(fuse.Base == 2, "tutorial migration: v3 fuse keeps its base", ("Base %d"):format(fuse.Base))
	for step, name in { [7] = "index", [8] = "multiplier", [9] = "events", [10] = "rebirth", [11] = "finish" } do
		lands("v3 " .. name, migrate({ Ver = 3, Step = step }), nil)
	end
	local finished = migrate({ Ver = 3, Step = 11, Done = true })
	result(finished.Done and finished.Step == #TutorialConfig.Steps, "tutorial migration: a finished save stays finished", ("step %d, done %s"):format(finished.Step, tostring(finished.Done)))
	local current = migrate({ Ver = TutorialConfig.DataVersion, Step = 3, Base = 1 }, 99, 99)
	result(current.Step == 3 and current.Base == 1 and current.Ver == TutorialConfig.DataVersion, "tutorial migration: a current-layout save is not touched", ("step %d, base %d"):format(current.Step, current.Base))
	local fresh = migrate({})
	result(fresh.Step == 0 and not fresh.Done, "tutorial migration: a save without a tutorial is 'not decided yet' (step 0)")
end

-- Studio /tutorial reset's extra: forget the tutorial-flow tips (every
-- TutorialConfig.Tips id) and the hourly rival-steal counter.
local function clearTutorialFlowTips(player: Player)
	local ids: { string } = {}
	for _, tip in TutorialConfig.Tips do
		table.insert(ids, tip.Id)
	end
	PlayerDataService.ResetTutorialFlowTips(player, ids)
end

-- The one-time tips (TutorialConfig.PlanTip), pure: never during the
-- tutorial, once each, one at a time.
local function runTipSelfTest(result: (boolean, string, string?) -> ())
	local function state(change: { [string]: any }?): TutorialConfig.TipState
		local base: TutorialConfig.TipState = {
			Done = true,
			Replay = false,
			Quiet = true,
			Showing = false,
			SinceGone = math.huge,
			SinceDone = math.huge,
			Seen = {},
			Cash = 0,
			UpgradeCost = 100,
			MultiplierLevel = 0,
			MultiplierCost = 1000,
			NewIndex = false,
			EventChip = false,
			RebirthProgress = 0,
			RivalLab = false,
		}
		if change then
			for key, value in change do
				(base :: any)[key] = value
			end
		end
		return base
	end
	local triggers: { [string]: { [string]: any } } = {
		tipUpgrade = { Cash = 100 },
		tipMultiplier = { Cash = 1000, UpgradeCost = 1e9 },
		tipIndex = { NewIndex = true },
		tipEvent = { EventChip = true },
		tipRebirth = { RebirthProgress = 0.5 },
		tipRival = { RivalLab = true },
	}
	local everything: { [string]: any } = { Cash = 1000, NewIndex = true, EventChip = true, RebirthProgress = 1, RivalLab = true }
	for _, tip in TutorialConfig.Tips do
		result(TipConfig.IsValid(tip.Id), ("tips: %s is a saved tip id (TipConfig)"):format(tip.Id))
		result(TutorialConfig.PlanTip(state(triggers[tip.Id])) == tip.Id, ("tips: %s fires on its own trigger"):format(tip.Id), tostring(TutorialConfig.PlanTip(state(triggers[tip.Id]))))
		result(TutorialConfig.PlanTip(state(nil)) == nil, ("tips: %s does not fire without it"):format(tip.Id))
		local ran = table.clone(triggers[tip.Id])
		ran.Done = false
		result(TutorialConfig.PlanTip(state(ran)) == nil, ("tips: %s never fires during the tutorial"):format(tip.Id))
	end
	local running = table.clone(everything)
	running.Done = false
	result(TutorialConfig.PlanTip(state(running)) == nil, "tips: none fires while the tutorial runs, whatever is true")
	local replay = table.clone(everything)
	replay.Replay = true
	result(TutorialConfig.PlanTip(state(replay)) == nil, "tips: none fires during a replay")
	local busy = table.clone(everything)
	busy.Quiet = false
	result(TutorialConfig.PlanTip(state(busy)) == nil, "tips: none fires with a card or overlay open")
	local showing = table.clone(everything)
	showing.Showing = true
	result(TutorialConfig.PlanTip(state(showing)) == nil, "tips: at most one on screen")
	local early = table.clone(everything)
	early.SinceDone = TutorialConfig.TipAfterDoneSeconds - 0.1
	result(TutorialConfig.PlanTip(state(early)) == nil, "tips: the first waits a moment after the tutorial ends")
	local gap = table.clone(everything)
	gap.SinceGone = TutorialConfig.TipGapSeconds - 0.1
	local gapDone = table.clone(everything)
	gapDone.SinceGone = TutorialConfig.TipGapSeconds
	result(TutorialConfig.PlanTip(state(gap)) == nil and TutorialConfig.PlanTip(state(gapDone)) ~= nil, ("tips: a second one waits %d s after the first is gone"):format(TutorialConfig.TipGapSeconds))
	local order: { string } = {}
	local seen: { [string]: boolean } = {}
	for _ = 1, #TutorialConfig.Tips + 2 do
		local plan = everything
		local planned = TutorialConfig.PlanTip(state({ Cash = plan.Cash, NewIndex = plan.NewIndex, EventChip = plan.EventChip, RebirthProgress = plan.RebirthProgress, RivalLab = plan.RivalLab, Seen = seen }))
		if not planned then
			break
		end
		table.insert(order, planned)
		seen[planned] = true
	end
	local want: { string } = {}
	for _, tip in TutorialConfig.Tips do
		table.insert(want, tip.Id)
	end
	result(table.concat(order, ",") == table.concat(want, ","), "tips: each fires once, in order, and never again", table.concat(order, ","))
	result(
		TutorialConfig.PlanTip(state({ Cash = 1e9, MultiplierLevel = 1, UpgradeCost = 1e12 })) == nil,
		"tips: the Multiplier tip is for level 0 only"
	)
	result(TutorialConfig.PlanTip(state({ RebirthProgress = 0.49 })) == nil, "tips: the Rebirth tip waits for 50%")
	-- tipRival: ~20 s after "You're ready!", and only with a rival lab in the world.
	local rivalSoon = TutorialConfig.PlanTip(state({ RivalLab = true, SinceDone = TutorialConfig.RivalTipAfterDoneSeconds - 0.1 }))
	local rivalDue = TutorialConfig.PlanTip(state({ RivalLab = true, SinceDone = TutorialConfig.RivalTipAfterDoneSeconds }))
	result(rivalSoon == nil and rivalDue == "tipRival", ("tips: tipRival waits %d s after the tutorial ends"):format(TutorialConfig.RivalTipAfterDoneSeconds), tostring(rivalSoon) .. " / " .. tostring(rivalDue))
	local rivalTip = TutorialConfig.GetTip("tipRival")
	result(
		rivalTip ~= nil and rivalTip.Target == "NearestRivalPedestal" and rivalTip.PromptName == "StealPrompt" and rivalTip.MaxSeconds == 180,
		"tips: tipRival points at the nearest rival pedestal's StealPrompt and lasts 3 min"
	)
	local maxed = state({ Cash = 1e9 })
	maxed.UpgradeCost = nil
	maxed.MultiplierCost = nil
	result(TutorialConfig.PlanTip(maxed) == nil, "tips: nothing fires when everything is maxed")
	-- The steal comes first: a fresh save, tutorial Done, cash for an upgrade
	-- and a rival lab in the world -> tipRival, and nothing else until it is
	-- done plus the usual gap.
	local fresh = { Cash = 100, RivalLab = true }
	local beforeRival = TutorialConfig.PlanTip(state(fresh))
	local rivalReady = table.clone(fresh)
	rivalReady.SinceDone = TutorialConfig.RivalTipAfterDoneSeconds - 0.1
	local waiting = TutorialConfig.PlanTip(state(rivalReady))
	rivalReady.SinceDone = TutorialConfig.RivalTipAfterDoneSeconds
	local firstTip = TutorialConfig.PlanTip(state(rivalReady))
	result(
		beforeRival == "tipRival" and waiting == nil and firstTip == "tipRival",
		"tips: with a rival lab, tipUpgrade does not jump the queue; tipRival is the first tip",
		("%s / %s / %s"):format(tostring(beforeRival), tostring(waiting), tostring(firstTip))
	)
	local afterRival = { Cash = 100, RivalLab = true, Seen = { tipRival = true }, SinceDone = 100, SinceGone = TutorialConfig.TipGapSeconds - 0.1 }
	local tooSoon = TutorialConfig.PlanTip(state(afterRival))
	afterRival.SinceGone = TutorialConfig.TipGapSeconds
	local upgradeNow = TutorialConfig.PlanTip(state(afterRival))
	result(
		tooSoon == nil and upgradeNow == "tipUpgrade",
		("tips: tipUpgrade comes only after tipRival ends + %d s"):format(TutorialConfig.TipGapSeconds),
		tostring(tooSoon) .. " / " .. tostring(upgradeNow)
	)
	local noLab = state({ Cash = 100, RivalLab = false })
	result(
		TutorialConfig.PlanTip(noLab) == "tipUpgrade" and not TutorialConfig.RivalTipFirst(noLab) and noLab.Seen.tipRival == nil,
		"tips: no rival lab -> tipRival is skipped (not marked seen) and the others run"
	)
	local pathRivalTip = TutorialConfig.GetTip("tipRival")
	local upgradeTip = TutorialConfig.GetTip("tipUpgrade")
	result(
		TutorialConfig.PathOn(pathRivalTip, true, false) and TutorialConfig.PathOn(pathRivalTip, true, true) and not TutorialConfig.PathOn(upgradeTip, true, false)
			and TutorialConfig.PathOn(upgradeTip, true, true) and not TutorialConfig.PathOn(nil, false, true),
		"tips: a tip with its own target owns the lit path (the goal path is off while it runs); the goal path follows otherwise"
	)
	-- The HUD reveal table points at real steps, and nothing stays hidden after the last one.
	local lastStep = #TutorialConfig.Steps
	local bad: { string } = {}
	for _, key in TutorialConfig.HudKeys do
		local at = TutorialConfig.HudReveal[key]
		if at == nil or TutorialConfig.IndexOf(at) == nil then
			table.insert(bad, key .. " -> " .. tostring(at))
		elseif not TutorialConfig.IsHudShown(key, lastStep, false, false) then
			table.insert(bad, key .. " hidden at the last step")
		end
	end
	result(#bad == 0, "tutorial: every HUD key reveals at a real step, nothing hidden after the last", table.concat(bad, ", "))
end

-- The presenter's waits for a straight run, from the config (claim -> Done,
-- walking excluded): each step's instruction stays up at least
-- BannerMinSeconds (a Timed step its Seconds), then "Nice!" and the settle;
-- the claim's welcome splash outlasts those two.
local function modelledTutorialSeconds(): number
	local total = TutorialConfig.FirstStepDelay
	for _, step in TutorialConfig.Steps do
		local hold = math.max(TutorialConfig.BannerMinSeconds, step.Seconds or 0)
		local after = TutorialConfig.NiceSeconds + TutorialConfig.SettleSeconds
		if step.Id == "claim" then
			after = math.max(after, TutorialConfig.WelcomeSeconds)
		end
		total += hold + after
	end
	return total
end

-- "You're ready!" must be SEEN: a Timed step's clock counts only the seconds its
-- banner is really on screen (TutorialConfig.AdvanceBannerClock /
-- TimedStepReady, the same primitives TutorialController runs every frame).
-- The scenario of the bug: the finish step starts while the FUSION SUCCESS big
-- card is still open, which holds for 5 s here (an injected clock: 0.1 s
-- frames, no waiting), then closes.
local function runTimedBannerSelfTest(result: (boolean, string, string?) -> ())
	local index = TutorialConfig.IndexOf("finish")
	local step = if index then TutorialConfig.GetStep(index) else nil
	if not step or step.Kind ~= "Timed" then
		result(false, "tutorial: the finish step is a Timed step")
		return
	end
	local hold = TutorialConfig.GetBannerHold(step)
	result(hold >= TutorialConfig.BannerMinSeconds and hold >= (step.Seconds or 0), "tutorial: a Timed banner stays up max(Seconds, BannerMinSeconds) visible seconds", ("%.1f s"):format(hold))

	local function run(coveredSeconds: number): (number?, number, boolean)
		local dt = 0.1
		local visibleSeconds, clock = 0, 0
		local readyWhileCovered = false
		for _ = 1, 600 do
			local visible = clock >= coveredSeconds
			visibleSeconds = TutorialConfig.AdvanceBannerClock(visibleSeconds, dt, visible)
			clock += dt
			if TutorialConfig.TimedStepReady(step, visibleSeconds) then
				if not visible then
					readyWhileCovered = true
				end
				return clock, visibleSeconds, readyWhileCovered
			end
		end
		return nil, visibleSeconds, readyWhileCovered
	end

	local uncoveredAt, uncoveredVisible = run(0)
	result(uncoveredAt ~= nil and math.abs(uncoveredAt - hold) <= 0.25, "tutorial: with nothing in the way the finish step is ready after its hold", ("%s s"):format(tostring(uncoveredAt)))
	local doneAt, visibleAtDone, wasCovered = run(5)
	result(not wasCovered, "tutorial: the finish step never completes behind the open fusion card")
	result(
		doneAt ~= nil and visibleAtDone >= hold - 0.01 and doneAt >= 5 + hold - 0.15,
		"tutorial: with the fusion card open for 5 s, \"You're ready!\" is visible for its full hold before Done",
		("done at %s s, %.1f visible s (hold %.1f)"):format(tostring(doneAt), visibleAtDone, hold)
	)
	result(uncoveredVisible >= hold - 0.01, "tutorial: an uncovered finish step also shows its full hold")

	-- tipRival starts RivalTipAfterDoneSeconds after Done (the end of "You're
	-- ready!"), never sooner, even with everything else in place.
	local function tipAt(sinceDone: number): string?
		return TutorialConfig.PlanTip({
			Done = true,
			Replay = false,
			Quiet = true,
			Showing = false,
			SinceGone = math.huge,
			SinceDone = sinceDone,
			Seen = {},
			Cash = 0,
			UpgradeCost = nil,
			MultiplierLevel = 1,
			MultiplierCost = nil,
			NewIndex = false,
			EventChip = false,
			RebirthProgress = 0,
			RivalLab = true,
		})
	end
	local rivalAfter = TutorialConfig.RivalTipAfterDoneSeconds
	result(
		tipAt(rivalAfter - 0.1) == nil and tipAt(rivalAfter) == "tipRival",
		("tutorial: tipRival starts %d s after Done (the end of \"You're ready!\"), not before"):format(rivalAfter),
		("%s at %.1f s, %s at %.1f s"):format(tostring(tipAt(rivalAfter - 0.1)), rivalAfter - 0.1, tostring(tipAt(rivalAfter)), rivalAfter)
	)
end

local function runTutorialSelfTest(player: Player, result: (boolean, string, string?) -> ())
	result(not TutorialService.ShouldSkipOnJoin(false), "tutorial: a live server (not Studio) never skips the tutorial on join")
	runTimedBannerSelfTest(result)
	result(#TutorialConfig.Steps == 4, "tutorial: four steps", ("%d steps"):format(#TutorialConfig.Steps))
	runTutorialMigrationSelfTest(result)
	runTipSelfTest(result)
	-- /tutorial reset also forgets the tutorial-flow tips and the steal counter
	-- (not the other saved tips); the tester's own are put back after.
	local tipData = PlayerDataService.GetData(player)
	if tipData then
		local savedTips = table.clone(tipData.Tips)
		local savedSteals = table.clone(tipData.RivalSteals)
		for _, tip in TutorialConfig.Tips do
			tipData.Tips[tip.Id] = true
		end
		tipData.Tips.tutorialReplay = true
		table.insert(tipData.RivalSteals, RivalService.Now())
		clearTutorialFlowTips(player)
		local left: { string } = {}
		for _, tip in TutorialConfig.Tips do
			if tipData.Tips[tip.Id] then
				table.insert(left, tip.Id)
			end
		end
		result(#left == 0 and #tipData.RivalSteals == 0 and tipData.Tips.tutorialReplay == true, "tutorial: /tutorial reset clears tipRival, tipUpgrade, tipMultiplier, tipIndex, tipEvent, tipRebirth and the RivalSteals counter, and nothing else", table.concat(left, ","))
		tipData.Tips = savedTips
		tipData.RivalSteals = savedSteals
	end
	-- No lab yet: claim one through the real claim path, release it after.
	local claimState, releaseClaim, claimWhy = TycoonService.SelfTestClaim(player)
	if claimState == "Skip" then
		print(("[SelfTest] SKIP tutorial drive: could not claim a lab (%s)"):format(tostring(claimWhy)))
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

	TutorialService.DebugReset(player)
	PlayerDataService.SyncTycoon(player)
	local function tutorial(): any
		local data = PlayerDataService.GetData(player)
		return data and data.Tutorial
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local home = if root and root:IsA("BasePart") then root.CFrame else nil
	local function fuseTwoCommons()
		local commons = {}
		local owned: { any } = PlayerDataService.GetInventory(player) or {}
		for _, item in owned do
			if item.Tier == TutorialConfig.FreePullTier and #commons < 2 and not PlayerDataService.IsItemCarried(player, item.Uid) then
				table.insert(commons, item.Uid)
			end
		end
		FusionService.HandleFusionRequest(player, { Uids = commons })
	end
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
		-- What the real client shows for this step: the banner, the card (only
		-- Fusing), the HUD set of the table, the weapon bar off at Rebirth 0.
		tutorialProbe(player, { Kind = "Step", StepIndex = index, StepId = step.Id }, result)
		if step.Id == "pull" then
			-- The step needs BOTH free pulls: one is not enough, and the pull
			-- count in the snapshot ("0/2" -> "1/2") follows.
			TycoonService.TutorialPull(player)
			PlayerDataService.SyncTycoon(player)
			local mid = tutorial()
			result(mid ~= nil and mid.Step == index and not mid.Done, "tutorial: one free pull does not finish the pull step", ("step %s"):format(tostring(mid and mid.Step)))
			-- A single pull of a Common opens the big card ("COMMON ORB!").
			tutorialProbe(player, { Kind = "BigCard", Expect = "COMMON ORB!" }, result)
			TycoonService.TutorialPull(player)
		elseif step.Id == "fuse" then
			fuseTwoCommons()
			-- The tutorial fusion (Common x2 -> Rare) now opens the big card too:
			-- the step flow waits for it like the pull's. (The server-driven
			-- fusion has no client request, so the client feeds the same
			-- result through ResultController.)
			tutorialProbe(player, { Kind = "BigCard", Expect = "RARE ORB!", FakeFusion = true }, result)
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
	local t = tutorial()
	result(t ~= nil and t.Done == true and stuck == nil, "tutorial: every step completes in order", ("%s; stuck at %s"):format(table.concat(order, " > "), tostring(stuck)))
	task.wait(1)
	watch:Disconnect()
	result(popups == 0, "tutorial: no shop or deal pop-up while it runs", ("%d shown"):format(popups))

	-- The straight run, timed: the real client presents each step (waits at
	-- their config values), the actions are simulated the moment its banner is
	-- up and the last step is advanced by the client itself. The lab is
	-- already claimed here, so the claim step is skipped: its waits come from
	-- the model, and the model's total must agree with the measured steps.
	local modelled = modelledTutorialSeconds()
	result(modelled < TUTORIAL_BUDGET_SECONDS, ("tutorial: a straight run's waits total under %d s"):format(TUTORIAL_BUDGET_SECONDS), ("%.1f s modelled, claim to Done, walking excluded"):format(modelled))
	TutorialService.DebugReset(player)
	PlayerDataService.SyncTycoon(player)
	local started = os.clock()
	local timedStuck: string? = nil
	local doneAt: number? = nil
	for _ = 1, #TutorialConfig.Steps + 2 do
		local now = tutorial()
		if not now or now.Done then
			doneAt = doneAt or os.clock()
			break
		end
		local index = now.Step
		local step = TutorialConfig.GetStep(index)
		if not step or step.Id == "claim" then
			timedStuck = "claim (needs a claimed lab)"
			break
		end
		local report = askPresented(player, step.Id)
		if not report or not (report.Data and report.Data.Up) then
			timedStuck = step.Id .. " (never presented)"
			break
		end
		if step.Id == "pull" then
			for _ = 1, TutorialConfig.FreePulls do
				TycoonService.TutorialPull(player)
			end
		elseif step.Id == "fuse" then
			fuseTwoCommons()
		else
			-- Timed: the client asks the server itself once its Seconds are up.
			local waitUntil = os.clock() + (step.Seconds or 0) + 8
			while os.clock() < waitUntil do
				local current = tutorial()
				if not current or current.Done or current.Step ~= index then
					break
				end
				task.wait(0.1)
			end
		end
		PlayerDataService.SyncTycoon(player)
		local after = tutorial()
		if after and after.Done then
			doneAt = os.clock()
			break
		end
		if after and after.Step == index then
			timedStuck = step.Id
			break
		end
	end
	local measured = if doneAt then doneAt - started else nil
	local claimWaits = TutorialConfig.BannerMinSeconds + math.max(TutorialConfig.NiceSeconds + TutorialConfig.SettleSeconds, TutorialConfig.WelcomeSeconds)
	result(
		timedStuck == nil and measured ~= nil and measured + claimWaits < TUTORIAL_BUDGET_SECONDS,
		("tutorial: a straight run on the real presenter ends in under %d s"):format(TUTORIAL_BUDGET_SECONDS),
		("pull -> Done %s s measured (result cards close by themselves, nobody taps), plus about %.1f s for the claim step; stuck: %s"):format(
			if measured then ("%.1f"):format(measured) else "?",
			claimWaits,
			tostring(timedStuck)
		)
	)
	print(("[SelfTest] tutorial time: %.1f s modelled (claim to Done, config waits); pull -> Done %s s measured on the real presenter"):format(modelled, if measured then ("%.1f"):format(measured) else "?"))

	if home and root and root:IsA("BasePart") then
		root.CFrame = home
	end
	TutorialService.DebugSetStep(player, 3)
	local resumeOk, resumeDetail = PlayerDataService.SelfTestTutorialRoundTrip(player)
	local resumed = tutorial()
	result(resumeOk and resumed ~= nil and resumed.Step == 3, "tutorial: a save left mid-way resumes at its step", resumeDetail)

	PlayerDataService.SelfTestSwapTutorial(player, saved)
	PlayerDataService.SyncTycoon(player)
	if releaseClaim then
		releaseClaim()
	end
end

-- The playtime gifts restart every visit: a fresh join is 0 s with no claims,
-- a claim before its minutes is refused, a rejoin (RewardService.SelfTestRejoin
-- drops and re-creates the visit's state) is 0 s again with gift 1 claimable
-- again, and an old save's Gifts table loads and is ignored. The cash a claim
-- pays is taken back and the tester's play time put back.
local function runGiftSessionSelfTest(player: Player, result: (boolean, string, string?) -> ())
	local first = GiftConfig.Gifts[1]
	local savedSeconds = RewardService.GetGiftState(player).PlaySeconds
	local savedClaimed = table.clone(RewardService.GetGiftState(player).Claimed)
	local cashStart = PlayerDataService.GetCash(player)

	RewardService.SelfTestRejoin(player)
	local fresh = RewardService.GetGiftState(player)
	result(fresh.PlaySeconds < 2 and #fresh.Claimed == 0, "gifts: a fresh join is 0 s with nothing claimed", ("%.1f s, %d claimed"):format(fresh.PlaySeconds, #fresh.Claimed))

	local early = RewardService.SelfTestClaimGift(player, 1)
	result(early == "NotYet" and #RewardService.GetGiftState(player).Claimed == 0, "gifts: a claim before its minutes is refused", early)

	RewardService.SetGiftSeconds(player, first.Minutes * 60 + 1)
	local granted = RewardService.SelfTestClaimGift(player, 1)
	local again = RewardService.SelfTestClaimGift(player, 1)
	result(granted == "Granted" and again == "Claimed", "gifts: gift 1 claims once at its minutes, then reads claimed", ("%s, then %s"):format(granted, again))

	RewardService.SelfTestRejoin(player)
	local rejoined = RewardService.GetGiftState(player)
	result(rejoined.PlaySeconds < 2 and #rejoined.Claimed == 0, "gifts: after a rejoin the time is 0 s again and nothing is claimed", ("%.1f s, %d claimed"):format(rejoined.PlaySeconds, #rejoined.Claimed))
	RewardService.SetGiftSeconds(player, first.Minutes * 60 + 1)
	local regranted = RewardService.SelfTestClaimGift(player, 1)
	result(regranted == "Granted", "gifts: after a rejoin gift 1 can be claimed again", regranted)

	local loaded, ignored, written = PlayerDataService.SelfTestOldGifts()
	result(loaded and ignored and not written, "gifts: an old save with a Gifts table loads without error and is ignored (never written back)", ("loaded %s, ignored %s, written %s"):format(tostring(loaded), tostring(ignored), tostring(written)))

	-- Put it back: the cash two claims paid, the play time and claims.
	local gained = PlayerDataService.GetCash(player) - cashStart
	if gained > 0 then
		PlayerDataService.SpendCash(player, gained)
	end
	local current = RewardService.GetGiftState(player)
	current.PlaySeconds = savedSeconds
	current.Claimed = savedClaimed
	PlayerDataService.SyncTycoon(player)
end

-- The Secret pity meter (FusionConfig.SecretPityFull): fail charges, the
-- sure success at full, the cap, the save and rebirth round trips, the Fuse
-- panel's bar and 100% on the real client. Mythics are given and everything
-- the section made is removed after; rebirths and the meter are put back.
local function runSecretPitySelfTest(player: Player, result: (boolean, string, string?) -> ())
	local full = FusionConfig.SecretPityFull
	local savedRebirths = PlayerDataService.GetRebirths(player)
	local savedPity = PlayerDataService.GetSecretPity(player)
	local before: { [string]: boolean } = {}
	local owned: { any } = PlayerDataService.GetInventory(player) or {}
	for _, item in owned do
		before[item.Uid] = true
	end
	local function countTier(tier: string): number
		local total = 0
		local current: { any } = PlayerDataService.GetInventory(player) or {}
		for _, item in current do
			if item.Tier == tier and not before[item.Uid] then
				total += 1
			end
		end
		return total
	end
	local mythic, legendary = ItemConfig.PickRandomOfTier("Mythic"), ItemConfig.PickRandomOfTier("Legendary")
	if not mythic or not legendary then
		result(false, "secret pity: ItemConfig has a Mythic and a Legendary to fuse")
		return
	end
	if savedRebirths < RebirthConfig.SecretFusionRebirths then
		PlayerDataService.SetRebirths(player, RebirthConfig.SecretFusionRebirths)
	end
	PlayerDataService.SetSecretPity(player, 0)

	-- Fuses `count` fresh orbs of `item`'s tier with the worst roll (a fail
	-- unless the meter is full). Waits out the fusion cooldown first.
	local function giveMythics(count: number): ()
		for _ = 1, count do
			PlayerDataService.AddItem(player, mythic.Id, "Mythic", nil, nil)
		end
		RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	end
	local function fuse(item: any, count: number): ()
		local uids: { string } = {}
		for _ = 1, count do
			local entry = PlayerDataService.AddItem(player, item.Id, item.Tier, nil, nil)
			if entry then
				table.insert(uids, entry.Uid)
			end
		end
		task.wait(1.7)
		FusionService.HandleFusionRequest(player, { Uids = uids })
	end
	FusionService.SelfTestSetRoll(1 - 1e-9)

	-- The charge is the input count; the meter stops at full.
	result(FusionConfig.GetPityCharge(6) == 6 and FusionConfig.GetPityCharge(2) == 2, "secret pity: a 6-input fail charges 6 points, a 2-input fail 2")
	fuse(mythic, 2)
	local afterPair = PlayerDataService.GetSecretPity(player)
	result(afterPair == math.min(full, 2), "secret pity: a failed 2-input Mythic fusion adds 2 points", ("meter %d"):format(afterPair))
	PlayerDataService.SetSecretPity(player, 0)
	fuse(mythic, 6)
	local afterSix = PlayerDataService.GetSecretPity(player)
	result(afterSix == math.min(full, 6), "secret pity: a failed 6-input Mythic fusion adds 6 points (the meter stops at full)", ("meter %d of %d"):format(afterSix, full))
	PlayerDataService.SetSecretPity(player, 0)
	fuse(legendary, 2)
	result(PlayerDataService.GetSecretPity(player) == 0, "secret pity: a failed Legendary fusion leaves the meter alone", ("meter %d"):format(PlayerDataService.GetSecretPity(player)))
	result(countTier("Secret") == 0, "secret pity: below full the worst roll still fails (no Secret yet)")

	-- Round trips with a part-full meter.
	local part = math.max(1, full - 2)
	PlayerDataService.SetSecretPity(player, part)
	local afterSave, afterRebirth = PlayerDataService.SelfTestPityPersists(player)
	local roundOk, roundDetail = PlayerDataService.SelfTestRoundTrip(player)
	result(afterSave == part and roundOk, "secret pity: the meter survives toDisk -> reconcile", ("after save %d, %s"):format(afterSave, tostring(roundDetail)))
	result(afterRebirth == part, "secret pity: a rebirth does not reset the meter", ("after rebirth %d"):format(afterRebirth))
	local fingerprint = PlayerDataService.SelfTestFingerprint(player)
	PlayerDataService.SetSecretPity(player, part - 1)
	result(PlayerDataService.SelfTestFingerprint(player) ~= fingerprint, "secret pity: the remote-fuzz fingerprint covers the meter")

	-- The cap, then the sure success at full.
	PlayerDataService.SetSecretPity(player, full - 1)
	fuse(mythic, 6)
	result(PlayerDataService.GetSecretPity(player) == full, "secret pity: the meter stops at full", ("meter %d of %d"):format(PlayerDataService.GetSecretPity(player), full))
	local secretsBefore = countTier("Secret")
	local showMeter = PlayerDataService.GetSecretPity(player)
	-- The client's view at full (the panel is probed before the fuse eats it).
	PlayerDataService.SyncTycoon(player)
	tutorialProbe(player, { Kind = "ClearScreen", Label = "the pity fusions", Report = false }, result)
	giveMythics(2)
	tutorialProbe(player, { Kind = "FuseMeter", Pity = showMeter, Full = true }, result)
	fuse(mythic, 2)
	result(countTier("Secret") == secretsBefore + 1, "secret pity: at full the next Mythic fusion succeeds even on the worst roll", ("Secrets %d -> %d"):format(secretsBefore, countTier("Secret")))
	result(PlayerDataService.GetSecretPity(player) == 0, "secret pity: a Secret from fusion resets the meter to 0", ("meter %d"):format(PlayerDataService.GetSecretPity(player)))
	FusionService.SelfTestSetRoll(nil)

	-- Not full: the panel shows the server's value.
	PlayerDataService.SetSecretPity(player, part)
	PlayerDataService.SyncTycoon(player)
	tutorialProbe(player, { Kind = "ClearScreen", Label = "the pity fusion", Report = false }, result)
	giveMythics(2)
	tutorialProbe(player, { Kind = "FuseMeter", Pity = part, Full = false }, result)

	-- Put it all back.
	local added: { string } = {}
	local current: { any } = PlayerDataService.GetInventory(player) or {}
	for _, item in current do
		if not before[item.Uid] then
			table.insert(added, item.Uid)
		end
	end
	PlayerDataService.RemoveItemsByUid(player, added)
	PlayerDataService.SetSecretPity(player, savedPity)
	PlayerDataService.SetRebirths(player, savedRebirths)
	PlayerDataService.SyncTycoon(player)
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
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

	-- Lab chain "Fuse a Mythic" (Polish 12): a Mythic fused BEFORE the player
	-- reached the step counts (achievement kinds count from 0), the step is
	-- done at once, the QUESTS badge shows, and the claim grants the glove.
	local weapons = PlayerDataService.GetWeapons(player)
	local hadGlove = weapons.SlapGlove == true
	weapons.SlapGlove = nil
	local mythics = PlayerDataService.GetStat(player, "Fused_Mythic")
	if mythics < 1 then
		PlayerDataService.AddStat(player, "Fused_Mythic", 1 - mythics)
	end
	QuestService.DebugSetChain(player, 3)
	local chainQuests = PlayerDataService.GetQuestState(player)
	result(
		chainQuests ~= nil and chainQuests.ChainBase == 0 and QuestService.WhyNotClaim(player, "chain") == nil,
		"quests: a chain step 'Fuse a Mythic' is complete at once when a Mythic was fused before it started",
		table.concat(QuestService.GetStatusLines(player), " | ")
	)
	PlayerDataService.SyncTycoon(player)
	task.wait(0.6)
	tutorialProbe(player, { Kind = "QuestBadge" }, result)
	local claimed, claimReason = QuestService.Claim(player, "chain")
	result(
		claimed and PlayerDataService.GetWeapons(player).SlapGlove == true,
		"quests: claiming 'Fuse a Mythic' grants the Slap Glove",
		("claimed %s, reason %s"):format(tostring(claimed), tostring(claimReason))
	)
	weapons.SlapGlove = if hadGlove then true else nil
	CombatService.RefreshTools(player)

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

-- AUTO-FILL on a tier the tester holds nothing of: 6 Golden orbs fill the
-- chamber (same stack, toast); 1 Golden + 1 Rainbow select nothing and show
-- the "not enough" toast. The test orbs are removed after.
local function runAutoFillSelfTest(player: Player, result: (boolean, string, string?) -> ())
	local rebirths = PlayerDataService.GetRebirths(player)
	local held: { [string]: boolean } = {}
	local owned: { any } = PlayerDataService.GetInventory(player) or {}
	for _, item in owned do
		held[item.Tier] = true
	end
	local tier: string? = nil
	for _, candidate in FusionConfig.TierOrder do
		if not held[candidate] and FusionConfig.CanFuseTierFor(candidate, rebirths) and ItemConfig.PickRandomOfTier(candidate) then
			tier = candidate
			break
		end
	end
	if not tier then
		print("[SelfTest] SKIP auto-fill: every fusable tier already holds items")
		return
	end
	local def = ItemConfig.PickRandomOfTier(tier) :: any
	local function add(mutation: string?, count: number): { string }
		local uids = {}
		for _ = 1, count do
			local item = PlayerDataService.AddItem(player, def.Id, tier :: string, mutation)
			if item then
				table.insert(uids, item.Uid)
			end
		end
		return uids
	end
	-- Only plain orbs: no tip.
	local plain = add(nil, 3)
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	tutorialProbe(player, { Kind = "FuseTip", Tier = tier, Expect = "" }, result)
	PlayerDataService.RemoveItemsByUid(player, plain)
	-- The more-orbs odds line: 2 of 6 plain orbs in the chamber name the next
	-- orb and a full chamber; a full chamber or nothing more owned hides it.
	local oddsOrbs = add(nil, FusionConfig.MaxFusionInputs)
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	local sparkDef = QuestConfig.PowerUps.FusionSpark
	local oddsBonus = EventState.GetFusionSuccessBonus() + (if PlayerDataService.IsArmed(player, sparkDef.Key) then sparkDef.FusionBonus or 0 else 0)
	local function oddsPercent(count: number): string
		return FusionConfig.FormatPercent(FusionConfig.GetFusionChance(tier :: string, count, oddsBonus) * 100) .. "%"
	end
	tutorialProbe(player, {
		Kind = "FuseOdds",
		Tier = tier,
		Chamber = 2,
		Expect = ("Add more %s for better odds: 3 → %s, 6 → %s"):format(GoalSteps.Plural(tier), oddsPercent(3), oddsPercent(6)),
	}, result)
	tutorialProbe(player, { Kind = "FuseOdds", Tier = tier, Chamber = FusionConfig.MaxFusionInputs, Expect = "" }, result)
	PlayerDataService.RemoveItemsByUid(player, { oddsOrbs[3], oddsOrbs[4], oddsOrbs[5], oddsOrbs[6] })
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	tutorialProbe(player, { Kind = "FuseOdds", Tier = tier, Chamber = 2, Expect = "" }, result)
	PlayerDataService.RemoveItemsByUid(player, { oddsOrbs[1], oddsOrbs[2] })
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	-- Three Golden orbs: the tip names GOLDEN, and goes once an orb is in.
	local tipGoldens = add("Golden", 3)
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	tutorialProbe(player, { Kind = "FuseTip", Tier = tier, Expect = "GOLDEN" }, result)
	PlayerDataService.RemoveItemsByUid(player, tipGoldens)
	local goldens = add("Golden", FusionConfig.MaxFusionInputs)
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	tutorialProbe(player, { Kind = "AutoFillMutated", Tier = tier, Expect = "Fill", Count = FusionConfig.MaxFusionInputs }, result)
	PlayerDataService.RemoveItemsByUid(player, goldens)
	local pair = add("Golden", 1)
	for _, uid in add("Rainbow", 1) do
		table.insert(pair, uid)
	end
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	tutorialProbe(player, { Kind = "AutoFillMutated", Tier = tier, Expect = "None", Count = 0 }, result)
	PlayerDataService.RemoveItemsByUid(player, pair)
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
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

-- The "own a tier" goals' next action (GoalSteps through GoalService.ComputeStep)
-- on stubbed inventories: line, hint and the arrow's target. Pure: nothing
-- of the tester's is changed (the stub inventory and cash are passed in).
local function runGoalStepsSelfTest(player: Player, result: (boolean, string, string?) -> ())
	local goalsById: { [string]: any } = {}
	for _, goal in GoalConfig.Goals do
		goalsById[goal.Id] = goal
	end
	local sparkDef = QuestConfig.PowerUps.FusionSpark
	local bonus = EventState.GetFusionSuccessBonus() + (if PlayerDataService.IsArmed(player, sparkDef.Key) then sparkDef.FusionBonus or 0 else 0)
	local function percent(tier: string, count: number): string
		return FusionConfig.FormatPercent(FusionConfig.GetFusionChance(tier, count, bonus) * 100) .. "%"
	end
	local RICH = 1e30 -- cash that affords any pull
	local function check(name: string, goalId: string, counts: { [string]: number }, cash: number, want: { Line: string, Hint: string?, Target: string })
		local inventory: { { Uid: string, Tier: string } } = {}
		for tier, count in counts do
			for index = 1, count do
				table.insert(inventory, { Uid = ("selftest-%s-%d"):format(tier, index), Tier = tier })
			end
		end
		local step = GoalService.ComputeStep(player, goalsById[goalId], inventory, cash)
		if not step then
			result(false, "goal steps: " .. name, "no step")
			return
		end
		local lines = GoalSteps.Format(step)
		local line = GoalSteps.Plain(lines.Line)
		local hint = if lines.Hint then GoalSteps.Plain(lines.Hint) else nil
		result(
			line == want.Line and hint == want.Hint and step.Target == want.Target,
			"goal steps: " .. name,
			("line '%s' hint '%s' target %s; wanted '%s' '%s' %s"):format(line, tostring(hint), step.Target, want.Line, tostring(want.Hint), want.Target)
		)
	end

	-- own_legendary (Epics make it).
	check("Legendary with 1 Epic and nothing to fuse says pull", "own_legendary", { Epic = 1 }, RICH, {
		Line = "Pull from the Gacha for more orbs (1 / 2 Epic)",
		Target = "GachaStation",
	})
	check("Legendary with 1 Epic and 3 Rares says fuse the Rares", "own_legendary", { Epic = 1, Rare = 3 }, RICH, {
		Line = "Fuse Rares to make Epics (1 / 2 Epic)",
		Target = "FusionMachine",
	})
	check("Legendary with 3 Epics says fuse them, with the odds hint", "own_legendary", { Epic = 3 }, RICH, {
		Line = ("Fuse your 3 Epics: %s"):format(percent("Epic", 3)),
		Hint = ("More Epics = better odds (6 → %s)"):format(percent("Epic", 6)),
		Target = "FusionMachine",
	})
	check("Legendary with 6 Epics has no odds hint", "own_legendary", { Epic = 6 }, RICH, {
		Line = ("Fuse your 6 Epics: %s"):format(percent("Epic", 6)),
		Target = "FusionMachine",
	})
	check("Legendary with 9 Epics fuses 6", "own_legendary", { Epic = 9 }, RICH, {
		Line = ("Fuse your 6 Epics: %s"):format(percent("Epic", 6)),
		Target = "FusionMachine",
	})
	-- The earn-cash line needs no free pulls to hide behind.
	if PlayerDataService.GetTutorialFreePulls(player) > 0 then
		print("[SelfTest] SKIP goal steps earn-cash: the tester still has tutorial free pulls")
	else
		local cost = TycoonConfig.GetGachaPullCost(PlayerDataService.GetGachaPulls(player), PlayerDataService.GetSteadyIncomePerSecond(player))
		check("Legendary with 1 Epic and $0 says earn cash, arrow at UPGRADES", "own_legendary", { Epic = 1 }, 0, {
			Line = ("Earn cash for your next pull (%s)"):format(NumberFormat.Money(cost)),
			Target = "ui:Upgrades",
		})
	end

	-- One case for each of the other tier goals.
	check("Rare with 3 Commons", "own_rare", { Common = 3 }, RICH, {
		Line = ("Fuse your 3 Commons: %s"):format(percent("Common", 3)),
		Hint = ("More Commons = better odds (6 → %s)"):format(percent("Common", 6)),
		Target = "FusionMachine",
	})
	check("Rare with 1 Common says pull", "own_rare", { Common = 1 }, RICH, {
		Line = "Pull from the Gacha for more orbs (1 / 2 Common)",
		Target = "GachaStation",
	})
	check("Epic with 1 Rare and 4 Commons", "own_epic", { Rare = 1, Common = 4 }, RICH, {
		Line = "Fuse Commons to make Rares (1 / 2 Rare)",
		Target = "FusionMachine",
	})
	check("Epic with 2 Rares", "own_epic", { Rare = 2 }, RICH, {
		Line = ("Fuse your 2 Rares: %s"):format(percent("Rare", 2)),
		Hint = ("More Rares = better odds (6 → %s)"):format(percent("Rare", 6)),
		Target = "FusionMachine",
	})
	check("Mythic with 2 Legendaries", "own_mythic", { Legendary = 2 }, RICH, {
		Line = ("Fuse your 2 Legendaries: %s"):format(percent("Legendary", 2)),
		Hint = ("More Legendaries = better odds (6 → %s)"):format(percent("Legendary", 6)),
		Target = "FusionMachine",
	})
	check("Mythic with 1 Legendary and 2 Epics", "own_mythic", { Legendary = 1, Epic = 2 }, RICH, {
		Line = "Fuse Epics to make Legendaries (1 / 2 Legendary)",
		Target = "FusionMachine",
	})
	-- Goals that aren't "own a tier" carry no step.
	result(GoalService.ComputeStep(player, goalsById.claim_base, {}, RICH) == nil, "goal steps: a goal that isn't 'own a tier' has no step")
end

-- The gacha price cap (TycoonConfig.GetGachaPullCost): the cap and the
-- early climb, steady income ignoring everything temporary or bought, and
-- the x10 price being the sum of the next ten. Pure maths on the tester's
-- own income inputs; nothing is changed.
local function runGachaPriceSelfTest(player: Player, result: (boolean, string, string?) -> ())
	local cap = TycoonConfig.GachaMaxIncomeSeconds
	local capped = TycoonConfig.GetGachaPullCost(1000, 1e6)
	result(capped == cap * 1e6, ("gacha price: pull 1000 at $1M/s costs %d s of income"):format(cap), ("cost %s"):format(tostring(capped)))
	local first = TycoonConfig.GetGachaPullCost(0, 1e9)
	result(first == TycoonConfig.GachaBasePullCost, "gacha price: pull 0 costs the base price however rich you are", ("cost %s"):format(tostring(first)))
	local broke = TycoonConfig.GetGachaPullCost(500, 0)
	result(broke == TycoonConfig.GachaBasePullCost, "gacha price: the cap never goes under the base price (no income)", ("cost %s"):format(tostring(broke)))
	local sum = 0
	for offset = 0, TycoonConfig.MultiPullCount - 1 do
		sum += TycoonConfig.GetGachaPullCost(300 + offset, 5e6)
	end
	local multi = TycoonConfig.GetGachaMultiPullCost(300, TycoonConfig.MultiPullCount, 5e6)
	result(multi == sum and multi <= cap * 5e6 * TycoonConfig.MultiPullCount, "gacha price: x10 is the sum of the next ten prices, each under the cap", ("x10 %s, sum %s"):format(tostring(multi), tostring(sum)))
	local inputs = PlayerDataService.GetIncomeInputs(player)
	if not inputs then
		result(false, "gacha price: steady income ignores boosts and passes", "no income inputs for the tester")
		return
	end
	local steady = TycoonConfig.GetSteadyIncomePerSecond(inputs)
	local boosted = table.clone(inputs)
	boosted.BoostMultiplier = 2
	boosted.PassMultiplier = 2
	boosted.OverclockMultiplier = 3
	boosted.EventGeneratorMultiplier = 4
	local steadyBoosted = TycoonConfig.GetSteadyIncomePerSecond(boosted)
	local live = TycoonConfig.GetPassiveCashPerSecond(boosted)
	result(
		steadyBoosted == steady and (live > TycoonConfig.GetPassiveCashPerSecond(inputs) or steady == 0),
		"gacha price: a timed boost, an event, the Overclock or a 2x Cash pass does not change the steady income (the pull price)",
		("steady %.3f, with boosts %.3f, live income with boosts %.3f"):format(steady, steadyBoosted, live)
	)
	local pulls = PlayerDataService.GetGachaPulls(player)
	result(
		TycoonConfig.GetGachaPullCost(pulls, steady) == TycoonConfig.GetGachaPullCost(pulls, steadyBoosted)
			and PlayerDataService.GetSteadyIncomePerSecond(player) == steady,
		"gacha price: the server's steady income is the one built from the same inputs",
		("pulls %d, steady %.3f"):format(pulls, steady)
	)
end

-- The Gacha Pad card (client-built, own pad): its numbers against the
-- server's luck now and under an admin-luck event (no persistent state is
-- touched: Workspace attributes, restored), then its buttons.
local function runGachaCardSelfTest(player: Player, result: (boolean, string, string?) -> ())
	-- The card only exists for a claimed lab.
	local claimState, releaseClaim, claimWhy = TycoonService.SelfTestClaim(player)
	if claimState == "Skip" then
		result(false, "gacha card: a claimed lab to test on", ("could not claim a lab for the tester: %s"):format(tostring(claimWhy)))
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

	-- Start away from the pad (the card closed); the CLIENT then steps onto the
	-- pad and checks the frame after the card opens (all 6 tiles laid out).
	root.CFrame = away
	task.wait(0.8)
	tutorialProbe(player, { Kind = "GachaOpen" }, result)
	-- On the pad: wait 0.4 s, then everything is read from the card's tree.
	root.CFrame = onPad
	task.wait(0.4)
	-- What the server would charge now: the card must show the same.
	local chargePulls = PlayerDataService.GetGachaPulls(player)
	local chargeSteady = PlayerDataService.GetSteadyIncomePerSecond(player)
	local serverCost = TycoonConfig.GetGachaPullCost(chargePulls, chargeSteady)
	local serverMultiCost = TycoonConfig.GetGachaMultiPullCost(chargePulls, TycoonConfig.MultiPullCount, chargeSteady)
	tutorialProbe(player, { Kind = "GachaCard", Label = "luck as is", Luck = PlayerDataService.GetLuck(player), ServerCost = serverCost, ServerMultiCost = serverMultiCost }, result)
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
	-- What the open card hides (the GACHA label, the VIP chip).
	tutorialProbe(player, { Kind = "GachaCovers" }, result)
	-- Standing on the pad: the card fits on screen and a turn never moves it.
	tutorialProbe(player, { Kind = "GachaOnPad", Phone = false }, result)
	tutorialProbe(player, { Kind = "GachaOnPad", Phone = true }, result)
	-- Approach: 8 studs in front of the pad on the walkway side (toward the
	-- walkway line, plot-local x = 0), the card opens above the pad on screen.
	local plotOrigin = plot:FindFirstChild("PlotOrigin")
	local originCFrame = if plotOrigin and plotOrigin:IsA("BasePart") then plotOrigin.CFrame else plot:GetPivot()
	local towardWalkway = originCFrame:VectorToWorldSpace(Vector3.new(-1, 0, 0))
	root.CFrame = CFrame.lookAt(pad.Position + towardWalkway * 8 + Vector3.new(0, pad.Size.Y / 2 + 3, 0), pad.Position + Vector3.new(0, pad.Size.Y / 2 + 3, 0))
	task.wait(0.8)
	tutorialProbe(player, { Kind = "GachaApproach", Phone = false }, result)
	tutorialProbe(player, { Kind = "GachaApproach", Phone = true }, result)

	-- 25 studs away: the card pops out and the small GACHA label shows.
	root.CFrame = away
	task.wait(0.6)
	tutorialProbe(player, { Kind = "GachaFar" }, result)
	-- Back on the pad: it pops in again.
	root.CFrame = onPad
	task.wait(0.5)
	tutorialProbe(player, { Kind = "GachaBack" }, result)

	-- The server half of the key bar: the remotes' shared function. Cash is
	-- spent and given back; nothing is pulled.
	local freePulls = PlayerDataService.GetTutorialFreePulls(player)
	if freePulls > 0 then
		result(true, "gacha keys: RequestGachaPull / Auto pull refusals (skipped: the tester still has tutorial free pulls)")
	else
		local cash = PlayerDataService.GetCash(player)
		local cost = TycoonConfig.GetGachaPullCost(PlayerDataService.GetGachaPulls(player), PlayerDataService.GetSteadyIncomePerSecond(player))
		TycoonService.SelfTestFreezeIncome(player, true) -- the "$0" steps below need cash that stays put
		-- 25 studs away: refused, and Auto pull will not start.
		root.CFrame = away
		task.wait(0.4)
		-- "Costs nothing": the pull count and the inventory are unchanged and
		-- cash did not drop (it may rise: passive income ticks during the wait).
		local function inventoryCount(): number
			local inventory = PlayerDataService.GetInventory(player)
			return if inventory then #inventory else 0
		end
		local pullsBefore, itemsBefore, cashBefore = PlayerDataService.GetGachaPulls(player), inventoryCount(), PlayerDataService.GetCash(player)
		local okFar, reasonFar = TycoonService.RequestGachaPull(player, 1)
		local pullsAfter, itemsAfter, cashAfter = PlayerDataService.GetGachaPulls(player), inventoryCount(), PlayerDataService.GetCash(player)
		result(
			not okFar and reasonFar == "TooFar" and pullsAfter == pullsBefore and itemsAfter == itemsBefore and cashAfter >= cashBefore,
			"gacha keys: RequestGachaPull from 25 studs is refused (TooFar) and costs nothing",
			("ok %s, reason %s, pulls %d -> %d, items %d -> %d, cash %s -> %s"):format(tostring(okFar), tostring(reasonFar), pullsBefore, pullsAfter, itemsBefore, itemsAfter, tostring(cashBefore), tostring(cashAfter))
		)
		TycoonService.SetAutoPull(player, true)
		local farStop = TycoonService.GetAutoPullStop(player)
		result(not TycoonService.IsAutoPulling(player) and farStop ~= nil and farStop.Reason == "TooFar", "gacha keys: Auto pull from 25 studs does not start (TooFar)", ("running %s, stop %s"):format(tostring(TycoonService.IsAutoPulling(player)), if farStop then farStop.Reason else "none"))
		-- On the pad with $0: the pull is refused for cash, Auto stops at once
		-- and says why (with the price), a bad count is refused.
		root.CFrame = onPad
		task.wait(0.4)
		PlayerDataService.SpendCash(player, PlayerDataService.GetCash(player))
		local okBroke, reasonBroke, costBroke = TycoonService.RequestGachaPull(player, 1)
		result(not okBroke and reasonBroke == "InsufficientCash" and costBroke == cost, "gacha keys: RequestGachaPull at $0 is refused (InsufficientCash, with the price)", ("ok %s, reason %s, cost %s (price %s)"):format(tostring(okBroke), tostring(reasonBroke), tostring(costBroke), tostring(cost)))
		TycoonService.SetAutoPull(player, true)
		task.wait(0.5)
		local stop = TycoonService.GetAutoPullStop(player)
		-- Auto pull is x10 per cycle: the price it reports is the x10 price.
		local autoCost = TycoonConfig.GetGachaMultiPullCost(PlayerDataService.GetGachaPulls(player), TycoonConfig.MultiPullCount, PlayerDataService.GetSteadyIncomePerSecond(player))
		result(
			not TycoonService.IsAutoPulling(player) and stop ~= nil and stop.Reason == "InsufficientCash" and stop.Cost == autoCost,
			"gacha keys: Auto pull at $0 stops at once with the reason (InsufficientCash, the x10 price)",
			("running %s, stop %s, cost %s (x10 price %s), cash %s"):format(tostring(TycoonService.IsAutoPulling(player)), if stop then stop.Reason else "none", tostring(if stop then stop.Cost else nil), tostring(autoCost), tostring(PlayerDataService.GetCash(player)))
		)
		local okCount, reasonCount = TycoonService.RequestGachaPull(player, 5)
		result(not okCount and reasonCount == "BadCount", "gacha keys: RequestGachaPull { Count = 5 } is refused (BadCount)", ("ok %s, reason %s"):format(tostring(okCount), tostring(reasonCount)))
		-- Auto pull is x10 per cycle: cash for exactly 20 pulls (two cycles),
		-- then it stops for cash. Each cycle shows the 10-pull card on the
		-- client, and no two cycles start within AutoPullMinSeconds. (Studio
		-- Mock store only: this really pulls 20 items.)
		local pulls0 = PlayerDataService.GetGachaPulls(player)
		local steady0 = PlayerDataService.GetSteadyIncomePerSecond(player)
		local cycle1 = TycoonConfig.GetGachaMultiPullCost(pulls0, TycoonConfig.MultiPullCount, steady0)
		local cycle2 = TycoonConfig.GetGachaMultiPullCost(pulls0 + TycoonConfig.MultiPullCount, TycoonConfig.MultiPullCount, steady0)
		tutorialProbe(player, { Kind = "AutoReset" }, result)
		-- Cash for EXACTLY two cycles: passive income paused for the run and
		-- whatever the save has left is spent first, so nothing else pays.
		TycoonService.SelfTestFreezeIncome(player, true)
		PlayerDataService.SpendCash(player, PlayerDataService.GetCash(player))
		-- (+2% of a cycle: the first 10 items may move the steady income a little.)
		PlayerDataService.AddCash(player, cycle1 + cycle2 + math.floor(cycle2 * 0.02))
		-- The server test owns the tester's spot: put them on the pad again
		-- after the client probe, and let that replicate before Auto starts.
		root.CFrame = onPad
		task.wait(0.4)
		local startOffPad = Vector3.new(root.Position.X - pad.Position.X, 0, root.Position.Z - pad.Position.Z).Magnitude
		TycoonService.SetAutoPull(player, true)
		local autoStarted = os.clock()
		while TycoonService.IsAutoPulling(player) and os.clock() - autoStarted < 40 do
			task.wait(0.1)
			-- Cycle 1's items land on the pedestals and raise the steady income,
			-- which the price cap follows: refund cycle 2 at the price now (the
			-- game's pricing stays as it is; only the test's cash is re-set).
			if #TycoonService.GetAutoPullLog(player) == 1 then
				local price = TycoonConfig.GetGachaMultiPullCost(PlayerDataService.GetGachaPulls(player), TycoonConfig.MultiPullCount, PlayerDataService.GetSteadyIncomePerSecond(player))
				local want = price + math.floor(price * 0.02)
				local have = PlayerDataService.GetCash(player)
				if have ~= want then
					PlayerDataService.SpendCash(player, have)
					PlayerDataService.AddCash(player, want)
				end
			end
		end
		local autoStop = TycoonService.GetAutoPullStop(player)
		local autoLog = TycoonService.GetAutoPullLog(player)
		local gapOk = #autoLog == 2 and autoLog[2] - autoLog[1] >= GachaConfig.AutoPullMinSeconds - 0.05
		result(
			#autoLog == 2 and autoStop ~= nil and autoStop.Reason == "InsufficientCash",
			"gacha keys: Auto pull ran exactly 2 x10 cycles with cash for 20 pulls, then stopped (InsufficientCash)",
			("%d cycles, stop %s, pulls %d -> %d, tester %.1f studs flat from the pad when Auto started"):format(#autoLog, if autoStop then autoStop.Reason else "none (still running)", pulls0, PlayerDataService.GetGachaPulls(player), startOffPad)
		)
		result(gapOk, ("gacha keys: no Auto pull cycle starts within %ds of the previous one"):format(GachaConfig.AutoPullMinSeconds), ("gap %s"):format(if #autoLog == 2 then ("%.2f s"):format(autoLog[2] - autoLog[1]) else "n/a"))
		tutorialProbe(player, { Kind = "AutoCards", Expect = #autoLog }, result)
		TycoonService.SetAutoPull(player, false)
		TycoonService.SelfTestFreezeIncome(player, false)
		PlayerDataService.SpendCash(player, PlayerDataService.GetCash(player))
		PlayerDataService.AddCash(player, cash)
		PlayerDataService.SyncTycoon(player)
	end

	root.CFrame = home
	if releaseClaim then
		releaseClaim()
	end
end

-- The effects tray (client UI/EffectsTray): a Luck Potion and 2 Safe Fusion
-- tokens granted through the data layer the shop grant uses, then the client
-- reports what the tray shows at both layouts. Everything is put back.
local function runEffectsTraySelfTest(player: Player, result: (boolean, string, string?) -> ())
	local tokensBefore = PlayerDataService.GetSafeFusionTokens(player)
	local luckBefore = PlayerDataService.GetBoostSeconds(player, "Luck")
	PlayerDataService.AddBoostSeconds(player, "Luck", ShopConfig.LuckPotionSeconds)
	PlayerDataService.AddSafeFusionTokens(player, 2)
	-- Speed Boots: the attribute QuestService publishes to the client on a sync.
	local bootsBefore = player:GetAttribute("SpeedBootsUntil")
	player:SetAttribute("SpeedBootsUntil", Workspace:GetServerTimeNow() + 120)
	PlayerDataService.SyncTycoon(player)
	task.wait(0.8)
	tutorialProbe(player, { Kind = "EffectsTray", Tokens = tokensBefore + 2 }, result)
	player:SetAttribute("SpeedBootsUntil", bootsBefore)
	PlayerDataService.AddSafeFusionTokens(player, -2)
	local added = PlayerDataService.GetBoostSeconds(player, "Luck") - luckBefore
	PlayerDataService.AddBoostSeconds(player, "Luck", -added)
	PlayerDataService.SyncTycoon(player)
end

-- The friend boost (FriendService / FriendConfig): the friendship call is
-- swapped for a stub and fake peers are counted, so one tester covers 0, 2
-- and 6 friends and a failing call. Steady income and offline pay must not
-- move; the client reports the chip. The real check is put back at the end.
local function runFriendBoostSelfTest(player: Player, result: (boolean, string, string?) -> ())
	local function fakePeers(count: number): { Player }
		local peers: { Player } = {}
		for index = 1, count do
			local fake: any = { UserId = -9000 - index, Name = "Friend" .. index, DisplayName = "Friend" .. index }
			table.insert(peers, fake)
		end
		return peers
	end
	local function near(a: number, b: number): boolean
		return math.abs(a - b) <= 1e-9 * math.max(1, math.abs(a), math.abs(b))
	end
	local function friendsRow(inputs: TycoonConfig.IncomeInputs): number?
		for _, part in TycoonConfig.GetIncomeBreakdown(inputs) do
			if part.Label == "Friends" then
				return part.Value
			end
		end
		return nil
	end
	local function chip(percent: number)
		task.wait(0.8)
		tutorialProbe(player, { Kind = "FriendChip", Percent = percent }, result)
	end

	local allFriends = function(): boolean
		return true
	end
	local ok, err = pcall(function()
		-- 0 friends.
		FriendService.SetCheck(function()
			return false
		end)
		local count0 = FriendService.Recount(player, fakePeers(3))
		local inputs0 = PlayerDataService.GetIncomeInputs(player)
		if not inputs0 then
			result(false, "friend boost: income inputs for the tester", "none")
			return
		end
		local mult0 = TycoonConfig.GetIncomeMultiplier(inputs0)
		local live0 = TycoonConfig.GetPassiveCashPerSecond(inputs0)
		local steady0 = PlayerDataService.GetSteadyIncomePerSecond(player)
		local offline0 = PlayerDataService.GetBasePassiveCashPerSecond(player)
		result(
			count0 == 0 and inputs0.FriendMultiplier == 1 and PlayerDataService.GetTycoonSnapshot(player).Friends == 0,
			"friend boost: 0 friends -> multiplier 1, snapshot Friends 0",
			("count %d, multiplier %s"):format(count0, tostring(inputs0.FriendMultiplier))
		)
		chip(0)

		-- 2 friends.
		FriendService.SetCheck(allFriends)
		local count2 = FriendService.Recount(player, fakePeers(2))
		local inputs2 = PlayerDataService.GetIncomeInputs(player) :: TycoonConfig.IncomeInputs
		local row2 = friendsRow(inputs2)
		result(
			count2 == 2
				and near(inputs2.FriendMultiplier or 0, 1.3)
				and row2 ~= nil
				and near(row2, 1.3)
				and near(TycoonConfig.GetIncomeMultiplier(inputs2), mult0 * 1.3)
				and near(TycoonConfig.GetPassiveCashPerSecond(inputs2), live0 * 1.3)
				and PlayerDataService.GetTycoonSnapshot(player).Friends == 2,
			"friend boost: 2 friends -> x1.30 on all income, a Friends row of 1.3 in the breakdown",
			("count %d, multiplier %s, row %s, income %s vs %s"):format(
				count2,
				tostring(inputs2.FriendMultiplier),
				tostring(row2),
				tostring(TycoonConfig.GetPassiveCashPerSecond(inputs2)),
				tostring(live0)
			)
		)
		result(
			near(PlayerDataService.GetSteadyIncomePerSecond(player), steady0)
				and near(PlayerDataService.GetBasePassiveCashPerSecond(player), offline0)
				and OfflineConfig.Compute(PlayerDataService.GetBasePassiveCashPerSecond(player), 3600) == OfflineConfig.Compute(offline0, 3600),
			"friend boost: steady income (the gacha price) and offline earnings ignore friends",
			("steady %s vs %s, base %s vs %s"):format(
				tostring(PlayerDataService.GetSteadyIncomePerSecond(player)),
				tostring(steady0),
				tostring(PlayerDataService.GetBasePassiveCashPerSecond(player)),
				tostring(offline0)
			)
		)
		chip(30)

		-- 6 friends: capped at +60%.
		local count6 = FriendService.Recount(player, fakePeers(6))
		local inputs6 = PlayerDataService.GetIncomeInputs(player) :: TycoonConfig.IncomeInputs
		result(
			count6 == FriendConfig.MaxFriends
				and near(inputs6.FriendMultiplier or 0, 1.6)
				and near(TycoonConfig.GetIncomeMultiplier(inputs6), mult0 * 1.6)
				and near(PlayerDataService.GetSteadyIncomePerSecond(player), steady0),
			"friend boost: 6 friends are capped at x1.60",
			("count %d, multiplier %s"):format(count6, tostring(inputs6.FriendMultiplier))
		)
		chip(60)

		-- The Roblox call fails: not friends, nothing thrown.
		FriendService.SetCheck(function()
			error("friend check failed (selftest)")
		end)
		local failedOk, failedCount = pcall(FriendService.Recount, player, fakePeers(3))
		local inputsFail = PlayerDataService.GetIncomeInputs(player) :: TycoonConfig.IncomeInputs
		result(
			failedOk and failedCount == 0 and inputsFail.FriendMultiplier == 1,
			"friend boost: a failing friendship call counts as not friends, no server error",
			("ok %s, count %s, multiplier %s"):format(tostring(failedOk), tostring(failedCount), tostring(inputsFail.FriendMultiplier))
		)
		chip(0)

		-- Friends made mid-session: a pair that turns friends is found by the
		-- recheck loop once its answer is older than RecheckSeconds, one
		-- Roblox call per step, and both players' counts go up.
		local fakeFriend = fakePeers(1)[1]
		local both: { Player } = { player, fakeFriend }
		local clockNow = 0
		local askedCalls = 0
		local nowFriends = false
		FriendService.SetClock(function()
			return clockNow
		end)
		FriendService.SetCheck(function()
			askedCalls += 1
			return nowFriends
		end)
		PlayerDataService.SetFriendCount(fakeFriend, 0)
		local before = FriendService.Recount(player, both)
		nowFriends = true
		askedCalls = 0
		clockNow = FriendConfig.RecheckSeconds - 1
		local early = FriendService.RecheckStep(both)
		clockNow = FriendConfig.RecheckSeconds + 1
		local due = FriendService.RecheckStep(both)
		local afterOne = FriendService.RecheckStep(both)
		result(
			before == 0
				and not early
				and due
				and not afterOne
				and askedCalls == 1
				and PlayerDataService.GetFriendCount(player) == 1
				and PlayerDataService.GetFriendCount(fakeFriend) == 1,
			"friend boost: a pair that becomes friends mid-session is found by the recheck, both counts +1, one call",
			("before %d, early %s, due %s, again %s, calls %d, counts %d/%d"):format(
				before,
				tostring(early),
				tostring(due),
				tostring(afterOne),
				askedCalls,
				PlayerDataService.GetFriendCount(player),
				PlayerDataService.GetFriendCount(fakeFriend)
			)
		)
		PlayerDataService.SetFriendCount(fakeFriend, 0)
	end)
	-- The real check, clock and count, whatever happened above.
	FriendService.SetClock(nil)
	FriendService.SetCheck(nil)
	FriendService.Recount(player)
	if not ok then
		result(false, "friend boost (errored)", tostring(err))
	end
end


-- Rival labs (RivalService + HeistService's rival path): the fill, a real
-- player's slot, the Rebirth rule, a steal end to end (grab, deliver, the
-- guard's tag, the 90 s respawn on an injected clock), the hourly limit, the
-- orb rolls and a lab despawning mid-carry. Everything is put back after.
local function runRivalSelfTest(player: Player, result: (boolean, string, string?) -> ())
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		result(true, "rivals (skipped: the tester has no character)")
		return
	end
	local home = root.CFrame
	local rebirthsBefore = PlayerDataService.GetRebirths(player)
	local standIns: { any } = {}
	local fakeNow = RivalService.Now()
	local savedSteals = HeistService.SelfTestGetRivalSteals(player)
	local releaseClaim: (() -> ())? = nil

	local function waitUntil(condition: () -> boolean, timeout: number): boolean
		local started = os.clock()
		while not condition() and os.clock() - started < timeout do
			task.wait(0.1)
		end
		return condition()
	end
	local function inventoryUids(): { [string]: boolean }
		local uids: { [string]: boolean } = {}
		local inventory: { any } = PlayerDataService.GetInventory(player) or {}
		for _, item in inventory do
			uids[item.Uid] = true
		end
		return uids
	end
	local function inventoryCount(): number
		local count = 0
		for _ in inventoryUids() do
			count += 1
		end
		return count
	end
	local function putNextTo(pedestal: BasePart)
		character:PivotTo(pedestal.CFrame * CFrame.new(0, 3, 5))
		task.wait(0.1)
	end
	local function anyOrb(): (any?, number?)
		for _, view in RivalService.GetRivals() do
			for index = 1, RivalConfig.PedestalCount do
				if RivalService.GetOrb(view.Id, index) then
					return view, index
				end
			end
		end
		return nil, nil
	end
	local limit = RivalConfig.GuardUprightSelfTestDegrees
	-- Every built guard's root is within `limit` degrees of vertical. Returns
	-- (ok, how many guards were measured, the ones past the limit).
	local function guardsUpright(): (boolean, number, string)
		local measured = 0
		local bad: { string } = {}
		for _, view in RivalService.GetRivals() do
			local angle = RivalService.GetGuardUprightDegrees(view.Id)
			if angle then
				measured += 1
				if angle > limit then
					table.insert(bad, ("%s %.0f deg"):format(view.Name, angle))
				end
			end
		end
		return #bad == 0, measured, table.concat(bad, ", ")
	end
	local function guardHumanoid(rivalId: number): Humanoid?
		local model = RivalService.GetGuardModel(rivalId)
		return if model then model:FindFirstChildOfClass("Humanoid") else nil
	end
	-- The gate sign's board relative to its slot (the same for every lab).
	local function signRelative(plot: Model, origin: CFrame): CFrame?
		local gate = plot:FindFirstChild("SignGate")
		local board = gate and gate:FindFirstChild("SignBoard")
		return if board and board:IsA("BasePart") then origin:ToObjectSpace(board.CFrame) else nil
	end
	local function sameOrientation(a: CFrame, b: CFrame): boolean
		return (a.Position - b.Position).Magnitude < 0.05 and a.LookVector:Dot(b.LookVector) > 0.999 and a.UpVector:Dot(b.UpVector) > 0.999
	end
	-- Enabled lights in `root`, on the pedestals or everywhere else.
	local function countLights(root: Instance, onPedestals: boolean): number
		local count = 0
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("Light") and descendant.Enabled and (descendant:FindFirstAncestor("Pedestals") ~= nil) == onPedestals then
				count += 1
			end
		end
		return count
	end

	local ok, err = pcall(function()
		PlayerDataService.SetRebirths(player, 0)
		RivalService.SetClock(function()
			return fakeNow
		end)
		HeistService.SelfTestClearRivalSteals(player)
		RivalService.Step()

		-- 1. The fill: a solo server gets MaxRivals labs, built like a player's.
		local rivals = RivalService.GetRivals()
		local freeNow = #TycoonService.GetFreeSlots()
		result(
			#rivals == math.min(RivalConfig.MaxRivals, #rivals + freeNow) and #rivals >= 1,
			("rivals: the server fills %d rival lab(s) in free slots"):format(RivalConfig.MaxRivals),
			("%d labs, %d slots free"):format(#rivals, freeNow)
		)
		local shapeBad: { string } = {}
		for _, view in rivals do
			local plot = view.Plot
			local pedestals = plot:FindFirstChild("Pedestals")
			if plot:GetAttribute("Rival") ~= true or plot:GetAttribute("OwnerUserId") ~= nil or plot:GetAttribute("Claimed") == true then
				table.insert(shapeBad, view.Name .. " attributes")
			end
			-- Decoration mode (group 1): the lab's pictures are all there.
			local names = {
				"FusionMachine",
				"GachaStation",
				"MultiplierStation",
				PortalKit.MODEL_NAME,
				FactoryKit.BELT_NAME,
				FactoryKit.COLLECTOR_NAME,
			}
			for _, generator in TycoonConfig.Generators do
				table.insert(names, GeneratorKit.GetModelName(generator.Id))
			end
			for _, name in names do
				if not plot:FindFirstChild(name) then
					table.insert(shapeBad, ("%s has no %s"):format(view.Name, name))
				end
			end
			for _, generator in TycoonConfig.Generators do
				local model = plot:FindFirstChild(GeneratorKit.GetModelName(generator.Id))
				local level = model and model:GetAttribute("Level")
				if not (typeof(level) == "number" and level >= 1) then
					table.insert(shapeBad, ("%s %s is not running"):format(view.Name, generator.Id))
				end
			end
			-- ... and nothing to press: zero prompts but the 4 steal prompts, no
			-- Highlights, no live owner-only label, no label on the stations.
			local stealPrompts, otherPrompts, highlights, ownerLabels = 0, 0, 0, 0
			for _, descendant in plot:GetDescendants() do
				if descendant:IsA("ProximityPrompt") then
					if descendant.Name == "StealPrompt" then
						stealPrompts += 1
					else
						otherPrompts += 1
					end
				elseif descendant:IsA("Highlight") then
					highlights += 1
				elseif descendant:IsA("BillboardGui") and descendant:GetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE) == true and descendant.Enabled then
					ownerLabels += 1
				end
			end
			if stealPrompts ~= RivalConfig.PedestalCount or otherPrompts > 0 then
				table.insert(shapeBad, ("%s has %d steal prompts and %d other prompts"):format(view.Name, stealPrompts, otherPrompts))
			end
			if highlights > 0 or ownerLabels > 0 then
				table.insert(shapeBad, ("%s has %d Highlights, %d live owner-only labels"):format(view.Name, highlights, ownerLabels))
			end
			for _, stationName in { "GachaStation", "MultiplierStation", "FusionMachine" } do
				local station = plot:FindFirstChild(stationName)
				if station and station:FindFirstChildWhichIsA("BillboardGui", true) then
					table.insert(shapeBad, ("%s %s carries a label (no prices on a rival lab)"):format(view.Name, stationName))
				end
			end
			-- The gate sign: upright and turned like a player's (relative to the slot).
			local g = PlotLayout.Gate
			local relative = signRelative(plot, view.Origin)
			local nominal = CFrame.new(0, g.BoardCenterY, PlotLayout.SIGN_Z)
			if not relative or not sameOrientation(relative, nominal) or relative.UpVector.Y < 0.999 then
				table.insert(shapeBad, view.Name .. " sign is not upright and square to its slot")
			end
			for index = 1, RivalConfig.PedestalCount do
				local pedestal = pedestals and pedestals:FindFirstChild("Pedestal" .. index)
				local steal = pedestal and pedestal:FindFirstChild("StealPrompt")
				if
					not pedestal
					or pedestal:GetAttribute("Filled") ~= true
					or not steal
					or steal:GetAttribute("RivalId") ~= view.Id
					or steal:GetAttribute("OwnerUserId") ~= nil
					or pedestal:FindFirstChild("UnlockPrompt")
				then
					table.insert(shapeBad, ("%s pedestal %d"):format(view.Name, index))
				end
			end
			local title: string? = nil
			for _, descendant in plot:GetDescendants() do
				if descendant:IsA("TextLabel") and descendant.Name == "Title" and descendant:FindFirstAncestor("SignGate") then
					title = descendant.Text
					break
				end
			end
			if title ~= "RIVAL LAB" then
				table.insert(shapeBad, view.Name .. " sign reads " .. tostring(title))
			end
		end
		result(#shapeBad == 0, "rivals: each lab is ownerless, with 4 filled steal pedestals, a RIVAL LAB sign, the Fusion Machine, Gacha, Multiplier, factory line and portal as pictures, and zero prompts but the 4 steal prompts", table.concat(shapeBad, "; "))
		local tiersBad: { string } = {}
		for _, view in rivals do
			for index = 1, RivalConfig.PedestalCount do
				local orb = RivalService.GetOrb(view.Id, index)
				if not orb or orb.Tier == "Legendary" or orb.Tier == "Mythic" or orb.Tier == "Secret" then
					table.insert(tiersBad, ("%s/%d %s"):format(view.Name, index, if orb then orb.Tier else "empty"))
				end
			end
		end
		result(#tiersBad == 0, "rivals: with the lowest player at Rebirth 0 every orb is a Common, Rare or Epic", table.concat(tiersBad, "; "))

		-- Guards (group 2 / 3): built async, so give the rigs a moment.
		waitUntil(function()
			for _, view in RivalService.GetRivals() do
				if RivalService.GetGuardModel(view.Id) == nil then
					return false
				end
			end
			return true
		end, 10)
		local upright, measured, uprightDetail = guardsUpright()
		if measured == 0 then
			result(true, "rivals: guards stand upright after spawn (skipped: no guard rig built)")
		else
			result(upright, "rivals: every guard's root is within 20 deg of vertical after spawn", uprightDetail)
			local rigBad: { string } = {}
			for _, view in rivals do
				local humanoid = guardHumanoid(view.Id)
				local model = RivalService.GetGuardModel(view.Id)
				local guardRoot = model and model:FindFirstChild("HumanoidRootPart")
				if humanoid and model and guardRoot and guardRoot:IsA("BasePart") then
					for _, humanoidState in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Physics, Enum.HumanoidStateType.Seated } do
						if humanoid:GetStateEnabled(humanoidState) then
							table.insert(rigBad, ("%s can enter %s"):format(view.Name, humanoidState.Name))
						end
					end
					if humanoid.BreakJointsOnDeath or humanoid.RequiresNeck or guardRoot.Anchored or humanoid.HipHeight <= 0 or humanoid.PlatformStand then
						table.insert(rigBad, ("%s: BreakJointsOnDeath %s, RequiresNeck %s, Anchored %s, HipHeight %.2f, PlatformStand %s"):format(
							view.Name,
							tostring(humanoid.BreakJointsOnDeath),
							tostring(humanoid.RequiresNeck),
							tostring(guardRoot.Anchored),
							humanoid.HipHeight,
							tostring(humanoid.PlatformStand)
						))
					end
					-- The name over its head: the rival's, in a world label (60 studs).
					local head = model:FindFirstChild("Head")
					local nameGui = head and head:FindFirstChild("GuardName")
					local nameText = nameGui and nameGui:FindFirstChild("Text", true)
					if
						not (nameGui and nameGui:IsA("BillboardGui") and nameText and nameText:IsA("TextLabel"))
						or nameText.Text ~= RivalConfig.GetShortName(view.Name)
						or nameGui.MaxDistance ~= RivalConfig.GuardNameDistance
						or nameGui.AlwaysOnTop
						or nameGui.LightInfluence ~= 0
						or humanoid.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None
					then
						table.insert(rigBad, view.Name .. " name label is not the rival's name / 60 studs / world-label rules")
					end
				end
			end
			result(#rigBad == 0, "rivals: guards can't fall over or ragdoll, hip height from the rig, named after their rival", table.concat(rigBad, "; "))
			-- Self-heal: a guard laid on its side stands itself up (1 s tilted,
			-- GettingUp, 1 s more, then the pivot).
			local first = rivals[1]
			if first and RivalService.SelfTestLayDown(first.Id) then
				local laidDown = RivalService.GetGuardUprightDegrees(first.Id) or 0
				local stood = waitUntil(function()
					return (RivalService.GetGuardUprightDegrees(first.Id) or 90) <= limit
				end, 5)
				result(laidDown > RivalConfig.UprightLimitDegrees and stood, "rivals: a guard laid on its side stands up again by itself within 5 s", ("laid at %.0f deg, stood %s"):format(laidDown, tostring(stood)))
			end
		end

		-- 2. A real player is never refused a plot: fill every slot with
		-- stand-in players, then one more displaces the farthest rival.
		local freeSlots = TycoonService.GetFreeSlots()
		local made = 0
		for index = 1, #freeSlots do
			local stand: any = { UserId = -9100 - index, Name = "RivalTest" .. index, DisplayName = "RivalTest" .. index }
			if TycoonService.SelfTestCreatePlot(stand) then
				table.insert(standIns, stand)
				made += 1
			end
		end
		local rivalsFull = RivalService.GetRivals()
		local fullOk = #TycoonService.GetFreeSlots() == 0 and #rivalsFull >= 1
		if fullOk then
			local anchors: { Vector3 } = {}
			for _, slot in TycoonService.GetPlayerSlots() do
				table.insert(anchors, PlotLayout.GetSlotCFrame(slot).Position)
			end
			local expected: any = nil
			local expectedDistance = -math.huge
			for _, view in rivalsFull do
				local nearest = math.huge
				for _, anchor in anchors do
					nearest = math.min(nearest, (view.Origin.Position - anchor).Magnitude)
				end
				if nearest > expectedDistance or (nearest == expectedDistance and expected ~= nil and view.Id > expected.Id) then
					expected, expectedDistance = view, nearest
				end
			end
			local extra: any = { UserId = -9099, Name = "RivalTestX", DisplayName = "RivalTestX" }
			local plot = TycoonService.SelfTestCreatePlot(extra)
			table.insert(standIns, extra)
			result(
				plot ~= nil
					and RivalService.GetRival(expected.Id) == nil
					and #RivalService.GetRivals() == #rivalsFull - 1
					and plot:GetAttribute("SlotIndex") == expected.SlotIndex
					and expected.Plot.Parent == nil,
				"rivals: a player joining a full server displaces the farthest rival and gets its slot",
				("expected %s (slot %d) to go; plot %s, slot %s, %d -> %d labs"):format(
					expected.Name,
					expected.SlotIndex,
					tostring(plot ~= nil),
					tostring(plot and plot:GetAttribute("SlotIndex")),
					#rivalsFull,
					#RivalService.GetRivals()
				)
			)
		else
			result(true, "rivals: displacement (skipped: the server could not be filled)", ("%d free, %d rivals, %d stand-ins"):format(#TycoonService.GetFreeSlots(), #rivalsFull, made))
		end
		-- The gate sign stands like a player's: same CFrame relative to its slot.
		local standPlot = if standIns[1] then TycoonService.GetPlotForPlayer(standIns[1]) else nil
		local standSlot = if standPlot then standPlot:GetAttribute("SlotIndex") else nil
		local referenceSign = if standPlot and typeof(standSlot) == "number" then signRelative(standPlot, PlotLayout.GetSlotCFrame(standSlot)) else nil
		if referenceSign then
			local signBad: { string } = {}
			for _, view in RivalService.GetRivals() do
				local rivalSign = signRelative(view.Plot, view.Origin)
				if not rivalSign or not sameOrientation(rivalSign, referenceSign) then
					table.insert(signBad, view.Name)
				end
			end
			result(#signBad == 0, "rivals: each gate sign has the same orientation relative to its slot as a player plot's", table.concat(signBad, ", "))
		else
			result(true, "rivals: sign orientation vs a player plot (skipped: no stand-in plot was built)")
		end
		for _, stand in standIns do
			TycoonService.SelfTestRemovePlot(stand)
		end
		table.clear(standIns)
		RivalService.Step()
		result(#RivalService.GetRivals() >= 1 and #TycoonService.GetFreeSlots() >= 0, "rivals: the labs refill once the slots free up")

		-- 3. The Rebirth rule: Rebirth 0 may rob a rival, not a player.
		local isProtected = HeistService.IsProtected(player)
		result(
			HeistService.WhyCantSteal(0, true) == nil
				and HeistService.WhyCantSteal(0, false) == "NeedsRebirth"
				and HeistService.WhyCantSteal(1, false) == nil
				and HeistConfig.MinRebirthsVsRivals == 0
				and HeistConfig.MinRebirthsVsPlayers == 1,
			"rivals: Rebirth 0 may steal from a rival, not from a player; Rebirth 1 may from both"
		)
		PlayerDataService.SetRebirths(player, 1)
		local protectedAtOne = HeistService.IsProtected(player)
		PlayerDataService.SetRebirths(player, 0)
		result(isProtected and not protectedAtOne, "rivals: a Rebirth 0 lab is protected from other players, a Rebirth 1 lab is not")

		-- 4. A steal end to end.
		local state, release, why = TycoonService.SelfTestClaim(player)
		if state == "Skip" then
			result(true, "rivals: steal, deliver and tag (skipped: no lab for the tester)", tostring(why))
		else
			releaseClaim = release
			local plot = TycoonService.GetPlotForPlayer(player)
			local view, index = anyOrb()
			local pedestal = view and RivalService.GetPedestal(view.Id, index :: number)
			if not plot or not view or not pedestal or not index then
				result(false, "rivals: a rival with an orb and the tester's lab", "none")
			else
				-- Light budget: a rival lab adds at most what one fully filled player
				-- lab adds: its floor lights, and on its pedestals two lights each (the
				-- "PedestalLight" and the orb's own), RivalConfig.MaxPedestalLights.
				local rivalFloor, playerFloor = countLights(view.Plot, false), countLights(plot, false)
				local rivalLights = countLights(view.Plot, true)
				result(
					rivalFloor <= playerFloor and rivalLights <= RivalConfig.MaxPedestalLights,
					"rivals: a rival lab's lights stay within one claimed player lab's",
					("floor %d vs %d, pedestal + orb lights %d (max %d)"):format(rivalFloor, playerFloor, rivalLights, RivalConfig.MaxPedestalLights)
				)
				-- CLAUDE.md caps on every rival light: pedestal lights Brightness 0.8-1.6
				-- and Range 8-12, the orb light Brightness 1 (its range grows with the
				-- tier), all Shadows = false.
				local capBad: { string } = {}
				for _, descendant in view.Plot:GetDescendants() do
					if descendant:IsA("Light") and descendant.Enabled and descendant:FindFirstAncestor("Pedestals") then
						local isPedestalLight = descendant.Name == "PedestalLight"
						local brightnessOk = if isPedestalLight then descendant.Brightness >= 0.8 and descendant.Brightness <= 1.6 else descendant.Brightness == PlotLayout.Pedestal.OrbLightBrightness
						local rangeOk = not isPedestalLight or (descendant.Range >= 8 and descendant.Range <= 12)
						if descendant.Shadows or not brightnessOk or not rangeOk then
							table.insert(capBad, ("%s brightness %.2f range %.1f shadows %s"):format(descendant:GetFullName(), descendant.Brightness, descendant.Range, tostring(descendant.Shadows)))
						end
					end
				end
				result(#capBad == 0, "rivals: every rival pedestal light obeys the caps (pedestal 0.8-1.6 / 8-12, orb 1, no shadows)", table.concat(capBad, "; "))
				putNextTo(pedestal)
				local orb = RivalService.GetOrb(view.Id, index)
				local before = inventoryCount()
				local beforeUids = inventoryUids()
				local grabbed, reason = HeistService.TryRivalSteal(player, view.Id, index)
				result(
					grabbed and HeistService.IsCarrying(player) and pedestal:GetAttribute("BeingStolen") == true and RivalService.IsCarried(view.Id, index),
					"rivals: a Rebirth 0 player grabs an orb from a rival lab",
					tostring(reason)
				)
				local again = HeistService.TryRivalSteal(player, view.Id, index)
				result(not again, "rivals: a second grab while carrying is refused")
				-- Deliver: the tester runs home (the carry loop sees the root inside the walls).
				local origin = plot.PrimaryPart
				if origin then
					character:PivotTo(origin.CFrame * CFrame.new(0, 3, 0))
				end
				local delivered = waitUntil(function()
					return not HeistService.IsCarrying(player)
				end, 3)
				local added: { any } = {}
				local inventoryNow: { any } = PlayerDataService.GetInventory(player) or {}
				for _, item in inventoryNow do
					if not beforeUids[item.Uid] then
						table.insert(added, item)
					end
				end
				result(
					delivered
						and #added == 1
						and orb ~= nil
						and added[1].ItemId == orb.ItemId
						and added[1].Tier == orb.Tier
						and inventoryCount() == before + 1,
					"rivals: delivery creates the orb for the thief",
					("delivered %s, %d new item(s)"):format(tostring(delivered), #added)
				)
				local respawnAt = RivalService.GetRespawnAt(view.Id, index)
				result(
					RivalService.GetOrb(view.Id, index) == nil and respawnAt ~= nil and math.abs((respawnAt :: number) - (fakeNow + RivalConfig.RespawnSeconds)) < 0.001,
					"rivals: a delivered orb leaves its pedestal with a 90 s respawn timer"
				)
				result(
					pedestal:GetAttribute("RespawnAt") == respawnAt and pedestal:GetAttribute("Filled") == false and pedestal:FindFirstChild("PedestalVisualElements") == nil,
					"rivals: the stolen orb's pedestal shows the empty cap and carries RespawnAt for the client's \"back in\" chip",
					("RespawnAt %s, Filled %s"):format(tostring(pedestal:GetAttribute("RespawnAt")), tostring(pedestal:GetAttribute("Filled")))
				)
				-- The respawn, on the injected clock.
				fakeNow += RivalConfig.RespawnSeconds - 0.5
				RivalService.Step()
				local early = RivalService.GetOrb(view.Id, index) == nil
				fakeNow += 1
				RivalService.Step()
				local back = RivalService.GetOrb(view.Id, index)
				result(
					early and back ~= nil and pedestal:GetAttribute("Filled") == true and pedestal:GetAttribute("RespawnAt") == nil,
					"rivals: the orb is back after 90 s (injected clock), not before, and the countdown goes"
				)
				if added[1] then
					PlayerDataService.RemoveItemsByUid(player, { added[1].Uid })
				end

				-- The guard's tag sends the orb back.
				local guardModel = RivalService.GetGuardModel(view.Id)
				local guardRoot = guardModel and guardModel:FindFirstChild("HumanoidRootPart")
				if not guardRoot or not guardRoot:IsA("BasePart") then
					result(true, "rivals: the guard's touch returns the orb (skipped: the guard rig did not build)")
				else
					putNextTo(pedestal)
					local countBefore = inventoryCount()
					local grabbedAgain = HeistService.TryRivalSteal(player, view.Id, index)
					task.wait(HeistConfig.TagGraceSeconds + 0.3)
					local thiefRoot = character:FindFirstChild("HumanoidRootPart")
					if thiefRoot and thiefRoot:IsA("BasePart") then
						guardModel:PivotTo(thiefRoot.CFrame * CFrame.new(0, 0, 3))
					end
					local tagged = waitUntil(function()
						return not HeistService.IsCarrying(player)
					end, 3)
					result(
						grabbedAgain and tagged and RivalService.GetOrb(view.Id, index) ~= nil and inventoryCount() == countBefore,
						"rivals: the guard's touch sends the orb back, nothing created",
						("grabbed %s, tagged %s"):format(tostring(grabbedAgain), tostring(tagged))
					)
				end

				-- A chase across the street's speed belts: the thief stands on the far
				-- side of the street, the guard runs the belts for a few seconds, and
				-- its root stays upright the whole way.
				if guardRoot and guardRoot:IsA("BasePart") then
					putNextTo(pedestal)
					if HeistService.TryRivalSteal(player, view.Id, index) then
						local farSide = if view.Origin.Position.Z < 0 then 1 else -1
						character:PivotTo(CFrame.new(view.Origin.Position.X, StreetLayout.STREET_TOP_Y + 4, farSide * 12))
						local worst = 0
						local chaseUntil = os.clock() + 6
						while os.clock() < chaseUntil do
							worst = math.max(worst, RivalService.GetGuardUprightDegrees(view.Id) or 0)
							task.wait(0.2)
						end
						HeistService.FailCarriesFor(player, "Failed")
						result(worst <= limit, "rivals: a guard chasing across the speed belts stays within 20 deg of vertical", ("worst %.0f deg"):format(worst))
					else
						result(true, "rivals: guard upright over a chase (skipped: the grab was refused)")
					end
					character:PivotTo(home)
				end

				-- A hit stuns the guard: no tag while it is down; a second hit mid-stun
				-- is one stun; afterwards PlatformStand is off and it stands upright.
				if guardRoot and guardRoot:IsA("BasePart") then
					RivalService.StunGuard(view.Id, guardRoot.Position + Vector3.new(0, 0, 3))
					result(RivalService.IsGuardStunned(view.Id) and RivalService.GetGuardRoot(view.Id) == nil, "rivals: a weapon hit stuns the guard (it can't tag while down)")
					task.wait(0.5)
					RivalService.StunGuard(view.Id, guardRoot.Position + Vector3.new(0, 0, -3))
					task.wait(RivalConfig.GuardStunSeconds + 0.6)
					local humanoid = guardHumanoid(view.Id)
					local afterStun = RivalService.GetGuardUprightDegrees(view.Id) or 0
					result(
						not RivalService.IsGuardStunned(view.Id) and humanoid ~= nil and not humanoid.PlatformStand and afterStun <= limit,
						"rivals: after a stun (and a second hit) the guard is off PlatformStand and within 20 deg of vertical",
						("PlatformStand %s, %.0f deg"):format(tostring(humanoid and humanoid.PlatformStand), afterStun)
					)
				end

				-- 5. StealsPerHour.
				HeistService.SelfTestClearRivalSteals(player)
				HeistService.SelfTestRecordRivalSteals(player, RivalConfig.StealsPerHour - 1)
				local leftAt11 = HeistService.GetRivalStealsLeft(player)
				HeistService.SelfTestRecordRivalSteals(player, 1)
				local leftAt12, wait = HeistService.GetRivalStealsLeft(player)
				putNextTo(pedestal)
				local blocked, blockedReason, blockedSeconds = HeistService.TryRivalSteal(player, view.Id, index)
				result(
					leftAt11 == 1 and leftAt12 == 0 and not blocked and blockedReason == "RivalAlert" and (blockedSeconds or 0) >= 1 and wait == blockedSeconds,
					("rivals: past %d steals an hour the grab is refused with RivalAlert and the minutes left"):format(RivalConfig.StealsPerHour),
					("left %d/%d, %s, %ss"):format(leftAt11, leftAt12, tostring(blockedReason), tostring(blockedSeconds))
				)
				fakeNow += RivalConfig.StealWindowSeconds + 1
				RivalService.Step()
				local viewNow, indexNow = anyOrb()
				local pedestalNow = viewNow and RivalService.GetPedestal(viewNow.Id, indexNow :: number)
				if viewNow and indexNow and pedestalNow then
					putNextTo(pedestalNow)
					local freed = HeistService.TryRivalSteal(player, viewNow.Id, indexNow)
					result(freed and HeistService.GetRivalStealsLeft(player) == RivalConfig.StealsPerHour, "rivals: an hour later the limit is open again")

					-- 6. A lab that despawns mid-carry fails cleanly.
					local carriedBefore = inventoryCount()
					local despawnOk, despawnErr = pcall(function(): string?
						RivalService.Despawn(viewNow.Id)
						return nil
					end)
					task.wait(0.2)
					result(
						despawnOk
							and not HeistService.IsCarrying(player)
							and player:GetAttribute("HeistTier") == nil
							and RivalService.GetRival(viewNow.Id) == nil
							and HeistService.GetRivalCarryCount() == 0
							and inventoryCount() == carriedBefore,
						"rivals: a lab despawning mid-carry fails the carry cleanly, no error, nothing created",
						tostring(despawnErr)
					)
				else
					result(true, "rivals: despawn mid-carry (skipped: no grabbable orb)")
				end
			end
		end

		-- 7. Orb rolls: no Mythic / Secret in any band over 10 000 draws, only
		-- plain or the 5% Golden, and a banned tier is skipped even if listed.
		local bandsBad: { string } = {}
		for band = 0, RivalConfig.MaxBand + 1 do
			local golden = 0
			for _ = 1, 10000 do
				local orb = RivalService.RollOrb(band)
				if RivalConfig.BannedTiers[orb.Tier] or ItemConfig.GetItemById(orb.ItemId) == nil then
					table.insert(bandsBad, ("band %d rolled %s"):format(band, orb.Tier))
					break
				end
				if orb.Mutation == "Golden" then
					golden += 1
				elseif orb.Mutation ~= nil then
					table.insert(bandsBad, ("band %d rolled mutation %s"):format(band, tostring(orb.Mutation)))
					break
				end
			end
			if golden < 350 or golden > 650 then
				table.insert(bandsBad, ("band %d: %d Golden in 10000 (want ~500)"):format(band, golden))
			end
		end
		result(#bandsBad == 0, "rivals: 10 000 draws per band, no Mythic / Secret, only plain or ~5% Golden", table.concat(bandsBad, "; "))
		local weights = RivalConfig.TierWeights[0]
		local savedMythic = weights.Mythic
		weights.Mythic = 1000
		local leaked = false
		for step = 0, 999 do
			if RivalConfig.BannedTiers[RivalConfig.PickTier(0, step / 1000)] then
				leaked = true
			end
		end
		weights.Mythic = savedMythic
		result(not leaked, "rivals: PickTier skips a banned tier even if a band lists it")
	end)
	if not ok then
		result(false, "rivals (errored)", tostring(err))
	end

	-- Put everything back.
	for _, stand in standIns do
		TycoonService.SelfTestRemovePlot(stand)
	end
	HeistService.FailCarriesFor(player, "Failed")
	if releaseClaim then
		releaseClaim()
	end
	HeistService.SelfTestSetRivalSteals(player, savedSteals)
	RivalService.SetClock(nil)
	PlayerDataService.SetRebirths(player, rebirthsBefore)
	PlayerDataService.SyncTycoon(player)
	local backCharacter = player.Character
	if backCharacter then
		backCharacter:PivotTo(home)
	end
	RivalService.Step()
end

local function runSelfTestBody(player: Player, result: (boolean, string, string?) -> (), only: string?)
	print(("[SelfTest] running for %s"):format(player.Name))
	if only == "combat" then
		print("[SelfTest] == 10. combat ==")
		runCombatSelfTest(player, result)
		return
	elseif only == "rivals" then
		print("[SelfTest] == 16. rival labs ==")
		runRivalSelfTest(player, result)
		return
	elseif only == "friends" then
		print("[SelfTest] == 14. friend boost ==")
		runFriendBoostSelfTest(player, result)
		return
	elseif only == "notify" then
		print("[SelfTest] == 15. notifications ==")
		NotifyService.SelfTest(result)
		return
	elseif only == "gacha" then
		print("[SelfTest] == 12. gacha card ==")
		runGachaCardSelfTest(player, result)
		return
	elseif only == "tutorial" then
		print("[SelfTest] == 9. tutorial ==")
		tutorialProbe(player, { Kind = "ClearScreen", Label = "the tutorial", Report = false, Suppress = true }, result)
		runTutorialSelfTest(player, result)
		tutorialProbe(player, { Kind = "ClearScreen", Label = "the tutorial's end", Report = false }, result)
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
	-- A junk ClaimDaily / ClaimGift is a LEGIT claim when one is claimable
	-- (right after 00:00 UTC the daily reward is): park that for the fuzz, so
	-- a state change here still means a junk call changed something.
	local fuzzData = PlayerDataService.GetData(player)
	local savedDaily: { [string]: any }? = nil
	local savedPlaySeconds = 0
	if fuzzData then
		savedDaily = table.clone(fuzzData.Daily)
		DailyConfig.Apply(fuzzData.Daily, RewardConfig.GetUtcDay(os.time()))
		savedPlaySeconds = RewardService.GetGiftState(player).PlaySeconds
		RewardService.SetGiftSeconds(player, 0)
	end
	local before = PlayerDataService.SelfTestFingerprintFields(player)
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
	local fingerprintAfter = PlayerDataService.SelfTestFingerprintFields(player)
	if fuzzData then
		-- Put the daily and the gift clock back (play time that ticked meanwhile stays).
		if savedDaily then
			for key, value in savedDaily do
				(fuzzData.Daily :: any)[key] = value
			end
		end
		RewardService.SetGiftSeconds(player, RewardService.GetGiftState(player).PlaySeconds + savedPlaySeconds)
	end
	if not fuzzReport then
		result(false, "remote fuzz", "no report from the client")
	else
		result(#serverErrors == 0, ("remote fuzz: no server errors (%d junk calls)"):format(fuzzReport.Fired or 0), table.concat(serverErrors, " | "))
		-- Names the field(s) that moved (before -> after), so a failure says what changed.
		local changed = PlayerDataService.SelfTestFingerprintDiff(before, fingerprintAfter)
		result(#changed == 0, "remote fuzz: no state change", if #changed > 0 then "changed field(s): " .. table.concat(changed, " | ") else nil)
		result(PlayerDataService.GetCash(player) >= cashBefore, "remote fuzz: no cash spent")
		-- The fuzz's admin calls aim at a fake negative id (the tester may be a
		-- listed admin); a non-admin is still refused by the same check the
		-- AdminService handlers run.
		result(
			not AdminConfig.IsAdmin(-987654321, nil) and not AdminConfig.IsAdmin(-987654321, -987654321) and not AdminConfig.IsAdmin(0, nil),
			"admin check: a fake negative id is never an admin"
		)
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
		runAutoFillSelfTest(player, result)
	end)

	-- 9. The tutorial, driven step by step on the real paths (the remote's
	-- own handlers): every step completes in order, no shop / deal pop-up
	-- while it runs, and a save left mid-way resumes at its step. The
	-- tester's own tutorial state is restored after.
	-- The daily reward (claimable after 00:00 UTC) is closed and kept from
	-- popping up by itself for the rest of the run; whatever the section
	-- opens (an explain card, a "?" card, a weapon-unlock card) is closed at
	-- its end, so a leak cannot reach the sections that measure the screen.
	runSection("9. tutorial", result, function()
		tutorialProbe(player, { Kind = "ClearScreen", Label = "the tutorial", Report = false, Suppress = true }, result)
		runTutorialSelfTest(player, result)
		tutorialProbe(player, { Kind = "ClearScreen", Label = "the tutorial's end", Report = false }, result)
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
		runGoalStepsSelfTest(player, result)
		runSecretPitySelfTest(player, result)
		runGiftSessionSelfTest(player, result)
		-- Claiming "Fuse a Mythic" there granted the Slap Glove: the real
		-- "You got the Slap Glove!" card is up now. Close it (and its queue)
		-- so section 12 starts on a bare screen.
		task.wait(0.5)
		tutorialProbe(player, { Kind = "ClearScreen", Label = "the progression section's end", Report = false }, result)
	end)

	-- 12. The Gacha Pad card: odds against the server's luck, silhouettes,
	-- the (i) panel, the custom buttons.
	runSection("12. gacha card", result, function()
		-- One precondition line instead of one FAIL per check when a card is up.
		tutorialProbe(player, { Kind = "ClearScreen", Label = "the gacha card", Report = true }, result)
		runGachaPriceSelfTest(player, result)
		runGachaCardSelfTest(player, result)
	end)

	-- 13. The effects tray: a Luck Potion and Safe Fusion tokens show up as
	-- round icons bottom right.
	runSection("13. effects tray", result, function()
		runEffectsTraySelfTest(player, result)
	end)

	-- 13b. The 🎟 PASSES circle, from a stubbed owned set.
	runSection("13b. passes circle", result, function()
		tutorialProbe(player, { Kind = "PassesCircle" }, result)
	end)

	-- 14. The friend boost: the count, the multiplier, the chip.
	runSection("14. friend boost", result, function()
		runFriendBoostSelfTest(player, result)
	end)

	-- 15. Notifications: priority, once a day, due times, launch data and the
	-- sender's answers, all with an injected clock and a fake sender.
	runSection("15. notifications", result, function()
		NotifyService.SelfTest(result)
		-- The daily reward may open by itself again.
		tutorialProbe(player, { Kind = "ClearScreen", Label = "the end", Report = false, Suppress = false }, result)
	end)

	-- 16. Rival labs: the fill, a real player's slot, the Rebirth rule, a
	-- steal end to end, the limits, the rolls (also: /selftest rivals).
	runSection("16. rival labs", result, function()
		runRivalSelfTest(player, result)
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
	TycoonService.SelfTestFreezeIncome(player, false)
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
		elseif verb == "status" then
			print(("DebugService: %s's quests:"):format(player.Name))
			for _, line in QuestService.GetStatusLines(player) do
				print("  " .. line)
			end
		else
			warn("DebugService: /quest complete <id> | /quest reset | /quest status")
		end
		PlayerDataService.SyncTycoon(player)
	elseif command == SOUND_COMMAND then
		local slotName: string? = nil
		for slot in SoundConfig.Slots do
			if argument ~= "" and slot:lower() == argument then
				slotName = slot
			end
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if slotName and root then
			local sound = SoundKit.Play(slotName, root)
			print(("DebugService: /sound %s -> %s"):format(slotName, if sound then SoundConfig.Slots[slotName].Id else "silent (empty or failed id)"))
		else
			local names = {}
			for slot in SoundConfig.Slots do
				table.insert(names, slot)
			end
			table.sort(names)
			warn("DebugService: /sound <" .. table.concat(names, "|") .. ">")
		end
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
	elseif command == DATA_COMMAND then
		local seconds = tonumber(argument:match("^slowload%s+(%S+)$"))
		if seconds and seconds == seconds then
			PlayerDataService.DebugSlowLoad(seconds)
			print(("DebugService: the next join's data load waits %d s first"):format(math.clamp(seconds, 0, 60)))
		else
			warn("DebugService: /data slowload <seconds>")
		end
	elseif command == COMBAT_COMMAND then
		if argument == "box" then
			local on = CombatService.ToggleBoxDrawing()
			print(("DebugService: melee hitbox drawing %s"):format(if on then "ON" else "OFF"))
		else
			warn("DebugService: /combat box")
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
			-- Replays the whole first-minutes run: the tutorial-flow tips and
			-- the hourly steal counter start over too (/tips reset stays as is).
			clearTutorialFlowTips(player)
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
		if verb == "time" and minutes then
			RewardService.SetGiftSeconds(player, minutes * 60)
		elseif verb == "reset" then
			RewardService.ResetGifts(player)
		else
			warn("DebugService: /gifts time <minutes> | /gifts reset")
			return
		end
		PlayerDataService.SyncTycoon(player)
		local gifts = RewardService.GetGiftState(player)
		print(("DebugService: %s gifts -> %d s this visit, %d ready"):format(
			player.Name,
			math.floor(gifts.PlaySeconds),
			GiftConfig.CountReady(gifts.PlaySeconds, gifts.Claimed)
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

	print("DebugService: Studio commands active: /cash <amount>, /resetmultiplier, /rebirthready, /rebirths <n>, /give <itemId> [mutation], /offline <minutes>, /shield <s>, /stealable, /tips reset, /tutorial reset|step <n>, /weapons all|reset, /data slowload <s>, /anim export, /quest complete <id>|reset|status, /powerup <key> <n>, /sound <slot>, /event <id> [min] | off, /eventclock <min>, /eventmut <charged|void|celestial>, /shop grant <key>, /deal slot <h> | pop, /daily day|miss|reset, /gifts time|reset, /selftest, /wipe")
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
	RewardService = require(script.Parent.RewardService)
	FriendService = require(script.Parent.FriendService)
	NotifyService = require(script.Parent.NotifyService)
	RivalService = require(script.Parent.RivalService)
	GoalService = require(script.Parent.GoalService)

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
