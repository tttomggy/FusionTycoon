local Controllers = script.Parent.Controllers

local InventoryController = require(Controllers.InventoryController)
local FusionController = require(Controllers.FusionController)
local TycoonController = require(Controllers.TycoonController)
local ItemController = require(Controllers.ItemController)
local AnnouncementController = require(Controllers.AnnouncementController)
local HudController = require(Controllers.HudController)
local ToastController = require(Controllers.ToastController)
local ResultController = require(Controllers.ResultController)
local WorldLabelController = require(Controllers.WorldLabelController)
local WorldAnimationController = require(Controllers.WorldAnimationController)
local GoalMarkerController = require(Controllers.GoalMarkerController)
local BeltController = require(Controllers.BeltController)
local GeneratorController = require(Controllers.GeneratorController)
local FactoryController = require(Controllers.FactoryController)
local HeistController = require(Controllers.HeistController)

-- Data controllers first so their remote listeners are connected before
-- anything else (the server syncs as soon as your save loads).
InventoryController.Init()
TycoonController.Init()
ToastController.Init()
AnnouncementController.Init()
HudController.Init()
ResultController.Init()
WorldAnimationController.Init()
GoalMarkerController.Init()
BeltController.Init()
GeneratorController.Init()
HeistController.Init()

-- FusionController waits for this player's own plot (and its Fusion
-- Machine) to replicate, so it gets its own thread instead of blocking.
task.spawn(FusionController.Init)

-- Waits for the server's plots folder before hiding other players'
-- owner-only labels.
task.spawn(WorldLabelController.Init)

-- Also waits for the plots folder, then animates every nearby factory line.
task.spawn(FactoryController.Init)

-- ItemController waits on the local player's own Pedestals folder, which
-- only exists after they claim their plot - possibly much later than
-- startup - so it runs on its own thread instead of blocking this script.
task.spawn(ItemController.Init)
