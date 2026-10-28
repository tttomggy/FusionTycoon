--!strict
--[[
	UpgradeGuide
	------------
	The coach's Upgrade step leads INTO the UPGRADES panel. While the coach
	has taken over (Takes), its step is Upgrade and it published an
	UpgradeTarget (the best affordable +$/s per $):

	  panel closed   the hand sits on the UPGRADES button
	  panel open     the list scrolls the best row into view and the hand
	                 points at that row's buy button, captioned with the
	                 row's own "next" number ("+$13.3/s")
	  after the buy  the coach moves on (Pull / Fuse / Earn) and the hand
	                 goes; the panel closing puts it back on UPGRADES

	The hand is TutorialHand's one hand, so this only runs while nothing
	else owns it: not during the tutorial, not while a tip (TutorialController)
	is up. The planning is pure (Plan) so /selftest can run it.
]]
local RunService = game:GetService("RunService")

local TycoonController = require(script.Parent.Parent.Controllers.TycoonController)
local HudController = require(script.Parent.Parent.Controllers.HudController)
local GoalMarkerController = require(script.Parent.Parent.Controllers.GoalMarkerController)
local TutorialHand = require(script.Parent.TutorialHand)
local UpgradesPanel = require(script.Parent.UpgradesPanel)
local UIKit = require(script.Parent.UIKit)

local UpgradeGuide = {}

local CHECK_SECONDS = 0.1

export type PlanInput = {
	Active: boolean, -- tutorial done, no tip up, the coach has taken over on Upgrade
	StationId: string?, -- the coach's UpgradeTarget station
	Kind: string?,
	PanelOpen: boolean,
	OtherOverlay: boolean, -- some other modal / card is open
}

export type Plan = {
	Where: string, -- "None" | "Button" (the HUD's UPGRADES) | "Row" (a row in the panel)
	StationId: string?,
	Kind: string?,
}

-- Where the hand goes. Pure.
function UpgradeGuide.Plan(input: PlanInput): Plan
	if not input.Active or not input.StationId or input.OtherOverlay then
		return { Where = "None" }
	end
	if input.PanelOpen then
		return { Where = "Row", StationId = input.StationId, Kind = input.Kind or "Upgrade" }
	end
	return { Where = "Button" }
end

local owned: GuiObject? = nil -- the target this module set on the hand
local lastCheck = 0
local lastWhere = "None"
local lastStation: string? = nil
local paused = false -- /selftest owns the hand

local function release()
	if owned and TutorialHand.GetTarget() == owned then
		TutorialHand.SetTarget(nil)
		TutorialHand.SetCaption(nil)
	end
	owned = nil
end

local function setHand(gui: GuiObject?, caption: string?)
	if gui == nil then
		release()
		return
	end
	if TutorialHand.GetTarget() ~= gui then
		TutorialHand.SetTarget(gui)
	end
	TutorialHand.SetCaption(caption)
	owned = gui
end

local function liveInput(): PlanInput
	local progress = TycoonController.GetGoalProgress()
	local coach = if progress then progress.Coach else nil
	local target = if coach then coach.UpgradeTarget else nil
	local active = TycoonController.HasSynced()
		and TycoonController.GetTutorial().Done
		and coach ~= nil
		and coach.Takes
		and coach.Step == "Upgrade"
		and not GoalMarkerController.IsTipActive()
		and (TutorialHand.GetTarget() == nil or TutorialHand.GetTarget() == owned)
	local panelOpen = UpgradesPanel.IsOpen()
	return {
		Active = active,
		StationId = if target then target.StationId else nil,
		Kind = if target then target.Kind else nil,
		PanelOpen = panelOpen,
		OtherOverlay = UIKit.IsOverlayOpen(if panelOpen then "UpgradesPanel" else nil),
	}
end

local function frame()
	local now = os.clock()
	if now - lastCheck < CHECK_SECONDS then
		return
	end
	lastCheck = now
	if paused then
		release()
		return
	end
	local plan = UpgradeGuide.Plan(liveInput())
	lastWhere, lastStation = plan.Where, plan.StationId
	if plan.Where == "Row" then
		local stationId = plan.StationId :: string
		-- A row below the fold comes up first; the hand follows the list.
		UpgradesPanel.ScrollTo(stationId)
		setHand(UpgradesPanel.GetButtonFor(stationId, plan.Kind), UpgradesPanel.GetCaptionFor(stationId))
	elseif plan.Where == "Button" then
		setHand(HudController.GetCoachTarget("Upgrades"), nil)
	else
		release()
	end
end

-- /selftest: where the hand was last sent (Where, StationId).
function UpgradeGuide.GetLast(): (string, string?)
	return lastWhere, lastStation
end

-- /selftest: while paused the guide leaves the hand alone (and lets go of it).
function UpgradeGuide.SetPaused(value: boolean)
	paused = value
	if value then
		release()
	end
end

function UpgradeGuide.IsOwningHand(): boolean
	return owned ~= nil and TutorialHand.GetTarget() == owned
end

function UpgradeGuide.Init()
	RunService.Heartbeat:Connect(frame)
end

return UpgradeGuide
