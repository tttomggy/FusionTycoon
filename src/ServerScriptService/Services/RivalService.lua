--!strict
--[[
	RivalService
	------------
	Rival labs: NPC-owned labs in plot slots no player owns, so a brand-new
	player can steal from minute 3 even in an empty server (numbers in
	RivalConfig; the steal itself is HeistService's, same grab / carry /
	deliver flow).

	Labs
	  * Up to RivalConfig.MaxRivals, in the free slots nearest to the real
	    players' labs. Built by TycoonService.BuildRivalPlot (the player plot
	    code: shell, walls, sign gate, pedestals; no generators, stations or
	    Fusion Machine, no owner). Slots are TycoonService's table: a real
	    player is never refused a plot because of a rival. With no slot free
	    TycoonService calls DespawnFarthest (registered in :Start), and the
	    lab farthest from every player's lab goes first; a carry from it
	    fails cleanly (HeistService.FailRivalCarries) before the plot goes.
	  * Orbs are server objects (every client sees the same ones): plain,
	    one RivalConfig.GoldenChance Golden, rolled from the weights of the
	    LOWEST Rebirth count among the real players (RivalConfig.PickTier), so
	    a new player never sees a Mythic. If that lowest count drops (a new
	    player joins) the orbs rolled for a higher band are re-rolled.
	  * A stolen orb comes back after RivalConfig.RespawnSeconds (the
	    respawn clock is injectable: SetClock, /selftest).

	Guard
	  * One blocky R15 NPC per lab (HumanoidDescription rig), server-side. It
	    patrols the lab; HeistService calls BeginCarry on a grab and it
	    chases the carrier at RivalConfig.GuardSpeed along PathfindingService
	    paths (recomputed at most every GuardPathSeconds), gives up GuardLeash
	    studs past its gate and walks home. HeistService owns the tag: the
	    guard within HeistConfig.TagDistance of the carrier sends the orb back.
	  * Weapons work on it like on a player (CombatService -> StunGuard): it
	    falls over for GuardStunSeconds, can't tag, and loses the chase.
	  * ONE guard loop per server.

	Rivals never steal, never appear in leaderboards, friend counts, the
	notification queue or analytics player counts (they are not Players).

	Follows ServiceTemplate:
	  :Init()   own state only.
	  :Start()  resolves PlayerDataService and TycoonService, registers the
	            slot reclaimer, starts the fill loop and the guard loop.
	            (HeistService requires this service, not the other way
	            round: it registers an OnDespawn hook.)
]]
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local RivalConfig = require(ReplicatedStorage.Shared.Config.RivalConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))

export type Orb = {
	ItemId: string,
	Tier: string,
	Mutation: string?,
	Name: string,
	Rate: number, -- $/s the label shows
}

type PedestalState = {
	Orb: Orb?,
	Carried: boolean,
	RespawnAt: number?, -- RivalService clock time a stolen orb is back
	Band: number, -- the band the orb was rolled for
}

type GuardMode = "Patrol" | "Chase" | "Home"

type Guard = {
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Mode: GuardMode,
	Target: Player?,
	StunUntil: number,
	Stunned: boolean,
	PatrolIndex: number,
	PauseUntil: number,
	Waypoints: { PathWaypoint },
	WaypointIndex: number,
	PathPending: boolean,
	LastPathAt: number,
	WalkTrack: AnimationTrack?,
	IdleTrack: AnimationTrack?,
}

type Rival = {
	Id: number,
	Name: string,
	SlotIndex: number,
	Plot: Model,
	Origin: CFrame,
	Pedestals: { [number]: PedestalState },
	Guard: Guard?,
}

-- What other services see of a rival lab.
export type RivalView = {
	Id: number,
	Name: string,
	SlotIndex: number,
	Plot: Model,
	Origin: CFrame,
}

type State = {
	rivals: { [number]: Rival },
	nextId: number,
	nameSerial: number,
	clock: () -> number,
	rng: Random,
	running: boolean,
	guardAccumulator: number,
	connections: { RBXScriptConnection },
	-- Called with a rival's id just before it goes (HeistService fails its carries).
	despawnHooks: { (number) -> () },
}

--[[ Private state -------------------------------------------------------- ]]

-- Unix seconds. The respawn clock and the hourly limit use it so a saved
-- rival-steal time means the same in another server or after a rejoin.
local function wallClock(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local state: State = {
	rivals = {},
	nextId = 1,
	nameSerial = 0,
	clock = wallClock,
	rng = Random.new(),
	running = false,
	guardAccumulator = 0,
	connections = {},
	despawnHooks = {},
}

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule

local RivalService = {}

RivalService.Name = "RivalService"

local World = UITheme.World

-- The default R15 locomotion clips (the same ids the stock Animate script uses).
local WALK_ANIMATION = "rbxassetid://507777826"
local IDLE_ANIMATION = "rbxassetid://507766666"
local GUARD_KNOCKBACK = 40
local GUARD_KICK = 25
local GUARD_DISPLAY_NAME = "Lab Guard"

--[[ Small helpers ------------------------------------------------------------- ]]

local function now(): number
	return state.clock()
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getPedestal(rival: Rival, index: number): BasePart?
	local folder = rival.Plot:FindFirstChild("Pedestals")
	local pedestal = folder and folder:FindFirstChild("Pedestal" .. index)
	return if pedestal and pedestal:IsA("BasePart") then pedestal else nil
end

-- Where the lab's gate is (the guard's leash is measured from it).
local function gateWorld(rival: Rival): Vector3
	return rival.Origin:PointToWorldSpace(Vector3.new(0, 0, PlotLayout.PLOT_HALF))
end

local function view(rival: Rival): RivalView
	return {
		Id = rival.Id,
		Name = rival.Name,
		SlotIndex = rival.SlotIndex,
		Plot = rival.Plot,
		Origin = rival.Origin,
	}
end

--[[ Orbs ----------------------------------------------------------------------- ]]

-- The lowest Rebirth count among the real players (0 with nobody in).
function RivalService.GetLowestRebirths(): number
	local lowest: number? = nil
	for _, player in Players:GetPlayers() do
		if PlayerDataService.IsDataLoaded(player) then
			local rebirths = PlayerDataService.GetRebirths(player)
			lowest = if lowest == nil then rebirths else math.min(lowest, rebirths)
		end
	end
	return lowest or 0
end

-- One rival orb for `band`: never a banned tier, plain, one GoldenChance
-- Golden. Pure but for the RNG (injectable: SetRandom).
function RivalService.RollOrb(band: number): Orb
	local tier = RivalConfig.PickTier(band, state.rng:NextNumber())
	local def = ItemConfig.PickRandomOfTier(tier, state.rng) or ItemConfig.Items[1]
	local mutation: string? = if state.rng:NextNumber() < RivalConfig.GoldenChance then "Golden" else nil
	return {
		ItemId = def.Id,
		Tier = def.Tier,
		Mutation = mutation,
		Name = MutationConfig.GetDisplayName(def.Name, mutation, nil),
		Rate = TycoonConfig.GetItemCashPerSecond(def.Tier, MutationConfig.List(mutation, nil)),
	}
end

-- Draws the pedestal for what the state says: the orb, the stolen ghost
-- (carried) or bare (empty). No EMPTY pill: a rival lab has no owner.
local function showPedestal(rival: Rival, index: number)
	local pedestal = getPedestal(rival, index)
	local ped = rival.Pedestals[index]
	if not pedestal or not ped then
		return
	end
	local orb = ped.Orb
	if orb then
		if ped.Carried then
			PedestalVisuals.SetStolen(pedestal)
		else
			PedestalVisuals.Apply(pedestal, orb.Tier, orb.Mutation, nil)
		end
		BillboardKit.SetPedestalLabel(pedestal, {
			Tier = orb.Tier,
			Mutation = orb.Mutation,
			ItemName = orb.Name,
			Rate = orb.Rate,
			Stolen = ped.Carried,
		})
		local stealLabel = ("%s · +%s/s"):format(orb.Name, NumberFormat.Money(orb.Rate))
		pedestal:SetAttribute("StealLabel", stealLabel)
		local steal = pedestal:FindFirstChild("StealPrompt")
		if steal and steal:IsA("ProximityPrompt") then
			steal.ObjectText = stealLabel
		end
		-- For the client's "best pedestal" (the tipRival arrows).
		pedestal:SetAttribute("OrbTier", orb.Tier)
	else
		PedestalVisuals.Clear(pedestal)
		BillboardKit.SetPedestalLabel(pedestal, nil)
		local filled = pedestal:FindFirstChild("FilledLabel")
		local empty = pedestal:FindFirstChild("EmptyLabel")
		if filled and filled:IsA("BillboardGui") then
			filled.Enabled = false
		end
		if empty and empty:IsA("BillboardGui") then
			empty.Enabled = false
		end
		pedestal:SetAttribute("StealLabel", "")
		pedestal:SetAttribute("OrbTier", nil)
		local steal = pedestal:FindFirstChild("StealPrompt")
		if steal and steal:IsA("ProximityPrompt") then
			steal.ObjectText = ""
		end
	end
	pedestal:SetAttribute("Filled", orb ~= nil)
	pedestal:SetAttribute("BeingStolen", ped.Carried)
end

local function fillPedestal(rival: Rival, index: number, band: number)
	local ped = rival.Pedestals[index]
	if not ped then
		return
	end
	ped.Orb = RivalService.RollOrb(band)
	ped.Band = band
	ped.Carried = false
	ped.RespawnAt = nil
	showPedestal(rival, index)
end

--[[ Guard ------------------------------------------------------------------------ ]]

local function guardColors(): { [string]: Color3 }
	return {
		Head = World.CapsuleWhite,
		Torso = World.AccentRival,
		Arms = World.AccentRival,
		Legs = World.Structure,
	}
end

local function describeGuard(): HumanoidDescription
	local colors = guardColors()
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = colors.Head
	description.TorsoColor = colors.Torso
	description.LeftArmColor = colors.Arms
	description.RightArmColor = colors.Arms
	description.LeftLegColor = colors.Legs
	description.RightLegColor = colors.Legs
	return description
end

local function loadTrack(humanoid: Humanoid, id: string, looped: boolean): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = looped
		return track
	end
	return nil
end

-- Builds the rival's guard (yields: the rig comes from a HumanoidDescription),
-- unless the lab went in the meantime. A failed rig leaves the lab guardless.
local function buildGuard(rival: Rival)
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(describeGuard(), Enum.HumanoidRigType.R15)
	end)
	if not ok or not rig then
		warn(("RivalService: no guard rig for %s (%s)"):format(rival.Name, tostring(rig)))
		return
	end
	if state.rivals[rival.Id] ~= rival or rival.Plot.Parent == nil then
		rig:Destroy()
		return
	end
	rig.Name = "LabGuard"
	local root = rig:FindFirstChild("HumanoidRootPart")
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		rig:Destroy()
		return
	end
	humanoid.DisplayName = GUARD_DISPLAY_NAME
	humanoid.WalkSpeed = RivalConfig.GuardPatrolSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	rig:SetAttribute("RivalGuard", rival.Id)
	local home = rival.Origin:PointToWorldSpace(RivalConfig.GuardHome + Vector3.new(0, 3, 0))
	rig:PivotTo(CFrame.new(home) * rival.Origin.Rotation)
	rig.Parent = rival.Plot
	pcall(function()
		root:SetNetworkOwner(nil) -- the server drives it; no player's client can
	end)
	local guard: Guard = {
		Model = rig,
		Root = root,
		Humanoid = humanoid,
		Mode = "Patrol",
		Target = nil,
		StunUntil = 0,
		Stunned = false,
		PatrolIndex = 1,
		PauseUntil = 0,
		Waypoints = {},
		WaypointIndex = 1,
		PathPending = false,
		LastPathAt = -math.huge,
		WalkTrack = loadTrack(humanoid, WALK_ANIMATION, true),
		IdleTrack = loadTrack(humanoid, IDLE_ANIMATION, true),
	}
	if guard.IdleTrack then
		guard.IdleTrack:Play()
	end
	rival.Guard = guard
end

local function setMoving(guard: Guard, moving: boolean)
	local walk, idle = guard.WalkTrack, guard.IdleTrack
	if moving then
		if walk and not walk.IsPlaying then
			walk:Play()
		end
		if idle and idle.IsPlaying then
			idle:Stop()
		end
	else
		if idle and not idle.IsPlaying then
			idle:Play()
		end
		if walk and walk.IsPlaying then
			walk:Stop()
		end
	end
end

-- Asks PathfindingService for a path to `target` without yielding the guard
-- loop; the waypoints land in guard.Waypoints when it returns.
local function requestPath(guard: Guard, target: Vector3)
	if guard.PathPending then
		return
	end
	guard.PathPending = true
	guard.LastPathAt = os.clock()
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local from = guard.Root.Position
		local ok = pcall(function()
			path:ComputeAsync(from, target)
		end)
		guard.PathPending = false
		if ok and path.Status == Enum.PathStatus.Success then
			guard.Waypoints = path:GetWaypoints()
			guard.WaypointIndex = if #guard.Waypoints > 1 then 2 else 1
		else
			guard.Waypoints = {}
			guard.WaypointIndex = 1
		end
	end)
end

-- Moves along the last computed path toward `fallback` (the straight line
-- when there is no path).
local function followPath(guard: Guard, fallback: Vector3)
	local waypoint = guard.Waypoints[guard.WaypointIndex]
	if waypoint then
		if flatDistance(guard.Root.Position, waypoint.Position) < RivalConfig.GuardWaypointReach then
			guard.WaypointIndex += 1
			waypoint = guard.Waypoints[guard.WaypointIndex]
		end
	end
	if waypoint then
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			guard.Humanoid.Jump = true
		end
		guard.Humanoid:MoveTo(waypoint.Position)
	else
		guard.Humanoid:MoveTo(fallback)
	end
end

local function recoverGuard(guard: Guard)
	guard.Stunned = false
	guard.Humanoid.PlatformStand = false
	-- Back on its feet: keep the facing, drop the tumble.
	local position = guard.Root.Position
	local look = guard.Root.CFrame.LookVector
	guard.Root.AssemblyAngularVelocity = Vector3.zero
	guard.Root.CFrame = CFrame.lookAt(position + Vector3.new(0, 2, 0), position + Vector3.new(look.X, 2, look.Z))
	guard.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

local function guardStep(rival: Rival)
	local guard = rival.Guard
	if not guard or guard.Root.Parent == nil then
		return
	end
	local t = os.clock() -- the guard runs on the real clock (SetClock is for orbs and limits)
	if t < guard.StunUntil then
		setMoving(guard, false)
		return
	end
	if guard.Stunned then
		recoverGuard(guard)
	end
	local humanoid = guard.Humanoid
	local position = guard.Root.Position

	if guard.Mode == "Chase" then
		local target = guard.Target
		local targetRoot = if target and target.Parent then getRoot(target) else nil
		if not targetRoot or flatDistance(position, gateWorld(rival)) > RivalConfig.GuardLeash then
			-- Gone, or too far from home: give up and walk back.
			guard.Mode = "Home"
			guard.Target = nil
			guard.Waypoints = {}
		else
			humanoid.WalkSpeed = RivalConfig.GuardSpeed
			if t - guard.LastPathAt >= RivalConfig.GuardPathSeconds then
				requestPath(guard, targetRoot.Position)
			end
			followPath(guard, targetRoot.Position)
			setMoving(guard, true)
			return
		end
	end

	humanoid.WalkSpeed = RivalConfig.GuardPatrolSpeed
	if guard.Mode == "Home" then
		local home = rival.Origin:PointToWorldSpace(RivalConfig.GuardHome)
		if flatDistance(position, home) <= RivalConfig.GuardWaypointReach + 1 then
			guard.Mode = "Patrol"
			guard.PauseUntil = t + RivalConfig.GuardPatrolPauseSeconds
		else
			if t - guard.LastPathAt >= RivalConfig.GuardPathSeconds * 4 then
				requestPath(guard, home)
			end
			followPath(guard, home)
			setMoving(guard, true)
		end
		return
	end

	-- Patrol: the stops in front of the pedestals, a short pause at each.
	if t < guard.PauseUntil then
		setMoving(guard, false)
		return
	end
	local points = RivalConfig.PatrolPoints
	local stop = rival.Origin:PointToWorldSpace(points[guard.PatrolIndex])
	if flatDistance(position, stop) <= RivalConfig.GuardWaypointReach then
		guard.PatrolIndex = guard.PatrolIndex % #points + 1
		guard.PauseUntil = t + RivalConfig.GuardPatrolPauseSeconds
		setMoving(guard, false)
	else
		humanoid:MoveTo(Vector3.new(stop.X, position.Y, stop.Z))
		setMoving(guard, true)
	end
end

--[[ Public API: labs ------------------------------------------------------------ ]]

function RivalService.GetRivals(): { RivalView }
	local list: { RivalView } = {}
	for _, rival in state.rivals do
		table.insert(list, view(rival))
	end
	table.sort(list, function(a: RivalView, b: RivalView)
		return a.Id < b.Id
	end)
	return list
end

function RivalService.GetRival(rivalId: number): RivalView?
	local rival = state.rivals[rivalId]
	return if rival then view(rival) else nil
end

function RivalService.GetPedestal(rivalId: number, index: number): BasePart?
	local rival = state.rivals[rivalId]
	return if rival then getPedestal(rival, index) else nil
end

-- The orb standing on the pedestal right now (nil: empty, or being carried).
function RivalService.GetOrb(rivalId: number, index: number): Orb?
	local rival = state.rivals[rivalId]
	local ped = rival and rival.Pedestals[index]
	if ped and ped.Orb and not ped.Carried then
		return ped.Orb
	end
	return nil
end

-- A pedestal that holds an orb a thief is carrying.
function RivalService.IsCarried(rivalId: number, index: number): boolean
	local rival = state.rivals[rivalId]
	local ped = rival and rival.Pedestals[index]
	return ped ~= nil and ped.Carried
end

-- When a stolen orb is back (RivalService clock time), nil if not waiting.
function RivalService.GetRespawnAt(rivalId: number, index: number): number?
	local rival = state.rivals[rivalId]
	local ped = rival and rival.Pedestals[index]
	return if ped then ped.RespawnAt else nil
end

function RivalService.Now(): number
	return now()
end

-- /selftest: a controllable clock (unix seconds) for the 90 s respawn and
-- the hourly limit (nil puts the wall clock back; the guard always runs on
-- os.clock), and a seeded RNG for the orb rolls.
function RivalService.SetClock(clock: (() -> number)?)
	state.clock = clock or wallClock
end

function RivalService.SetRandom(rng: Random?)
	state.rng = rng or Random.new()
end

-- A thief grabbed the orb: the pedestal shows it gone, the guard gives chase.
-- Returns the orb, or nil if there is nothing to grab.
function RivalService.BeginCarry(rivalId: number, index: number, thief: Player): Orb?
	local rival = state.rivals[rivalId]
	local ped = rival and rival.Pedestals[index]
	if not rival or not ped or not ped.Orb or ped.Carried then
		return nil
	end
	ped.Carried = true
	showPedestal(rival, index)
	local guard = rival.Guard
	if guard then
		guard.Mode = "Chase"
		guard.Target = thief
		guard.Waypoints = {}
		guard.LastPathAt = -math.huge
	end
	return ped.Orb
end

-- The carry ended. Delivered: the orb is gone and comes back after
-- RespawnSeconds; anything else: it is back on the pedestal now. Safe for a
-- lab that has gone.
function RivalService.EndCarry(rivalId: number, index: number, delivered: boolean)
	local rival = state.rivals[rivalId]
	local ped = rival and rival.Pedestals[index]
	if not rival or not ped then
		return
	end
	ped.Carried = false
	if delivered then
		ped.Orb = nil
		ped.RespawnAt = now() + RivalConfig.RespawnSeconds
	end
	showPedestal(rival, index)
	-- The chase is over once nobody carries from this lab.
	local carried = false
	for _, other in rival.Pedestals do
		carried = carried or other.Carried
	end
	local guard = rival.Guard
	if guard and not carried and guard.Mode == "Chase" then
		guard.Mode = "Home"
		guard.Target = nil
		guard.Waypoints = {}
	end
end

-- The guard's root while it can tag (alive, on its feet), else nil.
function RivalService.GetGuardRoot(rivalId: number): BasePart?
	local rival = state.rivals[rivalId]
	local guard = rival and rival.Guard
	if not guard or guard.Root.Parent == nil or os.clock() < guard.StunUntil then
		return nil
	end
	return guard.Root
end

-- The guard's root even while it is down (/selftest moves it).
function RivalService.GetGuardModel(rivalId: number): Model?
	local rival = state.rivals[rivalId]
	local guard = rival and rival.Guard
	return if guard then guard.Model else nil
end

function RivalService.IsGuardStunned(rivalId: number): boolean
	local rival = state.rivals[rivalId]
	local guard = rival and rival.Guard
	return guard ~= nil and os.clock() < guard.StunUntil
end

function RivalService.GetGuardMode(rivalId: number): string?
	local rival = state.rivals[rivalId]
	local guard = rival and rival.Guard
	return if guard then guard.Mode else nil
end

-- The rival id whose guard model `part` belongs to (CombatService), or nil.
function RivalService.GuardOfPart(part: Instance): number?
	local current: Instance? = part
	while current and current ~= Workspace do
		local id = current:GetAttribute("RivalGuard")
		if typeof(id) == "number" then
			return id
		end
		current = current.Parent
	end
	return nil
end

-- A weapon hit the guard (CombatService): it falls over for GuardStunSeconds,
-- can't tag and loses the chase. `from` is where the blow came from.
function RivalService.StunGuard(rivalId: number, from: Vector3): boolean
	local rival = state.rivals[rivalId]
	local guard = rival and rival.Guard
	if not guard or guard.Root.Parent == nil then
		return false
	end
	guard.StunUntil = os.clock() + RivalConfig.GuardStunSeconds
	guard.Stunned = true
	guard.Humanoid.PlatformStand = true
	local away = guard.Root.Position - from
	local flat = Vector3.new(away.X, 0, away.Z)
	local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)
	guard.Root.AssemblyLinearVelocity = direction * GUARD_KNOCKBACK + Vector3.new(0, GUARD_KICK, 0)
	if guard.Mode == "Chase" then
		-- It lost the chase; the carry goes on and the guard walks home when up.
		guard.Mode = "Home"
		guard.Target = nil
		guard.Waypoints = {}
	end
	return true
end

--[[ Building and removing ------------------------------------------------------ ]]

-- The free slot nearest to a real player's lab (the labs people can see).
local function pickSlot(): number?
	local free = TycoonService.GetFreeSlots()
	if #free == 0 then
		return nil
	end
	local anchors: { Vector3 } = {}
	for _, slot in TycoonService.GetPlayerSlots() do
		table.insert(anchors, PlotLayout.GetSlotCFrame(slot).Position)
	end
	local best: number? = nil
	local bestDistance = math.huge
	for _, slot in free do
		local position = PlotLayout.GetSlotCFrame(slot).Position
		local nearest = math.huge
		for _, anchor in anchors do
			nearest = math.min(nearest, (position - anchor).Magnitude)
		end
		if nearest < bestDistance then
			best, bestDistance = slot, nearest
		end
	end
	return best
end

local function spawnRival(): Rival?
	local slot = pickSlot()
	if not slot or not TycoonService.ReserveSlot(slot) then
		return nil
	end
	local id = state.nextId
	state.nextId += 1
	state.nameSerial += 1
	local name = RivalConfig.GetName(state.nameSerial)
	local plot = TycoonService.BuildRivalPlot(slot, id, name)
	if not plot then
		TycoonService.ReleaseSlot(slot)
		return nil
	end
	local rival: Rival = {
		Id = id,
		Name = name,
		SlotIndex = slot,
		Plot = plot,
		Origin = PlotLayout.GetSlotCFrame(slot),
		Pedestals = {},
		Guard = nil,
	}
	state.rivals[id] = rival
	local band = RivalConfig.GetBand(RivalService.GetLowestRebirths())
	for index = 1, RivalConfig.PedestalCount do
		rival.Pedestals[index] = { Orb = nil, Carried = false, RespawnAt = nil, Band = band }
		fillPedestal(rival, index, band)
	end
	task.spawn(buildGuard, rival)
	return rival
end

-- Registers `hook(rivalId)`, run just before a lab goes: HeistService fails
-- any carry from it (the orb is "back", the thief is told). A plain list so
-- this service never requires HeistService (which requires this one).
function RivalService.OnDespawn(hook: (number) -> ())
	table.insert(state.despawnHooks, hook)
end

-- Takes rival `rivalId` away: any carry from it fails cleanly first, then the
-- guard, the plot and the slot.
function RivalService.Despawn(rivalId: number): boolean
	local rival = state.rivals[rivalId]
	if not rival then
		return false
	end
	for _, hook in state.despawnHooks do
		local ok, err = pcall(function(): string?
			hook(rivalId)
			return nil
		end)
		if not ok then
			warn("RivalService: despawn hook failed - " .. tostring(err))
		end
	end
	state.rivals[rivalId] = nil
	local guard = rival.Guard
	rival.Guard = nil
	if guard then
		guard.Model:Destroy()
	end
	rival.Plot:Destroy()
	TycoonService.ReleaseSlot(rival.SlotIndex)
	return true
end

-- The rival lab farthest from every player's lab (their slot centres; the
-- origin with nobody in). Ties go to the newest.
local function farthestRival(): Rival?
	local anchors: { Vector3 } = {}
	for _, slot in TycoonService.GetPlayerSlots() do
		table.insert(anchors, PlotLayout.GetSlotCFrame(slot).Position)
	end
	if #anchors == 0 then
		table.insert(anchors, Vector3.zero)
	end
	local best: Rival? = nil
	local bestDistance = -math.huge
	for _, rival in state.rivals do
		local nearest = math.huge
		for _, anchor in anchors do
			nearest = math.min(nearest, (rival.Origin.Position - anchor).Magnitude)
		end
		if nearest > bestDistance or (nearest == bestDistance and best ~= nil and rival.Id > best.Id) then
			best, bestDistance = rival, nearest
		end
	end
	return best
end

-- A real player needs a slot and none is free: the farthest rival goes
-- (TycoonService's reclaimer). False if there is no rival to give up.
function RivalService.DespawnFarthest(): boolean
	local rival = farthestRival()
	if not rival then
		return false
	end
	return RivalService.Despawn(rival.Id)
end

--[[ Housekeeping --------------------------------------------------------------------- ]]

-- One pass: refill the labs, bring back stolen orbs whose time is up, and
-- re-roll orbs that were rolled for a higher band than the server's lowest.
-- Called every FillSeconds; /selftest calls it with its own clock.
function RivalService.Step()
	while true do
		local count = 0
		for _ in state.rivals do
			count += 1
		end
		if count >= RivalConfig.MaxRivals or not spawnRival() then
			break
		end
	end
	local band = RivalConfig.GetBand(RivalService.GetLowestRebirths())
	local t = now()
	for _, rival in state.rivals do
		for index, ped in rival.Pedestals do
			if ped.Orb == nil and not ped.Carried and ped.RespawnAt ~= nil and t >= ped.RespawnAt then
				fillPedestal(rival, index, band)
			elseif ped.Orb ~= nil and not ped.Carried and ped.Band > band then
				fillPedestal(rival, index, band)
			end
		end
	end
end

--[[ Lifecycle ------------------------------------------------------------------ ]]

function RivalService:Init()
	-- Own state only; the labs are built in :Start (they need TycoonService).
end

function RivalService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)

	TycoonService.SetSlotReclaimer(RivalService.DespawnFarthest)

	state.running = true
	-- The fill / respawn loop. Deferred a moment so the world and the first
	-- players' plots are in before any rival picks a slot.
	task.spawn(function()
		task.wait(1)
		while state.running do
			local ok, err = pcall(function(): string?
				RivalService.Step()
				return nil
			end)
			if not ok then
				warn("RivalService: step failed - " .. tostring(err))
			end
			task.wait(RivalConfig.FillSeconds)
		end
	end)
	-- The one guard loop for every lab.
	table.insert(
		state.connections,
		RunService.Heartbeat:Connect(function(dt: number)
			state.guardAccumulator += dt
			if state.guardAccumulator < RivalConfig.GuardTickSeconds then
				return
			end
			state.guardAccumulator = 0
			for _, rival in state.rivals do
				local ok, err = pcall(function(): string?
					guardStep(rival)
					return nil
				end)
				if not ok then
					warn("RivalService: guard step failed - " .. tostring(err))
				end
			end
		end)
	)
end

function RivalService:Stop()
	state.running = false
	TycoonService.SetSlotReclaimer(nil)
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
end

return RivalService
