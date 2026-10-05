--!strict
--[[
	SelfTestController
	------------------
	The client half of Studio's /selftest (DebugService runs the server
	half and prints every PASS / FAIL). Inert outside Studio. On the
	server's SelfTest event it:

	  1. Fuzzes every remote that takes arguments with junk (wrong types,
	     NaN, ±inf, huge / negative numbers, missing fields, a 10k-char
	     string, another player's id) and spams one 50 times. The server
	     checks its own Output and the player's state for changes.
	  2. Hashes the event lineup for the server's slots (determinism:
	     client and server must agree).
	  3. Opens and closes every panel twice at phone and desktop scale and
	     counts PlayerGui instances: a second open/close cycle must not add
	     any (leftovers = a leak).
	  4. Loads every SoundConfig slot (SoundKit.CheckAll).
	  5. Checks every UIKit.Modal draws over the HUD (DisplayOrder +
	     backdrop) and that every shop chip lands its section's header
	     within 2 px of the top at both scales.

	Then it sends SelfTestReport with the results and any client errors
	seen in Output meanwhile. Never fires a remote with a VALID request:
	no no-argument remote (ClaimDaily, RequestRebirth, ...) is fuzzed,
	since any call to those is a real action.
]]
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local DealConfig = require(ReplicatedStorage.Shared.Config.DealConfig)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)

local SelfTestController = {}

local localPlayer = Players.LocalPlayer
local running = false

local NAN = 0 / 0
local INF = math.huge
local BIG_STRING = string.rep("x", 10000)

-- Junk for every remote that takes arguments. Each entry is the argument
-- list for one FireServer call. None of these is a valid request.
local function fuzzCases(otherUserId: number): { [string]: { { any } } }
	local junkNumbers = { NAN, INF, -INF, 1e308, -5, 0, 1.5, 2 ^ 53 }
	local cases: { [string]: { { any } } } = {
		RequestFusion = {
			{},
			{ "x" },
			{ { Uids = "x" } },
			{ { Uids = { 1, 2 } } },
			{ { Uids = { "a" } } },
			{ { Uids = { "a", "a" } } },
			{ { Uids = { "nope-1", "nope-2" } } },
			{ { Uids = { BIG_STRING, "b" } } },
		},
		RequestPlaceItem = { {}, { 5, "x" }, { "nope", NAN }, { "nope", INF }, { BIG_STRING, 1 }, { "nope", 1 } },
		RequestRemoveItem = { {}, { "x" }, { NAN }, { INF }, { -1 }, { 99 }, { 1.5 } },
		RequestUpgrade = { {}, { 5 }, { "no_such_generator" }, { BIG_STRING } },
		RequestUpgradeMax = { {}, { "x" }, { { GeneratorId = 5 } }, { { GeneratorId = "no_such_generator" } } },
		RequestSteal = {
			{},
			{ "x" },
			{ { OwnerUserId = localPlayer.UserId, PedestalIndex = 1 } },
			{ { OwnerUserId = otherUserId, PedestalIndex = 99 } },
			{ { OwnerUserId = otherUserId, PedestalIndex = NAN } },
		},
		RequestShopPurchase = { {}, { "x" }, { { Key = 5 } }, { { Key = "NoSuchProduct" } }, { { Key = BIG_STRING } } },
		ShopAnalytics = { {}, { { Event = "Nope" } }, { { Event = "ShopOpened", Key = "NoSuchProduct" } }, { { Event = 5 } } },
		ClaimGift = { {}, { "x" }, { { Index = 0 } }, { { Index = 99 } }, { { Index = "1" } } },
		SetSetting = {
			{},
			{ { Key = "Nope", Value = 1 } },
			{ { Key = "RevealRule", Tier = "Nope", Value = "Always" } },
			{ { Key = "RevealRule", Tier = "Common", Value = "Bogus" } },
			{ { Key = "SfxMuted", Value = "yes" } },
			{ { Key = "AutoFuse", Value = 1 } },
		},
		MarkTipSeen = { {}, { { Id = "nope" } }, { { Id = 5 } }, { { Id = BIG_STRING } } },
		AdminAction = { {}, { { Action = "Nope" } }, { { Action = "StartEvent", Args = { Id = "Nope" } } } },
	}
	for _, n in junkNumbers do
		table.insert(cases.RequestSteal, { { OwnerUserId = n, PedestalIndex = n } })
		table.insert(cases.ClaimGift, { { Index = n } })
		table.insert(cases.RequestRemoveItem, { n })
		table.insert(cases.SetSetting, { { Key = "SfxVolume", Value = if n == n and math.abs(n) ~= INF then "x" else n } })
	end
	return cases
end

local function fuzz(otherUserId: number): number
	local fired = 0
	for name, calls in fuzzCases(otherUserId) do
		local remote = (RemoteEvents :: any)[name] :: RemoteEvent?
		if remote then
			for _, args in calls do
				remote:FireServer(table.unpack(args))
				fired += 1
			end
		end
	end
	-- Spam: 50 junk calls in one second.
	for _ = 1, 50 do
		RemoteEvents.RequestRemoveItem:FireServer(99)
		fired += 1
		task.wait(0.02)
	end
	return fired
end

local function scheduleHash(slots: { number }): string
	local ids = {}
	for _, slot in slots do
		table.insert(ids, EventConfig.GetEventForSlot(slot).Id)
	end
	return table.concat(ids, ",")
end

type PanelSpec = { Name: string, Open: () -> (), Close: () -> () }

local function panelSpecs(): { PanelSpec }
	local function toggle(module: any): PanelSpec
		return { Name = "", Open = module.Toggle, Close = module.Toggle }
	end
	local specs: { PanelSpec } = {}
	local function add(name: string, spec: PanelSpec)
		spec.Name = name
		table.insert(specs, spec)
	end
	add("UpgradesPanel", toggle(require(UI.UpgradesPanel)))
	add("ShopPanel", toggle(require(UI.ShopPanel)))
	add("SettingsPanel", toggle(require(UI.SettingsPanel)))
	add("IndexPanel", toggle(require(UI.IndexPanel)))
	add("GiftsPanel", toggle(require(UI.GiftsPanel)))
	local rebirth = require(UI.RebirthPanel) :: any
	add("RebirthPanel", { Name = "", Open = rebirth.Open, Close = rebirth.Close })
	local fuse = require(UI.FusePanel) :: any
	add("FusePanel", { Name = "", Open = fuse.Open, Close = fuse.Close })
	local howTo = require(UI.HowToHeistPanel) :: any
	add("HowToHeistPanel", { Name = "", Open = howTo.Open, Close = howTo.Close })
	return specs
end

local function countGui(): number
	return #localPlayer:WaitForChild("PlayerGui"):GetDescendants()
end

-- Opens / closes each panel twice per scale; the instance count after the
-- second close must equal the count after the first (the first may build
-- the panel once, which is expected).
local function testPanels(): { string }
	local lines: { string } = {}
	for _, phone in { false, true } do
		UIKit.SetForcedPhone(phone)
		task.wait(0.2)
		for _, spec in panelSpecs() do
			local counts: { number } = {}
			local ok, err = pcall(function()
				for cycle = 1, 2 do
					spec.Open()
					task.wait(0.3)
					spec.Close()
					task.wait(0.4)
					counts[cycle] = countGui()
				end
			end)
			local scale = if phone then "phone" else "desktop"
			if not ok then
				table.insert(lines, ("FAIL panel %s (%s): %s"):format(spec.Name, scale, tostring(err)))
			elseif counts[2] ~= counts[1] then
				table.insert(lines, ("FAIL panel %s (%s): %+d instances after a second open/close"):format(spec.Name, scale, counts[2] - counts[1]))
			else
				table.insert(lines, ("PASS panel %s (%s)"):format(spec.Name, scale))
			end
		end
	end
	UIKit.SetForcedPhone(nil)
	return lines
end

-- The HUD's ScreenGuis: every open card must draw over them, dim
-- backdrop included.
local HUD_GUIS = { "Hud", "EventHud" }

local function testHudOrder(): { string }
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local hudTop = -math.huge
	for _, name in HUD_GUIS do
		local gui = playerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") then
			hudTop = math.max(hudTop, gui.DisplayOrder)
		end
	end
	local bad: { string } = {}
	for _, gui in UIKit.GetModalGuis() do
		if gui.DisplayOrder <= hudTop or not gui:FindFirstChild("Backdrop") then
			table.insert(bad, ("%s (%d)"):format(gui.Name, gui.DisplayOrder))
		end
	end
	if #bad > 0 then
		return { "FAIL hud below modals: " .. table.concat(bad, ", ") .. (" vs HUD %d"):format(hudTop) }
	end
	return { ("PASS hud below modals (%d cards over HUD %d)"):format(#UIKit.GetModalGuis(), hudTop) }
end

-- Every shop chip lands its header within 2 px of the top, at both scales.
local function testChipJumps(): { string }
	local lines: { string } = {}
	local shop = require(UI.ShopPanel) :: any
	for _, phone in { false, true } do
		UIKit.SetForcedPhone(phone)
		task.wait(0.2)
		local ok, err = pcall(function()
			shop.Open()
			task.wait(0.5)
			for _, line in shop.SelfTestChipJumps(if phone then "phone" else "desktop") do
				table.insert(lines, line)
			end
			shop.Toggle()
			task.wait(0.4)
		end)
		if not ok then
			table.insert(lines, "FAIL chip jumps: " .. tostring(err))
		end
	end
	UIKit.SetForcedPhone(nil)
	return lines
end

local function run(payload: any)
	if running then
		return
	end
	running = true
	local errors: { string } = {}
	local connection = LogService.MessageOut:Connect(function(message: string, kind: Enum.MessageType)
		if kind == Enum.MessageType.MessageError then
			table.insert(errors, message)
		end
	end)
	local otherUserId = if typeof(payload) == "table" and typeof(payload.OtherUserId) == "number" then payload.OtherUserId else 1
	local slots = if typeof(payload) == "table" and typeof(payload.Slots) == "table" then payload.Slots else {}
	local dealSlots = if typeof(payload) == "table" and typeof(payload.DealSlots) == "table" then payload.DealSlots else {}
	local dealKeys = {}
	for _, slot in dealSlots do
		table.insert(dealKeys, DealConfig.GetDealForSlot(slot))
	end

	local fired = fuzz(otherUserId)
	-- Give the server a moment to answer every junk call before it compares.
	task.wait(1.5)
	RemoteEvents.SelfTestReport:FireServer({ Stage = "Fuzz", Fired = fired })

	local panelLines = testPanels()
	for _, line in testHudOrder() do
		table.insert(panelLines, line)
	end
	for _, line in testChipJumps() do
		table.insert(panelLines, line)
	end
	local failedSounds = SoundKit.CheckAll()
	connection:Disconnect()
	RemoteEvents.SelfTestReport:FireServer({
		Stage = "Done",
		ScheduleHash = scheduleHash(slots),
		DealHash = table.concat(dealKeys, ","),
		Panels = panelLines,
		FailedSounds = failedSounds,
		ClientErrors = errors,
	})
	running = false
end

function SelfTestController.Init()
	if not RunService:IsStudio() then
		return
	end
	RemoteEvents.SelfTest.OnClientEvent:Connect(function(payload: any)
		task.spawn(run, payload)
	end)
end

return SelfTestController
