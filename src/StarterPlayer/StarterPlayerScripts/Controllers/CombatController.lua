--!strict
--[[
	CombatController
	----------------
	The client half of weapons and ragdoll (CombatConfig; CombatService
	decides every hit).

	  * Weapon bar: the default Backpack bar is replaced by a row of glyph
	    circles (built from UITheme, no images) centred above the bottom
	    buttons: number keys 1-5 or a tap equip / unequip; a dark wipe shows
	    each weapon's cooldown; weapons a rebirth will unlock show greyed
	    with "R1" / "R2" / "R3" (a tap says "Unlocks at Rebirth N"); the
	    whole bar greys while you carry a stolen orb (hands full).
	  * Using one (Tool.Activated): melee sends the nearest eligible player
	    in front of you; ranged and the Freeze Ray send where you aim (the
	    mouse on a computer, the camera's centre on a touch screen); the
	    Banana Peel goes on the ground in front of you. RequestHit only; the
	    server re-checks everything.
	  * HitReceived: you ragdoll (Humanoid Physics state + the impulse; the
	    server swaps your joints and restores them) and prompts switch off
	    until you're up; or you freeze (40% speed). The server's times rule.
	  * Every client: HitFx effects (BONK! pop with stars, a thin Neon beam
	    seen from the side, SLIP!), the icy tint on frozen players, a faint
	    shimmer on immune ones, and the sound slots.
	  * WeaponUnlocked: the tutorial-style card "🏏 You got a Bat!" (after
	    the tutorial, if it's still running).
]]
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
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local UI = script.Parent.Parent.UI
local UIKit = require(UI.UIKit)
local TutorialCards = require(UI.TutorialCards)
local TycoonController = require(script.Parent.TycoonController)
local ToastController = require(script.Parent.ToastController)

local CombatController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts
local World = UITheme.World

local SLOT_SIZE = { Desktop = 56, Phone = 52 }
local SLOT_GAP = 10
-- Above the HUD's bottom row (22 margin + 64 / 60 button + 5 shadow) + a gap.
local BAR_BOTTOM = { Desktop = 22 + 64 + 5 + 12, Phone = 22 + 60 + 5 + 12 }
local BEAM_SECONDS = 0.18
local BEAM_THICKNESS = 0.25
local POP_SECONDS = 0.9
local SHIMMER_SPEED = 10
local SHIMMER_MAX = 0.45
local KEY_CODES = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }

local localPlayer = Players.LocalPlayer

type Slot = { Weapon: CombatConfig.Weapon, Button: TextButton, Holder: Frame, Wipe: Frame, Badge: TextLabel }

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

local function rebirthsOf(player: Player): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Rebirths")
	return if value and value:IsA("IntValue") then value.Value else 0
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
		if weapon.UnlockRebirth then
			ToastController.Show(("Unlocks at Rebirth %d"):format(weapon.UnlockRebirth), "Neutral")
		end
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

local function rebuildBar()
	for _, child in bar:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	slots = {}
	local owned = ownedWeapons()
	local size = if UIKit.IsPhone() then SLOT_SIZE.Phone else SLOT_SIZE.Desktop
	local key = 0
	for order, weapon in CombatConfig.Weapons do
		local has = owned[weapon.Id] == true
		-- Quest weapons only show once earned; rebirth ones always (greyed).
		if has or weapon.UnlockRebirth then
			local button, holder = UIKit.Button({
				Name = weapon.Id,
				Parent = bar,
				Style = if has then "Violet" else "Disabled",
				Text = weapon.Glyph,
				TextSize = math.floor(size * 0.5),
				Size = UDim2.fromOffset(size, size),
				Radius = 999,
				LayoutOrder = order,
				ShadowOffset = UITheme.SmallShadowOffset,
				OnClick = function()
					toggleEquip(weapon)
				end,
			})
			local wipe = Instance.new("Frame")
			wipe.Name = "Cooldown"
			wipe.AnchorPoint = Vector2.new(0, 1)
			wipe.Position = UDim2.fromScale(0, 1)
			wipe.Size = UDim2.fromScale(1, 0)
			wipe.BackgroundColor3 = Colors.Black
			wipe.BackgroundTransparency = 0.45
			wipe.BorderSizePixel = 0
			wipe.ZIndex = button.ZIndex + 3
			wipe.Parent = button
			UIKit.Corner(wipe, 999)
			if has then
				key += 1
			end
			local badge = UIKit.Label({
				Name = "Badge",
				Text = if has then tostring(key) else ("R%d"):format(weapon.UnlockRebirth or 0),
				Font = Fonts.Display,
				TextSize = 13,
				TextColor3 = Colors.Text,
				Stroke = UITheme.Stroke.Text,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 2, 0, -4),
				Size = UDim2.fromOffset(26, 16),
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = button.ZIndex + 4,
				Parent = holder,
			})
			table.insert(slots, { Weapon = weapon, Button = button, Holder = holder, Wipe = wipe, Badge = badge })
		end
	end
	bar.Position = UDim2.new(0.5, 0, 1, -(if UIKit.IsPhone() then BAR_BOTTOM.Phone else BAR_BOTTOM.Desktop))
	-- No bar at all before Rebirth 1: nobody can hit you, you can't hit
	-- anyone, and three greyed slots are noise for a new player.
	screenGui.Enabled = TycoonController.GetRebirths() >= 1
end

local function refreshBar()
	local carrying = isCarrying()
	local character = localPlayer.Character
	local now = os.clock()
	for _, slot in slots do
		local weapon = slot.Weapon
		local last = lastLocalSwing[weapon.Id]
		local left = if last then math.max(0, weapon.Cooldown - (now - last)) else 0
		slot.Wipe.Size = UDim2.fromScale(1, if weapon.Cooldown > 0 then left / weapon.Cooldown else 0)
		local equipped = character ~= nil and character:FindFirstChild(weapon.Id) ~= nil
		local stroke = slot.Button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if equipped then World.AccentGold else Colors.Ink
		end
		slot.Button.BackgroundTransparency = if carrying then 0.5 else 0
	end
end

--[[ Using a weapon --------------------------------------------------------------------- ]]

-- The nearest other player a melee swing could reach (the server decides).
local function meleeTarget(weapon: CombatConfig.Weapon): Player?
	local root = getRoot(localPlayer)
	if not root then
		return nil
	end
	local best: Player? = nil
	local bestDistance = math.huge
	local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	for _, other in Players:GetPlayers() do
		local otherRoot = if other ~= localPlayer then getRoot(other) else nil
		if otherRoot and rebirthsOf(other) >= CombatConfig.MinRebirths then
			local offset = otherRoot.Position - root.Position
			local distance = offset.Magnitude
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local inFront = flat.Magnitude < 1
				or facing.Magnitude == 0
				or math.deg(math.acos(math.clamp(flat.Unit:Dot(facing.Unit), -1, 1))) <= CombatConfig.MeleeMaxAngle
			if distance <= weapon.Range + 1 and inFront and distance < bestDistance then
				best, bestDistance = other, distance
			end
		end
	end
	return best
end

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

local function use(weapon: CombatConfig.Weapon)
	if isCarrying() then
		ToastController.Show("Hands full: run it home!", "Neutral")
		return
	end
	if ragdolledUntil > serverNow() then
		return
	end
	local last = lastLocalSwing[weapon.Id]
	if last and os.clock() - last < weapon.Cooldown then
		return
	end
	lastLocalSwing[weapon.Id] = os.clock()
	if weapon.Kind == "Melee" then
		local target = meleeTarget(weapon)
		RemoteEvents.RequestHit:FireServer({ Weapon = weapon.Id, TargetUserId = if target then target.UserId else nil })
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
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	if typeof(payload.Impulse) == "Vector3" then
		root:ApplyImpulse(payload.Impulse * root.AssemblyMass)
	end
	ProximityPromptService.Enabled = false
	local character = localPlayer.Character
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

local function popText(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position + Vector3.new(0, 3, 0)
	anchor.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 70)
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

-- A thin Neon cylinder between two points (seen from the side, never a
-- flat circle facing up), gone in BEAM_SECONDS.
local function beam(from: Vector3, to: Vector3, color: Color3)
	local length = (to - from).Magnitude
	if length < 0.1 then
		return
	end
	local part = Instance.new("Part")
	part.Name = "WeaponBeam"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(length, BEAM_THICKNESS, BEAM_THICKNESS)
	part.CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0)
	part.Parent = Workspace.Terrain
	TweenService:Create(part, TweenInfo.new(BEAM_SECONDS), { Transparency = 1 }):Play()
	task.delay(BEAM_SECONDS, function()
		part:Destroy()
	end)
end

local function onHitFx(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local from = if typeof(payload.From) == "Vector3" then payload.From else nil
	local to = if typeof(payload.To) == "Vector3" then payload.To else nil
	if payload.Kind == "Bonk" and to then
		popText(to, "💫 BONK! 💫", World.AccentGold)
		SoundKit.PlayAt("Bonk", to)
	elseif payload.Kind == "Slip" and to then
		popText(to, "🍌 SLIP!", World.Banana)
		SoundKit.PlayAt("Slip", to)
	elseif payload.Kind == "Freeze" and to then
		popText(to, "🥶 FROZEN!", World.Ice)
		SoundKit.PlayAt("Freeze", to)
	elseif payload.Kind == "Beam" and from and to then
		beam(from, to, World.WeaponLaser)
		SoundKit.PlayAt("Laser", from)
	elseif payload.Kind == "FreezeBeam" and from and to then
		beam(from, to, World.Ice)
		SoundKit.PlayAt("Freeze", from)
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
			elseif not frozen and tinted[character] then
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
			Title = ("You got a %s!"):format(weapon.Name),
			Body = weapon.Blurb,
		}, nil, showUnlocks)
	end
end

function CombatController.Init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	screenGui = UIKit.Screen("WeaponBar", 41)
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
	end)
end

return CombatController
