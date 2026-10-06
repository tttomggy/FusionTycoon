--!strict
--[[
	TutorialController
	------------------
	Drives the first-time tutorial on the client (TutorialConfig.Steps; the
	server owns the step, TutorialService, and sends it in the snapshot).

	For the current step:
	  1. The card (UI/TutorialCards): icon, title, two short sentences, OK.
	  2. After OK, the guidance: the goal arrow points at the step's Target
	     (GoalMarkerController's tutorial layer, with its pulsing floor
	     ring), the lit path runs there from your feet (Effects/TutorialPath)
	     and a pulsing coach ring wraps the step's HUD element (Coach). In the
	     Fuse panel the ring walks AUTO-FILL -> the odds chips -> FUSE.
	     Card steps with a Target / Coach show it while the card is open.
	  3. Done: Card steps on OK (TutorialAdvance, re-checked); Open steps
	     when that panel opens; Arrive steps when you reach the target
	     (server checks the distance); Action steps only when the server
	     confirms the real action (the snapshot's Step moves on). Then
	     "✓ Nice!" + the step sound, and the next card 0.6 s later (after any
	     big result card has closed).

	While it runs (TycoonController.IsTutorialActive) shop side cards, deal
	pop-ups, the Daily card and one-time tips wait; held tips show at the
	end. An old save that skipped it gets "replay it in ⚙ Settings" once.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local TutorialCards = require(UI.TutorialCards)
local FusePanel = require(UI.FusePanel)
local IndexPanel = require(UI.IndexPanel)
local RebirthPanel = require(UI.RebirthPanel)
local TutorialPath = require(script.Parent.Parent.Effects.TutorialPath)
local TycoonController = require(script.Parent.TycoonController)
local GoalMarkerController = require(script.Parent.GoalMarkerController)
local HudController = require(script.Parent.HudController)
local EventController = require(script.Parent.EventController)
local ToastController = require(script.Parent.ToastController)
local ResultController = require(script.Parent.ResultController)

local TutorialController = {}

local COACH_PAD = 8
local COACH_STROKE = 4
local COACH_PULSE = 1.08
local COACH_DISPLAY_ORDER = 170 -- over every panel, never takes a tap
local ODDS_COACH_SECONDS = 1.5
local BIG_CARD_WAIT_SECONDS = 6
local ARRIVE_MARGIN = 2

local localPlayer = Players.LocalPlayer

local shownStep: number? = nil -- the step whose card / guidance is up
local guiding = false -- OK pressed: the step's guidance runs
local cardToken = 0
local advanceSentFor: number? = nil
local oddsCoachUntil: number? = nil
local replayHintShown = false
local wasActive = false
-- os.clock() of the last OK that should have completed the step: if the
-- step hasn't moved RESHOW_SECONDS later (a refused re-check, a lost
-- reply), its card comes back.
local okAt: number? = nil
local RESHOW_SECONDS = 4

local coachGui: ScreenGui
local coachRing: Frame
local coachScale: UIScale

--[[ Coach ring --------------------------------------------------------------------- ]]

local function buildCoachRing()
	coachGui = UIKit.Screen("TutorialCoach", COACH_DISPLAY_ORDER)
	local ring = Instance.new("Frame")
	ring.Name = "CoachRing"
	ring.BackgroundTransparency = 1
	ring.Active = false
	ring.Visible = false
	ring.Parent = coachGui
	UIKit.Corner(ring, UITheme.Radius.Button + COACH_PAD)
	UIKit.Stroke(ring, COACH_STROKE, UITheme.Gradients.Gold.Top)
	coachScale = Instance.new("UIScale")
	coachScale.Parent = ring
	TweenService:Create(
		coachScale,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Scale = COACH_PULSE }
	):Play()
	coachRing = ring
end

-- Wraps `target` (any GuiObject on screen), or hides the ring.
local function placeCoach(target: GuiObject?)
	if not target or not target.Visible or target.AbsoluteSize.X <= 0 then
		coachRing.Visible = false
		return
	end
	local scale = UIKit.EffectiveScale(coachRing)
	local position = target.AbsolutePosition / scale
	local size = target.AbsoluteSize / scale
	coachRing.AnchorPoint = Vector2.new(0.5, 0.5)
	coachRing.Position = UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y / 2)
	coachRing.Size = UDim2.fromOffset(size.X + COACH_PAD * 2, size.Y + COACH_PAD * 2)
	coachRing.Visible = true
end

local function coachTarget(name: string): GuiObject?
	if name == "EventChip" then
		return EventController.GetChip()
	end
	return HudController.GetCoachTarget(name)
end

--[[ Steps ----------------------------------------------------------------------------- ]]

local function currentStep(): TutorialConfig.Step?
	local t = TycoonController.GetTutorial()
	if t.Done then
		return nil
	end
	return TutorialConfig.GetStep(t.Step)
end

local function sendAdvance(stepIndex: number)
	if advanceSentFor == stepIndex then
		return
	end
	advanceSentFor = stepIndex
	RemoteEvents.TutorialAdvance:FireServer({ Step = stepIndex })
	-- A lost reply (or a refused re-check) lets the player try again.
	task.delay(2, function()
		if advanceSentFor == stepIndex then
			advanceSentFor = nil
		end
	end)
end

-- Multiplier: level 1 out of reach now -> the card says when to come back
-- and OK completes it.
local function multiplierShortfall(): number?
	local cost = TycoonConfig.GetCashMultiplierUpgradeCost(TycoonController.GetCashMultiplierLevel())
	if cost and TycoonController.GetCash() < cost then
		return cost
	end
	return nil
end

-- Done on OK (rather than by an action) for this step right now?
local function doneOnOk(step: TutorialConfig.Step): boolean
	if TycoonController.GetTutorial().Replay or step.Kind == "Card" then
		return true
	end
	return step.Id == "multiplier" and multiplierShortfall() ~= nil
end

local function setGuidance(step: TutorialConfig.Step?, on: boolean)
	guiding = on
	if step and (on or (step.Kind == "Card" and (step.Target or step.Coach))) then
		GoalMarkerController.SetTutorialTarget(step.Target, step.Title, true)
		TutorialPath.SetEnabled(step.Target ~= nil)
	else
		GoalMarkerController.SetTutorialTarget(nil, nil, TycoonController.IsTutorialActive())
		TutorialPath.SetEnabled(false)
	end
end

local function showCard(stepIndex: number)
	local step = TutorialConfig.GetStep(stepIndex)
	if not step then
		return
	end
	local body = step.Body
	local shortfall = if step.Id == "multiplier" then multiplierShortfall() else nil
	if shortfall then
		body ..= (" Come back when you have %s."):format(NumberFormat.Money(shortfall))
	end
	-- A Card step's target / coach show while its card is up.
	setGuidance(step, false)
	if step.Kind == "Card" and (step.Target or step.Coach) then
		setGuidance(step, true)
	end
	TutorialCards.ShowStep({ Icon = step.Icon, Title = step.Title, Body = body }, step.OkText, function()
		if TycoonController.GetTutorial().Step ~= stepIndex then
			return
		end
		if doneOnOk(step) then
			setGuidance(nil, false)
			okAt = os.clock()
			sendAdvance(stepIndex)
		else
			setGuidance(step, true)
		end
	end)
end

-- The next card, once any big result card (the fusion's Rare) has closed.
local function queueCard(stepIndex: number, delay: number)
	cardToken += 1
	local token = cardToken
	task.delay(delay, function()
		local waited = 0
		while ResultController.IsBigCardOpen() and waited < BIG_CARD_WAIT_SECONDS do
			waited += task.wait(0.25)
		end
		if token == cardToken and TycoonController.GetTutorial().Step == stepIndex and not TycoonController.GetTutorial().Done then
			showCard(stepIndex)
		end
	end)
end

local function finishTutorial()
	cardToken += 1
	shownStep = nil
	TutorialCards.Close()
	setGuidance(nil, false)
	GoalMarkerController.SetTutorialTarget(nil, nil, false)
	coachRing.Visible = false
	ToastController.FlushHeld()
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
	local active = TycoonController.IsTutorialActive() and t.Step >= 1
	if not active then
		if wasActive then
			ToastController.Show("✓ Nice!", "Success")
			SoundKit.Play("RevealMinor", nil)
			finishTutorial()
		end
		wasActive = false
		return
	end
	wasActive = true
	if shownStep == t.Step then
		return
	end
	local previous = shownStep
	shownStep = t.Step
	advanceSentFor = nil
	okAt = nil
	oddsCoachUntil = nil
	setGuidance(nil, false)
	if previous ~= nil then
		-- The last step is done (server-confirmed): a quick cheer, then on.
		TutorialCards.Close()
		ToastController.Show("✓ Nice!", "Success")
		SoundKit.Play("RevealMinor", nil)
		queueCard(t.Step, TutorialConfig.NextCardDelay)
	else
		queueCard(t.Step, 1)
	end
end

-- Every frame: the coach ring, Open / Arrive completion.
local function step()
	local tutorialStep = currentStep()
	if not tutorialStep or not TycoonController.IsTutorialActive() then
		coachRing.Visible = false
		return
	end
	local t = TycoonController.GetTutorial()
	local cardUp = TutorialCards.IsOpen()
	local stepIndex = t.Step

	-- Coach ring: the Fuse panel's sequence, else the step's HUD element.
	local target: GuiObject? = nil
	if tutorialStep.Id == "fuse" and guiding and FusePanel.IsOpen() then
		if FusePanel.GetSelectedCount() < 2 then
			oddsCoachUntil = nil
			target = FusePanel.GetCoachTarget("AutoFill")
		else
			oddsCoachUntil = oddsCoachUntil or (os.clock() + ODDS_COACH_SECONDS)
			target = FusePanel.GetCoachTarget(if os.clock() < (oddsCoachUntil :: number) then "Odds" else "Fuse")
		end
	elseif tutorialStep.Coach and (guiding or (cardUp and tutorialStep.Kind == "Card")) then
		target = coachTarget(tutorialStep.Coach)
	end
	placeCoach(target)

	if okAt and not cardUp and os.clock() - okAt > RESHOW_SECONDS then
		okAt = nil
		showCard(stepIndex)
		return
	end
	if not guiding or cardUp then
		return
	end
	if tutorialStep.Kind == "Open" then
		local opened = (tutorialStep.Id == "index" and IndexPanel.IsOpen())
			or (tutorialStep.Id == "rebirth" and RebirthPanel.IsOpen())
		if opened then
			sendAdvance(stepIndex)
		end
	elseif tutorialStep.Kind == "Arrive" then
		local marked = GoalMarkerController.GetMarkedPosition()
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if marked and root and root:IsA("BasePart") then
			local offset = root.Position - marked
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= TutorialConfig.ArriveDistance - ARRIVE_MARGIN then
				sendAdvance(stepIndex)
			end
		end
	end
end

-- The card for the current step again (the goal card's tap, /selftest).
function TutorialController.ShowCurrentCard()
	local t = TycoonController.GetTutorial()
	if TycoonController.IsTutorialActive() and t.Step >= 1 then
		showCard(t.Step)
	end
end

function TutorialController.Init()
	buildCoachRing()
	TutorialCards.Init()
	TutorialPath.Init()
	TutorialPath.SetTargetSource(GoalMarkerController.GetMarkedPosition)
	ToastController.SetBigHold(TycoonController.IsTutorialActive)
	TycoonController.TycoonChanged:Connect(onTycoonChanged)
	RunService.RenderStepped:Connect(step)
	onTycoonChanged()
end

return TutorialController
