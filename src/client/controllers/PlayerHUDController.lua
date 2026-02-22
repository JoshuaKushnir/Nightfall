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
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared

-- Modules
local UIBinding = require(script.Parent.Parent.modules.UIBinding)

-- Types
local PlayerData = require(Shared.types.PlayerData)
type PlayerProfile = PlayerData.PlayerProfile
type PlayerState = PlayerData.PlayerState

-- Controllers (injected via Init)
local StateSyncController = nil
local MovementController = nil

-- UI Elements
local playerGui: PlayerGui
local screenGui: ScreenGui
local hudFrame: Frame
local healthBar: Frame
local manaBar: Frame
local postureBar: Frame
local luminanceBar: Frame
local levelLabel: TextLabel
local stateLabel: TextLabel
local coinsLabel: TextLabel
local expLabel: TextLabel

-- Movement HUD elements (#95)
local movementGui: ScreenGui
local breathBarFill: Frame
local breathLabel: TextLabel
local momentumFill: Frame
local momentumLabel: TextLabel
local exhaustedOverlay: Frame
local movementHudConn: RBXScriptConnection?

-- State
local profile: PlayerProfile? = nil
local currentState: PlayerState? = nil

--------------------------------------------------------------------------------
-- Movement HUD (#95)  Breath bar + Momentum chain
--------------------------------------------------------------------------------

--[[
	Builds the movement HUD anchored bottom-left.
	Two rows:
	  Row 1 — BREATH label + depleting bar (dark-teal fill, red on exhaust)
	  Row 2 — MOMENTUM label + chain fill (grey→orange→gold at 3×)
]]
local function createMovementHUD()
	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 5)

	-- Separate ScreenGui so it never clashes with the main HUD ZIndex
	movementGui = Instance.new("ScreenGui")
	movementGui.Name = "MovementHUD"
	movementGui.ResetOnSpawn = false
	movementGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	movementGui.DisplayOrder = 10
	movementGui.Parent = playerGui

	-- Root panel — bottom-left
	local panel = Instance.new("Frame")
	panel.Name = "MovementPanel"
	panel.Size = UDim2.new(0, 220, 0, 78)
	panel.Position = UDim2.new(0, 16, 1, -94)
	panel.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	panel.BackgroundTransparency = 0.35
	panel.BorderSizePixel = 0
	panel.Parent = movementGui
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel
	local panelPadding = Instance.new("UIPadding")
	panelPadding.PaddingLeft   = UDim.new(0, 12)
	panelPadding.PaddingRight  = UDim.new(0, 12)
	panelPadding.PaddingTop    = UDim.new(0, 10)
	panelPadding.PaddingBottom = UDim.new(0, 10)
	panelPadding.Parent = panel

	-- ── BREATH ROW ──────────────────────────────────────────────
	local breathRowLabel = Instance.new("TextLabel")
	breathRowLabel.Name = "BreathTitle"
	breathRowLabel.Size = UDim2.new(1, 0, 0, 14)
	breathRowLabel.Position = UDim2.new(0, 0, 0, 0)
	breathRowLabel.BackgroundTransparency = 1
	breathRowLabel.Text = "BREATH"
	breathRowLabel.TextColor3 = Color3.fromRGB(160, 210, 220)
	breathRowLabel.TextSize = 11
	breathRowLabel.Font = Enum.Font.GothamBold
	breathRowLabel.TextXAlignment = Enum.TextXAlignment.Left
	breathRowLabel.Parent = panel

	local breathBg = Instance.new("Frame")
	breathBg.Name = "BreathBg"
	breathBg.Size = UDim2.new(1, 0, 0, 16)
	breathBg.Position = UDim2.new(0, 0, 0, 16)
	breathBg.BackgroundColor3 = Color3.fromRGB(30, 35, 42)
	breathBg.BorderSizePixel = 0
	breathBg.Parent = panel
	local breathBgCorner = Instance.new("UICorner")
	breathBgCorner.CornerRadius = UDim.new(0, 4)
	breathBgCorner.Parent = breathBg

	breathBarFill = Instance.new("Frame")
	breathBarFill.Name = "BreathFill"
	breathBarFill.Size = UDim2.new(1, 0, 1, 0)
	breathBarFill.BackgroundColor3 = Color3.fromRGB(56, 182, 190)
	breathBarFill.BorderSizePixel = 0
	breathBarFill.Parent = breathBg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = breathBarFill

	-- Exhausted flash overlay (hidden by default)
	exhaustedOverlay = Instance.new("Frame")
	exhaustedOverlay.Name = "ExhaustedOverlay"
	exhaustedOverlay.Size = UDim2.new(1, 0, 1, 0)
	exhaustedOverlay.BackgroundColor3 = Color3.fromRGB(200, 50, 30)
	exhaustedOverlay.BackgroundTransparency = 1
	exhaustedOverlay.BorderSizePixel = 0
	exhaustedOverlay.ZIndex = 5
	exhaustedOverlay.Parent = breathBg
	local exhaustedCorner = Instance.new("UICorner")
	exhaustedCorner.CornerRadius = UDim.new(0, 4)
	exhaustedCorner.Parent = exhaustedOverlay

	breathLabel = Instance.new("TextLabel")
	breathLabel.Name = "BreathValue"
	breathLabel.Size = UDim2.new(1, 0, 1, 0)
	breathLabel.BackgroundTransparency = 1
	breathLabel.Text = "100"
	breathLabel.TextColor3 = Color3.fromRGB(220, 240, 245)
	breathLabel.TextSize = 11
	breathLabel.Font = Enum.Font.GothamBold
	breathLabel.ZIndex = 6
	breathLabel.Parent = breathBg

	-- ── MOMENTUM ROW ────────────────────────────────────────────
	local momentumRowLabel = Instance.new("TextLabel")
	momentumRowLabel.Name = "MomentumTitle"
	momentumRowLabel.Size = UDim2.new(1, 0, 0, 14)
	momentumRowLabel.Position = UDim2.new(0, 0, 0, 40)
	momentumRowLabel.BackgroundTransparency = 1
	momentumRowLabel.Text = "MOMENTUM"
	momentumRowLabel.TextColor3 = Color3.fromRGB(215, 175, 100)
	momentumRowLabel.TextSize = 11
	momentumRowLabel.Font = Enum.Font.GothamBold
	momentumRowLabel.TextXAlignment = Enum.TextXAlignment.Left
	momentumRowLabel.Parent = panel

	local momentumBg = Instance.new("Frame")
	momentumBg.Name = "MomentumBg"
	momentumBg.Size = UDim2.new(1, 0, 0, 16)
	momentumBg.Position = UDim2.new(0, 0, 0, 56)
	momentumBg.BackgroundColor3 = Color3.fromRGB(30, 28, 20)
	momentumBg.BorderSizePixel = 0
	momentumBg.Parent = panel
	local momentumBgCorner = Instance.new("UICorner")
	momentumBgCorner.CornerRadius = UDim.new(0, 4)
	momentumBgCorner.Parent = momentumBg

	momentumFill = Instance.new("Frame")
	momentumFill.Name = "MomentumFill"
	momentumFill.Size = UDim2.new(0, 0, 1, 0)
	momentumFill.BackgroundColor3 = Color3.fromRGB(160, 110, 30)
	momentumFill.BorderSizePixel = 0
	momentumFill.Parent = momentumBg
	local momentumFillCorner = Instance.new("UICorner")
	momentumFillCorner.CornerRadius = UDim.new(0, 4)
	momentumFillCorner.Parent = momentumFill

	momentumLabel = Instance.new("TextLabel")
	momentumLabel.Name = "MomentumValue"
	momentumLabel.Size = UDim2.new(1, 0, 1, 0)
	momentumLabel.BackgroundTransparency = 1
	momentumLabel.Text = "1.0×"
	momentumLabel.TextColor3 = Color3.fromRGB(230, 200, 140)
	momentumLabel.TextSize = 11
	momentumLabel.Font = Enum.Font.GothamBold
	momentumLabel.ZIndex = 4
	momentumLabel.Parent = momentumBg
end

--[[
	Polled each Heartbeat. Reads MovementController getters and updates
	breath bar, exhausted flash, and momentum fill+colour.
]]
local MOMENTUM_CAP = 3.0
local exhaustPulseTime = 0

local function updateMovementHUD(dt: number)
	if not MovementController then return end

	-- ── Breath ──────────────────────────────────────
	local breath    = MovementController.GetBreath()
	local breathMax = MovementController.GetBreathMax()
	local pct       = math.clamp(breath / breathMax, 0, 1)

	-- Smooth the bar width
	breathBarFill.Size = breathBarFill.Size:Lerp(
		UDim2.new(pct, 0, 1, 0),
		math.min(1, dt * 8)
	)

	-- Text
	breathLabel.Text = tostring(math.floor(breath))

	-- Colour: teal → yellow → orange as Breath gets low
	if pct > 0.5 then
		breathBarFill.BackgroundColor3 = Color3.fromRGB(56, 182, 190)
	elseif pct > 0.2 then
		breathBarFill.BackgroundColor3 = Color3.fromRGB(210, 170, 50)
	else
		breathBarFill.BackgroundColor3 = Color3.fromRGB(210, 60, 40)
	end

	-- Exhausted flash overlay
	local exhausted = MovementController.IsBreathExhausted()
	if exhausted then
		exhaustPulseTime += dt * 4
		local alpha = 0.5 + 0.4 * math.sin(exhaustPulseTime)
		exhaustedOverlay.BackgroundTransparency = 1 - alpha * 0.55
	else
		exhaustPulseTime = 0
		exhaustedOverlay.BackgroundTransparency = 1
	end

	-- ── Momentum ────────────────────────────────────
	local mult = MovementController.GetMomentumMultiplier()
	local mPct = math.clamp((mult - 1.0) / (MOMENTUM_CAP - 1.0), 0, 1)

	-- Smooth fill
	momentumFill.Size = momentumFill.Size:Lerp(
		UDim2.new(mPct, 0, 1, 0),
		math.min(1, dt * 6)
	)

	-- Colour: dull gold → bright orange → blazing gold at cap
	if mPct < 0.5 then
		momentumFill.BackgroundColor3 = Color3.fromRGB(130, 90, 25)
	elseif mPct < 0.85 then
		momentumFill.BackgroundColor3 = Color3.fromRGB(210, 130, 30)
	else
		momentumFill.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
	end

	-- Label shows multiplier; "MAX" when at cap
	if mult >= MOMENTUM_CAP - 0.01 then
		momentumLabel.Text = "MAX"
		momentumLabel.TextColor3 = Color3.fromRGB(255, 230, 80)
	else
		momentumLabel.Text = string.format("%.1f×", mult)
		momentumLabel.TextColor3 = Color3.fromRGB(230, 200, 140)
	end
end

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
	
	local _, posture = createStatBar("Posture", UDim2.new(0, 20, 0, 110), Color3.fromRGB(180, 160, 50))
	postureBar = posture
	
	local _, lumin = createStatBar("Luminance", UDim2.new(0, 20, 0, 145), Color3.fromRGB(240, 240, 200))
	luminanceBar = lumin
	
	-- Create info labels (shifted down)
	levelLabel = createInfoLabel("LevelLabel", UDim2.new(0, 20, 0, 180), "Level: 1")
	stateLabel = createInfoLabel("StateLabel", UDim2.new(0, 20, 0, 205), "State: Loading...")
	coinsLabel = createInfoLabel("CoinsLabel", UDim2.new(0, 20, 0, 230), "Coins: 0")
	expLabel = createInfoLabel("ExpLabel", UDim2.new(0, 20, 0, 255), "EXP: 0/100")
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

	-- Bind posture bar
	UIBinding.BindProgress(postureBar, function()
		if not profile then return 0 end
		return profile.CurrentPosture / profile.MaxPosture
	end, profileSignal)
	
	UIBinding.BindText(postureBar.Parent.PostureLabel, function()
		if not profile then return "Posture: --/--" end
		return string.format("Posture: %d/%d", profile.CurrentPosture, profile.MaxPosture)
	end, profileSignal)

	-- Bind luminance bar
	UIBinding.BindProgress(luminanceBar, function()
		if not profile then return 0 end
		local lum = profile.Luminance or 0
		-- assume a 0-100 cap until mechanic is implemented
		return math.clamp(lum / 100, 0, 1)
	end, profileSignal)
	
	UIBinding.BindText(luminanceBar.Parent.LuminanceLabel, function()
		if not profile then return "Luminance: --" end
		return string.format("Luminance: %d", profile.Luminance or 0)
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
	MovementController  = dependencies.MovementController

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

	-- Create Movement HUD (#95)
	createMovementHUD()
	movementHudConn = RunService.Heartbeat:Connect(updateMovementHUD)

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
	if movementHudConn then
		movementHudConn:Disconnect()
		movementHudConn = nil
	end
	if movementGui then
		movementGui:Destroy()
	end
	if screenGui then
		screenGui:Destroy()
	end

	UIBinding.DisconnectAll(hudFrame)

	print("[PlayerHUDController] Shutdown complete")
end

return PlayerHUDController
