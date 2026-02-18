--!strict
--[[
	DummyService.lua

	Manages combat test dummies for development.
	Provides spawn/despawn functionality and dummy state management.

	Issue #52: Create Combat Test Dummies
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DummyDataModule = require(ReplicatedStorage.Shared.types.DummyData)
type DummyData = DummyDataModule.DummyData

local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local Loader = require(ReplicatedStorage.Shared.modules.Loader)

local DummyService = {}

-- Storage
local ActiveDummies: {[string]: DummyData} = {}
local DummyModels: {[string]: Model} = {}

-- Constants
local DUMMY_MODEL_TEMPLATE = "DummyTemplate" -- Assume this exists in ReplicatedStorage
local DUMMY_HEALTH = 100
local DUMMY_LIFETIME = 300 -- 5 minutes
local SPAWN_EVENT_NAME = "SpawnDummy"
local DESPAWN_EVENT_NAME = "DespawnDummy"

-- Default positions where dummies auto-spawn on game start
-- Adjust these Vector3 positions to match your map layout
local AUTO_SPAWN_POSITIONS: {Vector3} = {
	Vector3.new(0,  3,  10),
	Vector3.new(10, 3,  0),
	Vector3.new(-10, 3, 0),
}

--[[
	Initialize the service
]]
function DummyService:Init()
	print("[DummyService] Initializing...")

	-- Clean up on server shutdown
	game:BindToClose(function()
		DummyService._CleanupAllDummies()
	end)

	print("[DummyService] Initialized successfully")
end

--[[
	Start the service
]]
function DummyService:Start()
	print("[DummyService] Starting...")

	-- Auto-spawn dummies at predefined positions so testers have targets immediately
	for _, pos in AUTO_SPAWN_POSITIONS do
		DummyService.SpawnDummy(pos)
	end
	print(`[DummyService] ✓ Auto-spawned {#AUTO_SPAWN_POSITIONS} dummy(s) at game start`)

	-- Listen for spawn requests
	local spawnEvent = NetworkProvider:GetRemoteEvent(SPAWN_EVENT_NAME)
	if spawnEvent then
		spawnEvent.OnServerEvent:Connect(function(player, position)
			if not DummyService._IsPlayerAllowed(player) then
				warn(`[DummyService] Spawn denied for {player.Name} ({player.UserId}) - dev-only`)
				return
			end
			DummyService.SpawnDummy(position)
		end)
	end

	-- Listen for despawn requests
	local despawnEvent = NetworkProvider:GetRemoteEvent(DESPAWN_EVENT_NAME)
	if despawnEvent then
		despawnEvent.OnServerEvent:Connect(function(player, dummyId)
			if not DummyService._IsPlayerAllowed(player) then
				warn(`[DummyService] Despawn denied for {player.Name} ({player.UserId}) - dev-only`)
				return
			end
			DummyService.DespawnDummy(dummyId)
		end)
	end

	print("[DummyService] Started successfully")
end

--[[
	Check whether a player is allowed to spawn/despawn dummies (dev-only)
	@param player The player to check
	@return boolean
]]
function DummyService._IsPlayerAllowed(player: Player?): boolean
	-- Allow only in Studio for development workflows
	if Loader and Loader.IsStudio and Loader.IsStudio() then
		return true
	end

	-- Fallback: allow game creator in non-studio environments
	if player and player.UserId == game.CreatorId then
		return true
	end

	return false
end

--[[
	Spawn a dummy at the specified position
	@param position Where to spawn the dummy
	@return Dummy ID if successful
]]
function DummyService.SpawnDummy(position: Vector3): string?
	-- Generate unique ID
	local dummyId = Utils.GenerateId()

	-- Create dummy data
	local dummyData: DummyData = {
		Id = dummyId,
		Position = position,
		Health = DUMMY_HEALTH,
		MaxHealth = DUMMY_HEALTH,
		IsActive = true,
		SpawnTime = tick(),
	}

	-- Create visual model
	local model = DummyService._CreateDummyModel(dummyData)
	if not model then
		print("[DummyService] Failed to create dummy model")
		return nil
	end

	-- Store references
	ActiveDummies[dummyId] = dummyData
	DummyModels[dummyId] = model

	-- Set up auto-despawn
	task.delay(DUMMY_LIFETIME, function()
		if ActiveDummies[dummyId] then
			DummyService.DespawnDummy(dummyId)
		end
	end)

	print(`[DummyService] ✓ Dummy spawned: {dummyId} at {position}`)

	-- Broadcast spawn to clients
	local spawnEvent = NetworkProvider:GetRemoteEvent(SPAWN_EVENT_NAME)
	if spawnEvent then
		spawnEvent:FireAllClients(dummyData)
	end

	return dummyId
end

--[[
	Despawn a dummy
	@param dummyId The ID of the dummy to despawn
]]
function DummyService.DespawnDummy(dummyId: string)
	local dummyData = ActiveDummies[dummyId]
	local model = DummyModels[dummyId]

	if not dummyData then
		print(`[DummyService] Dummy not found: {dummyId}`)
		return
	end

	-- Mark as inactive
	dummyData.IsActive = false

	-- Remove model
	if model then
		model:Destroy()
		DummyModels[dummyId] = nil
	end

	-- Remove from storage
	ActiveDummies[dummyId] = nil

	print(`[DummyService] ✓ Dummy despawned: {dummyId}`)

	-- Broadcast despawn to clients
	local despawnEvent = NetworkProvider:GetRemoteEvent(DESPAWN_EVENT_NAME)
	if despawnEvent then
		despawnEvent:FireAllClients(dummyId)
	end
end

--[[
	Get dummy data by ID
	@param dummyId The dummy ID
	@return DummyData or nil
]]
function DummyService.GetDummyData(dummyId: string): DummyData?
	return ActiveDummies[dummyId]
end

--[[
	Get all active dummies
	@return Array of DummyData
]]
function DummyService.GetAllDummies(): {DummyData}
	local dummies = {}
	for _, dummy in ActiveDummies do
		table.insert(dummies, dummy)
	end
	return dummies
end

--[[
	Apply damage to a dummy
	@param dummyId The dummy ID
	@param damage Amount of damage
	@return True if damage applied, false if dummy died or not found
]]
function DummyService.ApplyDamage(dummyId: string, damage: number): boolean
	local dummyData = ActiveDummies[dummyId]
	if not dummyData or not dummyData.IsActive then
		return false
	end

	dummyData.Health = math.max(0, dummyData.Health - damage)

	if dummyData.Health <= 0 then
		print(`[DummyService] ☠️ Dummy defeated: {dummyId}`)
		DummyService.DespawnDummy(dummyId)
		return false
	end

	print(`[DummyService] ✓ Dummy hit: {dummyId} ({damage} damage, {dummyData.Health} HP remaining)`)
	return true
end

--[[
	Create the visual model for a dummy
	@param dummyData The dummy data
	@return Model or nil
]]
function DummyService._CreateDummyModel(dummyData: DummyData): Model?
	-- For now, create a simple part as placeholder
	-- In a real implementation, you'd clone a template model
	local model = Instance.new("Model")
	model.Name = `Dummy_{dummyData.Id}`

	local part = Instance.new("Part")
	part.Name = "Body"
	part.Size = Vector3.new(4, 6, 2)
	part.Position = dummyData.Position
	part.Anchored = true
	part.CanCollide = true
	part.BrickColor = BrickColor.new("Bright red") -- Visual indicator
	part.Material = Enum.Material.Plastic
	part.Parent = model

	-- Add humanoid for compatibility (though no AI)
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = dummyData.Health
	humanoid.MaxHealth = dummyData.MaxHealth
	humanoid.Parent = model

	model.Parent = Workspace

	return model
end

--[[
	Clean up all dummies
]]
function DummyService._CleanupAllDummies()
	for dummyId in ActiveDummies do
		DummyService.DespawnDummy(dummyId)
	end
end

return DummyService