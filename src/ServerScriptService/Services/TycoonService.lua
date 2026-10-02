--!nonstrict
--[[
	TycoonService
	-------------
	Owns every player's plot: builds it from TycoonTemplate at their slot,
	runs the droppers, collector, stations (claim, Dropper 2, gacha,
	multiplier) and pedestals, pays passive income and handles generator
	upgrades.

	Every position, offset and size comes from PlotLayout (plot-local space:
	origin at the plot's centre, floor top y = 0, +Z toward the gate). This
	file must not hard-code geometry.

	Lifecycle: :Init() connects its own remotes/players and starts its loops.
	:Start() resolves FusionMachineService. PlayerDataService is a leaf
	(requires no services), so its module-scope require can't form a cycle.
]]
local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage.Shared.Config
local TycoonConfig = require(Config.TycoonConfig)
local PlotNaming = require(Config.PlotNaming)
local PlotLayout = require(Config.PlotLayout)
local FusionConfig = require(Config.FusionConfig)
local ItemConfig = require(Config.ItemConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local StationKit = require(ReplicatedStorage.Shared.Modules.StationKit)
local DropperKit = require(ReplicatedStorage.Shared.Modules.DropperKit)
local PlotKit = require(ReplicatedStorage.Shared.Modules.PlotKit)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)
local ImportedEffects = require(ReplicatedStorage.Shared.VFX.ImportedEffects)

local PlayerDataService = require(script.Parent.PlayerDataService)

type FusionMachineServiceModule = typeof(require(script.Parent.FusionMachineService))
-- Resolved in :Start().
local FusionMachineService: FusionMachineServiceModule

local TycoonService = {}
TycoonService.Name = "TycoonService"

local World = UITheme.World

-- Optional VFX extracted from the user's Toolbox packs (FindFirstChild so a
-- session without them degrades to the sparkle/sound feedback only).
local VFXFolder = ReplicatedStorage.Shared.VFX
local levelingUpEffectTemplate = VFXFolder:FindFirstChild("LevelingUpEffect") :: BasePart?
local explosionEffectTemplate = VFXFolder:FindFirstChild("ExplosionEffect") :: BasePart?

--[[ Tuning (not geometry) ---------------------------------------------------- ]]

local GACHA_RATE_TIERS_SHOWN = 3
local PLOT_SIGN_REFRESH_SECONDS = 5
local CASH_DROP_DEBRIS_LIFETIME_SECONDS = 30
local CASH_DROP_SPEED_STUDS_PER_SECOND = 6
local STATION_DEBOUNCE_SECONDS = 1
local BURST_COUNT = 30
local DROPPER_POP_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
local STATION_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
local GACHA_MAJOR_EXPLOSION_SCALE = 0.5
local GACHA_MAJOR_EXPLOSION_BURST_SECONDS = 0.25

-- Cash balls pass through characters ("Default") but still hit the plot
-- floor/collector (PlotEnvironment).
local CASH_COLLISION_GROUP = "CashParts"
local PLOT_ENVIRONMENT_COLLISION_GROUP = PlotKit.FLOOR_COLLISION_GROUP

local EXPECTED_TEMPLATE_PART_NAMES = { "Floor", "Dropper1", "ClaimButton", "PlotOrigin", "SpawnLocation" }

--[[ State --------------------------------------------------------------------- ]]

local occupiedSlots: { [number]: boolean } = {}
local slotByUserId: { [number]: number } = {}
local plotByUserId: { [number]: Model } = {}
local originByUserId: { [number]: CFrame } = {}
local plotSignByUserId: { [number]: BillboardKit.SignSurface } = {}

local function syncTycoon(player: Player)
	PlayerDataService.SyncTycoon(player)
end

--[[ Income + upgrades ----------------------------------------------------------- ]]

local function onPassiveIncomeTick()
	for _, player in Players:GetPlayers() do
		if PlayerDataService.IsDataLoaded(player) then
			-- Same formula the HUD's "+$X/s" uses.
			local cashPerSecond = PlayerDataService.GetPassiveCashPerSecond(player)
			if cashPerSecond > 0 then
				PlayerDataService.AddCash(player, cashPerSecond * TycoonConfig.PassiveIncomeIntervalSeconds)
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
	RemoteEvents.UpgradeResult:FireClient(player, { Success = true, GeneratorId = generatorId, NewLevel = newLevel })
	syncTycoon(player)
end

--[[ Helpers ------------------------------------------------------------------- ]]

local function setupCollisionGroups()
	-- pcall: "already exists" if this ever re-runs without a server restart.
	pcall(function()
		PhysicsService:RegisterCollisionGroup(CASH_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(PLOT_ENVIRONMENT_COLLISION_GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(CASH_COLLISION_GROUP, "Default", false)
end

local function getPlotsFolder(): Folder
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PlotNaming.PlotsFolderName
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function claimSlotIndex(): number?
	for index = 1, PlotLayout.MAX_PLOT_SLOTS do
		if not occupiedSlots[index] then
			occupiedSlots[index] = true
			return index
		end
	end
	return nil
end

-- Resolves the touching Player only for an actual character limb.
local function getTouchingPlayer(hit: BasePart): Player?
	local character = hit.Parent
	if not character or not character:FindFirstChildOfClass("Humanoid") then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function findPart(plot: Model, name: string): BasePart?
	local part = plot:FindFirstChild(name, true)
	return if part and part:IsA("BasePart") then part else nil
end

local function validatePlotClone(plot: Model, player: Player)
	local missing = {}
	for _, name in EXPECTED_TEMPLATE_PART_NAMES do
		if not plot:FindFirstChild(name, true) then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		warn((
			"TycoonService: %s's cloned plot is missing %s. TycoonTemplate was likely incomplete or mid-sync "
				.. "when it was cloned; plots are cloned once per session, so restart Play after fixing it."
		):format(player.Name, table.concat(missing, ", ")))
	end
end

local function playSound(parent: Instance, soundId: string, volume: number)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function burst(parent: Instance, color: Color3, count: number)
	local emitter = SparkleEmitter.Create({ Color = color })
	emitter.Enabled = false
	emitter.Parent = parent
	emitter:Emit(count)
	Debris:AddItem(emitter, 3)
end

local function newPrompt(parent: Instance, name: string, actionText: string, objectText: string, distance: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.MaxActivationDistance = distance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	-- Where ranges overlap, only the nearest E prompt shows.
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Parent = parent
	return prompt
end

--[[ Plot shell: floor, walkway, walls, gate ramp, spawn ---------------------------- ]]

local function buildShell(plot: Model, origin: CFrame, player: Player)
	local plotOrigin = findPart(plot, "PlotOrigin")
	if plotOrigin then
		plotOrigin.CFrame = origin
		plotOrigin.Transparency = 1
		plotOrigin.CanCollide = false
		plotOrigin.CanQuery = false
		plotOrigin.CanTouch = false
		plotOrigin.Anchored = true
		plot.PrimaryPart = plotOrigin
	end

	PlotKit.BuildFloor(origin, plot, findPart(plot, "Floor"))
	PlotKit.BuildWalkway(origin, plot)
	PlotKit.BuildWalls(origin, plot, false)
	PlotKit.BuildGateRamp(origin, plot)

	-- Spawn on the street in front of the gate; RespawnLocation picks it.
	local spawn = plot:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		spawn.Size = PlotLayout.SPAWN_SIZE
		spawn.CFrame = PartKit.At(origin, PlotLayout.SPAWN_POSITION, PlotLayout.STREET_TOP_Y + PlotLayout.SPAWN_SIZE.Y / 2)
		spawn.Transparency = 1
		spawn.Anchored = true
		for _, child in spawn:GetChildren() do
			if child:IsA("Decal") then
				child:Destroy()
			end
		end
		player.RespawnLocation = spawn
		local character = player.Character
		if character then
			character:PivotTo(spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + 3, 0))
		end
	else
		warn(("TycoonService: no SpawnLocation in %s's plot"):format(player.Name))
	end
end

--[[ Stations ---------------------------------------------------------------------- ]]

-- Builds a StationKit station named `name` and returns its Pad (which
-- holds the prompt and the label).
local function buildStation(
	plot: Model,
	origin: CFrame,
	name: string,
	localPos: Vector3,
	accent: Color3,
	hologram: StationKit.Hologram,
	options: StationKit.BuildOptions?
): BasePart
	local station = StationKit.Build(origin, localPos, accent, hologram, plot, options)
	station.Name = name
	return station:FindFirstChild("Pad") :: BasePart
end

--[[ Droppers + collector ------------------------------------------------------------- ]]

local function awardCash(player: Player, amount: number)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	PlayerDataService.AddCash(player, amount)
	syncTycoon(player)
end

local function spawnCashPart(plot: Model, origin: CFrame, dropper: Model, player: Player)
	local spawnAt = DropperKit.GetBallSpawn(dropper)
	if not spawnAt then
		return
	end
	local multiplier = TycoonConfig.GetCashMultiplierValue(PlayerDataService.GetCashMultiplierLevel(player))
	playSound(dropper.PrimaryPart or plot, DROPPER_POP_SOUND_ID, 0.35)

	local cashPart = PartKit.Part({
		Name = "CashDrop",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * PlotLayout.Dropper.BallDiameter,
		CFrame = spawnAt,
		Color = World.AccentGreen,
		Material = Enum.Material.Neon,
		Parent = plot,
	})
	cashPart.Anchored = false
	cashPart.CollisionGroup = CASH_COLLISION_GROUP
	cashPart:SetAttribute("CashValue", TycoonConfig.DropperCashValue * multiplier)
	-- Out of the spout toward the collector (plot +X).
	cashPart.AssemblyLinearVelocity = origin.RightVector * CASH_DROP_SPEED_STUDS_PER_SECOND
	Debris:AddItem(cashPart, CASH_DROP_DEBRIS_LIFETIME_SECONDS)
end

local function startDropperLoop(plot: Model, origin: CFrame, player: Player, dropper: Model)
	task.spawn(function()
		while plot.Parent and dropper.Parent do
			task.wait(TycoonConfig.DropperIntervalSeconds)
			if not plot.Parent or not dropper.Parent then
				break
			end
			spawnCashPart(plot, origin, dropper, player)
		end
	end)
end

-- One gold strip both droppers' balls roll onto.
local function createCollector(plot: Model, origin: CFrame, player: Player)
	local size = PlotLayout.COLLECTOR_SIZE
	local collector = PartKit.Part({
		Name = "Collector",
		Size = size,
		CFrame = PartKit.At(origin, PlotLayout.COLLECTOR, PlotLayout.COLLECTOR_TOP_Y - size.Y / 2),
		Color = World.AccentGold,
		Material = Enum.Material.Neon,
		Parent = plot,
	})
	collector.CollisionGroup = PLOT_ENVIRONMENT_COLLISION_GROUP

	collector.Touched:Connect(function(hit: BasePart)
		if hit.Parent == nil or hit:GetAttribute("Collected") then
			return
		end
		local value = hit:GetAttribute("CashValue")
		if not value then
			return
		end
		hit:SetAttribute("Collected", true)
		local popPosition = Vector3.new(hit.Position.X, collector.Position.Y + size.Y / 2 + 1, hit.Position.Z)
		hit:Destroy()
		awardCash(player, value)
		RemoteEvents.CashCollected:FireClient(player, { Amount = value, Position = popPosition })
	end)
end

local function spawnDropper2(plot: Model, origin: CFrame, player: Player)
	local dropper = DropperKit.Build(origin, PlotLayout.DROPPER2, "Dropper2", plot)
	startDropperLoop(plot, origin, player, dropper)
end

local function createDropper2Station(plot: Model, origin: CFrame, player: Player)
	-- The slot shows a translucent ghost of the dropper until it's bought.
	local ghost = DropperKit.Build(origin, PlotLayout.DROPPER2, "Ghost")
	local pad = buildStation(plot, origin, "Dropper2Station", PlotLayout.DROPPER2, World.AccentGreen, "Ghost", { Ghost = ghost })
	local cost = TycoonConfig.Dropper2Cost
	BillboardKit.Pad(pad, {
		Name = "Dropper2Label",
		Title = "DROPPER 2",
		TitleColor = UITheme.Colors.DropperTitle,
		Pill = NumberFormat.Money(cost),
		PillGradient = UITheme.Gradients.Green,
		Detail = "Doubles your drops",
		StudsOffset = Vector3.new(0, PlotLayout.Station.LabelOffsetY, 0),
	})
	local prompt = newPrompt(pad, "BuyPrompt", ("Buy (%s)"):format(NumberFormat.Money(cost)), "Dropper 2", PlotLayout.Station.PromptDistance)

	local purchased = false
	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		if purchased or triggeringPlayer.UserId ~= player.UserId then
			return
		end
		if not PlayerDataService.SpendCash(player, cost) then
			return
		end
		purchased = true
		PlayerDataService.SetHasDropper2(player, true)
		syncTycoon(player)
		local station = pad.Parent
		if station then
			station:Destroy()
		end
		spawnDropper2(plot, origin, player)
	end)
end

--[[ Gacha station ------------------------------------------------------------------ ]]

local gachaRng = Random.new()

-- "Common 78% · Rare 18% · Epic 3.5%", straight from FusionConfig.GachaRates.
local function formatPercent(rate: number): string
	local percent = rate * 100
	if math.abs(percent - math.floor(percent + 0.5)) < 1e-6 then
		return ("%d%%"):format(math.floor(percent + 0.5))
	end
	return (("%.1f"):format(percent):gsub("%.0$", "")) .. "%"
end

local function getGachaRatesText(): string
	local tiers = table.clone(FusionConfig.TierOrder)
	table.sort(tiers, function(a, b)
		return (FusionConfig.GachaRates[a] or 0) > (FusionConfig.GachaRates[b] or 0)
	end)
	local parts = {}
	for index = 1, math.min(GACHA_RATE_TIERS_SHOWN, #tiers) do
		local tier = tiers[index]
		table.insert(parts, ("%s %s"):format(tier, formatPercent(FusionConfig.GachaRates[tier] or 0)))
	end
	return table.concat(parts, " · ")
end

local function createGachaStation(plot: Model, origin: CFrame, player: Player)
	local pad = buildStation(plot, origin, "GachaStation", PlotLayout.GACHA_STATION, World.AccentGold, "Capsule")
	local padLabel = BillboardKit.Pad(pad, {
		Name = "GachaLabel",
		Title = "GACHA",
		TitleColor = UITheme.Colors.GoldLabel,
		Pill = "",
		PillGradient = UITheme.Gradients.Gold,
		PillTextColor = UITheme.Colors.GoldText,
		PillTextStroke = false,
		Detail = getGachaRatesText(),
		StudsOffset = Vector3.new(0, PlotLayout.Station.LabelOffsetY, 0),
	})
	-- E-to-pull, never Touched: walking across the pad must not spend cash.
	local prompt = newPrompt(pad, "PullPrompt", "Pull", "Gacha Pad", PlotLayout.Station.PromptDistance)

	local function refreshLabel()
		local cost = TycoonConfig.GetGachaPullCost(PlayerDataService.GetGachaPulls(player))
		padLabel.SetPill(("%s / pull"):format(NumberFormat.Money(cost)))
		prompt.ActionText = ("Pull (%s)"):format(NumberFormat.Money(cost))
	end
	refreshLabel()

	local debounce = false
	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		if debounce or triggeringPlayer.UserId ~= player.UserId then
			return
		end

		-- Roll first: a config gap can then never charge for nothing.
		local resultTier = FusionConfig.RollGachaTier(gachaRng)
		local rewardItem = ItemConfig.PickRandomOfTier(resultTier, gachaRng)
		if not rewardItem then
			warn(("TycoonService: no ItemConfig entry found for tier %s"):format(resultTier))
			RemoteEvents.GachaPullResult:FireClient(player, { Success = false, Reason = "MissingRewardItem" })
			return
		end

		local cost = TycoonConfig.GetGachaPullCost(PlayerDataService.GetGachaPulls(player))
		if not PlayerDataService.SpendCash(player, cost) then
			RemoteEvents.GachaPullResult:FireClient(player, { Success = false, Reason = "InsufficientCash", Cost = cost })
			return
		end

		debounce = true
		PlayerDataService.IncrementGachaPulls(player)
		syncTycoon(player)
		refreshLabel()

		local newEntry = PlayerDataService.AddItem(player, rewardItem.Id, rewardItem.Tier)
		RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))

		burst(pad, FusionConfig.TierAccentColors[resultTier] or World.AccentGold, BURST_COUNT)
		if explosionEffectTemplate and FusionConfig.MajorRevealTiers[resultTier] then
			ImportedEffects.Play(explosionEffectTemplate, pad.CFrame, plot, {
				Scale = GACHA_MAJOR_EXPLOSION_SCALE,
				BurstSeconds = GACHA_MAJOR_EXPLOSION_BURST_SECONDS,
			})
		end
		playSound(pad, STATION_SOUND_ID, 0.8)

		RemoteEvents.GachaPullResult:FireClient(player, { Success = true, NewItem = newEntry })

		task.wait(STATION_DEBOUNCE_SECONDS)
		debounce = false
	end)
end

--[[ Multiplier station --------------------------------------------------------------- ]]

local function createMultiplierStation(plot: Model, origin: CFrame, player: Player)
	local pad = buildStation(plot, origin, "MultiplierStation", PlotLayout.MULTIPLIER_STATION, World.AccentViolet, "Chevrons")
	local padLabel = BillboardKit.Pad(pad, {
		Name = "MultiplierLabel",
		Title = "MULTIPLIER",
		TitleColor = UITheme.Colors.VioletLight,
		Pill = "",
		PillGradient = UITheme.Gradients.Violet,
		StudsOffset = Vector3.new(0, PlotLayout.Station.LabelOffsetY, 0),
	})
	local prompt = newPrompt(pad, "UpgradePrompt", "Upgrade", "Cash Multiplier", PlotLayout.Station.PromptDistance)

	local function refreshLabel()
		local level = PlayerDataService.GetCashMultiplierLevel(player)
		local current = TycoonConfig.GetCashMultiplierValue(level)
		if level >= TycoonConfig.GetCashMultiplierMaxLevel() then
			padLabel.SetPill(("%s MAX"):format(NumberFormat.Multiplier(current)))
			padLabel.SetDetail(nil)
			prompt.Enabled = false
			return
		end
		local cost = TycoonConfig.GetCashMultiplierUpgradeCost(level) :: number
		local nextValue = TycoonConfig.GetCashMultiplierValue(level + 1)
		padLabel.SetPill(("%s → %s"):format(NumberFormat.Multiplier(current), NumberFormat.Multiplier(nextValue)))
		padLabel.SetDetail(("%s · press E"):format(NumberFormat.Money(cost)))
	end
	refreshLabel()

	local debounce = false
	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		if debounce or triggeringPlayer.UserId ~= player.UserId then
			return
		end
		local level = PlayerDataService.GetCashMultiplierLevel(player)
		if level >= TycoonConfig.GetCashMultiplierMaxLevel() then
			return
		end
		local cost = TycoonConfig.GetCashMultiplierUpgradeCost(level) :: number
		if not PlayerDataService.SpendCash(player, cost) then
			return
		end

		debounce = true
		local oldMultiplier = TycoonConfig.GetCashMultiplierValue(level)
		local newMultiplier = TycoonConfig.GetCashMultiplierValue(level + 1)
		PlayerDataService.SetCashMultiplierLevel(player, level + 1)
		syncTycoon(player)
		refreshLabel()
		-- Pedestal labels show income with the multiplier applied.
		TycoonService.RefreshPedestalLabels(player)

		burst(pad, World.AccentViolet, BURST_COUNT)
		if levelingUpEffectTemplate then
			ImportedEffects.Play(levelingUpEffectTemplate, pad.CFrame, plot)
		end
		playSound(pad, STATION_SOUND_ID, 0.8)

		RemoteEvents.MultiplierUpgraded:FireClient(player, { OldMultiplier = oldMultiplier, NewMultiplier = newMultiplier })

		task.wait(STATION_DEBOUNCE_SECONDS)
		debounce = false
	end)
end

--[[ Pedestals ------------------------------------------------------------------------ ]]

-- "Pedestal1".."PedestalN" inside a "Pedestals" folder, so ItemService can
-- look one up by index. PedestalVisuals styles them once an item is placed.
local function createPedestals(plot: Model, origin: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "Pedestals"
	folder.Parent = plot

	local p = PlotLayout.Pedestal
	for index = 1, PlotLayout.PEDESTAL_COUNT do
		local pedestal = PartKit.Part({
			Name = "Pedestal" .. index,
			Size = p.ColumnSize,
			CFrame = PartKit.At(origin, PlotLayout.GetPedestalPosition(index), p.ColumnSize.Y / 2),
			Color = World.Structure,
			Parent = folder,
		})
		pedestal:SetAttribute("BaseSize", pedestal.Size)
		pedestal:SetAttribute("PedestalIndex", index)

		-- Plate on top: StructureLight while empty, tier Neon when filled
		-- (PedestalVisuals).
		PartKit.Part({
			Name = "Cap",
			Size = p.CapSize,
			CFrame = pedestal.CFrame * CFrame.new(0, p.ColumnSize.Y / 2 + p.CapSize.Y / 2, 0),
			Color = World.StructureLight,
			Parent = pedestal,
		})

		local prompt = newPrompt(pedestal, "DisplayPrompt", "Display", ("Pedestal %d"):format(index), p.PromptDistance)
		-- Enabled by the owner's client once they have something to display.
		prompt.Enabled = false

		BillboardKit.SetPedestalLabel(pedestal, nil)
	end
end

-- Re-applies saved displays when a returning player claims their plot.
local function restoreSavedPedestals(plot: Model, player: Player)
	local folder = plot:FindFirstChild("Pedestals")
	if not folder then
		return
	end
	for pedestalIndex, uid in PlayerDataService.GetPedestalDisplays(player) do
		local pedestal = folder:FindFirstChild("Pedestal" .. pedestalIndex)
		local item = uid and PlayerDataService.GetItemByUid(player, uid)
		if pedestal and pedestal:IsA("BasePart") and item then
			PedestalVisuals.Apply(pedestal, item.Tier)
		elseif uid and not item then
			-- Points at an item that no longer exists; free the slot.
			PlayerDataService.SetPedestalDisplay(player, pedestalIndex, nil)
		end
	end
end

--[[ Public ---------------------------------------------------------------------------- ]]

-- `player`'s plot Model, or nil. Lets ItemService resolve pedestals without
-- trusting a client-supplied plot.
function TycoonService.GetPlotForPlayer(player: Player): Model?
	return plotByUserId[player.UserId]
end

-- Re-labels every pedestal on `player`'s plot: the filled label where
-- something is displayed, the owner-only EMPTY label elsewhere. ItemService
-- calls this on place/remove; this service after restoring on claim and after
-- a multiplier purchase. Lives here so the two services don't reference each
-- other.
function TycoonService.RefreshPedestalLabels(player: Player)
	local plot = plotByUserId[player.UserId]
	local folder = plot and plot:FindFirstChild("Pedestals")
	if not folder then
		return
	end
	local displays = PlayerDataService.GetPedestalDisplays(player)
	local multiplier = TycoonConfig.GetCashMultiplierValue(PlayerDataService.GetCashMultiplierLevel(player))
	for index = 1, PlotLayout.PEDESTAL_COUNT do
		local pedestal = folder:FindFirstChild("Pedestal" .. index)
		if pedestal and pedestal:IsA("BasePart") then
			local uid = displays[index]
			local item = uid and PlayerDataService.GetItemByUid(player, uid)
			if item then
				local def = ItemConfig.GetItemById(item.ItemId)
				BillboardKit.SetPedestalLabel(pedestal, {
					Tier = item.Tier,
					ItemName = def and def.Name or item.ItemId,
					Rate = TycoonConfig.GetPedestalCashPerSecond(item.Tier) * multiplier,
				})
			else
				BillboardKit.SetPedestalLabel(pedestal, nil)
			end
		end
	end
end

--[[ Plot sign ------------------------------------------------------------------------ ]]

local function getBestTier(player: Player): string?
	local inventory = PlayerDataService.GetInventory(player)
	if not inventory then
		return nil
	end
	local best: string? = nil
	local bestRank = 0
	for _, item in inventory do
		local rank = ItemConfig.Tiers[item.Tier] or 0
		if rank > bestRank then
			bestRank = rank
			best = item.Tier
		end
	end
	return best
end

local function refreshPlotSigns()
	for userId, sign in plotSignByUserId do
		local player = Players:GetPlayerByUserId(userId)
		local plot = plotByUserId[userId]
		if player and plot then
			if plot:GetAttribute("Claimed") ~= true or not PlayerDataService.IsDataLoaded(player) then
				sign.Set("FREE LAB", "Step on the green pad")
			else
				local droppers = if PlayerDataService.HasDropper2(player) then 2 else 1
				local income = PlayerDataService.GetPassiveCashPerSecond(player)
					+ TycoonConfig.GetDropperCashPerSecond(droppers, PlayerDataService.GetCashMultiplierLevel(player))
				sign.Set(
					("%s'S LAB"):format(player.DisplayName:upper()),
					("%s/s · best: %s"):format(NumberFormat.Money(income), getBestTier(player) or "none")
				)
			end
		end
	end
end

--[[ Claim ------------------------------------------------------------------------------ ]]

local function connectClaimStation(plot: Model, origin: CFrame, player: Player)
	local claimButton = findPart(plot, "ClaimButton")
	if not claimButton then
		warn(("TycoonService: ClaimButton missing in %s's plot"):format(player.Name))
		return
	end
	-- ClaimButton becomes the claim station's Pad.
	local pad = buildStation(plot, origin, "ClaimStation", PlotLayout.CLAIM_STATION, World.AccentGreen, "Arrow", { Pad = claimButton })
	pad.CanTouch = true

	-- Owner-only: other players' clients disable it (WorldLabelController).
	local claimLabel = BillboardKit.Pad(pad, {
		Name = "ClaimLabel",
		Title = "CLAIM",
		TitleColor = UITheme.Colors.Text,
		Pill = "STEP HERE",
		PillGradient = UITheme.Gradients.Green,
		Detail = ("This base is yours, %s"):format(player.DisplayName),
		StudsOffset = Vector3.new(0, PlotLayout.Station.LabelOffsetY, 0),
		OwnerOnly = true,
	})

	local connection: RBXScriptConnection
	connection = pad.Touched:Connect(function(hit: BasePart)
		local toucher = getTouchingPlayer(hit)
		if not toucher or toucher.UserId ~= player.UserId or plot:GetAttribute("Claimed") then
			return
		end
		plot:SetAttribute("Claimed", true)
		connection:Disconnect()
		claimLabel.Gui:Destroy()
		PlotKit.SetWallStripsClaimed(plot, true)
		-- The station stays as a plain green pad; only the arrow goes.
		local station = pad.Parent
		local arrow = station and station:FindFirstChild("Hologram")
		if arrow then
			arrow:Destroy()
		end

		-- Saved state (Dropper 2, pedestals) is restored below.
		while not PlayerDataService.IsDataLoaded(player) and player.Parent do
			task.wait(0.25)
		end
		if not player.Parent or not plot.Parent then
			return
		end

		local dropper1 = plot:FindFirstChild("Dropper1")
		if not dropper1 or not dropper1:IsA("Model") then
			warn(("TycoonService: Dropper1 missing in %s's plot"):format(player.Name))
			return
		end

		createCollector(plot, origin, player)
		startDropperLoop(plot, origin, player, dropper1)
		if PlayerDataService.HasDropper2(player) then
			spawnDropper2(plot, origin, player)
		else
			createDropper2Station(plot, origin, player)
		end
		createMultiplierStation(plot, origin, player)
		createGachaStation(plot, origin, player)
		createPedestals(plot, origin)
		restoreSavedPedestals(plot, player)
		TycoonService.RefreshPedestalLabels(player)
		syncTycoon(player)
		refreshPlotSigns()
	end)
end

--[[ Plot lifecycle ----------------------------------------------------------------------- ]]

local function createPlotForPlayer(player: Player)
	if plotByUserId[player.UserId] then
		return
	end

	local template = ReplicatedStorage:FindFirstChild("TycoonTemplate")
	if not template or not template:IsA("Model") then
		warn("TycoonService: ReplicatedStorage.TycoonTemplate (a Model) not found; skipping plot for " .. player.Name)
		return
	end

	local slotIndex = claimSlotIndex()
	if not slotIndex then
		warn(("TycoonService: no free plot slot for %s (all %d taken)"):format(player.Name, PlotLayout.MAX_PLOT_SLOTS))
		return
	end
	slotByUserId[player.UserId] = slotIndex
	local origin = PlotLayout.GetSlotCFrame(slotIndex)
	originByUserId[player.UserId] = origin

	local plot = template:Clone()
	plot.Name = PlotNaming.GetPlotName(player.UserId)
	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("Claimed", false)
	plot:SetAttribute("SlotIndex", slotIndex)
	validatePlotClone(plot, player)

	buildShell(plot, origin, player)
	plotSignByUserId[player.UserId] = PlotKit.BuildSignGate(origin, plot)

	-- Dropper 1 stands at its spot from the start (the template part becomes
	-- its Body); it produces once claimed.
	local dropper1Body = findPart(plot, "Dropper1")
	if dropper1Body then
		DropperKit.Build(origin, PlotLayout.DROPPER1, "Dropper1", plot, dropper1Body)
	end

	plot.Parent = getPlotsFolder()
	FusionMachineService.Build(origin, PlotLayout.FUSION_MACHINE, plot)

	plotByUserId[player.UserId] = plot
	connectClaimStation(plot, origin, player)
	refreshPlotSigns()
end

local function removePlotForPlayer(player: Player)
	local plot = plotByUserId[player.UserId]
	if plot then
		plot:Destroy()
		plotByUserId[player.UserId] = nil
	end
	originByUserId[player.UserId] = nil
	plotSignByUserId[player.UserId] = nil
	local slotIndex = slotByUserId[player.UserId]
	if slotIndex then
		occupiedSlots[slotIndex] = nil
		slotByUserId[player.UserId] = nil
	end
end

function TycoonService:Init()
	setupCollisionGroups()

	RemoteEvents.RequestUpgrade.OnServerEvent:Connect(onRequestUpgrade)

	Players.PlayerAdded:Connect(createPlotForPlayer)
	Players.PlayerRemoving:Connect(removePlotForPlayer)
	-- Deferred, not spawned: plot creation needs FusionMachineService, which
	-- is only resolved in :Start(). Deferred threads run after Init+Start.
	for _, player in Players:GetPlayers() do
		task.defer(createPlotForPlayer, player)
	end

	task.spawn(function()
		while true do
			task.wait(TycoonConfig.PassiveIncomeIntervalSeconds)
			onPassiveIncomeTick()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(PLOT_SIGN_REFRESH_SECONDS)
			refreshPlotSigns()
		end
	end)
end

function TycoonService:Start()
	FusionMachineService = require(script.Parent.FusionMachineService)
end

return TycoonService
