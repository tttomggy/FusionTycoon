--!strict
--[[
	TutorialController
	------------------
	Drives the first-time tutorial on the client (Tutorial 5: four steps,
	claim / pull 2 / fuse / ready, under a minute; the steps are
	TutorialConfig.Steps, the server owns the step, TutorialService, and
	sends it in the snapshot). One instruction at a time; a step that
	introduces something opens one big explain card first (UI/TutorialExplain:
	only Fusing has one, its OK is live at once):

	  1. THE OBJECTIVE BAR (UI/TutorialBanner), top centre under the Roblox
	     top bar: icon, the step's instruction ("Pull 2 free orbs 0/2": a
	     step with `Count` shows the live count), "2 / 4", and while it has a
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
	     big button; in the Fuse panel AUTO-FILL then FUSE. Never a rectangle.
	  5. Done: "Action" steps only when the server confirms the real action
	     (the snapshot's Step moves on); "Timed" steps ask the
	     server (TutorialAdvance, re-checked) after their Seconds. Then the banner shows "✓ Nice!" and the
	     Step sound; the next step starts after a pause (Tutorial 4: ONE
	     step at a time, in order, see "Presenting a step" below).

	Besides the Fusing card there is the welcome splash after the claim
	("WELCOME TO YOUR LAB!", fades by itself). The HUD builds up as it goes
	(UI/HudGate): this file only tells it nothing: the gate reads the same
	saved step. The pedestals have no step: when the first pull lands on one,
	its "+$X/s" shows for a few seconds with one TopStack line.

	After it, the one-time TIPS (TutorialConfig.Tips; the tip runner below):
	a hand on the thing plus one TopStack line, once per account, at most one
	at a time, 20 s apart, never a card: UPGRADES (cash >= the cheapest
	upgrade), the Multiplier Pad, INDEX (a new entry), the event chip, REBIRTH
	(50%), and the old giftHand / questHand. While the tutorial runs
	(TycoonController.IsTutorialActive) shop side cards, deal pop-ups, the
	Daily card and big tips wait; held tips show at the end. An old save
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
local MissionBanner = require(UI.MissionBanner)
local TutorialExplain = require(UI.TutorialExplain)
local TutorialHand = require(UI.TutorialHand)
local HudGate = require(UI.HudGate)
local FusePanel = require(UI.FusePanel)
local GiftsPanel = require(UI.GiftsPanel)
local QuestsPanel = require(UI.QuestsPanel)
local UpgradesPanel = require(UI.UpgradesPanel)
local IndexPanel = require(UI.IndexPanel)
local RebirthPanel = require(UI.RebirthPanel)
local EventInfoCard = require(UI.EventInfoCard)
local TutorialPath = require(script.Parent.Parent.Effects.TutorialPath)
local TycoonController = require(script.Parent.TycoonController)
local InventoryController = require(script.Parent.InventoryController)
local GoalMarkerController = require(script.Parent.GoalMarkerController)
local HudController = require(script.Parent.HudController)
local EventController = require(script.Parent.EventController)
local ToastController = require(script.Parent.ToastController)
local ResultController = require(script.Parent.ResultController)
local AnnouncementController = require(script.Parent.AnnouncementController)

local TutorialController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local PEDESTAL_POP_SECONDS = 4 -- "+$X/s" over the pedestal the first pull landed on
local ARRIVE_STUDS = 8 -- inside this the distance is dropped (you're there)
local PEDESTAL_POP_OFFSET = 6 -- studs above a pedestal for "+$X/s"
local RESEND_SECONDS = 2
local WAIT_STEP = 0.1 -- how often a wait looks again
local QUIET_TIMEOUT = 20 -- a panel the player leaves open holds the next step this long, not for ever
local CARD_SHOW_TIMEOUT = 3 -- an explain card that is not drawn by then is dropped (warn), the banner goes on
local CARD_MAX_SECONDS = 90 -- a card nobody answers closes by itself after this long
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
local bannerVisibleSeconds = 0 -- seconds the presented instruction has really been on screen (see tickBannerClock)
local bannerClockAt = 0
local clock = os.clock -- /selftest injects its own (SelfTestSetClock)
local advanceSentFor: number? = nil
local replayHintShown = false
local wasActive = false
local pedestalPops: { BillboardGui } = {}
local pedestalPopUntil = 0 -- os.clock() the "+$X/s" pops go
local pedestalHintShown = false -- the pedestal line was shown for this run of the tutorial
local applyPath: () -> () -- the path's on/off: a tip's own target, else the goal path (defined with the tips)
local tipPressing: TutorialConfig.TipDef? = nil -- a world tip (the Multiplier Pad, a rival lab): its path and big button are up
local rivalDeliveriesAtTipStart = 0 -- tipRival ends on the next delivered rival steal
local pressing = false

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

local function rootPosition(): Vector3?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

--[[ World prompts ------------------------------------------------------------------------ ]]

-- The step's ProximityPrompt at its target, once built.
local function findPrompt(step: { Target: string?, PromptName: string? }): ProximityPrompt?
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
local function pressPrompt(step: { Target: string?, PromptName: string? })
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
		-- A hold prompt (the rival steal, 1.5 s) needs the whole hold.
		if prompt.HoldDuration > 0 then
			task.wait(prompt.HoldDuration + 0.15)
		else
			RunService.Heartbeat:Wait()
		end
		prompt:InputHoldEnd()
		pressing = false
	end)
end

--[[ "+$X/s" over each pedestal's orb (when the first pull lands on one) --------------------- ]]

local function clearPedestalPops()
	for _, gui in pedestalPops do
		gui:Destroy()
	end
	table.clear(pedestalPops)
end

local function showPedestalPops(): number
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
	return #pedestalPops
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

-- The instruction is really in front of the player: shown, slid in (not out
-- under a centred card) and the screen quiet.
local function bannerVisibleNow(): boolean
	return TutorialBanner.IsShown() and not TutorialBanner.IsCovered() and screenQuiet()
end

-- Every frame: the presented instruction's clock counts only the visible
-- seconds (TutorialConfig.AdvanceBannerClock). A hitch is capped, so one
-- long frame cannot stand in for a second on screen.
local MAX_CLOCK_STEP = 0.5
local function tickBannerClock()
	local now = clock()
	local dt = math.clamp(now - bannerClockAt, 0, MAX_CLOCK_STEP)
	bannerClockAt = now
	bannerVisibleSeconds = TutorialConfig.AdvanceBannerClock(bannerVisibleSeconds, dt, bannerVisibleNow())
end

-- A new instruction goes up: its clock starts from nothing.
local function resetBannerClock()
	bannerVisibleSeconds = 0
	bannerClockAt = clock()
end

-- The server moved past a step the player was never shown, and it is a step
-- the server skips when the save already satisfies it (TutorialConfig `Skip`:
-- the Multiplier already bought): nothing is left to teach or to do.
local function serverSkipped(index: number, step: TutorialConfig.Step): boolean
	return active and step.Skip ~= nil and serverStep > index
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
end

local function labName(): string
	return ("%s'S LAB"):format(localPlayer.DisplayName:upper())
end

-- The instruction as shown: a step with a Count (the pull step) carries its
-- live "0/2" after the words.
local function bannerText(step: TutorialConfig.Step): string
	local count = step.Count
	if not count then
		return step.Banner
	end
	local done = if step.Id == "pull" then TycoonController.GetTutorial().PullsDone else 0
	return ("%s %d/%d"):format(step.Banner, math.clamp(done, 0, count), count)
end

-- The banner, path and goal arrow for step `index` (after its explain card).
local function beginGuidance(index: number)
	local step = TutorialConfig.GetStep(index)
	if not step or presented ~= index then
		return
	end
	local t = TycoonController.GetTutorial()
	resetBannerClock()
	advanceSentFor = nil
	TutorialBanner.Show(bannerText(step), step.Sub, step.Icon, index, #TutorialConfig.Steps)
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

-- The explain card is on screen: open and with a size you can see.
local function cardDrawn(): boolean
	local body = TutorialExplain.GetBody()
	return TutorialExplain.IsOpen() and body ~= nil and body.AbsoluteSize.X > 0 and body.AbsoluteSize.Y > 0
end

-- The explain card. Returns (closed, drawn): `closed` is true once the player
-- pressed OK (or closed it); `drawn` is false when the card never showed
-- (warned, the step goes on to its banner). A card the server moved past, or
-- that nobody answers for CARD_MAX_SECONDS, is closed without an OK.
local function showCard(step: TutorialConfig.Step, index: number, mine: number): (boolean, boolean)
	local card = step.Card
	if not card then
		return true, true
	end
	local model = if card.Model then GoalMarkerController.ResolvePlotTarget(card.Model) else nil
	local closed = false
	TutorialExplain.Show(card, model, function()
		closed = true
	end)
	local drawn = closed or waitFor(mine, function()
		return closed or cardDrawn()
	end, CARD_SHOW_TIMEOUT)
	if runnerSeq ~= mine then
		return closed, true
	end
	if not drawn then
		warn(("[Tutorial] step %d (%s): its explain card did not show within %d s; going on to the banner"):format(index, step.Id, CARD_SHOW_TIMEOUT))
		TutorialExplain.Close()
		return false, false
	end
	waitFor(mine, function()
		return closed or not active or serverStep > index
	end, CARD_MAX_SECONDS)
	if not closed and runnerSeq == mine then
		TutorialExplain.Close()
	end
	return closed, true
end

-- Plays step `index` from its card to the pause after it. False: the runner
-- was stopped (a restart, the tutorial ended). The second value is true when
-- the server moved past the step (skipped, or while its card was up): the
-- runner then goes to the server's step, not to index + 1.
local function playStep(index: number, mine: number): (boolean, boolean?)
	local step = TutorialConfig.GetStep(index)
	if not step then
		return false
	end
	presented = index
	-- A Timed step reveals its HUD pieces once its banner is really on screen
	-- (stepFrame), so "You're ready!" is up while they pop in one by one.
	if step.Kind ~= "Timed" then
		begun = math.max(begun, index)
	end
	if serverSkipped(index, step) then
		-- The server skipped it (already satisfied): present the server's step.
		return true, true
	end
	advanceSentFor = nil
	local already = isStepDone(index)

	-- 1. The explain card, on a quiet screen (after CardDelay: INDEX has
	-- popped in by then).
	if step.Card then
		waitFor(mine, function()
			return screenQuiet() or serverSkipped(index, step)
		end, QUIET_TIMEOUT)
		if (step.CardDelay or 0) > 0 and runnerSeq == mine then
			task.wait(step.CardDelay)
		end
		if runnerSeq ~= mine then
			return false
		end
		if serverSkipped(index, step) then
			return true, true
		end
		local closed = showCard(step, index, mine)
		if runnerSeq ~= mine then
			return false
		end
		-- The server moved on while the card was up and the player never
		-- answered it: drop it and present the server's step.
		if not closed and active and serverStep > index then
			return true, true
		end
		-- The action may have happened while the card was up.
		already = isStepDone(index)
	end

	-- 2. The instruction, until the step is done.
	local hasBanner = false
	if already then
		-- Done ahead of time: the bar says so and moves on.
		TutorialBanner.Show(step.Banner, nil, step.Icon, index, #TutorialConfig.Steps)
		resetBannerClock()
		begun = math.max(begun, index)
		hasBanner = true
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
			-- The instruction stays up its minimum VISIBLE time (a card on top
			-- does not count), and is in front of the player when "✓ Nice!"
			-- replaces it.
			waitFor(mine, function()
				return bannerVisibleSeconds >= TutorialConfig.BannerMinSeconds
			end, CARD_MAX_SECONDS)
			waitFor(mine, bannerVisibleNow, QUIET_TIMEOUT)
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
	clearPedestalPops()
	pedestalPopUntil = 0
	pedestalHintShown = false
	ToastController.FlushHeld()
end

local function runTutorial(mine: number)
	-- The world settles first.
	task.wait(TutorialConfig.FirstStepDelay)
	while runnerSeq == mine and active do
		local index = if lastPlayed then lastPlayed + 1 else serverStep
		if index > #TutorialConfig.Steps then
			break
		end
		local played, jumped = playStep(index, mine)
		if not played then
			break
		end
		local reached = if jumped then math.max(index, serverStep - 1) else index
		lastPlayed = reached
		begun = math.max(begun, reached)
	end
	if runnerSeq == mine then
		runnerRunning = false
		wasActive = false
		endTutorial()
		-- After the tutorial the path follows the current goal (👣).
		local t = TycoonController.GetTutorial()
		applyPath()
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
	pedestalHintShown = false
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
			applyPath()
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
	if step.Hand then
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
	local here = rootPosition()
	if tutorialStep.Kind == "Timed" and bannerVisibleNow() then
		begun = math.max(begun, index)
	end

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

	-- The live count in the instruction ("Pull 2 free orbs 1/2").
	if tutorialStep.Count then
		TutorialBanner.SetText(bannerText(tutorialStep))
	end

	-- The big button, at a world target with a prompt.
	local showButton = false
	if tutorialStep.Prompt and not ResultController.IsBigCardOpen() and not FusePanel.IsOpen() then
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

	-- Completion that isn't a server-confirmed action: the last step is Timed
	-- (the server re-checks its own clock). Its clock is the VISIBLE seconds
	-- of the banner, so nothing ends behind a card (TutorialConfig.TimedStepReady).
	if TutorialConfig.TimedStepReady(tutorialStep, bannerVisibleSeconds) then
		sendAdvance(index)
	end
end

--[[ The pedestal line (no step: the first pull that lands on a pedestal) --------------- ]]

local function pedestalFrame()
	if pedestalPopUntil > 0 and os.clock() >= pedestalPopUntil then
		pedestalPopUntil = 0
		clearPedestalPops()
	end
	if pedestalHintShown or not active or TycoonController.GetTutorial().Replay then
		return
	end
	if next(TycoonController.GetPedestalDisplays()) == nil then
		return
	end
	-- Only once the orb is in the inventory (its "+$X/s" needs it).
	if showPedestalPops() == 0 then
		return
	end
	pedestalHintShown = true
	pedestalPopUntil = os.clock() + PEDESTAL_POP_SECONDS
	AnnouncementController.ShowLine(TutorialConfig.PedestalLine, "PedestalHint")
end

--[[ One-time tips (after the tutorial) --------------------------------------------------- ]]

-- TutorialConfig.Tips plus the two older just-in-time hands. At most one is
-- up (a hand on the thing + one TopStack line), the next waits TipGapSeconds
-- after it goes, each fires once per account (marked seen when it starts).
-- Over: the player opened what it points at, or TipMaxSeconds.
type TipRuntime = {
	Opened: () -> boolean,
	Hand: () -> GuiObject?,
	Ready: (() -> boolean)?, -- the older hands decide themselves
}

local tipShowing: string? = nil
local tipShownAt = 0
local tipGoneAt = -math.huge -- os.clock() the last tip went
local indexBaseline: number? = nil
local indexFound = false -- an Index entry appeared since the tutorial ended
local lastPlan = 0

local function handOf(name: string): () -> GuiObject?
	return function()
		return HudController.GetCoachTarget(name)
	end
end

local TIPS: { [string]: TipRuntime } = {
	tipUpgrade = { Opened = UpgradesPanel.IsOpen, Hand = handOf("Upgrades") },
	tipMultiplier = {
		Opened = function(): boolean
			return TycoonController.GetCashMultiplierLevel() >= 1
		end,
		Hand = function(): GuiObject?
			return TutorialHand.GetContextualButton()
		end,
	},
	tipIndex = { Opened = IndexPanel.IsOpen, Hand = handOf("Index") },
	tipEvent = { Opened = EventInfoCard.IsOpen, Hand = EventController.GetChip },
	tipRebirth = { Opened = RebirthPanel.IsOpen, Hand = handOf("Rebirth") },
	tipRival = {
		Opened = function(): boolean
			return TycoonController.GetRivalDeliveries() > rivalDeliveriesAtTipStart
		end,
		Hand = function(): GuiObject?
			return TutorialHand.GetContextualButton()
		end,
	},
	giftHand = {
		Opened = GiftsPanel.IsOpen,
		Hand = handOf("Gifts"),
		Ready = function(): boolean
			return GiftsPanel.GetStatus() > 0
		end,
	},
	questHand = {
		Opened = QuestsPanel.IsOpen,
		Hand = handOf("Quests"),
		Ready = function(): boolean
			return QuestsPanel.GetReadyCount() > 0
		end,
	},
}
local OLDER_HANDS = { "giftHand", "questHand" }

-- One set of arrows at a time: a tip with its own target (tipRival, the
-- Multiplier Pad) owns the path while it runs and the goal path (👣) is off;
-- otherwise the path follows the goal after the tutorial.
function applyPath()
	local running = if tipShowing ~= nil then tipPressing else nil
	TutorialPath.SetEnabled(TutorialConfig.PathOn(running, TycoonController.GetTutorial().Done, TycoonController.IsGoalPathOn()))
end

local function tipQuiet(): boolean
	return not UIKit.IsOverlayOpen() and screenQuiet()
end

local function indexCount(): number
	local total = 0
	for _ in TycoonController.GetIndex() do
		total += 1
	end
	return total
end

local function endTip()
	local id = tipShowing
	if not id then
		return
	end
	tipShowing = nil
	tipPressing = nil
	tipGoneAt = os.clock()
	TutorialHand.SetContextual(nil, nil)
	TutorialHand.SetTarget(nil)
	GoalMarkerController.SetTutorialTarget(nil, nil, false)
	GoalMarkerController.SetTipActive(false) -- the loop coach gets the arrow back
	if id == "tipRival" then
		MissionBanner.SetTip(false)
	end
	applyPath()
end

local function startTip(id: string)
	tipShowing = id
	GoalMarkerController.SetTipActive(true) -- a tip owns the arrow while it runs
	tipShownAt = os.clock()
	TycoonController.MarkTipSeen(id)
	if id == "tipRival" then
		rivalDeliveriesAtTipStart = TycoonController.GetRivalDeliveries()
	end
	local def = TutorialConfig.GetTip(id)
	if def then
		if id == "tipRival" then
			-- The mission box is this tip's text (no announcement line).
			MissionBanner.SetTip(true)
		else
			AnnouncementController.ShowLine(def.Line, "Tip")
		end
		if def.Target then
			tipPressing = def
			GoalMarkerController.SetTutorialTarget(def.Target, def.WorldLine or def.Line, true)
		end
	end
	applyPath()
end

-- The Index counter: what was found before the tutorial ended is not new.
local function trackIndex(done: boolean)
	local count = indexCount()
	if not done or indexBaseline == nil then
		indexBaseline = count
	elseif count > indexBaseline then
		indexBaseline = count
		indexFound = true
	end
end

local function tipState(done: boolean, replay: boolean): TutorialConfig.TipState
	local level = TycoonController.GetCashMultiplierLevel()
	local _, upgradeCost = TycoonConfig.GetCheapestUpgrade(TycoonController.GetGeneratorLevels())
	local cost = TycoonController.GetRebirthCost()
	local seen: { [string]: boolean } = {}
	for _, tip in TutorialConfig.Tips do
		seen[tip.Id] = TycoonController.HasSeenTip(tip.Id)
	end
	local chip = EventController.GetChip()
	local cash = TycoonController.GetCash()
	return {
		Done = done,
		Replay = replay,
		Quiet = tipQuiet(),
		Showing = tipShowing ~= nil,
		SinceGone = os.clock() - tipGoneAt,
		SinceDone = TycoonController.GetSecondsSinceTutorialDone(),
		Seen = seen,
		Cash = cash,
		UpgradeCost = if upgradeCost < math.huge then upgradeCost else nil,
		MultiplierLevel = level,
		MultiplierCost = TycoonConfig.GetCashMultiplierUpgradeCost(level),
		NewIndex = indexFound and not seen.tipIndex,
		EventChip = chip ~= nil and chip.Visible,
		RebirthProgress = if cost > 0 then cash / cost else 0,
		RivalLab = GoalMarkerController.ResolvePlotTarget("NearestRivalPedestal") ~= nil,
	}
end

local function tipFrame()
	if not TycoonController.HasSynced() then
		return
	end
	local t = TycoonController.GetTutorial()
	local now = os.clock()
	local due = now - lastPlan >= 0.25
	if due then
		lastPlan = now
		trackIndex(t.Done)
	end
	if not t.Done or t.Replay then
		if tipShowing then
			endTip()
		end
		return
	end

	-- A tip on screen: keep its hand on the thing, end it when followed.
	local id = tipShowing
	if id then
		local runtime = TIPS[id]
		local def = TutorialConfig.GetTip(id)
		local maxSeconds = (def and def.MaxSeconds) or TutorialConfig.TipMaxSeconds
		if not runtime or runtime.Opened() or os.clock() - tipShownAt >= maxSeconds then
			endTip()
			return
		end
		local pressing = tipPressing
		if pressing then
			local showButton = false
			if pressing.Prompt and not ResultController.IsBigCardOpen() then
				local prompt = findPrompt(pressing)
				showButton = prompt ~= nil and inReach(prompt)
			end
			if showButton then
				TutorialHand.SetContextual(pressing.Prompt, function()
					pressPrompt(pressing)
				end)
			else
				TutorialHand.SetContextual(nil, nil)
			end
		end
		local button = runtime.Hand()
		TutorialHand.SetTarget(if button and button.Visible and tipQuiet() then button else nil)
		return
	end

	-- Plan a new one a few times a second; another hand on screen wins.
	if not due or TutorialHand.GetTarget() ~= nil then
		return
	end
	local state = tipState(t.Done, t.Replay)
	local planned = TutorialConfig.PlanTip(state)
	if planned then
		if planned == "tipIndex" then
			indexFound = false
		end
		startTip(planned)
		return
	end
	-- The older just-in-time hands (a gift is ready, a quest can be claimed).
	if not state.Quiet or state.SinceGone < TutorialConfig.TipGapSeconds or state.SinceDone < TutorialConfig.TipAfterDoneSeconds then
		return
	end
	if TutorialConfig.RivalTipFirst(state) then
		return -- the steal comes first
	end
	for _, handId in OLDER_HANDS do
		local runtime = TIPS[handId]
		local button = runtime.Hand()
		if not TycoonController.HasSeenTip(handId) and (runtime.Ready :: () -> boolean)() and button and button.Visible then
			tipShowing = handId
			tipShownAt = now
			TycoonController.MarkTipSeen(handId)
			return
		end
	end
end

-- The current step's banner text and what is up (/selftest).
function TutorialController.GetPresentedStep(): TutorialConfig.Step?
	return presentedStep()
end

-- /selftest: the seconds the presented instruction has really been visible,
-- and a clock to count them on (nil puts os.clock back).
function TutorialController.GetBannerVisibleSeconds(): number
	return bannerVisibleSeconds
end

function TutorialController.SelfTestSetClock(injected: (() -> number)?)
	clock = injected or os.clock
	bannerClockAt = clock()
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
	resetBannerClock()
	RunService.RenderStepped:Connect(function()
		tickBannerClock()
		stepFrame()
		pedestalFrame()
		tipFrame()
	end)
	onTycoonChanged()
end

return TutorialController
