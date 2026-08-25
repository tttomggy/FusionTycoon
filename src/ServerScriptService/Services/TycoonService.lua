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

-- Awards one Dropper1 pickup's worth of cash and pushes an immediate balance sync.
local function awardDropperCash(player: Player)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	PlayerDataService.AddCash(player, TycoonConfig.DropperCashValue)
	syncTycoon(player)
end

local function spawnCashPart(plot: Model, player: Player, dropper: BasePart)
	local cashPart = Instance.new("Part")
	cashPart.Name = "CashDrop"
	cashPart.Shape = Enum.PartType.Ball
	cashPart.Size = Vector3.new(1.5, 1.5, 1.5)
	cashPart.Color = Color3.fromRGB(85, 255, 127)
	cashPart.Material = Enum.Material.Neon
	cashPart.Anchored = true
	cashPart.CanCollide = false
	cashPart.Position = dropper.Position + Vector3.new(0, dropper.Size.Y / 2 + 1, 0)
	cashPart:SetAttribute("CashValue", TycoonConfig.DropperCashValue)
	cashPart.Parent = plot

	local collected = false
	cashPart.Touched:Connect(function(hit: BasePart)
		if collected then
			return
		end
		local toucher = getTouchingPlayer(hit)
		if not toucher or toucher.UserId ~= player.UserId then
			return
		end

		collected = true
		awardDropperCash(player)
		cashPart:Destroy()
	end)
end

-- Self-terminating: the loop exits once the plot is destroyed (Parent becomes nil).
local function startDropperLoop(plot: Model, player: Player)
	-- Recursive lookup: Dropper1 may be nested under an organizational group/folder.
	local dropper = plot:FindFirstChild("Dropper1", true)
	if not dropper or not dropper:IsA("BasePart") then
		warn(("TycoonService: Dropper1 missing or not a BasePart in %s's plot"):format(player.Name))
		return
	end

	print(("TycoonService: %s's Dropper1 is now producing cash"):format(player.Name))

	task.spawn(function()
		while plot.Parent do
			task.wait(TycoonConfig.DropperIntervalSeconds)
			if not plot.Parent then
				break
			end
			spawnCashPart(plot, player, dropper :: BasePart)
		end
	end)
end

local function connectClaimButton(plot: Model, player: Player)
	-- Recursive lookup: ClaimButton may be nested under an organizational group/folder.
	local claimButton = plot:FindFirstChild("ClaimButton", true)
	if not claimButton or not claimButton:IsA("BasePart") then
		warn(("TycoonService: ClaimButton missing or not a BasePart in %s's plot"):format(player.Name))
		return
	end

	-- Touched only fires while CanTouch is true; force it in case the template disabled it.
	(claimButton :: BasePart).CanTouch = true

	print(("TycoonService: ClaimButton connected for %s"):format(player.Name))

	local connection: RBXScriptConnection
	connection = (claimButton :: BasePart).Touched:Connect(function(hit: BasePart)
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
		print(("TycoonService: %s claimed their plot"):format(player.Name))
		startDropperLoop(plot, player)
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
