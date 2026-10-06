--!strict
--[[
	EventService
	------------
	Runs the lab weather clock (EventConfig). Every second it works out which
	event should be on from the clock, deterministically from the UTC slot
	time (never random at runtime), so every server agrees with no messaging,
	and starts or ends it. An override (Studio /event, the admin panel)
	replaces the scheduled event until it ends; then the clock resumes.

	It publishes the live event as workspace attributes (EventId,
	EventEndsAt in server time, EventStrength), which every client and the
	leaf services read through EventState. The effect hooks below are the
	server's way in; they read the same EventState, so a roll always matches
	what the odds displays show:

	  EventService.GetMutationOddsMultiplier(mutation, source)
	  EventService.GetFusionSuccessBonus()
	  EventService.GetGeneratorMultiplier()
	  EventService.GetFusionEventMutation()

	Other code reacts to start/end through EventService.OnEventChanged.

	World effects (server-side rewards; every visual is client-side from the
	attributes plus EventFx cues):
	  Golden Rain    a coin in every claimed plot every CoinIntervalSeconds /
	                 strength (PlotLayout.IsFloorPointFree spots, max
	                 CoinMaxLive, gone after CoinLifetimeSeconds). Only the
	                 owner collects (touch + server distance check): it pays
	                 CoinIncomeSeconds x strength (clamped) of their income.
	  Power Surge    a lightning strike every LightningIntervalSeconds /
	                 strength on one random displayed item in the server
	                 (never one being carried); a normal item has
	                 LightningChargeChance to turn Charged.
	  Meteor Shower  MeteorCount x strength meteors at random times; each
	                 leaves a crater on the street (StreetLayout bounds) with
	                 a "Grab Meteor Core" prompt: the first finished hold
	                 wins an item (MeteorCoreTiers, MeteorCelestialChance).

	Follows ServiceTemplate:
	  :Init()   publishes the empty state.
	  :Start()  resolves PlayerDataService and TycoonService, starts the
	            clock loop and the world effects.
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local StreetLayout = require(ReplicatedStorage.Shared.Config.StreetLayout)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local AnalyticsKit = require(script.Parent.Parent.Modules.AnalyticsKit)

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))

--[[ Types ---------------------------------------------------------------- ]]

-- The running event: id, strength, end in server time. Id nil = nothing on.
export type ActiveEvent = { Id: string?, Strength: number, EndsAt: number }

type Override = { Id: string?, Strength: number, EndsAt: number }

type State = {
	active: ActiveEvent,
	-- An admin/debug event (or a forced quiet spell) until EndsAt (server time).
	override: Override?,
	changeHandlers: { (newEvent: ActiveEvent, oldEvent: ActiveEvent) -> () },
	running: boolean,
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	active = { Id = nil, Strength = 1, EndsAt = 0 },
	override = nil,
	changeHandlers = {},
	running = false,
}

local TICK_SECONDS = 1
local EFFECT_FEED_MIN_TIER = "Legendary"
local CRATER_PILL_MAX_DISTANCE = 120

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule

local rng = Random.new()
-- Bumped on every event change, so an effect loop from the last event stops.
local generation = 0

local EventService = {}

EventService.Name = "EventService"

--[[ Private helpers ------------------------------------------------------ ]]

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- EventId last: a reader reacting to it sees the matching end and strength.
local function publish(event: ActiveEvent)
	Workspace:SetAttribute("EventEndsAt", event.EndsAt)
	Workspace:SetAttribute("EventStrength", event.Strength)
	Workspace:SetAttribute("EventId", event.Id or "")
	if event.Id then
		for _, player in Players:GetPlayers() do
			AnalyticsKit.Funnel(player, "FirstEvent")
		end
	end
end

-- What should be on right now: the override if it's live, else the clock.
local function desiredEvent(): ActiveEvent
	local now = serverNow()
	local override = state.override
	if override and override.EndsAt > now then
		return { Id = override.Id, Strength = override.Strength, EndsAt = override.EndsAt }
	end
	state.override = nil
	local clock = EventState.Now()
	local slot = EventConfig.GetScheduledEvent(clock)
	if slot then
		-- The slot's end on the event clock, in server time.
		return { Id = slot.Id, Strength = 1, EndsAt = now + (slot.EndsAt - clock) }
	end
	return { Id = nil, Strength = 1, EndsAt = 0 }
end

local function tick()
	local wanted = desiredEvent()
	local current = state.active
	if wanted.Id == current.Id and wanted.Strength == current.Strength then
		-- Same event: keep its end time fresh (an override can extend it).
		if wanted.Id and math.abs(wanted.EndsAt - current.EndsAt) > 1 then
			current.EndsAt = wanted.EndsAt
			publish(current)
		end
		return
	end
	state.active = wanted
	publish(wanted)
	if current.Id or wanted.Id then
		warn(("EventService: %s -> %s (x%d)"):format(tostring(current.Id), tostring(wanted.Id), wanted.Strength))
	end
	for _, handler in state.changeHandlers do
		task.spawn(handler, wanted, current)
	end
end

--[[ Public API ------------------------------------------------------------ ]]

-- The running event (Id nil between events).
function EventService.GetActive(): ActiveEvent
	return state.active
end

-- Registers `handler(newEvent, oldEvent)` for every start/end/switch.
function EventService.OnEventChanged(handler: (newEvent: ActiveEvent, oldEvent: ActiveEvent) -> ())
	table.insert(state.changeHandlers, handler)
end

-- Forces `id` at `strength` for `seconds` (admin panel, /event). It replaces
-- the scheduled event until it ends; then the clock resumes.
function EventService.ForceEvent(id: string, seconds: number, strength: number?)
	state.override = {
		Id = id,
		Strength = math.clamp(math.floor(strength or 1), 1, 3),
		EndsAt = serverNow() + math.max(seconds, 1),
	}
	tick()
end

-- Ends whatever is on now (/event off). A scheduled event stays off until
-- its slot is over, so it doesn't snap straight back.
function EventService.EndEvent()
	local current = state.active
	if current.Id then
		state.override = { Id = nil, Strength = 1, EndsAt = current.EndsAt }
	else
		state.override = nil
	end
	tick()
end

-- Studio /eventclock: shifts the clock by `minutes` so the schedule can be
-- walked through. Clients read the same offset (EventState.Now).
function EventService.SetClockOffset(minutes: number)
	Workspace:SetAttribute("EventClockOffset", math.floor(minutes * 60))
	state.override = nil
	tick()
end

--[[ Effect hooks (other code reads these; no globals) ---------------------- ]]

function EventService.GetMutationOddsMultiplier(mutation: string, source: string): number
	local event = state.active
	return EventConfig.GetMutationOddsMultiplier(event.Id, event.Strength, mutation, source)
end

function EventService.GetFusionSuccessBonus(): number
	local event = state.active
	return EventConfig.GetFusionSuccessBonus(event.Id, event.Strength)
end

function EventService.GetGeneratorMultiplier(): number
	local event = state.active
	return EventConfig.GetGeneratorMultiplier(event.Id, event.Strength)
end

function EventService.GetFusionEventMutation(): (string?, number)
	local event = state.active
	return EventConfig.GetFusionEventMutation(event.Id, event.Strength)
end

--[[ World effects ------------------------------------------------------------ ]]

-- How an event-only mutation came about (the reveal card's "how you got it"
-- and the server banner's line).
export type MutationSource = "VoidMoon" | "Lightning" | "Meteor" | "Debug"

-- The SERVER banner for an event-only mutation, at any tier: "Har got a
-- VOID Nova Heart under the Void Moon!" (AnnouncementController, Verb
-- "event").
function EventService.AnnounceEventMutation(
	player: Player,
	item: { ItemId: string, Tier: string, Mutation: string?, EventMutations: { string }? },
	source: MutationSource
)
	local def = ItemConfig.GetItemById(item.ItemId)
	-- The banner's colour word is the top of the stack; the line names it all.
	local label = MutationConfig.GetStackLabel(item.Mutation, item.EventMutations)
	RemoteEvents.RareFusionAnnouncement:FireAllClients({
		Message = ("%s got a %s %s!"):format(player.DisplayName, label, def and def.Name or item.ItemId),
		Tier = item.Tier,
		Mutation = MutationConfig.GetTop(item.Mutation, item.EventMutations),
		EventMutations = item.EventMutations,
		PlayerName = player.DisplayName,
		Verb = "event",
		Source = source,
		ItemName = def and def.Name or item.ItemId,
	})
end

local function isFeedTier(tier: string): boolean
	return (ItemConfig.Tiers[tier] or 0) >= (ItemConfig.Tiers[EFFECT_FEED_MIN_TIER] or math.huge)
end

local function itemName(item: { ItemId: string, Mutation: string?, EventMutations: { string }? }): string
	local def = ItemConfig.GetItemById(item.ItemId)
	return MutationConfig.GetDisplayName(def and def.Name or item.ItemId, item.Mutation, item.EventMutations)
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function claimedPlot(player: Player): Model?
	local plot = TycoonService.GetPlotForPlayer(player)
	if plot and plot.Parent and plot:GetAttribute("Claimed") == true and plot.PrimaryPart then
		return plot
	end
	return nil
end

-- Event objects ----------------------------------------------------------------

-- Workspace.EventObjects.<Id>: every server object an event makes goes here,
-- so its end is one ClearAllChildren (clients clear their own FX in the
-- same folder).
local objectFolders: { [string]: Folder } = {}

local function buildObjectFolders()
	local root = Instance.new("Folder")
	root.Name = EventConfig.ObjectsFolderName
	for _, id in EventConfig.Order do
		local folder = Instance.new("Folder")
		folder.Name = id
		folder.Parent = root
		objectFolders[id] = folder
	end
	root.Parent = Workspace
end

local function objectsFolder(id: string): Folder
	return objectFolders[id]
end

-- A subfolder of an event's folder (e.g. one per lab for Golden Rain coins).
local function subFolder(id: string, name: string): Folder
	local parent = objectsFolder(id)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

-- Destroys everything `id` left in the world (coins, craters, prompts).
local function clearEventObjects(id: string?)
	local folder = id and objectFolders[id]
	if folder then
		folder:ClearAllChildren()
	end
end

-- Golden Rain ----------------------------------------------------------------

local function labCoinFolderName(owner: Player): string
	return "Lab" .. owner.UserId
end

local STREET_COIN_FOLDER = "Street"

-- This rain's earnings per player (session-only; the chip and the end toast
-- read the Player attribute GoldenRainTally). Reset when a rain starts.
local tallies: { [number]: number } = {}

local function resetTallies()
	tallies = {}
	for _, player in Players:GetPlayers() do
		player:SetAttribute("GoldenRainTally", nil)
	end
end

-- Pays `player` `seconds` of their income for a coin, adds it to the tally
-- and pops "+$X" (BIG: gold and larger) where it was.
local function payCoin(player: Player, seconds: number, position: Vector3, big: boolean)
	local amount = math.floor(PlayerDataService.GetPassiveCashPerSecond(player) * seconds)
	if amount <= 0 then
		return
	end
	PlayerDataService.AddCash(player, amount)
	PlayerDataService.AddStat(player, "RainCoins", 1) -- the "Collect 15 coins" quest
	AnalyticsKit.Source(player, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, if big then "BigCoin" else "Coin")
	PlayerDataService.SyncTycoon(player)
	local tally = (tallies[player.UserId] or 0) + amount
	tallies[player.UserId] = tally
	player:SetAttribute("GoldenRainTally", tally)
	RemoteEvents.EventFx:FireClient(player, { Kind = "Coin", Position = position, Amount = amount, Big = big })
end

-- Every live coin's rules, so a Coin Magnet (quest power-up) can collect
-- it through the same path as a touch.
type CoinRules = { CanTake: (Player) -> boolean, OnTake: (Player, Vector3) -> () }
local liveCoins: { [BasePart]: CoinRules } = {}

-- Collects `coin` for `player` once (first wins); the caller checked reach.
local function takeCoin(coin: BasePart, player: Player)
	local rules = liveCoins[coin]
	if not rules or coin:GetAttribute("Collected") then
		return
	end
	coin:SetAttribute("Collected", true)
	liveCoins[coin] = nil
	local position = coin.Position
	coin:Destroy()
	rules.OnTake(player, position)
end

-- A Neon gold coin on its edge, spinning and bobbing (FT_Hover). `canTake`
-- decides who may collect it (re-checked by distance on the server);
-- `onTake` pays them.
local function buildCoin(
	parent: Instance,
	cframe: CFrame,
	big: boolean,
	canTake: (Player) -> boolean,
	onTake: (Player, Vector3) -> ()
)
	local c = PlotLayout.EventCoin
	local coin = PartKit.Part({
		Name = if big then "BigCoin" else "Coin",
		Shape = Enum.PartType.Cylinder,
		Size = if big then c.Size * c.BigScale else c.Size,
		CFrame = cframe,
		Color = UITheme.World.AccentGold,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = parent,
	})
	coin.CanQuery = false
	coin.CanTouch = true
	coin:SetAttribute("Big", big)
	PartKit.SetHover(coin, c.SpinDegPerSec, c.Bob, c.BobPeriod, "Bob")
	local reach = EventConfig.CoinCollectDistance + (if big then c.Size.Y * (c.BigScale - 1) else 0)
	coin.Touched:Connect(function(hit: BasePart)
		if coin:GetAttribute("Collected") then
			return
		end
		local character = hit:FindFirstAncestorWhichIsA("Model")
		local toucher = character and Players:GetPlayerFromCharacter(character)
		local root = toucher and getRoot(toucher)
		if not toucher or not root or not canTake(toucher) or not PlayerDataService.IsDataLoaded(toucher) then
			return
		end
		if (root.Position - coin.Position).Magnitude > reach then
			return
		end
		-- First valid touch wins (street coins are a race).
		takeCoin(coin, toucher)
	end)
	liveCoins[coin] = { CanTake = canTake, OnTake = onTake }
	coin.Destroying:Connect(function()
		liveCoins[coin] = nil
	end)
	Debris:AddItem(coin, EventConfig.CoinLifetimeSeconds)
end

-- A lab coin: only the owner collects. 1 in BigCoinChance is BIG.
local function spawnCoin(owner: Player, plot: Model, strength: number)
	local coinFolder = subFolder("GoldenRain", labCoinFolderName(owner))
	if #coinFolder:GetChildren() >= EventConfig.CoinMaxLive then
		return
	end
	local c = PlotLayout.EventCoin
	local inner = PlotLayout.PLOT_HALF - PlotLayout.WALL_THICKNESS
	local origin = (plot.PrimaryPart :: BasePart).CFrame
	local big = rng:NextInteger(1, EventConfig.BigCoinChance) == 1
	-- Normal coins scale with an admin's strength (clamped); BIG ones don't.
	local seconds = if big
		then EventConfig.BigCoinIncomeSeconds
		else math.min(EventConfig.CoinIncomeSeconds * strength, EventConfig.CoinMaxIncomeSeconds)
	for _ = 1, c.SpawnTries do
		local x, z = rng:NextNumber(-inner, inner), rng:NextNumber(-inner, inner)
		if PlotLayout.IsFloorPointFree(x, z, c.SpawnMargin * (if big then c.BigScale else 1)) then
			local centerY = if big then c.CenterY * c.BigScale else c.CenterY
			buildCoin(coinFolder, PartKit.At(origin, Vector3.new(x, 0, z), centerY), big, function(player)
				return player == owner
			end, function(player, position)
				payCoin(player, seconds, position, big)
			end)
			return
		end
	end
end

-- A street coin: anyone, first come; it pays the GRABBER's income.
local function spawnStreetCoin()
	local folder = subFolder("GoldenRain", STREET_COIN_FOLDER)
	if #folder:GetChildren() >= EventConfig.StreetCoinMaxLive then
		return
	end
	local point = StreetLayout.GetRandomMeteorPoint(rng)
	local cframe = CFrame.new(point + Vector3.new(0, PlotLayout.EventCoin.CenterY, 0))
	buildCoin(folder, cframe, false, function()
		return true
	end, function(player, position)
		payCoin(player, EventConfig.StreetCoinIncomeSeconds, position, false)
	end)
end

-- Coin Magnet: every armed player pulls in each coin they may take within
-- the radius. Returns the players whose magnet ran (disarmed at rain end).
local function runMagnets(used: { [Player]: boolean })
	local radius = QuestConfig.PowerUps.CoinMagnet.Radius or 0
	for _, player in Players:GetPlayers() do
		local root = getRoot(player)
		if root and PlayerDataService.IsArmed(player, "CoinMagnet") and PlayerDataService.IsDataLoaded(player) then
			used[player] = true
			for coin, rules in liveCoins do
				if coin.Parent and rules.CanTake(player) and (coin.Position - root.Position).Magnitude <= radius then
					takeCoin(coin, player)
				end
			end
		end
	end
end

local function runGoldenRain(myGeneration: number, strength: number)
	local labInterval = EventConfig.CoinIntervalSeconds / strength
	local streetInterval = EventConfig.StreetCoinIntervalSeconds / strength
	local nextLab, nextStreet = 0, os.clock() + streetInterval
	local nextMagnet = 0
	local magnetUsers: { [Player]: boolean } = {}
	while generation == myGeneration do
		local now = os.clock()
		if now >= nextMagnet then
			nextMagnet = now + QuestConfig.MagnetIntervalSeconds
			runMagnets(magnetUsers)
		end
		if now >= nextLab then
			nextLab = now + labInterval
			for _, player in Players:GetPlayers() do
				local plot = if PlayerDataService.IsDataLoaded(player) then claimedPlot(player) else nil
				if plot then
					spawnCoin(player, plot, strength)
				end
			end
		end
		if now >= nextStreet then
			nextStreet = now + streetInterval
			spawnStreetCoin()
		end
		task.wait(math.max(0.1, math.min(nextLab, nextStreet, nextMagnet) - os.clock()))
	end
	-- A magnet lasts one rain: spent on the rain it ran in.
	for player in magnetUsers do
		if player.Parent then
			PlayerDataService.SetArmed(player, "CoinMagnet", false)
			PlayerDataService.SyncTycoon(player)
		end
	end
end

-- Power Surge -------------------------------------------------------------------

type Target = { Owner: Player, Uid: string, Index: number, Pedestal: BasePart }

local LIGHTNING_TARGET_ATTRIBUTE = "LightningTarget"
-- Pedestals currently marked, so an event end can unmark them.
local markedPedestals: { [BasePart]: boolean } = {}

local function unmark(pedestal: BasePart)
	markedPedestals[pedestal] = nil
	pedestal:SetAttribute(LIGHTNING_TARGET_ATTRIBUTE, nil)
end

local function unmarkAll()
	for pedestal in markedPedestals do
		unmark(pedestal)
	end
end

-- Every displayed item of `player` that isn't being carried in a heist.
local function playerTargets(player: Player): { Target }
	local targets = {}
	local plot = if PlayerDataService.IsDataLoaded(player) then claimedPlot(player) else nil
	local pedestals = plot and plot:FindFirstChild("Pedestals")
	if pedestals then
		for index, uid in PlayerDataService.GetPedestalDisplays(player) do
			local pedestal = pedestals:FindFirstChild("Pedestal" .. index)
			if uid and pedestal and pedestal:IsA("BasePart") and not PlayerDataService.IsItemCarried(player, uid) then
				table.insert(targets, { Owner = player, Uid = uid, Index = index, Pedestal = pedestal })
			end
		end
	end
	return targets
end

-- A plot first (every lab with a displayed item equally likely), then one of
-- its pedestals: one rich lab can't hog the strikes.
local function pickTarget(): Target?
	local labs: { { Target } } = {}
	for _, player in Players:GetPlayers() do
		local targets = playerTargets(player)
		if #targets > 0 then
			table.insert(labs, targets)
		end
	end
	if #labs == 0 then
		return nil
	end
	local lab = labs[rng:NextInteger(1, #labs)]
	return lab[rng:NextInteger(1, #lab)]
end

-- The bolt on a marked target: it may STACK Charged onto the item (any
-- base mutation stays; an item already Charged is skipped). Returns
-- whether it did.
local function strike(target: Target): boolean
	-- Still the same item on that pedestal, and not carried off meanwhile.
	local displays = PlayerDataService.GetPedestalDisplays(target.Owner)
	if displays[target.Index] ~= target.Uid or PlayerDataService.IsItemCarried(target.Owner, target.Uid) then
		return false
	end
	local item = PlayerDataService.GetItemByUid(target.Owner, target.Uid)
	if
		not item
		or MutationConfig.HasEvent(item.EventMutations, "Charged")
		or rng:NextNumber() >= EventConfig.LightningChargeChance
	then
		return false
	end
	-- Something was already on it: the card says "+ CHARGED (stacked!)".
	local stacked = #MutationConfig.List(item.Mutation, item.EventMutations) > 0
	-- Charged: inventory, Index, pedestal visuals and labels, then the syncs.
	local added, isNew = PlayerDataService.AddItemEventMutation(target.Owner, target.Uid, "Charged")
	if not added then
		return false
	end
	PedestalVisuals.Apply(target.Pedestal, item.Tier, item.Mutation, item.EventMutations)
	TycoonService.RefreshPedestalLabels(target.Owner)
	RemoteEvents.SyncInventory:FireClient(target.Owner, PlayerDataService.GetInventory(target.Owner))
	PlayerDataService.SyncTycoon(target.Owner)
	-- The owner gets the event mutation reveal card; everyone the banner.
	RemoteEvents.EventReward:FireClient(target.Owner, {
		Caption = "⚡ STRUCK BY LIGHTNING",
		Item = item,
		NewIndex = isNew,
		Source = "Lightning",
		Added = "Charged",
		Stacked = stacked,
	})
	EventService.AnnounceEventMutation(target.Owner, item, "Lightning")
	return true
end

local function runPowerSurge(myGeneration: number, strength: number)
	local interval = EventConfig.LightningIntervalSeconds / strength
	local warning = math.min(EventConfig.LightningWarningSeconds, interval)
	while generation == myGeneration do
		task.wait(interval - warning)
		if generation ~= myGeneration then
			return
		end
		local target = pickTarget()
		if target then
			-- Mark it: every client shows the cyan ring and "STRIKE IN 3·2·1".
			markedPedestals[target.Pedestal] = true
			target.Pedestal:SetAttribute(LIGHTNING_TARGET_ATTRIBUTE, true)
			RemoteEvents.EventFx:FireAllClients({
				Kind = "StrikeWarning",
				Pedestal = target.Pedestal,
				Position = target.Pedestal.Position,
				Seconds = warning,
			})
			task.wait(warning)
			unmark(target.Pedestal)
			if generation ~= myGeneration then
				return
			end
			local charged = strike(target)
			RemoteEvents.EventFx:FireAllClients({
				Kind = "Lightning",
				Position = target.Pedestal.Position,
				Result = if charged then "Charged" else "Missed",
			})
		else
			task.wait(warning)
		end
	end
end

-- Meteor Shower -------------------------------------------------------------------


local function rollCoreItem(): (string?, string, string?)
	local total = 0
	for _, entry in EventConfig.MeteorCoreTiers do
		total += entry.Weight
	end
	local roll = rng:NextNumber() * total
	local tier = EventConfig.MeteorCoreTiers[1].Tier
	for _, entry in EventConfig.MeteorCoreTiers do
		roll -= entry.Weight
		if roll < 0 then
			tier = entry.Tier
			break
		end
	end
	local def = ItemConfig.PickRandomOfTier(tier, rng)
	return def and def.Id, tier
end

local function grantCore(player: Player)
	local itemId, tier = rollCoreItem()
	if not itemId then
		warn(("EventService: no ItemConfig entry for meteor tier %s"):format(tier))
		return
	end
	-- The normal pull roll for the base, then Celestial ON TOP (stacking).
	local multipliers: MutationConfig.OddsMultipliers = {}
	for _, name in MutationConfig.Order do
		multipliers[name] = EventService.GetMutationOddsMultiplier(name, "Pull")
	end
	local base = MutationConfig.Roll(rng, PlayerDataService.GetLuck(player), "Pull", multipliers)
	local celestial = rng:NextNumber() < EventConfig.MeteorCelestialChance
	local entry, isNew = PlayerDataService.AddItem(player, itemId, tier, base, if celestial then { "Celestial" } else nil)
	if not entry then
		return
	end
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	PlayerDataService.SyncTycoon(player)
	RemoteEvents.EventReward:FireClient(player, {
		Caption = "☄ METEOR CORE",
		Item = entry,
		NewIndex = isNew,
		Source = "Meteor",
		Added = if celestial then "Celestial" else nil,
		Stacked = celestial and entry.Mutation ~= nil,
	})
	if celestial then
		EventService.AnnounceEventMutation(player, entry, "Meteor")
	elseif isFeedTier(tier) then
		local def = ItemConfig.GetItemById(itemId)
		RemoteEvents.RareFusionAnnouncement:FireAllClients({
			Message = ("%s grabbed a %s from a meteor!"):format(player.DisplayName, itemName(entry)),
			Tier = tier,
			Mutation = base,
			PlayerName = player.DisplayName,
			Verb = "grabbed",
			ItemName = def and def.Name or itemId,
		})
	end
end

-- Studio /eventmut: a random Epic with an event-only mutation, through the
-- real reward path (EventReward -> the reveal card, and the banner).
function EventService.GrantEventMutationItem(player: Player, mutation: string): boolean
	if not MutationConfig.IsEventOnly(mutation) or not PlayerDataService.IsDataLoaded(player) then
		return false
	end
	local def = ItemConfig.PickRandomOfTier("Epic", rng)
	if not def then
		return false
	end
	local entry, isNew = PlayerDataService.AddItem(player, def.Id, "Epic", mutation)
	if not entry then
		return false
	end
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	PlayerDataService.SyncTycoon(player)
	local source: MutationSource = if mutation == "Void"
		then "VoidMoon"
		elseif mutation == "Charged" then "Lightning"
		else "Meteor"
	RemoteEvents.EventReward:FireClient(player, {
		Caption = "EVENT MUTATION",
		Item = entry,
		NewIndex = isNew,
		Source = source,
		Added = mutation,
	})
	EventService.AnnounceEventMutation(player, entry, source)
	return true
end

-- The crater: a dark rock disc, orange Neon crack strips (never a flat Neon
-- disc), a glowing core, and the race-to-grab prompt.
local function buildCrater(point: Vector3)
	local m = StreetLayout.MeteorCrater
	local folder = objectsFolder("MeteorShower")
	local crater = Instance.new("Model")
	crater.Name = "MeteorCrater"
	local base = CFrame.new(point + Vector3.new(0, m.Height / 2, 0))
	local disc = PartKit.Part({
		Name = "Crater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(m.Height, m.Diameter, m.Diameter),
		CFrame = base * CFrame.Angles(0, 0, math.rad(90)),
		Color = UITheme.World.Structure,
		Parent = crater,
	})
	disc.CanCollide = false
	for index = 1, m.CrackCount do
		local angle = (index / m.CrackCount) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local crack = PartKit.Part({
			Name = "Crack",
			Size = Vector3.new(m.CrackLength, m.CrackHeight, m.CrackWidth),
			CFrame = base
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(m.CrackLength / 2 + m.CoreDiameter / 2, m.Height / 2 + m.CrackHeight / 2, 0),
			Color = UITheme.World.AccentRebirth,
			Material = Enum.Material.Neon,
			Parent = crater,
		})
		PartKit.MakeDecorative(crack)
	end
	local core = PartKit.Part({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * m.CoreDiameter,
		CFrame = base * CFrame.new(0, m.Height / 2 + m.CoreDiameter / 2, 0),
		Color = UITheme.World.AccentRebirth,
		Material = Enum.Material.Neon,
		Parent = crater,
	})
	PartKit.MakeDecorative(core)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MeteorPrompt"
	prompt.ActionText = "Grab Meteor Core"
	prompt.ObjectText = "First to grab wins"
	prompt.HoldDuration = EventConfig.MeteorGrabSeconds
	prompt.MaxActivationDistance = EventConfig.MeteorPromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Parent = core
	BillboardKit.Chip(core, {
		Name = "CraterPill",
		Text = "Hold E · free item",
		Gradient = UITheme.Gradients.Meteor,
		Studs = Vector2.new(6.5, 1.4),
		StudsOffset = Vector3.new(0, 3, 0),
		MaxDistance = CRATER_PILL_MAX_DISTANCE,
	})
	-- First valid completion wins; everyone after gets "Too slow!".
	local claimed = false
	prompt.Triggered:Connect(function(player: Player)
		local root = getRoot(player)
		if not root or (root.Position - core.Position).Magnitude > EventConfig.MeteorPromptDistance + 2 then
			return
		end
		if claimed or not PlayerDataService.IsDataLoaded(player) then
			RemoteEvents.EventNotice:FireClient(player, { Text = "Too slow!" })
			return
		end
		claimed = true
		prompt.Enabled = false
		grantCore(player)
		crater:Destroy()
	end)
	crater.PrimaryPart = disc
	crater.Parent = folder
	Debris:AddItem(crater, EventConfig.MeteorCraterLifetime)
end

local function dropMeteor(myGeneration: number)
	local point = StreetLayout.GetRandomMeteorPoint(rng)
	local m = StreetLayout.MeteorCrater
	RemoteEvents.EventFx:FireAllClients({
		Kind = "Meteor",
		From = point + m.FallFrom,
		To = point,
		Seconds = EventConfig.MeteorFallSeconds,
	})
	task.delay(EventConfig.MeteorFallSeconds, function()
		-- The shower may have ended mid-fall: no crater after its cleanup.
		if generation == myGeneration then
			buildCrater(point)
		end
	end)
end

local function runMeteorShower(myGeneration: number, strength: number, endsAt: number)
	local count = EventConfig.MeteorCount * strength
	-- Random landing times inside the window, leaving room to fall.
	local window = math.max(1, endsAt - Workspace:GetServerTimeNow() - EventConfig.MeteorFallSeconds - 5)
	local times = {}
	for index = 1, count do
		times[index] = rng:NextNumber(0, window)
	end
	table.sort(times)
	local started = os.clock()
	for _, at in times do
		local wait = at - (os.clock() - started)
		if wait > 0 then
			task.wait(wait)
		end
		if generation ~= myGeneration then
			return
		end
		dropMeteor(myGeneration)
	end
end

-- Ends the old event's world effects (its loops stop on the generation bump,
-- its objects go) and starts the new one's.
local function startWorldEffects(event: ActiveEvent, old: ActiveEvent?)
	generation += 1
	local myGeneration = generation
	if old then
		clearEventObjects(old.Id)
	end
	clearEventObjects(event.Id)
	unmarkAll()
	if event.Id == "GoldenRain" then
		resetTallies()
		task.spawn(runGoldenRain, myGeneration, event.Strength)
	elseif event.Id == "PowerSurge" then
		task.spawn(runPowerSurge, myGeneration, event.Strength)
	elseif event.Id == "MeteorShower" then
		task.spawn(runMeteorShower, myGeneration, event.Strength, event.EndsAt)
	end
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function EventService:Init()
	buildObjectFolders()
	publish(state.active)
end

function EventService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)
	EventService.OnEventChanged(function(newEvent: ActiveEvent, oldEvent: ActiveEvent)
		startWorldEffects(newEvent, oldEvent)
		-- Every odds display and income number re-reads the event on sync
		-- (pad and board labels, the HUD's generator income).
		for _, player in Players:GetPlayers() do
			if PlayerDataService.IsDataLoaded(player) then
				PlayerDataService.SyncTycoon(player)
			end
		end
	end)
	state.running = true
	tick()
	task.spawn(function()
		while state.running do
			task.wait(TICK_SECONDS)
			tick()
		end
	end)
end

function EventService:Stop()
	state.running = false
end

return EventService
