--!strict
--[[
	StateSyncService.lua
	Handles server-side state synchronization with clients.

	Responsibilities:
	- Responds to client state sync requests
	- Sends state updates to clients when state changes
	- Sends profile updates to clients when data changes
	- Manages sync timing and throttling

	Architecture:
	- Listens for RequestStateSync events
	- Connects to StateService signals for state changes
	- Connects to DataService for profile updates
	- Sends updates via NetworkService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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

-- State
local lastSyncTimestamp: {[Player]: number} = {}
local SYNC_THROTTLE: number = 0.5 -- Minimum time between syncs (seconds)

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
	Checks if enough time has passed since last sync
]]
local function canSync(player: Player): boolean
	local lastSync = lastSyncTimestamp[player] or 0
	return (os.time() - lastSync) >= SYNC_THROTTLE
end

--[[
	Sends current state to a player
]]
local function sendStatToClient(player: Player)
	if not canSync(player) then
		return
	end

	local state = StateService:GetState(player)
	if not state then
		warn("[StateSyncService] No state found for player:", player.Name)
		return
	end

	-- Create state change packet
	local packet: NetworkTypes.StateChangePacket = {
		NewState = state,
		Timestamp = os.time()
	}

	NetworkService:SendToClient(player, "StateChanged", packet)
	lastSyncTimestamp[player] = os.time()
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

	-- Convert PlayerData to PlayerProfile (nested structure for nested component tables)
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
		Coins = 0, -- TODO: Add coins to PlayerData
	}

	-- Create profile data packet
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
	-- Send current state and profile
	sendStatToClient(player)
	sendProfileToClient(player, true)

	print("[StateSyncService] Sent initial sync to:", player.Name)
end

--[[
	Handles state change events and notifies client
]]
local function onStateChanged(player: Player, oldState: PlayerState, newState: PlayerState)
	-- Notify client of state change
	local packet: NetworkTypes.StateChangePacket = {
		NewState = newState,
		Timestamp = os.time()
	}

	NetworkService:SendToClient(player, "StateChanged", packet)
end

--[[
	Handles player data changes and notifies client
]]
local function onPlayerDataChanged(player: Player)
	sendProfileToClient(player, false)
end

--[[
	Handles combat data changes (health, mana, etc.)
]]
local function sendCombatUpdate(player: Player)
	local profileData = DataService:GetProfile(player)
	if not profileData then
		warn(`[StateSyncService] sendCombatUpdate failed: no profile found for {player.Name}`)
		return
	end

	local packet: NetworkTypes.CombatDataPacket = {
		Health = profileData.Health.Current,
		MaxHealth = profileData.Health.Max,
		Mana = profileData.Mana.Current,
		MaxMana = profileData.Mana.Max,
		Posture = profileData.Posture.Current,
		MaxPosture = profileData.Posture.Max,
		Level = profileData.Level,
	}

	print(`[StateSyncService] Sending CombatData to {player.Name}: HP={packet.Health}, Mana={packet.Mana}, Posture={packet.Posture}`)
	NetworkService:SendToClient(player, "CombatData", packet)
end

--[[
	Cleanup when player leaves
]]
local function onPlayerRemoving(player: Player)
	lastSyncTimestamp[player] = nil
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local StateSyncService = {}

--[[
	Initializes the service (called by runtime)
]]
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

--[[
	Starts the service and registers handlers (called by runtime)
]]
function StateSyncService:Start()
	-- Register network event handlers
	NetworkService:RegisterHandler("RequestStateSync", onRequestStateSync)

	-- Connect to StateService signals
	local stateChangedSignal = StateService:GetStateChangedSignal()
	stateChangedSignal:Connect(onStateChanged)

	-- Connect to player events
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	print("[StateSyncService] Started - Ready to sync state with clients")
end

--[[
	Manually trigger a state sync for a player
]]
function StateSyncService.SyncPlayer(player: Player)
	sendStatToClient(player)
	sendProfileToClient(player, false)
end

--[[
	Send combat update to a specific player
]]
function StateSyncService.SendCombatUpdate(player: Player)
	sendCombatUpdate(player)
end

--[[
	Cleanup on shutdown (called by runtime)
]]
function StateSyncService:Shutdown()
	table.clear(lastSyncTimestamp)
	print("[StateSyncService] Shutdown complete")
end

return StateSyncService
