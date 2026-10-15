--!strict
--[[
	GachaConfig
	-----------
	The Gacha Pad's remote pulls and Auto pull (TycoonService; the card's key
	bar is GachaBoardController). Prices and odds are TycoonConfig /
	FusionConfig; this is only the convenience layer.

	Auto pull (the T key) is FREE for every player, not a pass and not sold
	(docs/systems/monetization.md, "earned, never sold"): while it is on the
	server makes one single pull every AutoPullSeconds, each one following the
	player's reveal rule like Auto-Fuse (no big card for every Common, only
	the small skipped line). It stops by itself when the player can't afford
	the pull, walks away, starts carrying, dies or leaves, or presses T again.
]]
local GachaConfig = {}

GachaConfig.AutoPullSeconds = 1.2 -- between two auto pulls
-- RequestGachaPull / SetAutoPull need the character this many studs (on top
-- of the pad prompt's own PromptDistance) from the pad: a little lag
-- allowance, so a pull is never refused for standing on the pad's edge.
GachaConfig.RangeSlack = 3
-- The key bar dims its buttons (and says "Step closer") beyond this much of
-- the server's reach, so the two never disagree at the edge.
GachaConfig.ClientReachMargin = 1

return GachaConfig
