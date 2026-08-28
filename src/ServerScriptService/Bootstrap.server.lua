local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Services

print("=== BOOTSTRAP SCRIPT STARTED ===")

print("Loading LightingService...")
local LightingService = require(Services.LightingService)
print("LightingService Loaded!")

print("Loading PlayerDataService...")
local PlayerDataService = require(Services.PlayerDataService)
print("PlayerDataService Loaded!")

print("Loading FusionService...")
local FusionService = require(Services.FusionService)
print("FusionService Loaded!")

print("Loading FusionMachineService...")
local FusionMachineService = require(Services.FusionMachineService)
print("FusionMachineService Loaded!")

print("Loading TycoonService...")
local TycoonService = require(Services.TycoonService)
print("TycoonService Loaded!")

print("Loading ItemService...")
local ItemService = require(Services.ItemService)
print("ItemService Loaded!")

print("Loading DebugService...")
local DebugService = require(Services.DebugService)
print("DebugService Loaded!")

print("Initializing Services...")
LightingService.Init()
FusionMachineService.Init()
PlayerDataService.Init()
FusionService.Init()
TycoonService.Init()
ItemService.Init()
DebugService.Init()

print("=== ALL SERVICES INITIALIZED SUCCESSFULLY ===")