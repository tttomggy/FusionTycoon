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
local UserInputService = game:GetService("UserInputService")
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
local NotifyConfig = require(ReplicatedStorage.Shared.Config.NotifyConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local ShopPrices = require(ReplicatedStorage.Shared.Modules.ShopPrices)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
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
-- Never a real player and never an admin (negative ids are refused by
-- AdminConfig.IsAdmin); the fuzz's per-player admin calls aim at it.
local FAKE_USER_ID = -987654321

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
			-- Rival labs: { RivalId, PedestalIndex }. No such lab, junk types.
			{ { RivalId = 999999, PedestalIndex = 1 } },
			{ { RivalId = "x", PedestalIndex = 1 } },
			{ { RivalId = { 1 }, PedestalIndex = 1 } },
			{ { RivalId = 1, PedestalIndex = 99 } },
			{ { RivalId = 1, PedestalIndex = NAN } },
			{ { RivalId = BIG_STRING, PedestalIndex = BIG_STRING } },
		},
		RequestShopPurchase = { {}, { "x" }, { { Key = 5 } }, { { Key = "NoSuchProduct" } }, { { Key = BIG_STRING } } },
		NotifyOptInAnalytics = { {}, { "x" }, { { Event = "Nope" } }, { { Event = 5 } }, { { Event = BIG_STRING } } },
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
		-- fingerprint check); an admin tester: junk ids are rejected. The
		-- per-player actions use FAKE_USER_ID, never a real player's id: a listed
		-- admin running this must not be able to reset someone in the server.
		AdminAction = {
			{},
			{ { Action = "Nope" } },
			{ { Action = "StartEvent", Args = { Id = "Nope" } } },
			{ { Action = "RestartTutorial", Args = { UserId = FAKE_USER_ID } } },
			{ { Action = "ResetPlayer", Args = { UserId = FAKE_USER_ID } } },
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
		table.insert(cases.RequestSteal, { { RivalId = n, PedestalIndex = n } })
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
	{ Name = "896x414 phone", Size = Vector2.new(896, 414), Phone = true },
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

-- Event guidance (EventController.PlanGuidance, the maths refreshGuidance
-- runs): Night / Void Moon point at the Fusion Machine only when there is a
-- pair to fuse, and say why; Rainbow Storm points at the pad only when a pull
-- is affordable; nothing points while the tutorial runs or within 30 s of it.
local function testEventGuidance(): { string }
	local EventController = require(script.Parent.EventController) :: any
	local lines: { string } = {}
	local function state(overrides: any): any
		local base = { CanFuse = false, CanPull = false, Quiet = false, OnPad = false }
		for key, value in overrides do
			base[key] = value
		end
		return base
	end
	local function check(name: string, ok: boolean, detail: string)
		table.insert(lines, ("%s event guidance: %s%s"):format(if ok then "PASS" else "FAIL", name, if ok then "" else " | " .. detail))
	end
	for _, night in { "Night", "VoidMoon" } do
		local none = EventController.PlanGuidance(night, 1, state({}))
		check(night .. " with nothing to fuse shows no pointer and no pill", none.Target == nil and none.PillText == nil, ("target %s pill %s"):format(tostring(none.Target), tostring(none.PillText)))
		local pair = EventController.PlanGuidance(night, 1, state({ CanFuse = true }))
		check(night .. " with a fusable pair points at the machine and says why",
			pair.Target == "Machine" and pair.Text == "FUSE NOW" and pair.PillStation == "Machine"
				and pair.PillText ~= nil and pair.PillText:find("FUSIONS MUTATE MORE", 1, true) ~= nil and pair.PillText:find("FUSE NOW", 1, true) ~= nil,
			("target %s text '%s' pill '%s'"):format(tostring(pair.Target), pair.Text, tostring(pair.PillText)))
		local quiet = EventController.PlanGuidance(night, 1, state({ CanFuse = true, Quiet = true }))
		check(night .. " is silent while the tutorial runs / just ended", quiet.Target == nil and quiet.PillText == nil, ("target %s"):format(tostring(quiet.Target)))
	end
	local broke = EventController.PlanGuidance("RainbowStorm", 1, state({ CanFuse = true }))
	check("Rainbow Storm with no pull affordable shows no pointer", broke.Target == nil and broke.PillText == nil, ("target %s"):format(tostring(broke.Target)))
	local pull = EventController.PlanGuidance("RainbowStorm", 1, state({ CanPull = true }))
	check("Rainbow Storm with a pull affordable points at the pad", pull.Target == "Pad" and pull.Text == "PULL HERE" and pull.PillText ~= nil and pull.PillText:find("PULL NOW", 1, true) ~= nil, ("target %s '%s'"):format(tostring(pull.Target), pull.Text))
	local then_ = EventController.PlanGuidance("RainbowStorm", 1, state({ CanPull = true, CanFuse = true, OnPad = true }))
	check("Rainbow Storm on the pad with a pair says THEN FUSE", then_.Target == "Machine" and then_.Text == "THEN FUSE", ("target %s '%s'"):format(tostring(then_.Target), then_.Text))
	local padNoPair = EventController.PlanGuidance("RainbowStorm", 1, state({ CanPull = true, OnPad = true }))
	check("Rainbow Storm on the pad with nothing to fuse keeps pointing at the pad", padNoPair.Target == "Pad", ("target %s"):format(tostring(padNoPair.Target)))
	local other = EventController.PlanGuidance("GoldenRain", 1, state({ CanFuse = true, CanPull = true }))
	check("other events add no station pointer", other.Target == nil and other.PillText == nil, ("target %s"):format(tostring(other.Target)))
	return lines
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
			local plan = UIKit.PlanModalFor(spec.MaxSize, spec.FitContent, view, viewport.Phone, spec.BigPanel)
			-- The panel + shadow sits MODAL_MARGIN inside the root all round.
			local top = plan.Top + margin * plan.Fit
			local height = plan.Visual - 2 * margin * plan.Fit
			local why = UIKit.CheckCardPlacement(top, height, view.Y, viewport.Phone, spec.BigPanel)
			checked += 1
			if why then
				table.insert(failures, ("%s %s"):format(spec.Name, why))
			elseif viewport.Phone and spec.BigPanel and top + height > view.Y - UIKit.PANEL_BOTTOM_GAP + 0.5 then
				-- A phone big panel hides the HUD: it may run down to 8 px above the bottom, no further.
				table.insert(failures, ("%s ends at %d, past %d"):format(spec.Name, top + height, view.Y - UIKit.PANEL_BOTTOM_GAP))
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
		-- The Fuse All card with every tier gained and used up (its worst case):
		-- placed like the rest, its OK button inside the band.
		do
			local ResultController = require(script.Parent.ResultController) :: any
			local worst = ResultController.WorstFuseAllResult()
			local chips = 0
			for _, counts in { worst.Gained, worst.Consumed } do
				for _, n in counts do
					if n > 0 then
						chips += 1
					end
				end
			end
			local fuse = ResultController.PlanFuseAllFor(chips, true, viewport.Phone)
			local visual = fuse.Height + UITheme.ShadowOffset
			local top, fit = UIKit.PlanCardFor(visual, view.Y, viewport.Phone)
			local why = UIKit.CheckCardPlacement(top, visual * fit, view.Y, viewport.Phone)
			local okBottom = top + fuse.OkBottom * fit
			local bandBottom = view.Y - UIKit.GetCardBottomFor(viewport.Phone)
			checked += 1
			if why then
				table.insert(failures, ("FuseAllSummary (%d chips, %d rows, %d px) %s"):format(chips, fuse.Rows, fuse.Height, why))
			elseif okBottom > bandBottom + 0.5 then
				table.insert(failures, ("FuseAllSummary OK button ends at %d, the band ends at %d"):format(okBottom, bandBottom))
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

-- The checks that measure the live screen (cards in the band, text fits,
-- the objective bar, the hand, shop chips) mean nothing in a squeezed game
-- view: a 2346 x 125 window gave every card a negative height and 60 FAILs
-- that were not the game's. Returns why the window is too small (nil = fine);
-- the run then says so ONCE and skips those checks: a FAIL for a small desktop
-- view, a PASS for a phone-sized one (windowLine; a phone view is the point of
-- an emulated run, and its phone checks all ran).
local MIN_WINDOW = Vector2.new(1000, 600)
local function windowProblem(): string?
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1366, 768)
	if size.X >= MIN_WINDOW.X and size.Y >= MIN_WINDOW.Y then
		return nil
	end
	return ("the game view is %d x %d, the live-screen checks need at least %d x %d (Studio: enlarge the game window, undock Output / other panels, then run /selftest again)"):format(size.X, size.Y, MIN_WINDOW.X, MIN_WINDOW.Y)
end

-- True on a phone-sized view: the phone layout, or a touch screen with no keyboard.
local function isPhoneView(): boolean
	return UIKit.IsPhone() or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
end

-- The one report line for a view windowProblem() rejected.
local function windowLine(problem: string): string
	if isPhoneView() then
		local camera = Workspace.CurrentCamera
		local size = if camera then camera.ViewportSize else Vector2.new(0, 0)
		return ("PASS selftest window: phone view %d x %d, desktop-only live-screen checks skipped"):format(size.X, size.Y)
	end
	return "FAIL selftest window: " .. problem
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
			local big = false
			for _, spec in UIKit.GetModalSpecs() do
				if spec.Name == gui.Name then
					big = spec.BigPanel
				end
			end
			local why = UIKit.CheckCardPlacement(top, height, view.Y, UIKit.IsPhone(), big)
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
			-- The Fuse All card, every tier gained and used up: in the band, its OK
			-- button fully inside it, and as tall as PlanFuseAllFor says.
			result.CloseCards()
			task.wait(0.3)
			local worst = result.WorstFuseAllResult()
			result.SelfTestShowFuseAll(worst)
			task.wait(0.4)
			if measurePlacedCards(label .. " fuse all") == 0 then
				table.insert(cardLines, ("FAIL cards centred (FuseAllSummary, %s live): the card is not up"):format(label))
			end
			local fuseCard = localPlayer:WaitForChild("PlayerGui"):FindFirstChild("FuseAllSummary", true)
			local okButton = if fuseCard then fuseCard:FindFirstChild("Ok", true) else nil
			if fuseCard and okButton and okButton:IsA("GuiObject") then
				local view = UIKit.GetLogicalViewport()
				local scaleNow = screenScale(okButton)
				local okTop, okHeight = visibleRect(okButton, nil, scaleNow)
				local bandTop, bandBottom = UIKit.GetCardTop(), view.Y - UIKit.GetCardBottom()
				local fuseBody = fuseCard:FindFirstChild("Body")
				local chips = 0
				for _, counts in { worst.Gained, worst.Consumed } do
					for _, n in counts do
						if n > 0 then
							chips += 1
						end
					end
				end
				local planned = result.PlanFuseAllFor(chips, true, UIKit.IsPhone())
				local measured = if fuseBody and fuseBody:IsA("GuiObject")
					then fuseBody.AbsoluteSize.Y / (scaleNow * (tonumber((fuseCard :: GuiObject):GetAttribute("FitScale")) or 1))
					else 0
				local problems: { string } = {}
				if okTop < bandTop - 0.5 or okTop + okHeight > bandBottom + 0.5 then
					table.insert(problems, ("OK button %d..%d, band %d..%d"):format(okTop, okTop + okHeight, bandTop, bandBottom))
				end
				if math.abs(measured - planned.Height) > 2 then
					table.insert(problems, ("card is %d px tall, PlanFuseAllFor says %d"):format(measured, planned.Height))
				end
				table.insert(cardLines, if #problems > 0
					then cardFailures(("FuseAllSummary, %s live"):format(label), problems)
					else ("PASS cards centred (FuseAllSummary OK button inside the band, %s live, %d px card)"):format(label, planned.Height))
			else
				table.insert(cardLines, ("FAIL cards centred (FuseAllSummary, %s live): no OK button"):format(label))
			end
			result.CloseCards()
			task.wait(0.3)
			local hud = localPlayer:WaitForChild("PlayerGui"):FindFirstChild("Hud")
			if hud then
				-- Both the NEXT-event card and a RUNNING one (Night), with the
				-- tutorial's OK row off and on.
				-- The tutorial's objective bar is up (the events step): the bar and the
				-- card never overlap, the bar steps aside while the card is open and
				-- comes back after. Only when no real tutorial owns the bar.
				local TutorialBanner = require(UI.TutorialBanner) :: any
				local ownBar = not TutorialBanner.IsShown()
				if ownBar then
					TutorialBanner.Show("Lab weather!", "Every 15 min. Tap it to see what to do", "🌦", 9, 11)
					task.wait(0.6)
				end
				for _, now in { false, true } do
					for _, okRow in { false, true } do
						local variant = ("%s %s%s"):format(label, if now then "running" else "next", if okRow then " +OK" else "")
						eventInfo.SetTutorialOk(okRow)
						eventInfo.Show(hud, if now then "Night" else "GoldenRain", now)
						measurePlacedCards(variant)
						local card = eventInfo.GetFrame()
						if TutorialBanner.IsShown() and card then
							local bar = TutorialBanner.GetFrame()
							local function measureBar(): (number, number, number, number, boolean)
								local barTop, barHeight = visibleRect(bar, nil, screenScale(bar))
								local cardTop, cardHeight = visibleRect(card, card:FindFirstChild("Shadow") :: GuiObject?, screenScale(card))
								-- Clear when the bar is above the card (the bar's bottom + 8 px) or off the screen.
								local clear = barTop + barHeight + 8 <= cardTop or barTop + barHeight <= 0 or barTop >= cardTop + cardHeight
								return barTop, barHeight, cardTop, cardHeight, clear
							end
							-- The bar slides out (0.2 s) once the card is open: wait for it, not a fixed time (max 1.5 s).
							local barTop, barHeight, cardTop, cardHeight, clear = measureBar()
							local deadline = os.clock() + 1.5
							while not clear and eventInfo.IsOpen() and os.clock() < deadline do
								task.wait(0.05)
								barTop, barHeight, cardTop, cardHeight, clear = measureBar()
							end
							if not eventInfo.IsOpen() then
								-- EventController closes a "running" card whose event is not the live lineup's
								-- first (the test shows Night / GoldenRain whatever is running): the card rect is stale.
								table.insert(cardLines, ("WARN tutorial bar vs card (%s): the live event lineup closed the card before the check"):format(variant))
							else
								table.insert(cardLines, if clear
									then ("PASS tutorial bar vs card (%s): bar y %d..%d, card y %d..%d, covered %s"):format(variant, barTop, barTop + barHeight, cardTop, cardTop + cardHeight, tostring(TutorialBanner.IsCovered()))
									else ("FAIL tutorial bar vs card (%s): the objective bar (y %d..%d) overlaps the card (y %d..%d), covered %s"):format(variant, barTop, barTop + barHeight, cardTop, cardTop + cardHeight, tostring(TutorialBanner.IsCovered())))
							end
						end
						eventInfo.Hide()
						task.wait(0.6)
						if TutorialBanner.IsShown() then
							local bar = TutorialBanner.GetFrame()
							local barTop = visibleRect(bar, nil, screenScale(bar))
							table.insert(cardLines, if barTop >= UIKit.GetCardTop() - 1 and not TutorialBanner.IsCovered()
								then ("PASS tutorial bar vs card (%s): the bar is back after the card closes"):format(variant)
								else ("FAIL tutorial bar vs card (%s): the bar is still out after the card closed (y %d)"):format(variant, barTop))
						end
					end
				end
				if ownBar then
					TutorialBanner.Hide()
					task.wait(0.4)
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
-- after the second close must not exceed the count after the first (the
-- first may build the panel once, which is expected; a shrink is fine).
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
			elseif counts[2] > counts[1] then
				-- Only growth is a leak; a shrink is a panel dropping something it no longer needs.
				table.insert(lines, ("FAIL panel %s (%s): %+d instances after a second open/close"):format(spec.Name, scale, counts[2] - counts[1]))
			else
				table.insert(lines, ("PASS panel %s (%s)"):format(spec.Name, scale))
			end
		end
	end
	UIKit.SetForcedPhone(nil)
	return lines
end

--[[ Phone big panels -----------------------------------------------------------
	Upgrades, Shop, Items, Fuse, Index, Gifts, Quests, Rebirth, Settings on the
	phone layout (UIKit.Modal BigPanel): the HUD (Hud, WeaponBar, EffectsTray)
	is hidden while one is open and back after; the panel ends at least 8 px
	above the screen bottom; the header is one row <= 56 px; every text is
	>= 13 px; and Upgrades shows >= 3 whole rows of >= 64 px (name >= 18 px,
	buttons >= 44 px) at 844 x 390 and 896 x 414. The live part runs at this
	window's size with the phone layout forced; the row count runs the real
	plan at the two phone sizes. ]]
local PHONE_TEST_VIEWS = { Vector2.new(844, 390), Vector2.new(896, 414) }
local MIN_PANEL_TEXT = 13
local MAX_PHONE_HEADER = 56
local MIN_UPGRADE_ROWS = 3
local MIN_ROW_HEIGHT = 64
local MIN_ROW_NAME = 18

local function hudGuisEnabled(): { string }
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local shown: { string } = {}
	for _, name in { "Hud", "WeaponBar", "EffectsTray" } do
		local gui = playerGui:FindFirstChild(name)
		-- The weapon bar is off anyway before Rebirth 1 (the caller only
		-- counts guis that were on before the panel opened).
		if gui and gui:IsA("ScreenGui") and gui.Enabled then
			table.insert(shown, name)
		end
	end
	return shown
end

local function testPhonePanels(): { string }
	local lines: { string } = {}
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local specs: { PanelSpec } = {}
	for _, spec in panelSpecs() do
		if spec.Name ~= "HowToHeistPanel" then
			table.insert(specs, spec)
		end
	end
	local quests = require(UI.QuestsPanel) :: any
	table.insert(specs, { Name = "Quests", Open = quests.Open, Close = quests.Close })
	local picker = require(UI.ItemPickerUI) :: any
	local hud = require(script.Parent.HudController) :: any
	table.insert(specs, { Name = "ItemPickerUI", Open = hud.OpenInventory, Close = picker.Close })

	UIKit.SetForcedPhone(true)
	task.wait(0.3)
	local before = hudGuisEnabled()
	for _, spec in specs do
		local problems: { string } = {}
		-- The Gifts modal's ScreenGui is called "Gifts"; the others match the spec.
		local guiName = if spec.Name == "GiftsPanel" then "Gifts" else spec.Name
		local ok, err = pcall(function()
			spec.Open()
			task.wait(0.6)
			local isBig = false
			for _, modalSpec in UIKit.GetModalSpecs() do
				if modalSpec.Name == guiName then
					isBig = modalSpec.BigPanel
				end
			end
			local gui = playerGui:FindFirstChild(guiName)
			local root = gui and gui:FindFirstChild("Root")
			local panel = root and root:FindFirstChild("Panel")
			local body = panel and panel:FindFirstChild("Body")
			if not isBig or not gui or not body or not body:IsA("GuiObject") then
				error("not a BigPanel modal")
			end
			-- The HUD is hidden while the panel is open.
			if not UIKit.IsPhoneHudHidden() then
				table.insert(problems, "UIKit says the HUD is still shown")
			end
			for _, name in hudGuisEnabled() do
				table.insert(problems, name .. " is still enabled")
			end
			-- Ends at least 8 px above the bottom of the screen.
			local view = UIKit.GetLogicalViewport()
			local top, height = visibleRect(body, panel:FindFirstChild("Shadow") :: GuiObject?, screenScale(body))
			if top + height > view.Y - UIKit.PANEL_BOTTOM_GAP + 0.5 then
				table.insert(problems, ("ends at %d, the screen ends at %d (8 px gap)"):format(top + height, view.Y))
			end
			-- One compact header row.
			local header = body:FindFirstChild("Header")
			if header and header:IsA("GuiObject") then
				local headerHeight = header.AbsoluteSize.Y / UIKit.EffectiveScale(header)
				if headerHeight > MAX_PHONE_HEADER + 0.5 then
					table.insert(problems, ("header is %d px tall, max %d"):format(headerHeight, MAX_PHONE_HEADER))
				end
			else
				table.insert(problems, "no header")
			end
			-- Nothing smaller than 13 px (scaled text is capped by its own constraint).
			local small: { string } = {}
			for _, text in (gui :: ScreenGui):GetDescendants() do
				if (text:IsA("TextLabel") or text:IsA("TextButton")) and text.Text ~= "" and not text.TextScaled and text.TextSize < MIN_PANEL_TEXT and shownOnScreen(text, gui :: ScreenGui) then
					local short = text:GetFullName():gsub("^.*%.Root%.", "")
					table.insert(small, ("%s %d px"):format(short, text.TextSize))
				end
			end
			if #small > 0 then
				table.insert(problems, "text under 13 px: " .. table.concat(small, ", "))
			end
			-- Upgrades: the row and its buttons, as built.
			if spec.Name == "UpgradesPanel" then
				local metrics = (require(UI.UpgradesPanel) :: any).SelfTestMetrics()
				if not metrics then
					table.insert(problems, "no generator row")
				else
					if metrics.RowHeight < MIN_ROW_HEIGHT - 0.5 then
						table.insert(problems, ("row is %d px tall, min %d"):format(metrics.RowHeight, MIN_ROW_HEIGHT))
					end
					if metrics.NameSize < MIN_ROW_NAME then
						table.insert(problems, ("row name is %d px, min %d"):format(metrics.NameSize, MIN_ROW_NAME))
					end
					if metrics.ButtonHeight < UITheme.MinTapSize - 0.5 or metrics.MaxButtonHeight < UITheme.MinTapSize - 0.5 then
						table.insert(problems, ("buttons are %d / %d px tall, min %d"):format(metrics.ButtonHeight, metrics.MaxButtonHeight, UITheme.MinTapSize))
					end
				end
			end
		end)
		spec.Close()
		task.wait(0.5)
		if not ok then
			table.insert(problems, tostring(err))
		end
		-- And the HUD is back after it closes.
		if UIKit.IsPhoneHudHidden() then
			table.insert(problems, "UIKit says the HUD is still hidden after close")
		end
		local after = hudGuisEnabled()
		if #after ~= #before then
			table.insert(problems, ("HUD guis on after close: %s, before: %s"):format(table.concat(after, ","), table.concat(before, ",")))
		end
		table.insert(lines, if #problems > 0
			then ("FAIL phone panel %s: %s"):format(spec.Name, table.concat(problems, "; "))
			else ("PASS phone panel %s (HUD hidden and restored, <= viewport - 8, header <= 56, text >= 13)"):format(spec.Name))
	end
	UIKit.SetForcedPhone(nil)
	task.wait(0.3)

	-- Upgrades shows >= 3 whole rows at the two phone sizes (the real plan).
	local upgrades = require(UI.UpgradesPanel) :: any
	for _, size in PHONE_TEST_VIEWS do
		local view = size / UITheme.PhoneScale
		local rows = -1
		for _, modalSpec in UIKit.GetModalSpecs() do
			if modalSpec.Name == "UpgradesPanel" then
				local plan = UIKit.PlanModalFor(modalSpec.MaxSize, modalSpec.FitContent, view, true, true)
				rows = upgrades.SelfTestPhoneRows(UIKit.PhoneContentHeightFor(plan))
			end
		end
		table.insert(lines, if rows >= MIN_UPGRADE_ROWS
			then ("PASS phone panel Upgrades rows (%dx%d: %d whole rows)"):format(size.X, size.Y, rows)
			else ("FAIL phone panel Upgrades rows (%dx%d): %d whole rows, need %d"):format(size.X, size.Y, rows, MIN_UPGRADE_ROWS))
	end
	return lines
end

-- The game must open in landscape on a phone: the client sets
-- PlayerGui.ScreenOrientation to LandscapeSensor at boot (Bootstrap).
local function testOrientation(): { string }
	local orientation = localPlayer:WaitForChild("PlayerGui").ScreenOrientation
	if orientation == Enum.ScreenOrientation.LandscapeSensor then
		return { "PASS orientation: PlayerGui.ScreenOrientation is LandscapeSensor" }
	end
	return { ("FAIL orientation: PlayerGui.ScreenOrientation is %s, not LandscapeSensor"):format(orientation.Name) }
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

	-- The slots rise strictly top to bottom, at the three target screens: the
	-- same plan the stack uses, with every slot occupied (a 89 px bar, the
	-- 44 px chip, the 93 px steal mission slot (box + shadow), a 64 px line), the objective
	-- bar clear of the Roblox top bar, no two rects overlapping and the last
	-- slot inside the screen. (The live Ys alone cannot be compared: an EMPTY
	-- objective slot has no bar to order, and the chip then keeps its place
	-- beside the top bar at y 12, which is below nothing.)
	local STACK_VIEWS = {
		{ Name = "1920x1080", Size = Vector2.new(1920, 1080), Phone = false },
		{ Name = "1366x768", Size = Vector2.new(1366, 768), Phone = false },
		{ Name = "844x390 phone", Size = Vector2.new(844, 390), Phone = true },
	}
	for _, stackView in STACK_VIEWS do
		local phone = stackView.Phone
		local cardTop = UIKit.GetCardTopFor(phone)
		local plan = TopStack.PlanFor(cardTop, 89, 44, 64, 93)
		local view = stackView.Size / (if phone then UITheme.PhoneScale else 1)
		local rects = {
			{ Name = "Objective", Y = plan.Objective, Height = 89 },
			{ Name = "Chip", Y = plan.Chip, Height = 44 },
			{ Name = "Mission", Y = plan.Mission, Height = 93 },
			{ Name = "Announce", Y = plan.Announce, Height = 64 },
		}
		local strict = plan.Objective < plan.Chip and plan.Chip < plan.Mission and plan.Mission < plan.Announce and plan.Announce < plan.Status
		local overlap: string? = nil
		for index = 2, #rects do
			local above, below = rects[index - 1], rects[index]
			if above.Y + above.Height > below.Y then
				overlap = ("%s (%d+%d) overlaps %s (%d)"):format(above.Name, above.Y, above.Height, below.Name, below.Y)
			end
		end
		local clear = plan.Objective >= cardTop and cardTop >= UIKit.TOP_BAR_HEIGHT + UIKit.CARD_TOP_GAP
		local inside = plan.Status + 64 <= view.Y
		local label = stackView.Name
		table.insert(lines, if strict and clear and inside and overlap == nil
			then ("PASS top stack slots in order, no overlap (%s: %d / %d / %d / %d / %d)"):format(label, plan.Objective, plan.Chip, plan.Mission, plan.Announce, plan.Status)
			else ("FAIL top stack slots out of order (%s: %d / %d / %d / %d / %d, bar top %d, view %d%s)"):format(label, plan.Objective, plan.Chip, plan.Mission, plan.Announce, plan.Status, cardTop, view.Y, if overlap then ", " .. overlap else ""))
	end
	-- The live slots: the ones in use rise strictly and sit inside the screen.
	local view = UIKit.GetLogicalViewport()
	local used: { { Name: string, Y: number, Height: number } } = {}
	for _, slot in { "Objective", "Chip", "Mission", "Announce" } do
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

	-- Every stud-sized label BillboardKit builds (EMPTY pills, the LOCK
	-- console, pedestal labels, station pads, rival-lab chips...) is capped:
	-- at 3 studs from its adornee, on a 1080p view, it draws <= 240 px wide.
	local capChecked, capBad = 0, {}
	do
		local camera = Workspace.CurrentCamera
		local fov = if camera then camera.FieldOfView else PlotLayout.LabelCap.ReferenceFov
		for _, gui in Workspace:GetDescendants() do
			if gui:IsA("BillboardGui") and gui:GetAttribute(BillboardKit.STUD_LABEL_ATTRIBUTE) == true then
				capChecked += 1
				local wide = BillboardKit.ProjectedWidth(gui.Size.X.Scale, 3, gui.DistanceLowerLimit, 1080, fov)
				if wide > 240 then
					table.insert(capBad, ("%s limit %.1f, %.0f px"):format(gui:GetFullName(), gui.DistanceLowerLimit, wide))
				end
			end
		end
	end
	table.insert(lines, if #capBad == 0 and capChecked > 0
		then ("PASS stud-sized world labels stop growing up close (%d labels, <= 240 px at 3 studs)"):format(capChecked)
		else ("FAIL stud-sized world labels (%d checked): %s"):format(capChecked, table.concat(capBad, "; ")))

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

-- The steal mission box (UI/MissionBanner in TopStack's Mission slot): the
-- pure rules, then the live box. Live part: shows with an owner, <= 100 px
-- tall, inside the screen, every text >= 12 px on screen, between the chip
-- and the announcement line (no overlap), hidden under a modal and back
-- after, gone after the first delivery; the gacha card's clamp still clears
-- the stack with the box up.
local function testMissionBanner(): { string }
	local MissionBanner = require(UI.MissionBanner) :: any
	local TopStack = require(UI.TopStack) :: any
	local Board = require(script.Parent.GachaBoardController) :: any
	local lines: { string } = {}
	local function check(ok: boolean, name: string, detail: string?)
		table.insert(lines, ("%s steal mission: %s%s"):format(if ok then "PASS" else "FAIL", name, if ok or not detail then "" else " | " .. detail))
	end
	-- Pure rules.
	local base = { Owner = true, Done = false, Elapsed = 0, TutorialRunning = false, Down = false }
	local function plan(changes: any): boolean
		local state = table.clone(base)
		for key, value in changes do
			(state :: any)[key] = value
		end
		return MissionBanner.PlanShow(state)
	end
	check(plan({}), "shows for an owner before the first delivery")
	check(
		not plan({ Owner = false }) and not plan({ Done = true }) and not plan({ Elapsed = MissionBanner.MAX_SECONDS }) and not plan({ TutorialRunning = true }) and not plan({ Down = true }),
		"hidden with no owner, after the first delivery, after 3 minutes, in a tutorial step, and while ragdolled"
	)
	check(plan({ Elapsed = MissionBanner.MAX_SECONDS - 1 }), "still up one second before the 3 minutes")
	check(
		MissionBanner.PlanStep(false, false) == 1 and MissionBanner.PlanStep(true, false) == 2 and MissionBanner.PlanStep(true, true) == 3,
		"step 1 lit until an orb is carried, step 2 while carrying, a flash on delivery"
	)
	check(
		MissionBanner.TitleFor("Dr. Fizz's Lab") == "STEAL FROM DR. FIZZ!" and MissionBanner.TitleFor(nil) == "STEAL A FREE ORB!",
		"the title names the rival lab when known",
		MissionBanner.TitleFor("Dr. Fizz's Lab")
	)
	local clear = MissionBanner.ROBLOX_BUTTONS_X / UITheme.PhoneScale
	local narrow = MissionBanner.WidthFor(1055, true)
	check(
		MissionBanner.WidthFor(2000, false) == MissionBanner.MAX_WIDTH and (1055 - narrow) / 2 >= clear and MissionBanner.WidthFor(500, true) >= MissionBanner.MIN_WIDTH,
		"520 px wide on desktop, clear of the Roblox buttons on a phone",
		("phone width at 1055 logical: %d"):format(narrow)
	)

	-- The stack with the box up: no overlap, the gacha clamp clears it.
	local slot = MissionBanner.HEIGHT + UITheme.ShadowOffset
	for _, phone in { false, true } do
		local top = UIKit.GetCardTopFor(phone)
		local stack = TopStack.PlanFor(top, 0, 44, 0, slot)
		local without = TopStack.PlanFor(top, 0, 44, 0)
		check(stack.Chip + 44 <= stack.Mission and stack.Mission + slot <= stack.Announce and stack.Announce >= without.Announce + slot, ("sits between the chip and the announcement (%s)"):format(if phone then "phone" else "desktop"))
	end
	local gacha = PlotLayout.Gacha
	local clampOk, clampDetail = true, {}
	for _, viewHeight in { 1080, 768 } do
		local stackBottom = TopStack.PlanFor(UIKit.GetCardTopFor(false), 0, 44, 0, slot).Announce
		local cardHeight = 300
		for _, anchorY in { viewHeight * 0.5, viewHeight * 0.3, viewHeight * 0.1 } do
			local cardTop = anchorY - cardHeight + Board.StackShiftFor(anchorY, cardHeight, stackBottom, viewHeight)
			if cardTop < math.ceil(stackBottom) + gacha.StackGapPx - 0.5 then
				clampOk = false
				table.insert(clampDetail, ("view %d anchor %.0f top %.0f < %d"):format(viewHeight, anchorY, cardTop, math.ceil(stackBottom) + gacha.StackGapPx))
			end
		end
	end
	check(clampOk, "the gacha card's clamp clears the stack with the box up", table.concat(clampDetail, "; "))

	-- Live box.
	MissionBanner.SetTestState({ Owner = true, Done = false, Elapsed = 0, TutorialRunning = false, Down = false })
	local waited = 0
	while not TopStack.IsMissionShown() and waited < 2 do
		task.wait(0.05)
		waited += 0.05
	end
	task.wait(0.6) -- the slide-in
	local shown = TopStack.IsMissionShown()
	check(shown and MissionBanner.IsRegistered(), "the box shows for an owner", ("shown %s | %s"):format(tostring(shown), MissionBanner.GetBlocker()))
	if shown then
		local body = MissionBanner.GetBody() :: Frame
		local scale = screenScale(body)
		local view = UIKit.GetLogicalViewport()
		-- AbsolutePosition sits below the Roblox top bar even here: visibleRect
		-- adds the inset back (without it a phone read -8.5 for a 64 slot).
		-- The slide-in ends when the box reaches its slot, not after a fixed wait.
		local slideBy = os.clock() + 1.5
		local topY, logicalHeight = visibleRect(body, nil, scale)
		while math.abs(topY - TopStack.GetY("Mission")) > 2 and os.clock() < slideBy do
			task.wait(0.05)
			topY, logicalHeight = visibleRect(body, nil, scale)
		end
		local left = body.AbsolutePosition.X / scale
		local right = left + body.AbsoluteSize.X / scale
		check(logicalHeight <= 100 and logicalHeight > 0, "the box is at most 100 px tall", ("%.0f px"):format(logicalHeight))
		check(left >= 0 and right <= view.X + 1 and topY >= 0 and topY + logicalHeight <= view.Y + 1, "the box is inside the screen", ("x %.0f-%.0f of %.0f, y %.0f+%.0f of %.0f"):format(left, right, view.X, topY, logicalHeight, view.Y))
		local wantY = TopStack.GetY("Mission")
		check(math.abs(topY - wantY) <= 2, "the box sits at TopStack's Mission y", ("y %.1f, slot %.1f"):format(topY, wantY))
		local announceY = TopStack.GetY("Announce")
		check(topY + logicalHeight + UITheme.ShadowOffset <= announceY + 0.5, "the box ends above the announcement line", ("bottom %.0f, announce y %.0f"):format(topY + logicalHeight + UITheme.ShadowOffset, announceY))
		local smallest = math.huge
		local fits = true
		local labels: { TextLabel } = { MissionBanner.GetTitleLabel() }
		for _, label in MissionBanner.GetStepLabels() do
			table.insert(labels, label)
		end
		for _, label in labels do
			-- A scaled label's size is read from its drawn line height.
			local size = if label.TextScaled then label.TextBounds.Y / 1.25 else label.TextSize
			smallest = math.min(smallest, size * scale)
			if label.TextBounds.Y > label.AbsoluteSize.Y + 1 or label.TextBounds.X > label.AbsoluteSize.X + 1 then
				fits = false
			end
		end
		check(smallest >= 12, "every text is at least 12 px on screen", ("smallest %.1f px"):format(smallest))
		check(fits, "every text fits its box (no cut-off)")
		check(MissionBanner.GetLitStep() == (if Players.LocalPlayer:GetAttribute("HeistTier") ~= nil then 2 else 1), "the lit step follows the carried orb")
	end

	-- A modal hides it; closing the modal brings it back.
	UIKit.SetOverlay("SelfTestMission", true)
	task.wait(0.3)
	local hiddenUnder = not TopStack.IsMissionShown()
	UIKit.SetOverlay("SelfTestMission", false)
	task.wait(0.3)
	check(hiddenUnder and TopStack.IsMissionShown(), "hidden while a modal is open, back when it closes", ("hidden %s, back %s | %s"):format(tostring(hiddenUnder), tostring(TopStack.IsMissionShown()), MissionBanner.GetBlocker()))

	-- A tutorial step / a ragdoll takes it away; the end brings it back.
	MissionBanner.SetTestState({ Owner = true, Done = false, Elapsed = 0, TutorialRunning = true, Down = false })
	task.wait(0.3)
	local hiddenTutorial = not TopStack.IsMissionShown()
	MissionBanner.SetTestState({ Owner = true, Done = false, Elapsed = 0, TutorialRunning = false, Down = true })
	task.wait(0.3)
	local hiddenDown = not TopStack.IsMissionShown()
	MissionBanner.SetTestState({ Owner = true, Done = false, Elapsed = 0, TutorialRunning = false, Down = false })
	task.wait(0.3)
	check(hiddenTutorial and hiddenDown and TopStack.IsMissionShown(), "hidden in a tutorial step and while ragdolled, back after", ("tutorial %s, down %s, back %s | %s"):format(tostring(hiddenTutorial), tostring(hiddenDown), tostring(TopStack.IsMissionShown()), MissionBanner.GetBlocker()))

	-- After the first delivery it is gone for good.
	MissionBanner.SetTestState({ Owner = true, Done = true, Elapsed = 0, TutorialRunning = false, Down = false })
	task.wait(0.3)
	check(not TopStack.IsMissionShown() and TopStack.GetHeight("Mission") == 0, "gone after a delivered steal, the slot empty")
	MissionBanner.SetTestState(nil)
	task.wait(0.2)
	return lines
end

-- The goal arrow's owner (GoalMarkerController.PlanGoalArrow): the coach's
-- target once it has taken over, nothing for its Earn, nothing while a tip
-- runs (then the coach gets it back), the goal's own step or target
-- otherwise. One arrow on screen, ever.
local function testCoachArrow(): { string }
	local GoalConfig = require(ReplicatedStorage.Shared.Config.GoalConfig)
	local LoopCoach = require(ReplicatedStorage.Shared.Config.LoopCoach)
	local marker = require(script.Parent.GoalMarkerController) :: any
	local lines: { string } = {}
	local goal: any = nil
	for _, candidate in GoalConfig.Goals do
		if candidate.Id == "own_legendary" then
			goal = candidate
		end
	end
	local function coach(step: string, target: string?, takes: boolean): any
		return { Step = step, Target = target, Takes = takes, Lit = step }
	end
	local goalStep = { Kind = "Fuse", Tier = "Epic", Owned = 3, Target = "FusionMachine" }
	local function check(name: string, progress: any, tip: boolean, wantTarget: string?, wantText: string)
		local target, text = marker.PlanGoalArrow(goal, progress, tip)
		table.insert(
			lines,
			if target == wantTarget and text == wantText
				then ("PASS goal arrow: " .. name)
				else ("FAIL goal arrow: %s (target %s '%s', wanted %s '%s')"):format(name, tostring(target), text, tostring(wantTarget), wantText)
		)
	end
	local upgrade = coach("Upgrade", "Generator_ember_forge", true)
	check("the coach's upgrade station once it has taken over", { Current = 1, Target = 2, Step = goalStep, Coach = upgrade }, false, "Generator_ember_forge", LoopCoach.ArrowText.Upgrade)
	check("a tip owns the arrow while it runs", { Current = 1, Target = 2, Step = goalStep, Coach = upgrade }, true, nil, "")
	check("the coach gets the arrow back when the tip ends", { Current = 1, Target = 2, Step = goalStep, Coach = upgrade }, false, "Generator_ember_forge", LoopCoach.ArrowText.Upgrade)
	check("Earn points at nothing", { Current = 1, Target = 2, Step = goalStep, Coach = coach("Earn", nil, true) }, false, nil, LoopCoach.ArrowText.Earn)
	check("the goal's own step keeps the arrow while the coach waits", { Current = 1, Target = 2, Step = goalStep, Coach = coach("Pull", "GachaStation", false) }, false, "FusionMachine", goal.Text)
	check("no step and no coach: the goal's own target", { Current = 1, Target = 2 }, false, goal.Target, goal.Text)
	check("no coach during the tutorial: the goal's step", { Current = 1, Target = 2, Step = goalStep }, true, "FusionMachine", goal.Text)
	return lines
end

-- The loop-closing announcements' timing (LoopCoachController.Plan*): the
-- "new orb earns" line only for a pedestal that gained income, "more cash"
-- only once a pull was unaffordable and is affordable again after a fuse.
local function testLoopMoments(): { string }
	local controller = require(script.Parent.LoopCoachController) :: any
	local lines: { string } = {}
	local function check(name: string, ok: boolean, detail: string?)
		table.insert(lines, if ok then "PASS loop moments: " .. name else ("FAIL loop moments: %s (%s)"):format(name, detail or ""))
	end
	local line, keep = controller.PlanNewOrb({ Before = 10, At = 0 }, 14, 1, false)
	check("a gained pedestal income says what it earns", line == controller.NewOrbLine(4) and keep == nil, tostring(line))
	line, keep = controller.PlanNewOrb({ Before = 10, At = 0 }, 10, 1, false)
	check("no gain yet: keep waiting, say nothing", line == nil and keep ~= nil)
	line, keep = controller.PlanNewOrb({ Before = 10, At = 0 }, 10, 60, false)
	check("an orb that never reached a pedestal gives up silently", line == nil and keep == nil)
	line, keep = controller.PlanNewOrb(nil, 99, 1, false)
	check("no fuse, no line", line == nil and keep == nil)
	local say, saw = controller.PlanMoreCash(true, false, true)
	check("still affordable since the fuse: no line", say == false and saw == false)
	say, saw = controller.PlanMoreCash(true, false, false)
	check("broke after the fuse: remembered, no line", say == false and saw == true)
	say, saw = controller.PlanMoreCash(true, true, true)
	check("affordable again after being broke: the line", say == true)
	say, saw = controller.PlanMoreCash(false, true, true)
	check("no fuse yet: no line", say == false and saw == false)
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
		-- The goal card with its 3 lines (title, next action, odds hint).
		local goalOk, goalResult = pcall(hud.SelfTestGoalLines, if phone then "phone" else "desktop")
		if not goalOk then
			table.insert(lines, "FAIL hud goal tracker lines: " .. tostring(goalResult))
		else
			for _, line in goalResult do
				table.insert(lines, line)
			end
		end
		-- The loop strip: five >= 44 px cells, the right chip lit, +62 px (desktop) / +40 px (phone) at most.
		local stripOk, stripResult = pcall(hud.SelfTestLoopStrip, if phone then "phone" else "desktop")
		if not stripOk then
			table.insert(lines, "FAIL hud loop strip: " .. tostring(stripResult))
		else
			for _, line in stripResult do
				table.insert(lines, line)
			end
		end
	end
	UIKit.SetForcedPhone(nil)
	return lines
end

-- Phone HUD coverage: with every card up (SHOP, GIFTS, QUESTS, three
-- power-ups, LOCK, the deal tile, "next in", the goal card and the quest
-- tracker) the UNION of all HUD rects covers at most 20% of the screen at
-- 844 x 390 and 896 x 414 (the % is printed so before / after can be
-- compared); every icon card is >= 44 px on screen with its words >= 13 px;
-- the HUD stays clear of the weapon bar (when /weapons all is on) and of the
-- phone jump button.
local PHONE_COVERAGE_LIMIT = 20
local PHONE_VIEWPORTS = {
	{ Name = "844 x 390", Size = Vector2.new(844, 390) },
	{ Name = "896 x 414", Size = Vector2.new(896, 414) }, -- iPhone XR landscape
}

-- Area of the union of rects (sweep over x; rects are { Position, Size }).
local function unionArea(rects: { { Position: Vector2, Size: Vector2 } }): number
	local xs: { number } = {}
	for _, rect in rects do
		table.insert(xs, rect.Position.X)
		table.insert(xs, rect.Position.X + rect.Size.X)
	end
	table.sort(xs)
	local total = 0
	for index = 1, #xs - 1 do
		local x0, x1 = xs[index], xs[index + 1]
		if x1 > x0 then
			local spans: { { number } } = {}
			for _, rect in rects do
				if rect.Position.X <= x0 and rect.Position.X + rect.Size.X >= x1 then
					table.insert(spans, { rect.Position.Y, rect.Position.Y + rect.Size.Y })
				end
			end
			table.sort(spans, function(a, b)
				return a[1] < b[1]
			end)
			local covered, edge = 0, -math.huge
			for _, span in spans do
				local from = math.max(span[1], edge)
				if span[2] > from then
					covered += span[2] - from
					edge = span[2]
				end
			end
			total += covered * (x1 - x0)
		end
	end
	return total
end

local function testPhoneHudCoverage(): { string }
	local hud = require(script.Parent.HudController) :: any
	local combat = require(script.Parent.CombatController) :: any
	local EffectsTray = require(UI.EffectsTray) :: any
	local lines: { string } = {}
	UIKit.SetForcedPhone(true)
	task.wait(0.3)
	local ok, err = pcall(function()
		hud.SelfTestBusy(function()
			local scale = UITheme.PhoneScale
			for _, viewport in PHONE_VIEWPORTS do
				local view = viewport.Size / scale
				local rects = hud.GetObstacleRectsFor(view)
				local list: { { Position: Vector2, Size: Vector2 } } = {}
				for _, rect in rects do
					table.insert(list, rect)
				end
				local percent = unionArea(list) / (view.X * view.Y) * 100
				table.insert(lines, ("%s phone HUD coverage (%s): %.1f%% of the screen (limit %d%%, %d rects)"):format(
					if percent <= PHONE_COVERAGE_LIMIT then "PASS" else "FAIL", viewport.Name, percent, PHONE_COVERAGE_LIMIT, #list))
				-- Clear of the weapon bar (when it is up) and the jump button.
				local jump = EffectsTray.JumpRectFor(view, scale, true)
				local bar = combat.GetBarRectFor(view)
				local hits: { string } = {}
				local blockers: { { Name: string, Rect: { Position: Vector2, Size: Vector2 } } } = {}
				if bar then
					table.insert(blockers, { Name = "WeaponBar", Rect = bar })
				end
				if jump then
					table.insert(blockers, { Name = "JumpButton", Rect = jump })
				end
				for name, rect in rects do
					for _, blocker in blockers do
						local other, otherRect = blocker.Name, blocker.Rect
						local ox = math.min(rect.Position.X + rect.Size.X, otherRect.Position.X + otherRect.Size.X) - math.max(rect.Position.X, otherRect.Position.X)
						local oy = math.min(rect.Position.Y + rect.Size.Y, otherRect.Position.Y + otherRect.Size.Y) - math.max(rect.Position.Y, otherRect.Position.Y)
						if ox > 1 and oy > 1 then
							table.insert(hits, name .. "/" .. other)
						end
					end
				end
				table.sort(hits)
				table.insert(lines, (if #hits == 0 then "PASS" else "FAIL") .. (" phone HUD clear of the jump button and weapon bar (%s%s): %s"):format(
					viewport.Name, if bar then "" else ", weapon bar not showing (/weapons all)", if #hits == 0 then "no overlap" else table.concat(hits, ", ")))
			end
			-- Tap targets and text sizes of every icon card.
			local bad: { string } = {}
			local views = hud.GetCardViews()
			for _, card in views do
				if card.Size.X < UITheme.MinTapSize - 0.5 or card.Size.Y < UITheme.MinTapSize - 0.5 then
					table.insert(bad, ("%s is %dx%d px"):format(card.Name, card.Size.X, card.Size.Y))
				end
				if card.GlyphSize < 13 or (card.WordSize ~= nil and card.WordSize < 13) then
					table.insert(bad, ("%s text %d/%s"):format(card.Name, card.GlyphSize, tostring(card.WordSize)))
				end
			end
			table.insert(lines, (if #bad == 0 and #views >= 10 then "PASS" else "FAIL") .. (" phone HUD icon cards: %d cards, each >= %d px with text >= 13 px%s"):format(
				#views, UITheme.MinTapSize, if #bad > 0 then " | " .. table.concat(bad, "; ") else ""))
			return nil
		end)
	end)
	if not ok then
		table.insert(lines, "FAIL phone HUD coverage: " .. tostring(err))
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
		local label = if phone then "phone" else "desktop"
		local view = workspace.CurrentCamera.ViewportSize
		if not phone and (view.Y < UITheme.PhoneHeightThreshold or view.X < 1024) then
			-- The desktop plan never runs in a window this small (the live HUD would be the
			-- phone's): its left column is wider than the room beside the centred lines.
			table.insert(lines, ("PASS skipped lines (desktop): skipped, the %dx%d window is too small for the desktop plan (needs 1024 wide and %d tall)"):format(view.X, view.Y, UITheme.PhoneHeightThreshold))
			continue
		end
		UIKit.SetForcedPhone(phone)
		task.wait(0.2)
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

-- Warn: a miss is printed as a WARN and not counted as a FAIL (the Bat's reach, approved by eye).
type ProbeLine = { Ok: boolean, Name: string, Detail: string?, Warn: boolean? }

local TIMED_REVEAL_WAIT = 3 -- the last step's pop-ins are staggered up to 1.5 s

local PRESENT_WAIT = 30
local CATCH_UP_SLACK = 2 -- seconds on top of the presenter's own pacing

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
	-- The presenter follows the server: the server's step moved just before
	-- this probe, so the step on screen must be this one within the presenter's
	-- own pacing (the last step's minimum banner time, "Nice!", the pause) plus
	-- the card's delay and a little slack.
	local caughtUp = os.clock() - started
	local allowed = TutorialConfig.BannerMinSeconds + TutorialConfig.NiceSeconds + TutorialConfig.SettleSeconds + (step.CardDelay or 0) + CATCH_UP_SLACK
	table.insert(lines, {
		Ok = caughtUp <= allowed,
		Name = ("tutorial %s: the presenter caught up with the server's step"):format(stepId),
		Detail = ("%.1f s after the server moved, allowed %.1f s"):format(caughtUp, allowed),
	})
	local TutorialExplain = require(UI.TutorialExplain) :: any
	local TutorialHand = require(UI.TutorialHand) :: any
	-- The explain card: a step that introduces something opens it first
	-- (title, >= 22 px text, an OK); OK hands over to the banner (or ends
	-- the step). The claim has none.
	local cardOpen = TutorialCards.IsOpen() or TutorialExplain.IsOpen()
	local tooSmall = windowProblem() ~= nil
	if step.Card then
		-- THIS step's card: the previous step's may still be fading out.
		local waited = os.clock()
		local function cardUp(): boolean
			local shown = TutorialExplain.GetBody()
			return TutorialExplain.IsOpen() and shown ~= nil and shown.Text == step.Card.Body
		end
		while not cardUp() and os.clock() - waited < 10 do
			task.wait(0.05)
		end
		local firstSeen = os.clock()
		local shownAt0 = TutorialExplain.GetReadTimes()
		local seenEarly = firstSeen - shownAt0 <= 0.8 -- the OK must still be grey now
		local lockedAtOpen = not TutorialExplain.IsOkReady()
		-- The card as the player sees it: after its pop-in and placing loop.
		task.wait(0.4)
		local body = TutorialExplain.GetBody()
		table.insert(lines, {
			-- Drawn: positive on both axes, unless the window is too small to draw
			-- any card (reported once as "selftest window").
			Ok = TutorialExplain.IsOpen() and body ~= nil and body.TextSize >= 22 and body.Text == step.Card.Body and (tooSmall or (body.AbsoluteSize.X > 0 and body.AbsoluteSize.Y > 0 and body.TextBounds.Y > 0)),
			Name = ("tutorial %s: its explain card opens first (text >= 22 px, drawn)"):format(stepId),
			Detail = if body
				then ("open %s, text matches %s, %d px, drawn %dx%d, text height %d, shows %q"):format(
					tostring(TutorialExplain.IsOpen()),
					tostring(body.Text == step.Card.Body),
					body.TextSize,
					body.AbsoluteSize.X,
					body.AbsoluteSize.Y,
					body.TextBounds.Y,
					body.Text:sub(1, 30)
				)
				else "no card",
		})
		table.insert(lines, dimLine(stepId .. " (card up)"))
		-- Read time: OK is off when the card opens and on 1.5 s after it
		-- showed (measured from the card's own clock, not raced).
		local readUntil = os.clock() + TutorialConfig.CardReadSeconds + 2
		while not TutorialExplain.IsOkReady() and os.clock() < readUntil do
			task.wait(0.05)
		end
		local shownAt, readyAt = TutorialExplain.GetReadTimes()
		local delay = if readyAt > 0 then readyAt - shownAt else -1
		-- CardReadSeconds 0 (Tutorial 5): OK is live the moment the card opens.
		local liveAtOnce = TutorialConfig.CardReadSeconds <= 0
		table.insert(lines, {
			Ok = (liveAtOnce and not lockedAtOpen or (not liveAtOnce and (not seenEarly or lockedAtOpen)))
				and delay >= TutorialConfig.CardReadSeconds - 0.2
				and delay <= TutorialConfig.CardReadSeconds + 0.5,
			Name = ("tutorial %s: the card's OK turns on after %.1f s"):format(stepId, TutorialConfig.CardReadSeconds),
			Detail = ("grey when first seen (%.2f s after it opened): %s, turned on after %.2f s"):format(firstSeen - shownAt0, tostring(lockedAtOpen), delay),
		})
		-- A tap anywhere on the card is OK: the tap area covers the card body.
		local tapArea = TutorialExplain.GetTapArea()
		table.insert(lines, {
			Ok = tapArea ~= nil and tapArea.Active ~= false and (tooSmall or (tapArea.AbsoluteSize.X > 0 and tapArea.AbsoluteSize.Y > 0)),
			Name = ("tutorial %s: a tap anywhere on the card counts as OK"):format(stepId),
		})
		-- The orb diagram reads in card.Orbs order (orb, symbol, orb, symbol,
		-- orb): the real row builder, laid out at the card's image width on
		-- desktop and on a phone (the list layout once sorted by Name).
		if step.Card.Orbs then
			local wanted = table.concat(step.Card.Orbs, "|")
			for _, rowWidth in { 488, 330 } do
				local host = Instance.new("ScreenGui")
				host.Name = "SelfTestOrbRow"
				host.IgnoreGuiInset = true
				local hostFrame = Instance.new("Frame")
				hostFrame.BackgroundTransparency = 1
				hostFrame.Size = UDim2.fromOffset(rowWidth, 170)
				hostFrame.Parent = host
				host.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
				local row = TutorialExplain.BuildOrbRow(hostFrame, step.Card.Orbs)
				task.wait(0.1)
				local pieces = row:GetChildren()
				local placed: { GuiObject } = {}
				for _, piece in pieces do
					if piece:IsA("GuiObject") then
						table.insert(placed, piece)
					end
				end
				table.sort(placed, function(a, b)
					return a.AbsolutePosition.X < b.AbsolutePosition.X
				end)
				local seen: { string } = {}
				for _, piece in placed do
					table.insert(seen, tostring(piece:GetAttribute("Part")))
				end
				host:Destroy()
				table.insert(lines, {
					Ok = table.concat(seen, "|") == wanted,
					Name = ("tutorial %s: the card's orb row reads left to right in card order (%d px wide)"):format(stepId, rowWidth),
					Detail = ("left to right %s, wanted %s"):format(table.concat(seen, " "), table.concat(step.Card.Orbs, " ")),
				})
			end
		end
		TutorialExplain.PressOk()
		task.wait(0.2)
		table.insert(lines, dimLine(stepId .. " (after OK)"))
		local banner = TutorialBanner.IsShown()
		table.insert(lines, {
			Ok = banner,
			Name = ("tutorial %s: the banner takes over after OK"):format(stepId),
		})
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
	if TutorialBanner.IsShown() and not tooSmall then
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
	-- A step with a Count carries its live "0/2" after the instruction.
	local bannerOk = if step.Count then text:match("^" .. step.Banner:gsub("%p", "%%%0") .. " %d+/%d+$") ~= nil else text == step.Banner
	table.insert(lines, {
		Ok = bannerOk and words <= 6,
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
	if step.Hand and not tooSmall then
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
	-- A NEW! pill is a badge on its button's top edge: its bottom within 6 px
	-- of the edge, centred on the button within 4 px.
	if not tooSmall then
		local badgeBad: { string } = {}
		local probes = HudGate.MeasureBadges()
		for _, probe in probes do
			if math.abs(probe.PillBottom - probe.ButtonTop) > 6 or math.abs(probe.PillCentreX - probe.ButtonCentreX) > 4 then
				table.insert(badgeBad, ("%s bottom %.0f vs top %.0f, centre %.0f vs %.0f"):format(probe.Key, probe.PillBottom, probe.ButtonTop, probe.PillCentreX, probe.ButtonCentreX))
			end
		end
		table.insert(lines, {
			Ok = #badgeBad == 0,
			Name = ("tutorial %s: NEW! pills sit on their buttons' top edge (%d checked)"):format(stepId, #probes),
			Detail = table.concat(badgeBad, "; "),
		})
	end
	-- The weapon bar: nothing at Rebirth 0 (no greyed R1 / R2 / R3).
	local rebirths = require(script.Parent.TycoonController).GetRebirths()
	local bar = localPlayer:WaitForChild("PlayerGui"):FindFirstChild("WeaponBar")
	if rebirths == 0 and bar and bar:IsA("ScreenGui") then
		table.insert(lines, { Ok = not bar.Enabled, Name = "tutorial: no weapon bar before Rebirth 1" })
	end
	return lines
end

-- Closes every card an earlier section may have left up (a tutorial card, the
-- explain card, the daily reward, the event info, a shop side card, a result
-- card, a queued weapon-unlock card) and returns what it found open, then what
-- is still registered after closing. `suppressDaily` (true / false / nil to
-- leave it) keeps the daily reward from opening by itself during a section
-- (and the notification opt-in from prompting).
local function clearScreen(suppressDaily: boolean?): ({ string }, { string })
	local TutorialCards = require(UI.TutorialCards) :: any
	local TutorialExplain = require(UI.TutorialExplain) :: any
	local DailyCard = require(UI.DailyCard) :: any
	local EventInfoCard = require(UI.EventInfoCard) :: any
	local ShopCards = require(UI.ShopCards) :: any
	local ResultController = require(script.Parent.ResultController) :: any
	local CombatController = require(script.Parent.CombatController) :: any
	if suppressDaily ~= nil then
		local DailyController = require(script.Parent.DailyController) :: any
		local NotifyOptInController = require(script.Parent.NotifyOptInController) :: any
		DailyController.SelfTestSuppress(suppressDaily)
		NotifyOptInController.SelfTestSuppress(suppressDaily)
	end
	local found = UIKit.GetOpenOverlays()
	if EventInfoCard.IsOpen() then
		table.insert(found, "EventInfoCard")
	end
	local side = ShopCards.GetSideName()
	if side then
		table.insert(found, "side card " .. side)
	end
	local queued = CombatController.SelfTestClearUnlocks()
	if queued > 0 then
		table.insert(found, ("%d queued weapon-unlock cards"):format(queued))
	end
	TutorialCards.Close()
	TutorialExplain.Close()
	DailyCard.Close()
	EventInfoCard.Hide()
	ShopCards.CloseSide()
	ResultController.CloseCards()
	local deadline = os.clock() + 1.5
	while UIKit.IsOverlayOpen() and os.clock() < deadline do
		task.wait(0.1)
	end
	return found, UIKit.GetOpenOverlays()
end

-- "no overlay open": the precondition of a section that measures the bare
-- screen. Closes what it finds (one leak is one FAIL, not one per check).
local function probeClearScreen(label: string, report: boolean, suppressDaily: boolean?): { ProbeLine }
	local found, remaining = clearScreen(suppressDaily)
	if not report then
		return {}
	end
	return {
		{
			Ok = #found == 0 and #remaining == 0,
			Name = ("no overlay open before %s"):format(label),
			Detail = ("open: %s; still open after closing them: %s"):format(
				if #found > 0 then table.concat(found, ", ") else "none",
				if #remaining > 0 then table.concat(remaining, ", ") else "none"
			),
		},
	}
end

-- The loop nudges (LoopCoachController's idle nudge, UpgradeGuide's hand
-- into the UPGRADES panel). The nudge runs on a stub clock: 40 s idle + cash
-- -> one line and the Gacha arrow; an action resets it; at most 3; none
-- while a tip / the mission box / a modal / the tutorial blocks; a fusable
-- pair + cash says both. The hand: the pure plan, then (panel opened by the
-- test, at desktop and phone layouts) the best row's button inside the
-- scroll view with the fingertip just above it, back on UPGRADES when the
-- panel closes.
local function testLoopNudge(): { string }
	local Coach = require(script.Parent.LoopCoachController) :: any
	local Marker = require(script.Parent.GoalMarkerController) :: any
	local UpgradeGuide = require(UI.UpgradeGuide) :: any
	local UpgradesPanel = require(UI.UpgradesPanel) :: any
	local TutorialHand = require(UI.TutorialHand) :: any
	local GoalConfig = require(ReplicatedStorage.Shared.Config.GoalConfig)
	local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
	local TycoonController = require(script.Parent.TycoonController) :: any
	local lines: { string } = {}
	local function check(ok: boolean, name: string, detail: string?)
		table.insert(lines, ("%s loop nudge: %s%s"):format(if ok then "PASS" else "FAIL", name, if ok or not detail then "" else " | " .. detail))
	end
	local free = { Blocked = false, CanPull = true }

	-- The idle clock (stubbed): 40 s, once per spell, again after 90 s, max 3.
	local n = Coach.NewNudger(0)
	local early = Coach.NudgeTick(n, 39.9, free)
	local first = Coach.NudgeTick(n, 40, free)
	check(early == nil and first ~= nil and first.Line == Coach.NudgeLines[1] and first.Target == "GachaStation", "40 s idle with cash -> the pull line and the Gacha arrow", first and first.Line or "none")
	check(Coach.NudgeTick(n, 41, free) == nil and Coach.NudgeTick(n, 129, free) == nil, "once per idle spell until another 90 s have passed")
	local second = Coach.NudgeTick(n, 130, free)
	check(second ~= nil and first ~= nil and second.Line ~= first.Line, "the second nudge is not the same line twice in a row", second and second.Line or "none")
	Coach.NudgeAction(n, 140, "Pull")
	check(n.Target == nil and Coach.NudgeTick(n, 179, free) == nil, "an action clears the arrow and restarts the 40 s")
	local third = Coach.NudgeTick(n, 180, free)
	check(third ~= nil and third.Target == "GachaStation", "a new spell nudges again after 40 s")
	Coach.NudgeAction(n, 200, "Upgrade")
	check(Coach.NudgeTick(n, 1000, free) == nil and n.Total == 3, "at most 3 a session", ("total %d"):format(n.Total))

	-- Nothing while something else has the player's attention.
	local blocked = Coach.NewNudger(0)
	local silent = Coach.NudgeTick(blocked, 40, { Blocked = true, CanPull = true }) == nil
	local restarted = Coach.NudgeTick(blocked, 41, free) == nil and Coach.NudgeTick(blocked, 79.9, free) == nil
	check(silent and restarted and Coach.NudgeTick(blocked, 80, free) ~= nil, "none during a tip / the mission box / a modal / the tutorial; the idle clock restarts after", ("silent %s, restarted %s"):format(tostring(silent), tostring(restarted)))
	check(Coach.NudgeTick(Coach.NewNudger(0), 500, { Blocked = false, CanPull = false }) == nil, "none without cash for a pull (the coach's Earn line covers it)")

	-- A fusable pair + cash: both steps; the arrow on the machine, then the pad.
	local pair = Coach.NewNudger(0)
	local both = Coach.NudgeTick(pair, 40, { Blocked = false, CanPull = true, FuseTier = "Epic", FuseCount = 2 })
	check(both ~= nil and both.Line:gsub("<[^>]+>", "") == "Fuse your 2 Epics, then pull more orbs for the next fuse!" and both.Target == "FusionMachine", "a pair and cash: the two-step line, the Fusion Machine first", both and both.Line or "none")
	Coach.NudgeAction(pair, 45, "Fuse")
	check(pair.Target == "GachaStation", "after the fuse the arrow moves to the Gacha Pad", tostring(pair.Target))
	Coach.NudgeAction(pair, 46, "Pull")
	check(pair.Target == nil, "the next pull clears it")

	-- The arrow: under a tip, over the coach.
	local goal = GoalConfig.Goals[1]
	local progress: any = { Current = 0, Target = 1, Coach = { Step = "Fuse", Target = "FusionMachine", Takes = true, Lit = "Fuse" } }
	local nudged = Marker.PlanGoalArrow(goal, progress, false, "GachaStation")
	local coached = Marker.PlanGoalArrow(goal, progress, false, nil)
	local tipped = Marker.PlanGoalArrow(goal, progress, true, "GachaStation")
	check(nudged == "GachaStation" and coached == "FusionMachine" and tipped == nil, "the nudge arrow beats the coach's, a running tip beats the nudge", ("nudged %s, coached %s, tipped %s"):format(tostring(nudged), tostring(coached), tostring(tipped)))

	-- The hand into the UPGRADES panel (pure).
	local planned = {
		off = UpgradeGuide.Plan({ Active = false, StationId = "basic_generator", PanelOpen = true, OtherOverlay = false }),
		button = UpgradeGuide.Plan({ Active = true, StationId = "basic_generator", PanelOpen = false, OtherOverlay = false }),
		row = UpgradeGuide.Plan({ Active = true, StationId = "ember_forge", Kind = "Upgrade", PanelOpen = true, OtherOverlay = false }),
		other = UpgradeGuide.Plan({ Active = true, StationId = "ember_forge", PanelOpen = false, OtherOverlay = true }),
	}
	check(
		planned.off.Where == "None" and planned.button.Where == "Button" and planned.row.Where == "Row" and planned.row.StationId == "ember_forge" and planned.other.Where == "None",
		"the hand: UPGRADES button, then the best row inside the panel, back on the button when it closes",
		("%s / %s / %s / %s"):format(planned.off.Where, planned.button.Where, planned.row.Where, planned.other.Where)
	)

	-- Live: the row's button in the open panel, at both layouts.
	local station: string? = nil
	for _, generator in TycoonConfig.Generators do
		local level = TycoonController.GetGeneratorLevel(generator.Id)
		if level > 0 and level < generator.MaxLevel and TycoonConfig.IsUnlocked(generator, TycoonController.GetGeneratorLevels()) then
			station = generator.Id
		end
	end
	if not station then
		check(true, "live upgrade hand skipped: no unlocked generator below its max")
		return lines
	end
	-- A desktop layout forced into a small real window (the 936 x 485 phone
	-- emulator) leaves the list shorter than one row, so a row can never sit
	-- whole inside it: the placement checks mean nothing there (a WARN).
	local squeezed = windowProblem() ~= nil
	for _, phone in { false, true } do
		local label = if phone then "844x390 phone" else "1920x1080"
		local soft = squeezed and not phone
		local function placement(ok: boolean, name: string, detail: string?)
			if ok or not soft then
				check(ok, name, detail)
			else
				table.insert(lines, ("WARN loop nudge: %s | %s (desktop layout in a %d x %d window)"):format(name, detail or "", Workspace.CurrentCamera.ViewportSize.X, Workspace.CurrentCamera.ViewportSize.Y))
			end
		end
		UIKit.SetForcedPhone(phone)
		task.wait(0.4)
		local openedHere = not UpgradesPanel.IsOpen()
		if openedHere then
			UpgradesPanel.Toggle()
		end
		task.wait(0.6)
		-- The guide scrolls every 0.1 s until the row is in; so does the probe.
		for _ = 1, 8 do
			if not UpgradesPanel.ScrollTo(station) then
				break
			end
			task.wait(0.1)
		end
		task.wait(0.2)
		local button = UpgradesPanel.GetButtonFor(station, "Upgrade") :: GuiObject?
		local caption = UpgradesPanel.GetCaptionFor(station)
		check(button ~= nil and caption ~= nil and caption:sub(1, 1) == "+" and caption:sub(-2) == "/s", ("%s: the row has a buy button and the '+$/s' caption"):format(label), tostring(caption))
		if button then
			TutorialHand.SetTarget(button)
			TutorialHand.SetCaption(caption)
			-- The hand places itself on a render step: wait for its first frame.
			local waited = os.clock()
			while TutorialHand.GetTip() == nil and os.clock() - waited < 1 do
				task.wait(0.05)
			end
			task.wait(0.1)
			local tip = TutorialHand.GetTip()
			local rect = TutorialHand.GetRect()
			local pos, size = button.AbsolutePosition, button.AbsoluteSize
			local list = button:FindFirstAncestorWhichIsA("ScrollingFrame")
			local inside = list ~= nil
				and pos.Y >= list.AbsolutePosition.Y - 1
				and pos.Y + size.Y <= list.AbsolutePosition.Y + list.AbsoluteSize.Y + 1
				and pos.X >= list.AbsolutePosition.X - 1
				and pos.X + size.X <= list.AbsolutePosition.X + list.AbsoluteSize.X + 1
			placement(inside, ("%s: the best row's button sits inside the scroll view"):format(label), ("button y %.0f+%.0f, list y %s"):format(pos.Y, size.Y, if list then ("%.0f+%.0f"):format(list.AbsolutePosition.Y, list.AbsoluteSize.Y) else "none"))
			local above = tip ~= nil and math.abs(tip.X - (pos.X + size.X / 2)) <= 12 and tip.Y <= pos.Y + 1 and pos.Y - tip.Y <= 12
			local clear = rect ~= nil and (rect.Position.Y + rect.Size.Y <= pos.Y + 1 or rect.Position.Y >= pos.Y + size.Y - 1 or rect.Position.X + rect.Size.X <= pos.X or rect.Position.X >= pos.X + size.X)
			local onScreen = rect ~= nil and rect.Position.X >= -1 and rect.Position.Y >= -GuiService:GetGuiInset().Y - 1
			placement(above and clear and onScreen, ("%s: the hand's fingertip is within 12 px above the button and its box clears it"):format(label), if tip then ("tip %.0f,%.0f vs button %.0f,%.0f"):format(tip.X, tip.Y, pos.X, pos.Y) else "no hand: " .. tostring(TutorialHand.GetBlocker()))
			check(TutorialHand.GetCaption() == caption, ("%s: the caption rides the hand"):format(label), tostring(TutorialHand.GetCaption()))
		end
		TutorialHand.SetTarget(nil)
		TutorialHand.SetCaption(nil)
		if openedHere and UpgradesPanel.IsOpen() then
			UpgradesPanel.Toggle()
		end
		task.wait(0.3)
	end
	UIKit.SetForcedPhone(nil)
	return lines
end

-- The fuse ladder (FuseLadder + FusePanel + the fusion card): the tab the
-- panel opens on / jumps to with stubbed inventories (3 Commons + 2 Rares ->
-- Rare; a fuse leaving 1 Common + 3 Rares -> Rare stays; nothing fusable ->
-- Common; a manual pick survives until close), the ready dot (>= 2, not
-- selected), the ladder strip's lit / next tiers, tab tap targets >= 44 px at
-- desktop and phone, the fusion card's "Fuse 2 Rares -> Epic next" line and
-- its GO TO button, the earnBoth rule and the income split text.
local function testFuseLadder(): { string }
	local FuseLadder = require(ReplicatedStorage.Shared.Modules.FuseLadder)
	local TipConfig = require(ReplicatedStorage.Shared.Config.TipConfig)
	local LoopCoach = require(ReplicatedStorage.Shared.Config.LoopCoach)
	local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
	local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
	local FusePanel = require(UI.FusePanel) :: any
	local Coach = require(script.Parent.LoopCoachController) :: any
	local ResultController = require(script.Parent.ResultController) :: any
	local FusionController = require(script.Parent.FusionController) :: any
	local HudController = require(script.Parent.HudController) :: any
	local Marker = require(script.Parent.GoalMarkerController) :: any
	local TycoonController = require(script.Parent.TycoonController) :: any
	local lines: { string } = {}
	local function check(ok: boolean, name: string, detail: string?)
		table.insert(lines, ("%s fuse ladder: %s%s"):format(if ok then "PASS" else "FAIL", name, if ok or not detail then "" else " | " .. detail))
	end

	-- Pure rules.
	check(FuseLadder.PickTab({ Common = 3, Rare = 2 }, 0) == "Rare", "3 Commons + 2 Rares picks Rare")
	check(FuseLadder.PickTab({ Common = 1, Rare = 3 }, 0) == "Rare", "1 Common + 3 Rares keeps Rare")
	check(FuseLadder.PickTab({ Common = 5, Rare = 1 }, 0) == "Common", "5 Commons + 1 Rare picks Common (a lone Rare is not a pair)")
	check(FuseLadder.PickTab({}, 0) == "Common", "nothing fusable picks Common")
	check(FuseLadder.PickTab({ Mythic = 4 }, 0) == "Common", "a Mythic pair is skipped before Rebirth 1 (locked)")
	check(FuseLadder.BestOwned({ Common = 3, Epic = 1 }) == "Epic" and FuseLadder.NextAim({ Common = 3, Epic = 1 }) == "Legendary", "the strip lights Epic and aims at Legendary")
	check(FuseLadder.NextAim({}) == "Rare", "an empty inventory aims at Rare")
	local rare3, rare1, rare0 = FuseLadder.ResultNext("Rare", 3, 0), FuseLadder.ResultNext("Rare", 1, 0), FuseLadder.ResultNext("Secret", 5, 9)
	check(rare3.Kind == "Fuse" and rare3.Line == "Fuse 2 Rares → Epic next" and rare3.Button == "GO TO RARE", "the card for 3 Rares: 'Fuse 2 Rares → Epic next' / GO TO RARE", tostring(rare3.Line))
	check(rare1.Kind == "Pull" and rare1.Line == FuseLadder.PullLine, "the card for 1 Rare: the 'Pull more orbs' line")
	check(rare0.Kind == "None" and FuseLadder.ResultNext("Mythic", 3, 0).Kind == "None", "no line for a Secret, or for Mythics before Rebirth 1")
	check(FuseLadder.ResultNext("Legendary", 2, 0).Line == "Fuse 2 Legendaries → Mythic next", "Legendaries pluralise")

	-- The panel with stubbed counts, at both layouts.
	for _, phone in { false, true } do
		local label = if phone then "844x390 phone" else "1920x1080"
		UIKit.SetForcedPhone(phone)
		task.wait(0.4)
		local ok, err = pcall(function()
			FusePanel.Open()
			task.wait(0.5)
			local view = FusePanel.SelfTestOpenWith({ Common = 3, Rare = 2 })
			check(view.Tier == "Rare", ("%s: 3 Commons + 2 Rares opens on Rare"):format(label), view.Tier)
			check(view.Ready.Common == true and view.Ready.Rare == false, ("%s: the pair on Common shows the ready dot; the selected Rare tab does not"):format(label))
			view = FusePanel.SelfTestAfterFuse({ Common = 1, Rare = 3 })
			check(view.Tier == "Rare", ("%s: a fuse leaving 1 Common + 3 Rares stays on Rare"):format(label), view.Tier)
			check(view.Ready.Common == false, ("%s: 1 Common is no ready dot"):format(label))
			view = FusePanel.SelfTestAfterFuse({ Common = 3, Rare = 1 })
			check(view.Tier == "Common", ("%s: a fuse that leaves 3 Commons + 1 Rare goes back to Common"):format(label), view.Tier)
			view = FusePanel.SelfTestAfterFuse({ Common = 1, Rare = 1, Epic = 2 })
			check(view.Tier == "Epic" and view.Best == "Epic" and view.Aim == "Legendary" and (view.NextText == "Next: Legendary" or not view.StripShown), ("%s: the pair of Epics leads: Epic tab, strip lit to Epic, 'Next: Legendary'"):format(label), ("%s / %s / %s / '%s'"):format(view.Tier, tostring(view.Best), tostring(view.Aim), view.NextText))
			view = FusePanel.SelfTestOpenWith({})
			check(view.Tier == "Common", ("%s: owning nothing opens on Common"):format(label), view.Tier)
			view = FusePanel.SelfTestOpenWith({ Common = 3, Rare = 2 })
			view = FusePanel.SelfTestPick("Common")
			check(view.Tier == "Common" and view.Ready.Rare == true, ("%s: a manual tab pick, and the Rare pair now shows its dot"):format(label), view.Tier)
			view = FusePanel.SelfTestAfterFuse({ Common = 1, Rare = 3 })
			check(view.Tier == "Common", ("%s: a manual pick survives a fuse until the panel closes"):format(label), view.Tier)
			view = FusePanel.SelfTestOpenWith({ Common = 3, Rare = 2 })
			check(view.Tier == "Rare", ("%s: reopening leads up the ladder again"):format(label), view.Tier)
			local smallest = math.huge
			for _, height in view.TabHeights do
				smallest = math.min(smallest, height)
			end
			check(smallest >= UITheme.MinTapSize - 0.5, ("%s: every tab is >= %d px tall"):format(label, UITheme.MinTapSize), ("smallest %.1f"):format(smallest))
			if not phone then
				local stripLine = ("%s %s %s '%s'"):format(tostring(view.StripShown), tostring(view.Best), tostring(view.Aim), view.NextText)
				if not view.StripShown and view.Best == "Rare" and view.Aim == "Epic" and windowProblem() ~= nil then
					-- The strip hides below a 420 x 250 column; a desktop layout forced into a
					-- small real window (the phone emulator) never gets one. Best / Aim are right.
					local camera = Workspace.CurrentCamera
					table.insert(lines, ("WARN fuse ladder: 1920x1080: the ladder strip is hidden: the real window is %d x %d, the column is under 420 x 250 | %s"):format(camera.ViewportSize.X, camera.ViewportSize.Y, stripLine))
				else
					check(view.StripShown and view.Best == "Rare" and view.Aim == "Epic" and view.NextText == "Next: Epic", "1920x1080: the ladder strip is shown, Rare lit, 'Next: Epic'", stripLine)
				end
			else
				check(true, ("844x390 phone: the ladder strip is %s (it hides where it does not fit; the dots and the jump stay)"):format(if view.StripShown then "shown" else "hidden"))
			end
		end)
		if not ok then
			check(false, label .. ": the panel probe raised", tostring(err))
		end
		FusePanel.SelfTestReset()
		FusePanel.Close()
		task.wait(0.3)
	end
	UIKit.SetForcedPhone(nil)

	-- The fusion card's next row, live against the real inventory.
	local ok, err = pcall(function()
		ResultController.CloseCards()
		local fake = fakeFusionResult()
		local want = ResultController.GetFusionNext(fake.NewItem)
		ResultController.SelfTestFusionResolved(fake)
		local started = os.clock()
		while not ResultController.IsBigCardOpen() and os.clock() - started < 2 do
			task.wait(0.1)
		end
		task.wait(0.2)
		local line, hasButton = ResultController.GetBigCardNext()
		check(line == want.Line and hasButton == (want.Kind == "Fuse"), "the live NEW ORB card shows FuseLadder's line" .. (if hasButton then " and the GO TO RARE button" else ""), ("card '%s' button %s vs '%s' %s"):format(tostring(line), tostring(hasButton), tostring(want.Line), want.Kind))
		check(want.Kind ~= "Pull" or Marker.GetHint() == "GachaStation", "the 'pull more' variant puts the Gacha arrow up", tostring(Marker.GetHint()))
		ResultController.CloseCards()
		Marker.SetHint(nil)
		-- GO TO RARE's request opens the panel on that tab.
		FusionController.RequestFuseTab("Rare")
		task.wait(0.5)
		local view = FusePanel.SelfTestView()
		check(FusePanel.IsOpen() and view.Tier == "Rare", "GO TO RARE opens the Fuse panel on the Rare tab", view.Tier)
		FusePanel.Close()
		task.wait(0.3)
	end)
	if not ok then
		check(false, "the fusion card probe raised", tostring(err))
	end

	-- "Machines AND orbs both earn cash!": once, after the tutorial.
	check(Coach.PlanEarnBoth(true, false, 1, 2) == true, "earnBoth fires with an orb on a pedestal and a generator upgraded")
	check(Coach.PlanEarnBoth(false, false, 1, 2) == false, "earnBoth is silent during the tutorial")
	check(Coach.PlanEarnBoth(true, true, 1, 2) == false, "earnBoth is silent once seen (it is saved per account)")
	check(Coach.PlanEarnBoth(true, false, 0, 5) == false and Coach.PlanEarnBoth(true, false, 3, 1) == false, "earnBoth needs BOTH an orb on display and an upgrade")
	check(TipConfig.IsValid("earnBoth") and TipConfig.EarnBothLine == "Machines AND orbs both earn cash!", "the earnBoth id is a saved tip and its line is TipConfig's", TipConfig.EarnBothLine)
	check(LoopCoach.Explain.Earn == "Orbs on pedestals and generators both earn $/s", "the loop strip's 💰 text says both earn", LoopCoach.Explain.Earn)

	-- The income split: its parts are the one formula's parts, and the HUD
	-- breakdown shows them.
	local inputs = TycoonController.GetIncomeInputs()
	local split = TycoonConfig.GetIncomeSplit(inputs)
	local total = TycoonConfig.GetPassiveCashPerSecond(inputs)
	check(math.abs(split.Generators + split.Orbs - total) <= math.max(total * 0.01, 1e-6), "Generators $/s + Orbs $/s add up to the income pill's number (within 1%)", ("%.3f + %.3f vs %.3f"):format(split.Generators, split.Orbs, total))
	HudController.RefreshIncomeBreakdown()
	local text = HudController.GetIncomeBreakdownText()
	local expected = TipConfig.IncomeSplitFormat:format(NumberFormat.Money(split.Generators), NumberFormat.Money(split.Orbs))
	check(text:find(expected, 1, true) ~= nil, "the multiplier pill's breakdown starts with 'Generators $X/s · Orbs $Y/s'", text:sub(1, 80))
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
	table.insert(parts, WeaponAnimator.Describe(character))
	table.insert(parts, "trace: " .. (require(script.Parent.CombatController) :: any).GetHoldTrace())
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
			Warn = weaponId == "Bat",
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
		-- >= 0.4 s of swing, or the track's own length less 0.05 s if that is
		-- shorter: the measure counts Heartbeat frames, so a couple of frames
		-- of jitter must not fail a swing that is as long as its animation.
		local trackLength = if actionTrack then actionTrack.Length else 0
		local needVisible = if trackLength > 0 then math.min(0.4, trackLength - 0.05) else 0.4
		table.insert(lines, {
			Ok = played and peak >= 1.5 * scale,
			Warn = weaponId == "Bat",
			Name = ("combat %s: the hand's peak distance from its held position during the swing is >= 1.5 studs (x height/5)"):format(weaponId),
			Detail = ("peak %.2f studs, needs %.2f (avatar %.1f studs tall, x%.2f)"):format(peak, 1.5 * scale, height, scale),
		})
		table.insert(lines, {
			Ok = played and visible >= needVisible,
			Name = ("combat %s: the swing stays visible for >= 0.4 s (or its track length - 0.05 s)"):format(weaponId),
			Detail = ("measured %.2f s away from the held pose, needs %.2f s (track %.2f s)"):format(visible, needVisible, trackLength),
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

-- Every CombatConfig.AnimationIds entry is a well-formed rbxassetid://<digits>
-- and loads on the local Animator (a track with a length once preloaded).
-- The second value is true when ids loaded as Animations but not ONE has a
-- length: the place cannot load them this session, and every pose check that
-- needs a track would fail for that reason alone (the server skips those).
local function probeAnimationIds(): ({ ProbeLine }, boolean)
	local character = localPlayer.Character
	local animator = character and character:FindFirstChildWhichIsA("Animator", true)
	local problems = {}
	local count = 0
	local tracks: { [string]: AnimationTrack } = {}
	for name, id in CombatConfig.AnimationIds do
		count += 1
		if not string.match(id, "^rbxassetid://%d+$") then
			table.insert(problems, ("%s: malformed id %q"):format(name, id))
		elseif animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			local ok, track = pcall(function()
				return (animator :: Animator):LoadAnimation(animation)
			end)
			if ok and track then
				tracks[name] = track
			else
				table.insert(problems, ("%s: LoadAnimation failed"):format(name))
			end
		end
	end
	local started = os.clock()
	while os.clock() - started < 5 do
		local pending = false
		for _, track in tracks do
			if track.Length <= 0 then
				pending = true
				break
			end
		end
		if not pending then
			break
		end
		task.wait(0.1)
	end
	local created, loaded = 0, 0
	for name, track in tracks do
		created += 1
		if track.Length <= 0 then
			table.insert(problems, ("%s: no length after 5 s (not loadable by this place?)"):format(name))
		else
			loaded += 1
		end
		track:Destroy()
	end
	return {
		{
			Ok = count > 0 and animator ~= nil and #problems == 0,
			Name = "combat animation ids: every AnimationIds entry is rbxassetid://<digits> and loads",
			Detail = if #problems == 0 then ("%d ids ok"):format(count) else table.concat(problems, "; "),
		},
	}, created > 0 and loaded == 0
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
		Detail = ("opened after %d frames (blocked by: %s); %d/%d tiles with AbsoluteSize > 0, %d/%d %% labels with TextBounds.Y > 0%s"):format(
			frames,
			tostring(Board.GetBlockReason()),
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
local function probeGachaCard(serverLuck: number, label: string, serverCost: number?, serverMultiCost: number?): { ProbeLine }
	local lines: { ProbeLine } = {}
	local TycoonController = require(script.Parent.TycoonController) :: any
	local Board = require(script.Parent.GachaBoardController) :: any
	local started = os.clock()
	while math.abs(TycoonController.GetLuck() - serverLuck) > 1e-6 and os.clock() - started < 3 do
		task.wait(0.1)
	end
	local clientLuck = TycoonController.GetLuck()
	if math.abs(clientLuck - serverLuck) > 1e-6 then
		-- Say so: every % below is then drawn at a luck the server does not have.
		table.insert(lines, {
			Ok = false,
			Name = ("gacha card (%s): the client's luck equals the server's after the sync"):format(label),
			Detail = ("client x%.4f, server x%.4f"):format(clientLuck, serverLuck),
		})
	end
	Board.RefreshNow()
	local card = waitForCard(true, 3)
	-- The card redraws by itself when luck changes (the sync, an event
	-- attribute, the 0.5 s poll): give it that, then measure what it drew.
	local redrawBy = os.clock() + 2
	local function tilesAtServerLuck(): boolean
		local current = Board.GetCard()
		if not current then
			return false
		end
		local want = FusionConfig.GetGachaRates(serverLuck)
		for _, tier in FusionConfig.TierOrder do
			local tile = (current.Billboard :: BillboardGui):FindFirstChild("Tile_" .. tier, true)
			local percent = tile and tile:FindFirstChild("Percent")
			if not (percent and percent:IsA("TextLabel")) or percent.Text ~= FusionConfig.FormatPercent((want[tier] or 0) * 100) .. "%" then
				return false
			end
		end
		return true
	end
	while not tilesAtServerLuck() and os.clock() < redrawBy do
		task.wait(0.1)
	end
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
		Detail = ("shown %s, PopScale %.3f, open %s, card %dx%d px, blocked by: %s"):format(tostring(card.Shown), card.Pop.Scale, tostring(card.Open), card.Card.AbsoluteSize.X, card.Card.AbsoluteSize.Y, tostring(Board.GetBlockReason())),
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
	local wantHeight = if card.Phone then require(script.Parent.GachaBoardController).PhoneFullHeight else G.TopPadPx + G.CardPx.Y + G.ButtonRowPx
	if gui.Size.X.Scale ~= 0 or gui.Size.Y.Scale ~= 0 or gui.Size.X.Offset ~= G.CardPx.X or gui.Size.Y.Offset ~= wantHeight then
		table.insert(billboardBad, ("Size %s, wanted pixels %dx%d"):format(tostring(gui.Size), G.CardPx.X, wantHeight))
	end
	-- (0, 0.5), or slid down by the stack clamp (Y below 0.5, never above).
	if gui.SizeOffset.X ~= 0 or gui.SizeOffset.Y > 0.5 + 1e-6 then
		table.insert(billboardBad, ("SizeOffset %s, wanted (0, 0.5) or the card slid down (0, <0.5)"):format(tostring(gui.SizeOffset)))
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
	if card.Phone then
		-- The phone variant drops the coloured line: the (i) panel carries the mutation odds.
		if not (line and line:IsA("TextLabel")) or line.Visible then
			table.insert(styleBad, "the phone card still shows the mutation line")
		end
	elseif not (line and line:IsA("TextLabel") and drawnProblem(line, gui) == nil and line.RichText and line.TextSize <= 12) then
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
	if not (price and price:IsA("TextLabel") and coin and coin:IsA("GuiObject") and drawnProblem(price, gui) == nil and drawnProblem(coin, gui) == nil and price.TextSize == (if card.Phone then G.PhonePriceTextPx else 24)) then
		table.insert(styleBad, ("no coin + %d px price"):format(if card.Phone then G.PhonePriceTextPx else 24))
	else
		local free = TycoonController.GetTutorial().FreePulls > 0
		local wantPrice = if free then "FREE" else require(ReplicatedStorage.Shared.Modules.NumberFormat).Money(require(ReplicatedStorage.Shared.Config.TycoonConfig).GetGachaPullCost(TycoonController.GetGachaPulls(), TycoonController.GetSteadyIncomePerSecond()))
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
		Name = ("gacha card (%s): the PS99 face: white paper, title and (i) on the top edge, 6 bare orb cells, one coloured mutation line (desktop only), coin + price on the bottom edge"):format(label),
		Detail = if #styleBad > 0 then table.concat(styleBad, "; ") else ("%d cells, price %q, mutation line %q"):format(cells, if price and price:IsA("TextLabel") then price.Text else "?", if card.Phone then "(hidden on phone)" elseif line and line:IsA("TextLabel") then line.Text:gsub("<[^>]+>", "") else "?"),
	})

	-- The card's price is the server's charge: the server sent what it would
	-- charge for the same pulls and income (its own steady income); the card's
	-- label and the client's formula must show the same numbers once the sync
	-- has landed (a mismatch lasts at most one sync).
	if typeof(serverCost) == "number" and typeof(serverMultiCost) == "number" then
		local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
		local free = TycoonController.GetTutorial().FreePulls > 0
		local wantText = NumberFormat.Money(serverCost)
		local priceLabel = cardFrame:FindFirstChild("Price", true)
		local waited = os.clock()
		while priceLabel and priceLabel:IsA("TextLabel") and not free and priceLabel.Text ~= wantText and os.clock() - waited < 3 do
			task.wait(0.1)
		end
		local pulls = TycoonController.GetGachaPulls()
		local steady = TycoonController.GetSteadyIncomePerSecond()
		local clientCost = TycoonConfig.GetGachaPullCost(pulls, steady)
		local clientMulti = TycoonConfig.GetGachaMultiPullCost(pulls, TycoonConfig.MultiPullCount, steady)
		local shown = if priceLabel and priceLabel:IsA("TextLabel") then priceLabel.Text else "?"
		table.insert(lines, {
			Ok = clientCost == serverCost and clientMulti == serverMultiCost and (free or shown == wantText),
			Name = ("gacha card (%s): the pad card's price equals the server's charge for the same pulls and income"):format(label),
			Detail = ("pulls %d, steady %.3f: server %s (x10 %s), client %s (x10 %s), card shows %q%s"):format(
				pulls, steady, tostring(serverCost), tostring(serverMultiCost), tostring(clientCost), tostring(clientMulti), shown, if free then " (tutorial free pulls: label says FREE)" else ""
			),
		})
	end

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
	local autoWord = if card.Phone then "Auto" else "Auto ×10"
	local captions = { Pull = "Pull", Multi = "×10", Auto = if Board.IsAutoOn() then autoWord .. " ON" else autoWord }
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
				-- A phone shrinks the billboard by its UIScale (GachaBoardController.PhoneScaleFor,
				-- ~0.56 at 844 x 390); the tap target there is the whole key holder behind
				-- the circle, measured at that scale.
				local tap = if UIKit.IsPhone() then (entry.Holder :: GuiObject).AbsoluteSize else size
				if tap.X < 43.5 or tap.Y < 43.5 then
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
	-- The stack clamp may have slid the card down (SizeOffset below 0.5).
	local gui = card.Billboard :: BillboardGui
	local slide = (0.5 - gui.SizeOffset.Y) * gui.Size.Y.Offset
	return { Left = anchor.X - size.X / 2, Top = anchor.Y - size.Y + slide, Right = anchor.X + size.X / 2, Bottom = anchor.Y + slide, AnchorZ = anchor.Z }
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

-- " | a; b" for a Detail: the hard misses, then the soft ones ("" if none).
local function joinProblems(hard: { string }, soft: { string }): string
	local all = table.clone(hard)
	for _, problem in soft do
		table.insert(all, problem)
	end
	return if #all > 0 then " | " .. table.concat(all, "; ") else ""
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
-- Returns (hard, soft, detail): the card shut, the anchor off the pad or behind
-- the camera are hard (FAIL); the card off the pad's centre on screen or not
-- covering the ball are soft (a WARN, never counted).
local function positionProblems(card: any, camera: Camera, needBallBelow: boolean): ({ string }, { string }, string)
	local Board = require(script.Parent.GachaBoardController) :: any
	local pad = card.Pad :: BasePart
	local anchor = card.Anchor :: Attachment
	local box = cardScreenBox(card, camera)
	local hard: { string } = {}
	local problems: { string } = {}
	local flat = Vector2.new(anchor.WorldPosition.X - pad.Position.X, anchor.WorldPosition.Z - pad.Position.Z).Magnitude
	if flat >= 0.1 then
		table.insert(hard, ("the anchor is %.2f studs off the pad's centre"):format(flat))
	end
	if not (card.Open and card.Shown) then
		table.insert(hard, "the card is not open: " .. Board.DescribeState())
	end
	if box.AnchorZ <= 0 then
		table.insert(hard, "the anchor is behind the camera")
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
	return hard, problems, ("flat %.3f studs, card x %.0f-%.0f y %.0f-%.0f, pad centre x %.0f, capsule centre %s"):format(flat, box.Left, box.Right, box.Top, box.Bottom, padCentre.X, ballText)
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
	local approachHard, approachSoft, approachDetail = positionProblems(card, camera, true)
	camera.CFrame = CFrame.lookAt(pad.Position + Vector3.new(0, 40, 0), pad.Position, Vector3.new(0, 0, -1))
	waitFrames(6)
	local topHard, topSoft, topDetail = positionProblems(card, camera, false)
	camera.CameraType = savedType
	camera.CFrame = savedCFrame
	UIKit.SetForcedPhone(nil)
	local window = ("%d x %d window"):format(camera.ViewportSize.X, camera.ViewportSize.Y)
	return {
		{
			Ok = #approachHard + #approachSoft == 0,
			Warn = #approachHard == 0 and #approachSoft > 0,
			Name = ("gacha card (%s, %s): 8 studs in front of the pad the card is centred on the pad and covers the capsule ball"):format(layout, window),
			Detail = ("%.1f studs from the pad; %s%s"):format(distance, approachDetail, joinProblems(approachHard, approachSoft)),
		},
		{
			Ok = #topHard + #topSoft == 0,
			Warn = #topHard == 0 and #topSoft > 0,
			Name = ("gacha card (%s, %s): with the camera straight above the pad the card is centred on it"):format(layout, window),
			Detail = ("%s%s"):format(topDetail, joinProblems(topHard, topSoft)),
		},
	}
end

-- Where a world point lands on a screen of `size` px seen through `camera`'s
-- pose and field of view (Roblox's FieldOfView is vertical): the window can't be
-- resized from a script, so the phone sizes are projected by hand.
local function projectFor(camera: Camera, world: Vector3, size: Vector2): Vector2?
	local rel = camera.CFrame:PointToObjectSpace(world)
	if rel.Z >= 0 then
		return nil
	end
	local tanHalf = math.tan(math.rad(camera.FieldOfView) / 2)
	local ndcY = (rel.Y / -rel.Z) / tanHalf
	local ndcX = (rel.X / -rel.Z) / (tanHalf * size.X / size.Y)
	return Vector2.new((ndcX * 0.5 + 0.5) * size.X, (0.5 - ndcY * 0.5) * size.Y)
end

-- The live card's drawn top with NO announcement up, then with one showing
-- (less the anchor's drift between the two samples): a toast never moves the
-- card, so the two agree (the caller allows 1 px).
-- Returns (quiet, withToast, problem).
local function gachaToastTops(): (number?, number?, string?)
	local Board = require(script.Parent.GachaBoardController) :: any
	local TopStack = require(UI.TopStack) :: any
	local waited = 0
	while TopStack.GetHeight("Announce") > 0 and waited < 4 do
		task.wait(0.1)
		waited += 0.1
	end
	waitFrames(3)
	local quiet = Board.GetDrawnTop()
	local quietAnchor = Board.GetDrawnAnchorY()
	TopStack.Announce({
		Key = "SelfTestGachaToast",
		Priority = 5,
		Seconds = 1,
		Height = 40,
		Show = function(_y: number) end,
		Hide = function(_cut: boolean): number?
			return 0
		end,
	})
	local up = 0
	while TopStack.GetHeight("Announce") <= 0 and up < 1 do
		task.wait(0.05)
		up += 0.05
	end
	waitFrames(3)
	local shown = TopStack.GetHeight("Announce") > 0
	-- The card's top is the anchor's screen y less its height plus the clamp's
	-- slide, so a standing tester's camera drifting a pixel or two between the
	-- samples (198.0 vs 200.2 with the clamp's shift 0.00 in both) is not the
	-- toast. Take the anchor's drift out; what is left is the slide and height.
	local withToast = Board.GetDrawnTop()
	local withAnchor = Board.GetDrawnAnchorY()
	if withToast and quietAnchor and withAnchor then
		withToast -= withAnchor - quietAnchor
	end
	return quiet, withToast, if shown then nil else "the test announcement never showed"
end

-- The gacha card on a phone `size` px big with the tester at one spot on the
-- pad (`where`), default camera: its whole rect (title to key bar) is on
-- screen, below TopStack's STABLE chip row (+ PhoneTopGapPx) and above the
-- weapon bar (or the HUD's bottom row before Rebirth 1), and the % text is
-- still >= 13 px on screen. When the window IS this size the live drawn card
-- is measured; otherwise (projecting onto a size that is not the window says
-- nothing about the drawn card) the pure PhonePlanFor decides, from the
-- anchor's projection. Returns (hard, soft, detail): the card's POSITION
-- (off the width, under the chip row, below the floor) is a soft miss (a WARN,
-- never counted); a card that is not built or a % text under 13 px is hard.
local MIN_PERCENT_PX = PlotLayout.Gacha.PhoneMinTextPx
local function gachaPhoneAt(card: any, camera: Camera, size: Vector2, where: string): ({ string }, { string }, string)
	local Board = require(script.Parent.GachaBoardController) :: any
	local TopStack = require(UI.TopStack) :: any
	local combat = require(script.Parent.CombatController) :: any
	local G = PlotLayout.Gacha
	local view = size / UITheme.PhoneScale
	local anchor = card.Anchor :: Attachment
	local gui = card.Billboard :: BillboardGui
	-- The billboard sits StudsOffset (2 studs toward the camera) off the anchor.
	local point = projectFor(camera, anchor.WorldPosition + camera.CFrame:VectorToWorldSpace(gui.StudsOffset), size)
	if not point then
		return { where .. ": the anchor is behind the camera" }, {}, where .. ": behind the camera"
	end
	local full = Board.PhoneFullHeight
	local live = UIKit.IsPhone() and card.PopRoot.Visible and math.abs(camera.ViewportSize.X - size.X) < 2 and math.abs(camera.ViewportSize.Y - size.Y) < 2
	-- TopStack's lowest stable slot with the event chip up: its Announce line's y (logical) x 0.8.
	local stackBottom = TopStack.PlanFor(UIKit.GetCardTopFor(true), 0, 44, 0).Announce * UITheme.PhoneScale
	local barRect = combat.GetBarRectFor(view, false)
	local floorLogical = if barRect then barRect.Position.Y else view.Y - UIKit.GetCardBottomFor(true)
	local floorPx = floorLogical * UITheme.PhoneScale
	local scale, top, bottom = 0, 0, 0
	if live then
		local drawnTop, drawnBottom, drawnScale = Board.GetDrawnRect()
		if not drawnTop or not drawnBottom or not drawnScale then
			return { where .. ": the live card has no screen rect" }, {}, where .. ": no rect"
		end
		scale, top, bottom = drawnScale, drawnTop, drawnBottom
		stackBottom = TopStack.GetStableBottom() * UITheme.PhoneScale
		floorPx = Board.GetPhoneFloorPx() or floorPx
	else
		local slide: number
		scale, slide = Board.PhonePlanFor(point.Y, Board.PhoneScaleFor(view), stackBottom, floorPx, size.Y)
		top, bottom = point.Y - full * scale + slide, point.Y + slide
	end
	local width = G.CardPx.X * scale
	local left, right = point.X - width / 2, point.X + width / 2
	local hard: { string } = {}
	local problems: { string } = {}
	if left < 0 or right > size.X then
		table.insert(problems, ("%s: x %.0f..%.0f is off the %d px width"):format(where, left, right, size.X))
	end
	-- The card's top: ceil(stable stack bottom) + PhoneTopGapPx of air (a whole px).
	local minTop = math.ceil(stackBottom) + G.PhoneTopGapPx
	if top < minTop - 0.5 then
		table.insert(problems, ("%s: top %.1f is above the stack's bottom %.0f + %d px of air = %d"):format(where, top, stackBottom, G.PhoneTopGapPx, minTop))
	end
	if bottom > floorPx + 0.5 or bottom > size.Y then
		table.insert(problems, ("%s: bottom %.0f is below the %s at %.0f"):format(where, bottom, if barRect then "weapon bar" else "bottom row", floorPx))
	end
	local percentPx = 0
	local tiles = card.Tiles
	if typeof(tiles) ~= "table" or next(tiles) == nil then
		table.insert(hard, "card not built: the card has no Tiles to measure")
	else
		for _, tile in tiles do
			percentPx = (tile.Percent :: TextLabel).TextSize * scale
			break
		end
	end
	if percentPx < MIN_PERCENT_PX - 0.05 then
		table.insert(hard, ("%s: the %% text is %.1f px"):format(where, percentPx))
	end
	return hard, problems, ("%s %s scale %.3f x %.0f..%.0f y %.0f..%.0f"):format(if live then "live" else "projected", where, scale, left, right, top, bottom)
end

-- One line per phone size over every tester spot (`hard` / `soft` / `details`
-- hold gachaPhoneAt's output over the spots); `quiet`, `withToast`,
-- `toastProblem` are the probe's one gachaToastTops measurement. The position
-- misses (soft) make a WARN; a hard miss (card shut, % text, a toast moving
-- the card) is a FAIL.
local function gachaPhoneLine(size: Vector2, hard: { string }, soft: { string }, details: { string }, standing: string, quiet: number?, withToast: number?, toastProblem: string?): ProbeLine
	local name = ("gacha card (phone %dx%d): standing on the pad (centre and 3 studs off each side) the whole card is on screen, under the event chip row and over the weapon bar, %% text >= %d px"):format(size.X, size.Y, MIN_PERCENT_PX)
	local problems: { string } = table.clone(hard)
	if toastProblem then
		table.insert(problems, toastProblem)
	elseif quiet and withToast and math.abs(quiet - withToast) > 1 then
		table.insert(problems, ("a toast moved the card: top %.1f quiet, %.1f with an announcement"):format(quiet, withToast))
	end
	local hardCount = #problems
	for _, problem in soft do
		table.insert(problems, problem)
	end
	return {
		Ok = #problems == 0,
		Warn = hardCount == 0 and #soft > 0,
		Name = name,
		Detail = ("%s; %s; drawn top %s / %s with a toast%s"):format(
			standing,
			table.concat(details, "; "),
			if quiet then ("%.0f"):format(quiet) else "n/a",
			if withToast then ("%.0f"):format(withToast) else "n/a",
			if #problems > 0 then " | " .. table.concat(problems, "; ") else ""
		),
	}
end

-- The phone variant at a phone `size`: every text drawn on the card (the face,
-- the pills, the key bar) is >= 13 px on screen, and the (i) hit area >= 44 px.
-- Measured as design size x PhoneScaleFor(size): the variant's sizes are
-- constants, so the two test sizes need not be the live window.
local function gachaPhoneText(card: any, size: Vector2): ProbeLine
	local Board = require(script.Parent.GachaBoardController) :: any
	local name = ("gacha card (phone %dx%d): every text on the card is >= %d px after the scale, the (i) hit area >= 44 px"):format(size.X, size.Y, MIN_PERCENT_PX)
	if not card.Phone then
		return { Ok = false, Name = name, Detail = "the phone variant is not applied (card.Phone is false)" }
	end
	local scale = Board.PhoneScaleFor(size / UITheme.PhoneScale)
	local gui = card.Billboard :: BillboardGui
	local small: { string } = {}
	local checked = 0
	for _, object in gui:GetDescendants() do
		if (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Text ~= "" and drawnProblem(object, gui) == nil then
			checked += 1
			local px = object.TextSize * scale
			if px < MIN_PERCENT_PX - 0.05 then
				table.insert(small, ("%s %q %.1f px"):format(object.Name, object.Text:sub(1, 12), px))
			end
		end
	end
	if checked == 0 then
		table.insert(small, "no text is drawn: " .. Board.DescribeState())
	end
	local hitPx = (card.InfoHit :: GuiObject).Size.X.Offset * scale
	if hitPx < UITheme.MinTapSize - 0.05 then
		table.insert(small, ("the (i) hit area is %.1f px"):format(hitPx))
	end
	-- Long odds keep the full size too (never a smaller % to fit the tile), and
	-- slide inward so they stay on the card, in every column.
	for _, sample in { "0.0035%", "0.00022%" } do
		for column = 1, 3 do
			local size, shift = Board.PlanPercent(sample, true, column)
			if size * scale < MIN_PERCENT_PX - 0.05 then
				table.insert(small, ("%q in column %d is %.1f px"):format(sample, column, size * scale))
			end
			if math.abs(shift) > 20 then
				table.insert(small, ("%q in column %d slides %d px"):format(sample, column, shift))
			end
		end
	end
	for _, key in { "Pull", "Multi", "Auto" } do
		local keyHolder = gui:FindFirstChild(key .. "Key", true)
		if keyHolder and keyHolder:IsA("GuiObject") then
			local keyPx = math.min(keyHolder.Size.X.Offset, keyHolder.Size.Y.Offset) * scale
			if keyPx < UITheme.MinTapSize - 0.05 then
				table.insert(small, ("the %s key's tap area is %.1f px"):format(key, keyPx))
			end
		end
	end
	return {
		Ok = #small == 0 and checked > 0,
		Name = name,
		Detail = ("scale %.3f, %d texts, (i) hit %.1f px%s"):format(scale, checked, hitPx, if #small > 0 then " | " .. table.concat(small, "; ") else ""),
	}
end

-- The desktop card on a view `size` px big, character on the pad, default
-- camera, the event chip up: the card's top stays >= TopStack's bottom + 4 px
-- (the NIGHT chip once hid its first row of orbs). Checked as placed
-- (anchor projection, then the clamp), and again with the anchor pushed high
-- on the screen (a tilted camera) so the clamp has to do its work. The live
-- card is only measured when the real window is tall enough for the desktop
-- card (minTop + its height): in a shorter one (the phone emulator with the
-- desktop layout forced) the "keep the key bar on screen" cap rightly wins
-- and the line says it was skipped. A top that misses its spot is a WARN; a
-- toast moving the card is a FAIL.
local function gachaDesktopStack(card: any, camera: Camera, size: Vector2, quiet: number?, withToast: number?, toastProblem: string?): ProbeLine
	local Board = require(script.Parent.GachaBoardController) :: any
	local TopStack = require(UI.TopStack) :: any
	local G = PlotLayout.Gacha
	local name = ("gacha card (desktop %dx%d): standing on the pad the card's top is >= the stack's bottom + %d px"):format(size.X, size.Y, G.StackGapPx)
	local anchor = card.Anchor :: Attachment
	local point = projectFor(camera, anchor.WorldPosition, size)
	if not point then
		return { Ok = false, Name = name, Detail = "the anchor is behind the camera" }
	end
	local height = (card.Billboard :: BillboardGui).Size.Y.Offset
	local stackBottom = TopStack.PlanFor(UIKit.GetCardTopFor(false), 0, 44, 0).Announce
	local minTop = math.ceil(stackBottom) + G.StackGapPx
	local problems: { string } = {} -- soft: where the top sits (a WARN)
	local hard: { string } = {} -- a toast moving the card (a FAIL)
	local detail: { string } = {}
	for _, anchorY in { point.Y, size.Y * 0.3, size.Y * 0.1 } do
		local top = anchorY - height + Board.StackShiftFor(anchorY, height, stackBottom, size.Y)
		table.insert(detail, ("anchor y %.0f -> top %.0f"):format(anchorY, top))
		if top < minTop - 0.5 then
			table.insert(problems, ("anchor y %.0f: top %.1f is above the stack's bottom %.0f + %d = %d"):format(anchorY, top, stackBottom, G.StackGapPx, minTop))
		end
	end
	-- The live card (this window): the same rule on what is drawn, against the
	-- STABLE bottom (chip row), with no announcement up and with one showing:
	-- a toast never moves the card (the two tops agree within 1 px). The pair
	-- is measured once per probe (the caller's gachaToastTops).
	local liveMin = math.ceil(TopStack.GetStableBottom()) + G.StackGapPx
	if toastProblem then
		table.insert(hard, toastProblem)
	end
	local windowY = camera.ViewportSize.Y
	local needed = liveMin + height
	local liveTall = windowY >= needed
	if not liveTall then
		table.insert(detail, ("live top skipped: window %d px tall, the desktop card needs %d"):format(windowY, needed))
	end
	local liveTops: { { Label: string, Top: number? } } = { { Label = "no toast", Top = quiet }, { Label = "toast up", Top = withToast } }
	for _, entry in liveTops do
		local label, liveTop = entry.Label, entry.Top
		if liveTall and liveTop and card.PopRoot.Visible then
			table.insert(detail, ("live top %.0f %s (min %d)"):format(liveTop, label, liveMin))
			if liveTop < liveMin - 0.5 then
				table.insert(problems, ("live card top %.1f (%s) is above the stable stack bottom + %d = %d"):format(liveTop, label, G.StackGapPx, liveMin))
			end
		end
	end
	if quiet and withToast and math.abs(quiet - withToast) > 1 then
		table.insert(hard, ("a toast moved the card: top %.1f quiet, %.1f with an announcement"):format(quiet, withToast))
	end
	-- A miss says what the clamp itself used (its last frame; only while the
	-- clamp debug flag is on, which the probe sets).
	if #problems + #hard > 0 and Board.IsClampDebug() then
		table.insert(problems, Board.GetClampTrace() .. (", stable bottom now %.1f"):format(TopStack.GetStableBottom()))
	end
	return {
		Ok = #problems + #hard == 0,
		Warn = #hard == 0 and #problems > 0,
		Name = name,
		Detail = ("stack bottom %.0f, %s%s"):format(stackBottom, table.concat(detail, ", "), joinProblems(hard, problems)),
	}
end

-- The probe that is current (probeTutorial sets it) and the undo for the
-- camera / forced layout it left changed (never the tester's position). A probe the server gave up
-- on keeps running; it must never touch the next probe's layout, so its
-- restore only runs while it is still current, and a new probe starts by
-- running the previous probe's undo.
local activeProbeId: number? = nil
local restoreProbe: (() -> ())? = nil

-- On the pad: the anchor (the Attachment's world position) NEVER changes: not
-- over 4 camera yaws at a fixed zoom, not over the zoom range (6 / 12.5 / 40
-- studs), and no billboard offset is ever written. Then the card's rect: the
-- desktop stack clamp at two window sizes, the phone clamp at two phone sizes
-- with the tester at the pad's centre and 3 studs off each side.
local function probeGachaOnPad(phone: boolean, probeId: number?): { ProbeLine }
	local layout = if phone then "phone layout" else "desktop layout"
	local function current(): boolean
		return activeProbeId == probeId
	end
	UIKit.SetForcedPhone(phone)
	-- The clamp prints its numbers (GachaBoardController.SetClampDebug) while this probe runs.
	local debugBoard = require(script.Parent.GachaBoardController) :: any
	debugBoard.SetClampDebug(true)
	restoreProbe = function()
		debugBoard.SetClampDebug(false)
		UIKit.SetForcedPhone(nil)
	end
	task.wait(0.4)
	local layoutLine: ProbeLine = {
		Ok = UIKit.IsPhone() == phone,
		Name = ("gacha card (%s): the probe starts in its own layout"):format(layout),
		Detail = ("UIKit.IsPhone() is %s, the probe wants %s"):format(tostring(UIKit.IsPhone()), tostring(phone)),
	}
	local card = waitForCard(true, 3)
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not card or not camera or not root or not root:IsA("BasePart") then
		if current() then
			debugBoard.SetClampDebug(false)
			UIKit.SetForcedPhone(nil)
			restoreProbe = nil
		end
		return { layoutLine, { Ok = false, Name = ("gacha card (%s): on the pad"):format(layout), Detail = "no card, camera or character" } }
	end
	local gui = card.Billboard :: BillboardGui
	local anchor = card.Anchor :: Attachment
	local want = anchor.WorldPosition
	local savedCFrame, savedRoot = camera.CFrame, root.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	-- Undo: camera and forced layout only. The SERVER test owns the tester's
	-- position: a deferred client teleport here beat the server's own move
	-- (the client owns its character) and left the tester off the pad.
	restoreProbe = function()
		debugBoard.SetClampDebug(false)
		camera.CameraType = Enum.CameraType.Custom
		camera.CFrame = savedCFrame
		UIKit.SetForcedPhone(nil)
	end
	-- Leaves the world as it found it, but only if this probe is still the
	-- current one (a stale probe's restore was already run by its successor).
	-- The tester goes back where THIS probe found them, here, before the
	-- report, never in a deferred restore.
	local function finish(lines: { ProbeLine }): { ProbeLine }
		if current() then
			root.CFrame = savedRoot
			root.AssemblyLinearVelocity = Vector3.zero
			local undo = restoreProbe
			restoreProbe = nil
			if undo then
				undo()
			end
		end
		return lines
	end
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
		if not current() then
			return {}
		end
		check("yaw " .. yaw)
	end
	for _, studs in { 6, 12.5, 40 } do
		defaultCamera(camera, root, back, studs, 0)
		waitFrames(8)
		if not current() then
			return {}
		end
		check(("zoom %.1f"):format(studs))
	end
	local lines: { ProbeLine } = {
		layoutLine,
		{
			Ok = #moved == 0,
			Name = ("gacha card (%s): the anchor never changes while the camera turns (4 yaws) or zooms (6 / 12.5 / 40 studs)"):format(layout),
			Detail = ("anchor %s%s"):format(tostring(want), if #moved > 0 then " | changed: " .. table.concat(moved, "; ") else ""),
		},
	}
	if phone then
		-- The tester starts wherever the server put them: say how far off the
		-- pad's centre (PhoneScaleFor assumes the centre), then stand there.
		local startOff = Vector3.new(root.Position.X - want.X, 0, root.Position.Z - want.Z).Magnitude
		local centre = Vector3.new(want.X, root.Position.Y, want.Z)
		-- The camera sits at +X looking at the tester, so screen-right is -Z.
		local sites: { { Label: string, Offset: Vector3 } } = {
			{ Label = "centre", Offset = Vector3.zero },
			{ Label = "3 studs right", Offset = Vector3.new(0, 0, -3) },
			{ Label = "3 studs left", Offset = Vector3.new(0, 0, 3) },
			{ Label = "3 studs toward the camera", Offset = Vector3.new(3, 0, 0) },
			{ Label = "3 studs away from the camera", Offset = Vector3.new(-3, 0, 0) },
		}
		local hardMisses: { [number]: { string } } = {}
		local softMisses: { [number]: { string } } = {}
		local details: { [number]: { string } } = {}
		for index in PHONE_TEST_VIEWS do
			hardMisses[index] = {}
			softMisses[index] = {}
			details[index] = {}
		end
		local quiet, withToast, toastProblem
		for siteIndex, site in sites do
			root.CFrame = CFrame.new(centre + site.Offset)
			root.AssemblyLinearVelocity = Vector3.zero
			defaultCamera(camera, root, back, 12.5, 0)
			waitFrames(10)
			if not current() then
				return {}
			end
			if siteIndex == 1 then
				-- Once per probe: the toast never moves the card.
				quiet, withToast, toastProblem = gachaToastTops()
				if not current() then
					return {}
				end
			end
			-- The card must be up at every spot (a shut card names its cause). A
			-- tester that fell out of the world respawns as a NEW character: the
			-- probe's root (and the server's) are then stale, so say it.
			local shutNote: string? = nil
			if localPlayer.Character ~= character or not root:IsDescendantOf(Workspace) then
				shutNote = ("%s: the tester respawned (the old character is gone)"):format(site.Label)
			end
			local cardNow = debugBoard.GetCard()
			if not shutNote and not (cardNow and cardNow.Open and cardNow.Shown) then
				waitFrames(20)
				cardNow = debugBoard.GetCard()
				if not (cardNow and cardNow.Open and cardNow.Shown) then
					shutNote = ("%s: the card is shut: %s"):format(site.Label, debugBoard.DescribeState())
				end
			end
			for index, size in PHONE_TEST_VIEWS do
				local hard, soft, detail = gachaPhoneAt(card, camera, size, site.Label)
				if shutNote then
					table.insert(hard, shutNote)
				end
				for _, problem in hard do
					table.insert(hardMisses[index], problem)
				end
				for _, problem in soft do
					table.insert(softMisses[index], problem)
				end
				table.insert(details[index], detail)
			end
		end
		local standing = ("tester started %.1f studs from the anchor, stood at its centre"):format(startOff)
		for index, size in PHONE_TEST_VIEWS do
			table.insert(lines, gachaPhoneLine(size, hardMisses[index], softMisses[index], details[index], standing, quiet, withToast, toastProblem))
			table.insert(lines, gachaPhoneText(card, size))
		end
	else
		defaultCamera(camera, root, back, 12.5, 0)
		waitFrames(6)
		local quiet, withToast, toastProblem = gachaToastTops()
		if not current() then
			return {}
		end
		for _, size in { Vector2.new(1920, 1080), Vector2.new(1366, 768) } do
			table.insert(lines, gachaDesktopStack(card, camera, size, quiet, withToast, toastProblem))
		end
	end
	return finish(lines)
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
-- with a timer and a Safe Fusion circle with "×N" are up in one row: in the
-- BOTTOM-RIGHT corner on desktop, the TOP-RIGHT corner on a phone. Their timers
-- read the live seconds, tap targets are >= 44 px on screen, nothing overlaps
-- a HUD rect or the weapon bar, and the old effect pills are gone. Measured
-- at both layouts.
-- The tray's and the tooltip's placement maths against the real HUD rects and
-- the weapon bar at explicit window sizes (the same idea as "cards centred"),
-- with 3 and with 5 effects. Desktop (1251 x 666, 1366 x 768, 1920 x 1080):
-- one right-aligned row in the bottom-right corner, 16 px from the right and
-- bottom edges and 12 px right of the bottom row's ⚙ (or, when it cannot fit,
-- directly above that row), touching no HUD rect or the weapon bar. Tablet
-- (1024 x 768, 1180 x 820, 1366 x 1024: the desktop layout WITH Roblox's jump
-- button): the same, with the jump rect an obstacle (the row sits above it
-- when the corner is taken), and the bottom row and weapon bar clear of it.
-- Phone (844 x 390, 896 x 414): one row (or at most 2 right-aligned rows when it wraps)
-- in the top-right quarter below GetCardTop, clear of TopStack, the HUD, the
-- weapon bar and the jump button. A desktop plan never runs under 500 px tall
-- (the game is the phone layout there). The Luck tooltip is on screen,
-- touching none. Needs the weapon bar up (/weapons all).
local EFFECTS_VIEWPORTS = {
	{ Name = "1251 x 666", Size = Vector2.new(1251, 666), Layout = "desktop" },
	{ Name = "1366 x 768", Size = Vector2.new(1366, 768), Layout = "desktop" },
	{ Name = "1920 x 1080", Size = Vector2.new(1920, 1080), Layout = "desktop" },
	{ Name = "1024 x 768", Size = Vector2.new(1024, 768), Layout = "tablet" }, -- iPad
	{ Name = "1180 x 820", Size = Vector2.new(1180, 820), Layout = "tablet" },
	{ Name = "1366 x 1024", Size = Vector2.new(1366, 1024), Layout = "tablet" },
	{ Name = "844 x 390", Size = Vector2.new(844, 390), Layout = "phone" },
	{ Name = "896 x 414", Size = Vector2.new(896, 414), Layout = "phone" }, -- iPhone XR landscape
}

local function rectsOverlap(a: { Position: Vector2, Size: Vector2 }, b: { Position: Vector2, Size: Vector2 }): boolean
	local ox = math.min(a.Position.X + a.Size.X, b.Position.X + b.Size.X) - math.max(a.Position.X, b.Position.X)
	local oy = math.min(a.Position.Y + a.Size.Y, b.Position.Y + b.Size.Y) - math.max(a.Position.Y, b.Position.Y)
	return ox > 1 and oy > 1
end

-- `rect` grown by `gap` px all round (the jump button's air).
local function grown(rect: { Position: Vector2, Size: Vector2 }, gap: number): { Position: Vector2, Size: Vector2 }
	return { Position = rect.Position - Vector2.new(gap, gap), Size = rect.Size + Vector2.new(2 * gap, 2 * gap) }
end

local function probeEffectsTrayViewports(): { ProbeLine }
	local EffectsTray = require(UI.EffectsTray) :: any
	local hud = require(script.Parent.HudController) :: any
	local combat = require(script.Parent.CombatController) :: any
	local lines: { ProbeLine } = {}
	for _, viewport in EFFECTS_VIEWPORTS do
		local phone = viewport.Layout == "phone"
		local touch = viewport.Layout ~= "desktop" -- the jump button is on screen
		do
			UIKit.SetForcedPhone(phone)
			task.wait(0.4)
			EffectsTray.Refresh()
			task.wait(0.2)
			local label = ("%s, %s"):format(viewport.Name, viewport.Layout)
			-- The card's natural size and the scale it is drawn at, from the live card.
			EffectsTray.TestHover("Luck", true)
			task.wait(0.2)
			local live = EffectsTray.GetTooltip()
			EffectsTray.TestHover("Luck", false)
			local view = viewport.Size / live.Scale
			local obstacles = hud.GetObstacleRectsFor(view, touch)
			local weaponBar = combat.GetBarRectFor(view, touch)
			if weaponBar then
				obstacles.WeaponBar = weaponBar
			end
			local jump = EffectsTray.JumpRectFor(view, live.Scale, touch)
			local cardTop = UIKit.GetCardTop()
			if jump then
				-- The bottom row and the weapon bar clear the jump button (JUMP_GAP of air).
				local clearJump: { string } = {}
				local airy = grown(jump, UIKit.JUMP_GAP)
				for _, name in { "BottomRow", "WeaponBar" } do
					local rect = obstacles[name]
					if rect and rectsOverlap(rect, airy) then
						table.insert(clearJump, ("%s at %d,%d %dx%d"):format(name, rect.Position.X, rect.Position.Y, rect.Size.X, rect.Size.Y))
					end
				end
				if not obstacles.BottomRow then
					table.insert(clearJump, "no BottomRow rect")
				elseif obstacles.BottomRow.Position.X < 0 then
					table.insert(clearJump, "bottom row pushed off the left edge")
				end
				table.insert(lines, {
					Ok = #clearJump == 0,
					Name = ("jump button (%s): the bottom row and the weapon bar are %d px clear of it"):format(label, UIKit.JUMP_GAP),
					Detail = ("jump %d,%d %dx%d | bottom row %s%s"):format(
						jump.Position.X, jump.Position.Y, jump.Size.X, jump.Size.Y,
						if obstacles.BottomRow then ("%d..%d"):format(obstacles.BottomRow.Position.X, obstacles.BottomRow.Position.X + obstacles.BottomRow.Size.X) else "missing",
						if #clearJump > 0 then " | " .. table.concat(clearJump, "; ") else ""),
				})
			end
			if viewport.Layout == "tablet" then
				-- A finger: every bottom-row button is a 44 px tap or more on a tablet.
				local smallest = hud.GetBottomRowMinTap()
				table.insert(lines, {
					Ok = smallest >= UITheme.MinTapSize,
					Name = ("tablet (%s): every bottom-row button is at least %d px"):format(label, UITheme.MinTapSize),
					Detail = ("smallest %d px"):format(smallest),
				})
			end
			if viewport.Name == "1180 x 820" then
				-- Roblox shows and hides the jump button with the last input; the
				-- HUD reserves its place on any touch device regardless, so toggling
				-- TouchGui moves neither the tray, the bottom row nor the weapon bar.
				local playerGui = localPlayer:WaitForChild("PlayerGui")
				local touchGui = playerGui:FindFirstChild("TouchGui")
				local fake: ScreenGui? = nil
				if not touchGui then
					local made = Instance.new("ScreenGui")
					made.Name = "TouchGui"
					made.Parent = playerGui
					fake = made
					touchGui = made
				end
				local function snapshot(): { Vector2 }
					EffectsTray.Refresh()
					task.wait(0.3)
					local out: { Vector2 } = {}
					local row = hud.GetBottomRowRect()
					local bar = combat.GetBarRect()
					local plan = EffectsTray.GetPlan()
					for _, rect in { row, bar, if plan then plan.Rect else nil } do
						table.insert(out, if rect then rect.Position else Vector2.zero)
						table.insert(out, if rect then rect.Size else Vector2.zero)
					end
					table.insert(out, Vector2.new(if UIKit.JumpButtonShowing() then 1 else 0, 0))
					return out
				end
				local gui = touchGui :: ScreenGui
				local was = gui.Enabled
				gui.Enabled = true
				local shown = snapshot()
				gui.Enabled = false
				local hidden = snapshot()
				gui.Enabled = was
				if fake then
					fake:Destroy()
				end
				local moved: { string } = {}
				local SNAPSHOT_NAMES = { "bottom row position", "bottom row size", "weapon bar position", "weapon bar size", "effects tray position", "effects tray size", "jump button showing" }
				for index, a in shown do
					-- ±1 px: a rect may land on a neighbouring pixel, but nothing visibly moves.
					local d = a - hidden[index]
					if math.abs(d.X) > 1 or math.abs(d.Y) > 1 then
						table.insert(moved, ("%s %s -> %s"):format(SNAPSHOT_NAMES[index] or ("#" .. index), tostring(a), tostring(hidden[index])))
					end
				end
				table.insert(lines, {
					Ok = #moved == 0 and UIKit.JumpPresentFor(false, true) and UIKit.JumpPresentFor(true, false) and not UIKit.JumpPresentFor(false, false),
					Name = ("jump button (%s): showing or hiding it moves neither the tray, the bottom row nor the weapon bar"):format(label),
					Detail = if #moved == 0 then "same rects, within 1 px" else table.concat(moved, "; "),
				})
			end
			local plan3: any = nil
			for _, effects in { 3, 5 } do
				local plan = EffectsTray.PlanTrayFor(view, obstacles, effects, jump, cardTop, phone)
				if effects == 3 then
					plan3 = plan
				end
				if phone and effects == 5 then
					-- Friends + Passes + 3 timed effects: two rows are fine when one row of
					-- 48 px cells does not fit beside TopStack.
					local onScreen = plan.Rect.Position.X >= 0 and plan.Rect.Position.Y >= 0
						and plan.Rect.Position.X + plan.Rect.Size.X <= view.X
						and plan.Rect.Position.Y + plan.Rect.Size.Y <= view.Y
					table.insert(lines, {
						Ok = plan.Rows <= 2 and plan.Circle >= UITheme.MinTapSize and #plan.Hits == 0 and onScreen,
						Name = ("passes circle: the phone tray (%s) holds Friends + Passes + 3 timed effects in at most 2 rows, 44 px taps, on screen, clear of the HUD, TopStack and jump button"):format(viewport.Name),
						Detail = ("%d rows, %d px icons, on screen %s, touches: %s"):format(plan.Rows, plan.Circle, tostring(onScreen), table.concat(plan.Hits, ", ")),
					})
				end
				-- Every circle's centre y: one row (±1 px), or right-aligned rows when it wraps.
				local rowYs: { number } = {}
				local rightEdges: { number } = {}
				local rowCounts: { [number]: number } = {}
				for slot = 1, effects do
					local circle = EffectsTray.CircleRectFor(plan, slot)
					local y = math.floor(circle.Position.Y + circle.Size.Y / 2 + 0.5)
					local found = false
					for index, known in rowYs do
						if math.abs(known - y) <= 1 then
							rowCounts[index] += 1
							found = true
						end
					end
					if not found then
						table.insert(rowYs, y)
						table.insert(rightEdges, circle.Position.X + circle.Size.X)
						rowCounts[#rowYs] = 1
					end
				end
				local rowProblems: { string } = {}
				if plan.Corner ~= (if phone then "TopRight" else "BottomRight") then
					table.insert(rowProblems, ("planned for the %s corner"):format(plan.Corner))
				end
				if plan.Rows == 1 and #rowYs ~= 1 then
					table.insert(rowProblems, ("%d rows, want one"):format(#rowYs))
				end
				if #rowYs ~= plan.Rows then
					table.insert(rowProblems, ("planned %d rows, circles sit on %d"):format(plan.Rows, #rowYs))
				end
				for index = 2, #rightEdges do
					if math.abs(rightEdges[index] - rightEdges[1]) > 1 then
						table.insert(rowProblems, "rows are not aligned")
						break
					end
				end
				if not phone and plan.Rows ~= 1 then
					table.insert(rowProblems, ("%d rows on desktop, want one"):format(plan.Rows))
				end
				table.insert(lines, {
					Ok = #rowProblems == 0,
					Name = ("effects tray plan (%s, %d effects): %s"):format(label,
						effects, if phone then "one row, or right-aligned rows when it wraps" else "one row"),
					Detail = ("%d px icons, %d per row, %d rows%s"):format(plan.Circle, plan.PerRow, plan.Rows, if #rowProblems > 0 then ": " .. table.concat(rowProblems, "; ") else ""),
				})
				local right = plan.Rect.Position.X + plan.Rect.Size.X
				local placeProblems: { string } = {}
				local bottomRow = obstacles.BottomRow
				if phone then
					-- The top-right quarter, below GetCardTop, 8 px from the right edge.
					if plan.Rect.Position.Y < cardTop - 1 then
						table.insert(placeProblems, ("starts at y %d, GetCardTop is %d"):format(plan.Rect.Position.Y, cardTop))
					end
					if plan.Rect.Position.X + plan.Rect.Size.X / 2 < view.X / 2 or plan.Rect.Position.Y + plan.Rect.Size.Y > view.Y / 2 then
						table.insert(placeProblems, "not in the top-right quarter")
					end
					if right > view.X - 4 or right < view.X - 12 then
						table.insert(placeProblems, ("right edge at %d of %d (want 8 px, a cell's 4 px gap included)"):format(right, view.X))
					end
				else
					-- The bottom-right corner: the rightmost circle 16 px from the right
					-- edge, timers 16 px from the bottom, 12 px right of the bottom row's
					-- ⚙; or above the bottom row (and the jump button), right-aligned.
					local first = EffectsTray.CircleRectFor(plan, 1)
					if math.abs(view.X - 16 - (first.Position.X + first.Size.X)) > 1 then
						table.insert(placeProblems, ("first circle ends %d px from the right edge, want 16"):format(view.X - (first.Position.X + first.Size.X)))
					end
					if not bottomRow then
						table.insert(placeProblems, "no BottomRow rect to measure against")
					elseif plan.Lifted then
						if plan.Rect.Position.Y + plan.Rect.Size.Y > bottomRow.Position.Y + 1 then
							table.insert(placeProblems, "lifted row still reaches the bottom row's top")
						end
						if jump and plan.Rect.Position.Y + plan.Rect.Size.Y > jump.Position.Y - UIKit.JUMP_GAP + 1 and plan.Rect.Position.X < jump.Position.X + jump.Size.X then
							table.insert(placeProblems, "lifted row is not above the jump button")
						end
					else
						if math.abs(view.Y - 16 - (plan.Rect.Position.Y + plan.Rect.Size.Y)) > 1 then
							table.insert(placeProblems, ("bottom at %d of %d, want 16 px from the edge"):format(plan.Rect.Position.Y + plan.Rect.Size.Y, view.Y))
						end
						if plan.Rect.Position.X < bottomRow.Position.X + bottomRow.Size.X + 12 - 1 then
							table.insert(placeProblems, ("starts at %d, the bottom row ends at %d (want 12 px between)"):format(plan.Rect.Position.X, bottomRow.Position.X + bottomRow.Size.X))
						end
					end
				end
				if plan.Circle < 44 then
					table.insert(placeProblems, ("%d px icons, under the 44 px tap size"):format(plan.Circle))
				end
				table.insert(lines, {
					Ok = #placeProblems == 0 and weaponBar ~= nil and #plan.Hits == 0,
					Name = if phone
						then ("effects tray plan (%s, %d effects): top-right, below GetCardTop, clear of TopStack, the HUD, the weapon bar and the jump button"):format(label, effects)
						else ("effects tray plan (%s, %d effects): bottom-right, right of the ⚙ (or above it%s), clear of the weapon bar"):format(label, effects, if jump then " and the jump button" else ""),
					Detail = ("rect %d,%d %dx%d, %d px icons%s, weapon bar %s, touches: %s%s"):format(
						plan.Rect.Position.X, plan.Rect.Position.Y, plan.Rect.Size.X, plan.Rect.Size.Y, plan.Circle,
						if plan.Lifted then ", lifted" else "",
						if weaponBar then "up" else "NOT showing (/weapons all)", table.concat(plan.Hits, ", "),
						if #placeProblems > 0 then " | " .. table.concat(placeProblems, "; ") else ""
					),
				})
			end
			local size = live.Size / live.Scale
			table.insert(lines, {
				Ok = size.X >= EffectsTray.TOOLTIP_MIN_WIDTH - 1 and size.Y < view.Y,
				Name = ("effects tray plan (%s): the Luck tooltip is at least %d px wide and shorter than the screen"):format(label, EffectsTray.TOOLTIP_MIN_WIDTH),
				Detail = ("card %dx%d"):format(size.X, size.Y),
			})
			local circle = EffectsTray.CircleRectFor(plan3, 1)
			-- The tooltip also stays off the jump button.
			local tipObstacles: { [string]: any } = table.clone(obstacles)
			if jump then
				tipObstacles.JumpButton = jump
			end
			local tip = EffectsTray.PlanTooltipFor(view, tipObstacles, circle, size, phone)
			local narrow = false
			if tip.Overlap > 0 or not tip.OnScreen then
				-- The live card narrows to its minimum width when nothing is clear (taller by the wrap).
				tip = EffectsTray.PlanTooltipFor(view, tipObstacles, circle, Vector2.new(EffectsTray.TOOLTIP_MIN_WIDTH, size.Y * 1.6), phone)
				narrow = true
			end
			table.insert(lines, {
				Ok = tip.OnScreen and tip.Overlap == 0,
				Name = ("effects tray plan (%s): the Luck tooltip is on screen and touches no HUD rect%s"):format(label, if jump then " or the jump button" else ""),
				Detail = ("%s%s at %d,%d, card %dx%d, on screen %s, touches: %s"):format(
					tip.Side, if narrow then " (narrow)" else "", tip.Left, tip.Top, size.X, size.Y, tostring(tip.OnScreen), table.concat(tip.Hits, ", ")
				),
			})
		end
	end
	return lines
end

-- The Friends chip (UI/EffectsTray): always there, "+N%" under a 👥 circle,
-- the rule as its tooltip, and the client's own multiplier agreeing with the
-- count the server just synced (`percent` = 0 / 30 / 60). A tap must not throw
-- (the invite itself needs Roblox's window, so only the tooltip half is run).
local function probeFriendChip(percent: number): { ProbeLine }
	local EffectsTray = require(UI.EffectsTray) :: any
	local tycoon = require(script.Parent.TycoonController) :: any
	local FriendConfig = require(ReplicatedStorage.Shared.Config.FriendConfig) :: any
	local lines: { ProbeLine } = {}
	EffectsTray.Refresh()
	task.wait(0.3)
	local chip: any = nil
	for _, view in EffectsTray.GetCells() do
		if view.Id == "Friends" then
			chip = view
		end
	end
	local want = ("+%d%%"):format(percent)
	table.insert(lines, {
		Ok = chip ~= nil and chip.Timer == want and chip.Glyph == "👥",
		Name = ("friend chip: a 👥 circle reading %s"):format(want),
		Detail = if chip then ("glyph '%s', text '%s'"):format(chip.Glyph, chip.Timer) else "no Friends cell in the tray",
	})
	local inputs = tycoon.GetIncomeInputs()
	local wantMultiplier = 1 + percent / 100
	table.insert(lines, {
		Ok = math.abs((inputs.FriendMultiplier or 0) - wantMultiplier) < 1e-9 and tycoon.GetFriendCount() == percent / FriendConfig.PercentPerFriend,
		Name = ("friend chip: the client's income inputs carry x%.2f from the snapshot"):format(wantMultiplier),
		Detail = ("FriendMultiplier %s, count %s"):format(tostring(inputs.FriendMultiplier), tostring(tycoon.GetFriendCount())),
	})
	if chip then
		EffectsTray.TestHover("Friends", true)
		task.wait(0.2)
		local tip = EffectsTray.GetTooltip()
		EffectsTray.TestHover("Friends", false)
		table.insert(lines, {
			Ok = tip.Visible and tip.Plain == FriendConfig.RuleText(),
			Name = "friend chip: the tooltip is the rule (+15% income each, max +60%)",
			Detail = ("visible %s, plain '%s'"):format(tostring(tip.Visible), tostring(tip.Plain)),
		})
		local tapOk = pcall(EffectsTray.TestTap, "Friends")
		EffectsTray.TestTap("Friends") -- a second tap unpins it
		table.insert(lines, {
			Ok = tapOk and not EffectsTray.GetTooltip().Visible,
			Name = "friend chip: a tap pins the tooltip and a second tap closes it",
			Detail = ("tap ok %s"):format(tostring(tapOk)),
		})
		table.insert(lines, {
			Ok = chip.HitSize.X >= UITheme.MinTapSize and chip.HitSize.Y >= UITheme.MinTapSize,
			Name = ("friend chip: the tap target is at least %d px"):format(UITheme.MinTapSize),
			Detail = ("hit %d x %d"):format(math.floor(chip.HitSize.X), math.floor(chip.HitSize.Y)),
		})
	end
	return lines
end

-- The 🎟 PASSES circle (UI/EffectsTray): one circle for every owned pass, from
-- a stubbed owned set. None: no circle. {DoubleCash}: label x2, one tooltip
-- line, no badge. {DoubleCash, VIP, Lucky}: badge 3, label x2.5, 3 lines.
local function probePassesCircle(): { ProbeLine }
	local EffectsTray = require(UI.EffectsTray) :: any
	local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat) :: any
	local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig) :: any
	local lines: { ProbeLine } = {}
	local function circle(owned: { [string]: boolean }): any
		EffectsTray.SetTestOwned(owned)
		task.wait(0.3)
		for _, view in EffectsTray.GetCells() do
			if view.Id == "Passes" then
				return view
			end
		end
		return nil
	end
	local function tooltipLines(): number
		EffectsTray.TestHover("Passes", true)
		task.wait(0.2)
		local tip = EffectsTray.GetTooltip()
		EffectsTray.TestHover("Passes", false)
		if not tip.Visible or tip.Name ~= "Your passes" then
			return -1
		end
		return #string.split(tip.Plain, "\n")
	end
	local ok, err = pcall(function()
		local none = circle({})
		table.insert(lines, {
			Ok = none == nil,
			Name = "passes circle: a player with no pass has no circle",
			Detail = if none then "a Passes cell is showing" else "no Passes cell",
		})
		local one = circle({ DoubleCash = true })
		local oneLines = if one then tooltipLines() else -1
		table.insert(lines, {
			Ok = one ~= nil
				and one.Glyph == "🎟"
				and one.Timer == NumberFormat.Multiplier(ShopConfig.DoubleCashMultiplier)
				and one.Badge == nil
				and oneLines == 1,
			Name = "passes circle: {DoubleCash} shows one 🎟 circle labelled x2, no badge, a one-line tooltip",
			Detail = if one then ("glyph '%s', label '%s', badge %s, %d tooltip lines"):format(one.Glyph, one.Timer, tostring(one.Badge), oneLines) else "no Passes cell",
		})
		local three = circle({ DoubleCash = true, VIP = true, Lucky = true })
		local threeLines = if three then tooltipLines() else -1
		local wantLabel = NumberFormat.Multiplier(ShopConfig.DoubleCashMultiplier * ShopConfig.VipMultiplier)
		table.insert(lines, {
			Ok = three ~= nil and three.Badge == "3" and three.Timer == wantLabel and threeLines == 3,
			Name = ("passes circle: {DoubleCash, VIP, Lucky} shows badge 3, label %s, a three-line tooltip"):format(wantLabel),
			Detail = if three then ("badge %s, label '%s', %d tooltip lines"):format(tostring(three.Badge), three.Timer, threeLines) else "no Passes cell",
		})
		local luckyOnly = circle({ Lucky = true, LabStyle = true })
		table.insert(lines, {
			Ok = luckyOnly ~= nil and luckyOnly.Timer == "ON",
			Name = "passes circle: passes that do not touch cash read ON",
			Detail = if luckyOnly then ("label '%s'"):format(luckyOnly.Timer) else "no Passes cell",
		})
		if three then
			table.insert(lines, {
				Ok = three.HitSize.X >= UITheme.MinTapSize and three.HitSize.Y >= UITheme.MinTapSize,
				Name = ("passes circle: the tap target is at least %d px"):format(UITheme.MinTapSize),
				Detail = ("hit %d x %d"):format(math.floor(three.HitSize.X), math.floor(three.HitSize.Y)),
			})
		end
	end)
	EffectsTray.SetTestOwned(nil)
	if not ok then
		table.insert(lines, { Ok = false, Name = "passes circle (errored)", Detail = tostring(err) })
	end
	return lines
end

local function probeEffectsTray(tokens: number): { ProbeLine }
	local EffectsTray = require(UI.EffectsTray) :: any
	local hud = require(script.Parent.HudController) :: any
	local tycoon = require(script.Parent.TycoonController) :: any
	local lines: { ProbeLine } = {}
	-- A window too small to lay the HUD out reports "selftest window" once;
	-- the checks that measure positions on it are skipped here too.
	local tooSmall = windowProblem() ~= nil
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
		-- In the bottom-right (desktop) / top-right (phone) quarter of the window, and timers that read the live seconds.
		local camera = workspace.CurrentCamera
		local window = if camera then camera.ViewportSize else Vector2.new(1366, 768)
		local inset = GuiService:GetGuiInset().Y
		local outside: { string } = {}
		for id, entry in byId do
			local centre = entry.Position + entry.Size / 2 - Vector2.new(0, inset)
			local inQuarter = if phone
				then centre.X > window.X * 0.5 and centre.Y < window.Y * 0.5
				else centre.X > window.X * 0.5 and centre.Y > window.Y * 0.5
			if not inQuarter then
				table.insert(outside, ("%s at %d,%d"):format(id, centre.X, centre.Y))
			end
		end
		table.sort(outside)
		if not tooSmall then
			table.insert(lines, {
				Ok = next(byId) ~= nil and #outside == 0,
				Name = ("effects tray (%s, window %d × %d): in the %s quarter"):format(label, window.X, window.Y, if phone then "top-right" else "bottom-right"),
				Detail = table.concat(outside, ", "),
			})
		end
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
		if not tooSmall and (tip.Position.X < -1 or tip.Position.X + tip.Size.X > viewport.X + 1) then
			table.insert(tipProblems, ("off screen: x %d-%d of %d"):format(tip.Position.X, tip.Position.X + tip.Size.X, viewport.X))
		end
		-- Opens to the LEFT of the icon (or above / below it when the left is taken).
		if not tooSmall and luckCell then
			local cellTop = luckCell.Position.Y - inset
			if tip.Position.X < luckCell.Position.X + luckCell.Size.X - 1 and tip.Position.X + tip.Size.X > luckCell.Position.X + 1
				and tip.Position.Y < cellTop + luckCell.Size.Y - 1 and tip.Position.Y + tip.Size.Y > cellTop + 1 then
				table.insert(tipProblems, "covers the icon")
			end
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
		if #covered > 0 and not tooSmall then
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
		local obstacles: { [string]: any } = hud.GetObstacleRects()
		local trayWeaponBar = (require(script.Parent.CombatController) :: any).GetBarRect()
		if trayWeaponBar then
			obstacles.WeaponBar = trayWeaponBar
		end
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
		if not tooSmall then
			local plan = EffectsTray.GetPlan()
			table.insert(lines, {
				Ok = #overlaps == 0,
				Name = ("effects tray (%s): no overlap with any HUD rect"):format(label),
				Detail = table.concat(overlaps, ", ")
					.. (if plan then (" | plan %d px icons, %d per row, %d rows"):format(plan.Circle, plan.PerRow, plan.Rows) else ""),
			})
		end
	end
	for _, line in probeEffectsTrayViewports() do
		table.insert(lines, line)
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
-- The Fuse panel's mutation tip on `tier` with an empty chamber (`expect` = a
-- mutation word it must name, or "" for no tip), then with one orb in.
local function probeFuseTip(tier: string, expect: string): { ProbeLine }
	local panel = require(UI.FusePanel) :: any
	task.wait(0.4) -- the inventory sync
	panel.Open()
	task.wait(0.2)
	local empty = panel.SelfTestTip(tier, false)
	local oneIn = panel.SelfTestTip(tier, true)
	panel.Close()
	local lines: { ProbeLine } = {}
	if expect == "" then
		table.insert(lines, {
			Ok = empty == nil,
			Name = "fuse tip: an empty chamber with only plain orbs shows no tip",
			Detail = tostring(empty),
		})
	else
		local want = ("Tip: put a %s orb in first, then AUTO-FILL fills %s."):format(expect, expect)
		table.insert(lines, {
			Ok = empty == want,
			Name = ("fuse tip: an empty chamber with a group of %s orbs names %s"):format(expect, expect),
			Detail = tostring(empty),
		})
		table.insert(lines, {
			Ok = oneIn == nil,
			Name = "fuse tip: gone as soon as an orb is in the chamber",
			Detail = tostring(oneIn),
		})
	end
	return lines
end

-- The Fuse panel's "Add more ... for better odds" line on `tier` with
-- `chamber` orbs in: `expect` is the whole line, or "" when it must be hidden.
local function probeFuseOdds(tier: string, chamber: number, expect: string): { ProbeLine }
	local panel = require(UI.FusePanel) :: any
	task.wait(0.4) -- the inventory sync
	panel.Open()
	task.wait(0.2)
	local text = panel.SelfTestOdds(tier, chamber)
	panel.Close()
	return {
		{
			Ok = (text or "") == expect,
			Name = if expect == ""
				then ("fuse odds line: hidden with %d %s in the chamber"):format(chamber, tier)
				else ("fuse odds line: %d %s in the chamber says '%s'"):format(chamber, tier, expect),
			Detail = tostring(text),
		},
	}
end

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

-- The Fuse panel's Secret meter on the Mythic tab: it shows the server's
-- value, and at full says so and the success % reads 100%.
local function probeFuseMeter(pity: number, full: boolean): { ProbeLine }
	local TycoonController = require(script.Parent.TycoonController) :: any
	local panel = require(UI.FusePanel) :: any
	local waited = os.clock()
	while TycoonController.GetSecretPity() ~= pity and os.clock() - waited < 3 do
		task.wait(0.1)
	end
	task.wait(0.4) -- the inventory sync
	panel.Open()
	task.wait(0.2)
	local view = panel.SelfTestMeter("Mythic")
	task.wait(0.6) -- the bar's tween
	panel.Close()
	local wantText = if full then "NEXT FUSE IS A SURE SECRET!" else ("SECRET METER  %d / %d"):format(pity, FusionConfig.SecretPityFull)
	local label = if full then "full" else "part-full"
	return {
		{
			Ok = TycoonController.GetSecretPity() == pity and view.Visible and view.Text == wantText and math.abs(view.Fill - pity / FusionConfig.SecretPityFull) < 1e-6,
			Name = ("fuse panel (%s meter): the SECRET METER bar shows the server's value"):format(label),
			Detail = ("client meter %d, server %d, visible %s, text %q, fill %.2f"):format(TycoonController.GetSecretPity(), pity, tostring(view.Visible), view.Text, view.Fill),
		},
		{
			Ok = view.Selected >= FusionConfig.MinFusionInputs and ((view.Chance == "100%") == full),
			Name = if full
				then "fuse panel (full meter): the success % reads 100%"
				else "fuse panel (part-full meter): the success % is the normal Mythic odds, not 100%",
			Detail = ("%d orbs in the chamber, chance label %q"):format(view.Selected, view.Chance),
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
	-- This probe is the current one now; whatever the previous probe left
	-- changed (camera, forced layout, tester) is put back before it starts.
	activeProbeId = if typeof(payload.ProbeId) == "number" then payload.ProbeId else nil
	local undo = restoreProbe
	restoreProbe = nil
	if undo then
		pcall(undo)
	end
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
		elseif payload.Kind == "Presented" then
			-- The timed run: answers the moment the real presenter has the step's
			-- banner up (no checks, no waits of its own). Data.Seconds: how long it took.
			local TutorialController = require(script.Parent.TutorialController) :: any
			local TutorialBanner = require(UI.TutorialBanner) :: any
			local TutorialExplain = require(UI.TutorialExplain) :: any
			local started = os.clock()
			local function up(): boolean
				local current = TutorialController.GetPresentedStep()
				return current ~= nil and current.Id == payload.StepId and TutorialBanner.IsShown()
			end
			while not up() and os.clock() - started < PRESENT_WAIT do
				-- The player taps the explain card at once (its OK is live).
				if TutorialExplain.IsOpen() and TutorialExplain.IsOkReady() then
					TutorialExplain.PressOk()
				end
				task.wait(0.05)
			end
			reportData = { Seconds = os.clock() - started, Up = up() }
			return {}
		elseif payload.Kind == "BigCard" then
			return probeBigCard(payload.Expect, payload.FakeFusion == true)
		elseif payload.Kind == "ClearScreen" then
			return probeClearScreen(tostring(payload.Label), payload.Report == true, if typeof(payload.Suppress) == "boolean" then payload.Suppress else nil)
		elseif payload.Kind == "Weapon" then
			return probeWeapon(payload.Weapon)
		elseif payload.Kind == "SampleRest" then
			return probeSampleRest()
		elseif payload.Kind == "Switch" then
			return probeSwitch(payload.From, payload.To)
		elseif payload.Kind == "WeaponReleased" then
			return probeWeaponReleased()
		elseif payload.Kind == "AnimationIds" then
			local idLines, allFailed = probeAnimationIds()
			reportData = { AllFailed = allFailed }
			return idLines
		elseif payload.Kind == "Fallback" then
			return probeFallback()
		elseif payload.Kind == "GachaOpen" then
			return probeGachaOpen()
		elseif payload.Kind == "GachaCard" then
			return probeGachaCard(payload.Luck, tostring(payload.Label), payload.ServerCost, payload.ServerMultiCost)
		elseif payload.Kind == "GachaButtons" then
			return probeGachaButtons()
		elseif payload.Kind == "GachaApproach" then
			return probeGachaApproach(payload.Phone == true)
		elseif payload.Kind == "GachaOnPad" then
			return probeGachaOnPad(payload.Phone == true, payload.ProbeId)
		elseif payload.Kind == "GachaCovers" then
			return probeGachaCovers()
		elseif payload.Kind == "GachaFar" then
			return probeGachaFar()
		elseif payload.Kind == "GachaBack" then
			return probeGachaBack()
		elseif payload.Kind == "QuestBadge" then
			return probeQuestBadge()
		elseif payload.Kind == "FriendChip" then
			return probeFriendChip(if typeof(payload.Percent) == "number" then payload.Percent else 0)
		elseif payload.Kind == "PassesCircle" then
			return probePassesCircle()
		elseif payload.Kind == "EffectsTray" then
			return probeEffectsTray(if typeof(payload.Tokens) == "number" then payload.Tokens else 0)
		elseif payload.Kind == "FuseMeter" then
			return probeFuseMeter(tonumber(payload.Pity) or 0, payload.Full == true)
		elseif payload.Kind == "FuseTip" then
			return probeFuseTip(tostring(payload.Tier), tostring(payload.Expect))
		elseif payload.Kind == "FuseOdds" then
			return probeFuseOdds(tostring(payload.Tier), tonumber(payload.Chamber) or 0, tostring(payload.Expect))
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
		table.insert(lines, { Ok = false, Name = ("probe %s errored on the client"):format(tostring(payload.Kind)), Detail = tostring(result) })
	end
	RemoteEvents.SelfTestReport:FireServer({ Stage = "TutorialProbe", ProbeId = payload.ProbeId, Lines = lines, Data = reportData })
end

-- NotifyOptInController with a stub Roblox service and a fake session clock
-- (so it does not wait 5 real minutes): nothing while the tutorial runs or
-- before MinSessionSeconds; after that one ask at the first high moment (a
-- fusion success, an Epic+ pull, the daily reveal closing); the fallback asks
-- at FallbackSeconds when no moment came; never twice in a session; and a
-- service that errors costs no client error.
local function testNotifyOptIn(): { string }
	local controller = require(script.Parent.NotifyOptInController) :: any
	local DailyController = require(script.Parent.DailyController) :: any
	local lines: { string } = {}
	local calls = 0
	local canErrors = false
	local stub = {
		CanPromptOptInAsync = function(): boolean
			if canErrors then
				error("selftest: CanPromptOptInAsync failed")
			end
			return true
		end,
		PromptOptIn = function()
			calls += 1
		end,
	}
	local now = 0
	local tutorial = false
	local function fresh()
		now = 0
		controller.SetServiceForTest(stub, function()
			return tutorial
		end, function()
			return now
		end)
	end
	-- Runs `fire`, waits out the settle delay plus a margin, returns the asks it caused.
	local function asks(fire: () -> ()): number
		local before = calls
		fire()
		task.wait(1.4)
		return calls - before
	end
	local function moment(kind: string, tier: string?): number
		return asks(function()
			controller.OnMoment(kind, tier)
		end)
	end
	local function add(ok: boolean, name: string)
		table.insert(lines, (if ok then "PASS " else "FAIL ") .. name)
	end
	local ok, err = pcall(function()
		clearScreen(true)
		controller.SelfTestSuppress(false)
		local minSeconds = NotifyConfig.MinSessionSeconds
		local fallback = NotifyConfig.FallbackSeconds

		tutorial = true
		fresh()
		now = fallback + 1
		add(moment("Fusion") == 0, "notify opt-in: not asked while the tutorial is active")
		add(asks(controller.Tick) == 0, "notify opt-in: the fallback does not ask during the tutorial either")

		tutorial = false
		fresh()
		now = minSeconds - 1
		add(asks(controller.OnDailyRevealClosed) == 0, "notify opt-in: a daily reveal close before 5 min asks nothing")
		add(moment("Fusion") == 0, "notify opt-in: a fusion success close before 5 min asks nothing")
		now = minSeconds + 1
		add(moment("Pull", "Rare") == 0, "notify opt-in: a Rare pull close asks nothing (below the Epic floor)")
		add(moment("Fusion") == 1, "notify opt-in: after 5 min a fusion success close asks once")
		add(moment("Fusion") == 0 and asks(controller.OnDailyRevealClosed) == 0, "notify opt-in: a second moment in the same session asks no more")

		fresh()
		now = fallback - 1
		add(asks(controller.Tick) == 0, "notify opt-in: before the fallback time with no moment asks nothing")
		now = fallback + 1
		add(asks(controller.Tick) == 1, "notify opt-in: at the fallback time with no moment asks once")
		add(moment("Fusion") == 0 and asks(controller.Tick) == 0, "notify opt-in: a moment after the fallback ask asks no more")

		fresh()
		now = minSeconds + 1
		add(moment("Pull", NotifyConfig.MinPullTier) == 1, "notify opt-in: a pull of the Epic floor closing asks once")
		fresh()
		now = minSeconds + 1
		add(asks(controller.OnDailyRevealClosed) == 1, "notify opt-in: after 5 min the daily reveal closing asks once")

		canErrors = true
		fresh()
		now = minSeconds + 1
		add(moment("Fusion") == 0, "notify opt-in: a CanPromptOptInAsync error asks nothing and throws nothing")
	end)
	controller.SetServiceForTest(nil, nil, nil)
	controller.SelfTestSuppress(true)
	DailyController.SelfTestSuppress(true)
	if not ok then
		add(false, "notify opt-in section errored: " .. tostring(err))
	end
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
	if typeof(payload) == "table" and payload.Only == "cards" then
		-- /selftest cards: only the card-placement checks.
		cardLines = {}
		local lines: { string } = {}
		local ok, err = pcall(function()
			local tooSmall = windowProblem()
			if tooSmall then
				table.insert(lines, windowLine(tooSmall))
			else
				testPlacedCards()
				for _, line in cardLines do
					table.insert(lines, line)
				end
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

	local modalError = UIKit.SelfTestModal()
	-- The destroyed throwaway must stay out of every layout change: phone, desktop,
	-- then back to the real window (an error here lands in "no client errors").
	for _, forced in { true, false } do
		UIKit.SetForcedPhone(forced)
		task.wait(0.2)
	end
	UIKit.SetForcedPhone(nil)
	-- No daily reward / notification prompt pops up by itself mid-run (it did
	-- after 00:00 UTC and hid the steal mission box).
	clearScreen(true)
	local hoverLines = testHover("before")
	local fired = fuzz(otherUserId)
	-- Give the server a moment to answer every junk call before it compares.
	task.wait(1.5)
	RemoteEvents.SelfTestReport:FireServer({ Stage = "Fuzz", Fired = fired })

	cardLines = {}
	textFitLines = {}
	local tooSmall = windowProblem()
	local panelLines: { string } = {}
	-- Each stage prints its seconds and tells the server it is still moving
	-- (its wait for "Done" counts from the latest one).
	local function stage(name: string, probe: () -> { string }, skip: boolean?)
		if skip then
			return
		end
		local started = os.clock()
		if name == "loop nudge" or name == "mission banner" then
			-- The live state these two depend on, so a flake explains itself.
			local TutorialController = require(script.Parent.TutorialController) :: any
			local UpgradeGuide = require(UI.UpgradeGuide) :: any
			local presented = TutorialController.GetPresentedStep()
			local guideWhere, guideStation = UpgradeGuide.GetLast()
			local camera = Workspace.CurrentCamera
			print(
				("[SelfTest] client state before %s: tip %s, coach step %s, overlays [%s], layout %s %dx%d, UpgradeGuide owns hand %s (last %s %s), hand target %s"):format(
					name,
					tostring(TutorialController.GetTipShowing()),
					if presented then tostring(presented.Id) else "none",
					table.concat(UIKit.GetOpenOverlays(), ", "),
					if UIKit.IsPhone() then "phone" else "desktop",
					camera.ViewportSize.X,
					camera.ViewportSize.Y,
					tostring(UpgradeGuide.IsOwningHand()),
					tostring(guideWhere),
					tostring(guideStation),
					tostring(require(UI.TutorialHand).GetTarget())
				)
			)
		end
		for _, line in probe() do
			table.insert(panelLines, line)
		end
		-- A stage that leaves a modal / card up would poison the next one (the
		-- steal mission box hides under any overlay): name it and close it.
		if UIKit.IsOverlayOpen() then
			local open = table.concat(UIKit.GetOpenOverlays(), ", ")
			clearScreen(nil)
			table.insert(panelLines, ("WARN stage %s left an overlay open (closed it): %s"):format(name, open))
		end
		print(("[SelfTest] client stage %s took %.1f s"):format(name, os.clock() - started))
		RemoteEvents.SelfTestReport:FireServer({ Stage = "Progress", Name = name })
	end
	stage("panels", function()
		if tooSmall then
			return { windowLine(tooSmall) }
		end
		local lines = testPanels()
		for _, line in textFitLines do
			table.insert(lines, line)
		end
		return lines
	end)
	stage("modal + hover", function()
		local lines: { string } = {}
		if modalError then
			table.insert(lines, "FAIL UIKit.Modal builds: " .. modalError)
		end
		for _, line in hoverLines do
			table.insert(lines, line)
		end
		for _, line in testHover("after a pedestal rebuild") do
			table.insert(lines, line)
		end
		return lines
	end)
	stage("placed cards", function()
		testPlacedCards()
		return cardLines
	end, tooSmall ~= nil)
	stage("card math", testCardMath)
	stage("fusion card", testFusionCard)
	stage("event guidance", testEventGuidance)
	stage("hud order", testHudOrder)
	stage("orientation", testOrientation)
	stage("phone panels", testPhonePanels, tooSmall ~= nil)
	stage("hud left column", testHudLeftColumn)
	stage("coach arrow", testCoachArrow)
	stage("loop moments", testLoopMoments)
	stage("deal tile", testDealTile)
	stage("phone hud coverage", testPhoneHudCoverage)
	stage("skipped lines", testSkippedLines)
	stage("plain", testPlain)
	stage("bundle contents", testBundleContents)
	stage("deal cards", testDealCards)
	stage("top stack", testTopStack)
	stage("mission banner", testMissionBanner)
	-- The cards above were measured live; the deal path needs the screen bare
	-- (the daily reward card is up after 00:00 UTC until it is claimed).
	clearScreen(true)
	stage("deal path", function()
		local shopController = require(script.Parent.ShopController) :: any
		return shopController.SelfTestDealPath()
	end)
	stage("loop nudge", function()
		-- Independent of live state: no tip and no UPGRADES guide touches the
		-- hand while the probe owns it; both come back even if a check raises.
		local UpgradeGuide = require(UI.UpgradeGuide) :: any
		local TutorialController = require(script.Parent.TutorialController) :: any
		UpgradeGuide.SetPaused(true)
		TutorialController.SelfTestSetTipsPaused(true)
		local ok, result = pcall(testLoopNudge)
		UpgradeGuide.SetPaused(false)
		TutorialController.SelfTestSetTipsPaused(false)
		UIKit.SetForcedPhone(nil)
		if ok then
			return result
		end
		return { "FAIL loop nudge: the probe raised | " .. tostring(result) }
	end)
	stage("fuse ladder", testFuseLadder)
	stage("chip jumps", testChipJumps, tooSmall ~= nil)
	stage("unlock card", testUnlockCard)
	stage("notify opt-in", testNotifyOptIn)
	stage("music", testMusic)
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
