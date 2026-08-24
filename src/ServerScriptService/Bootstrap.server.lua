local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Services

local PlayerDataService = require(Services.PlayerDataService)
local FusionService = require(Services.FusionService)
local TycoonService = require(Services.TycoonService)

-- PlayerDataService must be ready before other services start accepting requests.
PlayerDataService.Init()
FusionService.Init()
TycoonService.Init()
