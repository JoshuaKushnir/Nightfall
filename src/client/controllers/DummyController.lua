--!strict
--[[
	DummyController.lua

	Client-side management of combat test dummies.
	Handles spawning/despawning visuals and replication.

	Issue #52: Create Combat Test Dummies
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DummyDataModule = require(ReplicatedStorage.Shared.types.DummyData)
type DummyData = DummyDataModule.DummyData

local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)

local DummyController = {}

-- Storage
local DummyModels: {[string]: Model} = {}

-- Constants
local SPAWN_EVENT_NAME = "SpawnDummy"
local DESPAWN_EVENT_NAME = "DespawnDummy"

--[[
	Initialize the controller
]]
function DummyController:Init()
	print("[DummyController] Initializing...")
	
	-- Nothing to init yet
	
	print("[DummyController] Initialized successfully")
end

--[[
	Start the controller
]]
function DummyController:Start()
	print("[DummyController] Starting...")
	
	-- Listen for spawn events
	local spawnEvent = NetworkProvider:GetRemoteEvent(SPAWN_EVENT_NAME)
	if spawnEvent then
		spawnEvent.OnClientEvent:Connect(function(dummyData: DummyData)
			DummyController._OnDummySpawned(dummyData)
		end)
	end
	
	-- Listen for despawn events
	local despawnEvent = NetworkProvider:GetRemoteEvent(DESPAWN_EVENT_NAME)
	if despawnEvent then
		despawnEvent.OnClientEvent:Connect(function(dummyId: string)
			DummyController._OnDummyDespawned(dummyId)
		end)
	end
	
	print("[DummyController] Started successfully")
end

--[[
	Handle dummy spawn event
	@param dummyData The dummy data
]]
function DummyController._OnDummySpawned(dummyData: DummyData)
	print(`[DummyController] Dummy spawned: {dummyData.Id}`)
	
	-- Create visual model
	local model = DummyController._CreateDummyModel(dummyData)
	if model then
		DummyModels[dummyData.Id] = model
	end
end

--[[
	Handle dummy despawn event
	@param dummyId The dummy ID
]]
function DummyController._OnDummyDespawned(dummyId: string)
	print(`[DummyController] Dummy despawned: {dummyId}`)
	
	local model = DummyModels[dummyId]
	if model then
		model:Destroy()
		DummyModels[dummyId] = nil
	end
end

--[[
	Create the visual model for a dummy
	@param dummyData The dummy data
	@return Model or nil
]]
function DummyController._CreateDummyModel(dummyData: DummyData): Model?
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

	-- Add humanoid for compatibility
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = dummyData.Health
	humanoid.MaxHealth = dummyData.MaxHealth
	humanoid.Parent = model

	model.Parent = Workspace

	return model
end

return DummyController