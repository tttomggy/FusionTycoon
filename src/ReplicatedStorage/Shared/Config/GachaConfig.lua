--!strict
--[[
	GachaConfig
	-----------
	The Gacha Pad's remote pulls and Auto pull (TycoonService; the card's key
	bar is GachaBoardController). Prices and odds are TycoonConfig /
	FusionConfig; this is only the convenience layer.

	Auto pull (the T key) is FREE for every player, not a pass and not sold
	(docs/systems/monetization.md, "earned, never sold"): while it is on the
	server runs a x10 pull (the same shared pull function as the R key) and
	the client shows the 10-pull card, which closes itself after
	AutoPullCardSeconds; the BEST OF 10 big card follows the reveal rule like
	a manual x10 and waits for the player to close it. The client then fires
	AutoPullReady and the server starts the next x10, never sooner than
	AutoPullMinSeconds after the previous one and after at most
	AutoPullTimeoutSeconds without the signal. It stops by itself when the
	player can't afford x10, walks away, starts carrying, dies or leaves, or
	presses T again.
]]
local GachaConfig = {}

GachaConfig.AutoPullCardSeconds = 2.5 -- the 10-pull card closes itself after this long during Auto pull
GachaConfig.AutoPullMinSeconds = 3 -- never two auto x10 pulls closer than this
GachaConfig.AutoPullTimeoutSeconds = 8 -- the next x10 starts without AutoPullReady after this long
-- RequestGachaPull / SetAutoPull need the character this many studs (on top
-- of the pad prompt's own PromptDistance) from the pad: a little lag
-- allowance, so a pull is never refused for standing on the pad's edge.
GachaConfig.RangeSlack = 3
-- The key bar dims its buttons (and says "Step closer") beyond this much of
-- the server's reach, so the two never disagree at the edge.
GachaConfig.ClientReachMargin = 1

return GachaConfig
