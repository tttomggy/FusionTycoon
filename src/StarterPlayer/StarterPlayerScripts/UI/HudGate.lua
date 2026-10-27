--!strict
--[[
	HudGate
	-------
	The progressive HUD (Tutorial 2). A new player starts with the cash card
	and the tutorial banner only; every other HUD element is registered here
	under a key (TutorialConfig.HudKeys) and stays hidden until the step that
	introduces it (TutorialConfig.HudReveal). When a key turns on it pops in
	(scale 0 -> 1.15 -> 1), throws a few sparkles and wears a small "NEW!"
	pill for 3 s (an optional note under it, TutorialConfig.HudRevealNote).

	A finished tutorial, an old save and a replay show everything, silently.

	How it holds an element hidden: the owners (HudController,
	EventController) keep setting their own Visible from their own state, so
	the gate does not fight them from their side; it runs after them, every
	frame at the end of the render step, and forces a hidden key's roots
	Visible = false. On the reveal the root is set visible again (ForceShow)
	or the owner's OnShow refreshes it (a tracker that is only visible while
	it has something to say).

	  Register(key, { Roots, AlsoHide?, ForceShow?, OnShow?, NewSide? })
	    Roots      the elements that pop in (functions: buttons get rebuilt)
	    AlsoHide   other elements held hidden with them, never animated
	    ForceShow  false: the owner decides Visible, OnShow refreshes it
	    NewSide    where the NEW! pill sits: "Top" (default), "Below", "Right"
	               Top is a badge: centred on the button's top edge, its bottom
	               BADGE_OVERLAP px below it, the note right above it; measured
	               from AbsolutePosition + the GuiInset, re-placed every frame
	  IsShown(key)    the state this frame; IsVisible(key) the element itself
	                  (/selftest checks both per step)
	  MeasureBadges() /selftest: a real NEW! pill per shown Top key, measured
	  Init()
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local UIKit = require(script.Parent.UIKit)
local TycoonController = require(script.Parent.Parent.Controllers.TycoonController)

local HudGate = {}

local Colors = UITheme.Colors

local NEW_SECONDS = 3
local SPARKLE_COUNT = 6
local SPARKLE_DISTANCE = 46
local POP_UP = 1.15
local POPS_DISPLAY_ORDER = 59
-- The NEW! pill is a badge on the button's top edge: its bottom hangs this
-- many px below the edge (the selftest allows +-6), the note sits above it.
local BADGE_OVERLAP = 4
local BADGE_GAP = 8 -- "Below" / "Right": the gap to the button

export type Entry = {
	Roots: () -> { GuiObject },
	AlsoHide: (() -> { GuiObject })?,
	ForceShow: boolean?,
	OnShow: (() -> ())?,
	NewSide: string?,
}

local entries: { [string]: Entry } = {}
local shown: { [string]: boolean } = {}
local pendingAt: { [string]: number } = {}
local started = false -- the first synced evaluation happened (silent)

function HudGate.Register(key: string, entry: Entry)
	entries[key] = entry
end

-- The tutorial step the player has been SHOWN (TutorialController plays the
-- steps one at a time and may trail the server's step): nil = no limit yet.
local stepSource: (() -> number?)? = nil

function HudGate.SetStepSource(source: () -> number?)
	stepSource = source
end

-- What the tutorial wants for `key` right now (before any reveal delay).
local function wanted(key: string): boolean
	if not TycoonController.HasSynced() then
		return false
	end
	local t = TycoonController.GetTutorial()
	local step = t.Step
	local source = stepSource
	if source and not t.Done and not t.Replay then
		local shown = source()
		if shown then
			step = math.min(step, shown)
		end
	end
	return TutorialConfig.IsHudShown(key, step, t.Done, t.Replay)
end

-- Is the element itself on screen (any root Visible)? /selftest.
function HudGate.IsVisible(key: string): boolean
	local entry = entries[key]
	if not entry then
		return false
	end
	for _, root in entry.Roots() do
		if root.Visible then
			return true
		end
	end
	return false
end

function HudGate.IsShown(key: string): boolean
	return shown[key] == true or (entries[key] == nil and wanted(key))
end

local function popTween(root: GuiObject)
	-- The element's own UIScale when it has one (a button may already carry
	-- a pulse scale; two on one parent are not guaranteed to multiply).
	local scale = root:FindFirstChildOfClass("UIScale")
	if not scale then
		local created = Instance.new("UIScale")
		created.Name = "HudPopScale"
		created.Parent = root
		scale = created
	end
	local s = scale :: UIScale
	s.Scale = 0
	local grow = TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = POP_UP })
	grow.Completed:Once(function()
		TweenService:Create(s, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	grow:Play()
end

-- The effects live on their own overlay (a root may be a row with a
-- UIListLayout, which would lay a child out like a sibling) and follow the
-- element's AbsolutePosition.
local overlay: Frame? = nil

local function getOverlay(): Frame
	local existing = overlay
	if existing and existing.Parent then
		return existing
	end
	local gui = UIKit.Screen("HudPops", POPS_DISPLAY_ORDER)
	local frame = Instance.new("Frame")
	frame.Name = "Pops"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Active = false
	frame.Parent = gui
	overlay = frame
	return frame
end

-- The element's rectangle in the overlay's own (design px) space. The overlay
-- is an IgnoreGuiInset gui, but AbsolutePosition is still reported below the
-- Roblox top bar, so the inset is added back (without it every pill sat one
-- top bar, ~58 px, above its button).
local function rectOf(root: GuiObject): (Vector2, Vector2)
	local scale = UIKit.EffectiveScale(getOverlay())
	local inset = Vector2.new(0, GuiService:GetGuiInset().Y)
	return (root.AbsolutePosition + inset) / scale, root.AbsoluteSize / scale
end

local function sparkles(root: GuiObject)
	local position, size = rectOf(root)
	local centre = position + size / 2
	for index = 1, SPARKLE_COUNT do
		local angle = (index / SPARKLE_COUNT) * math.pi * 2
		local star = UIKit.Label({
			Name = "HudSparkle",
			Text = "✨",
			TextSize = 22,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(centre.X, centre.Y),
			Size = UDim2.fromOffset(26, 26),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = getOverlay(),
		})
		local goal = UDim2.fromOffset(centre.X + math.cos(angle) * SPARKLE_DISTANCE, centre.Y + math.sin(angle) * SPARKLE_DISTANCE)
		local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(star, info, { Position = goal, TextTransparency = 1 }):Play()
		task.delay(0.65, function()
			star:Destroy()
		end)
	end
end

-- Puts the pill holder against `root` (the badge rule: see BADGE_OVERLAP).
local function placeHolder(holder: Frame, root: GuiObject, side: string?)
	local position, size = rectOf(root)
	if side == "Below" then
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y + BADGE_GAP)
	elseif side == "Right" then
		holder.AnchorPoint = Vector2.new(0, 0)
		holder.Position = UDim2.fromOffset(position.X + size.X + BADGE_GAP, position.Y)
	else
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.fromOffset(position.X + size.X / 2, position.Y + BADGE_OVERLAP)
	end
end

local function newPill(root: GuiObject, note: string?, side: string?): (Frame, GuiObject)
	local holder = Instance.new("Frame")
	holder.Name = "HudNew"
	holder.BackgroundTransparency = 1
	holder.AutomaticSize = Enum.AutomaticSize.XY
	holder.Size = UDim2.new()
	holder.Parent = getOverlay()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = if side == "Below" or side == "Right" then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 4)
	layout.Parent = holder
	local badge = UIKit.Pill({
		Name = "NewPill",
		Parent = holder,
		Text = "NEW!",
		TextSize = 14,
		Height = 24,
		Gradient = UITheme.Gradients.Pink,
		LayoutOrder = 2,
	})
	if note then
		UIKit.Pill({
			Name = "NewNote",
			Parent = holder,
			Text = note,
			TextSize = 14,
			Height = 26,
			Color = Colors.Panel,
			LayoutOrder = 1,
		})
	end
	-- Follows the element for its 3 s (it re-places every frame, so a bottom
	-- row that moves, a phone layout or the jump button takes it along).
	local started = os.clock()
	local connection: RBXScriptConnection
	placeHolder(holder, root, side)
	connection = RunService.RenderStepped:Connect(function()
		if os.clock() - started > NEW_SECONDS or not root.Parent then
			connection:Disconnect()
			holder:Destroy()
			return
		end
		placeHolder(holder, root, side)
	end)
	return holder, UIKit.PillRoot(badge)
end

export type BadgeProbe = { Key: string, PillBottom: number, ButtonTop: number, PillCentreX: number, ButtonCentreX: number }

-- /selftest: puts a real NEW! pill on every shown key whose NewSide is Top
-- (the buttons) and measures it one frame later, in logical px with the inset
-- added back (the selftest's visibleRect rule). The pills are removed again.
function HudGate.MeasureBadges(): { BadgeProbe }
	local probes: { BadgeProbe } = {}
	local made: { { Key: string, Holder: Frame, Badge: GuiObject, Root: GuiObject } } = {}
	for key, entry in entries do
		if shown[key] and (entry.NewSide == nil or entry.NewSide == "Top") then
			local root = entry.Roots()[1]
			if root and root.Visible and root.AbsoluteSize.X > 0 then
				local holder, badge = newPill(root, TutorialConfig.HudRevealNote[key], entry.NewSide)
				table.insert(made, { Key = key, Holder = holder, Badge = badge, Root = root })
			end
		end
	end
	RunService.RenderStepped:Wait()
	local inset = GuiService:GetGuiInset().Y
	local scale = UIKit.EffectiveScale(getOverlay())
	for _, item in made do
		local badgePos, badgeSize = item.Badge.AbsolutePosition, item.Badge.AbsoluteSize
		local rootPos, rootSize = item.Root.AbsolutePosition, item.Root.AbsoluteSize
		table.insert(probes, {
			Key = item.Key,
			PillBottom = (badgePos.Y + inset + badgeSize.Y) / scale,
			ButtonTop = (rootPos.Y + inset) / scale,
			PillCentreX = (badgePos.X + badgeSize.X / 2) / scale,
			ButtonCentreX = (rootPos.X + rootSize.X / 2) / scale,
		})
		item.Holder:Destroy()
	end
	return probes
end

local function reveal(key: string, animate: boolean)
	local entry = entries[key]
	if not entry then
		return
	end
	local roots = entry.Roots()
	for _, root in roots do
		if entry.ForceShow ~= false then
			root.Visible = true
		end
	end
	if entry.OnShow then
		entry.OnShow()
	end
	if not animate then
		return
	end
	SoundKit.Play("Toast", nil)
	for _, root in roots do
		popTween(root)
	end
	-- Let the layout place the element first, then the sparkles and NEW!.
	task.delay(0.05, function()
		for index, root in entry.Roots() do
			sparkles(root)
			-- One NEW! pill per key, on its first element.
			if index == 1 then
				newPill(root, TutorialConfig.HudRevealNote[key], entry.NewSide)
			end
		end
	end)
end

local function step()
	local synced = TycoonController.HasSynced()
	for key, entry in entries do
		local want = wanted(key)
		if want and not shown[key] then
			if not started then
				shown[key] = true
				reveal(key, false)
			else
				local at = pendingAt[key]
				if not at then
					at = os.clock() + (TutorialConfig.HudRevealDelay[key] or 0)
					pendingAt[key] = at
				end
				if os.clock() >= (at :: number) then
					shown[key] = true
					pendingAt[key] = nil
					reveal(key, true)
				end
			end
		elseif not want then
			shown[key] = false
			pendingAt[key] = nil
		end
		if not shown[key] then
			for _, root in entry.Roots() do
				if root.Visible then
					root.Visible = false
				end
			end
			local also = entry.AlsoHide
			if also then
				for _, root in also() do
					if root.Visible then
						root.Visible = false
					end
				end
			end
		end
	end
	if synced then
		started = true
	end
end

function HudGate.Init()
	RunService:BindToRenderStep("HudGate", Enum.RenderPriority.Last.Value, step)
end

return HudGate
