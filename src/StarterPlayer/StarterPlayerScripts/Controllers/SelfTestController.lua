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
	     counts the panels' own instances (every modal ScreenGui): a second
	     open/close cycle must not add any (leftovers = a leak).
	  4. Loads every SoundConfig slot (SoundKit.CheckAll).
	  5. Checks every UIKit.Modal draws over the HUD (DisplayOrder +
	     backdrop) and that every shop chip lands its section's header
	     within 2 px of the top at both scales.

	Then it sends SelfTestReport with the results and any client errors
	seen in Output meanwhile. Never fires a remote with a VALID request:
	no no-argument remote (ClaimDaily, RequestRebirth, ...) is fuzzed,
	since any call to those is a real action.
]]
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
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
		-- Never the current slot: 0, a wrong slot, junk types.
		MarkDealPopup = { {}, { "x" }, { { Slot = "1" } }, { { Slot = 1 } }, { { Slot = 1.5 } } },
		-- Never a real hit: unknown / junk weapons, junk targets and vectors.
		RequestHit = {
			{},
			{ "x" },
			{ { Weapon = "Nope" } },
			{ { Weapon = 5 } },
			{ { Weapon = "Bat", TargetUserId = "x" } },
			{ { Weapon = "LaserGun", Direction = "x" } },
			{ { Weapon = "LaserGun", Direction = Vector3.new(NAN, 0, 0) } },
			{ { Weapon = "FreezeRay", Direction = Vector3.new(INF, 0, 0) } },
			{ { Weapon = "BananaPeel", Origin = Vector3.new(1e9, 0, 0) } },
		},
		-- Never a real step: 0, out of range, fractions, junk, a non-true Replay.
		TutorialAdvance = { {}, { "x" }, { { Step = 0 } }, { { Step = 99 } }, { { Step = 1.5 } }, { { Step = "1" } }, { { Replay = "yes" } } },
		-- A non-admin tester: the SUSPICIOUS warn and nothing changes (the
		-- fingerprint check); an admin tester: junk ids are rejected.
		AdminAction = {
			{},
			{ { Action = "Nope" } },
			{ { Action = "StartEvent", Args = { Id = "Nope" } } },
			{ { Action = "RestartTutorial", Args = { UserId = otherUserId } } },
			{ { Action = "ResetPlayer", Args = { UserId = otherUserId } } },
			{ { Action = "ResetPlayer", Args = { UserId = 0 / 0 } } },
			{ { Action = "ResetPlayer", Args = { UserId = "x" } } },
			{ { Action = "ResetPlayer" } },
		},
		-- Never a real quest or power-up: junk ids / keys and types.
		ClaimQuest = { {}, { "x" }, { { Id = 5 } }, { { Id = "nope" } }, { { Id = BIG_STRING } }, { { Id = { "chain" } } } },
		UsePowerUp = { {}, { "x" }, { { Key = 5 } }, { { Key = "Nope" } }, { { Key = BIG_STRING } }, { { Key = { "CashBurst" } } } },
	}
	for _, n in junkNumbers do
		table.insert(cases.RequestSteal, { { OwnerUserId = n, PedestalIndex = n } })
		table.insert(cases.ClaimGift, { { Index = n } })
		table.insert(cases.ClaimQuest, { { Id = n } })
		table.insert(cases.UsePowerUp, { { Key = n } })
		table.insert(cases.MarkDealPopup, { { Slot = n } })
		table.insert(cases.RequestHit, { { Weapon = "Bat", TargetUserId = n } })
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
		RemoteEvents.RequestSteal:FireServer({ OwnerUserId = otherUserId, PedestalIndex = 99 })
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

-- Instances in the panels' own subtrees: every UIKit.Modal's ScreenGui
-- (each panel is one) plus how many modal guis exist (a panel that made a
-- new one per open would leak). Not the whole PlayerGui: the HUD's deal
-- countdown, timed pills, toasts and event chips churn on their own and
-- swung the old whole-PlayerGui count by ±3 between cycles.
--[[ Cards centred --------------------------------------------------------
	Every modal and centred card: what you see (panel + shadow) centred in
	the band between GetCardTop and GetCardBottom, inside it, or starting at
	its top when taller (UIKit.CheckCardPlacement). The viewport can't be
	forced, so the three target screens run the REAL plan functions
	(PlanModalFor / PlanCardFor, the ones placeRoot / FitHeight call); the
	live cards are measured from AbsolutePosition / AbsoluteSize at this
	window's size. ]]
local CARD_VIEWPORTS = {
	{ Name = "1920x1080", Size = Vector2.new(1920, 1080), Phone = false },
	{ Name = "1366x768", Size = Vector2.new(1366, 768), Phone = false },
	{ Name = "844x390 phone", Size = Vector2.new(844, 390), Phone = true },
}
-- Holder heights of the fixed-size centred cards (result cards, the
-- celebration, the event info card), a spread from short to taller than
-- any band.
local CARD_HEIGHTS = { 260, 340, 420, 520, 600, 700, 900 }
local cardLines: { string } = {}

local function cardFailures(label: string, failures: { string }): string
	return ("FAIL cards centred (%s): %s"):format(label, table.concat(failures, "; "))
end

-- A fake successful single fusion (Common x2 -> Rare), as FusionResolved
-- would carry it.
local function fakeFusionResult(): any
	local def = ItemConfig.GetItemsByTier("Rare")[1]
	return {
		Success = true,
		Upgraded = true,
		Count = 2,
		ConsumedTier = "Common",
		NewItem = { Uid = "selftest-fusion", ItemId = if def then def.Id else "", Tier = "Rare" },
	}
end

-- Every successful single fusion opens the big card whatever the reveal rule
-- says, with no top banner; Fuse All / Auto-Fuse keep the rule.
local function testFusionCard(): { string }
	local ResultController = require(script.Parent.ResultController) :: any
	local SettingsConfig = require(ReplicatedStorage.Shared.Config.SettingsConfig) :: any
	local TycoonController = require(script.Parent.TycoonController) :: any
	local lines: { string } = {}
	local ok, err = pcall(function()
		ResultController.CloseCards()
		local fake = fakeFusionResult()
		ResultController.SelfTestFusionResolved(fake)
		local started = os.clock()
		while not ResultController.IsBigCardOpen() and os.clock() - started < 2 do
			task.wait(0.1)
		end
		local headline = ResultController.GetBigCardHeadline()
		table.insert(lines, ("%s single fusion: the big card opens with RARE ORB! (got %s)"):format(if headline == "RARE ORB!" then "PASS" else "FAIL", tostring(headline)))
		table.insert(lines, ("%s single fusion: no top banner (FusionBannerShows)"):format(if ResultController.FusionBannerShows(fake) == false then "PASS" else "FAIL"))
		ResultController.CloseCards()
		-- Fuse All / Auto-Fuse: still the player's reveal rule.
		local rule = TycoonController.GetRevealRule()
		local follows = true
		for _, tier in { "Common", "Rare", "Epic", "Legendary", "Mythic" } do
			if ResultController.ShowsBigCardFor(tier, nil) ~= SettingsConfig.ShowsBigCard(tier, nil, rule) then
				follows = false
			end
		end
		table.insert(lines, ("%s Fuse All / Auto-Fuse follow the reveal rule"):format(if follows then "PASS" else "FAIL"))
	end)
	if not ok then
		table.insert(lines, "FAIL single fusion big card: " .. tostring(err))
	end
	return lines
end

local function testCardMath(): { string }
	local lines: { string } = {}
	local margin = UIKit.MODAL_MARGIN
	for _, viewport in CARD_VIEWPORTS do
		local scale = if viewport.Phone then UITheme.PhoneScale else 1
		local view = viewport.Size / scale
		local failures: { string } = {}
		local checked = 0
		for _, spec in UIKit.GetModalSpecs() do
			local plan = UIKit.PlanModalFor(spec.MaxSize, spec.FitContent, view, viewport.Phone)
			-- The panel + shadow sits MODAL_MARGIN inside the root all round.
			local top = plan.Top + margin * plan.Fit
			local height = plan.Visual - 2 * margin * plan.Fit
			local why = UIKit.CheckCardPlacement(top, height, view.Y, viewport.Phone)
			checked += 1
			if why then
				table.insert(failures, ("%s %s"):format(spec.Name, why))
			end
		end
		for _, height in CARD_HEIGHTS do
			local visual = height + UITheme.ShadowOffset
			local top, fit = UIKit.PlanCardFor(visual, view.Y, viewport.Phone)
			local why = UIKit.CheckCardPlacement(top, visual * fit, view.Y, viewport.Phone)
			checked += 1
			if why then
				table.insert(failures, ("card %d px %s"):format(height, why))
			end
		end
		if #failures > 0 then
			table.insert(lines, cardFailures(viewport.Name, failures))
		else
			table.insert(lines, ("PASS cards centred (%s, %d cards)"):format(viewport.Name, checked))
		end
	end
	return lines
end

-- Logical px of `gui`'s visible rect: itself plus a "Shadow" sibling or
-- child below it.
-- AbsolutePosition is reported below the Roblox top-bar inset even in
-- IgnoreGuiInset guis, so the inset is added back before converting.
local function visibleRect(gui: GuiObject, shadow: GuiObject?, screenScale: number): (number, number)
	local inset = GuiService:GetGuiInset().Y
	local top = gui.AbsolutePosition.Y + inset
	local bottom = top + gui.AbsoluteSize.Y
	if shadow and shadow.Visible then
		bottom = math.max(bottom, shadow.AbsolutePosition.Y + inset + shadow.AbsoluteSize.Y)
	end
	return top / screenScale, (bottom - top) / screenScale
end

local function screenScale(gui: Instance): number
	local screen = gui:FindFirstAncestorWhichIsA("ScreenGui")
	local mobile = screen and screen:FindFirstChild("MobileScale")
	return if mobile and mobile:IsA("UIScale") then mobile.Scale else 1
end

-- Every open modal's panel (+ shadow), measured at this window's size.
local function measureOpenModals(label: string)
	local view = UIKit.GetLogicalViewport()
	for _, gui in UIKit.GetModalGuis() do
		local root = if gui.Enabled then gui:FindFirstChild("Root") else nil
		local panel = root and root:FindFirstChild("Panel")
		local body = panel and panel:FindFirstChild("Body")
		if panel and body and body:IsA("GuiObject") then
			local shadow = panel:FindFirstChild("Shadow") :: GuiObject?
			local top, height = visibleRect(body, shadow, screenScale(body))
			local why = UIKit.CheckCardPlacement(top, height, view.Y, UIKit.IsPhone())
			table.insert(
				cardLines,
				if why
					then cardFailures(("%s, %s live"):format(gui.Name, label), { why })
					else ("PASS cards centred (%s, %s live, top %d)"):format(gui.Name, label, math.floor(top))
			)
		end
	end
end

-- Every visible card UIKit.FitHeight placed (result cards, the event info
-- card), measured at this window's size.
local function measurePlacedCards(label: string): number
	local view = UIKit.GetLogicalViewport()
	local found = 0
	-- Let the card's layout settle first (AbsoluteSize changes land a frame
	-- late and the card re-places itself on the next one).
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	for _, gui in localPlayer:WaitForChild("PlayerGui"):GetDescendants() do
		if gui:IsA("GuiObject") and gui:GetAttribute("CardPlaced") == true and gui.Visible then
			local screen = gui:FindFirstAncestorWhichIsA("ScreenGui")
			if screen and screen.Enabled then
				found += 1
				local shadow = gui:FindFirstChild("Shadow") :: GuiObject?
				local top, height = visibleRect(gui, shadow, screenScale(gui))
				local why = UIKit.CheckCardPlacement(top, height, view.Y, UIKit.IsPhone())
				table.insert(
					cardLines,
					if why
						then cardFailures(("%s, %s live"):format(gui.Name, label), { why })
						else ("PASS cards centred (%s, %s live, top %d)"):format(gui.Name, label, math.floor(top))
				)
			end
		end
	end
	return found
end

local function testPlacedCards(): { string }
	local result = require(script.Parent.ResultController) :: any
	local eventInfo = require(UI.EventInfoCard) :: any
	local common = ItemConfig.GetItemsByTier("Common")[1]
	for _, phone in { false, true } do
		UIKit.SetForcedPhone(phone)
		task.wait(0.2)
		local label = if phone then "phone" else "desktop"
		local ok, err = pcall(function()
			if common then
				result.ShowItemCard("Self test", { Uid = "selftest", ItemId = common.Id, Tier = "Common" }, "Self test")
				task.wait(0.4)
				measurePlacedCards(label)
				result.CloseCards()
				task.wait(0.3)
			end
			local hud = localPlayer:WaitForChild("PlayerGui"):FindFirstChild("Hud")
			if hud then
				eventInfo.Show(hud, "GoldenRain", false)
				task.wait(0.4)
				measurePlacedCards(label)
				eventInfo.Hide()
			end
		end)
		if not ok then
			table.insert(cardLines, "FAIL cards centred (live cards): " .. tostring(err))
		end
	end
	UIKit.SetForcedPhone(nil)
	return {}
end

--[[ Hovering things stay home -------------------------------------------
	Every FT_Hover target sits within its bob of its HoverBase, and (except
	event objects on the street) inside one of the 12 plot slots; every
	FT_Orbit model's balls stay round their orb. Run before the fuzz and
	again after the server rebuilt the pedestal orbs. ]]
local HOVER_SETTLE_SECONDS = 10
local startedAt = os.clock()

local function insideAnySlot(position: Vector3): boolean
	for index = 1, PlotLayout.MAX_PLOT_SLOTS do
		if PlotLayout.IsInsidePlot(PlotLayout.GetSlotCFrame(index):PointToObjectSpace(position)) then
			return true
		end
	end
	return false
end

local function testHover(label: string): { string }
	local wait = HOVER_SETTLE_SECONDS - (os.clock() - startedAt)
	if wait > 0 then
		task.wait(wait)
	end
	local eventObjects = workspace:FindFirstChild("EventObjects")
	local bad: { string } = {}
	local checked = 0
	for _, target in CollectionService:GetTagged(PartKit.HOVER_TAG) do
		local pose = target:IsDescendantOf(workspace) and PartKit.GetRestPose(target)
		if pose then
			checked += 1
			local position = pose.Position
			local base = target:GetAttribute(PartKit.HOVER_BASE_ATTRIBUTE)
			local bob = (target:GetAttribute("BobStuds") :: number?) or 0
			local onStreet = eventObjects ~= nil and target:IsDescendantOf(eventObjects)
			if typeof(base) ~= "CFrame" then
				table.insert(bad, target:GetFullName() .. " has no HoverBase")
			elseif (position - base.Position).Magnitude > math.abs(bob) + 1 then
				table.insert(bad, ("%s %.0f studs from rest"):format(target:GetFullName(), (position - base.Position).Magnitude))
			elseif not onStreet and not insideAnySlot(position) then
				table.insert(bad, ("%s outside every plot at %s"):format(target:GetFullName(), tostring(position)))
			end
		end
	end
	for _, model in CollectionService:GetTagged(PartKit.ORBIT_TAG) do
		local group = model.Parent
		local center = group and group:IsA("Model") and group.PrimaryPart
		local radius = (model:GetAttribute("Radius") :: number?) or 1
		if center then
			for _, ball in model:GetChildren() do
				if ball:IsA("BasePart") then
					checked += 1
					if (ball.Position - center.Position).Magnitude > radius + 1 then
						table.insert(bad, ball:GetFullName() .. " left its orb")
					end
				end
			end
		end
	end
	if #bad > 0 then
		return { ("FAIL hovering things stay home (%s): %s"):format(label, table.concat(bad, "; ")) }
	end
	return { ("PASS hovering things stay home (%s, %d checked)"):format(label, checked) }
end

-- Every visible, non-empty TextLabel / TextButton in the open modals must
-- report TextFits (nothing cut off), at this scale.
local textFitLines: { string } = {}

local function shownOnScreen(gui: GuiObject, root: Instance): boolean
	local current: Instance? = gui
	while current and current ~= root do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return gui.AbsoluteSize.X > 0 and gui.AbsoluteSize.Y > 0
end

local function checkTextFits(panelName: string, label: string)
	local bad: { string } = {}
	local checked = 0
	for _, gui in UIKit.GetModalGuis() do
		if gui.Enabled then
			for _, text in gui:GetDescendants() do
				if (text:IsA("TextLabel") or text:IsA("TextButton")) and text.Text ~= "" and shownOnScreen(text, gui) then
					checked += 1
					if not text.TextFits then
						table.insert(bad, ("%s %q"):format(text:GetFullName(), text.Text:sub(1, 40)))
					end
				end
			end
		end
	end
	table.insert(
		textFitLines,
		if #bad > 0
			then ("FAIL text fits (%s, %s): %s"):format(panelName, label, table.concat(bad, "; "))
			else ("PASS text fits (%s, %s, %d labels)"):format(panelName, label, checked)
	)
end

local function countGui(): number
	local guis = UIKit.GetModalGuis()
	local count = #guis
	for _, gui in guis do
		count += #gui:GetDescendants()
	end
	return count
end

-- Opens / closes each panel twice per scale; the panels' instance count
-- after the second close must equal the count after the first (the first
-- may build the panel once, which is expected).
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
					if cycle == 1 then
						measureOpenModals(if phone then "phone" else "desktop")
						checkTextFits(spec.Name, if phone then "phone" else "desktop")
					end
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

-- TopStack: the slots stack top to bottom without overlap, the queue is
-- capped at 4 (the oldest lowest-priority item goes), a priority item jumps
-- the line, and the welcome splash waits for the line to empty.
local function testTopStack(): { string }
	local TopStack = require(UI.TopStack) :: any
	local lines: { string } = {}
	local done = false
	TopStack.WhenIdle(function()
		done = true
	end)
	local started = os.clock()
	while not done and os.clock() - started < 15 do
		task.wait(0.1)
	end
	if not done then
		return { "FAIL top stack: the announcement line never emptied" }
	end

	-- The slots rise strictly top to bottom, at both layouts: the same plan
	-- the stack uses, with every slot occupied (a 89 px bar, the 44 px chip,
	-- a 64 px line), the objective bar clear of the Roblox top bar and the
	-- last slot inside the screen. (The live Ys alone cannot be compared:
	-- an EMPTY objective slot has no bar to order, and the chip then keeps
	-- its place beside the top bar at y 12, which is below nothing.)
	for _, phone in { false, true } do
		local cardTop = UIKit.GetCardTopFor(phone)
		local plan = TopStack.PlanFor(cardTop, 89, 44, 64)
		local view = (if phone then Vector2.new(844, 390) else Vector2.new(1920, 1080)) / (if phone then UITheme.PhoneScale else 1)
		local strict = plan.Objective < plan.Chip and plan.Chip < plan.Announce and plan.Announce < plan.Status
		local clear = plan.Objective >= cardTop and cardTop >= UIKit.TOP_BAR_HEIGHT + UIKit.CARD_TOP_GAP
		local inside = plan.Status + 64 <= view.Y
		local label = if phone then "phone" else "desktop"
		table.insert(lines, if strict and clear and inside
			then ("PASS top stack slots in order (%s: %d / %d / %d / %d)"):format(label, plan.Objective, plan.Chip, plan.Announce, plan.Status)
			else ("FAIL top stack slots out of order (%s: %d / %d / %d / %d, bar top %d, view %d)"):format(label, plan.Objective, plan.Chip, plan.Announce, plan.Status, cardTop, view.Y))
	end
	-- The live slots: the ones in use rise strictly and sit inside the screen.
	local view = UIKit.GetLogicalViewport()
	local used: { { Name: string, Y: number, Height: number } } = {}
	for _, slot in { "Objective", "Chip", "Announce" } do
		local height = TopStack.GetHeight(slot)
		if height > 0 then
			table.insert(used, { Name = slot, Y = TopStack.GetY(slot), Height = height })
		end
	end
	local liveOk = true
	local liveText: { string } = {}
	for index, entry in used do
		table.insert(liveText, ("%s %d+%d"):format(entry.Name, entry.Y, entry.Height))
		if entry.Y < 0 or entry.Y + entry.Height > view.Y or (index > 1 and entry.Y <= used[index - 1].Y) then
			liveOk = false
		end
		if entry.Name == "Objective" and entry.Y < UIKit.GetCardTop() then
			liveOk = false
		end
	end
	table.insert(lines, if liveOk
		then ("PASS top stack live slots in order and on screen (%s)"):format(table.concat(liveText, ", "))
		else ("FAIL top stack live slots (%s)"):format(table.concat(liveText, ", ")))

	-- The heist's gate sign and lock are world billboards: closer than
	-- GateSignMinDistance they must stop growing (a 160 px bar and a 230 px
	-- disc once filled the screen), and at that distance stay under 80 px.
	local plotsFolder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	local gateChecked, gateBad = 0, {}
	if plotsFolder then
		local camera = Workspace.CurrentCamera
		local fov = if camera then math.rad(camera.FieldOfView) else math.rad(70)
		local pixelsPerStud = 1080 / (2 * PlotLayout.ShieldFence.GateSignMinDistance * math.tan(fov / 2))
		for _, gui in plotsFolder:GetDescendants() do
			if gui:IsA("BillboardGui") and (gui.Name == "GateSign" or gui.Name == "ShieldLockIcon") then
				gateChecked += 1
				local tall = gui.Size.Y.Scale * pixelsPerStud
				if gui.DistanceLowerLimit < PlotLayout.ShieldFence.GateSignMinDistance - 0.01 or tall > 80 then
					table.insert(gateBad, ("%s limit %.0f, %.0f px"):format(gui:GetFullName(), gui.DistanceLowerLimit, tall))
				end
			end
		end
	end
	table.insert(lines, if #gateBad == 0
		then ("PASS gate sign and lock stop growing up close (%d billboards)"):format(gateChecked)
		else "FAIL gate sign / lock billboards: " .. table.concat(gateBad, "; "))

	local shown: { string } = {}
	local function item(name: string, priority: number?)
		TopStack.Announce({
			Priority = priority,
			Seconds = 0.05,
			Height = 0,
			Show = function()
				table.insert(shown, name)
			end,
			Hide = function()
				return nil
			end,
		})
	end
	for _, name in { "A", "B", "C", "D", "E", "F" } do
		item(name)
	end
	local queued = TopStack.GetQueueLength()
	item("P", 1)
	done = false
	TopStack.WhenIdle(function()
		done = true
	end)
	started = os.clock()
	while not done and os.clock() - started < 5 do
		task.wait(0.1)
	end
	local order = table.concat(shown, "")
	table.insert(lines, if queued == TopStack.MAX_QUEUED and order == "APDEF"
		then "PASS top stack queue (capped at 4, A already showing, priority P next, oldest dropped)"
		else ("FAIL top stack queue: queued %d, shown order %s (want 4, APDEF)"):format(queued, order))
	return lines
end

-- On the phone layout, every HUD element of the left group stays inside
-- the left 40% of the screen (deal badge, timed pills included); at both
-- layouts the column's rects (goal card, quest tracker, cash card, SHOP /
-- QUESTS / LOCK rows, deal badge) never overlap.
local function testHudLeftColumn(): { string }
	local hud = require(script.Parent.HudController) :: any
	local lines: { string } = {}
	for _, phone in { true, false } do
		UIKit.SetForcedPhone(phone)
		task.wait(0.2)
		local ok, result = pcall(hud.SelfTestLeftColumn, if phone then "phone" else "desktop")
		if not ok then
			table.insert(lines, "FAIL hud left column: " .. tostring(result))
		else
			for _, line in result do
				table.insert(lines, line)
			end
		end
	end
	UIKit.SetForcedPhone(nil)
	return lines
end

--[[ Tutorial probes ---------------------------------------------------------------------
	The server drives the tutorial step by step (DebugService) and asks, per
	step, what this client really shows: the banner (the step's own text, at
	most 6 words), no card of any kind before the claim, exactly the HUD
	elements of the table (TutorialConfig.HudReveal), the weapon bar off at
	Rebirth 0. And after a single pull: the big "COMMON ORB!" card.
]]

type ProbeLine = { Ok: boolean, Name: string, Detail: string? }

local TIMED_REVEAL_WAIT = 3 -- the last step's pop-ins are staggered up to 1.5 s

local PRESENT_WAIT = 30

-- A dim backdrop must have a card with it: asks UIKit which modals dim the
-- screen without a card on screen (a moment later, since a card that just
-- closed is still fading).
local function dimLine(label: string): ProbeLine
	local bad = UIKit.GetDimProblems()
	if #bad > 0 then
		task.wait(0.25)
		bad = UIKit.GetDimProblems()
	end
	return {
		Ok = #bad == 0,
		Name = ("tutorial %s: no dim backdrop without a card on screen"):format(label),
		Detail = table.concat(bad, ", "),
	}
end

local function probeStep(stepIndex: number, stepId: string): { ProbeLine }
	local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
	local TutorialController = require(script.Parent.TutorialController) :: any
	local TutorialCards = require(UI.TutorialCards) :: any
	local TutorialBanner = require(UI.TutorialBanner) :: any
	local HudGate = require(UI.HudGate) :: any
	local lines: { ProbeLine } = {}
	local step = TutorialConfig.GetStep(stepIndex)
	local started = os.clock()
	local function presented(): boolean
		local current = TutorialController.GetPresentedStep()
		return current ~= nil and current.Id == stepId
	end
	-- The presenter plays one step at a time (the previous step's minimum
	-- banner time, "✓ Nice!", the pause, then this card): give it time.
	while not presented() and os.clock() - started < PRESENT_WAIT do
		task.wait(0.1)
	end
	if not presented() or not step then
		return { { Ok = false, Name = ("tutorial %s: its banner shows"):format(stepId), Detail = "never presented" } }
	end
	local TutorialExplain = require(UI.TutorialExplain) :: any
	local TutorialHand = require(UI.TutorialHand) :: any
	-- The explain card: a step that introduces something opens it first
	-- (title, >= 22 px text, an OK); OK hands over to the banner (or ends
	-- the step). The claim has none.
	local cardOpen = TutorialCards.IsOpen() or TutorialExplain.IsOpen()
	if step.Card then
		local waited = os.clock()
		while not TutorialExplain.IsOpen() and os.clock() - waited < 10 do
			task.wait(0.1)
		end
		local body = TutorialExplain.GetBody()
		table.insert(lines, {
			Ok = TutorialExplain.IsOpen() and body ~= nil and body.TextSize >= 22 and body.Text == step.Card.Body,
			Name = ("tutorial %s: its explain card opens first (text >= 22 px)"):format(stepId),
			Detail = if body then ("%d px"):format(body.TextSize) else "no card",
		})
		-- Read time: OK is off at first (✕ and a tap outside too), on after 1.5 s.
		task.wait(0.4)
		local lockedEarly = not TutorialExplain.IsOkReady()
		table.insert(lines, dimLine(stepId .. " (card up)"))
		task.wait(TutorialConfig.CardReadSeconds)
		table.insert(lines, {
			Ok = lockedEarly and TutorialExplain.IsOkReady(),
			Name = ("tutorial %s: the card's OK turns on after %.1f s"):format(stepId, TutorialConfig.CardReadSeconds),
			Detail = ("off at 0.4 s: %s, on at %.1f s: %s"):format(tostring(lockedEarly), 0.4 + TutorialConfig.CardReadSeconds, tostring(TutorialExplain.IsOkReady())),
		})
		TutorialExplain.PressOk()
		task.wait(0.2)
		table.insert(lines, dimLine(stepId .. " (after OK)"))
		local banner = TutorialBanner.IsShown()
		table.insert(lines, {
			Ok = step.CardEnds == true or banner,
			Name = ("tutorial %s: the banner takes over after OK"):format(stepId),
		})
		if step.CardEnds then
			return lines
		end
	else
		table.insert(lines, { Ok = not cardOpen, Name = ("tutorial %s: no card"):format(stepId) })
	end
	if stepId == "claim" then
		local UIKit = require(UI.UIKit) :: any
		local anyCard = cardOpen or UIKit.IsOverlayOpen() or TutorialBanner.IsSplashShown()
		table.insert(lines, { Ok = not anyCard, Name = "tutorial: no card shows before the claim" })
	end
	task.wait(0.5) -- the slide-in
	table.insert(lines, dimLine(stepId))
	-- The objective bar sits fully on screen, under the Roblox top bar.
	if TutorialBanner.IsShown() then
		local barBody = TutorialBanner.GetFrame()
		local barView = UIKit.GetLogicalViewport()
		local barTop, barHeight = visibleRect(barBody, nil, screenScale(barBody))
		local barLeft = barBody.AbsolutePosition.X / screenScale(barBody)
		local barRight = barLeft + barBody.AbsoluteSize.X / screenScale(barBody)
		table.insert(lines, {
			Ok = barTop >= UIKit.GetCardTop() - 1 and barTop + barHeight <= barView.Y and barLeft >= 0 and barRight <= barView.X + 1,
			Name = ("tutorial %s: the objective bar is fully on screen below the top bar"):format(stepId),
			Detail = ("top %.0f (min %d), bottom %.0f of %.0f, x %.0f-%.0f of %.0f"):format(barTop, UIKit.GetCardTop(), barTop + barHeight, barView.Y, barLeft, barRight, barView.X),
		})
	end
	local text = TutorialBanner.GetBaseText()
	local words = #text:split(" ")
	table.insert(lines, {
		Ok = text == step.Banner and words <= 6,
		Name = ("tutorial %s: the banner reads its instruction in 6 words or fewer"):format(stepId),
		Detail = ("%q (%d words)"):format(text, words),
	})
	-- The objective bar: 36 px text (28 on a phone), a lime border, 520-640 wide.
	local objectiveBar = TutorialBanner.GetFrame()
	local label = TutorialBanner.GetTextLabel()
	local UIKitForBar = require(UI.UIKit) :: any
	local phone = UIKitForBar.IsPhone()
	local widthOk = if phone then true else (objectiveBar.AbsoluteSize.X / UIKitForBar.EffectiveScale(objectiveBar) >= 520 and objectiveBar.AbsoluteSize.X / UIKitForBar.EffectiveScale(objectiveBar) <= 640)
	table.insert(lines, {
		Ok = widthOk and label.TextSize == (if phone then 28 else 36) and TutorialBanner.GetStepText() == ("%d / %d"):format(stepIndex, #TutorialConfig.Steps),
		Name = ("tutorial %s: the objective bar (width, text size, step counter)"):format(stepId),
		Detail = ("%.0f px wide, text %d, %s"):format(objectiveBar.AbsoluteSize.X, label.TextSize, TutorialBanner.GetStepText()),
	})
	-- The hand: it never overlaps the button it points at, and its
	-- fingertip is within 12 px of the button's top-centre (above it) or
	-- bottom-centre (a button too near the top of the screen gets the hand
	-- below it). The Fuse panel's buttons and the contextual button are
	-- closed / out of reach in this drive.
	if step.Hand then
		local until_ = os.clock() + 3
		local tip = TutorialHand.GetTip()
		while tip == nil and os.clock() < until_ do
			task.wait(0.1)
			tip = TutorialHand.GetTip()
		end
		local target = TutorialHand.GetTarget()
		local rect = TutorialHand.GetRect()
		local clear, tipOk = false, false
		local detail = "no hand"
		if tip and target and rect then
			local p, sz = target.AbsolutePosition, target.AbsoluteSize
			local overlapX = rect.Position.X < p.X + sz.X and rect.Position.X + rect.Size.X > p.X
			local overlapY = rect.Position.Y < p.Y + sz.Y and rect.Position.Y + rect.Size.Y > p.Y
			clear = not (overlapX and overlapY)
			local edgeY = if tip.Y <= p.Y + sz.Y / 2 then p.Y else p.Y + sz.Y
			local distance = (tip - Vector2.new(p.X + sz.X / 2, edgeY)).Magnitude
			tipOk = distance <= 12
			detail = ("tip %.0f,%.0f (%.1f px from the edge centre) hand %.0f,%.0f target %.0f,%.0f %.0fx%.0f"):format(tip.X, tip.Y, distance, rect.Position.X, rect.Position.Y, p.X, p.Y, sz.X, sz.Y)
		end
		table.insert(lines, {
			Ok = clear,
			Name = ("tutorial %s: the hand does not cover its target"):format(stepId),
			Detail = detail,
		})
		table.insert(lines, {
			Ok = tipOk,
			Name = ("tutorial %s: the hand's tip is within 12 px of its target's edge"):format(stepId),
			Detail = detail,
		})
	end
	-- The HUD set: each key shown exactly from the step that introduces it
	-- (the staggered ones get their time).
	local deadline = os.clock() + TIMED_REVEAL_WAIT
	local mismatches: { string } = {}
	repeat
		table.clear(mismatches)
		for _, key in TutorialConfig.HudKeys do
			local at = TutorialConfig.IndexOf(TutorialConfig.HudReveal[key])
			local expected = at ~= nil and stepIndex >= at
			if HudGate.IsShown(key) ~= expected or HudGate.IsVisible(key) ~= expected then
				table.insert(mismatches, ("%s want %s"):format(key, tostring(expected)))
			end
		end
		if #mismatches > 0 then
			task.wait(0.15)
		end
	until #mismatches == 0 or os.clock() > deadline
	table.insert(lines, {
		Ok = #mismatches == 0,
		Name = ("tutorial %s: the HUD shows exactly its set"):format(stepId),
		Detail = table.concat(mismatches, ", "),
	})
	-- The weapon bar: nothing at Rebirth 0 (no greyed R1 / R2 / R3).
	local rebirths = require(script.Parent.TycoonController).GetRebirths()
	local bar = localPlayer:WaitForChild("PlayerGui"):FindFirstChild("WeaponBar")
	if rebirths == 0 and bar and bar:IsA("ScreenGui") then
		table.insert(lines, { Ok = not bar.Enabled, Name = "tutorial: no weapon bar before Rebirth 1" })
	end
	return lines
end

local function probeBigCard(expect: string, fakeFusion: boolean?): { ProbeLine }
	local ResultController = require(script.Parent.ResultController) :: any
	if fakeFusion then
		ResultController.SelfTestFusionResolved(fakeFusionResult())
	end
	local started = os.clock()
	while not ResultController.IsBigCardOpen() and os.clock() - started < 3 do
		task.wait(0.1)
	end
	local headline = ResultController.GetBigCardHeadline()
	return {
		{
			Ok = ResultController.IsBigCardOpen() and headline == expect,
			Name = if fakeFusion then "a single fusion (Common x2 -> Rare) opens the big card" else "a single pull of a Common opens the big card",
			Detail = ("headline %s"):format(tostring(headline)),
		},
	}
end

-- The rest pose, sampled on request (the server unequips everything, waits
-- 0.3 s, then asks): the hand in UpperTorso space and the three joint values.
local restHand: Vector3? = nil
local restJoints: { CFrame? } = {}

local function missingRig(character: Model?): boolean
	return character == nil or character:FindFirstChild("RightHand") == nil or character:FindFirstChild("UpperTorso") == nil
end

local function probeSampleRest(): { ProbeLine }
	local WeaponPose = require(script.Parent.Parent.Effects.WeaponPose) :: any
	local character = localPlayer.Character
	if missingRig(character) then
		restHand = nil
		return {}
	end
	RunService.Heartbeat:Wait()
	restHand = WeaponPose.GetHandOffset(character)
	restJoints = WeaponPose.GetJointValues(character)
	return {}
end

-- The held check: the hand is DRAWN away from its rest pose (RightHand in
-- UpperTorso space, sampled on Heartbeat; never the joint values we wrote).
-- Returns the hand's held position.
local function probeHeld(lines: { ProbeLine }, character: Model, weapon: CombatConfig.Weapon, label: string): Vector3
	local WeaponPose = require(script.Parent.Parent.Effects.WeaponPose) :: any
	local rest = restHand :: Vector3
	task.wait(0.35) -- the 0.15 s raise
	RunService.Heartbeat:Wait()
	local held = WeaponPose.GetHandOffset(character) :: Vector3
	local holding = WeaponPose.GetHeldWeapon(character) == weapon.Id
	if weapon.Kind == "Ranged" or weapon.Kind == "Freeze" then
		-- Aimed: the hand is up around shoulder height.
		local torso = character:FindFirstChild("UpperTorso") :: BasePart?
		local shoulderY = if torso then torso.Size.Y / 2 - 0.3 else 0.7
		table.insert(lines, {
			Ok = holding and math.abs(held.Y - shoulderY) <= 0.8 and held.Z < -0.8,
			Name = ("combat %s: the hand is raised to about shoulder height while aiming"):format(label),
			Detail = ("hand y %.2f (shoulder %.2f), z %.2f"):format(held.Y, shoulderY, held.Z),
		})
	else
		local forward = rest.Z - held.Z -- torso space: forward is -Z
		table.insert(lines, {
			Ok = holding and (held - rest).Magnitude >= 1 and forward >= 0.5,
			Name = ("combat %s: the hand is drawn at least 1 stud away from its rest pose while held"):format(label),
			Detail = ("moved %.2f studs, %.2f forward, pose %s"):format((held - rest).Magnitude, forward, tostring(WeaponPose.GetHeldWeapon(character))),
		})
	end
	return held
end

-- A weapon the server just equipped on this character. Everything is read
-- from where the RIGHT HAND is DRAWN, never from the joint values we wrote.
local function probeWeapon(weaponId: string): { ProbeLine }
	local lines: { ProbeLine } = {}
	local CombatController = require(script.Parent.CombatController) :: any
	local WeaponPose = require(script.Parent.Parent.Effects.WeaponPose) :: any
	local character = localPlayer.Character
	if missingRig(character) then
		table.insert(lines, { Ok = true, Name = ("combat %s: the arm pose (skipped: no RightHand / UpperTorso, not an R15 rig)"):format(weaponId) })
		return lines
	end
	local char = character :: Model
	if not restHand then
		table.insert(lines, { Ok = false, Name = ("combat %s: the arm pose"):format(weaponId), Detail = "no rest-pose sample" })
		return lines
	end
	local weapon = CombatConfig.GetWeapon(weaponId) :: CombatConfig.Weapon
	local started = os.clock()
	while WeaponPose.GetHeldWeapon(char) ~= weaponId and os.clock() - started < 2 do
		task.wait(0.05)
	end
	local held = probeHeld(lines, char, weapon, weaponId)
	local tool = char:FindFirstChildOfClass("Tool")
	if tool and weapon.Kind == "Melee" then
		local clearance = WeaponPose.GetToolClearance(char, tool) or 0
		table.insert(lines, {
			Ok = clearance >= 1.5,
			Name = ("combat %s: the held weapon reaches 1.5 studs clear of the torso"):format(weaponId),
			Detail = ("%.2f studs"):format(clearance),
		})
	end

	local played = CombatController.PlayPose(weaponId)
	local peak, travelled, visible = 0, 0, 0
	local last = held
	local sampled = os.clock()
	local lastFrame = sampled
	while os.clock() - sampled < 1 do
		RunService.Heartbeat:Wait()
		local now = WeaponPose.GetHandOffset(char)
		local clock = os.clock()
		if now then
			peak = math.max(peak, (now - held).Magnitude)
			travelled += (now - last).Magnitude
			if (now - held).Magnitude >= 0.3 then
				visible += clock - lastFrame
			end
			last = now
		end
		lastFrame = clock
	end
	if weapon.Kind == "Melee" then
		table.insert(lines, {
			Ok = played and peak >= 2.5,
			Name = ("combat %s: the hand's peak distance from its held position during the swing is >= 2.5 studs"):format(weaponId),
			Detail = ("peak %.2f studs"):format(peak),
		})
		table.insert(lines, {
			Ok = played and visible >= 0.5,
			Name = ("combat %s: the swing stays visible for >= 0.5 s"):format(weaponId),
			Detail = ("%.2f s away from the held pose"):format(visible),
		})
	else
		local need = if weapon.Kind == "Peel" then 1 else 0.2
		table.insert(lines, {
			Ok = played and travelled >= need,
			Name = ("combat %s: the hand is drawn travelling during the %s"):format(weaponId, if weapon.Kind == "Peel" then "toss" else "shot (aim + recoil)"),
			Detail = ("%.2f studs (needs %.1f)"):format(travelled, need),
		})
	end
	return lines
end

-- A slot-to-slot switch (no unequip in between): the NEW weapon's hand is held.
local function probeSwitch(fromId: string, toId: string): { ProbeLine }
	local lines: { ProbeLine } = {}
	local character = localPlayer.Character
	local label = ("switch %s -> %s"):format(fromId, toId)
	if missingRig(character) then
		table.insert(lines, { Ok = true, Name = ("combat %s (skipped: not an R15 rig)"):format(label) })
		return lines
	end
	if not restHand then
		table.insert(lines, { Ok = false, Name = ("combat %s"):format(label), Detail = "no rest-pose sample" })
		return lines
	end
	probeHeld(lines, character :: Model, CombatConfig.GetWeapon(toId) :: CombatConfig.Weapon, label)
	return lines
end

local function jointsAtRest(a: { CFrame? }, b: { CFrame? }): string?
	for index = 1, 3 do
		local x, y = a[index], b[index]
		if x and y then
			local moved = (x.Position - y.Position).Magnitude
			local rx, ry, rz = x:ToObjectSpace(y):ToOrientation()
			if moved > 0.02 or math.max(math.abs(rx), math.abs(ry), math.abs(rz)) > 0.02 then
				return ("joint %d off its base (%.3f studs)"):format(index, moved)
			end
		end
	end
	return nil
end

-- After the server took the weapon away: the hand is back at rest, the
-- shoulder / waist / elbow are at base and no BaseC0 is left.
local function probeWeaponReleased(): { ProbeLine }
	local WeaponPose = require(script.Parent.Parent.Effects.WeaponPose) :: any
	local character = localPlayer.Character
	if missingRig(character) then
		return { { Ok = true, Name = "combat release: the arm is back at rest after unequip (skipped: not an R15 rig)" } }
	end
	local rest = restHand
	if not rest then
		return { { Ok = false, Name = "combat release: the arm is back at rest after unequip", Detail = "no rest-pose sample" } }
	end
	local char = character :: Model
	task.wait(0.5)
	RunService.Heartbeat:Wait()
	local away = ((WeaponPose.GetHandOffset(char) :: Vector3) - rest).Magnitude
	local stored = WeaponPose.HasBaseStored(char)
	local joints = jointsAtRest(WeaponPose.GetJointValues(char), restJoints)
	return {
		{
			Ok = away <= 0.3 and not stored and joints == nil,
			Name = "combat release: after unequip the hand is back at rest, Waist / RightElbow at base, no BaseC0 left",
			Detail = ("%.2f studs from rest, base stored %s, %s"):format(away, tostring(stored), tostring(joints or "joints at base")),
		},
	}
end

local function probeTutorial(payload: any)
	local lines: { ProbeLine } = {}
	local ok, result = pcall(function()
		if payload.Kind == "Step" then
			return probeStep(payload.StepIndex, payload.StepId)
		elseif payload.Kind == "BigCard" then
			return probeBigCard(payload.Expect, payload.FakeFusion == true)
		elseif payload.Kind == "Weapon" then
			return probeWeapon(payload.Weapon)
		elseif payload.Kind == "SampleRest" then
			return probeSampleRest()
		elseif payload.Kind == "Switch" then
			return probeSwitch(payload.From, payload.To)
		elseif payload.Kind == "WeaponReleased" then
			return probeWeaponReleased()
		end
		return {}
	end)
	if ok then
		lines = result
	else
		table.insert(lines, { Ok = false, Name = "tutorial probe", Detail = tostring(result) })
	end
	RemoteEvents.SelfTestReport:FireServer({ Stage = "TutorialProbe", Lines = lines })
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

	local hoverLines = testHover("before")
	local fired = fuzz(otherUserId)
	-- Give the server a moment to answer every junk call before it compares.
	task.wait(1.5)
	RemoteEvents.SelfTestReport:FireServer({ Stage = "Fuzz", Fired = fired })

	cardLines = {}
	textFitLines = {}
	local panelLines = testPanels()
	for _, line in textFitLines do
		table.insert(panelLines, line)
	end
	for _, line in hoverLines do
		table.insert(panelLines, line)
	end
	for _, line in testHover("after a pedestal rebuild") do
		table.insert(panelLines, line)
	end
	testPlacedCards()
	for _, line in cardLines do
		table.insert(panelLines, line)
	end
	for _, line in testCardMath() do
		table.insert(panelLines, line)
	end
	for _, line in testFusionCard() do
		table.insert(panelLines, line)
	end
	for _, line in testHudOrder() do
		table.insert(panelLines, line)
	end
	for _, line in testHudLeftColumn() do
		table.insert(panelLines, line)
	end
	for _, line in testTopStack() do
		table.insert(panelLines, line)
	end
	local shopController = require(script.Parent.ShopController) :: any
	for _, line in shopController.SelfTestDealPath() do
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
		if typeof(payload) == "table" and payload.Stage == "TutorialProbe" then
			task.spawn(probeTutorial, payload)
		else
			task.spawn(run, payload)
		end
	end)
end

return SelfTestController
