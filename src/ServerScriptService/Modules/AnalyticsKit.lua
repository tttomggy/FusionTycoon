--!strict
--[[
	AnalyticsKit
	------------
	The ONE wrapper round AnalyticsService. Every call is in a pcall, so an
	analytics failure never breaks gameplay, and nothing is sent in Studio
	(each call prints "[Analytics] …" instead).

	  AnalyticsKit.Funnel(player, step)        onboarding funnel, once per
	                                           player EVER (PlayerData.Funnel,
	                                           through SetFunnelStore)
	  AnalyticsKit.Source(player, amount, kind, sku?)
	  AnalyticsKit.Sink(player, amount, kind, sku?)
	                                           LogEconomyEvent for "Cash";
	                                           kind = an
	                                           AnalyticsEconomyTransactionType
	                                           name
	  AnalyticsKit.AddIncome(player, amount)   passive income, summed and
	                                           logged once a minute
	  AnalyticsKit.Custom(player, name, value?, field?)
	                                           LogCustomEvent (+ CustomField01)

	Funnel steps (in order): Join, ClaimLab, FirstUpgrade, FirstPull,
	FirstDisplay, FirstFuse, FirstMultiplier, FirstEvent, FirstRebirth,
	FirstSteal.

	Not a service: services and PlayerDataService require it directly.
]]
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AnalyticsKit = {}

local CURRENCY = "Cash"
local INCOME_FLUSH_SECONDS = 60

AnalyticsKit.FunnelSteps = {
	"Join",
	"ClaimLab",
	"FirstUpgrade",
	"FirstPull",
	"FirstDisplay",
	"FirstFuse",
	"FirstMultiplier",
	"FirstEvent",
	"FirstRebirth",
	"FirstSteal",
}

export type FunnelStore = {
	-- true the FIRST time `step` is marked for `player` (and records it).
	Mark: (player: Player, step: string) -> boolean,
	GetBalance: (player: Player) -> number,
}

local isStudio = RunService:IsStudio()
local store: FunnelStore? = nil
local pendingIncome: { [Player]: number } = {}
local flushing = false

local function send(description: string, call: () -> ())
	if isStudio then
		print("[Analytics] " .. description)
		return
	end
	local ok, err = pcall(function()
		call()
	end)
	if not ok then
		warn(("AnalyticsKit: %s failed (%s)"):format(description, tostring(err)))
	end
end

local function balance(player: Player): number
	local current = store
	if not current then
		return 0
	end
	local ok, value = pcall(function(): number
		return current.GetBalance(player)
	end)
	return if ok and typeof(value) == "number" then value else 0
end

-- PlayerDataService hands over where funnel steps are saved and the cash
-- balance (so this module never requires a service).
function AnalyticsKit.SetFunnelStore(newStore: FunnelStore)
	store = newStore
end

function AnalyticsKit.Funnel(player: Player, step: string)
	local index = table.find(AnalyticsKit.FunnelSteps, step)
	local current = store
	if not index or not current then
		return
	end
	local ok, first = pcall(function(): boolean
		return current.Mark(player, step)
	end)
	if not ok or first ~= true then
		return
	end
	send(("funnel %d %s · %s"):format(index, step, player.Name), function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, index, step)
	end)
end

local function economy(player: Player, flow: Enum.AnalyticsEconomyFlowType, amount: number, kind: string, sku: string?)
	if amount <= 0 or amount ~= amount or amount == math.huge then
		return
	end
	local ending = balance(player)
	send(("%s %s %.0f (%s%s) · %s"):format(flow.Name, CURRENCY, amount, kind, if sku then " " .. sku else "", player.Name), function()
		AnalyticsService:LogEconomyEvent(player, flow, CURRENCY, amount, ending, kind, sku)
	end)
end

function AnalyticsKit.Source(player: Player, amount: number, kind: string, sku: string?)
	economy(player, Enum.AnalyticsEconomyFlowType.Source, amount, kind, sku)
end

function AnalyticsKit.Sink(player: Player, amount: number, kind: string, sku: string?)
	economy(player, Enum.AnalyticsEconomyFlowType.Sink, amount, kind, sku)
end

local function flushIncome()
	local batch = pendingIncome
	pendingIncome = {}
	for player, amount in batch do
		if player.Parent == Players then
			AnalyticsKit.Source(player, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "PassiveIncome")
		end
	end
end

-- Passive income ticks: summed per player, one Source event a minute.
function AnalyticsKit.AddIncome(player: Player, amount: number)
	if amount <= 0 or amount ~= amount then
		return
	end
	pendingIncome[player] = (pendingIncome[player] or 0) + amount
	if not flushing then
		flushing = true
		task.spawn(function()
			while true do
				task.wait(INCOME_FLUSH_SECONDS)
				flushIncome()
			end
		end)
	end
end

function AnalyticsKit.Custom(player: Player, name: string, value: number?, field: string?)
	local fields = if field then { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = field } else nil
	send(("custom %s%s%s · %s"):format(name, if value then " = " .. tostring(value) else "", if field then " [" .. field .. "]" else "", player.Name), function()
		AnalyticsService:LogCustomEvent(player, name, value or 1, fields)
	end)
end

-- A leaving player's unsent income is logged now (PlayerDataService's
-- release hook calls this before the player is gone).
function AnalyticsKit.Release(player: Player)
	local amount = pendingIncome[player]
	pendingIncome[player] = nil
	if amount then
		AnalyticsKit.Source(player, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "PassiveIncome")
	end
end

return AnalyticsKit
