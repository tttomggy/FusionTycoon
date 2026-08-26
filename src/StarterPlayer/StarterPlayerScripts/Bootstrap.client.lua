local Controllers = script.Parent.Controllers

local InventoryController = require(Controllers.InventoryController)
local FusionController = require(Controllers.FusionController)
local TycoonController = require(Controllers.TycoonController)
local ItemController = require(Controllers.ItemController)
local AnnouncementController = require(Controllers.AnnouncementController)

InventoryController.Init()
FusionController.Init()
TycoonController.Init()
AnnouncementController.Init()

-- ItemController waits on the local player's own Pedestals folder, which
-- only exists after they claim their plot - possibly much later than
-- startup - so it runs on its own thread instead of blocking this script.
task.spawn(ItemController.Init)
