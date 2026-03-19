--!strict
--[[
	PlayerHUDController.lua

	Deepwoken-style bottom-centre HUD cluster.

	Layout (top → bottom on screen):
	  "RING N"            top-right corner, persistent
	  zone notification   top-centre, slides gold dividers in/out
	  ─────────────────────────────────────────────────────
	  [Ex][Br][Sa][Si][Gr][Wl][Da][Sl]   status icons
	  ████████████████████████████████   HP  (340 × 22 px, gold fill)
	  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓   Posture  (340 × 6 px)
	  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒        Mana   (238 × 6 px)
	  ░░░░░░░░░░░░░░░░░               Breath (187 × 6 px)
	  [①][②][③][④]    ● ● ● ● ●      ability slots  +  resonance pips
	  ─────────────────────────────────────────────────────
	  (dark gradient scrim, no hard box frame)

	Polish / Deepwoken feel
	  • No outer panel — bars float on a soft gradient scrim
	  • White flash on HP bar when health decreases
	  • Red pulse on HP fill when HP ≤ 15 %
	  • Aspect-tinted UIStroke on HP bar (driven by SelectAspectResult / SwitchAspectResult)
	  • Posture: grey → amber → blood-red tween on every update
	  • Breath: teal → yellow → red; exhausted red pulse overlay
	  • Mana: UITheme.Palette.ManaBlue
	  • 4 ability slot frames with countdown overlays
	  • 5 resonance pip dots from ProgressionController
	  • HideHUD() / ShowHUD() for inventory or dialogue occlusion
	  • UpdateAspectBorder(aspectId) exposed for AspectController

	Data flow
	  StateSyncController               → health + mana bars + value label
	  PostureChanged RemoteEvent        → posture bar
	  MovementController (Heartbeat)    → breath bar + exhausted overlay
	  ProgressionController._resonanceListeners → resonance pips
	  NetworkController RingChanged     → zone notification + ring label
	  Character Attribute changes       → status icon tinting
	  SwitchAspectResult / SelectAspectResult → HP border colour
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared

local UITheme         = require(script.Parent.Parent.modules.UITheme)
local HUDLayout       = require(script.Parent.Parent.modules.HUDLayout)
local HUDTheme        = require(Shared.modules.HUDTheme)
local NetworkProvider = require(Shared.network.NetworkProvider)

local PlayerData   = require(Shared.types.PlayerData)
type PlayerProfile = PlayerData.PlayerProfile
type PlayerState   = PlayerData.PlayerState

--------------------------------------------------------------------------------
-- Injected dependencies
--------------------------------------------------------------------------------
local StateSyncController:   any = nil
local MovementController:    any = nil
local NetworkController:     any = nil
local ProgressionController: any = nil

--------------------------------------------------------------------------------
-- UI roots
--------------------------------------------------------------------------------
local playerGui:  PlayerGui
local clusterGui: ScreenGui

--------------------------------------------------------------------------------
-- Element references
--------------------------------------------------------------------------------
local healthFill:       Frame
local healthValueLabel: TextLabel
local healthBarStroke:  UIStroke
local healthFlashFrame: Frame
local postureFill:      Frame
local manaFill:         Frame
local breathFill:       Frame
local exhaustedOverlay: Frame
local ringLabel:        TextLabel

local statusIcons: { [string]: { frame: Frame, label: TextLabel } } = {}
local statusConns: { RBXScriptConnection } = {}

type SlotData = { frame: Frame, overlay: Frame, cooldownLabel: TextLabel }
local abilitySlots: { SlotData } = {}

local resonanceDots: { Frame } = {}

local zoneFrame:      Frame
local zoneTopDiv:     Frame
local zoneBotDiv:     Frame
local zoneNameLabel:  TextLabel
local zoneFadeThread: thread?

--------------------------------------------------------------------------------
-- Runtime state
--------------------------------------------------------------------------------
local profile:          PlayerProfile? = nil
local currentState:     PlayerState?   = nil
local movementConn:     RBXScriptConnection?
local lastHealth:       number  = math.huge
local critPulseConn:    RBXScriptConnection?
local critPulseActive:  boolean = false
local exhaustPulseTime: number  = 0
local currentRing:      number  = 0
local hudVisible:       boolean = true

--------------------------------------------------------------------------------
-- Status-effect config
--------------------------------------------------------------------------------
local STATUS_CONFIG: { { id: string, abbr: string, color: Color3 } } = {
	{ id = "Exposed",    abbr = "Ex", color = Color3.fromRGB(190,  80,  50) },
	{ id = "Burning",    abbr = "Br", color = Color3.fromRGB(220, 130,  40) },
	{ id = "Saturated",  abbr = "Sa", color = Color3.fromRGB( 60, 120, 200) },
	{ id = "Silenced",   abbr = "Si", color = Color3.fromRGB( 90,  70, 120) },
	{ id = "Grounded",   abbr = "Gr", color = Color3.fromRGB(110,  85,  50) },
	{ id = "Weightless", abbr = "Wl", color = Color3.fromRGB(150, 200, 220) },
	{ id = "Dampened",   abbr = "Da", color = Color3.fromRGB( 60, 140, 100) },
	{ id = "Slow",       abbr = "Sl", color = Color3.fromRGB(160, 160, 180) },
}

local MAX_RESONANCE_PIPS = 5

--------------------------------------------------------------------------------
-- Shared tween presets
--------------------------------------------------------------------------------
local FAST   = TweenInfo.new(UITheme.Motion.DurationQuick,  UITheme.Motion.EasingQuick,  UITheme.Motion.EasingInOut)
local SMOOTH = TweenInfo.new(UITheme.Motion.DurationSmooth, UITheme.Motion.EasingSmooth, UITheme.Motion.EasingInOut)
local SLOW   = TweenInfo.new(UITheme.Motion.DurationSlow,   UITheme.Motion.EasingSmooth, UITheme.Motion.EasingInOut)

local function tw(inst: Instance, info: TweenInfo, props: { [string]: any })
	TweenService:Create(inst, info, props):Play()
end

--------------------------------------------------------------------------------
-- Instance helpers
--------------------------------------------------------------------------------
local function mkCorner(inst: Instance, r: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = r
	c.Parent = inst
end

local function mkStroke(inst: Instance, col: Color3, thick: number, trans: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color        = col
	s.Thickness    = thick
	s.Transparency = trans or 0
	s.Parent       = inst
	return s
end

local function mkLabel(parent: Instance, name: string, text: string,
	size: UDim2, pos: UDim2, fontSize: number, font: Enum.Font,
	color: Color3, xAlign: Enum.TextXAlignment, zIndex: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name               = name
	l.Size               = size
	l.Position           = pos
	l.BackgroundTransparency = 1
	l.Text               = text
	l.TextColor3         = color
	l.Font               = font
	l.TextSize           = fontSize
	l.TextXAlignment     = xAlign
	if zIndex then l.ZIndex = zIndex end
	l.Parent             = parent
	return l
end

--------------------------------------------------------------------------------
-- Colour helpers
--------------------------------------------------------------------------------
local function getHealthColor(pct: number): Color3
	if pct <= HUDTheme.HealthCritThreshold then return HUDTheme.HealthCritColor end
	if pct <= HUDTheme.HealthWarnThreshold  then return HUDTheme.HealthWarnColor end
	return HUDTheme.HealthFullColor
end

local function getPostureColor(pct: number): Color3
	if pct < HUDTheme.PostureWarnThreshold then return UITheme.Palette.PostureGrey end
	local t = (pct - HUDTheme.PostureWarnThreshold) / (1 - HUDTheme.PostureWarnThreshold)
	return UITheme.Palette.PostureGrey:Lerp(HUDTheme.PostureWarnColor, t)
end

--------------------------------------------------------------------------------
-- Crit pulse (RunService loop — only active when HP ≤ 15 %)
--------------------------------------------------------------------------------
local function startCritPulse()
	if critPulseActive then return end
	critPulseActive = true
	critPulseConn = RunService.Heartbeat:Connect(function()
		if not healthFill or not healthFill.Parent then return end
		local alpha = 0.5 + 0.5 * math.sin(tick() * math.pi * 2)
		healthFill.BackgroundColor3 =
			HUDTheme.HealthCritColor:Lerp(Color3.fromRGB(255, 40, 40), alpha * 0.5)
	end)
end

local function stopCritPulse()
	if not critPulseActive then return end
	critPulseActive = false
	if critPulseConn then critPulseConn:Disconnect(); critPulseConn = nil end
end

--------------------------------------------------------------------------------
-- Bar updaters
--------------------------------------------------------------------------------
local function updateHealthBar(current: number, max: number)
	if not healthFill then return end
	local pct = if max > 0 then math.clamp(current / max, 0, 1) else 0

	-- Damage flash
	if current < lastHealth and healthFlashFrame then
		healthFlashFrame.BackgroundTransparency = 0.20
		tw(healthFlashFrame, FAST, { BackgroundTransparency = 1 })
	end
	lastHealth = current

	tw(healthFill, FAST, { Size = UDim2.new(pct, 0, 1, 0) })

	if pct <= HUDTheme.HealthCritThreshold then
		startCritPulse()
	else
		stopCritPulse()
		healthFill.BackgroundColor3 = getHealthColor(pct)
	end

	if healthValueLabel then
		healthValueLabel.Text = string.format("%d / %d", math.floor(current), math.floor(max))
	end
end

local function updatePostureBar(current: number, max: number)
	if not postureFill then return end
	local pct = if max > 0 then math.clamp(current / max, 0, 1) else 0
	tw(postureFill, FAST, { Size = UDim2.new(pct, 0, 1, 0) })
	postureFill.BackgroundColor3 = getPostureColor(pct)
end

local function updateManaBar(current: number, max: number)
	if not manaFill then return end
	local pct = if max > 0 then math.clamp(current / max, 0, 1) else 0
	tw(manaFill, FAST, { Size = UDim2.new(pct, 0, 1, 0) })
end

local function updateBreathVisuals(pct: number)
	if not breathFill then return end
	if pct > UITheme.BarThresholds.BreathSafeThreshold then
		breathFill.BackgroundColor3 = UITheme.Palette.BreathTeal
	elseif pct > UITheme.BarThresholds.BreathWarningThreshold then
		breathFill.BackgroundColor3 = UITheme.Palette.BreathYellow
	else
		breathFill.BackgroundColor3 = UITheme.Palette.BreathRed
	end
end

--------------------------------------------------------------------------------
-- Aspect border
--------------------------------------------------------------------------------
local function updateAspectBorder(aspectId: string?)
	if not healthBarStroke then return end
	local col = aspectId and HUDTheme.AspectBorderColor[aspectId]
	if col then
		healthBarStroke.Color        = col
		healthBarStroke.Transparency = 0
	else
		healthBarStroke.Color        = UITheme.Palette.AccentIron
		healthBarStroke.Transparency = 0.5
	end
end

--------------------------------------------------------------------------------
-- Status icons
--------------------------------------------------------------------------------
local function refreshStatusIcons()
	local char = Players.LocalPlayer.Character
	for _, cfg in STATUS_CONFIG do
		local data = statusIcons[cfg.id]
		if not data then continue end
		local active = char ~= nil and char:GetAttribute("Status_" .. cfg.id) == true
		tw(data.frame, FAST, {
			BackgroundColor3       = if active then cfg.color else UITheme.Palette.PanelMid,
			BackgroundTransparency = if active then 0 else 0.70,
		})
		data.label.TextTransparency = if active then 0 else 0.50
	end
end

local function bindStatusAttributes()
	for _, c in statusConns do c:Disconnect() end
	table.clear(statusConns)
	local char = Players.LocalPlayer.Character
	if not char then return end
	for _, cfg in STATUS_CONFIG do
		table.insert(statusConns,
			char:GetAttributeChangedSignal("Status_" .. cfg.id):Connect(refreshStatusIcons))
	end
	refreshStatusIcons()
end

--------------------------------------------------------------------------------
-- Resonance pips
--------------------------------------------------------------------------------
local function updateResonancePips(shards: number)
	for i, dot in resonanceDots do
		local filled = i <= shards
		tw(dot, FAST, {
			BackgroundColor3       = if filled then UITheme.Palette.AccentGold else UITheme.Palette.PanelMid,
			BackgroundTransparency = if filled then 0.10 else 0.60,
		})
	end
end

--------------------------------------------------------------------------------
-- Ability slot cooldown API
--------------------------------------------------------------------------------
local function setSlotCooldown(slotIndex: number, duration: number)
	local s = abilitySlots[slotIndex]
	if not s then return end
	s.overlay.BackgroundTransparency = 0.45
	s.cooldownLabel.Text    = tostring(math.ceil(duration))
	s.cooldownLabel.Visible = true
	local remaining = duration
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		remaining -= dt
		if remaining <= 0 then
			conn:Disconnect()
			s.overlay.BackgroundTransparency = 1
			s.cooldownLabel.Visible          = false
			s.cooldownLabel.Text             = ""
		else
			s.cooldownLabel.Text = tostring(math.ceil(remaining))
		end
	end)
end

--------------------------------------------------------------------------------
-- Ring label (persistent top-right)
--------------------------------------------------------------------------------
local function setRingLabel(ring: number)
	currentRing = ring
	if ringLabel then
		ringLabel.Text = if ring > 0 then "RING " .. ring else ""
	end
end

--------------------------------------------------------------------------------
-- Zone / ring notification (Deepwoken gold-divider style)
--------------------------------------------------------------------------------
local function buildZoneNotification(parent: ScreenGui)
	zoneFrame = Instance.new("Frame")
	zoneFrame.Name               = "ZoneNotification"
	zoneFrame.AnchorPoint        = Vector2.new(0.5, 0)
	zoneFrame.Position           = UDim2.new(0.5, 0, 0, 24)
	zoneFrame.Size               = UDim2.new(0, 400, 0, 56)
	zoneFrame.BackgroundTransparency = 1
	zoneFrame.BorderSizePixel    = 0
	zoneFrame.Visible            = false
	zoneFrame.Parent             = parent

	zoneTopDiv = Instance.new("Frame")
	zoneTopDiv.Name               = "TopDivider"
	zoneTopDiv.AnchorPoint        = Vector2.new(0.5, 0)
	zoneTopDiv.Position           = UDim2.new(0.5, 0, 0, 0)
	zoneTopDiv.Size               = UDim2.new(0, 0, 0, 1)
	zoneTopDiv.BackgroundColor3   = UITheme.Palette.AccentGold
	zoneTopDiv.BackgroundTransparency = 1
	zoneTopDiv.BorderSizePixel    = 0
	zoneTopDiv.Parent             = zoneFrame

	zoneNameLabel = Instance.new("TextLabel")
	zoneNameLabel.Name               = "ZoneName"
	zoneNameLabel.AnchorPoint        = Vector2.new(0.5, 0.5)
	zoneNameLabel.Position           = UDim2.new(0.5, 0, 0.5, 0)
	zoneNameLabel.Size               = UDim2.new(1, 0, 1, -12)
	zoneNameLabel.BackgroundTransparency = 1
	zoneNameLabel.TextColor3         = UITheme.Palette.TextPrimary
	zoneNameLabel.TextTransparency   = 1
	zoneNameLabel.TextSize           = 24
	zoneNameLabel.Font               = UITheme.Typography.FontBold
	zoneNameLabel.TextXAlignment     = Enum.TextXAlignment.Center
	zoneNameLabel.TextWrapped        = true
	zoneNameLabel.Parent             = zoneFrame

	zoneBotDiv = Instance.new("Frame")
	zoneBotDiv.Name               = "BotDivider"
	zoneBotDiv.AnchorPoint        = Vector2.new(0.5, 1)
	zoneBotDiv.Position           = UDim2.new(0.5, 0, 1, 0)
	zoneBotDiv.Size               = UDim2.new(0, 0, 0, 1)
	zoneBotDiv.BackgroundColor3   = UITheme.Palette.AccentGold
	zoneBotDiv.BackgroundTransparency = 1
	zoneBotDiv.BorderSizePixel    = 0
	zoneBotDiv.Parent             = zoneFrame
end

local function showZoneChange(packet: any)
	if not zoneFrame then return end
	if zoneFadeThread then task.cancel(zoneFadeThread); zoneFadeThread = nil end

	local isRingChange = packet.OldRing ~= nil
		and packet.NewRing ~= nil
		and packet.OldRing ~= packet.NewRing

	if isRingChange and packet.NewRing then setRingLabel(packet.NewRing) end

	local displayText: string
	if isRingChange then
		displayText = "RING " .. tostring(packet.NewRing)
		if packet.ZoneName and packet.ZoneName ~= "" then
			displayText = packet.ZoneName:upper() .. "  ·  " .. displayText
		end
	elseif packet.ZoneName and packet.ZoneName ~= "" then
		displayText = packet.ZoneName:upper()
	else
		return
	end

	if isRingChange then
		zoneFrame.Size           = UDim2.new(0, 420, 0, 56)
		zoneNameLabel.TextColor3 = UITheme.Palette.AccentGold
		zoneNameLabel.TextSize   = 24
		zoneNameLabel.Font       = UITheme.Typography.FontBold
	else
		zoneFrame.Size           = UDim2.new(0, 300, 0, 40)
		zoneNameLabel.TextColor3 = UITheme.Palette.TextPrimary
		zoneNameLabel.TextSize   = 18
		zoneNameLabel.Font       = UITheme.Typography.FontRegular
	end

	zoneNameLabel.Text             = displayText
	zoneNameLabel.TextTransparency = 1
	zoneTopDiv.Size                = UDim2.new(0, 0, 0, 1)
	zoneTopDiv.BackgroundTransparency = 1
	zoneBotDiv.Size                = UDim2.new(0, 0, 0, 1)
	zoneBotDiv.BackgroundTransparency = 1
	zoneFrame.Visible              = true

	tw(zoneNameLabel, SMOOTH, { TextTransparency = 0 })
	if isRingChange then
		tw(zoneTopDiv, SMOOTH, { Size = UDim2.new(0, 360, 0, 1), BackgroundTransparency = 0 })
		tw(zoneBotDiv, SMOOTH, { Size = UDim2.new(0, 360, 0, 1), BackgroundTransparency = 0 })
	end

	zoneFadeThread = task.delay(3.5, function()
		tw(zoneNameLabel, SLOW, { TextTransparency = 1 })
		tw(zoneTopDiv,    SLOW, { BackgroundTransparency = 1 })
		local fin = TweenService:Create(zoneBotDiv, SLOW, { BackgroundTransparency = 1 })
		fin.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then zoneFrame.Visible = false end
		end)
		fin:Play()
		zoneFadeThread = nil
	end)
end

--------------------------------------------------------------------------------
-- Build entire HUD cluster
--------------------------------------------------------------------------------
local function buildHUDCluster()
	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 10)

	clusterGui = Instance.new("ScreenGui")
	clusterGui.Name           = "PlayerHUD"
	clusterGui.ResetOnSpawn   = false
	clusterGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	clusterGui.DisplayOrder   = HUDLayout.Layers.HUD
	clusterGui.IgnoreGuiInset = false
	clusterGui.Parent         = playerGui

	-- Zone notification (parented to same ScreenGui, positioned independently)
	buildZoneNotification(clusterGui)

	-- Persistent RING N — top-right
	ringLabel = mkLabel(
		clusterGui, "RingLabel", "",
		UDim2.new(0, 110, 0, 20),
		UDim2.new(1, -HUDLayout.SafeArea.SideMargin, 0, HUDLayout.SafeArea.TopMargin),
		UITheme.Typography.SizeSmall, UITheme.Typography.FontBold,
		UITheme.Palette.TextSecondary, Enum.TextXAlignment.Right
	)
	ringLabel.AnchorPoint = Vector2.new(1, 0)

	local CW = HUDTheme.ClusterWidth  -- 340

	-- ── Dark gradient scrim (no hard border) ────────────────────────────────
	local scrim = Instance.new("Frame")
	scrim.Name             = "Scrim"
	scrim.AnchorPoint      = Vector2.new(0.5, 1)
	scrim.Position         = UDim2.new(0.5, 0, 1, -(HUDTheme.HUD_BOTTOM_OFFSET - 16))
	scrim.Size             = UDim2.new(0, CW + 40, 0, 190)
	scrim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	scrim.BackgroundTransparency = 0.70
	scrim.BorderSizePixel  = 0
	mkCorner(scrim, UDim.new(0, 12))
	scrim.Parent = clusterGui

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.0, 0.0),
		NumberSequenceKeypoint.new(0.6, 0.2),
		NumberSequenceKeypoint.new(1.0, 1.0),
	})
	grad.Parent = scrim

	-- ── Root cluster (children stacked vertically, centre-aligned) ───────────
	local cluster = Instance.new("Frame")
	cluster.Name             = "HUDCluster"
	cluster.AnchorPoint      = Vector2.new(0.5, 1)
	cluster.Position         = UDim2.new(0.5, 0, 1, -HUDTheme.HUD_BOTTOM_OFFSET)
	cluster.Size             = UDim2.new(0, CW, 0, 10)
	cluster.BackgroundTransparency = 1
	cluster.BorderSizePixel  = 0
	cluster.Parent           = clusterGui

	local clusterLayout = Instance.new("UIListLayout")
	clusterLayout.FillDirection       = Enum.FillDirection.Vertical
	clusterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	clusterLayout.Padding             = UDim.new(0, 3)
	clusterLayout.Parent              = cluster

	-- Auto-size cluster height
	clusterLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		cluster.Size = UDim2.new(0, CW, 0, clusterLayout.AbsoluteContentSize.Y)
	end)

	-- ── Status icon row ──────────────────────────────────────────────────────
	local iconRow = Instance.new("Frame")
	iconRow.Name             = "StatusIcons"
	iconRow.Size             = UDim2.new(1, 0, 0, HUDTheme.StatusIconSize)
	iconRow.BackgroundTransparency = 1
	iconRow.Parent           = cluster

	local iconLayout = Instance.new("UIListLayout")
	iconLayout.FillDirection       = Enum.FillDirection.Horizontal
	iconLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	iconLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
	iconLayout.Padding             = UDim.new(0, HUDTheme.StatusIconSpacing)
	iconLayout.Parent              = iconRow

	for _, cfg in STATUS_CONFIG do
		local f = Instance.new("Frame")
		f.Name                   = "Status_" .. cfg.id
		f.Size                   = UDim2.new(0, HUDTheme.StatusIconSize + 8, 0, HUDTheme.StatusIconSize)
		f.BackgroundColor3       = UITheme.Palette.PanelMid
		f.BackgroundTransparency = 0.70
		f.BorderSizePixel        = 0
		mkCorner(f, UITheme.Corners.Small)
		f.Parent = iconRow

		local lbl = Instance.new("TextLabel")
		lbl.Size               = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text               = cfg.abbr
		lbl.TextColor3         = UITheme.Palette.TextPrimary
		lbl.TextTransparency   = 0.50
		lbl.Font               = UITheme.Typography.FontBold
		lbl.TextSize           = UITheme.Typography.SizeXSmall
		lbl.Parent             = f

		statusIcons[cfg.id] = { frame = f, label = lbl }
	end

	-- ── HP bar ───────────────────────────────────────────────────────────────
	local hpContainer = Instance.new("Frame")
	hpContainer.Name             = "HealthBar"
	hpContainer.Size             = UDim2.new(0, HUDTheme.HealthBarWidth, 0, HUDTheme.HealthBarHeight)
	hpContainer.BackgroundColor3 = UITheme.Palette.PanelDark
	hpContainer.BackgroundTransparency = 0.30
	hpContainer.BorderSizePixel  = 0
	hpContainer.ClipsDescendants = true
	mkCorner(hpContainer, UITheme.Corners.Small)
	hpContainer.Parent = cluster

	healthBarStroke = mkStroke(hpContainer, UITheme.Palette.AccentIron, 1.5, 0.5)

	healthFill = Instance.new("Frame")
	healthFill.Name             = "Fill"
	healthFill.Size             = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = HUDTheme.HealthFullColor
	healthFill.BorderSizePixel  = 0
	mkCorner(healthFill, UITheme.Corners.Small)
	healthFill.Parent = hpContainer

	healthFlashFrame = Instance.new("Frame")
	healthFlashFrame.Name               = "DamageFlash"
	healthFlashFrame.Size               = UDim2.new(1, 0, 1, 0)
	healthFlashFrame.BackgroundColor3   = Color3.new(1, 1, 1)
	healthFlashFrame.BackgroundTransparency = 1
	healthFlashFrame.BorderSizePixel    = 0
	healthFlashFrame.ZIndex             = 4
	healthFlashFrame.Parent             = hpContainer

	mkLabel(hpContainer, "HpLabel", "hp",
		UDim2.new(0.35, 0, 1, 0), UDim2.new(0, 8, 0, 0),
		UITheme.Typography.SizeSmall, UITheme.Typography.FontBold,
		UITheme.Palette.TextPrimary, Enum.TextXAlignment.Left, 5)

	healthValueLabel = mkLabel(hpContainer, "HpValue", "-- / --",
		UDim2.new(1, -16, 1, 0), UDim2.new(0, 0, 0, 0),
		UITheme.Typography.SizeSmall, UITheme.Typography.FontBold,
		UITheme.Palette.TextPrimary, Enum.TextXAlignment.Right, 5)


	local postureContainer = Instance.new("Frame")
	postureContainer.Name             = "PostureBar"
	postureContainer.Size             = UDim2.new(0, HUDTheme.HealthBarWidth, 0, HUDTheme.PostureBarHeight)
	postureContainer.BackgroundColor3 = UITheme.Palette.PanelDark
	postureContainer.BackgroundTransparency = 0.40
	postureContainer.BorderSizePixel  = 0
	postureContainer.ClipsDescendants = true
	mkCorner(postureContainer, UITheme.Corners.Small)
	postureContainer.Parent = cluster

	postureFill = Instance.new("Frame")
	postureFill.Name             = "Fill"
	postureFill.Size             = UDim2.new(0, 0, 1, 0)
	postureFill.BackgroundColor3 = UITheme.Palette.PostureGrey
	postureFill.BorderSizePixel  = 0
	mkCorner(postureFill, UITheme.Corners.Small)
	postureFill.Parent = postureContainer

	mkLabel(postureContainer, "PostureLabel", "POSTURE",
		UDim2.new(1, -6, 1, 0), UDim2.new(0, 0, 0, 0),
		UITheme.Typography.SizeXSmall, UITheme.Typography.FontBold,
		UITheme.Palette.TextSecondary, Enum.TextXAlignment.Right, 3)

	-- Mana bar (70 % of cluster width)
	local manaW = math.floor(CW * HUDTheme.ManaBarWidthScale)
	local manaContainer = Instance.new("Frame")
	manaContainer.Name             = "ManaBar"
	manaContainer.Size             = UDim2.new(0, manaW, 0, HUDTheme.AmbientBarHeight)
	manaContainer.BackgroundColor3 = UITheme.Palette.PanelDark
	manaContainer.BackgroundTransparency = 0.40
	manaContainer.BorderSizePixel  = 0
	manaContainer.ClipsDescendants = true
	mkCorner(manaContainer, UITheme.Corners.Small)
	manaContainer.Parent = cluster

	manaFill = Instance.new("Frame")
	manaFill.Name             = "Fill"
	manaFill.Size             = UDim2.new(1, 0, 1, 0)
	manaFill.BackgroundColor3 = UITheme.Palette.ManaBlue
	manaFill.BorderSizePixel  = 0
	mkCorner(manaFill, UITheme.Corners.Small)
	manaFill.Parent = manaContainer

	mkLabel(manaContainer, "ManaLabel", "mana",
		UDim2.new(1, -6, 1, 0), UDim2.new(0, 0, 0, 0),
		UITheme.Typography.SizeXSmall, UITheme.Typography.FontRegular,
		UITheme.Palette.TextSecondary, Enum.TextXAlignment.Right, 3)

	-- Breath bar (55 % of cluster width)
	local breathW = math.floor(CW * HUDTheme.BreathBarWidthScale)
	local breathContainer = Instance.new("Frame")
	breathContainer.Name             = "BreathBar"
	breathContainer.Size             = UDim2.new(0, breathW, 0, HUDTheme.AmbientBarHeight)
	breathContainer.BackgroundColor3 = UITheme.Palette.PanelDark
	breathContainer.BackgroundTransparency = 0.40
	breathContainer.BorderSizePixel  = 0
	breathContainer.ClipsDescendants = true
	mkCorner(breathContainer, UITheme.Corners.Small)
	breathContainer.Parent = cluster

	breathFill = Instance.new("Frame")
	breathFill.Name             = "Fill"
	breathFill.Size             = UDim2.new(1, 0, 1, 0)
	breathFill.BackgroundColor3 = UITheme.Palette.BreathTeal
	breathFill.BorderSizePixel  = 0
	mkCorner(breathFill, UITheme.Corners.Small)
	breathFill.Parent = breathContainer

	-- Exhausted flash overlay lives on the breath container, not the fill
	exhaustedOverlay = Instance.new("Frame")
	exhaustedOverlay.Name               = "ExhaustedOverlay"
	exhaustedOverlay.Size               = UDim2.new(1, 0, 1, 0)
	exhaustedOverlay.BackgroundColor3   = UITheme.Palette.BreathRed
	exhaustedOverlay.BackgroundTransparency = 1
	exhaustedOverlay.BorderSizePixel    = 0
	exhaustedOverlay.ZIndex             = 5
	mkCorner(exhaustedOverlay, UITheme.Corners.Small)
	exhaustedOverlay.Parent = breathContainer

	mkLabel(breathContainer, "BreathLabel", "breath",
		UDim2.new(1, -6, 1, 0), UDim2.new(0, 0, 0, 0),
		UITheme.Typography.SizeXSmall, UITheme.Typography.FontRegular,
		UITheme.Palette.TextSecondary, Enum.TextXAlignment.Right, 6)

	-- ── Bottom row: ability slots  +  resonance pips ─────────────────────────
	local SS    = HUDTheme.AbilitySlotSize     -- 32
	local SSP   = HUDTheme.AbilitySlotSpacing  --  6
	local PIPH  = 8
	local PIPSP = 5

	local bottomRow = Instance.new("Frame")
	bottomRow.Name             = "BottomRow"
	bottomRow.Size             = UDim2.new(1, 0, 0, SS)
	bottomRow.BackgroundTransparency = 1
	bottomRow.Parent           = cluster

	local bottomLayout = Instance.new("UIListLayout")
	bottomLayout.FillDirection       = Enum.FillDirection.Horizontal
	bottomLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bottomLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
	bottomLayout.Padding             = UDim.new(0, SSP * 2)
	bottomLayout.Parent              = bottomRow

	-- Ability slots group
	local slotsFrame = Instance.new("Frame")
	slotsFrame.Name = "AbilitySlots"
	slotsFrame.Size = UDim2.new(0,
		(SS * HUDTheme.AbilitySlotCount) + (SSP * (HUDTheme.AbilitySlotCount - 1)),
		0, SS)
	slotsFrame.BackgroundTransparency = 1
	slotsFrame.Parent = bottomRow

	local slotsLayout = Instance.new("UIListLayout")
	slotsLayout.FillDirection       = Enum.FillDirection.Horizontal
	slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	slotsLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
	slotsLayout.Padding             = UDim.new(0, SSP)
	slotsLayout.Parent              = slotsFrame

	for i = 1, HUDTheme.AbilitySlotCount do
		local sf = Instance.new("Frame")
		sf.Name                   = "Slot" .. i
		sf.Size                   = UDim2.new(0, SS, 0, SS)
		sf.BackgroundColor3       = UITheme.Palette.PanelMid
		sf.BackgroundTransparency = 0.50
		sf.BorderSizePixel        = 0
		mkCorner(sf, UITheme.Corners.Small)
		mkStroke(sf, UITheme.Palette.AccentIron, 1, 0.55)
		sf.Parent = slotsFrame

		-- Slot number (top-left micro label)
		local numLbl = Instance.new("TextLabel")
		numLbl.Size               = UDim2.new(0, 10, 0, 10)
		numLbl.Position           = UDim2.new(0, 3, 0, 2)
		numLbl.BackgroundTransparency = 1
		numLbl.Text               = tostring(i)
		numLbl.TextColor3         = UITheme.Palette.TextSecondary
		numLbl.Font               = UITheme.Typography.FontBold
		numLbl.TextSize           = UITheme.Typography.SizeXSmall
		numLbl.ZIndex             = 2
		numLbl.Parent             = sf

		-- Dark cooldown overlay
		local ov = Instance.new("Frame")
		ov.Name                   = "CooldownOverlay"
		ov.Size                   = UDim2.new(1, 0, 1, 0)
		ov.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
		ov.BackgroundTransparency = 1
		ov.BorderSizePixel        = 0
		ov.ZIndex                 = 3
		mkCorner(ov, UITheme.Corners.Small)
		ov.Parent = sf

		-- Countdown number
		local cdLbl = Instance.new("TextLabel")
		cdLbl.Size               = UDim2.new(1, 0, 1, 0)
		cdLbl.BackgroundTransparency = 1
		cdLbl.Text               = ""
		cdLbl.TextColor3         = UITheme.Palette.TextPrimary
		cdLbl.Font               = UITheme.Typography.FontBold
		cdLbl.TextSize           = UITheme.Typography.SizeMedium
		cdLbl.TextXAlignment     = Enum.TextXAlignment.Center
		cdLbl.Visible            = false
		cdLbl.ZIndex             = 4
		cdLbl.Parent             = sf

		abilitySlots[i] = { frame = sf, overlay = ov, cooldownLabel = cdLbl }
	end

	-- Resonance pips group
	local pipsW = (PIPH * MAX_RESONANCE_PIPS) + (PIPSP * (MAX_RESONANCE_PIPS - 1)) + 90
	local pipsFrame = Instance.new("Frame")
	pipsFrame.Name             = "ResonancePips"
	pipsFrame.Size             = UDim2.new(0, pipsW, 0, SS)
	pipsFrame.BackgroundTransparency = 1
	pipsFrame.Parent           = bottomRow

	local pipsLayout = Instance.new("UIListLayout")
	pipsLayout.FillDirection       = Enum.FillDirection.Horizontal
	pipsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	pipsLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
	pipsLayout.Padding             = UDim.new(0, PIPSP)
	pipsLayout.Parent              = pipsFrame

	mkLabel(pipsFrame, "ResonanceTitle", "RESONANCE",
		UDim2.new(0, 82, 0, PIPH + 2),
		UDim2.new(0, 0, 0.5, -(PIPH / 2 + 1)),
		UITheme.Typography.SizeXSmall, UITheme.Typography.FontBold,
		UITheme.Palette.TextSecondary, Enum.TextXAlignment.Left)

	for i = 1, MAX_RESONANCE_PIPS do
		local dot = Instance.new("Frame")
		dot.Name             = "Pip" .. i
		dot.Size             = UDim2.new(0, PIPH, 0, PIPH)
		dot.BackgroundColor3 = UITheme.Palette.PanelMid
		dot.BackgroundTransparency = 0.60
		dot.BorderSizePixel  = 0
		mkCorner(dot, UDim.new(1, 0))
		dot.Parent = pipsFrame
		resonanceDots[i] = dot
	end
end

--------------------------------------------------------------------------------
-- Profile / state callbacks
--------------------------------------------------------------------------------
local function onProfileLoaded(newProfile: PlayerProfile)
	profile = newProfile
	updateHealthBar(newProfile.CurrentHealth, newProfile.MaxHealth)
	updateManaBar(newProfile.CurrentMana,     newProfile.MaxMana)
end

local function onProfileUpdated(newProfile: PlayerProfile)
	profile = newProfile
	updateHealthBar(newProfile.CurrentHealth, newProfile.MaxHealth)
	updateManaBar(newProfile.CurrentMana,     newProfile.MaxMana)
end

local function onStateChanged(_old: PlayerState, newState: PlayerState)
	currentState = newState
end

--------------------------------------------------------------------------------
-- Heartbeat: breath bar + exhausted overlay
--------------------------------------------------------------------------------
local function onHeartbeat(dt: number)
	if not MovementController then return end

	local breath    = MovementController.GetBreath    and MovementController.GetBreath()    or 0
	local breathMax = MovementController.GetBreathMax and MovementController.GetBreathMax() or 100
	local pct = if breathMax > 0 then math.clamp(breath / breathMax, 0, 1) else 1

	if breathFill then
		breathFill.Size = breathFill.Size:Lerp(UDim2.new(pct, 0, 1, 0), math.min(1, dt * 8))
	end
	updateBreathVisuals(pct)

	if exhaustedOverlay then
		local exhausted = MovementController.IsBreathExhausted
			and MovementController.IsBreathExhausted()
		if exhausted then
			exhaustPulseTime += dt * 4
			exhaustedOverlay.BackgroundTransparency =
				1 - (0.5 + 0.4 * math.sin(exhaustPulseTime)) * 0.55
		else
			exhaustPulseTime = 0
			exhaustedOverlay.BackgroundTransparency = 1
		end
	end
end

--------------------------------------------------------------------------------
-- Controller API
--------------------------------------------------------------------------------
local PlayerHUDController = {}

function PlayerHUDController:Init(dependencies: any)
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

function PlayerHUDController:Start()
	buildHUDCluster()

	movementConn = RunService.Heartbeat:Connect(onHeartbeat)

	StateSyncController.GetProfileLoadedSignal():Connect(onProfileLoaded)
	StateSyncController.GetProfileUpdatedSignal():Connect(onProfileUpdated)
	StateSyncController.GetStateChangedSignal():Connect(onStateChanged)

	profile      = StateSyncController.GetCurrentProfile()
	currentState = StateSyncController.GetCurrentState()
	if profile then
		updateHealthBar(profile.CurrentHealth, profile.MaxHealth)
		updateManaBar(profile.CurrentMana,     profile.MaxMana)
	end

	-- Posture
	local postureEvent = NetworkProvider:GetRemoteEvent("PostureChanged")
	if postureEvent then
		postureEvent.OnClientEvent:Connect(function(playerId: number, current: number, max: number)
			if playerId ~= Players.LocalPlayer.UserId then return end
			updatePostureBar(current, max)
		end)
	end

	-- Zone / ring + aspect border
	if NetworkController then
		NetworkController:RegisterHandler("RingChanged", showZoneChange)
		NetworkController:RegisterHandler("SwitchAspectResult", function(packet: any)
			updateAspectBorder(packet and packet.AspectId)
		end)
		NetworkController:RegisterHandler("SelectAspectResult", function(packet: any)
			updateAspectBorder(packet and packet.AspectId)
		end)
	end

	-- Status attributes (bind on spawn + respawn)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		task.wait()
		bindStatusAttributes()
	end)
	if Players.LocalPlayer.Character then
		bindStatusAttributes()
	end

	-- Resonance pips
	if ProgressionController then
		local state = ProgressionController:GetState()
		if state then updateResonancePips(state.ResonanceShards or 0) end
		table.insert(ProgressionController._resonanceListeners, function(s: any)
			updateResonancePips(s.ResonanceShards or 0)
		end)
	end

	print("[PlayerHUDController] HUD cluster active")
end

function PlayerHUDController:Shutdown()
	if movementConn then movementConn:Disconnect(); movementConn = nil end
	stopCritPulse()
	for _, c in statusConns do c:Disconnect() end
	table.clear(statusConns)
	if zoneFadeThread then task.cancel(zoneFadeThread); zoneFadeThread = nil end
	if clusterGui then clusterGui:Destroy() end
	print("[PlayerHUDController] Shutdown complete")
end

function PlayerHUDController:HideHUD()
	if clusterGui then clusterGui.Enabled = false end
	hudVisible = false
end

function PlayerHUDController:ShowHUD()
	if clusterGui then clusterGui.Enabled = true end
	hudVisible = true
end

-- Public surface for other controllers
PlayerHUDController.UpdateAspectBorder = updateAspectBorder
PlayerHUDController.SetSlotCooldown    = setSlotCooldown
PlayerHUDController.UpdateHealthBar    = updateHealthBar
PlayerHUDController.UpdatePostureBar   = updatePostureBar

return PlayerHUDController
