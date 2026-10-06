--!strict
--[[
	TutorialController
	------------------
	Drives the first-time tutorial on the client (Tutorial 2; the steps are
	TutorialConfig.Steps, the server owns the step, TutorialService, and
	sends it in the snapshot). One instruction at a time, no OK cards:

	  1. THE BANNER (UI/TutorialBanner), top centre: the step's instruction
	     and, while it has a world target, the live distance ("· 24m").
	  2. THE PATH (Effects/TutorialPath): lime dots from your feet to the
	     target, chevrons on the floor at it, the goal arrow's bouncing pill
	     (GoalMarkerController's tutorial layer).
	  3. THE BIG BUTTON (UI/TutorialHand): standing at a world target with a
	     prompt, a green "PULL" / "UPGRADE" / "FUSE" / "BUY" button appears
	     above the bottom bar; it triggers that ProximityPrompt
	     (InputHoldBegin / InputHoldEnd) so the real server path runs.
	  4. THE HAND 👆: one for the whole UI, on the exact button to press: the
	     big button; in the Fuse panel AUTO-FILL then FUSE; the event chip;
	     REBIRTH. Never a rectangle.
	  5. Done: "Action" steps only when the server confirms the real action
	     (the snapshot's Step moves on); "Timed" / "Open" steps ask the
	     server (TutorialAdvance, re-checked) after their Seconds or once the
	     chip / panel was opened. Then the banner shows a ✓ and the Step
	     sound, and the next instruction slides in 0.4 s later.

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
local TutorialHand = require(UI.TutorialHand)
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

local localPlayer = Players.LocalPlayer

local presented: number? = nil -- the step whose banner is up (nil between steps)
local lastSeen: number? = nil -- the snapshot step last handled
local seq = 0 -- bumped on every change, so a stale transition stops
local stepStart = 0 -- os.clock() the presented step's banner came in
local advanceSentFor: number? = nil
local replayHintShown = false
local wasActive = false
local pedestalPops: { BillboardGui } = {}
local lastSub: string? = nil
local pressing = false

--[[ Steps ----------------------------------------------------------------------------- ]]

local function presentedStep(): TutorialConfig.Step?
	local index = presented
	return if index then TutorialConfig.GetStep(index) else nil
end

local function sendAdvance(stepIndex: number)
	if advanceSentFor == stepIndex then
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
	return position ~= nil and here ~= nil and prompt.Enabled and (position - here).Magnitude <= prompt.MaxActivationDistance
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

local function stopGuidance()
	TutorialHand.SetContextual(nil, nil)
	TutorialHand.SetTarget(nil)
	TutorialPath.SetEnabled(false)
	GoalMarkerController.SetTutorialTarget(nil, nil, TycoonController.IsTutorialActive())
	clearPedestalPops()
end

local function labName(): string
	return ("%s'S LAB"):format(localPlayer.DisplayName:upper())
end

-- Slides step `index`'s banner in and turns its guidance on.
local function present(index: number)
	local step = TutorialConfig.GetStep(index)
	if not step then
		return
	end
	local t = TycoonController.GetTutorial()
	presented = index
	stepStart = os.clock()
	advanceSentFor = nil
	lastSub = step.Sub
	TutorialBanner.Show(step.Banner, step.Sub)
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
	if step.Id == "pedestals" then
		showPedestalPops()
	end
end

-- The step changed (or the tutorial started / ended): ✓ the old banner, then
-- the new one.
local function changeStep(newStep: number?, finished: boolean)
	seq += 1
	local mine = seq
	local previousIndex = presented
	local previous = presentedStep()
	presented = nil
	stopGuidance()
	if previous and previous.Id == "events" then
		EventInfoCard.Hide()
	end
	task.spawn(function()
		if previousIndex ~= nil then
			if previous and previous.Id == "claim" then
				TutorialBanner.ShowSplash("WELCOME TO YOUR LAB!", labName())
			end
			SoundKit.Play("RevealMinor", nil)
			TutorialBanner.Complete()
		elseif not finished then
			task.wait(FIRST_STEP_DELAY)
		end
		if mine ~= seq then
			return
		end
		if finished or not newStep then
			TutorialBanner.Hide()
			return
		end
		present(newStep)
	end)
end

local function finishTutorial()
	TutorialCards.Close()
	TutorialBanner.SetSkip(nil)
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
			wasActive = false
			lastSeen = nil
			changeStep(nil, true)
			finishTutorial()
		end
		-- After the tutorial the path follows the current goal (👣).
		if lastSeen == nil then
			TutorialPath.SetEnabled(t.Done and TycoonController.IsGoalPathOn())
		end
		return
	end
	wasActive = true
	if lastSeen == t.Step then
		return
	end
	lastSeen = t.Step
	changeStep(t.Step, false)
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
	if not tutorialStep or not TycoonController.IsTutorialActive() then
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

	-- Completion that isn't a server-confirmed action.
	if tutorialStep.Kind == "Timed" then
		if elapsed >= (tutorialStep.Seconds or 0) then
			sendAdvance(index)
		end
	elseif tutorialStep.Kind == "Open" then
		local opened = (tutorialStep.Id == "events" and EventInfoCard.IsOpen())
			or (tutorialStep.Id == "rebirth" and RebirthPanel.IsOpen())
		if opened or elapsed >= (tutorialStep.Seconds or 0) then
			sendAdvance(index)
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
	TutorialBanner.Init()
	TutorialHand.Init()
	TutorialPath.Init()
	TutorialPath.SetTargetSource(GoalMarkerController.GetMarkedPosition)
	ToastController.SetBigHold(TycoonController.IsTutorialActive)
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
