--!strict
--[[
	DummyController.lua

	Client-side observer for combat test dummies.

	The server creates all dummy models in Workspace and Roblox replication
	propagates them to clients automatically, so this controller does NOT
	create its own geometry.  It:
	  • Tracks a name->model mapping so other controllers can look up dummies.
	  • Reacts to DummyStateChanged: plays a brief highlight flash so the
	    local player sees the state transition clearly on their end.

	Issue #64: Spawnable test dummies for attack testing
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local TweenService      = game:GetService("TweenService")

local AnimationLoader = require(ReplicatedStorage.Shared.modules.AnimationLoader)

local DummyDataModule = require(ReplicatedStorage.Shared.types.DummyData)
type DummyData  = DummyDataModule.DummyData
type DummyState = DummyDataModule.DummyState

local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)

local DummyController = {}

-- Client-side model registry (populated from Workspace replicated models)
local DummyModels: {[string]: Model} = {}

-- Per-dummy idle AnimationTrack (looped while dummy is in Normal state)
local DummyIdleTracks: {[string]: AnimationTrack} = {}

-- Constants
local SPAWN_EVENT_NAME         = "SpawnDummy"
local DESPAWN_EVENT_NAME       = "DespawnDummy"
local STATE_CHANGED_EVENT_NAME = "DummyStateChanged"

-- Animation folder / asset for the dummy idle (must exist under ReplicatedStorage.animations/Dummy/)
local IDLE_ANIM_FOLDER = "Idle"
local IDLE_ANIM_ASSET  = "Idle"

-- Flash colour shown briefly on state entry (purely visual, server color is authoritative)
local STATE_FLASH_COLOR: {[DummyState]: Color3} = {
	Normal    = Color3.fromRGB(180, 180, 180),
	Blocking  = Color3.fromRGB(80,  120, 255),
	Staggered = Color3.fromRGB(255, 140, 40),
}

-- ──────────────────────────────────────────────────────────────────────────
-- Animation helpers
-- ──────────────────────────────────────────────────────────────────────────

--[[
	Load and loop the idle animation on a dummy model.
	Safe to call multiple times - skips if a track is already active.
]]
local function playIdleAnimation(dummyId: string, model: Model)
	if DummyIdleTracks[dummyId] then return end  -- already playing

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`[DummyController] No Humanoid found on dummy {dummyId} for idle animation`)
		return
	end

	local track = AnimationLoader.LoadTrack(humanoid, IDLE_ANIM_FOLDER, IDLE_ANIM_ASSET)
	if track then
		track.Looped = true
		track:Play()
		DummyIdleTracks[dummyId] = track
		print(`[DummyController] Playing idle animation on dummy {dummyId}`)
	end
end

--[[
	Stop and discard the idle animation track for a dummy.
]]
local function stopIdleAnimation(dummyId: string)
	local track = DummyIdleTracks[dummyId]
	if track then
		track:Stop()
		DummyIdleTracks[dummyId] = nil
		print(`[DummyController] Stopped idle animation on dummy {dummyId}`)
	end
end

-- ──────────────────────────────────────────────────────────────────────────
-- Lifecycle
-- ──────────────────────────────────────────────────────────────────────────

function DummyController:Init()
	print("[DummyController] Initializing...")
	print("[DummyController] Initialized successfully")
end

function DummyController:Start()
	print("[DummyController] Starting...")

	-- Spawn: record the replicated model reference
	local spawnEvent = NetworkProvider:GetRemoteEvent(SPAWN_EVENT_NAME)
	if spawnEvent then
		spawnEvent.OnClientEvent:Connect(function(dummyData: DummyData)
			DummyController._OnDummySpawned(dummyData)
		end)
	end

	-- Despawn: drop the reference (server destroys the model; replication removes it)
	local despawnEvent = NetworkProvider:GetRemoteEvent(DESPAWN_EVENT_NAME)
	if despawnEvent then
		despawnEvent.OnClientEvent:Connect(function(dummyId: string)
			DummyController._OnDummyDespawned(dummyId)
		end)
	end

	-- State change: client-side flash effect
	local stateEvent = NetworkProvider:GetRemoteEvent(STATE_CHANGED_EVENT_NAME)
	if stateEvent then
		stateEvent.OnClientEvent:Connect(function(packet: {DummyId: string, State: DummyState, Health: number, MaxHealth: number})
			DummyController._OnStateChanged(packet)
		end)
	end

	print("[DummyController] Started successfully")
end

-- ──────────────────────────────────────────────────────────────────────────
-- Event handlers
-- ──────────────────────────────────────────────────────────────────────────

--[[
	Server fires SpawnDummy after creating the model.
	Wait briefly for replication then store the reference.
]]
function DummyController._OnDummySpawned(dummyData: DummyData)
	print(`[DummyController] Dummy spawned: {dummyData.Id}`)

	-- The model is created server-side and replicates; find it in Workspace.
	-- Poll briefly to handle replication lag.
	task.spawn(function()
		local modelName = `Dummy_{dummyData.Id}`
		local found: Model? = nil
		for _ = 1, 10 do
			found = Workspace:FindFirstChild(modelName) :: Model?
			if found then break end
			task.wait(0.1)
		end
		if found then
			DummyModels[dummyData.Id] = found
			print(`[DummyController] Linked to replicated model: {modelName}`)
			playIdleAnimation(dummyData.Id, found)
		else
			warn(`[DummyController] Replicated model not found: {modelName}`)
		end
	end)
end

--[[
	Server fires DespawnDummy before destroying the model.
]]
function DummyController._OnDummyDespawned(dummyId: string)
	print(`[DummyController] Dummy despawned: {dummyId}`)
	stopIdleAnimation(dummyId)
	DummyModels[dummyId] = nil
end

--[[
	Server fires DummyStateChanged whenever a dummy transitions state.
	Play a brief local highlight flash so the transition reads clearly.
]]
function DummyController._OnStateChanged(packet: {DummyId: string, State: DummyState, Health: number, MaxHealth: number})
	local model = DummyModels[packet.DummyId]
	if not model then return end

	print(`[DummyController] Dummy {packet.DummyId} state -> {packet.State} ({packet.Health}/{packet.MaxHealth} HP)`)

	-- Idle animation: play when Normal, stop for all other states
	if packet.State == "Normal" then
		local m = DummyModels[packet.DummyId]
		if m then
			playIdleAnimation(packet.DummyId, m)
		end
	else
		stopIdleAnimation(packet.DummyId)
	end

	local flashColor = STATE_FLASH_COLOR[packet.State]
	if not flashColor then return end

	-- Brief tween all visible parts to a flash color, then hand back to server color
	local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Linear)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local tween = TweenService:Create(part, tweenInfo, { Color = flashColor })
			tween:Play()
		end
	end
end

-- ──────────────────────────────────────────────────────────────────────────
-- Public helpers
-- ──────────────────────────────────────────────────────────────────────────

--[[
	Return the replicated model for a dummy (may be nil before replication).
]]
function DummyController.GetModel(dummyId: string): Model?
	return DummyModels[dummyId]
end

return DummyController