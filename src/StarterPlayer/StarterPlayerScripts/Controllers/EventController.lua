--!strict
--[[
	EventController
	---------------
	Every event visual, client-side, from the workspace attributes
	EventService publishes (read through EventState) plus its EventFx cues.
	Rewards are all server-side; nothing here pays.

	On a live start (the attribute flips while you're in the game):
	  * a start banner: 3-2-1 countdown, then the icon, name and blurb on the
	    event's gradient, with a sound. Rainbow Storm also gets the big
	    SERVER · EVENT banner (AnnouncementController).
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
	3:12"), else a muted "NEXT · ☄ METEOR SHOWER in 8:40". Tapping it opens
	the schedule card (NOW / NEXT / THEN and the Admin Abuse line). The two
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

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local GeneratorKit = require(ReplicatedStorage.Shared.Modules.GeneratorKit)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local RevealEffects = require(script.Parent.Parent.Effects.RevealEffects)
local AnnouncementController = require(script.Parent.AnnouncementController)
local ResultController = require(script.Parent.ResultController)
local ToastController = require(script.Parent.ToastController)

local EventController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts
local Sky = UITheme.EventSky

local localPlayer = Players.LocalPlayer

-- The one sound id proven to load in this project (see RevealEffects);
-- thunder is the same ping slowed right down.
local SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
local THUNDER_SPEED = 0.25

local SKY_TWEEN_SECONDS = 3
local NIGHT_TWEEN_SECONDS = 6
local NIGHT_CLOCK = 23.99 -- tweened forward through dusk; midnight
local STORM_DENSITY_ADD = 0.12
local GOLD_TINT_ALPHA = 1
local RAINBOW_TINT_TOWARD_WHITE = 0.78
local RAINBOW_CYCLE_SECONDS = 12

local BANNER_SIZE = Vector2.new(460, 120)
local BANNER_Y = 96 -- under the top bar and the goal tracker's row
local COUNTDOWN_STEP = 0.6
local BANNER_HOLD_SECONDS = 4

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
local POP_SECONDS = 1.2
local POP_RISE_STUDS = 4
local POP_MAX_DISTANCE = 150

local CHIP_Y = 12
local CHIP_SIZE = { Desktop = Vector2.new(330, 44), Phone = Vector2.new(270, 44) }
local CHIP_TEXT_SIZE = { Desktop = 18, Phone = 15 }
local CARD_GAP = 10
local CARD_WIDTH = 330
local CARD_ROW_HEIGHT = 40
local LINEUP_COUNT = 3

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
	TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal):Play()
end

local function playSound(parent: Instance, speed: number?, volume: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = SOUND_ID
	sound.PlaybackSpeed = speed or 1
	sound.Volume = volume or 0.8
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 6)
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
	folder.Parent = fxParent(id)
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
				anchor.CFrame = CFrame.new(camera.CFrame.Position + MOON_DIRECTION * MOON_DISTANCE)
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

-- 3-2-1 in a big numeral, then the icon + name + blurb, on the event's
-- gradient. A newer event's banner replaces it.
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
	local numeral = UIKit.Label({
		Name = "Countdown",
		Text = "3",
		Font = Fonts.Display,
		TextSize = 72,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 4,
		Parent = body,
	})
	UIKit.PopIn(holder)
	task.spawn(function()
		for count = 3, 1, -1 do
			if bannerHolder ~= holder or generation ~= myGeneration then
				return
			end
			numeral.Text = tostring(count)
			playSound(screenGui, 0.8 + (3 - count) * 0.1, 0.5)
			task.wait(COUNTDOWN_STEP)
		end
		if bannerHolder ~= holder or generation ~= myGeneration then
			return
		end
		numeral:Destroy()
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
		playSound(screenGui, 1.2, 1)
		UIKit.PopIn(holder)
		task.wait(BANNER_HOLD_SECONDS)
		if bannerHolder == holder then
			closeBanner()
		end
	end)
end

--[[ Event changes -------------------------------------------------------------------- ]]

local function onEventChanged(live: boolean)
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
			ToastController.Show(("%s %s is over"):format(EventConfig.Icons[old] or "", EventConfig.Names[old] or old), "Neutral")
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
			AnnouncementController.ShowEventHype("🌈 RAINBOW STORM! Every mutation chance x5")
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
	playSound(bottom, THUNDER_SPEED, 1)
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
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - to).Magnitude < METEOR_SHAKE_RADIUS then
			RevealEffects.ShakeCamera(0.4, 0.4)
		end
	end)
end

-- "+$X" rising and fading over `position`, parented into the event's folder
-- (so the event's end takes any still on screen).
local function floatPop(parent: Instance, position: Vector3, text: string, color: Color3, textSize: number)
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
	local info = TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffsetWorldSpace = Vector3.new(0, POP_RISE_STUDS, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	end
	Debris:AddItem(anchor, POP_SECONDS)
end

local function onEventFx(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Kind == "Lightning" and typeof(payload.Position) == "Vector3" then
		strikeLightning(payload.Position)
	elseif
		payload.Kind == "Meteor"
		and typeof(payload.From) == "Vector3"
		and typeof(payload.To) == "Vector3"
		and typeof(payload.Seconds) == "number"
	then
		dropMeteor(payload.From, payload.To, payload.Seconds)
	elseif payload.Kind == "Coin" and typeof(payload.Position) == "Vector3" and typeof(payload.Amount) == "number" then
		floatPop(fxParent("GoldenRain"), payload.Position, "+" .. NumberFormat.Money(payload.Amount), Colors.Cash, POP_TEXT_SIZE)
	end
end

local function onEventNotice(payload: any)
	if typeof(payload) == "table" and typeof(payload.Text) == "string" then
		ToastController.Show(payload.Text, "Neutral", { Big = payload.Big == true })
	end
end

local function onEventReward(payload: any)
	if typeof(payload) == "table" and typeof(payload.Caption) == "string" then
		ResultController.ShowItemCard(payload.Caption, payload.Item)
	end
end

--[[ HUD chip, schedule card, Event Boards ---------------------------------------------- ]]

local hudGui: ScreenGui
local chip: TextButton
local chipHolder: Frame
local chipStyle: string? = nil
local cardHolder: Frame
local cardRows: { { Tag: TextLabel, Name: TextLabel, Timer: TextLabel } } = {}
local cardAdminLabel: TextLabel

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
	if first and first.Now then
		style = UITheme.EventGradient[first.Id] or "Disabled"
		text = ("%s · %s"):format(eventTitle(first.Id), EventState.FormatTimer(first.Seconds))
		color = Colors.Text
	else
		style = "Disabled"
		text = if first then ("NEXT · %s in %s"):format(eventTitle(first.Id), EventState.FormatTimer(first.Seconds)) else ""
		color = Colors.Muted
	end
	UIKit.SetButton(chip, { Style = if style ~= chipStyle then style else nil, Text = text, TextColor3 = color })
	chipStyle = style
end

local function refreshCard(lineup: { EventState.LineupEntry })
	local tags = lineupTags(lineup)
	for index, row in cardRows do
		local entry = lineup[index]
		row.Tag.Text = tags[index] or ""
		row.Name.Text = if entry then eventTitle(entry.Id) else ""
		row.Name.TextColor3 = if entry then UITheme.GetEventGradient(entry.Id).Top else Colors.Text
		row.Timer.Text = if entry then lineupTimer(entry) else ""
	end
	cardAdminLabel.Text = EventState.GetAdminAbuseText()
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
	if cardHolder.Visible then
		refreshCard(lineup)
	end
	refreshBoards(lineup)
end

local function buildCard()
	local height = 44 + LINEUP_COUNT * CARD_ROW_HEIGHT + 34
	local body, holder = UIKit.Panel({
		Name = "ScheduleCard",
		Parent = hudGui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, CHIP_Y + CHIP_SIZE.Desktop.Y + CARD_GAP),
		Size = UDim2.fromOffset(CARD_WIDTH, height),
		Radius = 18,
	})
	cardHolder = holder
	holder.Visible = false
	local z = body.ZIndex + 1
	UIKit.Label({
		Name = "Title",
		Text = "LAB WEATHER",
		Font = Fonts.Display,
		TextSize = 20,
		TextColor3 = Colors.VioletLight,
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 26),
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	for index = 1, LINEUP_COUNT do
		local y = 44 + (index - 1) * CARD_ROW_HEIGHT
		local function cell(name: string, x: number, width: number, font: Font, size: number, align: Enum.TextXAlignment): TextLabel
			return UIKit.Label({
				Name = name .. index,
				Text = "",
				Font = font,
				TextSize = size,
				Position = UDim2.new(x, if x == 0 then 16 else 0, 0, y),
				Size = UDim2.new(width, -16, 0, CARD_ROW_HEIGHT - 6),
				TextXAlignment = align,
				ZIndex = z,
				Stroke = UITheme.Stroke.Text,
				Parent = body,
			})
		end
		local tag = cell("Tag", 0, 0.2, Fonts.BodyHeavy, 13, Enum.TextXAlignment.Left)
		tag.TextColor3 = Colors.Muted
		table.insert(cardRows, {
			Tag = tag,
			Name = cell("Name", 0.2, 0.5, Fonts.Display, 17, Enum.TextXAlignment.Left),
			Timer = cell("Timer", 0.7, 0.3, Fonts.Display, 16, Enum.TextXAlignment.Right),
		})
	end
	cardAdminLabel = UIKit.Label({
		Name = "AdminAbuse",
		Text = "",
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.GoldLabel,
		Position = UDim2.new(0, 16, 1, -32),
		Size = UDim2.new(1, -32, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = body,
	})
end

local function toggleCard()
	cardHolder.Visible = not cardHolder.Visible
	if cardHolder.Visible then
		refreshCard(EventState.GetLineup(LINEUP_COUNT))
		UIKit.PopIn(cardHolder)
	end
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
	buildCard()
	applyLayout(UIKit.IsPhone())
	UIKit.LayoutChanged:Connect(applyLayout)
end

--[[ Public ------------------------------------------------------------------------------ ]]

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
	RemoteEvents.EventFx.OnClientEvent:Connect(onEventFx)
	RemoteEvents.EventNotice.OnClientEvent:Connect(onEventNotice)
	RemoteEvents.EventReward.OnClientEvent:Connect(onEventReward)
end

return EventController
