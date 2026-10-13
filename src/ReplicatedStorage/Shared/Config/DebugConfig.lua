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
	  StudioStartRebirths    Every player who joins in Studio ON THE MOCK
	                         STORE gets Rebirths raised to this (never
	                         lowered), the way `/rebirths 3` does it: both
	                         sides can fight with no commands typed.
	  StudioGrantAllWeapons  ... and every weapon, like `/weapons all`.
	                         Once per join. The Live store, live servers and
	                         the FT_StudioSaves test store never get either
	                         (DebugService.ShouldApplyStudioStart; /selftest
	                         asserts it). `/rebirths 0` still works to test
	                         Rebirth-0 flows during a session.
]]
local DebugConfig = {}

DebugConfig.SkipTutorialInStudio = true
DebugConfig.StudioStartRebirths = 3
DebugConfig.StudioGrantAllWeapons = true

return DebugConfig
