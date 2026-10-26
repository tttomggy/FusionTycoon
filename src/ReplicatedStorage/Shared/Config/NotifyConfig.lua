--!strict
--[[
	NotifyConfig
	------------
	When NotifyOptInController asks for Roblox experience notifications (once
	per session, Roblox's own modal). Never on join: not before
	MinSessionSeconds of this session's play and a finished tutorial, then at
	the first high moment (a successful fusion's card closing, a pull of
	MinPullTier or better closing, the daily reveal closing), or at
	FallbackSeconds the next time no overlay is open.
]]
local NotifyConfig = {}

NotifyConfig.MinSessionSeconds = 300
NotifyConfig.FallbackSeconds = 480
NotifyConfig.MinPullTier = "Epic"

return NotifyConfig
