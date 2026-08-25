local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Services

print("=== BOOTSTRAP SCRIPT STARTED ===")

print("Loading PlayerDataService...")
local PlayerDataService = require(Services.PlayerDataService)
print("PlayerDataService Loaded!")

print("Loading FusionService...")
local FusionService = require(Services.FusionService)
print("FusionService Loaded!")

print("Loading TycoonService...")
local TycoonService = require(Services.TycoonService)
print("TycoonService Loaded!")

print("Initializing Services...")
PlayerDataService.Init()
FusionService.Init()
TycoonService.Init()

print("=== ALL SERVICES INITIALIZED SUCCESSFULLY ===")