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
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local DealConfig = require(ReplicatedStorage.Shared.Config.DealConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local ShopPrices = require(ReplicatedStorage.Shared.Modules.ShopPrices)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
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
			{ { Key = "MusicOn", Value = "yes" } },
			{ { Key = "MusicVolume", Value = "loud" } },
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
			{ { Weapon = "Bat", TargetUserId = "x", Direction = "x" } },
			{ { Weapon = "LaserGun", Direction = "x" } },
			{ { Weapon = "LaserGun", Direction = Vector3.new(NAN, 0, 0) } },
			{ { Weapon = "FreezeRay", Direction = Vector3.new(INF, 0, 0) } },
			{ { Weapon = "BananaPeel", Origin = Vector3.new(1e9, 0, 0) } },
		},
		-- Never a real pull: a bad or missing count (only 1 and 10 are valid), and
		-- Auto pull with a non-boolean (a true On is not fuzzed: it would start).
		RequestGachaPull = { {}, { "x" }, { { Count = "1" } }, { { Count = 0 } }, { { Count = 5 } }, { { Count = 11 } }, { { Count = NAN } }, { { Count = 1.5 } }, { { Count = { 1 } } } },
		SetAutoPull = { {}, { "x" }, { { On = "yes" } }, { { On = 1 } }, { { On = {} } } },
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
		table.insert(cases.RequestHit, { { Weapon = "Bat", TargetUserId = n, Direction = Vector3.new(n, n, n) } })
		table.insert(cases.RequestGachaPull, { { Count = n } })
		table.insert(cases.SetSetting, { { Key = "SfxVolume", Value = if n == n and math.abs(n) ~= INF then "x" else n } })
		table.insert(cases.SetSetting, { { Key = "MusicVolume", Value = if n == n and math.abs(n) ~= INF then "x" else n } })
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
	-- Let the cards' settle loops (UIKit.SettleCard) finish first: wait for
	-- every placed card's `Settling` attribute to clear, up to 1 s.
	RunService.Heartbeat:Wait()
	local waited = os.clock()
	repeat
		local settling = false
		for _, gui in localPlayer:WaitForChild("PlayerGui"):GetDescendants() do
			if gui:IsA("GuiObject") and gui:GetAttribute("CardPlaced") == true and gui:GetAttribute("Settling") == true then
				settling = true
				break
			end
		end
		if settling then
			RunService.Heartbeat:Wait()
		end
	until not settling or os.clock() - waited > 1
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
				-- Both the NEXT-event card and a RUNNING one (Night), with the
				-- tutorial's OK row off and on.
				for _, now in { false, true } do
					for _, okRow in { false, true } do
						eventInfo.SetTutorialOk(okRow)
						eventInfo.Show(hud, if now then "Night" else "GoldenRain", now)
						measurePlacedCards(("%s %s%s"):format(label, if now then "running" else "next", if okRow then " +OK" else ""))
						eventInfo.Hide()
						task.wait(0.1)
					end
				end
				eventInfo.SetTutorialOk(false)
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

-- The deal tile (pack art or emoji fallback, ribbon = the saving, timer =
-- the seconds left), clear of the left column and the bottom row, and the
-- hidden gates, at the desktop and phone layouts.
local function testDealTile(): { string }
	local hud = require(script.Parent.HudController) :: any
	local lines: { string } = {}
	for _, phone in { false, true } do
		UIKit.SetForcedPhone(phone)
		task.wait(0.2)
		local ok, result = pcall(hud.SelfTestDealTile, if phone then "phone" else "desktop")
		if not ok then
			table.insert(lines, "FAIL deal tile: " .. tostring(result))
		else
			for _, line in result do
				table.insert(lines, line)
			end
		end
	end
	UIKit.SetForcedPhone(nil)
	return lines
end

-- Three skipped-card lines at once never overlap any HUD rect (the left
-- column, the bottom row) or the weapon bar, and sit centred.
local function testSkippedLines(): { string }
	local result = require(script.Parent.ResultController) :: any
	local hud = require(script.Parent.HudController) :: any
	local combat = require(script.Parent.CombatController) :: any
	local common = ItemConfig.GetItemsByTier("Common")[1]
	if not common then
		return { "PASS skipped lines (skipped: no Common item)" }
	end
	local lines: { string } = {}
	for _, phone in { false, true } do
		UIKit.SetForcedPhone(phone)
		task.wait(0.2)
		local label = if phone then "phone" else "desktop"
		local ok, err = pcall(function()
			local items = {}
			for index = 1, 3 do
				table.insert(items, { Uid = "selftest" .. index, ItemId = common.Id, Tier = "Common" })
			end
			local rects = result.ShowSelfTestSkippedLines(items)
			local obstacles = hud.GetObstacleRects()
			local bar = combat.GetBarRect()
			if bar then
				obstacles.WeaponBar = bar
			end
			local screenWidth = workspace.CurrentCamera.ViewportSize.X
			local bad: { string } = {}
			for index, rect in rects do
				local off = rect.Position.X + rect.Size.X / 2 - screenWidth / 2
				if math.abs(off) > 2 then
					table.insert(bad, ("line %d off-centre (%d px)"):format(index, math.floor(off)))
				end
				for name, other in obstacles do
					local overlapX = math.min(rect.Position.X + rect.Size.X, other.Position.X + other.Size.X) - math.max(rect.Position.X, other.Position.X)
					local overlapY = math.min(rect.Position.Y + rect.Size.Y, other.Position.Y + other.Size.Y) - math.max(rect.Position.Y, other.Position.Y)
					if overlapX > 1 and overlapY > 1 then
						table.insert(bad, ("line %d over %s"):format(index, name))
					end
				end
			end
			if #rects ~= 3 then
				table.insert(bad, ("%d lines up, want 3"):format(#rects))
			end
			table.insert(lines, if #bad == 0
				then ("PASS skipped lines never overlap the HUD (%s, 3 lines, centred)"):format(label)
				else ("FAIL skipped lines (%s): %s"):format(label, table.concat(bad, ", ")))
		end)
		result.ClearSkippedLines()
		if not ok then
			table.insert(lines, ("FAIL skipped lines (%s): %s"):format(label, tostring(err)))
		end
	end
	UIKit.SetForcedPhone(nil)
	return lines
end

-- Every product and power-up has a plain-words line for a 7-year-old.
-- The background music: every track loads, the toggle stops it and turning it
-- back on resumes it, and a big sting ducks it. The player's setting is put back.
local function testMusic(): { string }
	local MusicConfig = require(ReplicatedStorage.Shared.Config.MusicConfig)
	local Music = require(script.Parent.MusicController) :: any
	local tycoon = require(script.Parent.TycoonController) :: any
	local lines: { string } = {}
	local failed = Music.CheckAll()
	table.insert(
		lines,
		if #failed == 0
			then ("PASS music: all %d tracks load"):format(#MusicConfig.Tracks)
			else "FAIL music: a track did not load: " .. table.concat(failed, ", ")
	)
	local sound: Sound? = Music.GetSound()
	if not sound then
		table.insert(lines, "FAIL music: the playlist Sound exists")
		return lines
	end
	local music = sound :: Sound
	local wasOn, wasVolume = tycoon.IsMusicOn(), tycoon.GetMusicVolume()
	tycoon.SetMusicOn(true)
	tycoon.SetMusicVolume(require(ReplicatedStorage.Shared.Config.SettingsConfig).DefaultMusicVolume, false)
	local waited = 0
	while not (music.IsLoaded and music.IsPlaying) and waited < 10 do
		task.wait(0.25)
		waited += 0.25
	end
	local playing = music.IsPlaying
	table.insert(lines, (if playing then "PASS" else "FAIL") .. " music: the playlist is playing (Settings -> Music on)")
	-- Ducking: a big sting dips the level to about 40%.
	local level = music.Volume
	local steady = music.TimePosition > 3 and music.TimeLength > 0 and music.TimeLength - music.TimePosition > 4
	if playing and steady and level > 0.01 then
		SoundKit.Play("RevealMajor", nil)
		task.wait(0.7)
		local ducked = music.Volume
		table.insert(
			lines,
			(if ducked <= level * (MusicConfig.DuckFraction + 0.15) then "PASS" else "FAIL")
				.. (" music: a big reveal sting ducks the music (%.3f -> %.3f)"):format(level, ducked)
		)
		task.wait(MusicConfig.DuckSeconds)
	else
		table.insert(lines, "PASS music: ducking check skipped (a track fade is in progress)")
	end
	tycoon.SetMusicOn(false)
	task.wait(0.5)
	table.insert(lines, (if not music.IsPlaying then "PASS" else "FAIL") .. " music: turning it off stops the music")
	tycoon.SetMusicOn(true)
	task.wait(0.6)
	table.insert(lines, (if music.IsPlaying then "PASS" else "FAIL") .. " music: turning it back on resumes it")
	tycoon.SetMusicVolume(wasVolume, true)
	tycoon.SetMusicOn(wasOn)
	return lines
end

-- A weapon earned before Rebirth 1 says when it works.
local function testUnlockCard(): { string }
	local combat = require(script.Parent.CombatController) :: any
	local title, body = combat.GetUnlockCardText("SlapGlove", 0)
	local earlyOk = title:find("Slap Glove", 1, true) ~= nil and body:find("Rebirth 1", 1, true) ~= nil
	local _, later = combat.GetUnlockCardText("SlapGlove", 1)
	local laterOk = later:find("Rebirth", 1, true) == nil
	return {
		(if earlyOk then "PASS" else "FAIL") .. (" unlock card at Rebirth 0 says '%s' / '%s'"):format(title, (body:gsub("\n", " / "))),
		(if laterOk then "PASS" else "FAIL") .. " unlock card at Rebirth 1+ has no Rebirth note",
	}
end

local function testPlain(): { string }
	local missing: { string } = {}
	local count = 0
	for key, item in ShopConfig.Items do
		count += 1
		if typeof(item.Plain) ~= "string" or item.Plain:gsub("%s", "") == "" then
			table.insert(missing, key)
		end
	end
	for key, def in QuestConfig.PowerUps do
		count += 1
		if typeof(def.Plain) ~= "string" or def.Plain:gsub("%s", "") == "" then
			table.insert(missing, key)
		end
	end
	table.sort(missing)
	return {
		if #missing == 0
			then ("PASS plain words: all %d products and power-ups have a Plain line"):format(count)
			else "FAIL plain words missing: " .. table.concat(missing, ", "),
	}
end

-- A bundle card (the 3 deals and the Starter Pack) shows one tile per
-- DISTINCT part, a YOU GET line per part, and a worth line equal to the live
-- sum of the parts.
local function testDealCards(): { string }
	local DealParts = require(UI.DealParts) :: any
	local shop = require(script.Parent.ShopController) :: any
	local lines: { string } = {}
	local gui = Instance.new("ScreenGui")
	gui.Name = "SelfTestDealParts"
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	for _, key in { "DealPowerHour", "DealFusionKit", "DealRichLab", "StarterPack" } do
		local item = ShopConfig.GetItem(key) :: ShopConfig.Item
		local parts: { string } = item.Parts or {}
		local seen: { [string]: boolean } = {}
		local distinct = 0
		for _, part in parts do
			if not seen[part] then
				seen[part] = true
				distinct += 1
			end
		end
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(600, 400)
		frame.Parent = gui
		local tiles = DealParts.BuildTiles(frame, parts, 2)
		local youGet = DealParts.BuildYouGet(frame, parts, 2, UDim.new(1, 0), 14)
		local tileCount, lineCount = 0, 0
		for _, child in tiles:GetChildren() do
			if child.Name:sub(1, 9) == "PartTile_" then
				tileCount += 1
			end
		end
		local plainOk = true
		for _, child in youGet:GetChildren() do
			if child.Name:sub(1, 7) == "YouGet_" then
				lineCount += 1
				local partItem = ShopConfig.GetItem(child.Name:sub(8)) :: ShopConfig.Item?
				if not partItem or not (child :: TextLabel).Text:find(UIKit.EscapeRichText(DealParts.PlainLine(child.Name:sub(8))), 1, true) then
					plainOk = false
				end
			end
		end
		local worthLine, worth = shop.GetWorthLine(key)
		local live = ShopPrices.GetPartsTotal(key)
		local price = ShopPrices.Get(key)
		-- The worth is the live sum (or absent while a price is unknown or the
		-- bundle isn't cheaper).
		local expectWorth = if live and not (price and live <= price) then live else nil
		local worthOk = worth == expectWorth and (worthLine == nil or (worthLine :: string):find(tostring(worth), 1, true) ~= nil)
		table.insert(lines, if tileCount == distinct and lineCount == distinct and plainOk and worthOk
			then ("PASS deal card %s: %d tiles, %d YOU GET lines, worth %s"):format(key, tileCount, lineCount, if worth then tostring(worth) else "n/a (prices not live)")
			else ("FAIL deal card %s: tiles %d / lines %d (want %d), plain %s, worth %s (live sum %s)"):format(key, tileCount, lineCount, distinct, tostring(plainOk), tostring(worth), tostring(live)))
		frame:Destroy()
	end
	gui:Destroy()
	return lines
end

-- Counts the DealParts pieces under `root`.
local function countBundleParts(root: Instance): (number, number)
	local tiles, lines = 0, 0
	for _, descendant in root:GetDescendants() do
		if descendant.Name:sub(1, 9) == "PartTile_" then
			tiles += 1
		elseif descendant.Name:sub(1, 7) == "YouGet_" then
			lines += 1
		end
	end
	return tiles, lines
end

local function distinctCount(parts: { string }): number
	local seen: { [string]: boolean } = {}
	local count = 0
	for _, part in parts do
		if not seen[part] then
			seen[part] = true
			count += 1
		end
	end
	return count
end

-- Every item with `Parts`, in every place it is drawn (the shop's Deal and
-- Featured banners and its grid tiles, the Starter / deal side cards), shows
-- one tile per distinct part and one YOU GET line per part: read from the
-- instance tree. The Pocket Cash line carries the real amount. Also: every
-- text in the shop is at least 13 px (a scaled text by its minimum).
local function testBundleContents(): { string }
	local DealParts = require(UI.DealParts) :: any
	local ShopCards = require(UI.ShopCards) :: any
	local shop = require(UI.ShopPanel) :: any
	local shopController = require(script.Parent.ShopController) :: any
	local lines: { string } = {}
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	for _, phone in { false, true } do
		local label = if phone then "phone" else "desktop"
		UIKit.SetForcedPhone(phone)
		task.wait(0.2)
		local ok, err = pcall(function()
			shop.Open()
			task.wait(0.6)
			local gui = playerGui:FindFirstChild("ShopPanel")
			if not gui then
				table.insert(lines, ("FAIL shop bundles (%s): no ShopPanel gui"):format(label))
				return true
			end
			-- Containers: the banners (ShopKey) and the grid tiles (named by key).
			local checked, bad = 0, {}
			for _, container in gui:GetDescendants() do
				local key = container:GetAttribute("ShopKey")
				if typeof(key) ~= "string" then
					key = container.Name
				end
				local entry = ShopConfig.GetItem(key :: string) :: ShopConfig.Item?
				local isBanner = container.Name == "FeaturedBanner" or container.Name == "DealBanner"
				if entry and entry.Parts and (isBanner or container.Name == key) and container:IsA("Frame") then
					checked += 1
					local want = distinctCount(entry.Parts)
					local tileCount, lineCount = countBundleParts(container)
					if tileCount ~= want or lineCount ~= want then
						table.insert(bad, ("%s %s: %d tiles / %d lines, want %d"):format(container.Name, key :: string, tileCount, lineCount, want))
					end
				end
			end
			table.insert(lines, if #bad == 0 and checked > 0
				then ("PASS shop bundles (%s): %d places show one tile and one YOU GET line per part"):format(label, checked)
				else ("FAIL shop bundles (%s): %d checked; %s"):format(label, checked, table.concat(bad, "; ")))

			-- The Starter Pack banner says "Worth ... if bought separately", never "one by one".
			local oneByOne = false
			for _, descendant in gui:GetDescendants() do
				if descendant:IsA("TextLabel") and descendant.Text:lower():find("one by one", 1, true) then
					oneByOne = true
				end
			end
			table.insert(lines, if oneByOne then ("FAIL shop (%s): still says 'one by one'"):format(label) else ("PASS shop (%s): no 'one by one' text"):format(label))

			-- Pocket Cash's line shows the amount it grants right now.
			local cashLine = DealParts.PlainLine("PocketCash")
			local amount = "+" .. NumberFormat.Money(shopController.GetCashAmount("PocketCash"))
			table.insert(lines, if cashLine:find(amount, 1, true)
				then ("PASS Pocket Cash line carries the real amount (%s)"):format(cashLine)
				else ("FAIL Pocket Cash line '%s' lacks %s"):format(cashLine, amount))

			-- Nothing in the shop is under 13 px.
			local small: { string } = {}
			local texts = 0
			for _, descendant in gui:GetDescendants() do
				if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and descendant.Text ~= "" then
					texts += 1
					local size = descendant.TextSize
					local constraint = descendant:FindFirstChildOfClass("UITextSizeConstraint")
					if descendant.TextScaled then
						size = if constraint then constraint.MinTextSize else 0
					end
					if size < 13 then
						table.insert(small, ("%s %d"):format(descendant:GetFullName():match("[^%.]+%.[^%.]+$") or descendant.Name, size))
					end
				end
			end
			table.insert(lines, if #small == 0
				then ("PASS shop text (%s): all %d texts are >= 13 px"):format(label, texts)
				else ("FAIL shop text (%s): under 13 px: %s"):format(label, table.concat(small, ", ", 1, math.min(#small, 8))))
			shop.Toggle()
			task.wait(0.4)
			return true
		end)
		if not ok then
			table.insert(lines, ("FAIL shop bundles (%s): %s"):format(label, tostring(err)))
		end
	end
	UIKit.SetForcedPhone(nil)

	-- The side cards (Starter Pack, the three deals).
	local sideBad, sideChecked = {}, 0
	for _, key in { "StarterPack", "DealPowerHour", "DealFusionKit", "DealRichLab" } do
		local entry = ShopConfig.GetItem(key) :: ShopConfig.Item
		ShopCards.ShowStarter({
			Name = "SelfTestSideCard",
			Caption = "self-test",
			Title = entry.Name,
			Detail = "",
			Parts = entry.Parts,
			BuyText = "TEST",
			DismissText = "No",
		}, function() end, function() end)
		task.wait(0.3)
		local card = playerGui:FindFirstChild("ShopCards") and (playerGui.ShopCards :: Instance):FindFirstChild("SelfTestSideCard")
		if card then
			sideChecked += 1
			local want = distinctCount(entry.Parts or {})
			local tileCount, lineCount = countBundleParts(card)
			if tileCount ~= want or lineCount ~= want then
				table.insert(sideBad, ("%s: %d tiles / %d lines, want %d"):format(key, tileCount, lineCount, want))
			end
		else
			table.insert(sideBad, key .. ": no card")
		end
		ShopCards.CloseSide()
		task.wait(0.3)
	end
	table.insert(lines, if #sideBad == 0
		then ("PASS side cards: %d bundles show one tile and one YOU GET line per part"):format(sideChecked)
		else "FAIL side cards: " .. table.concat(sideBad, "; "))
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
			Ok = TutorialExplain.IsOpen() and body ~= nil and body.TextSize >= 22 and body.Text == step.Card.Body and body.AbsoluteSize.X > 0 and body.AbsoluteSize.Y > 0 and body.TextBounds.Y > 0,
			Name = ("tutorial %s: its explain card opens first (text >= 22 px, drawn)"):format(stepId),
			Detail = if body then ("%d px, drawn %dx%d, text height %d"):format(body.TextSize, body.AbsoluteSize.X, body.AbsoluteSize.Y, body.TextBounds.Y) else "no card",
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
	local size = ResultController.GetBigCardHeadlineSize()
	return {
		{
			Ok = ResultController.IsBigCardOpen() and headline == expect and size.X > 0 and size.Y > 0,
			Name = if fakeFusion then "a single fusion (Common x2 -> Rare) opens the big card" else "a single pull of a Common opens the big card",
			Detail = ("headline %s, drawn %dx%d"):format(tostring(headline), size.X, size.Y),
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

-- What the rig is doing right now, for a FAIL's Detail: the rest and held
-- hand offsets, every playing track (name, priority, weight, time), the
-- shoulder's C0 against its stored base, which pose owners are up and
-- whether the fallback switch is still on. A FAIL pasted from here is
-- enough to tell "rest sampled mid-fade" from "track at weight 0 / out-
-- prioritised" from "forceFallback left on".
local function describeRig(character: Model, rest: Vector3?, held: Vector3?): string
	local WeaponPose = require(script.Parent.Parent.Effects.WeaponPose) :: any
	local WeaponAnimator = require(script.Parent.Parent.Effects.WeaponAnimator) :: any
	local parts: { string } = {}
	local function v(vector: Vector3?): string
		return if vector then ("(%.2f, %.2f, %.2f)"):format(vector.X, vector.Y, vector.Z) else "nil"
	end
	table.insert(parts, ("rest %s, held %s"):format(v(rest), v(held)))
	local animator = character:FindFirstChildWhichIsA("Animator", true)
	local tracks: { string } = {}
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			table.insert(tracks, ("%s[%s w%.2f/%.2f t%.2f]"):format(track.Name ~= "" and track.Name or tostring(track.Animation and track.Animation.Name), track.Priority.Name, track.WeightCurrent, track.WeightTarget, track.TimePosition))
		end
	end
	table.insert(parts, ("tracks {%s}"):format(table.concat(tracks, ", ")))
	local shoulder = character:FindFirstChild("RightUpperArm") and (character :: any).RightUpperArm:FindFirstChild("RightShoulder")
	if shoulder and shoulder:IsA("Motor6D") then
		local base = shoulder:GetAttribute("BaseC0")
		table.insert(parts, ("shoulder enabled %s, C0 %s, BaseC0 %s"):format(tostring(shoulder.Enabled), v(shoulder.C0.Position), if typeof(base) == "CFrame" then v(base.Position) else "none"))
	else
		table.insert(parts, "shoulder: no Motor6D")
	end
	table.insert(parts, ("anim %s, pose %s, forceFallback %s"):format(tostring(WeaponAnimator.GetHeldWeapon(character)), tostring(WeaponPose.GetHeldWeapon(character)), tostring(WeaponAnimator.SelfTestIsForcingFallback())))
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	table.insert(parts, ("humanoid %s, platformStand %s, root anchored %s"):format(humanoid and humanoid:GetState().Name or "none", tostring(humanoid and humanoid.PlatformStand), tostring(root and root:IsA("BasePart") and root.Anchored)))
	return table.concat(parts, "; ")
end

-- Nothing held, nothing playing, no base stored, and the hand still for two
-- samples: only then is it the REST pose (a hold track still fading out, or
-- a pose not yet released, made rest == held and the hold checks read 0.01).
local function waitForRest(character: Model): boolean
	local WeaponPose = require(script.Parent.Parent.Effects.WeaponPose) :: any
	local WeaponAnimator = require(script.Parent.Parent.Effects.WeaponAnimator) :: any
	local deadline = os.clock() + 2
	local previous: Vector3? = nil
	while os.clock() < deadline do
		RunService.Heartbeat:Wait()
		local hand = WeaponPose.GetHandOffset(character)
		local idle = WeaponPose.GetHeldWeapon(character) == nil
			and WeaponAnimator.GetHeldWeapon(character) == nil
			and not WeaponAnimator.AnyPlaying(character)
			and not WeaponPose.HasBaseStored(character)
			and character:FindFirstChildOfClass("Tool") == nil
		if idle and hand and previous and (hand - previous).Magnitude < 0.02 then
			return true
		end
		previous = hand
		task.wait(0.05)
	end
	return false
end

local function probeSampleRest(): { ProbeLine }
	local WeaponPose = require(script.Parent.Parent.Effects.WeaponPose) :: any
	local character = localPlayer.Character
	if missingRig(character) then
		restHand = nil
		return {}
	end
	local char = character :: Model
	local settled = waitForRest(char)
	RunService.Heartbeat:Wait()
	restHand = WeaponPose.GetHandOffset(char)
	restJoints = WeaponPose.GetJointValues(char)
	if not settled then
		-- Say so now: the checks that follow compare against this sample.
		return { { Ok = false, Name = "combat: the rest pose settles before it is sampled (nothing held, no track playing, hand still)", Detail = describeRig(char, restHand, nil) } }
	end
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
	local holding = (require(script.Parent.CombatController) :: any).GetHeldPoseWeapon(character) == weapon.Id
	if weapon.Kind == "Ranged" or weapon.Kind == "Freeze" then
		-- Aimed: the hand is up around shoulder height.
		local torso = character:FindFirstChild("UpperTorso") :: BasePart?
		local shoulderY = if torso then torso.Size.Y / 2 - 0.3 else 0.7
		table.insert(lines, {
			Ok = holding and math.abs(held.Y - shoulderY) <= 0.8 and held.Z < -0.8,
			Name = ("combat %s: the hand is raised to about shoulder height while aiming"):format(label),
			Detail = ("hand y %.2f (shoulder %.2f), z %.2f | %s"):format(held.Y, shoulderY, held.Z, describeRig(character, rest, held)),
		})
	else
		-- The bat sits on the shoulder (no "forward" needed): the hand is drawn
		-- away from rest and the hold track loops.
		local WeaponAnimator = require(script.Parent.Parent.Effects.WeaponAnimator) :: any
		local holdTrack = WeaponAnimator.GetHoldTrack(character)
		local looping = holdTrack ~= nil and holdTrack.IsPlaying and holdTrack.Looped
		table.insert(lines, {
			Ok = holding and (held - rest).Magnitude >= 1 and looping,
			Name = ("combat %s: the hand is drawn at least 1 stud away from its rest pose and the hold track loops"):format(label),
			Detail = ("moved %.2f studs, hold track looping %s, pose %s | %s"):format((held - rest).Magnitude, tostring(looping), tostring((require(script.Parent.CombatController) :: any).GetHeldPoseWeapon(character)), describeRig(character, rest, held)),
		})
	end
	return held
end

-- The needs below are for a 5-stud avatar; a smaller one (the monkey) swings
-- a shorter arc, so they scale with the character's height, clamped to
-- 0.6-1.0. Height = sole to top of the head (a held tool must not count).
local function heightScale(character: Model): (number, number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if not humanoid or not root or not root:IsA("BasePart") or not head or not head:IsA("BasePart") then
		return 1, 5
	end
	local height = (head.Position.Y + head.Size.Y / 2) - (root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight)
	return math.clamp(height / 5, 0.6, 1), height
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
	while CombatController.GetHeldPoseWeapon(char) ~= weaponId and os.clock() - started < 2 do
		task.wait(0.05)
	end
	local held = probeHeld(lines, char, weapon, weaponId)
	local tool = char:FindFirstChildOfClass("Tool")
	if tool and weapon.Kind == "Melee" then
		local clearance = WeaponPose.GetToolClearance(char, tool) or 0
		local scale, height = heightScale(char)
		table.insert(lines, {
			Ok = clearance >= 1.5 * scale,
			Name = ("combat %s: the held weapon reaches 1.5 studs (x height/5) clear of the torso"):format(weaponId),
			Detail = ("%.2f studs, needs %.2f (avatar %.1f studs tall, x%.2f)"):format(clearance, 1.5 * scale, height, scale),
		})
	end

	-- The tracks: a looping hold track plays while held; the swing track
	-- plays, is >= 0.4 s long and fires its Hit marker exactly once.
	local WeaponAnimator = require(script.Parent.Parent.Effects.WeaponAnimator) :: any
	local holdTrack = WeaponAnimator.GetHoldTrack(char)
	table.insert(lines, {
		Ok = holdTrack ~= nil and holdTrack.IsPlaying and holdTrack.Looped,
		Name = ("combat %s: the held weapon plays a looping hold track"):format(weaponId),
		Detail = if holdTrack then ("playing %s, looped %s"):format(tostring(holdTrack.IsPlaying), tostring(holdTrack.Looped)) else "no hold track (C0 fallback)",
	})
	local actionTrack = WeaponAnimator.GetActionTrack(char)
	local hits = 0
	local hitConnection = if actionTrack then actionTrack:GetMarkerReachedSignal("Hit"):Connect(function()
		hits += 1
	end) else nil
	local played = CombatController.PlayPose(weaponId)
	local trackPlaying = false
	local peak, travelled, visible = 0, 0, 0
	local last = held
	local sampled = os.clock()
	local lastFrame = sampled
	while os.clock() - sampled < 1 do
		RunService.Heartbeat:Wait()
		local now = WeaponPose.GetHandOffset(char)
		local clock = os.clock()
		if actionTrack and actionTrack.IsPlaying then
			trackPlaying = true
		end
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
	if hitConnection then
		hitConnection:Disconnect()
	end
	if weapon.Kind == "Melee" or weapon.Kind == "Peel" then
		local length = if actionTrack then actionTrack.Length else 0
		table.insert(lines, {
			Ok = played and trackPlaying and length >= (if weapon.Kind == "Melee" then 0.4 else 0.3) and hits == 1,
			Name = ("combat %s: the action track plays, is long enough and its Hit marker fires once"):format(weaponId),
			Detail = ("playing %s, length %.2f s, Hit fired %d x"):format(tostring(trackPlaying), length, hits),
		})
	end
	if weapon.Kind == "Melee" then
		local scale, height = heightScale(char)
		table.insert(lines, {
			Ok = played and peak >= 1.5 * scale,
			Name = ("combat %s: the hand's peak distance from its held position during the swing is >= 1.5 studs (x height/5)"):format(weaponId),
			Detail = ("peak %.2f studs, needs %.2f (avatar %.1f studs tall, x%.2f)"):format(peak, 1.5 * scale, height, scale),
		})
		table.insert(lines, {
			Ok = played and visible >= 0.4,
			Name = ("combat %s: the swing stays visible for >= 0.4 s"):format(weaponId),
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
	local WeaponAnimator = require(script.Parent.Parent.Effects.WeaponAnimator) :: any
	local playing = WeaponAnimator.AnyPlaying(char)
	return {
		{
			Ok = away <= 0.3 and not stored and joints == nil and not playing,
			Name = "combat release: after unequip no weapon track plays, the hand is back at rest and no BaseC0 is left",
			Detail = ("%.2f studs from rest, base stored %s, %s, track playing %s | %s"):format(away, tostring(stored), tostring(joints or "joints at base"), tostring(playing), describeRig(char, rest, nil)),
		},
	}
end

-- The live fallback (no id, not Studio): WeaponAnimator.Hold says no and the
-- C0 WeaponPose still runs, then restores.
local function probeFallback(): { ProbeLine }
	local WeaponPose = require(script.Parent.Parent.Effects.WeaponPose) :: any
	local WeaponAnimator = require(script.Parent.Parent.Effects.WeaponAnimator) :: any
	local character = localPlayer.Character
	if missingRig(character) then
		return { { Ok = true, Name = "combat live fallback: the C0 pose still runs (skipped: not an R15 rig)" } }
	end
	local char = character :: Model
	-- The C0 fallback only drives a Motor6D shoulder. On an AnimationConstraint
	-- rig it is not what ships (Harris publishes the animation ids before
	-- launch), so there it is skipped, as a PASS.
	local upperArm = char:FindFirstChild("RightUpperArm")
	local shoulderMotor = upperArm and upperArm:FindFirstChild("RightShoulder")
	if not (shoulderMotor and shoulderMotor:IsA("Motor6D") and shoulderMotor.Enabled) then
		return { { Ok = true, Name = "combat live fallback: the C0 pose still runs (skipped: AnimationConstraint rig)" } }
	end
	local settled = waitForRest(char)
	local rest = WeaponPose.GetHandOffset(char) :: Vector3
	local bat = CombatConfig.GetWeapon("Bat") :: CombatConfig.Weapon
	-- The switch is always switched back, whatever Hold does.
	WeaponAnimator.SelfTestForceFallback(true)
	local okHold, usedTrack = pcall(WeaponAnimator.Hold, char, bat)
	WeaponAnimator.SelfTestForceFallback(false)
	WeaponPose.Hold(char, bat)
	task.wait(0.4)
	RunService.Heartbeat:Wait()
	local heldAt = WeaponPose.GetHandOffset(char) :: Vector3
	local moved = (heldAt - rest).Magnitude
	local holding = WeaponPose.GetHeldWeapon(char) == "Bat"
	local detail = describeRig(char, rest, heldAt)
	WeaponPose.Release(char, "Bat")
	task.wait(0.2)
	local stored = WeaponPose.HasBaseStored(char)
	return {
		{
			Ok = settled and okHold and not usedTrack and holding and moved >= 1 and not stored and not WeaponAnimator.SelfTestIsForcingFallback(),
			Name = "combat live fallback: with no id the C0 pose still runs, moves the hand >= 1 stud (and restores)",
			Detail = ("rest settled %s, track used %s, pose held %s, hand moved %.2f studs, base left %s | %s"):format(tostring(settled), tostring(usedTrack), tostring(holding), moved, tostring(stored), detail),
		},
	}
end

-- Why a GuiObject is NOT drawn (nil = drawn): both axes of AbsoluteSize > 0
-- and Visible all the way up to `root`, which must be enabled. Every UI
-- check reads the INSTANCE TREE through this, never a table the controller
-- keeps about itself (that is how unparented tiles passed once).
local function drawnProblem(object: GuiObject, root: Instance): string?
	local size = object.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return ("size %dx%d"):format(size.X, size.Y)
	end
	local current: Instance? = object
	while current and current ~= root do
		if current:IsA("GuiObject") and not current.Visible then
			return current.Name .. " hidden"
		end
		current = current.Parent
	end
	if current == nil then
		return "not under its gui"
	end
	if root:IsA("LayerCollector") and not root.Enabled then
		return "gui disabled"
	end
	return nil
end

-- Waits until the Gacha card is in the wanted state (open = shown at
-- UIScale 1, or closed = hidden); returns the card.
local function waitForCard(open: boolean, timeout: number): any?
	local Board = require(script.Parent.GachaBoardController) :: any
	local started = os.clock()
	local card = Board.GetCard()
	while os.clock() - started < timeout do
		card = Board.GetCard()
		if card and ((open and card.Open and card.Shown and card.Pop.Scale >= 0.999) or (not open and not card.Shown)) then
			return card
		end
		task.wait(0.05)
	end
	return card
end

-- The gacha station's own prompts (Pull / Pull x10 / How it works): each must
-- be OFF, and none may have drawn a prompt UI.
local gachaPromptShown = 0
local gachaPromptWatch: RBXScriptConnection? = nil

local function stationPrompts(card: any): { ProximityPrompt }
	local list: { ProximityPrompt } = {}
	local station = (card.Pad :: BasePart).Parent
	if station then
		for _, descendant in station:GetDescendants() do
			if descendant:IsA("ProximityPrompt") then
				table.insert(list, descendant)
			end
		end
	end
	return list
end

local function watchGachaPrompts()
	if gachaPromptWatch then
		return
	end
	gachaPromptShown = 0
	gachaPromptWatch = game:GetService("ProximityPromptService").PromptShown:Connect(function(prompt: ProximityPrompt)
		local name = prompt.Name
		if name == "PullPrompt" or name == "Pull10Prompt" or name == "HelpPrompt" and prompt:GetAttribute("HelpTopic") == "Gacha" then
			gachaPromptShown += 1
		end
	end)
end

-- The card opening: the character is moved onto the pad and, the FRAME AFTER
-- the card opens, all 6 tiles are laid out (AbsoluteSize > 0 both axes) and
-- their % has text height (the old card drew its tiles in pieces). Needs the
-- card closed first (the server teleports the character away before this).
local function probeGachaOpen(): { ProbeLine }
	local Board = require(script.Parent.GachaBoardController) :: any
	local lines: { ProbeLine } = {}
	local card = waitForCard(false, 3)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not card or not root or not root:IsA("BasePart") then
		return { { Ok = false, Name = "gacha card: it opens fully in one frame", Detail = "no card or no character" } }
	end
	watchGachaPrompts()
	local pad = card.Pad :: BasePart
	local gui = card.Billboard :: BillboardGui
	root.CFrame = CFrame.new(pad.Position + Vector3.new(0, pad.Size.Y / 2 + 3, 0))
	local frames = 0
	local started = os.clock()
	while os.clock() - started < 3 do
		RunService.Heartbeat:Wait()
		frames += 1
		local now = Board.GetCard()
		if now and now.Shown then
			break
		end
	end
	RunService.Heartbeat:Wait() -- the frame after it opened
	local after = Board.GetCard()
	local drawn, texted = 0, 0
	local bad: { string } = {}
	for _, tier in FusionConfig.TierOrder do
		local tile = gui:FindFirstChild("Tile_" .. tier, true)
		local percent = tile and tile:FindFirstChild("Percent")
		if tile and tile:IsA("GuiObject") and tile.AbsoluteSize.X > 0 and tile.AbsoluteSize.Y > 0 and drawnProblem(tile, gui) == nil then
			drawn += 1
		else
			table.insert(bad, ("%s tile %s"):format(tier, if tile and tile:IsA("GuiObject") then ("%dx%d"):format(tile.AbsoluteSize.X, tile.AbsoluteSize.Y) else "missing"))
		end
		if percent and percent:IsA("TextLabel") and percent.TextBounds.Y > 0 then
			texted += 1
		else
			table.insert(bad, ("%s %% %s"):format(tier, if percent and percent:IsA("TextLabel") then ("TextBounds.Y %d"):format(percent.TextBounds.Y) else "missing"))
		end
	end
	table.insert(lines, {
		Ok = after ~= nil and after.Shown and drawn == #FusionConfig.TierOrder and texted == #FusionConfig.TierOrder,
		Name = "gacha card: it opens fully in one frame (the frame after it opens all 6 tiles are laid out and their % has text height)",
		Detail = ("opened after %d frames; %d/%d tiles with AbsoluteSize > 0, %d/%d %% labels with TextBounds.Y > 0%s"):format(
			frames,
			drawn,
			#FusionConfig.TierOrder,
			texted,
			#FusionConfig.TierOrder,
			if #bad > 0 then " | " .. table.concat(bad, "; ") else ""
		),
	})
	-- No gacha prompt draws UI: all off, and none was shown while we stood here.
	task.wait(0.8)
	local on: { string } = {}
	for _, prompt in stationPrompts(card) do
		if prompt.Enabled and (prompt.Name == "PullPrompt" or prompt.Name == "Pull10Prompt" or prompt.Name == "HelpPrompt") then
			table.insert(on, prompt.Name)
		end
	end
	table.insert(lines, {
		Ok = #on == 0 and gachaPromptShown == 0,
		Name = "gacha card: no gacha ProximityPrompt draws UI (Pull / Pull x10 / How it works are off)",
		Detail = ("enabled prompts [%s], PromptShown fired %d times"):format(table.concat(on, ", "), gachaPromptShown),
	})
	if gachaPromptWatch then
		gachaPromptWatch:Disconnect()
		gachaPromptWatch = nil
	end
	return lines
end

-- The pop-up card, read from the instance tree (the character already
-- stands on the pad): it is open at UIScale 1, all 6 tiles are drawn with
-- an orb (or the black "?" orb) and a % that has text height and is >= 12 px
-- tall, no ViewportFrame / CanvasGroup, exactly one sizing UIScale besides
-- the phone's, no GachaBoard in the workspace, the anchor 1 stud over the
-- head; then each tier's drawn % equals GetGachaRates at the server's luck,
-- the luck pill, the silhouettes and the (i) panel's per-orb sums.
local function probeGachaCard(serverLuck: number, label: string): { ProbeLine }
	local lines: { ProbeLine } = {}
	local TycoonController = require(script.Parent.TycoonController) :: any
	local Board = require(script.Parent.GachaBoardController) :: any
	local started = os.clock()
	while math.abs(TycoonController.GetLuck() - serverLuck) > 1e-6 and os.clock() - started < 3 do
		task.wait(0.1)
	end
	Board.RefreshNow()
	local card = waitForCard(true, 3)
	RunService.Heartbeat:Wait()
	task.wait(0.15) -- the layout settles
	if not card then
		table.insert(lines, { Ok = false, Name = ("gacha card (%s): your card exists"):format(label), Detail = "no card (the lab is unclaimed, or the pad has not streamed in)" })
		return lines
	end
	local gui = card.Billboard :: BillboardGui
	table.insert(lines, {
		Ok = card.Shown and card.Pop.Scale >= 0.999 and card.Open,
		Name = ("gacha card (%s): with the character on the pad the card is open at UIScale 1"):format(label),
		Detail = ("shown %s, PopScale %.3f, open %s, card %dx%d px"):format(tostring(card.Shown), card.Pop.Scale, tostring(card.Open), card.Card.AbsoluteSize.X, card.Card.AbsoluteSize.Y),
	})

	-- Six tiles drawn, each with an orb (or the black one) and a % with text height >= 12 px.
	local tiles, orbs, percents, tall = 0, 0, 0, 0
	local tallBad: { string } = {}
	for _, tier in FusionConfig.TierOrder do
		local tile = gui:FindFirstChild("Tile_" .. tier, true)
		if tile and tile:IsA("GuiObject") and drawnProblem(tile, gui) == nil then
			tiles += 1
			local orb = tile:FindFirstChild("Orb")
			local silhouette = tile:FindFirstChild("Silhouette")
			local orbDrawn = orb and orb:IsA("GuiObject") and drawnProblem(orb, gui) == nil
			local silhouetteDrawn = silhouette and silhouette:IsA("GuiObject") and drawnProblem(silhouette, gui) == nil
			if orbDrawn or silhouetteDrawn then
				orbs += 1
			end
			local percent = tile:FindFirstChild("Percent")
			if percent and percent:IsA("TextLabel") and drawnProblem(percent, gui) == nil and percent.TextBounds.Y > 0 then
				percents += 1
				if percent.AbsoluteSize.Y >= 12 then
					tall += 1
				else
					table.insert(tallBad, ("%s %.1f px"):format(tier, percent.AbsoluteSize.Y))
				end
			end
		end
	end
	local total = #FusionConfig.TierOrder
	table.insert(lines, {
		Ok = tiles == total and orbs == total and percents == total and tall == total,
		Name = ("gacha card (%s): all 6 tiles are drawn, each with an orb and a %% >= 12 px tall"):format(label),
		Detail = ("%d/%d tiles drawn, %d orbs, %d %% labels with text height, %d >= 12 px tall%s"):format(tiles, total, orbs, percents, tall, if #tallBad > 0 then " | too small: " .. table.concat(tallBad, ", ") else ""),
	})

	-- No ViewportFrame, no CanvasGroup; the only UIScale besides the phone's
	-- is the pop.
	local viewports, canvasGroups, scales = 0, 0, {}
	for _, descendant in gui:GetDescendants() do
		if descendant:IsA("ViewportFrame") then
			viewports += 1
		elseif descendant:IsA("CanvasGroup") then
			canvasGroups += 1
		elseif descendant:IsA("UIScale") and descendant.Name ~= "PhoneScale" and descendant.Name ~= "SelectScale" then
			table.insert(scales, (descendant:GetFullName():gsub("^.-GachaCard%.", "")))
		end
	end
	local leftover = Workspace:FindFirstChild("GachaBoard", true)
	table.sort(scales)
	table.insert(lines, {
		Ok = viewports == 0 and canvasGroups == 0 and table.concat(scales, ",") == "Root.PopRoot.PopScale" and leftover == nil,
		Name = ("gacha card (%s): no ViewportFrame, no CanvasGroup, only the pop UIScale besides the phone one, no GachaBoard"):format(label),
		Detail = ("ViewportFrames %d, CanvasGroups %d, UIScales [%s], GachaBoard %s"):format(viewports, canvasGroups, table.concat(scales, ", "), tostring(leftover)),
	})

	-- The billboard itself: adorned to the pad, pixel size, grows upward from
	-- the anchor (pad top + 0.5..3 studs, centred), the flags from the brief.
	local G = PlotLayout.Gacha
	local pad = card.Pad :: BasePart
	local anchor = card.Anchor :: Attachment
	local flat = Vector2.new(anchor.WorldPosition.X - pad.Position.X, anchor.WorldPosition.Z - pad.Position.Z).Magnitude
	local up = anchor.WorldPosition.Y - (pad.Position.Y + PlotLayout.Station.PadHeight / 2)
	local billboardBad: { string } = {}
	if gui.Adornee ~= anchor or anchor.Name ~= "GachaCardAnchor" or anchor.Parent ~= pad then
		table.insert(billboardBad, ("Adornee is %s, not the GachaCardAnchor on the pad"):format(tostring(gui.Adornee)))
	end
	if gui.Size.X.Scale ~= 0 or gui.Size.Y.Scale ~= 0 or gui.Size.X.Offset ~= G.CardPx.X or gui.Size.Y.Offset ~= G.TopPadPx + G.CardPx.Y + G.ButtonRowPx then
		table.insert(billboardBad, ("Size %s, wanted pixels %dx%d"):format(tostring(gui.Size), G.CardPx.X, G.TopPadPx + G.CardPx.Y + G.ButtonRowPx))
	end
	if gui.SizeOffset ~= Vector2.new(0, 0.5) then
		table.insert(billboardBad, ("SizeOffset %s, wanted (0, 0.5)"):format(tostring(gui.SizeOffset)))
	end
	if gui.StudsOffset ~= Vector3.new(0, 0, 2) or gui.StudsOffsetWorldSpace ~= Vector3.zero then
		table.insert(billboardBad, ("an offset is off: StudsOffset %s (wanted 0, 0, 2), world %s (wanted 0)"):format(tostring(gui.StudsOffset), tostring(gui.StudsOffsetWorldSpace)))
	end
	if flat >= 0.1 then
		table.insert(billboardBad, ("the anchor is %.2f studs off the pad's centre (flat)"):format(flat))
	end
	if math.abs(up - G.AnchorUpStuds) > 0.05 then
		table.insert(billboardBad, ("anchor %.2f studs over the pad top, wanted %.2f"):format(up, G.AnchorUpStuds))
	end
	if gui.AlwaysOnTop or gui.LightInfluence ~= 0 or gui.MaxDistance ~= G.MaxDistance or gui.ResetOnSpawn then
		table.insert(billboardBad, ("AlwaysOnTop %s, LightInfluence %s, MaxDistance %s, ResetOnSpawn %s"):format(tostring(gui.AlwaysOnTop), tostring(gui.LightInfluence), tostring(gui.MaxDistance), tostring(gui.ResetOnSpawn)))
	end
	table.insert(lines, {
		Ok = #billboardBad == 0,
		Name = ("gacha card (%s): a pixel-size BillboardGui adorned to an Attachment straight above the pad, growing up from the anchor (pad top + 2.2 studs = the capsule ball's base, StudsOffset (0, 0, 2) toward the camera), AlwaysOnTop off, MaxDistance 150"):format(label),
		Detail = ("Size %s, SizeOffset %s, anchor %.2f studs off the pad's centre (flat), %.2f over the pad top, MaxDistance %s%s"):format(tostring(gui.Size), tostring(gui.SizeOffset), flat, up, tostring(gui.MaxDistance), if #billboardBad > 0 then " | " .. table.concat(billboardBad, "; ") else ""),
	})

	-- Each tier's drawn % is GetGachaRates at the server's luck.
	local rates = FusionConfig.GetGachaRates(serverLuck)
	local bad: { string } = {}
	local drawnTiles = 0
	for _, tier in FusionConfig.TierOrder do
		local tile = gui:FindFirstChild("Tile_" .. tier, true)
		local percent = tile and tile:FindFirstChild("Percent")
		local want = FusionConfig.FormatPercent((rates[tier] or 0) * 100) .. "%"
		if not (tile and tile:IsA("GuiObject")) then
			table.insert(bad, ("%s: no tile in the tree"):format(tier))
		elseif not (percent and percent:IsA("TextLabel")) then
			table.insert(bad, ("%s: no Percent label"):format(tier))
		else
			local problem = drawnProblem(percent, gui) or drawnProblem(tile, gui)
			if problem then
				table.insert(bad, ("%s: not drawn (%s)"):format(tier, problem))
			elseif percent.Text ~= want or percent.TextBounds.Y <= 0 then
				table.insert(bad, ("%s shows %q (text height %d), wants %q"):format(tier, percent.Text, percent.TextBounds.Y, want))
			else
				drawnTiles += 1
			end
		end
	end
	table.insert(lines, {
		Ok = #bad == 0 and drawnTiles == #FusionConfig.TierOrder,
		Name = ("gacha card (%s): every tier's drawn %% equals GetGachaRates at the server's luck (x%.2f)"):format(label, serverLuck),
		Detail = ("%d/%d tiles drawn%s"):format(drawnTiles, #FusionConfig.TierOrder, if #bad > 0 then " | " .. table.concat(bad, "; ") else ""),
	})

	-- The luck pill is up exactly when luck > x1.
	local pill = gui:FindFirstChild("LuckPill", true)
	local pillRoot = if pill then UIKit.PillRoot(pill :: any) else nil
	local pillDrawn = pillRoot ~= nil and pillRoot:IsA("GuiObject") and drawnProblem(pillRoot, gui) == nil
	table.insert(lines, {
		Ok = pillDrawn == (serverLuck > 1.0001),
		Name = ("gacha card (%s): the luck pill is drawn exactly when luck is above x1"):format(label),
		Detail = ("pill drawn %s, luck %.2f"):format(tostring(pillDrawn), serverLuck),
	})

	-- Silhouettes: an unfound tier is a SOLID black orb of the same size as the
	-- real one (no mark) and the real orb is hidden; it still shows its %; a
	-- found one the reverse.
	local found: { [string]: boolean } = {}
	for key in TycoonController.GetIndex() do
		local def = ItemConfig.GetItemById(key:match("^(.-)|") or "")
		if def then
			found[def.Tier] = true
		end
	end
	local silhouetteBad: { string } = {}
	local checkedSilhouette = 0
	for _, tier in FusionConfig.TierOrder do
		local tile = gui:FindFirstChild("Tile_" .. tier, true)
		local orb = tile and tile:FindFirstChild("Orb")
		local silhouette = tile and tile:FindFirstChild("Silhouette")
		local percent = tile and tile:FindFirstChild("Percent")
		if tile and orb and orb:IsA("GuiObject") and silhouette and silhouette:IsA("GuiObject") and percent and percent:IsA("TextLabel") then
			checkedSilhouette += 1
			local orbDrawn = drawnProblem(orb, gui) == nil
			local dark = drawnProblem(silhouette, gui) == nil
			local solid = silhouette.BackgroundColor3 == UITheme.Colors.Black and silhouette.BackgroundTransparency == 0 and #silhouette:GetChildren() == 1 -- the corner only: no "?" mark
			local sameSize = math.abs(silhouette.AbsoluteSize.X - orb.AbsoluteSize.X) < 0.5
			if dark == (found[tier] == true) or orbDrawn ~= (found[tier] == true) or percent.Text == "" or not solid or not sameSize then
				table.insert(silhouetteBad, ("%s dark=%s orb=%s found=%s text=%q solid=%s sameSize=%s"):format(tier, tostring(dark), tostring(orbDrawn), tostring(found[tier] == true), percent.Text, tostring(solid), tostring(sameSize)))
			end
		end
	end
	table.insert(lines, {
		Ok = checkedSilhouette == #FusionConfig.TierOrder and #silhouetteBad == 0,
		Name = ("gacha card (%s): an unfound tier is a solid black orb (no ?) and still shows its %%"):format(label),
		Detail = ("%d tiles checked%s"):format(checkedSilhouette, if #silhouetteBad > 0 then " | " .. table.concat(silhouetteBad, "; ") else ""),
	})

	-- The PS99 face: white paper, the title on the top edge, (i) on the top-right
	-- corner, 6 orb cells with no tile backgrounds or ribbons, ONE mutation line
	-- (each value in its colour), the coin + price on the bottom edge, and none
	-- of the old violet/gold styling.
	local styleBad: { string } = {}
	local cardFrame = card.Card :: Frame
	local paper = cardFrame:FindFirstChildOfClass("UIGradient")
	local paperStroke = cardFrame:FindFirstChildOfClass("UIStroke")
	if not paper or paper.Color.Keypoints[1].Value ~= UITheme.Colors.CardPaper or not paperStroke or paperStroke.Color ~= UITheme.Colors.CardPaperStroke then
		table.insert(styleBad, "the card is not the white paper with the light rim")
	end
	local title = cardFrame:FindFirstChild("Title")
	if not (title and title:IsA("TextLabel") and title.Text == "Gacha Pad" and title.TextSize == 26 and drawnProblem(title, gui) == nil) then
		table.insert(styleBad, "no 26 px 'Gacha Pad' title")
	elseif math.abs((title.AbsolutePosition.Y + title.AbsoluteSize.Y / 2) - cardFrame.AbsolutePosition.Y) > 1 then
		table.insert(styleBad, ("the title is not centred on the card's top edge (%.1f px off)"):format((title.AbsolutePosition.Y + title.AbsoluteSize.Y / 2) - cardFrame.AbsolutePosition.Y))
	end
	local info = cardFrame:FindFirstChild("Info")
	local infoHit = cardFrame:FindFirstChild("InfoHit")
	if not (info and info:IsA("GuiObject") and infoHit and infoHit:IsA("GuiObject") and drawnProblem(info, gui) == nil) then
		table.insert(styleBad, "no (i)")
	elseif math.abs((info.AbsolutePosition.Y + info.AbsoluteSize.Y / 2) - cardFrame.AbsolutePosition.Y) > 1 or infoHit.AbsoluteSize.X < 43.5 then
		table.insert(styleBad, ("the (i) is off the top edge or its hit area is %.0f px"):format(infoHit.AbsoluteSize.X))
	end
	local cells = 0
	for _, child in (cardFrame:FindFirstChild("Tiles") :: Instance):GetChildren() do
		if child.Name:sub(1, 5) == "Tile_" then
			cells += 1
			if (child :: GuiObject).BackgroundTransparency ~= 1 then
				table.insert(styleBad, child.Name .. " has a tile background")
			end
		end
	end
	if cells ~= #FusionConfig.TierOrder then
		table.insert(styleBad, ("%d orb cells"):format(cells))
	end
	if gui:FindFirstChild("Ribbon", true) or gui:FindFirstChild("Header", true) or gui:FindFirstChild("Mutations", true) or gui:FindFirstChild("Sparkle", true) then
		table.insert(styleBad, "old ribbon / header / chips / sparkle instances are still there")
	end
	local line = cardFrame:FindFirstChild("MutationLine")
	local rows = FusionConfig.GetGachaOddsRows(serverLuck, require(ReplicatedStorage.Shared.Modules.EventState).GetOddsEvent())
	if not (line and line:IsA("TextLabel") and drawnProblem(line, gui) == nil and line.RichText and line.TextSize <= 12) then
		table.insert(styleBad, "no mutation line")
	else
		for _, row in rows.Mutations do
			if not line.Text:find(row.Text, 1, true) then
				table.insert(styleBad, ("the mutation line lacks %s %s"):format(row.Mutation, row.Text))
			end
		end
		if #rows.Mutations == 0 then
			table.insert(styleBad, "no mutation odds to show")
		end
		if line.AbsolutePosition.Y + line.AbsoluteSize.Y > cardFrame.AbsolutePosition.Y + cardFrame.AbsoluteSize.Y + 0.5 then
			table.insert(styleBad, "the mutation line hangs below the card")
		end
	end
	local price = cardFrame:FindFirstChild("Price", true)
	local coin = cardFrame:FindFirstChild("Coin", true)
	if not (price and price:IsA("TextLabel") and coin and coin:IsA("GuiObject") and drawnProblem(price, gui) == nil and drawnProblem(coin, gui) == nil and price.TextSize == 24) then
		table.insert(styleBad, "no coin + 24 px price")
	else
		local free = TycoonController.GetTutorial().FreePulls > 0
		local wantPrice = if free then "FREE" else require(ReplicatedStorage.Shared.Modules.NumberFormat).Money(require(ReplicatedStorage.Shared.Config.TycoonConfig).GetGachaPullCost(TycoonController.GetGachaPulls()))
		if price.Text ~= wantPrice then
			table.insert(styleBad, ("price shows %q, wanted %q"):format(price.Text, wantPrice))
		end
		local edge = cardFrame.AbsolutePosition.Y + cardFrame.AbsoluteSize.Y
		if math.abs((price.AbsolutePosition.Y + price.AbsoluteSize.Y / 2) - edge) > 2 then
			table.insert(styleBad, ("the price is not centred on the bottom edge (%.1f px off)"):format((price.AbsolutePosition.Y + price.AbsoluteSize.Y / 2) - edge))
		end
	end
	table.insert(lines, {
		Ok = #styleBad == 0,
		Name = ("gacha card (%s): the PS99 face: white paper, title and (i) on the top edge, 6 bare orb cells, one coloured mutation line, coin + price on the bottom edge"):format(label),
		Detail = if #styleBad > 0 then table.concat(styleBad, "; ") else ("%d cells, price %q, mutation line %q"):format(cells, if price and price:IsA("TextLabel") then price.Text else "?", if line and line:IsA("TextLabel") then line.Text:gsub("<[^>]+>", "") else "?"),
	})

	-- The (i) panel: per-orb % sum to the tier %.
	Board.OpenPanel()
	task.wait(0.45)
	local coveredCard = Board.GetCard()
	table.insert(lines, {
		Ok = coveredCard ~= nil and not coveredCard.Shown and not coveredCard.Open,
		Name = ("gacha card (%s): while the (i) panel (a modal) is open the card is hidden"):format(label),
		Detail = ("shown %s, open %s"):format(tostring(coveredCard and coveredCard.Shown), tostring(coveredCard and coveredCard.Open)),
	})
	local panelLines = Board.GetPanelLines()
	local sumBad = {}
	for _, tier in FusionConfig.TierOrder do
		local entry = panelLines[tier]
		local sum = 0
		if entry then
			for _, value in entry.Orbs do
				sum += value
			end
		end
		local want = (rates[tier] or 0) * 100
		if not entry or #entry.Orbs == 0 or math.abs(sum - want) > math.max(1e-9, want * 1e-9) or math.abs(entry.Total - want) > math.max(1e-9, want * 1e-9) then
			table.insert(sumBad, ("%s orbs sum %.6f, tier %.6f, %d orb lines"):format(tier, sum, want, if entry then #entry.Orbs else 0))
		end
	end
	Board.ClosePanel()
	local reopened = waitForCard(true, 2)
	table.insert(lines, {
		Ok = reopened ~= nil and reopened.Shown and reopened.Pop.Scale >= 0.999,
		Name = ("gacha card (%s): it comes back after the panel closes"):format(label),
		Detail = ("shown %s, PopScale %.2f"):format(tostring(reopened and reopened.Shown), if reopened then reopened.Pop.Scale else 0),
	})
	table.insert(lines, {
		Ok = #sumBad == 0,
		Name = ("gacha card (%s): the (i) panel's per-orb %% sum to each tier's %%"):format(label),
		Detail = if #sumBad > 0 then table.concat(sumBad, "; ") else "all tiers add up",
	})
	return lines
end

-- The key bar under the card (character on the pad): 3 buttons E / R / T,
-- each >= 44 px even at the phone's 0.8, drawn (read from the tree), E R T
-- bound through ContextActionService, text fits. (Placement is
-- probeGachaPlace / probeGachaPlan.)
local function probeGachaButtons(): { ProbeLine }
	local lines: { ProbeLine } = {}
	local Board = require(script.Parent.GachaBoardController) :: any
	local card = waitForCard(true, 3)
	if not card then
		return { { Ok = false, Name = "gacha card: the key bar", Detail = "no card" } }
	end
	local gui = card.Billboard :: BillboardGui
	RunService.Heartbeat:Wait()
	task.wait(0.2)
	local bar = Board.GetKeyBar()
	local parts: { string } = {}
	local drawn, small = 0, 0
	local expected = { Pull = "E", Multi = "R", Auto = "T" }
	local captions = { Pull = "Pull", Multi = "×10", Auto = if Board.IsAutoOn() then "Auto ×10 ON" else "Auto ×10" }
	local captionBad: { string } = {}
	local sides, centre = {}, 0
	if bar then
		for _, entry in bar.Buttons do
			if entry.Caption.Text ~= captions[entry.Id] then
				table.insert(captionBad, ("%s caption %q, wanted %q"):format(entry.Id, entry.Caption.Text, captions[entry.Id]))
			end
			if entry.Id == "Multi" then
				centre = entry.Button.AbsoluteSize.X
			else
				table.insert(sides, entry.Button.AbsoluteSize.X)
			end
		end
		for _, entry in bar.Buttons do
			local round = entry.Button :: GuiObject
			local problem = drawnProblem(round, gui)
			local size = round.AbsoluteSize
			table.insert(parts, ("%s[%s] %dx%d visible=%s%s"):format(entry.Id, expected[entry.Id] or "?", size.X, size.Y, tostring(problem == nil), if problem then " (" .. problem .. ")" else ""))
			if problem == nil then
				drawn += 1
				-- A phone shrinks the billboard by its UIScale; the tap target is
				-- measured at that scale.
				if size.X < 43.5 or size.Y < 43.5 then
					small += 1
				end
			end
		end
	end
	table.insert(lines, {
		Ok = bar ~= nil and drawn == 3 and small == 0 and #captionBad == 0 and #sides == 2 and centre > sides[1] and centre > sides[2],
		Name = "gacha card: the key bar shows 3 round buttons (E Pull, R x10 bigger in the centre, T Auto), each drawn and >= 44 px",
		Detail = if bar then table.concat(parts, "; ") .. (if #captionBad > 0 then " | " .. table.concat(captionBad, "; ") else "") .. (if #sides == 2 then (" | centre %.1f px, sides %.1f / %.1f"):format(centre, sides[1], sides[2]) else "") else "no key bar",
	})
	local bound = Board.GetBoundKeys()
	table.sort(bound)
	table.insert(lines, {
		Ok = table.concat(bound, ",") == "E,R,T",
		Name = "gacha card: with the card open E, R and T are bound (ContextActionService)",
		Detail = ("bound [%s]"):format(table.concat(bound, ", ")),
	})

	-- Text fits (what is drawn).
	local unfit, checked = {}, 0
	for _, text in gui:GetDescendants() do
		if (text:IsA("TextLabel") or text:IsA("TextButton")) and text.Text ~= "" and drawnProblem(text, gui) == nil then
			checked += 1
			if not text.TextFits then
				table.insert(unfit, text.Name .. " " .. text.Text:sub(1, 24))
			end
		end
	end
	table.insert(lines, {
		Ok = checked > 0 and #unfit == 0,
		Name = ("gacha card: text fits (%d labels)"):format(checked),
		Detail = if #unfit > 0 then table.concat(unfit, "; ") else ("%d labels measured"):format(checked),
	})

	return lines
end

-- Where the open card is on screen. A billboard's pixels are screen pixels,
-- centred on the anchor's projection with its bottom edge on it, so the rect
-- is built from the projected anchor and PopRoot's (phone-scaled) size.
type ScreenBox = { Left: number, Top: number, Right: number, Bottom: number, AnchorZ: number }

local function cardScreenBox(card: any, camera: Camera): ScreenBox
	local anchor = camera:WorldToViewportPoint((card.Anchor :: Attachment).WorldPosition)
	local size = (card.PopRoot :: GuiObject).AbsoluteSize
	return { Left = anchor.X - size.X / 2, Top = anchor.Y - size.Y, Right = anchor.X + size.X / 2, Bottom = anchor.Y, AnchorZ = anchor.Z }
end

-- Puts the camera 12.5 studs behind the character (the default view), looking
-- at it, `back` being the horizontal direction from the character to the camera.
local function defaultCamera(camera: Camera, root: BasePart, back: Vector3, studs: number, yaw: number)
	local focus = root.Position + Vector3.new(0, 1.5, 0)
	local rotated = CFrame.Angles(0, math.rad(yaw), 0):VectorToWorldSpace(back)
	camera.CFrame = CFrame.lookAt(focus + rotated * studs + Vector3.new(0, studs * 0.24, 0), focus)
end

local function waitFrames(count: number)
	for _ = 1, count do
		RunService.RenderStepped:Wait()
	end
end

-- The position checks, for one camera. (1) THE BUG CHECK: the anchor's flat
-- (XZ) distance to the pad's centre is < 0.1 studs (the card was adorned to a
-- cylinder turned 90 degrees, so it sat ~9.8 studs sideways). (2) The card's
-- horizontal centre on screen is within 30 px of the pad's projected centre.
-- (3) With the ball in view, the capsule's projected centre (the band) is
-- inside the card's on-screen rect (card body plus button row): the card
-- covers the ball. A billboard's own AbsolutePosition is
-- local to the billboard, so the screen box comes from the anchor's projection
-- and PopRoot's (phone-scaled) size.
local function positionProblems(card: any, camera: Camera, needBallBelow: boolean): ({ string }, string)
	local pad = card.Pad :: BasePart
	local anchor = card.Anchor :: Attachment
	local box = cardScreenBox(card, camera)
	local problems: { string } = {}
	local flat = Vector2.new(anchor.WorldPosition.X - pad.Position.X, anchor.WorldPosition.Z - pad.Position.Z).Magnitude
	if flat >= 0.1 then
		table.insert(problems, ("the anchor is %.2f studs off the pad's centre"):format(flat))
	end
	if not (card.Open and card.Shown) then
		table.insert(problems, "the card is not open")
	end
	if box.AnchorZ <= 0 then
		table.insert(problems, "the anchor is behind the camera")
	end
	local padCentre = camera:WorldToViewportPoint(pad.Position)
	local centreX = (box.Left + box.Right) / 2
	if math.abs(centreX - padCentre.X) > 30 then
		table.insert(problems, ("not centred on the pad: card centre x %.0f vs the pad's %.0f"):format(centreX, padCentre.X))
	end
	local ballText = "n/a"
	if needBallBelow then
		local station = pad.Parent
		local ball = station and station:FindFirstChild("CapsuleBand", true)
		if ball and ball:IsA("BasePart") then
			local centre = camera:WorldToViewportPoint(ball.Position)
			ballText = ("%.0f,%.0f"):format(centre.X, centre.Y)
			if not (centre.X >= box.Left and centre.X <= box.Right and centre.Y >= box.Top and centre.Y <= box.Bottom) then
				table.insert(problems, ("the card does not cover the ball: its centre (%.0f, %.0f) is outside the card (x %.0f-%.0f, y %.0f-%.0f)"):format(centre.X, centre.Y, box.Left, box.Right, box.Top, box.Bottom))
			end
		else
			table.insert(problems, "no CapsuleBand part on the station")
		end
	end
	return problems, ("flat %.3f studs, card x %.0f-%.0f y %.0f-%.0f, pad centre x %.0f, capsule centre %s"):format(flat, box.Left, box.Right, box.Top, box.Bottom, padCentre.X, ballText)
end

-- Approach: the server stands the character 8 studs in front of the pad on
-- the walkway side. At the default camera (12.5 behind, looking along the
-- approach) and again with the camera straight above the pad (top-down), the
-- position checks above hold; the ball check at the approach view (the
-- top-down view hides the height). Run for each HUD layout
-- (UIKit.SetForcedPhone); the Studio window size is what it is.
local function probeGachaApproach(phone: boolean): { ProbeLine }
	local layout = if phone then "phone layout" else "desktop layout"
	UIKit.SetForcedPhone(phone)
	task.wait(0.4)
	local card = waitForCard(true, 3)
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not card or not camera or not root or not root:IsA("BasePart") then
		UIKit.SetForcedPhone(nil)
		return { { Ok = false, Name = ("gacha card (%s): approach"):format(layout), Detail = "no card, camera or character" } }
	end
	local pad = card.Pad :: BasePart
	local savedType, savedCFrame = camera.CameraType, camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	local toPad = Vector3.new(pad.Position.X - root.Position.X, 0, pad.Position.Z - root.Position.Z)
	local distance = toPad.Magnitude
	defaultCamera(camera, root, -toPad.Unit, 12.5, 0)
	waitFrames(6)
	local approachProblems, approachDetail = positionProblems(card, camera, true)
	camera.CFrame = CFrame.lookAt(pad.Position + Vector3.new(0, 40, 0), pad.Position, Vector3.new(0, 0, -1))
	waitFrames(6)
	local topProblems, topDetail = positionProblems(card, camera, false)
	camera.CameraType = savedType
	camera.CFrame = savedCFrame
	UIKit.SetForcedPhone(nil)
	local window = ("%d x %d window"):format(camera.ViewportSize.X, camera.ViewportSize.Y)
	return {
		{
			Ok = #approachProblems == 0,
			Name = ("gacha card (%s, %s): 8 studs in front of the pad the card is centred on the pad and covers the capsule ball"):format(layout, window),
			Detail = ("%.1f studs from the pad; %s%s"):format(distance, approachDetail, if #approachProblems > 0 then " | " .. table.concat(approachProblems, "; ") else ""),
		},
		{
			Ok = #topProblems == 0,
			Name = ("gacha card (%s, %s): with the camera straight above the pad the card is centred on it"):format(layout, window),
			Detail = ("%s%s"):format(topDetail, if #topProblems > 0 then " | " .. table.concat(topProblems, "; ") else ""),
		},
	}
end

-- On the pad: the anchor (the Attachment's world position) NEVER changes: not
-- over 4 camera yaws at a fixed zoom, not over the zoom range (6 / 12.5 / 40
-- studs), and no billboard offset is ever written.
local function probeGachaOnPad(phone: boolean): { ProbeLine }
	local layout = if phone then "phone layout" else "desktop layout"
	UIKit.SetForcedPhone(phone)
	task.wait(0.4)
	local card = waitForCard(true, 3)
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not card or not camera or not root or not root:IsA("BasePart") then
		UIKit.SetForcedPhone(nil)
		return { { Ok = false, Name = ("gacha card (%s): on the pad"):format(layout), Detail = "no card, camera or character" } }
	end
	local gui = card.Billboard :: BillboardGui
	local anchor = card.Anchor :: Attachment
	local want = anchor.WorldPosition
	local savedType, savedCFrame = camera.CameraType, camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	local back = Vector3.new(1, 0, 0)
	local moved: { string } = {}
	local function check(what: string)
		if (anchor.WorldPosition - want).Magnitude > 1e-3 or gui.StudsOffset ~= Vector3.new(0, 0, 2) or gui.StudsOffsetWorldSpace ~= Vector3.zero then
			table.insert(moved, ("%s: anchor %s, StudsOffset %s, world %s"):format(what, tostring(anchor.WorldPosition), tostring(gui.StudsOffset), tostring(gui.StudsOffsetWorldSpace)))
		end
	end
	check("start")
	for _, yaw in { 0, 90, 180, 270 } do
		defaultCamera(camera, root, back, 12.5, yaw)
		waitFrames(6)
		check("yaw " .. yaw)
	end
	for _, studs in { 6, 12.5, 40 } do
		defaultCamera(camera, root, back, studs, 0)
		waitFrames(8)
		check(("zoom %.1f"):format(studs))
	end
	camera.CameraType = savedType
	camera.CFrame = savedCFrame
	UIKit.SetForcedPhone(nil)
	return {
		{
			Ok = #moved == 0,
			Name = ("gacha card (%s): the anchor never changes while the camera turns (4 yaws) or zooms (6 / 12.5 / 40 studs)"):format(layout),
			Detail = ("anchor %s%s"):format(tostring(want), if #moved > 0 then " | changed: " .. table.concat(moved, "; ") else ""),
		},
	}
end

-- What the open card covers steps aside: the pad's small GACHA label is off
-- and your VIP head chip (a stand-in VipTag is made if you have none) is off;
-- a modal covering the card gives the chip back, and it is hidden again when
-- the card returns.
local function probeGachaCovers(): { ProbeLine }
	local Board = require(script.Parent.GachaBoardController) :: any
	local card = waitForCard(true, 3)
	local character = localPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if not card or not head then
		return { { Ok = false, Name = "gacha card: it hides the GACHA label and your VIP chip", Detail = "no card or no head" } }
	end
	local made = false
	local tag = head:FindFirstChild("VipTag")
	if not tag then
		made = true
		tag = Instance.new("BillboardGui")
		tag.Name = "VipTag"
		tag.Size = UDim2.fromScale(3.6, 1.1)
		tag.Parent = head
	end
	local chip = tag :: BillboardGui
	chip.Enabled = true
	Board.RefreshNow()
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	local label = card.Label
	local labelOn = label ~= nil and label:IsA("BillboardGui") and label.Enabled
	local function ballState(): (boolean, boolean, string)
		local station = (card.Pad :: BasePart).Parent
		local hidden, shown, parts = true, true, {}
		for _, name in { "CapsuleTop", "CapsuleBottom", "CapsuleBand" } do
			local part = station and station:FindFirstChild(name, true)
			if part and part:IsA("BasePart") then
				table.insert(parts, ("%s %d"):format(name, part.LocalTransparencyModifier))
				hidden = hidden and part.LocalTransparencyModifier == 1
				shown = shown and part.LocalTransparencyModifier == 0
			else
				table.insert(parts, name .. " missing")
				hidden, shown = false, false
			end
		end
		return hidden, shown, table.concat(parts, ", ")
	end
	local openHidden, _, openText = ballState()
	local lines: { ProbeLine } = {
		{
			Ok = openHidden,
			Name = "gacha card: while it is open the capsule ball is hidden (LocalTransparencyModifier 1 on CapsuleTop / CapsuleBottom / CapsuleBand)",
			Detail = openText,
		},
		{
			Ok = not labelOn and not chip.Enabled,
			Name = "gacha card: while it is open the pad's GACHA label and your VIP chip are hidden",
			Detail = ("label Enabled %s, VIP chip Enabled %s"):format(tostring(labelOn), tostring(chip.Enabled)),
		},
	}
	Board.OpenPanel()
	task.wait(0.45)
	local _, closedShown, closedText = ballState()
	table.insert(lines, {
		Ok = closedShown,
		Name = "gacha card: after it closes (a modal covers it) the ball is shown again (LocalTransparencyModifier 0)",
		Detail = closedText,
	})
	table.insert(lines, {
		Ok = chip.Enabled,
		Name = "gacha card: when it closes (a modal covers it) the VIP chip comes back",
		Detail = ("VIP chip Enabled %s"):format(tostring(chip.Enabled)),
	})
	Board.ClosePanel()
	waitForCard(true, 2)
	Board.RefreshNow()
	RunService.Heartbeat:Wait()
	table.insert(lines, {
		Ok = not chip.Enabled,
		Name = "gacha card: when it returns the VIP chip is hidden again",
		Detail = ("VIP chip Enabled %s"):format(tostring(chip.Enabled)),
	})
	Board.OpenPanel()
	task.wait(0.45)
	Board.ClosePanel()
	if made then
		chip:Destroy()
	else
		chip.Enabled = true
	end
	return lines
end

-- The character is 25 studs away: the card is closed and the small GACHA
-- label (name + price) shows; E / R / T are unbound.
local function probeGachaFar(): { ProbeLine }
	local card = waitForCard(false, 3)
	if not card then
		return { { Ok = false, Name = "gacha card: far away it is hidden and the small label shows", Detail = "no card" } }
	end
	task.wait(0.15)
	local label = card.Label
	local title = label and label:FindFirstChild("Title")
	local pillText = label and label:FindFirstChild("Text", true)
	local labelOn = label ~= nil and label:IsA("BillboardGui") and label.Enabled
	local titleText = if title and title:IsA("TextLabel") then title.Text else "?"
	local price = if pillText and pillText:IsA("TextLabel") then pillText.Text else "?"
	local Board = require(script.Parent.GachaBoardController) :: any
	local bound = Board.GetBoundKeys()
	return {
		{
			Ok = not card.Shown and labelOn and titleText == "GACHA" and price ~= "" and price ~= "?",
			Name = "gacha card: 25 studs away the card is closed and the small GACHA label shows",
			Detail = ("card shown %s, PopScale %.2f, label Enabled %s, title %q, price %q"):format(tostring(card.Shown), card.Pop.Scale, tostring(labelOn), titleText, price),
		},
		{
			Ok = #bound == 0,
			Name = "gacha card: 25 studs away E, R and T are unbound",
			Detail = ("still bound [%s]"):format(table.concat(bound, ", ")),
		},
	}
end

-- Back on the pad: it opens again.
local function probeGachaBack(): { ProbeLine }
	local card = waitForCard(true, 3)
	if not card then
		return { { Ok = false, Name = "gacha card: walking back opens it again", Detail = "no card" } }
	end
	local Board = require(script.Parent.GachaBoardController) :: any
	local bound = Board.GetBoundKeys()
	table.sort(bound)
	return {
		{
			Ok = card.Shown and card.Pop.Scale >= 0.999,
			Name = "gacha card: walking back to the pad opens it again (shown, UIScale 1)",
			Detail = ("shown %s, PopScale %.3f, label Enabled %s"):format(tostring(card.Shown), card.Pop.Scale, tostring(card.Label and (card.Label :: any).Enabled)),
		},
		{
			Ok = table.concat(bound, ",") == "E,R,T",
			Name = "gacha card: walking back to the pad binds E, R and T again",
			Detail = ("bound [%s]"):format(table.concat(bound, ", ")),
		},
	}
end

-- "14:55" / "1:02:03" -> seconds (nil when it is not a timer).
local function timerSeconds(text: string): number?
	local parts = string.split(text, ":")
	if #parts < 2 or #parts > 3 then
		return nil
	end
	local total = 0
	for _, part in parts do
		local value = tonumber(part)
		if not value then
			return nil
		end
		total = total * 60 + value
	end
	return total
end

-- The effects tray: with a Luck Potion, Speed Boots and Safe Fusion tokens
-- granted by the server, a luck circle with a timer, a Speed Boots circle
-- with a timer and a Safe Fusion circle with "×N" are up in the BOTTOM-LEFT
-- quarter of the screen, their timers read the live seconds, tap targets are
-- >= 44 px on screen, nothing overlaps a HUD rect, and the old effect pills
-- are gone. Measured at both layouts.
local function probeEffectsTray(tokens: number): { ProbeLine }
	local EffectsTray = require(UI.EffectsTray) :: any
	local hud = require(script.Parent.HudController) :: any
	local tycoon = require(script.Parent.TycoonController) :: any
	local lines: { ProbeLine } = {}
	for _, phone in { false, true } do
		UIKit.SetForcedPhone(phone)
		task.wait(0.4)
		EffectsTray.Refresh()
		task.wait(0.3)
		local label = if phone then "phone" else "desktop"
		local byId: { [string]: any } = {}
		for _, view in EffectsTray.GetCells() do
			byId[view.Id] = view
		end
		local luck, safe, boots = byId.Luck, byId.SafeFusion, byId.SpeedBoots
		local luckOk = luck ~= nil and luck.Timer:match("^%d+:%d%d") ~= nil and luck.Badge == "×2"
		local safeOk = safe ~= nil and safe.Badge == ("×%d"):format(tokens) and safe.Timer == ""
		table.insert(lines, {
			Ok = luckOk and safeOk,
			Name = ("effects tray (%s): a luck circle with a timer and a Safe Fusion circle with ×%d"):format(label, tokens),
			Detail = ("luck %s, safe %s"):format(
				if luck then ("timer '%s' badge '%s'"):format(luck.Timer, tostring(luck.Badge)) else "missing",
				if safe then ("timer '%s' badge '%s'"):format(safe.Timer, tostring(safe.Badge)) else "missing"
			),
		})
		-- Bottom-left quarter of the window, and timers that read the live seconds.
		local camera = workspace.CurrentCamera
		local window = if camera then camera.ViewportSize else Vector2.new(1366, 768)
		local inset = GuiService:GetGuiInset().Y
		local outside: { string } = {}
		for id, entry in byId do
			local centre = entry.Position + entry.Size / 2 - Vector2.new(0, inset)
			if centre.X >= window.X / 2 or centre.Y <= window.Y / 2 then
				table.insert(outside, ("%s at %d,%d"):format(id, centre.X, centre.Y))
			end
		end
		table.sort(outside)
		table.insert(lines, {
			Ok = next(byId) ~= nil and #outside == 0,
			Name = ("effects tray (%s, window %d × %d): in the bottom-left quarter"):format(label, window.X, window.Y),
			Detail = table.concat(outside, ", "),
		})
		local liveOk = true
		local liveDetail: { string } = {}
		local checks: { { Id: string, Want: number } } = {
			{ Id = "Luck", Want = tycoon.GetBoostSecondsLeft("Luck") },
			{ Id = "SpeedBoots", Want = math.max(0, ((tycoon.GetQuests() or {}).SpeedBootsUntil or 0) - workspace:GetServerTimeNow()) },
		}
		for _, check in checks do
			local entry = byId[check.Id]
			local shown = if entry then timerSeconds(entry.Timer) else nil
			local good = shown ~= nil and check.Want > 0 and math.abs((shown :: number) - check.Want) <= 3
			liveOk = liveOk and good
			table.insert(liveDetail, ("%s shows %s, live %ds"):format(check.Id, if entry then entry.Timer else "missing", check.Want))
		end
		table.insert(lines, {
			Ok = liveOk and boots ~= nil,
			Name = ("effects tray (%s): the Luck and Speed Boots timers read the live seconds"):format(label),
			Detail = table.concat(liveDetail, "; "),
		})
		-- >= 44 screen px tap targets (the cell, 48-64 px icons, x 0.8 on a phone).
		local smallest = math.huge
		for _, view in byId do
			smallest = math.min(smallest, view.HitSize.X, view.HitSize.Y)
		end
		table.insert(lines, {
			Ok = smallest >= UITheme.MinTapSize,
			Name = ("effects tray (%s): every tap target is at least %d px"):format(label, UITheme.MinTapSize),
			Detail = ("smallest %d px"):format(math.floor(smallest)),
		})
		-- Cartoon sticker badges (no product photos): the glyph, an effect
		-- layer behind it, and the glyph sized with the circle.
		local wantGlyphs: { [string]: string } = { Luck = "🍀", SpeedBoots = "👟", SafeFusion = "🛡" }
		local stickerBad: { string } = {}
		for id, glyph in wantGlyphs do
			local view = byId[id]
			if not view then
				table.insert(stickerBad, id .. " missing")
			elseif view.Glyph ~= glyph or view.FxCount < 1 or view.GlyphSize < 24 then
				table.insert(stickerBad, ("%s glyph '%s' size %d, %d effect parts"):format(id, view.Glyph, view.GlyphSize, view.FxCount))
			end
		end
		table.sort(stickerBad)
		table.insert(lines, {
			Ok = #stickerBad == 0,
			Name = ("effects tray (%s): cartoon badges with a glyph and an effect layer"):format(label),
			Detail = table.concat(stickerBad, ", "),
		})
		-- Tooltip: hover shows the name, the Plain line and the time; leaving hides it.
		EffectsTray.TestHover("Luck", true)
		task.wait(0.2)
		local tip = EffectsTray.GetTooltip()
		local plainWant = ("Rare orbs %d× more likely"):format(ShopConfig.LuckPotionMultiplier)
		local viewport = if camera then camera.ViewportSize else Vector2.new(1366, 768)
		local luckCell = byId.Luck
		local tipProblems: { string } = {}
		if not tip.Visible then
			table.insert(tipProblems, "not visible after MouseEnter")
		end
		if tip.Name == "" then
			table.insert(tipProblems, "no name")
		end
		if tip.Plain ~= plainWant then
			table.insert(tipProblems, ("plain '%s', want '%s'"):format(tip.Plain, plainWant))
		end
		if not tip.Time:match("%d+:%d%d") then
			table.insert(tipProblems, ("time '%s'"):format(tip.Time))
		end
		if tip.Size.X / tip.Scale > 220 + 1 then
			table.insert(tipProblems, ("%d px wide (max 220)"):format(tip.Size.X / tip.Scale))
		end
		if tip.Position.X < -1 or tip.Position.X + tip.Size.X > viewport.X + 1 then
			table.insert(tipProblems, ("off screen: x %d-%d of %d"):format(tip.Position.X, tip.Position.X + tip.Size.X, viewport.X))
		end
		-- Opens to the RIGHT of the icon, centred on it (it only falls back to
		-- above when there is no room on the right).
		if luckCell and tip.Position.X < luckCell.Position.X + luckCell.Size.X - 1 and tip.Position.Y + tip.Size.Y > luckCell.Position.Y - inset + 1 then
			table.insert(tipProblems, "neither right of nor above the icon")
		end
		-- Nothing covers it: no HUD rect (left column, deal tile, bottom row)
		-- or the weapon bar under it, and its layer is above the HUD's.
		local tipRect = { Position = tip.Position + Vector2.new(0, inset), Size = tip.Size }
		local covered: { string } = {}
		local tipObstacles: { [string]: any } = hud.GetObstacleRects()
		local weaponBar = (require(script.Parent.CombatController) :: any).GetBarRect()
		if weaponBar then
			tipObstacles.WeaponBar = weaponBar
		end
		for name, rect in tipObstacles do
			local ox = math.min(tipRect.Position.X + tipRect.Size.X, rect.Position.X + rect.Size.X) - math.max(tipRect.Position.X, rect.Position.X)
			local oy = math.min(tipRect.Position.Y + tipRect.Size.Y, rect.Position.Y + rect.Size.Y) - math.max(tipRect.Position.Y, rect.Position.Y)
			if ox > 1 and oy > 1 then
				table.insert(covered, name)
			end
		end
		table.sort(covered)
		if #covered > 0 then
			table.insert(tipProblems, "overlaps " .. table.concat(covered, ", "))
		end
		local hudGuiForOrder = localPlayer:WaitForChild("PlayerGui"):FindFirstChild("Hud")
		if hudGuiForOrder and hudGuiForOrder:IsA("ScreenGui") and EffectsTray.GetTooltipDisplayOrder() <= hudGuiForOrder.DisplayOrder then
			table.insert(tipProblems, ("layer %d is not above the HUD's %d"):format(EffectsTray.GetTooltipDisplayOrder(), hudGuiForOrder.DisplayOrder))
		end
		table.insert(lines, {
			Ok = #tipProblems == 0,
			Name = ("effects tray (%s): hovering the Luck icon shows its name, what it does and the time left"):format(label),
			Detail = table.concat(tipProblems, "; "),
		})
		EffectsTray.TestHover("Luck", false)
		task.wait(0.1)
		table.insert(lines, {
			Ok = not EffectsTray.GetTooltip().Visible,
			Name = ("effects tray (%s): leaving the icon hides the tooltip"):format(label),
			Detail = "",
		})
		-- A tap shows it too and it closes by itself after 3 s.
		EffectsTray.TestTap("SafeFusion")
		task.wait(0.2)
		local tapTip = EffectsTray.GetTooltip()
		local tapOk = tapTip.Visible and tapTip.Time == ("×%d left"):format(tokens)
		task.wait(3.2)
		table.insert(lines, {
			Ok = tapOk and not EffectsTray.GetTooltip().Visible,
			Name = ("effects tray (%s): a tap shows the tooltip (×N left) and it closes after 3 s"):format(label),
			Detail = ("shown '%s' %s"):format(tapTip.Time, if tapTip.Visible then "visible" else "NOT visible"),
		})
		-- No overlap with any HUD rect or the weapon bar.
		local obstacles = hud.GetObstacleRects()
		local overlaps: { string } = {}
		for id, view in byId do
			for name, rect in obstacles do
				local ox = math.min(view.Position.X + view.Size.X, rect.Position.X + rect.Size.X) - math.max(view.Position.X, rect.Position.X)
				local oy = math.min(view.Position.Y + view.Size.Y, rect.Position.Y + rect.Size.Y) - math.max(view.Position.Y, rect.Position.Y)
				if ox > 1 and oy > 1 then
					table.insert(overlaps, id .. "/" .. name)
				end
			end
		end
		table.sort(overlaps)
		table.insert(lines, {
			Ok = #overlaps == 0,
			Name = ("effects tray (%s): no overlap with any HUD rect"):format(label),
			Detail = table.concat(overlaps, ", "),
		})
	end
	UIKit.SetForcedPhone(nil)
	-- The old pills are gone from the SHOP row and the phone status stack.
	local hudGui = localPlayer:WaitForChild("PlayerGui"):FindFirstChild("Hud")
	local leftovers: { string } = {}
	if hudGui then
		for _, name in { "IncomeBoost", "LuckBoost", "Overclock", "Effects" } do
			if hudGui:FindFirstChild(name, true) then
				table.insert(leftovers, name)
			end
		end
	end
	table.insert(lines, {
		Ok = #leftovers == 0,
		Name = "effects tray: the old effect pills are gone from the HUD",
		Detail = table.concat(leftovers, ", "),
	})
	return lines
end

-- The quests badge (the server completes the "Fuse a Mythic" chain step first):
-- the QUESTS button shows a red "!" for it.
local function probeQuestBadge(): { ProbeLine }
	local hud = require(script.Parent.HudController) :: any
	task.wait(0.3)
	local visible, text = hud.GetQuestsBadge()
	return {
		{
			Ok = visible and text == "!",
			Name = "quests: the QUESTS button shows a red ! while the lab chain step is done and unclaimed",
			Detail = ("badge %s, text '%s'"):format(if visible then "visible" else "hidden", text),
		},
	}
end

-- AUTO-FILL on `tier` with an empty chamber: which orbs it selects and the
-- toast it shows. `expect` = "Fill" (n orbs of one stack + the "Filled with"
-- toast) or "None" (0 orbs + the "Not enough" toast).
local function probeAutoFillMutated(tier: string, expect: string, count: number): { ProbeLine }
	local panel = require(UI.FusePanel) :: any
	local toasts = require(script.Parent.ToastController) :: any
	task.wait(0.4) -- the inventory sync
	panel.Open()
	task.wait(0.2)
	local picked = panel.SelfTestAutoFill(tier)
	local toast = toasts.GetLastText()
	panel.Close()
	local sameStack = #picked > 0
	for _, item in picked do
		if not MutationConfig.SameStack(item.Mutation, item.EventMutations, picked[1].Mutation, picked[1].EventMutations) then
			sameStack = false
		end
	end
	local detail = ("%d selected, toast '%s'"):format(#picked, toast)
	if expect == "Fill" then
		return {
			{
				Ok = #picked == count and sameStack and toast:find("Filled with", 1, true) ~= nil,
				Name = "fuse: AUTO-FILL with only mutated orbs left fills with the largest same-stack group and says so",
				Detail = detail,
			},
		}
	end
	return {
		{
			Ok = #picked == 0 and toast == "Not enough matching orbs to fuse",
			Name = "fuse: AUTO-FILL with no mutated pair selects nothing and shows the 'not enough' toast",
			Detail = detail,
		},
	}
end

-- The knockback checks run on the TARGET's client (the one that simulates
-- its character): where its own root is, and whether it is standing again.
local function probeRootPos(): ({ ProbeLine }, { [string]: any })
	local root = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return { { Ok = false, Name = "combat launch: the target client reports its root", Detail = "no HumanoidRootPart on the target's client" } }, {}
	end
	return {}, { Pos = root.Position }
end

local function probeGetUp(): { ProbeLine }
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return { { Ok = false, Name = "combat launch: the target is standing again (target client)", Detail = "no character on the target's client" } }
	end
	local movers = 0
	for _, descendant in character:GetDescendants() do
		if descendant.Name == "KnockbackMover" or descendant.Name == "KnockbackSpin" then
			movers += 1
		end
	end
	local state = humanoid:GetState()
	return {
		{
			Ok = state ~= Enum.HumanoidStateType.Physics and not humanoid.PlatformStand and movers == 0,
			Name = "combat launch: after the get-up the target client is standing (state not Physics, PlatformStand off, no KnockbackMover)",
			Detail = ("state %s, PlatformStand %s, movers left %d"):format(state.Name, tostring(humanoid.PlatformStand), movers),
		},
	}
end

-- A real click: CombatController.Use is the function a tool's Activated runs.
-- (The test asks for it on the ATTACKER's client; the server then runs the
-- whole chain: RequestHit, the box, the verdict, ApplyHit.)
local function probeSwing(weaponId: string): { ProbeLine }
	local CombatController = require(script.Parent.CombatController) :: any
	CombatController.ResetLocalCooldowns()
	local sent, why = CombatController.Use(weaponId)
	return {
		{
			Ok = sent == true,
			Name = ("combat swing (%s): a click on the attacker's client swings and sends RequestHit"):format(weaponId),
			Detail = if sent then "sent" else ("not sent: %s"):format(tostring(why)),
		},
	}
end

local function probeTutorial(payload: any)
	local lines: { ProbeLine } = {}
	local reportData: { [string]: any }? = nil
	local ok, result = pcall(function()
		if payload.Kind == "RootPos" then
			local rootLines, rootData = probeRootPos()
			reportData = rootData
			return rootLines
		elseif payload.Kind == "GetUp" then
			return probeGetUp()
		elseif payload.Kind == "Swing" then
			return probeSwing(tostring(payload.Weapon))
		elseif payload.Kind == "Step" then
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
		elseif payload.Kind == "Fallback" then
			return probeFallback()
		elseif payload.Kind == "GachaOpen" then
			return probeGachaOpen()
		elseif payload.Kind == "GachaCard" then
			return probeGachaCard(payload.Luck, tostring(payload.Label))
		elseif payload.Kind == "GachaButtons" then
			return probeGachaButtons()
		elseif payload.Kind == "GachaApproach" then
			return probeGachaApproach(payload.Phone == true)
		elseif payload.Kind == "GachaOnPad" then
			return probeGachaOnPad(payload.Phone == true)
		elseif payload.Kind == "GachaCovers" then
			return probeGachaCovers()
		elseif payload.Kind == "GachaFar" then
			return probeGachaFar()
		elseif payload.Kind == "GachaBack" then
			return probeGachaBack()
		elseif payload.Kind == "QuestBadge" then
			return probeQuestBadge()
		elseif payload.Kind == "EffectsTray" then
			return probeEffectsTray(if typeof(payload.Tokens) == "number" then payload.Tokens else 0)
		elseif payload.Kind == "AutoFillMutated" then
			return probeAutoFillMutated(tostring(payload.Tier), tostring(payload.Expect), if typeof(payload.Count) == "number" then payload.Count else 0)
		elseif payload.Kind == "AutoReset" then
			(require(script.Parent.ResultController) :: any).ResetAutoCardCount()
			return {}
		elseif payload.Kind == "AutoCards" then
			local shown = (require(script.Parent.ResultController) :: any).GetAutoCardCount()
			return {
				{
					Ok = shown == payload.Expect,
					Name = "auto pull: each x10 cycle showed the 10-pull card",
					Detail = ("%d cards shown, %s cycles ran"):format(shown, tostring(payload.Expect)),
				},
			}
		end
		return {}
	end)
	if ok then
		lines = result
	else
		table.insert(lines, { Ok = false, Name = "tutorial probe", Detail = tostring(result) })
	end
	RemoteEvents.SelfTestReport:FireServer({ Stage = "TutorialProbe", Lines = lines, Data = reportData })
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
	if typeof(payload) == "table" and payload.Only == "cards" then
		-- /selftest cards: only the card-placement checks.
		cardLines = {}
		local lines: { string } = {}
		local ok, err = pcall(function()
			testPlacedCards()
			for _, line in cardLines do
				table.insert(lines, line)
			end
			for _, line in testCardMath() do
				table.insert(lines, line)
			end
		end)
		if not ok then
			table.insert(lines, "FAIL cards: " .. tostring(err))
		end
		connection:Disconnect()
		RemoteEvents.SelfTestReport:FireServer({ Stage = "Done", Panels = lines })
		running = false
		return
	end
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
	for _, line in testDealTile() do
		table.insert(panelLines, line)
	end
	for _, line in testSkippedLines() do
		table.insert(panelLines, line)
	end
	for _, line in testPlain() do
		table.insert(panelLines, line)
	end
	for _, line in testBundleContents() do
		table.insert(panelLines, line)
	end
	for _, line in testDealCards() do
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
	for _, line in testUnlockCard() do
		table.insert(panelLines, line)
	end
	for _, line in testMusic() do
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
