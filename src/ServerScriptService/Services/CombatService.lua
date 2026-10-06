--!strict
--[[
	CombatService
	-------------
	Weapons and ragdoll (every number in CombatConfig). Cartoon bonks: no
	health, no damage, no deaths.

	  * Weapons are earned: rebirth milestones (an OnSync hook grants them,
	    PlayerData.Weapons, and fires WeaponUnlocked for the card); quest
	    weapons come later (Studio: /weapons all | reset). Each one is a
	    Roblox Tool in the Backpack, given on every spawn.
	  * A hit: the client only sends RequestHit { Weapon, TargetUserId?,
	    Origin, Direction }. Everything is re-checked here: the weapon is
	    owned AND equipped (the Tool is in the character), its cooldown (here,
	    per player and weapon), both sides' eligibility (Rebirth 1+, not
	    protected, not spawn-protected, not ragdolled / immune, the attacker
	    not carrying), range from the server's own roots plus RangeSlack,
	    a melee target in front of you, and for ranged weapons a server
	    raycast with line of sight. Numbers through RemoteGuard; rate-limited.
	  * Ragdoll: the server owns the until-times (Player attributes
	    RagdollUntil / ImmuneUntil / FrozenUntil / SpawnProtectUntil, server
	    time). It swaps the target's Motor6Ds for BallSocketConstraints
	    (replicated to everyone), fires HitReceived { Impulse, Seconds } to
	    the target (whose client goes Physical and takes the impulse) and
	    restores the joints after RagdollSeconds. A client that ignores it
	    breaks nothing: the server's times still gate everything.
	  * Freeze Ray: no ragdoll; FrozenUntil, the target's client walks at
	    Freeze.SpeedMultiplier.
	  * Banana Peel: placed near you (one out, LifetimeSeconds), the first
	    eligible enemy to touch it is ragdolled.
	  * Hitting a carrying thief: HeistService.KnockCarrier (the orb goes
	    home, the owner sees SAVED). Analytics: Hit (weapon), ThiefKnocked,
	    GuardKnocked.
	  * HitFx { Weapon, Kind, From, To } to everyone: the bonk / beam /
	    freeze / slip effects (CombatController).

	Follows the ServiceTemplate contract.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)
local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type HeistServiceModule = typeof(require(script.Parent.HeistService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))

local PlayerDataService: PlayerDataServiceModule
local HeistService: HeistServiceModule
local TycoonService: TycoonServiceModule

local CombatService = {}
CombatService.Name = "CombatService"

local World = UITheme.World
local MAX_COORDINATE = 1e5
local ROOT_JOINT_NAMES = { RootJoint = true, Root = true }
local FOLDER_NAME = "CombatObjects"

type Joint = { Motor: Motor6D, Constraint: BallSocketConstraint, A0: Attachment, A1: Attachment }

local state = {
	-- userId -> weapon id -> os.clock() of the last accepted swing
	lastSwing = {} :: { [number]: { [string]: number } },
	-- userId -> the joints swapped out for the current ragdoll
	joints = {} :: { [number]: { Joint } },
	-- userId -> placed banana peels
	peels = {} :: { [number]: { BasePart } },
	folder = nil :: Folder?,
}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function untilActive(player: Player, attribute: string): boolean
	local value = player:GetAttribute(attribute)
	return typeof(value) == "number" and value > serverNow()
end

--[[ Eligibility -------------------------------------------------------------------- ]]

-- Why `player` can't fight at all (nil = they can): the stealing gate.
local function whyCantFight(player: Player): string?
	if not PlayerDataService.IsDataLoaded(player) then
		return "DataNotLoaded"
	end
	if PlayerDataService.GetRebirths(player) < CombatConfig.MinRebirths then
		return "NeedsRebirth"
	end
	local humanoid = getHumanoid(player)
	if not humanoid or humanoid.Health <= 0 or not getRoot(player) then
		return "NoCharacter"
	end
	return nil
end

-- Why `target` can't be hit right now (nil = it can).
function CombatService.WhyNotHittable(target: Player): string?
	local why = whyCantFight(target)
	if why then
		return why
	end
	if untilActive(target, "SpawnProtectUntil") then
		return "SpawnProtected"
	end
	if untilActive(target, "RagdollUntil") or untilActive(target, "ImmuneUntil") then
		return "Immune"
	end
	return nil
end

-- Why `attacker` can't swing `weapon` (nil = they can); doesn't touch the
-- cooldown.
local function whyCantSwing(attacker: Player, weapon: CombatConfig.Weapon): string?
	local why = whyCantFight(attacker)
	if why then
		return why
	end
	if not PlayerDataService.GetWeapons(attacker)[weapon.Id] then
		return "NotOwned"
	end
	local character = attacker.Character
	local tool = character and character:FindFirstChild(weapon.Id)
	if not tool or not tool:IsA("Tool") then
		return "NotEquipped"
	end
	if PlayerDataService.IsCarrying(attacker) then
		return "Carrying"
	end
	if untilActive(attacker, "RagdollUntil") then
		return "Ragdolled"
	end
	return nil
end

-- The server-side cooldown: true (and the swing is recorded) if it's ready.
function CombatService.TakeCooldown(player: Player, weapon: CombatConfig.Weapon): boolean
	local swings = state.lastSwing[player.UserId] or {}
	state.lastSwing[player.UserId] = swings
	local last = swings[weapon.Id]
	local now = os.clock()
	if last and now - last < weapon.Cooldown then
		return false
	end
	swings[weapon.Id] = now
	return true
end

-- /selftest: forget every swing, so the cooldown test starts clean.
function CombatService.ResetCooldowns(player: Player)
	state.lastSwing[player.UserId] = nil
end

--[[ Ragdoll --------------------------------------------------------------------------- ]]

local function restoreJoints(userId: number)
	local joints: { Joint } = state.joints[userId] or {}
	state.joints[userId] = nil
	for _, joint in joints do
		joint.Constraint:Destroy()
		joint.A0:Destroy()
		joint.A1:Destroy()
		if joint.Motor.Parent then
			joint.Motor.Enabled = true
		end
	end
end

-- Motor6D -> BallSocketConstraint (the root joint stays), replicated.
local function swapJoints(player: Player)
	local character = player.Character
	if not character then
		return
	end
	restoreJoints(player.UserId)
	local joints: { Joint } = {}
	for _, motor in character:GetDescendants() do
		if motor:IsA("Motor6D") and not ROOT_JOINT_NAMES[motor.Name] and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 60
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -45
			socket.TwistUpperAngle = 45
			socket.Parent = motor.Parent
			motor.Enabled = false
			table.insert(joints, { Motor = motor, Constraint = socket, A0 = a0, A1 = a1 })
		end
	end
	state.joints[player.UserId] = joints
end

-- Ragdolls `target` for RagdollSeconds with `impulse` (studs/s).
local function ragdoll(target: Player, impulse: Vector3)
	local seconds = CombatConfig.RagdollSeconds
	local now = serverNow()
	target:SetAttribute("RagdollUntil", now + seconds)
	target:SetAttribute("ImmuneUntil", now + seconds + CombatConfig.GetUpImmuneSeconds)
	swapJoints(target)
	RemoteEvents.HitReceived:FireClient(target, { Impulse = impulse, Seconds = seconds })
	local character = target.Character
	task.delay(seconds, function()
		if target.Character == character then
			restoreJoints(target.UserId)
		end
	end)
end

local function freeze(target: Player)
	local seconds = CombatConfig.Freeze.Seconds
	local now = serverNow()
	target:SetAttribute("FrozenUntil", now + seconds)
	target:SetAttribute("ImmuneUntil", now + seconds)
	RemoteEvents.HitReceived:FireClient(target, { Freeze = true, Seconds = seconds })
end

-- A guard: standing at one of their own pedestals that HeistService marks
-- GuardedByOwner.
local function isGuarding(player: Player): boolean
	local plot = TycoonService.GetPlotForPlayer(player)
	local pedestals = plot and plot:FindFirstChild("Pedestals")
	local children: { Instance } = if pedestals then pedestals:GetChildren() else {}
	for _, pedestal in children do
		if pedestal:GetAttribute("GuardedByOwner") == true then
			return true
		end
	end
	return false
end

-- A confirmed hit: the heist knock, the ragdoll / freeze, the FX, analytics.
function CombatService.ApplyHit(attacker: Player?, target: Player, weapon: CombatConfig.Weapon, from: Vector3)
	local targetRoot = getRoot(target)
	if not targetRoot then
		return
	end
	if attacker and isGuarding(target) then
		AnalyticsKit.Custom(attacker, "GuardKnocked")
	end
	if HeistService.KnockCarrier(target) and attacker then
		AnalyticsKit.Custom(attacker, "ThiefKnocked")
	end
	if weapon.Kind == "Freeze" then
		freeze(target)
	else
		local away = targetRoot.Position - from
		local flat = Vector3.new(away.X, 0, away.Z)
		local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)
		ragdoll(target, direction * weapon.Knockback + Vector3.new(0, CombatConfig.UpwardKick, 0))
	end
	RemoteEvents.HitFx:FireAllClients({
		Weapon = weapon.Id,
		Kind = if weapon.Kind == "Freeze" then "Freeze" elseif weapon.Kind == "Peel" then "Slip" else "Bonk",
		From = from,
		To = targetRoot.Position,
	})
	if attacker then
		AnalyticsKit.Custom(attacker, "Hit", nil, weapon.Id)
	end
end

--[[ Tools ---------------------------------------------------------------------------- ]]

local HANDLES: { [string]: { Size: Vector3, Color: Color3 } } = {
	Bat = { Size = Vector3.new(0.5, 0.5, 4), Color = World.WeaponWood },
	LaserGun = { Size = Vector3.new(0.6, 0.9, 2), Color = World.WeaponBody },
	FreezeRay = { Size = Vector3.new(0.6, 0.9, 2.2), Color = World.Ice },
	SlapGlove = { Size = Vector3.new(1.2, 1.2, 0.6), Color = World.GloveRed },
	BananaPeel = { Size = Vector3.new(1, 0.4, 1), Color = World.Banana },
}

local function buildTool(weapon: CombatConfig.Weapon): Tool
	local tool = Instance.new("Tool")
	tool.Name = weapon.Id
	tool.ToolTip = weapon.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("Weapon", weapon.Id)
	local look = HANDLES[weapon.Id] or HANDLES.Bat
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = look.Size
	handle.Color = look.Color
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = tool
	tool.GripPos = Vector3.new(0, 0, -look.Size.Z / 2 + 0.4)
	return tool
end

-- Puts every owned weapon in the Backpack (once each; none left over).
local function giveTools(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local owned = PlayerDataService.GetWeapons(player)
	local character = player.Character
	local containers: { Instance } = { backpack }
	if character then
		table.insert(containers, character)
	end
	for _, container in containers do
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("Weapon") and not owned[child.Name] then
				child:Destroy()
			end
		end
	end
	for _, weapon in CombatConfig.Weapons do
		if owned[weapon.Id] and not backpack:FindFirstChild(weapon.Id) and not (character and character:FindFirstChild(weapon.Id)) then
			buildTool(weapon).Parent = backpack
		end
	end
end

-- The sync hook: rebirth milestones grant their weapons.
local function grantByRebirths(player: Player)
	local granted = false
	for _, id in CombatConfig.GetUnlockedByRebirths(PlayerDataService.GetRebirths(player)) do
		if PlayerDataService.GrantWeapon(player, id) then
			granted = true
			RemoteEvents.WeaponUnlocked:FireClient(player, { Weapon = id })
		end
	end
	if granted then
		giveTools(player)
	end
end

-- Studio /weapons all | reset.
function CombatService.DebugSetAll(player: Player, all: boolean)
	if all then
		for _, weapon in CombatConfig.Weapons do
			if PlayerDataService.GrantWeapon(player, weapon.Id) then
				RemoteEvents.WeaponUnlocked:FireClient(player, { Weapon = weapon.Id })
			end
		end
	else
		PlayerDataService.ResetWeapons(player)
	end
	giveTools(player)
end

--[[ Banana Peel ----------------------------------------------------------------------- ]]

local function getFolder(): Folder
	local folder = state.folder
	if folder and folder.Parent then
		return folder
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	state.folder = created
	return created
end

local function placePeel(owner: Player, weapon: CombatConfig.Weapon, at: Vector3): boolean
	local peels = state.peels[owner.UserId] or {}
	state.peels[owner.UserId] = peels
	for index = #peels, 1, -1 do
		if not peels[index].Parent then
			table.remove(peels, index)
		end
	end
	if #peels >= CombatConfig.Peel.MaxOut then
		return false
	end
	-- On the floor under the requested point.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ownerExclude: { Instance } = { getFolder() }
	if owner.Character then
		table.insert(ownerExclude, owner.Character)
	end
	params.FilterDescendantsInstances = ownerExclude
	local ground = Workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
	if not ground then
		return false
	end
	local peel = PartKit.Part({
		Name = "BananaPeel",
		Size = CombatConfig.Peel.Size,
		CFrame = CFrame.new(ground.Position + Vector3.new(0, CombatConfig.Peel.Size.Y / 2, 0)),
		Color = World.Banana,
		CanCollide = false,
		Parent = getFolder(),
	})
	peel.CanQuery = false
	peel.CanTouch = true
	peel:SetAttribute("OwnerUserId", owner.UserId)
	table.insert(peels, peel)
	peel.Touched:Connect(function(hit: BasePart)
		if not peel.Parent then
			return
		end
		local character = hit:FindFirstAncestorWhichIsA("Model")
		local victim = character and Players:GetPlayerFromCharacter(character)
		if not victim or victim == owner or CombatService.WhyNotHittable(victim) then
			return
		end
		local position = peel.Position
		peel:Destroy()
		CombatService.ApplyHit(if owner.Parent then owner else nil, victim, weapon, position)
	end)
	task.delay(CombatConfig.Peel.LifetimeSeconds, function()
		if peel.Parent then
			peel:Destroy()
		end
	end)
	return true
end

--[[ RequestHit -------------------------------------------------------------------------- ]]

local function vector(value: unknown): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local v = value :: Vector3
	for _, n in { v.X, v.Y, v.Z } do
		if n ~= n or math.abs(n) > MAX_COORDINATE then
			return nil
		end
	end
	return v
end

local function onRequestHit(attacker: Player, payload: unknown)
	if not RemoteGuard.Allow(attacker, "RequestHit", CombatConfig.HitsPerSecond, CombatConfig.HitBurst) then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local p = payload :: any
	local weapon = CombatConfig.GetWeapon(p.Weapon)
	if not weapon or whyCantSwing(attacker, weapon) then
		return
	end
	local root = getRoot(attacker) :: BasePart
	if not CombatService.TakeCooldown(attacker, weapon) then
		return
	end

	if weapon.Kind == "Melee" then
		local targetId = RemoteGuard.Int(p.TargetUserId, 1, 2 ^ 53)
		local target = targetId and Players:GetPlayerByUserId(targetId)
		local targetRoot = target and getRoot(target)
		if not target or target == attacker or not targetRoot or CombatService.WhyNotHittable(target) then
			return
		end
		local offset = targetRoot.Position - root.Position
		if offset.Magnitude > weapon.Range + CombatConfig.RangeSlack then
			return
		end
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if flat.Magnitude > 1 and facing.Magnitude > 0 then
			local angle = math.deg(math.acos(math.clamp(flat.Unit:Dot(facing.Unit), -1, 1)))
			if angle > CombatConfig.MeleeMaxAngle then
				return
			end
		end
		CombatService.ApplyHit(attacker, target, weapon, root.Position)
	elseif weapon.Kind == "Ranged" or weapon.Kind == "Freeze" then
		local direction = vector(p.Direction)
		if not direction or direction.Magnitude < 0.01 then
			return
		end
		local origin = root.Position + Vector3.new(0, 1.5, 0)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local exclude: { Instance } = { getFolder() }
		if attacker.Character then
			table.insert(exclude, attacker.Character)
		end
		params.FilterDescendantsInstances = exclude
		local hit = Workspace:Raycast(origin, direction.Unit * weapon.Range, params)
		local endPoint = if hit then hit.Position else origin + direction.Unit * weapon.Range
		local character = hit and hit.Instance:FindFirstAncestorWhichIsA("Model")
		local target = character and Players:GetPlayerFromCharacter(character)
		if target and target ~= attacker and not CombatService.WhyNotHittable(target) then
			CombatService.ApplyHit(attacker, target, weapon, origin)
		end
		RemoteEvents.HitFx:FireAllClients({
			Weapon = weapon.Id,
			Kind = if weapon.Kind == "Freeze" then "FreezeBeam" else "Beam",
			From = origin,
			To = endPoint,
		})
	elseif weapon.Kind == "Peel" then
		local at = vector(p.Origin)
		if not at or (at - root.Position).Magnitude > CombatConfig.Peel.PlaceReach + CombatConfig.RangeSlack then
			at = root.Position + root.CFrame.LookVector * 3
		end
		placePeel(attacker, weapon, at :: Vector3)
	end
end

--[[ Lifecycle --------------------------------------------------------------------------- ]]

local function onCharacterAdded(player: Player, character: Model)
	restoreJoints(player.UserId)
	player:SetAttribute("SpawnProtectUntil", serverNow() + CombatConfig.SpawnProtectSeconds)
	player:SetAttribute("RagdollUntil", nil)
	player:SetAttribute("FrozenUntil", nil)
	-- The Backpack is rebuilt on each spawn: give the tools once it's there.
	task.defer(function()
		if player.Character == character and PlayerDataService.IsDataLoaded(player) then
			giveTools(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	state.lastSwing[player.UserId] = nil
	state.joints[player.UserId] = nil
	local peels: { BasePart } = state.peels[player.UserId] or {}
	for _, peel in peels do
		peel:Destroy()
	end
	state.peels[player.UserId] = nil
end

function CombatService:Init()
	RemoteEvents.RequestHit.OnServerEvent:Connect(onRequestHit)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

function CombatService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	HeistService = require(script.Parent.HeistService)
	TycoonService = require(script.Parent.TycoonService)
	PlayerDataService.OnSync(grantByRebirths)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return CombatService
