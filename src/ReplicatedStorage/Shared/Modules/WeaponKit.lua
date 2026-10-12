--!strict
--[[
	WeaponKit
	---------
	The five weapons as small models built from parts, welded to a small
	Handle (the grip, 0.4 x 1 x 0.4). Everything is in HANDLE space: the
	Handle's centre is the origin, +Y is up the grip, -Z is "forward" (where
	the weapon points when the arm is out), +X is the hand's right.

	  Build(id)         the Roblox Tool CombatService hands out (Grip* set
	                    so it sits IN the right hand)
	  BuildModel(id)    the same parts as an anchored Model, for
	                    ViewportFrames (the weapon bar, the unlock card)
	  BuildPlaced()     the Banana Peel on the floor: 3 curved petals and a
	                    stem round an invisible Hitbox (CombatService)
	  GetMuzzle/GetTrailPoints   attachments the client FX hang on
	  Validate(tool)    /selftest: Handle, every part welded + massless,
	                    nothing collides, fits a 4.5-stud box

	Rules: SmoothPlastic bodies plus thin Neon accents (colours from
	UITheme.World; the Freeze Ray's tank is Glass), no flat Neon circles
	(the Neon cylinders are thin bands seen from the side), every part
	Massless with CanCollide / CanQuery / CanTouch off, about 4 studs long
	at most.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)

local WeaponKit = {}

local World = UITheme.World
local PI = math.pi

WeaponKit.MAX_EXTENT = 4.5 -- studs: a weapon fits a box this big
local HANDLE_SIZE = Vector3.new(0.4, 1, 0.4)

type Builder = {
	Handle: BasePart,
	Container: Instance,
	Anchored: boolean,
}

type PartProps = {
	Name: string,
	Size: Vector3,
	At: CFrame, -- relative to the Handle
	Color: Color3,
	Material: Enum.Material?,
	Transparency: number?,
	Shape: Enum.PartType?,
	Ellipsoid: boolean?, -- a block with a Sphere SpecialMesh (non-uniform balls)
}

--[[ Part helpers ------------------------------------------------------------------- ]]

local function style(part: BasePart, anchored: boolean)
	part.Anchored = anchored
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function make(b: Builder, props: PartProps): Part
	local part = Instance.new("Part")
	part.Name = props.Name
	if props.Shape then
		part.Shape = props.Shape
	end
	part.Size = props.Size
	part.Color = props.Color
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	style(part, b.Anchored)
	part.CFrame = b.Handle.CFrame * props.At
	if props.Ellipsoid then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	local weld = Instance.new("Weld")
	weld.Name = "WeaponWeld"
	weld.Part0 = b.Handle
	weld.Part1 = part
	weld.C0 = props.At
	weld.C1 = CFrame.new()
	weld.Parent = part
	part.Parent = b.Container
	return part
end

local function block(b: Builder, name: string, size: Vector3, at: CFrame | Vector3, color: Color3, material: Enum.Material?, transparency: number?): Part
	return make(b, {
		Name = name,
		Size = size,
		At = if typeof(at) == "Vector3" then CFrame.new(at) else at,
		Color = color,
		Material = material,
		Transparency = transparency,
	})
end

-- A ball / ellipsoid (a Sphere mesh on a block, so every axis can differ).
local function blob(b: Builder, name: string, size: Vector3, at: CFrame | Vector3, color: Color3): Part
	return make(b, {
		Name = name,
		Size = size,
		At = if typeof(at) == "Vector3" then CFrame.new(at) else at,
		Color = color,
		Ellipsoid = true,
	})
end

-- Roblox cylinders run along their X axis; these rotate one to run along
-- Y / Z, or between two points.
local AXIS_TURN = {
	X = CFrame.new(),
	Y = CFrame.Angles(0, 0, PI / 2),
	Z = CFrame.Angles(0, PI / 2, 0),
}

local function cyl(
	b: Builder,
	name: string,
	axis: "X" | "Y" | "Z",
	center: Vector3,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?,
	transparency: number?
): Part
	return make(b, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		At = CFrame.new(center) * AXIS_TURN[axis],
		Color = color,
		Material = material,
		Transparency = transparency,
	})
end

local function cylBetween(b: Builder, name: string, from: Vector3, to: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	local length = (to - from).Magnitude
	return make(b, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		At = CFrame.lookAt((from + to) / 2, to) * AXIS_TURN.Z,
		Color = color,
		Material = material,
	})
end

local function attach(b: Builder, name: string, at: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = at
	attachment.Parent = b.Handle
end

--[[ Models --------------------------------------------------------------------------- ]]

local Neon = Enum.Material.Neon

-- Bat: a faceted taper (thin at the grip, fat at the end), a black grip
-- wrap, a knob, two lime Neon stripe bands, a dented "pro" look.
local BAT_FROM, BAT_TO = 0.5, 2.8
local BAT_D0, BAT_D1 = 0.40, 0.82
local BAT_SEGMENTS = 7

local function batDiameter(y: number): number
	return BAT_D0 + (BAT_D1 - BAT_D0) * math.clamp((y - BAT_FROM) / (BAT_TO - BAT_FROM), 0, 1)
end

local function buildBat(b: Builder)
	b.Handle.Color = World.WeaponGrip
	cyl(b, "GripWrap", "Y", Vector3.zero, 1.02, 0.5, World.WeaponGrip)
	cyl(b, "KnobNeck", "Y", Vector3.new(0, -0.54, 0), 0.14, 0.56, World.WeaponWood)
	blob(b, "Knob", Vector3.new(0.62, 0.62, 0.62), Vector3.new(0, -0.7, 0), World.WeaponWood)
	local step = (BAT_TO - BAT_FROM) / BAT_SEGMENTS
	for i = 1, BAT_SEGMENTS do
		local y = BAT_FROM + step * (i - 0.5)
		cyl(b, "Barrel" .. i, "Y", Vector3.new(0, y, 0), step + 0.03, batDiameter(y), World.WeaponWood)
	end
	blob(b, "BarrelEnd", Vector3.new(BAT_D1, BAT_D1, BAT_D1), Vector3.new(0, BAT_TO, 0), World.WeaponWood)
	for i, y in { 1.95, 2.3 } do
		cyl(b, "Stripe" .. i, "Y", Vector3.new(0, y, 0), 0.09, batDiameter(y) + 0.05, World.WeaponLime, Neon)
	end
	-- Dents: dark ellipsoids half sunk into the wood.
	blob(b, "Dent1", Vector3.new(0.12, 0.34, 0.28), Vector3.new(batDiameter(1.5) / 2 - 0.02, 1.5, 0.05), World.WeaponWoodDark)
	blob(b, "Dent2", Vector3.new(0.3, 0.3, 0.12), Vector3.new(-0.06, 2.62, -(batDiameter(2.62) / 2 - 0.02)), World.WeaponWoodDark)
	attach(b, "TrailA", Vector3.new(0, 3.0, 0))
	attach(b, "TrailB", Vector3.new(0, 1.7, 0))
end

-- The guns share a trigger guard under the body.
local function triggerGuard(b: Builder, color: Color3)
	block(b, "GuardFront", Vector3.new(0.1, 0.42, 0.1), Vector3.new(0, 0.3, -0.52), color)
	block(b, "GuardBottom", Vector3.new(0.1, 0.08, 0.42), Vector3.new(0, 0.1, -0.36), color)
	block(b, "Trigger", Vector3.new(0.08, 0.22, 0.08), Vector3.new(0, 0.34, -0.3), World.WeaponBodyDark)
end

-- Laser Gun: a chunky sci-fi blaster. Body, barrel with 2 cooling rings, a
-- glowing cyan core in the side window, grip, trigger guard, a scope fin.
local function buildLaserGun(b: Builder)
	b.Handle.Color = World.WeaponGrip
	block(b, "GripCap", Vector3.new(0.46, 0.12, 0.46), Vector3.new(0, -0.54, 0), World.WeaponBodyDark)
	block(b, "Body", Vector3.new(0.62, 0.66, 1.9), Vector3.new(0, 0.83, -0.3), World.WeaponBody)
	block(b, "TopRail", Vector3.new(0.34, 0.1, 1.6), Vector3.new(0, 1.2, -0.3), World.WeaponBodyDark)
	cyl(b, "Barrel", "Z", Vector3.new(0, 0.88, -1.8), 1.1, 0.3, World.WeaponBodyDark)
	cyl(b, "Ring1", "Z", Vector3.new(0, 0.88, -1.55), 0.14, 0.48, World.WeaponBody)
	cyl(b, "Ring2", "Z", Vector3.new(0, 0.88, -1.95), 0.14, 0.48, World.WeaponBody)
	cyl(b, "MuzzleGlow", "Z", Vector3.new(0, 0.88, -2.36), 0.06, 0.34, World.WeaponLaser, Neon)
	block(b, "WindowFrame", Vector3.new(0.64, 0.4, 0.74), Vector3.new(0, 0.86, -0.1), World.WeaponBodyDark)
	block(b, "Core", Vector3.new(0.68, 0.24, 0.6), Vector3.new(0, 0.86, -0.1), World.WeaponLaser, Neon)
	triggerGuard(b, World.WeaponBodyDark)
	block(b, "ScopeFin", Vector3.new(0.1, 0.28, 1), Vector3.new(0, 1.38, -0.5), World.WeaponBody)
	block(b, "ScopeStrip", Vector3.new(0.12, 0.04, 0.9), Vector3.new(0, 1.54, -0.5), World.WeaponLaser, Neon)
	attach(b, "Muzzle", Vector3.new(0, 0.88, -2.42))
end

-- Freeze Ray: the blaster shape in white / ice blue, a coiled barrel (3
-- thin rings), a frosted glass tank (Glass, transparency 0.4) with a light
-- blue Neon core.
local function buildFreezeRay(b: Builder)
	b.Handle.Color = World.IceDeep
	block(b, "GripCap", Vector3.new(0.46, 0.12, 0.46), Vector3.new(0, -0.54, 0), World.IceWhite)
	block(b, "Body", Vector3.new(0.6, 0.6, 1.5), Vector3.new(0, 0.8, -0.15), World.IceWhite)
	blob(b, "BodyRear", Vector3.new(0.62, 0.62, 0.62), Vector3.new(0, 0.8, 0.6), World.IceWhite)
	block(b, "SideStrip", Vector3.new(0.63, 0.06, 1), Vector3.new(0, 0.96, -0.15), World.Ice, Neon)
	cyl(b, "TankCapRear", "Z", Vector3.new(0, 1.4, 0.38), 0.12, 0.68, World.IceDeep)
	cyl(b, "TankCapFront", "Z", Vector3.new(0, 1.4, -0.78), 0.12, 0.68, World.IceDeep)
	cyl(b, "TankCore", "Z", Vector3.new(0, 1.4, -0.2), 0.95, 0.34, World.Ice, Neon)
	cyl(b, "Tank", "Z", Vector3.new(0, 1.4, -0.2), 1.1, 0.62, World.IceGlass, Enum.Material.Glass, 0.4)
	cyl(b, "Barrel", "Z", Vector3.new(0, 0.8, -1.5), 1.2, 0.26, World.IceDeep)
	for i, z in { -1.2, -1.5, -1.8 } do
		cyl(b, "Coil" .. i, "Z", Vector3.new(0, 0.8, z), 0.07, 0.42, World.Ice, Neon)
	end
	cyl(b, "Flare", "Z", Vector3.new(0, 0.8, -2.12), 0.2, 0.5, World.IceWhite)
	triggerGuard(b, World.IceDeep)
	attach(b, "Muzzle", Vector3.new(0, 0.8, -2.3))
end

-- Slap Glove: a big red cartoon glove: puffy palm, 4 fingers stacked up
-- the side, a thumb, a white cuff. The Handle is invisible inside it.
local FINGER_LENGTHS = { 0.85, 0.95, 0.85, 0.7 }

local function buildSlapGlove(b: Builder)
	b.Handle.Transparency = 1
	blob(b, "Palm", Vector3.new(0.8, 1.3, 1.1), Vector3.new(0, 0, -0.1), World.GloveRed)
	for i, length in FINGER_LENGTHS do
		local y = 0.48 - (i - 1) * 0.32
		cyl(b, "Finger" .. i, "Z", Vector3.new(0, y, -0.5 - length / 2), length, 0.34, World.GloveRed)
		blob(b, "FingerTip" .. i, Vector3.new(0.34, 0.34, 0.34), Vector3.new(0, y, -0.5 - length), World.GloveRed)
	end
	local thumbBase = Vector3.new(-0.2, 0.5, -0.1)
	local thumbTip = thumbBase + Vector3.new(-0.1, 0.55, -0.4)
	cylBetween(b, "Thumb", thumbBase, thumbTip, 0.38, World.GloveRed)
	blob(b, "ThumbTip", Vector3.new(0.38, 0.38, 0.38), thumbTip, World.GloveRed)
	-- Three white ridges across the back of the hand.
	for i, z in { -0.4, -0.15, 0.1 } do
		block(b, "Ridge" .. i, Vector3.new(0.06, 0.8, 0.07), Vector3.new(0.38, 0, z), World.CapsuleWhite)
	end
	cyl(b, "Cuff", "Z", Vector3.new(0, 0, 0.5), 0.5, 1.05, World.CapsuleWhite)
	attach(b, "TrailA", Vector3.new(0, 0.6, -1.35))
	attach(b, "TrailB", Vector3.new(0, -0.6, -1.2))
end

-- Banana (in the hand): a crescent of fat segments from a brown stem at the
-- palm, curving up and forward to a dark tip.
local BANANA_SEGMENTS = 7
local BANANA_RADIUS = 1.7
local BANANA_SWEEP = math.rad(85)
local BANANA_START = Vector3.new(0, -0.35, 0.05)

local function bananaPoint(theta: number): Vector3
	return BANANA_START + Vector3.new(0, BANANA_RADIUS * math.sin(theta), -BANANA_RADIUS * (1 - math.cos(theta)))
end

local function buildBananaInHand(b: Builder)
	b.Handle.Transparency = 1
	cylBetween(b, "Stem", BANANA_START + Vector3.new(0, -0.3, 0.02), BANANA_START, 0.2, World.BananaStem)
	for i = 1, BANANA_SEGMENTS do
		local from = bananaPoint(BANANA_SWEEP * (i - 1) / BANANA_SEGMENTS)
		local to = bananaPoint(BANANA_SWEEP * i / BANANA_SEGMENTS)
		local thickness = 0.3 + 0.22 * math.sin(PI * (i - 0.5) / BANANA_SEGMENTS)
		-- A touch longer so neighbouring segments overlap.
		local along = (to - from).Unit * 0.04
		cylBetween(b, "Segment" .. i, from - along, to + along, thickness, World.Banana)
	end
	blob(b, "Tip", Vector3.new(0.24, 0.24, 0.24), bananaPoint(BANANA_SWEEP), World.BananaStem)
end

local BUILDERS: { [string]: (Builder) -> () } = {
	Bat = buildBat,
	LaserGun = buildLaserGun,
	FreezeRay = buildFreezeRay,
	SlapGlove = buildSlapGlove,
	BananaPeel = buildBananaInHand,
}

--[[ How each one sits in the right hand ------------------------------------------------
	The grip frame is the Handle's axes in the hand's frame: with the arm
	out front, +Y = up, -Z = forward. The guns and the glove need none of it
	(they point straight forward); the Bat tilts forward 25 degrees so it
	reads "up and forward".
]]
local BAT_TILT = math.rad(25)

local GRIPS: { [string]: { Pos: Vector3, Forward: Vector3, Right: Vector3, Up: Vector3 } } = {
	Bat = {
		Pos = Vector3.new(0, -0.1, 0),
		Forward = Vector3.new(0, -math.sin(BAT_TILT), -math.cos(BAT_TILT)),
		Right = Vector3.new(1, 0, 0),
		Up = Vector3.new(0, math.cos(BAT_TILT), -math.sin(BAT_TILT)),
	},
	LaserGun = { Pos = Vector3.new(0, 0, 0), Forward = Vector3.new(0, 0, -1), Right = Vector3.new(1, 0, 0), Up = Vector3.new(0, 1, 0) },
	FreezeRay = { Pos = Vector3.new(0, 0, 0), Forward = Vector3.new(0, 0, -1), Right = Vector3.new(1, 0, 0), Up = Vector3.new(0, 1, 0) },
	SlapGlove = { Pos = Vector3.new(0, 0, 0.1), Forward = Vector3.new(0, 0, -1), Right = Vector3.new(1, 0, 0), Up = Vector3.new(0, 1, 0) },
	BananaPeel = { Pos = Vector3.new(0, 0, 0), Forward = Vector3.new(0, 0, -1), Right = Vector3.new(1, 0, 0), Up = Vector3.new(0, 1, 0) },
}

-- How the model is turned for a ViewportFrame (the bat leans, the rest
-- tip toward the camera a little).
local DISPLAY_TILT: { [string]: CFrame } = {
	Bat = CFrame.Angles(0, 0, math.rad(-38)),
	LaserGun = CFrame.Angles(math.rad(12), 0, 0),
	FreezeRay = CFrame.Angles(math.rad(12), 0, 0),
	SlapGlove = CFrame.Angles(math.rad(10), 0, math.rad(-12)),
	BananaPeel = CFrame.Angles(0, 0, math.rad(-10)),
}

--[[ Public API ----------------------------------------------------------------------- ]]

local function newHandle(anchored: boolean): Part
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = HANDLE_SIZE
	handle.Material = Enum.Material.SmoothPlastic
	handle.Color = World.WeaponGrip
	style(handle, anchored)
	return handle
end

local function assemble(weaponId: string, container: Instance, handle: Part, anchored: boolean)
	handle.Parent = container
	local build = BUILDERS[weaponId] or BUILDERS.Bat
	build({ Handle = handle, Container = container, Anchored = anchored })
end

-- The Roblox Tool for `weaponId` (CombatService; one per owned weapon).
function WeaponKit.Build(weaponId: string): Tool
	local id = if BUILDERS[weaponId] then weaponId else "Bat"
	local weapon = CombatConfig.GetWeapon(id)
	local tool = Instance.new("Tool")
	tool.Name = id
	tool.ToolTip = if weapon then weapon.Name else id
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("Weapon", id)
	local grip = GRIPS[id]
	tool.GripPos = grip.Pos
	tool.GripForward = grip.Forward
	tool.GripRight = grip.Right
	tool.GripUp = grip.Up
	assemble(id, tool, newHandle(false), false)
	return tool
end

-- The same parts as an anchored Model (PrimaryPart = Handle) at the
-- origin, for ViewportFrames.
function WeaponKit.BuildModel(weaponId: string): Model
	local id = if BUILDERS[weaponId] then weaponId else "Bat"
	local model = Instance.new("Model")
	model.Name = id
	local handle = newHandle(true)
	assemble(id, model, handle, true)
	model.PrimaryPart = handle
	return model
end

-- How a viewport should turn the model before spinning it.
function WeaponKit.GetDisplayTilt(weaponId: string): CFrame
	return DISPLAY_TILT[weaponId] or CFrame.new()
end

--[[ The Banana Peel on the floor ------------------------------------------------------
	3 curved yellow petals splayed 120 degrees apart round a brown stem. All
	anchored cosmetic parts, plus an invisible "Hitbox" (the Touched sensor,
	CombatConfig.Peel.Size). The pivot is the floor point under the stem, so
	`model:PivotTo(CFrame.new(ground))`.
]]
local PETAL_SEGMENTS = {
	{ Radius = 0.3, Length = 0.38, Width = 0.5, Tilt = 4 },
	{ Radius = 0.62, Length = 0.34, Width = 0.42, Tilt = 20 },
	{ Radius = 0.9, Length = 0.28, Width = 0.3, Tilt = 40 },
}
local PETAL_THICKNESS = 0.1

function WeaponKit.BuildPlaced(): Model
	local model = Instance.new("Model")
	model.Name = "BananaPeel"
	local function cosmetic(part: Part)
		style(part, true)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.Parent = model
	end
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = CombatConfig.Peel.Size
	hitbox.CFrame = CFrame.new(0, CombatConfig.Peel.Size.Y / 2, 0)
	hitbox.Transparency = 1
	style(hitbox, true)
	hitbox.CanTouch = true
	hitbox.Parent = model
	model.WorldPivot = CFrame.new() -- the floor point under the stem

	for petal = 0, 2 do
		local yaw = CFrame.Angles(0, math.rad(petal * 120), 0)
		for index, segment in PETAL_SEGMENTS do
			local tilt = math.rad(segment.Tilt)
			local part = Instance.new("Part")
			part.Name = ("Petal%d_%d"):format(petal + 1, index)
			part.Size = Vector3.new(segment.Width, PETAL_THICKNESS, segment.Length)
			part.Material = Enum.Material.SmoothPlastic
			part.Color = if index == #PETAL_SEGMENTS then World.BananaStem else World.Banana
			-- Out along -Z, rising a little more toward the tip.
			local rise = PETAL_THICKNESS / 2 + math.sin(tilt) * segment.Length / 2 + (index - 1) * 0.05
			part.CFrame = yaw * CFrame.new(0, rise, -segment.Radius) * CFrame.Angles(tilt, 0, 0)
			cosmetic(part)
		end
	end
	local stem = Instance.new("Part")
	stem.Name = "Stem"
	stem.Shape = Enum.PartType.Cylinder
	stem.Size = Vector3.new(0.34, 0.26, 0.26)
	stem.Material = Enum.Material.SmoothPlastic
	stem.Color = World.BananaStem
	stem.CFrame = CFrame.new(0, 0.17, 0) * CFrame.Angles(0, 0, PI / 2)
	cosmetic(stem)
	return model
end

--[[ Attachments the FX hang on -------------------------------------------------------- ]]

function WeaponKit.GetHandle(tool: Instance): BasePart?
	local handle = tool:FindFirstChild("Handle")
	return if handle and handle:IsA("BasePart") then handle else nil
end

-- The gun's muzzle (nil for melee).
function WeaponKit.GetMuzzle(tool: Instance): Attachment?
	local handle = WeaponKit.GetHandle(tool)
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	return if muzzle and muzzle:IsA("Attachment") then muzzle else nil
end

-- The Bat's / Glove's swing-trail points (nil for the rest).
function WeaponKit.GetTrailPoints(tool: Instance): (Attachment?, Attachment?)
	local handle = WeaponKit.GetHandle(tool)
	local a = handle and handle:FindFirstChild("TrailA")
	local b = handle and handle:FindFirstChild("TrailB")
	if a and a:IsA("Attachment") and b and b:IsA("Attachment") then
		return a, b
	end
	return nil, nil
end

--[[ /selftest ----------------------------------------------------------------------- ]]

-- Size of the box (in Handle axes) that holds every part.
function WeaponKit.GetExtent(container: Instance): Vector3
	local handle = WeaponKit.GetHandle(container)
	if not handle then
		return Vector3.zero
	end
	local inverse = handle.CFrame:Inverse()
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BasePart") then
			local half = descendant.Size / 2
			local relative = inverse * descendant.CFrame
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = relative:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						low = low:Min(corner)
						high = high:Max(corner)
					end
				end
			end
		end
	end
	return high - low
end

-- nil when `tool` is a sound weapon build, else what is wrong with it.
function WeaponKit.Validate(tool: Instance): string?
	local handle = WeaponKit.GetHandle(tool)
	if not handle then
		return "no Handle"
	end
	if handle.Size.Y > 1.05 or handle.Size.X > 0.45 or handle.Size.Z > 0.45 then
		return "Handle is not a grip-sized part"
	end
	local welded: { [Instance]: boolean } = {}
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("Weld") or descendant:IsA("WeldConstraint") then
			local joint = descendant :: any
			if joint.Part0 == handle and joint.Part1 then
				welded[joint.Part1] = true
			elseif joint.Part1 == handle and joint.Part0 then
				welded[joint.Part0] = true
			end
		end
	end
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("BasePart") then
			if not descendant.Massless then
				return descendant.Name .. " is not Massless"
			end
			if descendant.CanCollide or descendant.CanQuery or descendant.CanTouch then
				return descendant.Name .. " can collide / query / touch"
			end
			if descendant ~= handle and not welded[descendant] then
				return descendant.Name .. " is not welded to the Handle"
			end
			-- No flat Neon circles: a Neon cylinder shorter than it is wide
			-- is a thin band seen from the side, never a chunky disc.
			if descendant.Material == Enum.Material.Neon and descendant:IsA("Part") and descendant.Shape == Enum.PartType.Cylinder then
				if descendant.Size.X < descendant.Size.Y and descendant.Size.X > 0.1 then
					return descendant.Name .. " is a flat Neon disc"
				end
			end
		end
	end
	local extent = WeaponKit.GetExtent(tool)
	if extent.X > WeaponKit.MAX_EXTENT or extent.Y > WeaponKit.MAX_EXTENT or extent.Z > WeaponKit.MAX_EXTENT then
		return ("%s is bigger than %.1f studs"):format(tostring(extent), WeaponKit.MAX_EXTENT)
	end
	return nil
end

return WeaponKit
