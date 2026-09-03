--!strict
--[[
	ServiceTemplate
	---------------
	Copy this file to create a new server service, then delete what you don't
	need. ServiceManager deliberately SKIPS any module whose name ends in
	"Template", so this file is never loaded or Init'd at runtime.

	ServiceManager drives two phases. The split is the whole point of the
	pattern, so keep the contract:

	  :Init()   Self-contained setup ONLY. Build this service's own state and
	            connect its own event handlers. MUST NOT touch another
	            service - during Init, other services may not have Init'd yet.
	            Init order is therefore not something you may depend on.

	  :Start()  Everything cross-service. By the time Start runs, every
	            service has completed Init, so it is safe to resolve
	            references to them and call into them.

	Both are optional - omit either if a service doesn't need it.

	Why this removes a real hazard: requiring a sibling service at the top of
	a file (`local Other = require(script.Parent.OtherService)`) runs at
	module-load time and deadlocks the moment two services require each other.
	Resolving in :Start() breaks that cycle by construction.
]]

local Players = game:GetService("Players")

--[[ Remotes -------------------------------------------------------------- ]]
--
-- This project has ONE source of truth for remotes:
-- ReplicatedStorage.Shared.Network.RemoteEvents. It creates the container
-- folder on the server and makes the client WaitForChild it, so no service
-- should ever call Instance.new("RemoteEvent") directly.
--
-- To add a remote for your service:
--   1. Add its name to REMOTE_EVENT_NAMES in RemoteEvents.lua, with a comment
--      stating direction, e.g. "client -> server: attempt to do X".
--   2. Require the module at the top of your service:
--        local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
--   3. Connect it in :Init() (never at module scope), tracking the connection:
--        table.insert(
--            state.connections,
--            RemoteEvents.YourRequest.OnServerEvent:Connect(onYourRequest)
--        )
--   4. Validate every argument before use - a client can send anything.

--[[ Private state -------------------------------------------------------- ]]

-- Everything mutable lives in one explicitly-typed table that is NOT exposed
-- on the returned service, so no other module can reach in and mutate it.
-- Outside access goes through the public API below.
type State = {
	connections: { RBXScriptConnection },
	valueByUserId: { [number]: number },
}

local state: State = {
	connections = {},
	valueByUserId = {},
}

--[[ Cross-service references --------------------------------------------- ]]

-- Declared here with a type but NO value; assigned in :Start(). The
-- `typeof(require(...))` annotation is a TYPE-level reference only - it does
-- not require the module at runtime, so it cannot create a load-time cycle,
-- while still giving full type checking and autocomplete.
--
--   type PlayerDataServiceModule = typeof(require(script.Parent.PlayerDataService))
--   local PlayerDataService: PlayerDataServiceModule
--
--   function MyService:Start()
--       PlayerDataService = require(script.Parent.PlayerDataService)
--   end
--
-- Keeping the identifier's original name means call sites read identically to
-- a module-scope require, so converting an existing service is a one-line
-- change rather than a rewrite of every call site.
--
-- The window where the value is still nil is not reachable in practice:
-- ServiceManager runs Init across all services and then Start across all
-- services with no yield in between, so anything connected during Init cannot
-- be resumed until after Start has assigned these. If you add a service whose
-- :Init() YIELDS, you break that guarantee - don't.

--[[ Service -------------------------------------------------------------- ]]

local ServiceTemplate = {}

-- Used by ServiceManager for log lines and error attribution.
ServiceTemplate.Name = "ServiceTemplate"

--[[ Private helpers ------------------------------------------------------ ]]

local function onPlayerRemoving(player: Player)
	-- Session-scoped state must be released, or it leaks for the life of the
	-- server. Anything that should survive a rejoin belongs in
	-- PlayerDataService, not here.
	state.valueByUserId[player.UserId] = nil
end

--[[ Public API ----------------------------------------------------------- ]]

function ServiceTemplate.GetValue(player: Player): number
	return state.valueByUserId[player.UserId] or 0
end

function ServiceTemplate.SetValue(player: Player, value: number)
	state.valueByUserId[player.UserId] = value
end

--[[ Lifecycle ------------------------------------------------------------ ]]

function ServiceTemplate:Init()
	-- Own setup only. Track connections so :Stop() can tear them down.
	table.insert(state.connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
end

function ServiceTemplate:Start()
	-- Cross-service wiring only - every service has finished Init by now.
	--   PlayerDataService = require(script.Parent.PlayerDataService)
end

-- Optional. ServiceManager does not call this during normal boot; it exists
-- so a service can be torn down deterministically (tests, soft shutdown)
-- without leaking connections.
function ServiceTemplate:Stop()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
	table.clear(state.valueByUserId)
end

return ServiceTemplate
