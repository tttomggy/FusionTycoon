--!strict
--[[
	TrailerController
	-----------------
	The /trailer cinematic: the same ~30 s every time, recorded by Harris
	(Win+Alt+R, real Roblox player, full screen 1080p) and edited into the
	game's video thumbnail. AdminService sends TrailerStart { Shot?, Stop? }
	to admins only.

	CLIENT-ONLY. Nothing here touches the server: no cash, items, events,
	saves, analytics or banners for anyone else. Every orb, NPC, card and
	sky is built on this client and removed at the end, which is what makes
	it safe in a live server. Real game visuals only (the Roblox video
	thumbnail policy): the real orbs (PedestalVisuals), the real fusion and
	pull VFX (RevealEffects, the pad's burst), the real cards
	(ResultController) and banner (AnnouncementController), the real event
	skies (EventController.PreviewLocal). No extra post effects, no claims.

	  Clean frame  every PlayerGui gui and the CoreGui hidden (the cards a
	               shot needs come back for that shot), proximity prompts
	               off, every character hidden (LocalTransparencyModifier),
	               the camera Scriptable. All of it restored exactly on end,
	               /trailer stop, F8, or your character dying / resetting.
	  Camera       TrailerConfig keyframes (plot-local), evaluated every
	               frame with TweenService:GetValue; arcs round a point;
	               targets ("Thief", "Owner", "Core", "Moon") tracked live.
	  Cuts         a 0.25 s fade to black and back (own ScreenGui, top
	               DisplayOrder); "3 2 1" on black before the first shot.

	Shots (TrailerConfig.Shots): night · pull · fuse · heist · voidmoon ·
	hold. /trailer <id> plays one (retakes).
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local TrailerConfig = require(ReplicatedStorage.Shared.Config.TrailerConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)
local ImportedEffects = require(ReplicatedStorage.Shared.VFX.ImportedEffects)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local RevealEffects = require(script.Parent.Parent.Effects.RevealEffects)
local EventController = require(script.Parent.EventController)
local ResultController = require(script.Parent.ResultController)
local AnnouncementController = require(script.Parent.AnnouncementController)
local ToastController = require(script.Parent.ToastController)

local TrailerController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts
local Look = UITheme.Trailer

local localPlayer = Players.LocalPlayer

local RENDER_STEP_NAME = "FT_Trailer"
local FADE_DISPLAY_ORDER = 2147483647
local CARD_GUIS = { Results = true, Announcements = true } -- shown only in the shots that need them
local MOON_LOOK_DISTANCE = 100
local CARRY_ORB_ABOVE_HEAD = 2
local PULL_BURST_COUNT = 30 -- TycoonService's pad burst
local PULL_EXPLOSION = { Scale = 0.5, BurstSeconds = 0.25 } -- TycoonService's gacha explosion
local OTHERS_REFRESH_SECONDS = 0.5
local RIG_WAIT_SECONDS = 4

local explosionTemplate = ReplicatedStorage.Shared.VFX:FindFirstChild("ExplosionEffect") :: BasePart?

type Actor = {
	Model: Model,
	Root: BasePart,
	RootHeight: number,
	Run: AnimationTrack?,
	Idle: AnimationTrack?,
	Moving: boolean?,
}

type ShotRun = {
	Update: (t: number) -> (),
	Cleanup: () -> (),
}

type Item = { ItemId: string, Tier: string, Mutation: string?, Uid: string }

local running = false
local runToken = 0
local plot: Model? = nil
local origin = CFrame.new()
local localFolder: Folder? = nil -- every world object the trailer builds
local restoreSteps: { () -> () } = {}
local hiddenGuis: { [LayerCollector]: boolean } = {}
local fadeGui: ScreenGui? = nil
local fadeFrame: Frame? = nil
local countLabel: TextLabel? = nil
local currentShot: TrailerConfig.Shot? = nil
local currentRun: ShotRun? = nil
local shotStart = 0
local targets: { [string]: (() -> Vector3?)? } = {}
local moonDirection = Vector3.new(0, 1, 0)
local stopConnections: { RBXScriptConnection } = {}
local templates: { [string]: Model } = {}
local templatesRequested = false

--[[ Helpers ----------------------------------------------------------------------- ]]

local function world(localPos: Vector3): Vector3
	return origin:PointToWorldSpace(localPos)
end

local function toLocal(worldPos: Vector3): Vector3
	return origin:PointToObjectSpace(worldPos)
end

local function alive(token: number): boolean
	return running and runToken == token
end

-- Waits `seconds`, false if the run was stopped meanwhile.
local function sleep(token: number, seconds: number): boolean
	local started = os.clock()
	while os.clock() - started < seconds do
		if not alive(token) then
			return false
		end
		RunService.Heartbeat:Wait()
	end
	return alive(token)
end

local function onRestore(step: () -> ())
	table.insert(restoreSteps, step)
end

-- The first item of `tier` in ItemConfig, as a local display item.
local function itemFor(look: TrailerConfig.ItemLook, uid: string): Item
	local defs = ItemConfig.GetItemsByTier(look.Tier)
	return {
		ItemId = if defs[1] then defs[1].Id else look.Tier,
		Tier = look.Tier,
		Mutation = look.Mutation,
		Uid = "trailer_" .. uid,
	}
end

local function smooth(u: number): number
	return TweenService:GetValue(math.clamp(u, 0, 1), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
end

local function phase(t: number, a: number, b: number): number
	return if b > a then math.clamp((t - a) / (b - a), 0, 1) else (if t >= b then 1 else 0)
end

-- A point along a polyline (plot-local) at u in [0, 1], by length.
local function alongPath(path: { Vector3 }, u: number): (Vector3, Vector3)
	local total = 0
	for index = 2, #path do
		total += (path[index] - path[index - 1]).Magnitude
	end
	local want = total * math.clamp(u, 0, 1)
	for index = 2, #path do
		local a, b = path[index - 1], path[index]
		local length = (b - a).Magnitude
		if want <= length or index == #path then
			local s = if length > 0 then math.clamp(want / length, 0, 1) else 1
			return a:Lerp(b, s), b - a
		end
		want -= length
	end
	return path[#path], Vector3.new(0, 0, 1)
end

-- Fires `callback` once, the first frame t reaches `at`.
local function beats(): (t: number, at: number, callback: () -> ()) -> ()
	local fired: { [number]: boolean } = {}
	return function(t: number, at: number, callback: () -> ())
		if t >= at and not fired[at] then
			fired[at] = true
			task.spawn(callback)
		end
	end
end

--[[ Clean frame -------------------------------------------------------------------- ]]

local function setCardGuis(on: boolean)
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for name in CARD_GUIS do
		local gui = playerGui:FindFirstChild(name)
		if gui and gui:IsA("LayerCollector") and hiddenGuis[gui] then
			gui.Enabled = on
		end
	end
end

local function enterCleanFrame()
	-- Every enabled gui in PlayerGui (ScreenGuis and the goal marker's
	-- BillboardGui alike), except the trailer's own fade.
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, child in playerGui:GetChildren() do
			if child:IsA("LayerCollector") and child.Enabled and child ~= fadeGui then
				child.Enabled = false
				hiddenGuis[child] = true
			end
		end
	end
	onRestore(function()
		for gui in hiddenGuis do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		table.clear(hiddenGuis)
	end)

	-- CoreGui (player list, chat, backpack, ...), each type as it was.
	local coreStates: { [Enum.CoreGuiType]: boolean } = {}
	for _, coreType in Enum.CoreGuiType:GetEnumItems() do
		if coreType ~= Enum.CoreGuiType.All then
			coreStates[coreType] = StarterGui:GetCoreGuiEnabled(coreType)
		end
	end
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	onRestore(function()
		for coreType, enabled in coreStates do
			pcall(function()
				StarterGui:SetCoreGuiEnabled(coreType, enabled)
			end)
		end
	end)

	-- No mouse cursor in the recording.
	local mouseIconWas = UserInputService.MouseIconEnabled
	UserInputService.MouseIconEnabled = false
	onRestore(function()
		UserInputService.MouseIconEnabled = mouseIconWas
	end)

	local promptsWere = ProximityPromptService.Enabled
	ProximityPromptService.Enabled = false
	onRestore(function()
		ProximityPromptService.Enabled = promptsWere
	end)

	local camera = Workspace.CurrentCamera
	if camera then
		local cameraType = camera.CameraType
		local subject = camera.CameraSubject
		local fov = camera.FieldOfView
		local cframe = camera.CFrame
		camera.CameraType = Enum.CameraType.Scriptable
		onRestore(function()
			camera.FieldOfView = fov
			camera.CFrame = cframe
			camera.CameraSubject = subject
			camera.CameraType = cameraType
		end)
	end

	-- Other players' overhead names and tags (their parts are hidden every
	-- frame in the render step).
	local hiddenTags: { [Instance]: boolean } = {}
	local namesWere: { [Humanoid]: Enum.HumanoidDisplayDistanceType } = {}
	local function hideTags()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character and player ~= localPlayer then
				for _, descendant in character:GetDescendants() do
					if descendant:IsA("BillboardGui") and descendant.Enabled then
						descendant.Enabled = false
						hiddenTags[descendant] = true
					elseif descendant:IsA("Humanoid") and namesWere[descendant] == nil then
						namesWere[descendant] = descendant.DisplayDistanceType
						descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					end
				end
			end
		end
	end
	hideTags()
	local token = runToken
	task.spawn(function()
		while alive(token) do
			task.wait(OTHERS_REFRESH_SECONDS)
			if alive(token) then
				hideTags()
			end
		end
	end)
	onRestore(function()
		for tag in hiddenTags do
			if tag.Parent and tag:IsA("BillboardGui") then
				tag.Enabled = true
			end
		end
		for humanoid, was in namesWere do
			if humanoid.Parent then
				humanoid.DisplayDistanceType = was
			end
		end
	end)
end

-- Every character (yours and everyone else's) invisible on this client.
local function hideCharacters(hidden: boolean)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			for _, descendant in character:GetDescendants() do
				if descendant:IsA("BasePart") or descendant:IsA("Decal") then
					descendant.LocalTransparencyModifier = if hidden then 1 else 0
				end
			end
		end
	end
end

--[[ Fade + countdown ---------------------------------------------------------------- ]]

local function buildFade()
	local gui = UIKit.Screen("TrailerFade", FADE_DISPLAY_ORDER)
	local frame = Instance.new("Frame")
	frame.Name = "Black"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Colors.Black
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.ZIndex = 10
	frame.Parent = gui
	local label = UIKit.Label({
		Name = "Count",
		Font = Fonts.Display,
		TextSize = 120,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, 160),
		ZIndex = 11,
		Stroke = 4,
		Parent = frame,
	})
	fadeGui = gui
	fadeFrame = frame
	countLabel = label
end

local function fadeTo(token: number, transparency: number): boolean
	local frame = fadeFrame
	if not frame then
		return false
	end
	TweenService:Create(
		frame,
		TweenInfo.new(TrailerConfig.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ BackgroundTransparency = transparency }
	):Play()
	return sleep(token, TrailerConfig.FadeSeconds)
end

-- "3 2 1" on black, then nothing (the video starts on black).
local function countdown(token: number): boolean
	local label = countLabel
	local seconds = math.max(1, math.floor(TrailerConfig.CountdownSeconds))
	for n = seconds, 1, -1 do
		if label then
			label.Text = tostring(n)
		end
		SoundKit.Play("Toast", nil)
		if not sleep(token, 1) then
			return false
		end
	end
	if label then
		label.Text = ""
	end
	return sleep(token, TrailerConfig.BlackHoldSeconds)
end

--[[ Camera ------------------------------------------------------------------------- ]]

local function targetPosition(name: string): Vector3?
	local getter = targets[name]
	return if getter then getter() else nil
end

local function keyPos(kf: TrailerConfig.Keyframe): Vector3
	local follow = kf.Follow
	local followed = if follow then targetPosition(follow) else nil
	if followed then
		local floor = Vector3.new(followed.X, origin.Position.Y, followed.Z)
		return floor + origin:VectorToWorldSpace(kf.Pos)
	end
	return world(kf.Pos)
end

local function keyLook(kf: TrailerConfig.Keyframe, cameraPos: Vector3): Vector3
	local lookAt = kf.LookAt
	if typeof(lookAt) == "Vector3" then
		return world(lookAt)
	end
	local name = lookAt :: string
	if name == "Moon" then
		return cameraPos + moonDirection * MOON_LOOK_DISTANCE
	end
	return targetPosition(name) or world(Vector3.new(0, 5, 0))
end

-- The camera CFrame and FOV of `shot` at time t.
local function evaluateCamera(shot: TrailerConfig.Shot, t: number): (CFrame, number)
	local frames = shot.Camera
	local first = frames[1]
	if #frames == 1 or t <= first.T then
		local pos = keyPos(first)
		return CFrame.lookAt(pos, keyLook(first, pos)), first.Fov
	end
	local a, b = frames[#frames - 1], frames[#frames]
	for index = 2, #frames do
		if t <= frames[index].T then
			a, b = frames[index - 1], frames[index]
			break
		end
	end
	local style = Enum.EasingStyle.Sine
	local easing = b.Easing
	if easing then
		pcall(function()
			style = (Enum.EasingStyle :: any)[easing]
		end)
	end
	local u = TweenService:GetValue(phase(t, a.T, b.T), style, Enum.EasingDirection.InOut)
	local fromPos, toPos = keyPos(a), keyPos(b)
	local pos: Vector3
	local around = b.ArcAround
	if around then
		-- Swing round the point: angle, radius and height interpolated.
		local la, lb = toLocal(fromPos), toLocal(toPos)
		local angleA = math.atan2(la.Z - around.Z, la.X - around.X)
		local angleB = math.atan2(lb.Z - around.Z, lb.X - around.X)
		local delta = (angleB - angleA + math.pi) % (2 * math.pi) - math.pi
		local radiusA = Vector2.new(la.X - around.X, la.Z - around.Z).Magnitude
		local radiusB = Vector2.new(lb.X - around.X, lb.Z - around.Z).Magnitude
		local angle = angleA + delta * u
		local radius = radiusA + (radiusB - radiusA) * u
		local height = la.Y + (lb.Y - la.Y) * u
		pos = world(Vector3.new(around.X + math.cos(angle) * radius, height, around.Z + math.sin(angle) * radius))
	else
		pos = fromPos:Lerp(toPos, u)
	end
	local look = keyLook(a, pos):Lerp(keyLook(b, pos), u)
	return CFrame.lookAt(pos, look), a.Fov + (b.Fov - a.Fov) * u
end

local function renderStep()
	hideCharacters(true)
	local shot = currentShot
	local camera = Workspace.CurrentCamera
	if not shot or not camera then
		return
	end
	local t = os.clock() - shotStart
	local shotRun = currentRun
	if shotRun then
		local update = shotRun.Update
		local ok, err = pcall(function()
			update(t)
		end)
		if not ok then
			warn("TrailerController: " .. tostring(err))
		end
	end
	local cframe, fov = evaluateCamera(shot, t)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cframe
	camera.FieldOfView = fov
end

--[[ Actors (local NPC rigs) ------------------------------------------------------------ ]]

local function readAnimationIds(): (string?, string?)
	local character = localPlayer.Character
	local animate = character and character:FindFirstChild("Animate")
	local function first(name: string): string?
		local value = animate and animate:FindFirstChild(name)
		local animation = value and value:FindFirstChildOfClass("Animation")
		return if animation and animation.AnimationId ~= "" then animation.AnimationId else nil
	end
	return first("run"), first("idle")
end

local function loadTrack(humanoid: Humanoid, id: string?): AnimationTrack?
	if not id then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	return if ok then track else nil
end

local function describe(colors: { [string]: Color3 }): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = colors.Head
	description.TorsoColor = colors.Torso
	description.LeftArmColor = colors.Arms
	description.RightArmColor = colors.Arms
	description.LeftLegColor = colors.Legs
	description.RightLegColor = colors.Legs
	return description
end

local RIG_LOOKS: { [string]: { [string]: Color3 } } = {
	Thief = { Head = Look.ThiefMask, Torso = Look.ThiefBody, Arms = Look.ThiefBody, Legs = Look.ThiefBody },
	Owner = { Head = Look.OwnerHead, Torso = Look.OwnerTorso, Arms = Look.OwnerArms, Legs = Look.OwnerLegs },
}

-- Blocky R15 rigs from a HumanoidDescription, built once (they yield).
local function requestTemplates()
	if templatesRequested then
		return
	end
	templatesRequested = true
	for name, colors in RIG_LOOKS do
		task.spawn(function()
			local ok, rig = pcall(function()
				return Players:CreateHumanoidModelFromDescription(describe(colors), Enum.HumanoidRigType.R15)
			end)
			if ok and rig then
				rig.Archivable = true
				templates[name] = rig
			end
		end)
	end
end

-- A puppet copy of your own character (no scripts, tags or sounds).
local function cloneYou(): Model?
	local character = localPlayer.Character
	if not character then
		return nil
	end
	local was = character.Archivable
	character.Archivable = true
	local ok, clone = pcall(function()
		return character:Clone()
	end)
	character.Archivable = was
	return if ok then clone else nil
end

-- Your clone recoloured, if the HumanoidDescription rig never came.
local function recolour(model: Model, colors: { [string]: Color3 })
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Accessory") or descendant:IsA("Clothing") or descendant:IsA("ShirtGraphic") or descendant:IsA("BodyColors") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			local name = descendant.Name
			if name == "Head" then
				descendant.Color = colors.Head
			elseif name:find("Torso") then
				descendant.Color = colors.Torso
			elseif name:find("Arm") or name:find("Hand") then
				descendant.Color = colors.Arms
			elseif name:find("Leg") or name:find("Foot") then
				descendant.Color = colors.Legs
			end
		end
	end
end

local function makeActor(kind: string, parent: Instance): Actor?
	local model: Model? = nil
	if kind == "You" then
		model = cloneYou()
	else
		local started = os.clock()
		while not templates[kind] and os.clock() - started < RIG_WAIT_SECONDS do
			task.wait(0.1)
		end
		local template = templates[kind]
		if template then
			model = template:Clone()
		else
			local clone = cloneYou()
			if clone then
				recolour(clone, RIG_LOOKS[kind])
			end
			model = clone
		end
	end
	if not model then
		return nil
	end
	local rig = model :: Model
	rig.Name = "Trailer" .. kind
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Sound") or descendant:IsA("BillboardGui") or descendant:IsA("ForceField") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = true
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		rig:Destroy()
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	root.Anchored = true
	rig.Parent = parent
	local runId, idleId = readAnimationIds()
	return {
		Model = rig,
		Root = root,
		RootHeight = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2,
		Run = loadTrack(humanoid, runId),
		Idle = loadTrack(humanoid, idleId),
		Moving = nil,
	}
end

-- `localPos` is the floor point (plot-local; y = floor height there).
local function pose(actor: Actor, localPos: Vector3, facing: Vector3, moving: boolean)
	local at = world(localPos + Vector3.new(0, actor.RootHeight, 0))
	local flat = origin:VectorToWorldSpace(Vector3.new(facing.X, 0, facing.Z))
	actor.Root.CFrame = if flat.Magnitude > 0.01 then CFrame.lookAt(at, at + flat) else CFrame.new(at)
	if actor.Moving ~= moving then
		actor.Moving = moving
		local run, idle = actor.Run, actor.Idle
		if moving then
			if idle then
				idle:Stop(0.15)
			end
			if run then
				run:Play(0.15)
			end
		else
			if run then
				run:Stop(0.15)
			end
			if idle then
				idle:Play(0.15)
			end
		end
	end
end

local function headTop(actor: Actor): Vector3
	return actor.Root.Position + Vector3.new(0, actor.RootHeight + 0.6, 0)
end

--[[ World pieces --------------------------------------------------------------------- ]]

local function folder(): Folder
	local existing = localFolder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "TrailerLocal"
	created.Parent = Workspace
	localFolder = created
	return created
end

local function pedestalPart(index: number): BasePart?
	local pedestals = plot and plot:FindFirstChild("Pedestals")
	local pedestal = pedestals and pedestals:FindFirstChild("Pedestal" .. index)
	return if pedestal and pedestal:IsA("BasePart") then pedestal else nil
end

local function machineParts(): (BasePart?, BasePart?)
	local machine = plot and plot:FindFirstChild("FusionMachine")
	local core = machine and machine:FindFirstChild("Core")
	local ring = machine and machine:FindFirstChild("Ring")
	return if core and core:IsA("BasePart") then core else nil, if ring and ring:IsA("BasePart") then ring else nil
end

local function corePosition(): Vector3
	return world(PlotLayout.FUSION_MACHINE + Vector3.new(0, PlotLayout.Machine.CoreY, 0))
end

-- An orb exactly like a pedestal's (PedestalVisuals), centred at `center`.
local function orbAt(look: TrailerConfig.ItemLook, center: Vector3): Model
	return PedestalVisuals.BuildCarryOrb(look.Tier, look.Mutation, CFrame.new(center), folder())
end

local function pill(adornee: BasePart, text: string, color: Color3, height: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "TrailerPill"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(220, 48)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = 200
	gui.Parent = folder()
	UIKit.Pill({
		Parent = gui,
		Text = text,
		Color = color,
		Font = Fonts.Display,
		TextSize = 28,
		Height = 44,
		TextStroke = UITheme.Stroke.Text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	return gui
end

-- The game's hold ring (the HOW TO HEIST "E" ring) over a pedestal,
-- filling as `setFill(u)` is called.
local function holdRing(adornee: BasePart): (BillboardGui, (u: number) -> ())
	local gui = Instance.new("BillboardGui")
	gui.Name = "TrailerHoldRing"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(84, 84)
	gui.StudsOffset = Vector3.new(0, PlotLayout.Pedestal.OrbCenterY + 1.5 - PlotLayout.Pedestal.ColumnSize.Y / 2, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = 200
	gui.Parent = folder()
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundColor3 = Colors.Panel2
	ring.BackgroundTransparency = 0.2
	ring.Parent = gui
	UIKit.Corner(ring, 999)
	UIKit.Stroke(ring, 4, Colors.White)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 0.5)
	fill.Size = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = Colors.Danger
	fill.Parent = ring
	UIKit.Corner(fill, 999)
	UIKit.Label({
		Name = "Key",
		Text = "E",
		Font = Fonts.Display,
		TextSize = 34,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Stroke = UITheme.Stroke.Text,
		Parent = ring,
	})
	return gui, function(u: number)
		fill.Size = UDim2.fromScale(u, u)
	end
end

--[[ The staged lab (every pedestal shows TrailerConfig.Pedestals) ------------------------ ]]

local STASHED_NAMES = { PedestalVisualElements = true, PedestalLight = true, PedestalHighlight = true }

local function applyLook(index: number, look: TrailerConfig.ItemLook?)
	local pedestal = pedestalPart(index)
	if pedestal and look then
		PedestalVisuals.Apply(pedestal, look.Tier, look.Mutation)
	end
end

-- Stashes the server's orb visuals on every pedestal (reparented locally,
-- never destroyed), shows the trailer lineup, and restores it all at the end.
local function stageLab()
	for index = 1, PlotLayout.PEDESTAL_COUNT do
		local pedestal = pedestalPart(index)
		if pedestal then
			local stashed: { Instance } = {}
			for _, child in pedestal:GetChildren() do
				if STASHED_NAMES[child.Name] then
					table.insert(stashed, child)
					child.Parent = nil
				end
			end
			local labels: { LayerCollector } = {}
			for _, descendant in pedestal:GetDescendants() do
				if descendant:IsA("LayerCollector") and descendant.Enabled then
					descendant.Enabled = false
					table.insert(labels, descendant)
				end
			end
			local cap = pedestal:FindFirstChild("Cap") :: BasePart?
			local lip = cap and cap:FindFirstChild("CapLip") :: BasePart?
			local was = {
				Transparency = pedestal.Transparency,
				CapTransparency = cap and cap.Transparency,
				CapColor = cap and cap.Color,
				CapMaterial = cap and cap.Material,
				LipColor = lip and lip.Color,
				LipTransparency = lip and lip.Transparency,
			}
			-- The +2 spots show solid (a full lab).
			pedestal.Transparency = 0
			if cap then
				cap.Transparency = 0
			end
			applyLook(index, TrailerConfig.Pedestals[index])
			onRestore(function()
				PedestalVisuals.Clear(pedestal)
				for _, child in stashed do
					child.Parent = pedestal
				end
				for _, label in labels do
					label.Enabled = true
				end
				pedestal.Transparency = was.Transparency
				if cap then
					cap.Transparency = was.CapTransparency :: number
					cap.Color = was.CapColor :: Color3
					cap.Material = was.CapMaterial :: Enum.Material
				end
				if lip then
					lip.Color = was.LipColor :: Color3
					lip.Transparency = was.LipTransparency :: number
				end
			end)
		end
	end
end

--[[ Shots ------------------------------------------------------------------------------ ]]

type Builder = (token: number) -> ShotRun

local function noop() end

local builders: { [string]: Builder } = {}

-- 1. The lab at night: a slow push-in from the gate.
builders.night = function()
	EventController.PreviewLocal("Night")
	return {
		Update = noop,
		Cleanup = function()
			EventController.PreviewLocal("None") -- the plain sky until the run ends
		end,
	}
end

-- 2. A local NPC (a generic yellow / blue noob, never your own avatar)
-- walks onto the Gacha Pad and pulls: the pad's real burst, then the big
-- reveal card for a Rainbow Legendary.
builders.pull = function()
	local cfg = TrailerConfig.Pull
	local station = plot and plot:FindFirstChild("GachaStation")
	local pad = station and station:FindFirstChild("Pad") :: BasePart?
	local puller = makeActor("Owner", folder())
	local beat = beats()
	local item = itemFor(cfg.Item, "pull")
	return {
		Update = function(t: number)
			if puller then
				local u = smooth(phase(t, cfg.WalkStart, cfg.WalkEnd))
				local moving = t > cfg.WalkStart and t < cfg.WalkEnd
				local at = cfg.WalkFrom:Lerp(cfg.WalkTo, u)
				pose(puller, at, if moving then cfg.WalkTo - cfg.WalkFrom else Vector3.new(-1, 0, 1), moving)
			end
			beat(t, cfg.PullAt, function()
				if not pad then
					return
				end
				local emitter = SparkleEmitter.Create({ Color = FusionConfig.TierAccentColors[item.Tier] or Colors.White })
				emitter.Enabled = false
				emitter.Parent = pad
				emitter:Emit(PULL_BURST_COUNT)
				Debris:AddItem(emitter, 3)
				if explosionTemplate and FusionConfig.MajorRevealTiers[item.Tier] then
					ImportedEffects.Play(explosionTemplate, pad.CFrame, folder(), PULL_EXPLOSION)
				end
				SoundKit.Play("Station", pad)
			end)
			beat(t, cfg.CardAt, function()
				setCardGuis(true)
				ResultController.ShowItemCard("YOU PULLED", item, nil, false)
			end)
		end,
		Cleanup = function()
			ResultController.CloseCards()
			setCardGuis(false)
			if puller then
				puller.Model:Destroy()
			end
		end,
	}
end

-- 3. Two Mythic orbs float into the machine: the real charge-up and
-- reveal, a Secret, your own FUSION SUCCESS! banner, an orbit round it.
builders.fuse = function()
	local cfg = TrailerConfig.Fuse
	local core, ring = machineParts()
	local center = corePosition()
	targets.Core = function()
		return center
	end
	local inputs: { Model } = {}
	for _, from in cfg.InputFrom do
		table.insert(inputs, orbAt({ Tier = cfg.InputTier }, world(from)))
	end
	local secret: Model? = nil
	local beat = beats()
	local revealAt = cfg.FloatEnd + cfg.ChargeSeconds
	local result = itemFor({ Tier = cfg.ResultTier }, "fuse")
	return {
		Update = function(t: number)
			local u = smooth(phase(t, cfg.FloatStart, cfg.FloatEnd))
			for index, orb in inputs do
				if orb.Parent then
					local from = world(cfg.InputFrom[index])
					orb:PivotTo(CFrame.new(from:Lerp(center, u)) * CFrame.Angles(0, t * 2, 0))
				end
			end
			beat(t, cfg.FloatEnd, function()
				for _, orb in inputs do
					orb:Destroy()
				end
				if core then
					RevealEffects.PlayChargeUp({ Core = core, Ring = ring }, cfg.ChargeSeconds)
				end
			end)
			beat(t, revealAt, function()
				if core then
					core.LocalTransparencyModifier = 1
					secret = orbAt({ Tier = cfg.ResultTier }, center)
					RevealEffects.PlayReveal({ Core = core, Ring = ring }, {
						AccentColor = FusionConfig.TierAccentColors[cfg.ResultTier] or Colors.White,
						IsMajor = true,
					})
				end
			end)
			beat(t, revealAt + cfg.BannerDelay, function()
				setCardGuis(true)
				AnnouncementController.PreviewFusionBanner(result)
			end)
			local orb = secret
			if orb and orb.Parent then
				orb:PivotTo(CFrame.new(center) * CFrame.Angles(0, t * 0.8, 0))
			end
		end,
		Cleanup = function()
			setCardGuis(false)
			if core then
				core.LocalTransparencyModifier = 0
			end
			for _, orb in inputs do
				orb:Destroy()
			end
			if secret then
				secret:Destroy()
			end
			targets.Core = nil
		end,
	}
end

-- 4. A masked red thief holds E at pedestal 2, grabs the orb and runs for
-- the gate with it over his head; the yellow / blue owner chases: RUN!,
-- then the catch and the orb goes home.
builders.heist = function()
	local cfg = TrailerConfig.Heist
	local look = TrailerConfig.Pedestals[cfg.Pedestal]
	local pedestal = pedestalPart(cfg.Pedestal)
	local thief = makeActor("Thief", folder())
	local owner = makeActor("Owner", folder())
	local beat = beats()
	local carry: Model? = nil
	local ringGui: BillboardGui? = nil
	local setFill: ((number) -> ())? = nil
	if pedestal then
		local gui, fill = holdRing(pedestal)
		ringGui, setFill = gui, fill
	end
	local holdStart = cfg.ThiefRunStart - HeistConfig.GrabHoldSeconds
	targets.Thief = function()
		return if thief then thief.Root.Position + Vector3.new(0, 1, 0) else nil
	end
	targets.Owner = function()
		return if owner then owner.Root.Position + Vector3.new(0, 1, 0) else nil
	end
	local caught = false
	return {
		Update = function(t: number)
			local fill = setFill
			if fill then
				fill(phase(t, holdStart, cfg.ThiefRunStart))
			end
			if thief then
				local u = smooth(phase(t, cfg.ThiefRunStart, cfg.ThiefRunEnd))
				local at, direction = alongPath(cfg.ThiefPath, u)
				local moving = t > cfg.ThiefRunStart and t < cfg.ThiefRunEnd and not caught
				pose(thief, at, if t < cfg.ThiefRunStart then Vector3.new(0, 0, -1) else direction, moving)
				local orb = carry
				if orb and orb.Parent then
					orb:PivotTo(CFrame.new(headTop(thief) + Vector3.new(0, CARRY_ORB_ABOVE_HEAD, 0)))
				end
			end
			if owner then
				local u = smooth(phase(t, cfg.OwnerRunStart, cfg.OwnerRunEnd))
				local at, direction = alongPath(cfg.OwnerPath, u)
				pose(owner, at, direction, t > cfg.OwnerRunStart and t < cfg.OwnerRunEnd)
			end
			beat(t, cfg.ThiefRunStart, function()
				if ringGui then
					ringGui:Destroy()
				end
				if pedestal then
					PedestalVisuals.SetStolen(pedestal)
				end
				if thief and look then
					carry = orbAt(look, headTop(thief))
					pill(thief.Root, "RUN!", Colors.Danger, 6)
				end
			end)
			beat(t, cfg.CatchAt, function()
				caught = true
				for _, child in folder():GetChildren() do
					if child.Name == "TrailerPill" then
						child:Destroy()
					end
				end
				if thief then
					pill(thief.Root, "CAUGHT!", Colors.ShieldTeal, 6)
				end
				SoundKit.Play("Toast", nil)
			end)
			beat(t, cfg.OrbBackAt, function()
				if carry then
					carry:Destroy()
					carry = nil
				end
				applyLook(cfg.Pedestal, look)
			end)
		end,
		Cleanup = function()
			if ringGui then
				ringGui:Destroy()
			end
			if carry then
				carry:Destroy()
			end
			for _, child in folder():GetChildren() do
				if child.Name == "TrailerPill" then
					child:Destroy()
				end
			end
			for _, actor in { thief, owner } do
				if actor then
					actor.Model:Destroy()
				end
			end
			applyLook(cfg.Pedestal, look)
			targets.Thief = nil
			targets.Owner = nil
		end,
	}
end

-- 5. Void Moon: tilt up from the machine to the purple moon, back down to a
-- Void orb revealing at the machine, with the event-mutation card.
builders.voidmoon = function()
	local cfg = TrailerConfig.VoidMoon
	moonDirection = origin:VectorToWorldSpace(cfg.MoonDirection).Unit
	EventController.PreviewLocal("VoidMoon", { MoonDirection = moonDirection })
	local core, ring = machineParts()
	local center = corePosition()
	targets.Core = function()
		return center
	end
	local voidOrb: Model? = nil
	local beat = beats()
	local item = itemFor(cfg.Item, "void")
	return {
		Update = function(t: number)
			beat(t, cfg.RevealAt, function()
				if core then
					core.LocalTransparencyModifier = 1
					voidOrb = orbAt(cfg.Item, center)
					RevealEffects.PlayReveal({ Core = core, Ring = ring }, {
						AccentColor = UITheme.GetMutationColor(cfg.Item.Mutation) or Colors.White,
						IsMajor = true,
					})
				end
			end)
			beat(t, cfg.CardAt, function()
				setCardGuis(true)
				ResultController.ShowItemCard("VOID MOON", item, nil, true)
			end)
			local orb = voidOrb
			if orb and orb.Parent then
				orb:PivotTo(CFrame.new(center) * CFrame.Angles(0, t * 0.8, 0))
			end
		end,
		Cleanup = function()
			ResultController.CloseCards()
			setCardGuis(false)
			if core then
				core.LocalTransparencyModifier = 0
			end
			if voidOrb then
				voidOrb:Destroy()
			end
			targets.Core = nil
			EventController.PreviewLocal("None") -- the plain sky until the run ends
		end,
	}
end

-- 6. The hero shot: the Secret on its pedestal, held still (the logo goes
-- on in editing).
builders.hold = function()
	applyLook(TrailerConfig.HeroPedestal, TrailerConfig.HeroItem)
	return {
		Update = noop,
		Cleanup = function()
			applyLook(TrailerConfig.HeroPedestal, TrailerConfig.Pedestals[TrailerConfig.HeroPedestal])
		end,
	}
end

--[[ Run / stop ---------------------------------------------------------------------------- ]]

local function endShot()
	local shotRun = currentRun
	currentRun = nil
	currentShot = nil
	if shotRun then
		local cleanup = shotRun.Cleanup
		local ok, err = pcall(function()
			cleanup()
		end)
		if not ok then
			warn("TrailerController: cleanup: " .. tostring(err))
		end
	end
end

function TrailerController.Stop()
	if not running then
		return
	end
	running = false
	runToken += 1
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	end)
	endShot()
	pcall(EventController.StopPreview)
	pcall(ResultController.CloseCards)
	for index = #restoreSteps, 1, -1 do
		local step = restoreSteps[index]
		local ok, err = pcall(function()
			step()
		end)
		if not ok then
			warn("TrailerController: restore: " .. tostring(err))
		end
	end
	table.clear(restoreSteps)
	hideCharacters(false)
	for _, connection in stopConnections do
		connection:Disconnect()
	end
	table.clear(stopConnections)
	table.clear(targets)
	if localFolder then
		localFolder:Destroy()
		localFolder = nil
	end
	if fadeGui then
		fadeGui:Destroy()
		fadeGui = nil
		fadeFrame = nil
		countLabel = nil
	end
end

local function watchForStop()
	local function onCharacterGone()
		task.defer(TrailerController.Stop)
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(stopConnections, humanoid.Died:Connect(onCharacterGone))
	end
	table.insert(stopConnections, localPlayer.CharacterRemoving:Connect(onCharacterGone))
	table.insert(stopConnections, localPlayer.CharacterAdded:Connect(onCharacterGone))
	table.insert(
		stopConnections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode == TrailerConfig.StopKey then
				TrailerController.Stop()
			end
		end)
	)
end

-- Plays every shot (or just `only`), with the countdown first.
function TrailerController.Play(only: string?)
	TrailerController.Stop()
	local plotsFolder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	local myPlot = plotsFolder and plotsFolder:FindFirstChild(PlotNaming.GetPlotName(localPlayer.UserId))
	local plotOrigin = myPlot and myPlot:FindFirstChild("PlotOrigin", true)
	if not myPlot or not myPlot:IsA("Model") or not plotOrigin or not plotOrigin:IsA("BasePart") then
		ToastController.Show("Claim your lab first, then /trailer", "Neutral")
		return
	end
	local shots: { TrailerConfig.Shot } = {}
	for _, shot in TrailerConfig.Shots do
		if only == nil or shot.Id == only then
			table.insert(shots, shot)
		end
	end
	if #shots == 0 then
		return
	end
	plot = myPlot
	origin = plotOrigin.CFrame
	running = true
	runToken += 1
	local token = runToken
	requestTemplates()
	buildFade()
	enterCleanFrame()
	stageLab()
	-- No live event's sky in shots that don't ask for one.
	EventController.PreviewLocal("None")
	watchForStop()
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, renderStep)

	task.spawn(function()
		if not countdown(token) then
			return
		end
		for index, shot in shots do
			local builder = builders[shot.Id]
			if not builder then
				continue
			end
			local ok, shotRun = pcall(builder, token)
			if not alive(token) then
				return
			end
			if ok then
				currentRun = shotRun
			else
				warn("TrailerController: " .. shot.Id .. ": " .. tostring(shotRun))
			end
			currentShot = shot
			shotStart = os.clock()
			if not fadeTo(token, 1) then
				return
			end
			if not sleep(token, shot.Duration - TrailerConfig.FadeSeconds * (if index < #shots then 2 else 1)) then
				return
			end
			if not fadeTo(token, 0) then
				return
			end
			endShot()
		end
		TrailerController.Stop()
	end)
end

function TrailerController.IsRunning(): boolean
	return running
end

function TrailerController.Init()
	RemoteEvents.TrailerStart.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.Stop == true then
			TrailerController.Stop()
		elseif typeof(payload.Shot) == "string" and TrailerConfig.GetShot(payload.Shot) then
			TrailerController.Play(payload.Shot)
		elseif payload.Shot == nil then
			TrailerController.Play(nil)
		end
	end)
end

return TrailerController
