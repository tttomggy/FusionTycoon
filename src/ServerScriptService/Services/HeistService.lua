--!strict
--[[
	HeistService
	------------
	Stealing displayed items, and the lab shield (numbers in HeistConfig).

	Shield
	  * Per player, until a server time (workspace:GetServerTimeNow()). It is
	    published as the plot attribute ShieldUntil so every client renders
	    the fence without a remote.
	  * Raised for ClaimShieldSeconds on claim, ShieldSeconds when the owner
	    stands on their YOURS pad (the claimed claim station) while it's
	    down, and VictimShieldSeconds after losing an item.
	  * While up, a loop every EjectTickSeconds moves any non-owner whose
	    root is inside the plot's walls to the street in front of its gate.

	Protection
	  * A lab whose owner is under HeistConfig.MinRebirths can't be stolen
	    from at all (plot attribute Protected; the sign shows a PROTECTED
	    pill). /stealable lifts it in Studio for testing.

	Follows ServiceTemplate:
	  :Init()   own state and PlayerRemoving.
	  :Start()  resolves PlayerDataService and TycoonService, starts the loop.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)

--[[ Types ---------------------------------------------------------------- ]]

type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
type TycoonServiceModule = typeof(require(script.Parent.TycoonService))

type State = {
	connections: { RBXScriptConnection },
	-- Server time (GetServerTimeNow) each player's shield is up until.
	shieldUntil: { [number]: number },
	-- os.clock() each player's thief cooldown ends.
	cooldownUntil: { [number]: number },
	-- os.clock() of each victim's recent losses (pruned to LossWindowSeconds).
	recentLosses: { [number]: { number } },
	-- Plots seen claimed (the claim shield is raised once, on the change).
	claimSeen: { [number]: boolean },
	-- os.clock() of each owner's last shield-pad activation.
	lastPadAt: { [number]: number },
	-- Studio /stealable: lab stealable even under MinRebirths.
	debugStealable: { [number]: boolean },
	running: boolean,
}

--[[ Private state -------------------------------------------------------- ]]

local state: State = {
	connections = {},
	shieldUntil = {},
	cooldownUntil = {},
	recentLosses = {},
	claimSeen = {},
	lastPadAt = {},
	debugStealable = {},
	running = false,
}

-- Resolved in :Start(), never at module scope.
local PlayerDataService: PlayerDataServiceModule
local TycoonService: TycoonServiceModule

local HeistService = {}

HeistService.Name = "HeistService"

--[[ Private helpers ------------------------------------------------------ ]]

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The player's claimed plot and its origin, or nil.
local function getClaimedPlot(player: Player): (Model?, CFrame?)
	local plot = TycoonService.GetPlotForPlayer(player)
	if not plot or plot:GetAttribute("Claimed") ~= true then
		return nil, nil
	end
	local origin = plot.PrimaryPart
	if not origin then
		return nil, nil
	end
	return plot, origin.CFrame
end

local function isInsidePlot(origin: CFrame, position: Vector3): boolean
	return PlotLayout.IsInsidePlot(origin:PointToObjectSpace(position))
end

-- The street in front of the plot's gate (its SpawnLocation), plus clearance.
local function getEjectCFrame(plot: Model): CFrame?
	local spawn = plot:FindFirstChildWhichIsA("SpawnLocation", true)
	if not spawn then
		return nil
	end
	return spawn.CFrame + Vector3.new(0, spawn.Size.Y / 2 + PlotLayout.SPAWN_CHARACTER_CLEARANCE, 0)
end

local function pruneLosses(userId: number)
	local losses = state.recentLosses[userId]
	if not losses then
		return
	end
	local cutoff = os.clock() - HeistConfig.LossWindowSeconds
	for index = #losses, 1, -1 do
		if losses[index] < cutoff then
			table.remove(losses, index)
		end
	end
end

--[[ Public API: shield and protection ------------------------------------ ]]

-- Raises `player`'s shield for `seconds` from now (0 drops it).
function HeistService.RaiseShield(player: Player, seconds: number)
	local untilTime = if seconds > 0 then serverNow() + seconds else 0
	state.shieldUntil[player.UserId] = untilTime
	local plot = TycoonService.GetPlotForPlayer(player)
	if plot then
		plot:SetAttribute("ShieldUntil", untilTime)
	end
end

function HeistService.IsShielded(player: Player): boolean
	return (state.shieldUntil[player.UserId] or 0) > serverNow()
end

-- Under MinRebirths (and not /stealable): nobody can steal from this lab.
function HeistService.IsProtected(player: Player): boolean
	if state.debugStealable[player.UserId] then
		return false
	end
	return PlayerDataService.GetRebirths(player) < HeistConfig.MinRebirths
end

-- The 10-minute loss cap is hit: unstealable until a loss ages out.
function HeistService.IsLossCapped(player: Player): boolean
	pruneLosses(player.UserId)
	local losses = state.recentLosses[player.UserId]
	return losses ~= nil and #losses >= HeistConfig.LossCap
end

-- Studio /heistcd: clears the thief cooldown.
function HeistService.ClearCooldown(player: Player)
	state.cooldownUntil[player.UserId] = nil
end

-- Studio /stealable: toggles stealable-at-Rebirth-0 for this player's lab.
function HeistService.SetDebugStealable(player: Player, stealable: boolean)
	if stealable then
		state.debugStealable[player.UserId] = true
	else
		state.debugStealable[player.UserId] = nil
	end
end

--[[ Loop: claim shield, shield pad, protection, eject --------------------- ]]

local function onPadCheck(player: Player, origin: CFrame)
	local root = getRoot(player)
	if not root or HeistService.IsShielded(player) or HeistService.IsProtected(player) then
		return
	end
	local offset = origin:PointToObjectSpace(root.Position) - PlotLayout.CLAIM_STATION
	local radius = PlotLayout.Station.PadDiameter / 2
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > radius or math.abs(offset.Y) > PlotLayout.Station.LabelOffsetY then
		return
	end
	local now = os.clock()
	local last = state.lastPadAt[player.UserId]
	if last and now - last < HeistConfig.ShieldPadDebounceSeconds then
		return
	end
	state.lastPadAt[player.UserId] = now
	HeistService.RaiseShield(player, HeistConfig.ShieldSeconds)
end

local function ejectIntruders(owner: Player, plot: Model, origin: CFrame)
	local target: CFrame? = nil
	for _, other in Players:GetPlayers() do
		if other ~= owner then
			local root = getRoot(other)
			if root and isInsidePlot(origin, root.Position) then
				target = target or getEjectCFrame(plot)
				local character = other.Character
				if target and character then
					character:PivotTo(target)
				end
			end
		end
	end
end

local function tick()
	for _, player in Players:GetPlayers() do
		if PlayerDataService.IsDataLoaded(player) then
			local plot, origin = getClaimedPlot(player)
			if plot and origin then
				if not state.claimSeen[player.UserId] then
					state.claimSeen[player.UserId] = true
					HeistService.RaiseShield(player, HeistConfig.ClaimShieldSeconds)
				end
				local protected = HeistService.IsProtected(player)
				if plot:GetAttribute("Protected") ~= protected then
					plot:SetAttribute("Protected", protected)
				end
				onPadCheck(player, origin)
				-- A protected lab needs no eject: nothing there can be stolen.
				if not protected and HeistService.IsShielded(player) then
					ejectIntruders(player, plot, origin)
				end
			end
		end
	end
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	state.shieldUntil[userId] = nil
	state.cooldownUntil[userId] = nil
	state.recentLosses[userId] = nil
	state.claimSeen[userId] = nil
	state.lastPadAt[userId] = nil
	state.debugStealable[userId] = nil
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function HeistService:Init()
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

function HeistService:Start()
	PlayerDataService = require(script.Parent.PlayerDataService)
	TycoonService = require(script.Parent.TycoonService)

	state.running = true
	task.spawn(function()
		while state.running do
			task.wait(HeistConfig.EjectTickSeconds)
			tick()
		end
	end)
end

function HeistService:Stop()
	state.running = false
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
end

return HeistService
