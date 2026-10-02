local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage.Shared.Config
local TycoonConfig = require(Config.TycoonConfig)
local PlotNaming = require(Config.PlotNaming)
local PlotLayout = require(Config.PlotLayout)
local FusionConfig = require(Config.FusionConfig)
local ItemConfig = require(Config.ItemConfig)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local PadStyler = require(ReplicatedStorage.Shared.Modules.PadStyler)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)
local ImportedEffects = require(ReplicatedStorage.Shared.VFX.ImportedEffects)

-- PlayerDataService is a leaf (requires no services), so this module-scope
-- require can't form a cycle.
local PlayerDataService = require(script.Parent.PlayerDataService)

type FusionMachineServiceModule = typeof(require(script.Parent.FusionMachineService))
-- Resolved in :Start().
local FusionMachineService: FusionMachineServiceModule

local TycoonService = {}
TycoonService.Name = "TycoonService"

-- From user-supplied Toolbox VFX packs (Workspace), extracted to
-- ReplicatedStorage.Shared.VFX.*.rbxm. Optional by design (FindFirstChild,
-- not WaitForChild) so a session running before that extraction step happens
-- degrades to whatever VFX already existed at each site instead of erroring.
local VFXFolder = ReplicatedStorage.Shared.VFX
local levelingUpEffectTemplate = VFXFolder:FindFirstChild("LevelingUpEffect") :: BasePart?
local explosionEffectTemplate = VFXFolder:FindFirstChild("ExplosionEffect") :: BasePart?

-- Every pad billboard in the plot (Buy Dropper 2, Gacha Pull, Multiplier Pad)
-- shares this MaxDistance. Unset, a BillboardGui renders at any distance -
-- confirmed via testing to be why Fusion Odds and Gacha Pull were visible
-- and overlapping from clear across the map. 20 sits outside every
-- ProximityPrompt's own 10-stud MaxActivationDistance (see
-- GACHA_PAD_PROMPT_MAX_ACTIVATION_DISTANCE/PEDESTAL_PROMPT_MAX_ACTIVATION_DISTANCE
-- below, and FusionMachineService's own PROMPT_MAX_ACTIVATION_DISTANCE), so a
-- label becomes readable before its pad's interaction range kicks in rather
-- than appearing at the same moment. FusionMachineService.lua's own Fusion
-- Odds billboard uses the same value independently, for the same reason.
local BILLBOARD_MAX_VISIBLE_DISTANCE_STUDS = 20

local MAX_PLOT_SLOTS = 50
-- Must comfortably exceed the plot row's own total footprint (Dropper1 ->
-- Dropper2 slot -> Multiplier Pad -> Gacha Pad), or adjacent plots' pads
-- overlap regardless of how wide the Floor itself is. The Pedestal Showcase
-- doesn't factor in here - it reaches into -Z, not along this X row, so it
-- has no plot-to-plot spacing constraint (see PEDESTAL_SHOWCASE_* below).
local PLOT_SLOT_SPACING_STUDS = 140
-- Explicit gap above PlotOrigin's surface height for SpawnLocation, so a
-- spawning character never clips into the floor even if PlotOrigin's Y
-- reading is off by a hair.
local SPAWN_LOCATION_CLEARANCE_STUDS = 0.5
local CASH_DROP_DEBRIS_LIFETIME_SECONDS = 30
-- How far in front of Dropper1 (along its facing direction) the Collector sits,
-- so cash lands on the open floor first instead of spawning right on top of it.
local COLLECTOR_FORWARD_OFFSET_STUDS = 12
local CASH_DROP_FORWARD_SPEED_STUDS_PER_SECOND = 6

-- ClaimButton comes from the template with whatever Material/Color it was
-- authored with (easy to miss entirely); styled bright green here so it
-- reads as an interactive "claim" action at a glance.
local CLAIM_BUTTON_COLOR = Color3.fromRGB(20, 255, 80)
-- Claim pod: a short PadStyler-accented riser built beneath ClaimButton so it
-- reads as a small kiosk/pod instead of a flat button sitting on the ground.
-- Purely a decorative part parented alongside ClaimButton - it never touches
-- ClaimButton's own Position/Size/Touched wiring, so the claim trigger itself
-- is unaffected.
local CLAIM_POD_RISER_HEIGHT_STUDS = 3
local CLAIM_POD_RISER_MARGIN_STUDS = 1

-- Cash parts belong to their own collision group so they pass through player
-- characters (left in "Default") without being bumped. Floor/Collector are
-- moved into a second group so they keep colliding with cash even though
-- "Default" no longer does.
local CASH_COLLISION_GROUP = "CashParts"
local PLOT_ENVIRONMENT_COLLISION_GROUP = "PlotEnvironment"

local DROPPER2_COST = TycoonConfig.Dropper2Cost
local DROPPER2_LABEL = "Buy Dropper 2"
local DROPPER2_SIDE_OFFSET_STUDS = 12

-- Multiplier Pad sits one row-slot further along the same edge as the
-- Dropper2 button/spawn spot, so the row reads: Dropper1, Dropper2, Pad.
local MULTIPLIER_PAD_LABEL = "Buy Multiplier Pad"
local MULTIPLIER_PAD_ROW_OFFSET_STUDS = DROPPER2_SIDE_OFFSET_STUDS * 2
-- ClaimButton's placement comes from the template, not this service, so
-- unlike every other row element (all placed relative to PlotOrigin, which
-- is why they never collide with each other) a fixed offset for the pad
-- can't guarantee it clears ClaimButton wherever the author put it. Checked
-- against ClaimButton's actual position at build time instead: see the
-- clearance check in createMultiplierPad. Capped at 32, comfortably short of
-- the Gacha Pad (starts at +52, see PlotLayout.GACHA_PAD_ROW_OFFSET_STUDS -
-- that value's own comment spells out exactly why it needs to stay this far
-- out) so pushing the pad clear of ClaimButton can't create a new collision,
-- or activation-range overlap, further up the row.
local MULTIPLIER_PAD_MIN_CLAIM_BUTTON_CLEARANCE_STUDS = 12
local MULTIPLIER_PAD_MAX_ROW_OFFSET_STUDS = 32
-- Touched fires continuously while a character stands on the pad; this
-- debounce turns that into one purchase per touch instead of many per frame.
local MULTIPLIER_PAD_DEBOUNCE_SECONDS = 1
-- One-shot feedback (VFX/sound/screen popup) when a multiplier purchase
-- succeeds - purely presentational, doesn't touch SpendCash/SetCashMultiplierLevel.
local MULTIPLIER_UPGRADE_ACCENT_COLOR = Color3.fromRGB(200, 60, 255)
local MULTIPLIER_UPGRADE_BURST_COUNT = 30
-- rbxasset://sounds/bell.wav fails to load in this project ("Temp read
-- failed") - reusing DROPPER_POP_SOUND_ID's electronicpingshort.wav instead,
-- since that one's already confirmed working (it plays on every dropper pop).
local MULTIPLIER_UPGRADE_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"

-- Dropper idle glow + per-drop "pop" feedback. Matches the falling cash
-- part's own color so the dropper visually reads as the source of that cash.
local DROPPER_ACCENT_COLOR = Color3.fromRGB(85, 255, 127)
local DROPPER_IDLE_PULSE_SECONDS = 2.2

-- Gacha Pad: the only source of fusable items. Sits one row-slot past the
-- Multiplier Pad (see PlotLayout.GACHA_PAD_ROW_OFFSET_STUDS), so the main row
-- reads: Dropper1, Dropper2, Multiplier Pad, Gacha Pad. The Pedestal Showcase
-- isn't part of this row at all anymore - it's a separate alcove off to the
-- side (see PEDESTAL_SHOWCASE_* above and createPedestals below).
local GACHA_PAD_LABEL = "Gacha Pull"
local GACHA_PAD_DEBOUNCE_SECONDS = 1
local GACHA_PAD_ACCENT_COLOR = Color3.fromRGB(255, 215, 60)
-- rbxasset://sounds/bell.wav fails to load in this project ("Temp read
-- failed") - reusing DROPPER_POP_SOUND_ID's electronicpingshort.wav instead,
-- since that one's already confirmed working (it plays on every dropper pop).
local GACHA_PULL_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
-- Matches PEDESTAL_PROMPT_MAX_ACTIVATION_DISTANCE / FusionMachineService's own
-- PROMPT_MAX_ACTIVATION_DISTANCE - every ProximityPrompt in the game uses the
-- same reach so none of them feel inconsistent stood next to another.
local GACHA_PAD_PROMPT_MAX_ACTIVATION_DISTANCE = 10
-- Matches RevealEffects.lua's MAJOR_EXPLOSION_SCALE/BURST_SECONDS exactly -
-- same source pack, same "toned down to match the reveal's existing weight,
-- not overpowering it" reasoning, same MajorRevealTiers flag.
local GACHA_MAJOR_EXPLOSION_SCALE = 0.5
local GACHA_MAJOR_EXPLOSION_BURST_SECONDS = 0.25
local DROPPER_IDLE_LIGHT_BRIGHTNESS = 2
local DROPPER_IDLE_LIGHT_RANGE = 10
local DROPPER_POP_PARTICLE_BASE_COUNT = 8
-- Dropper1/Dropper2 don't produce distinct item tiers (just multiplier-scaled
-- cash), so the pop's intensity scales off the current cash multiplier
-- instead - the closest thing this system has to a "rarity" signal. Capped
-- so the effect stays "slightly bigger," not absurd, at very high multipliers.
local DROPPER_POP_SCALE_CAP = 8
local DROPPER_POP_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"

-- Pedestal Showcase: a row of empty display pedestals, one row-slot further
-- along than the Multiplier Pad, so the full row reads: Dropper1, Dropper2,
-- Multiplier Pad, Pedestal 1..N. Their own tier-specific styling is applied
-- later by PedestalVisuals (via ItemService), not here - these start bare.
-- Pedestal Showcase: a dedicated alcove off the main row (see PlotLayout.lua)
-- instead of inline with Dropper1/Dropper2/Multiplier Pad/Gacha Pad - a
-- straight line stepping into -Z at a fixed local X, so it reads as a
-- display case players walk up to on purpose. Count/spacing/position come
-- from PlotLayout (shared with FusionMachineService's connector walkway and
-- Floor's own Z sizing) rather than being redefined here, so none of them can
-- silently drift apart again. The showcase's own reach into -Z has no
-- PLOT_SLOT_SPACING_STUDS-style constraint the way the main row's X extent
-- does - plots are only ever laid out side-by-side along X (see
-- createPlotForPlayer's PivotTo), so -Z is open regardless of neighbors.
local PEDESTAL_COUNT = PlotLayout.PEDESTAL_COUNT
local PEDESTAL_SIZE = Vector3.new(PlotLayout.PEDESTAL_SIZE_X_STUDS, 3, PlotLayout.PEDESTAL_SIZE_Z_STUDS)
local PEDESTAL_SHOWCASE_X_OFFSET_STUDS = PlotLayout.PEDESTAL_SHOWCASE_X_OFFSET_STUDS
local PEDESTAL_SHOWCASE_Z_OFFSET_STUDS = PlotLayout.PEDESTAL_SHOWCASE_Z_OFFSET_STUDS
local PEDESTAL_SPACING_STUDS = PlotLayout.PEDESTAL_SPACING_STUDS
local PEDESTAL_PROMPT_MAX_ACTIVATION_DISTANCE = 10

-- Floor's original template Size (50x1x50, ~25-stud radius) predates the pad
-- row's current length: every row element is independently anchored to
-- PlotOrigin (nothing was ever actually falling), but most of the row sat
-- visually past Floor's own edge. Resized/recentered at plot-creation time
-- (see resizeFloorToFitRow) to actually cover Dropper1 through the Gacha Pad
-- on the X axis, and the Pedestal Showcase on the Z axis, with margin on
-- every edge.
--
-- Deliberately NOT extended out to the Fusion Machine too: covering it would
-- need Floor's edge to reach past local X = 107 (the machine's Base sits at
-- +95 with a 12-stud half-width), leaving under 15 studs of clearance before
-- the next plot's own Floor at PLOT_SLOT_SPACING_STUDS = 140 - recreating
-- the exact cross-plot overlap risk fixed a few turns ago. The machine
-- already has its own dedicated 24x24 Base for solid ground; it doesn't
-- depend on this plot's Floor the way the row does. A connector walkway
-- (see FusionMachineService.lua) bridges the remaining gap instead.
local FLOOR_ROW_MARGIN_STUDS = PlotLayout.FLOOR_ROW_MARGIN_STUDS

-- Slot bookkeeping: a fixed row of slots is reused as players join/leave
-- rather than growing forever.
local occupiedSlots: { [number]: boolean } = {}
local slotByUserId: { [number]: number } = {}
local plotByUserId: { [number]: Model } = {}

local function syncTycoon(player: Player)
	PlayerDataService.SyncTycoon(player)
end

local function onPassiveIncomeTick()
	for _, player in Players:GetPlayers() do
		if PlayerDataService.IsDataLoaded(player) then
			-- Generators + pedestals, with the cash multiplier applied. Same
			-- function the client HUD uses for its "+$X/s" readout.
			local cashPerSecond = PlayerDataService.GetPassiveCashPerSecond(player)
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
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PlotNaming.PlotsFolderName
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

-- The Collector alone stays anchored to the Floor's own CFrame (not
-- PlotOrigin): it has to track wherever Dropper1's cash actually falls,
-- which depends on Dropper1's own live position/rotation, not a fixed
-- reference point. This is existing, working dropper logic and is
-- intentionally left as-is - see createCollector.
local function getFloorPart(plot: Model): BasePart?
	local floor = plot:FindFirstChild("Floor", true)
	if floor and floor:IsA("BasePart") then
		return floor :: BasePart
	end
	return nil
end

local function getFloorTopY(floor: BasePart?): number
	if not floor then
		return 0
	end
	return floor.Position.Y + floor.Size.Y / 2
end

-- Everything else spawned for a plot (purchase buttons, Multiplier Pad,
-- Dropper2, Pedestals) is positioned as an offset from PlotOrigin - a fixed,
-- author-placed reference part in TycoonTemplate - rather than from Floor or
-- from wherever Dropper1's template position happens to be. This removes any
-- dependency on Floor's size/rotation or Dropper1's exact placement, which is
-- what let those offsets silently drift out of alignment before.
local function getPlotOrigin(plot: Model): BasePart?
	local origin = plot:FindFirstChild("PlotOrigin", true)
	if origin and origin:IsA("BasePart") then
		return origin :: BasePart
	end
	return nil
end

-- Resolves the (CFrame, surfaceY) every non-dropper plot layout function
-- offsets from. Falls back to Dropper1's own CFrame/Y with a warning if a
-- template is missing a PlotOrigin part, so layout degrades gracefully
-- instead of erroring outright.
local function resolvePlotOrigin(plot: Model, dropper1: BasePart, player: Player): (CFrame, number)
	local origin = getPlotOrigin(plot)
	if origin then
		return origin.CFrame, origin.Position.Y
	end
	warn(("TycoonService: PlotOrigin not found in %s's plot; add one to TycoonTemplate. Falling back to Dropper1 for layout."):format(player.Name))
	return dropper1.CFrame, dropper1.Position.Y
end

-- Snaps `part` flush onto a surface at world-Y `surfaceY` (typically
-- PlotOrigin's own Y, which the plot's author places at floor-top height)
-- without disturbing its horizontal placement or rotation, so dropped-in
-- template parts (Dropper1) and cloned ones (Dropper2) never float above or
-- clip into the floor.
local function snapToFloorY(part: BasePart, surfaceY: number)
	local position = part.Position
	part.Position = Vector3.new(position.X, surfaceY + part.Size.Y / 2, position.Z)
end

-- Repositions every SpawnLocation found anywhere in the plot (matched by
-- class, not name, so any extra/duplicate spawn point is caught too) to sit
-- just above PlotOrigin's own X/Z/surface-height, the same reference point
-- everything else in the plot uses - so it can't quietly drift out of sync
-- with the floor again the way the template's authored SpawnLocation did.
-- A plot is only ever cloned once per player per server session (see the
-- early-return in createPlotForPlayer) - if ReplicatedStorage.TycoonTemplate
-- was mid-edit or mid-Rojo-sync at that exact moment, the resulting clone can
-- be silently incomplete and will just sit that way for the rest of the
-- session, since nothing else re-clones it. This turns that into one
-- unambiguous log line at creation time instead of a much later, harder-to-
-- trace symptom (players falling through the floor, missing pads, etc).
local EXPECTED_TEMPLATE_PART_NAMES = { "Floor", "Dropper1", "ClaimButton", "PlotOrigin", "SpawnLocation" }
local function validatePlotClone(plot: Model, player: Player)
	local missing = {}
	for _, name in EXPECTED_TEMPLATE_PART_NAMES do
		if not plot:FindFirstChild(name, true) then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		warn((
			"TycoonService: %s's cloned plot is missing %s. TycoonTemplate in ReplicatedStorage was "
				.. "likely incomplete or out of sync at the exact moment this plot was cloned. A plot is "
				.. "only ever cloned once per player per server session, so fixing the template now won't "
				.. "repair this one - restart the server (or have %s leave and rejoin) after confirming the "
				.. "template is correct."
		):format(player.Name, table.concat(missing, ", "), player.Name))
	end
end

-- Resizes/recenters Floor so it actually covers Dropper1 through the Gacha
-- Pad on the X axis and the Pedestal Showcase on the Z axis, with margin,
-- rather than either extending visually past Floor's original template edge.
-- Runs at plot-creation time so Floor looks right even before the plot is
-- claimed. See the FLOOR_* constants above for why this deliberately stops
-- short of the Fusion Machine.
local function resizeFloorToFitRow(plot: Model, player: Player)
	local floor = getFloorPart(plot)
	local plotOrigin = getPlotOrigin(plot)
	if not floor or not plotOrigin then
		warn(("TycoonService: couldn't resize Floor for %s's plot - Floor or PlotOrigin missing"):format(player.Name))
		return
	end

	local rowStartLocalX = -FLOOR_ROW_MARGIN_STUDS
	-- Shared with FusionMachineService (see PlotLayout.lua) so Floor's actual
	-- right edge and the connector walkway's starting point can never drift
	-- apart the way two independently-hardcoded copies of this number could.
	local rowEndLocalX = PlotLayout.GetFloorRowEndLocalX()

	-- ClaimButton's position comes from the template (not computed by this
	-- service the way everything else in the row is), so its actual
	-- footprint is checked here rather than assumed to fit inside the
	-- default margin - it doesn't: it sits at local X = -10, and with its
	-- own half-width its edge reaches -12, past the row's usual -10 start.
	local claimButton = plot:FindFirstChild("ClaimButton", true)
	if claimButton and claimButton:IsA("BasePart") then
		local claimButtonLocal = plotOrigin.CFrame:PointToObjectSpace(claimButton.Position)
		local claimButtonLeftEdge = claimButtonLocal.X - claimButton.Size.X / 2 - FLOOR_ROW_MARGIN_STUDS
		rowStartLocalX = math.min(rowStartLocalX, claimButtonLeftEdge)
	end

	local sizeX = rowEndLocalX - rowStartLocalX
	local centerLocalX = (rowStartLocalX + rowEndLocalX) / 2

	-- Z axis mirrors the X axis logic above: a negative-side reach covering
	-- the Pedestal Showcase's last pedestal, and a positive-side margin for
	-- the main row/walkway's own width - both from PlotLayout, same reasoning
	-- as GetFloorRowEndLocalX (single source of truth, no second hardcoded copy).
	local rowStartLocalZ = PlotLayout.GetFloorRowStartLocalZ()
	local rowEndLocalZ = PlotLayout.GetFloorRowEndLocalZ()
	local sizeZ = rowEndLocalZ - rowStartLocalZ
	local centerLocalZ = (rowStartLocalZ + rowEndLocalZ) / 2

	floor.Size = Vector3.new(sizeX, floor.Size.Y, sizeZ)

	-- Only X/Z move (recentering to cover the row); Y is left exactly as
	-- authored, since Floor's top surface already matches PlotOrigin's own Y
	-- and Size.Y (thickness) isn't changing.
	local centerWorldPosition = plotOrigin.CFrame:PointToWorldSpace(Vector3.new(centerLocalX, 0, centerLocalZ))
	floor.Position = Vector3.new(centerWorldPosition.X, floor.Position.Y, centerWorldPosition.Z)
end

-- Runs at plot-creation time (before the plot is even claimed), since a
-- player's very first spawn can happen before they've touched ClaimButton -
-- fixing this only on claim would be too late for that first spawn.
local function fixSpawnLocations(plot: Model, player: Player)
	local plotOrigin = getPlotOrigin(plot)
	if not plotOrigin then
		warn(("TycoonService: PlotOrigin not found in %s's plot; can't reposition SpawnLocation(s)"):format(player.Name))
		return
	end

	local fixedCount = 0
	for _, descendant in plot:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			local spawn = descendant :: SpawnLocation
			spawn.Position = Vector3.new(
				plotOrigin.Position.X,
				plotOrigin.Position.Y + SPAWN_LOCATION_CLEARANCE_STUDS + spawn.Size.Y / 2,
				plotOrigin.Position.Z
			)
			fixedCount += 1
		end
	end

	if fixedCount == 0 then
		warn(("TycoonService: no SpawnLocation found in %s's plot"):format(player.Name))
	elseif fixedCount > 1 then
		warn(("TycoonService: %d SpawnLocations found in %s's plot (expected 1) - all repositioned relative to PlotOrigin"):format(fixedCount, player.Name))
	end
end

-- Shared billboard format for every purchase button/pad so they all read the
-- same way: the item name on top, its cost (or current tier) underneath.
local function setPurchaseLabelText(label: TextLabel, itemName: string, detail: string)
	label.Text = ("%s\n%s"):format(itemName, detail)
end

-- Awards a Collector pickup's worth of cash and pushes an immediate balance sync.
local function awardCash(player: Player, amount: number)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end
	PlayerDataService.AddCash(player, amount)
	syncTycoon(player)
end

-- Subtle always-on "idle" feedback for a producing dropper: a soft glow that
-- gently pulses. Deliberately doesn't bob the dropper's own Position/CFrame
-- (unlike PadStyler's floating accent orb) since spawnCashPart and the
-- Collector's forward-offset both read dropper.Position/CFrame live on every
-- drop - a decorative element gets the motion instead of the dropper itself.
-- Safe to call more than once (e.g. Dropper2 inherits Dropper1's elements via
-- Clone()): clears anything from a previous call first.
local function applyDropperIdleVisuals(dropper: BasePart)
	local existingElements = dropper:FindFirstChild("DropperIdleElements")
	if existingElements then
		existingElements:Destroy()
	end
	local existingLight = dropper:FindFirstChild("DropperIdleLight")
	if existingLight then
		existingLight:Destroy()
	end

	local elements = Instance.new("Folder")
	elements.Name = "DropperIdleElements"
	elements.Parent = dropper

	local highlight = Instance.new("Highlight")
	highlight.Name = "DropperIdleHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = DROPPER_ACCENT_COLOR
	highlight.OutlineTransparency = 0.3
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = elements

	local light = Instance.new("PointLight")
	light.Name = "DropperIdleLight"
	light.Color = DROPPER_ACCENT_COLOR
	light.Brightness = DROPPER_IDLE_LIGHT_BRIGHTNESS
	light.Range = DROPPER_IDLE_LIGHT_RANGE
	light.Parent = dropper

	TweenService:Create(
		highlight,
		TweenInfo.new(DROPPER_IDLE_PULSE_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ OutlineTransparency = 0.85 }
	):Play()
end

-- Brief "pop" the moment a dropper ejects a cash item: a small particle
-- burst plus a one-shot sound, scaled mildly by the current cash multiplier
-- (see DROPPER_POP_SCALE_CAP) so bigger payouts feel a little bigger too -
-- purely cosmetic, doesn't touch the cash value itself.
local function playDropperPopEffect(dropper: BasePart, multiplier: number)
	local scale = math.min(multiplier, DROPPER_POP_SCALE_CAP)

	local burst = SparkleEmitter.Create({ Color = DROPPER_ACCENT_COLOR })
	burst.Enabled = false
	burst.Parent = dropper
	burst:Emit(math.floor(DROPPER_POP_PARTICLE_BASE_COUNT * scale))
	Debris:AddItem(burst, 2)

	local sound = Instance.new("Sound")
	sound.SoundId = DROPPER_POP_SOUND_ID
	sound.Volume = 0.35
	sound.PlaybackSpeed = 1 + math.min((scale - 1) * 0.05, 0.3)
	sound.Parent = dropper
	sound:Play()
	Debris:AddItem(sound, 2)
end

-- Spawns an unanchored, collidable cash part above Dropper1 so it physically
-- falls; collection happens on contact with the plot's Collector pad, not by
-- the player touching the falling part directly. Its value is scaled by the
-- player's current Multiplier Pad level at spawn time, so items already in
-- flight aren't retroactively changed by a purchase made after they dropped.
local function spawnCashPart(plot: Model, dropper: BasePart, player: Player)
	local multiplier = TycoonConfig.GetCashMultiplierValue(PlayerDataService.GetCashMultiplierLevel(player))
	playDropperPopEffect(dropper, multiplier)

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
	cashPart:SetAttribute("CashValue", TycoonConfig.DropperCashValue * multiplier)
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
	local floor = getFloorPart(plot)
	local floorTopY = getFloorTopY(floor)
	if floor then
		floor.CollisionGroup = PLOT_ENVIRONMENT_COLLISION_GROUP
	end

	-- Offset along the Floor's facing direction (not the dropper's own
	-- rotation): cash spawns above the dropper and lands on open floor first,
	-- then travels to the Collector rather than dropping straight onto it.
	local forward = if floor then floor.CFrame.LookVector else dropper.CFrame.LookVector
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
		RemoteEvents.CashCollected:FireClient(player, {
			Amount = value,
			Position = collector.Position + Vector3.new(0, collector.Size.Y / 2 + 1, 0),
		})
	end)

	return collector
end

-- Self-terminating: the loop exits once the plot is destroyed (Parent becomes nil).
-- `dropper` must already be resolved by the caller, since this is shared by
-- both Dropper1 (found in the template) and Dropper2 (spawned on purchase).
local function startDropperLoop(plot: Model, player: Player, dropper: BasePart, _dropperLabel: string)
	applyDropperIdleVisuals(dropper)
	createCollector(plot, dropper, player)

	task.spawn(function()
		while plot.Parent do
			task.wait(TycoonConfig.DropperIntervalSeconds)
			if not plot.Parent then
				break
			end
			spawnCashPart(plot, dropper, player)
		end
	end)
end

-- Clones Dropper1's appearance to build Dropper2, positioned as an offset
-- from PlotOrigin (see resolvePlotOrigin) rather than relative to Dropper1's
-- own CFrame, then starts it producing cash the same way.
local function spawnDropper2(plot: Model, player: Player, referenceDropper: BasePart)
	local originCFrame, originY = resolvePlotOrigin(plot, referenceDropper, player)
	local worldPosition = originCFrame:PointToWorldSpace(Vector3.new(DROPPER2_SIDE_OFFSET_STUDS, 0, 0))

	local dropper2 = referenceDropper:Clone()
	dropper2.Name = "Dropper2"
	dropper2.Anchored = true
	-- Keep Dropper1's own facing (so cash-fling direction and the Collector's
	-- forward offset behave identically), just relocated via PlotOrigin.
	dropper2.CFrame = CFrame.new(worldPosition) * referenceDropper.CFrame.Rotation
	-- Explicit styling rather than whatever Dropper2 would otherwise inherit
	-- from cloning Dropper1. Neon (not Metal - see the comment on
	-- connectClaimButton for why Metal reads dark regardless of Color3)
	-- guarantees the accent color actually shows up under this game's lighting.
	dropper2.Material = Enum.Material.Neon
	dropper2.Color = DROPPER_ACCENT_COLOR
	dropper2.Parent = plot
	snapToFloorY(dropper2, originY)

	startDropperLoop(plot, player, dropper2, "Dropper2")
end

-- Spawns a purchase button (at the spot Dropper2 will occupy) that, once
-- bought by the plot owner, deducts DROPPER2_COST and spawns Dropper2.
-- Positioned as an offset from PlotOrigin (see resolvePlotOrigin) so buttons
-- line up neatly in a row regardless of Floor's own size/rotation, even as
-- more are added in the future.
local function createPurchaseButton(plot: Model, player: Player, dropper1: BasePart)
	local originCFrame, originY = resolvePlotOrigin(plot, dropper1, player)
	local buttonWorldPosition = originCFrame:PointToWorldSpace(Vector3.new(DROPPER2_SIDE_OFFSET_STUDS, 0, 0))

	local button = Instance.new("Part")
	button.Name = "BuyDropper2Button"
	button.Size = Vector3.new(4, 1, 4)
	button.Anchored = true
	button.CanCollide = true
	button.Position = Vector3.new(buttonWorldPosition.X, originY + button.Size.Y / 2, buttonWorldPosition.Z)
	button.Parent = plot
	PadStyler.Apply(button, { AccentColor = Color3.fromRGB(60, 160, 255) })

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 60)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.MaxDistance = BILLBOARD_MAX_VISIBLE_DISTANCE_STUDS
	billboard.AlwaysOnTop = true
	billboard.Parent = button

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	setPurchaseLabelText(label, DROPPER2_LABEL, NumberFormat.Money(DROPPER2_COST))
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
		PlayerDataService.SetHasDropper2(player, true)
		syncTycoon(player)
		button:Destroy()

		spawnDropper2(plot, player, dropper1)
	end)
end

-- Gacha Pad: rolls a tier from FusionConfig.GachaRates, then a random item
-- of that tier. The pull price rises with every pull.
local gachaRng = Random.new()

local function createGachaPad(plot: Model, player: Player, dropper1: BasePart)
	local originCFrame, originY = resolvePlotOrigin(plot, dropper1, player)
	local rowOffset = PlotLayout.GACHA_PAD_ROW_OFFSET_STUDS
	local padWorldPosition = originCFrame:PointToWorldSpace(Vector3.new(rowOffset, 0, 0))

	local pad = Instance.new("Part")
	pad.Name = "GachaPad"
	pad.Size = Vector3.new(PlotLayout.GACHA_PAD_SIZE_X_STUDS, 1, PlotLayout.GACHA_PAD_SIZE_X_STUDS)
	pad.Anchored = true
	pad.CanCollide = true
	pad.Position = Vector3.new(padWorldPosition.X, originY + pad.Size.Y / 2, padWorldPosition.Z)
	pad.Parent = plot
	PadStyler.Apply(pad, { AccentColor = GACHA_PAD_ACCENT_COLOR })

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 60)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.MaxDistance = BILLBOARD_MAX_VISIBLE_DISTANCE_STUDS
	billboard.AlwaysOnTop = true
	billboard.Parent = pad

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = billboard


	-- Prompt-gated rather than Touched-triggered: walking onto the pad no
	-- longer spends cash on its own, only an explicit key press does - the
	-- same "E to ..." pattern already used by pedestals and the Fusion
	-- Machine, and it stops a player from being charged repeatedly just for
	-- standing on or walking through the pad.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PullPrompt"
	prompt.ObjectText = "Gacha Pad"
	prompt.MaxActivationDistance = GACHA_PAD_PROMPT_MAX_ACTIVATION_DISTANCE
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	-- The price rises with every pull (TycoonConfig.GetGachaPullCost), so the
	-- label and prompt are refreshed after each one.
	local function refreshGachaLabel()
		local cost = TycoonConfig.GetGachaPullCost(PlayerDataService.GetGachaPulls(player))
		setPurchaseLabelText(label, GACHA_PAD_LABEL, ("%s per pull"):format(NumberFormat.Money(cost)))
		prompt.ActionText = ("Pull (%s)"):format(NumberFormat.Money(cost))
	end
	refreshGachaLabel()

	local debounce = false
	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		if debounce then
			return
		end
		if triggeringPlayer.UserId ~= player.UserId then
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
		refreshGachaLabel()

		local newEntry = PlayerDataService.AddItem(player, rewardItem.Id, rewardItem.Tier)
		RemoteEvents.SyncInventory:FireClient(player, PlayerDataService.GetInventory(player))

		-- World-visible VFX/sound at the pad, tinted to the rolled tier's own
		-- accent color so a Mythic pull visibly reads as rarer than a Common one.
		local tierColor = FusionConfig.TierAccentColors[resultTier] or GACHA_PAD_ACCENT_COLOR
		local burst = SparkleEmitter.Create({ Color = tierColor })
		burst.Enabled = false
		burst.Parent = pad
		burst:Emit(30)
		Debris:AddItem(burst, 3)

		-- Same MajorRevealTiers flag that drives the Fusion Machine's own
		-- major reveal (see RevealEffects.lua) - a Legendary/Mythic pull gets
		-- the same Explosion piece, scaled/timed the same way, so both major
		-- reveal moments in the game carry equivalent weight.
		if explosionEffectTemplate and FusionConfig.MajorRevealTiers[resultTier] then
			ImportedEffects.Play(explosionEffectTemplate, pad.CFrame, plot, {
				Scale = GACHA_MAJOR_EXPLOSION_SCALE,
				BurstSeconds = GACHA_MAJOR_EXPLOSION_BURST_SECONDS,
			})
		end

		local sound = Instance.new("Sound")
		sound.SoundId = GACHA_PULL_SOUND_ID
		sound.Volume = 0.8
		sound.Parent = pad
		sound:Play()
		Debris:AddItem(sound, 3)

		RemoteEvents.GachaPullResult:FireClient(player, {
			Success = true,
			NewItem = newEntry,
		})

		task.wait(GACHA_PAD_DEBOUNCE_SECONDS)
		debounce = false
	end)
end

-- Multiplier Pad: each purchase moves the owner to the next of 10 fixed
-- levels (TycoonConfig.CashMultiplierLevels). The multiplier applies to all
-- income. The pad stays after buying; its label shows current -> next.
local function createMultiplierPad(plot: Model, player: Player, dropper1: BasePart)
	local originCFrame, originY = resolvePlotOrigin(plot, dropper1, player)
	local rowOffset = MULTIPLIER_PAD_ROW_OFFSET_STUDS

	-- ClaimButton's actual position isn't known until the plot is live (it
	-- comes from the template), so its clearance is checked here rather than
	-- assumed: if the pad's usual spot would land on top of it, push the pad
	-- further along the row instead.
	local claimButton = plot:FindFirstChild("ClaimButton", true)
	if claimButton and claimButton:IsA("BasePart") then
		local candidatePosition = originCFrame:PointToWorldSpace(Vector3.new(rowOffset, 0, 0))
		local horizontalClearance =
			Vector2.new(candidatePosition.X - claimButton.Position.X, candidatePosition.Z - claimButton.Position.Z).Magnitude
		if horizontalClearance < MULTIPLIER_PAD_MIN_CLAIM_BUTTON_CLEARANCE_STUDS then
			local needed = rowOffset + (MULTIPLIER_PAD_MIN_CLAIM_BUTTON_CLEARANCE_STUDS - horizontalClearance) + 4
			rowOffset = math.min(needed, MULTIPLIER_PAD_MAX_ROW_OFFSET_STUDS)
			warn((
				"TycoonService: Multiplier Pad's usual spot was too close to ClaimButton in %s's plot "
					.. "(%.1f studs, wanted >= %d) - shifted to +%d along the row instead."
			):format(player.Name, horizontalClearance, MULTIPLIER_PAD_MIN_CLAIM_BUTTON_CLEARANCE_STUDS, rowOffset))
		end
	end

	local padWorldPosition = originCFrame:PointToWorldSpace(Vector3.new(rowOffset, 0, 0))

	local pad = Instance.new("Part")
	pad.Name = "MultiplierPad"
	pad.Size = Vector3.new(4, 1, 4)
	pad.Anchored = true
	pad.CanCollide = true
	pad.Position = Vector3.new(padWorldPosition.X, originY + pad.Size.Y / 2, padWorldPosition.Z)
	pad.Parent = plot
	PadStyler.Apply(pad, { AccentColor = Color3.fromRGB(200, 60, 255) })

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 60)
	-- Deliberately different from the Dropper2 button's billboard offset
	-- (0, 2, 0): with correctly-spaced parts this alone wouldn't matter, but
	-- it means two labels never land at the exact same relative height even
	-- if something ever pulls the parts close together again.
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.MaxDistance = BILLBOARD_MAX_VISIBLE_DISTANCE_STUDS
	billboard.AlwaysOnTop = true
	billboard.Parent = pad

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = billboard

	local function refreshLabel()
		local level = PlayerDataService.GetCashMultiplierLevel(player)
		local maxLevel = TycoonConfig.GetCashMultiplierMaxLevel()
		local currentMultiplier = TycoonConfig.GetCashMultiplierValue(level)

		if level >= maxLevel then
			setPurchaseLabelText(
				label,
				MULTIPLIER_PAD_LABEL,
				("Level %d/%d (%s) - MAX"):format(level, maxLevel, NumberFormat.Multiplier(currentMultiplier))
			)
			return
		end

		local cost = TycoonConfig.GetCashMultiplierUpgradeCost(level) :: number
		local nextMultiplier = TycoonConfig.GetCashMultiplierValue(level + 1)
		setPurchaseLabelText(
			label,
			MULTIPLIER_PAD_LABEL,
			("%s → %s  ·  %s"):format(
				NumberFormat.Multiplier(currentMultiplier),
				NumberFormat.Multiplier(nextMultiplier),
				NumberFormat.Money(cost)
			)
		)
	end

	refreshLabel()

	-- E-to-buy, same as the Gacha Pad. It used to buy on Touched, so just
	-- standing on the pad (or walking across it) spent cash every second.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UpgradePrompt"
	prompt.ActionText = "Upgrade"
	prompt.ObjectText = "Cash Multiplier"
	prompt.MaxActivationDistance = GACHA_PAD_PROMPT_MAX_ACTIVATION_DISTANCE
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad

	local debounce = false
	prompt.Triggered:Connect(function(toucher: Player)
		if debounce then
			return
		end
		if toucher.UserId ~= player.UserId then
			return
		end

		local level = PlayerDataService.GetCashMultiplierLevel(player)
		if level >= TycoonConfig.GetCashMultiplierMaxLevel() then
			prompt.Enabled = false
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

		-- World-visible VFX/sound at the pad, plus a personal screen popup for
		-- the buyer - pure feedback, no effect on the multiplier/cash logic above.
		local burst = SparkleEmitter.Create({ Color = MULTIPLIER_UPGRADE_ACCENT_COLOR })
		burst.Enabled = false
		burst.Parent = pad
		burst:Emit(MULTIPLIER_UPGRADE_BURST_COUNT)
		Debris:AddItem(burst, 3)

		-- The dedicated "LevelingUp" piece extracted from the user-supplied
		-- VFX pack - this moment previously had nothing beyond the sparkle
		-- burst above and the personal popup.
		if levelingUpEffectTemplate then
			ImportedEffects.Play(
				levelingUpEffectTemplate,
				CFrame.new(pad.Position + Vector3.new(0, pad.Size.Y / 2, 0)),
				plot
			)
		end

		local sound = Instance.new("Sound")
		sound.SoundId = MULTIPLIER_UPGRADE_SOUND_ID
		sound.Volume = 0.8
		sound.Parent = pad
		sound:Play()
		Debris:AddItem(sound, 3)

		RemoteEvents.MultiplierUpgraded:FireClient(player, {
			OldMultiplier = oldMultiplier,
			NewMultiplier = newMultiplier,
		})

		task.wait(MULTIPLIER_PAD_DEBOUNCE_SECONDS)
		debounce = false
	end)
end

-- Builds the plot's row of empty Pedestal Showcase slots (named "Pedestal1"
-- through "PedestalN" inside a "Pedestals" folder, so ItemService can look
-- one up by index without needing to know anything about plot layout).
-- Pedestals start bare; PedestalVisuals.Apply gives them tier-specific
-- styling once ItemService places an item on one.
local function createPedestals(plot: Model, player: Player, dropper1: BasePart)
	local originCFrame, originY = resolvePlotOrigin(plot, dropper1, player)

	local pedestalsFolder = Instance.new("Folder")
	pedestalsFolder.Name = "Pedestals"
	pedestalsFolder.Parent = plot

	for index = 1, PEDESTAL_COUNT do
		-- Fixed local X, stepping further into -Z per pedestal - a line
		-- receding away from the main row's own Z = 0 walkway instead of
		-- sitting inline with it.
		local localZ = PEDESTAL_SHOWCASE_Z_OFFSET_STUDS - (index - 1) * PEDESTAL_SPACING_STUDS
		local targetWorldPosition = originCFrame:PointToWorldSpace(Vector3.new(PEDESTAL_SHOWCASE_X_OFFSET_STUDS, 0, localZ))

		local pedestal = Instance.new("Part")
		pedestal.Name = "Pedestal" .. index
		pedestal.Size = PEDESTAL_SIZE
		pedestal.Anchored = true
		pedestal.CanCollide = true
		pedestal.Material = Enum.Material.Slate
		pedestal.Color = Color3.fromRGB(40, 40, 46)
		pedestal.Position = Vector3.new(targetWorldPosition.X, originY + PEDESTAL_SIZE.Y / 2, targetWorldPosition.Z)
		pedestal:SetAttribute("BaseSize", pedestal.Size)
		pedestal:SetAttribute("PedestalIndex", index)
		pedestal.Parent = pedestalsFolder

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DisplayPrompt"
		prompt.ActionText = "Display"
		prompt.ObjectText = ("Pedestal %d"):format(index)
		prompt.MaxActivationDistance = PEDESTAL_PROMPT_MAX_ACTIVATION_DISTANCE
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		-- Left disabled until the client confirms the local player has a
		-- displayable item and this specific pedestal is still empty.
		prompt.Enabled = false
		prompt.Parent = pedestal
	end

end

-- Re-applies saved pedestal displays when a returning player claims their
-- plot. Before this, displayed items kept earning after a rejoin but the
-- pedestals looked empty, so players thought their Mythic was gone.
local function restoreSavedPedestals(plot: Model, player: Player)
	local pedestalsFolder = plot:FindFirstChild("Pedestals")
	if not pedestalsFolder then
		return
	end
	for pedestalIndex, uid in PlayerDataService.GetPedestalDisplays(player) do
		local pedestal = pedestalsFolder:FindFirstChild("Pedestal" .. pedestalIndex)
		local item = uid and PlayerDataService.GetItemByUid(player, uid)
		if pedestal and pedestal:IsA("BasePart") and item then
			PedestalVisuals.Apply(pedestal, item.Tier)
		elseif uid and not item then
			-- Points at an item that no longer exists; free the slot.
			PlayerDataService.SetPedestalDisplay(player, pedestalIndex, nil)
		end
	end
end

-- Builds the "claim pod" riser beneath ClaimButton: a short, slightly wider
-- PadStyler-accented base so the whole thing reads as a small kiosk/pod
-- rather than a flat button sitting directly on the ground. Purely
-- decorative - positioned from ClaimButton's own live Position/Size, but
-- never modifies ClaimButton itself, so its Touched-based claim trigger is
-- completely unaffected.
-- Returns the floating accent orb PadStyler.Apply creates, so the caller can
-- remove just that piece once the plot is claimed - the orb's floating/
-- bobbing/pulsing/sparkle treatment reads as "still active, come look,"
-- which should stop once claiming is done, even though the riser's dark
-- base and steady glow are meant to stay as permanent plot furniture.
local function createClaimPodRiser(plot: Model, claimButton: BasePart): BasePart?
	local riser = Instance.new("Part")
	riser.Name = "ClaimPodRiser"
	riser.Size = Vector3.new(
		claimButton.Size.X + CLAIM_POD_RISER_MARGIN_STUDS * 2,
		CLAIM_POD_RISER_HEIGHT_STUDS,
		claimButton.Size.Z + CLAIM_POD_RISER_MARGIN_STUDS * 2
	)
	riser.Anchored = true
	riser.CanCollide = true
	-- Its top sits right at ClaimButton's own bottom (so the button reads as
	-- the surface on top of the riser), extending straight down from there.
	riser.Position = Vector3.new(
		claimButton.Position.X,
		claimButton.Position.Y - claimButton.Size.Y / 2 - CLAIM_POD_RISER_HEIGHT_STUDS / 2,
		claimButton.Position.Z
	)
	riser.Parent = plot

	local styleElements = PadStyler.Apply(riser, { AccentColor = CLAIM_BUTTON_COLOR })
	local orb = styleElements.Orb
	return if orb and orb:IsA("BasePart") then orb :: BasePart else nil
end

-- Returns `player`'s plot Model, or nil if they don't have one (not yet
-- joined this session, or already left). Used by ItemService to resolve a
-- pedestal request without ever trusting a client-supplied plot reference.
function TycoonService.GetPlotForPlayer(player: Player): Model?
	return plotByUserId[player.UserId]
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

	buttonPart.Material = Enum.Material.Neon
	buttonPart.Color = CLAIM_BUTTON_COLOR
	local claimPodOrb = createClaimPodRiser(plot, buttonPart)

	local connection: RBXScriptConnection
	connection = buttonPart.Touched:Connect(function(hit: BasePart)
		local toucher = getTouchingPlayer(hit)
		if not toucher then
			return
		end
		if toucher.UserId ~= player.UserId then
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

		-- The claim pod's riser (dark base + steady glow) stays as permanent
		-- plot furniture, but its floating/bobbing/pulsing accent orb reads
		-- as "still active, come look" - that part should stop once the
		-- plot is actually claimed.
		if claimPodOrb then
			claimPodOrb:Destroy()
		end

		-- Saved state (Dropper2, pedestals) is restored below, so wait for
		-- the profile if the DataStore is being slow.
		while not PlayerDataService.IsDataLoaded(player) and player.Parent do
			task.wait(0.25)
		end
		if not player.Parent or not plot.Parent then
			return
		end

		-- Recursive lookup: Dropper1 may be nested under an organizational group/folder.
		local dropper1 = plot:FindFirstChild("Dropper1", true)
		if not dropper1 or not dropper1:IsA("BasePart") then
			warn(("TycoonService: Dropper1 missing or not a BasePart in %s's plot"):format(player.Name))
			return
		end

		local dropper1Part = dropper1 :: BasePart
		dropper1Part.Anchored = true
		-- The template's own Dropper1 comes in as a default Part (Plastic,
		-- default gray) - confirmed directly from TycoonTemplate.rbxm's
		-- Material/Color3uint8 values, not a guess. Under this game's darker
		-- lighting that reads as an unstyled black cube. Neon (not Metal,
		-- which renders based on specular reflection off the environment and
		-- can look dark/muted under diffuse lighting regardless of its
		-- Color3 - confirmed as the actual cause after testing, same class
		-- of issue as the original ClaimButton visibility fix) guarantees
		-- the accent color always reads at full brightness. Styled to match
		-- Dropper2 (which already gets this explicitly since it's a part
		-- this service spawns outright) so both droppers read as the same
		-- machine rather than one styled and one default-gray.
		dropper1Part.Material = Enum.Material.Neon
		dropper1Part.Color = DROPPER_ACCENT_COLOR
		-- Dropper1's rotation (and everything about how it produces cash) is
		-- untouched template/gameplay logic, but its X/Z/height are now placed
		-- directly at PlotOrigin (offset zero) - the same reference point the
		-- buy button (+12), Multiplier Pad (+24), Gacha Pad (+52), and the
		-- Pedestal Showcase already measure their own offsets from. Dropper1
		-- was the one part
		-- still left on its old template position while everything else
		-- switched to PlotOrigin-relative offsets, which is exactly what let
		-- it visibly drift out of line with the rest of the row.
		local plotOrigin = getPlotOrigin(plot)
		if plotOrigin then
			dropper1Part.CFrame = CFrame.new(plotOrigin.Position.X, dropper1Part.Position.Y, plotOrigin.Position.Z)
				* dropper1Part.CFrame.Rotation
			snapToFloorY(dropper1Part, plotOrigin.Position.Y)
		else
			warn(("TycoonService: PlotOrigin not found in %s's plot; add one to TycoonTemplate. Falling back to Floor for Dropper1's height."):format(player.Name))
			snapToFloorY(dropper1Part, getFloorTopY(getFloorPart(plot)))
		end

		startDropperLoop(plot, player, dropper1Part, "Dropper1")
		if PlayerDataService.HasDropper2(player) then
			spawnDropper2(plot, player, dropper1Part)
		else
			createPurchaseButton(plot, player, dropper1Part)
		end
		createMultiplierPad(plot, player, dropper1Part)
		createPedestals(plot, player, dropper1Part)
		restoreSavedPedestals(plot, player)
		createGachaPad(plot, player, dropper1Part)
		syncTycoon(player)
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
	plot.Name = PlotNaming.GetPlotName(player.UserId)
	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("Claimed", false)
	plot.Parent = getPlotsFolder()

	if plot:IsA("Model") then
		validatePlotClone(plot :: Model, player)

		local plotModel = plot :: Model
		-- Without an explicit PrimaryPart, Model:PivotTo pivots around the
		-- model's bounding-box center - an unpredictable point that depends on
		-- every part in the template, not on PlotOrigin. Anchoring the pivot
		-- to PlotOrigin itself means PlotOrigin lands at EXACTLY
		-- ((slotIndex - 1) * PLOT_SLOT_SPACING_STUDS, 0, 0) for every plot,
		-- making the whole plot's world placement - not just this service's
		-- own pad layout - fully deterministic relative to PlotOrigin.
		local plotOrigin = plotModel:FindFirstChild("PlotOrigin", true)
		if plotOrigin and plotOrigin:IsA("BasePart") then
			plotModel.PrimaryPart = plotOrigin :: BasePart
		else
			warn(("TycoonService: PlotOrigin not found in %s's plot; add one to TycoonTemplate. Plot placement will pivot around the model's bounding-box center instead."):format(player.Name))
		end
		plotModel:PivotTo(CFrame.new((slotIndex - 1) * PLOT_SLOT_SPACING_STUDS, 0, 0))
		resizeFloorToFitRow(plotModel, player)
		fixSpawnLocations(plotModel, player)

		-- Every plot gets its own Fusion Machine (it used to be one shared
		-- machine next to slot 1 only).
		local originPart = getPlotOrigin(plotModel)
		if originPart then
			FusionMachineService.Build(originPart.CFrame, originPart.Position.Y, plotModel)
		end
	else
		warn("TycoonService: TycoonTemplate is not a Model, so plots cannot be repositioned and will overlap")
	end

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
end

function TycoonService:Start()
	FusionMachineService = require(script.Parent.FusionMachineService)
end

return TycoonService
