--!nonstrict
--[[
	TycoonService
	-------------
	Owns every player's plot: builds it from TycoonTemplate at their slot,
	runs the stations (claim, gacha, multiplier), pedestals and the factory
	line (generators, belt, collector), pays passive income and handles
	generator upgrades.

	Every position, offset and size comes from PlotLayout (plot-local space:
	origin at the plot's centre, floor top y = 0, +Z toward the gate). This
	file must not hard-code geometry.

	Lifecycle: :Init() connects its own remotes/players and starts its loops.
	:Start() resolves FusionMachineService and WorldService and registers the
	factory-line OnSync hook. PlayerDataService is a leaf
	(requires no services), so its module-scope require can't form a cycle.
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage.Shared.Config
local TycoonConfig = require(Config.TycoonConfig)
local PlotNaming = require(Config.PlotNaming)
local PlotLayout = require(Config.PlotLayout)
local StreetLayout = require(Config.StreetLayout)
local FusionConfig = require(Config.FusionConfig)
local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local LockKit = require(ReplicatedStorage.Shared.Modules.LockKit)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local RebirthConfig = require(Config.RebirthConfig)
local MutationConfig = require(Config.MutationConfig)
local IndexConfig = require(Config.IndexConfig)
local ItemConfig = require(Config.ItemConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local StationKit = require(ReplicatedStorage.Shared.Modules.StationKit)
local PlotKit = require(ReplicatedStorage.Shared.Modules.PlotKit)
local GeneratorKit = require(ReplicatedStorage.Shared.Modules.GeneratorKit)
local FactoryKit = require(ReplicatedStorage.Shared.Modules.FactoryKit)
local PortalKit = require(ReplicatedStorage.Shared.Modules.PortalKit)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)
local ImportedEffects = require(ReplicatedStorage.Shared.VFX.ImportedEffects)

local PlayerDataService = require(script.Parent.PlayerDataService)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)

type FusionMachineServiceModule = typeof(require(script.Parent.FusionMachineService))
type WorldServiceModule = typeof(require(script.Parent.WorldService))
-- Resolved in :Start().
local FusionMachineService: FusionMachineServiceModule
local WorldService: WorldServiceModule

type PulledItem = { Def: ItemConfig.ItemDef, Mutation: string? }

-- Run after every successful pull (FusionService: Auto-Fuse). A plain list
-- so FusionService can subscribe without this service referencing it.
local pullHooks: { (Player) -> () } = {}

local function runPullHooks(player: Player)
	for _, hook in pullHooks do
		task.spawn(hook, player)
	end
end

-- Each claimed plot's free-pull handler (RewardService's daily / gift
-- pulls and items go through the plot's real pull path: VFX, Index,
-- banners, the reveal card).
type RewardPuller = (pulls: { PulledItem }, caption: string) -> boolean
local rewardPullersByUserId: { [number]: RewardPuller } = {}

local TycoonService = {}
TycoonService.Name = "TycoonService"

local World = UITheme.World

-- Optional VFX extracted from the user's Toolbox packs (FindFirstChild so a
-- session without them degrades to the sparkle/sound feedback only).
local VFXFolder = ReplicatedStorage.Shared.VFX
local levelingUpEffectTemplate = VFXFolder:FindFirstChild("LevelingUpEffect") :: BasePart?
local explosionEffectTemplate = VFXFolder:FindFirstChild("ExplosionEffect") :: BasePart?

--[[ Tuning (not geometry) ---------------------------------------------------- ]]

local MULTI_PULL_COUNT = 10
local PLOT_SIGN_REFRESH_SECONDS = 5
local STATION_DEBOUNCE_SECONDS = 1
local BURST_COUNT = 30
local GACHA_MAJOR_EXPLOSION_SCALE = 0.5
local GACHA_MAJOR_EXPLOSION_BURST_SECONDS = 0.25

-- The TycoonTemplate parts the plot is built from. Anything else in the
-- template (e.g. the retired dropper part still saved in the .rbxm) is
-- stripped from each clone.
local EXPECTED_TEMPLATE_PART_NAMES = { "Floor", "ClaimButton", "PlotOrigin", "SpawnLocation" }

--[[ State --------------------------------------------------------------------- ]]

local occupiedSlots: { [number]: boolean } = {}
local slotByUserId: { [number]: number } = {}
local plotByUserId: { [number]: Model } = {}
local originByUserId: { [number]: CFrame } = {}
local plotSignByUserId: { [number]: BillboardKit.SignSurface } = {}
local collectorLabelByUserId: { [number]: BillboardKit.PadLabel } = {}
type PortalState = { Model: Model, Label: BillboardKit.ProgressPadLabel }
local portalByUserId: { [number]: PortalState } = {}

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
				local earned = cashPerSecond * TycoonConfig.PassiveIncomeIntervalSeconds
				PlayerDataService.AddCash(player, earned)
				AnalyticsKit.AddIncome(player, earned)
				syncTycoon(player)
			end
		end
	end
end

-- Buys ONE level of `generatorId` (validation, cost, unlocks, cap). The
-- single source of an upgrade purchase: RequestUpgrade calls it once,
-- RequestUpgradeMax in a loop. No result event, no sync. Returns (true,
-- nil, newLevel), or (false, reason, the unaffordable cost if it was cash).
local function buyOneLevel(player: Player, generatorId: string): (boolean, string?, number?)
	local generator = TycoonConfig.GetGeneratorById(generatorId)
	if not generator then
		return false, "InvalidGenerator"
	end
	local generatorLevels = PlayerDataService.GetGenerators(player) or {}
	if not TycoonConfig.IsUnlocked(generator, generatorLevels) then
		return false, "Locked"
	end
	local currentLevel = generatorLevels[generatorId] or 0
	if currentLevel >= generator.MaxLevel then
		return false, "MaxLevel"
	end
	local cost = TycoonConfig.GetUpgradeCost(generator, currentLevel)
	if not PlayerDataService.SpendCash(player, cost) then
		return false, "InsufficientCash", cost
	end
	local newLevel = currentLevel + 1
	PlayerDataService.SetGeneratorLevel(player, generatorId, newLevel)
	return true, nil, newLevel
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
	-- Hands full: no upgrades while carrying a stolen item (HeistService).
	if PlayerDataService.IsCarrying(player) then
		RemoteEvents.UpgradeResult:FireClient(player, { Success = false, Reason = "Carrying", GeneratorId = generatorId })
		return
	end

	local ok, reason, newLevel = buyOneLevel(player, generatorId)
	if not ok then
		RemoteEvents.UpgradeResult:FireClient(player, { Success = false, Reason = reason, GeneratorId = generatorId })
		return
	end
	RemoteEvents.UpgradeResult:FireClient(player, { Success = true, GeneratorId = generatorId, NewLevel = newLevel })
	local upgraded = TycoonConfig.GetGeneratorById(generatorId)
	if upgraded and newLevel then
		AnalyticsKit.Sink(player, TycoonConfig.GetUpgradeCost(upgraded, newLevel - 1), Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Upgrade")
	end
	AnalyticsKit.Funnel(player, "FirstUpgrade")
	syncTycoon(player)
end

-- MAX ×N / MAX ALL: { GeneratorId } buys that generator's levels while cash
-- lasts; { All = true } buys the cheapest available level across every
-- unlocked generator, one at a time (TycoonConfig.GetCheapestUpgrade, the
-- same pick GetMaxAllPlan shows). Each level goes through buyOneLevel; one
-- sync and one UpgradeMaxResult at the end. Zero levels bought = nothing
-- spent.
local function onRequestUpgradeMax(player: Player, rawRequest: unknown)
	local request = if typeof(rawRequest) == "table" then rawRequest :: { [any]: any } else {}
	local all = request.All == true
	local singleId = if not all and typeof(request.GeneratorId) == "string" then request.GeneratorId :: string else nil
	local function reject(reason: string, nextCost: number?)
		RemoteEvents.UpgradeMaxResult:FireClient(player, {
			Success = false,
			Reason = reason,
			All = all,
			GeneratorId = singleId,
			NextCost = nextCost,
		})
	end
	if not all and not (singleId and TycoonConfig.GetGeneratorById(singleId)) then
		reject("InvalidGenerator")
		return
	end
	if not PlayerDataService.IsDataLoaded(player) then
		reject("DataNotLoaded")
		return
	end
	if PlayerDataService.IsCarrying(player) then
		reject("Carrying")
		return
	end

	local levels, spent = 0, 0
	local perGenerator: { [string]: number } = {}
	local newLevels: { [string]: number } = {}
	local stopReason: string? = nil
	local nextCost: number? = nil
	for _ = 1, TycoonConfig.MaxUpgradeSteps do
		local generatorId = singleId
		local cost = 0
		if all then
			local generator, cheapest = TycoonConfig.GetCheapestUpgrade(PlayerDataService.GetGenerators(player) or {})
			if not generator then
				stopReason = "MaxLevel"
				break
			end
			generatorId, cost = generator.Id, cheapest
		else
			local generator = TycoonConfig.GetGeneratorById(singleId :: string) :: TycoonConfig.GeneratorDef
			cost = TycoonConfig.GetUpgradeCost(generator, PlayerDataService.GetGeneratorLevel(player, generator.Id))
		end
		local id = generatorId :: string
		local ok, reason, newLevel = buyOneLevel(player, id)
		if not ok then
			stopReason = reason
			nextCost = if reason == "InsufficientCash" then newLevel else nil
			break
		end
		levels += 1
		spent += cost
		perGenerator[id] = (perGenerator[id] or 0) + 1
		newLevels[id] = newLevel :: number
	end

	if levels == 0 then
		reject(stopReason or "InsufficientCash", nextCost)
		return
	end
	RemoteEvents.UpgradeMaxResult:FireClient(player, {
		Success = true,
		All = all,
		GeneratorId = singleId,
		Levels = levels,
		Spent = spent,
		PerGenerator = perGenerator,
		NewLevels = newLevels,
	})
	-- One sink for the whole MAX (never one event per level).
	AnalyticsKit.Sink(player, spent, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "UpgradeMax")
	AnalyticsKit.Funnel(player, "FirstUpgrade")
	syncTycoon(player)
end

--[[ Helpers ------------------------------------------------------------------- ]]

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

-- Removes template children the plot is no longer built from.
local function stripTemplateLeftovers(plot: Model)
	for _, child in plot:GetChildren() do
		if not table.find(EXPECTED_TEMPLATE_PART_NAMES, child.Name) then
			child:Destroy()
		end
	end
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

local function playSound(parent: Instance)
	SoundKit.Play("Station", parent)
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
	PlotKit.BuildShieldFence(origin, plot)

	-- Spawn on the street in front of the gate; RespawnLocation picks it.
	local spawn = plot:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		spawn.Size = PlotLayout.SPAWN_SIZE
		spawn.CFrame = PartKit.At(origin, PlotLayout.SPAWN_POSITION, StreetLayout.STREET_TOP_Y + PlotLayout.SPAWN_SIZE.Y / 2)
		spawn.Transparency = 1
		-- Non-solid: its edge reaches the speed belt's outer edge, and an
		-- invisible solid block there would snag riders.
		spawn.CanCollide = false
		spawn.Anchored = true
		for _, child in spawn:GetChildren() do
			if child:IsA("Decal") then
				child:Destroy()
			end
		end
		player.RespawnLocation = spawn
		local character = player.Character
		if character then
			character:PivotTo(spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + PlotLayout.SPAWN_CHARACTER_CLEARANCE, 0))
		end
	else
		warn(("TycoonService: no SpawnLocation in %s's plot"):format(player.Name))
	end
end

--[[ Station label refreshes --------------------------------------------------------
	Each station registers its label refresh here; the OnSync hook runs them
	all, so anything that changes a player's numbers (an upgrade, a rebirth)
	shows on the pads without each caller knowing which labels exist.
]]
local stationRefreshesByUserId: { [number]: { () -> () } } = {}

local function addStationRefresh(player: Player, refresh: () -> ())
	local list = stationRefreshesByUserId[player.UserId]
	if not list then
		list = {}
		stationRefreshesByUserId[player.UserId] = list
	end
	table.insert(list, refresh)
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

--[[ Gacha station ------------------------------------------------------------------ ]]

local gachaRng = Random.new()

-- The one luck number (PlayerDataService.GetLuck: rebirth x admin luck x
-- the shop's Lucky pass / Luck Potion), for the rolls and the odds label.
local function getLuck(player: Player): number
	return PlayerDataService.GetLuck(player)
end

-- The pad's odds disclosure at the player's luck (FusionConfig.FormatOdds,
-- the same numbers the rolls use): all six tiers, then the pull mutations.
local function getOddsText(luck: number): string
	local odds = FusionConfig.FormatOdds(luck, EventState.GetOddsEvent())
	return odds.Gacha .. "\n" .. odds.PullMutations
end

-- A Secret or a Rainbow pull is a server-wide moment (SERVER · SECRET /
-- SERVER · RAINBOW banners on every client).
local function announcePull(player: Player, item: PlayerDataService.InventoryItem?)
	if not item or (item.Tier ~= "Secret" and item.Mutation ~= "Rainbow") then
		return
	end
	local def = ItemConfig.GetItemById(item.ItemId)
	local itemName = if def then def.Name else item.ItemId
	RemoteEvents.RareFusionAnnouncement:FireAllClients({
		Message = ("%s pulled a %s!"):format(player.DisplayName, MutationConfig.GetDisplayName(itemName, item.Mutation)),
		Tier = item.Tier,
		Mutation = item.Mutation,
		PlayerName = player.DisplayName,
		Verb = "pulled",
		ItemName = itemName,
	})
end

-- Rolls `count` pulls (tier, then mutation, then item) at `luck` WITHOUT
-- touching cash or the inventory, so a config gap can never charge for
-- nothing. nil if any roll has no item to give.
local function rollPulls(count: number, luck: number): { PulledItem }?
	local pulls: { PulledItem } = {}
	-- The live event's mutation odds (Golden Rain, Rainbow Storm).
	local pullMultipliers = EventState.GetMutationMultipliers("Pull")
	for _ = 1, count do
		local tier = FusionConfig.RollGachaTier(gachaRng, luck)
		local mutation = MutationConfig.Roll(gachaRng, luck, "Pull", pullMultipliers)
		local def = ItemConfig.PickRandomOfTier(tier, gachaRng)
		if not def then
			warn(("TycoonService: no ItemConfig entry found for tier %s"):format(tier))
			return nil
		end
		table.insert(pulls, { Def = def, Mutation = mutation })
	end
	return pulls
end

-- Adds already-paid-for pulls: each item, its Index entry and the pull
-- count (`free` rewards don't count, so they never raise the pad price).
-- Returns (items, newIndexItems, tiersCompleted).
local function grantPulls(
	player: Player,
	pulls: { PulledItem },
	free: boolean?
): ({ PlayerDataService.InventoryItem }, { PlayerDataService.InventoryItem }, { string })
	local items, newIndexItems, tiersCompleted = {}, {}, {}
	for _, pull in pulls do
		if not free then
			PlayerDataService.IncrementGachaPulls(player)
		end
		local entry, isNew = PlayerDataService.AddItem(player, pull.Def.Id, pull.Def.Tier, pull.Mutation)
		if entry then
			table.insert(items, entry)
			if isNew then
				table.insert(newIndexItems, entry)
				if
					IndexConfig.IsTierComplete(PlayerDataService.GetIndex(player), entry.Tier)
					and not table.find(tiersCompleted, entry.Tier)
				then
					table.insert(tiersCompleted, entry.Tier)
				end
			end
		end
	end
	return items, newIndexItems, tiersCompleted
end

local function bestTier(items: { PlayerDataService.InventoryItem }): string
	local best = FusionConfig.TierOrder[1]
	for _, item in items do
		if (ItemConfig.Tiers[item.Tier] or 0) > (ItemConfig.Tiers[best] or 0) then
			best = item.Tier
		end
	end
	return best
end

local function createGachaStation(plot: Model, origin: CFrame, player: Player)
	local pad = buildStation(plot, origin, "GachaStation", PlotLayout.GACHA_STATION, World.AccentGold, "Capsule", { Word = "PULL" })
	local padLabel = BillboardKit.Pad(pad, {
		Name = "GachaLabel",
		Title = "GACHA",
		TitleColor = UITheme.Colors.GoldLabel,
		Pill = "",
		PillGradient = UITheme.Gradients.Gold,
		PillTextColor = UITheme.Colors.GoldText,
		PillTextStroke = false,
		Detail = getOddsText(getLuck(player)),
		StudsOffset = Vector3.new(0, PlotLayout.Station.LabelOffsetY, 0),
		TallDetail = true,
	})
	-- E-to-pull, never Touched: walking across the pad must not spend cash.
	local prompt = newPrompt(pad, "PullPrompt", "Pull", "Gacha Pad", PlotLayout.Station.PromptDistance)
	-- R / ButtonY: ten pulls at once, offset so it doesn't cover the E prompt.
	local multiPrompt = newPrompt(pad, "Pull10Prompt", ("Pull ×%d"):format(MULTI_PULL_COUNT), "", PlotLayout.Station.PromptDistance)
	multiPrompt.KeyboardKeyCode = Enum.KeyCode.R
	multiPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	multiPrompt.UIOffset = Vector2.new(0, PlotLayout.Station.MultiPromptOffsetPx)
	-- AlwaysShow: it must show whenever Pull does. Under OnePerButton it was
	-- grouped with the E prompts (touch has one "button" for every prompt),
	-- so the nearer Pull could hide it. Nothing disables it: an unaffordable
	-- x10 still shows and the server answers "Need $X for 10 pulls".
	multiPrompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow

	-- Runs on every sync too (addStationRefresh): price, odds at the
	-- player's luck (so a rebirth updates them), and the x10 cost.
	local function refreshLabel()
		local pulls = PlayerDataService.GetGachaPulls(player)
		local cost = TycoonConfig.GetGachaPullCost(pulls)
		padLabel.SetPill(("%s / pull"):format(NumberFormat.Money(cost)))
		padLabel.SetDetail(getOddsText(getLuck(player)))
		prompt.ActionText = ("Pull (%s)"):format(NumberFormat.Money(cost))
		multiPrompt.ObjectText = NumberFormat.Money(TycoonConfig.GetGachaMultiPullCost(pulls, MULTI_PULL_COUNT))
	end
	refreshLabel()
	addStationRefresh(player, refreshLabel)

	local function celebrate(tier: string)
		burst(pad, FusionConfig.TierAccentColors[tier] or World.AccentGold, BURST_COUNT)
		if explosionEffectTemplate and FusionConfig.MajorRevealTiers[tier] then
			ImportedEffects.Play(explosionEffectTemplate, pad.CFrame, plot, {
				Scale = GACHA_MAJOR_EXPLOSION_SCALE,
				BurstSeconds = GACHA_MAJOR_EXPLOSION_BURST_SECONDS,
			})
		end
		playSound(pad)
	end

	-- Shared by the single pull and Pull x10.
	local debounce = false

	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		if debounce or triggeringPlayer.UserId ~= player.UserId then
			return
		end
		if PlayerDataService.IsCarrying(player) then
			RemoteEvents.GachaPullResult:FireClient(player, { Success = false, Reason = "Carrying" })
			return
		end
		local rolled = rollPulls(1, getLuck(player))
		if not rolled then
			RemoteEvents.GachaPullResult:FireClient(player, { Success = false, Reason = "MissingRewardItem" })
			return
		end
		local cost = TycoonConfig.GetGachaPullCost(PlayerDataService.GetGachaPulls(player))
		if not PlayerDataService.SpendCash(player, cost) then
			RemoteEvents.GachaPullResult:FireClient(player, { Success = false, Reason = "InsufficientCash", Cost = cost })
			return
		end

		debounce = true
		AnalyticsKit.Sink(player, cost, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Pull")
		AnalyticsKit.Funnel(player, "FirstPull")
		local items, newIndexItems, tiersCompleted = grantPulls(player, rolled)
		local newEntry = items[1]
		-- After AddItem, so the snapshot's Index (and income) include it.
		syncTycoon(player)
		refreshLabel()
		RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
		celebrate(rolled[1].Def.Tier)
		RemoteEvents.GachaPullResult:FireClient(player, {
			Success = true,
			NewItem = newEntry,
			NewIndex = #newIndexItems > 0,
			IndexTierComplete = tiersCompleted[1],
		})
		announcePull(player, newEntry)
		runPullHooks(player)

		task.wait(STATION_DEBOUNCE_SECONDS)
		debounce = false
	end)

	-- Free pulls / reward items (RewardService): the same result path as a
	-- paid pull, with the reward's caption on the card.
	rewardPullersByUserId[player.UserId] = function(pulls: { PulledItem }, caption: string): boolean
		if not pad.Parent then
			return false
		end
		local items, newIndexItems, tiersCompleted = grantPulls(player, pulls, true)
		if #items == 0 then
			return false
		end
		syncTycoon(player)
		refreshLabel()
		RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
		celebrate(bestTier(items))
		if #items == 1 then
			RemoteEvents.GachaPullResult:FireClient(player, {
				Success = true,
				NewItem = items[1],
				NewIndex = #newIndexItems > 0,
				IndexTierComplete = tiersCompleted[1],
				Caption = caption,
				Reward = true, -- revealed once the daily card / Gifts panel close
			})
		else
			RemoteEvents.GachaMultiPullResult:FireClient(player, {
				Success = true,
				Items = items,
				NewIndexItems = newIndexItems,
				IndexTiersCompleted = tiersCompleted,
				Title = caption,
				Reward = true,
			})
		end
		for _, item in items do
			announcePull(player, item)
		end
		runPullHooks(player)
		return true
	end

	multiPrompt.Triggered:Connect(function(triggeringPlayer: Player)
		if debounce or triggeringPlayer.UserId ~= player.UserId then
			return
		end
		if PlayerDataService.IsCarrying(player) then
			RemoteEvents.GachaMultiPullResult:FireClient(player, { Success = false, Reason = "Carrying" })
			return
		end
		-- Roll all of them before charging anything.
		local rolled = rollPulls(MULTI_PULL_COUNT, getLuck(player))
		if not rolled then
			RemoteEvents.GachaMultiPullResult:FireClient(player, { Success = false, Reason = "MissingRewardItem" })
			return
		end
		local cost = TycoonConfig.GetGachaMultiPullCost(PlayerDataService.GetGachaPulls(player), MULTI_PULL_COUNT)
		if not PlayerDataService.SpendCash(player, cost) then
			RemoteEvents.GachaMultiPullResult:FireClient(player, { Success = false, Reason = "InsufficientCash", Cost = cost })
			return
		end

		debounce = true
		AnalyticsKit.Sink(player, cost, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Pull10")
		AnalyticsKit.Funnel(player, "FirstPull")
		local items, newIndexItems, tiersCompleted = grantPulls(player, rolled)
		syncTycoon(player) -- once, for all ten
		refreshLabel()
		RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
		celebrate(bestTier(items))
		RemoteEvents.GachaMultiPullResult:FireClient(player, {
			Success = true,
			Items = items,
			NewIndexItems = newIndexItems,
			IndexTiersCompleted = tiersCompleted,
		})
		for _, item in items do
			announcePull(player, item)
		end
		runPullHooks(player)

		task.wait(STATION_DEBOUNCE_SECONDS)
		debounce = false
	end)
end

--[[ Multiplier station --------------------------------------------------------------- ]]

local function createMultiplierStation(plot: Model, origin: CFrame, player: Player)
	local pad = buildStation(plot, origin, "MultiplierStation", PlotLayout.MULTIPLIER_STATION, World.AccentViolet, "Chevrons", { Word = "BOOST" })
	local padLabel = BillboardKit.Pad(pad, {
		Name = "MultiplierLabel",
		Title = "MULTIPLIER",
		TitleColor = UITheme.Colors.VioletLight,
		Pill = "",
		PillGradient = UITheme.Gradients.Violet,
		-- The price, in the same Gold pill as the Gacha's "$483 / pull".
		SecondPillGradient = UITheme.Gradients.Gold,
		SecondPillTextColor = UITheme.Colors.GoldText,
		StudsOffset = Vector3.new(0, PlotLayout.Station.LabelOffsetY, 0),
	})
	local prompt = newPrompt(pad, "UpgradePrompt", "Upgrade", "Cash Multiplier", PlotLayout.Station.PromptDistance)

	local function refreshLabel()
		-- The pad's own value (not x rebirth): "x2.25 · LV 5/15", "x5 MAX".
		local level = PlayerDataService.GetCashMultiplierLevel(player)
		local maxLevel = TycoonConfig.GetCashMultiplierMaxLevel()
		local current = TycoonConfig.GetCashMultiplierValue(level)
		if level >= maxLevel then
			padLabel.SetPill(("%s MAX"):format(NumberFormat.Multiplier(current)))
			padLabel.SetSecondPill(nil)
			padLabel.SetDetail(nil)
			prompt.Enabled = false
			return
		end
		prompt.Enabled = true
		local cost = TycoonConfig.GetCashMultiplierUpgradeCost(level) :: number
		local nextValue = TycoonConfig.GetCashMultiplierValue(level + 1)
		padLabel.SetPill(
			("%s → %s · LV %d/%d"):format(NumberFormat.Multiplier(current), NumberFormat.Multiplier(nextValue), level, maxLevel)
		)
		padLabel.SetSecondPill(NumberFormat.Money(cost))
		prompt.ObjectText = NumberFormat.Money(cost)
		-- Live "need" caption: this refresh runs on every sync (each payout
		-- tick included), so it follows the owner's cash.
		local cash = PlayerDataService.GetCash(player)
		if cash < cost then
			padLabel.SetDetail(("Need %s more"):format(NumberFormat.Money(cost - cash)), UITheme.Colors.MythicBannerLabel)
		else
			padLabel.SetDetail(nil)
		end
	end
	refreshLabel()
	addStationRefresh(player, refreshLabel)

	local debounce = false
	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		if debounce or triggeringPlayer.UserId ~= player.UserId then
			return
		end
		if PlayerDataService.IsCarrying(player) then
			RemoteEvents.MultiplierUpgraded:FireClient(player, { Success = false, Reason = "Carrying" })
			return
		end
		local level = PlayerDataService.GetCashMultiplierLevel(player)
		if level >= TycoonConfig.GetCashMultiplierMaxLevel() then
			return
		end
		local cost = TycoonConfig.GetCashMultiplierUpgradeCost(level) :: number
		if not PlayerDataService.SpendCash(player, cost) then
			-- Never silent: the client toasts "Need $X".
			RemoteEvents.MultiplierUpgraded:FireClient(player, { Success = false, Reason = "InsufficientCash", Cost = cost })
			return
		end

		debounce = true
		AnalyticsKit.Sink(player, cost, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "MultiplierPad")
		AnalyticsKit.Funnel(player, "FirstMultiplier")
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
		playSound(pad)

		RemoteEvents.MultiplierUpgraded:FireClient(player, { Success = true, OldMultiplier = oldMultiplier, NewMultiplier = newMultiplier })

		task.wait(STATION_DEBOUNCE_SECONDS)
		debounce = false
	end)
end

--[[ Pedestals ------------------------------------------------------------------------ ]]

-- "Pedestal1".."PedestalN" inside a "Pedestals" folder, so ItemService can
-- look one up by index. PedestalVisuals styles them once an item is placed.
-- The folder is built complete and parented LAST, so it replicates to the
-- client in one piece (parenting it first let it arrive before its children,
-- and the client wired only the pedestals it could see at that moment).
local function createPedestals(plot: Model, origin: CFrame, player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "Pedestals"

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

		-- Plate on top: StructureLight while empty, tier colour when filled,
		-- with a thin Neon lip under it that only shows when filled
		-- (PedestalVisuals).
		local cap = PartKit.Part({
			Name = "Cap",
			Size = p.CapSize,
			CFrame = pedestal.CFrame * CFrame.new(0, p.ColumnSize.Y / 2 + p.CapSize.Y / 2, 0),
			Color = World.StructureLight,
			Parent = pedestal,
		})
		local lip = PartKit.Part({
			Name = "CapLip",
			Size = Vector3.new(p.CapSize.X + p.CapLipInflate, p.CapLipHeight, p.CapSize.Z + p.CapLipInflate),
			CFrame = cap.CFrame * CFrame.new(0, -(p.CapSize.Y / 2 + p.CapLipHeight / 2), 0),
			Color = World.StructureLight,
			Material = Enum.Material.Neon,
			Transparency = 1,
			Parent = cap,
		})
		PartKit.MakeDecorative(lip)

		-- Always enabled: the owner's client handles it (picker or remove) and
		-- every other client hides it (WorldLabelController, OwnerOnly).
		local prompt = newPrompt(pedestal, "DisplayPrompt", "Display", ("Pedestal %d"):format(index), p.PromptDistance)
		prompt:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)

		-- Hold E to steal (HeistService). Enemy-only: each client enables it
		-- only for an eligible non-owner (WorldLabelController); the server
		-- re-checks everything on RequestSteal.
		local steal = newPrompt(pedestal, "StealPrompt", "Steal", "", HeistConfig.PromptDistance)
		steal.HoldDuration = HeistConfig.GrabHoldSeconds
		steal.Enabled = false
		steal:SetAttribute("EnemyOnly", true)
		steal:SetAttribute("OwnerUserId", player.UserId)
		pedestal:SetAttribute("Filled", false)
		pedestal:SetAttribute("BeingStolen", false)

		BillboardKit.SetPedestalLabel(pedestal, nil)
	end

	folder.Parent = plot
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
			PedestalVisuals.Apply(pedestal, item.Tier, item.Mutation)
		elseif uid and not item then
			-- Points at an item that no longer exists; free the slot.
			PlayerDataService.SetPedestalDisplay(player, pedestalIndex, nil)
		end
	end
end

--[[ LOCK console (heist shield) ------------------------------------------------------- ]]

-- Built once on claim. HeistService answers the prompt (TryLock) through
-- ProximityPromptService; each owner's client drives the label pill, the
-- button colour and the prompt's Enabled from the plot's shield attributes.
local function createLockConsole(plot: Model, origin: CFrame)
	local L = PlotLayout.LockConsole
	local _, post = LockKit.Build(origin, plot)
	local prompt = newPrompt(post, LockKit.PROMPT_NAME, "Lock lab", ("%ds shield"):format(HeistConfig.ShieldSeconds), L.PromptDistance)
	prompt:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)
	BillboardKit.Pad(post, {
		Name = "LockLabel",
		Title = "🔒 LOCK LAB",
		TitleColor = UITheme.Colors.Text,
		Pill = ("READY · %ds shield"):format(HeistConfig.ShieldSeconds),
		PillGradient = UITheme.Gradients.Shield,
		StudsOffset = Vector3.new(0, L.LabelOffsetY - L.PostSize.Y / 2, 0),
		MaxDistance = L.LabelMaxDistance,
		OwnerOnly = true,
	})
end

--[[ Factory line ---------------------------------------------------------------------- ]]

-- The belt, the collector (with its owner-only generator-income label) and the five
-- generators, built once on claim. The generators are restyled from the
-- player's levels on every sync; the cash balls are client-side.
local function createFactoryLine(plot: Model, origin: CFrame, player: Player)
	local collector = FactoryKit.Build(origin, plot)
	local c = PlotLayout.Collector
	collectorLabelByUserId[player.UserId] = BillboardKit.Pad(collector, {
		Name = "CollectorLabel",
		Title = "COLLECTOR",
		TitleColor = UITheme.Colors.GoldLabel,
		Pill = "+$0/s",
		PillGradient = UITheme.Gradients.Gold,
		PillTextColor = UITheme.Colors.GoldText,
		PillTextStroke = false,
		StudsOffset = Vector3.new(0, c.LabelOffsetY, 0),
		MaxDistance = c.LabelMaxDistance,
		OwnerOnly = true,
	})
	for _, generator in TycoonConfig.Generators do
		GeneratorKit.Build(origin, generator.Id, plot)
	end
end

--[[ Rebirth Portal ------------------------------------------------------------------- ]]

-- The portal in the back-right corner, with its owner-only progress label.
-- Its prompt only opens the client's Rebirth panel; RebirthService handles
-- the actual request.
local function createRebirthPortal(plot: Model, origin: CFrame, player: Player)
	local P = PlotLayout.RebirthPortal
	local model = PortalKit.Build(origin, plot)
	local label = BillboardKit.ProgressPad(model.PrimaryPart :: BasePart, {
		Name = "RebirthLabel",
		Title = "REBIRTH",
		TitleColor = UITheme.Colors.Rebirth,
		Pill = "",
		PillGradient = UITheme.Gradients.Orange,
		BarColor = UITheme.Colors.Rebirth,
		CaptionColor = UITheme.Colors.RebirthLabel,
		StudsOffset = Vector3.new(0, P.LabelOffsetY, 0),
		MaxDistance = P.LabelMaxDistance,
		OwnerOnly = true,
	})
	portalByUserId[player.UserId] = { Model = model, Label = label }
end

-- Text, bar and Ready state only (no rebuilds); runs on every sync, which
-- includes every payout tick.
local function refreshRebirthPortal(player: Player)
	local portal = portalByUserId[player.UserId]
	if not portal then
		return
	end
	local rebirths = PlayerDataService.GetRebirths(player)
	local cash = PlayerDataService.GetCash(player)
	local cost = RebirthConfig.GetCost(rebirths)
	local ready = cash >= cost
	local now = NumberFormat.Multiplier(RebirthConfig.GetIncomeMultiplier(rebirths))
	local nextValue = NumberFormat.Multiplier(RebirthConfig.GetIncomeMultiplier(rebirths + 1))
	PortalKit.SetReady(portal.Model, ready)
	portal.Label.SetPill(
		if ready then ("READY · %s → %s"):format(now, nextValue) else ("REBIRTH · %s"):format(NumberFormat.Money(cost))
	)
	portal.Label.SetProgress(cash / cost)
	portal.Label.SetCaption(("%s / %s"):format(NumberFormat.Money(math.min(cash, cost)), NumberFormat.Money(cost)))
end

-- OnSync hook: runs before every snapshot, so the world matches what the
-- client is about to be told: station labels, pedestal labels, the
-- collector, generator states (SetState skips unchanged ones). An upgrade,
-- a rebirth or a debug command all refresh the plot just by syncing.
-- Must not call SyncTycoon.
local function refreshFactoryLine(player: Player)
	local plot = plotByUserId[player.UserId]
	local levels = PlayerDataService.GetGenerators(player)
	if not plot or not levels or plot:GetAttribute("Claimed") ~= true then
		return
	end
	-- Generator income only (what the balls add up to); pedestals pop their
	-- own share on the client. Same formula as the payout, minus pedestals.
	local refreshes = stationRefreshesByUserId[player.UserId]
	if refreshes then
		for _, refresh in refreshes do
			refresh()
		end
	end
	-- Pedestal rates include the income multiplier (pad x rebirth x Index).
	TycoonService.RefreshPedestalLabels(player)
	-- The odds board's chance cells: the owner's rebirths ("R1" until the
	-- Secret recipe unlocks) and the live event (Void Moon: boosted, purple).
	local board = plot:FindFirstChild("OddsBoard")
	local boardPart = board and board:FindFirstChild("Board")
	local surface = boardPart and boardPart:FindFirstChild("OddsSurface")
	if surface and surface:IsA("SurfaceGui") then
		local odds = FusionConfig.FormatOdds(getLuck(player), EventState.GetOddsEvent())
		BillboardKit.SetOddsChances(surface, odds.Fusion, {
			Rebirths = PlayerDataService.GetRebirths(player),
			Boosted = EventState.GetFusionSuccessBonus() > 0,
		})
	end
	refreshRebirthPortal(player)
	local label = collectorLabelByUserId[player.UserId]
	if label then
		local inputs = PlayerDataService.GetIncomeInputs(player)
		local generatorIncome = if inputs then TycoonConfig.GetGeneratorIncome(inputs) else 0
		label.SetPill(("+%s/s"):format(NumberFormat.Money(generatorIncome)))
	end
	local multiplier = PlayerDataService.GetIncomeMultiplier(player)
	for _, generator in TycoonConfig.Generators do
		local model = plot:FindFirstChild(GeneratorKit.GetModelName(generator.Id))
		if model and model:IsA("Model") then
			GeneratorKit.SetState(model, levels[generator.Id] or 0, TycoonConfig.IsUnlocked(generator, levels), multiplier)
		end
	end
end

--[[ Public ---------------------------------------------------------------------------- ]]

-- The shop's lab look on `player`'s claimed plot: Neon Pink (LabStyle pass
-- or the Starter Pack's cosmetic) and the VIP gold trim. Also publishes the
-- plot attributes LabStyle / VIP (clients: pink cash balls). Called on
-- claim and whenever passes change (MonetizationService).
function TycoonService.ApplyLabLook(player: Player)
	local plot = plotByUserId[player.UserId]
	if not plot or not plot:GetAttribute("Claimed") then
		return
	end
	local pink = PlayerDataService.HasCosmetic(player, "LabStyle")
	local vip = PlayerDataService.OwnsPass(player, "VIP")
	plot:SetAttribute("LabStyle", pink)
	plot:SetAttribute("VIP", vip)
	PlotKit.ApplyLabLook(plot, pink, vip)
end

-- `count` free pulls at the player's luck (daily / gift rewards): the real
-- pull path and reveal, paid by the game, not raising the pad price. False
-- if the player has no plot yet (nothing is given).
function TycoonService.GrantFreePulls(player: Player, count: number, caption: string): boolean
	local puller = rewardPullersByUserId[player.UserId]
	local pulls = math.max(1, math.floor(count))
	local rolled = puller and rollPulls(pulls, getLuck(player))
	if not puller or not rolled then
		return false
	end
	-- Before the puller's sync, so the first-pull goal pays in that snapshot.
	PlayerDataService.IncrementFreePulls(player, pulls)
	if not puller(rolled, caption) then
		PlayerDataService.IncrementFreePulls(player, -pulls)
		return false
	end
	AnalyticsKit.Funnel(player, "FirstPull")
	return true
end

-- One item of `tier` with the normal pull mutation roll (the Day 7 / gift
-- item), shown like a pull. False if it can't be given.
function TycoonService.GrantRewardItem(player: Player, tier: string, caption: string): boolean
	local puller = rewardPullersByUserId[player.UserId]
	local def = ItemConfig.PickRandomOfTier(tier, gachaRng)
	if not puller or not def then
		return false
	end
	local mutation = MutationConfig.Roll(gachaRng, getLuck(player), "Pull", EventState.GetMutationMultipliers("Pull"))
	return puller({ { Def = def, Mutation = mutation } }, caption)
end

-- Registers `callback(player)` to run after every successful pull (Pull
-- or Pull x10), on its own thread.
function TycoonService.OnPull(callback: (Player) -> ())
	table.insert(pullHooks, callback)
end

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
	local multiplier = PlayerDataService.GetIncomeMultiplier(player)
	local unlocked = PlayerDataService.GetPedestalCount(player)
	for index = 1, PlotLayout.PEDESTAL_COUNT do
		local pedestal = folder:FindFirstChild("Pedestal" .. index)
		if pedestal and pedestal:IsA("BasePart") then
			-- Spots past 4 need the +2 Pedestals pass: a dim plinth with a
			-- locked label until then (its prompt offers the pass, client).
			local locked = index > unlocked
			pedestal:SetAttribute("Locked", locked)
			local dim = if locked then PlotLayout.LockedPedestalTransparency else 0
			pedestal.Transparency = dim
			local cap = pedestal:FindFirstChild("Cap")
			if cap and cap:IsA("BasePart") then
				cap.Transparency = dim
			end
			local uid = if locked then nil else displays[index]
			local item = uid and PlayerDataService.GetItemByUid(player, uid)
			local steal = pedestal:FindFirstChild("StealPrompt")
			pedestal:SetAttribute("Filled", item ~= nil)
			if item then
				local def = ItemConfig.GetItemById(item.ItemId)
				local name = MutationConfig.GetDisplayName(def and def.Name or item.ItemId, item.Mutation)
				local rate = TycoonConfig.GetItemCashPerSecond(item.Tier, item.Mutation) * multiplier
				BillboardKit.SetPedestalLabel(pedestal, {
					Tier = item.Tier,
					Mutation = item.Mutation,
					ItemName = name,
					Rate = rate,
					Stolen = PlayerDataService.IsItemCarried(player, item.Uid),
				})
				-- What a thief sees on the StealPrompt: the item and its value.
				-- Also an attribute, so the client can put it back after
				-- showing its own text (the Rebirth-0 teaser).
				local stealLabel = ("%s · +%s/s"):format(name, NumberFormat.Money(rate))
				pedestal:SetAttribute("StealLabel", stealLabel)
				if steal and steal:IsA("ProximityPrompt") then
					steal.ObjectText = stealLabel
				end
			else
				BillboardKit.SetPedestalLabel(pedestal, nil)
				BillboardKit.SetPedestalLocked(pedestal, locked)
				pedestal:SetAttribute("StealLabel", "")
				if steal and steal:IsA("ProximityPrompt") then
					steal.ObjectText = ""
				end
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
			-- HeistService keeps the plot's Protected attribute (owner under
			-- HeistConfig.MinRebirths): the sign says so with a teal pill.
			sign.SetPill(if plot:GetAttribute("Protected") == true then "🛡 PROTECTED · NEW LAB" else nil)
			if plot:GetAttribute("Claimed") ~= true or not PlayerDataService.IsDataLoaded(player) then
				sign.Set("FREE LAB", "Step on the green pad")
			else
				local income = PlayerDataService.GetPassiveCashPerSecond(player)
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
	local pad = buildStation(plot, origin, "ClaimStation", PlotLayout.CLAIM_STATION, World.AccentGreen, "Arrow", { Pad = claimButton, Word = "CLAIM" })
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
		local face = station and station:FindFirstChild("Face")
		if face and face:IsA("BasePart") then
			BillboardKit.SetPadFace(face, UITheme.Colors.Disabled, "YOURS", true)
		end

		-- Saved state (pedestals) is restored below.
		while not PlayerDataService.IsDataLoaded(player) and player.Parent do
			task.wait(0.25)
		end
		AnalyticsKit.Funnel(player, "ClaimLab")
		if not player.Parent or not plot.Parent then
			return
		end

		-- New saves (and old ones) start with the Basic Generator running.
		local levels = PlayerDataService.GetGenerators(player) or {}
		if (levels.basic_generator or 0) < TycoonConfig.StartingBasicGeneratorLevel then
			PlayerDataService.SetGeneratorLevel(player, "basic_generator", TycoonConfig.StartingBasicGeneratorLevel)
		end

		createMultiplierStation(plot, origin, player)
		createGachaStation(plot, origin, player)
		createPedestals(plot, origin, player)
		restoreSavedPedestals(plot, player)
		TycoonService.RefreshPedestalLabels(player)
		TycoonService.ApplyLabLook(player)
		createFactoryLine(plot, origin, player)
		createRebirthPortal(plot, origin, player)
		createLockConsole(plot, origin)
		syncTycoon(player) -- also styles the factory line (refreshFactoryLine)
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
	-- The FREE LAB placeholder makes way for this player's plot.
	WorldService.SetSlotOccupied(slotIndex, true)
	local origin = PlotLayout.GetSlotCFrame(slotIndex)
	originByUserId[player.UserId] = origin

	local plot = template:Clone()
	plot.Name = PlotNaming.GetPlotName(player.UserId)
	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("Claimed", false)
	plot:SetAttribute("SlotIndex", slotIndex)
	stripTemplateLeftovers(plot)
	validatePlotClone(plot, player)

	buildShell(plot, origin, player)
	plotSignByUserId[player.UserId] = PlotKit.BuildSignGate(origin, plot)

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
	collectorLabelByUserId[player.UserId] = nil
	stationRefreshesByUserId[player.UserId] = nil
	rewardPullersByUserId[player.UserId] = nil
	portalByUserId[player.UserId] = nil
	local slotIndex = slotByUserId[player.UserId]
	if slotIndex then
		occupiedSlots[slotIndex] = nil
		slotByUserId[player.UserId] = nil
		WorldService.SetSlotOccupied(slotIndex, false)
	end
end

function TycoonService:Init()
	RemoteEvents.RequestUpgrade.OnServerEvent:Connect(onRequestUpgrade)
	RemoteEvents.RequestUpgradeMax.OnServerEvent:Connect(onRequestUpgradeMax)

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
	WorldService = require(script.Parent.WorldService)
	PlayerDataService.OnSync(refreshFactoryLine)
end

return TycoonService
