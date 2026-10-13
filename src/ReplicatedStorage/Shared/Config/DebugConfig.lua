--!strict
--[[
	DebugConfig
	-----------
	Studio-only switches. Every one of them is ignored on a live server (the
	code that reads them also checks RunService:IsStudio()).

	  SkipTutorialInStudio   Every player who joins in Studio (Player1,
	                         Player2 ...) gets the tutorial marked Done on
	                         load: the full HUD, no banner / cards / hand.
	                         No rewards are granted and the free pulls are
	                         left alone. `/tutorial reset` and Settings'
	                         "Replay tutorial" still run it in that session.
]]
local DebugConfig = {}

DebugConfig.SkipTutorialInStudio = true

return DebugConfig
