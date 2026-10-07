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

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
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
		AdminAction = { {}, { { Action = "Nope" } }, { { Action = "StartEvent", Args = { Id = "Nope" } } } },
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

-- On the phone layout, every HUD element of the left group stays inside
-- the left 40% of the screen (deal badge, timed pills included).
local function testHudLeftColumn(): { string }
	local hud = require(script.Parent.HudController) :: any
	UIKit.SetForcedPhone(true)
	task.wait(0.2)
	local ok, result = pcall(hud.SelfTestLeftColumn, "phone")
	UIKit.SetForcedPhone(nil)
	if not ok then
		return { "FAIL hud left column: " .. tostring(result) }
	end
	return result
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
	while not presented() and os.clock() - started < 8 do
		task.wait(0.1)
	end
	if not presented() or not step then
		return { { Ok = false, Name = ("tutorial %s: its banner shows"):format(stepId), Detail = "never presented" } }
	end
	task.wait(0.5) -- the slide-in
	local text = TutorialBanner.GetBaseText()
	local words = #text:split(" ")
	table.insert(lines, {
		Ok = text == step.Banner and words <= 6,
		Name = ("tutorial %s: the banner reads its instruction in 6 words or fewer"):format(stepId),
		Detail = ("%q (%d words)"):format(text, words),
	})
	-- No card of any kind: no tutorial card, and before the claim nothing
	-- else either (no modal, no result card, no welcome splash yet).
	local cardOpen = TutorialCards.IsOpen()
	table.insert(lines, { Ok = not cardOpen, Name = ("tutorial %s: no tutorial card"):format(stepId) })
	if stepId == "claim" then
		local UIKit = require(UI.UIKit) :: any
		local anyCard = cardOpen or UIKit.IsOverlayOpen() or TutorialBanner.IsSplashShown()
		table.insert(lines, { Ok = not anyCard, Name = "tutorial: no card shows before the claim" })
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

local function probeBigCard(expect: string): { ProbeLine }
	local ResultController = require(script.Parent.ResultController) :: any
	local started = os.clock()
	while not ResultController.IsBigCardOpen() and os.clock() - started < 3 do
		task.wait(0.1)
	end
	local headline = ResultController.GetBigCardHeadline()
	return {
		{
			Ok = ResultController.IsBigCardOpen() and headline == expect,
			Name = "a single pull of a Common opens the big card",
			Detail = ("headline %s"):format(tostring(headline)),
		},
	}
end

local function probeTutorial(payload: any)
	local lines: { ProbeLine } = {}
	local ok, result = pcall(function()
		if payload.Kind == "Step" then
			return probeStep(payload.StepIndex, payload.StepId)
		elseif payload.Kind == "BigCard" then
			return probeBigCard(payload.Expect)
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
	for _, line in testHudOrder() do
		table.insert(panelLines, line)
	end
	for _, line in testHudLeftColumn() do
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
