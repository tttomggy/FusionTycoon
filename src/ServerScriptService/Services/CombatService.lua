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
	  * A hit: the client only sends RequestHit { Weapon, Origin?, Direction? }
	    (a melee swing sends the weapon id alone). Everything is decided here:
	    the weapon is owned AND equipped (the Tool is in the character), its
	    cooldown (per player and weapon), both sides' eligibility (Rebirth 1+,
	    not protected, not spawn-protected, not ragdolled / immune, the
	    attacker not carrying). Melee: MeleeHitDelay after the swing the
	    server boxes the weapon's MeleeBox in front of the attacker's root; a
	    player whose root was in the box at the swing REQUEST time (the
	    last HistorySeconds of every root are kept) counts too; the Bat hits
	    the nearest hittable player in it, the Glove all of them, and
	    every other player in the box gets the attacker-only shield pop with
	    its reason. Nobody beyond Range + RangeSlack is hit. One log line per swing in Studio ("box found [...] ->
	    HIT / MISS / <name> <reason>"). Ranged weapons: a server raycast with
	    line of sight. Numbers through RemoteGuard; rate-limited.
	  * Ragdoll: the server owns the until-times (Player attributes
	    RagdollUntil / ImmuneUntil / FrozenUntil / SpawnProtectUntil, server
	    time). It swaps the target's Motor6Ds for BallSocketConstraints
	    (replicated to everyone), launches the target with a server-made
	    LinearVelocity "KnockbackMover" on the root for LaunchSeconds (the
	    target's own client simulates it; no ownership change), fires
	    HitReceived { Impulse, Seconds } to the target (whose client goes
	    Physical) and restores the joints after RagdollSeconds. A client that
	    ignores it breaks nothing: the server's times still gate everything.
	  * Freeze Ray: no ragdoll; FrozenUntil, the target's client walks at
	    Freeze.SpeedMultiplier.
	  * Banana Peel: placed near you (one out, LifetimeSeconds), the first
	    eligible enemy to touch it is ragdolled.
	  * Hitting a carrying thief: HeistService.KnockCarrier (the orb goes
	    home, the owner sees SAVED). Analytics: Hit (weapon), ThiefKnocked,
	    GuardKnocked.
	  * HitFx { Weapon, Kind, From, To, Attacker?, Target? } to everyone: the
	    bonk / beam / freeze / slip effects, a Swing for every accepted melee
	    swing (a miss too, so others see it), a Throw when a peel lands
	    (CombatController). Attacker / Target are UserIds.
	  * The tools are WeaponKit.Build (models welded to a Handle); the placed
	    peel is WeaponKit.BuildPlaced.

	Follows the ServiceTemplate contract.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local WeaponKit = require(ReplicatedStorage.Shared.Modules.WeaponKit)
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

local MAX_COORDINATE = 1e5
local ROOT_JOINT_NAMES = { RootJoint = true, Root = true }
local FOLDER_NAME = "CombatObjects"
local DATA_POLL_SECONDS = 0.25 -- a spawn that beat the DataStore load re-checks this often
local DATA_WAIT_SECONDS = 30

type Joint = { Motor: Motor6D, Constraint: BallSocketConstraint, A0: Attachment, A1: Attachment }

-- What a melee swing found and did, for the Studio log and /selftest.
export type Verdict = { Seq: number, Weapon: string, Found: { string }, Hit: { string }, Line: string }

local state = {
	-- userId -> weapon id -> os.clock() of the last accepted swing
	lastSwing = {} :: { [number]: { [string]: number } },
	-- userId -> the joints swapped out for the current ragdoll
	joints = {} :: { [number]: { Joint } },
	-- userId -> the character launched by a hit (PlatformStand / movers to undo)
	launches = {} :: { [number]: Launch },
	logLaunch = false,
	-- userId -> the verdict of that player's last melee swing (/selftest reads it)
	verdicts = {} :: { [number]: Verdict },
	verdictSeq = 0,
	-- /combat box: draw each swing's hitbox (Studio only)
	drawBox = false,
	-- userId -> the last HistorySeconds of the character root: { T = os.clock(), Pos }
	history = {} :: { [number]: { { T: number, Pos: Vector3 } } },
	-- userId -> placed banana peels
	peels = {} :: { [number]: { Model } },
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

type Launch = { Character: Model, Humanoid: Humanoid?, Root: BasePart, Token: number }

local MOVER_NAME = "KnockbackMover"
local SPIN_MOVER_NAME = "KnockbackSpin"
local MOVER_ATTACHMENT_NAME = "KnockbackAttachment"
local LIMB_DRAG_CHECK_SECONDS = 0.1 -- when the root is checked for limb drag
local LIMB_DRAG_LOST_SHARE = 0.4 -- more than this share of the speed lost: add UpperTorso
local launchToken = 0

local function flatSpeed(velocity: Vector3): number
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

-- Destroys every knockback mover (and its attachment) left on `character`.
local function destroyMovers(character: Model?)
	if not character then
		return
	end
	for _, descendant in character:GetDescendants() do
		local name = descendant.Name
		if name == MOVER_NAME or name == SPIN_MOVER_NAME or name == MOVER_ATTACHMENT_NAME then
			descendant:Destroy()
		end
	end
end

-- Studio-only log of the target root's flat speed for 10 Heartbeats after a
-- launch (CombatService.SetLaunchLogging; /selftest turns it on). This is
-- what the SERVER sees: the truth is measured on the target's own client.
local function logLaunch(root: BasePart, label: string)
	task.spawn(function()
		local speeds: { string } = {}
		for _ = 1, 10 do
			RunService.Heartbeat:Wait()
			table.insert(speeds, ("%.1f"):format(flatSpeed(root.AssemblyLinearVelocity)))
		end
		print(("[CombatService] %s: target root flat speed over 10 Heartbeats (server view): %s"):format(label, table.concat(speeds, ", ")))
	end)
end

-- A LinearVelocity on `part` (its own Attachment at the part's centre), the
-- standard Roblox body mover. A constraint the server creates replicates to
-- every client, and whoever owns the assembly (the target's own client)
-- simulates it, so no ownership change is needed and it works whatever the
-- ownership.
local function addVelocityMover(part: BasePart, velocity: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Name = MOVER_ATTACHMENT_NAME
	attachment.Parent = part
	local mover = Instance.new("LinearVelocity")
	mover.Name = MOVER_NAME
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	mover.VectorVelocity = velocity
	mover.MaxForce = math.huge
	mover.Parent = part
end

-- The server-made launch. In order: any mover left from a earlier hit goes
-- (a new hit REPLACES the old mover, never stacks), PlatformStand on (the
-- ground controller is off, nothing brakes the flight), a LinearVelocity on
-- the root for LaunchSeconds, and for the Glove / peel an AngularVelocity
-- spin for the same time. If the limbs drag the root (more than 40% of the
-- speed lost by LIMB_DRAG_CHECK_SECONDS) the same mover goes on UpperTorso
-- too, not on every part.
local function launch(target: Player, impulse: Vector3, spin: boolean)
	local character = target.Character
	local root = getRoot(target)
	if not character or not root then
		return
	end
	destroyMovers(character)
	launchToken += 1
	local token = launchToken
	local humanoid = getHumanoid(target)
	if humanoid then
		humanoid.PlatformStand = true
	end
	state.launches[target.UserId] = { Character = character, Humanoid = humanoid, Root = root, Token = token }
	addVelocityMover(root, impulse)
	if spin then
		local attachment = Instance.new("Attachment")
		attachment.Name = MOVER_ATTACHMENT_NAME
		attachment.Parent = root
		local spinner = Instance.new("AngularVelocity")
		spinner.Name = SPIN_MOVER_NAME
		spinner.Attachment0 = attachment
		spinner.RelativeTo = Enum.ActuatorRelativeTo.World
		spinner.AngularVelocity = CombatConfig.SpinImpulse
		spinner.MaxTorque = math.huge
		spinner.Parent = root
	end
	if state.logLaunch then
		logLaunch(root, "launch")
	end
	local wanted = flatSpeed(impulse)
	task.delay(LIMB_DRAG_CHECK_SECONDS, function()
		local launched = state.launches[target.UserId]
		if not launched or launched.Token ~= token or not root.Parent then
			return
		end
		local torso = character:FindFirstChild("UpperTorso")
		if torso and torso:IsA("BasePart") and wanted > 0 and flatSpeed(root.AssemblyLinearVelocity) < wanted * (1 - LIMB_DRAG_LOST_SHARE) then
			addVelocityMover(torso, impulse)
		end
	end)
	task.delay(CombatConfig.LaunchSeconds, function()
		local launched = state.launches[target.UserId]
		if launched and launched.Token == token then
			destroyMovers(character)
		end
	end)
end

-- Gets the target standing again: movers gone, PlatformStand off, then
-- GettingUp. Safe to call twice, on respawn and on leaving mid-ragdoll
-- (nobody is left platform-standing).
local function endLaunch(userId: number, _player: Player?)
	local launched = state.launches[userId]
	state.launches[userId] = nil
	if not launched then
		return
	end
	destroyMovers(launched.Character)
	local humanoid = launched.Humanoid
	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

-- Ragdolls `target` for RagdollSeconds with `impulse` (studs/s).
local function ragdoll(target: Player, impulse: Vector3, spin: boolean)
	local seconds = CombatConfig.RagdollSeconds
	local now = serverNow()
	target:SetAttribute("RagdollUntil", now + seconds)
	target:SetAttribute("ImmuneUntil", now + seconds + CombatConfig.GetUpImmuneSeconds)
	swapJoints(target)
	launch(target, impulse, spin)
	RemoteEvents.HitReceived:FireClient(target, { Impulse = impulse, Seconds = seconds, Spin = spin })
	local character = target.Character
	local token = launchToken
	task.delay(seconds, function()
		if target.Character == character then
			restoreJoints(target.UserId)
		end
		-- A second hit in the meantime owns the launch now (and its own timer).
		local launched = state.launches[target.UserId]
		if launched and launched.Token == token then
			endLaunch(target.UserId, target)
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
		-- The "Knock 3 thieves" quest (QuestService) counts it.
		PlayerDataService.AddStat(attacker, "Knocks", 1)
	end
	if weapon.Kind == "Freeze" then
		freeze(target)
	else
		local away = targetRoot.Position - from
		local flat = Vector3.new(away.X, 0, away.Z)
		local direction = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)
		ragdoll(
			target,
			direction * weapon.Knockback + Vector3.new(0, CombatConfig.UpwardKick, 0),
			weapon.Kind == "Peel" or weapon.Id == "SlapGlove"
		)
	end
	RemoteEvents.HitFx:FireAllClients({
		Weapon = weapon.Id,
		Kind = if weapon.Kind == "Freeze" then "Freeze" elseif weapon.Kind == "Peel" then "Slip" else "Bonk",
		From = from,
		To = targetRoot.Position,
		Attacker = if attacker then attacker.UserId else nil,
		Target = target.UserId,
	})
	if attacker then
		AnalyticsKit.Custom(attacker, "Hit", nil, weapon.Id)
	end
end

--[[ Tools ---------------------------------------------------------------------------- ]]

--[[ Holding it ------------------------------------------------------------------------
	Humanoid:EquipTool welds the Handle to the right hand (a "RightGrip" weld
	in the hand). It is the engine's job, so this only checks it landed:
	the weld exists and the Handle is within GRIP_REACH studs of the hand.
	A tool that is not in a hand (or an avatar whose weld never formed) is
	repaired with the same weld the engine builds, so a weapon can never sit
	in front of the chest.
]]
local GRIP_REACH = 1.5

local function getHand(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
end

-- Why `tool` (equipped on `character`) is not held (nil = it is).
function CombatService.GetGripProblem(character: Model, tool: Tool): string?
	local hand = getHand(character)
	local handle = tool:FindFirstChild("Handle")
	if not hand or not handle or not handle:IsA("BasePart") then
		return "no RightHand or no Handle"
	end
	local grip = hand:FindFirstChild("RightGrip")
	if not grip or not grip:IsA("JointInstance") and not grip:IsA("WeldConstraint") then
		return "no RightGrip weld in the hand"
	end
	local distance = (handle.Position - hand.Position).Magnitude
	if distance > GRIP_REACH then
		return ("the Handle is %.1f studs from the hand"):format(distance)
	end
	return nil
end

-- Rebuilds the RightGrip the way the engine does (attachment frame, the
-- tool's Grip).
local function repairGrip(character: Model, tool: Tool)
	local hand = getHand(character)
	local handle = tool:FindFirstChild("Handle")
	if not hand or not handle or not handle:IsA("BasePart") then
		return
	end
	local old = hand:FindFirstChild("RightGrip")
	if old then
		old:Destroy()
	end
	local attachment = hand:FindFirstChild("RightGripAttachment")
	local weld = Instance.new("Weld")
	weld.Name = "RightGrip"
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = if attachment and attachment:IsA("Attachment") then attachment.CFrame else CFrame.new()
	weld.C1 = tool.Grip
	weld.Parent = hand
end

local function watchGrip(tool: Tool)
	tool.Equipped:Connect(function()
		task.wait(0.15) -- the engine's weld, then a physics step
		local character = tool.Parent
		if tool.Parent ~= character or not character or not character:IsA("Model") then
			return
		end
		local problem = CombatService.GetGripProblem(character, tool)
		if problem then
			warn(("CombatService: %s is not held (%s); rebuilding RightGrip"):format(tool.Name, problem))
			repairGrip(character, tool)
		end
	end)
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
			local tool = WeaponKit.Build(weapon.Id)
			watchGrip(tool)
			tool.Parent = backpack
		end
	end
end

-- True when an owned weapon is in neither the Backpack nor the character.
local function missingTools(player: Player): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false
	end
	local character = player.Character
	for id in PlayerDataService.GetWeapons(player) do
		if not backpack:FindFirstChild(id) and not (character and character:FindFirstChild(id)) then
			return true
		end
	end
	return false
end

-- The sync hook: rebirth milestones grant their weapons, and a Backpack
-- that lost (or never got) an owned weapon is refilled.
local function grantByRebirths(player: Player)
	local granted = false
	for _, id in CombatConfig.GetUnlockedByRebirths(PlayerDataService.GetRebirths(player)) do
		if PlayerDataService.GrantWeapon(player, id) then
			granted = true
			RemoteEvents.WeaponUnlocked:FireClient(player, { Weapon = id })
		end
	end
	if granted or (player.Character ~= nil and missingTools(player)) then
		giveTools(player)
	end
end

-- A quest reward (QuestService): grants the weapon, the unlock card and
-- the Tool. Returns whether it was new.
function CombatService.GrantWeapon(player: Player, id: string): boolean
	if not PlayerDataService.GrantWeapon(player, id) then
		return false
	end
	RemoteEvents.WeaponUnlocked:FireClient(player, { Weapon = id })
	giveTools(player)
	return true
end

-- /selftest: tools match what the player owns again (after the test took a
-- weapon back).
function CombatService.RefreshTools(player: Player)
	giveTools(player)
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
	local peel = WeaponKit.BuildPlaced()
	peel:PivotTo(CFrame.new(ground.Position) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	peel:SetAttribute("OwnerUserId", owner.UserId)
	peel.Parent = getFolder()
	local hitbox = peel:FindFirstChild("Hitbox") :: BasePart
	table.insert(peels, peel)
	-- Everyone sees the throw arc (the client hides the peel until it lands).
	local ownerRoot = getRoot(owner)
	RemoteEvents.HitFx:FireAllClients({
		Weapon = weapon.Id,
		Kind = "Throw",
		From = if ownerRoot then ownerRoot.Position + Vector3.new(0, 1, 0) else ground.Position + Vector3.new(0, 3, 0),
		To = ground.Position,
		Attacker = owner.UserId,
	})
	hitbox.Touched:Connect(function(hit: BasePart)
		if not peel.Parent then
			return
		end
		local character = hit:FindFirstAncestorWhichIsA("Model")
		local victim = character and Players:GetPlayerFromCharacter(character)
		if not victim or victim == owner or CombatService.WhyNotHittable(victim) then
			return
		end
		local position = hitbox.Position
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

-- A swing or shot that landed on a target who can't be hit (a new lab under
-- Rebirth 1, spawn-protected, or immune after a get-up) is shown to the
-- ATTACKER only, with the reason, so a hit that does nothing never looks
-- like a bug.
local function notifyIgnored(attacker: Player, targetRoot: BasePart, why: string)
	if why == "Immune" or why == "SpawnProtected" or why == "NeedsRebirth" then
		RemoteEvents.HitFx:FireClient(attacker, { Kind = "Immune", To = targetRoot.Position, Attacker = attacker.UserId, Reason = why })
	end
end

-- The player whose character `part` belongs to (an accessory or tool part
-- counts), or nil.
local function playerOfPart(part: Instance): Player?
	local current: Instance? = part
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local owner = Players:GetPlayerFromCharacter(current)
			if owner then
				return owner
			end
		end
		current = current.Parent
	end
	return nil
end

-- The box in front of `root`: flat facing (no tilt), its centre the
-- weapon's MeleeBoxForward studs forward.
local function meleeBoxCFrame(root: BasePart, weapon: CombatConfig.Weapon): CFrame
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local _, forwardStuds = CombatConfig.GetMeleeBox(weapon)
	return CFrame.lookAt(root.Position, root.Position + forward) * CFrame.new(0, 0, -forwardStuds)
end

-- Where `player`'s root was at os.clock() time `at` (the nearest kept
-- sample), or nil when nothing that recent is kept.
local function positionAt(player: Player, at: number): Vector3?
	local samples = state.history[player.UserId]
	if not samples then
		return nil
	end
	local best: Vector3? = nil
	local bestGap = math.huge
	for _, sample in samples do
		local gap = math.abs(sample.T - at)
		if gap < bestGap then
			bestGap = gap
			best = sample.Pos
		end
	end
	return best
end

-- One Heartbeat sample of every root; samples older than HistorySeconds
-- (plus a frame of slack) go.
local function recordHistory()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local root = getRoot(player)
		if root then
			local samples = state.history[player.UserId]
			if not samples then
				samples = {}
				state.history[player.UserId] = samples
			end
			table.insert(samples, { T = now, Pos = root.Position })
			while #samples > 1 and now - samples[1].T > CombatConfig.HistorySeconds + 0.1 do
				table.remove(samples, 1)
			end
		end
	end
end

-- /combat box: a red transparent part where the box was, for 0.2 s.
local function drawMeleeBox(cframe: CFrame, size: Vector3)
	local part = Instance.new("Part")
	part.Name = "MeleeBoxDebug"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.new(1, 0.1, 0.1)
	part.Transparency = 0.6
	part.Size = size
	part.CFrame = cframe
	part.Parent = getFolder()
	task.delay(0.2, function()
		part:Destroy()
	end)
end

local function recordVerdict(attacker: Player, weapon: CombatConfig.Weapon, found: { string }, hit: { string }, line: string)
	state.verdictSeq += 1
	state.verdicts[attacker.UserId] = { Seq = state.verdictSeq, Weapon = weapon.Id, Found = found, Hit = hit, Line = line }
	if RunService:IsStudio() then
		print(line)
	end
end

-- MeleeHitDelay after an accepted swing: the box, the verdict, the hits.
-- (Everything is read now, from the attacker's root as it is now.)
local function resolveMelee(attacker: Player, weapon: CombatConfig.Weapon, requestAt: number, requestBox: CFrame)
	local root = getRoot(attacker)
	local humanoid = getHumanoid(attacker)
	local prefix = ("[Combat] %s %s:"):format(attacker.Name, weapon.Id)
	if not attacker.Parent or not root or not humanoid or humanoid.Health <= 0 then
		recordVerdict(attacker, weapon, {}, {}, prefix .. " box found [] -> MISS (attacker gone)")
		return
	end
	-- Knocked down during the wind-up: the swing does nothing.
	if untilActive(attacker, "RagdollUntil") then
		recordVerdict(attacker, weapon, {}, {}, prefix .. " box found [] -> MISS (attacker ragdolled)")
		return
	end
	local boxSize = CombatConfig.GetMeleeBox(weapon)
	local cframe = meleeBoxCFrame(root, weapon)
	if state.drawBox then
		drawMeleeBox(cframe, boxSize)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if attacker.Character then { attacker.Character } else {}
	local parts = Workspace:GetPartBoundsInBox(cframe, boxSize, params)
	-- The distinct players in the box, nearest first. `seen` is their root
	-- distance from the attacker; one past Range + RangeSlack never counts.
	local maxReach = weapon.Range + CombatConfig.RangeSlack
	local seen: { [Player]: number } = {}
	local candidates: { Player } = {}
	local function consider(owner: Player, distance: number)
		if distance > maxReach then
			return
		end
		if seen[owner] == nil then
			table.insert(candidates, owner)
		end
		seen[owner] = math.min(seen[owner] or math.huge, distance)
	end
	for _, part in parts do
		local owner = playerOfPart(part)
		if owner and owner ~= attacker then
			local ownerRoot = getRoot(owner)
			consider(owner, if ownerRoot then (ownerRoot.Position - root.Position).Magnitude else math.huge)
		end
	end
	-- Lag tolerance: whoever's root was in the box when the swing was
	-- requested (the box and the roots as they were THEN) counts as well.
	local attackerThen = positionAt(attacker, requestAt) or root.Position
	local half = boxSize / 2
	for _, other in Players:GetPlayers() do
		if other ~= attacker and seen[other] == nil then
			local was = positionAt(other, requestAt)
			if was then
				local offset = requestBox:PointToObjectSpace(was)
				if math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z then
					consider(other, (was - attackerThen).Magnitude)
				end
			end
		end
	end
	table.sort(candidates, function(a: Player, b: Player)
		return (seen[a] :: number) < (seen[b] :: number)
	end)
	local found: { string } = {}
	for _, candidate in candidates do
		table.insert(found, ("%s %.1f studs"):format(candidate.Name, seen[candidate] :: number))
	end

	local hits: { Player } = {}
	local refusals: { string } = {}
	for _, candidate in candidates do
		local why = CombatService.WhyNotHittable(candidate)
		if why then
			table.insert(refusals, ("%s %s"):format(candidate.Name, why))
			local candidateRoot = getRoot(candidate)
			if candidateRoot then
				notifyIgnored(attacker, candidateRoot, why)
			end
		elseif weapon.Id == "SlapGlove" or #hits == 0 then
			table.insert(hits, candidate)
		end
	end

	local hitNames: { string } = {}
	for _, target in hits do
		table.insert(hitNames, target.Name)
	end
	local verdict: string
	if #hits > 0 then
		verdict = "HIT " .. table.concat(hitNames, ", ")
		if #refusals > 0 then
			verdict ..= "; " .. table.concat(refusals, ", ")
		end
	elseif #refusals > 0 then
		verdict = table.concat(refusals, ", ")
	else
		verdict = "MISS"
	end
	recordVerdict(attacker, weapon, found, hitNames, ("%s box found [%s] -> %s"):format(prefix, table.concat(found, ", "), verdict))
	for _, target in hits do
		CombatService.ApplyHit(attacker, target, weapon, root.Position)
	end
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
	if not weapon then
		return
	end
	-- A refused swing says why (to the attacker): no silent refusals.
	local refused = whyCantSwing(attacker, weapon)
	if refused then
		RemoteEvents.HitFx:FireClient(attacker, { Kind = "Refused", Reason = refused, Weapon = weapon.Id, Attacker = attacker.UserId })
		return
	end
	local root = getRoot(attacker) :: BasePart
	if not CombatService.TakeCooldown(attacker, weapon) then
		return
	end

	if weapon.Kind == "Melee" then
		-- Every accepted swing is seen by everyone, hit or miss (the cooldown
		-- above rate-limits it).
		RemoteEvents.HitFx:FireAllClients({
			Weapon = weapon.Id,
			Kind = "Swing",
			From = root.Position,
			To = root.Position + root.CFrame.LookVector * weapon.Range,
			Attacker = attacker.UserId,
		})
		-- The hit lands where the clip's Hit marker is, not at the click.
		local requestAt, requestBox = os.clock(), meleeBoxCFrame(root, weapon)
		task.delay(CombatConfig.MeleeHitDelay, function()
			resolveMelee(attacker, weapon, requestAt, requestBox)
		end)
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
		if target and target ~= attacker then
			local why = CombatService.WhyNotHittable(target)
			local targetRoot = getRoot(target)
			if not why then
				CombatService.ApplyHit(attacker, target, weapon, origin)
			elseif targetRoot then
				notifyIgnored(attacker, targetRoot, why)
			end
		end
		RemoteEvents.HitFx:FireAllClients({
			Weapon = weapon.Id,
			Kind = if weapon.Kind == "Freeze" then "FreezeBeam" else "Beam",
			From = origin,
			To = endPoint,
			Attacker = attacker.UserId,
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
	endLaunch(player.UserId, nil)
	player:SetAttribute("SpawnProtectUntil", serverNow() + CombatConfig.SpawnProtectSeconds)
	player:SetAttribute("RagdollUntil", nil)
	player:SetAttribute("FrozenUntil", nil)
	-- The Backpack is rebuilt on each spawn: give the tools once it's there.
	-- On a live server the character spawns before the DataStore load ends:
	-- wait for the data (up to DATA_WAIT_SECONDS), then give them.
	task.defer(function()
		local waited = 0
		while player.Parent == Players and player.Character == character and not PlayerDataService.IsDataLoaded(player) do
			if waited >= DATA_WAIT_SECONDS then
				return
			end
			task.wait(DATA_POLL_SECONDS)
			waited += DATA_POLL_SECONDS
		end
		if player.Parent == Players and player.Character == character and PlayerDataService.IsDataLoaded(player) then
			giveTools(player)
		end
	end)
end

-- Client fallback (CombatController.toggleEquip found no Tool for an owned weapon).
local function onRequestWeaponTools(player: Player)
	if not RemoteGuard.Allow(player, "RequestWeaponTools", 1, 2) then
		return
	end
	if PlayerDataService.IsDataLoaded(player) then
		giveTools(player)
	end
end

-- /selftest: the RequestWeaponTools handler, called directly. (Below the
-- handler: a local function is nil to code declared above it.)
function CombatService.SelfTestRequestWeaponTools(player: Player)
	onRequestWeaponTools(player)
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
	state.verdicts[player.UserId] = nil
	state.history[player.UserId] = nil
	state.joints[player.UserId] = nil
	endLaunch(player.UserId, nil)
	local peels: { Model } = state.peels[player.UserId] or {}
	for _, peel in peels do
		peel:Destroy()
	end
	state.peels[player.UserId] = nil
end

-- The verdict of `player`'s last melee swing (nil before the first). /selftest
-- compares Seq before and after a real swing.
function CombatService.GetLastVerdict(player: Player): Verdict?
	return state.verdicts[player.UserId]
end

-- /combat box (Studio): draw each swing's hitbox for 0.2 s. Returns the new state.
function CombatService.ToggleBoxDrawing(): boolean
	state.drawBox = RunService:IsStudio() and not state.drawBox
	return state.drawBox
end

-- /selftest: print the target root's flat speed for 10 Heartbeats per launch.
function CombatService.SetLaunchLogging(on: boolean)
	state.logLaunch = on
end

function CombatService:Init()
	RemoteEvents.RequestHit.OnServerEvent:Connect(onRequestHit)
	RemoteEvents.RequestWeaponTools.OnServerEvent:Connect(onRequestWeaponTools)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	RunService.Heartbeat:Connect(recordHistory)
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
