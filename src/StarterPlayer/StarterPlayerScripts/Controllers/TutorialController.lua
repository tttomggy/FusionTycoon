--!strict
--[[
	TutorialController
	------------------
	Drives the first-time tutorial on the client (Tutorial 2; the steps are
	TutorialConfig.Steps, the server owns the step, TutorialService, and
	sends it in the snapshot). One instruction at a time; a step that
	introduces something opens one big explain card first (UI/TutorialExplain):

	  1. THE OBJECTIVE BAR (UI/TutorialBanner), top centre under the Roblox
	     top bar: icon, the step's instruction, "3 / 11", and while it has a
	     world target the live distance (a lime "24m" pill).
	  2. THE PATH (Effects/TutorialPath): small lime arrows from your feet to
	     the target, the goal arrow's bouncing pill (GoalMarkerController's
	     tutorial layer).
	  3. THE BIG BUTTON (UI/TutorialHand): standing at a world target with a
	     prompt, a green "PULL" / "UPGRADE" / "FUSE" / "BUY" button appears
	     above the bottom bar; it triggers that ProximityPrompt
	     (InputHoldBegin / InputHoldEnd) so the real server path runs; the Gacha
	     Pad's PULL sends RequestGachaPull instead (the card's E key: the pad's
	     own prompts are off).
	  4. THE HAND 👆: one for the whole UI, on the exact button to press: the
	     big button; in the Fuse panel AUTO-FILL then FUSE; the event chip;
	     REBIRTH. Never a rectangle.
	  5. Done: "Action" steps only when the server confirms the real action
	     (the snapshot's Step moves on); "Timed" / "Open" steps ask the
	     server (TutorialAdvance, re-checked) after their Seconds or once the
	     chip / panel was opened. Then the banner shows "✓ Nice!" and the
	     Step sound; the next step starts after a pause (Tutorial 4: ONE
	     step at a time, in order, see "Presenting a step" below).

	The only card is the welcome splash after the claim ("WELCOME TO YOUR
	LAB!", fades by itself). The HUD builds up as it goes (UI/HudGate): this
	file only tells it nothing: the gate reads the same saved step.

	After it, two just-in-time hands, once each: the first time a gift is
	ready (GIFTS) and the first claimable quest (QUESTS). While it runs
	(TycoonController.IsTutorialActive) shop side cards, deal pop-ups, the
	Daily card and one-time tips wait; held tips show at the end. An old save
	that skipped it gets "replay it in ⚙ Settings" once.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local TutorialCards = require(UI.TutorialCards)
local TutorialBanner = require(UI.TutorialBanner)
local TutorialExplain = require(UI.TutorialExplain)
local TutorialHand = require(UI.TutorialHand)
local HudGate = require(UI.HudGate)
local FusePanel = require(UI.FusePanel)
local RebirthPanel = require(UI.RebirthPanel)
local GiftsPanel = require(UI.GiftsPanel)
local QuestsPanel = require(UI.QuestsPanel)
local EventInfoCard = require(UI.EventInfoCard)
local TutorialPath = require(script.Parent.Parent.Effects.TutorialPath)
local TycoonController = require(script.Parent.TycoonController)
local InventoryController = require(script.Parent.InventoryController)
local GoalMarkerController = require(script.Parent.GoalMarkerController)
local HudController = require(script.Parent.HudController)
local EventController = require(script.Parent.EventController)
local ToastController = require(script.Parent.ToastController)
local ResultController = require(script.Parent.ResultController)

local TutorialController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local FIRST_STEP_DELAY = 1 -- after joining: let the world settle, then the first banner
local ARRIVE_STUDS = 8 -- inside this the distance is dropped (you're there)
local PEDESTAL_POP_OFFSET = 6 -- studs above a pedestal for "+$X/s"
local RESEND_SECONDS = 2
local WAIT_STEP = 0.1 -- how often a wait looks again
local QUIET_TIMEOUT = 120 -- a panel the player leaves open cannot stall the tutorial for ever
local SPLASH_TIMEOUT = 4
local NICE_TEXT = "Nice!"
local EXPLAIN_OVERLAY = "TutorialExplain" -- the card's own UIKit overlay name

local localPlayer = Players.LocalPlayer

local presented: number? = nil -- the step on screen (its card, banner or ✓)
local serverStep = 0 -- the snapshot's step (it can be ahead of `presented`)
local active = false -- the snapshot says the tutorial is running
local runnerSeq = 0 -- bumped to stop a runner
local runnerRunning = false
local lastPlayed: number? = nil -- the last step played to its end
local begun = 0 -- the highest step begun (HudGate reveals up to it)
local guideUp = false -- the banner, path and hand are live for `presented`
local bannerShownAt = 0
local stepStart = 0 -- os.clock() the presented step's banner came in
local advanceSentFor: number? = nil
local replayHintShown = false
local wasActive = false
local pedestalPops: { BillboardGui } = {}
local lastSub: string? = nil
local pressing = false
local openSeen = false -- an Open step's card / panel has been up (it ends when it is closed)

--[[ Steps ----------------------------------------------------------------------------- ]]

local function presentedStep(): TutorialConfig.Step?
	local index = presented
	return if index then TutorialConfig.GetStep(index) else nil
end

local function sendAdvance(stepIndex: number)
	-- Only the server's current step can be advanced (the presenter may be
	-- showing an older one).
	if advanceSentFor == stepIndex or not active or stepIndex ~= serverStep then
		return
	end
	advanceSentFor = stepIndex
	RemoteEvents.TutorialAdvance:FireServer({ Step = stepIndex })
	-- A lost reply (or a refused re-check) lets the client ask again.
	task.delay(RESEND_SECONDS, function()
		if advanceSentFor == stepIndex then
			advanceSentFor = nil
		end
	end)
end

-- Multiplier: the level-1 price while it is out of reach right now.
local function multiplierShortfall(): number?
	local cost = TycoonConfig.GetCashMultiplierUpgradeCost(TycoonController.GetCashMultiplierLevel())
	if cost and TycoonController.GetCash() < cost then
		return cost
	end
	return nil
end

local function rootPosition(): Vector3?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

--[[ World prompts ------------------------------------------------------------------------ ]]

-- The step's ProximityPrompt at its target, once built.
local function findPrompt(step: TutorialConfig.Step): ProximityPrompt?
	if not step.Target or not step.PromptName then
		return nil
	end
	local target = GoalMarkerController.ResolvePlotTarget(step.Target)
	local found = target and target:FindFirstChild(step.PromptName, true)
	return if found and found:IsA("ProximityPrompt") then found else nil
end

local function promptPosition(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

-- Standing close enough that the prompt's own E would work.
local function inReach(prompt: ProximityPrompt): boolean
	local position = promptPosition(prompt)
	local here = rootPosition()
	-- The Gacha Pad's own prompts are OFF (the card's key bar replaced them):
	-- its button is still "in reach" by distance alone.
	local usable = prompt.Enabled or prompt.Name == "PullPrompt"
	return position ~= nil and here ~= nil and usable and (position - here).Magnitude <= prompt.MaxActivationDistance
end

-- The big button: the real prompt, triggered from the client.
local function pressPrompt(step: TutorialConfig.Step)
	if pressing then
		return
	end
	local prompt = findPrompt(step)
	if not prompt or not inReach(prompt) then
		return
	end
	pressing = true
	if prompt.Name == "PullPrompt" then
		-- The Gacha Pad: the same remote the card's E key sends, so the
		-- server runs the one shared pull function.
		RemoteEvents.RequestGachaPull:FireServer({ Count = 1 })
		task.delay(0.5, function()
			pressing = false
		end)
		return
	end
	task.spawn(function()
		prompt:InputHoldBegin()
		RunService.Heartbeat:Wait()
		prompt:InputHoldEnd()
		pressing = false
	end)
end

--[[ "+$X/s" over each pedestal's orb (the pedestals step) --------------------------------- ]]

local function clearPedestalPops()
	for _, gui in pedestalPops do
		gui:Destroy()
	end
	table.clear(pedestalPops)
end

local function showPedestalPops()
	clearPedestalPops()
	local multiplier = TycoonController.GetIncomeMultiplier()
	local byUid: { [string]: any } = {}
	for _, item in InventoryController.GetInventory() do
		byUid[item.Uid] = item
	end
	for index, uid in TycoonController.GetPedestalDisplays() do
		local item = byUid[uid]
		local pedestal = GoalMarkerController.ResolvePlotTarget("Pedestal" .. index)
		if item and pedestal and pedestal:IsA("BasePart") then
			local gui = Instance.new("BillboardGui")
			gui.Name = "TutorialIncomePop"
			gui.Adornee = pedestal
			gui.Size = UDim2.fromOffset(190, 44)
			gui.StudsOffset = Vector3.new(0, PEDESTAL_POP_OFFSET, 0)
			gui.AlwaysOnTop = true
			gui.LightInfluence = 0
			gui.ResetOnSpawn = false
			gui.Parent = localPlayer:WaitForChild("PlayerGui")
			UIKit.Label({
				Name = "Income",
				Text = ("+%s/s"):format(NumberFormat.Money(TycoonConfig.GetStackCashPerSecond(item) * multiplier)),
				Font = Fonts.Display,
				TextSize = 30,
				TextColor3 = Colors.Cash,
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				Stroke = UITheme.Stroke.Text,
				Parent = gui,
			})
			table.insert(pedestalPops, gui)
		end
	end
end

--[[ Presenting a step -------------------------------------------------------------------- ]]

-- Tutorial 4's rule: ONE STEP AT A TIME, in order, whatever the server's
-- step already is (it moves the moment the real action happens, so it can be
-- several steps ahead of what the player has been shown). A step is:
--   explain card (OK after the read time) -> banner / path / hand ->
--   done -> "✓ Nice!" -> the bar slides out -> a pause with nothing new ->
--   the next step. A step the player already did ahead of time still gets
--   its card, then completes at once with "Already done ✓".

local function isStepDone(index: number): boolean
	return not active or serverStep > index
end

-- Nothing the player opened is still up (a panel, a card, the event info, a
-- result card): the next step never starts over it.
local function screenQuiet(): boolean
	return not UIKit.IsOverlayOpen(EXPLAIN_OVERLAY)
		and not ResultController.IsBigCardOpen()
		and not EventInfoCard.IsOpen()
		and not TutorialCards.IsOpen()
end

local function waitFor(mine: number, predicate: () -> boolean, timeout: number?): boolean
	local started = os.clock()
	while runnerSeq == mine do
		if predicate() then
			return true
		end
		if timeout and os.clock() - started >= timeout then
			return false
		end
		task.wait(WAIT_STEP)
	end
	return false
end

-- The hand, the path, the goal arrow and the pedestal pops (not the card or
-- the banner).
local function stopGuidance()
	guideUp = false
	TutorialHand.SetContextual(nil, nil)
	TutorialHand.SetTarget(nil)
	TutorialPath.SetEnabled(false)
	GoalMarkerController.SetTutorialTarget(nil, nil, TycoonController.IsTutorialActive())
	clearPedestalPops()
end

local function labName(): string
	return ("%s'S LAB"):format(localPlayer.DisplayName:upper())
end

-- The banner, path and goal arrow for step `index` (after its explain card).
local function beginGuidance(index: number)
	local step = TutorialConfig.GetStep(index)
	if not step or presented ~= index then
		return
	end
	local t = TycoonController.GetTutorial()
	openSeen = false
	stepStart = os.clock()
	bannerShownAt = stepStart
	advanceSentFor = nil
	lastSub = step.Sub
	-- The event card gets its "OK, got it" while this step runs.
	EventInfoCard.SetTutorialOk(step.Id == "events")
	TutorialBanner.Show(step.Banner, step.Sub, step.Icon, index, #TutorialConfig.Steps)
	TutorialBanner.SetSkip(if t.Replay then function()
		sendAdvance(index)
	end else nil)
	if step.Target then
		GoalMarkerController.SetTutorialTarget(step.Target, step.Banner, true)
		TutorialPath.SetEnabled(true)
	else
		GoalMarkerController.SetTutorialTarget(nil, nil, true)
		TutorialPath.SetEnabled(false)
	end
	guideUp = true
end

-- The explain card: true once the player pressed OK (or closed it).
local function showCard(step: TutorialConfig.Step, mine: number): boolean
	local card = step.Card
	if not card then
		return true
	end
	local model = if card.Model then GoalMarkerController.ResolvePlotTarget(card.Model) else nil
	local closed = false
	TutorialExplain.Show(card, model, function()
		closed = true
	end)
	waitFor(mine, function()
		return closed or not active
	end)
	return closed
end

-- Plays step `index` from its card to the pause after it. False: the runner
-- was stopped (a restart, the tutorial ended).
local function playStep(index: number, mine: number): boolean
	local step = TutorialConfig.GetStep(index)
	if not step then
		return false
	end
	presented = index
	begun = math.max(begun, index)
	stepStart = os.clock()
	advanceSentFor = nil
	openSeen = false
	lastSub = step.Sub
	local already = isStepDone(index)
	if step.Id == "pedestals" and not already then
		showPedestalPops()
	end

	-- 1. The explain card, on a quiet screen (after CardDelay: INDEX has
	-- popped in by then).
	if step.Card then
		waitFor(mine, screenQuiet, QUIET_TIMEOUT)
		if (step.CardDelay or 0) > 0 and runnerSeq == mine then
			task.wait(step.CardDelay)
		end
		if runnerSeq ~= mine then
			return false
		end
		showCard(step, mine)
		if runnerSeq ~= mine then
			return false
		end
		-- The action may have happened while the card was up.
		already = isStepDone(index)
	end

	-- 2. The instruction, until the step is done.
	local hasBanner = false
	if already then
		-- Done ahead of time: the bar says so and moves on.
		TutorialBanner.Show(step.Banner, nil, step.Icon, index, #TutorialConfig.Steps)
		bannerShownAt = os.clock()
		hasBanner = true
	elseif step.CardEnds and not step.HoldSeconds then
		-- OK on the card ends the step (Index).
		waitFor(mine, function()
			sendAdvance(index)
			return isStepDone(index)
		end)
	else
		beginGuidance(index)
		hasBanner = true
		waitFor(mine, function()
			return isStepDone(index)
		end)
	end
	if runnerSeq ~= mine then
		return false
	end

	-- 3. Done: the hand and path go now; the instruction stays up its minimum
	-- time, then "✓ Nice!".
	stopGuidance()
	if hasBanner then
		if not already then
			local remaining = TutorialConfig.BannerMinSeconds - (os.clock() - bannerShownAt)
			if remaining > 0 then
				task.wait(remaining)
			end
			if runnerSeq ~= mine then
				return false
			end
		end
		if step.Id == "claim" then
			TutorialBanner.ShowSplash("WELCOME TO YOUR LAB!", labName())
		end
		SoundKit.Play("RevealMinor", nil)
		TutorialBanner.Complete(TutorialConfig.NiceSeconds, if already then TutorialConfig.AlreadyDoneText else NICE_TEXT)
	else
		SoundKit.Play("RevealMinor", nil)
	end
	if step.Id == "events" then
		-- A card the player opened stays open: only the "OK, got it" button goes.
		EventInfoCard.SetTutorialOk(false)
	end
	TutorialBanner.SetSkip(nil)

	-- 4. The pause: whatever the step opened is closed, the bar is out, the
	-- welcome splash is over, and a beat of nothing new.
	waitFor(mine, screenQuiet, QUIET_TIMEOUT)
	task.wait(TutorialConfig.SettleSeconds)
	waitFor(mine, function()
		return not TutorialBanner.IsSplashShown()
	end, SPLASH_TIMEOUT)
	return runnerSeq == mine
end

local function endTutorial()
	presented = nil
	lastPlayed = nil
	begun = 0
	TutorialBanner.SetSkip(nil)
	TutorialBanner.Hide()
	stopGuidance()
	TutorialCards.Close()
	TutorialExplain.Close()
	EventInfoCard.SetTutorialOk(false)
	ToastController.FlushHeld()
end

local function runTutorial(mine: number)
	-- The world settles first.
	task.wait(FIRST_STEP_DELAY)
	while runnerSeq == mine and active do
		local index = if lastPlayed then lastPlayed + 1 else serverStep
		if index > #TutorialConfig.Steps then
			break
		end
		if not playStep(index, mine) then
			break
		end
		lastPlayed = index
	end
	if runnerSeq == mine then
		runnerRunning = false
		wasActive = false
		endTutorial()
		-- After the tutorial the path follows the current goal (👣).
		local t = TycoonController.GetTutorial()
		TutorialPath.SetEnabled(t.Done and TycoonController.IsGoalPathOn())
	end
end

-- Stops the runner where it stands (a restart from step 1, a debug jump).
local function abortRunner()
	runnerSeq += 1
	runnerRunning = false
	guideUp = false
	TutorialExplain.Close()
	stopGuidance()
	TutorialBanner.Hide()
	EventInfoCard.SetTutorialOk(false)
end

local function startRunner()
	runnerSeq += 1
	local mine = runnerSeq
	runnerRunning = true
	task.spawn(runTutorial, mine)
end

local function onTycoonChanged()
	if not TycoonController.HasSynced() then
		return
	end
	local t = TycoonController.GetTutorial()
	if t.ReplayHint and not replayHintShown and not TycoonController.HasSeenTip("tutorialReplay") then
		replayHintShown = true
		TycoonController.MarkTipSeen("tutorialReplay")
		ToastController.Show("New: replay the tutorial in ⚙ Settings", "Neutral", { Big = true })
	end
	local nowActive = TycoonController.IsTutorialActive() and t.Step >= 1
	if not nowActive then
		active = false
		if not runnerRunning then
			-- After the tutorial the path follows the current goal (👣).
			if wasActive then
				wasActive = false
				endTutorial()
			end
			TutorialPath.SetEnabled(t.Done and TycoonController.IsGoalPathOn())
		end
		-- A running step finishes its ✓ and pause; the runner then ends it.
		return
	end
	local previous = serverStep
	serverStep = t.Step
	active = true
	wasActive = true
	-- The server went back (a replay, /tutorial step): start over from there.
	if runnerRunning and (t.Step < previous or (lastPlayed ~= nil and t.Step <= lastPlayed)) then
		abortRunner()
		lastPlayed = nil
		begun = 0
		presented = nil
	end
	if not runnerRunning then
		if lastPlayed ~= nil and t.Step <= lastPlayed then
			lastPlayed = nil
			begun = 0
		end
		startRunner()
	end
end

--[[ Every frame ----------------------------------------------------------------------------- ]]

local function flatDistance(from: Vector3, to: Vector3): number
	return Vector3.new(from.X - to.X, 0, from.Z - to.Z).Magnitude
end

-- What the hand points at for the presented step, or nil.
local function handTarget(step: TutorialConfig.Step, contextual: boolean): GuiObject?
	if ResultController.IsBigCardOpen() then
		return nil
	end
	if step.Id == "fuse" and FusePanel.IsOpen() then
		-- 2 taps: AUTO-FILL, then FUSE (the odds are not part of the tutorial).
		return FusePanel.GetCoachTarget(if FusePanel.GetSelectedCount() < 2 then "AutoFill" else "Fuse")
	end
	if contextual then
		return TutorialHand.GetContextualButton()
	end
	if step.Hand == "EventChip" then
		return EventController.GetChip()
	elseif step.Hand then
		return HudController.GetCoachTarget(step.Hand)
	end
	return nil
end

local function stepFrame()
	local tutorialStep = presentedStep()
	if not tutorialStep or not guideUp or not active then
		return
	end
	local index = presented :: number
	local elapsed = os.clock() - stepStart
	local here = rootPosition()

	-- The distance on the banner: only while there is a way to go.
	local marked = GoalMarkerController.GetMarkedPosition()
	local distance: number? = nil
	if tutorialStep.Target and marked and here then
		local d = flatDistance(here, marked)
		if d > ARRIVE_STUDS then
			distance = d
		end
	end
	TutorialBanner.SetDistance(distance)

	-- The sub line: the Multiplier Pad says what to come back with.
	local shortfall = if tutorialStep.Id == "multiplier" then multiplierShortfall() else nil
	local sub = if shortfall then ("Come back with %s"):format(NumberFormat.Money(shortfall)) else tutorialStep.Sub
	if sub ~= lastSub then
		lastSub = sub
		TutorialBanner.SetSub(sub)
	end

	-- The big button, at a world target with a prompt.
	local showButton = false
	if tutorialStep.Prompt and not ResultController.IsBigCardOpen() and not FusePanel.IsOpen() and shortfall == nil then
		local prompt = findPrompt(tutorialStep)
		showButton = prompt ~= nil and inReach(prompt)
	end
	if showButton then
		TutorialHand.SetContextual(tutorialStep.Prompt, function()
			pressPrompt(tutorialStep)
		end)
	else
		TutorialHand.SetContextual(nil, nil)
	end
	TutorialHand.SetTarget(handTarget(tutorialStep, showButton))

	-- Completion that isn't a server-confirmed action. Nothing ends while a
	-- card or panel is up.
	if tutorialStep.HoldSeconds then
		-- Pedestals: after its card the orbs earn on screen at least this long.
		if elapsed >= tutorialStep.HoldSeconds and screenQuiet() then
			sendAdvance(index)
		end
	elseif tutorialStep.Kind == "Timed" then
		if elapsed >= (tutorialStep.Seconds or 0) and screenQuiet() then
			sendAdvance(index)
		end
	elseif tutorialStep.Kind == "Open" then
		-- Done when the player CLOSES what they opened (✕, a tap outside, the
		-- card's OK); it stays open until then, and the Seconds fallback only
		-- applies to a player who never opened it.
		local open = (tutorialStep.Id == "events" and EventInfoCard.IsOpen())
			or (tutorialStep.Id == "rebirth" and RebirthPanel.IsOpen())
		if open then
			openSeen = true
		end
		if (openSeen and not open) or (not openSeen and elapsed >= (tutorialStep.Seconds or 0)) then
			sendAdvance(index)
		end
		if open then
			TutorialHand.SetTarget(nil) -- it is already open: nothing to point at
		end
	elseif shortfall and elapsed >= (tutorialStep.SkipSeconds or 3) then
		sendAdvance(index)
	end
end

--[[ Just-in-time hands (after the tutorial) ----------------------------------------------- ]]

local JIT = {
	{ Tip = "giftHand", Opened = GiftsPanel.IsOpen, Ready = function(): boolean
		return GiftsPanel.GetStatus() > 0
	end, Name = "Gifts" },
	{ Tip = "questHand", Opened = QuestsPanel.IsOpen, Ready = function(): boolean
		return QuestsPanel.GetReadyCount() > 0
	end, Name = "Quests" },
}

local jitShowing: string? = nil

-- The first time a gift is ready (and the first claimable quest) the hand
-- points at its button once; opening the panel ends it for good.
local function jitFrame()
	if not TycoonController.HasSynced() or not TycoonController.GetTutorial().Done or TycoonController.GetTutorial().Replay then
		return
	end
	if TutorialHand.GetTarget() ~= nil and jitShowing == nil then
		return -- the tutorial's own hand is up
	end
	if jitShowing then
		for _, entry in JIT do
			if entry.Tip == jitShowing then
				if entry.Opened() or TycoonController.HasSeenTip(entry.Tip) then
					TycoonController.MarkTipSeen(entry.Tip)
					jitShowing = nil
					TutorialHand.SetTarget(nil)
				end
			end
		end
		return
	end
	if UIKit.IsOverlayOpen() then
		return
	end
	for _, entry in JIT do
		if not TycoonController.HasSeenTip(entry.Tip) and entry.Ready() then
			local button = HudController.GetCoachTarget(entry.Name)
			if button and button.Visible then
				jitShowing = entry.Tip
				TutorialHand.SetTarget(button)
				return
			end
		end
	end
end

-- The current step's banner text and what is up (/selftest).
function TutorialController.GetPresentedStep(): TutorialConfig.Step?
	return presentedStep()
end

function TutorialController.GetBannerText(): string
	return TutorialBanner.GetText()
end

function TutorialController.Init()
	TutorialCards.Init()
	TutorialExplain.Init()
	TutorialBanner.Init()
	TutorialHand.Init()
	TutorialPath.Init()
	TutorialPath.SetTargetSource(GoalMarkerController.GetMarkedPosition)
	ToastController.SetBigHold(TycoonController.IsTutorialActive)
	-- The HUD reveals up to the step the player has been shown.
	HudGate.SetStepSource(function(): number?
		return if active and begun > 0 then begun else nil
	end)
	-- The LOCK console's and Gacha Pad's "How it works" (H) prompts.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, triggeringPlayer: Player)
		local topic = prompt:GetAttribute("HelpTopic")
		if triggeringPlayer == localPlayer and prompt.Name == "HelpPrompt" and typeof(topic) == "string" then
			TutorialCards.ShowTopic(topic)
		end
	end)
	TycoonController.TycoonChanged:Connect(onTycoonChanged)
	RunService.RenderStepped:Connect(function()
		stepFrame()
		jitFrame()
	end)
	onTycoonChanged()
end

return TutorialController
