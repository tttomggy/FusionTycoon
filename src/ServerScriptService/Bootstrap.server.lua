--!strict
-- Server entry point. All it does is hand the Services folder to
-- ServiceManager, which owns loading and the Init/Start lifecycle.
--
-- Adding a service no longer means editing this file: drop the ModuleScript
-- into Services/ and it is picked up automatically. See ServiceTemplate.lua
-- for the contract, and ServiceManager.INIT_ORDER for the (temporary,
-- documented) explicit boot order.
local ServerScriptService = game:GetService("ServerScriptService")

local ServiceManager = require(script.Parent.ServiceManager)

ServiceManager.Load(ServerScriptService.Services)
ServiceManager.Start()
