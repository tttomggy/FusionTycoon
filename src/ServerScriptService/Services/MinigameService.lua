--!strict
--[[
	MinigameService
	---------------
	ORB RUSH: a 90-second arena round every 15 minutes (hh:07, :22, :37, :52;
	numbers in MinigameConfig, geometry in ArenaLayout / StreetLayout.RushPortal,
	client in MinigameController; docs/systems/minigames.md).

	  Call       the 60 s before a round: the street portal is on and anyone can
	             JOIN (walk in, or the HUD pill: MinigameQueue { Action = "Join" }).
	             Entering the portal fails a carry in progress; a carrying player
	             can't queue from the pill.
	  Fill       at the end of the call the queued humans play (up to 8). Fewer than
	             MinigameConfig.FillTo get bots (server NPC rigs, one loop). Nobody
	             queued, no round.
	  Round      teleport to the arena, a 3-2-1-GO countdown (frozen), then orbs rain
	             in waves; walking through one takes it (the server checks the
	             distance to the character root, max PickupsPerTick a player a tick).
	             A weapon hit (CombatService) knocks 30% of the target's points out
	             as orbs; 2 s immunity. The last 15 s: gold orbs only, twice as fast.
	  Results    placements, prizes (below), everyone teleported home; the client
	             shows the podium card and the prize reveals through the normal pull
	             card (TycoonService.GrantRewardItem).

	Server authority: this service owns every orb, score, bot and prize. The
	client only renders (orbs are server parts it animates) and sends the one
	queue remote. While a player is in the arena PlayerDataService.IsInMinigame
	is true: no pulls, fusing, upgrades, Multiplier Pad, rebirth or stealing
	(WhyBusy "InArena"); passive income keeps paying.

	Prizes: 1st / 2nd / 3rd one orb of MinigameConfig.Prizes' weights; everyone
	else with MinPointsToPlace points the cash of ParticipationIncomeSeconds of
	their own passive income; below that, nothing (AFK gets nothing). A bot's
	place awards nothing and does not move anyone up (a human's prize is for
	their own place). At most PlacementPrizesPerHour placement prizes per player
	per rolling hour (past it: the cash). Leaving mid-round forfeits.

	Follows ServiceTemplate:
	  :Init()   own state, the remote handlers.
	  :Start()  resolves PlayerDataService, TycoonService and HeistService, builds
	            the arena and the portal, starts the loops.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ArenaLayout = require(ReplicatedStorage.Shared.Config.ArenaLayout)
local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MinigameConfig = require(ReplicatedStorage.Shared.Config.MinigameConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local StreetLayout = require(ReplicatedStorage.Shared.Config.StreetLayout)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)
local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))
type HeistServiceModule = typeof(require(script.Parent.HeistService))

export type Phase = "Idle" | "Call" | "Countdown" | "Play" | "Results"

type Skill = { Id: string, Weight: number, Speed: number, Reaction: number, Greed: number }

type Orb = {
	Id: number,
	Part: BasePart,
	Tier: string,
	Value: number,
	Position: Vector3, -- where it lies (flat + floor)
	LandAt: number, -- os.clock(): can be taken from here
	ExpiresAt: number,
}

type Participant = {
	Id: number,
	Name: string,
	Player: Player?, -- nil: a bot
	UserId: number, -- 0 for a bot
	Model: Model?, -- a bot's rig
	Points: number,
	ReachedAt: number, -- os.clock() of the last point (a tie goes to the earlier)
	ImmuneUntil: number, -- os.clock()
	SpawnIndex: number,
	Left: boolean,
	Skill: Skill?,
	Goal: number?, -- a bot's target orb id
	NextThink: number,
	StunUntil: number,
}

export type Award = {
	Kind: string, -- "Orb" | "Cash" | "None"
	Place: number,
	Tier: string?, -- Orb
	Seconds: number?, -- Cash: seconds of passive income
	Capped: boolean?, -- Cash because the hourly placement cap was hit
}

export type RankEntry = { IsBot: boolean, UserId: number, Points: number, Left: boolean }

type Timing = { Countdown: number, Round: number, Golden: number, Hold: number }

type State = {
	phase: Phase,
	round: MinigameConfig.Round?,
	lastCallSlot: number,
	queue: { Player },
	participants: { Participant },
	orbs: { [number]: Orb },
	orbCount: number,
	nextOrbId: number,
	nextBotId: number,
	rng: Random,
	running: boolean,
	timing: Timing,
	clock: () -> number, -- unix seconds
	forcedCallUntil: number?, -- a debug call window (unix)
	roundToken: number,
	goAt: number, -- os.clock() the round starts (after the countdown)
	endsAt: number, -- os.clock() the round ends
	goldenSent: boolean,
	savedSpawns: { [number]: SpawnLocation? },
	frozen: { [number]: { WalkSpeed: number, JumpPower: number, JumpHeight: number, UseJumpPower: boolean } },
	prizeLog: { [number]: { number } },
	arena: Folder?,
	orbFolder: Folder?,
	botFolder: Folder?,
	spawns: { SpawnLocation },
	towerLabels: { { Name: TextLabel, Points: TextLabel } },
	portalCounter: BillboardKit.Chip?,
	portalTitle: BillboardKit.Chip?,
	portalFace: BasePart?,
	portalTrigger: BasePart?,
	lastScoreSend: number,
	lastPublish: string,
	touchDebounce: { [number]: number },
	lastResults: { [string]: any }?,
	connections: { RBXScriptConnection },
}

--[[ Private state -------------------------------------------------------- ]]

local function unixNow(): number
	return Workspace:GetServerTimeNow()
end

local function defaultTiming(): Timing
	return {
		Countdown = MinigameConfig.CountdownSeconds,
		Round = MinigameConfig.RoundSeconds,
		Golden = MinigameConfig.GoldenWaveSeconds,
		Hold = MinigameConfig.ResultsHoldSeconds,
	}
end

local state: State = {
	phase = "Idle",
	round = nil,
	lastCallSlot = -1,
	queue = {},
	participants = {},
	orbs = {},
	orbCount = 0,
	nextOrbId = 1,
	nextBotId = 1,
	rng = Random.new(),
	running = false,
	timing = defaultTiming(),
	clock = unixNow,
	forcedCallUntil = nil,
	roundToken = 0,
	goAt = 0,
	endsAt = 0,
	goldenSent = false,
	savedSpawns = {},
	frozen = {},
	prizeLog = {},
	arena = nil,
	orbFolder = nil,
	botFolder = nil,
	spawns = {},
	towerLabels = {},
	portalCounter = nil,
	portalTitle = nil,
	portalFace = nil,
	portalTrigger = nil,
	lastScoreSend = 0,
	lastPublish = "",
	touchDebounce = {},
	lastResults = nil,
	connections = {},
}

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule
local HeistService: HeistServiceModule

local MinigameService = {}

MinigameService.Name = "MinigameService"

local World = UITheme.World

local JOIN_RATE = 1.5 -- MinigameQueue requests a second (burst 3)
local PORTAL_TOUCH_DEBOUNCE = 1.5
local SPAWN_STREAM_SECONDS = 3
local FREEZE_ATTRIBUTE = "OrbRushFrozen"

--[[ Small helpers ------------------------------------------------------------ ]]

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function humans(): { Participant }
	local list: { Participant } = {}
	for _, p in state.participants do
		if p.Player and not p.Left then
			table.insert(list, p)
		end
	end
	return list
end

local function participantFor(player: Player): Participant?
	for _, p in state.participants do
		if p.Player == player then
			return p
		end
	end
	return nil
end

local function tierDef(id: string): { Id: string, Value: number, Weight: number, Token: string }
	for _, tier in MinigameConfig.OrbTiers do
		if tier.Id == id then
			return tier
		end
	end
	return MinigameConfig.OrbTiers[1]
end

local function sendTo(player: Player, payload: { [string]: any })
	RemoteEvents.MinigameState:FireClient(player, payload)
end

local function sendToHumans(payload: { [string]: any })
	for _, p in humans() do
		sendTo(p.Player :: Player, payload)
	end
end

--[[ Schedule publishing (Workspace attributes, read by every client) ---------------- ]]

local function publish()
	local unix = state.clock()
	local round = state.round
	-- The next scheduled call that has not started yet (what "NEXT ORB RUSH at :22" shows).
	local slot = MinigameConfig.GetSlot(unix)
	local upcoming = MinigameConfig.GetRoundForSlot(slot)
	if upcoming.CallAt <= unix then
		upcoming = MinigameConfig.GetRoundForSlot(slot + 1)
	end
	local nextAt = upcoming.CallAt
	local startAt = if round then round.StartAt else 0
	local signature = ("%s|%.0f|%.0f|%.0f|%d"):format(state.phase, round and round.CallAt or 0, startAt, nextAt, #state.queue)
	if signature == state.lastPublish then
		return
	end
	state.lastPublish = signature
	Workspace:SetAttribute("OrbRushPhase", state.phase)
	Workspace:SetAttribute("OrbRushCallAt", if round then round.CallAt else 0)
	Workspace:SetAttribute("OrbRushStartAt", startAt)
	Workspace:SetAttribute("OrbRushNextAt", nextAt)
	Workspace:SetAttribute("OrbRushQueued", #state.queue)
	Workspace:SetAttribute("OrbRushMax", MinigameConfig.MaxPlayers)
end

-- What the portal last showed, so a scheduler tick that changes nothing sets nothing
-- (SetChipGradient rebuilds its gradient each call).
local portalShown = { On = false, Text = "", Count = -1, Built = false }

local function updatePortal()
	local on = state.phase == "Call"
	local counter, title, face = state.portalCounter, state.portalTitle, state.portalFace
	if counter and (portalShown.Count ~= #state.queue or portalShown.On ~= on) then
		counter.Gui.Enabled = on
		counter.Label.Text = ("%d / %d"):format(#state.queue, MinigameConfig.MaxPlayers)
		portalShown.Count = #state.queue
	end
	if title then
		local nextAt = Workspace:GetAttribute("OrbRushNextAt")
		local text = if on then "ORB RUSH · JOIN" else ("ORB RUSH · %s"):format(MinigameConfig.FormatMinute(if typeof(nextAt) == "number" then nextAt else 0))
		if title.Label.Text ~= text then
			title.Label.Text = text
		end
		if portalShown.On ~= on or not portalShown.Built then
			BillboardKit.SetChipGradient(title, if on then UITheme.Gradients.OrbRush else UITheme.Gradients.Disabled)
		end
	end
	if face and (portalShown.On ~= on or not portalShown.Built) then
		BillboardKit.SetPadFace(face, if on then World.RushPortal else World.Unclaimed, "RUSH", true)
	end
	portalShown.On = on
	portalShown.Built = true
end

local function setPhase(phase: Phase)
	state.phase = phase
	publish()
	updatePortal()
end

--[[ Arena ---------------------------------------------------------------------- ]]

local function newSurfaceFace(part: BasePart, face: Enum.NormalId, name: string): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = 260
	gui.ResetOnSpawn = false
	gui.Parent = part
	return gui
end

-- The score tower: four faces, a title and the top 3 live.
local function buildTower(parent: Instance)
	local size = ArenaLayout.TOWER_SIZE
	local tower = PartKit.Part({
		Name = "ScoreTower",
		Size = size,
		CFrame = CFrame.new(ArenaLayout.CENTER + Vector3.new(0, size.Y / 2, 0)),
		Color = World.ArenaTower,
		Parent = parent,
	})
	local band = PartKit.Cylinder({
		Name = "TowerBand",
		Center = CFrame.new(ArenaLayout.CENTER + Vector3.new(0, size.Y - 1.2, 0)),
		Height = 0.4,
		Diameter = size.X * 1.5,
		Color = World.ArenaRim,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
	PartKit.MakeDecorative(band)
	local faces = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
	for _, face in faces do
		local gui = newSurfaceFace(tower, face, "Scores" .. face.Name)
		local panel = Instance.new("Frame")
		panel.Size = UDim2.fromScale(1, 1)
		panel.BackgroundColor3 = World.ArenaTower
		panel.BorderSizePixel = 0
		panel.Parent = gui
		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromScale(1, 0.12)
		title.Position = UDim2.fromScale(0, 0.02)
		title.FontFace = UITheme.Fonts.Display
		title.TextScaled = true
		title.Text = "ORB RUSH"
		title.TextColor3 = UITheme.Colors.Text
		title.Parent = panel
		for row = 1, 3 do
			local rowFrame = Instance.new("Frame")
			rowFrame.BackgroundColor3 = UITheme.Colors.Panel
			rowFrame.BorderSizePixel = 0
			rowFrame.Size = UDim2.fromScale(0.9, 0.2)
			rowFrame.Position = UDim2.fromScale(0.05, 0.16 + (row - 1) * 0.24)
			rowFrame.Parent = panel
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.2, 0)
			corner.Parent = rowFrame
			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Size = UDim2.fromScale(0.62, 0.7)
			name.Position = UDim2.fromScale(0.05, 0.15)
			name.FontFace = UITheme.Fonts.Display
			name.TextScaled = true
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Text = ("%d."):format(row)
			name.TextColor3 = UITheme.Colors.Text
			name.Parent = rowFrame
			local points = Instance.new("TextLabel")
			points.BackgroundTransparency = 1
			points.Size = UDim2.fromScale(0.28, 0.7)
			points.Position = UDim2.fromScale(0.68, 0.15)
			points.FontFace = UITheme.Fonts.Display
			points.TextScaled = true
			points.TextXAlignment = Enum.TextXAlignment.Right
			points.Text = ""
			points.TextColor3 = World.OrbGold
			points.Parent = rowFrame
			table.insert(state.towerLabels, { Name = name, Points = points })
		end
	end
end

local function buildArena()
	local folder = Workspace:FindFirstChild("OrbRushArena")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "OrbRushArena"
	local center = ArenaLayout.CENTER

	-- The floating disc: SmoothPlastic, a narrower underside, a thin Neon band seen
	-- from the side (never a flat Neon face), SurfaceGui rings on top.
	PartKit.Cylinder({
		Name = "Floor",
		Center = CFrame.new(center - Vector3.new(0, ArenaLayout.FLOOR_THICKNESS / 2, 0)),
		Height = ArenaLayout.FLOOR_THICKNESS,
		Diameter = ArenaLayout.FLOOR_RADIUS * 2,
		Color = World.ArenaDisc,
		Parent = folder,
	})
	PartKit.Cylinder({
		Name = "Underside",
		Center = CFrame.new(center - Vector3.new(0, ArenaLayout.FLOOR_THICKNESS + 4, 0)),
		Height = 8,
		Diameter = ArenaLayout.FLOOR_RADIUS * 2 * 0.55,
		Color = World.ArenaDebris,
		CanCollide = false,
		Parent = folder,
	})
	for _, yOffset in { ArenaLayout.FLOOR_THICKNESS / 2, ArenaLayout.FLOOR_THICKNESS - 0.4 } do
		local band = PartKit.Cylinder({
			Name = "RimBand",
			Center = CFrame.new(center - Vector3.new(0, yOffset, 0)),
			Height = ArenaLayout.RIM_BAND_HEIGHT,
			Diameter = ArenaLayout.FLOOR_RADIUS * 2 + 0.3,
			Color = World.ArenaRim,
			Material = Enum.Material.Neon,
			Parent = folder,
		})
		PartKit.MakeDecorative(band)
	end
	for _, diameter in ArenaLayout.RING_DIAMETERS do
		local ring = BillboardKit.BuildPadFace(folder, CFrame.new(center), diameter, World.ArenaRim, nil)
		-- The pad face brings a PointLight; the arena has no lights (the glow is the SurfaceGui's).
		local light = ring:FindFirstChild("FaceLight")
		if light then
			light:Destroy()
		end
	end

	-- Invisible walls round the rim.
	local segments = ArenaLayout.WALL_SEGMENTS
	local radius = ArenaLayout.FLOOR_RADIUS + ArenaLayout.WALL_THICKNESS / 2
	local chord = 2 * radius * math.tan(math.pi / segments) + 1
	for index = 1, segments do
		local angle = (index - 1) / segments * 2 * math.pi
		local position = center + Vector3.new(math.cos(angle) * radius, ArenaLayout.WALL_HEIGHT / 2, math.sin(angle) * radius)
		PartKit.Part({
			Name = "Wall",
			Size = Vector3.new(chord, ArenaLayout.WALL_HEIGHT, ArenaLayout.WALL_THICKNESS),
			CFrame = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)),
			Color = World.ArenaDebris,
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = folder,
		})
	end

	-- Spawn points (RespawnLocation while in the round).
	table.clear(state.spawns)
	for index = 1, ArenaLayout.SPAWN_COUNT do
		local at = ArenaLayout.GetSpawnCFrame(index)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "ArenaSpawn" .. index
		spawn.Size = Vector3.new(4, 0.2, 4)
		spawn.CFrame = CFrame.new(Vector3.new(at.Position.X, center.Y + 0.1, at.Position.Z)) * at.Rotation
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.Transparency = 1
		spawn.Neutral = true
		spawn.AllowTeamChangeOnTouch = false
		spawn.Duration = 0
		spawn.Enabled = false -- only used as a RespawnLocation target
		for _, child in spawn:GetChildren() do
			if child:IsA("Decal") then
				child:Destroy()
			end
		end
		spawn.Parent = folder
		table.insert(state.spawns, spawn)
	end

	buildTower(folder)

	-- Floating lab debris and a few far "stars" (decoration, client-bobbed).
	for _, debris in ArenaLayout.GetDebris() do
		local part = PartKit.Part({
			Name = "Debris",
			ClassName = if debris.Wedge then "WedgePart" else "Part",
			Size = debris.Size,
			CFrame = CFrame.new(debris.Position) * CFrame.Angles(0, math.rad(debris.Yaw), math.rad(debris.Yaw * 0.3)),
			Color = World.ArenaDebris,
			CanCollide = false,
			Parent = folder,
		})
		PartKit.MakeDecorative(part)
		PartKit.SetHover(part, 3, 1.5, 6, "Bob")
	end
	local starSeed = 777
	for _ = 1, 60 do
		starSeed = (starSeed * 1103515245 + 12345) % 2147483648
		local a = starSeed / 2147483648 * 2 * math.pi
		starSeed = (starSeed * 1103515245 + 12345) % 2147483648
		local b = (starSeed / 2147483648 - 0.5) * math.pi
		local star = PartKit.Part({
			Name = "Star",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.6,
			CFrame = CFrame.new(center + Vector3.new(math.cos(a) * math.cos(b), math.sin(b), math.sin(a) * math.cos(b)) * 420),
			Color = World.OrbWhite,
			Material = Enum.Material.Neon,
			Parent = folder,
		})
		PartKit.MakeDecorative(star)
		star.CastShadow = false
	end

	local orbs = Instance.new("Folder")
	orbs.Name = "Orbs"
	orbs.Parent = folder
	local bots = Instance.new("Folder")
	bots.Name = "Bots"
	bots.Parent = folder
	state.orbFolder = orbs
	state.botFolder = bots
	folder.Parent = Workspace
	state.arena = folder
end

--[[ The street portal ---------------------------------------------------------- ]]

local function portalCFrame(): CFrame
	local portal = StreetLayout.RushPortal
	return CFrame.new(portal.Position.X, portal.Position.Y, portal.Position.Z)
end

local function buildPortal()
	local existing = Workspace:FindFirstChild("OrbRushPortal")
	if existing then
		existing:Destroy()
	end
	local portal = StreetLayout.RushPortal
	local folder = Instance.new("Model")
	folder.Name = "OrbRushPortal"
	local base = portalCFrame()
	for _, side in { -1, 1 } do
		PartKit.Part({
			Name = "Post",
			Size = portal.PostSize,
			CFrame = base * CFrame.new(side * portal.PostGap, portal.PostSize.Y / 2, 0),
			Color = World.StructureLight,
			Parent = folder,
		})
	end
	PartKit.Part({
		Name = "Beam",
		Size = portal.BeamSize,
		CFrame = base * CFrame.new(0, portal.ArchHeight, 0),
		Color = World.Structure,
		CanCollide = false,
		Parent = folder,
	})
	local strip = PartKit.Part({
		Name = "BeamStrip",
		Size = Vector3.new(portal.BeamSize.X, 0.2, portal.BeamSize.Z + 0.1),
		CFrame = base * CFrame.new(0, portal.ArchHeight - portal.BeamSize.Y / 2 - 0.1, 0),
		Color = World.RushPortal,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	PartKit.MakeDecorative(strip)
	local face = BillboardKit.BuildPadFace(folder, base, portal.Radius * 2, World.Unclaimed, "RUSH")
	BillboardKit.SetPadFace(face, World.Unclaimed, "RUSH", true) -- no street light: the ring's glow is enough
	state.portalFace = face

	local anchor = PartKit.Part({
		Name = "LabelAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = base * CFrame.new(0, portal.CounterOffsetY, 0),
		Color = World.Structure,
		Transparency = 1,
		Parent = folder,
	})
	PartKit.MakeDecorative(anchor)
	state.portalTitle = BillboardKit.Chip(anchor, {
		Name = "PortalTitle",
		Text = "ORB RUSH",
		Gradient = UITheme.Gradients.Disabled,
		Studs = Vector2.new(portal.TitleStuds.X, portal.TitleStuds.Y),
		StudsOffset = Vector3.new(0, portal.TitleOffsetY - portal.CounterOffsetY, 0),
		MaxDistance = portal.MaxDistance,
	})
	local counter = BillboardKit.Chip(anchor, {
		Name = "PortalCounter",
		Text = ("0 / %d"):format(MinigameConfig.MaxPlayers),
		Gradient = UITheme.Gradients.OrbRush,
		Studs = Vector2.new(portal.CounterStuds.X, portal.CounterStuds.Y),
		StudsOffset = Vector3.zero,
		MaxDistance = portal.MaxDistance,
	})
	counter.Gui.Enabled = false
	state.portalCounter = counter

	-- The trigger: walking in joins (fails a carry first).
	local trigger = PartKit.Part({
		Name = "Trigger",
		Size = portal.TriggerSize,
		CFrame = base * CFrame.new(0, portal.TriggerSize.Y / 2, 0),
		Color = World.RushPortal,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		Parent = folder,
	})
	state.portalTrigger = trigger
	folder.Parent = Workspace
end

--[[ Queue --------------------------------------------------------------------------- ]]

local function isQueued(player: Player): boolean
	return table.find(state.queue, player) ~= nil
end

local function setQueued(player: Player, queued: boolean)
	local index = table.find(state.queue, player)
	if queued and not index then
		table.insert(state.queue, player)
	elseif not queued and index then
		table.remove(state.queue, index)
	end
	player:SetAttribute("OrbRushQueued", if queued then true else nil)
	publish()
	updatePortal()
end

-- Why `player` can't queue right now (nil: they can). The pill's check; the
-- portal clears a carry first.
function MinigameService.WhyCantQueue(player: Player): string?
	if state.phase ~= "Call" then
		return "NoCall"
	end
	if not PlayerDataService.IsDataLoaded(player) then
		return "DataNotLoaded"
	end
	if PlayerDataService.IsInMinigame(player) then
		return "InArena"
	end
	if PlayerDataService.IsCarrying(player) then
		return "Carrying"
	end
	if not getRoot(player) then
		return "NoCharacter"
	end
	if not isQueued(player) and #state.queue >= MinigameConfig.MaxPlayers then
		return "Full"
	end
	return nil
end

-- Queues `player` (true), or says why not (false, reason). Idempotent.
function MinigameService.TryQueue(player: Player): (boolean, string?)
	local why = MinigameService.WhyCantQueue(player)
	if why then
		return false, why
	end
	if not isQueued(player) then
		setQueued(player, true)
		AnalyticsKit.Custom(player, "OrbRushQueued")
	end
	return true, nil
end

function MinigameService.Leave(player: Player)
	if isQueued(player) then
		setQueued(player, false)
	end
end

function MinigameService.IsQueued(player: Player): boolean
	return isQueued(player)
end

-- Where the pill puts you: just in front of the portal (street side).
local function portalLanding(): CFrame
	local portal = StreetLayout.RushPortal
	return CFrame.new(portal.Position.X, portal.Position.Y + 4, portal.Position.Z - 7)
end

local function onQueueRequest(player: Player, rawPayload: unknown)
	if not RemoteGuard.Allow(player, "MinigameQueue", JOIN_RATE, 3) then
		return
	end
	if typeof(rawPayload) ~= "table" then
		return
	end
	local action = (rawPayload :: { [string]: unknown }).Action
	if action == "Leave" then
		MinigameService.Leave(player)
		return
	end
	if action ~= "Join" then
		return
	end
	local ok, why = MinigameService.TryQueue(player)
	if not ok then
		sendTo(player, { Kind = "Message", Reason = why })
		return
	end
	-- The pill takes you to the portal when you are not already there.
	local root = getRoot(player)
	if root and (root.Position - StreetLayout.RushPortal.Position).Magnitude > 14 then
		local character = player.Character
		if character then
			character:PivotTo(portalLanding())
		end
	end
	sendTo(player, { Kind = "Queued" })
end

local function onPortalTouched(hit: BasePart)
	local character = hit.Parent
	local player = if character then Players:GetPlayerFromCharacter(character) else nil
	if not player then
		return
	end
	local now = os.clock()
	if (state.touchDebounce[player.UserId] or 0) > now then
		return
	end
	state.touchDebounce[player.UserId] = now + PORTAL_TOUCH_DEBOUNCE
	if state.phase ~= "Call" then
		sendTo(player, { Kind = "Message", Reason = "NoCall" })
		return
	end
	if not PlayerDataService.IsDataLoaded(player) or PlayerDataService.IsInMinigame(player) then
		return
	end
	-- Walking into the portal ends a carry in progress (the orb goes back), then queues.
	if PlayerDataService.IsCarrying(player) then
		HeistService.FailCarriesFor(player, "Failed")
	end
	local ok, why = MinigameService.TryQueue(player)
	if ok then
		sendTo(player, { Kind = "Queued" })
	else
		sendTo(player, { Kind = "Message", Reason = why })
	end
end

--[[ Orbs ------------------------------------------------------------------------------ ]]

local function destroyOrb(orb: Orb)
	if state.orbs[orb.Id] then
		state.orbs[orb.Id] = nil
		state.orbCount -= 1
	end
	orb.Part:Destroy()
end

local function clearOrbs()
	for _, orb in table.clone(state.orbs) do
		destroyOrb(orb)
	end
	if state.orbFolder then
		state.orbFolder:ClearAllChildren()
	end
	state.orbCount = 0
end

-- One orb lying at `ground` (a point on the floor top): it appears from `from`
-- (the sky, or the victim) over `dropSeconds` (the client animates it) and can
-- be taken from then on (a scattered orb after ScatterArmSeconds more).
local function spawnOrb(ground: Vector3, tierId: string, from: Vector3?, dropSeconds: number, armSeconds: number, arc: number?): Orb?
	if state.orbCount >= MinigameConfig.MaxOrbs or not state.orbFolder then
		return nil
	end
	local tier = tierDef(tierId)
	local part = Instance.new("Part")
	part.Name = "Orb"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * MinigameConfig.OrbSize
	part.Material = Enum.Material.Neon
	part.Color = (World :: any)[tier.Token]
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local position = ground + Vector3.new(0, MinigameConfig.OrbHoverHeight, 0)
	part.Position = position
	part:SetAttribute("Value", tier.Value)
	part:SetAttribute("Tier", tier.Id)
	part:SetAttribute("FromPos", from or (position + Vector3.new(0, MinigameConfig.OrbSkyHeight, 0)))
	part:SetAttribute("DropSeconds", dropSeconds)
	part:SetAttribute("Arc", arc or 0)
	local id = state.nextOrbId
	state.nextOrbId += 1
	local landAt = os.clock() + dropSeconds + armSeconds
	local orb: Orb = {
		Id = id,
		Part = part,
		Tier = tier.Id,
		Value = tier.Value,
		Position = position,
		LandAt = landAt,
		ExpiresAt = landAt + MinigameConfig.OrbLifetimeSeconds,
	}
	state.orbs[id] = orb
	state.orbCount += 1
	part.Parent = state.orbFolder
	return orb
end

-- A wave: OrbsPerWave orbs at random points, tiers by weight (golden: gold only).
local function dropWave(golden: boolean)
	for _ = 1, MinigameConfig.OrbsPerWave do
		local ground = ArenaLayout.GetDropPoint(state.rng:NextNumber(), state.rng:NextNumber())
		local tier = MinigameConfig.PickOrbTier(state.rng:NextNumber(), golden)
		spawnOrb(ground, tier.Id, nil, MinigameConfig.OrbFallSeconds, 0, nil)
	end
end

-- `points` knocked out of `p`: orbs scatter in an arc round them.
local function scatterOrbs(p: Participant, points: number, origin: Vector3)
	local ids = MinigameConfig.SplitPoints(points)
	local count = #ids
	for index, id in ids do
		local angle = (index / math.max(count, 1)) * 2 * math.pi + state.rng:NextNumber(-0.3, 0.3)
		local distance = state.rng:NextNumber(5, 12)
		local ground = Vector3.new(
			origin.X + math.cos(angle) * distance,
			ArenaLayout.CENTER.Y,
			origin.Z + math.sin(angle) * distance
		)
		-- Stay on the disc.
		local offset = Vector3.new(ground.X - ArenaLayout.CENTER.X, 0, ground.Z - ArenaLayout.CENTER.Z)
		if offset.Magnitude > ArenaLayout.PLAY_RADIUS then
			local clamped = offset.Unit * ArenaLayout.PLAY_RADIUS
			ground = Vector3.new(ArenaLayout.CENTER.X + clamped.X, ArenaLayout.CENTER.Y, ArenaLayout.CENTER.Z + clamped.Z)
		end
		spawnOrb(ground, id, origin + Vector3.new(0, 3, 0), 0.5, MinigameConfig.ScatterArmSeconds, 6)
	end
end

--[[ Ranking and awards (pure) ------------------------------------------------------------ ]]

-- Participants sorted: points high to low; a tie goes to whoever got there first.
local function ranked(): { Participant }
	local list = table.clone(state.participants)
	table.sort(list, function(a: Participant, b: Participant)
		if a.Points ~= b.Points then
			return a.Points > b.Points
		end
		if a.ReachedAt ~= b.ReachedAt then
			return a.ReachedAt < b.ReachedAt
		end
		return a.Id < b.Id
	end)
	return list
end

local function prunedPrizes(userId: number, unix: number): { number }
	local log = state.prizeLog[userId]
	if not log then
		log = {}
		state.prizeLog[userId] = log
	end
	local cutoff = unix - MinigameConfig.PrizeWindowSeconds
	for index = #log, 1, -1 do
		if log[index] <= cutoff then
			table.remove(log, index)
		end
	end
	return log
end

-- Placement prizes `userId` won in the last hour.
function MinigameService.GetPrizeCount(userId: number): number
	return #prunedPrizes(userId, state.clock())
end

-- /selftest: pretend `userId` won `count` placement prizes `ago` seconds back.
function MinigameService.SelfTestRecordPrizes(userId: number, count: number, ago: number?)
	local log = prunedPrizes(userId, state.clock())
	for _ = 1, count do
		table.insert(log, state.clock() - (ago or 0))
	end
end

function MinigameService.SelfTestClearPrizes(userId: number)
	state.prizeLog[userId] = nil
end

-- What each entry of an already-ranked list wins (entry i = place i). Pure but
-- for the prize rolls and the per-player hourly count (`counts[userId]`, how many
-- placement prizes they already won this hour; updated here). A bot or a player
-- who left wins nothing and does not push anyone up; a human below
-- MinPointsToPlace wins nothing; places 1-3 win an orb unless the hourly cap is
-- hit (then the cash); everyone else the cash.
function MinigameService.PlanAwards(entries: { RankEntry }, counts: { [number]: number }, roll: () -> number): { Award }
	local awards: { Award } = {}
	for place, entry in entries do
		local award: Award = { Kind = "None", Place = place }
		if not entry.IsBot and not entry.Left and entry.Points >= MinigameConfig.MinPointsToPlace then
			local won = counts[entry.UserId] or 0
			if place <= 3 and won < MinigameConfig.PlacementPrizesPerHour then
				award.Kind = "Orb"
				award.Tier = MinigameConfig.PickPrizeTier(place, roll())
				counts[entry.UserId] = won + 1
			else
				award.Kind = "Cash"
				award.Seconds = MinigameConfig.ParticipationIncomeSeconds
				award.Capped = place <= 3
			end
		end
		awards[place] = award
	end
	return awards
end

--[[ Bots ------------------------------------------------------------------------------------ ]]

local function botColors(): { Color3 }
	return { World.OrbBlue, World.OrbPurple, World.OrbGold, World.AccentGreen, World.AccentPink, World.AccentRival }
end

-- Builds a bot rig (yields) and puts it in the arena folder. nil if the rig failed.
local function buildBot(index: number, spawnIndex: number): Participant?
	local colors = botColors()
	local description = Instance.new("HumanoidDescription")
	local torso = colors[state.rng:NextInteger(1, #colors)]
	local legs = colors[state.rng:NextInteger(1, #colors)]
	description.HeadColor = World.CapsuleWhite
	description.TorsoColor = torso
	description.LeftArmColor = torso
	description.RightArmColor = torso
	description.LeftLegColor = legs
	description.RightLegColor = legs
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not rig or not state.botFolder then
		return nil
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local root = rig:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		rig:Destroy()
		return nil
	end
	local names = MinigameConfig.BotNames
	local name = names[state.rng:NextInteger(1, #names)]
	local skill = MinigameConfig.PickBotSkill(state.rng:NextNumber())
	local botId = state.nextBotId
	state.nextBotId += 1
	rig.Name = "RushBot" .. botId
	rig:SetAttribute("RushBot", botId)
	humanoid.DisplayName = name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	for _, humanoidState in { Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Seated } do
		humanoid:SetStateEnabled(humanoidState, false)
	end
	local head = rig:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		BillboardKit.Chip(head, {
			Name = "BotName",
			Text = name .. " · BOT",
			Gradient = UITheme.Gradients.OrbRush,
			Studs = Vector2.new(6.4, 1.2),
			StudsOffset = Vector3.new(0, 2.4, 0),
			MaxDistance = 90,
		})
	end
	rig:PivotTo(ArenaLayout.GetSpawnCFrame(spawnIndex))
	rig.Parent = state.botFolder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return {
		Id = 0,
		Name = name,
		Player = nil,
		UserId = 0,
		Model = rig,
		Points = 0,
		ReachedAt = math.huge,
		ImmuneUntil = 0,
		SpawnIndex = spawnIndex,
		Left = false,
		Skill = skill,
		Goal = nil,
		NextThink = 0,
		StunUntil = 0,
	}
end

local function botRoot(p: Participant): BasePart?
	local root = p.Model and p.Model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- One think of every bot: pick the orb the skill's rule likes (the same score as
-- MinigameConfig.SimulateRound) after its reaction time, walk to it.
local function stepBots(clockNow: number)
	for _, p in state.participants do
		local skill = p.Skill
		local root = botRoot(p)
		local humanoid = p.Model and p.Model:FindFirstChildOfClass("Humanoid")
		if skill and root and humanoid and not p.Left then
			if clockNow < p.StunUntil then
				humanoid:MoveTo(root.Position)
				continue
			end
			humanoid.WalkSpeed = skill.Speed
			local goal = if p.Goal then state.orbs[p.Goal] else nil
			if goal and clockNow < goal.LandAt then
				goal = nil
			end
			if goal == nil or clockNow >= p.NextThink then
				p.NextThink = clockNow + math.max(skill.Reaction, 0.05)
				local best: Orb? = nil
				local bestScore = -math.huge
				for _, orb in state.orbs do
					if clockNow >= orb.LandAt then
						local distance = flat(orb.Position, root.Position)
						if distance <= MinigameConfig.BotReachStuds then
							local score = MinigameConfig.ScoreOrb(skill.Greed, orb.Value, distance)
							if score > bestScore then
								best, bestScore = orb, score
							end
						end
					end
				end
				p.Goal = if best then best.Id else nil
				goal = best
			end
			if goal then
				humanoid:MoveTo(goal.Position)
			end
		end
	end
end

function MinigameService.BotOfPart(part: Instance): number?
	local current: Instance? = part
	while current and current ~= Workspace do
		local id = current:GetAttribute("RushBot")
		if typeof(id) == "number" then
			return id
		end
		current = current.Parent
	end
	return nil
end

-- A bot rig's root, by the id BotOfPart gave (nil once the round is over).
function MinigameService.GetBotRoot(botId: number): BasePart?
	for _, p in state.participants do
		if p.Model and p.Model:GetAttribute("RushBot") == botId then
			return botRoot(p)
		end
	end
	return nil
end

local function botByModelId(botId: number): Participant?
	for _, p in state.participants do
		if p.Model and p.Model:GetAttribute("RushBot") == botId then
			return p
		end
	end
	return nil
end

--[[ Hits --------------------------------------------------------------------------------------- ]]

-- A weapon hit `p`: 30% of their points scatter as orbs, 2 s immunity. Returns whether it landed.
local function hitParticipant(p: Participant, from: Vector3?): boolean
	if state.phase ~= "Play" then
		return false
	end
	local clockNow = os.clock()
	if clockNow < p.ImmuneUntil then
		return false
	end
	local origin: Vector3
	if p.Player then
		local root = getRoot(p.Player)
		if not root then
			return false
		end
		origin = root.Position
	else
		local root = botRoot(p)
		if not root then
			return false
		end
		origin = root.Position
	end
	p.ImmuneUntil = clockNow + MinigameConfig.HitImmunitySeconds
	if p.Player then
		-- CombatService reads this server-time attribute ("Immune").
		p.Player:SetAttribute("ImmuneUntil", Workspace:GetServerTimeNow() + MinigameConfig.HitImmunitySeconds)
	else
		p.StunUntil = clockNow + MinigameConfig.BotHitStunSeconds
		p.Goal = nil
	end
	local lost = MinigameConfig.ScatterPoints(p.Points)
	if lost > 0 then
		p.Points -= lost
		scatterOrbs(p, lost, origin)
	end
	return true
end

-- CombatService: `attacker` hit `target` (both in the arena). Returns whether it landed.
function MinigameService.OnPlayerHit(attacker: Player?, target: Player): boolean
	local p = participantFor(target)
	if not p or p.Left then
		return false
	end
	if attacker then
		local attackerP = participantFor(attacker)
		if not attackerP then
			return false
		end
	end
	local from = if attacker then getRoot(attacker) else nil
	return hitParticipant(p, if from then from.Position else nil)
end

-- CombatService: `attacker` hit bot `botId`'s rig.
function MinigameService.OnBotHit(attacker: Player, botId: number, from: Vector3): boolean
	if not participantFor(attacker) then
		return false
	end
	local p = botByModelId(botId)
	if not p then
		return false
	end
	local landed = hitParticipant(p, from)
	if landed then
		local root = botRoot(p)
		if root then
			local away = root.Position - from
			local flatAway = Vector3.new(away.X, 0, away.Z)
			local direction = if flatAway.Magnitude > 0.01 then flatAway.Unit else Vector3.new(0, 0, 1)
			root.AssemblyLinearVelocity = direction * 28 + Vector3.new(0, 18, 0)
		end
	end
	return landed
end

-- Whether `player` is playing right now (CombatService relaxes the Rebirth gate for them).
function MinigameService.IsPlaying(player: Player): boolean
	local p = participantFor(player)
	return p ~= nil and not p.Left and (state.phase == "Play" or state.phase == "Countdown")
end

function MinigameService.IsRoundLive(): boolean
	return state.phase == "Play"
end

--[[ Round --------------------------------------------------------------------------------------- ]]

local function setFrozen(player: Player, frozen: boolean)
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end
	if frozen then
		if not state.frozen[player.UserId] then
			state.frozen[player.UserId] = {
				WalkSpeed = humanoid.WalkSpeed,
				JumpPower = humanoid.JumpPower,
				JumpHeight = humanoid.JumpHeight,
				UseJumpPower = humanoid.UseJumpPower,
			}
		end
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		player:SetAttribute(FREEZE_ATTRIBUTE, true)
	else
		local saved = state.frozen[player.UserId]
		state.frozen[player.UserId] = nil
		-- Back to a normal walk (Speed Boots lift it again by themselves).
		humanoid.WalkSpeed = if saved and saved.WalkSpeed > 0 then saved.WalkSpeed else HeistConfig.NormalWalkSpeed
		if saved then
			humanoid.JumpPower = saved.JumpPower
			humanoid.JumpHeight = saved.JumpHeight
		end
		player:SetAttribute(FREEZE_ATTRIBUTE, nil)
	end
end

-- The arena SpawnLocations only count as spawns while a round runs (a joining
-- player with no RespawnLocation yet must never land in the arena).
local function setSpawnsEnabled(enabled: boolean)
	for _, spawn in state.spawns do
		spawn.Enabled = enabled
	end
end

-- Death in the arena puts you straight back on its spawn (not your plot).
local function armDeathReload(player: Player)
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end
	humanoid.Died:Once(function()
		task.defer(function()
			local p = participantFor(player)
			if p and not p.Left and (state.phase == "Play" or state.phase == "Countdown") and player.Parent == Players then
				local reloadable = player :: any
				reloadable:LoadCharacterAsync()
			end
		end)
	end)
end

local function arenaSpawnFor(p: Participant): CFrame
	return ArenaLayout.GetSpawnCFrame(p.SpawnIndex)
end

-- Puts a participant's character back on their spawn (fell off, reset).
local function toSpawn(p: Participant)
	local character = if p.Player then p.Player.Character else p.Model
	if character then
		character:PivotTo(arenaSpawnFor(p))
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

local function sendHome(p: Participant)
	local player = p.Player
	if not player then
		return
	end
	PlayerDataService.SetInMinigame(player, false)
	setFrozen(player, false)
	-- Back to their own plot's spawn (the RespawnLocation they had).
	local saved = state.savedSpawns[player.UserId]
	state.savedSpawns[player.UserId] = nil
	local at: CFrame? = nil
	if saved and saved.Parent then
		player.RespawnLocation = saved
		at = saved.CFrame + Vector3.new(0, 4, 0)
	else
		local plot = TycoonService.GetPlotForPlayer(player)
		local origin = plot and plot.PrimaryPart
		at = if origin then origin.CFrame * CFrame.new(0, 4, PlotLayout.SPAWN_POSITION.Z) else nil
	end
	local character = player.Character
	if character and at then
		character:PivotTo(at)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

-- The live standings for the clients: top 3 and every human's own line.
local function sendScores(final: boolean?)
	local list = ranked()
	local top: { { [string]: any } } = {}
	for index = 1, math.min(3, #list) do
		local p = list[index]
		table.insert(top, { Name = p.Name, Points = p.Points, Bot = p.Player == nil, UserId = p.UserId })
	end
	local clockNow = os.clock()
	local golden = clockNow >= state.endsAt - state.timing.Golden
	for index, p in list do
		if p.Player and not p.Left then
			sendTo(p.Player, {
				Kind = "Scores",
				Top = top,
				Points = p.Points,
				Place = index,
				Players = #list,
				TimeLeft = math.max(0, state.endsAt - clockNow),
				Golden = golden,
				Final = final == true,
			})
		end
	end
	-- The tower in the middle.
	for faceIndex, labels in state.towerLabels do
		local row = (faceIndex - 1) % 3 + 1
		local p = list[row]
		labels.Name.Text = if p then ("%d. %s"):format(row, p.Name) else ("%d."):format(row)
		labels.Points.Text = if p then tostring(p.Points) else ""
	end
end

local function removeParticipantsOrbs(p: Participant)
	local root = if p.Player then getRoot(p.Player) else botRoot(p)
	if root and p.Points > 0 then
		local lost = p.Points
		p.Points = 0
		scatterOrbs(p, lost, root.Position)
	end
end

-- A human left mid-round (or the server is closing): their orbs scatter, no prize.
local function humanLeft(player: Player)
	local p = participantFor(player)
	if p and not p.Left and (state.phase == "Play" or state.phase == "Countdown") then
		if state.phase == "Play" then
			removeParticipantsOrbs(p)
		end
		p.Left = true
	end
	MinigameService.Leave(player)
	state.savedSpawns[player.UserId] = nil
	state.frozen[player.UserId] = nil
end

-- Runs the whole round: bots, the teleport, the countdown, play, results. Yields.
-- `token` is state.roundToken at the call; a newer round invalidates this one.
local function playRound(token: number)
	local queued = table.clone(state.queue)
	state.queue = {}
	Workspace:SetAttribute("OrbRushQueued", 0)
	local players: { Player } = {}
	for _, player in queued do
		player:SetAttribute("OrbRushQueued", nil)
		if
			player.Parent == Players
			and PlayerDataService.IsDataLoaded(player)
			and not PlayerDataService.IsCarrying(player)
			and not PlayerDataService.IsInMinigame(player)
			and getRoot(player)
			and #players < MinigameConfig.MaxPlayers
		then
			table.insert(players, player)
		end
	end
	if #players == 0 then
		setPhase("Idle")
		return
	end

	-- The roster: humans, then bots up to FillTo, each on its own spawn (shuffled).
	local spawnOrder: { number } = {}
	for index = 1, ArenaLayout.SPAWN_COUNT do
		table.insert(spawnOrder, index)
	end
	for index = #spawnOrder, 2, -1 do
		local other = state.rng:NextInteger(1, index)
		spawnOrder[index], spawnOrder[other] = spawnOrder[other], spawnOrder[index]
	end
	state.participants = {}
	local nextSeat = 1
	for _, player in players do
		table.insert(state.participants, {
			Id = nextSeat,
			Name = player.DisplayName,
			Player = player,
			UserId = player.UserId,
			Model = nil,
			Points = 0,
			ReachedAt = math.huge,
			ImmuneUntil = 0,
			SpawnIndex = spawnOrder[nextSeat],
			Left = false,
			Skill = nil,
			Goal = nil,
			NextThink = 0,
			StunUntil = 0,
		})
		nextSeat += 1
	end
	setPhase("Countdown") -- (the roster is set; bots build next)
	local botsWanted = math.max(0, MinigameConfig.FillTo - #players)
	for _ = 1, botsWanted do
		local bot = buildBot(nextSeat, spawnOrder[nextSeat])
		if bot then
			bot.Id = nextSeat
			table.insert(state.participants, bot)
			nextSeat += 1
		end
	end
	if state.roundToken ~= token then
		return
	end

	-- The teleport. Each human is in the arena (IsInMinigame) from here: no pulls etc.
	local countdown = state.timing.Countdown
	setSpawnsEnabled(true)
	for _, p in state.participants do
		local player = p.Player
		if player then
			state.savedSpawns[player.UserId] = player.RespawnLocation
			PlayerDataService.SetInMinigame(player, true)
			local spawnPart = state.spawns[p.SpawnIndex]
			if spawnPart then
				player.RespawnLocation = spawnPart
			end
			task.spawn(function()
				pcall(function()
					player:RequestStreamAroundAsync(ArenaLayout.GetSpawnCFrame(p.SpawnIndex).Position, SPAWN_STREAM_SECONDS)
				end)
			end)
			local character = player.Character
			if character then
				character:PivotTo(arenaSpawnFor(p))
			end
			setFrozen(player, true)
			armDeathReload(player)
		end
	end
	state.goAt = os.clock() + countdown
	state.endsAt = state.goAt + state.timing.Round
	state.goldenSent = false
	local goServerAt = Workspace:GetServerTimeNow() + countdown
	local roster: { { [string]: any } } = {}
	for _, p in state.participants do
		table.insert(roster, { Name = p.Name, UserId = p.UserId, Bot = p.Player == nil })
	end
	for _, p in humans() do
		AnalyticsKit.Custom(p.Player :: Player, "OrbRushPlayed", #players)
		AnalyticsKit.Funnel(p.Player :: Player, "FirstOrbRush")
	end
	sendToHumans({
		Kind = "Start",
		GoAt = goServerAt,
		EndsAt = goServerAt + state.timing.Round,
		Countdown = countdown,
		Round = state.timing.Round,
		Golden = state.timing.Golden,
		Roster = roster,
	})
	sendScores()
	while os.clock() < state.goAt and state.roundToken == token do
		task.wait(0.1)
	end
	if state.roundToken ~= token then
		return
	end

	-- GO.
	for _, p in humans() do
		setFrozen(p.Player :: Player, false)
	end
	setPhase("Play")
	local nextWave = os.clock() + 0.2
	local nextBot = os.clock()
	local nextScores = 0.0
	while state.roundToken == token do
		local clockNow = os.clock()
		if clockNow >= state.endsAt then
			break
		end
		if #humans() == 0 then
			break -- everyone left: the bots stop
		end
		local golden = clockNow >= state.endsAt - state.timing.Golden
		if golden and not state.goldenSent then
			state.goldenSent = true
			sendToHumans({ Kind = "Golden" })
		end
		if clockNow >= nextWave then
			dropWave(golden)
			nextWave = clockNow + MinigameConfig.WaveSeconds / (if golden then MinigameConfig.GoldenWaveRateMultiplier else 1)
		end
		-- Expire old orbs.
		for _, orb in table.clone(state.orbs) do
			if clockNow >= orb.ExpiresAt then
				destroyOrb(orb)
			end
		end
		-- Pickups (server distance check against the character root).
		for _, p in state.participants do
			if p.Left then
				continue
			end
			local root = if p.Player then getRoot(p.Player) else botRoot(p)
			if not root then
				continue
			end
			-- Off the disc (fell, was thrown): back to the spawn, points intact.
			if root.Position.Y < ArenaLayout.CENTER.Y - ArenaLayout.FALL_BELOW then
				toSpawn(p)
				continue
			end
			local taken = 0
			for _, orb in table.clone(state.orbs) do
				if taken >= MinigameConfig.PickupsPerTick then
					break
				end
				if
					clockNow >= orb.LandAt
					and flat(orb.Position, root.Position) <= MinigameConfig.PickupRadius
					and math.abs(orb.Position.Y - root.Position.Y) <= 8
				then
					taken += 1
					p.Points += orb.Value
					p.ReachedAt = clockNow
					if p.Player then
						sendTo(p.Player, { Kind = "Pickup", Value = orb.Value, Tier = orb.Tier, Position = orb.Position, Points = p.Points })
					end
					destroyOrb(orb)
				end
			end
		end
		if clockNow >= nextBot then
			nextBot = clockNow + MinigameConfig.BotThinkSeconds
			stepBots(clockNow)
		end
		if clockNow >= nextScores then
			nextScores = clockNow + 0.25
			sendScores()
		end
		task.wait(MinigameConfig.TickSeconds)
	end
	if state.roundToken ~= token then
		return
	end

	-- Results.
	setPhase("Results")
	clearOrbs()
	sendScores(true)
	task.wait(state.timing.Hold)
	local order = ranked()
	local entries: { RankEntry } = {}
	for _, p in order do
		table.insert(entries, { IsBot = p.Player == nil, UserId = p.UserId, Points = p.Points, Left = p.Left })
	end
	local unix = state.clock()
	local counts: { [number]: number } = {}
	for _, p in order do
		if p.Player then
			counts[p.UserId] = #prunedPrizes(p.UserId, unix)
		end
	end
	local awards = MinigameService.PlanAwards(entries, counts, function()
		return state.rng:NextNumber()
	end)
	local podium: { { [string]: any } } = {}
	for place = 1, math.min(3, #order) do
		local p = order[place]
		table.insert(podium, { Place = place, Name = p.Name, Points = p.Points, Bot = p.Player == nil, UserId = p.UserId })
	end
	local nextCall = MinigameConfig.GetRoundForSlot(MinigameConfig.GetSlot(unix))
	if nextCall.CallAt <= unix then
		nextCall = MinigameConfig.GetRoundForSlot(nextCall.Slot + 1)
	end
	for place, p in order do
		local player = p.Player
		if player and not p.Left then
			sendHome(p)
		end
		if player and not p.Left and player.Parent == Players then
			local award = awards[place]
			local cash = 0
			if award.Kind == "Cash" then
				local inputs = PlayerDataService.GetIncomeInputs(player)
				if inputs then
					cash = math.max(0, TycoonConfig.GetPassiveCashPerSecond(inputs) * (award.Seconds or 0))
				end
			end
			sendTo(player, {
				Kind = "Results",
				Podium = podium,
				Place = place,
				Players = #order,
				Points = p.Points,
				Prize = if award.Kind == "Orb" then award.Tier else nil,
				Cash = if cash > 0 then cash else nil,
				Capped = award.Capped,
				NextAt = nextCall.CallAt,
			})
		end
	end
	-- Paying out after the cards are on their way.
	task.wait(0.4)
	for place, p in order do
		local player = p.Player
		local award = awards[place]
		if player and not p.Left and player.Parent == Players and PlayerDataService.IsDataLoaded(player) then
			AnalyticsKit.Custom(player, "OrbRushPlace", place)
			if award.Kind == "Orb" and award.Tier then
				table.insert(prunedPrizes(p.UserId, unix), unix)
				local caption = ("🏆 ORB RUSH · %s"):format(({ "1ST", "2ND", "3RD" })[place] or "")
				if not TycoonService.GrantRewardItem(player, award.Tier, caption) then
					local def = ItemConfig.PickRandomOfTier(award.Tier, state.rng)
					if def then
						PlayerDataService.AddItem(player, def.Id, def.Tier, nil, nil)
						PlayerDataService.SyncTycoon(player)
					end
				end
				AnalyticsKit.Custom(player, "OrbRushPrize", nil, award.Tier)
			elseif award.Kind == "Cash" then
				local inputs = PlayerDataService.GetIncomeInputs(player)
				if inputs then
					local cash = TycoonConfig.GetPassiveCashPerSecond(inputs) * (award.Seconds or 0)
					if cash > 0 then
						PlayerDataService.AddCash(player, cash)
					end
				end
			end
		end
	end
	state.lastResults = { Podium = podium, Awards = awards, Order = entries }
	-- Clean up.
	for _, p in state.participants do
		if p.Model then
			p.Model:Destroy()
		end
	end
	local finished = state.participants
	state.participants = {}
	if state.botFolder then
		state.botFolder:ClearAllChildren()
	end
	state.endsAt = 0
	state.goAt = 0
	setSpawnsEnabled(false)
	for _, p in finished do
		if p.Player then
			p.Player:SetAttribute(FREEZE_ATTRIBUTE, nil)
		end
	end
	setPhase("Idle")
end

--[[ Scheduler ------------------------------------------------------------------------------------ ]]

local function beginCall(round: MinigameConfig.Round, startAt: number)
	state.round = { Slot = round.Slot, CallAt = round.CallAt, StartAt = startAt }
	state.lastCallSlot = round.Slot
	for _, player in state.queue do
		player:SetAttribute("OrbRushQueued", nil)
	end
	state.queue = {}
	state.lastResults = nil
	setPhase("Call")
end

local function schedulerStep()
	local unix = state.clock()
	if state.phase == "Idle" then
		local forced = state.forcedCallUntil
		if forced and unix < forced then
			state.forcedCallUntil = nil
			beginCall({ Slot = -1, CallAt = unix, StartAt = forced }, forced)
			return
		end
		local round = MinigameConfig.GetRoundForSlot(MinigameConfig.GetSlot(unix))
		if unix >= round.CallAt and unix < round.StartAt and state.lastCallSlot ~= round.Slot then
			beginCall(round, round.StartAt)
		else
			publish()
			updatePortal()
		end
	elseif state.phase == "Call" then
		local round = state.round
		if round and unix >= round.StartAt then
			state.roundToken += 1
			local token = state.roundToken
			setPhase("Countdown")
			task.spawn(function()
				local ok, err = pcall(function(): string?
					playRound(token)
					return nil
				end)
				if not ok then
					warn("MinigameService: round failed - " .. tostring(err))
					MinigameService.AbortRound()
				end
			end)
		else
			publish()
			updatePortal()
		end
	end
end

-- Ends everything now and puts people back (an error, a shutdown, /selftest).
function MinigameService.AbortRound()
	state.roundToken += 1
	clearOrbs()
	for _, p in state.participants do
		if p.Player then
			sendHome(p)
		end
		if p.Model then
			p.Model:Destroy()
		end
	end
	state.participants = {}
	setSpawnsEnabled(false)
	if state.botFolder then
		state.botFolder:ClearAllChildren()
	end
	for _, player in state.queue do
		player:SetAttribute("OrbRushQueued", nil)
	end
	state.queue = {}
	state.forcedCallUntil = nil
	setPhase("Idle")
end

--[[ Studio + /selftest ------------------------------------------------------------------------------ ]]

function MinigameService.GetPhase(): Phase
	return state.phase
end

-- Studio /orbrush now: queue `players`, skip the call and start a round at once.
-- `timing` (optional) shortens it for /selftest. The caller waits for GetPhase() == "Idle".
function MinigameService.DebugStartNow(players: { Player }, timing: { Countdown: number?, Round: number?, Golden: number?, Hold: number? }?)
	if state.phase ~= "Idle" then
		return false
	end
	if timing then
		local base = defaultTiming()
		state.timing = {
			Countdown = timing.Countdown or base.Countdown,
			Round = timing.Round or base.Round,
			Golden = timing.Golden or base.Golden,
			Hold = timing.Hold or base.Hold,
		}
	end
	local unix = state.clock()
	state.lastResults = nil
	state.round = { Slot = -1, CallAt = unix, StartAt = unix }
	setPhase("Call")
	for _, player in players do
		MinigameService.TryQueue(player)
	end
	state.round = { Slot = -1, CallAt = unix, StartAt = unix }
	state.roundToken += 1
	local token = state.roundToken
	task.spawn(function()
		local ok, err = pcall(function(): string?
			playRound(token)
			return nil
		end)
		if not ok then
			warn("MinigameService: debug round failed - " .. tostring(err))
			MinigameService.AbortRound()
		end
		state.timing = defaultTiming()
	end)
	return true
end

-- Studio /orbrush call [seconds]: open a call window now (the queue closes after `seconds`).
function MinigameService.DebugCall(seconds: number)
	if state.phase ~= "Idle" then
		return false
	end
	local unix = state.clock()
	state.forcedCallUntil = unix + math.max(5, seconds)
	state.round = { Slot = -1, CallAt = unix, StartAt = unix + math.max(5, seconds) }
	return true
end

function MinigameService.SetClock(clock: (() -> number)?)
	state.clock = clock or unixNow
end

function MinigameService.SetRandom(rng: Random?)
	state.rng = rng or Random.new()
end

function MinigameService.GetParticipantCount(): (number, number)
	local humanCount, botCount = 0, 0
	for _, p in state.participants do
		if p.Player then
			humanCount += 1
		else
			botCount += 1
		end
	end
	return humanCount, botCount
end

-- /selftest: the score of `player` (nil when not in the round), and adding points.
function MinigameService.GetPoints(player: Player): number?
	local p = participantFor(player)
	return if p then p.Points else nil
end

function MinigameService.SelfTestAddPoints(player: Player, points: number)
	local p = participantFor(player)
	if p then
		p.Points += points
		p.ReachedAt = os.clock()
	end
end

function MinigameService.GetLastResults(): { [string]: any }?
	return state.lastResults
end

function MinigameService.GetOrbCount(): number
	return state.orbCount
end

function MinigameService.GetArenaFolder(): Folder?
	return state.arena
end

function MinigameService.GetPortalTrigger(): BasePart?
	return state.portalTrigger
end

-- /selftest: touch the portal as `player` would (the same handler).
function MinigameService.SelfTestEnterPortal(player: Player)
	local root = getRoot(player)
	if root then
		state.touchDebounce[player.UserId] = nil
		onPortalTouched(root)
	end
end

-- /selftest: a stand-in cannot touch; just the pure award planner and the prize log helpers above.

-- /selftest: the live roster as { Name, Bot, Points, SpawnIndex }.
function MinigameService.GetRoster(): { { Name: string, Bot: boolean, Points: number, SpawnIndex: number, Skill: string? } }
	local list = {}
	for _, p in state.participants do
		table.insert(list, { Name = p.Name, Bot = p.Player == nil, Points = p.Points, SpawnIndex = p.SpawnIndex, Skill = if p.Skill then p.Skill.Id else nil })
	end
	return list
end

--[[ Lifecycle ---------------------------------------------------------------------------------------- ]]

function MinigameService:Init()
	RemoteEvents.MinigameQueue.OnServerEvent:Connect(onQueueRequest)
	table.insert(
		state.connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			humanLeft(player)
			state.touchDebounce[player.UserId] = nil
			state.prizeLog[player.UserId] = nil
		end)
	)
end

function MinigameService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)
	HeistService = require(script.Parent.HeistService)

	buildArena()
	buildPortal()
	local trigger = state.portalTrigger
	if trigger then
		table.insert(state.connections, trigger.Touched:Connect(onPortalTouched))
	end
	-- A character that respawns in the arena (reset / fell): on its spawn, frozen
	-- if the countdown is still running, and the next death reloads it there too.
	local function hookPlayer(player: Player)
		table.insert(
			state.connections,
			player.CharacterAdded:Connect(function()
				local p = participantFor(player)
				if p and not p.Left and (state.phase == "Play" or state.phase == "Countdown") then
					task.defer(function()
						toSpawn(p)
						if state.phase == "Countdown" then
							setFrozen(player, true)
						end
						armDeathReload(player)
					end)
				end
			end)
		)
	end
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	table.insert(state.connections, Players.PlayerAdded:Connect(hookPlayer))
	-- Hold the player's leave-time save until the round has forgotten them.
	PlayerDataService.OnRelease(function(player: Player)
		humanLeft(player)
	end)

	state.running = true
	setPhase("Idle")
	task.spawn(function()
		while state.running do
			local ok, err = pcall(function(): string?
				schedulerStep()
				return nil
			end)
			if not ok then
				warn("MinigameService: scheduler failed - " .. tostring(err))
			end
			task.wait(0.25)
		end
	end)
end

function MinigameService:Stop()
	state.running = false
	MinigameService.AbortRound()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
end

return MinigameService
