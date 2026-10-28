--!strict
--[[
	TutorialConfig
	--------------
	The mandatory first-time tutorial (TutorialService on the server,
	TutorialController on the client), and the "?" help slideshows.

	Tutorial 5: under a minute, four steps (claim, pull 2, fuse, ready). It
	works like the egg games' tutorials: ONE instruction at a time as a big
	banner at the top centre ("Pull 2 free orbs · 8m", the live distance), a
	dotted lime path from your feet to the target, one pointing hand 👆 on
	the exact button to press, and a big contextual button near the bottom
	("PULL") once you stand at a world target. The only card is Fusing. The
	HUD builds up as you go (HudReveal). What the old steps taught (upgrade,
	pedestals, Index, Multiplier Pad, weather, Rebirth) is Tips: one-time
	hints after the tutorial.

	Each step:
	  Id         stable name (TutorialService's predicates, analytics)
	  Kind       "Action" done only by the real, server-confirmed action
	                      (TutorialService's predicate, checked in every sync)
	             "Timed"  done by itself once Seconds have passed (the client
	                      asks, the server checks the clock)
	  Banner     the instruction, at most 6 words (the distance is added)
	  Sub        an optional second line, one short sentence
	  Target     world target (GoalMarkerController names): path + chevrons
	  PromptName the ProximityPrompt at the target the contextual button
	             triggers; Prompt is the button's word ("PULL")
	  Hand       HUD element the hand points at ("Index", "Rebirth")
	  Seconds    Timed: how long
	  Skip       "Claimed": skipped when the save already has it (a resumed
	             or returning player)

	Saved as PlayerData.Tutorial = { Ver, Step, Done, FreeFuse, FreePulls,
	PullsGranted, Base, Replay, ReplayHint }; Step 0 = not decided yet (the
	first sync decides: new player -> 1, a save with real progress -> Done).
	A save from an older layout (Ver < DataVersion) has its step mapped by
	MigrateOld (PlayerDataService.sanitizeTutorial).
]]
local RebirthConfig = require(script.Parent.RebirthConfig)
local NumberFormat = require(script.Parent.Parent.Modules.NumberFormat)

local TutorialConfig = {}

export type Kind = "Action" | "Timed"

export type Card = {
	Icon: string,
	Title: string,
	Body: string,
	Weapon: string?, -- a CombatConfig weapon id: its turning model replaces the Icon (the unlock card)
}

-- An explain card shown before a step's banner (Tutorial 3): big image,
-- title, one or two short sentences, a big green OK. `Model` names the
-- world object (GoalMarkerController target) drawn in a ViewportFrame;
-- `Orbs` draws UIKit.TierOrbs instead ("Common", "+", "Common", "->",
-- "Rare"); else the Icon is the image.
export type ExplainCard = {
	Icon: string,
	Title: string,
	Body: string,
	Model: string?,
	Orbs: { string }?,
	Small: string?, -- a smaller second line under Body
}

export type Step = {
	Id: string,
	Kind: Kind,
	Banner: string,
	Sub: string?,
	Target: string?,
	PromptName: string?,
	Prompt: string?,
	Hand: string?,
	Seconds: number?,
	Count: number?, -- the banner says "<Banner> 0/Count" and the step needs Count actions
	Skip: string?,
	Icon: string?, -- the objective bar's 48 px step icon
	Card: ExplainCard?, -- opens first (never at the claim), then the banner
	CardDelay: number?, -- seconds after the step starts before the card opens
}

-- The saved layout version (Tutorial 5 = 4, 4 steps; 3 = Tutorial 3's 11;
-- 2 = Tutorial 2's 10; no Ver = Tutorial 1's 14 steps).
TutorialConfig.DataVersion = 4

-- Old saves with real progress skip it (with a one-time "replay in ⚙" toast).
TutorialConfig.ProgressRebirths = 1
TutorialConfig.ProgressPulls = 20
TutorialConfig.FreePulls = 2 -- guaranteed plain Commons, once per account
TutorialConfig.FreePullTier = "Common"
TutorialConfig.PathRebuildSeconds = 0.3
TutorialConfig.GoalPathSessions = 2 -- the goal path is on by default this many sessions

-- The banner and the welcome splash.
-- The objective bar (TutorialBanner): desktop width 520-640, phone full
-- width minus this margin (real px) on each side.
TutorialConfig.ObjectiveWidth = 600
TutorialConfig.ObjectiveMarginPhone = 32 -- both sides together (16 each)
TutorialConfig.StepDelay = 0.4 -- the default ✓ hold (Banner.Complete without a time)
TutorialConfig.WelcomeSeconds = 2 -- "WELCOME TO YOUR LAB!" auto-fades, no button
TutorialConfig.FirstStepDelay = 1 -- after joining: the world settles, then the first banner

-- Pacing (Tutorial 5: kids don't read cards, a minute is all we get). The
-- client plays the steps ONE AT A TIME, in order (TutorialController),
-- whatever the server's step already is:
--   done -> "✓ Nice!" NiceSeconds -> the bar slides out -> SettleSeconds of
--   nothing new -> the next step's explain card (never before the player has
--   closed whatever the step opened).
TutorialConfig.NiceSeconds = 0.6
TutorialConfig.SettleSeconds = 0.3
TutorialConfig.CardReadSeconds = 0 -- an explain card's OK is live at once (> 0: off this long, fill bar)
TutorialConfig.BannerMinSeconds = 1.5 -- an instruction stays up at least this long before it can change
TutorialConfig.AlreadyDoneText = "Already done ✓" -- a step whose action was done early

-- The arrow path (client-only: a flat ">" of two thin Neon bars per arrow,
-- TutorialPath).
TutorialConfig.PathArrowSpacing = 3 -- studs between arrows (widens past PathMaxArrows)
TutorialConfig.PathArrowSize = Vector3.new(1.2, 0.1, 0.25) -- one bar: length, height, thickness
TutorialConfig.PathArrowLift = 0.2 -- lying this far above the floor
TutorialConfig.PathMaxArrows = 40 -- 80 parts, a fixed pool
TutorialConfig.PathFlowSeconds = 1.2 -- one pulse runs from you to the target
TutorialConfig.PathArriveStuds = 6 -- the arrows stop this close to the target

TutorialConfig.Steps = {
	{
		Id = "claim",
		Kind = "Action",
		Icon = "🏠",
		Banner = "Claim your lab",
		Target = "ClaimStation",
		Skip = "Claimed",
	},
	{
		-- Both free pulls in one step; no card (the banner and its sub line say it).
		Id = "pull",
		Kind = "Action",
		Icon = "🎰",
		Banner = "Pull 2 free orbs",
		Sub = "Your first 2 are free!",
		Count = TutorialConfig.FreePulls,
		Target = "GachaStation",
		PromptName = "PullPrompt",
		Prompt = "PULL",
	},
	{
		Id = "fuse",
		Kind = "Action",
		Icon = "🔮",
		-- The one card worth reading: the orb diagram. Its OK is live at once.
		Card = {
			Icon = "🔮",
			Title = "Fusing",
			Body = "Fuse 2 same orbs → 1 better orb!",
			Small = "More orbs in = better odds.",
			Orbs = { "Common", "+", "Common", "→", "Rare" },
		},
		Banner = "Fuse your 2 orbs",
		Target = "FusionMachine",
		PromptName = "FusePrompt",
		Prompt = "FUSE",
	},
	{
		Id = "finish",
		Kind = "Timed",
		Icon = "🎉",
		Banner = "You're ready!",
		Seconds = 2,
	},
} :: { Step }

function TutorialConfig.GetStep(index: number): Step?
	return TutorialConfig.Steps[index]
end

--[[ The banner clock ----------------------------------------------------------------
	A step's clock counts only the seconds its instruction is REALLY on screen:
	the bar shown and in place (not slid out under a centred card) and nothing
	the player opened covering it. A Timed step ("You're ready!") that started
	while the FUSION SUCCESS card was still up used to run out behind it and
	finish the moment the card closed, so the banner never showed. Pure: also
	/selftest.
]]

-- Visible seconds an instruction stays up before it can change or advance:
-- BannerMinSeconds, and a Timed step its Seconds if that is longer.
function TutorialConfig.GetBannerHold(step: Step): number
	return math.max(TutorialConfig.BannerMinSeconds, step.Seconds or 0)
end

-- One frame of the clock: `dt` counts only while the banner is visible.
function TutorialConfig.AdvanceBannerClock(visibleSeconds: number, dt: number, visible: boolean): number
	return if visible then visibleSeconds + dt else visibleSeconds
end

-- May a Timed step ask the server to advance, given its visible seconds?
function TutorialConfig.TimedStepReady(step: Step, visibleSeconds: number): boolean
	return step.Kind == "Timed" and visibleSeconds >= TutorialConfig.GetBannerHold(step)
end

function TutorialConfig.IndexOf(id: string): number?
	for index, step in TutorialConfig.Steps do
		if step.Id == id then
			return index
		end
	end
	return nil
end

-- Older saves' steps -> Tutorial 5's. Every old list is written as step ids
-- of ITS OWN layout; the last hop (V4_FROM) maps an id to this list's step
-- (or to Done). Old Tutorial 1/2 saves hop through Tutorial 3's ids first.
local V1_STEP_IDS = { -- Tutorial 1's 14 steps, as Tutorial 3 step ids
	"claim", -- welcome
	"claim",
	"upgrade",
	"pull",
	"pedestals",
	"fuse",
	"index", -- index
	"multiplier",
	"events",
	"rebirth", -- gifts
	"rebirth", -- lock
	"rebirth", -- steal
	"rebirth",
	"finish",
}

-- Tutorial 2's 10 steps, as Tutorial 3 step ids.
local V2_STEP_IDS = { "claim", "upgrade", "pull", "pull2", "pedestals", "fuse", "multiplier", "events", "rebirth", "finish" }

-- Tutorial 3's 11 steps.
local V3_STEP_IDS = { "claim", "upgrade", "pull", "pull2", "pedestals", "fuse", "index", "multiplier", "events", "rebirth", "finish" }

-- Tutorial 3 step id -> the step here. "Done": the player had already seen
-- everything that is left (Index and later were all taught after the fuse).
-- A free-pull step whose 2 pulls are all used goes straight to "fuse".
local V4_FROM: { [string]: string } = {
	claim = "claim",
	upgrade = "pull",
	pull = "pull",
	pull2 = "pull",
	pedestals = "fuse",
	fuse = "fuse",
	index = "Done",
	multiplier = "Done",
	events = "Done",
	rebirth = "Done",
	finish = "Done",
}

local function fromV3Id(id: string?, freePullsUsedUp: boolean): (number, boolean)
	local mapped = if id then V4_FROM[id] else nil
	if mapped == nil then
		return 1, false
	elseif mapped == "Done" then
		return #TutorialConfig.Steps, true
	end
	if mapped == "pull" and freePullsUsedUp then
		mapped = "fuse"
	end
	return TutorialConfig.IndexOf(mapped) :: number, false
end

-- The step id (in Tutorial 3's list) an older save's step stands for: `ver`
-- < 2 = Tutorial 1's 14 steps, 2 = Tutorial 2's 10, 3 = Tutorial 3's 11.
function TutorialConfig.OldStepId(ver: number, oldStep: number): string?
	if ver < 2 then
		return V1_STEP_IDS[oldStep]
	elseif ver == 2 then
		return V2_STEP_IDS[oldStep]
	end
	return V3_STEP_IDS[oldStep]
end

-- (step, done) in this list for an older save at `oldStep` of layout `ver`.
-- `freePullsUsedUp`: its free pulls were granted and are gone (it then
-- resumes at the fuse). An unknown step starts over at the claim.
function TutorialConfig.MigrateOld(ver: number, oldStep: number, freePullsUsedUp: boolean): (number, boolean)
	return fromV3Id(TutorialConfig.OldStepId(ver, oldStep), freePullsUsedUp)
end

--[[ The HUD builds up ------------------------------------------------------------
	A new player starts with the cash card and the banner only. Each element
	pops in (HudController) when the step it names begins; the ones at
	"finish" pop in one by one (HudRevealDelay seconds after the step starts).
	Done / old saves / a replay show everything.
]]

TutorialConfig.HudKeys = { "Upgrades", "Items", "Index", "Rebirth", "Event", "Settings", "Shop", "Goal" }

TutorialConfig.HudReveal = {
	Items = "pull", -- the first pull
	Upgrades = "fuse",
	Index = "fuse", -- the fusion fills it
	Rebirth = "finish",
	Event = "finish",
	Settings = "finish",
	Shop = "finish", -- SHOP, GIFTS, QUESTS, the deal badge, the power-ups
	Goal = "finish", -- NEXT GOAL + the quest tracker
} :: { [string]: string }

-- Seconds after the step begins (the "one by one" of the last step).
TutorialConfig.HudRevealDelay = {
	Settings = 0.2,
	Shop = 0.8,
	Goal = 1.5,
} :: { [string]: number }

-- What a key's pop-in says under it for a moment (nil: just "NEW!").
TutorialConfig.HudRevealNote = {
	Index = "New orbs fill your Index!",
} :: { [string]: string }

-- Is HUD element `key` shown at tutorial `step`? (Pure: also /selftest.)
function TutorialConfig.IsHudShown(key: string, step: number, done: boolean, replay: boolean): boolean
	if done or replay then
		return true
	end
	local at = TutorialConfig.HudReveal[key]
	local index = if at then TutorialConfig.IndexOf(at) else nil
	if not index then
		return true
	end
	return step >= 1 and step >= index
end

--[[ One-time tips (what the removed steps became) --------------------------------
	Each fires ONCE per account (TipConfig.Ids, saved like the others), only
	after the tutorial is Done, only when no card or overlay is open, as the
	hand on the thing plus one short TopStack line, never a card. At most one
	on screen; the next one waits TipGapSeconds after the first is gone.
	TutorialController runs them; PlanTip is the pure "which one now?" rule
	(also /selftest). Hand: a HudController coach target ("Upgrades", "Index",
	"Rebirth") or "EventChip"; Target (+ PromptName / Prompt): a world target
	with the lit path and the big button, as the old Multiplier step.
]]

export type TipDef = {
	Id: string,
	Line: string,
	WorldLine: string?, -- the world bubble's text when it differs from Line (tipRival: the mission box carries the Line)
	Hand: string?,
	Target: string?,
	PromptName: string?,
	Prompt: string?,
	MaxSeconds: number?, -- how long it stays up (default TipMaxSeconds)
}

TutorialConfig.Tips = {
	{
		-- Steal from a rival lab (RivalService): path arrows to the nearest
		-- rival lab's best pedestal, then the big STEAL button (the hold) at it.
		Id = "tipRival",
		Target = "NearestRivalPedestal",
		PromptName = "StealPrompt",
		Prompt = "STEAL",
		Line = "Steal from the rival lab! Hold E, run home, don't get caught!",
		-- The big MissionBanner (TopStack Mission slot) says it all; the bubble over the pedestal keeps one word.
		WorldLine = "STEAL!",
		MaxSeconds = 180, -- ends on the first delivered rival steal, or after 3 min
	},
	{ Id = "tipUpgrade", Hand = "Upgrades", Line = "Upgrade generators to earn faster!" },
	{
		Id = "tipMultiplier",
		Target = "MultiplierStation",
		PromptName = "UpgradePrompt",
		Prompt = "BUY",
		Line = "The Multiplier Pad multiplies ALL your money!",
	},
	{ Id = "tipIndex", Hand = "Index", Line = "New orb! Each one boosts your income forever." },
	{ Id = "tipEvent", Hand = "EventChip", Line = "Lab weather! Tap it to see the bonus." },
	{ Id = "tipRebirth", Hand = "Rebirth", Line = "Rebirth when the bar is full: keep your orbs, earn faster forever." },
} :: { TipDef }

TutorialConfig.TipGapSeconds = 20 -- a second tip waits this long after the first is gone
TutorialConfig.TipAfterDoneSeconds = 3 -- ... and the first waits this long after the tutorial ends
TutorialConfig.TipMaxSeconds = 45 -- a tip nobody follows goes by itself (it stays seen)
TutorialConfig.RivalTipAfterDoneSeconds = 20 -- tipRival: this long after "You're ready!" (the tutorial's end)
TutorialConfig.RebirthTipProgress = 0.5 -- tipRebirth: cash / Rebirth cost
-- The line under the first pull that lands on a pedestal (no step for it).
TutorialConfig.PedestalLine = "Your orbs earn cash every second!"

function TutorialConfig.GetTip(id: string): TipDef?
	for _, tip in TutorialConfig.Tips do
		if tip.Id == id then
			return tip
		end
	end
	return nil
end

-- What the planner needs to know (numbers and flags the client reads, so the
-- rule itself needs no game state).
export type TipState = {
	Done: boolean, -- the tutorial is over
	Replay: boolean, -- ... but a replay is running
	Quiet: boolean, -- no card, panel or overlay is open
	Showing: boolean, -- a tip (or hand) is on screen
	SinceGone: number, -- seconds since the last tip went (math.huge: none yet)
	SinceDone: number, -- seconds since the tutorial ended (math.huge: before this session)
	Seen: { [string]: boolean },
	Cash: number,
	UpgradeCost: number?, -- the cheapest next generator level (nil: all maxed)
	MultiplierLevel: number,
	MultiplierCost: number?, -- the Multiplier Pad's next price (nil: maxed)
	NewIndex: boolean, -- an Index entry was found since the tutorial ended
	EventChip: boolean, -- the event chip is on screen
	RebirthProgress: number, -- cash / the Rebirth cost
	RivalLab: boolean, -- a rival lab with an orb you could grab is in the world
}

-- The steal comes first: while tipRival has not been shown and a rival lab is
-- in the world, every other tip and hand waits for it (it starts
-- RivalTipAfterDoneSeconds after Done, then the usual TipGapSeconds follow it).
-- No rival lab (a full server) means it is skipped, not marked seen, and the
-- others run.
function TutorialConfig.RivalTipFirst(state: TipState): boolean
	return state.RivalLab and not state.Seen.tipRival
end

-- The tip to show now, or nil. Never during the tutorial or a replay, never
-- over an open card, never two at once (the second waits TipGapSeconds), and
-- never twice (Seen).
function TutorialConfig.PlanTip(state: TipState): string?
	if not state.Done or state.Replay or not state.Quiet or state.Showing then
		return nil
	end
	if state.SinceDone < TutorialConfig.TipAfterDoneSeconds or state.SinceGone < TutorialConfig.TipGapSeconds then
		return nil
	end
	local rivalFirst = TutorialConfig.RivalTipFirst(state)
	local ready: { [string]: boolean } = {
		tipUpgrade = state.UpgradeCost ~= nil and state.Cash >= (state.UpgradeCost :: number),
		tipMultiplier = state.MultiplierLevel == 0 and state.MultiplierCost ~= nil and state.Cash >= (state.MultiplierCost :: number),
		tipIndex = state.NewIndex,
		tipEvent = state.EventChip,
		tipRebirth = state.RebirthProgress >= TutorialConfig.RebirthTipProgress,
		tipRival = state.RivalLab and state.SinceDone >= TutorialConfig.RivalTipAfterDoneSeconds,
	}
	for _, tip in TutorialConfig.Tips do
		if not state.Seen[tip.Id] and ready[tip.Id] and (tip.Id == "tipRival" or not rivalFirst) then
			return tip.Id
		end
	end
	return nil
end

-- Whether the lit path is on: a running tip with its own target (tipRival,
-- the Multiplier Pad) owns it, and the goal path (👣, the goal card's) is off
-- while it runs, so only one set of arrows is ever on screen. Otherwise the
-- path follows the goal once the tutorial is Done.
function TutorialConfig.PathOn(runningTip: TipDef?, done: boolean, goalPathOn: boolean): boolean
	if runningTip ~= nil and runningTip.Target ~= nil then
		return true
	end
	return done and goalPathOn
end

--[[ "?" help ------------------------------------------------------------------ ]]

-- "?" help: topic -> its cards, a mini slideshow (◀ ▶, OK). The details
-- live here, not in the tutorial.
TutorialConfig.Help = {
	Fuse = {
		{ Icon = "🔮", Title = "Fuse", Body = "Put 2 orbs of the same tier in the Fusion Machine to make a better one." },
		{ Icon = "🎯", Title = "Same tier only", Body = "Fuse orbs of the same tier: 2 Commons make a Rare, 2 Rares make an Epic." },
		{ Icon = "📈", Title = "More orbs, better odds", Body = "Put in 2 to 6 orbs. The more you add, the better the chance it works." },
		{ Icon = "🛟", Title = "A fail keeps your best", Body = "If it fails, you keep your best orb. Only the others are used up." },
		{ Icon = "✨", Title = "Mutations", Body = "If every orb has the same mutation, the new orb keeps it. Mix them and it's lost." },
		{ Icon = "🤫", Title = "Secret", Body = "Fusing Mythics into a Secret unlocks at Rebirth 1." },
	},
	Upgrades = {
		{ Icon = "⚡", Title = "Upgrade a generator", Body = "Generators make your cash. Upgrade them to earn faster." },
		{ Icon = "⏩", Title = "MAX", Body = "MAX buys as many levels as you can afford. MAX ALL does it for every generator." },
	},
	Index = {
		{ Icon = "📖", Title = "Your Index", Body = "Every new orb and mutation fills your Index and boosts your income forever." },
	},
	Rebirth = {
		{
			Icon = "♻️",
			Title = "Rebirth",
			Body = ("Get to %s and Rebirth. You keep your orbs, and every rebirth makes you earn faster and unlocks new things."):format(
				NumberFormat.Money(RebirthConfig.GetCost(0))
			),
		},
	},
	Lock = {
		{
			Icon = "🔒",
			Title = "LOCK your lab",
			Body = "At Rebirth 1 other players can steal your displayed orbs, and you can steal theirs. LOCK your lab to keep thieves out for 60 s.",
		},
		{ Icon = "🏃", Title = "Stealing", Body = "Hold E on an enemy pedestal to grab an orb, then run it home. Catch thieves by touching them." },
	},
	Gacha = {
		{ Icon = "🎰", Title = "Gacha Pad", Body = "Use the Gacha Pad to get orbs. Each pull costs a little more than the last, until you rebirth." },
		{ Icon = "🍀", Title = "Odds", Body = "The pad shows your odds. Rebirths and luck boosts make rare orbs more likely." },
		{ Icon = "⌨️", Title = "Keys", Body = "Stand by the pad: E pulls one, R pulls ten. On a controller X and Y, on a phone tap the buttons." },
		{ Icon = "🔁", Title = "Auto pull", Body = "Press T and the pad pulls 10 orbs at a time, again and again, showing each batch. It stops when you press T again, walk away or can't afford 10 pulls. It's free for everyone." },
	},
} :: { [string]: { Card } }

return TutorialConfig
