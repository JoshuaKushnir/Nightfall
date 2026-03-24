--!strict
--[[
	Class: StateSyncController
	Description: Manages client-side state synchronization with the server via event-level snapshots.
	Dependencies: NetworkTypes, PlayerData, Signal
	Usage: Listens to StateSnapshot, ProfileData, ProfileUpdate
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local Signal = require(ReplicatedStorage.Signal)

-- Types
local NetworkTypes = require(Shared.types.NetworkTypes)
local PlayerData = require(Shared.types.PlayerData)
type PlayerState = PlayerData.PlayerState
type PlayerProfile = PlayerData.PlayerProfile
type StateSnapshotPacket = NetworkTypes.StateSnapshotPacket

-- Controllers
local NetworkController = nil -- Dependency injection via Init()

-- Signals
local StateChangedSignal = Signal.new() :: Signal.Signal<PlayerState, PlayerState>
local ProfileLoadedSignal = Signal.new() :: Signal.Signal<PlayerProfile>
local ProfileUpdatedSignal = Signal.new() :: Signal.Signal<PlayerProfile>
local StateSyncErrorSignal = Signal.new() :: Signal.Signal<string>
local CombatDataUpdatedSignal = Signal.new() :: Signal.Signal<NetworkTypes.CombatDataPacket>

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

local function isStateNewer(newTimestamp: number): boolean
	return newTimestamp > lastSyncTimestamp
end

local function updateLocalState(newState: string, timestamp: number)
	if not isStateNewer(timestamp) then
		return
	end

	local oldState = cachedState
	cachedState = newState :: PlayerState
	lastSyncTimestamp = timestamp

	if oldState and oldState ~= newState then
		StateChangedSignal:Fire(oldState, newState :: PlayerState)
	end
end

local function updateLocalProfile(newProfile: PlayerProfile, isInitialLoad: boolean)
	cachedProfile = newProfile

	if isInitialLoad then
		ProfileLoadedSignal:Fire(newProfile)
	else
		ProfileUpdatedSignal:Fire(newProfile)
	end
end

local function onServerStateSnapshot(packet: StateSnapshotPacket)
	local timestamp = packet.Timestamp or os.time()

	if packet.State then
		updateLocalState(packet.State, timestamp)
	end

	local hasCombatData = packet.Health or packet.MaxHealth or packet.Mana or packet.MaxMana or packet.Posture or packet.MaxPosture or packet.Level
	if hasCombatData then
		local combatPacket: NetworkTypes.CombatDataPacket = {
			Health = packet.Health or (cachedProfile and cachedProfile.Health and cachedProfile.Health.Current) or 0,
			MaxHealth = packet.MaxHealth or (cachedProfile and cachedProfile.Health and cachedProfile.Health.Max) or 0,
			Mana = packet.Mana or (cachedProfile and cachedProfile.Mana and cachedProfile.Mana.Current) or 0,
			MaxMana = packet.MaxMana or (cachedProfile and cachedProfile.Mana and cachedProfile.Mana.Max) or 0,
			Posture = packet.Posture or (cachedProfile and cachedProfile.Posture and cachedProfile.Posture.Current) or 0,
			MaxPosture = packet.MaxPosture or (cachedProfile and cachedProfile.Posture and cachedProfile.Posture.Max) or 0,
			Level = packet.Level or (cachedProfile and cachedProfile.Level) or 0,
		}

		if not cachedProfile then
			cachedProfile = {
				Health = { Current = combatPacket.Health, Max = combatPacket.MaxHealth },
				Mana = { Current = combatPacket.Mana, Max = combatPacket.MaxMana },
				Posture = { Current = combatPacket.Posture, Max = combatPacket.MaxPosture },
				Level = combatPacket.Level,
			} :: any
			ProfileLoadedSignal:Fire(cachedProfile :: PlayerProfile)
		else
			if cachedProfile.Health then
				if packet.Health then cachedProfile.Health.Current = packet.Health end
				if packet.MaxHealth then cachedProfile.Health.Max = packet.MaxHealth end
			end
			if cachedProfile.Mana then
				if packet.Mana then cachedProfile.Mana.Current = packet.Mana end
				if packet.MaxMana then cachedProfile.Mana.Max = packet.MaxMana end
			end
			if cachedProfile.Posture then
				if packet.Posture then cachedProfile.Posture.Current = packet.Posture end
				if packet.MaxPosture then cachedProfile.Posture.Max = packet.MaxPosture end
			end
			if packet.Level then cachedProfile.Level = packet.Level end
			ProfileUpdatedSignal:Fire(cachedProfile)
		end

		CombatDataUpdatedSignal:Fire(combatPacket)
	end
end

local function onServerProfileLoaded(packet: NetworkTypes.ProfileDataPacket)
	updateLocalProfile(packet.ProfileData, true)
end

local function onServerProfileUpdated(packet: NetworkTypes.ProfileDataPacket)
	updateLocalProfile(packet.ProfileData, false)
end

local function requestInitialSync()
	if syncInProgress then return end
	syncInProgress = true

	NetworkController:SendToServer("RequestStateSync", { Timestamp = os.time() })

	task.delay(SYNC_TIMEOUT, function()
		if syncInProgress then
			syncInProgress = false
			StateSyncErrorSignal:Fire("State sync timeout")
		end
	end)
end

local function retrySyncWithBackoff(attempt: number)
	if attempt > MAX_RETRY_ATTEMPTS then
		StateSyncErrorSignal:Fire("Max retry attempts exceeded")
		return
	end
	task.delay(RETRY_DELAY * attempt, function()
		requestInitialSync()
	end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local StateSyncController = {}

function StateSyncController.GetCurrentState(): PlayerState?
	return cachedState
end

function StateSyncController.GetCurrentProfile(): PlayerProfile?
	return cachedProfile
end

function StateSyncController.GetStateChangedSignal()
	return StateChangedSignal
end

function StateSyncController.GetProfileLoadedSignal()
	return ProfileLoadedSignal
end

function StateSyncController.GetProfileUpdatedSignal()
	return ProfileUpdatedSignal
end

function StateSyncController.GetStateSyncErrorSignal()
	return StateSyncErrorSignal
end

function StateSyncController.GetCombatDataUpdatedSignal()
	return CombatDataUpdatedSignal
end

function StateSyncController.GetLastSyncTimestamp(): number
	return lastSyncTimestamp
end

function StateSyncController.IsSyncInProgress(): boolean
	return syncInProgress
end

function StateSyncController.RequestSync()
	requestInitialSync()
end

function StateSyncController:Init(dependencies)
	NetworkController = dependencies.NetworkController
	if not NetworkController then
		error("[StateSyncController] NetworkController dependency not provided")
	end
	print("[StateSyncController] Initialized")
end

function StateSyncController:Start()
	local success, err = pcall(function()
		NetworkController:RegisterHandler("StateSnapshot", onServerStateSnapshot)
		NetworkController:RegisterHandler("ProfileData", onServerProfileLoaded)
		NetworkController:RegisterHandler("ProfileUpdate", onServerProfileUpdated)
	end)

	if not success then
		warn(`[StateSyncController] Failed to register handlers: {err}`)
		task.delay(0.5, function()
			if NetworkController then
				NetworkController:RegisterHandler("StateSnapshot", onServerStateSnapshot)
				NetworkController:RegisterHandler("ProfileData", onServerProfileLoaded)
				NetworkController:RegisterHandler("ProfileUpdate", onServerProfileUpdated)
			end
		end)
	end

	requestInitialSync()
	print("[StateSyncController] STARTED - Listening for state snapshots")
end

function StateSyncController:Shutdown()
	StateChangedSignal:Destroy()
	ProfileLoadedSignal:Destroy()
	ProfileUpdatedSignal:Destroy()
	StateSyncErrorSignal:Destroy()
	CombatDataUpdatedSignal:Destroy()
	print("[StateSyncController] Shutdown complete")
end

return StateSyncController
