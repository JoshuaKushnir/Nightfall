--!strict
--[[
	Class: StateSyncService
	Description: Handles server-side state synchronization with clients using event-level snapshots.
	Dependencies: StateService, NetworkTypes, PlayerDataTypes, RunService
	Usage: Injected via framework.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Dependencies
local StateService = require(ReplicatedStorage.Shared.modules.StateService)
local NetworkTypes = require(ReplicatedStorage.Shared.types.NetworkTypes)
local PlayerDataTypes = require(ReplicatedStorage.Shared.types.PlayerData)

-- Services (injected via Init)
local NetworkService = nil
local DataService = nil

-- Types
type PlayerState = PlayerDataTypes.PlayerState
type PlayerProfile = PlayerDataTypes.PlayerProfile
type StateSnapshotPacket = NetworkTypes.StateSnapshotPacket

-- State
local SYNC_RATE = 1 / 20 -- 20 Hz snapshot rate
local accumulatedSnapshots: {[Player]: StateSnapshotPacket} = {}
local heartbeatConnection: RBXScriptConnection? = nil
local timeSinceLastSync = 0

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
	Initialize a snapshot for a player if it doesn't exist
]]
local function getOrInitSnapshot(player: Player): StateSnapshotPacket
	if not accumulatedSnapshots[player] then
		accumulatedSnapshots[player] = {
			Timestamp = os.time(),
		}
	end
	return accumulatedSnapshots[player]
end

--[[
	Sends current profile data to a player
]]
local function sendProfileToClient(player: Player, isInitialLoad: boolean)
	local profileData = DataService:GetProfile(player)
	if not profileData then
		warn("[StateSyncService] No profile found for player:", player.Name)
		return
	end

	local profile: PlayerProfile = {
		UserId = profileData.UserId,
		DisplayName = profileData.DisplayName,
		Level = profileData.Level,
		Experience = profileData.Experience,
		Health = {
			Current = profileData.Health.Current,
			Max = profileData.Health.Max,
		},
		Mana = {
			Current = profileData.Mana.Current,
			Max = profileData.Mana.Max,
		},
		Posture = {
			Current = profileData.Posture.Current,
			Max = profileData.Posture.Max,
		},
		Luminance = profileData.Luminance and {
			Current = profileData.Luminance.Current,
			Max = profileData.Luminance.Max,
		} or nil,
		EquippedMantras = profileData.EquippedMantras,
		Class = profileData.Class,
		Coins = 0,
	}

	local packet: NetworkTypes.ProfileDataPacket = {
		ProfileData = profile
	}

	if isInitialLoad then
		NetworkService:SendToClient(player, "ProfileData", packet)
	else
		NetworkService:SendToClient(player, "ProfileUpdate", packet)
	end
end

--[[
	Handles state sync request from client
]]
local function onRequestStateSync(player: Player, packet: any)
	-- Queue initial state snapshot
	local state = StateService:GetState(player)
	if state then
		local snapshot = getOrInitSnapshot(player)
		snapshot.State = state
		snapshot.Timestamp = os.time()
	end

	sendProfileToClient(player, true)
	print("[StateSyncService] Queued initial sync and sent profile to:", player.Name)
end

--[[
	Handles state change events and queues them
]]
local function onStateChanged(player: Player, oldState: PlayerState, newState: PlayerState)
	local snapshot = getOrInitSnapshot(player)
	snapshot.State = newState
	snapshot.Timestamp = os.time()
end

--[[
	Handles player data changes and notifies client
]]
local function onPlayerDataChanged(player: Player)
	sendProfileToClient(player, false)
end

--[[
	Queues combat data changes (health, mana, etc.)
]]
local function queueCombatUpdate(player: Player)
	local profileData = DataService:GetProfile(player)
	if not profileData then
		warn(`[StateSyncService] queueCombatUpdate failed: no profile found for {player.Name}`)
		return
	end

	local snapshot = getOrInitSnapshot(player)
	snapshot.Health = profileData.Health.Current
	snapshot.MaxHealth = profileData.Health.Max
	snapshot.Mana = profileData.Mana.Current
	snapshot.MaxMana = profileData.Mana.Max
	snapshot.Posture = profileData.Posture.Current
	snapshot.MaxPosture = profileData.Posture.Max
	snapshot.Level = profileData.Level
	snapshot.Timestamp = os.time()
end

--[[
	Process and send all queued snapshots
]]
local function flushSnapshots(dt: number)
	timeSinceLastSync += dt
	if timeSinceLastSync >= SYNC_RATE then
		timeSinceLastSync = 0

		for player, snapshot in pairs(accumulatedSnapshots) do
			if player and player.Parent then
				NetworkService:SendToClient(player, "StateSnapshot", snapshot)
			end
		end

		-- Clear snapshots after sending
		table.clear(accumulatedSnapshots)
	end
end

--[[
	Cleanup when player leaves
]]
local function onPlayerRemoving(player: Player)
	accumulatedSnapshots[player] = nil
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local StateSyncService = {}

function StateSyncService:Init(dependencies)
	NetworkService = dependencies.NetworkService
	DataService = dependencies.DataService

	if not NetworkService then
		error("[StateSyncService] NetworkService dependency not provided")
	end
	if not DataService then
		error("[StateSyncService] DataService dependency not provided")
	end

	print("[StateSyncService] Initialized")
end

function StateSyncService:Start()
	NetworkService:RegisterHandler("RequestStateSync", onRequestStateSync)

	local stateChangedSignal = StateService:GetStateChangedSignal()
	stateChangedSignal:Connect(onStateChanged)

	Players.PlayerRemoving:Connect(onPlayerRemoving)

	heartbeatConnection = RunService.Heartbeat:Connect(flushSnapshots)

	print("[StateSyncService] Started - Snapshot architecture running")
end

function StateSyncService.SyncPlayer(player: Player)
	local state = StateService:GetState(player)
	if state then
		local snapshot = getOrInitSnapshot(player)
		snapshot.State = state
		snapshot.Timestamp = os.time()
	end
	sendProfileToClient(player, false)
end

function StateSyncService.SendCombatUpdate(player: Player)
	queueCombatUpdate(player)
end

function StateSyncService:Shutdown()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	table.clear(accumulatedSnapshots)
	print("[StateSyncService] Shutdown complete")
end

return StateSyncService
