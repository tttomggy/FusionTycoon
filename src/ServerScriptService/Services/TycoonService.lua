local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Shared.Config
local TycoonConfig = require(Config.TycoonConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

local PlayerDataService = require(script.Parent.PlayerDataService)

local TycoonService = {}

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

function TycoonService.Init()
	RemoteEvents.RequestUpgrade.OnServerEvent:Connect(onRequestUpgrade)

	task.spawn(function()
		while true do
			task.wait(TycoonConfig.PassiveIncomeIntervalSeconds)
			onPassiveIncomeTick()
		end
	end)
end

return TycoonService
