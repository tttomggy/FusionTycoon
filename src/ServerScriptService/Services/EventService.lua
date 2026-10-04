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
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local StreetLayout = require(ReplicatedStorage.Shared.Config.StreetLayout)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)

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

local function isFeedTier(tier: string): boolean
	return (ItemConfig.Tiers[tier] or 0) >= (ItemConfig.Tiers[EFFECT_FEED_MIN_TIER] or math.huge)
end

local function itemName(item: { ItemId: string, Mutation: string? }): string
	local def = ItemConfig.GetItemById(item.ItemId)
	return MutationConfig.GetDisplayName(def and def.Name or item.ItemId, item.Mutation)
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

local function collectCoin(owner: Player, coin: BasePart, strength: number)
	if coin:GetAttribute("Collected") then
		return
	end
	coin:SetAttribute("Collected", true)
	local position = coin.Position
	coin:Destroy()
	local seconds = math.min(EventConfig.CoinIncomeSeconds * strength, EventConfig.CoinMaxIncomeSeconds)
	local amount = math.floor(PlayerDataService.GetPassiveCashPerSecond(owner) * seconds)
	if amount <= 0 then
		return
	end
	PlayerDataService.AddCash(owner, amount)
	PlayerDataService.SyncTycoon(owner)
	RemoteEvents.EventFx:FireClient(owner, { Kind = "Coin", Position = position, Amount = amount })
end

local function spawnCoin(owner: Player, plot: Model, strength: number)
	local coinFolder = subFolder("GoldenRain", labCoinFolderName(owner))
	if #coinFolder:GetChildren() >= EventConfig.CoinMaxLive then
		return
	end
	local c = PlotLayout.EventCoin
	local inner = PlotLayout.PLOT_HALF - PlotLayout.WALL_THICKNESS
	local origin = (plot.PrimaryPart :: BasePart).CFrame
	for _ = 1, c.SpawnTries do
		local x, z = rng:NextNumber(-inner, inner), rng:NextNumber(-inner, inner)
		if PlotLayout.IsFloorPointFree(x, z, c.SpawnMargin) then
			local coin = PartKit.Part({
				Name = "Coin",
				Shape = Enum.PartType.Cylinder,
				Size = c.Size,
				CFrame = PartKit.At(origin, Vector3.new(x, 0, z), c.CenterY),
				Color = UITheme.World.AccentGold,
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = coinFolder,
			})
			coin.CanQuery = false
			coin.CanTouch = true
			PartKit.SetHover(coin, c.SpinDegPerSec, c.Bob, c.BobPeriod, "Bob")
			-- Only the owner collects; the touch is re-checked by distance.
			coin.Touched:Connect(function(hit: BasePart)
				local character = hit:FindFirstAncestorWhichIsA("Model")
				local toucher = character and Players:GetPlayerFromCharacter(character)
				local root = toucher and getRoot(toucher)
				if toucher == owner and root and (root.Position - coin.Position).Magnitude <= EventConfig.CoinCollectDistance then
					collectCoin(owner, coin, strength)
				end
			end)
			Debris:AddItem(coin, EventConfig.CoinLifetimeSeconds)
			return
		end
	end
end

local function runGoldenRain(myGeneration: number, strength: number)
	local interval = EventConfig.CoinIntervalSeconds / strength
	while generation == myGeneration do
		for _, player in Players:GetPlayers() do
			local plot = if PlayerDataService.IsDataLoaded(player) then claimedPlot(player) else nil
			if plot then
				spawnCoin(player, plot, strength)
			end
		end
		task.wait(interval)
	end
end

-- Power Surge -------------------------------------------------------------------

type Target = { Owner: Player, Uid: string, Index: number, Pedestal: BasePart }

-- Every displayed item in the server that isn't being carried in a heist.
local function displayedTargets(): { Target }
	local targets = {}
	for _, player in Players:GetPlayers() do
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
	end
	return targets
end

local function strikeLightning()
	local targets = displayedTargets()
	if #targets == 0 then
		return
	end
	local target = targets[rng:NextInteger(1, #targets)]
	RemoteEvents.EventFx:FireAllClients({ Kind = "Lightning", Position = target.Pedestal.Position })
	local item = PlayerDataService.GetItemByUid(target.Owner, target.Uid)
	if not item or item.Mutation ~= nil or rng:NextNumber() >= EventConfig.LightningChargeChance then
		return
	end
	-- Charged: inventory, Index, pedestal visuals and labels, then the syncs.
	PlayerDataService.SetItemMutation(target.Owner, target.Uid, "Charged")
	PedestalVisuals.Apply(target.Pedestal, item.Tier, item.Mutation)
	TycoonService.RefreshPedestalLabels(target.Owner)
	RemoteEvents.SyncInventory:FireClient(target.Owner, PlayerDataService.GetInventory(target.Owner))
	PlayerDataService.SyncTycoon(target.Owner)
	local name = itemName(item)
	RemoteEvents.EventNotice:FireClient(target.Owner, { Text = ("⚡ Your %s got CHARGED!"):format(name), Big = true })
	if isFeedTier(item.Tier) then
		local def = ItemConfig.GetItemById(item.ItemId)
		RemoteEvents.RareFusionAnnouncement:FireAllClients({
			Message = ("%s's %s got CHARGED!"):format(target.Owner.DisplayName, name),
			Tier = item.Tier,
			Mutation = item.Mutation,
			PlayerName = target.Owner.DisplayName,
			Verb = "charged",
			ItemName = def and def.Name or item.ItemId,
		})
	end
end

local function runPowerSurge(myGeneration: number, strength: number)
	local interval = EventConfig.LightningIntervalSeconds / strength
	while generation == myGeneration do
		task.wait(interval)
		if generation == myGeneration then
			strikeLightning()
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
	local mutation = if rng:NextNumber() < EventConfig.MeteorCelestialChance then "Celestial" else nil
	return def and def.Id, tier, mutation
end

local function grantCore(player: Player)
	local itemId, tier, mutation = rollCoreItem()
	if not itemId then
		warn(("EventService: no ItemConfig entry for meteor tier %s"):format(tier))
		return
	end
	local entry, isNew = PlayerDataService.AddItem(player, itemId, tier, mutation)
	if not entry then
		return
	end
	RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))
	PlayerDataService.SyncTycoon(player)
	RemoteEvents.EventReward:FireClient(player, { Caption = "☄ METEOR CORE", Item = entry, NewIndex = isNew })
	if isFeedTier(tier) or mutation then
		local def = ItemConfig.GetItemById(itemId)
		RemoteEvents.RareFusionAnnouncement:FireAllClients({
			Message = ("%s grabbed a %s from a meteor!"):format(player.DisplayName, itemName(entry)),
			Tier = tier,
			Mutation = mutation,
			PlayerName = player.DisplayName,
			Verb = "grabbed",
			ItemName = def and def.Name or itemId,
		})
	end
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
	if event.Id == "GoldenRain" then
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
