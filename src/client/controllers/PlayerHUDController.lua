--!strict
--[[
	PlayerHUDController.lua
	Manages the player's HUD (Heads Up Display) with reactive data binding.
	
	Demonstrates the UIBinding framework by displaying:
	- Player health
	- Player mana
	- Player level
	- Player state (Idle, Combat, Casting, etc.)
	- Player data (coins, experience)
	
	Architecture:
	- Creates HUD UI elements programmatically
	- Binds UI to StateSyncController state
	- Auto-updates when server state changes
	- Handles profile load and updates
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared

-- Modules
local UIBinding = require(script.Parent.Parent.modules.UIBinding)

-- Types
local PlayerData = require(Shared.types.PlayerData)
type PlayerProfile = PlayerData.PlayerProfile
type PlayerState = PlayerData.PlayerState

-- Controllers (injected via Init)
local StateSyncController = nil

-- UI Elements
local playerGui: PlayerGui
local screenGui: ScreenGui
local hudFrame: Frame
local healthBar: Frame
local manaBar: Frame
local levelLabel: TextLabel
local stateLabel: TextLabel
local coinsLabel: TextLabel
local expLabel: TextLabel

-- State
local profile: PlayerProfile? = nil
local currentState: PlayerState? = nil

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

--[[
	Creates a stat bar (health, mana, etc.)
]]
local function createStatBar(name: string, position: UDim2, barColor: Color3): (Frame, Frame)
	local container = Instance.new("Frame")
	container.Name = name .. "Container"
	container.Size = UDim2.new(0, 200, 0, 25)
	container.Position = position
	container.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	container.BorderSizePixel = 2
	container.BorderColor3 = Color3.fromRGB(100, 100, 100)
	container.Parent = hudFrame
	
	local bar = Instance.new("Frame")
	bar.Name = name .. "Bar"
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.Position = UDim2.new(0, 0, 0, 0)
	bar.BackgroundColor3 = barColor
	bar.BorderSizePixel = 0
	bar.Parent = container
	
	local label = Instance.new("TextLabel")
	label.Name = name .. "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = name .. ": 100/100"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 14
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.5
	label.Parent = container
	
	return container, bar
end

--[[
	Creates a text label for displaying info
]]
local function createInfoLabel(name: string, position: UDim2, text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(0, 200, 0, 20)
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextSize = 16
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextStrokeTransparency = 0.5
	label.Parent = hudFrame
	
	return label
end

--[[
	Creates the HUD UI structure
]]
local function createHUD()
	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 5)
	
	if not playerGui then
		error("[PlayerHUDController] Failed to get PlayerGui")
	end
	
	-- Main ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlayerHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui
	
	-- HUD Frame
	hudFrame = Instance.new("Frame")
	hudFrame.Name = "HUDFrame"
	hudFrame.Size = UDim2.new(0, 250, 0, 200)
	hudFrame.Position = UDim2.new(0, 20, 0, 20)
	hudFrame.BackgroundTransparency = 0.3
	hudFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	hudFrame.BorderSizePixel = 0
	hudFrame.Parent = screenGui
	
	-- Add corner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = hudFrame
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = "NIGHTFALL"
	title.TextColor3 = Color3.fromRGB(200, 150, 255)
	title.TextSize = 18
	title.Font = Enum.Font.GothamBold
	title.Parent = hudFrame
	
	-- Create stat bars
	local _, health = createStatBar("Health", UDim2.new(0, 20, 0, 40), Color3.fromRGB(200, 50, 50))
	healthBar = health
	
	local _, mana = createStatBar("Mana", UDim2.new(0, 20, 0, 75), Color3.fromRGB(50, 100, 200))
	manaBar = mana
	
	-- Create info labels
	levelLabel = createInfoLabel("LevelLabel", UDim2.new(0, 20, 0, 110), "Level: 1")
	stateLabel = createInfoLabel("StateLabel", UDim2.new(0, 20, 0, 135), "State: Loading...")
	coinsLabel = createInfoLabel("CoinsLabel", UDim2.new(0, 20, 0, 160), "Coins: 0")
	expLabel = createInfoLabel("ExpLabel", UDim2.new(0, 20, 0, 185), "EXP: 0/100")
end

--------------------------------------------------------------------------------
-- Binding Functions
--------------------------------------------------------------------------------

--[[
	Sets up reactive bindings for all UI elements
]]
local function setupBindings()
	local profileSignal = StateSyncController.GetProfileUpdatedSignal()
	local stateSignal = StateSyncController.GetStateChangedSignal()
	
	-- Bind health bar
	UIBinding.BindProgress(healthBar, function()
		if not profile then return 0 end
		return profile.CurrentHealth / profile.MaxHealth
	end, profileSignal)
	
	UIBinding.BindText(healthBar.Parent.HealthLabel, function()
		if not profile then return "Health: --/--" end
		return string.format("Health: %d/%d", profile.CurrentHealth, profile.MaxHealth)
	end, profileSignal)
	
	-- Bind mana bar
	UIBinding.BindProgress(manaBar, function()
		if not profile then return 0 end
		return profile.CurrentMana / profile.MaxMana
	end, profileSignal)
	
	UIBinding.BindText(manaBar.Parent.ManaLabel, function()
		if not profile then return "Mana: --/--" end
		return string.format("Mana: %d/%d", profile.CurrentMana, profile.MaxMana)
	end, profileSignal)
	
	-- Bind level
	UIBinding.BindText(levelLabel, function()
		if not profile then return "Level: --" end
		return string.format("Level: %d", profile.Level)
	end, profileSignal)
	
	-- Bind state
	UIBinding.BindText(stateLabel, function()
		if not currentState then return "State: Loading..." end
		return string.format("State: %s", currentState)
	end, stateSignal)
	
	-- Bind coins
	UIBinding.BindText(coinsLabel, function()
		if not profile then return "Coins: --" end
		return string.format("Coins: %d", profile.Coins)
	end, profileSignal)
	
	-- Bind experience
	UIBinding.BindText(expLabel, function()
		if not profile then return "EXP: --/--" end
		local expNeeded = profile.Level * 100 -- Simple calculation
		return string.format("EXP: %d/%d", profile.Experience, expNeeded)
	end, profileSignal)
end

--[[
	Handles profile loaded event
]]
local function onProfileLoaded(newProfile: PlayerProfile)
	profile = newProfile
	print("[PlayerHUDController] Profile loaded:", newProfile)
end

--[[
	Handles profile updated event
]]
local function onProfileUpdated(newProfile: PlayerProfile)
	profile = newProfile
end

--[[
	Handles state changed event
]]
local function onStateChanged(oldState: PlayerState, newState: PlayerState)
	currentState = newState
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local PlayerHUDController = {}

--[[
	Initializes the controller (called by runtime)
]]
function PlayerHUDController:Init(dependencies)
	StateSyncController = dependencies.StateSyncController
	
	if not StateSyncController then
		error("[PlayerHUDController] StateSyncController dependency not provided")
	end
	
	print("[PlayerHUDController] Initialized")
end

--[[
	Starts the controller and creates the HUD (called by runtime)
]]
function PlayerHUDController:Start()
	-- Create HUD UI
	createHUD()
	
	-- Connect to StateSyncController signals
	StateSyncController.GetProfileLoadedSignal():Connect(onProfileLoaded)
	StateSyncController.GetProfileUpdatedSignal():Connect(onProfileUpdated)
	StateSyncController.GetStateChangedSignal():Connect(onStateChanged)
	
	-- Set up reactive bindings
	setupBindings()
	
	-- Get initial state if available
	profile = StateSyncController.GetCurrentProfile()
	currentState = StateSyncController.GetCurrentState()
	
	print("[PlayerHUDController] HUD created and bindings active")
end

--[[
	Cleanup on shutdown (called by runtime)
]]
function PlayerHUDController:Shutdown()
	if screenGui then
		screenGui:Destroy()
	end
	
	UIBinding.DisconnectAll(hudFrame)
	
	print("[PlayerHUDController] Shutdown complete")
end

return PlayerHUDController
