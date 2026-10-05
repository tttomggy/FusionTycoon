--!strict
--[[
	HeistScenes
	-----------
	The four looping 3D clips in HOW TO HEIST (HowToHeistPanel). Each is a
	ViewportFrame with a WorldModel (so rigs render and animate), built from
	the game's own pieces:

	  set      a 40 x 40 floor slab in the lab floor colour with the walkway
	           strip, the street beyond, and one plot wall with its gate gap
	  pieces   the real pedestal + orb (PedestalVisuals: a Golden Mythic with
	           its shell and satellites), the real LockKit console, flat pink
	           shield panels (World.Shield SmoothPlastic: ForceField doesn't
	           render in viewports), thin translucent floor rings (no Neon)
	  actors   YOU: a clone of your own character (scripts, sounds and
	           BillboardGuis stripped, root anchored), or a default R15 rig
	           if you have none; the other player: a default R15 rig in
	           UITheme.HeistScene.ThiefBody red. Moves are CFrame lerps; the
	           run and idle animations come from your own Animate script's
	           ids, so they always load.
	  labels   2D UIKit pills over the scene (BillboardGuis don't render in a
	           viewport), placed each frame by projecting the world point
	           through the scene camera.

	A clip is a pure function of its loop time t, so it loops cleanly.
	Build everything when the card opens (HeistScenes.Build), Step only the
	slide on screen, Destroy on close. No lights (viewports ignore them),
	no Highlights.

	  1 GRAB   YOU walk to an enemy pedestal, an "E" ring fills over the
	           grab hold, the orb lifts over your head (red beam) and you run
	           to the blue "🏠 YOUR LAB" gate.
	  2 GUARD  YOU stand by your pedestal on the teal guard ring (GUARDED);
	           the thief walks up, "✋ Owner is guarding" pops, they back off.
	  3 CATCH  the thief runs with your orb; YOU chase and touch them: a
	           white ring flash, CAUGHT!, the orb arcs back onto its pedestal
	           (the same Bezier as the real catch).
	  4 LOCK   YOU run to the LOCK console and press: the button turns teal,
	           the pink panels rise, "🔒 LOCKED · 60s", and the thief walks
	           into the wall and is pushed back.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local LockKit = require(ReplicatedStorage.Shared.Modules.LockKit)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.UIKit)

local HeistScenes = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts
local World = UITheme.World
local Look = UITheme.HeistScene

local localPlayer = Players.LocalPlayer

--[[ Set geometry (scene studs; +Z toward the camera, the gate side) -------- ]]

local FLOOR_SIZE = 40
local WALL_Z = 6 -- the plot wall's line (the gate gap is the walkway)
local GATE_HALF = PlotLayout.WALKWAY_WIDTH / 2
local CAMERA_OFFSET = Vector3.new(0, 13, 18) -- ~22 studs out, the usual 3/4 view
local CAMERA_TARGET = Vector3.new(0, 2.5, 2.5) -- a little forward, so the street side stays in frame
local CAMERA_FOV = 48
local CLIP_SECONDS = { 5, 5, 5, 6 }

local SHIELD_PANEL_HEIGHT = 7
local SHIELD_PANEL_ALPHA = 0.55
local RING_ALPHA = 0.55
local RING_THICKNESS = 0.06
local BEAM_HEIGHT = 7
local BEAM_WIDTH = 0.25
local ORB_ABOVE_HEAD = 2.6
local ORB_SPIN_DEG_PER_SEC = 40
local CATCH_ARC_HEIGHT = 8 -- the real catch's Bezier, scaled to the set
local HOLD_RING_SIZE = 46
local FLASH_SECONDS = 0.4

--[[ Types ---------------------------------------------------------------- ]]

type Actor = {
	Model: Model,
	Root: BasePart,
	RootHeight: number, -- root Y above the floor
	Run: AnimationTrack?,
	Idle: AnimationTrack?,
	Moving: boolean?,
}

type Pill = { Label: TextLabel, Holder: GuiObject }

export type Scene = {
	Frame: ViewportFrame,
	Step: (t: number) -> (), -- loop time is taken mod the clip length here
	Destroy: () -> (),
}

type Context = {
	Viewport: ViewportFrame,
	World: WorldModel,
	Camera: Camera,
	Overlay: Frame,
	Pills: { Pill },
}

--[[ Shared helpers --------------------------------------------------------- ]]

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- 0..1 progress of t through [a, b].
local function phase(t: number, a: number, b: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end

local function part(props: { [string]: any }, parent: Instance): BasePart
	local p = PartKit.Part({
		Name = props.Name,
		Size = props.Size,
		CFrame = props.CFrame,
		Color = props.Color,
		Shape = props.Shape,
		Material = props.Material,
		Transparency = props.Transparency,
		Parent = parent,
	})
	p.CanCollide = false
	p.CastShadow = false
	return p
end

-- Projects a world point through the scene camera to a scale position in
-- the viewport (or nil when it's behind the camera).
local function project(context: Context, world: Vector3): UDim2?
	local camera = context.Camera
	local local_ = camera.CFrame:PointToObjectSpace(world)
	if local_.Z >= -0.1 then
		return nil
	end
	local size = context.Viewport.AbsoluteSize
	local aspect = if size.Y > 0 then size.X / size.Y else 16 / 9
	local tanY = math.tan(math.rad(camera.FieldOfView) / 2)
	local x = (local_.X / -local_.Z) / (tanY * aspect)
	local y = (local_.Y / -local_.Z) / tanY
	return UDim2.fromScale((x + 1) / 2, (1 - y) / 2)
end

local function newPill(context: Context, text: string, color: Color3, textColor: Color3?): Pill
	local label = UIKit.Pill({
		Name = "ScenePill",
		Parent = context.Overlay,
		Text = text,
		Color = color,
		TextColor3 = textColor or Colors.Text,
		Font = Fonts.Display,
		TextSize = 15,
		Height = 26,
		TextStroke = 1.5,
		AnchorPoint = Vector2.new(0.5, 1),
	})
	local holder = UIKit.PillRoot(label)
	holder.Visible = false
	local pill: Pill = { Label = label, Holder = holder }
	table.insert(context.Pills, pill)
	return pill
end

-- Shows `pill` over `world` (hidden when `world` is nil).
local function placePill(context: Context, pill: Pill, world: Vector3?)
	local position = world and project(context, world)
	pill.Holder.Visible = position ~= nil
	if position then
		pill.Holder.Position = position
	end
end

--[[ The set ------------------------------------------------------------------ ]]

local function buildSet(world: WorldModel)
	part({
		Name = "Floor",
		Size = Vector3.new(FLOOR_SIZE, 1, WALL_Z + FLOOR_SIZE / 2),
		CFrame = CFrame.new(0, -0.5, (WALL_Z - FLOOR_SIZE / 2) / 2),
		Color = World.Floor,
	}, world)
	part({
		Name = "Street",
		Size = Vector3.new(FLOOR_SIZE, 1, FLOOR_SIZE / 2 - WALL_Z),
		CFrame = CFrame.new(0, -0.55, (WALL_Z + FLOOR_SIZE / 2) / 2),
		Color = World.Street,
	}, world)
	part({
		Name = "Walkway",
		Size = Vector3.new(PlotLayout.WALKWAY_WIDTH, 0.05, WALL_Z + FLOOR_SIZE / 2),
		CFrame = CFrame.new(0, 0.03, (WALL_Z - FLOOR_SIZE / 2) / 2),
		Color = World.Walkway,
	}, world)
	-- The wall along the front, with the gate gap where the walkway runs out.
	local half = FLOOR_SIZE / 2
	for _, side in { -1, 1 } do
		local length = half - GATE_HALF
		local x = side * (GATE_HALF + length / 2)
		part({
			Name = "Wall",
			Size = Vector3.new(length, PlotLayout.WALL_HEIGHT, PlotLayout.WALL_THICKNESS),
			CFrame = CFrame.new(x, PlotLayout.WALL_HEIGHT / 2, WALL_Z),
			Color = World.Structure,
		}, world)
		part({
			Name = "WallStrip",
			Size = Vector3.new(length, PlotLayout.WALL_STRIP_HEIGHT, PlotLayout.WALL_THICKNESS + 0.04),
			CFrame = CFrame.new(x, PlotLayout.WALL_HEIGHT, WALL_Z),
			Color = World.AccentViolet,
			Material = Enum.Material.Neon,
		}, world)
	end
end

-- A pedestal built like TycoonService's, styled by PedestalVisuals; returns
-- (pedestal, orb group, the orb group's home pivot).
local function buildPedestal(world: WorldModel, position: Vector3): (BasePart, Model?, CFrame)
	local p = PlotLayout.Pedestal
	local pedestal = part({
		Name = "Pedestal",
		Size = p.ColumnSize,
		CFrame = CFrame.new(position + Vector3.new(0, p.ColumnSize.Y / 2, 0)),
		Color = World.Structure,
	}, world)
	pedestal:SetAttribute("BaseSize", pedestal.Size)
	local cap = part({
		Name = "Cap",
		Size = p.CapSize,
		CFrame = pedestal.CFrame * CFrame.new(0, p.ColumnSize.Y / 2 + p.CapSize.Y / 2, 0),
		Color = World.StructureLight,
	}, pedestal)
	part({
		Name = "CapLip",
		Size = Vector3.new(p.CapSize.X + p.CapLipInflate, p.CapLipHeight, p.CapSize.Z + p.CapLipInflate),
		CFrame = cap.CFrame * CFrame.new(0, -(p.CapSize.Y / 2 + p.CapLipHeight / 2), 0),
		Color = World.StructureLight,
		Material = Enum.Material.Neon,
		Transparency = 1,
	}, cap)
	PedestalVisuals.Apply(pedestal, "Mythic", "Golden")
	local group: Model? = nil
	for _, descendant in pedestal:GetDescendants() do
		if descendant:IsA("Model") and descendant.Name == "OrbGroup" then
			group = descendant
			break
		end
	end
	local home = if group then group:GetPivot() else pedestal.CFrame
	return pedestal, group, home
end

-- A thin translucent disc on the floor (a guard ring). SmoothPlastic, not
-- Neon: the no-flat-Neon rule is about bloom in the world.
local function floorRing(world: WorldModel, center: Vector3, diameter: number, color: Color3): BasePart
	return part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(RING_THICKNESS, diameter, diameter),
		CFrame = CFrame.new(center + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = RING_ALPHA,
	}, world)
end

local function redBeam(world: WorldModel): BasePart
	return part({
		Name = "Beam",
		Size = Vector3.new(BEAM_WIDTH, BEAM_HEIGHT, BEAM_WIDTH),
		CFrame = CFrame.new(0, -100, 0),
		Color = Look.Beam,
		Transparency = 0.3,
	}, world)
end

local function itemLabel(): string
	local defs = ItemConfig.GetItemsByTier("Mythic")
	local name = if defs[1] then defs[1].Name else "Mythic"
	return MutationConfig.GetDisplayName(name, "Golden")
end

--[[ Actors ------------------------------------------------------------------- ]]

-- Animation ids from your own Animate script ("run" / "idle" StringValues).
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

-- Strips a cloned rig down to a puppet: no scripts, sounds, name tags,
-- forcefields; anchored root.
local function puppet(model: Model)
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BaseScript")
			or descendant:IsA("ModuleScript")
			or descendant:IsA("Sound")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("ForceField")
		then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CastShadow = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
end

local function makeActor(model: Model, world: WorldModel, runId: string?, idleId: string?): Actor?
	puppet(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end
	root.Anchored = true
	local height = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
	model.Parent = world
	return {
		Model = model,
		Root = root,
		RootHeight = height,
		Run = loadTrack(humanoid, runId),
		Idle = loadTrack(humanoid, idleId),
		Moving = nil,
	}
end

-- Puts `actor` at `position` (floor point) facing `toward`, running or idle.
local function pose(actor: Actor, position: Vector3, toward: Vector3, moving: boolean)
	local at = Vector3.new(position.X, actor.RootHeight, position.Z)
	local look = Vector3.new(toward.X, actor.RootHeight, toward.Z)
	actor.Root.CFrame = if (look - at).Magnitude > 0.01 then CFrame.lookAt(at, look) else CFrame.new(at)
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

-- Walks from a to b over [t0, t1]; returns (position, moving, facing point).
local function walk(t: number, t0: number, t1: number, a: Vector3, b: Vector3): (Vector3, boolean, Vector3)
	local u = phase(t, t0, t1)
	local moving = t > t0 and t < t1
	return a:Lerp(b, smooth(u)), moving, if (b - a).Magnitude > 0 then b + (b - a) else b
end

--[[ Rig templates (built once, cloned per scene) ------------------------------ ]]

local thiefTemplate: Model? = nil
local defaultTemplate: Model? = nil
local templatesRequested = false

local function buildTemplates()
	if templatesRequested then
		return
	end
	templatesRequested = true
	task.spawn(function()
		local okDefault, plain = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if okDefault and plain then
			plain.Archivable = true
			defaultTemplate = plain
		end
		local description = Instance.new("HumanoidDescription")
		description.HeadColor = Look.ThiefBody
		description.TorsoColor = Look.ThiefBody
		description.LeftArmColor = Look.ThiefBody
		description.RightArmColor = Look.ThiefBody
		description.LeftLegColor = Look.ThiefBody
		description.RightLegColor = Look.ThiefBody
		local okThief, thief = pcall(function()
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		if okThief and thief then
			thief.Archivable = true
			thiefTemplate = thief
		end
	end)
end

-- YOU: a puppet clone of your own character, else the default rig.
local function cloneYou(): Model?
	local character = localPlayer.Character
	if character then
		local wasArchivable = character.Archivable
		character.Archivable = true
		local ok, clone = pcall(function()
			return character:Clone()
		end)
		character.Archivable = wasArchivable
		if ok and clone then
			clone.Name = "You"
			return clone
		end
	end
	local template = defaultTemplate
	return if template then template:Clone() else nil
end

local function cloneThief(): Model?
	local template = thiefTemplate
	if not template then
		return nil
	end
	local clone = template:Clone()
	clone.Name = "Thief"
	return clone
end

--[[ Overlay pieces ---------------------------------------------------------------- ]]

-- The 2D "E" hold ring: a ring that fills (a growing disc) over the hold.
type HoldRing = { Frame: Frame, Fill: Frame }

local function newHoldRing(context: Context): HoldRing
	local ring = Instance.new("Frame")
	ring.Name = "HoldRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(HOLD_RING_SIZE, HOLD_RING_SIZE)
	ring.BackgroundColor3 = Colors.Panel
	ring.BackgroundTransparency = 0.2
	ring.Visible = false
	ring.Parent = context.Overlay
	UIKit.Corner(ring, 999)
	UIKit.Stroke(ring, 3, Colors.White)
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
		TextSize = 22,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = UITheme.Stroke.Text,
		ZIndex = 3,
		Parent = ring,
	})
	return { Frame = ring, Fill = fill }
end

-- The white flash ring at a catch.
local function newFlash(context: Context): Frame
	local ring = Instance.new("Frame")
	ring.Name = "Flash"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.Parent = context.Overlay
	UIKit.Corner(ring, 999)
	UIKit.Stroke(ring, 5, Colors.White)
	return ring
end

--[[ The clips ---------------------------------------------------------------------- ]]

-- Spins the orb group about its own centre at `center`.
local function placeOrb(group: Model?, center: Vector3, t: number)
	if group then
		group:PivotTo(CFrame.new(center) * CFrame.Angles(0, math.rad(ORB_SPIN_DEG_PER_SEC * t), 0))
	end
end

type Clip = (context: Context) -> ((t: number) -> ())

-- 1 GRAB
local function clipGrab(context: Context): (t: number) -> ()
	local world = context.World
	local _, orb, home = buildPedestal(world, Vector3.new(-5, 0, -3))
	local beam = redBeam(world)
	-- The "🏠 YOUR LAB" gate off to the right: two posts and a top bar.
	local gateX, gateZ = 15, -1
	for _, side in { -1, 1 } do
		part({
			Name = "HomePost",
			Size = Vector3.new(0.6, 5, 0.6),
			CFrame = CFrame.new(gateX, 2.5, gateZ + side * 2.5),
			Color = Look.HomeGate,
		}, world)
	end
	part({
		Name = "HomeBar",
		Size = Vector3.new(0.6, 0.6, 5.6),
		CFrame = CFrame.new(gateX, 5.2, gateZ),
		Color = Look.HomeGate,
	}, world)
	local you = makeActor(cloneYou() or Instance.new("Model"), world, readAnimationIds())
	local youPill = newPill(context, "YOU", Colors.Panel2)
	local itemPill = newPill(context, itemLabel(), Colors.Panel2, UITheme.GetTierLight("Mythic"))
	local homePill = newPill(context, "🏠 YOUR LAB", Look.HomeGate)
	local hold = newHoldRing(context)
	local start = Vector3.new(9, 0, 4)
	local atPedestal = Vector3.new(-2.4, 0, -3)
	local homeSpot = Vector3.new(gateX - 1, 0, gateZ)
	local holdStart, holdEnd = 1.3, 1.3 + HeistConfig.GrabHoldSeconds
	return function(t: number)
		local position, moving, facing
		if t < holdStart then
			position, moving, facing = walk(t, 0, holdStart - 0.1, start, atPedestal)
			if not moving then
				facing = home.Position
			end
		elseif t < holdEnd + 0.3 then
			position, moving, facing = atPedestal, false, home.Position
		else
			position, moving, facing = walk(t, holdEnd + 0.3, 4.4, atPedestal, homeSpot)
		end
		if you then
			pose(you, position, facing, moving)
		end
		-- The hold ring fills over GrabHoldSeconds.
		local holding = t >= holdStart and t < holdEnd
		hold.Frame.Visible = holding
		if holding then
			local at = project(context, home.Position + Vector3.new(0, 1.6, 0))
			if at then
				hold.Frame.Position = at
			end
			local u = phase(t, holdStart, holdEnd)
			hold.Fill.Size = UDim2.fromScale(u, u)
		end
		-- The orb: on the pedestal, then lifting over your head, then carried.
		local over = if you then headTop(you) + Vector3.new(0, ORB_ABOVE_HEAD, 0) else home.Position
		local orbAt = home.Position
		if t >= holdEnd then
			orbAt = home.Position:Lerp(over, smooth(phase(t, holdEnd, holdEnd + 0.3)))
		end
		placeOrb(orb, orbAt, t)
		local carried = t >= holdEnd + 0.3
		beam.CFrame = if carried then CFrame.new(orbAt + Vector3.new(0, BEAM_HEIGHT / 2 + 1.2, 0)) else CFrame.new(0, -100, 0)
		placePill(context, youPill, if you then headTop(you) + Vector3.new(0, 0.4, 0) else nil)
		placePill(context, itemPill, if carried then nil else home.Position + Vector3.new(0, 2.2, 0))
		placePill(context, homePill, Vector3.new(gateX, 6.2, gateZ))
	end
end

-- 2 GUARD
local function clipGuard(context: Context): (t: number) -> ()
	local world = context.World
	local pedestal, orb, home = buildPedestal(world, Vector3.new(-4, 0, -2))
	floorRing(world, Vector3.new(pedestal.Position.X, 0, pedestal.Position.Z), HeistConfig.OwnerBlockRadius * 2, Look.GuardRing)
	local you = makeActor(cloneYou() or Instance.new("Model"), world, readAnimationIds())
	local thief = makeActor(cloneThief() or Instance.new("Model"), world, readAnimationIds())
	local youPill = newPill(context, "YOU", Colors.Panel2)
	local thiefPill = newPill(context, "THIEF", Colors.Danger)
	local guardedPill = newPill(context, "🛡 GUARDED", Colors.ShieldTeal)
	local blockedPill = newPill(context, "✋ Owner is guarding", Colors.Danger)
	local ownerSpot = Vector3.new(-1.2, 0, -0.6)
	local far = Vector3.new(11, 0, 4)
	local near = Vector3.new(3.2, 0, -0.2)
	return function(t: number)
		placeOrb(orb, home.Position, t)
		if you then
			pose(you, ownerSpot, near, false)
		end
		local position, moving
		if t < 1.6 then
			position, moving = walk(t, 0, 1.5, far, near)
		elseif t < 3 then
			position, moving = near, false
		else
			-- Backs off still facing the pedestal.
			position, moving = walk(t, 3, 4.4, near, far)
		end
		if thief then
			pose(thief, position, pedestal.Position, moving)
		end
		placePill(context, guardedPill, home.Position + Vector3.new(0, 2.4, 0))
		placePill(context, youPill, if you then headTop(you) else nil)
		placePill(context, thiefPill, if thief then headTop(thief) else nil)
		placePill(context, blockedPill, if thief and t >= 1.6 and t < 3.4 then headTop(thief) + Vector3.new(0, 1.6, 0) else nil)
	end
end

-- 3 CATCH
local function clipCatch(context: Context): (t: number) -> ()
	local world = context.World
	local _, orb, home = buildPedestal(world, Vector3.new(-7, 0, -4))
	local beam = redBeam(world)
	local you = makeActor(cloneYou() or Instance.new("Model"), world, readAnimationIds())
	local thief = makeActor(cloneThief() or Instance.new("Model"), world, readAnimationIds())
	local youPill = newPill(context, "YOU", Colors.Panel2)
	local thiefPill = newPill(context, "THIEF", Colors.Danger)
	local caughtPill = newPill(context, "CAUGHT!", Colors.Panel, Colors.Danger)
	local flash = newFlash(context)
	local thiefFrom, thiefTo = Vector3.new(-3, 0, -2), Vector3.new(11, 0, 1)
	local catchAt = 2.0
	local thiefRun = 2.6 -- seconds to thiefTo if never caught
	local function thiefAt(time: number): Vector3
		return thiefFrom:Lerp(thiefTo, math.clamp(time / thiefRun, 0, 1))
	end
	local youFrom = Vector3.new(-8, 0, 2)
	local caughtSpot = thiefAt(catchAt)
	local flyStart, flyEnd = catchAt + 0.25, catchAt + 0.95
	return function(t: number)
		local thiefPos = if t < catchAt then thiefAt(t) else caughtSpot
		if thief then
			pose(thief, thiefPos, thiefPos + (thiefTo - thiefFrom), t < catchAt)
		end
		local youPos = youFrom:Lerp(caughtSpot - (thiefTo - thiefFrom).Unit * 1.6, math.clamp(t / catchAt, 0, 1))
		if you then
			pose(you, youPos, thiefPos, t < catchAt)
		end
		-- The orb: over the thief's head, then the real catch's Bezier home.
		local over = if thief then headTop(thief) + Vector3.new(0, ORB_ABOVE_HEAD, 0) else home.Position
		local orbAt: Vector3
		if t < flyStart then
			orbAt = over
		elseif t < flyEnd then
			local u = phase(t, flyStart, flyEnd)
			local p0, p2 = over, home.Position
			local p1 = (p0 + p2) / 2 + Vector3.new(0, CATCH_ARC_HEIGHT, 0)
			orbAt = p0:Lerp(p1, u):Lerp(p1:Lerp(p2, u), u)
		else
			orbAt = home.Position
		end
		placeOrb(orb, orbAt, t)
		beam.CFrame = if t < catchAt then CFrame.new(orbAt + Vector3.new(0, BEAM_HEIGHT / 2 + 1.2, 0)) else CFrame.new(0, -100, 0)
		-- The flash ring and CAUGHT!
		local flashing = t >= catchAt and t < catchAt + FLASH_SECONDS
		flash.Visible = flashing
		if flashing and thief then
			local at = project(context, thief.Root.Position)
			if at then
				flash.Position = at
			end
			local u = phase(t, catchAt, catchAt + FLASH_SECONDS)
			flash.Size = UDim2.fromOffset(30 + 150 * u, 30 + 150 * u)
			local stroke = flash:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = u
			end
		end
		placePill(context, youPill, if you then headTop(you) else nil)
		placePill(context, thiefPill, if thief and t < catchAt then headTop(thief) else nil)
		placePill(context, caughtPill, if thief and t >= catchAt and t < catchAt + 1.6 then headTop(thief) + Vector3.new(0, 0.4 + (t - catchAt), 0) else nil)
	end
end

-- 4 LOCK
local function clipLock(context: Context): (t: number) -> ()
	local world = context.World
	-- The real console, placed on the set (LOCK_CONSOLE is plot-local).
	local consoleSpot = Vector3.new(3, 0, 1.5)
	local origin = CFrame.new(consoleSpot - Vector3.new(PlotLayout.LOCK_CONSOLE.X, 0, PlotLayout.LOCK_CONSOLE.Z))
	local console = LockKit.Build(origin, world)
	-- SurfaceGuis don't render in a viewport, so the console's button gets a
	-- visible cap here (SmoothPlastic, recoloured on press).
	local top = console:FindFirstChild("Top")
	local L = PlotLayout.LockConsole
	local button = part({
		Name = "SceneButton",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.18, L.ButtonDiameter, L.ButtonDiameter),
		CFrame = (if top and top:IsA("BasePart") then top.CFrame else CFrame.new(consoleSpot))
			* CFrame.new(0, L.TopSize.Y / 2 + 0.09, 0)
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = World.Shield,
	}, world)
	for _, descendant in console:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
		end
	end
	-- The shield: flat pink panels along the wall, rising on LOCK.
	local panels: { BasePart } = {}
	local half = FLOOR_SIZE / 2
	local panelCFrames: { CFrame } = {}
	for _, x in { -half / 2 - GATE_HALF / 2, 0, half / 2 + GATE_HALF / 2 } do
		local width = if x == 0 then GATE_HALF * 2 + 0.2 else half - GATE_HALF + 0.2
		local panel = part({
			Name = "ShieldPanel",
			Size = Vector3.new(width, SHIELD_PANEL_HEIGHT, 0.12),
			CFrame = CFrame.new(x, -SHIELD_PANEL_HEIGHT / 2, WALL_Z),
			Color = World.Shield,
			Transparency = SHIELD_PANEL_ALPHA,
		}, world)
		table.insert(panels, panel)
		table.insert(panelCFrames, CFrame.new(x, SHIELD_PANEL_HEIGHT / 2, WALL_Z))
	end
	local you = makeActor(cloneYou() or Instance.new("Model"), world, readAnimationIds())
	local thief = makeActor(cloneThief() or Instance.new("Model"), world, readAnimationIds())
	local youPill = newPill(context, "YOU", Colors.Panel2)
	local thiefPill = newPill(context, "THIEF", Colors.Danger)
	local lockedPill = newPill(context, ("🔒 LOCKED · %ds"):format(HeistConfig.ShieldSeconds), Colors.ShieldTeal)
	local youFrom = Vector3.new(-9, 0, -4)
	local atConsole = consoleSpot + Vector3.new(-0.2, 0, 2.2)
	local thiefFrom = Vector3.new(1, 0, 15)
	local thiefWall = Vector3.new(0.5, 0, WALL_Z + 1.2)
	local thiefBack = Vector3.new(1.5, 0, WALL_Z + 3.5)
	local press, raised = 1.5, 2.2
	return function(t: number)
		local position, moving, facing = walk(t, 0, press - 0.1, youFrom, atConsole)
		if not moving and t >= press - 0.1 then
			facing = consoleSpot
		end
		if you then
			pose(you, position, facing, moving)
		end
		local locked = t >= press
		button.Color = if locked then Look.LockedButton else World.Shield
		local rise = smooth(phase(t, press, raised))
		for index, panel in panels do
			panel.CFrame = panelCFrames[index] * CFrame.new(0, -SHIELD_PANEL_HEIGHT * (1 - rise), 0)
		end
		-- The thief walks into the risen wall and is pushed back out.
		local thiefPos, thiefMoving
		if t < 2.8 then
			thiefPos, thiefMoving = walk(t, 0.4, 2.8, thiefFrom, thiefWall)
		elseif t < 3.4 then
			thiefPos, thiefMoving = thiefWall:Lerp(thiefBack, smooth(phase(t, 2.8, 3.4))), false
		else
			thiefPos, thiefMoving = thiefBack, false
		end
		if thief then
			pose(thief, thiefPos, Vector3.new(0, 0, 0), thiefMoving)
		end
		placePill(context, youPill, if you then headTop(you) else nil)
		placePill(context, thiefPill, if thief then headTop(thief) else nil)
		placePill(context, lockedPill, if t >= raised then consoleSpot + Vector3.new(0, 7, 0) else nil)
	end
end

local CLIPS: { Clip } = { clipGrab, clipGuard, clipCatch, clipLock }

--[[ Public ------------------------------------------------------------------------- ]]

-- Starts building the rig templates (they yield on the network); call once
-- early so the first open already has them.
function HeistScenes.Preload()
	buildTemplates()
end

-- Builds slide `index`'s scene in `parent` (a ViewportFrame filling it, with
-- the 2D overlay on top). Call Step(t) every frame while it's on screen.
function HeistScenes.Build(index: number, parent: GuiObject): Scene
	buildTemplates()
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Scene" .. index
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundColor3 = Look.Background
	viewport.Ambient = Look.Ambient
	viewport.LightColor = Look.LightColor
	viewport.LightDirection = Look.LightDirection
	viewport.ZIndex = parent.ZIndex
	viewport.Parent = parent
	UIKit.Corner(viewport, UITheme.Radius.Row)

	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = CAMERA_FOV
	camera.CFrame = CFrame.lookAt(CAMERA_TARGET + CAMERA_OFFSET, CAMERA_TARGET)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = viewport.ZIndex + 1
	overlay.ClipsDescendants = true
	overlay.Parent = parent

	local context: Context = { Viewport = viewport, World = world, Camera = camera, Overlay = overlay, Pills = {} }
	buildSet(world)
	local clip = CLIPS[index]
	local step: (t: number) -> () = function(_t: number) end
	if clip then
		step = clip(context)
	end
	for _, descendant in overlay:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = overlay.ZIndex + 1
		end
	end
	local length = CLIP_SECONDS[index] or 5

	return {
		Frame = viewport,
		Step = function(t: number)
			step(t % length)
		end,
		Destroy = function()
			viewport:Destroy()
			overlay:Destroy()
		end,
	}
end

return HeistScenes
