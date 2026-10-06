--!strict
--[[
	TipConfig
	---------
	The one-time tips and cards a player sees once per account. Seen ids are
	saved in PlayerData.Tips (a set) and sent in the snapshot; the client
	marks one with MarkTipSeen { Id }, and the server only accepts ids
	listed here. /tips reset (Studio) clears them all.
]]
local EventConfig = require(script.Parent.EventConfig)

local TipConfig = {}

TipConfig.Ids = {
	howToHeist = true, -- the HOW TO HEIST card, auto-opened after the first rebirth card
	stealHowTo = true, -- first visit to a lab with something to steal
	intruder = true, -- someone walked into your unlocked lab
	guarded = true, -- you're at a pedestal its owner is guarding
	catch = true, -- your first time as a victim: "TOUCH THEM!"
	lockAfterLoss = true, -- after your first real loss
	tutorialReplay = true, -- an old save skipped the tutorial: "replay it in ⚙ Settings" once
	giftHand = true, -- the hand on GIFTS the first time a gift is ready (TutorialController)
	questHand = true, -- the hand on QUESTS the first time a quest can be claimed
} :: { [string]: boolean }

-- "event_<EventId>": the HUD event chip pulses until the first tap for
-- that event (EventController).
for _, eventId in EventConfig.Order do
	TipConfig.Ids["event_" .. eventId] = true
end

function TipConfig.IsValid(id: unknown): boolean
	return typeof(id) == "string" and TipConfig.Ids[id] == true
end

return TipConfig
