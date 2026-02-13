--!strict
--[[
	Server Runtime Bootstrap
	
	Issue #5: Server & Client Bootstrap/Initialization Systems
	Epic: Phase 1 - Core Framework
	
	This is the server entry point. It loads and initializes all services
	in the correct order with proper dependency resolution.
	
	Initialization Sequence:
	1. Load all service modules from src/server/services/
	2. Call Init() on all services (dependency setup)
	3. Call Start() on all services (begin operations)
	4. Handle initialization errors gracefully
	
	Service Lifecycle:
	- Init(): Setup dependencies, create data structures, register handlers
	- Start(): Begin listening to events, start loops, connect signals
	
	All services should follow this pattern for consistent initialization.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Import Loader utility
local Loader = require(ReplicatedStorage.Shared.modules.Loader)

print(("="):rep(60))
print("🌙 NIGHTFALL - Server Bootstrap")
print(("="):rep(60))
print(`[Server] Execution Context: {Loader.GetContext()}`)
print(`[Server] Starting initialization sequence...`)
print("")

local INITIALIZATION_START = os.clock()

-- Step 1: Load all services
print("[Server] [1/3] Loading services...")
local servicesFolder = ServerScriptService.Server.services
local services = Loader.LoadModules(servicesFolder, false)

if not next(services) then
	error("[Server] No services found to load!")
end

print("")

-- Step 2: Initialize all services (Init method)
print("[Server] [2/3] Initializing services...")
local initSuccess = true

-- Build dependencies table for dependency injection
local dependencies = {
	NetworkService = services.NetworkService,
	DataService = services.DataService,
	StateSyncService = services.StateSyncService,
}

for name, service in services do
	if type(service) == "table" and service.Init then
		local success, err = pcall(service.Init, service, dependencies)
		
		if not success then
			warn(`[Server] ❌ Failed to initialize {name}: {err}`)
			initSuccess = false
		else
			print(`[Server] ✓ Initialized: {name}`)
		end
	end
end

if not initSuccess then
	warn("[Server] Some services failed to initialize - server may not function correctly")
end

print("")

-- Step 3: Start all services (Start method)
print("[Server] [3/3] Starting services...")
local startSuccess = true

-- Start in a specific order to handle dependencies
local startOrder = {
	"NetworkService",      -- Must start first (depended on by others)
	"StateSyncService",    -- Depends on NetworkService
	"DataService",
	"DefenseService",      -- May depend on other services
}

for _, name in startOrder do
	local service = services[name]
	if service and type(service) == "table" and service.Start then
		local success, err = pcall(service.Start, service)
		
		if not success then
			warn(`[Server] ❌ Failed to start {name}: {err}`)
			startSuccess = false
		else
			print(`[Server] ✓ Started: {name}`)
		end
	end
end

-- Start any other services not in the explicit order
for name, service in services do
	-- Skip if already started above
	local alreadyStarted = false
	for _, startedName in startOrder do
		if startedName == name then
			alreadyStarted = true
			break
		end
	end
	
	if not alreadyStarted and type(service) == "table" and service.Start then
		local success, err = pcall(service.Start, service)
		
		if not success then
			warn(`[Server] ❌ Failed to start {name}: {err}`)
			startSuccess = false
		else
			print(`[Server] ✓ Started: {name}`)
		end
	end
end

if not startSuccess then
	warn("[Server] Some services failed to start - server may not function correctly")
end

print("")

-- Initialization complete
local initTime = (os.clock() - INITIALIZATION_START) * 1000
local serviceCount = 0
for _ in services do
	serviceCount += 1
end

print(("="):rep(60))
print(`🌙 Server Bootstrap Complete`)
print(`   Services Loaded: {serviceCount}`)
print(`   Initialization Time: {math.floor(initTime * 100) / 100}ms`)
print(`   Status: {if initSuccess and startSuccess then "✓ Ready" else "⚠ Partial"}`)
print(("="):rep(60))
print("")

-- Export services for debugging (optional)
_G.Services = services

-- Handle server shutdown gracefully
game:BindToClose(function()
	print("[Server] Server shutdown initiated...")
	
	-- Call Shutdown() on all services if they have it
	for name, service in services do
		if type(service) == "table" and service.Shutdown then
			local success, err = pcall(service.Shutdown, service)
			
			if not success then
				warn(`[Server] Failed to shutdown {name}: {err}`)
			else
				print(`[Server] ✓ Shutdown: {name}`)
			end
		end
	end
	
	print("[Server] Shutdown complete")
end)

-- Return true to indicate successful module loading
return true
