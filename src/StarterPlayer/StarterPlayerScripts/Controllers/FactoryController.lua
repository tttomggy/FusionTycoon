--[[
	FactoryController
	-----------------
	The factory line's cash balls: a client-side PICTURE of generator income.
	The money itself is paid by the server's passive tick
	(TycoonConfig.GetPassiveCashPerSecond); balls never touch cash, so
	nothing is lost to physics and the server does no ball work.

	For every claimed plot within ACTIVE_RADIUS of the camera (yours and
	other players', so the street looks alive), each owned generator drops a
	ball every lerp(2.0, 0.5, (level - 1) / 24) seconds:

	  1. a 0.35 s arc from its Spout onto the belt's centre line,
	  2. a ride toward -Z at FactoryBelt.Speed to the belt's end,
	  3. a 0.2 s drop into the collector's centre, shrinking to nothing.

	Balls are Neon, tier-coloured and tier-sized (PlotLayout.FactoryBall),
	pooled, anchored and moved by CFrame with one BulkMoveTo per frame. At
	most MAX_BALLS_PER_PLOT live per plot; a ball skipped at the cap still
	counts toward the pops.

	Your own plot only: each arriving ball adds income/s x multiplier x
	interval to a running total, popped as one "+$X" over the collector
	every POP_WINDOW seconds. Pedestal income has no balls, so each of your
	filled pedestals within PEDESTAL_POP_RADIUS pops its own "+$X" (income
	x multiplier x PEDESTAL_POP_SECONDS) over its orb every
	PEDESTAL_POP_SECONDS. Collector + pedestal pops together add up to the
	HUD's income.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local GeneratorKit = require(ReplicatedStorage.Shared.Modules.GeneratorKit)
local FactoryKit = require(ReplicatedStorage.Shared.Modules.FactoryKit)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local TycoonController = require(script.Parent.TycoonController)
local InventoryController = require(script.Parent.InventoryController)
local HudController = require(script.Parent.HudController)

local FactoryController = {}

local INTERVAL_AT_LV1 = 2.0
local INTERVAL_AT_MAX = 0.5
local ARC_SECONDS = 0.35
local DROP_SECONDS = 0.2
local POP_WINDOW = 0.5
local MAX_BALLS_PER_PLOT = 60
local SURGE_BALL_WHITEN = 0.35 -- Power Surge: balls this far toward white
local ACTIVE_RADIUS = 120
local PARKED = CFrame.new(0, -1000, 0) -- where pooled balls wait, out of sight
local PEDESTAL_POP_SECONDS = 2
local PEDESTAL_POP_RADIUS = 60
local PEDESTAL_POP_ABOVE_ORB = 1

type Ball = {
	Part: BasePart,
	Diameter: number,
	Start: Vector3, -- world: the spout opening
	Land: Vector3, -- world: on the belt, level with the generator
	RideEnd: Vector3, -- world: the belt's back end
	DropEnd: Vector3, -- world: the collector's centre
	SpawnedAt: number,
	RideSeconds: number,
	Value: number, -- 0 on other players' plots (no pops there)
	Tier: string,
}

type PlotState = {
	Model: Model,
	Origin: CFrame,
	IsOwn: boolean,
	Balls: { Ball },
	NextSpawn: { [string]: number },
}

local localPlayer = Players.LocalPlayer
local ballFolder: Folder
local pool: { BasePart } = {}
local plots: { [Model]: PlotState } = {}

local movedParts: { BasePart } = {}
local movedCFrames: { CFrame } = {}

local pendingValue = 0
local pendingTier: string? = nil
local popClock = 0
local pedestalPopClock = 0

--[[ Pool ------------------------------------------------------------------------ ]]

local function acquireBall(tier: string, pink: boolean?): (BasePart, number)
	local b = PlotLayout.FactoryBall
	local diameter = b.Diameter[tier] or b.Diameter.Common
	local part = table.remove(pool)
	if not part then
		local new = Instance.new("Part")
		new.Name = "CashBall"
		new.Shape = Enum.PartType.Ball
		new.Material = Enum.Material.Neon
		new.Anchored = true
		new.CanCollide = false
		new.CanQuery = false
		new.CanTouch = false
		new.CastShadow = false
		new.CFrame = PARKED
		local light = Instance.new("PointLight")
		light.Name = "BallLight"
		light.Range = b.LightRange
		light.Brightness = b.LightBrightness
		light.Enabled = false
		light.Parent = new
		new.Parent = ballFolder
		part = new
	end
	local ball = part :: BasePart
	-- The Neon Pink Lab (LabStyle) skins that lab's balls pink.
	local color = if pink then UITheme.World.AccentPink else FusionConfig.TierAccentColors[tier] or UITheme.World.AccentGold
	ball.Size = Vector3.one * diameter
	-- Power Surge: brighter balls (toward white; no light is raised).
	ball.Color = if EventState.GetGeneratorMultiplier() > 1 then color:Lerp(UITheme.Colors.White, SURGE_BALL_WHITEN) else color
	local light = ball:FindFirstChild("BallLight") :: PointLight?
	if light then
		light.Color = color
		light.Enabled = b.LightTiers[tier] == true
	end
	return ball, diameter
end

local function releaseBall(part: BasePart)
	part.CFrame = PARKED
	local light = part:FindFirstChild("BallLight") :: PointLight?
	if light then
		light.Enabled = false
	end
	table.insert(pool, part)
end

local function clearPlot(state: PlotState)
	for _, ball in state.Balls do
		releaseBall(ball.Part)
	end
	table.clear(state.Balls)
	table.clear(state.NextSpawn)
end

--[[ Plots ------------------------------------------------------------------------ ]]

local function trackPlot(model: Instance)
	if not model:IsA("Model") or plots[model] then
		return
	end
	local slot = model:GetAttribute("SlotIndex")
	if typeof(slot) ~= "number" then
		return
	end
	plots[model] = {
		Model = model,
		Origin = PlotLayout.GetSlotCFrame(slot),
		IsOwn = model.Name == PlotNaming.GetPlotName(localPlayer.UserId),
		Balls = {},
		NextSpawn = {},
	}
end

local function untrackPlot(model: Instance)
	local state = plots[model :: Model]
	if state then
		clearPlot(state)
		plots[model :: Model] = nil
	end
end

local function getInterval(level: number): number
	local t = math.clamp((level - 1) / 24, 0, 1)
	return INTERVAL_AT_LV1 + (INTERVAL_AT_MAX - INTERVAL_AT_LV1) * t
end

local function tierRank(tier: string?): number
	return if tier then ItemConfig.Tiers[tier] or 0 else 0
end

local function addPending(value: number, tier: string)
	pendingValue += value
	if tierRank(tier) > tierRank(pendingTier) then
		pendingTier = tier
	end
end

local function spawnBall(state: PlotState, generator: TycoonConfig.GeneratorDef, spot: PlotLayout.GeneratorSpot, value: number)
	local origin = state.Origin
	local part, diameter = acquireBall(generator.Tier, state.Model:GetAttribute("LabStyle") == true)
	local radius = diameter / 2
	local bodyCenter = Vector3.new(spot.Position.X, spot.Height / 2, spot.Position.Z)
	local belt = PlotLayout.FactoryBelt
	local collectorTop = FactoryKit.GetCollectorTop()
	table.insert(state.Balls, {
		Part = part,
		Diameter = diameter,
		Start = origin:PointToWorldSpace(bodyCenter + GeneratorKit.GetSpoutOffset(spot)),
		Land = origin:PointToWorldSpace(FactoryKit.GetBeltPoint(spot.Position.Z) + Vector3.new(0, radius, 0)),
		RideEnd = origin:PointToWorldSpace(FactoryKit.GetBeltPoint(belt.EndZ) + Vector3.new(0, radius, 0)),
		DropEnd = origin:PointToWorldSpace(collectorTop),
		SpawnedAt = os.clock(),
		-- Power Surge: the belt runs faster by the generator multiplier.
		RideSeconds = (spot.Position.Z - belt.EndZ) / (belt.Speed * EventState.GetGeneratorMultiplier()),
		Value = value,
		Tier = generator.Tier,
	})
end

-- Drops the next ball for each owned generator whose interval has come up.
local function spawnDue(state: PlotState, now: number)
	local multiplier = if state.IsOwn
		then TycoonController.GetIncomeMultiplier()
		else 0
	-- Power Surge: balls drop more often and the line carries the boosted
	-- generator income (the HUD's figure, IncomeInputs.EventGeneratorMultiplier).
	local surge = EventState.GetGeneratorMultiplier()
	for _, generator in TycoonConfig.Generators do
		local spot = PlotLayout.GENERATORS[generator.Id]
		local model = state.Model:FindFirstChild(GeneratorKit.GetModelName(generator.Id))
		local level = model and model:GetAttribute("Level")
		if spot and typeof(level) == "number" and level >= 1 then
			local interval = getInterval(level) / surge
			local due = state.NextSpawn[generator.Id]
			if not due then
				-- First sight: stagger generators so they don't drop in step.
				state.NextSpawn[generator.Id] = now + interval * math.random()
			elseif now >= due then
				state.NextSpawn[generator.Id] = math.max(due + interval, now)
				local value = TycoonConfig.GetGeneratorCashPerSecond(generator, level) * multiplier * surge * interval
				if #state.Balls < MAX_BALLS_PER_PLOT then
					spawnBall(state, generator, spot, value)
				elseif state.IsOwn then
					addPending(value, generator.Tier)
				end
			end
		else
			state.NextSpawn[generator.Id] = nil
		end
	end
end

-- Positions every live ball; finished ones are pooled (and counted).
local function moveBalls(state: PlotState, now: number)
	local balls = state.Balls
	for index = #balls, 1, -1 do
		local ball = balls[index]
		local elapsed = now - ball.SpawnedAt
		local position: Vector3
		if elapsed < ARC_SECONDS then
			local u = elapsed / ARC_SECONDS
			position = ball.Start:Lerp(ball.Land, u) + Vector3.new(0, PlotLayout.FactoryBall.ArcRise * 4 * u * (1 - u), 0)
		elseif elapsed < ARC_SECONDS + ball.RideSeconds then
			position = ball.Land:Lerp(ball.RideEnd, (elapsed - ARC_SECONDS) / ball.RideSeconds)
		elseif elapsed < ARC_SECONDS + ball.RideSeconds + DROP_SECONDS then
			local u = (elapsed - ARC_SECONDS - ball.RideSeconds) / DROP_SECONDS
			position = ball.RideEnd:Lerp(ball.DropEnd, u)
			ball.Part.Size = Vector3.one * math.max(ball.Diameter * (1 - u), 0.05)
		else
			if state.IsOwn then
				addPending(ball.Value, ball.Tier)
			end
			releaseBall(ball.Part)
			balls[index] = balls[#balls]
			balls[#balls] = nil
			continue
		end
		table.insert(movedParts, ball.Part)
		table.insert(movedCFrames, CFrame.new(position))
	end
end

--[[ Pops --------------------------------------------------------------------------- ]]

local function popCollector(dt: number)
	popClock += dt
	if popClock < POP_WINDOW then
		return
	end
	popClock = 0
	if pendingValue <= 0 then
		return
	end
	local own: PlotState? = nil
	for _, state in plots do
		if state.IsOwn then
			own = state
		end
	end
	if own then
		local top = FactoryKit.GetCollectorTop() + Vector3.new(0, PlotLayout.Collector.PopHeight, 0)
		-- Cash green for Common; the tier's light colour once a better
		-- tier's ball landed in this window.
		local color = if tierRank(pendingTier) > tierRank("Common") and pendingTier
			then UITheme.GetTierLight(pendingTier)
			else UITheme.Colors.Cash
		HudController.FloatPop(own.Origin:PointToWorldSpace(top), "+" .. NumberFormat.Money(pendingValue), color)
	end
	pendingValue = 0
	pendingTier = nil
end

-- Every PEDESTAL_POP_SECONDS: one pop per filled pedestal of yours near
-- the camera, over its orb, in the item's tier light colour.
local function popPedestals(dt: number, cameraPosition: Vector3)
	pedestalPopClock += dt
	if pedestalPopClock < PEDESTAL_POP_SECONDS then
		return
	end
	pedestalPopClock = 0
	local own: PlotState? = nil
	for _, state in plots do
		if state.IsOwn then
			own = state
		end
	end
	local folder = own and own.Model:FindFirstChild("Pedestals")
	if not folder then
		return
	end
	local byUid: { [string]: any } = {}
	for _, item in InventoryController.GetInventory() do
		byUid[item.Uid] = item
	end
	local multiplier = TycoonController.GetIncomeMultiplier()
	for index, uid in TycoonController.GetPedestalDisplays() do
		local item = byUid[uid]
		local pedestal = folder:FindFirstChild("Pedestal" .. index)
		local elements = pedestal and pedestal:FindFirstChild("PedestalVisualElements")
		local group = elements and elements:FindFirstChild("OrbGroup")
		local orb = group and group:FindFirstChild("Orb")
		if item and orb and orb:IsA("BasePart") and (orb.Position - cameraPosition).Magnitude <= PEDESTAL_POP_RADIUS then
			local value = TycoonConfig.GetStackCashPerSecond(item) * multiplier * PEDESTAL_POP_SECONDS
			if value > 0 then
				local top = orb.Position + Vector3.new(0, orb.Size.Y / 2 + PEDESTAL_POP_ABOVE_ORB, 0)
				HudController.FloatPop(top, "+" .. NumberFormat.Money(value), UITheme.GetTierLight(item.Tier))
			end
		end
	end
end

--[[ Frame -------------------------------------------------------------------------- ]]

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local now = os.clock()
	table.clear(movedParts)
	table.clear(movedCFrames)
	for _, state in plots do
		local active = state.Model:GetAttribute("Claimed") == true
			and (state.Origin.Position - cameraPosition).Magnitude <= ACTIVE_RADIUS
		if active then
			spawnDue(state, now)
			moveBalls(state, now)
		elseif #state.Balls > 0 or next(state.NextSpawn) then
			clearPlot(state)
		end
	end
	if #movedParts > 0 then
		Workspace:BulkMoveTo(movedParts, movedCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	popCollector(dt)
	popPedestals(dt, cameraPosition)
end

function FactoryController.Init()
	ballFolder = Instance.new("Folder")
	ballFolder.Name = "FactoryBalls" -- client-only, never replicated
	ballFolder.Parent = Workspace

	local plotsFolder = Workspace:WaitForChild(PlotNaming.PlotsFolderName)
	for _, child in plotsFolder:GetChildren() do
		trackPlot(child)
	end
	plotsFolder.ChildAdded:Connect(function(child)
		-- Attributes are set before the plot is parented, but give the
		-- replicated model a frame to settle.
		task.defer(trackPlot, child)
	end)
	plotsFolder.ChildRemoved:Connect(untrackPlot)
	RunService.RenderStepped:Connect(step)
end

return FactoryController
