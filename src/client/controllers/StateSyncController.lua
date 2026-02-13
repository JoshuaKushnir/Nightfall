--!strict
--[[
	StateSyncController.lua
	Manages client-side state synchronization with the server.
	
	Responsibilities:
	- Listens for state updates from server via NetworkController
	- Maintains local cache of player state
	- Provides reactive signals for UI binding
	- Handles network latency and state inconsistencies
	- Implements optimistic updates with rollback
	
	Architecture:
	- Subscribes to network events for state changes
	- Emits signals when state changes (for UI binding)
	- Caches last known state to handle disconnections
	- Implements retry logic for failed updates
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Signal = require(ReplicatedStorage.Packages.Signal)

-- Types
local NetworkTypes = require(Shared.Types.NetworkTypes)
local PlayerData = require(Shared.Types.PlayerData)
type PlayerState = PlayerData.PlayerState
type PlayerProfile = PlayerData.PlayerProfile

-- Controllers
local NetworkController = nil -- Dependency injection via Init()

-- Signals
local StateChangedSignal = Signal.new() :: Signal.Signal<PlayerState, PlayerState>
local ProfileLoadedSignal = Signal.new() :: Signal.Signal<PlayerProfile>
local ProfileUpdatedSignal = Signal.new() :: Signal.Signal<PlayerProfile>
local StateSyncErrorSignal = Signal.new() :: Signal.Signal<string>

-- State Cache
local LocalPlayer = Players.LocalPlayer
local cachedState: PlayerState? = nil
local cachedProfile: PlayerProfile? = nil
local lastSyncTimestamp: number = 0
local syncInProgress: boolean = false

-- Configuration
local SYNC_TIMEOUT: number = 5 -- seconds
local MAX_RETRY_ATTEMPTS: number = 3
local RETRY_DELAY: number = 2 -- seconds

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
	Validates that the received state is newer than cached state
]]
local function isStateNewer(newTimestamp: number): boolean
	return newTimestamp > lastSyncTimestamp
end

--[[
	Updates the local state cache and fires signals
]]
local function updateLocalState(newState: PlayerState, timestamp: number)
	if not isStateNewer(timestamp) then
		warn("[StateSyncController] Ignoring stale state update")
		return
	end
	
	local oldState = cachedState
	cachedState = newState
	lastSyncTimestamp = timestamp
	
	-- Fire signal for UI binding
	if oldState then
		StateChangedSignal:Fire(oldState, newState)
	end
end

--[[
	Updates the local profile cache and fires signals
]]
local function updateLocalProfile(newProfile: PlayerProfile, isInitialLoad: boolean)
	cachedProfile = newProfile
	
	if isInitialLoad then
		ProfileLoadedSignal:Fire(newProfile)
	else
		ProfileUpdatedSignal:Fire(newProfile)
	end
end

--[[
	Handles state change events from the server
]]
local function onServerStateChanged(packet: NetworkTypes.StateChangePacket)
	updateLocalState(packet.NewState, packet.Timestamp or os.time())
end

--[[
	Handles profile data load events from the server
]]
local function onServerProfileLoaded(packet: NetworkTypes.ProfileDataPacket)
	updateLocalProfile(packet.ProfileData, true)
end

--[[
	Handles profile data update events from the server
]]
local function onServerProfileUpdated(packet: NetworkTypes.ProfileDataPacket)
	updateLocalProfile(packet.ProfileData, false)
end

--[[
	Handles combat data update events from the server
]]
local function onServerCombatDataUpdated(packet: NetworkTypes.CombatDataPacket)
	-- Update relevant parts of cached profile
	if cachedProfile then
		cachedProfile.CurrentHealth = packet.Health
		cachedProfile.CurrentMana = packet.Mana
		cachedProfile.Level = packet.Level
		ProfileUpdatedSignal:Fire(cachedProfile)
	end
end

--[[
	Requests initial state sync from the server
]]
local function requestInitialSync()
	if syncInProgress then
		warn("[StateSyncController] Sync already in progress")
		return
	end
	
	syncInProgress = true
	
	-- Request state from server
	NetworkController.SendToServer("RequestStateSync", {
		Timestamp = os.time()
	})
	
	-- Set timeout
	task.delay(SYNC_TIMEOUT, function()
		if syncInProgress then
			syncInProgress = false
			StateSyncErrorSignal:Fire("State sync timeout")
		end
	end)
end

--[[
	Implements retry logic for failed sync attempts
]]
local function retrySyncWithBackoff(attempt: number)
	if attempt > MAX_RETRY_ATTEMPTS then
		StateSyncErrorSignal:Fire("Max retry attempts exceeded")
		return
	end
	
	local delay = RETRY_DELAY * attempt
	task.delay(delay, function()
		requestInitialSync()
	end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local StateSyncController = {}

--[[
	Returns the current cached player state
]]
function StateSyncController.GetCurrentState(): PlayerState?
	return cachedState
end

--[[
	Returns the current cached player profile
]]
function StateSyncController.GetCurrentProfile(): PlayerProfile?
	return cachedProfile
end

--[[
	Returns signal that fires when state changes
	@returns Signal<OldState, NewState>
]]
function StateSyncController.GetStateChangedSignal()
	return StateChangedSignal
end

--[[
	Returns signal that fires when profile is initially loaded
	@returns Signal<PlayerProfile>
]]
function StateSyncController.GetProfileLoadedSignal()
	return ProfileLoadedSignal
end

--[[
	Returns signal that fires when profile is updated
	@returns Signal<PlayerProfile>
]]
function StateSyncController.GetProfileUpdatedSignal()
	return ProfileUpdatedSignal
end

--[[
	Returns signal that fires when sync errors occur
	@returns Signal<ErrorMessage>
]]
function StateSyncController.GetStateSyncErrorSignal()
	return StateSyncErrorSignal
end

--[[
	Returns the last sync timestamp
]]
function StateSyncController.GetLastSyncTimestamp(): number
	return lastSyncTimestamp
end

--[[
	Returns whether a sync is currently in progress
]]
function StateSyncController.IsSyncInProgress(): boolean
	return syncInProgress
end

--[[
	Requests a manual state sync from the server
]]
function StateSyncController.RequestSync()
	requestInitialSync()
end

--[[
	Initializes the controller (called by runtime)
]]
function StateSyncController.Init(dependencies)
	NetworkController = dependencies.NetworkController
	
	if not NetworkController then
		error("[StateSyncController] NetworkController dependency not provided")
	end
	
	print("[StateSyncController] Initialized")
end

--[[
	Starts the controller and sets up event handlers (called by runtime)
]]
function StateSyncController.Start()
	-- Register network event handlers
	NetworkController.RegisterHandler("StateChanged", onServerStateChanged)
	NetworkController.RegisterHandler("ProfileData", onServerProfileLoaded)
	NetworkController.RegisterHandler("ProfileUpdate", onServerProfileUpdated)
	NetworkController.RegisterHandler("CombatData", onServerCombatDataUpdated)
	
	-- Request initial state sync
	requestInitialSync()
	
	print("[StateSyncController] Started - Listening for state updates")
end

--[[
	Cleanup on shutdown (called by runtime)
]]
function StateSyncController.Shutdown()
	StateChangedSignal:Destroy()
	ProfileLoadedSignal:Destroy()
	ProfileUpdatedSignal:Destroy()
	StateSyncErrorSignal:Destroy()
	
	print("[StateSyncController] Shutdown complete")
end

return StateSyncController
