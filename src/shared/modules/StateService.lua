--!strict
--[[
	Class: StateService (The "Nexus")
	Description: Centralized state management for all player states in Nightfall
	Dependencies: PlayerData types
	
	This service acts as the single source of truth for player states.
	All state changes must go through this service to maintain consistency.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Import Types
local PlayerDataModule = require(ReplicatedStorage.Shared.types.PlayerData)
type PlayerData = PlayerDataModule.PlayerData
type PlayerState = PlayerDataModule.PlayerState

-- Service Definition
local StateService = {}
StateService.__index = StateService

-- Private State Storage
local PlayerStates: {[Player]: PlayerData} = {}

--[[
	Initialize a player's state when they join
	@param player The player to initialize
	@return PlayerData The initialized player data
]]
function StateService.InitializePlayer(player: Player): PlayerData
	assert(player, "Player cannot be nil")
	
	local playerData: PlayerData = {
		UserId = player.UserId,
		DisplayName = player.DisplayName,
		
		Health = {
			Current = 100,
			Max = 100,
		},
		
		Mana = {
			Current = 100,
			Max = 100,
			Regeneration = 5,
		},
		
		Posture = {
			Current = 100,
			Max = 100,
			Broken = false,
		},
		
		State = "Idle",
		LastStateChange = tick(),
		
		Mantras = {},
		ActiveCooldowns = {},
		
		Level = 1,
		Experience = 0,
	}
	
	PlayerStates[player] = playerData
	return playerData
end

--[[
	Get a player's current state data
	@param player The player to query
	@return PlayerData|nil The player's data or nil if not found
]]
function StateService.GetPlayerData(player: Player): PlayerData?
	return PlayerStates[player]
end

--[[
	Set a player's state (with validation)
	@param player The player to update
	@param newState The new state to set
	@return boolean Success status
]]
function StateService.SetPlayerState(player: Player, newState: PlayerState): boolean
	local playerData = PlayerStates[player]
	if not playerData then
		warn("Attempted to set state for non-existent player:", player.Name)
		return false
	end
	
	-- State-specific validation could go here
	playerData.State = newState
	playerData.LastStateChange = tick()
	
	return true
end

--[[
	Check if a player can perform an action based on their current state
	@param player The player to check
	@return boolean Whether the player can act
]]
function StateService.CanPlayerAct(player: Player): boolean
	local playerData = PlayerStates[player]
	if not playerData then
		return false
	end
	
	-- Players cannot act if stunned, dead, or ragdolled
	local blockedStates = {
		Stunned = true,
		Dead = true,
		Ragdolled = true,
	}
	
	return not blockedStates[playerData.State]
end

--[[
	Clean up player state when they leave
	@param player The player to clean up
]]
function StateService.CleanupPlayer(player: Player): ()
	PlayerStates[player] = nil
end

--[[
	Initialize the StateService
	Called once on server startup
]]
function StateService.Init(): ()
	print("[StateService] Initializing...")
	
	-- Handle existing players (if hot-reloaded)
	for _, player in Players:GetPlayers() do
		StateService.InitializePlayer(player)
	end
	
	-- Connect to player events
	Players.PlayerRemoving:Connect(StateService.CleanupPlayer)
	
	print("[StateService] Initialized successfully")
end

return StateService
