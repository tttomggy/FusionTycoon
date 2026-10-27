local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Controllers = script.Parent.Controllers
local UI = script.Parent.UI

-- One controller failing to load or Init must never leave the player with no
-- HUD: every require and every Init runs behind xpcall, warns with the
-- traceback, and the boot carries on with the next one.
local function failed(name: string, err: any)
	warn(("[Bootstrap] %s failed: %s"):format(name, tostring(err)))
end

local function safeRequire(name: string, container: Instance): any?
	local ok, result = xpcall(function()
		local module = container:FindFirstChild(name)
		assert(module and module:IsA("ModuleScript"), "no ModuleScript named " .. name)
		return require(module)
	end, debug.traceback)
	if not ok then
		failed(name, result)
		return nil
	end
	return result
end

local function safeInit(name: string, module: any?)
	if module == nil then
		return
	end
	local ok, err = xpcall(function()
		module.Init()
	end, debug.traceback)
	if not ok then
		failed(name, err)
	end
end

-- Landscape on every device, set before anything is built. The place file's
-- StarterGui carries the same value (default.project.json); this wins over an
-- old place file that doesn't, so a phone never opens the game in portrait.
Players.LocalPlayer:WaitForChild("PlayerGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

-- Preload every sound slot (SoundConfig); a bad id warns once, then is silent.
local SoundKit = safeRequire("SoundKit", ReplicatedStorage.Shared.Modules)
if SoundKit then
	local ok, err = xpcall(SoundKit.Preload, debug.traceback)
	if not ok then
		failed("SoundKit.Preload", err)
	end
end

local InventoryController = safeRequire("InventoryController", Controllers)
local FusionController = safeRequire("FusionController", Controllers)
local TycoonController = safeRequire("TycoonController", Controllers)
local ItemController = safeRequire("ItemController", Controllers)
local AnnouncementController = safeRequire("AnnouncementController", Controllers)
local HudController = safeRequire("HudController", Controllers)
local ToastController = safeRequire("ToastController", Controllers)
local ResultController = safeRequire("ResultController", Controllers)
local WorldLabelController = safeRequire("WorldLabelController", Controllers)
local WorldAnimationController = safeRequire("WorldAnimationController", Controllers)
local GoalMarkerController = safeRequire("GoalMarkerController", Controllers)
local BeltController = safeRequire("BeltController", Controllers)
local GeneratorController = safeRequire("GeneratorController", Controllers)
local FactoryController = safeRequire("FactoryController", Controllers)
local HeistController = safeRequire("HeistController", Controllers)
local EventController = safeRequire("EventController", Controllers)
local AdminController = safeRequire("AdminController", Controllers)
local ShopController = safeRequire("ShopController", Controllers)
local DailyController = safeRequire("DailyController", Controllers)
local NotifyOptInController = safeRequire("NotifyOptInController", Controllers)
local TutorialController = safeRequire("TutorialController", Controllers)
local CombatController = safeRequire("CombatController", Controllers)
local JumpPadController = safeRequire("JumpPadController", Controllers)
local MusicController = safeRequire("MusicController", Controllers)
local GachaBoardController = safeRequire("GachaBoardController", Controllers)
local LoopCoachController = safeRequire("LoopCoachController", Controllers)
local HudGate = safeRequire("HudGate", UI)
local TopStack = safeRequire("TopStack", UI)

-- Data controllers first so their remote listeners are connected before
-- anything else (the server syncs as soon as your save loads).
safeInit("InventoryController", InventoryController)
safeInit("TycoonController", TycoonController)
safeInit("ToastController", ToastController)
safeInit("TopStack", TopStack) -- the top-centre slots + the announcement queue
safeInit("AnnouncementController", AnnouncementController)
safeInit("HudController", HudController)
safeInit("ResultController", ResultController)
safeInit("WorldAnimationController", WorldAnimationController)
safeInit("GoalMarkerController", GoalMarkerController)
safeInit("BeltController", BeltController)
safeInit("GeneratorController", GeneratorController)
safeInit("HeistController", HeistController)
safeInit("EventController", EventController)
safeInit("AdminController", AdminController)
safeInit("ShopController", ShopController)
safeInit("DailyController", DailyController)
safeInit("NotifyOptInController", NotifyOptInController) -- the notification opt-in ask (5 min in, at the first high moment)
safeInit("TutorialController", TutorialController) -- the first-time tutorial (banner, dotted path, hand)
safeInit("HudGate", HudGate) -- the progressive HUD: what a new player sees builds up with the tutorial
safeInit("CombatController", CombatController) -- weapons: the bar, swings, ragdoll, hit effects
safeInit("MusicController", MusicController) -- the background playlist (Settings -> Music)
safeInit("JumpPadController", JumpPadController) -- the 2nd floor's jump pads launch your own character
safeInit("GachaBoardController", GachaBoardController) -- the Gacha odds card above your pad (+ its E / R / ? buttons)
safeInit("LoopCoachController", LoopCoachController) -- the loop-closing lines (new orb earns, more cash, free orb)

-- FusionController waits for this player's own plot (and its Fusion
-- Machine) to replicate, so it gets its own thread instead of blocking.
task.spawn(safeInit, "FusionController", FusionController)

-- Waits for the server's plots folder before hiding other players'
-- owner-only labels.
task.spawn(safeInit, "WorldLabelController", WorldLabelController)

-- Also waits for the plots folder, then animates every nearby factory line.
task.spawn(safeInit, "FactoryController", FactoryController)

-- ItemController answers the locked pedestal spots' Unlock prompt.
task.spawn(safeInit, "ItemController", ItemController)

-- Last, after every gameplay controller: they can never block the HUD.
-- /selftest is Studio-only, so the live client does not even load its file.
if RunService:IsStudio() then
	safeInit("SelfTestController", safeRequire("SelfTestController", Controllers))
end
safeInit("TrailerController", safeRequire("TrailerController", Controllers)) -- /trailer (admins; client-only cinematic)
