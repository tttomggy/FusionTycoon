--!strict
--[[
	ServiceManager
	--------------
	Loads every service ModuleScript once, then drives two lifecycle phases
	across all of them:

	    require all  ->  :Init() all  ->  :Start() all

	See ServiceTemplate.lua for the contract each service is expected to
	honour. The short version: :Init() is self-contained setup, :Start() is
	where cross-service references are allowed to be resolved.

	Compatible with services that still use the older `function S.Init()`
	(dot) form: every service's Init is zero-argument, so calling it as
	`service:Init()` simply passes a `self` the legacy function ignores. That
	lets services migrate to the `:Init()` form one at a time instead of
	needing a single big-bang rewrite.

	Failures are isolated per service per phase: one service erroring during
	Init cannot prevent the remaining services from initialising. The error is
	surfaced loudly rather than swallowed.
]]

local ServiceManager = {}

export type Service = {
	Name: string?,
	Init: ((any) -> ())?,
	Start: ((any) -> ())?,
	Stop: ((any) -> ())?,
}

-- Modules whose name ends in this are scaffolding, not runnable services.
local TEMPLATE_SUFFIX = "Template"

-- Explicit boot order, preserved exactly from the hand-maintained Bootstrap
-- this manager replaced. It is deliberately NOT alphabetical auto-discovery:
-- the previous order was hand-tuned, and silently reordering Init calls
-- during a refactor is how you introduce a bug nobody can trace later.
--
-- Once every service honours the Init/Start contract (no cross-service work
-- in Init), this list stops mattering and can be deleted. Until then, treat
-- it as load-bearing. Any service NOT listed here is still loaded - it just
-- runs after the listed ones, in Explorer order.
local INIT_ORDER: { string } = {
	"LightingService",
	"FusionMachineService",
	"PlayerDataService",
	"FusionService",
	"TycoonService",
	"ItemService",
	"DebugService",
}

local loadedByName: { [string]: any } = {}
local orderedNames: { string } = {}
local hasLoaded = false

local function isTemplate(name: string): boolean
	return #name > #TEMPLATE_SUFFIX and string.sub(name, -#TEMPLATE_SUFFIX) == TEMPLATE_SUFFIX
end

local function loadService(module: ModuleScript)
	if loadedByName[module.Name] then
		return
	end

	local ok, result = pcall(require, module)
	if not ok then
		warn(("ServiceManager: failed to require %s - %s"):format(module.Name, tostring(result)))
		return
	end

	if typeof(result) ~= "table" then
		warn(("ServiceManager: %s did not return a table (got %s) - skipping"):format(module.Name, typeof(result)))
		return
	end

	loadedByName[module.Name] = result
	table.insert(orderedNames, module.Name)
end

-- Runs one lifecycle phase across every loaded service, in boot order.
-- A service that doesn't define the phase is skipped silently - both
-- lifecycle methods are optional by design.
local function runPhase(phaseName: string)
	for _, name in orderedNames do
		local service = loadedByName[name]
		local method = service[phaseName]

		if typeof(method) == "function" then
			local ok, err = pcall(method, service)
			if not ok then
				warn(("ServiceManager: %s:%s() errored - %s"):format(name, phaseName, tostring(err)))
			end
		end
	end
end

--[[ Public API ----------------------------------------------------------- ]]

-- Requires every service ModuleScript under `container`, honouring
-- INIT_ORDER first and then appending anything not listed.
function ServiceManager.Load(container: Instance)
	if hasLoaded then
		warn("ServiceManager: Load called more than once - ignoring")
		return
	end
	hasLoaded = true

	for _, name in INIT_ORDER do
		local module = container:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			loadService(module)
		else
			warn(("ServiceManager: %s is listed in INIT_ORDER but was not found"):format(name))
		end
	end

	-- Anything added to the folder without being listed above still loads,
	-- so a new service can't silently do nothing just because someone forgot
	-- to touch this file.
	for _, child in container:GetChildren() do
		if child:IsA("ModuleScript") and not isTemplate(child.Name) then
			loadService(child)
		end
	end
end

-- Runs Init across all services, then Start across all services. Kept
-- separate from Load so tests can load services without booting them.
function ServiceManager.Start()
	runPhase("Init")
	runPhase("Start")

	print(("ServiceManager: %d services booted (%s)"):format(#orderedNames, table.concat(orderedNames, ", ")))
end

return ServiceManager
