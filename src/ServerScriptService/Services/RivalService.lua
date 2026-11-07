--!strict
--[[
	RivalService
	------------
	Rival labs: NPC-owned labs in plot slots no player owns, so a brand-new
	player can steal from minute 3 even in an empty server (numbers in
	RivalConfig; the steal itself is HeistService's, same grab / carry /
	deliver flow).

	Labs
	  * RivalConfig.MaxRivals (4), ONE per difficulty (Easy, Medium, Hard,
	    Insane), in the free slots nearest to the real players' labs. Built by
	    TycoonService.BuildRivalPlot (the player plot code: shell, walls, sign
	    gate, pedestals, plus the Fusion Machine, stations, factory line and
	    portal as decoration-mode pictures: no prompts, no labels, no owner).
	    Slots are TycoonService's table: a real player is never refused a plot
	    because of a rival. With no slot free TycoonService calls
	    DespawnFarthest (registered in :Start) and the LOWEST difficulty goes
	    first (Easy, Medium, Hard, Insane last; the lab farthest from every
	    player's lab breaks a tie); a carry from it fails cleanly
	    (HeistService.FailRivalCarries) before the plot goes. When slots are
	    short the labs that spawn are the ones that would despawn last.
	  * The DIFFICULTY (RivalConfig.Tiers) decides the lab: the orb tiers and
	    weights (only Insane rolls Mythic / Secret), the guards, the Rebirths a
	    thief needs, the hourly pool, the respawn and the Golden chance.
	  * Orbs are server objects (every client sees the same ones): plain, one
	    Golden at the difficulty's GoldenChance. A pedestal rolls its tier from
	    the lab's weights (RivalConfig.PickTier) at spawn, on a rotation and
	    when a stolen pedestal comes back.
	  * Rotation: every RivalConfig.RotateSeconds (+- jitter, labs spaced at
	    least RotateMinGapSeconds apart) a lab re-rolls its orbs: a flash on the
	    old orb, a shell closing on the new one. Never a pedestal that is being
	    carried from; the whole lab waits for the next tick while a guard
	    chases, a StealPrompt is held, or a player is within
	    RotateKeepOutStuds of a pedestal. A pedestal waiting to respawn rolls
	    its new orb when it comes back. The plot's NextRotateAt attribute
	    (RivalService clock = unix seconds) feeds the gate sign's "fresh orbs in
	    1:48" (WorldLabelController).
	  * A stolen orb comes back after the difficulty's RespawnSeconds (the
	    respawn clock is injectable: SetClock, /selftest).

	Guards (Rival.Guards, 1 / 1 / 2 / 3 by difficulty)
	  * Blocky R15 NPCs (HumanoidDescription rigs), server-side, named after
	    their rival, bigger and tougher-looking by difficulty (scale 1 / 1.1 /
	    1.2 + helmet / 1.35 black and red with a glowing visor). Each stays
	    upright (no FallingDown / Ragdoll / Physics / Seated, a self-heal for a
	    root tilted past 45 deg) and runs the same patrol / chase / home code,
	    spread over the patrol stops so they never stack. HeistService calls
	    BeginCarry on a grab: the (up to RivalConfig.MaxChasers = 2) nearest
	    guards chase the carrier at the difficulty's GuardSpeed along
	    PathfindingService paths (recomputed at most every GuardPathSeconds),
	    giving up at the difficulty's Leash past the gate (Insane: never); a
	    third guard is the gate-holder: it stands IN the gate (RivalConfig.GateHoldPoint) and tags in HolderTagRadius. Each chaser that
	    starts running tells the carrier (RivalSpotted: alarm + a red "!").
	    HeistService owns the tag: ANY guard within HeistConfig.TagDistance of
	    the carrier sends the orb back.
	  * Weapons work on ONE guard (CombatService -> StunGuard): it falls over for
	    the difficulty's StunSeconds, can't tag, and goes back to the chase when
	    it is up if the carrier is still running.
	  * ONE guard loop per server (every guard of every lab).

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
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local RivalConfig = require(ReplicatedStorage.Shared.Config.RivalConfig)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
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
	Thief: Player?, -- who carries it
	RespawnAt: number?, -- RivalService clock time a stolen orb is back
	Holders: { [Player]: boolean }, -- players holding this pedestal's StealPrompt
}

-- Patrol: walking the stops. Chase: after a carrier. Home: walking back to its
-- own spot. Hold: the gate-holder at its post in the gate (always).
type GuardMode = "Patrol" | "Chase" | "Home" | "Hold"

type Guard = {
	Index: number, -- 1..Rival.Guards (the "GuardIndex" attribute)
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Mode: GuardMode,
	Target: Player?,
	ResumeTarget: Player?, -- the carrier a stunned chaser goes back after once it is up
	StunUntil: number,
	Stunned: boolean,
	TiltedSince: number?, -- os.clock() the root's up-vector went past the limit (not stunned)
	GetUpAt: number?, -- os.clock() of the GettingUp attempt; still down a second later = pivot it
	PatrolIndex: number,
	PauseUntil: number,
	Holder: boolean, -- the gate-holder (a guard past MaxChasers): stands IN the gate at RivalConfig.GateHoldPoint, never chases
	HomeLocal: Vector3, -- plot-local: where it spawns and returns (the holder: its post in the gate)
	Faced: boolean, -- Hold: already turned to the gate
	Waypoints: { PathWaypoint },
	WaypointIndex: number,
	PathPending: boolean,
	LastPathAt: number,
	SpottedAt: number, -- os.clock() of the last "!" cue sent for this guard
	WalkTrack: AnimationTrack?,
	IdleTrack: AnimationTrack?,
}

type Rival = {
	Id: number,
	Name: string,
	Difficulty: string, -- RivalConfig.Difficulties
	SlotIndex: number,
	Plot: Model,
	Origin: CFrame,
	Pedestals: { [number]: PedestalState },
	Guards: { Guard },
	NextRotateAt: number, -- RivalService clock time of the next orb rotation
}

-- What other services see of a rival lab.
export type RivalView = {
	Id: number,
	Name: string,
	Difficulty: string,
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
	lastAlarmAt: { [number]: number }, -- carrier UserId -> os.clock() of the last alarm (one per grab)
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
	lastAlarmAt = {},
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
-- States the guard must never fall into (a belt, a knock or a stun must not
-- lay it on its side); PlatformStand is the stun's own, ended in recoverGuard.
local DISABLED_STATES = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Physics,
	Enum.HumanoidStateType.Seated,
}
local GUARD_NAME_OFFSET = Vector3.new(0, 2.4, 0) -- above the head
local GUARD_NAME_STUDS = Vector2.new(5.4, 1.1)

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
		Difficulty = rival.Difficulty,
		SlotIndex = rival.SlotIndex,
		Plot = rival.Plot,
		Origin = rival.Origin,
	}
end

--[[ Orbs ----------------------------------------------------------------------- ]]

local function roll(): number
	return state.rng:NextNumber()
end

-- One rival orb of `tier`: plain, one Golden at `difficulty`'s GoldenChance.
-- Pure but for the RNG (injectable: SetRandom).
function RivalService.RollOrbOfTier(tier: string, difficulty: string): Orb
	local def = ItemConfig.PickRandomOfTier(tier, state.rng) or ItemConfig.Items[1]
	local mutation: string? = if roll() < RivalConfig.GetTier(difficulty).GoldenChance then "Golden" else nil
	return {
		ItemId = def.Id,
		Tier = def.Tier,
		Mutation = mutation,
		Name = MutationConfig.GetDisplayName(def.Name, mutation, nil),
		Rate = TycoonConfig.GetItemCashPerSecond(def.Tier, MutationConfig.List(mutation, nil)),
	}
end

-- One rival orb for a lab of `difficulty`: its tier from the difficulty's
-- weights (never a tier the lab may not hand out), then RollOrbOfTier.
function RivalService.RollOrb(difficulty: string): Orb
	return RivalService.RollOrbOfTier(RivalConfig.PickTier(difficulty, roll()), difficulty)
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
	-- The client's "back in 1:12" chip (WorldLabelController) counts down to this.
	pedestal:SetAttribute("RespawnAt", if orb == nil then ped.RespawnAt else nil)
	pedestal:SetAttribute("BeingStolen", ped.Carried)
end

-- A transient flash at `center`: a ball from `fromSize` to `toSize` studs
-- fading out (decorative, destroyed when done). The swap cue on a rotation.
local function flash(center: Vector3, color: Color3, fromSize: number, toSize: number)
	local ball = Instance.new("Part")
	ball.Name = "RivalSwapFlash"
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Transparency = 0.35
	ball.Size = Vector3.one * fromSize
	ball.Position = center
	ball.Parent = Workspace
	local info = TweenInfo.new(RivalConfig.PopSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(ball, info, { Size = Vector3.one * toSize, Transparency = 1 })
	tween.Completed:Once(function()
		ball:Destroy()
	end)
	tween:Play()
end

-- Where the orb on a pedestal sits (its rest pose; clients bob it), or nil.
local function orbCenter(pedestal: BasePart): Vector3?
	local group = pedestal:FindFirstChild("OrbGroup", true)
	if group and group:IsA("Model") and group.PrimaryPart then
		return group.PrimaryPart.Position
	end
	return nil
end

local function tierColor(tier: string): Color3
	return FusionConfig.TierAccentColors[tier] or UITheme.Colors.Text
end

-- Rolls the pedestal's orb from the lab's difficulty. `cue`: the swap flash (a
-- rotation), not for a first fill or a respawn.
local function fillPedestal(rival: Rival, index: number, cue: boolean?)
	local ped = rival.Pedestals[index]
	if not ped then
		return
	end
	local pedestal = getPedestal(rival, index)
	local oldOrb = ped.Orb
	local oldCenter = if cue and pedestal and oldOrb then orbCenter(pedestal) else nil
	local newOrb = RivalService.RollOrb(rival.Difficulty)
	ped.Orb = newOrb
	ped.Carried = false
	ped.RespawnAt = nil
	if oldCenter and oldOrb then
		flash(oldCenter, tierColor(oldOrb.Tier), 1.5, 5)
	end
	showPedestal(rival, index)
	if cue and pedestal then
		local newCenter = orbCenter(pedestal)
		if newCenter then
			flash(newCenter, tierColor(newOrb.Tier), 6, 1.5)
		end
	end
end

--[[ Guard ------------------------------------------------------------------------ ]]

-- The guard's body colours by look: Easy / Medium / Hard keep the lab's own
-- (orange arms and torso, white head, dark legs); the Elite look is black and red.
local function guardColors(look: string): { [string]: Color3 }
	if look == "Elite" then
		return {
			Head = World.GuardDark,
			Torso = World.GuardDark,
			Arms = World.GuardRed,
			Legs = World.GuardDark,
		}
	end
	return {
		Head = World.CapsuleWhite,
		Torso = World.AccentRival,
		Arms = World.AccentRival,
		Legs = World.Structure,
	}
end

local function describeGuard(look: string): HumanoidDescription
	local colors = guardColors(look)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = colors.Head
	description.TorsoColor = colors.Torso
	description.LeftArmColor = colors.Arms
	description.RightArmColor = colors.Arms
	description.LeftLegColor = colors.Legs
	description.RightLegColor = colors.Legs
	return description
end

-- A rig accessory: one SmoothPlastic / Neon part welded to the head's
-- `attachment`. `handleOffset` is where the part's own attachment sits in its
-- local space (the part's centre lands at the head attachment minus this).
-- Massless and non-colliding: it must not change how the guard walks.
local function makeAccessory(name: string, attachment: string, size: Vector3, shape: Enum.PartType, color: Color3, material: Enum.Material, handleOffset: Vector3): Accessory
	local accessory = Instance.new("Accessory")
	accessory.Name = name
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = size
	handle.Shape = shape
	handle.Color = color
	handle.Material = material
	handle.Massless = true
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.CastShadow = false
	local hold = Instance.new("Attachment")
	hold.Name = attachment
	hold.Position = handleOffset
	hold.Parent = handle
	handle.Parent = accessory
	return accessory
end

-- Hard: a helmet cap. Elite: a dark helmet and a glowing Neon visor (a part,
-- not a Highlight). Easy / Medium wear nothing extra.
local function addGuardAccessories(humanoid: Humanoid, look: string)
	if look == "Helmet" or look == "Elite" then
		local color = if look == "Elite" then World.GuardDark else World.GuardHelmet
		humanoid:AddAccessory(makeAccessory("GuardHelmet", "HatAttachment", Vector3.new(1.5, 1.5, 1.5), Enum.PartType.Ball, color, Enum.Material.SmoothPlastic, Vector3.new(0, -0.35, 0)))
	end
	if look == "Elite" then
		humanoid:AddAccessory(makeAccessory("GuardVisor", "FaceFrontAttachment", Vector3.new(1.3, 0.28, 0.12), Enum.PartType.Block, World.DifficultyInsane, Enum.Material.Neon, Vector3.new(0, -0.1, 0.06)))
	end
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

-- Degrees between the root's up-vector and vertical (0 = standing).
local function uprightAngle(root: BasePart): number
	return math.deg(math.acos(math.clamp(root.CFrame.UpVector.Y, -1, 1)))
end

-- The HipHeight the rig's own legs call for: the gap from the root's bottom to
-- the soles. (A HumanoidDescription rig can come in with a wrong one, which
-- sinks it into the floor or holds it in the air.) nil when the rig has no foot.
local function rigHipHeight(rig: Model, root: BasePart): number?
	local foot = rig:FindFirstChild("LeftFoot")
	if not foot or not foot:IsA("BasePart") then
		return nil
	end
	local height = (root.Position.Y - root.Size.Y / 2) - (foot.Position.Y - foot.Size.Y / 2)
	return if height > 0 then height else nil
end

-- Puts the whole guard back on its feet where it is, facing `facing` (flat),
-- and stills it; it drops the last stud onto the floor under its HipHeight.
local function pivotUpright(guard: Guard, facing: Vector3)
	local position = guard.Root.Position
	local look = Vector3.new(facing.X, 0, facing.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, 1)
	end
	for _, part in guard.Model:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	guard.Model:PivotTo(CFrame.lookAt(position + Vector3.new(0, 2, 0), position + Vector3.new(0, 2, 0) + look))
end

-- The guard's name over its head, in the rival accent ("Dr. Fizz"), instead of
-- the stock overhead name. A world label: not on top, no light influence, a MaxDistance.
local function buildGuardName(rig: Model, humanoid: Humanoid, labName: string, scale: number)
	local shortName = RivalConfig.GetShortName(labName)
	humanoid.DisplayName = shortName
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	local head = rig:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	BillboardKit.Chip(head, {
		Name = "GuardName",
		Text = shortName,
		Gradient = UITheme.Gradients.Rival,
		Studs = GUARD_NAME_STUDS,
		StudsOffset = GUARD_NAME_OFFSET * scale, -- clears a bigger guard's head
		MaxDistance = RivalConfig.GuardNameDistance,
	})
end

-- Where guard `index` of `count` stands when idle: the lab's GuardHome, the
-- rest spread across x so they never stack (the gate-holder is the last one).
local function guardHomeLocal(index: number, count: number): Vector3
	local spread = (index - (count + 1) / 2) * RivalConfig.GuardSpread
	return RivalConfig.GuardHome + Vector3.new(spread, 0, 0)
end

-- Builds guard `index` of the rival's guards (yields: the rig comes from a
-- HumanoidDescription), unless the lab went in the meantime. A failed rig
-- leaves the lab one guard short.
local function buildGuard(rival: Rival, index: number)
	local tier = RivalConfig.GetTier(rival.Difficulty)
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(describeGuard(tier.Look), Enum.HumanoidRigType.R15)
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
	addGuardAccessories(humanoid, tier.Look)
	if tier.GuardScale ~= 1 then
		rig:ScaleTo(tier.GuardScale) -- bigger by difficulty; the Avatar Settings scale limits do not apply to a Model:ScaleTo
	end
	buildGuardName(rig, humanoid, rival.Name, tier.GuardScale)
	humanoid.WalkSpeed = RivalConfig.GuardPatrolSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	for _, humanoidState in DISABLED_STATES do
		humanoid:SetStateEnabled(humanoidState, false)
	end
	local hipHeight = rigHipHeight(rig, root)
	if hipHeight then
		humanoid.HipHeight = hipHeight
	end
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	rig:SetAttribute("RivalGuard", rival.Id)
	rig:SetAttribute("GuardIndex", index)
	local holder = RivalConfig.HasHolder(rival.Difficulty) and index > RivalConfig.MaxChasers
	local homeLocal = if holder then RivalConfig.GateHoldPoint else guardHomeLocal(index, math.min(tier.Guards, RivalConfig.MaxChasers))
	local home = rival.Origin:PointToWorldSpace(homeLocal + Vector3.new(0, 3 * tier.GuardScale, 0))
	rig:PivotTo(CFrame.new(home) * rival.Origin.Rotation)
	rig.Parent = rival.Plot
	pcall(function()
		root:SetNetworkOwner(nil) -- the server drives it; no player's client can
	end)
	local points = #RivalConfig.PatrolPoints
	local guard: Guard = {
		Index = index,
		Model = rig,
		Root = root,
		Humanoid = humanoid,
		Mode = if holder then "Hold" else "Patrol",
		Target = nil,
		ResumeTarget = nil,
		StunUntil = 0,
		Stunned = false,
		TiltedSince = nil,
		GetUpAt = nil,
		-- Spread over the stops so the guards never stack.
		PatrolIndex = ((index - 1) * math.max(1, points // tier.Guards)) % points + 1,
		PauseUntil = 0,
		Holder = holder,
		HomeLocal = homeLocal,
		Faced = false,
		Waypoints = {},
		WaypointIndex = 1,
		PathPending = false,
		LastPathAt = -math.huge,
		SpottedAt = -math.huge,
		WalkTrack = loadTrack(humanoid, WALK_ANIMATION, true),
		IdleTrack = loadTrack(humanoid, IDLE_ANIMATION, true),
	}
	if guard.IdleTrack then
		guard.IdleTrack:Play()
	end
	table.insert(rival.Guards, guard)
end

-- All of a lab's guards, one after the other (each rig yields).
local function buildGuards(rival: Rival)
	local count = RivalConfig.GetTier(rival.Difficulty).Guards
	for index = 1, count do
		if state.rivals[rival.Id] ~= rival or rival.Plot.Parent == nil then
			return
		end
		buildGuard(rival, index)
	end
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

-- Ends a stun: PlatformStand off, upright, GettingUp. The ONE place a stun ends
-- (guardStep, once StunUntil has passed - a second hit just moves StunUntil on;
-- Despawn calls it too so a lab that goes mid-stun leaves nothing stood down).
local function recoverGuard(guard: Guard)
	guard.Stunned = false
	guard.TiltedSince = nil
	guard.GetUpAt = nil
	guard.Humanoid.PlatformStand = false
	-- Back on its feet: keep the facing, drop the tumble.
	pivotUpright(guard, guard.Root.CFrame.LookVector)
	guard.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

-- Self-heal, once per tick while the guard is NOT stunned: a root tilted more
-- than the limit for GuardDownSeconds gets GettingUp, and if it is still down a
-- second later it is pivoted upright where it lies.
local function healGuard(guard: Guard, t: number, facing: Vector3)
	if guard.Humanoid.PlatformStand then
		guard.Humanoid.PlatformStand = false -- only a stun sets it, and a stun has ended
	end
	if uprightAngle(guard.Root) <= RivalConfig.UprightLimitDegrees then
		guard.TiltedSince = nil
		guard.GetUpAt = nil
		return
	end
	local since = guard.TiltedSince
	if since == nil then
		guard.TiltedSince = t
	elseif t - since > RivalConfig.GuardDownSeconds then
		local tried = guard.GetUpAt
		if tried == nil then
			guard.GetUpAt = t
			guard.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		elseif t - tried >= RivalConfig.GuardDownSeconds then
			pivotUpright(guard, facing)
			guard.TiltedSince = nil
			guard.GetUpAt = nil
		end
	end
end

-- The players carrying an orb out of this lab right now.
local function carriersOf(rival: Rival): { [Player]: boolean }
	local set: { [Player]: boolean } = {}
	for _, ped in rival.Pedestals do
		if ped.Carried and ped.Thief then
			set[ped.Thief] = true
		end
	end
	return set
end

-- Turns the guard to look along `direction` (flat) where it stands.
local function faceDirection(guard: Guard, direction: Vector3)
	local look = Vector3.new(direction.X, 0, direction.Z)
	if look.Magnitude < 0.01 then
		return
	end
	local position = guard.Root.Position
	guard.Model:PivotTo(CFrame.lookAt(position, position + look))
end

-- The lab's gate direction (+Z in plot space), flat, in the world.
local function gateDirection(rival: Rival): Vector3
	return rival.Origin:VectorToWorldSpace(Vector3.new(0, 0, 1))
end

-- A guard starts running after `target`: the carrier is told (the alarm once
-- per grab, a red "!" over THIS guard for the carrier only: the cue is the
-- client's, so nobody else sees it).
local function startChase(rival: Rival, guard: Guard, target: Player)
	guard.Mode = "Chase"
	guard.Target = target
	guard.ResumeTarget = nil
	guard.Faced = false
	guard.Waypoints = {}
	guard.LastPathAt = -math.huge
	local t = os.clock()
	local firstAlarm = t - (state.lastAlarmAt[target.UserId] or -math.huge) > 1
	if firstAlarm then
		state.lastAlarmAt[target.UserId] = t
	end
	guard.SpottedAt = t
	local head = guard.Model:FindFirstChild("Head")
	if head and target.Parent then
		RemoteEvents.RivalSpotted:FireClient(target, {
			RivalId = rival.Id,
			GuardIndex = guard.Index,
			Head = head,
			Alarm = firstAlarm,
			Seconds = RivalConfig.SpottedSeconds,
		})
	end
end

local function guardStep(rival: Rival, guard: Guard)
	if guard.Root.Parent == nil then
		return
	end
	local tier = RivalConfig.GetTier(rival.Difficulty)
	local t = os.clock() -- the guard runs on the real clock (SetClock is for orbs and limits)
	if t < guard.StunUntil then
		setMoving(guard, false)
		return
	end
	if guard.Stunned then
		recoverGuard(guard)
		-- Up again: back on the carrier it was chasing, if that thief is still running.
		local resume = guard.ResumeTarget
		guard.ResumeTarget = nil
		if resume and resume.Parent and carriersOf(rival)[resume] then
			startChase(rival, guard, resume)
		end
	end
	healGuard(guard, t, rival.Origin.LookVector)
	local humanoid = guard.Humanoid
	local position = guard.Root.Position

	if guard.Holder then
		-- The gate-holder: runs to its post in the gate (at the chase speed when it
		-- was knocked off it), stands facing the street. It never chases.
		local spot = rival.Origin:PointToWorldSpace(guard.HomeLocal)
		if flatDistance(position, spot) > RivalConfig.GuardWaypointReach + 1 then
			humanoid.WalkSpeed = tier.GuardSpeed
			if t - guard.LastPathAt >= RivalConfig.GuardPathSeconds * 4 then
				requestPath(guard, spot)
			end
			followPath(guard, spot)
			setMoving(guard, true)
			guard.Faced = false
		else
			setMoving(guard, false)
			if not guard.Faced then
				guard.Faced = true
				faceDirection(guard, gateDirection(rival))
			end
		end
		return
	end

	if guard.Mode == "Chase" then
		local target = guard.Target
		local targetRoot = if target and target.Parent then getRoot(target) else nil
		if not targetRoot or flatDistance(position, gateWorld(rival)) > tier.Leash then
			-- Gone, or too far from home: give up and walk back.
			guard.Mode = "Home"
			guard.Target = nil
			guard.Waypoints = {}
		else
			humanoid.WalkSpeed = tier.GuardSpeed
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
		local home = rival.Origin:PointToWorldSpace(guard.HomeLocal)
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

-- When the lab's next orb rotation is due (RivalService clock time).
function RivalService.GetNextRotateAt(rivalId: number): number?
	local rival = state.rivals[rivalId]
	return if rival then rival.NextRotateAt else nil
end

-- /selftest: the tiers of the standing orbs, pedestal 1..PedestalCount (nil
-- for an empty or carried one).
function RivalService.GetTiers(rivalId: number): { string? }
	local tiers: { string? } = {}
	local rival = state.rivals[rivalId]
	for index = 1, RivalConfig.PedestalCount do
		local ped = rival and rival.Pedestals[index]
		tiers[index] = if ped and ped.Orb then ped.Orb.Tier else nil
	end
	return tiers
end

-- /selftest: due now (the next Step rotates this lab if it may).
function RivalService.SelfTestMakeRotationDue(rivalId: number)
	local rival = state.rivals[rivalId]
	if rival then
		rival.NextRotateAt = now() - 1
		rival.Plot:SetAttribute("NextRotateAt", rival.NextRotateAt)
	end
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

-- A thief grabbed the orb: the pedestal shows it gone and the guards react:
-- the nearest (up to RivalConfig.MaxChasers) free guards chase the thief, the
-- others hold the gate. A guard already chasing someone else stays on them,
-- unless every guard is busy: then the nearest one switches to the new thief.
-- Returns the orb, or nil if there is nothing to grab.
function RivalService.BeginCarry(rivalId: number, index: number, thief: Player): Orb?
	local rival = state.rivals[rivalId]
	local ped = rival and rival.Pedestals[index]
	if not rival or not ped or not ped.Orb or ped.Carried then
		return nil
	end
	ped.Carried = true
	ped.Thief = thief
	showPedestal(rival, index)
	local thiefRoot = getRoot(thief)
	local thiefPosition = if thiefRoot then thiefRoot.Position else rival.Origin.Position
	local carriers = carriersOf(rival)
	local free: { Guard } = {}
	local busy: { Guard } = {}
	for _, guard in rival.Guards do
		if guard.Holder then
			continue -- the gate-holder stays in the gate
		end
		local target = guard.Target
		local running = guard.Mode == "Chase" and target ~= nil and carriers[target] == true and target ~= thief
		table.insert(if running then busy else free, guard)
	end
	local function byDistance(a: Guard, b: Guard): boolean
		return (a.Root.Position - thiefPosition).Magnitude < (b.Root.Position - thiefPosition).Magnitude
	end
	table.sort(free, byDistance)
	table.sort(busy, byDistance)
	if #free == 0 and busy[1] then
		table.insert(free, table.remove(busy, 1) :: Guard) -- every guard is busy: the nearest switches
	end
	local chasing = 0
	for _, guard in free do
		if chasing < RivalConfig.MaxChasers then
			chasing += 1
			startChase(rival, guard, thief)
		end
	end
	return ped.Orb
end

-- The carry ended. Delivered: the orb is gone and comes back after the
-- difficulty's RespawnSeconds; anything else: it is back on the pedestal now.
-- Safe for a lab that has gone.
function RivalService.EndCarry(rivalId: number, index: number, delivered: boolean)
	local rival = state.rivals[rivalId]
	local ped = rival and rival.Pedestals[index]
	if not rival or not ped then
		return
	end
	ped.Carried = false
	ped.Thief = nil
	if delivered then
		ped.Orb = nil
		ped.RespawnAt = now() + RivalConfig.GetTier(rival.Difficulty).RespawnSeconds
	end
	showPedestal(rival, index)
	-- The chase is over for every guard whose carrier is done; the holders
	-- stand down once nobody carries from this lab.
	local carriers = carriersOf(rival)
	for _, guard in rival.Guards do
		local target = guard.Target
		local runningHere = guard.Mode == "Chase" and target ~= nil and carriers[target] == true
		if guard.Mode == "Chase" and not runningHere then
			guard.Mode = "Home"
			guard.Target = nil
			guard.Waypoints = {}
		end
		local resume = guard.ResumeTarget
		if resume and not carriers[resume] then
			guard.ResumeTarget = nil
		end
	end
end

-- The roots of the lab's guards that can tag right now (alive, on their feet).
function RivalService.GetGuardRoots(rivalId: number): { BasePart }
	local roots: { BasePart } = {}
	local rival = state.rivals[rivalId]
	if rival then
		local t = os.clock()
		for _, guard in rival.Guards do
			if guard.Root.Parent ~= nil and t >= guard.StunUntil then
				table.insert(roots, guard.Root)
			end
		end
	end
	return roots
end

-- The tag zones of the lab's guards that can tag right now: the root and how far
-- from it a touch counts (HeistConfig.TagDistance; the gate-holder's is the
-- wider RivalConfig.HolderTagRadius, enough to cover the whole gate opening).
function RivalService.GetGuardTagZones(rivalId: number): { { Root: BasePart, Radius: number } }
	local zones: { { Root: BasePart, Radius: number } } = {}
	local rival = state.rivals[rivalId]
	if rival then
		local t = os.clock()
		for _, guard in rival.Guards do
			if guard.Root.Parent ~= nil and t >= guard.StunUntil then
				table.insert(zones, { Root = guard.Root, Radius = if guard.Holder then RivalConfig.HolderTagRadius else HeistConfig.TagDistance })
			end
		end
	end
	return zones
end

local function getGuard(rivalId: number, index: number?): Guard?
	local rival = state.rivals[rivalId]
	return if rival then rival.Guards[index or 1] else nil
end

-- How many guards the lab has built so far (RivalConfig.Tiers[...].Guards once all are in).
function RivalService.GetGuardCount(rivalId: number): number
	local rival = state.rivals[rivalId]
	return if rival then #rival.Guards else 0
end

-- A guard's model even while it is down (/selftest moves it). Index 1 by default.
function RivalService.GetGuardModel(rivalId: number, index: number?): Model?
	local guard = getGuard(rivalId, index)
	return if guard then guard.Model else nil
end

function RivalService.IsGuardStunned(rivalId: number, index: number?): boolean
	local guard = getGuard(rivalId, index)
	return guard ~= nil and os.clock() < guard.StunUntil
end

function RivalService.GetGuardMode(rivalId: number, index: number?): string?
	local guard = getGuard(rivalId, index)
	return if guard then guard.Mode else nil
end

-- How many of the lab's guards are chasing (never above RivalConfig.MaxChasers
-- per carrier: /selftest).
function RivalService.GetChaserCount(rivalId: number): number
	local rival = state.rivals[rivalId]
	local count = 0
	local guards: { Guard } = if rival then rival.Guards else {}
	for _, guard in guards do
		if guard.Mode == "Chase" then
			count += 1
		end
	end
	return count
end

-- Degrees a guard's root is off vertical (0 = standing), nil with no guard
-- (/selftest holds it to RivalConfig.GuardUprightSelfTestDegrees).
function RivalService.GetGuardUprightDegrees(rivalId: number, index: number?): number?
	local guard = getGuard(rivalId, index)
	if not guard or guard.Root.Parent == nil then
		return nil
	end
	return uprightAngle(guard.Root)
end

-- /selftest: lays a guard on its side where it stands, as a bad fall would
-- (the self-heal must stand it up again by itself).
function RivalService.SelfTestLayDown(rivalId: number, index: number?): boolean
	local guard = getGuard(rivalId, index)
	if not guard or guard.Root.Parent == nil then
		return false
	end
	guard.Model:PivotTo(guard.Root.CFrame * CFrame.Angles(0, 0, math.rad(90)) + Vector3.new(0, 1, 0))
	return true
end

-- The rival id and guard index whose guard model `part` belongs to
-- (CombatService), or nil.
function RivalService.GuardOfPart(part: Instance): (number?, number?)
	local current: Instance? = part
	while current and current ~= Workspace do
		local id = current:GetAttribute("RivalGuard")
		if typeof(id) == "number" then
			local index = current:GetAttribute("GuardIndex")
			return id, if typeof(index) == "number" then index else 1
		end
		current = current.Parent
	end
	return nil, nil
end

-- A weapon hit ONE guard (CombatService): it falls over for the difficulty's
-- StunSeconds and can't tag. A chaser remembers its carrier and goes back to the
-- chase once it is up (a short Insane stun buys a few strides, not the orb).
-- `from` is where the blow came from.
function RivalService.StunGuard(rivalId: number, index: number, from: Vector3): boolean
	local rival = state.rivals[rivalId]
	local guard = rival and rival.Guards[index]
	if not rival or not guard or guard.Root.Parent == nil then
		return false
	end
	guard.StunUntil = os.clock() + RivalConfig.GetTier(rival.Difficulty).StunSeconds
	guard.Stunned = true
	guard.Humanoid.PlatformStand = true
	local away = guard.Root.Position - from
	local flat = Vector3.new(away.X, 0, away.Z)
	local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)
	guard.Root.AssemblyLinearVelocity = direction * GUARD_KNOCKBACK + Vector3.new(0, GUARD_KICK, 0)
	if guard.Mode == "Chase" then
		guard.ResumeTarget = guard.Target
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

--[[ Rotation ------------------------------------------------------------------- ]]

-- Counts the players holding a pedestal's StealPrompt (a grab about to
-- happen); the prompt's hold events fire on the server too.
local function trackHolders(rival: Rival, index: number)
	local ped = rival.Pedestals[index]
	local pedestal = getPedestal(rival, index)
	local prompt = pedestal and pedestal:FindFirstChild("StealPrompt")
	if not ped or not prompt or not prompt:IsA("ProximityPrompt") then
		return
	end
	prompt.PromptButtonHoldBegan:Connect(function(holder: Player)
		ped.Holders[holder] = true
	end)
	prompt.PromptButtonHoldEnded:Connect(function(holder: Player)
		ped.Holders[holder] = nil
	end)
end

-- Sets the lab's next rotation time (spaced from the other labs') and
-- publishes it on the plot for the gate sign's countdown.
local function scheduleRotation(rival: Rival, wanted: number)
	local others: { number } = {}
	for _, other in state.rivals do
		if other ~= rival then
			table.insert(others, other.NextRotateAt)
		end
	end
	rival.NextRotateAt = RivalConfig.SpaceRotation(wanted, others)
	rival.Plot:SetAttribute("NextRotateAt", rival.NextRotateAt)
end

-- Whether `rival` may swap its orbs right now (else: the next tick tries
-- again): the guard isn't chasing, nobody holds a StealPrompt, and no player
-- stands at a pedestal (about to grab).
local function canRotate(rival: Rival): boolean
	for _, guard in rival.Guards do
		if guard.Mode == "Chase" then
			return false
		end
	end
	for index, ped in rival.Pedestals do
		if next(ped.Holders) ~= nil then
			return false
		end
		local pedestal = getPedestal(rival, index)
		if pedestal then
			for _, player in Players:GetPlayers() do
				local root = getRoot(player)
				if root and (root.Position - pedestal.Position).Magnitude <= RivalConfig.RotateKeepOutStuds then
					return false
				end
			end
		end
	end
	return true
end

-- Re-rolls every standing orb of the lab (not a carried one, not a pedestal
-- waiting to respawn: that one rolls when it is back), with the swap cue.
local function rotateLab(rival: Rival)
	for index, ped in rival.Pedestals do
		if ped.Orb ~= nil and not ped.Carried then
			fillPedestal(rival, index, true)
		end
	end
	scheduleRotation(rival, now() + RivalConfig.RotateDelay(roll()))
end

-- The difficulties that have no lab yet, in SPAWN order: the one that would
-- despawn last first (Insane, Hard, Medium, Easy), so when slots are short the
-- labs that exist are the ones the despawn order keeps.
local function missingDifficulties(): { string }
	local have: { [string]: boolean } = {}
	for _, rival in state.rivals do
		have[rival.Difficulty] = true
	end
	local missing: { string } = {}
	for index = #RivalConfig.Difficulties, 1, -1 do
		local difficulty = RivalConfig.Difficulties[index]
		if not have[difficulty] then
			table.insert(missing, difficulty)
		end
	end
	return missing
end

local function spawnRival(difficulty: string): Rival?
	local slot = pickSlot()
	if not slot or not TycoonService.ReserveSlot(slot) then
		return nil
	end
	local id = state.nextId
	state.nextId += 1
	state.nameSerial += 1
	local name = RivalConfig.GetName(state.nameSerial)
	local plot = TycoonService.BuildRivalPlot(slot, id, name, difficulty)
	if not plot then
		TycoonService.ReleaseSlot(slot)
		return nil
	end
	local rival: Rival = {
		Id = id,
		Name = name,
		Difficulty = difficulty,
		SlotIndex = slot,
		Plot = plot,
		Origin = PlotLayout.GetSlotCFrame(slot),
		Pedestals = {},
		Guards = {},
		NextRotateAt = 0,
	}
	local labsBefore = 0
	for _ in state.rivals do
		labsBefore += 1
	end
	state.rivals[id] = rival
	for index = 1, RivalConfig.PedestalCount do
		rival.Pedestals[index] = { Orb = nil, Carried = false, Thief = nil, RespawnAt = nil, Holders = {} }
		fillPedestal(rival, index)
		trackHolders(rival, index)
	end
	-- The first rotation of the 1st / 2nd / ... lab is spread over the interval.
	local fractions = RivalConfig.RotateFirstFractions
	local fraction = fractions[math.min(labsBefore + 1, #fractions)]
	scheduleRotation(rival, now() + RivalConfig.RotateSeconds * fraction)
	task.spawn(buildGuards, rival)
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
	local guards = rival.Guards
	rival.Guards = {}
	for _, guard in guards do
		if guard.Stunned then
			recoverGuard(guard) -- the stun ends on this path too
		end
		guard.Model:Destroy()
	end
	rival.Plot:Destroy()
	TycoonService.ReleaseSlot(rival.SlotIndex)
	return true
end

-- The lab to give up first: the LOWEST difficulty (Easy, Medium, Hard, Insane
-- last), and among labs of equal difficulty the one farthest from every
-- player's lab (their slot centres; the origin with nobody in); ties go to the
-- newest.
local function farthestRival(): Rival?
	local anchors: { Vector3 } = {}
	for _, slot in TycoonService.GetPlayerSlots() do
		table.insert(anchors, PlotLayout.GetSlotCFrame(slot).Position)
	end
	if #anchors == 0 then
		table.insert(anchors, Vector3.zero)
	end
	local best: Rival? = nil
	local bestRank = math.huge
	local bestDistance = -math.huge
	for _, rival in state.rivals do
		local rank = RivalConfig.GetTier(rival.Difficulty).Rank
		local nearest = math.huge
		for _, anchor in anchors do
			nearest = math.min(nearest, (rival.Origin.Position - anchor).Magnitude)
		end
		local better = rank < bestRank
			or (rank == bestRank and (nearest > bestDistance or (nearest == bestDistance and best ~= nil and rival.Id > best.Id)))
		if better then
			best, bestRank, bestDistance = rival, rank, nearest
		end
	end
	return best
end

-- A real player needs a slot and none is free: the lowest-difficulty rival
-- goes (TycoonService's reclaimer). False if there is no rival to give up.
function RivalService.DespawnFarthest(): boolean
	local rival = farthestRival()
	if not rival then
		return false
	end
	return RivalService.Despawn(rival.Id)
end

--[[ Housekeeping --------------------------------------------------------------------- ]]

-- One pass: refill the labs (one per difficulty), bring back stolen orbs whose
-- time is up, re-roll the orbs of a lab whose rotation is due, all only while
-- canRotate. Called every FillSeconds; /selftest calls it with its own clock.
function RivalService.Step()
	for _, difficulty in missingDifficulties() do
		local count = 0
		for _ in state.rivals do
			count += 1
		end
		if count >= RivalConfig.MaxRivals or not spawnRival(difficulty) then
			break
		end
	end
	local t = now()
	for _, rival in state.rivals do
		for index, ped in rival.Pedestals do
			if ped.Orb == nil and not ped.Carried and ped.RespawnAt ~= nil and t >= ped.RespawnAt then
				fillPedestal(rival, index)
			end
		end
		if t >= rival.NextRotateAt and canRotate(rival) then
			rotateLab(rival)
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
				for _, guard in rival.Guards do
					local ok, err = pcall(function(): string?
						guardStep(rival, guard)
						return nil
					end)
					if not ok then
						warn("RivalService: guard step failed - " .. tostring(err))
					end
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
