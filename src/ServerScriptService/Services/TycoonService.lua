local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage.Shared.Config
local TycoonConfig = require(Config.TycoonConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

local PlayerDataService = require(script.Parent.PlayerDataService)

local TycoonService = {}

local PLOTS_FOLDER_NAME = "PlayerTycoons"
local MAX_PLOT_SLOTS = 50
local PLOT_SLOT_SPACING_STUDS = 60
local CASH_DROP_DEBRIS_LIFETIME_SECONDS = 30
-- How far in front of Dropper1 (along its facing direction) the Collector sits,
-- so cash lands on the open floor first instead of spawning right on top of it.
local COLLECTOR_FORWARD_OFFSET_STUDS = 12
local CASH_DROP_FORWARD_SPEED_STUDS_PER_SECOND = 6

-- Cash parts belong to their own collision group so they pass through player
-- characters (left in "Default") without being bumped. Floor/Collector are
-- moved into a second group so they keep colliding with cash even though
-- "Default" no longer does.
local CASH_COLLISION_GROUP = "CashParts"
local PLOT_ENVIRONMENT_COLLISION_GROUP = "PlotEnvironment"

local DROPPER2_COST = 100
local DROPPER2_LABEL = "Buy Dropper 2"
local DROPPER2_SIDE_OFFSET_STUDS = 12

-- Slot bookkeeping: a fixed row of slots is reused as players join/leave
-- rather than growing forever.
local occupiedSlots: { [number]: boolean } = {}
local slotByUserId: { [number]: number } = {}
local plotByUserId: { [number]: Model } = {}

local function syncTycoon(player: Player)
	RemoteEvents.SyncTycoon:FireClient(player, {
		Cash = PlayerDataService.GetCash(player),
		Generators = PlayerDataService.GetGenerators(player) or {},
	})
end

local function calculateTotalCashPerSecond(player: Player): number
	local generatorLevels = PlayerDataService.GetGenerators(player)
	if not generatorLevels then
		return 0
	end

	local total = 0
	for _, generator in TycoonConfig.Generators do
		local level = generatorLevels[generator.Id] or 0
		if level > 0 then
			total += TycoonConfig.GetGeneratorCashPerSecond(generator, level)
		end
	end
	return total
end

local function onPassiveIncomeTick()
	for _, player in Players:GetPlayers() do
		if PlayerDataService.IsDataLoaded(player) then
			local cashPerSecond = calculateTotalCashPerSecond(player)
			if cashPerSecond > 0 then
				local income = cashPerSecond * TycoonConfig.PassiveIncomeIntervalSeconds
				PlayerDataService.AddCash(player, income)
				syncTycoon(player)
			end
		end
	end
end

local function onRequestUpgrade(player: Player, rawGeneratorId: unknown)
	if typeof(rawGeneratorId) ~= "string" then
		RemoteEvents.UpgradeResult:FireClient(player, { Success = false, Reason = "InvalidGenerator" })
		return
	end
	local generatorId = rawGeneratorId :: string

	if not PlayerDataService.IsDataLoaded(player) then
		RemoteEvents.UpgradeResult:FireClient(player, { Success = false, Reason = "DataNotLoaded", GeneratorId = generatorId })
		return
	end

	local generator = TycoonConfig.GetGeneratorById(generatorId)
	if not generator then
		RemoteEvents.UpgradeResult:FireClient(player, { Success = false, Reason = "InvalidGenerator", GeneratorId = generatorId })
		return
	end

	local generatorLevels = PlayerDataService.GetGenerators(player) or {}
	if not TycoonConfig.IsUnlocked(generator, generatorLevels) then
		RemoteEvents.UpgradeResult:FireClient(player, { Success = false, Reason = "Locked", GeneratorId = generatorId })
		return
	end

	local currentLevel = generatorLevels[generatorId] or 0
	if currentLevel >= generator.MaxLevel then
		RemoteEvents.UpgradeResult:FireClient(player, { Success = false, Reason = "MaxLevel", GeneratorId = generatorId })
		return
	end

	local cost = TycoonConfig.GetUpgradeCost(generator, currentLevel)
	if not PlayerDataService.SpendCash(player, cost) then
		RemoteEvents.UpgradeResult:FireClient(player, { Success = false, Reason = "InsufficientCash", GeneratorId = generatorId })
		return
	end

	local newLevel = currentLevel + 1
	PlayerDataService.SetGeneratorLevel(player, generatorId, newLevel)

	RemoteEvents.UpgradeResult:FireClient(player, {
		Success = true,
		GeneratorId = generatorId,
		NewLevel = newLevel,
	})
	syncTycoon(player)
end

--[[ Plot lifecycle: TycoonTemplate is cloned into Workspace for every player
	on join and reserved for them (OwnerUserId attribute), but stays inactive
	until that player touches their plot's ClaimButton, which starts Dropper1
	producing cash items. ]]

-- Registers the collision groups used by dropped cash and disables collision
-- between cash and "Default" (players, and any plot geometry left unassigned).
-- Floor/Collector are explicitly moved into PlotEnvironment in createCollector
-- so they keep colliding with cash despite that.
local function setupCollisionGroups()
	-- pcall guards against "already exists" errors if this ever re-runs
	-- (e.g. Studio script hot-reload) without a full server restart.
	pcall(function()
		PhysicsService:RegisterCollisionGroup(CASH_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(PLOT_ENVIRONMENT_COLLISION_GROUP)
	end)

	PhysicsService:CollisionGroupSetCollidable(CASH_COLLISION_GROUP, "Default", false)
end

local function getPlotsFolder(): Folder
	local folder = Workspace:FindFirstChild(PLOTS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PLOTS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function claimSlotIndex(): number
	for index = 1, MAX_PLOT_SLOTS do
		if not occupiedSlots[index] then
			occupiedSlots[index] = true
			return index
		end
	end
	error("TycoonService: no free plot slots available (raise MAX_PLOT_SLOTS)")
end

local function releaseSlotIndex(index: number)
	occupiedSlots[index] = nil
end

-- Resolves the touching Player only for an actual character limb, so tools,
-- accessories, or other props touching a button/pickup are ignored.
local function getTouchingPlayer(hit: BasePart): Player?
	local character = hit.Parent
	if not character or not character:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

-- Awards a Collector pickup's worth of cash and pushes an immediate balance sync.
local function awardCash(player: Player, amount: number)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	PlayerDataService.AddCash(player, amount)
	syncTycoon(player)
end

-- Spawns an unanchored, collidable cash part above Dropper1 so it physically
-- falls; collection happens on contact with the plot's Collector pad, not by
-- the player touching the falling part directly.
local function spawnCashPart(plot: Model, dropper: BasePart)
	local cashPart = Instance.new("Part")
	cashPart.Name = "CashDrop"
	cashPart.Shape = Enum.PartType.Ball
	cashPart.Size = Vector3.new(1.5, 1.5, 1.5)
	cashPart.Color = Color3.fromRGB(85, 255, 127)
	cashPart.Material = Enum.Material.Neon
	cashPart.Anchored = false
	cashPart.CanCollide = true
	cashPart.CollisionGroup = CASH_COLLISION_GROUP
	cashPart.Position = dropper.Position + Vector3.new(0, dropper.Size.Y / 2 + 1, 0)
	cashPart:SetAttribute("CashValue", TycoonConfig.DropperCashValue)
	cashPart.Parent = plot

	-- Nudge it toward the Collector so it rolls across the floor as it falls,
	-- instead of dropping straight down and landing wherever it spawned.
	cashPart.AssemblyLinearVelocity = dropper.CFrame.LookVector * CASH_DROP_FORWARD_SPEED_STUDS_PER_SECOND

	-- Safety net in case a part rolls astray and never reaches the Collector.
	Debris:AddItem(cashPart, CASH_DROP_DEBRIS_LIFETIME_SECONDS)
end

-- Creates the Collector pad on the plot's Floor, offset in front of Dropper1,
-- and wires it to credit the plot owner whenever a cash part lands on it.
local function createCollector(plot: Model, dropper: BasePart, player: Player): BasePart
	local floor = plot:FindFirstChild("Floor", true)
	local floorTopY = 0
	if floor and floor:IsA("BasePart") then
		local floorPart = floor :: BasePart
		floorTopY = floorPart.Position.Y + floorPart.Size.Y / 2
		floorPart.CollisionGroup = PLOT_ENVIRONMENT_COLLISION_GROUP
	end

	-- Offset along Dropper1's facing direction: cash spawns above the dropper
	-- and lands on open floor first, then travels to the Collector rather than
	-- dropping straight onto it.
	local forward = dropper.CFrame.LookVector
	local collectorTarget = dropper.Position + forward * COLLECTOR_FORWARD_OFFSET_STUDS

	local collector = Instance.new("Part")
	collector.Name = "Collector"
	collector.Size = Vector3.new(6, 1, 6)
	collector.Anchored = true
	collector.CanCollide = true
	collector.CollisionGroup = PLOT_ENVIRONMENT_COLLISION_GROUP
	collector.Material = Enum.Material.Neon
	collector.Color = Color3.fromRGB(255, 215, 0)
	collector.Position = Vector3.new(collectorTarget.X, floorTopY + collector.Size.Y / 2, collectorTarget.Z)
	collector.Parent = plot

	collector.Touched:Connect(function(hit: BasePart)
		if hit.Parent == nil or hit:GetAttribute("Collected") then
			return
		end
		local value = hit:GetAttribute("CashValue")
		if not value then
			return
		end

		hit:SetAttribute("Collected", true)
		hit:Destroy()
		awardCash(player, value)
	end)

	return collector
end

-- Self-terminating: the loop exits once the plot is destroyed (Parent becomes nil).
-- `dropper` must already be resolved by the caller, since this is shared by
-- both Dropper1 (found in the template) and Dropper2 (spawned on purchase).
local function startDropperLoop(plot: Model, player: Player, dropper: BasePart, dropperLabel: string)
	createCollector(plot, dropper, player)
	print(("TycoonService: %s's %s is now producing cash"):format(player.Name, dropperLabel))

	task.spawn(function()
		while plot.Parent do
			task.wait(TycoonConfig.DropperIntervalSeconds)
			if not plot.Parent then
				break
			end
			spawnCashPart(plot, dropper)
		end
	end)
end

-- Clones Dropper1's appearance to build Dropper2, offset to the side so it
-- doesn't overlap the original, then starts it producing cash the same way.
local function spawnDropper2(plot: Model, player: Player, referenceDropper: BasePart)
	local dropper2 = referenceDropper:Clone()
	dropper2.Name = "Dropper2"
	dropper2.CFrame = referenceDropper.CFrame + referenceDropper.CFrame.RightVector * DROPPER2_SIDE_OFFSET_STUDS
	dropper2.Parent = plot

	startDropperLoop(plot, player, dropper2, "Dropper2")
end

-- Spawns a purchase button on the Floor (at the spot Dropper2 will occupy)
-- that, once bought by the plot owner, deducts DROPPER2_COST and spawns Dropper2.
local function createPurchaseButton(plot: Model, player: Player, dropper1: BasePart)
	local floor = plot:FindFirstChild("Floor", true)
	local floorTopY = 0
	if floor and floor:IsA("BasePart") then
		floorTopY = (floor :: BasePart).Position.Y + (floor :: BasePart).Size.Y / 2
	end

	local buttonTarget = dropper1.Position + dropper1.CFrame.RightVector * DROPPER2_SIDE_OFFSET_STUDS

	local button = Instance.new("Part")
	button.Name = "BuyDropper2Button"
	button.Size = Vector3.new(4, 1, 4)
	button.Anchored = true
	button.CanCollide = true
	button.Material = Enum.Material.Neon
	button.Color = Color3.fromRGB(60, 160, 255)
	button.Position = Vector3.new(buttonTarget.X, floorTopY + button.Size.Y / 2, buttonTarget.Z)
	button.Parent = plot

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(160, 50)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = button

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ("%s\n$%d"):format(DROPPER2_LABEL, DROPPER2_COST)
	label.Parent = billboard

	local purchased = false
	local connection: RBXScriptConnection
	connection = button.Touched:Connect(function(hit: BasePart)
		if purchased then
			return
		end
		local toucher = getTouchingPlayer(hit)
		if not toucher or toucher.UserId ~= player.UserId then
			return
		end

		if not PlayerDataService.SpendCash(player, DROPPER2_COST) then
			return
		end

		purchased = true
		connection:Disconnect()
		syncTycoon(player)
		button:Destroy()

		print(("TycoonService: %s purchased Dropper2"):format(player.Name))
		spawnDropper2(plot, player, dropper1)
	end)
end

local function connectClaimButton(plot: Model, player: Player)
	-- Recursive lookup: ClaimButton may be nested under an organizational group/folder.
	local claimButton = plot:FindFirstChild("ClaimButton", true)
	if not claimButton or not claimButton:IsA("BasePart") then
		warn(("TycoonService: ClaimButton missing or not a BasePart in %s's plot"):format(player.Name))
		return
	end

	local buttonPart = claimButton :: BasePart

	-- Touched only fires while CanTouch is true; force it in case the template disabled it.
	buttonPart.CanTouch = true

	print(("TycoonService: ClaimButton connected for %s"):format(player.Name))

	local connection: RBXScriptConnection
	connection = buttonPart.Touched:Connect(function(hit: BasePart)
		local toucher = getTouchingPlayer(hit)
		if not toucher then
			return
		end
		if toucher.UserId ~= player.UserId then
			print(("TycoonService: %s touched %s's ClaimButton but doesn't own it"):format(toucher.Name, player.Name))
			return
		end
		if plot:GetAttribute("Claimed") then
			return
		end

		plot:SetAttribute("Claimed", true)
		connection:Disconnect()

		-- Retire the button visually/physically now that it's served its purpose.
		buttonPart.Transparency = 1
		buttonPart.CanCollide = false
		buttonPart.CanTouch = false

		print(("TycoonService: %s claimed their plot"):format(player.Name))

		-- Recursive lookup: Dropper1 may be nested under an organizational group/folder.
		local dropper1 = plot:FindFirstChild("Dropper1", true)
		if not dropper1 or not dropper1:IsA("BasePart") then
			warn(("TycoonService: Dropper1 missing or not a BasePart in %s's plot"):format(player.Name))
			return
		end

		startDropperLoop(plot, player, dropper1 :: BasePart, "Dropper1")
		createPurchaseButton(plot, player, dropper1 :: BasePart)
	end)
end

local function createPlotForPlayer(player: Player)
	if plotByUserId[player.UserId] then
		return
	end

	local template = ReplicatedStorage:FindFirstChild("TycoonTemplate")
	if not template then
		warn("TycoonService: ReplicatedStorage.TycoonTemplate not found; skipping plot creation for " .. player.Name)
		return
	end

	local slotIndex = claimSlotIndex()
	slotByUserId[player.UserId] = slotIndex

	local plot = template:Clone()
	plot.Name = ("Tycoon_%d"):format(player.UserId)
	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("Claimed", false)
	plot.Parent = getPlotsFolder()

	if plot:IsA("Model") then
		(plot :: Model):PivotTo(CFrame.new((slotIndex - 1) * PLOT_SLOT_SPACING_STUDS, 0, 0))
	else
		warn("TycoonService: TycoonTemplate is not a Model, so plots cannot be repositioned and will overlap")
	end

	print(("TycoonService: created plot for %s in slot %d"):format(player.Name, slotIndex))

	plotByUserId[player.UserId] = plot :: Model
	connectClaimButton(plot :: Model, player)
end

local function removePlotForPlayer(player: Player)
	local plot = plotByUserId[player.UserId]
	if plot then
		plot:Destroy()
		plotByUserId[player.UserId] = nil
	end

	local slotIndex = slotByUserId[player.UserId]
	if slotIndex then
		releaseSlotIndex(slotIndex)
		slotByUserId[player.UserId] = nil
	end
end

function TycoonService.Init()
	setupCollisionGroups()

	RemoteEvents.RequestUpgrade.OnServerEvent:Connect(onRequestUpgrade)

	Players.PlayerAdded:Connect(createPlotForPlayer)
	Players.PlayerRemoving:Connect(removePlotForPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(createPlotForPlayer, player)
	end

	task.spawn(function()
		while true do
			task.wait(TycoonConfig.PassiveIncomeIntervalSeconds)
			onPassiveIncomeTick()
		end
	end)
end

return TycoonService
