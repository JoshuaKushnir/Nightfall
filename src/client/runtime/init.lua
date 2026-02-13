--!strict
--[[
	Client Runtime Bootstrap
	
	Issue #5: Server & Client Bootstrap/Initialization Systems
	Epic: Phase 1 - Core Framework
	
	This is the client entry point. It loads and initializes all controllers
	in the correct order after the player and character are ready.
	
	Initialization Sequence:
	1. Wait for LocalPlayer
	2. Wait for character to load (optional but recommended)
	3. Load all controller modules from src/client/controllers/
	4. Call Init() on all controllers (dependency setup)
	5. Call Start() on all controllers (begin operations)
	
	Controller Lifecycle:
	- Init(): Setup dependencies, cache references, register handlers
	- Start(): Begin listening to events, start render loops, connect signals
	
	All controllers should follow this pattern for consistent initialization.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Import Loader utility
local Loader = require(ReplicatedStorage.Shared.modules.Loader)

print(("="):rep(60))
print("🌙 NIGHTFALL - Client Bootstrap")
print(("="):rep(60))
print(`[Client] Execution Context: {Loader.GetContext()}`)
print(`[Client] Starting initialization sequence...`)
print("")

local INITIALIZATION_START = os.clock()

-- Step 0: Wait for LocalPlayer
print("[Client] [0/4] Waiting for LocalPlayer...")
local player = Players.LocalPlayer

if not player then
	error("[Client] Failed to get LocalPlayer")
end

print(`[Client] ✓ LocalPlayer found: {player.Name}`)
print("")

-- Step 1: Wait for character (optional but recommended)
print("[Client] [1/4] Waiting for character...")
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?

if not humanoid then
	warn("[Client] Failed to find Humanoid - proceeding anyway")
else
	print(`[Client] ✓ Character loaded: {character.Name}`)
end

print("")

-- Step 2: Load all controllers
print("[Client] [2/4] Loading controllers...")
local controllersFolder = script.Parent.controllers
local controllers = Loader.LoadModules(controllersFolder, false)

-- Handle case where no controllers exist yet
if not next(controllers) then
	warn("[Client] No controllers found to load")
	controllers = {}
end

print("")

-- Step 3: Initialize all controllers (Init method)
print("[Client] [3/4] Initializing controllers...")
local initSuccess = true

-- Build dependencies table for dependency injection
local dependencies = {
	NetworkController = controllers.NetworkController,
	StateSyncController = controllers.StateSyncController,
}

for name, controller in controllers do
	if type(controller) == "table" and controller.Init then
		local success, err = pcall(controller.Init, controller, dependencies)
		
		if not success then
			warn(`[Client] ❌ Failed to initialize {name}: {err}`)
			initSuccess = false
		else
			print(`[Client] ✓ Initialized: {name}`)
		end
	end
end

if not initSuccess then
	warn("[Client] Some controllers failed to initialize")
end

print("")

-- Step 4: Start all controllers (Start method)
print("[Client] [4/4] Starting controllers...")
local startSuccess = true

for name, controller in controllers do
	if type(controller) == "table" and controller.Start then
		local success, err = pcall(controller.Start, controller)
		
		if not success then
			warn(`[Client] ❌ Failed to start {name}: {err}`)
			startSuccess = false
		else
			print(`[Client] ✓ Started: {name}`)
		end
	end
end

if not startSuccess then
	warn("[Client] Some controllers failed to start")
end

print("")

-- Initialization complete
local initTime = (os.clock() - INITIALIZATION_START) * 1000
local controllerCount = 0
for _ in controllers do
	controllerCount += 1
end

print(("="):rep(60))
print(`🌙 Client Bootstrap Complete`)
print(`   Controllers Loaded: {controllerCount}`)
print(`   Initialization Time: {math.floor(initTime * 100) / 100}ms`)
print(`   Status: {if initSuccess and startSuccess then "✓ Ready" else "⚠ Partial"}`)
print(("="):rep(60))
print("")

-- Export controllers for debugging (optional)
_G.Controllers = controllers

-- Listen for character respawn
player.CharacterAdded:Connect(function(newCharacter)
	print(`[Client] Character respawned: {newCharacter.Name}`)
	
	-- Call OnCharacterAdded on all controllers if they have it
	for name, controller in controllers do
		if type(controller) == "table" and controller.OnCharacterAdded then
			task.spawn(function()
				local success, err = pcall(controller.OnCharacterAdded, controller, newCharacter)
				
				if not success then
					warn(`[Client] OnCharacterAdded error in {name}: {err}`)
				end
			end)
		end
	end
end)

-- Return true to indicate successful module loading
return true
