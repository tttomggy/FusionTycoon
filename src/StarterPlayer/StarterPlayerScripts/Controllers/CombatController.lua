--!strict
--[[
	CombatController
	----------------
	The client half of weapons and ragdoll (CombatConfig; CombatService
	decides every hit).

	  * Weapon bar: the default Backpack bar is replaced by rounded-square
	    slots (64 px, 52 on a phone) above the bottom buttons, each a
	    ViewportFrame with the real WeaponKit model slowly turning, the key
	    number top-left and the name under it. Keys 1-5 or a tap equip /
	    unequip. Equipped = a lime ring + a 4 px lift; cooldown = a dark
	    radial sweep + the seconds left; not yet earned = a dim model with a
	    lock and "R2" / "R3" / "Quest" (a tap says how); the whole bar dims
	    while you carry a stolen orb (hands full), and it is off at Rebirth 0
	    and while the tutorial runs.
	  * Using one (Tool.Activated): melee sends only the weapon id (the SERVER
	    boxes the space in front of you and picks who it hits); ranged and
	    the Freeze Ray send where you aim (the
	    mouse on a computer, the camera's centre on a touch screen); the
	    Banana Peel goes on the ground in front of you. RequestHit only; the
	    server re-checks everything.
	  * Feel (all local, WeaponPose / WeaponFx): an equip raise, the Bat and
	    Glove swing with a trail, guns hold an aim pose pitched at your aim,
	    recoil + a muzzle flash on a shot, a throw for the peel. Everyone
	    sees yours through HitFx (Swing / Beam / FreezeBeam / Throw carry the
	    Attacker), the same code runs for theirs.
	  * HitReceived: you ragdoll (Humanoid Physics state; the launch is the server's KnockbackMover; the
	    server swaps your joints and restores them; a peel adds a spin) and
	    prompts switch off until you're up; or you freeze (40% speed). The
	    server's times rule.
	  * Every client: HitFx effects (BONK! pop with stars + a white ring, a
	    thin Neon beam seen from the side, an icy cone, SLIP!), the icy tint
	    and frost on frozen players, a faint shimmer on immune ones, and the
	    sound slots.
	  * WeaponUnlocked: the tutorial-style card "You got a Bat!" with the
	    big turning model (after the tutorial, if it's still running).
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatConfig = require(ReplicatedStorage.Shared.Config.CombatConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local WeaponKit = require(ReplicatedStorage.Shared.Modules.WeaponKit)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local TutorialCards = require(UI.TutorialCards)
local WeaponViewport = require(UI.WeaponViewport)
local Effects = script.Parent.Parent.Effects
local WeaponPose = require(Effects.WeaponPose)
local WeaponAnimator = require(Effects.WeaponAnimator)
local WeaponFx = require(Effects.WeaponFx)
local TycoonController = require(script.Parent.TycoonController)
local ToastController = require(script.Parent.ToastController)

local CombatController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts
local World = UITheme.World

local SLOT_SIZE = { Desktop = 64, Phone = 52 }
local SLOT_GAP = 10
local SLOT_RADIUS = 12
local LIFT = 4 -- the equipped slot rises this far
local NAME_HEIGHT = 14
local NAME_GAP = 2
local LIFT_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SWEEP_DARK = 0.35 -- the cooldown wipe's transparency
local LOCKED_DIM = 0.75
local CARRYING_DIM = 0.55
-- Above the HUD's bottom row (22 margin + 64 / 60 button + 5 shadow) + a gap.
local BAR_BOTTOM = { Desktop = 22 + 64 + 5 + 12, Phone = 22 + 60 + 5 + 12 }
local LASER_BEAM_SECONDS = 0.12
local FREEZE_BEAM_SECONDS = 0.18
local FREEZE_CONE_STUDS = 24
local POP_SECONDS = 0.9
local TRAIL_SECONDS = 0.3 -- the swing trail, from the clip's Hit marker
local HIT_STOP_SECONDS = 0.06
local LOCKED_TOAST_SECONDS = 3 -- "Fighting unlocks at Rebirth 1" at most this often
local SHAKE_ATTACKER_SECONDS = 0.15
local SHAKE_TARGET_SECONDS = 0.3
local FLASH_SECONDS = 0.1
local SHIMMER_SPEED = 10
local SHIMMER_MAX = 0.45
local KEY_CODES = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }

local localPlayer = Players.LocalPlayer

type Slot = {
	Weapon: CombatConfig.Weapon,
	Owned: boolean,
	Holder: Frame, -- the lifting panel holder
	Body: Frame,
	Stroke: UIStroke,
	Viewport: ViewportFrame,
	Name: TextLabel,
	Seconds: TextLabel,
	Sweep: Frame,
	SweepRight: UIGradient,
	SweepLeft: UIGradient,
	Lifted: boolean,
	Dim: number,
}

local screenGui: ScreenGui
local bar: Frame
local slots: { Slot } = {}
local lastLocalSwing: { [string]: number } = {}
local ragdolledUntil = 0
local frozenUntil = 0
local tinted: { [Model]: { [BasePart]: Color3 } } = {}
local shimmering: { [Model]: boolean } = {}
local pendingUnlocks: { string } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getHumanoid(): Humanoid?
	local character = localPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function isCarrying(): boolean
	return localPlayer:GetAttribute("HeistTier") ~= nil
end

local function untilActive(player: Player, attribute: string): boolean
	local value = player:GetAttribute(attribute)
	return typeof(value) == "number" and value > serverNow()
end

--[[ Weapon bar ------------------------------------------------------------------------ ]]

local function ownedWeapons(): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	for _, id in TycoonController.GetWeapons() do
		owned[id] = true
	end
	return owned
end

local function findTool(id: string): Tool?
	local character = localPlayer.Character
	local inHand = character and character:FindFirstChild(id)
	if inHand and inHand:IsA("Tool") then
		return inHand
	end
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	local stored = backpack and backpack:FindFirstChild(id)
	return if stored and stored:IsA("Tool") then stored else nil
end

local function toggleEquip(weapon: CombatConfig.Weapon)
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end
	if not ownedWeapons()[weapon.Id] then
		ToastController.Show(if weapon.UnlockRebirth then ("Unlocks at Rebirth %d"):format(weapon.UnlockRebirth) else "Earned from a quest", "Neutral")
		return
	end
	if isCarrying() then
		ToastController.Show("Hands full: run it home!", "Neutral")
		return
	end
	local tool = findTool(weapon.Id)
	if not tool then
		return
	end
	if tool.Parent == localPlayer.Character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
end

-- One half of the clock-wipe: a clipped half of the slot holding a full-size
-- dark frame whose gradient has a hard edge through the slot's centre.
-- Rotating the gradient to the angle sweeps the edge round like a clock hand
-- (UIGradient rotation is clockwise, 0 = left -> right); the dark side is
-- the half the gradient runs TOWARD. With the right half at min(angle, 180)
-- and the left at max(angle, 180) the lit part is a pie from 12 o'clock
-- clockwise, growing as the cooldown runs out.
local function sweepHalf(parent: Frame, right: boolean, zIndex: number): UIGradient
	local clip = Instance.new("Frame")
	clip.Name = if right then "RightHalf" else "LeftHalf"
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Position = UDim2.fromScale(if right then 0.5 else 0, 0)
	clip.Size = UDim2.fromScale(0.5, 1)
	clip.ZIndex = zIndex
	clip.Parent = parent
	local dark = Instance.new("Frame")
	dark.Name = "Dark"
	dark.BackgroundColor3 = Colors.Ink
	dark.BorderSizePixel = 0
	dark.Position = UDim2.fromScale(if right then -1 else 0, 0)
	dark.Size = UDim2.fromScale(2, 1)
	dark.ZIndex = zIndex
	dark.Parent = clip
	local gradient = Instance.new("UIGradient")
	-- Clear on the gradient's near side, dark where it runs toward.
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.499, 1),
		NumberSequenceKeypoint.new(0.501, SWEEP_DARK),
		NumberSequenceKeypoint.new(1, SWEEP_DARK),
	})
	gradient.Parent = dark
	return gradient
end

local function slotLabel(text: string, size: number, color: Color3, props: { [string]: any }): TextLabel
	local label = UIKit.Label({
		Text = text,
		Font = Fonts.Display,
		TextSize = size,
		TextColor3 = color,
		Stroke = UITheme.Stroke.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	for key, value in props do
		(label :: any)[key] = value
	end
	return label
end

local function lockedText(weapon: CombatConfig.Weapon): string
	return if weapon.UnlockRebirth then ("R%d"):format(weapon.UnlockRebirth) else "Quest"
end

local function rebuildBar()
	for _, child in bar:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	slots = {}
	local owned = ownedWeapons()
	local phone = UIKit.IsPhone()
	local size = if phone then SLOT_SIZE.Phone else SLOT_SIZE.Desktop
	local key = 0
	for order, weapon in CombatConfig.Weapons do
		local has = owned[weapon.Id] == true
		local cell = Instance.new("Frame")
		cell.Name = weapon.Id
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = order
		cell.Size = UDim2.fromOffset(size, LIFT + size + NAME_GAP + NAME_HEIGHT)
		cell.Parent = bar

		local body, holder = UIKit.Panel({
			Name = "Slot",
			Parent = cell,
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(0, LIFT),
			Color = Colors.Panel,
			Radius = SLOT_RADIUS,
			StrokeThickness = 2,
			ShadowOffset = UITheme.SmallShadowOffset,
		})
		body.ClipsDescendants = true
		local z = body.ZIndex

		local viewport = WeaponViewport.Create(weapon.Id, body, { Phase = order, ZIndex = z + 1 })
		viewport.AnchorPoint = Vector2.new(0.5, 0.5)
		viewport.Position = UDim2.fromScale(0.5, 0.5)
		viewport.Size = UDim2.new(1, -8, 1, -8)

		local sweep = Instance.new("Frame")
		sweep.Name = "Cooldown"
		sweep.BackgroundTransparency = 1
		sweep.Size = UDim2.fromScale(1, 1)
		sweep.ZIndex = z + 3
		sweep.Visible = false
		sweep.Parent = body
		local sweepRight = sweepHalf(sweep, true, z + 3)
		local sweepLeft = sweepHalf(sweep, false, z + 3)

		local seconds = slotLabel("", math.floor(size * 0.36), Colors.Text, {
			Name = "Seconds",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 0.5),
			ZIndex = z + 4,
			Visible = false,
			Parent = body,
		})

		if has then
			key += 1
			local badge = Instance.new("Frame")
			badge.Name = "Key"
			badge.BackgroundColor3 = Colors.PanelTop
			badge.BorderSizePixel = 0
			badge.Position = UDim2.fromOffset(3, 3)
			badge.Size = UDim2.fromOffset(18, 18)
			badge.ZIndex = z + 5
			badge.Parent = body
			UIKit.Corner(badge, 6)
			slotLabel(tostring(key), 13, Colors.Text, {
				Size = UDim2.fromScale(1, 1),
				ZIndex = z + 6,
				Parent = badge,
			})
		else
			slotLabel("🔒", math.floor(size * 0.34), Colors.Text, {
				Name = "Lock",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.34),
				Size = UDim2.fromScale(1, 0.4),
				ZIndex = z + 5,
				Parent = body,
			})
			slotLabel(lockedText(weapon), 14, Colors.Text, {
				Name = "LockText",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -4),
				Size = UDim2.new(1, 0, 0, 16),
				ZIndex = z + 5,
				Parent = body,
			})
		end

		local nameLabel = UIKit.Label({
			Name = "WeaponName",
			Text = weapon.Name,
			Font = Fonts.BodyHeavy,
			TextSize = 12,
			TextColor3 = if has then Colors.Muted else Colors.Faint,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, LIFT + size + NAME_GAP),
			Size = UDim2.fromOffset(size + SLOT_GAP, NAME_HEIGHT),
			Parent = cell,
		})
		UIKit.FitText(nameLabel, 12, 9)

		local tap = Instance.new("TextButton")
		tap.Name = "Tap"
		tap.Text = ""
		tap.AutoButtonColor = false
		tap.BackgroundTransparency = 1
		tap.Size = UDim2.fromScale(1, 1)
		tap.ZIndex = z + 8
		tap.Parent = body
		tap.Activated:Connect(function()
			toggleEquip(weapon)
		end)

		local stroke = body:FindFirstChildOfClass("UIStroke") :: UIStroke
		table.insert(slots, {
			Weapon = weapon,
			Owned = has,
			Holder = holder,
			Body = body,
			Stroke = stroke,
			Viewport = viewport,
			Name = nameLabel,
			Seconds = seconds,
			Sweep = sweep,
			SweepRight = sweepRight,
			SweepLeft = sweepLeft,
			Lifted = false,
			Dim = -1,
		})
	end
	bar.Position = UDim2.new(0.5, 0, 1, -(if phone then BAR_BOTTOM.Phone else BAR_BOTTOM.Desktop))
end

local function setSlotDim(slot: Slot, dim: number)
	if slot.Dim == dim then
		return
	end
	slot.Dim = dim
	WeaponViewport.SetDim(slot.Viewport, dim)
	slot.Body.BackgroundTransparency = dim * 0.5
	slot.Name.TextTransparency = dim * 0.6
end

local function refreshBar()
	-- No bar before Rebirth 1 (nobody can hit you, you can't hit anyone) and
	-- none while the tutorial runs: its action button owns that space.
	screenGui.Enabled = TycoonController.GetRebirths() >= 1 and not TycoonController.IsTutorialActive()
	if not screenGui.Enabled then
		return
	end
	local carrying = isCarrying()
	local character = localPlayer.Character
	local now = os.clock()
	for _, slot in slots do
		local weapon = slot.Weapon
		local last = lastLocalSwing[weapon.Id]
		local left = if last then math.max(0, weapon.Cooldown - (now - last)) else 0
		if left > 0 and slot.Owned then
			local angle = 360 * (1 - left / weapon.Cooldown) -- 0 = just used: all dark
			slot.SweepRight.Rotation = math.min(angle, 180)
			slot.SweepLeft.Rotation = math.max(angle, 180)
			slot.Seconds.Text = if left >= 10 then ("%d"):format(math.ceil(left)) else ("%.1f"):format(left)
			slot.Sweep.Visible = true
			slot.Seconds.Visible = true
		elseif slot.Sweep.Visible then
			slot.Sweep.Visible = false
			slot.Seconds.Visible = false
		end
		local equipped = slot.Owned and character ~= nil and character:FindFirstChild(weapon.Id) ~= nil
		if equipped ~= slot.Lifted then
			slot.Lifted = equipped
			TweenService:Create(slot.Holder, LIFT_TWEEN, { Position = UDim2.fromOffset(0, if equipped then 0 else LIFT) }):Play()
			slot.Stroke.Color = if equipped then World.WeaponLime else Colors.Ink
			slot.Stroke.Thickness = if equipped then 3 else 2
		end
		setSlotDim(slot, if not slot.Owned then LOCKED_DIM elseif carrying then CARRYING_DIM else 0)
	end
end

--[[ Using a weapon --------------------------------------------------------------------- ]]

local function aimDirection(): Vector3?
	local root = getRoot(localPlayer)
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return nil
	end
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local target: Vector3
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
		target = ray.Origin + ray.Direction * 200
	else
		local mouse = localPlayer:GetMouse()
		target = mouse.Hit.Position
	end
	local direction = target - origin
	return if direction.Magnitude > 0.01 then direction.Unit else nil
end

--[[ Feel: the pose + effects of anyone's swing, kick or toss ------------------------- ]]

local function findHeldTool(player: Player, weaponId: string): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChild(weaponId)
	return if tool and tool:IsA("Tool") then tool else nil
end

-- `player` uses `weapon`: their arm swings / kicks / tosses, with the trail
-- or muzzle flash and the sound. Yours runs the moment you click; everyone
-- else's runs from the HitFx you cause.
local function performFor(player: Player, weapon: CombatConfig.Weapon)
	local character = player.Character
	local root = getRoot(player)
	if not character or not root then
		return
	end
	local tool = findHeldTool(player, weapon.Id)
	if weapon.Kind == "Melee" then
		local color = if weapon.Id == "SlapGlove" then World.GloveRed else Colors.White
		-- The animation track first: the trail starts at its "Hit" marker (the
		-- whip / slap keyframe), not at a fixed time. Without a track the C0
		-- pose runs and the trail starts at once.
		local seconds = WeaponAnimator.Swing(character, weapon.Id, function()
			if tool and tool.Parent then
				WeaponFx.Trail(tool, color, TRAIL_SECONDS)
			end
		end)
		if seconds == 0 then
			seconds = WeaponPose.Swing(character, weapon.Id)
			if tool and seconds > 0 then
				WeaponFx.Trail(tool, color, seconds)
			end
		end
		SoundKit.PlayAt("Swing", root.Position)
	elseif weapon.Kind == "Ranged" or weapon.Kind == "Freeze" then
		local freezing = weapon.Kind == "Freeze"
		WeaponAnimator.Recoil(character)
		WeaponPose.Recoil(character)
		if tool then
			WeaponFx.MuzzleFlash(tool, if freezing then World.Ice else World.WeaponLaser)
		end
		SoundKit.PlayAt("Shoot", root.Position, if freezing then { PlaybackSpeed = 0.8 } else nil)
	elseif weapon.Kind == "Peel" then
		WeaponAnimator.Throw(character)
		WeaponPose.Throw(character)
	end
end

local lastLockedToast = 0
local REFUSED_TEXT: { [string]: string } = {
	NeedsRebirth = "Fighting unlocks at Rebirth 1",
	NotOwned = "You don't have that weapon yet",
	NotEquipped = "Equip it first",
	Carrying = "Hands full: run it home!",
	Ragdolled = "Get up first",
}

-- What a click on the weapon does. Returns whether it swung (and sent
-- RequestHit), else why not. /selftest calls it through CombatController.Use,
-- the same function Tool.Activated calls.
local function use(weapon: CombatConfig.Weapon): (boolean, string?)
	-- Under Rebirth 1 nobody can hit you and you can't hit anyone: say so
	-- (at most every 3 s) and send nothing.
	if TycoonController.GetRebirths() < CombatConfig.MinRebirths then
		if os.clock() - lastLockedToast >= LOCKED_TOAST_SECONDS then
			lastLockedToast = os.clock()
			ToastController.Show(REFUSED_TEXT.NeedsRebirth, "Neutral")
		end
		return false, "NeedsRebirth"
	end
	if isCarrying() then
		ToastController.Show("Hands full: run it home!", "Neutral")
		return false, "Carrying"
	end
	if ragdolledUntil > serverNow() then
		return false, "Ragdolled"
	end
	local last = lastLocalSwing[weapon.Id]
	if last and os.clock() - last < weapon.Cooldown then
		return false, "Cooldown"
	end
	lastLocalSwing[weapon.Id] = os.clock()
	performFor(localPlayer, weapon)
	if weapon.Kind == "Melee" then
		-- No target: the server's box decides who is hit.
		RemoteEvents.RequestHit:FireServer({ Weapon = weapon.Id })
	elseif weapon.Kind == "Ranged" or weapon.Kind == "Freeze" then
		local direction = aimDirection()
		if direction then
			RemoteEvents.RequestHit:FireServer({ Weapon = weapon.Id, Direction = direction })
		end
	elseif weapon.Kind == "Peel" then
		local root = getRoot(localPlayer)
		if root then
			RemoteEvents.RequestHit:FireServer({ Weapon = weapon.Id, Origin = root.Position + root.CFrame.LookVector * 3 })
		end
	end
	return true, nil
end

-- /selftest: click the weapon the way a player does (the function a tool's
-- Activated runs). Returns (swung, why not).
function CombatController.Use(weaponId: string): (boolean, string?)
	local weapon = CombatConfig.GetWeapon(weaponId)
	if not weapon then
		return false, "UnknownWeapon"
	end
	return use(weapon)
end

-- /selftest: forget the local swing times so the next click is not on cooldown.
function CombatController.ResetLocalCooldowns()
	table.clear(lastLocalSwing)
end

local wiredTools: { [Tool]: boolean } = {}
local function wireTool(tool: Instance)
	if not tool:IsA("Tool") or wiredTools[tool] then
		return
	end
	local weapon = CombatConfig.GetWeapon(tool:GetAttribute("Weapon"))
	if not weapon then
		return
	end
	wiredTools[tool] = true
	tool.Activated:Connect(function()
		use(weapon)
	end)
	tool.Destroying:Connect(function()
		wiredTools[tool] = nil
	end)
end

--[[ Being hit ------------------------------------------------------------------------- ]]

local function onHitReceived(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local seconds = if typeof(payload.Seconds) == "number" then math.clamp(payload.Seconds, 0, 10) else 0
	local humanoid = getHumanoid()
	local root = getRoot(localPlayer)
	if not humanoid or not root then
		return
	end
	if payload.Freeze == true then
		frozenUntil = serverNow() + seconds
		return
	end
	ragdolledUntil = serverNow() + seconds
	humanoid:UnequipTools()
	local character = localPlayer.Character :: Model
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	-- The launch is the server's KnockbackMover (a LinearVelocity on your
	-- root, simulated here because this client owns the character); nothing
	-- to write from this side.
	ProximityPromptService.Enabled = false
	task.delay(seconds, function()
		ProximityPromptService.Enabled = true
		if localPlayer.Character == character and humanoid.Parent then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

-- Freeze: walk at the multiplier while it lasts (re-applied each frame, so
-- a server speed change during it is honoured after).
local frozenBase: number? = nil
local function stepFreeze()
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end
	if frozenUntil > serverNow() then
		if not frozenBase then
			frozenBase = humanoid.WalkSpeed
		end
		humanoid.WalkSpeed = (frozenBase :: number) * CombatConfig.Freeze.SpeedMultiplier
	elseif frozenBase then
		humanoid.WalkSpeed = frozenBase :: number
		frozenBase = nil
	end
end

--[[ Effects (every client) --------------------------------------------------------------- ]]

-- A short camera shake (Humanoid.CameraOffset), strongest first.
local shakeToken = 0
local function shakeCamera(seconds: number, amplitude: number)
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end
	shakeToken += 1
	local mine = shakeToken
	local started = os.clock()
	task.spawn(function()
		while shakeToken == mine and os.clock() - started < seconds and humanoid.Parent do
			local fade = 1 - (os.clock() - started) / seconds
			humanoid.CameraOffset = Vector3.new((math.random() - 0.5) * 2, (math.random() - 0.5) * 2, 0) * amplitude * fade
			RunService.RenderStepped:Wait()
		end
		if shakeToken == mine and humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
		end
	end)
end

-- The target's body flashes white for FLASH_SECONDS.
local function flashWhite(character: Model)
	local originals: { [BasePart]: Color3 } = {}
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and not part:IsDescendantOf(character:FindFirstChildOfClass("Tool") or character) then
			originals[part] = part.Color
			part.Color = Colors.White
		end
	end
	task.delay(FLASH_SECONDS, function()
		for part, color in originals do
			if part.Parent then
				part.Color = color
			end
		end
	end)
end

local function popText(position: Vector3, text: string, color: Color3, boost: number?)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position + Vector3.new(0, 3, 0)
	anchor.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180 * (boost or 1), 70 * (boost or 1))
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.FontFace = Fonts.Display
	label.TextColor3 = color
	label.Parent = gui
	UIKit.TextStroke(label, UITheme.Stroke.Text)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(anchor, TweenInfo.new(POP_SECONDS), { WorldPosition = anchor.WorldPosition + Vector3.new(0, 2, 0) }):Play()
	task.delay(POP_SECONDS, function()
		anchor:Destroy()
	end)
end

-- The peel is hidden from the player's own eyes while the thrown banana
-- flies (the server places it at once; the arc lands it).
local function hidePeelFor(peel: Instance, seconds: number)
	local hidden = true
	local function hide(instance: Instance)
		if instance:IsA("BasePart") then
			instance.LocalTransparencyModifier = 1
		end
	end
	for _, descendant in peel:GetDescendants() do
		hide(descendant)
	end
	peel.DescendantAdded:Connect(function(descendant)
		if hidden then
			hide(descendant)
		end
	end)
	task.delay(seconds, function()
		hidden = false
		for _, descendant in peel:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.LocalTransparencyModifier = 0
			end
		end
	end)
end

local function watchPeels(folder: Instance)
	folder.ChildAdded:Connect(function(child)
		if child.Name == "BananaPeel" then
			hidePeelFor(child, WeaponFx.THROW_SECONDS)
		end
	end)
end

-- Where a shot leaves from: the attacker's muzzle if their tool is in
-- hand, else the server's origin.
local function muzzlePosition(attacker: Player?, weaponId: string, fallback: Vector3): Vector3
	local tool = if attacker then findHeldTool(attacker, weaponId) else nil
	local muzzle = if tool then WeaponKit.GetMuzzle(tool) else nil
	return if muzzle then muzzle.WorldPosition else fallback
end

local function onHitFx(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local from = if typeof(payload.From) == "Vector3" then payload.From else nil
	local to = if typeof(payload.To) == "Vector3" then payload.To else nil
	local weapon = CombatConfig.GetWeapon(payload.Weapon)
	local attacker = if typeof(payload.Attacker) == "number" then Players:GetPlayerByUserId(payload.Attacker) else nil
	-- Your own swing / shot already played when you clicked.
	local theirs = attacker ~= nil and attacker ~= localPlayer
	if payload.Kind == "Bonk" and to then
		-- A landed hit: a bigger pop, hit-stop on the attacker's swing, a
		-- camera shake for the attacker (short) and the target (longer), and
		-- the target flashes white. (The Bonk sound slot is wired and empty.)
		local glove = payload.Weapon == "SlapGlove"
		popText(to, if glove then "👋 SLAP! 👋" else "💫 BONK! 💫", World.AccentGold, 1.5)
		WeaponFx.FlashRing(to, Colors.White)
		SoundKit.PlayAt("Bonk", to)
		local attackerCharacter = attacker and attacker.Character
		if attackerCharacter then
			WeaponAnimator.HitStop(attackerCharacter, HIT_STOP_SECONDS)
		end
		if attacker == localPlayer then
			shakeCamera(SHAKE_ATTACKER_SECONDS, 0.35)
		end
		local victim = if typeof(payload.Target) == "number" then Players:GetPlayerByUserId(payload.Target) else nil
		if victim == localPlayer then
			shakeCamera(SHAKE_TARGET_SECONDS, 0.6)
		end
		if victim and victim.Character then
			flashWhite(victim.Character)
		end
	elseif payload.Kind == "Immune" and to then
		-- Only the attacker is told: a hit on a target who can't be hit
		-- does nothing, and says why.
		local reason = payload.Reason
		popText(to, if reason == "NeedsRebirth" then "🛡 NEW LAB" elseif reason == "SpawnProtected" then "🛡 SPAWN SAFE" else "🛡 IMMUNE", Colors.Muted)
	elseif payload.Kind == "Refused" and attacker == localPlayer then
		-- The server refused your swing: no silent refusals.
		local text = REFUSED_TEXT[tostring(payload.Reason)]
		if text and os.clock() - lastLockedToast >= LOCKED_TOAST_SECONDS then
			lastLockedToast = os.clock()
			ToastController.Show(text, "Neutral")
		end
	elseif payload.Kind == "Swing" then
		if theirs and weapon then
			performFor(attacker :: Player, weapon)
		end
	elseif payload.Kind == "Slip" and to then
		popText(to, "🍌 SLIP!", World.Banana)
		SoundKit.PlayAt("Slip", to)
	elseif payload.Kind == "Freeze" and to then
		popText(to, "🥶 FROZEN!", World.Ice)
		SoundKit.PlayAt("Freeze", to)
	elseif payload.Kind == "Throw" and from and to then
		if theirs and weapon then
			performFor(attacker :: Player, weapon)
		end
		WeaponFx.Throw(from, to)
	elseif payload.Kind == "Beam" and from and to then
		if theirs and weapon then
			performFor(attacker :: Player, weapon)
		end
		local start = muzzlePosition(attacker, "LaserGun", from)
		WeaponFx.Beam(start, to, World.WeaponLaser, LASER_BEAM_SECONDS)
		WeaponFx.Impact(to, World.WeaponLaser)
		SoundKit.PlayAt("Laser", start)
	elseif payload.Kind == "FreezeBeam" and from and to then
		if theirs and weapon then
			performFor(attacker :: Player, weapon)
		end
		local start = muzzlePosition(attacker, "FreezeRay", from)
		WeaponFx.Beam(start, to, World.Ice, FREEZE_BEAM_SECONDS)
		WeaponFx.FreezeCone(start, start + (to - start).Unit * math.min((to - start).Magnitude, FREEZE_CONE_STUDS))
		WeaponFx.Impact(to, World.Ice)
		SoundKit.PlayAt("Freeze", start)
	end
end

-- Icy tint on frozen players, a shimmer on immune ones (client-only).
local function stepLooks()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			local frozen = untilActive(player, "FrozenUntil")
			if frozen and not tinted[character] then
				local originals: { [BasePart]: Color3 } = {}
				for _, part in character:GetDescendants() do
					if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
						originals[part] = part.Color
						part.Color = World.Ice
					end
				end
				tinted[character] = originals
				WeaponFx.Frost.On(character)
			elseif not frozen and tinted[character] then
				WeaponFx.Frost.Off(character)
				for part, color in tinted[character] do
					if part.Parent then
						part.Color = color
					end
				end
				tinted[character] = nil
			end
			local immune = untilActive(player, "ImmuneUntil") and not untilActive(player, "RagdollUntil") and not frozen
			if immune or shimmering[character] then
				local value = if immune then SHIMMER_MAX * (0.5 + 0.5 * math.sin(now * SHIMMER_SPEED)) else 0
				for _, part in character:GetDescendants() do
					if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
						part.LocalTransparencyModifier = value
					end
				end
				if immune then
					shimmering[character] = true
				else
					shimmering[character] = nil
				end
			end
		end
	end
end

--[[ Unlock card ---------------------------------------------------------------------- ]]

local function showUnlocks()
	if #pendingUnlocks == 0 or TycoonController.IsTutorialActive() or TutorialCards.IsOpen() then
		return
	end
	local id = table.remove(pendingUnlocks, 1) :: string
	local weapon = CombatConfig.GetWeapon(id)
	if weapon then
		TutorialCards.ShowStep({
			Icon = weapon.Glyph,
			Weapon = weapon.Id,
			Title = ("You got a %s!"):format(weapon.Name),
			Body = weapon.Blurb,
		}, nil, showUnlocks)
	end
end

--[[ Watching tools in hand (everyone's) ---------------------------------------------- ]]

local function isGun(weapon: CombatConfig.Weapon): boolean
	return weapon.Kind == "Ranged" or weapon.Kind == "Freeze"
end

-- A weapon came up in `character`'s hand: the raise, the sound, and the aim
-- pose for guns.
local toolEventsLogged = 0

-- The arm: an animation track when there is a clip, else the C0 pose.
local function poseHold(character: Model, weapon: CombatConfig.Weapon)
	if not WeaponAnimator.Hold(character, weapon) then
		WeaponPose.Hold(character, weapon)
	end
end

-- Screen-px rect (top-bar inset added back) of the weapon bar while it is
-- shown, else nil: the Gacha card stays above it.
function CombatController.GetBarRect(): { Position: Vector2, Size: Vector2 }?
	if not screenGui or not screenGui.Enabled or not bar or bar.AbsoluteSize.X <= 0 then
		return nil
	end
	return { Position = bar.AbsolutePosition + Vector2.new(0, GuiService:GetGuiInset().Y), Size = bar.AbsoluteSize }
end

-- The weapon whose pose is up (track or C0), for /selftest and the re-hold.
function CombatController.GetHeldPoseWeapon(character: Model): string?
	return WeaponAnimator.GetHeldWeapon(character) or WeaponPose.GetHeldWeapon(character)
end

-- Studio only, a few lines per run: the order of tool ChildAdded / ChildRemoved
-- on a slot switch (the new tool's Add arrives BEFORE the old one's Remove).
local function logToolEvent(what: string, tool: Instance)
	if toolEventsLogged >= 8 or not RunService:IsStudio() or not tool:GetAttribute("Weapon") then
		return
	end
	toolEventsLogged += 1
	print(("[CombatController] tool event: %s %s"):format(what, tool.Name))
end

-- A weapon came up in `character`'s hand: the raise, the sound, and the aim
-- pose for guns.
local function onToolAdded(player: Player, character: Model, tool: Instance)
	local weapon = if tool:IsA("Tool") then CombatConfig.GetWeapon(tool:GetAttribute("Weapon")) else nil
	if not weapon then
		return
	end
	logToolEvent("added", tool)
	poseHold(character, weapon)
	local root = getRoot(player)
	if root then
		SoundKit.PlayAt("Equip", root.Position)
	end
end

local function onToolRemoved(player: Player, character: Model, tool: Instance)
	if not (tool:IsA("Tool") and CombatConfig.GetWeapon(tool:GetAttribute("Weapon"))) then
		return
	end
	logToolEvent("removed", tool)
	-- Only the removed weapon's own pose goes: on a slot switch the new tool
	-- was already added and its pose must stay.
	local removedId = tostring(tool:GetAttribute("Weapon"))
	WeaponAnimator.Release(character, removedId)
	WeaponPose.Release(character, removedId)
	-- Whatever order the events fired in, a weapon still in the hand is held.
	for _, child in character:GetChildren() do
		if child ~= tool and child:IsA("Tool") then
			local other = CombatConfig.GetWeapon(child:GetAttribute("Weapon"))
			if other and CombatController.GetHeldPoseWeapon(character) ~= other.Id then
				poseHold(character, other)
			end
		end
	end
end

local function watchPlayer(player: Player)
	local function watchCharacter(character: Model)
		for _, child in character:GetChildren() do
			onToolAdded(player, character, child)
		end
		character.ChildAdded:Connect(function(child)
			onToolAdded(player, character, child)
		end)
		character.ChildRemoved:Connect(function(child)
			onToolRemoved(player, character, child)
		end)
	end
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

-- Your gun arm follows where you aim (pitch only; the camera stays free).
local function stepAim()
	local character = localPlayer.Character
	if not character then
		return
	end
	for _, weapon in CombatConfig.Weapons do
		if isGun(weapon) and character:FindFirstChild(weapon.Id) then
			local direction = aimDirection()
			if direction then
				WeaponPose.SetAimPitch(character, math.asin(math.clamp(direction.Y, -1, 1)))
			end
			return
		end
	end
end

-- /selftest: plays `weaponId`'s swing / shot / toss on your own character
-- as if you had clicked (the tool must be equipped); returns whether it was.
function CombatController.PlayPose(weaponId: string): boolean
	local weapon = CombatConfig.GetWeapon(weaponId)
	if not weapon or not findHeldTool(localPlayer, weapon.Id) then
		return false
	end
	performFor(localPlayer, weapon)
	return true
end

function CombatController.Init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	screenGui = UIKit.Screen("WeaponBar", 41)
	screenGui.Enabled = false -- refreshBar turns it on at Rebirth 1+ (and off during the tutorial)
	bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundTransparency = 1
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.AutomaticSize = Enum.AutomaticSize.XY
	bar.Size = UDim2.new()
	bar.Parent = screenGui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.Parent = bar

	local lastKey = ""
	TycoonController.TycoonChanged:Connect(function()
		local key = table.concat(TycoonController.GetWeapons(), ",") .. ("|%d"):format(TycoonController.GetRebirths())
		if key ~= lastKey then
			lastKey = key
			rebuildBar()
		end
	end)
	UIKit.LayoutChanged:Connect(rebuildBar)
	rebuildBar()
	refreshBar()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local index = table.find(KEY_CODES, input.KeyCode)
		if not index then
			return
		end
		local owned = ownedWeapons()
		local n = 0
		for _, slot in slots do
			if owned[slot.Weapon.Id] then
				n += 1
				if n == index then
					toggleEquip(slot.Weapon)
					return
				end
			end
		end
	end)

	local function watchCharacter(character: Model)
		for _, child in character:GetChildren() do
			wireTool(child)
		end
		character.ChildAdded:Connect(wireTool)
	end
	localPlayer.CharacterAdded:Connect(watchCharacter)
	if localPlayer.Character then
		watchCharacter(localPlayer.Character)
	end

	RemoteEvents.HitReceived.OnClientEvent:Connect(onHitReceived)
	RemoteEvents.HitFx.OnClientEvent:Connect(onHitFx)
	RemoteEvents.WeaponUnlocked.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.Weapon) == "string" then
			table.insert(pendingUnlocks, payload.Weapon)
			showUnlocks()
		end
	end)
	TycoonController.TycoonChanged:Connect(showUnlocks)
	RunService.Heartbeat:Connect(function()
		refreshBar()
		stepFreeze()
		stepLooks()
		stepAim()
	end)

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	local existing = Workspace:FindFirstChild("CombatObjects")
	if existing then
		watchPeels(existing)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "CombatObjects" then
			watchPeels(child)
		end
	end)
end

return CombatController
