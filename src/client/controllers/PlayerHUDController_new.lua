--!strict
--[[
	PlayerHUDController.lua (Refactored)
	
	Manages the player's HUD (Heads Up Display) with reactive data binding.
	
	Refactored to use UITheme, HUDPrimitives, and HUDLayout for consistency
	and easy editing. Maintains 100% behavioral parity with previous version.
	
	Components:
	- Core HUD: health, mana, level, state labels
	- Movement HUD: breath meter, momentum meter with color thresholds
	- Resonance HUD: resonance points and shard count
	- Zone notifications: animated ring/zone entry display
	- Toast system: unified notification display
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared

-- Modules
local UIBinding = require(script.Parent.Parent.modules.UIBinding)
local UITheme = require(script.Parent.Parent.modules.UITheme)
local HUDPrimitives = require(script.Parent.Parent.modules.HUDPrimitives)
local HUDLayout = require(script.Parent.Parent.modules.HUDLayout)
local AspectRegistry = require(Shared.modules.AspectRegistry)

-- Types
local PlayerData = require(Shared.types.PlayerData)
type PlayerProfile = PlayerData.PlayerProfile
type PlayerState = PlayerData.PlayerState

-- Controllers (injected via Init)
local StateSyncController: any = nil
local MovementController: any = nil
local NetworkController: any = nil
local ProgressionController: any = nil

-- UI Root ScreenGuis
local playerGui: PlayerGui
local screenGui: ScreenGui           -- Core HUD
local movementGui: ScreenGui         -- Movement HUD (breath + momentum)
local resonanceGui: ScreenGui        -- Resonance display

-- Core HUD Elements
local hudFrame: Frame
local healthBar: Frame
local manaBar: Frame
local levelLabel: TextLabel
local stateLabel: TextLabel
local coinsLabel: TextLabel
local expLabel: TextLabel

-- Movement HUD Elements
local breathBarFill: Frame
local breathLabel: TextLabel
local momentumFill: Frame
local momentumLabel: TextLabel
local exhaustedOverlay: Frame
local movementHudConn: RBXScriptConnection?

-- Resonance HUD Elements
local resonanceLabel: TextLabel
local shardsLabel: TextLabel

-- Zone Notification Elements
local zoneFrame: Frame
local zoneTopDiv: Frame
local zoneBotDiv: Frame
local zoneNameLabel: TextLabel
local zoneFadeThread: thread?

-- Toast Container
local toastContainer: Frame?

-- State
local profile: PlayerProfile? = nil
local currentState: PlayerState? = nil

-- Movement HUD Animation State
local MOMENTUM_CAP = 3.0
local exhaustPulseTime = 0

--------------------------------------------------------------------------------
-- Movement HUD
--------------------------------------------------------------------------------

local function createMovementHUD()
	playerGui = playerGui or Players.LocalPlayer:WaitForChild("PlayerGui", 5)

	movementGui = Instance.new("ScreenGui")
	movementGui.Name = "MovementHUD"
	movementGui.ResetOnSpawn = false
	movementGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	movementGui.DisplayOrder = HUDLayout.Layers.HUD + 1
	movementGui.Parent = playerGui

	-- Position: bottom-left
	local panel = HUDPrimitives.PanelShell("MovementPanel", UDim2.new(0, 220, 0, 78))
	panel.Root.Position = HUDLayout.PositionBottomLeft(0, 0, 78)
	panel.Root.Parent = movementGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UITheme.Spacing.GapSmall
	layout.Parent = panel.Content

	-- ── BREATH ROW ──────────────────────────────────────────────

	local breathTitle = HUDPrimitives.Label("BREATH", UITheme.Typography.SizeSmall, UITheme.Palette.BreathTeal, true)
	breathTitle.Parent = panel.Content

	local breathBg = Instance.new("Frame")
	breathBg.Name = "BreathBg"
	breathBg.Size = UDim2.new(1, 0, 0, 16)
	breathBg.BackgroundColor3 = UITheme.Palette.PanelMid
	breathBg.BorderSizePixel = 0
	HUDPrimitives.applyCorner(breathBg, UITheme.Corners.Small)
	breathBg.Parent = panel.Content

	breathBarFill = Instance.new("Frame")
	breathBarFill.Name = "BreathFill"
	breathBarFill.Size = UDim2.new(1, 0, 1, 0)
	breathBarFill.BackgroundColor3 = UITheme.Palette.BreathTeal
	breathBarFill.BorderSizePixel = 0
	HUDPrimitives.applyCorner(breathBarFill, UITheme.Corners.Small)
	breathBarFill.Parent = breathBg

	-- Exhausted flash overlay
	exhaustedOverlay = Instance.new("Frame")
	exhaustedOverlay.Name = "ExhaustedOverlay"
	exhaustedOverlay.Size = UDim2.new(1, 0, 1, 0)
	exhaustedOverlay.BackgroundColor3 = UITheme.Palette.BreathRed
	exhaustedOverlay.BackgroundTransparency = 1
	exhaustedOverlay.BorderSizePixel = 0
	exhaustedOverlay.ZIndex = 5
	HUDPrimitives.applyCorner(exhaustedOverlay, UITheme.Corners.Small)
	exhaustedOverlay.Parent = breathBg

	breathLabel = Instance.new("TextLabel")
	breathLabel.Name = "BreathValue"
	breathLabel.Size = UDim2.new(1, 0, 1, 0)
	breathLabel.BackgroundTransparency = 1
	breathLabel.TextColor3 = UITheme.Palette.TextPrimary
	breathLabel.TextSize = UITheme.Typography.SizeSmall
	breathLabel.Font = UITheme.Typography.FontBold
	breathLabel.ZIndex = 6
	breathLabel.Parent = breathBg

	-- ── MOMENTUM ROW ────────────────────────────────────────────

	local momentumTitle = HUDPrimitives.Label("MOMENTUM", UITheme.Typography.SizeSmall, UITheme.Palette.MomentumGold, true)
	momentumTitle.Parent = panel.Content

	local momentumBg = Instance.new("Frame")
	momentumBg.Name = "MomentumBg"
	momentumBg.Size = UDim2.new(1, 0, 0, 16)
	momentumBg.BackgroundColor3 = UITheme.Palette.PanelMid
	momentumBg.BorderSizePixel = 0
	HUDPrimitives.applyCorner(momentumBg, UITheme.Corners.Small)
	momentumBg.Parent = panel.Content

	momentumFill = Instance.new("Frame")
	momentumFill.Name = "MomentumFill"
	momentumFill.Size = UDim2.new(0, 0, 1, 0)
	momentumFill.BackgroundColor3 = UITheme.Palette.MomentumGold
	momentumFill.BorderSizePixel = 0
	HUDPrimitives.applyCorner(momentumFill, UITheme.Corners.Small)
	momentumFill.Parent = momentumBg

	momentumLabel = Instance.new("TextLabel")
	momentumLabel.Name = "MomentumValue"
	momentumLabel.Size = UDim2.new(1, 0, 1, 0)
	momentumLabel.BackgroundTransparency = 1
	momentumLabel.TextColor3 = UITheme.Palette.TextAccent
	momentumLabel.TextSize = UITheme.Typography.SizeSmall
	momentumLabel.Font = UITheme.Typography.FontBold
	momentumLabel.ZIndex = 4
	momentumLabel.Parent = momentumBg
end

local function updateMovementHUD(dt: number)
	if not MovementController then return end

	-- ── Breath ──────────────────────────────────────
	local breath = MovementController.GetBreath()
	local breathMax = MovementController.GetBreathMax()
	local pct = math.clamp(breath / breathMax, 0, 1)

	-- Smooth the bar width
	breathBarFill.Size = breathBarFill.Size:Lerp(
		UDim2.new(pct, 0, 1, 0),
		math.min(1, dt * 8)
	)

	-- Text
	breathLabel.Text = tostring(math.floor(breath))

	-- Color: teal → yellow → red as Breath gets low
	if pct > UITheme.BarThresholds.BreathSafeThreshold then
		breathBarFill.BackgroundColor3 = UITheme.Palette.BreathTeal
	elseif pct > UITheme.BarThresholds.BreathWarningThreshold then
		breathBarFill.BackgroundColor3 = UITheme.Palette.BreathYellow
	else
		breathBarFill.BackgroundColor3 = UITheme.Palette.BreathRed
	end

	-- Exhausted flash overlay (pulsing when exhausted)
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

	-- Color: dull gold → orange → blazing gold
	if mPct < UITheme.BarThresholds.MomentumLowThreshold then
		momentumFill.BackgroundColor3 = UITheme.Palette.MomentumGold
	elseif mPct < UITheme.BarThresholds.MomentumHighThreshold then
		momentumFill.BackgroundColor3 = UITheme.Palette.MomentumOrange
	else
		momentumFill.BackgroundColor3 = UITheme.Palette.MomentumBright
	end

	-- Label shows multiplier; "MAX" when at cap
	if mult >= MOMENTUM_CAP - 0.01 then
		momentumLabel.Text = "MAX"
		momentumLabel.TextColor3 = UITheme.Palette.TextAccent
	else
		momentumLabel.Text = string.format("%.1f×", mult)
		momentumLabel.TextColor3 = UITheme.Palette.TextAccent
	end
end

--------------------------------------------------------------------------------
-- Resonance HUD
--------------------------------------------------------------------------------

local function updateResonanceDisplay(state: any)
	if resonanceLabel then
		resonanceLabel.Text = tostring(state.TotalResonance or 0)
	end
	if shardsLabel then
		shardsLabel.Text = tostring(state.ResonanceShards or 0)
	end
end

local function createResonanceHUD()
	playerGui = playerGui or Players.LocalPlayer:WaitForChild("PlayerGui", 5)

	resonanceGui = Instance.new("ScreenGui")
	resonanceGui.Name = "ResonanceHUD"
	resonanceGui.ResetOnSpawn = false
	resonanceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	resonanceGui.DisplayOrder = HUDLayout.Layers.HUD + 2
	resonanceGui.Parent = playerGui

	-- Position: bottom-right
	local panel = HUDPrimitives.PanelShell("ResonancePanel", UDim2.new(0, 160, 0, 60))
	panel.Root.Position = HUDLayout.PositionBottomRight(0, 0, 160, 60)
	panel.Root.Parent = resonanceGui

	-- Layout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UITheme.Spacing.GapSmall
	layout.Parent = panel.Content

	-- Resonance chip
	local resonanceChip = HUDPrimitives.ValueChip("ResonanceChip", "RESONANCE", "0")
	resonanceChip.Label.TextColor3 = UITheme.Palette.TextSecondary
	resonanceChip.Value.TextColor3 = UITheme.Palette.TextAccent
	resonanceLabel = resonanceChip.Value
	resonanceChip.Root.Parent = panel.Content

	-- Shards chip
	local shardsChip = HUDPrimitives.ValueChip("ShardsChip", "SHARDS", "0")
	shardsChip.Label.TextColor3 = UITheme.Palette.TextSecondary
	shardsChip.Value.TextColor3 = UITheme.Palette.TextAccent
	shardsLabel = shardsChip.Value
	shardsChip.Root.Parent = panel.Content
end

--------------------------------------------------------------------------------
-- Core HUD
--------------------------------------------------------------------------------

local function createCoreHUD()
	playerGui = playerGui or Players.LocalPlayer:WaitForChild("PlayerGui", 5)

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlayerHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = HUDLayout.Layers.HUD
	screenGui.Parent = playerGui

	-- Main panel
	local panel = HUDPrimitives.PanelShell("CoreHUD", UDim2.new(0, 280, 0, 200))
	panel.Root.Position = HUDLayout.CoreHUDPosition()
	panel.Root.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UITheme.Spacing.GapMedium
	layout.Parent = panel.Content

	-- Title
	local title = HUDPrimitives.Label("NIGHTFALL", UITheme.Typography.SizeLarge, UITheme.Palette.TextAccent, true)
	title.Parent = panel.Content

	-- Create stat bars
	local healthBarContainer = Instance.new("Frame")
	healthBarContainer.Size = UDim2.new(1, 0, 0, 32)
	healthBarContainer.BackgroundTransparency = 1
	healthBarContainer.Parent = panel.Content

	local healthLabel = HUDPrimitives.Label("HEALTH", UITheme.Typography.SizeSmall, UITheme.Palette.TextSecondary, true)
	healthLabel.Size = UDim2.new(1, 0, 0, 14)
	healthLabel.Parent = healthBarContainer

	healthBar = Instance.new("Frame")
	healthBar.Name = "HealthFill"
	healthBar.Size = UDim2.new(1, 0, 0, 14)
	healthBar.Position = UDim2.new(0, 0, 0, 16)
	healthBar.BackgroundColor3 = UITheme.Palette.HealthGreen
	healthBar.BorderSizePixel = 0
	HUDPrimitives.applyCorner(healthBar, UITheme.Corners.Small)
	healthBar.Parent = healthBarContainer

	local manaBarContainer = Instance.new("Frame")
	manaBarContainer.Size = UDim2.new(1, 0, 0, 32)
	manaBarContainer.BackgroundTransparency = 1
	manaBarContainer.Parent = panel.Content

	local manaLabel = HUDPrimitives.Label("MANA", UITheme.Typography.SizeSmall, UITheme.Palette.TextSecondary, true)
	manaLabel.Size = UDim2.new(1, 0, 0, 14)
	manaLabel.Parent = manaBarContainer

	manaBar = Instance.new("Frame")
	manaBar.Name = "ManaFill"
	manaBar.Size = UDim2.new(1, 0, 0, 14)
	manaBar.Position = UDim2.new(0, 0, 0, 16)
	manaBar.BackgroundColor3 = UITheme.Palette.AccentGold
	manaBar.BorderSizePixel = 0
	HUDPrimitives.applyCorner(manaBar, UITheme.Corners.Small)
	manaBar.Parent = manaBarContainer

	-- Info labels
	levelLabel = HUDPrimitives.Label("Level: --", UITheme.Typography.SizeSmall, UITheme.Palette.TextPrimary)
	levelLabel.Parent = panel.Content

	stateLabel = HUDPrimitives.Label("State: Loading", UITheme.Typography.SizeSmall, UITheme.Palette.TextSecondary)
	stateLabel.Parent = panel.Content

	coinsLabel = HUDPrimitives.Label("Coins: 0", UITheme.Typography.SizeSmall, UITheme.Palette.TextPrimary)
	coinsLabel.Parent = panel.Content

	expLabel = HUDPrimitives.Label("XP: 0/0", UITheme.Typography.SizeSmall, UITheme.Palette.TextPrimary)
	expLabel.Parent = panel.Content

	-- Zone notification (Deepwoken-style) — invisible until triggered
	zoneFrame = Instance.new("Frame")
	zoneFrame.Name = "ZoneNotification"
	zoneFrame.AnchorPoint = Vector2.new(0.5, 0)
	zoneFrame.Position = HUDLayout.ZoneNotificationPosition(340, 52)
	zoneFrame.Size = UDim2.new(0, 340, 0, 52)
	zoneFrame.BackgroundTransparency = 1
	zoneFrame.BorderSizePixel = 0
	zoneFrame.Visible = false
	zoneFrame.Parent = screenGui

	-- Top divider
	zoneTopDiv = Instance.new("Frame")
	zoneTopDiv.Name = "TopDivider"
	zoneTopDiv.AnchorPoint = Vector2.new(0.5, 0)
	zoneTopDiv.Position = UDim2.new(0.5, 0, 0, 0)
	zoneTopDiv.Size = UDim2.new(0, 0, 0, 1)
	zoneTopDiv.BackgroundColor3 = UITheme.Palette.TextAccent
	zoneTopDiv.BackgroundTransparency = 1
	zoneTopDiv.BorderSizePixel = 0
	zoneTopDiv.Parent = zoneFrame

	-- Zone name label
	zoneNameLabel = Instance.new("TextLabel")
	zoneNameLabel.Name = "ZoneName"
	zoneNameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	zoneNameLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	zoneNameLabel.Size = UDim2.new(1, 0, 1, -10)
	zoneNameLabel.BackgroundTransparency = 1
	zoneNameLabel.Font = UITheme.Typography.FontBold
	zoneNameLabel.TextXAlignment = Enum.TextXAlignment.Center
	zoneNameLabel.TextWrapped = true
	zoneNameLabel.Parent = zoneFrame

	-- Bottom divider
	zoneBotDiv = Instance.new("Frame")
	zoneBotDiv.Name = "BotDivider"
	zoneBotDiv.AnchorPoint = Vector2.new(0.5, 1)
	zoneBotDiv.Position = UDim2.new(0.5, 0, 1, 0)
	zoneBotDiv.Size = UDim2.new(0, 0, 0, 1)
	zoneBotDiv.BackgroundColor3 = UITheme.Palette.TextAccent
	zoneBotDiv.BackgroundTransparency = 1
	zoneBotDiv.BorderSizePixel = 0
	zoneBotDiv.Parent = zoneFrame

	-- Register zone change handler
	if NetworkController then
		NetworkController:RegisterHandler("RingChanged", function(packet: any)
			showZoneChange(packet)
		end)
	end
end

local function showZoneChange(packet: any)
	if not zoneFrame then return end

	-- Cancel any in-flight fade
	if zoneFadeThread then
		task.cancel(zoneFadeThread)
		zoneFadeThread = nil
	end

	local isRingChange = (packet.OldRing ~= nil)
		and (packet.NewRing ~= nil)
		and (packet.OldRing ~= packet.NewRing)

	-- Display text
	local displayText = ""
	if isRingChange then
		displayText = "Ring " .. tostring(packet.NewRing)
		if packet.ZoneName and packet.ZoneName ~= "" then
			displayText = packet.ZoneName .. "\n" .. displayText
		end
	elseif packet.ZoneName and packet.ZoneName ~= "" then
		displayText = packet.ZoneName
	else
		return
	end

	-- Configure style
	if isRingChange then
		zoneFrame.Size = UDim2.new(0, 340, 0, 58)
		zoneNameLabel.TextColor3 = UITheme.Palette.TextAccent
		zoneNameLabel.TextSize = 30
		zoneNameLabel.Font = UITheme.Typography.FontBold
	else
		zoneFrame.Size = UDim2.new(0, 280, 0, 40)
		zoneNameLabel.TextColor3 = UITheme.Palette.TextPrimary
		zoneNameLabel.TextSize = 20
		zoneNameLabel.Font = UITheme.Typography.FontRegular
	end

	-- Reset and show
	zoneNameLabel.Text = displayText
	zoneNameLabel.TextTransparency = 1
	zoneTopDiv.Size = UDim2.new(0, 0, 0, 1)
	zoneTopDiv.BackgroundTransparency = 1
	zoneBotDiv.Size = UDim2.new(0, 0, 0, 1)
	zoneBotDiv.BackgroundTransparency = 1
	zoneFrame.Visible = true

	-- Fade-in text
	local inInfo = TweenInfo.new(UITheme.Motion.DurationSmooth, UITheme.Motion.EasingQuick, UITheme.Motion.EasingInOut)
	TweenService:Create(zoneNameLabel, inInfo, { TextTransparency = 0 }):Play()

	if isRingChange then
		-- Dividers expand outward
		local divInfo = TweenInfo.new(0.5, UITheme.Motion.EasingQuick, UITheme.Motion.EasingInOut)
		TweenService:Create(zoneTopDiv, divInfo, {
			Size = UDim2.new(0, 300, 0, 1),
			BackgroundTransparency = 0,
		}):Play()
		TweenService:Create(zoneBotDiv, divInfo, {
			Size = UDim2.new(0, 300, 0, 1),
			BackgroundTransparency = 0,
		}):Play()
	end

	-- Hold 3s then fade out
	zoneFadeThread = task.delay(3, function()
		local outInfo = TweenInfo.new(0.55, UITheme.Motion.EasingQuick, UITheme.Motion.EasingInOut)
		TweenService:Create(zoneNameLabel, outInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(zoneTopDiv, outInfo, { BackgroundTransparency = 1 }):Play()
		local finTween = TweenService:Create(zoneBotDiv, outInfo, { BackgroundTransparency = 1 })
		finTween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				zoneFrame.Visible = false
			end
		end)
		finTween:Play()
		zoneFadeThread = nil
	end)
end

--------------------------------------------------------------------------------
-- Bindings
--------------------------------------------------------------------------------

local function setupBindings()
	local profileSignal = StateSyncController.GetProfileUpdatedSignal()
	local stateSignal = StateSyncController.GetStateChangedSignal()

	-- Health bar (width) and label
	UIBinding.BindProgress(healthBar, function()
		if not profile then return 0 end
		return profile.CurrentHealth / profile.MaxHealth
	end, profileSignal)

	-- Mana bar (width) and label
	UIBinding.BindProgress(manaBar, function()
		if not profile then return 0 end
		return profile.CurrentMana / profile.MaxMana
	end, profileSignal)

	-- Level label
	UIBinding.BindText(levelLabel, function()
		if not profile then return "Level: --" end
		return string.format("Level: %d", profile.Level)
	end, profileSignal)

	-- State label
	UIBinding.BindText(stateLabel, function()
		if not currentState then return "State: Loading" end
		return string.format("State: %s", currentState)
	end, stateSignal)

	-- Coins label
	UIBinding.BindText(coinsLabel, function()
		if not profile then return "Coins: 0" end
		return string.format("Coins: %d", profile.Coins)
	end, profileSignal)

	-- Experience label
	UIBinding.BindText(expLabel, function()
		if not profile then return "XP: 0/0" end
		local expNeeded = profile.Level * 100
		return string.format("XP: %d/%d", profile.Experience, expNeeded)
	end, profileSignal)
end

--------------------------------------------------------------------------------
-- Profile & State Handlers
--------------------------------------------------------------------------------

local function onProfileLoaded(newProfile: PlayerProfile)
	profile = newProfile
end

local function onProfileUpdated(newProfile: PlayerProfile)
	profile = newProfile
end

local function onStateChanged(oldState: PlayerState, newState: PlayerState)
	currentState = newState
end

--------------------------------------------------------------------------------
-- Toast API (used by other controllers)
--------------------------------------------------------------------------------

local PlayerHUDController = {}

function PlayerHUDController:ShowToast(title: string, subtitle: string, color: Color3?, duration: number?)
	if not screenGui then return end

	if not toastContainer then
		toastContainer = Instance.new("Frame")
		toastContainer.Name = "ToastContainer"
		toastContainer.Size = UDim2.new(0, 300, 0.5, 0)
		toastContainer.Position = UDim2.new(0.5, -150, 0.1, 0)
		toastContainer.BackgroundTransparency = 1
		toastContainer.Parent = screenGui

		local listLayout = Instance.new("UIListLayout")
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Padding = UITheme.Spacing.GapMedium
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		listLayout.Parent = toastContainer
	end

	color = color or UITheme.Palette.TextAccent
	duration = duration or 4.0

	local toast = Instance.new("Frame")
	toast.Size = UDim2.new(0, 280, 0, 60)
	toast.BackgroundColor3 = UITheme.Palette.PanelMid
	toast.BackgroundTransparency = 0.2
	toast.BorderSizePixel = 0
	toast.ClipsDescendants = true

	HUDPrimitives.applyCorner(toast, UITheme.Corners.Medium)
	HUDPrimitives.applyStroke(toast, color, UITheme.Strokes.Thin, 0.4)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -20, 0.5, 0)
	titleLabel.Position = UDim2.new(0, 10, 0, 5)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = UITheme.Typography.FontBold
	titleLabel.TextColor3 = color
	titleLabel.TextSize = UITheme.Typography.SizeMedium
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = title
	titleLabel.Parent = toast

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -20, 0.5, -5)
	subLabel.Position = UDim2.new(0, 10, 0.5, 0)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = UITheme.Typography.FontRegular
	subLabel.TextColor3 = UITheme.Palette.TextSecondary
	subLabel.TextSize = UITheme.Typography.SizeSmall
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.Text = subtitle
	subLabel.Parent = toast

	toast.Parent = toastContainer

	-- Fade in
	toast.Position = UDim2.new(0, 50, 0, 0)
	toast.BackgroundTransparency = 1
	titleLabel.TextTransparency = 1
	subLabel.TextTransparency = 1

	local inInfo = TweenInfo.new(UITheme.Motion.DurationSmooth, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(toast, inInfo, { Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0.2 }):Play()
	TweenService:Create(titleLabel, inInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(subLabel, inInfo, { TextTransparency = 0 }):Play()
	local strokeObj = toast:FindFirstChild("UIStroke")
	if strokeObj then
		TweenService:Create(strokeObj, inInfo, { Transparency = 0 }):Play()
	end

	-- Fade out after duration
	task.delay(duration, function()
		if not toast or not toast.Parent then return end
		local outInfo = TweenInfo.new(UITheme.Motion.DurationSmooth, UITheme.Motion.EasingQuick, UITheme.Motion.EasingInOut)
		local t = TweenService:Create(toast, outInfo, { BackgroundTransparency = 1 })
		TweenService:Create(titleLabel, outInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(subLabel, outInfo, { TextTransparency = 1 }):Play()
		local stroke = toast:FindFirstChild("UIStroke")
		if stroke then
			TweenService:Create(stroke, outInfo, { Transparency = 1 }):Play()
		end

		t.Completed:Connect(function()
			toast:Destroy()
		end)
		t:Play()
	end)
end

--------------------------------------------------------------------------------
-- Controller API
--------------------------------------------------------------------------------

function PlayerHUDController:Init(dependencies)
	StateSyncController = dependencies.StateSyncController
	MovementController = dependencies.MovementController
	NetworkController = dependencies.NetworkController
	ProgressionController = dependencies.ProgressionController

	if not StateSyncController then
		error("[PlayerHUDController] StateSyncController dependency not provided")
	end
	if not NetworkController then
		error("[PlayerHUDController] NetworkController dependency not provided")
	end

	print("[PlayerHUDController] Initialized")
end

function PlayerHUDController:Start()
	-- Create all HUD sections
	createCoreHUD()
	createMovementHUD()
	createResonanceHUD()

	-- Start movement HUD update loop
	movementHudConn = RunService.Heartbeat:Connect(updateMovementHUD)

	-- Connect to state changes
	StateSyncController.GetProfileLoadedSignal():Connect(onProfileLoaded)
	StateSyncController.GetProfileUpdatedSignal():Connect(onProfileUpdated)
	StateSyncController.GetStateChangedSignal():Connect(onStateChanged)

	-- Set up reactive bindings
	setupBindings()

	-- Initialize state from current values
	profile = StateSyncController.GetCurrentProfile()
	currentState = StateSyncController.GetCurrentState()

	-- Wire up resonance updates
	if ProgressionController then
		updateResonanceDisplay(ProgressionController:GetState())
		table.insert(ProgressionController._resonanceListeners, updateResonanceDisplay)
	end

	print("[PlayerHUDController] HUD created and active")
end

function PlayerHUDController:Shutdown()
	if movementHudConn then
		movementHudConn:Disconnect()
		movementHudConn = nil
	end
	if movementGui then
		movementGui:Destroy()
	end
	if resonanceGui then
		resonanceGui:Destroy()
	end
	if screenGui then
		screenGui:Destroy()
	end

	if hudFrame then
		UIBinding.DisconnectAll(hudFrame)
	end

	print("[PlayerHUDController] Shutdown complete")
end

return PlayerHUDController
