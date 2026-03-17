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
local StateSyncController = nil
local MovementController = nil

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
-- Zone notification UI (Deepwoken-style)
local zoneFrame: Frame
local zoneTopDiv: Frame
local zoneBotDiv: Frame
local zoneNameLabel: TextLabel
local zoneFadeThread: thread? = nil

-- Movement HUD elements (#95)
local movementGui: ScreenGui
local breathBarFill: Frame
local breathLabel: TextLabel
local momentumFill: Frame
local momentumLabel: TextLabel
local exhaustedOverlay: Frame
local movementHudConn: RBXScriptConnection?

-- Resonance + Shard HUD (#145)
local ProgressionController: any = nil
local resonanceGui: ScreenGui
local _resonanceLabel: TextLabel
local _shardsLabel: TextLabel

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
	movementGui.DisplayOrder = HUDLayout.Layers.HUD + 1
	movementGui.Parent = playerGui

	-- Root panel — bottom-left using HUDLayout
	local panel = Instance.new("Frame")
	panel.Name = "MovementPanel"
	panel.Size = UDim2.new(0, 220, 0, 78)
	panel.AnchorPoint = HUDLayout.Anchors.BottomLeft
	panel.Position = UDim2.new(
		HUDLayout.Anchors.BottomLeft.X,
		HUDLayout.SafeArea.SideMargin,
		HUDLayout.Anchors.BottomLeft.Y,
		-HUDLayout.SafeArea.BottomMargin
	)
	panel.BackgroundColor3 = UITheme.Palette.PanelDark
	panel.BackgroundTransparency = UITheme.Opacity.PanelBackground
	panel.BorderSizePixel = 0
	panel.Parent = movementGui
	
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UITheme.Corners.Medium
	panelCorner.Parent = panel
	
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = UITheme.Palette.AccentIron
	panelStroke.Thickness = UITheme.Strokes.Standard
	panelStroke.Transparency = 0.3
	panelStroke.Parent = panel
	
	local panelPadding = Instance.new("UIPadding")
	panelPadding.PaddingLeft = UITheme.Spacing.PaddingMedium
	panelPadding.PaddingRight = UITheme.Spacing.PaddingMedium
	panelPadding.PaddingTop = UITheme.Spacing.PaddingSmall
	panelPadding.PaddingBottom = UITheme.Spacing.PaddingSmall
	panelPadding.Parent = panel

	-- ── BREATH ROW ──────────────────────────────────────────────
	local breathRowLabel = Instance.new("TextLabel")
	breathRowLabel.Name = "BreathTitle"
	breathRowLabel.Size = UDim2.new(1, 0, 0, 14)
	breathRowLabel.Position = UDim2.new(0, 0, 0, 0)
	breathRowLabel.BackgroundTransparency = 1
	breathRowLabel.Text = "BREATH"
	breathRowLabel.TextColor3 = UITheme.Palette.BreathTeal
	breathRowLabel.TextSize = UITheme.Typography.SizeSmall
	breathRowLabel.Font = UITheme.Typography.FontBold
	breathRowLabel.TextXAlignment = Enum.TextXAlignment.Left
	breathRowLabel.Parent = panel

	local breathBg = Instance.new("Frame")
	breathBg.Name = "BreathBg"
	breathBg.Size = UDim2.new(1, 0, 0, 16)
	breathBg.Position = UDim2.new(0, 0, 0, 16)
	breathBg.BackgroundColor3 = UITheme.Palette.PanelMid
	breathBg.BorderSizePixel = 0
	breathBg.Parent = panel
	
	local breathBgCorner = Instance.new("UICorner")
	breathBgCorner.CornerRadius = UITheme.Corners.Small
	breathBgCorner.Parent = breathBg

	breathBarFill = Instance.new("Frame")
	breathBarFill.Name = "BreathFill"
	breathBarFill.Size = UDim2.new(1, 0, 1, 0)
	breathBarFill.BackgroundColor3 = UITheme.Palette.BreathTeal
	breathBarFill.BorderSizePixel = 0
	breathBarFill.Parent = breathBg
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UITheme.Corners.Small
	fillCorner.Parent = breathBarFill

	-- Exhausted flash overlay (hidden by default)
	exhaustedOverlay = Instance.new("Frame")
	exhaustedOverlay.Name = "ExhaustedOverlay"
	exhaustedOverlay.Size = UDim2.new(1, 0, 1, 0)
	exhaustedOverlay.BackgroundColor3 = UITheme.Palette.BreathRed
	exhaustedOverlay.BackgroundTransparency = 1
	exhaustedOverlay.BorderSizePixel = 0
	exhaustedOverlay.ZIndex = 5
	exhaustedOverlay.Parent = breathBg
	
	local exhaustedCorner = Instance.new("UICorner")
	exhaustedCorner.CornerRadius = UITheme.Corners.Small
	exhaustedCorner.Parent = exhaustedOverlay

	breathLabel = Instance.new("TextLabel")
	breathLabel.Name = "BreathValue"
	breathLabel.Size = UDim2.new(1, 0, 1, 0)
	breathLabel.BackgroundTransparency = 1
	breathLabel.Text = "100"
	breathLabel.TextColor3 = UITheme.Palette.TextPrimary
	breathLabel.TextSize = UITheme.Typography.SizeSmall
	breathLabel.Font = UITheme.Typography.FontBold
	breathLabel.ZIndex = 6
	breathLabel.Parent = breathBg

	-- ── MOMENTUM ROW ────────────────────────────────────────────
	local momentumRowLabel = Instance.new("TextLabel")
	momentumRowLabel.Name = "MomentumTitle"
	momentumRowLabel.Size = UDim2.new(1, 0, 0, 14)
	momentumRowLabel.Position = UDim2.new(0, 0, 0, 40)
	momentumRowLabel.BackgroundTransparency = 1
	momentumRowLabel.Text = "MOMENTUM"
	momentumRowLabel.TextColor3 = UITheme.Palette.AccentGold
	momentumRowLabel.TextSize = UITheme.Typography.SizeSmall
	momentumRowLabel.Font = UITheme.Typography.FontBold
	momentumRowLabel.TextXAlignment = Enum.TextXAlignment.Left
	momentumRowLabel.Parent = panel

	local momentumBg = Instance.new("Frame")
	momentumBg.Name = "MomentumBg"
	momentumBg.Size = UDim2.new(1, 0, 0, 16)
	momentumBg.Position = UDim2.new(0, 0, 0, 56)
	momentumBg.BackgroundColor3 = UITheme.Palette.PanelMid
	momentumBg.BorderSizePixel = 0
	momentumBg.Parent = panel
	
	local momentumBgCorner = Instance.new("UICorner")
	momentumBgCorner.CornerRadius = UITheme.Corners.Small
	momentumBgCorner.Parent = momentumBg

	momentumFill = Instance.new("Frame")
	momentumFill.Name = "MomentumFill"
	momentumFill.Size = UDim2.new(0, 0, 1, 0)
	momentumFill.BackgroundColor3 = UITheme.Palette.AccentGold
	momentumFill.BorderSizePixel = 0
	momentumFill.Parent = momentumBg
	
	local momentumFillCorner = Instance.new("UICorner")
	momentumFillCorner.CornerRadius = UITheme.Corners.Small
	momentumFillCorner.Parent = momentumFill

	momentumLabel = Instance.new("TextLabel")
	momentumLabel.Name = "MomentumValue"
	momentumLabel.Size = UDim2.new(1, 0, 1, 0)
	momentumLabel.BackgroundTransparency = 1
	momentumLabel.Text = "1.0×"
	momentumLabel.TextColor3 = UITheme.Palette.TextAccent
	momentumLabel.TextSize = UITheme.Typography.SizeSmall
	momentumLabel.Font = UITheme.Typography.FontBold
	momentumLabel.ZIndex = 4
	momentumLabel.Parent = momentumBg
end

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

	-- Colour: teal → yellow → orange as Breath gets low (using UITheme thresholds)
	if pct > 0.5 then
		breathBarFill.BackgroundColor3 = UITheme.Palette.BreathTeal
	elseif pct > 0.2 then
		breathBarFill.BackgroundColor3 = UITheme.Palette.BreathYellow
	else
		breathBarFill.BackgroundColor3 = UITheme.Palette.BreathRed
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

	-- Colour: dull gold → bright orange → blazing gold at cap (using UITheme)
	if mPct < 0.5 then
		momentumFill.BackgroundColor3 = UITheme.Palette.AccentGold
	elseif mPct < 0.85 then
		momentumFill.BackgroundColor3 = UITheme.Palette.PostureOrange
	else
		momentumFill.BackgroundColor3 = UITheme.Palette.AccentGold
	end

	-- Label shows multiplier; "MAX" when at cap
	if mult >= MOMENTUM_CAP - 0.01 then
		momentumLabel.Text = "MAX"
		momentumLabel.TextColor3 = UITheme.Palette.AccentGold
	else
		momentumLabel.Text = string.format("%.1f×", mult)
		momentumLabel.TextColor3 = UITheme.Palette.TextAccent
	end
end

--------------------------------------------------------------------------------
-- Resonance + Shard HUD (#145)
--------------------------------------------------------------------------------

local function _updateResonanceDisplay(state: any)
	if _resonanceLabel then
		_resonanceLabel.Text = tostring(state.TotalResonance or 0)
	end
	if _shardsLabel then
		_shardsLabel.Text = tostring(state.ResonanceShards or 0)
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

	local panel = Instance.new("Frame")
	panel.Name = "ResonancePanel"
	panel.Size = UDim2.new(0, 200, 0, 60)
	panel.AnchorPoint = HUDLayout.Anchors.BottomRight
	panel.Position = UDim2.new(
		HUDLayout.Anchors.BottomRight.X,
		-HUDLayout.SafeArea.SideMargin,
		HUDLayout.Anchors.BottomRight.Y,
		-HUDLayout.SafeArea.BottomMargin
	)
	panel.BackgroundColor3 = UITheme.Palette.PanelDark
	panel.BackgroundTransparency = UITheme.Opacity.PanelBackground
	panel.BorderSizePixel = 0
	panel.Parent = resonanceGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UITheme.Corners.Medium
	corner.Parent = panel
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Palette.AccentIron
	stroke.Thickness = UITheme.Strokes.Standard
	stroke.Transparency = 0.3
	stroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UITheme.Spacing.PaddingMedium
	padding.PaddingRight = UITheme.Spacing.PaddingMedium
	padding.PaddingTop = UITheme.Spacing.PaddingSmall
	padding.PaddingBottom = UITheme.Spacing.PaddingSmall
	padding.Parent = panel

	-- RESONANCE row
	local resTitleLbl = Instance.new("TextLabel")
	resTitleLbl.Size = UDim2.new(0.6, 0, 0, 16)
	resTitleLbl.Position = UDim2.fromOffset(0, 0)
	resTitleLbl.BackgroundTransparency = 1
	resTitleLbl.Text = "RESONANCE"
	resTitleLbl.TextColor3 = UITheme.Palette.AccentGold
	resTitleLbl.TextSize = UITheme.Typography.SizeSmall
	resTitleLbl.Font = UITheme.Typography.FontBold
	resTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
	resTitleLbl.Parent = panel

	_resonanceLabel = Instance.new("TextLabel")
	_resonanceLabel.Name = "ResonanceValue"
	_resonanceLabel.Size = UDim2.new(0.4, 0, 0, 16)
	_resonanceLabel.Position = UDim2.new(0.6, 0, 0, 0)
	_resonanceLabel.BackgroundTransparency = 1
	_resonanceLabel.Text = "0"
	_resonanceLabel.TextColor3 = UITheme.Palette.TextAccent
	_resonanceLabel.TextSize = UITheme.Typography.SizeSmall
	_resonanceLabel.Font = UITheme.Typography.FontBold
	_resonanceLabel.TextXAlignment = Enum.TextXAlignment.Right
	_resonanceLabel.Parent = panel

	-- SHARDS row
	local shardsTitleLbl = Instance.new("TextLabel")
	shardsTitleLbl.Size = UDim2.new(0.6, 0, 0, 16)
	shardsTitleLbl.Position = UDim2.fromOffset(0, 26)
	shardsTitleLbl.BackgroundTransparency = 1
	shardsTitleLbl.Text = "SHARDS"
	shardsTitleLbl.TextColor3 = UITheme.Palette.TextSecondary
	shardsTitleLbl.TextSize = UITheme.Typography.SizeSmall
	shardsTitleLbl.Font = UITheme.Typography.FontBold
	shardsTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
	shardsTitleLbl.Parent = panel

	_shardsLabel = Instance.new("TextLabel")
	_shardsLabel.Name = "ShardsValue"
	_shardsLabel.Size = UDim2.new(0.4, 0, 0, 16)
	_shardsLabel.Position = UDim2.new(0.6, 0, 0, 26)
	_shardsLabel.BackgroundTransparency = 1
	_shardsLabel.Text = "0"
	_shardsLabel.TextColor3 = UITheme.Palette.TextPrimary
	_shardsLabel.TextSize = UITheme.Typography.SizeSmall
	_shardsLabel.Font = UITheme.Typography.FontBold
	_shardsLabel.TextXAlignment = Enum.TextXAlignment.Right
	_shardsLabel.Parent = panel
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
	screenGui.DisplayOrder = HUDLayout.Layers.HUD
	screenGui.Parent = playerGui
	
	-- HUD Frame
	hudFrame = Instance.new("Frame")
	hudFrame.Name = "HUDFrame"
	hudFrame.Size = UDim2.new(0, 250, 0, 200)
	hudFrame.AnchorPoint = HUDLayout.Anchors.TopLeft
	hudFrame.Position = UDim2.new(0, HUDLayout.SafeArea.SideMargin, 0, HUDLayout.SafeArea.TopMargin)
	hudFrame.BackgroundTransparency = UITheme.Opacity.PanelBackground
	hudFrame.BackgroundColor3 = UITheme.Palette.PanelDark
	hudFrame.BorderSizePixel = 0
	hudFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UITheme.Corners.Medium
	corner.Parent = hudFrame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = UITheme.Palette.AccentIron
	stroke.Thickness = UITheme.Strokes.Standard
	stroke.Transparency = 0.3
	stroke.Parent = hudFrame

	-- Zone notification (Deepwoken-style) — invisible container anchored upper-center
	zoneFrame = Instance.new("Frame")
	zoneFrame.Name = "ZoneNotification"
	zoneFrame.AnchorPoint = HUDLayout.Anchors.TopCenter
	zoneFrame.Position = UDim2.new(HUDLayout.Anchors.TopCenter.X, 0, 0, 80)
	zoneFrame.Size = UDim2.new(0, 340, 0, 52)
	zoneFrame.BackgroundTransparency = 1
	zoneFrame.BorderSizePixel = 0
	zoneFrame.Visible = false
	zoneFrame.Parent = screenGui

	-- Top divider line
	zoneTopDiv = Instance.new("Frame")
	zoneTopDiv.Name = "TopDivider"
	zoneTopDiv.AnchorPoint = HUDLayout.Anchors.TopCenter
	zoneTopDiv.Position = UDim2.new(HUDLayout.Anchors.TopCenter.X, 0, 0, 0)
	zoneTopDiv.Size = UDim2.new(0, 0, 0, 1)
	zoneTopDiv.BackgroundColor3 = UITheme.Palette.AccentGold
	zoneTopDiv.BackgroundTransparency = 1
	zoneTopDiv.BorderSizePixel = 0
	zoneTopDiv.Parent = zoneFrame

	-- Zone name label (center)
	zoneNameLabel = Instance.new("TextLabel")
	zoneNameLabel.Name = "ZoneName"
	zoneNameLabel.AnchorPoint = HUDLayout.Anchors.Center
	zoneNameLabel.Position = UDim2.new(HUDLayout.Anchors.Center.X, 0, 0.5, 0)
	zoneNameLabel.Size = UDim2.new(1, 0, 1, -10)
	zoneNameLabel.BackgroundTransparency = 1
	zoneNameLabel.TextColor3 = UITheme.Palette.TextPrimary
	zoneNameLabel.TextTransparency = 1
	zoneNameLabel.TextSize = 28
	zoneNameLabel.Font = UITheme.Typography.FontBold
	zoneNameLabel.Text = ""
	zoneNameLabel.TextXAlignment = Enum.TextXAlignment.Center
	zoneNameLabel.Parent = zoneFrame

	-- Bottom divider line
	zoneBotDiv = Instance.new("Frame")
	zoneBotDiv.Name = "BotDivider"
	zoneBotDiv.AnchorPoint = Vector2.new(0.5, 1)
	zoneBotDiv.Position = UDim2.new(HUDLayout.Anchors.BottomCenter.X, 0, 1, 0)
	zoneBotDiv.Size = UDim2.new(0, 0, 0, 1)
	zoneBotDiv.BackgroundColor3 = UITheme.Palette.AccentGold
	zoneBotDiv.BackgroundTransparency = 1
	zoneBotDiv.BorderSizePixel = 0
	zoneBotDiv.Parent = zoneFrame
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Text = "NIGHTFALL"
	title.TextColor3 = UITheme.Palette.AccentGold
	title.TextSize = UITheme.Typography.SizeLarge
	title.Font = UITheme.Typography.FontBold
	title.Parent = hudFrame
	
	-- Create stat bars with theme colors
	local _, health = createStatBar("Health", UDim2.new(0, 20, 0, 40), UITheme.Palette.HealthGreen)
	healthBar = health
	
	local _, mana = createStatBar("Mana", UDim2.new(0, 20, 0, 75), UITheme.Palette.HealthYellow)
	manaBar = mana
	
	-- Create info labels
	levelLabel = createInfoLabel("LevelLabel", UDim2.new(0, 20, 0, 110), "Level: 1")
	stateLabel = createInfoLabel("StateLabel", UDim2.new(0, 20, 0, 135), "State: Loading...")

	--[[
		showZoneChange(packet)
		Deepwoken-style zone/ring notification.

		Ring change  (OldRing ~= NewRing):
		  • Large gold text
		  • Two thin gold divider lines expand from center
		  • Visible for 3 s then fades out

		Zone-only change (ZoneName set but ring unchanged):
		  • Smaller white text, no dividers
		  • Visible for 3 s then fades out
	]]
	local function showZoneChange(packet: any)
		print("[PlayerHUD] showZoneChange", packet)
		if not zoneFrame then return end

		-- cancel any in-flight fade
		if zoneFadeThread then
			task.cancel(zoneFadeThread)
			zoneFadeThread = nil
		end

		local isRingChange: boolean = (packet.OldRing ~= nil)
			and (packet.NewRing ~= nil)
			and (packet.OldRing ~= packet.NewRing)

		-- decide display text
		local displayText: string
		if isRingChange then
			displayText = "Ring " .. tostring(packet.NewRing)
			-- include zone name as subtitle if present
			if packet.ZoneName and packet.ZoneName ~= "" then
				displayText = packet.ZoneName .. "\n" .. "Ring " .. tostring(packet.NewRing)
			end
		elseif packet.ZoneName and packet.ZoneName ~= "" then
			displayText = packet.ZoneName
		else
			-- ring 0 or unchanged — nothing meaningful to show
			return
		end

		-- configure style
		if isRingChange then
			zoneFrame.Size = UDim2.new(0, 340, 0, 58)
			zoneNameLabel.TextColor3 = UITheme.Palette.AccentGold
			zoneNameLabel.TextSize = 30
			zoneNameLabel.Font = UITheme.Typography.FontBold
			zoneTopDiv.BackgroundColor3 = UITheme.Palette.AccentGold
			zoneBotDiv.BackgroundColor3 = UITheme.Palette.AccentGold
		else
			zoneFrame.Size = UDim2.new(0, 280, 0, 40)
			zoneNameLabel.TextColor3 = UITheme.Palette.TextPrimary
			zoneNameLabel.TextSize = 20
			zoneNameLabel.Font = UITheme.Typography.FontRegular
		end

		-- reset to fully transparent before show
		zoneNameLabel.Text = displayText
		zoneNameLabel.TextTransparency = 1
		zoneTopDiv.Size = UDim2.new(0, 0, 0, 1)
		zoneTopDiv.BackgroundTransparency = 1
		zoneBotDiv.Size = UDim2.new(0, 0, 0, 1)
		zoneBotDiv.BackgroundTransparency = 1
		zoneFrame.Visible = true

		-- fade-in text
		local inInfo = TweenInfo.new(
			UITheme.Motion.TransitionFast,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		)
		TweenService:Create(zoneNameLabel, inInfo, { TextTransparency = 0 }):Play()

		if isRingChange then
			-- divider lines slide outward from center
			local divInfo = TweenInfo.new(
				UITheme.Motion.TransitionNormal,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
			TweenService:Create(zoneTopDiv, divInfo, {
				Size = UDim2.new(0, 300, 0, 1),
				BackgroundTransparency = 0,
			}):Play()
			TweenService:Create(zoneBotDiv, divInfo, {
				Size = UDim2.new(0, 300, 0, 1),
				BackgroundTransparency = 0,
			}):Play()
		end

		-- hold 3 s then fade out
		zoneFadeThread = task.delay(3, function()
			local outInfo = TweenInfo.new(UITheme.Motion.TransitionSlow, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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

	-- register network handler for ring change / named zones
	if NetworkController then
		NetworkController:RegisterHandler("RingChanged", function(packet: any)
			showZoneChange(packet)
		end)
	else
		warn("[PlayerHUDController] cannot register RingChanged handler; NetworkController missing")
	end
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

-- Cached toast container
local toastContainer: Frame?

--[[
	Displays a floating toast notification.
]]
function PlayerHUDController:ShowToast(title: string, subtitle: string, color: Color3?, duration: number?)
	if not screenGui then return end
	
	if not toastContainer then
		toastContainer = Instance.new("Frame")
		toastContainer.Name = "ToastContainer"
		toastContainer.Size = UDim2.new(0, 300, 0.5, 0)
		toastContainer.AnchorPoint = HUDLayout.Anchors.TopCenter
		toastContainer.Position = UDim2.new(HUDLayout.Anchors.TopCenter.X, 0, 0, 10)
		toastContainer.BackgroundTransparency = 1
		toastContainer.Parent = screenGui
		
		local listLayout = Instance.new("UIListLayout")
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Padding = UITheme.Spacing.GapMedium
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		listLayout.Parent = toastContainer
	end
	
	color = color or UITheme.Palette.AccentGold
	duration = duration or 4.0
	
	local toast = Instance.new("Frame")
	toast.Size = UDim2.new(0, 280, 0, 60)
	toast.BackgroundColor3 = UITheme.Palette.PanelDark
	toast.BackgroundTransparency = UITheme.Opacity.PanelBackground
	toast.BorderSizePixel = 0
	toast.ClipsDescendants = true
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UITheme.Corners.Medium
	corner.Parent = toast
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = UITheme.Strokes.Standard
	stroke.Parent = toast
	
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
	
	toast.Position = UDim2.new(0, 50, 0, 0)
	toast.BackgroundTransparency = 1
	titleLabel.TextTransparency = 1
	subLabel.TextTransparency = 1
	stroke.Transparency = 1
	
	local inInfo = TweenInfo.new(
		UITheme.Motion.TransitionFast,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)
	TweenService:Create(toast, inInfo, { Position = UDim2.new(0,0,0,0), BackgroundTransparency = UITheme.Opacity.PanelBackground}):Play()
	TweenService:Create(titleLabel, inInfo, {TextTransparency = 0}):Play()
	TweenService:Create(subLabel, inInfo, {TextTransparency = 0}):Play()
	TweenService:Create(stroke, inInfo, {Transparency = 0}):Play()
	
	task.delay(duration, function()
		if not toast or not toast.Parent then return end
		local outInfo = TweenInfo.new(UITheme.Motion.TransitionNormal, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local t = TweenService:Create(toast, outInfo, {BackgroundTransparency = 1})
		TweenService:Create(titleLabel, outInfo, {TextTransparency = 1}):Play()
		TweenService:Create(subLabel, outInfo, {TextTransparency = 1}):Play()
		TweenService:Create(stroke, outInfo, {Transparency = 1}):Play()
		
		t.Completed:Connect(function()
			toast:Destroy()
		end)
		t:Play()
	end)
end

--[[
	Initializes the controller (called by runtime)
]]
function PlayerHUDController:Init(dependencies)
	StateSyncController   = dependencies.StateSyncController
	MovementController    = dependencies.MovementController
	NetworkController     = dependencies.NetworkController
	ProgressionController = dependencies.ProgressionController
	if not StateSyncController then
		error("[PlayerHUDController] StateSyncController dependency not provided")
	end
	if not NetworkController then
		error("[PlayerHUDController] NetworkController dependency not provided")
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

	-- Create Resonance + Shard display (#145)
	createResonanceHUD()
	if ProgressionController then
		-- Seed immediately if progression has already synced
		_updateResonanceDisplay(ProgressionController:GetState())
		-- Register for all future updates
		table.insert(ProgressionController._resonanceListeners, _updateResonanceDisplay)
	end

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
	if resonanceGui then
		resonanceGui:Destroy()
	end
	if screenGui then
		screenGui:Destroy()
	end

	UIBinding.DisconnectAll(hudFrame)

	print("[PlayerHUDController] Shutdown complete")
end

return PlayerHUDController
