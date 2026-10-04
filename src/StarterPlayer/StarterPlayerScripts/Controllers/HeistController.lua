--[[
	HeistController
	---------------
	The client side of stealing (HeistService owns every rule).

	  * Grab: holding E on an enemy pedestal's StealPrompt (enabled only when
	    the steal is allowed, WorldLabelController) fires RequestSteal with
	    just which pedestal: { OwnerUserId, PedestalIndex }. A rejection comes
	    back as HeistEnded { Outcome = "Rejected", Reason } -> a toast.
	  * Every client, for every carrying player (the server sets Heist*
	    attributes on the Player), the thief's own client included: a
	    cosmetic copy of the pedestal orb 3 studs over their head (mutation
	    shell and satellites), welded to the head so it follows animation
	    and jumps, a 40-stud Danger beam up from it, and a big "<item> · 31s"
	    chip under a THIEF caption. The orb lives in Workspace, not the
	    character, so first-person LocalTransparencyModifier never hides it.
	  * A successful grab, on the thief's screen: a full-width "🫳 YOU GRABBED
	    <item>! RUN HOME!" banner for GRAB_BANNER_SECONDS, a grab sound and a
	    +8 FOV punch, then the GET HOME! bar.
	  * The thief: an orange "GET HOME!" banner (item, seconds, a draining
	    bar) and the goal arrow on their own gate.
	  * The victim: a red "THIEF IN YOUR LAB!" banner with a live distance, a
	    Danger arrow locked on the thief, and an alarm.
	  * The first TagGraceSeconds of a carry: the thief's banner says RUN!,
	    the owner's "Catch them in 2…1…" (no tag yet, server-side).
	  * A catch (HeistOutcome = "Saved" on the thief) plays on every client:
	    a white flash ring at the thief, CAUGHT! over their head, and the orb
	    flying back to its pedestal (HeistReturnTo) on a Bezier arc.
	  * Results: HEIST COMPLETE! / stolen cards (ResultController), toasts
	    for the rest.
	  * Shield fences: every plot's ForceField fence fades in and out from its
	    ShieldUntil attribute, so remote players see your shield too.
	  * Your LOCK console (built by the server, owner-only label and prompt):
	    the label pill, the button's colour and the prompt's Enabled follow
	    your plot's ShieldUntil / ShieldRearmAt / Protected, no remote:
	    READY (pink, prompt on), LOCKED · 42s (teal), RECHARGING · 12s
	    (muted), PROTECTED · NEW LAB at Rebirth 0 (prompt off for the last
	    three). LOCK rejections toast ("Get back to your lab to lock it!").
	  * Teaching: every enemy pedestal you could grab right now (its
	    StealPrompt's local Mode is "Steal", WorldLabelController) gets a red
	    hand marker over its label (client-only, hidden while you carry).
	  * One-time tips, saved per account (PlayerData.Tips, TipConfig):
	    stealHowTo (first robbable lab you walk into), intruder (someone in
	    your unlocked lab), guarded (at a pedestal its owner guards), catch
	    (first time as a victim: TOUCH THEM! and a throbbing arrow),
	    lockAfterLoss (after the first real loss card). Big 4 s toasts.
	    Tapping the Rebirth-0 teaser prompt explains the unlock.
	  * GUARDED made visible (guarding itself is server-side, GuardedByOwner):
	    every viewer sees a teal "🛡 GUARDED" chip over a guarded pedestal,
	    and while an owner is inside their walls each of their filled
	    pedestals gets a faint teal floor ring of OwnerBlockRadius (stronger
	    while guarded). Client-only; no light, no Highlight; skipped for
	    protected (Rebirth 0) labs.

	Sounds: SoundConfig slots Grab (the whoosh) and Alarm (three quick
	blips at PlaybackSpeed 1.3).
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local PlotKit = require(ReplicatedStorage.Shared.Modules.PlotKit)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local ShieldState = require(ReplicatedStorage.Shared.Modules.ShieldState)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ToastController = require(script.Parent.ToastController)
local ResultController = require(script.Parent.ResultController)
local GoalMarkerController = require(script.Parent.GoalMarkerController)
local TycoonController = require(script.Parent.TycoonController)
local HudController = require(script.Parent.HudController)

local HeistController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local localPlayer = Players.LocalPlayer

local STEAL_PROMPT_NAME = "StealPrompt"
local CARRY_HEIGHT_ABOVE_HEAD = 3
local BEAM_LENGTH = 40
local BEAM_WIDTH = 0.6
local PILL_SIZE = UDim2.fromOffset(300, 64)
local GRAB_BANNER_SECONDS = 1.5
local GRAB_BANNER_HEIGHT = 96
local FOV_PUNCH = 8
local FOV_PUNCH_SECONDS = 0.3
-- The project's one sound id proven to load (a free library whoosh can't
-- be verified to load from here), pitched up into a quick pickup blip.
local PILL_MAX_DISTANCE = 200
local BANNER_SIZE = Vector2.new(480, 92)
local BANNER_TOP = 118 -- under the server banners (AnnouncementController)
local ALARM_PINGS = 3
local ALARM_GAP_SECONDS = 0.25
local FENCE_FADE_SECONDS = 0.3
local FENCE_SHOWN_TRANSPARENCY = 0
local FENCE_LINE_SHOWN_TRANSPARENCY = 0.2
local FENCE_CHECK_SECONDS = 0.2

-- Rejection reason -> toast. Unlisted reasons (exploit-only) stay silent.
local REJECT_MESSAGES: { [string]: string } = {
	Guarded = "The owner is guarding it!",
	AlreadyCarrying = "You're already carrying something!",
	Shielded = "Their shield is up",
	LabCapped = "This lab has been robbed enough for now",
	AlreadyStolen = "Someone's already carrying that",
	Empty = "Nothing to steal there",
	TooFar = "Get closer",
	NoCharacter = "Can't steal right now",
	DataNotLoaded = "Can't steal right now",
}

-- LOCK rejections (HeistService.TryLock reasons; Recharging adds seconds).
local LOCK_REJECT_MESSAGES: { [string]: string } = {
	TooFar = "Get to your LOCK button inside your gate!",
	Carrying = "Not while carrying!",
	AlreadyLocked = "Your lab is already locked",
	Protected = "New labs are protected until Rebirth 1",
}

local THIEF_FAIL_TOASTS: { [string]: string } = {
	Saved = "Caught!",
	Timeout = "Too slow!",
	Died = "You dropped it!",
	Left = "The heist was called off",
	Failed = "It slipped away",
}

type Visual = { Orb: Model, Pill: TextLabel, Connections: { RBXScriptConnection } }

-- Carried-orb visuals by carrying player.
local visuals: { [Player]: Visual } = {}

type Banner = { Holder: Frame, Title: TextLabel, Detail: TextLabel, Bar: Frame? }
local screenGui: ScreenGui
local banner: Banner? = nil
-- The local player's active heist: role, item, other player, end time.
type Active = { Role: string, Item: any, OtherName: string, OtherUserId: number, EndsAt: number, GraceEndsAt: number }
local active: Active? = nil

local MARKER_SIZE = UDim2.fromOffset(48, 48)
local MARKER_MAX_DISTANCE = 60
local STEAL_TIP = "Hold E on their pedestal to steal it!"

-- Pedestal -> its red hand marker (client-only BillboardGui).
local markers: { [Instance]: BillboardGui } = {}
-- Pedestal -> its GUARDED chip / its guard ring (client-only).
local guardChips: { [Instance]: BillboardGui } = {}
local guardRings: { [Instance]: BasePart } = {}
local GUARD_CHIP_SIZE = UDim2.fromOffset(150, 34)
local GUARD_RING_ALPHA = 0.25 -- faint, while the owner is home
local GUARD_RING_GUARDED_ALPHA = 0.6 -- while that pedestal is guarded
-- One-time tips (saved in PlayerData.Tips via TycoonController).
local GUARDED_TIP = "They're guarding it. Wait for them to walk away."
local INTRUDER_TIP = "Someone's in your lab! Stand by your items or run to your LOCK button!"
local LOCK_AFTER_LOSS_TIP = "Tip: hit the LOCK button inside your gate before you leave your lab."
-- Tapping the HUD LOCK chip points the goal arrow at your console this long.
local POINT_AT_CONSOLE_SECONDS = 8
local POINT_AT_CONSOLE_TOAST = "Your LOCK button is just inside your gate"
local pointToken = 0
local STEAL_AGAIN_TEXT = "You can steal again in %ds"

-- "You can steal again in 42s", from the Player attribute HeistCooldownUntil.
local function cooldownText(): string
	local untilTime = localPlayer:GetAttribute("HeistCooldownUntil")
	local left = if typeof(untilTime) == "number"
		then math.max(0, math.ceil(untilTime - Workspace:GetServerTimeNow()))
		else 0
	return STEAL_AGAIN_TEXT:format(left)
end
local LOSS_TIP_DELAY_SECONDS = 2.5
-- Set per carry: this is the player's first time as a victim.
local firstCatch = false

-- Plot -> whether its fence is currently shown on this client.
local fenceShown: { [Instance]: boolean } = {}
local fenceAccumulator = 0

--[[ Helpers ------------------------------------------------------------------ ]]

local function secondsLeft(endsAt: number): number
	return math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow()))
end

local function getOwnPlot(): Instance?
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	return folder and folder:FindFirstChild(PlotNaming.GetPlotName(localPlayer.UserId))
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

--[[ Carried orb (every client, every carrier) --------------------------------- ]]

local function clearVisual(player: Player)
	local visual = visuals[player]
	if not visual then
		return
	end
	visuals[player] = nil
	for _, connection in visual.Connections do
		connection:Disconnect()
	end
	visual.Orb:Destroy()
end

-- Welds the orb group's parts to its orb (unanchored, massless), and the
-- orb above the head. Satellites stay anchored: WorldAnimationController
-- moves them round the orb's live position (FT_Orbit).
local function attachOrb(group: Model, head: BasePart)
	local orb = group.PrimaryPart :: BasePart
	for _, part in group:GetDescendants() do
		local holder = part:FindFirstAncestorWhichIsA("Model")
		local orbiting = holder ~= nil and holder:HasTag(PartKit.ORBIT_TAG)
		if part:IsA("BasePart") and part ~= orb and not orbiting then
			part.Anchored = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = orb
			weld.Part1 = part
			weld.Parent = part
		end
	end
	orb.Anchored = false
	orb.Massless = true
	local weld = Instance.new("Weld")
	weld.Part0 = head
	weld.Part1 = orb
	weld.C0 = CFrame.new(0, head.Size.Y / 2 + CARRY_HEIGHT_ABOVE_HEAD, 0)
	weld.Parent = orb
end

local function buildBeam(orb: BasePart)
	local bottom = Instance.new("Attachment")
	bottom.Name = "BeamBottom"
	bottom.Parent = orb
	local top = Instance.new("Attachment")
	top.Name = "BeamTop"
	top.Position = Vector3.new(0, BEAM_LENGTH, 0)
	top.Parent = orb
	local beam = Instance.new("Beam")
	beam.Name = "ThiefBeam"
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Color = ColorSequence.new(Colors.Danger)
	beam.Transparency = NumberSequence.new(0.2, 1)
	beam.Width0 = BEAM_WIDTH
	beam.Width1 = BEAM_WIDTH
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = orb
end

local function buildPill(orb: BasePart): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "ThiefPill"
	gui.Size = PILL_SIZE
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = PILL_MAX_DISTANCE
	gui.Adornee = orb
	gui.Parent = orb
	UIKit.Label({
		Name = "Caption",
		Text = "THIEF",
		Font = Fonts.Display,
		TextSize = 16,
		TextColor3 = Colors.Danger,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = UITheme.Stroke.Text,
		Parent = gui,
	})
	local label = UIKit.Pill({
		Name = "Text",
		Parent = gui,
		Text = "",
		Gradient = UITheme.Gradients.Heist,
		Font = Fonts.Display,
		TextSize = 22,
		Height = 38,
		TextStroke = 1.5,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 22),
	})
	return label
end

local function buildVisual(player: Player)
	clearVisual(player)
	local tier = player:GetAttribute("HeistTier")
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if typeof(tier) ~= "string" or not head or not head:IsA("BasePart") then
		return
	end
	local mutation = player:GetAttribute("HeistMutation")
	local center = head.CFrame * CFrame.new(0, head.Size.Y / 2 + CARRY_HEIGHT_ABOVE_HEAD, 0)
	local group = PedestalVisuals.BuildCarryOrb(tier, if typeof(mutation) == "string" then mutation else nil, center, Workspace)
	group.Name = "CarriedOrb_" .. player.UserId
	attachOrb(group, head)
	local orb = group.PrimaryPart :: BasePart
	buildBeam(orb)
	local pill = buildPill(orb)
	visuals[player] = { Orb = group, Pill = pill, Connections = {} }
end

-- The catch, cosmetic only: a white flash ring at the thief, CAUGHT! over
-- their head, and the orb flying home to its pedestal on a Bezier arc.
local CATCH_FLY_SECONDS = 0.7
local CATCH_ARC_HEIGHT = 12
local CATCH_RING_SECONDS = 0.4
local CATCH_POP_SECONDS = 1

local function popCatch(player: Player, at: Vector3)
	local anchor = Instance.new("Attachment")
	anchor.Name = "CatchFlash"
	anchor.WorldPosition = at
	anchor.Parent = Workspace.Terrain
	local ring = Instance.new("BillboardGui")
	ring.Size = UDim2.fromOffset(40, 40)
	ring.AlwaysOnTop = false
	ring.LightInfluence = 0
	ring.MaxDistance = PILL_MAX_DISTANCE
	ring.Adornee = anchor
	ring.Parent = anchor
	local circle = Instance.new("Frame")
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromScale(1, 1)
	circle.BackgroundTransparency = 1
	circle.Parent = ring
	UIKit.Corner(circle, 999)
	local stroke = UIKit.Stroke(circle, 6, Colors.White)
	local info = TweenInfo.new(CATCH_RING_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, { Size = UDim2.fromOffset(220, 220) }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	task.delay(CATCH_RING_SECONDS, anchor.Destroy, anchor)

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local pop = Instance.new("BillboardGui")
		pop.Name = "CaughtPop"
		pop.Size = UDim2.fromOffset(200, 50)
		pop.StudsOffset = Vector3.new(0, 3, 0)
		pop.AlwaysOnTop = false
		pop.LightInfluence = 0
		pop.MaxDistance = PILL_MAX_DISTANCE
		pop.Adornee = head
		pop.Parent = head
		local text = UIKit.Label({
			Name = "Text",
			Text = "CAUGHT!",
			Font = Fonts.Display,
			TextSize = 36,
			TextColor3 = Colors.Danger,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Stroke = UITheme.Stroke.Text,
			Parent = pop,
		})
		local rise = TweenInfo.new(CATCH_POP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(pop, rise, { StudsOffset = Vector3.new(0, 6, 0) }):Play()
		TweenService:Create(text, rise, { TextTransparency = 1 }):Play()
		task.delay(CATCH_POP_SECONDS, pop.Destroy, pop)
	end
end

local function flyHome(group: Model, target: Vector3)
	local orb = group.PrimaryPart
	if not orb then
		group:Destroy()
		return
	end
	-- Off the head: anchor the orb (its WeldConstraints carry the shell).
	for _, child in orb:GetChildren() do
		if child:IsA("Weld") then
			child:Destroy()
		end
	end
	orb.Anchored = true
	local p0 = orb.Position
	local p2 = target
	local p1 = (p0 + p2) / 2 + Vector3.new(0, CATCH_ARC_HEIGHT, 0)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min((os.clock() - started) / CATCH_FLY_SECONDS, 1)
		local a = p0:Lerp(p1, t)
		local b = p1:Lerp(p2, t)
		orb.CFrame = CFrame.new(a:Lerp(b, t))
		if t >= 1 then
			connection:Disconnect()
			group:Destroy()
		end
	end)
end

local function refreshVisual(player: Player)
	if player:GetAttribute("HeistTier") ~= nil then
		buildVisual(player)
		return
	end
	local visual = visuals[player]
	local returnTo = player:GetAttribute("HeistReturnTo")
	if visual and player:GetAttribute("HeistOutcome") == "Saved" and typeof(returnTo) == "Vector3" then
		visuals[player] = nil
		for _, connection in visual.Connections do
			connection:Disconnect()
		end
		local orb = visual.Orb.PrimaryPart
		popCatch(player, if orb then orb.Position else returnTo)
		-- HeistReturnTo is the pedestal column's centre; the orb floats at
		-- OrbCenterY above its bottom.
		local p = PlotLayout.Pedestal
		flyHome(visual.Orb, returnTo + Vector3.new(0, p.OrbCenterY - p.ColumnSize.Y / 2, 0))
		return
	end
	clearVisual(player)
end

local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal("HeistTier"):Connect(function()
		refreshVisual(player)
	end)
	player.CharacterAdded:Connect(function()
		task.defer(refreshVisual, player)
	end)
	refreshVisual(player)
end

local function updatePills()
	for player, visual in visuals do
		local endsAt = player:GetAttribute("HeistEndsAt")
		local name = player:GetAttribute("HeistItemName")
		if typeof(endsAt) == "number" then
			visual.Pill.Text = ("%s · %ds"):format(if typeof(name) == "string" then name else "Loot", secondsLeft(endsAt))
		end
	end
end

--[[ Banner (local player only) ------------------------------------------------- ]]

local function clearBanner()
	if banner then
		local holder = banner.Holder
		banner = nil
		UIKit.PopOut(holder).Completed:Once(function()
			holder:Destroy()
		end)
	end
end

local TOUCH_LINE_HEIGHT = 40

-- `extraLine`: a big line under the detail (the first-catch tip, "TOUCH THEM!").
local function buildBanner(isThief: boolean, extraLine: string?): Banner
	if banner then
		banner.Holder:Destroy()
		banner = nil
	end
	local gradient = if isThief then UITheme.Gradients.Orange else UITheme.Gradients.Heist
	local body, holder = UIKit.Panel({
		Name = "HeistBanner",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BANNER_TOP),
		Size = UDim2.fromOffset(BANNER_SIZE.X, BANNER_SIZE.Y + (if extraLine then TOUCH_LINE_HEIGHT else 0)),
		Gradient = { { 0, gradient.Top }, { 1, gradient.Bottom } },
		Radius = 18,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	local z = body.ZIndex + 1
	local title = UIKit.Label({
		Name = "Title",
		Text = if isThief then "GET HOME!" else "THIEF IN YOUR LAB!",
		Font = Fonts.Display,
		TextSize = 28,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	local detail = UIKit.Label({
		Name = "Detail",
		Font = Fonts.BodyHeavy,
		TextSize = 15,
		TextWrapped = true,
		RichText = true,
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, if isThief then 22 else 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 1.5,
		Parent = body,
	})
	if extraLine then
		UIKit.Label({
			Name = "ExtraLine",
			Text = extraLine,
			Font = Fonts.Display,
			TextSize = 34,
			TextColor3 = Colors.Text,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 16, 1, -6),
			Size = UDim2.new(1, -32, 0, TOUCH_LINE_HEIGHT),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z,
			Stroke = UITheme.Stroke.Text,
			Parent = body,
		})
	end
	local bar: Frame? = nil
	if isThief then
		bar = UIKit.ProgressBar({
			Name = "TimeBar",
			Parent = body,
			Position = UDim2.new(0, 24, 1, -22),
			Size = UDim2.new(1, -48, 0, 12),
			FillColor = Colors.Text,
			Value = 1,
			ZIndex = z,
		})
	end
	UIKit.PopIn(holder)
	local built: Banner = { Holder = holder, Title = title, Detail = detail, Bar = bar }
	banner = built
	return built
end

local function updateBanner()
	local current = active
	local shown = banner
	if not current or not shown then
		return
	end
	local left = secondsLeft(current.EndsAt)
	local graceLeft = current.GraceEndsAt - Workspace:GetServerTimeNow()
	local itemName = UIKit.EscapeRichText(tostring(current.Item.Name))
	if current.Role == "Thief" then
		shown.Title.Text = if graceLeft > 0 then "RUN!" else "GET HOME!"
		shown.Detail.Text = ("%s · %ds"):format(itemName, left)
		if shown.Bar then
			UIKit.SetProgress(shown.Bar, left / HeistConfig.CarrySeconds)
		end
	else
		local thief = Players:GetPlayerByUserId(current.OtherUserId)
		local thiefRoot = thief and getRoot(thief)
		local myRoot = getRoot(localPlayer)
		local distance = if thiefRoot and myRoot then (thiefRoot.Position - myRoot.Position).Magnitude else nil
		local status = if graceLeft > 0
			then ("Catch them in %d…"):format(math.ceil(graceLeft))
			elseif distance then ("%d studs away · %ds"):format(math.floor(distance + 0.5), left)
			else nil
		shown.Detail.Text = ("%s grabbed your %s · Touch them to get it back%s"):format(
			UIKit.EscapeRichText(current.OtherName),
			itemName,
			if status then UIKit.Colored("\n" .. status, Colors.Text) else ""
		)
	end
end

-- The grab moment on the thief's own screen: a full-width banner, a pickup
-- blip and a quick FOV punch. Returns once the banner has shown.
local function playGrabMoment(itemName: string)
	local holder = Instance.new("Frame")
	holder.Name = "GrabBanner"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, BANNER_TOP)
	holder.Size = UDim2.new(1, 0, 0, GRAB_BANNER_HEIGHT)
	holder.BackgroundColor3 = Colors.White
	holder.BorderSizePixel = 0
	holder.ZIndex = 5
	holder.Parent = screenGui
	UIKit.PairGradient(holder, UITheme.Gradients.Orange, 0)
	UIKit.Stroke(holder, UITheme.Stroke.Modal)
	UIKit.Label({
		Name = "Text",
		Text = ("🫳 YOU GRABBED %s! RUN HOME!"):format(itemName:upper()),
		Font = Fonts.Display,
		TextSize = 36,
		TextScaled = true,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 1, -24),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6,
		Stroke = UITheme.Stroke.Text,
		Parent = holder,
	})
	UIKit.PopIn(holder)

	SoundKit.Play("Grab", nil)

	local camera = Workspace.CurrentCamera
	if camera then
		local base = camera.FieldOfView
		local half = TweenInfo.new(FOV_PUNCH_SECONDS / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
		TweenService:Create(camera, half, { FieldOfView = base + FOV_PUNCH }):Play()
	end

	task.delay(GRAB_BANNER_SECONDS, function()
		UIKit.PopOut(holder).Completed:Once(function()
			holder:Destroy()
		end)
	end)
end

local function playAlarm()
	task.spawn(function()
		for _ = 1, ALARM_PINGS do
			SoundKit.Play("Alarm", nil, { PlaybackSpeed = 1.3 })
			task.wait(ALARM_GAP_SECONDS)
		end
	end)
end

--[[ Remote handlers --------------------------------------------------------------- ]]

local function onPromptTriggered(prompt: ProximityPrompt, triggeringPlayer: Player)
	if triggeringPlayer ~= localPlayer or prompt.Name ~= STEAL_PROMPT_NAME then
		return
	end
	local owner = prompt:GetAttribute("OwnerUserId")
	local pedestal = prompt.Parent
	local index = pedestal and pedestal:GetAttribute("PedestalIndex")
	if typeof(owner) ~= "number" or typeof(index) ~= "number" then
		return
	end
	-- WorldLabelController's local Mode: a guarded pedestal, your steal
	-- cooldown and the Rebirth-0 teaser are instant taps that only explain
	-- themselves.
	local mode = prompt:GetAttribute("Mode")
	if mode == "Cooldown" then
		ToastController.Show(cooldownText(), "Neutral")
		return
	elseif mode == "Guarded" then
		ToastController.Show(REJECT_MESSAGES.Guarded, "Neutral")
		return
	elseif mode == "Locked" then
		ToastController.Show(("Stealing unlocks at Rebirth %d"):format(HeistConfig.MinRebirths), "Neutral")
		return
	end
	RemoteEvents.RequestSteal:FireServer({ OwnerUserId = owner, PedestalIndex = index })
end

local function onHeistStarted(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Item) ~= "table" or typeof(payload.EndsAt) ~= "number" then
		return
	end
	local isThief = payload.Role == "Thief"
	local started: Active = {
		Role = if isThief then "Thief" else "Victim",
		Item = payload.Item,
		OtherName = tostring(payload.OtherName),
		OtherUserId = tonumber(payload.OtherUserId) or 0,
		EndsAt = payload.EndsAt,
		GraceEndsAt = tonumber(payload.GraceEndsAt) or 0,
	}
	active = started
	if isThief then
		-- The big grab banner first, then the GET HOME! bar (if still carrying).
		playGrabMoment(tostring(started.Item.Name))
		task.delay(GRAB_BANNER_SECONDS, function()
			if active == started then
				buildBanner(true)
				updateBanner()
			end
		end)
	else
		-- First time as a victim: a big TOUCH THEM! line and a throbbing arrow.
		firstCatch = not TycoonController.HasSeenTip("catch")
		if firstCatch then
			TycoonController.MarkTipSeen("catch")
		end
		buildBanner(false, if firstCatch then "TOUCH THEM!" else nil)
		updateBanner()
	end
	if isThief then
		local plot = getOwnPlot()
		local gate = plot and plot:FindFirstChild("SignGate")
		if gate then
			GoalMarkerController.SetOverride(gate, "GET HOME!", false)
		end
	else
		local thief = Players:GetPlayerByUserId(started.OtherUserId)
		local thiefRoot = thief and getRoot(thief)
		if thiefRoot then
			GoalMarkerController.SetOverride(thiefRoot, "THIEF!", true, firstCatch)
		end
		playAlarm()
	end
end

local function onHeistEnded(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Outcome == "Rejected" then
		if payload.Role == "Lock" then
			local text = if payload.Reason == "Recharging"
				then ("Lock recharging · %ds"):format(tonumber(payload.Seconds) or 0)
				else LOCK_REJECT_MESSAGES[payload.Reason]
			if text then
				ToastController.Show(text, "Neutral")
			end
			return
		end
		if payload.Reason == "Cooldown" then
			ToastController.Show(STEAL_AGAIN_TEXT:format(tonumber(payload.Seconds) or 0), "Neutral")
			return
		end
		local message = REJECT_MESSAGES[payload.Reason]
		if message then
			ToastController.Show(message, "Neutral")
		end
		return
	end

	active = nil
	clearBanner()
	GoalMarkerController.SetOverride(nil)
	local item = payload.Item
	if typeof(item) ~= "table" then
		return
	end
	local other = tostring(payload.OtherName)
	if payload.Role == "Thief" then
		if payload.Outcome == "Delivered" then
			ResultController.ShowHeistComplete(item, other, cooldownText())
		else
			ToastController.Show(THIEF_FAIL_TOASTS[payload.Outcome] or "It slipped away", "Error")
		end
	else
		if payload.Outcome == "Delivered" then
			ResultController.ShowItemStolen(item, other, HeistConfig.VictimShieldSeconds)
			-- First real loss: after the card, how to stop the next one.
			if not TycoonController.HasSeenTip("lockAfterLoss") then
				TycoonController.MarkTipSeen("lockAfterLoss")
				task.delay(LOSS_TIP_DELAY_SECONDS, function()
					ToastController.Show(LOCK_AFTER_LOSS_TIP, "Neutral", { Big = true })
				end)
			end
		elseif payload.Outcome == "Saved" then
			ToastController.Show(("SAVED! You got your %s back"):format(tostring(item.Name)), "Neutral")
		else
			ToastController.Show(("Your %s is back!"):format(tostring(item.Name)), "Neutral")
		end
	end
end

--[[ Shield fences (every plot) ------------------------------------------------------ ]]

local function setFence(plot: Instance, shown: boolean)
	fenceShown[plot] = shown
	local fence = plot:FindFirstChild("ShieldFence")
	if not fence then
		return
	end
	local info = TweenInfo.new(FENCE_FADE_SECONDS, Enum.EasingStyle.Quad)
	for _, part in fence:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute(PlotKit.SHIELD_PART_ATTRIBUTE) then
			local shownTransparency = if part.Material == Enum.Material.Neon
				then FENCE_LINE_SHOWN_TRANSPARENCY
				else FENCE_SHOWN_TRANSPARENCY
			TweenService:Create(part, info, { Transparency = if shown then shownTransparency else 1 }):Play()
		end
	end
end

--[[ Your LOCK console ------------------------------------------------------------- ]]

local consoleState: ShieldState.State? = nil
local consoleLabel: BillboardKit.PadLabel? = nil
local consoleLabelGui: BillboardGui? = nil

local function updateConsole()
	local plot = getOwnPlot()
	local console = plot and plot:FindFirstChild("LockConsole")
	local post = console and console:FindFirstChild("Post")
	if not plot or not console or not post then
		return
	end
	local labelGui = post:FindFirstChild("LockLabel")
	if labelGui and labelGui:IsA("BillboardGui") and labelGui ~= consoleLabelGui then
		consoleLabelGui = labelGui
		consoleLabel = BillboardKit.FindPadLabel(labelGui)
		consoleState = nil
	end
	local state, seconds = ShieldState.Get(plot)
	-- Someone walked into your unlocked lab: tell you once (the HUD LOCK
	-- chip turns into the red alarm on its own while LOCK is ready).
	if (state == "Ready" or state == "Recharging") and not TycoonController.HasSeenTip("intruder") then
		local origin = plot:IsA("Model") and plot.PrimaryPart
		if origin then
			for _, other in Players:GetPlayers() do
				local root = other ~= localPlayer and getRoot(other)
				if root and PlotLayout.IsInsidePlot(origin.CFrame:PointToObjectSpace(root.Position)) then
					TycoonController.MarkTipSeen("intruder")
					ToastController.Show(INTRUDER_TIP, "Neutral", { Big = true })
					break
				end
			end
		end
	end
	local label = consoleLabel
	if label then
		if state == "Locked" then
			label.SetPill(("LOCKED · %ds"):format(seconds))
		elseif state == "Recharging" then
			label.SetPill(("RECHARGING · %ds"):format(seconds))
		end
	end
	if state == consoleState then
		return
	end
	consoleState = state
	local prompt = post:FindFirstChild("LockPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = state == "Ready"
	end
	if label then
		if state == "Ready" then
			label.SetPill(("READY · %ds shield"):format(HeistConfig.ShieldSeconds))
			label.SetPillGradient(UITheme.Gradients.Shield)
		elseif state == "Locked" then
			label.SetPillGradient(UITheme.Gradients.Teal)
		elseif state == "Recharging" then
			label.SetPillGradient(UITheme.Gradients.Disabled)
		else
			label.SetPill("🛡 PROTECTED · NEW LAB")
			label.SetPillGradient(UITheme.Gradients.Teal)
		end
	end
	local face = console:FindFirstChild("ButtonFace")
	local gui = face and face:FindFirstChild("ButtonGui")
	local disc = gui and gui:FindFirstChild("Disc")
	if disc and disc:IsA("Frame") then
		disc.BackgroundColor3 = if state == "Ready"
			then UITheme.World.Shield
			elseif state == "Locked" then Colors.ShieldTeal
			else UITheme.Gradients.Disabled.Top
		disc.BackgroundTransparency = if state == "Protected" then 0.6 else 0
	end
	if gui and gui:IsA("SurfaceGui") then
		-- Glows teal while locked; dim otherwise when it can't be pressed.
		gui.Brightness = if state == "Locked" then 2 elseif state == "Ready" then 1.5 else 0.6
	end
end

local function updateFences()
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	if not folder then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for _, plot in folder:GetChildren() do
		local shieldUntil = plot:GetAttribute("ShieldUntil")
		local shown = typeof(shieldUntil) == "number" and shieldUntil > now
		if (fenceShown[plot] == true) ~= shown then
			setFence(plot, shown)
		end
	end
	for plot in fenceShown do
		if plot.Parent ~= folder then
			fenceShown[plot] = nil
		end
	end
end

--[[ Teaching: hand markers and the one-time tip ------------------------------------- ]]

local function buildMarker(pedestal: BasePart): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "StealMarker"
	gui.Size = MARKER_SIZE
	-- Offsets are from the pedestal's centre; PlotLayout's are from its bottom.
	local p = PlotLayout.Pedestal
	gui.StudsOffset = Vector3.new(0, p.StealMarkerOffsetY - p.ColumnSize.Y / 2, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = MARKER_MAX_DISTANCE
	gui.Adornee = pedestal
	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.Size = UDim2.fromScale(1, 1)
	circle.BackgroundColor3 = Colors.Danger
	circle.Parent = gui
	UIKit.Corner(circle, 999)
	UIKit.Stroke(circle, 3)
	UIKit.Label({
		Name = "Hand",
		Text = "🫳",
		Font = Fonts.Display,
		TextSize = 26,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = circle,
	})
	gui.Parent = pedestal -- created on this client: nobody else sees it
	return gui
end

local function buildGuardChip(pedestal: BasePart): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "GuardedChip"
	gui.Size = GUARD_CHIP_SIZE
	local p = PlotLayout.Pedestal
	gui.StudsOffset = Vector3.new(0, p.GuardedChipOffsetY - p.ColumnSize.Y / 2, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = MARKER_MAX_DISTANCE
	gui.Adornee = pedestal
	UIKit.Pill({
		Name = "Text",
		Parent = gui,
		Text = "🛡 GUARDED",
		Color = Colors.ShieldTeal,
		Font = Fonts.Display,
		TextSize = 18,
		Height = 32,
		TextStroke = 1.5,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	gui.Parent = pedestal -- created on this client
	return gui
end

-- A faint teal ring on the floor round the pedestal, OwnerBlockRadius wide:
-- a SurfaceGui ring face (BillboardKit.BuildPadFace), not a Neon disc.
local function buildGuardRing(pedestal: BasePart, origin: CFrame): BasePart
	local bottom = pedestal.Position - Vector3.new(0, pedestal.Size.Y / 2, 0)
	local face = BillboardKit.BuildPadFace(
		Workspace, -- created on this client: only this player sees it
		CFrame.new(bottom) * origin.Rotation,
		HeistConfig.OwnerBlockRadius * 2,
		Colors.ShieldTeal,
		nil
	)
	face.Name = "GuardRing"
	local gui = face:FindFirstChild("PadFace")
	if gui then
		-- Just the ring: drop the soft glow fill.
		for _, name in { "GlowOuter", "GlowCore" } do
			local glow = gui:FindFirstChild(name)
			if glow and glow:IsA("Frame") then
				glow.Visible = false
			end
		end
	end
	return face
end

local function setGuardRingAlpha(face: BasePart, alpha: number)
	local gui = face:FindFirstChild("PadFace")
	local ring = gui and gui:FindFirstChild("Ring")
	local stroke = ring and ring:FindFirstChild("RingStroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Transparency = 1 - alpha
	end
end

local function ownerIsHome(plot: Instance, origin: CFrame): boolean
	local ownerId = plot:GetAttribute("OwnerUserId")
	local owner = typeof(ownerId) == "number" and Players:GetPlayerByUserId(ownerId) or nil
	local root = owner and getRoot(owner)
	return root ~= nil and PlotLayout.IsInsidePlot(origin:PointToObjectSpace(root.Position))
end

-- GUARDED chips (every guarded filled pedestal) and guard rings (filled
-- pedestals of an owner who's home), for every viewer.
local function updateGuards()
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	if not folder then
		return
	end
	local seenChips: { [Instance]: boolean } = {}
	local seenRings: { [Instance]: boolean } = {}
	for _, plot in folder:GetChildren() do
		local pedestals = plot:FindFirstChild("Pedestals")
		local origin = plot:IsA("Model") and plot.PrimaryPart
		if pedestals and origin and plot:GetAttribute("Protected") == false then
			local home = ownerIsHome(plot, origin.CFrame)
			for _, pedestal in pedestals:GetChildren() do
				if pedestal:IsA("BasePart") and pedestal:GetAttribute("Filled") == true then
					local guarded = pedestal:GetAttribute("GuardedByOwner") == true
						and pedestal:GetAttribute("BeingStolen") ~= true
					if guarded then
						seenChips[pedestal] = true
						local chip = guardChips[pedestal]
						if not chip or not chip.Parent then
							guardChips[pedestal] = buildGuardChip(pedestal)
						end
					end
					if home then
						seenRings[pedestal] = true
						local ring = guardRings[pedestal]
						if not ring or not ring.Parent then
							ring = buildGuardRing(pedestal, origin.CFrame)
							guardRings[pedestal] = ring
						end
						setGuardRingAlpha(ring :: BasePart, if guarded then GUARD_RING_GUARDED_ALPHA else GUARD_RING_ALPHA)
					end
				end
			end
		end
	end
	for pedestal, chip in guardChips do
		if not seenChips[pedestal] then
			chip:Destroy()
			guardChips[pedestal] = nil
		end
	end
	for pedestal, ring in guardRings do
		if not seenRings[pedestal] then
			ring:Destroy()
			guardRings[pedestal] = nil
		end
	end
end

-- Markers on every grabbable enemy pedestal, and the first-visit tip.
-- A pedestal worth a red hand: grabbable now, or after your cooldown (the
-- markers stay up while it runs so you can plan the next target).
local function isMarkTarget(pedestal: Instance, prompt: Instance): boolean
	local mode = prompt:GetAttribute("Mode")
	return mode == "Steal" or (mode == "Cooldown" and pedestal:GetAttribute("GuardedByOwner") ~= true)
end

local function updateTeaching()
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	if not folder then
		return
	end
	local myRoot = getRoot(localPlayer)
	local seen: { [Instance]: boolean } = {}
	for _, plot in folder:GetChildren() do
		local pedestals = plot:FindFirstChild("Pedestals")
		local hasTarget = false
		if pedestals then
			for _, pedestal in pedestals:GetChildren() do
				local prompt = pedestal:FindFirstChild("StealPrompt")
				if pedestal:IsA("BasePart") and prompt and isMarkTarget(pedestal, prompt) then
					hasTarget = true
					seen[pedestal] = true
					local marker = markers[pedestal]
					if not marker or not marker.Parent then
						markers[pedestal] = buildMarker(pedestal)
					end
				end
			end
		end
		-- First time inside a lab you could rob: say how, once.
		local origin = plot:IsA("Model") and plot.PrimaryPart
		if hasTarget and myRoot and origin and not TycoonController.HasSeenTip("stealHowTo") then
			if PlotLayout.IsInsidePlot(origin.CFrame:PointToObjectSpace(myRoot.Position)) then
				TycoonController.MarkTipSeen("stealHowTo")
				ToastController.Show(STEAL_TIP, "Neutral", { Big = true })
			end
		end
		-- Standing at a pedestal its owner is guarding: wait them out.
		if pedestals and myRoot and not TycoonController.HasSeenTip("guarded") then
			for _, pedestal in pedestals:GetChildren() do
				local prompt = pedestal:FindFirstChild("StealPrompt")
				if
					pedestal:IsA("BasePart")
					and prompt
					and prompt:GetAttribute("Mode") == "Guarded"
					and (pedestal.Position - myRoot.Position).Magnitude <= HeistConfig.PromptDistance
				then
					TycoonController.MarkTipSeen("guarded")
					ToastController.Show(GUARDED_TIP, "Neutral", { Big = true })
					break
				end
			end
		end
	end
	for pedestal, marker in markers do
		if not seen[pedestal] then
			marker:Destroy()
			markers[pedestal] = nil
		end
	end
end

--[[ Init ------------------------------------------------------------------------- ]]

-- The HUD LOCK chip was tapped: point the goal arrow at your console for a
-- few seconds (never over a running heist's arrow).
local function pointAtConsole()
	ToastController.Show(POINT_AT_CONSOLE_TOAST, "Neutral")
	if active then
		return
	end
	local plot = getOwnPlot()
	local console = plot and plot:FindFirstChild("LockConsole")
	if not console then
		return
	end
	pointToken += 1
	local myToken = pointToken
	GoalMarkerController.SetOverride(console, "LOCK", false)
	task.delay(POINT_AT_CONSOLE_SECONDS, function()
		if pointToken == myToken and not active then
			GoalMarkerController.SetOverride(nil)
		end
	end)
end

function HeistController.Init()
	screenGui = UIKit.Screen("Heist", 105)
	HudController.SetLockChipHandler(pointAtConsole)
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	RemoteEvents.HeistStarted.OnClientEvent:Connect(onHeistStarted)
	RemoteEvents.HeistEnded.OnClientEvent:Connect(onHeistEnded)
	-- Pulls, upgrades and the Multiplier Pad all refuse a carrying thief
	-- with Reason "Carrying"; one toast for all of them.
	for _, remote in {
		RemoteEvents.GachaPullResult,
		RemoteEvents.GachaMultiPullResult,
		RemoteEvents.UpgradeResult,
		RemoteEvents.UpgradeMaxResult,
		RemoteEvents.MultiplierUpgraded,
	} do
		remote.OnClientEvent:Connect(function(payload: any)
			if typeof(payload) == "table" and payload.Success == false and payload.Reason == "Carrying" then
				ToastController.Show("Get home with that item first!", "Neutral")
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(clearVisual)

	RunService.Heartbeat:Connect(function(dt: number)
		updatePills()
		updateBanner()
		fenceAccumulator += dt
		if fenceAccumulator >= FENCE_CHECK_SECONDS then
			fenceAccumulator = 0
			updateFences()
			updateTeaching()
			updateGuards()
			updateConsole()
		end
	end)
end

return HeistController
