local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Services

local PlayerDataService = require(Services.PlayerDataService)
local FusionService = require(Services.FusionService)

-- PlayerDataService must be ready before FusionService starts accepting requests.
PlayerDataService.Init()
FusionService.Init()
