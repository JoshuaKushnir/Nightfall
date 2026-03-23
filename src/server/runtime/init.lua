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
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)

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
	AspectService = services.AspectService,
	InventoryService = services.InventoryService,
	ProgressionService = services.ProgressionService,
	PostureService = services.PostureService,
	EffectRunner    = services.EffectRunner,
	PassiveSystem   = services.PassiveSystem,

	WeaponService   = services.WeaponService,
	DefenseService  = services.DefenseService,
	CombatService   = services.CombatService,
	DeathService    = services.DeathService,
	HollowedService = services.HollowedService,
	ZoneService     = services.ZoneService,
	AbilitySystem   = services.AbilitySystem,
	DummyService    = services.DummyService,     -- #194: restored (was accidentally commented out)
	MovementService = services.MovementService,  -- #194: added to dependency injection
	TrainingToolService = services.TrainingToolService,
	WitnessService  = services.WitnessService,
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
	"AspectService",       -- new Aspect system logic
	"InventoryService",    -- handles inventory & item usage
	"TrainingToolService", -- handles training tool usage
	"WeaponService",       -- #69: equip system (after NetworkService)
	"DefenseService",      -- Defense mechanics
	"MovementService",     -- #194: movement validation (depends on NetworkService)
	"CombatService",       -- Combat validation and damage application
	"DummyService",        -- #194: training dummies (after CombatService)
	"PostureService",      -- #75: Posture+HP dual health (lazy-requires CombatService)
	"ProgressionService",  -- #138/#139: Resonance, Ring caps, Discipline selection
	"DeathService",        -- #144: death→respawn pipeline (needs ProgressionService for shard loss)
	"HollowedService",     -- #143: Ring 1 enemy AI (patrol/aggro/attack, Resonance grant on kill)
	"ZoneService",         -- #142: Ring boundary detection (after ProgressionService)
	"WitnessService",      -- #181: Observation tracking (depends on HollowedService)
	"EffectRunner",        -- must start before EffectHandlers registers handlers
	"PassiveSystem",       -- hook pipeline
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

-- Register all effect handlers now that EffectRunner and PostureService are started
if services.EffectRunner then
    local EffectHandlers = require(ServerScriptService.Server.services.EffectHandlers)
    EffectHandlers.RegisterAll(services.EffectRunner, services.PostureService)
end

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

-- Setup combat hit event handling (Phase 2)
if services.CombatService and services.NetworkService then
	local CombatService = services.CombatService
	local NetworkService = services.NetworkService
	local StateService = require(ReplicatedStorage.Shared.modules.StateService)
	
	-- Register handler for hit requests from clients
	-- Clients send this when hitbox triggers
	NetworkService:RegisterHandler("StateRequest", function(player: Player, requestData: any)
		if requestData.Type == "HitRequest" then
			-- Validate and process hit
			local success, damage = CombatService.ValidateHit(player, requestData.HitData)
			if success then
				print(`[Server] Hit processed: {player.Name} dealt {damage} damage`)
			end
		elseif requestData.Type == "SetState" then
			-- Handle state change request (e.g., for dodge iframes)
			local newState = requestData.State
			if newState then
				StateService:SetPlayerState(player, newState)
				print(`[Server] State changed for {player.Name}: {newState}`)
			end
		end
	end)
	print("[Server] ✓ Combat hit event handler registered")
end

-- WeaponAttackRequest: validates packet shape then delegates to WeaponService.HandleAttackRequest (#171)
if services.NetworkService and services.WeaponService then
	local NetworkService = services.NetworkService
	NetworkService:RegisterHandler("WeaponAttackRequest", function(player: Player, packet: any)
		if type(packet) ~= "table"
			or type(packet.WeaponId) ~= "string"
			or (packet.AttackType ~= "Light" and packet.AttackType ~= "Heavy")
			or type(packet.ClientTime) ~= "number"
		then
			warn(("[WeaponAttackRequest] Malformed packet from %s"):format(player.Name))
			return
		end
		services.WeaponService.HandleAttackRequest(player, packet)
	end)
	print("[Server] ✓ WeaponAttackRequest handler registered (#171)")
end

-- Register AdminCommand handler (dev/admin-only commands)
if services.NetworkService and services.DummyService then
	local NetworkService = services.NetworkService
	local DummyService = services.DummyService
	local Utils = require(ReplicatedStorage.Shared.modules.Utils)

	NetworkService:RegisterHandler("AdminCommand", function(player: Player, packet: any)
		if not packet or type(packet.Command) ~= "string" then
			warn("[AdminCommand] Malformed packet")
			return
		end

		local cmd = string.lower(packet.Command)
		local args = packet.Args or {}

		-- Only allow authorized devs/admins to run admin commands
		if not DummyService._IsPlayerAllowed(player) then
			warn(`[AdminCommand] Permission denied for {player.Name}`)
			NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "permission_denied" } })
			return
		end

		if cmd == "toggle_hitboxes" then
			local newState = args[1] == "true"
			local DebugSettings = require(ReplicatedStorage.Shared.modules.DebugSettings)
			DebugSettings.Set("ShowHitboxes", newState)
			print(`[AdminCommand] {player.Name} toggled server hitboxes {newState and "ON" or "OFF"}`)
			NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Result = "ok" } })
			
		elseif cmd == "tp_dev" then
            local pointName = args[1]
            local devPoints = {
                heaven = Vector3.new(0, 10000, 0),
                testing = Vector3.new(500, 50, 500),
                origin = Vector3.new(0, 10, 0)
            }
            
            local target = devPoints[string.lower(pointName)]
            if target then
                local char = player.Character
                if char and char.PrimaryPart then
                    char:SetPrimaryPartCFrame(CFrame.new(target + Vector3.new(0, 5, 0)))
                    print(`[Admin] {player.Name} TP'd to {pointName}`)
                end
            end
			
		elseif cmd == "spawn_dummy" then
			-- Determine spawn position
			local spawnPos: Vector3? = nil
			if #args >= 3 then
				local x = tonumber(args[1])
				local y = tonumber(args[2])
				local z = tonumber(args[3])
				if x and y and z then
					spawnPos = Vector3.new(x, y, z)
				end
			elseif #args == 1 and tostring(args[1]) == "here" then
				local root = Utils.GetRootPart(player)
				if root then
					spawnPos = root.Position + root.CFrame.LookVector * 10
				end
			else
				local root = Utils.GetRootPart(player)
				if root then
					spawnPos = root.Position + root.CFrame.LookVector * 10
				end
			end

			if not spawnPos then
				spawnPos = Vector3.new(0, 5, 0)
			end

			local dummyId = DummyService.SpawnDummy(spawnPos)
			if NetworkService and player then
				NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Result = dummyId and "ok" or "failed", DummyId = dummyId } })
			end
			print(`[AdminCommand] {player.Name} spawned dummy: {dummyId}`)

		elseif cmd == "grant_resonance" then
			-- Debug: grant resonance directly so devs can earn stat points without combat
			local amount = tonumber(args[1]) or 200
			local ProgressionSvc = services.ProgressionService
			if ProgressionSvc then
				ProgressionSvc.GrantResonance(player, amount, "Debug")
				if NetworkService and player then
					NetworkService:SendToClient(player, "DebugInfo", {
						Category = "AdminCommand",
						Data = { Result = ("granted %d resonance"):format(amount) }
					})
				end
				print(("[AdminCommand] %s +%d debug Resonance"):format(player.Name, amount))
			else
				warn("[AdminCommand] ProgressionService not available")
				if NetworkService and player then
					NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "progression_unavailable" } })
				end
			end
		elseif cmd == "set_aspect" then
			-- Developer helper: give player the specified aspect with all branches
			local aspectId = args[1]
			if not aspectId then
				if NetworkService and player then
					NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "missing_aspect" } })
				end
			else
				local AspectSvc = services.AspectService
				if AspectSvc then
					local ok = AspectSvc.DebugSetAspect(player, aspectId)
					if ok then
						if NetworkService and player then
							NetworkService:SendToClient(player, "SwitchAspectResult", { Success = true, AspectId = aspectId })
							NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Result = ("set aspect %s"):format(aspectId) } })
						end
						print(`[AdminCommand] {player.Name} debug set aspect to {aspectId}`)
					else
						if NetworkService and player then
							NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "invalid_aspect" } })
						end
					end
				else
					warn("[AdminCommand] AspectService not available")
					if NetworkService and player then
						NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "aspect_unavailable" } })
					end
				end
			end

		-- Progression testing commands ---
		-- Only allow these debug commands in Studio (not public servers)
		elseif DebugMode and cmd == "kill_player" then
			-- Debug: force player death to test shard loss on death
			local char = player.Character
			if char then
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.Health = 0
					print(`[AdminCommand] {player.Name} killed (debug death)`)
					if NetworkService and player then
						NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Result = "killed" } })
					end
				else
					if NetworkService and player then
						NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "no_humanoid" } })
					end
				end
			else
				if NetworkService and player then
					NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "no_character" } })
				end
			end

		elseif DebugMode and cmd == "set_ring" then
			-- Debug: change player's ring to test soft caps
			local ring = tonumber(args[1]) or 1
			ring = math.clamp(ring, 0, 5)
			local ProgressionSvc = services.ProgressionService
			if ProgressionSvc then
				ProgressionSvc.SetPlayerRing(player, ring)
				print(`[AdminCommand] {player.Name} set to Ring {ring}`)
				if NetworkService and player then
					NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Result = ("ring_%d"):format(ring) } })
				end
			else
				warn("[AdminCommand] ProgressionService not available")
				if NetworkService and player then
					NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "progression_unavailable" } })
				end
			end

		elseif DebugMode and cmd == "reset_progression" then
			-- Debug: reset all progression for retesting from scratch
			local DataSvc = services.DataService
			local ProgressionSvc = services.ProgressionService
			if DataSvc and ProgressionSvc then
				local profile = DataSvc:GetProfile(player)
				if profile then
					profile.TotalResonance = 0
					profile.ResonanceShards = 0
					profile.StatPoints = 0
					profile.Stats = { Strength = 0, Fortitude = 0, Agility = 0, Intelligence = 0, Willpower = 0, Charisma = 0 }
					profile.DisciplineId = "Wayward"
					-- Reset derived values
					profile.Health.Max = 100
					profile.Health.Current = 100
					profile.Posture.Max = 100
					profile.Mana.Max = 100
					profile.Mana.Regen = 2.0
					-- Reset additional progression fields
					profile.CurrentRing = 0
					profile.OmenMarks = 0
					profile.Level = 1
					profile.Experience = 0
					profile.Inventory = {}
					profile.EquippedItems = {}
					profile.Mantras = {}
					profile.ActiveCooldowns = {}
					profile.AspectData = nil
					ProgressionSvc.SyncToClient(player)
					print(`[AdminCommand] {player.Name} progression reset`)
					if NetworkService and player then
						NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Result = "progression_reset" } })
					end
				else
					if NetworkService and player then
						NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "no_profile" } })
					end
				end
			else
				warn("[AdminCommand] DataService not available")
				if NetworkService and player then
					NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "data_unavailable" } })
				end
			end

		elseif DebugMode and cmd == "grant_stat_points" then
			-- Debug: directly grant stat points (bypasses resonance milestone)
			local amount = tonumber(args[1]) or 1
			local DataSvc = services.DataService
			if DataSvc then
				local profile = DataSvc:GetProfile(player)
				if profile then
					profile.StatPoints = (profile.StatPoints or 0) + amount
					print(`[AdminCommand] {player.Name} +{amount} stat points (total: {profile.StatPoints})`)
					if NetworkService and player then
						NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Result = ("+%d stat_points"):format(amount) } })
					end
					-- Also sync to update UI
					local ProgressionSvc = services.ProgressionService
					if ProgressionSvc then
						ProgressionSvc.SyncToClient(player)
					end
				else
					if NetworkService and player then
						NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "no_profile" } })
					end
				end
			else
				warn("[AdminCommand] DataService not available")
				if NetworkService and player then
					NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "data_unavailable" } })
				end
			end

		elseif DebugMode and cmd == "grant_training_tool" then
			-- Debug: grant a training tool to player's inventory
			-- Usage: /admin grant_training_tool [stat] [rarity]
			-- stat: Strength, Fortitude, Agility, Intelligence, Willpower, Charisma
			-- rarity: Common, Uncommon, Rare
			local statName = args[1] or "Strength"
			local rarity = args[2] or "Common"
			
			-- Validate stat name
			local validStats = {Strength=true, Fortitude=true, Agility=true, Intelligence=true, Willpower=true, Charisma=true}
			if not validStats[statName] then
				warn("[AdminCommand] Invalid stat name: " .. statName)
				if NetworkService and player then
					NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "invalid_stat" } })
				end
				return
			end
			
			-- Build item ID
			local rarityLower = string.lower(rarity)
			local itemId = "training_tool_" .. string.lower(statName) .. "_" .. rarityLower
			
			-- Check if item exists via ItemRegistry
			local ItemRegistry = require(ReplicatedStorage.Shared.modules.ItemRegistry)
			if not ItemRegistry.Has(itemId) then
				warn("[AdminCommand] Training tool not found: " .. itemId)
				if NetworkService and player then
					NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "item_not_found" } })
				end
				return
			end
			
			-- Add item to inventory
			local InventorySvc = services.InventoryService
			if InventorySvc then
				local itemDef = ItemRegistry.Get(itemId)
				local success = InventorySvc.GiveItem(player, itemDef)
				if success then
					print(`[AdminCommand] {player.Name} received {itemId}`)
					if NetworkService and player then
						NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Result = itemId } })
					end
				else
					if NetworkService and player then
						NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "give_failed" } })
					end
				end
			else
				warn("[AdminCommand] InventoryService not available")
			end
		else
			warn(`[AdminCommand] Unknown admin command: {cmd}`)
			if NetworkService and player then
				NetworkService:SendToClient(player, "DebugInfo", { Category = "AdminCommand", Data = { Error = "unknown_command" } })
			end
		end
	end)
	print("[Server] ✓ AdminCommand handler registered")
end

-- Register UseAbility handler (weapon active abilities, issue #72)
if services.NetworkService and services.AbilitySystem then
	local NetworkService = services.NetworkService
	local AbilitySystem = services.AbilitySystem

	NetworkService:RegisterHandler("UseAbility", function(player: Player, _packet: any)
		AbilitySystem.HandleUseAbility(player)
	end)
	print("[Server] ✓ UseAbility handler registered")
end

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
