local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Controllers = script.Parent.Controllers

-- Preload every sound slot (SoundConfig); a bad id warns once, then is silent.
require(ReplicatedStorage.Shared.Modules.SoundKit).Preload()

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
local EventController = require(Controllers.EventController)
local AdminController = require(Controllers.AdminController)
local ShopController = require(Controllers.ShopController)
local DailyController = require(Controllers.DailyController)
local SelfTestController = require(Controllers.SelfTestController)
local TrailerController = require(Controllers.TrailerController)
local TutorialController = require(Controllers.TutorialController)
local CombatController = require(Controllers.CombatController)

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
EventController.Init()
AdminController.Init()
ShopController.Init()
DailyController.Init()
SelfTestController.Init() -- Studio /selftest only
TrailerController.Init() -- /trailer (admins; client-only cinematic)
TutorialController.Init() -- the first-time tutorial (cards, lit path, coach rings)
CombatController.Init() -- weapons: the bar, swings, ragdoll, hit effects

-- FusionController waits for this player's own plot (and its Fusion
-- Machine) to replicate, so it gets its own thread instead of blocking.
task.spawn(FusionController.Init)

-- Waits for the server's plots folder before hiding other players'
-- owner-only labels.
task.spawn(WorldLabelController.Init)

-- Also waits for the plots folder, then animates every nearby factory line.
task.spawn(FactoryController.Init)

-- ItemController answers the locked pedestal spots' Unlock prompt.
task.spawn(ItemController.Init)
