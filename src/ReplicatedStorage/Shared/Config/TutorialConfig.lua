--!strict
--[[
	TutorialConfig
	--------------
	The mandatory first-time tutorial (TutorialService on the server,
	TutorialController on the client), and the "?" help slideshows that
	replay its cards.

	Each step:
	  Id      stable name (TutorialService's predicates, analytics)
	  Kind    "Card"   done on OK (remote TutorialAdvance, re-checked)
	          "Action" done only by the real, server-confirmed action
	                   (TutorialService's predicate, checked in every sync)
	          "Open"   done when the client opens that UI (Index, Rebirth)
	          "Arrive" done on OK once the player stands at Target
	                   (the server checks the distance)
	  Icon / Title / Body   the card: at most 2 short sentences
	  Target  world target (GoalMarkerController names): the lit path
	  Coach   HUD element to ring (HudController.GetCoachTarget names)
	  Skip    "Claimed" | "Upgraded" | "MultiplierBought": skipped when the
	          save already has it (a resumed or returning player)

	Saved as PlayerData.Tutorial = { Step, Done, FreeFuse, FreePulls,
	PullsGranted, Base, Replay, ReplayHint }; Step 0 = not decided yet (the
	first sync decides: new player -> 1, a save with real progress -> Done).
]]
local RebirthConfig = require(script.Parent.RebirthConfig)
local NumberFormat = require(script.Parent.Parent.Modules.NumberFormat)

local TutorialConfig = {}

export type Kind = "Card" | "Action" | "Open" | "Arrive"

export type Card = {
	Icon: string,
	Title: string,
	Body: string,
}

export type Step = {
	Id: string,
	Kind: Kind,
	Icon: string,
	Title: string,
	Body: string,
	Target: string?,
	Coach: string?,
	Skip: string?,
	OkText: string?,
}

-- Old saves with real progress skip it (with a one-time "replay in ⚙" toast).
TutorialConfig.ProgressRebirths = 1
TutorialConfig.ProgressPulls = 20
TutorialConfig.FreePulls = 2 -- guaranteed plain Commons, once per account
TutorialConfig.FreePullTier = "Common"
TutorialConfig.ArriveDistance = 14 -- studs from the Target (server check)
TutorialConfig.NextCardDelay = 0.6 -- after a step's "Nice!"
TutorialConfig.PathRebuildSeconds = 0.3
TutorialConfig.GoalPathSessions = 2 -- the goal path is on by default this many sessions
-- Optional chevron texture for the path Beams (an uploaded decal id). Empty:
-- a solid glowing ribbon whose transparency flows toward the target.
TutorialConfig.PathTexture = ""

TutorialConfig.Steps = {
	{
		Id = "welcome",
		Kind = "Card",
		Icon = "🧪",
		Title = "Welcome!",
		Body = "Welcome to your Fusion Lab! Pull glowing orbs, fuse them into rarer ones, and get rich.",
	},
	{
		Id = "claim",
		Kind = "Action",
		Icon = "🏠",
		Title = "Claim your lab",
		Body = "This lab is waiting for you. Follow the glowing path and step on the pad to claim it!",
		Target = "ClaimStation",
		Skip = "Claimed",
	},
	{
		Id = "upgrade",
		Kind = "Action",
		Icon = "⚡",
		Title = "Upgrade a generator",
		Body = "Generators make your cash. Upgrade the Basic Generator.",
		Target = "Generator_basic_generator",
		Coach = "Upgrades",
		Skip = "Upgraded",
	},
	{
		Id = "pull",
		Kind = "Action",
		Icon = "🎰",
		Title = "Pull an orb",
		Body = "Use the Gacha Pad to get orbs. Your first 2 pulls are free!",
		Target = "GachaStation",
	},
	{
		Id = "pedestals",
		Kind = "Card",
		Icon = "🏛",
		Title = "Pedestals",
		Body = "Your best orbs go on display by themselves and make money every second.",
		Target = "Pedestal1",
		Coach = "Income",
	},
	{
		Id = "fuse",
		Kind = "Action",
		Icon = "🔮",
		Title = "Fuse",
		Body = "Put 2 orbs of the same tier in the Fusion Machine to make a better one.",
		Target = "FusionMachine",
	},
	{
		Id = "index",
		Kind = "Open",
		Icon = "📖",
		Title = "Your Index",
		Body = "Every new orb and mutation fills your Index and boosts your income forever.",
		Coach = "Index",
	},
	{
		Id = "multiplier",
		Kind = "Action",
		Icon = "✖️",
		Title = "Multiplier Pad",
		Body = "This multiplies ALL your money.",
		Target = "MultiplierStation",
		Skip = "MultiplierBought",
	},
	{
		Id = "events",
		Kind = "Card",
		Icon = "🌦",
		Title = "Lab weather",
		Body = "Every 15 minutes the lab weather changes: Golden Rain, Meteors, Void Moon… Tap the chip to see what to do.",
		Coach = "EventChip",
	},
	{
		Id = "gifts",
		Kind = "Card",
		Icon = "🎁",
		Title = "Free gifts",
		Body = "Play to unlock free gifts.",
		Coach = "Gifts",
	},
	{
		Id = "lock",
		Kind = "Arrive",
		Icon = "🔒",
		Title = "LOCK your lab",
		Body = "At Rebirth 1 other players can steal your displayed orbs, and you can steal theirs. LOCK your lab to keep thieves out for 60 s.",
		Target = "LockConsole",
	},
	{
		Id = "steal",
		Kind = "Card",
		Icon = "🏃",
		Title = "Stealing",
		Body = "Hold E on an enemy pedestal to grab an orb, then run it home. Catch thieves by touching them.",
	},
	{
		Id = "rebirth",
		Kind = "Open",
		Icon = "♻️",
		Title = "Rebirth",
		Body = ("Get to %s and Rebirth. You keep your orbs, and every rebirth makes you earn faster and unlocks new things."):format(
			NumberFormat.Money(RebirthConfig.GetCost(0))
		),
		Coach = "Rebirth",
	},
	{
		Id = "finish",
		Kind = "Card",
		Icon = "🎉",
		Title = "You're ready!",
		Body = "Your goal is on the top left. Follow the glowing path anytime.",
		OkText = "LET'S GO!",
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

-- The card for step `id` (the "?" slideshows reuse the tutorial's copy).
local function stepCard(id: string): Card
	local index = TutorialConfig.IndexOf(id) :: number
	local step = TutorialConfig.Steps[index]
	return { Icon = step.Icon, Title = step.Title, Body = step.Body }
end

-- "?" help: topic -> its cards, a mini slideshow (◀ ▶, OK).
TutorialConfig.Help = {
	Fuse = {
		stepCard("fuse"),
		{ Icon = "🎯", Title = "Same tier only", Body = "Fuse orbs of the same tier: 2 Commons make a Rare, 2 Rares make an Epic." },
		{ Icon = "📈", Title = "More orbs, better odds", Body = "Put in 2 to 6 orbs. The more you add, the better the chance it works." },
		{ Icon = "🛟", Title = "A fail keeps your best", Body = "If it fails, you keep your best orb. Only the others are used up." },
		{ Icon = "✨", Title = "Mutations", Body = "If every orb has the same mutation, the new orb keeps it. Mix them and it's lost." },
		{ Icon = "🤫", Title = "Secret", Body = "Fusing Mythics into a Secret unlocks at Rebirth 1." },
	},
	Upgrades = {
		stepCard("upgrade"),
		{ Icon = "⏩", Title = "MAX", Body = "MAX buys as many levels as you can afford. MAX ALL does it for every generator." },
	},
	Index = { stepCard("index") },
	Rebirth = { stepCard("rebirth") },
	Lock = { stepCard("lock"), stepCard("steal") },
	Gacha = {
		{ Icon = "🎰", Title = "Gacha Pad", Body = "Use the Gacha Pad to get orbs. Each pull costs a little more than the last, until you rebirth." },
		{ Icon = "🍀", Title = "Odds", Body = "The pad shows your odds. Rebirths and luck boosts make rare orbs more likely." },
	},
} :: { [string]: { Card } }

return TutorialConfig
