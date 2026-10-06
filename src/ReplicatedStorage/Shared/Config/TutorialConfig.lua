--!strict
--[[
	TutorialConfig
	--------------
	The mandatory first-time tutorial (TutorialService on the server,
	TutorialController on the client), and the "?" help slideshows.

	Tutorial 2: it works like the egg games' tutorials. ONE instruction at a
	time as a big banner at the top centre ("Upgrade your generator · 8m",
	the live distance), a dotted lime path from your feet to the target,
	chevrons on the floor at the target, one pointing hand 👆 on the exact
	button to press, and a big contextual button near the bottom ("PULL")
	once you stand at a world target. No OK cards. The HUD builds up as you
	go (HudReveal).

	Each step:
	  Id         stable name (TutorialService's predicates, analytics)
	  Kind       "Action" done only by the real, server-confirmed action
	                      (TutorialService's predicate, checked in every sync)
	             "Timed"  done by itself once Seconds have passed (the client
	                      asks, the server checks the clock)
	             "Open"   done when the player opens that UI (chip, panel), or
	                      after Seconds (whichever is first)
	  Banner     the instruction, at most 6 words (the distance is added)
	  Sub        an optional second line, one short sentence
	  Target     world target (GoalMarkerController names): path + chevrons
	  PromptName the ProximityPrompt at the target the contextual button
	             triggers; Prompt is the button's word ("PULL")
	  Hand       HUD element the hand points at ("EventChip", "Rebirth")
	  Seconds    Timed / Open: how long
	  Skip       "Claimed" | "Upgraded" | "MultiplierBought": skipped when the
	             save already has it (a resumed or returning player)
	  SkipSeconds  an Action step the player may leave after this long when
	             it is out of reach (the Multiplier Pad: "Come back with $X")

	Saved as PlayerData.Tutorial = { Ver, Step, Done, FreeFuse, FreePulls,
	PullsGranted, Base, Replay, ReplayHint }; Step 0 = not decided yet (the
	first sync decides: new player -> 1, a save with real progress -> Done).
	A save from Tutorial 1 (no Ver) has its step mapped by MigrateStep.
]]
local RebirthConfig = require(script.Parent.RebirthConfig)
local NumberFormat = require(script.Parent.Parent.Modules.NumberFormat)

local TutorialConfig = {}

export type Kind = "Action" | "Timed" | "Open"

export type Card = {
	Icon: string,
	Title: string,
	Body: string,
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
	Skip: string?,
	SkipSeconds: number?,
}

-- The saved layout version (Tutorial 2 = 2; no Ver = Tutorial 1's 14 steps).
TutorialConfig.DataVersion = 2

-- Old saves with real progress skip it (with a one-time "replay in ⚙" toast).
TutorialConfig.ProgressRebirths = 1
TutorialConfig.ProgressPulls = 20
TutorialConfig.FreePulls = 2 -- guaranteed plain Commons, once per account
TutorialConfig.FreePullTier = "Common"
TutorialConfig.PathRebuildSeconds = 0.3
TutorialConfig.GoalPathSessions = 2 -- the goal path is on by default this many sessions

-- The banner and the welcome splash.
TutorialConfig.StepDelay = 0.4 -- after a step's ✓, the next banner slides in
TutorialConfig.WelcomeSeconds = 2 -- "WELCOME TO YOUR LAB!" auto-fades, no button

-- The arrow path (client-only: a flat ">" of two thin Neon bars per arrow,
-- TutorialPath).
TutorialConfig.PathArrowSpacing = 3 -- studs between arrows (widens past PathMaxArrows)
TutorialConfig.PathArrowSize = Vector3.new(1.2, 0.1, 0.25) -- one bar: length, height, thickness
TutorialConfig.PathArrowLift = 0.2 -- lying this far above the floor
TutorialConfig.PathMaxArrows = 40 -- 80 parts, a fixed pool
TutorialConfig.PathFlowSeconds = 1.2 -- one pulse runs from you to the target
TutorialConfig.PathArriveStuds = 6 -- the arrows stop this close to the target
TutorialConfig.ChevronCount = 3

TutorialConfig.Steps = {
	{
		Id = "claim",
		Kind = "Action",
		Banner = "Claim your lab",
		Target = "ClaimStation",
		Skip = "Claimed",
	},
	{
		Id = "upgrade",
		Kind = "Action",
		Banner = "Upgrade your generator",
		Target = "Generator_basic_generator",
		PromptName = "GeneratorPrompt",
		Prompt = "UPGRADE",
		Skip = "Upgraded",
	},
	{
		Id = "pull",
		Kind = "Action",
		Banner = "Pull an orb",
		Sub = "Your first 2 are free!",
		Target = "GachaStation",
		PromptName = "PullPrompt",
		Prompt = "PULL",
	},
	{
		Id = "pull2",
		Kind = "Action",
		Banner = "Pull one more!",
		Target = "GachaStation",
		PromptName = "PullPrompt",
		Prompt = "PULL",
	},
	{
		Id = "pedestals",
		Kind = "Timed",
		Banner = "Your orbs make money!",
		Target = "Pedestal1",
		Seconds = 3,
	},
	{
		Id = "fuse",
		Kind = "Action",
		Banner = "Fuse 2 orbs",
		Target = "FusionMachine",
		PromptName = "FusePrompt",
		Prompt = "FUSE",
	},
	{
		Id = "multiplier",
		Kind = "Action",
		Banner = "Make more money",
		Target = "MultiplierStation",
		PromptName = "UpgradePrompt",
		Prompt = "BUY",
		Skip = "MultiplierBought",
		SkipSeconds = 3,
	},
	{
		Id = "events",
		Kind = "Open",
		Banner = "Lab weather!",
		Sub = "Every 15 min. Tap it to see what to do",
		Hand = "EventChip",
		Seconds = 6,
	},
	{
		Id = "rebirth",
		Kind = "Open",
		Banner = ("Reach %s to Rebirth"):format(NumberFormat.Money(RebirthConfig.GetCost(0))),
		Hand = "Rebirth",
		Seconds = 6,
	},
	{
		Id = "finish",
		Kind = "Timed",
		Banner = "You're ready!",
		Seconds = 3,
	},
} :: { Step }

function TutorialConfig.GetStep(index: number): Step?
	return TutorialConfig.Steps[index]
end

function TutorialConfig.IndexOf(id: string): number?
	for index, step in TutorialConfig.Steps do
		if step.Id == id then
			return index
		end
	end
	return nil
end

-- Tutorial 1's step (its 14-step list) -> this list's step. A save in the
-- middle of the old one resumes at the nearest step here.
local OLD_STEP_IDS = {
	"claim", -- welcome
	"claim",
	"upgrade",
	"pull",
	"pedestals",
	"fuse",
	"multiplier", -- index
	"multiplier",
	"events",
	"rebirth", -- gifts
	"rebirth", -- lock
	"rebirth", -- steal
	"rebirth",
	"finish",
}

function TutorialConfig.MigrateStep(oldStep: number): number
	local id = OLD_STEP_IDS[oldStep]
	return if id then TutorialConfig.IndexOf(id) :: number else 1
end

--[[ The HUD builds up ------------------------------------------------------------
	A new player starts with the cash card and the banner only. Each element
	pops in (HudController) when the step it names begins; the ones at
	"finish" pop in one by one (HudRevealDelay seconds after the step starts).
	Done / old saves / a replay show everything.
]]

TutorialConfig.HudKeys = { "Upgrades", "Items", "Index", "Rebirth", "Event", "Settings", "Shop", "Goal" }

TutorialConfig.HudReveal = {
	Upgrades = "upgrade", -- the upgrade step
	Items = "pull2", -- after the first pull
	Index = "multiplier", -- after the first fusion
	Rebirth = "rebirth",
	Event = "events",
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
	},
} :: { [string]: { Card } }

return TutorialConfig
