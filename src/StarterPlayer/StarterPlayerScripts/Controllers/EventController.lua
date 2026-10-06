--!strict
--[[
	EventController
	---------------
	Every event visual, client-side, from the workspace attributes
	EventService publishes (read through EventState) plus its EventFx cues.
	Rewards are all server-side; nothing here pays.

	On a live start (the attribute flips while you're in the game):
	  * a start banner straight away for 2.5 s: the icon, name and blurb
	    on the event's gradient, with a sound (no countdown). Rainbow Storm
	    also gets the big SERVER · EVENT banner (AnnouncementController).
	  * the sky (below). On the end: a toast, and the sky goes back.

	Sky: the baseline Lighting values (what LightingService set) are taken
	once, before anything here touches them, and each event tweens from
	that baseline and back to it exactly:
	  Golden Rain    gold tint + falling gold sparkles round the camera
	  Power Surge    storm tint, Atmosphere a little denser and bluer, and
	                 every generator Band flickers (LocalTransparencyModifier,
	                 so it never fights the server's Band state)
	  Night          ClockTime to midnight (no light is raised: the orbs and
	                 cores just read brighter in the dark)
	  Void Moon      a night + purple tint + a purple moon disc
	  Rainbow Storm  a slow tint through the rainbow stops + rainbow sparkles

	HUD chip (top-centre, clear of the top bar and the goal tracker): the
	running event on its gradient with a live timer ("⚡ POWER SURGE ·
	3:12"), else a muted "NEXT · ☄ METEOR SHOWER in 8:40", with a small ⓘ
	inside its right end. A tap anywhere on it opens the info card
	(EventInfoCard); the first time you see an event type it pulses until
	that first tap. The two
	street Event Boards (WorldService) are filled from the same lineup
	(EventState.GetLineup) every second.

	EventFx (S->C cues): Lightning (beam from the sky, a ColorCorrection
	flash, low thunder), Meteor (a glowing rock falling to its crater), Coin
	(a "+$X" pop where your coin was). EventNotice is a toast; EventReward a
	big result card.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local GeneratorKit = require(ReplicatedStorage.Shared.Modules.GeneratorKit)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local RevealEffects = require(script.Parent.Parent.Effects.RevealEffects)
local AnnouncementController = require(script.Parent.AnnouncementController)
local ResultController = require(script.Parent.ResultController)
local ToastController = require(script.Parent.ToastController)
local TycoonController = require(script.Parent.TycoonController)
local GoalMarkerController = require(script.Parent.GoalMarkerController)
local EventInfoCard = require(script.Parent.Parent.UI.EventInfoCard)

local EventController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts
local Sky = UITheme.EventSky

local localPlayer = Players.LocalPlayer

-- The one sound id proven to load in this project (see RevealEffects);
-- thunder is the same ping slowed right down.

local SKY_TWEEN_SECONDS = 3
local NIGHT_TWEEN_SECONDS = 6
local NIGHT_CLOCK = 23.99 -- tweened forward through dusk; midnight
local STORM_DENSITY_ADD = 0.12
local GOLD_TINT_ALPHA = 1
local RAINBOW_TINT_TOWARD_WHITE = 0.78
local RAINBOW_CYCLE_SECONDS = 12

local BANNER_SIZE = Vector2.new(460, 120)
local BANNER_Y = 96 -- under the top bar and the goal tracker's row
local BANNER_HOLD_SECONDS = 2.5

local PARTICLE_HEIGHT = 30
local PARTICLE_AREA = 80
local PARTICLE_RATE = 40

local FLICKER_STEP = 0.09
local FLICKER_DIM = 0.65
local BAND_RESCAN_SECONDS = 2

local MOON_DISTANCE = 700
local MOON_DIAMETER = 90
local MOON_DIRECTION = Vector3.new(-0.55, 0.45, -0.7).Unit

local LIGHTNING_HEIGHT = 140
local LIGHTNING_SECONDS = 0.35
local FLASH_BRIGHTNESS = 0.35
local FLASH_SECONDS = 0.18

local METEOR_SHAKE_RADIUS = 60

local POP_TEXT_SIZE = 24
local BIG_POP_TEXT_SIZE = 36
local RESULT_POP_SECONDS = 1.5
local WARNING_RING_DIAMETER = 6
local INCOMING_RING_DIAMETER = 8
local SURGE_CHIP_MAX_DISTANCE = 80
local SURGE_CHIP_RESCAN_SECONDS = 2
local POP_SECONDS = 1.2
local POP_RISE_STUDS = 4
local POP_MAX_DISTANCE = 150

local CHIP_Y = 12
local CHIP_SIZE = { Desktop = Vector2.new(330, 44), Phone = Vector2.new(270, 44) }
local CHIP_TEXT_SIZE = { Desktop = 18, Phone = 15 }
local LINEUP_COUNT = 3
-- A small ⓘ sits inside the chip's right end. The first time you see an
-- event type (Tips "event_<Id>" unseen) the chip itself pulses (a scale
-- bounce + a gold glow) until you tap it once. The card never opens by
-- itself.
local CHIP_ICON_WIDTH = 26 -- the ⓘ, and the matching inset on both sides
local PULSE_SCALE = 1.06
local PULSE_SECONDS = 0.5
local PULSE_GLOW_SPREAD = 8 -- px the glow shows past the chip
local PULSE_GLOW_TRANSPARENCY = { From = 0.85, To = 0.4 }
local GUIDE_SECONDS = 0.5 -- event arrows and pad pills refresh
local ON_PAD_RADIUS = 6 -- standing on your Gacha Pad: the arrow moves to the machine
local EVENT_PILL_MAX_DISTANCE = 120

-- Baseline Lighting, captured before the first change and restored exactly.
type Baseline = {
	ClockTime: number,
	Tint: Color3,
	Brightness: number,
	Density: number?,
	AtmosphereColor: Color3?,
}

local baseline: Baseline? = nil
local currentId: string? = nil
-- /trailer: an event's look shown on this client only (PreviewLocal); live
-- event changes wait until StopPreview.
local previewId: string? = nil
local instantSky = false -- PreviewLocal snaps instead of tweening
local moonDirection = MOON_DIRECTION
-- Bumped on every change: loops from the last event exit.
local generation = 0
local screenGui: ScreenGui
local bannerHolder: Frame? = nil

--[[ Helpers ------------------------------------------------------------------- ]]

local function colorCorrection(): ColorCorrectionEffect?
	return Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
end

local function atmosphere(): Atmosphere?
	return Lighting:FindFirstChildOfClass("Atmosphere")
end

local function captureBaseline(): Baseline
	if baseline then
		return baseline
	end
	local cc = colorCorrection()
	local atm = atmosphere()
	local captured: Baseline = {
		ClockTime = Lighting.ClockTime,
		Tint = if cc then cc.TintColor else Colors.White,
		Brightness = if cc then cc.Brightness else 0,
		Density = if atm then atm.Density else nil,
		AtmosphereColor = if atm then atm.Color else nil,
	}
	baseline = captured
	return captured
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any })
	if instantSky then
		for property, value in goal do
			(instance :: any)[property] = value
		end
		return
	end
	TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal):Play()
end



--[[ Sky ------------------------------------------------------------------------- ]]

-- Every client FX of an event (sky particles, the moon, lightning, meteors,
-- pops) goes in Workspace.EventObjects.<Id>, next to the server's objects
-- (local children exist only on this client). The event's end clears the
-- whole folder here, as the server clears its own.
local fxFolder: Folder? = nil

local function fxParent(id: string?): Instance
	local folder = if id then EventState.GetObjectsFolder(id) else nil
	return folder or Workspace.CurrentCamera
end

-- A tiny invisible anchored part to hang attachments and billboards on
-- (instead of Terrain attachments, which no folder would clean up).
local function anchorPart(parent: Instance, position: Vector3, name: string): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.one * 0.2
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(position)
	part.Parent = parent
	return part
end

-- Clears this client's FX for `id` (and the sky folder).
local function clearFx(id: string?)
	if fxFolder then
		fxFolder:Destroy()
		fxFolder = nil
	end
	local folder = if id then EventState.GetObjectsFolder(id) else nil
	if folder then
		folder:ClearAllChildren()
	end
end

local function newFx(id: string): Folder
	if fxFolder then
		fxFolder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "SkyFx"
	-- A preview's FX hang off the camera, never the server's event folder.
	folder.Parent = fxParent(if previewId then nil else id)
	fxFolder = folder
	return folder
end

-- Tweens Lighting back to the baseline, then sets it exactly.
local function restoreSky(myGeneration: number)
	local base = baseline
	if not base then
		return
	end
	local cc = colorCorrection()
	local atm = atmosphere()
	local clockChanged = math.abs(Lighting.ClockTime - base.ClockTime) > 0.01
	local clockSeconds = if clockChanged then NIGHT_TWEEN_SECONDS else SKY_TWEEN_SECONDS
	if clockChanged then
		-- From midnight forward into the afternoon again (0 -> 17.2).
		if Lighting.ClockTime > base.ClockTime then
			Lighting.ClockTime = 0
		end
		tween(Lighting, clockSeconds, { ClockTime = base.ClockTime })
	end
	if cc then
		tween(cc, SKY_TWEEN_SECONDS, { TintColor = base.Tint, Brightness = base.Brightness })
	end
	if atm and base.Density and base.AtmosphereColor then
		tween(atm, SKY_TWEEN_SECONDS, { Density = base.Density, Color = base.AtmosphereColor })
	end
	task.delay(math.max(clockSeconds, SKY_TWEEN_SECONDS) + 0.1, function()
		-- Only snap when nothing new started (a switch tweens on from here).
		if generation ~= myGeneration or currentId ~= nil then
			return
		end
		Lighting.ClockTime = base.ClockTime
		if cc then
			cc.TintColor = base.Tint
			cc.Brightness = base.Brightness
		end
		if atm and base.Density and base.AtmosphereColor then
			atm.Density = base.Density
			atm.Color = base.AtmosphereColor
		end
	end)
end

-- Sparkles falling round the camera in `color` (a ColorSequence).
local function cameraParticles(folder: Folder, color: ColorSequence, myGeneration: number)
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "WeatherEmitter"
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.Transparency = 1
	emitterPart.Size = Vector3.new(PARTICLE_AREA, 1, PARTICLE_AREA)
	emitterPart.Parent = folder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = color
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new(0.35)
	emitter.Lifetime = NumberRange.new(3, 4)
	emitter.Rate = PARTICLE_RATE
	emitter.Speed = NumberRange.new(8, 12)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.SpreadAngle = Vector2.new(10, 10)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = emitterPart
	task.spawn(function()
		while generation == myGeneration and emitterPart.Parent do
			local camera = Workspace.CurrentCamera
			if camera then
				emitterPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, PARTICLE_HEIGHT, 0))
			end
			task.wait(0.1)
		end
	end)
end

-- Every generator Band on every plot, flickering until the event ends.
local function flickerBands(myGeneration: number)
	local bands: { BasePart } = {}
	local scanned = -math.huge
	while generation == myGeneration do
		if os.clock() - scanned > BAND_RESCAN_SECONDS then
			scanned = os.clock()
			bands = {}
			local plots = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
			if plots then
				for _, descendant in plots:GetDescendants() do
					local parent = descendant.Parent
					if
						descendant.Name == "Band"
						and descendant:IsA("BasePart")
						and parent
						and parent.Name:sub(1, #GeneratorKit.MODEL_PREFIX) == GeneratorKit.MODEL_PREFIX
					then
						table.insert(bands, descendant)
					end
				end
			end
		end
		for _, band in bands do
			band.LocalTransparencyModifier = if math.random() < 0.3 then FLICKER_DIM else 0
		end
		task.wait(FLICKER_STEP)
	end
	for _, band in bands do
		band.LocalTransparencyModifier = 0
	end
end

-- The Void Moon: a purple disc (a world BillboardGui, so the haze doesn't
-- swallow it) held in the same patch of sky as the camera moves.
local function buildMoon(folder: Folder, myGeneration: number)
	local anchor = anchorPart(folder, Vector3.zero, "VoidMoonAnchor")
	local gui = Instance.new("BillboardGui")
	gui.Name = "VoidMoon"
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(MOON_DIAMETER, MOON_DIAMETER)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = MOON_DISTANCE * 2
	gui.Parent = folder
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.Size = UDim2.fromScale(1, 1)
	disc.BackgroundColor3 = Colors.White
	disc.BorderSizePixel = 0
	disc.Parent = gui
	UIKit.Corner(disc, 9999)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Sky.MoonGlow),
		ColorSequenceKeypoint.new(1, Sky.Moon),
	})
	gradient.Rotation = 135
	gradient.Parent = disc
	task.spawn(function()
		while generation == myGeneration and gui.Parent do
			local camera = Workspace.CurrentCamera
			if camera then
				anchor.CFrame = CFrame.new(camera.CFrame.Position + moonDirection * MOON_DISTANCE)
			end
			RunService.RenderStepped:Wait()
		end
		anchor:Destroy()
	end)
end

local function rainbowTint(myGeneration: number)
	local stops = UITheme.Mutation.RainbowStops
	local started = os.clock()
	while generation == myGeneration do
		local cc = colorCorrection()
		if cc then
			local t = ((os.clock() - started) / RAINBOW_CYCLE_SECONDS) % 1 * #stops
			local from = stops[math.floor(t) % #stops + 1]
			local to = stops[(math.floor(t) + 1) % #stops + 1]
			cc.TintColor = from:Lerp(to, t % 1):Lerp(Colors.White, RAINBOW_TINT_TOWARD_WHITE)
		end
		task.wait(0.05)
	end
end

local function applySky(id: string, myGeneration: number)
	local base = captureBaseline()
	local cc = colorCorrection()
	local atm = atmosphere()
	local folder = newFx(id)
	if id == "GoldenRain" then
		if cc then
			tween(cc, SKY_TWEEN_SECONDS, { TintColor = base.Tint:Lerp(Sky.GoldTint, GOLD_TINT_ALPHA) })
		end
		cameraParticles(folder, ColorSequence.new(UITheme.World.AccentGold), myGeneration)
	elseif id == "PowerSurge" then
		if cc then
			tween(cc, SKY_TWEEN_SECONDS, { TintColor = Sky.StormTint })
		end
		if atm and base.Density then
			tween(atm, SKY_TWEEN_SECONDS, { Density = base.Density + STORM_DENSITY_ADD, Color = Sky.StormHaze })
		end
		task.spawn(flickerBands, myGeneration)
	elseif id == "Night" or id == "VoidMoon" then
		tween(Lighting, NIGHT_TWEEN_SECONDS, { ClockTime = NIGHT_CLOCK })
		if id == "VoidMoon" then
			if cc then
				tween(cc, SKY_TWEEN_SECONDS, { TintColor = Sky.VoidTint })
			end
			buildMoon(folder, myGeneration)
		end
	elseif id == "RainbowStorm" then
		cameraParticles(folder, UITheme.GetRainbowSequence(), myGeneration)
		task.spawn(rainbowTint, myGeneration)
	end
end

--[[ Banner ------------------------------------------------------------------------- ]]

local function closeBanner()
	local holder = bannerHolder
	bannerHolder = nil
	if holder then
		UIKit.PopOut(holder).Completed:Once(function()
			holder:Destroy()
		end)
	end
end

-- The icon + name + blurb on the event's gradient, straight away, for
-- BANNER_HOLD_SECONDS. A newer event's banner replaces it.
local function showStartBanner(id: string, myGeneration: number)
	closeBanner()
	local body, holder = UIKit.Panel({
		Name = "EventBanner",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BANNER_Y),
		Size = UDim2.fromOffset(BANNER_SIZE.X, BANNER_SIZE.Y),
		Radius = 22,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	bannerHolder = holder
	body.BackgroundColor3 = Colors.White
	if id == "RainbowStorm" then
		local gradient = Instance.new("UIGradient")
		gradient.Color = UITheme.GetRainbowSequence()
		gradient.Parent = body
	else
		UIKit.PairGradient(body, UITheme.GetEventGradient(id))
	end
	local z = body.ZIndex + 1
	UIKit.Label({
		Name = "Title",
		Text = ("%s %s"):format(EventConfig.Icons[id] or "", EventConfig.Names[id] or id),
		Font = Fonts.Display,
		TextSize = 40,
		Position = UDim2.fromOffset(16, 14),
		Size = UDim2.new(1, -32, 0, 48),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 3,
		Parent = body,
	})
	local _, strength = EventState.GetActive()
	UIKit.Label({
		Name = "Blurb",
		Text = (EventConfig.Blurbs[id] or "") .. (if strength > 1 then (" · ADMIN x%d"):format(strength) else ""),
		Font = Fonts.Body,
		TextSize = 18,
		TextWrapped = true,
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.new(1, -32, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	SoundKit.Play("EventStart", nil)
	UIKit.PopIn(holder)
	task.delay(BANNER_HOLD_SECONDS, function()
		if bannerHolder == holder and generation == myGeneration then
			closeBanner()
		end
	end)
end

--[[ Event changes -------------------------------------------------------------------- ]]

-- Defined with the HUD below.
local refreshGuidance: () -> ()
local refreshChipPulse: () -> ()

local function onEventChanged(live: boolean)
	if previewId then
		return -- StopPreview picks up whatever is live then
	end
	local id = EventState.GetActive()
	if id == currentId then
		return
	end
	local old = currentId
	currentId = id
	generation += 1
	local myGeneration = generation
	if old then
		clearFx(old)
		restoreSky(myGeneration)
		if live then
			local text = ("%s %s is over"):format(EventConfig.Icons[old] or "", EventConfig.Names[old] or old)
			local tally = localPlayer:GetAttribute("GoldenRainTally")
			if old == "GoldenRain" and typeof(tally) == "number" and tally > 0 then
				text ..= (" · you earned +%s"):format(NumberFormat.Money(tally))
			end
			ToastController.Show(text, "Neutral")
			SoundKit.Play("EventEnd", nil)
		end
	end
	if not id then
		return
	end
	-- A switch straight from one event to another tweens from the current
	-- look; the baseline was captured before the first.
	task.delay(if old then SKY_TWEEN_SECONDS + 0.2 else 0, function()
		if generation == myGeneration then
			applySky(id, myGeneration)
		end
	end)
	if live then
		showStartBanner(id, myGeneration)
		if id == "RainbowStorm" then
			local info = EventConfig.GetInfo(id)
			AnnouncementController.ShowEventHype("🌈 RAINBOW STORM! " .. (if info then info.Happening[1] else ""))
		end
	end
end

--[[ EventFx -------------------------------------------------------------------------- ]]

local function strikeLightning(position: Vector3)
	local parent = fxParent("PowerSurge")
	local topPart = anchorPart(parent, position + Vector3.new(math.random(-12, 12), LIGHTNING_HEIGHT, math.random(-12, 12)), "BoltTop")
	local bottomPart = anchorPart(parent, position, "BoltBottom")
	local top = Instance.new("Attachment")
	top.Parent = topPart
	local bottom = Instance.new("Attachment")
	bottom.Parent = bottomPart
	local beam = Instance.new("Beam")
	beam.Attachment0 = top
	beam.Attachment1 = bottom
	beam.Color = ColorSequence.new(Sky.Lightning)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0 = 1.6
	beam.Width1 = 0.6
	beam.Segments = 12
	beam.CurveSize0 = math.random(-14, 14)
	beam.CurveSize1 = math.random(-14, 14)
	beam.Parent = top
	-- The flash is a screen brightness pulse, not a light (light caps).
	local cc = colorCorrection()
	local base = captureBaseline()
	if cc then
		cc.Brightness = base.Brightness + FLASH_BRIGHTNESS
		tween(cc, FLASH_SECONDS, { Brightness = base.Brightness })
	end
	SoundKit.Play("Thunder", bottomPart)
	task.delay(LIGHTNING_SECONDS, function()
		beam.Transparency = NumberSequence.new(0.6)
	end)
	Debris:AddItem(topPart, 6)
	Debris:AddItem(bottomPart, 6)
end

local function dropMeteor(from: Vector3, to: Vector3, seconds: number)
	local rock = Instance.new("Part")
	rock.Name = "Meteor"
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.one * 3
	rock.Material = Enum.Material.SmoothPlastic
	rock.Color = Sky.MeteorRock
	rock.Anchored = true
	rock.CanCollide = false
	rock.CanQuery = false
	rock.CanTouch = false
	rock.CFrame = CFrame.new(from)
	rock.Parent = fxParent("MeteorShower")
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.2, 0)
	a0.Parent = rock
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.2, 0)
	a1.Parent = rock
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Sky.MeteorGlow)
	trail.LightEmission = 1
	trail.Lifetime = 0.6
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Parent = rock
	TweenService:Create(rock, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(to) }):Play()
	task.delay(seconds, function()
		rock:Destroy()
		SoundKit.PlayAt("MeteorImpact", to)
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - to).Magnitude < METEOR_SHAKE_RADIUS then
			RevealEffects.ShakeCamera(0.4, 0.4)
		end
	end)
end

-- "+$X" rising and fading over `position`, parented into the event's folder
-- (so the event's end takes any still on screen).
local function floatPop(parent: Instance, position: Vector3, text: string, color: Color3, textSize: number, seconds: number?)
	local lifetime = seconds or POP_SECONDS
	local anchor = anchorPart(parent, position, "Pop")
	local gui = Instance.new("BillboardGui")
	gui.Name = "Pop"
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(260, textSize + 18)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = POP_MAX_DISTANCE
	gui.Parent = anchor
	local label = UIKit.Label({
		Name = "Text",
		Text = text,
		Font = Fonts.Display,
		TextSize = textSize,
		TextColor3 = color,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = UITheme.Stroke.Text,
		Parent = gui,
	})
	local info = TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = Vector3.new(0, POP_RISE_STUDS, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	end
	Debris:AddItem(anchor, lifetime)
end

-- A flat ring on the floor (a SurfaceGui face, never a Neon disc), no light.
local function floorRing(parent: Instance, position: Vector3, diameter: number, color: Color3, word: string?): BasePart
	local face = BillboardKit.BuildPadFace(parent, CFrame.new(position), diameter, color, word)
	local light = face:FindFirstChild("FaceLight")
	if light then
		light:Destroy()
	end
	return face
end

-- 3 s before a bolt: a cyan ring under the target pedestal and a red
-- "⚡ STRIKE IN 3·2·1" over it, on every client.
local function strikeWarning(pedestal: Instance?, position: Vector3, seconds: number)
	local parent = fxParent("PowerSurge")
	local base = position
	if pedestal and pedestal:IsA("BasePart") then
		base = pedestal.Position - Vector3.new(0, pedestal.Size.Y / 2 - 0.05, 0)
	end
	local ring = floorRing(parent, base, WARNING_RING_DIAMETER, UITheme.Mutation.Charged, nil)
	local anchor = anchorPart(parent, position + Vector3.new(0, 6, 0), "StrikeWarning")
	local chip = BillboardKit.Chip(anchor, {
		Name = "StrikeWarning",
		Text = "⚡ STRIKE IN 3",
		Gradient = UITheme.Gradients.Red,
		Studs = Vector2.new(6.5, 1.5),
		MaxDistance = 150,
	})
	chip.Gui.Adornee = anchor
	task.spawn(function()
		local endsAt = os.clock() + seconds
		while anchor.Parent and os.clock() < endsAt do
			chip.Label.Text = ("⚡ STRIKE IN %d"):format(math.max(1, math.ceil(endsAt - os.clock())))
			task.wait(0.1)
		end
		anchor:Destroy()
		ring:Destroy()
	end)
end

-- 2 s before a meteor lands: a red "☄ INCOMING" ring where it will hit.
local function incomingRing(at: Vector3, seconds: number)
	local parent = fxParent("MeteorShower")
	local ring = floorRing(parent, at + Vector3.new(0, 0.06, 0), INCOMING_RING_DIAMETER, Colors.Danger, nil)
	local anchor = anchorPart(parent, at + Vector3.new(0, 4, 0), "Incoming")
	local chip = BillboardKit.Chip(anchor, {
		Name = "Incoming",
		Text = "☄ INCOMING",
		Gradient = UITheme.Gradients.Red,
		Studs = Vector2.new(5.5, 1.4),
		MaxDistance = 200,
	})
	chip.Gui.Adornee = anchor
	Debris:AddItem(ring, seconds)
	Debris:AddItem(anchor, seconds)
end

local function onEventFx(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Kind == "StrikeWarning" and typeof(payload.Position) == "Vector3" and typeof(payload.Seconds) == "number" then
		local pedestal = if typeof(payload.Pedestal) == "Instance" then payload.Pedestal else nil
		strikeWarning(pedestal, payload.Position, payload.Seconds)
	elseif payload.Kind == "Lightning" and typeof(payload.Position) == "Vector3" then
		strikeLightning(payload.Position)
		local charged = payload.Result == "Charged"
		floatPop(
			fxParent("PowerSurge"),
			payload.Position + Vector3.new(0, 4, 0),
			if charged then "CHARGED!" else "MISSED",
			if charged then UITheme.Mutation.Charged else Colors.Muted,
			if charged then BIG_POP_TEXT_SIZE else POP_TEXT_SIZE,
			RESULT_POP_SECONDS
		)
	elseif
		payload.Kind == "Meteor"
		and typeof(payload.From) == "Vector3"
		and typeof(payload.To) == "Vector3"
		and typeof(payload.Seconds) == "number"
	then
		dropMeteor(payload.From, payload.To, payload.Seconds)
		local warning = math.min(EventConfig.MeteorWarningSeconds, payload.Seconds)
		task.delay(payload.Seconds - warning, incomingRing, payload.To, warning)
	elseif payload.Kind == "Coin" and typeof(payload.Position) == "Vector3" and typeof(payload.Amount) == "number" then
		local big = payload.Big == true
		SoundKit.Play(if big then "BigCoin" else "CoinPickup", nil)
		floatPop(
			fxParent("GoldenRain"),
			payload.Position,
			(if big then "BIG +" else "+") .. NumberFormat.Money(payload.Amount),
			if big then Colors.GoldLabel else Colors.Cash,
			if big then BIG_POP_TEXT_SIZE else POP_TEXT_SIZE
		)
	end
end

local function onEventNotice(payload: any)
	if typeof(payload) == "table" and typeof(payload.Text) == "string" then
		ToastController.Show(payload.Text, "Neutral", { Big = payload.Big == true })
	end
end

local function onEventReward(payload: any)
	if typeof(payload) == "table" and typeof(payload.Caption) == "string" then
		ResultController.ShowItemCard(payload.Caption, payload.Item, nil, payload.NewIndex == true)
	end
end

--[[ HUD chip, schedule card, Event Boards ---------------------------------------------- ]]

local hudGui: ScreenGui
local chip: TextButton
local chipHolder: Frame
local chipIcon: TextLabel
local chipScale: UIScale
local chipGlow: Frame
local pulseTweens: { Tween } = {}

local function stopPulse()
	for _, tween in pulseTweens do
		tween:Cancel()
	end
	table.clear(pulseTweens)
	chipScale.Scale = 1
	chipGlow.Visible = false
end

-- The chip pulses (scale bounce + gold glow) while the running event's type
-- is unseen (Tips "event_<Id>"); one tap stops it for good.
refreshChipPulse = function()
	if not chipScale then
		return
	end
	local running = EventState.GetActive()
	local show = running ~= nil
		and TycoonController.HasSynced()
		and not TycoonController.HasSeenTip("event_" .. running)
	if show and #pulseTweens == 0 then
		local info = TweenInfo.new(PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		chipGlow.Visible = true
		chipGlow.BackgroundTransparency = PULSE_GLOW_TRANSPARENCY.From
		local bounce = TweenService:Create(chipScale, info, { Scale = PULSE_SCALE })
		local glow = TweenService:Create(chipGlow, info, { BackgroundTransparency = PULSE_GLOW_TRANSPARENCY.To })
		bounce:Play()
		glow:Play()
		pulseTweens = { bounce, glow }
	elseif not show and #pulseTweens > 0 then
		stopPulse()
	end
end
local chipStyle: string? = nil
local function eventTitle(id: string): string
	return ("%s %s"):format(EventConfig.Icons[id] or "", EventConfig.Names[id] or id)
end

local function lineupTimer(entry: EventState.LineupEntry): string
	local timer = EventState.FormatTimer(entry.Seconds)
	return if entry.Now then timer .. " left" else "in " .. timer
end

local function lineupTags(lineup: { EventState.LineupEntry }): { string }
	local tags = {}
	local upcoming = 0
	for index, entry in lineup do
		if entry.Now then
			tags[index] = "NOW"
		else
			upcoming += 1
			tags[index] = if upcoming == 1 then "NEXT" else "THEN"
		end
	end
	return tags
end

local function refreshChip(lineup: { EventState.LineupEntry })
	local first = lineup[1]
	local style, text, color
	local subText = ""
	if first and first.Now then
		style = UITheme.EventGradient[first.Id] or "Disabled"
		text = ("%s · %s"):format(eventTitle(first.Id), EventState.FormatTimer(first.Seconds))
		color = Colors.Text
		-- Golden Rain: a running tally of what you've earned this rain.
		local tally = localPlayer:GetAttribute("GoldenRainTally")
		if first.Id == "GoldenRain" and typeof(tally) == "number" and tally > 0 then
			subText = ("💰 +%s this rain"):format(NumberFormat.Money(tally))
		end
	else
		style = "Disabled"
		text = if first then ("NEXT · %s in %s"):format(eventTitle(first.Id), EventState.FormatTimer(first.Seconds)) else ""
		color = Colors.Muted
	end
	UIKit.SetButton(chip, {
		Style = if style ~= chipStyle then style else nil,
		Text = text,
		SubText = subText,
		TextColor3 = color,
	})
	chipIcon.TextColor3 = color
	chipStyle = style
end

local function refreshBoards(lineup: { EventState.LineupEntry })
	local world = Workspace:FindFirstChild("World")
	local boards = world and world:FindFirstChild("EventBoards")
	if not boards then
		return
	end
	local tags = lineupTags(lineup)
	local rows: { BillboardKit.EventBoardRow } = {}
	for index, entry in lineup do
		rows[index] = {
			Tag = tags[index],
			Title = eventTitle(entry.Id),
			Timer = lineupTimer(entry),
			Gradient = if entry.Now then UITheme.GetEventGradient(entry.Id) else UITheme.Gradients.Disabled,
		}
	end
	local adminText = EventState.GetAdminAbuseText()
	for _, descendant in boards:GetDescendants() do
		if descendant:IsA("SurfaceGui") and descendant.Name == "EventBoardSurface" then
			BillboardKit.SetEventBoard(descendant, rows, adminText)
		end
	end
end

local function refreshSchedule()
	local lineup = EventState.GetLineup(LINEUP_COUNT)
	refreshChip(lineup)
	-- The open card follows the chip: it closes when the event it explains
	-- ends, and a "next" card turns into the running one when it starts.
	local shownId, shownNow = EventInfoCard.GetShown()
	local first = lineup[1]
	if shownId and first and (first.Id ~= shownId or first.Now ~= shownNow) then
		if shownNow then
			EventInfoCard.Hide()
		else
			EventInfoCard.Show(hudGui, first.Id, first.Now)
		end
	end
	refreshChipPulse()
	EventInfoCard.Refresh()
	refreshBoards(lineup)
end

-- The running event, else the next one: what the info card explains.
local function cardSubject(): (string?, boolean)
	local first = EventState.GetLineup(1)[1]
	if not first then
		return nil, false
	end
	return first.Id, first.Now
end

local function toggleCard()
	-- Tapping the chip during an event you haven't tapped before marks it
	-- seen (the pulse stops for good).
	local running = EventState.GetActive()
	if running and TycoonController.HasSynced() and not TycoonController.HasSeenTip("event_" .. running) then
		TycoonController.MarkTipSeen("event_" .. running)
		refreshChipPulse()
	end
	if EventInfoCard.IsOpen() then
		EventInfoCard.Hide()
		return
	end
	local id, now = cardSubject()
	if id then
		EventInfoCard.Show(hudGui, id, now)
	end
end

-- A tap anywhere outside the card (and not on the chip, which toggles it)
-- closes it.
local function isInside(gui: GuiObject, position: Vector2): boolean
	local at, size = gui.AbsolutePosition, gui.AbsoluteSize
	return position.X >= at.X and position.X <= at.X + size.X and position.Y >= at.Y and position.Y <= at.Y + size.Y
end

local function onInputBegan(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local card = EventInfoCard.GetFrame()
	if not card or not card.Visible then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	if isInside(card, position) or isInside(chipHolder, position) then
		return
	end
	EventInfoCard.Hide()
end

local function applyLayout(isPhone: boolean)
	local size = if isPhone then CHIP_SIZE.Phone else CHIP_SIZE.Desktop
	chipHolder.Size = UDim2.fromOffset(size.X, size.Y)
	local column = chip:FindFirstChild("Content") and (chip :: any).Content:FindFirstChild("TextColumn")
	local label = column and column:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.TextSize = if isPhone then CHIP_TEXT_SIZE.Phone else CHIP_TEXT_SIZE.Desktop
	end
end

local function buildHud()
	hudGui = UIKit.Screen("EventHud", 41)
	chip, chipHolder = UIKit.Button({
		Name = "EventChip",
		Parent = hudGui,
		Style = "Disabled",
		Text = "",
		TextSize = CHIP_TEXT_SIZE.Desktop,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, CHIP_Y),
		Size = UDim2.fromOffset(CHIP_SIZE.Desktop.X, CHIP_SIZE.Desktop.Y),
		Radius = 22,
		OnClick = toggleCard,
	})
	-- The ⓘ inside the right end (the whole chip is the tap target). The
	-- text column is inset by the same width on both sides so it stays
	-- centred and never runs under the icon.
	local content = chip:FindFirstChild("Content")
	if content then
		UIKit.Padding(content, 0, CHIP_ICON_WIDTH, 0, CHIP_ICON_WIDTH)
	end
	chipIcon = UIKit.Label({
		Name = "InfoIcon",
		Text = "ⓘ",
		Font = Fonts.Display,
		TextSize = 18,
		TextColor3 = Colors.Muted,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, CHIP_ICON_WIDTH - 6, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = chip.ZIndex + 2,
		Stroke = UITheme.Stroke.Text,
		Parent = chip,
	})
	-- The first-time pulse: a UIScale on the holder (body + shadow bounce
	-- together) and a gold glow behind them.
	chipScale = Instance.new("UIScale")
	chipScale.Name = "PulseScale"
	chipScale.Parent = chipHolder
	chipGlow = Instance.new("Frame")
	chipGlow.Name = "PulseGlow"
	chipGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	chipGlow.Position = UDim2.fromScale(0.5, 0.5)
	chipGlow.Size = UDim2.new(1, PULSE_GLOW_SPREAD * 2, 1, PULSE_GLOW_SPREAD * 2)
	chipGlow.BackgroundColor3 = Colors.GoldLabel
	chipGlow.BorderSizePixel = 0
	chipGlow.ZIndex = 0
	chipGlow.Visible = false
	chipGlow.Parent = chipHolder
	UIKit.Corner(chipGlow, 999)
	applyLayout(UIKit.IsPhone())
	UserInputService.InputBegan:Connect(onInputBegan)
	UIKit.LayoutChanged:Connect(applyLayout)
end

--[[ Point the way: event arrows and pad pills -------------------------------------------- ]]

local function myRoot(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function boundsOf(target: Instance): (CFrame?, Vector3?)
	if target:IsA("Model") then
		return target:GetBoundingBox()
	elseif target:IsA("BasePart") then
		return target.CFrame, target.Size
	end
	return nil, nil
end

-- The nearest child of the event's folder (or its `sub` folder) that
-- `pick` accepts, as the part to point at.
local function nearestIn(id: string, sub: string?, pick: (Instance) -> BasePart?): BasePart?
	local folder = EventState.GetObjectsFolder(id)
	local container = if folder and sub then folder:FindFirstChild(sub) else folder
	local root = myRoot()
	if not container or not root then
		return nil
	end
	local best: BasePart? = nil
	local bestDistance = math.huge
	for _, child in container:GetChildren() do
		local part = pick(child)
		if part then
			local distance = flatDistance(part.Position, root.Position)
			if distance < bestDistance then
				best, bestDistance = part, distance
			end
		end
	end
	return best
end

-- An unclaimed crater's core (its prompt is still on).
local function craterCore(child: Instance): BasePart?
	if not child:IsA("Model") then
		return nil
	end
	local core = child:FindFirstChild("Core")
	local prompt = core and core:FindFirstChild("MeteorPrompt")
	if core and core:IsA("BasePart") and prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
		return core
	end
	return nil
end

-- A street coin (Golden Rain, EventObjects.GoldenRain.Street).
local function streetCoin(child: Instance): BasePart?
	return if child:IsA("BasePart") and child:GetAttribute("Collected") ~= true then child else nil
end

-- A pill over one of your own stations, in the event's folder (so the
-- event's end removes it).
local function ensureStationPill(id: string, station: Instance, text: string)
	local folder = EventState.GetObjectsFolder(id)
	if not folder or folder:FindFirstChild("StationPill_" .. station.Name) then
		return
	end
	local center, size = boundsOf(station)
	if not center or not size then
		return
	end
	local anchor = anchorPart(folder, center.Position + Vector3.new(0, size.Y / 2 + 3, 0), "StationPill_" .. station.Name)
	local gui = Instance.new("BillboardGui")
	gui.Name = "EventPill"
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(320, 40)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = EVENT_PILL_MAX_DISTANCE
	gui.Parent = anchor
	UIKit.Pill({
		Name = "Text",
		Parent = gui,
		Text = text,
		Gradient = UITheme.GetEventGradient(id),
		Font = Fonts.Display,
		TextSize = 18,
		Height = 34,
		TextStroke = 1.5,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
end

-- Power Surge: "⚡ ×1.25" over every running generator in every lab
-- (client, in the event's folder; rescanned for new labs and upgrades).
local surgeScan = 0
local function refreshSurgeChips()
	if os.clock() - surgeScan < SURGE_CHIP_RESCAN_SECONDS then
		return
	end
	surgeScan = os.clock()
	local folder = EventState.GetObjectsFolder("PowerSurge")
	local plots = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	if not folder or not plots then
		return
	end
	local text = "⚡ " .. NumberFormat.Multiplier(EventState.GetGeneratorMultiplier())
	for _, plot in plots:GetChildren() do
		for _, model in plot:GetChildren() do
			local level = model:GetAttribute("Level")
			local body = model:FindFirstChild("Body")
			local name = "SurgeChip_" .. plot.Name .. "_" .. model.Name
			if
				model.Name:sub(1, #GeneratorKit.MODEL_PREFIX) == GeneratorKit.MODEL_PREFIX
				and typeof(level) == "number"
				and level >= 1
				and body
				and body:IsA("BasePart")
				and not folder:FindFirstChild(name)
			then
				local anchor = anchorPart(folder, body.Position + Vector3.new(0, body.Size.Y / 2 + 2.6, 0), name)
				local chip = BillboardKit.Chip(anchor, {
					Name = "SurgeChip",
					Text = text,
					Gradient = UITheme.Gradients.Surge,
					Studs = Vector2.new(3.6, 1.2),
					MaxDistance = SURGE_CHIP_MAX_DISTANCE,
				})
				chip.Gui.Adornee = anchor
			end
		end
	end
end

refreshGuidance = function()
	local id, strength = EventState.GetActive()
	if id == "PowerSurge" then
		refreshSurgeChips()
	else
		surgeScan = 0
	end
	local target: Instance? = nil
	local text = ""
	local root = myRoot()
	if id == "RainbowStorm" then
		local pad = GoalMarkerController.ResolvePlotTarget("GachaStation")
		local machine = GoalMarkerController.ResolvePlotTarget("FusionMachine")
		if pad then
			local odds = EventConfig.GetMutationOddsMultiplier(id, strength, "Diamond", "Pull")
			ensureStationPill(id, pad, ("🌈 MUTATIONS ×%d · PULL NOW"):format(odds))
		end
		local padCenter = if pad then boundsOf(pad) else nil
		local onPad = padCenter ~= nil and root ~= nil and flatDistance(padCenter.Position, root.Position) <= ON_PAD_RADIUS
		if onPad and machine then
			target, text = machine, "THEN FUSE"
		else
			target, text = pad, "PULL HERE"
		end
	elseif id == "Night" or id == "VoidMoon" then
		local machine = GoalMarkerController.ResolvePlotTarget("FusionMachine")
		if machine then
			ensureStationPill(id, machine, "🌙 FUSE NOW")
		end
		target, text = machine, "FUSE NOW"
	elseif id == "MeteorShower" then
		target, text = nearestIn(id, nil, craterCore), "GRAB THE CORE"
	elseif id == "GoldenRain" then
		target, text = nearestIn(id, "Street", streetCoin), "GRAB THE COIN"
	end
	GoalMarkerController.SetEventOverride(target, text)
end

--[[ Public ------------------------------------------------------------------------------ ]]

--[[ Local preview (/trailer) ----------------------------------------------------------- ]]

-- Lighting exactly at the captured baseline.
local function snapBaseline()
	local base = captureBaseline()
	local cc = colorCorrection()
	local atm = atmosphere()
	Lighting.ClockTime = base.ClockTime
	if cc then
		cc.TintColor = base.Tint
		cc.Brightness = base.Brightness
	end
	if atm and base.Density and base.AtmosphereColor then
		atm.Density = base.Density
		atm.Color = base.AtmosphereColor
	end
end

export type PreviewOptions = { MoonDirection: Vector3? }

-- Shows event `id`'s sky and FX on THIS client only, at once (no banner,
-- no workspace attributes, nothing on the server). Live event changes wait
-- until StopPreview. `MoonDirection` (world) moves the Void Moon. "None"
-- holds the plain baseline sky (no event look, live or previewed).
function EventController.PreviewLocal(id: string, options: PreviewOptions?)
	captureBaseline()
	previewId = id
	generation += 1
	local myGeneration = generation
	if fxFolder then
		fxFolder:Destroy()
		fxFolder = nil
	end
	snapBaseline()
	moonDirection = if options and options.MoonDirection then options.MoonDirection.Unit else MOON_DIRECTION
	if id == "None" then
		return
	end
	instantSky = true
	local ok, err = pcall(function()
		applySky(id, myGeneration)
	end)
	instantSky = false
	if not ok then
		warn("EventController.PreviewLocal: " .. tostring(err))
	end
end

-- Ends a preview: FX gone, Lighting exactly back at the baseline, then
-- whatever event is live now comes back as usual.
function EventController.StopPreview()
	if not previewId then
		return
	end
	previewId = nil
	generation += 1
	if fxFolder then
		fxFolder:Destroy()
		fxFolder = nil
	end
	moonDirection = MOON_DIRECTION
	snapBaseline()
	currentId = nil
	onEventChanged(false)
end

-- The top-centre HUD chip (the tutorial's coach ring points at it).
function EventController.GetChip(): GuiObject?
	return chipHolder
end

function EventController.IsPreviewing(): boolean
	return previewId ~= nil
end

function EventController.Init()
	screenGui = UIKit.Screen("EventBanner", 105)
	-- Baseline before any event could change it: LightingService runs on the
	-- server at boot, so it has replicated by the time this script runs.
	captureBaseline()
	onEventChanged(false)
	for _, attribute in { "EventId", "EventStrength" } do
		-- Deferred: the attributes of one change arrive together.
		Workspace:GetAttributeChangedSignal(attribute):Connect(function()
			task.defer(onEventChanged, true)
		end)
	end
	buildHud()
	refreshSchedule()
	-- An event's end time passing (between ticks) is also a change; the
	-- chip, card and boards tick with it.
	task.spawn(function()
		while true do
			task.wait(1)
			onEventChanged(true)
			refreshSchedule()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(GUIDE_SECONDS)
			refreshGuidance()
		end
	end)
	RemoteEvents.EventFx.OnClientEvent:Connect(onEventFx)
	RemoteEvents.EventNotice.OnClientEvent:Connect(onEventNotice)
	RemoteEvents.EventReward.OnClientEvent:Connect(onEventReward)
end

return EventController
