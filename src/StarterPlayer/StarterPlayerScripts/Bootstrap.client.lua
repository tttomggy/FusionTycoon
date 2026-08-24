local Controllers = script.Parent.Controllers

local InventoryController = require(Controllers.InventoryController)
local FusionController = require(Controllers.FusionController)
local TycoonController = require(Controllers.TycoonController)

InventoryController.Init()
FusionController.Init()
TycoonController.Init()
