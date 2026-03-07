--!strict
--[[
	Class: StateService (The "Nexus")
	Description: Enhanced centralized state management for all player states in Nightfall
	
	Issue #3: Enhanced State Machine System with Transition Validation
	Epic: Phase 1 - Core Framework
	
	This service acts as the single source of truth for player states.
	All state changes must go through this service to maintain consistency.
	
	New Features:
	- State transition validation matrix (prevents illegal transitions)
	- State history tracking (last 5 states with timestamps)
	- Signal-based state change notifications
	- State duration tracking and analytics
	- Automatic state timeout/expiration
	
	Dependencies: PlayerData types, Signal library
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Import Types
local PlayerDataModule = require(ReplicatedStorage.Shared.types.PlayerData)
type PlayerData = PlayerDataModule.PlayerData
type PlayerState = PlayerDataModule.PlayerState

-- Import Signal library
local Signal = require(ReplicatedStorage.Signal)
type Signal<T...> = Signal.Signal<T...>

-- Service Definition
local StateService = {}
StateService.__index = StateService

-- Private State Storage
local PlayerStates: {[Player]: PlayerData} = {}

-- State history tracking
export type StateHistoryEntry = {
	State: PlayerState,
	Timestamp: number,
	Duration: number?, -- How long they were in this state (set when transitioning out)
}

local PlayerStateHistory: {[Player]: {StateHistoryEntry}} = {}

-- Clash state semantics (added Section 4c):
--   Clashing            : both players have triggered a near-simultaneous
--                          attack. Entry triggered server-side when two
--                          AttackInitiated timestamps fall within tolerance.
--                          Movement/attacking inputs are locked; very short.
--   ClashWindow         : 0.5s follow-up window. Player may choose a
--                          discipline-specific follow-up (parry/counter/dash).
--                          Inputs for other actions are suspended.
--   ClashFollowSuccess  : follow-up executed correctly; grants posture
--                          damage bonus and brief stagger on opponent. Short
--                          exit back to normal states (idle/walking).
--   ClashFollowMiss     : follow-up missed; player is briefly stunned/exposed.
--                          Transitions to Stunned and then resumes.
--
-- State transition validation matrix
-- Maps: CurrentState -> { AllowedNextStates }
local VALID_TRANSITIONS: {[PlayerState]: {[PlayerState]: boolean}} = {
	Idle = {
		Walking = true,
		Running = true,
		Jumping = true,
		Attacking = true,
		Blocking = true,
		Dodging = true,
		Casting = true,
		Stunned = true,
		Ragdolled = true,
		Dead = true,
	},
	Walking = {
		Idle = true,
		Running = true,
		Jumping = true,
		Attacking = true,
		Blocking = true,
		Dodging = true,
		Casting = true,
		Stunned = true,
		Ragdolled = true,
		Dead = true,
	},
	Running = {
		Idle = true,
		Walking = true,
		Jumping = true,
		Attacking = true,
		Dodging = true,
		Stunned = true,
		Ragdolled = true,
		Dead = true,
	},
	Jumping = {
		Idle = true,
		Walking = true,
		Running = true,
		Attacking = true,
		Dodging = true,
		Stunned = true,
		Ragdolled = true,
		Dead = true,
	},
	Attacking = {
		Idle = true,
		Walking = true,
		Stunned = true,
		Ragdolled = true,
		Dead = true,
	},
	Blocking = {
		Idle = true,
		Walking = true,
		Stunned = true,
		Ragdolled = true,
		Dead = true,
	},
	Dodging = {
		Idle = true,
		Walking = true,
		Running = true,
		Stunned = true,
		Ragdolled = true,
		Dead = true,
	},
	Casting = {
		Idle = true,
		Walking = true,
		Stunned = true,
		Ragdolled = true,
		Dead = true,
	},
	Stunned = {
		Idle = true,
		Ragdolled = true,
		Dead = true,
	},
	Suppressed = {
		Idle = true,
		Stunned = true, -- if suppressed triggers stun or other recovery
		Dead = true,
	},
	Ragdolled = {
		Idle = true,
		Dead = true,
	},
	Dead = {
		-- Dead is a terminal state - only admin ForceState can change it
	},

	-- Clash-specific transitions (Section 4c)
	Clashing = {
		ClashWindow = true,
		Dead = true,
	},
	ClashWindow = {
		ClashFollowSuccess = true,
		ClashFollowMiss = true,
		Dead = true,
	},
	ClashFollowSuccess = {
		Idle = true,
		Walking = true,
		-- may also transition to Stunned if follow-up causes stagger
		Stunned = true,
		Dead = true,
	},
	ClashFollowMiss = {
		Stunned = true,
		Idle = true,
		Dead = true,
	},
}

-- State timeout configuration (seconds)
local STATE_TIMEOUTS: {[PlayerState]: number?} = {
	Stunned = 2.0, -- Stun automatically expires after 2 seconds
	Blocking = 10.0, -- Can't hold block forever
	Casting = 5.0, -- Cast timeout (should be handled by ability system)
}

-- Signals
local StateChangedSignal: Signal<Player, PlayerState, PlayerState> = Signal.new()
local StateTimeoutSignal: Signal<Player, PlayerState> = Signal.new()

-- Private State Storage
type PlayerStateData = {
	Data: PlayerData,
	StateStartTime: number,
	TimeoutThread: thread?,
}

-- Private State Storage
type PlayerStateData = {
	Data: PlayerData,
	StateStartTime: number,
	TimeoutThread: thread?,
}

local ExtendedPlayerStates: {[Player]: PlayerStateData} = {}

-- Private helper: Start state timeout timer
local function StartStateTimeout(player: Player, state: PlayerState)
	local timeout = STATE_TIMEOUTS[state]
	if not timeout then
		return -- No timeout for this state
	end
	
	local stateData = ExtendedPlayerStates[player]
	if not stateData then
		return
	end
	
	-- Cancel existing timeout
	if stateData.TimeoutThread then
		task.cancel(stateData.TimeoutThread)
	end
	
	-- Start new timeout
	stateData.TimeoutThread = task.delay(timeout, function()
		if player.Parent == Players and stateData.Data.State == state then
			print(`[StateService] State timeout for {player.Name}: {state} expired after {timeout}s`)
			
			-- Auto-transition to Idle
			StateService:SetPlayerState(player, "Idle")
			
			-- Fire timeout signal
			StateTimeoutSignal:Fire(player, state)
		end
	end)
end

-- Private helper: Add to state history
local function AddToStateHistory(player: Player, oldState: PlayerState, newState: PlayerState, duration: number)
	if not PlayerStateHistory[player] then
		PlayerStateHistory[player] = {}
	end
	
	local history = PlayerStateHistory[player]
	
	-- Add new entry
	table.insert(history, {
		State = oldState,
		Timestamp = os.time(),
		Duration = duration,
	})
	
	-- Keep only last 5 states
	if #history > 5 then
		table.remove(history, 1)
	end
end

--[[
	Initialize a player's state when they join
	@param player The player to initialize
	@param playerData Optional existing player data (from DataService)
	@return PlayerData The initialized player data
]]
function StateService:InitializePlayer(player: Player, playerData: PlayerData?): PlayerData
	assert(player, "Player cannot be nil")
	
	-- Use provided data or create new
	local data: PlayerData = playerData or {
		UserId = player.UserId,
		Username = player.Name,
		DisplayName = player.DisplayName,
		
		Level = 1,
		Experience = 0,
		StatPoints = 0,
		
		Strength = 5,
		Fortitude = 5,
		Agility = 5,
		Intelligence = 5,
		Willpower = 5,
		Charisma = 5,
		
		Health = {
			Current = 100,
			Max = 100,
			Regen = 1.0,
		},
		
		Mana = {
			Current = 100,
			Max = 100,
			Regen = 2.0,
			RegenDelay = 3.0,
		},
		
		Posture = {
			Current = 100,
			Max = 100,
			Regen = 5.0,
			RegenDelay = 2.0,
			Broken = false,
		},
		
		EquippedMantras = {},
		KnownMantras = {},
		Equipment = {
			Weapon = nil,
			Armor = nil,
			Helmet = nil,
			Accessory1 = nil,
			Accessory2 = nil,
		},
		Inventory = {},
		
		Class = "None",
		ElementAffinities = {},
		UnlockedAbilities = {},
		CompletedQuests = {},
		ActiveQuests = {},
		
		PlayTime = 0,
		LastJoinTimestamp = os.time(),
		CreatedTimestamp = data.CreatedTimestamp or os.time(),
		DataVersion = 1,
	}
	
	-- Set initial state
	data.State = "Idle"
	data.LastStateChange = tick()
	
	-- Store extended state data
	ExtendedPlayerStates[player] = {
		Data = data,
		StateStartTime = tick(),
		TimeoutThread = nil,
	}
	
	-- Initialize state history
	PlayerStateHistory[player] = {
		{
			State = "Idle",
			Timestamp = os.time(),
			Duration = nil, -- Current state
		}
	}
	
	-- Legacy compatibility
	PlayerStates[player] = data
	
	return data
end

--[[
	Get a player's current state data
	@param player The player to query
	@return PlayerData|nil The player's data or nil if not found
]]
function StateService:GetPlayerData(player: Player): PlayerData?
	return PlayerStates[player]
end

--[[
	Check if a state transition is valid
	@param player The player to check
	@param newState The state to transition to
	@return boolean Whether the transition is allowed
]]
function StateService:CanTransitionTo(player: Player, newState: PlayerState): boolean
	local playerData = PlayerStates[player]
	if not playerData then
		warn(`[StateService] Cannot check transition for non-existent player: {player.Name}`)
		return false
	end
	
	local currentState = playerData.State
	local allowedTransitions = VALID_TRANSITIONS[currentState]
	
	if not allowedTransitions then
		warn(`[StateService] No transition rules defined for state: {currentState}`)
		return false
	end
	
	return allowedTransitions[newState] == true
end

--[[
	Set a player's state (with validation)
	@param player The player to update
	@param newState The new state to set
	@param force Whether to bypass validation (admin only)
	@return boolean Success status
]]
function StateService:SetPlayerState(player: Player, newState: PlayerState, force: boolean?): boolean
	local stateData = ExtendedPlayerStates[player]
	if not stateData then
		warn(`[StateService] Attempted to set state for non-existent player: {player.Name}`)
		return false
	end
	
	local playerData = stateData.Data
	local oldState = playerData.State
	
	-- Same state, no change needed
	if oldState == newState then
		return true
	end
	
	-- Validate transition (unless forced)
	if not force then
		if not self:CanTransitionTo(player, newState) then
			warn(`[StateService] Invalid state transition for {player.Name}: {oldState} -> {newState}`)
			return false
		end
	end
	
	-- Calculate duration in old state
	local duration = tick() - stateData.StateStartTime
	
	-- Add to history
	AddToStateHistory(player, oldState, newState, duration)
	
	-- Cancel old state timeout
	if stateData.TimeoutThread then
		task.cancel(stateData.TimeoutThread)
		stateData.TimeoutThread = nil
	end
	
	-- Update state
	playerData.State = newState
	playerData.LastStateChange = tick()
	stateData.StateStartTime = tick()
	
	-- Start new state timeout if applicable
	StartStateTimeout(player, newState)
	
	-- Fire state changed signal
	StateChangedSignal:Fire(player, oldState, newState)
	
	print(`[StateService] {player.Name} state: {oldState} -> {newState} (duration: {math.floor(duration * 100) / 100}s)`)
	
	return true
end

--[[
	Force a player into a specific state (admin/debugging)
	Bypasses validation checks
	@param player The player to update
	@param newState The state to force
]]
function StateService:ForceState(player: Player, newState: PlayerState)
	StateService:SetPlayerState(player, newState, true)
end

--[[
	Get a player's state history
	@param player The player to query
	@return {StateHistoryEntry} Array of recent states (last 5)
]]
function StateService:GetStateHistory(player: Player): {StateHistoryEntry}
	return PlayerStateHistory[player] or {}
end

--[[
	Check if a player can perform an action based on their current state
	@param player The player to check
	@return boolean Whether the player can act
]]
function StateService:CanPlayerAct(player: Player): boolean
	local playerData = PlayerStates[player]
	if not playerData then
		return false
	end
	
	-- Players cannot act if stunned, dead, ragdolled, or suppressed
	local blockedStates = {
		Stunned = true,
		Dead = true,
		Ragdolled = true,
		Suppressed = true,
	}
	
	return not blockedStates[playerData.State]
end

--[[
	Get the signal for state changes
	@return Signal<Player, OldState, NewState>
]]
function StateService:GetStateChangedSignal(): Signal<Player, PlayerState, PlayerState>
	return StateChangedSignal
end

--[[
	Get the signal for state timeouts
	@return Signal<Player, ExpiredState>
]]
function StateService:GetStateTimeoutSignal(): Signal<Player, PlayerState>
	return StateTimeoutSignal
end

--[[
	Clean up player state when they leave
	@param player The player to clean up
]]
function StateService:CleanupPlayer(player: Player): ()
	-- Cancel any active timeout
	local stateData = ExtendedPlayerStates[player]
	if stateData and stateData.TimeoutThread then
		task.cancel(stateData.TimeoutThread)
	end
	
	-- Clear data
	PlayerStates[player] = nil
	ExtendedPlayerStates[player] = nil
	PlayerStateHistory[player] = nil
end

--[[
	Initialize the StateService
	Called once on server startup
]]
function StateService:Init(): ()
	print("[StateService] Initializing...")
	
	-- Handle existing players (if hot-reloaded)
	for _, player in Players:GetPlayers() do
		StateService.InitializePlayer(player)
	end
	
	-- Connect to player events
	Players.PlayerRemoving:Connect(StateService.CleanupPlayer)
	
	print("[StateService] Initialized successfully")
	print("[StateService] Features: State validation, History tracking, Signal notifications, Auto-timeouts")
end

return StateService
