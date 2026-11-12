--!strict
--[[
	RetentionSelfTest
	-----------------
	/selftest section 18 ("retention"; also `/selftest retention`), Studio only:
	the retention fix's rules (docs/RETENTION_FIX_REPORT.md). Pure where it can
	be; DebugService also asks the client's probe ("ComeBack") for the card.

	  1. The first rival steal (RivalConfig.FirstSteal): on SimulateEscape over
	     every pair of slots, a first steal from Easy or Medium gets home with
	     the guard behind, beside or AHEAD of the thief (between the pedestal and
	     the gate); later steals keep the old grace and speeds.
	  2. Lab placement: with the four labs spawned around a player in any slot,
	     the Easy lab is the nearest to them (gate to gate), and a joining player
	     takes the free slot nearest the Easy lab.
	  3. The arrow: before the first delivery the Easy lab beats a nearer
	     Medium; after it the nearest wins.
	  4. Analytics rules: the session marks, the join days (Day2Return), the
	     come-back report's server re-check, the fail reasons.
	  5. Live: a grab from the Easy lab with the tester's FirstRivalSteal mark
	     cleared is a first steal (10 s grace, the chasers at most 11); with the
	     mark set it is not; ComeBackShown is refused early and accepted once
	     eligible. The tester's state is put back.

	Not a service: DebugService requires it inside its run.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local RetentionConfig = require(ReplicatedStorage.Shared.Config.RetentionConfig)
local RivalConfig = require(ReplicatedStorage.Shared.Config.RivalConfig)

local RetentionSelfTest = {}

type Result = (boolean, string, string?) -> ()

-- Every route a carrier runs: a rival pedestal to the thief's gate, +15% for
-- bends (the same routes the Insane escape check uses).
local function allRoutes(): { number }
	local routes: { number } = {}
	for from = 1, PlotLayout.MAX_PLOT_SLOTS do
		for to = 1, PlotLayout.MAX_PLOT_SLOTS do
			if from ~= to then
				local pedestalAt = PlotLayout.GetSlotCFrame(from):PointToWorldSpace(Vector3.new(6, 0, -2))
				local gateAt = PlotLayout.GetSlotCFrame(to):PointToWorldSpace(Vector3.new(0, 0, PlotLayout.PLOT_HALF - 2))
				table.insert(routes, (pedestalAt - gateAt).Magnitude * 1.15)
			end
		end
	end
	return routes
end

local function runEscape(result: Result)
	local routes = allRoutes()
	-- Gaps: chasers 6 / 6 behind (the worst case of the Insane check), right on
	-- the thief (0), and a guard 10 / 25 studs AHEAD, between the pedestal and the
	-- gate (the interception that caught new players on Easy 2 s in).
	local gapSets: { { number } } = { { 6, 6 }, { 0 }, { -10 }, { -25 } }
	local notes: { string } = {}
	for _, difficulty in { "Easy", "Medium" } do
		local bad: { string } = {}
		for _, gaps in gapSets do
			local first, later = 0, 0
			for _, distance in routes do
				local input: RivalConfig.EscapeInput = {
					Difficulty = difficulty,
					Distance = distance,
					CarrierSpeed = HeistConfig.CarryWalkSpeed,
					Gaps = gaps,
				}
				if RivalConfig.SimulateEscape(input) then
					later += 1
				end
				input.FirstSteal = true
				if RivalConfig.SimulateEscape(input) then
					first += 1
				end
			end
			local label = table.concat(gaps :: { any }, "/")
			table.insert(notes, ("%s gaps %s: first steal %d / %d, later steals %d / %d"):format(difficulty, label, first, #routes, later, #routes))
			if first ~= #routes then
				table.insert(bad, ("gaps %s: %d of %d routes"):format(label, first, #routes))
			end
		end
		result(#bad == 0, ("retention: a first steal from %s gets home on every route (guard behind, on, or ahead of the thief)"):format(difficulty), table.concat(bad, "; "))
	end
	print("[SelfTest] retention escape model: " .. table.concat(notes, " | "))
	-- Later steals: the old rules exactly.
	local same = RivalConfig.TagGraceFor(false) == HeistConfig.TagGraceSeconds and RivalConfig.TagGraceFor(nil) == HeistConfig.TagGraceSeconds
	for _, difficulty in RivalConfig.Difficulties do
		same = same and RivalConfig.ChaseSpeedFor(difficulty, false) == RivalConfig.GetTier(difficulty).GuardSpeed
		same = same and RivalConfig.ChaseSpeedFor(difficulty, true) < HeistConfig.CarryWalkSpeed
	end
	result(same, "retention: later steals keep the 2 s grace and every guard speed; a first steal's chasers are slower than a carrier")
	result(
		RivalConfig.FirstSteal.TagGraceSeconds * HeistConfig.CarryWalkSpeed > 34 + RivalConfig.GetTier("Medium").Leash,
		"retention: the first-steal grace outlasts Medium's leash (the chasers give up before they may tag)",
		("%d studs run vs %d"):format(RivalConfig.FirstSteal.TagGraceSeconds * HeistConfig.CarryWalkSpeed, 34 + RivalConfig.GetTier("Medium").Leash)
	)
end

-- The four labs spawned (Insane first) around players in `playerSlots`, by the
-- live rule (SortSlotsByDistance + SlotPickIndex). Returns difficulty -> slot.
local function placeLabs(playerSlots: { number }): { [string]: number }
	local free: { number } = {}
	for slot = 1, PlotLayout.MAX_PLOT_SLOTS do
		if not table.find(playerSlots, slot) then
			table.insert(free, slot)
		end
	end
	local anchors: { Vector3 } = {}
	for _, slot in playerSlots do
		table.insert(anchors, PlotLayout.GetSlotGatePosition(slot))
	end
	local missing = { "Insane", "Hard", "Medium", "Easy" }
	local placed: { [string]: number } = {}
	while #missing > 0 and #free > 0 do
		local sorted = RivalConfig.SortSlotsByDistance(free, anchors, PlotLayout.GetSlotGatePosition)
		local slot = sorted[RivalConfig.SlotPickIndex(missing[1], missing, #sorted)]
		placed[missing[1]] = slot
		table.remove(free, table.find(free, slot) :: number)
		table.remove(missing, 1)
	end
	return placed
end

local function gateDistance(a: number, b: number): number
	return (PlotLayout.GetSlotGatePosition(a) - PlotLayout.GetSlotGatePosition(b)).Magnitude
end

local function runPlacement(result: Result)
	local bad: { string } = {}
	local oldTotal, newTotal, cases = 0, 0, 0
	for slot = 1, PlotLayout.MAX_PLOT_SLOTS do
		local placed = placeLabs({ slot })
		local easy = placed.Easy
		for difficulty, labSlot in placed do
			if difficulty ~= "Easy" and easy and gateDistance(slot, labSlot) < gateDistance(slot, easy) - 1e-6 then
				table.insert(bad, ("player in slot %d: %s (slot %d) nearer than Easy (slot %d)"):format(slot, difficulty, labSlot, easy))
			end
		end
		if not easy then
			table.insert(bad, ("player in slot %d: no Easy lab"):format(slot))
		end
		-- A second player joins: the slot nearest the Easy lab vs the old rule
		-- (the lowest free slot).
		if easy then
			local free: { number } = {}
			for other = 1, PlotLayout.MAX_PLOT_SLOTS do
				if other ~= slot and not table.find({ placed.Insane, placed.Hard, placed.Medium, placed.Easy }, other) then
					table.insert(free, other)
				end
			end
			local joined = RivalConfig.SortSlotsByDistance(free, { PlotLayout.GetSlotGatePosition(easy) }, PlotLayout.GetSlotGatePosition)[1]
			table.sort(free)
			local old = free[1]
			if joined and old then
				cases += 1
				oldTotal += gateDistance(old, easy)
				newTotal += gateDistance(joined, easy)
				if gateDistance(joined, easy) > gateDistance(old, easy) + 1e-6 then
					table.insert(bad, ("a player joining next to slot %d lands farther from Easy than the lowest free slot"):format(slot))
				end
			end
		end
	end
	result(#bad == 0, "retention: the Easy lab spawns nearest the player (any slot), and a joining player lands next to it", table.concat(bad, "; "))
	if cases > 0 then
		print(("[SelfTest] retention: a joining player's gate to the Easy lab's gate: %.0f studs on average (the old lowest-free-slot rule: %.0f)"):format(newTotal / cases, oldTotal / cases))
	end
	-- Slots short: whatever spawns still keeps the nearest for the lowest difficulty.
	local short = RivalConfig.SlotPickIndex("Insane", { "Insane", "Hard", "Medium", "Easy" }, 2)
	result(short == 2 and RivalConfig.SlotPickIndex("Easy", { "Easy" }, 5) == 1, "retention: SlotPickIndex clamps to the free slots (Insane takes the 2nd of 2, Easy the nearest)")
end

local function runRules(result: Result)
	result(
		RivalConfig.BetterTargetLab(true, 1, 200, 2, 50) and not RivalConfig.BetterTargetLab(false, 1, 200, 2, 50) and RivalConfig.BetterTargetLab(true, 1, 50, 1, 60),
		"retention: before the first delivery the arrow prefers the Easy lab over a nearer Medium; after it, the nearest"
	)
	result(
		RivalConfig.FirstStealFailReason("Saved") == "Tagged" and RivalConfig.FirstStealFailReason("Timeout") == "Timeout",
		"retention: FirstRivalStealFailed reasons (a guard's touch is Tagged)"
	)
	local function same(a: { number }, b: { number }): boolean
		return table.concat(a :: { any }, ",") == table.concat(b :: { any }, ",")
	end
	result(
		same(RetentionConfig.CrossedMarks(119, 120), { 120 })
			and same(RetentionConfig.CrossedMarks(0, 700), { 120, 300, 600 })
			and same(RetentionConfig.CrossedMarks(300, 301), {})
			and same(RetentionConfig.CrossedMarks(599.5, 600.5), { 600 }),
		"retention: SessionMinutes fires once at 2, 5 and 10 minutes of a visit"
	)
	local day = 20400
	local new = RetentionConfig.OnJoin(0, 0, 0, day, 0)
	local sameDay = RetentionConfig.OnJoin(new.First, new.Last, 1, day, day)
	local nextDay = RetentionConfig.OnJoin(new.First, new.Last, 1, day + 1, day)
	local nextAgain = RetentionConfig.OnJoin(nextDay.First, nextDay.Last, 2, day + 1, day + 1)
	local later = RetentionConfig.OnJoin(nextAgain.First, nextAgain.Last, 3, day + 4, day + 1)
	local legacyOne = RetentionConfig.OnJoin(0, 0, 1, day + 1, day)
	local legacyMany = RetentionConfig.OnJoin(0, 0, 5, day + 1, day)
	result(
		new.First == day and new.ReturnDays == nil
			and sameDay.ReturnDays == nil
			and nextDay.ReturnDays == 1
			and nextAgain.ReturnDays == nil
			and later.ReturnDays == 4
			and legacyOne.First == day and legacyOne.ReturnDays == 1
			and legacyMany.First == -1 and legacyMany.ReturnDays == nil,
		"retention: Day2Return / ReturnVisit on the first join of each later UTC day (an old one-session save dated by its last save, older ones never)"
	)
	local rule = RetentionConfig.ComeBack
	result(
		RetentionConfig.CanMarkComeBack(false, 1, true, rule.MinSeconds)
			and not RetentionConfig.CanMarkComeBack(true, 1, true, rule.MinSeconds)
			and not RetentionConfig.CanMarkComeBack(false, 2, true, rule.MinSeconds)
			and not RetentionConfig.CanMarkComeBack(false, 1, false, rule.MinSeconds)
			and not RetentionConfig.CanMarkComeBack(false, 1, true, rule.MinSeconds - 1),
		"retention: the server re-checks ComeBackShown (first session, not seen, tutorial over, MinSeconds in)"
	)
end

export type Deps = {
	PlayerDataService: any,
	HeistService: any,
	RivalService: any,
	RewardService: any,
}

-- The live checks (the tester's character near the Easy lab; their state put back).
local function runLive(player: Player, result: Result, deps: Deps)
	local PlayerDataService = deps.PlayerDataService
	local HeistService = deps.HeistService
	local RivalService = deps.RivalService
	local RewardService = deps.RewardService
	local data = PlayerDataService.GetData(player)
	if not data then
		result(true, "retention live (skipped: no data loaded)")
		return
	end
	-- ComeBackShown: refused at 0 s of play, accepted once eligible; put back.
	local tipId = RetentionConfig.ComeBack.TipId
	local hadTip = data.Tips[tipId] == true
	local savedSeconds = RewardService.GetGiftState(player).PlaySeconds
	local savedSessions = data.Sessions
	local savedDone = data.Tutorial.Done
	data.Tips[tipId] = nil
	data.Sessions = 1
	data.Tutorial.Done = true
	RewardService.SetGiftSeconds(player, 0)
	local early = RewardService.MarkComeBackShown(player)
	RewardService.SetGiftSeconds(player, RetentionConfig.ComeBack.MinSeconds + 5)
	local accepted = RewardService.MarkComeBackShown(player)
	local saved = data.Tips[tipId] == true
	local twice = RewardService.MarkComeBackShown(player)
	data.Tips[tipId] = if hadTip then true else nil
	data.Sessions = savedSessions
	data.Tutorial.Done = savedDone
	RewardService.SetGiftSeconds(player, savedSeconds)
	result(not early and accepted and saved and not twice, "retention: ComeBackShown refused at 0 s, saved once eligible, never twice", ("early %s, accepted %s, saved %s, twice %s"):format(tostring(early), tostring(accepted), tostring(saved), tostring(twice)))

	-- A grab from the Easy lab: first steal with the mark cleared, not with it set.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		result(true, "retention live steal (skipped: the tester has no character)")
		return
	end
	local easy: any = nil
	local index: number? = nil
	for _, view in RivalService.GetRivals() do
		if view.Difficulty == "Easy" then
			for i = 1, RivalConfig.PedestalCount do
				if RivalService.GetOrb(view.Id, i) and not RivalService.IsCarried(view.Id, i) then
					easy, index = view, i
					break
				end
			end
		end
	end
	if not easy or not index then
		result(true, "retention live steal (skipped: no Easy lab with an orb; a full server)")
		return
	end
	local home = root.CFrame
	local hadMark = PlayerDataService.SelfTestSetFunnelStep(player, "FirstRivalSteal", false)
	local savedSteals = HeistService.SelfTestGetRivalSteals(player)
	HeistService.SelfTestClearRivalSteals(player)
	local ok, err = pcall(function()
		local function grab(): (boolean, string?)
			local pedestal = RivalService.GetPedestal(easy.Id, index)
			if pedestal then
				character:PivotTo(pedestal.CFrame * CFrame.new(0, 3, 5))
				task.wait(0.1)
			end
			local grabbed, reason = HeistService.TryRivalSteal(player, easy.Id, index)
			return grabbed, reason
		end
		local grabbed, reason = grab()
		local first, grace = HeistService.SelfTestCarryRules(player)
		task.wait(0.5) -- a guard tick or five: the chaser's speed is set
		local fastest = 0
		for g = 1, RivalService.GetGuardCount(easy.Id) do
			local model = RivalService.GetGuardModel(easy.Id, g)
			local humanoid = model and model:FindFirstChildOfClass("Humanoid")
			if humanoid and RivalService.GetGuardMode(easy.Id, g) == "Chase" then
				fastest = math.max(fastest, humanoid.WalkSpeed)
			end
		end
		result(
			grabbed and first == true and grace == RivalConfig.FirstSteal.TagGraceSeconds and fastest <= RivalConfig.FirstSteal.MaxGuardSpeed,
			"retention: a save's first rival steal gets the 10 s grace and chasers no faster than 11",
			("grabbed %s (%s), first %s, grace %s, fastest chaser %.1f"):format(tostring(grabbed), tostring(reason), tostring(first), tostring(grace), fastest)
		)
		HeistService.FailCarriesFor(player, "Failed")
		task.wait(0.3)
		PlayerDataService.SelfTestSetFunnelStep(player, "FirstRivalSteal", true)
		local again = grab()
		local laterFirst, laterGrace = HeistService.SelfTestCarryRules(player)
		result(
			again and laterFirst == false and laterGrace == HeistConfig.TagGraceSeconds,
			"retention: after the first delivery a steal has the normal 2 s grace",
			("grabbed %s, first %s, grace %s"):format(tostring(again), tostring(laterFirst), tostring(laterGrace))
		)
		HeistService.FailCarriesFor(player, "Failed")
	end)
	if not ok then
		result(false, "retention live steal errored", tostring(err))
		HeistService.FailCarriesFor(player, "Failed")
	end
	PlayerDataService.SelfTestSetFunnelStep(player, "FirstRivalSteal", hadMark)
	HeistService.SelfTestSetRivalSteals(player, savedSteals)
	character:PivotTo(home)
end

function RetentionSelfTest.Run(player: Player, result: Result, deps: Deps)
	runEscape(result)
	runPlacement(result)
	runRules(result)
	runLive(player, result, deps)
end

return RetentionSelfTest
