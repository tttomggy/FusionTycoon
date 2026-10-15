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
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
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
	local gui = card.Gui :: ScreenGui
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
	local gui = card.Gui :: ScreenGui
	table.insert(lines, {
		Ok = card.Shown and card.Pop.Scale >= 0.999 and card.Open,
		Name = ("gacha card (%s): with the character on the pad the card is open at UIScale 1"):format(label),
		Detail = ("shown %s, PopScale %.3f, open %s, card %dx%d px, fit %.2f"):format(tostring(card.Shown), card.Pop.Scale, tostring(card.Open), card.Card.AbsoluteSize.X, card.Card.AbsoluteSize.Y, card.Fit.Scale),
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

	-- No ViewportFrame, no CanvasGroup; the only UIScales besides the gui's
	-- phone scale are the pop and the squeeze.
	local viewports, canvasGroups, scales = 0, 0, {}
	for _, descendant in gui:GetDescendants() do
		if descendant:IsA("ViewportFrame") then
			viewports += 1
		elseif descendant:IsA("CanvasGroup") then
			canvasGroups += 1
		elseif descendant:IsA("UIScale") and descendant.Name ~= "MobileScale" and descendant.Name ~= "SelectScale" then
			table.insert(scales, (descendant:GetFullName():gsub("^.-GachaCard%.", "")))
		end
	end
	local leftover = Workspace:FindFirstChild("GachaBoard", true)
	table.sort(scales)
	table.insert(lines, {
		Ok = viewports == 0 and canvasGroups == 0 and table.concat(scales, ",") == "Root.FitScale,Root.PopRoot.PopScale" and leftover == nil,
		Name = ("gacha card (%s): no ViewportFrame, no CanvasGroup, only the pop and the squeeze UIScale besides the phone one, no GachaBoard"):format(label),
		Detail = ("ViewportFrames %d, CanvasGroups %d, UIScales [%s], GachaBoard %s"):format(viewports, canvasGroups, table.concat(scales, ", "), tostring(leftover)),
	})

	-- A screen-space gui under the Gacha display order: over the HUD, under every modal.
	table.insert(lines, {
		Ok = gui.DisplayOrder == PlotLayout.Gacha.DisplayOrder and gui.DisplayOrder > 41 and not gui.ResetOnSpawn,
		Name = ("gacha card (%s): its gui sits above the HUD and the weapon bar, under every modal, and survives respawn"):format(label),
		Detail = ("DisplayOrder %d, ResetOnSpawn %s"):format(gui.DisplayOrder, tostring(gui.ResetOnSpawn)),
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

	-- Silhouettes: an unfound tier shows the black "?" orb (and the real orb is
	-- hidden) and still shows its %; a found one the reverse.
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
		local mark = silhouette and silhouette:FindFirstChild("Mark")
		local percent = tile and tile:FindFirstChild("Percent")
		if tile and orb and orb:IsA("GuiObject") and silhouette and silhouette:IsA("GuiObject") and mark and mark:IsA("GuiObject") and percent and percent:IsA("TextLabel") then
			checkedSilhouette += 1
			local orbDrawn = drawnProblem(orb, gui) == nil
			local dark = drawnProblem(silhouette, gui) == nil and drawnProblem(mark, gui) == nil
			if dark == (found[tier] == true) or orbDrawn ~= (found[tier] == true) or percent.Text == "" then
				table.insert(silhouetteBad, ("%s dark=%s orb=%s found=%s text=%q"):format(tier, tostring(dark), tostring(orbDrawn), tostring(found[tier] == true), percent.Text))
			end
		end
	end
	table.insert(lines, {
		Ok = checkedSilhouette == #FusionConfig.TierOrder and #silhouetteBad == 0,
		Name = ("gacha card (%s): an unfound tier is a black ? orb and still shows its %%"):format(label),
		Detail = ("%d tiles checked%s"):format(checkedSilhouette, if #silhouetteBad > 0 then " | " .. table.concat(silhouetteBad, "; ") else ""),
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
	local gui = card.Gui :: ScreenGui
	RunService.Heartbeat:Wait()
	task.wait(0.2)
	local bar = Board.GetKeyBar()
	local parts: { string } = {}
	local drawn, small = 0, 0
	local expected = { Pull = "E", Multi = "R", Auto = "T" }
	if bar then
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
		Ok = bar ~= nil and drawn == 3 and small == 0,
		Name = "gacha card: the key bar shows 3 buttons (E Pull, R x10, T Auto), each drawn and >= 44 px",
		Detail = if bar then table.concat(parts, "; ") else "no key bar",
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

-- Placement: the character stands on the pad and the camera is set to each of
-- 5 views in turn (close behind 6 studs, default 12.5, max zoom-out, top-down,
-- looking away from the pad). At each, the card + button row (read from the
-- instance tree) is fully inside the safe rect and overlaps no HUD rect (the
-- left column, the bottom row, the weapon bar) or the TopStack zone. Run once
-- per HUD layout (desktop, phone), live.
local function probeGachaPlace(phone: boolean): { ProbeLine }
	local lines: { ProbeLine } = {}
	local Board = require(script.Parent.GachaBoardController) :: any
	local Hud = require(script.Parent.HudController) :: any
	local CombatController = require(script.Parent.CombatController) :: any
	local TopStack = require(script.Parent.Parent.UI.TopStack) :: any
	local layout = if phone then "phone layout" else "desktop layout"
	UIKit.SetForcedPhone(phone)
	task.wait(0.4)
	local card = waitForCard(true, 3)
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not card or not camera or not root or not root:IsA("BasePart") then
		UIKit.SetForcedPhone(nil)
		return { { Ok = false, Name = ("gacha card (%s): placement"):format(layout), Detail = "no card, camera or character" } }
	end
	local pad = card.Pad :: BasePart
	local standing = pad.Position + Vector3.new(0, pad.Size.Y / 2 + 3, 0)
	root.CFrame = CFrame.new(standing)
	local savedType, savedCFrame = camera.CameraType, camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	local away = Vector3.new(1, 0, 0)
	local focus = standing + Vector3.new(0, 1.5, 0)
	local views = {
		{ Name = "close behind (6 studs)", CFrame = CFrame.lookAt(focus + away * 6 + Vector3.new(0, 2, 0), focus) },
		{ Name = "default (12.5 studs)", CFrame = CFrame.lookAt(focus + away * 12.5 + Vector3.new(0, 3, 0), focus) },
		{ Name = "max zoom-out", CFrame = CFrame.lookAt(focus + away * 126 + Vector3.new(0, 15, 0), focus) },
		{ Name = "top-down", CFrame = CFrame.lookAt(focus + Vector3.new(0, 30, 0), focus, Vector3.new(0, 0, -1)) },
		{ Name = "looking away from the pad", CFrame = CFrame.lookAt(focus + away * 12.5 + Vector3.new(0, 3, 0), focus + away * 40) },
	}
	for _, view in views do
		camera.CFrame = view.CFrame
		Board.SnapNow()
		for _ = 1, 6 do
			RunService.RenderStepped:Wait()
		end
		local inset = GuiService:GetGuiInset().Y
		local box = card.PopRoot :: GuiObject
		local left, top = box.AbsolutePosition.X, box.AbsolutePosition.Y + inset
		local right, bottom = left + box.AbsoluteSize.X, top + box.AbsoluteSize.Y
		local safe = Board.GetSafeRectScreenPx()
		local problems: { string } = {}
		if not card.Shown then
			table.insert(problems, "card not shown")
		end
		if safe then
			local tolerance = 1.5
			if left < safe.Left - tolerance or right > safe.Right + tolerance or top < safe.Top - tolerance or bottom > safe.Bottom + tolerance then
				table.insert(problems, ("outside the safe rect x %.0f-%.0f y %.0f-%.0f"):format(safe.Left, safe.Right, safe.Top, safe.Bottom))
			end
		else
			table.insert(problems, "no safe rect")
		end
		local obstacles = Hud.GetObstacleRects()
		local bar = CombatController.GetBarRect()
		if bar then
			obstacles.WeaponBar = bar
		end
		local scale = if phone then UITheme.PhoneScale else 1
		obstacles.TopStack = { Position = Vector2.zero, Size = Vector2.new(camera.ViewportSize.X, TopStack.GetBottom() * scale) }
		for name, rect in obstacles do
			local overlapX = math.min(right, rect.Position.X + rect.Size.X) - math.max(left, rect.Position.X)
			local overlapY = math.min(bottom, rect.Position.Y + rect.Size.Y) - math.max(top, rect.Position.Y)
			if overlapX > 1.5 and overlapY > 1.5 then
				table.insert(problems, ("overlaps %s (%.0f,%.0f %.0fx%.0f)"):format(name, rect.Position.X, rect.Position.Y, rect.Size.X, rect.Size.Y))
			end
		end
		local obstacleCount = 0
		for _ in obstacles do
			obstacleCount += 1
		end
		table.insert(lines, {
			Ok = #problems == 0,
			Name = ("gacha card (%s, %s): the card + button row is inside the safe rect and overlaps no HUD rect"):format(layout, view.Name),
			Detail = ("card x %.0f-%.0f y %.0f-%.0f of %.0fx%.0f, fit %.2f, %d HUD rects%s"):format(left, right, top, bottom, camera.ViewportSize.X, camera.ViewportSize.Y, card.Fit.Scale, obstacleCount, if #problems > 0 then " | " .. table.concat(problems, "; ") else ""),
		})
	end
	camera.CameraType = savedType
	camera.CFrame = savedCFrame
	UIKit.SetForcedPhone(nil)
	return lines
end

-- The clamp math itself (pure, no live HUD): at 1366x768 and 844x390 (the
-- phone's 0.8), for a grid of anchor points from far off every edge to the
-- middle, with a synthetic left column, bottom row, weapon bar and top stack,
-- the planned card is inside the safe rect, shrinks only when the rect is
-- shorter than the card (never below 0.7) and is not squeezed otherwise.
local function probeGachaPlan(): { ProbeLine }
	local Board = require(script.Parent.GachaBoardController) :: any
	local G = PlotLayout.Gacha
	local lines: { ProbeLine } = {}
	local full = Vector2.new(G.CardPx.X, G.CardPx.Y + G.ButtonRowPx)
	for _, case in { { Name = "1366x768", Viewport = Vector2.new(1366, 768), Phone = false }, { Name = "844x390", Viewport = Vector2.new(844, 390), Phone = true } } do
		local scale = if case.Phone then UITheme.PhoneScale else 1
		local rects = {
			CashCard = { Position = Vector2.new(12, 70), Size = Vector2.new(if case.Phone then 140 else 220, 60) },
			BottomRow = { Position = Vector2.new(case.Viewport.X / 2 - 200, case.Viewport.Y - (if case.Phone then 90 else 110)), Size = Vector2.new(400, 70) },
		}
		local weaponBar = { Position = Vector2.new(case.Viewport.X / 2 - 150, case.Viewport.Y - (if case.Phone then 150 else 190)), Size = Vector2.new(300, 64) }
		local safe = Board.PlanSafeRect(case.Viewport, scale, 100, rects, weaponBar)
		local bad: { string } = {}
		local worstFit, squeezed = 1, 0
		local points = 0
		for _, fx in { -2000, 0, 0.25, 0.5, 0.75, 1, 3000 } do
			for _, fy in { -2000, 0, 0.25, 0.5, 0.75, 1, 3000 } do
				local point = Vector2.new(if math.abs(fx) > 1 then fx else fx * case.Viewport.X / scale, if math.abs(fy) > 1 then fy else fy * case.Viewport.Y / scale)
				local position, fit = Board.PlanCard(point, safe)
				points += 1
				worstFit = math.min(worstFit, fit)
				if fit < 1 then
					squeezed += 1
				end
				local halfW, h = full.X * fit / 2, full.Y * fit
				local inside = position.X - halfW >= safe.Left - 0.01 and position.X + halfW <= safe.Right + 0.01 and position.Y - h >= safe.Top - 0.01 and position.Y <= safe.Bottom + 0.01
				if not inside and (safe.Bottom - safe.Top) >= h then
					table.insert(bad, ("point (%.0f, %.0f) -> (%.0f, %.0f) fit %.2f outside"):format(point.X, point.Y, position.X, position.Y, fit))
				end
			end
		end
		local available = safe.Bottom - safe.Top
		local wantSqueeze = available < full.Y
		table.insert(lines, {
			Ok = #bad == 0 and worstFit >= G.MinSqueeze - 1e-6 and ((squeezed > 0) == wantSqueeze),
			Name = ("gacha card (%s): the clamp keeps the card inside the safe rect; it shrinks (min 0.7) only when the rect is too short"):format(case.Name),
			Detail = ("safe x %.0f-%.0f y %.0f-%.0f (%.0f tall, card %.0f), %d points, squeezed %d, worst fit %.2f%s"):format(safe.Left, safe.Right, safe.Top, safe.Bottom, available, full.Y, points, squeezed, worstFit, if #bad > 0 then " | " .. table.concat(bad, "; ", 1, math.min(#bad, 3)) else ""),
		})
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
		elseif payload.Kind == "GachaPlace" then
			return probeGachaPlace(payload.Phone == true)
		elseif payload.Kind == "GachaPlan" then
			return probeGachaPlan()
		elseif payload.Kind == "GachaFar" then
			return probeGachaFar()
		elseif payload.Kind == "GachaBack" then
			return probeGachaBack()
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
