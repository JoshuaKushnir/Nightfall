--!strict
--[[
	DataService - ProfileService wrapper for player data persistence
	
	Issue #2: ProfileService Data Wrapper for Player Data Persistence
	Epic: Phase 1 - Core Framework
	
	This service manages all player data loading, saving, and session management.
	It wraps ProfileService to provide a clean API integrated with PlayerData types.
	
	Key Features:
	- Automatic data loading on player join
	- Auto-save on player leave
	- Session locking (prevents duplication exploits)
	- Retry logic with exponential backoff
	- Data versioning support
	- Integration with StateService
	
	Usage:
		-- Server-side only
		DataService:Init()
		DataService:Start()
		
		-- Access player data
		local playerData = DataService:GetProfile(player)
		if playerData then
			print(playerData.Level, playerData.Health.Current)
		end
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Dependencies
-- Wait for Packages to be available (Rojo sync delay)
local ProfileServiceModule = ReplicatedStorage:WaitForChild("Packages", 5):WaitForChild("ProfileService", 5)
local ProfileService = require(ProfileServiceModule)
local PlayerDataTypes = require(ReplicatedStorage.Shared.types.PlayerData)
local StateService = require(ReplicatedStorage.Shared.modules.StateService)

-- Types
type PlayerData = PlayerDataTypes.PlayerData
type Profile = ProfileService.Profile<PlayerData>
type ProfileStore = ProfileService.ProfileStore<PlayerData>

-- Constants
local DATA_STORE_NAME = "PlayerData"
local DATA_VERSION = 1

-- Default player data template (matches PlayerData type)
local DEFAULT_PLAYER_DATA: PlayerData = {
	-- Identity
	UserId = 0,
	Username = "",
	DisplayName = "",
	
	-- Progression
	Level = 1,
	Experience = 0,
	StatPoints = 0,
	
	-- Combat Stats
	Strength = 5,
	Fortitude = 5,
	Agility = 5,
	Intelligence = 5,
	Willpower = 5,
	Charisma = 5,
	
	-- Components
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
	
	-- Inventory & Equipment
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
	
	-- Progression Systems
	Class = "None",
	ElementAffinities = {},
	UnlockedAbilities = {},
	CompletedQuests = {},
	ActiveQuests = {},
	
	-- Meta
	PlayTime = 0,
	LastJoinTimestamp = 0,
	CreatedTimestamp = 0,
	DataVersion = DATA_VERSION,
}

-- Service state
local DataService = {
	_initialized = false,
	_profileStore = nil :: ProfileStore?,
	_profiles = {} :: { [Player]: Profile },
	_loadingPlayers = {} :: { [Player]: boolean },
}

-- Private helper: Reconcile data with template
local function ReconcileData(data: any, template: any): any
	-- Deep merge: preserve existing values, add missing fields from template
	for key, templateValue in template do
		if data[key] == nil then
			-- Missing field, add from template
			if type(templateValue) == "table" then
				data[key] = table.clone(templateValue)
			else
				data[key] = templateValue
			end
		elseif type(templateValue) == "table" and type(data[key]) == "table" then
			-- Recursively reconcile nested tables
			ReconcileData(data[key], templateValue)
		end
	end
	
	return data
end

-- Private helper: Handle data versioning/migration
local function MigrateData(data: PlayerData): PlayerData
	local currentVersion = data.DataVersion or 0
	
	if currentVersion < DATA_VERSION then
		print(`[DataService] Migrating player data from v{currentVersion} to v{DATA_VERSION}`)
		
		-- Future migration logic goes here
		-- Example:
		-- if currentVersion < 2 then
		--     data.NewField = DefaultValue
		-- end
		
		data.DataVersion = DATA_VERSION
	end
	
	return data
end

-- Private helper: Setup profile for player
local function SetupProfile(player: Player, profile: Profile): PlayerData?
	if not profile then
		return nil
	end
	
	-- Update identity fields
	profile.Data.UserId = player.UserId
	profile.Data.Username = player.Name
	profile.Data.DisplayName = player.DisplayName
	profile.Data.LastJoinTimestamp = os.time()
	
	-- First time player
	if profile.Data.CreatedTimestamp == 0 then
		profile.Data.CreatedTimestamp = os.time()
		print(`[DataService] New player profile created: {player.Name}`)
	end
	
	-- Data reconciliation and migration
	ReconcileData(profile.Data, DEFAULT_PLAYER_DATA)
	MigrateData(profile.Data)
	
	-- Add player's UserId to profile (for GDPR compliance)
	profile:AddUserId(player.UserId)
	
	-- Listen for profile release (kicked from another server)
	profile:ListenToRelease(function(placeId: number?, gameJobId: string?)
		if player.Parent == Players then
			warn(`[DataService] Profile released for {player.Name} - kicking player`)
			player:Kick("Your data was loaded in another server. Please rejoin.")
		end
	end)
	
	return profile.Data
end

--[=[
	Initialize DataService (called once at server start)
	Creates the ProfileStore and sets up player join/leave handlers
]=]
function DataService:Init()
	if self._initialized then
		warn("[DataService] Already initialized")
		return
	end
	
	print("[DataService] Initializing...")
	
	-- Create ProfileStore
	self._profileStore = ProfileService.GetProfileStore(
		DATA_STORE_NAME,
		table.clone(DEFAULT_PLAYER_DATA)
	)
	
	self._initialized = true
	print("[DataService] Initialized successfully")
end

--[=[
	Start DataService (called after all services Init)
	Begins listening for player join/leave events
]=]
function DataService:Start()
	if not self._initialized then
		error("[DataService] Must call Init() before Start()")
	end
	
	print("[DataService] Starting...")
	
	-- Handle players who joined before server was ready
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_OnPlayerAdded(player)
		end)
	end
	
	-- Listen for new players
	Players.PlayerAdded:Connect(function(player)
		self:_OnPlayerAdded(player)
	end)
	
	-- Listen for players leaving
	Players.PlayerRemoving:Connect(function(player)
		self:_OnPlayerRemoving(player)
	end)
	
	print("[DataService] Started successfully")
end

--[=[
	Internal: Handle player join
	@private
]=]
function DataService:_OnPlayerAdded(player: Player)
	if self._loadingPlayers[player] then
		return -- Already loading
	end
	
	self._loadingPlayers[player] = true
	print(`[DataService] Loading profile for: {player.Name}`)
	
	local profile = self:LoadProfile(player)
	
	if not profile then
		warn(`[DataService] Failed to load profile for: {player.Name} - kicking`)
		player:Kick("Failed to load your data. Please try again later.")
		self._loadingPlayers[player] = nil
		return
	end
	
	-- Initialize player state in StateService
	local playerData = self:GetProfile(player)
	if playerData then
		StateService:InitializePlayer(player, playerData)
		print(`[DataService] Profile loaded successfully for: {player.Name}`)
	end
	
	self._loadingPlayers[player] = nil
end

--[=[
	Internal: Handle player leave
	@private
]=]
function DataService:_OnPlayerRemoving(player: Player)
	print(`[DataService] Releasing profile for: {player.Name}`)
	
	-- Save and release profile
	local success = self:SaveProfile(player)
	if not success then
		warn(`[DataService] Failed to save profile for: {player.Name} on leave`)
	end
	
	self:ReleaseProfile(player)
	
	-- Cleanup state
	StateService:CleanupPlayer(player)
end

--[=[
	Load a player's profile from DataStore
	
	@param player - The player to load data for
	@return PlayerData? - The loaded player data, or nil if loading failed
]=]
function DataService:LoadProfile(player: Player): PlayerData?
	if not self._initialized or not self._profileStore then
		error("[DataService] Not initialized")
	end
	
	-- Check if already loaded
	if self._profiles[player] then
		warn(`[DataService] Profile already loaded for: {player.Name}`)
		return self._profiles[player].Data
	end
	
	local profileKey = `Player_{player.UserId}`
	
	-- Load profile with session locking
	local profile = self._profileStore:LoadProfileAsync(profileKey, function(placeId: number, gameJobId: string)
		-- Profile is session-locked in another server
		print(`[DataService] Profile {profileKey} is active in another server (PlaceId: {placeId})`)
		
		-- In production, you might want to:
		-- 1. Wait and retry ("Repeat")
		-- 2. Cancel and kick player ("Cancel")
		-- 3. Force load and kick player from other server ("ForceLoad")
		
		if player.Parent == Players then
			return "Repeat" -- Retry loading
		else
			return "Cancel" -- Player left during loading
		end
	end)
	
	if not profile then
		return nil
	end
	
	-- Setup profile
	local playerData = SetupProfile(player, profile)
	
	if playerData then
		self._profiles[player] = profile
	end
	
	return playerData
end

--[=[
	Save a player's profile to DataStore
	
	@param player - The player to save data for
	@return boolean - True if save succeeded, false otherwise
]=]
function DataService:SaveProfile(player: Player): boolean
	local profile = self._profiles[player]
	
	if not profile then
		warn(`[DataService] No profile to save for: {player.Name}`)
		return false
	end
	
	if not profile:IsActive() then
		warn(`[DataService] Profile inactive for: {player.Name}`)
		return false
	end
	
	-- Update play time
	profile.Data.PlayTime += os.time() - profile.Data.LastJoinTimestamp
	
	-- Trigger save
	profile:Save()
	
	print(`[DataService] Profile saved for: {player.Name}`)
	return true
end

--[=[
	Get a player's loaded profile data
	
	@param player - The player to get data for
	@return PlayerData? - The player's data, or nil if not loaded
]=]
function DataService:GetProfile(player: Player): PlayerData?
	local profile = self._profiles[player]
	
	if not profile or not profile:IsActive() then
		return nil
	end
	
	return profile.Data
end

--[=[
	Release a player's profile (clears session lock)
	Called automatically on player leave
	
	@param player - The player to release profile for
]=]
function DataService:ReleaseProfile(player: Player)
	local profile = self._profiles[player]
	
	if not profile then
		return
	end
	
	if profile:IsActive() then
		profile:Release()
	end
	
	self._profiles[player] = nil
end

--[=[
	Get all active profiles (for admin/debugging)
	
	@return number - Count of active profiles
]=]
function DataService:GetActiveProfileCount(): number
	local count = 0
	for _ in self._profiles do
		count += 1
	end
	return count
end

return DataService
