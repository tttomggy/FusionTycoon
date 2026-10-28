--!strict
--[[
	MissionBanner
	-------------
	The steal mission: ONE big instruction box in TopStack's Mission slot
	(under the event chip), because stealing is the hook of the game and a
	small world bubble 74 studs away was never read:

	  STEAL A FREE ORB!              (STEAL FROM DR. FIZZ! once the lab is known)
	  [1 🤚 Hold E at the glowing orb] [2 🏃 Run home with it] [3 🛡 Don't get caught!]

	Step 1 is lit until the player holds a stolen orb (the HeistTier
	attribute), step 2 while carrying; a delivery flashes a ✔ and the box
	goes away for good (saved as the tip id "rivalStealDone").

	Owner: tipRival (TutorialController tells it with SetTip) or the
	LoopCoach Steal step, until the first delivered rival steal. It hides
	when 3 minutes pass, a tutorial step runs, or the player is ragdolled /
	frozen (back when they recover); TopStack hides it while a modal or
	centred card is open. No close button. The planning is pure (PlanShow /
	PlanStep / TitleFor / WidthFor) so /selftest can run it.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RivalConfig = require(ReplicatedStorage.Shared.Config.RivalConfig)
local UIKit = require(script.Parent.UIKit)
local TopStack = require(script.Parent.TopStack)
local TycoonController = require(script.Parent.Parent.Controllers.TycoonController)
local GoalMarkerController = require(script.Parent.Parent.Controllers.GoalMarkerController)

local MissionBanner = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts
local localPlayer = Players.LocalPlayer

local DISPLAY_ORDER = 61 -- over the objective bar (60), under every panel
MissionBanner.DONE_TIP = "rivalStealDone"
MissionBanner.MAX_SECONDS = 180 -- one owner spell (the tip's own length)
MissionBanner.FLASH_SECONDS = 1.4 -- the ✔ after a delivery
MissionBanner.HEIGHT = 88 -- logical px, box only (the slot adds the shadow)
MissionBanner.MAX_WIDTH = TopStack.WIDEST_WIDTH -- the widest top-centre line
MissionBanner.MIN_WIDTH = 300
MissionBanner.ROBLOX_BUTTONS_X = 170 -- the Roblox top-left buttons, px after the scale
MissionBanner.GENERIC_TITLE = "STEAL A FREE ORB!"

local TITLE_MAX, TITLE_MIN = 28, 20
local STEP_TEXT = { Desktop = 15, Phone = 16 } -- logical; 16 x 0.8 = 12.8 px on a phone
local STEP_HEIGHT = 40
local CELL_GAP = 6
local PAD = 10
local SLIDE_SECONDS = 0.35
local SLIDE_OUT_SECONDS = 0.25

MissionBanner.Steps = {
	"1 🤚 Hold E at the glowing orb",
	"2 🏃 Run home with it",
	"3 🛡 Don't get caught!",
} :: { string }

--[[ Pure planning ------------------------------------------------------------- ]]

export type PlanState = {
	Owner: boolean, -- tipRival is running, or the coach is on Steal
	Done: boolean, -- the first rival steal was delivered (never shows again)
	Elapsed: number, -- seconds into this owner spell
	TutorialRunning: boolean, -- a tutorial step is up
	Down: boolean, -- ragdolled / frozen (back when they recover)
}

-- Whether the box is wanted now (TopStack still hides it behind a modal).
function MissionBanner.PlanShow(state: PlanState): boolean
	return state.Owner
		and not state.Done
		and state.Elapsed < MissionBanner.MAX_SECONDS
		and not state.TutorialRunning
		and not state.Down
end

-- The lit step (1 / 2); 3 is the delivery ✔ flash.
function MissionBanner.PlanStep(carrying: boolean, flashing: boolean): number
	if flashing then
		return 3
	end
	return if carrying then 2 else 1
end

-- "STEAL FROM DR. FIZZ!" for "Dr. Fizz's Lab"; the generic line when the lab
-- is not known yet.
function MissionBanner.TitleFor(labName: string?): string
	if labName == nil or labName == "" then
		return MissionBanner.GENERIC_TITLE
	end
	return ("STEAL FROM %s!"):format(RivalConfig.GetShortName(labName):upper())
end

-- The box's logical width: 520, less on a window too narrow to clear the
-- Roblox buttons on both sides of the centre.
function MissionBanner.WidthFor(viewX: number, phone: boolean): number
	if not phone then
		return MissionBanner.MAX_WIDTH
	end
	local clear = MissionBanner.ROBLOX_BUTTONS_X / UITheme.PhoneScale + 8
	return math.clamp(viewX - 2 * clear, MissionBanner.MIN_WIDTH, MissionBanner.MAX_WIDTH)
end

--[[ State --------------------------------------------------------------------- ]]

local screenGui: ScreenGui
local holder: Frame
local body: Frame
local titleLabel: TextLabel
local cells: { Frame } = {}
local cellLabels: { TextLabel } = {}
local cellStrokes: { UIStroke } = {}

local tipRunning = false
local ownerSince: number? = nil
local flashUntil = 0
local lastDeliveries = 0
local titleText = MissionBanner.GENERIC_TITLE
local litStep = 0 -- 1 / 2 / 3 (flash), 0 = nothing drawn yet
local registered = false
local slideToken = 0
local testState: { [string]: any }? = nil
local lastNameCheck = 0

-- TutorialController: tipRival started / ended.
function MissionBanner.SetTip(running: boolean)
	tipRunning = running
end

-- /selftest: fields here replace the live PlanState's (nil: back to live).
function MissionBanner.SetTestState(overrides: { [string]: any }?)
	testState = overrides
end

local function isDown(): boolean
	local now = Workspace:GetServerTimeNow()
	for _, name in { "RagdollUntil", "FrozenUntil" } do
		local until_ = localPlayer:GetAttribute(name)
		if typeof(until_) == "number" and until_ > now then
			return true
		end
	end
	return false
end

-- The nearest rival lab's name (its plot's RivalName attribute), nil until
-- one is built.
local function nearestLabName(): string?
	local pedestal = GoalMarkerController.ResolvePlotTarget("NearestRivalPedestal")
	local current: Instance? = if pedestal then pedestal.Parent else nil
	while current and current ~= Workspace do
		local name = current:GetAttribute("RivalName")
		if typeof(name) == "string" then
			return name
		end
		current = current.Parent
	end
	return nil
end

local function liveState(now: number, owner: boolean): PlanState
	local tutorial = TycoonController.GetTutorial()
	local state: PlanState = {
		Owner = owner,
		Done = TycoonController.HasSeenTip(MissionBanner.DONE_TIP) or TycoonController.GetRivalDeliveries() > 0,
		Elapsed = if ownerSince then now - ownerSince else 0,
		TutorialRunning = not tutorial.Done or tutorial.Replay == true,
		Down = isDown(),
	}
	local overrides = testState
	if overrides then
		for key, value in overrides do
			(state :: any)[key] = value
		end
	end
	return state
end

local function coachSteals(): boolean
	local progress = TycoonController.GetGoalProgress()
	local coach = if progress then progress.Coach else nil
	return coach ~= nil and coach.Step == "Steal"
end

--[[ Drawing -------------------------------------------------------------------- ]]

local function stepTextSize(): number
	return if UIKit.IsPhone() then STEP_TEXT.Phone else STEP_TEXT.Desktop
end

local function applySize()
	local width = MissionBanner.WidthFor(UIKit.GetLogicalViewport().X, UIKit.IsPhone())
	holder.Size = UDim2.fromOffset(width, MissionBanner.HEIGHT + UITheme.ShadowOffset)
	local cellWidth = (width - 2 * PAD - 2 * CELL_GAP) / 3
	for index, cell in cells do
		cell.Position = UDim2.fromOffset(PAD + (index - 1) * (cellWidth + CELL_GAP), PAD + 28)
		cell.Size = UDim2.fromOffset(cellWidth, STEP_HEIGHT)
		cellLabels[index].TextSize = stepTextSize()
	end
end

local function render(step: number)
	litStep = step
	titleLabel.Text = if step == 3 then "GOT IT! ✔" else titleText
	for index, cell in cells do
		local lit = index == step or step == 3
		cell.BackgroundColor3 = if lit then Colors.White else Colors.Ink
		cell.BackgroundTransparency = if lit then 0.72 else 0.55
		cellStrokes[index].Enabled = lit
		local text = MissionBanner.Steps[index]
		cellLabels[index].Text = if step == 3 then "✔ " .. text:sub(3) else text
	end
end

local function slideY(y: number): UDim2
	return UDim2.new(0.5, 0, 0, y)
end

local function show(y: number)
	slideToken += 1
	applySize()
	holder.Visible = true
	holder.Position = slideY(-(MissionBanner.HEIGHT + 20))
	TweenService:Create(holder, TweenInfo.new(SLIDE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = slideY(y) }):Play()
end

local function hide()
	slideToken += 1
	local mine = slideToken
	local tween = TweenService:Create(holder, TweenInfo.new(SLIDE_OUT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = slideY(-(MissionBanner.HEIGHT + 20)) })
	tween:Play()
	tween.Completed:Once(function()
		if slideToken == mine then
			holder.Visible = false
		end
	end)
end

local function move(y: number)
	holder.Position = slideY(y)
end

local missionDef: TopStack.Mission = {
	Key = "StealMission",
	Height = MissionBanner.HEIGHT + UITheme.ShadowOffset,
	Show = show,
	Hide = hide,
	Move = move,
}

--[[ Frame --------------------------------------------------------------------- ]]

local function frame()
	local now = os.clock()
	local deliveries = TycoonController.GetRivalDeliveries()
	local owner = tipRunning or coachSteals()
	if owner and ownerSince == nil then
		ownerSince = now
	elseif not owner then
		ownerSince = nil
	end

	-- A delivery while the box is up: ✔ flash, then it is done for good.
	if deliveries > lastDeliveries then
		lastDeliveries = deliveries
		if not TycoonController.HasSeenTip(MissionBanner.DONE_TIP) then
			TycoonController.MarkTipSeen(MissionBanner.DONE_TIP)
		end
		if TopStack.IsMissionShown() then
			flashUntil = now + MissionBanner.FLASH_SECONDS
		end
	end
	local flashing = now < flashUntil

	local wanted = flashing or MissionBanner.PlanShow(liveState(now, owner))
	if wanted and not registered then
		registered = true
		TopStack.SetMission(missionDef)
	elseif not wanted and registered then
		registered = false
		TopStack.SetMission(nil)
	end
	if not wanted then
		return
	end

	-- The lab's name in the title, once it is known (a slow lookup).
	if now - lastNameCheck > 0.5 then
		lastNameCheck = now
		titleText = MissionBanner.TitleFor(nearestLabName())
	end
	local step = MissionBanner.PlanStep(localPlayer:GetAttribute("HeistTier") ~= nil, flashing)
	if step ~= litStep or (step ~= 3 and titleLabel.Text ~= titleText) then
		render(step)
	end
end

local function build()
	screenGui = UIKit.Screen("MissionBanner", DISPLAY_ORDER)
	local panel, root = UIKit.Panel({
		Name = "Mission",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = slideY(-(MissionBanner.HEIGHT + 20)),
		Size = UDim2.fromOffset(MissionBanner.MAX_WIDTH, MissionBanner.HEIGHT + UITheme.ShadowOffset),
		Color = Colors.White,
		Radius = 18,
		ZIndex = 2,
	})
	holder, body = root, panel
	UIKit.PairGradient(body, UITheme.Gradients.Orange)
	holder.Visible = false
	local z = body.ZIndex + 1

	titleLabel = UIKit.Label({
		Name = "Title",
		Text = MissionBanner.GENERIC_TITLE,
		Font = Fonts.Display,
		TextSize = TITLE_MAX,
		TextColor3 = UITheme.WarmText,
		Position = UDim2.fromOffset(PAD, 6),
		Size = UDim2.new(1, -2 * PAD, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = UITheme.WarmTextStroke,
		ZIndex = z,
		Parent = body,
	})
	UIKit.FitText(titleLabel, TITLE_MAX, TITLE_MIN)

	for index, text in MissionBanner.Steps do
		local cell = Instance.new("Frame")
		cell.Name = "Step" .. index
		cell.BorderSizePixel = 0
		cell.BackgroundColor3 = Colors.Ink
		cell.BackgroundTransparency = 0.55
		cell.ZIndex = z
		cell.Parent = body
		UIKit.Corner(cell, 10)
		local stroke = UIKit.Stroke(cell, 2, Colors.White)
		stroke.Enabled = false
		local label = UIKit.Label({
			Name = "Text",
			Text = text,
			Font = Fonts.BodyHeavy,
			TextSize = STEP_TEXT.Desktop,
			TextColor3 = UITheme.WarmText,
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(1, -12, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			Stroke = UITheme.WarmTextStroke,
			ZIndex = z + 1,
			Parent = cell,
		})
		cells[index], cellLabels[index], cellStrokes[index] = cell, label, stroke
	end
	applySize()
	render(1)
end

--[[ /selftest ------------------------------------------------------------------ ]]

function MissionBanner.GetBody(): Frame
	return body
end

function MissionBanner.GetTitleLabel(): TextLabel
	return titleLabel
end

function MissionBanner.GetStepLabels(): { TextLabel }
	return cellLabels
end

function MissionBanner.GetLitStep(): number
	return litStep
end

function MissionBanner.IsRegistered(): boolean
	return registered
end

function MissionBanner.Init()
	build()
	lastDeliveries = TycoonController.GetRivalDeliveries()
	UIKit.LayoutChanged:Connect(applySize)
	RunService.Heartbeat:Connect(frame)
end

return MissionBanner
