local Controllers = script.Parent.Controllers

local InventoryController = require(Controllers.InventoryController)
local FusionController = require(Controllers.FusionController)
local TycoonController = require(Controllers.TycoonController)
local ItemController = require(Controllers.ItemController)
local AnnouncementController = require(Controllers.AnnouncementController)
local HudController = require(Controllers.HudController)
local ToastController = require(Controllers.ToastController)
local ResultController = require(Controllers.ResultController)

-- Data controllers first so their remote listeners are connected before
-- anything else (the server syncs as soon as your save loads).
InventoryController.Init()
TycoonController.Init()
ToastController.Init()
AnnouncementController.Init()
HudController.Init()
ResultController.Init()

-- FusionController waits for this player's own plot (and its Fusion
-- Machine) to replicate, so it gets its own thread instead of blocking.
task.spawn(FusionController.Init)

-- ItemController waits on the local player's own Pedestals folder, which
-- only exists after they claim their plot - possibly much later than
-- startup - so it runs on its own thread instead of blocking this script.
task.spawn(ItemController.Init)
