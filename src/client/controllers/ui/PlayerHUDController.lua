--!strict
--[[
	PlayerHUDController.lua

	Clean 4-bar Deepwoken-style HUD.
	No labels. No boxes. No clutter.

	Bars (bottom-centre, stacked):
	  HP         300 x 16 px   warm gold fill
	  Posture    300 x  5 px   grey -> blood-red
	  Mana       200 x  5 px   muted blue
	  Luminance  150 x  5 px   pale gold

	Also manages the top-centre zone / ring notification.
	Hides entirely when inventory is open (called by InventoryController).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared

local UITheme         = require(script.Parent.Parent.Parent.modules.UITheme)
local HUDLayout       = require(script.Parent.Parent.Parent.modules.HUDLayout)
local HUDTheme        = require(Shared.modules.ui.HUDTheme)
local NetworkProvider = require(Shared.network.NetworkProvider)

local PlayerData   = require(Shared.types.PlayerData)
type PlayerProfile = PlayerData.PlayerProfile
type PlayerState   = PlayerData.PlayerState

--------------------------------------------------------------------------------
-- Injected deps
--------------------------------------------------------------------------------
local StateSyncController: any = nil
local MovementController:  any = nil
local NetworkController:   any = nil

--------------------------------------------------------------------------------
-- UI roots
--------------------------------------------------------------------------------
local playerGui:  PlayerGui
local clusterGui: ScreenGui

--------------------------------------------------------------------------------
-- Bar fill references
--------------------------------------------------------------------------------
local healthFill:       Frame
local healthFlashFrame: Frame
local healthBarStroke:  UIStroke
local healthLabel:      TextLabel
local postureFill:      Frame
local postureLabel:     TextLabel
local manaFill:         Frame
local manaLabel:        TextLabel
local luminanceFill:    Frame
local luminanceLabel:   TextLabel

-- Zone notification
local zoneFrame:     Frame
local zoneTopDiv:    Frame
local zoneBotDiv:    Frame
local zoneNameLabel: TextLabel
local zoneFadeThread: thread?

--------------------------------------------------------------------------------
-- Runtime state
--------------------------------------------------------------------------------
local profile:         PlayerProfile? = nil
local lastHealth:      number  = math.huge
local critPulseConn:   RBXScriptConnection?
local critPulseActive: boolean = false
local hudVisible:      boolean = true

--------------------------------------------------------------------------------
-- Tween presets
--------------------------------------------------------------------------------
local FAST   = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SMOOTH = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLOW   = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function tw(inst: Instance, info: TweenInfo, props: { [string]: any })
	TweenService:Create(inst, info, props):Play()
end

--------------------------------------------------------------------------------
-- Colour helpers
--------------------------------------------------------------------------------
local function healthColor(pct: number): Color3
	if pct <= HUDTheme.HealthCritThreshold then return HUDTheme.HealthCritColor end
	if pct <= HUDTheme.HealthWarnThreshold  then return HUDTheme.HealthWarnColor end
	return HUDTheme.HealthFullColor
end

local function postureColor(pct: number): Color3
	if pct < HUDTheme.PostureWarnThreshold then return UITheme.Palette.PostureGrey end
	local t = (pct - HUDTheme.PostureWarnThreshold) / (1 - HUDTheme.PostureWarnThreshold)
	return UITheme.Palette.PostureGrey:Lerp(HUDTheme.PostureWarnColor, t)
end

--------------------------------------------------------------------------------
-- Crit pulse (HP fill cycles red when <= 15 %)
--------------------------------------------------------------------------------
local function startCritPulse()
	if critPulseActive then return end
	critPulseActive = true
	critPulseConn = RunService.Heartbeat:Connect(function()
		if not healthFill or not healthFill.Parent then return end
		local a = 0.5 + 0.5 * math.sin(tick() * math.pi * 2)
		healthFill.BackgroundColor3 =
			HUDTheme.HealthCritColor:Lerp(Color3.fromRGB(255, 40, 40), a * 0.5)
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
local function updateHealth(current: number, max: number)
	if not healthFill then
		warn("[PlayerHUDController] updateHealth called but healthFill is nil")
		return
	end
	current = math.max(0, current or 0)
	max = math.max(1, max or 100)
	local pct = math.clamp(current / max, 0, 1)
	print(`[PlayerHUDController] updateHealth: {current}/{max} = {math.floor(pct * 100)}%`)

	if healthLabel then
		healthLabel.Text = string.format("HP: %d / %d", math.floor(current), math.floor(max))
	end

	-- White flash on damage
	if current < lastHealth and healthFlashFrame then
		healthFlashFrame.BackgroundTransparency = 0.25
		tw(healthFlashFrame, FAST, { BackgroundTransparency = 1 })
	end
	lastHealth = current

	tw(healthFill, FAST, { Size = UDim2.new(pct, 0, 1, 0) })

	if pct <= HUDTheme.HealthCritThreshold then
		startCritPulse()
	else
		stopCritPulse()
		healthFill.BackgroundColor3 = healthColor(pct)
	end
end

local function updatePosture(current: number, max: number)
	if not postureFill then
		warn("[PlayerHUDController] updatePosture called but postureFill is nil")
		return
	end
	current = math.max(0, current or 0)
	max = math.max(1, max or 100)
	local pct = math.clamp(current / max, 0, 1)
	print(`[PlayerHUDController] updatePosture: {current}/{max} = {math.floor(pct * 100)}%`)

	if postureLabel then
		postureLabel.Text = string.format("PO: %d / %d", math.floor(current), math.floor(max))
	end

	tw(postureFill, FAST, { Size = UDim2.new(pct, 0, 1, 0) })
	postureFill.BackgroundColor3 = postureColor(pct)
end

local function updateMana(current: number, max: number)
	if not manaFill then
		warn("[PlayerHUDController] updateMana called but manaFill is nil")
		return
	end
	current = math.max(0, current or 0)
	max = math.max(1, max or 100)
	local pct = math.clamp(current / max, 0, 1)
	print(`[PlayerHUDController] updateMana: {current}/{max} = {math.floor(pct * 100)}%`)

	if manaLabel then
		manaLabel.Text = string.format("MP: %d / %d", math.floor(current), math.floor(max))
	end

	tw(manaFill, FAST, { Size = UDim2.new(pct, 0, 1, 0) })
end

local function updateLuminance(current: number, max: number)
	if not luminanceFill then return end
	current = math.max(0, current or 0)
	max = math.max(1, max or 100)
	local pct = math.clamp(current / max, 0, 1)

	if luminanceLabel then
		luminanceLabel.Text = string.format("LU: %d / %d", math.floor(current), math.floor(max))
	end

	tw(luminanceFill, FAST, { Size = UDim2.new(pct, 0, 1, 0) })
end

local function updateAspectBorder(aspectId: string?)
	if not healthBarStroke then return end
	local col = aspectId and HUDTheme.AspectBorderColor[aspectId]
	if col then
		healthBarStroke.Color        = col
		healthBarStroke.Transparency = 0
	else
		healthBarStroke.Color        = UITheme.Palette.AccentIron
		healthBarStroke.Transparency = 0.55
	end
end

--------------------------------------------------------------------------------
-- Factory: one dark background + fill frame
-- Returns (background, fill)
--------------------------------------------------------------------------------
local function makeBar(
	parent:    Instance,
	name:      string,
	w:         number,
	h:         number,
	fillColor: Color3
): (Frame, Frame, TextLabel)
	local bg = Instance.new("Frame")
	bg.Name                   = name
	bg.Size                   = UDim2.new(0, w, 0, h)
	bg.BackgroundColor3       = UITheme.Palette.PanelDark
	bg.BackgroundTransparency = 0.50
	bg.BorderSizePixel        = 0
	bg.ClipsDescendants       = true

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 3)
	bgCorner.Parent = bg

	bg.Parent = parent

	local fill = Instance.new("Frame")
	fill.Name             = "Fill"
	fill.Size             = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel  = 0

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	fill.Parent = bg

	local label = Instance.new("TextLabel")
	label.Name = "ValueLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextSize = math.max(10, h * 0.85)
	label.Font = Enum.Font.SourceSansBold
	label.Text = ""
	label.ZIndex = 5
	label.Parent = bg

	return bg, fill, label
end

--------------------------------------------------------------------------------
-- Zone / ring notification
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
	zoneNameLabel.TextSize           = 22
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
		zoneNameLabel.TextSize   = 22
		zoneNameLabel.Font       = UITheme.Typography.FontBold
	else
		zoneFrame.Size           = UDim2.new(0, 300, 0, 40)
		zoneNameLabel.TextColor3 = UITheme.Palette.TextPrimary
		zoneNameLabel.TextSize   = 16
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
			if state == Enum.PlaybackState.Completed then
				zoneFrame.Visible = false
			end
		end)
		fin:Play()
		zoneFadeThread = nil
	end)
end

--------------------------------------------------------------------------------
-- Build the 4-bar cluster
--------------------------------------------------------------------------------
local function buildHUD()
	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then
		error("[PlayerHUDController] Failed to find PlayerGui")
		return
	end

	-- Clean up any existing HUD
	local existing = playerGui:FindFirstChild("PlayerHUD")
	if existing then
		existing:Destroy()
	end

	clusterGui = Instance.new("ScreenGui")
	clusterGui.Name           = "PlayerHUD"
	clusterGui.ResetOnSpawn   = false
	clusterGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	clusterGui.DisplayOrder   = HUDLayout.Layers.HUD
	clusterGui.IgnoreGuiInset = false
	clusterGui.Parent         = playerGui

	-- Zone notification (independent of cluster position)
	buildZoneNotification(clusterGui)

	local BW   = HUDTheme.BarWidth          -- 300
	local HPH  = HUDTheme.HealthBarHeight   -- 16
	local ABH  = HUDTheme.AmbientBarHeight  --  5
	local GAP  = HUDTheme.BarGap            --  3
	local OFF  = HUDTheme.HUD_BOTTOM_OFFSET -- 90

	local totalH = HPH + ABH * 3 + GAP * 3

	-- Invisible cluster frame — just a layout container
	local cluster = Instance.new("Frame")
	cluster.Name             = "HUDCluster"
	cluster.AnchorPoint      = Vector2.new(0.5, 1)
	cluster.Position         = UDim2.new(0.5, 0, 1, -OFF)
	cluster.Size             = UDim2.new(0, BW, 0, totalH)
	cluster.BackgroundTransparency = 1
	cluster.BorderSizePixel  = 0
	cluster.Parent           = clusterGui

	-- Barely-visible gradient scrim so bars read against any background
	local scrim = Instance.new("Frame")
	scrim.Name             = "Scrim"
	scrim.AnchorPoint      = Vector2.new(0.5, 1)
	scrim.Position         = UDim2.new(0.5, 0, 1, -OFF + 14)
	scrim.Size             = UDim2.new(0, BW + 24, 0, totalH + 22)
	scrim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	scrim.BackgroundTransparency = 0.82
	scrim.BorderSizePixel  = 0

	local scrimGrad = Instance.new("UIGradient")
	scrimGrad.Rotation = 90
	scrimGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.0, 0.0),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1.0, 1.0),
	})
	scrimGrad.Parent = scrim
	scrim.Parent = clusterGui

	-- Stack bars vertically
	local layout = Instance.new("UIListLayout")
	layout.FillDirection       = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding             = UDim.new(0, GAP)
	layout.Parent              = cluster

	-- ── HP bar ───────────────────────────────────────────────────────────────
	local hpBg, hpFill, hpLbl = makeBar(cluster, "HealthBar", BW, HPH, HUDTheme.HealthFullColor)
	healthFill = hpFill
	healthLabel = hpLbl

	-- Aspect-coloured stroke on HP bar
	healthBarStroke = Instance.new("UIStroke")
	healthBarStroke.Color        = UITheme.Palette.AccentIron
	healthBarStroke.Thickness    = 1
	healthBarStroke.Transparency = 0.55
	healthBarStroke.Parent       = hpBg

	-- White damage-flash overlay
	healthFlashFrame = Instance.new("Frame")
	healthFlashFrame.Name               = "DamageFlash"
	healthFlashFrame.Size               = UDim2.new(1, 0, 1, 0)
	healthFlashFrame.BackgroundColor3   = Color3.new(1, 1, 1)
	healthFlashFrame.BackgroundTransparency = 1
	healthFlashFrame.BorderSizePixel    = 0
	healthFlashFrame.ZIndex             = 3
	healthFlashFrame.Parent             = hpBg

	-- ── Posture bar ──────────────────────────────────────────────────────────
	local _, postureFill_, posLbl = makeBar(cluster, "PostureBar", BW, ABH, UITheme.Palette.PostureGrey)
	postureFill = postureFill_
	postureLabel = posLbl

	-- ── Mana bar (67 % width) ────────────────────────────────────────────────
	local manaW = math.floor(BW * HUDTheme.ManaBarWidthScale)
	local _, manaFill_, manaLbl = makeBar(cluster, "ManaBar", manaW, ABH, UITheme.Palette.ManaBlue)
	manaFill = manaFill_
	manaLabel = manaLbl

	-- ── Luminance bar (50 % width) ───────────────────────────────────────────
	local lumW = math.floor(BW * HUDTheme.LuminanceBarWidthScale)
	local _, lumFill, lumLbl = makeBar(cluster, "LuminanceBar", lumW, ABH, HUDTheme.LuminanceColor)
	luminanceFill = lumFill
	luminanceLabel = lumLbl
end

--------------------------------------------------------------------------------
-- Profile callbacks
--------------------------------------------------------------------------------
local function onProfileLoaded(p: PlayerProfile)
	profile = p
	updateHealth(p.Health.Current,    p.Health.Max)
	updatePosture(p.Posture.Current,  p.Posture.Max)
	updateMana(p.Mana.Current,        p.Mana.Max)
	if p.Luminance then
		updateLuminance(p.Luminance.Current, p.Luminance.Max)
	end
end

local function onProfileUpdated(p: PlayerProfile)
	profile = p
	updateHealth(p.Health.Current,    p.Health.Max)
	updatePosture(p.Posture.Current,  p.Posture.Max)
	updateMana(p.Mana.Current,        p.Mana.Max)
	if p.Luminance then
		updateLuminance(p.Luminance.Current, p.Luminance.Max)
	end
end

local function onCombatDataUpdated(packet: any)
	print("[PlayerHUDController] ===== onCombatDataUpdated CALLED =====")
	print(`[PlayerHUDController] Packet: HP={packet.Health}/{packet.MaxHealth}, MP={packet.Mana}/{packet.MaxMana}, PO={packet.Posture}/{packet.MaxPosture}`)

	-- Update cached profile if it exists
	if profile then
		if packet.Health then
			profile.Health.Current = packet.Health
			if packet.MaxHealth then profile.Health.Max = packet.MaxHealth end
		end
		if packet.Mana then
			profile.Mana.Current = packet.Mana
			if packet.MaxMana then profile.Mana.Max = packet.MaxMana end
		end
		if packet.Posture then
			profile.Posture.Current = packet.Posture
			if packet.MaxPosture then profile.Posture.Max = packet.MaxPosture end
		end
	end

	-- Always update UI from packet data (don't wait for profile to load)
	if packet.Health then
		local maxHealth = packet.MaxHealth or (profile and profile.Health.Max) or 100
		print(`[PlayerHUDController] Calling updateHealth({packet.Health}, {maxHealth})`)
		updateHealth(packet.Health, maxHealth)
	end

	if packet.Mana then
		local maxMana = packet.MaxMana or (profile and profile.Mana.Max) or 100
		print(`[PlayerHUDController] Calling updateMana({packet.Mana}, {maxMana})`)
		updateMana(packet.Mana, maxMana)
	end

	if packet.Posture then
		local maxPosture = packet.MaxPosture or (profile and profile.Posture.Max) or 100
		print(`[PlayerHUDController] Calling updatePosture({packet.Posture}, {maxPosture})`)
		updatePosture(packet.Posture, maxPosture)
	end

	print("[PlayerHUDController] ===== onCombatDataUpdated COMPLETE =====")
end

--------------------------------------------------------------------------------
-- Controller API
--------------------------------------------------------------------------------
local PlayerHUDController = {}

function PlayerHUDController:Init(dependencies: any)
	StateSyncController  = dependencies.StateSyncController
	MovementController   = dependencies.MovementController
	NetworkController    = dependencies.NetworkController

	if not StateSyncController then
		error("[PlayerHUDController] StateSyncController dependency required")
	end
	if not NetworkController then
		error("[PlayerHUDController] NetworkController dependency required")
	end

	print("[PlayerHUDController] Initialized")
end

function PlayerHUDController:Start()
	local buildSuccess, buildErr = pcall(buildHUD)
	if not buildSuccess then
		warn("[PlayerHUDController] Failed to build HUD: " .. tostring(buildErr))
		return
	end

	-- Data signals - safe nil checks
	if StateSyncController then
		print("[PlayerHUDController] StateSyncController exists, setting up signals...")

		local profileLoadedSig = StateSyncController.GetProfileLoadedSignal and StateSyncController.GetProfileLoadedSignal()
		if profileLoadedSig then
			print("[PlayerHUDController] ✓ Connected to ProfileLoadedSignal")
			profileLoadedSig:Connect(onProfileLoaded)
		else
			warn("[PlayerHUDController] ProfileLoadedSignal not available")
		end

		local profileUpdatedSig = StateSyncController.GetProfileUpdatedSignal and StateSyncController.GetProfileUpdatedSignal()
		if profileUpdatedSig then
			print("[PlayerHUDController] ✓ Connected to ProfileUpdatedSignal")
			profileUpdatedSig:Connect(onProfileUpdated)
		else
			warn("[PlayerHUDController] ProfileUpdatedSignal not available")
		end

		local combatDataSig = StateSyncController.GetCombatDataUpdatedSignal and StateSyncController.GetCombatDataUpdatedSignal()
		if combatDataSig then
			print("[PlayerHUDController] ✓ Connected to CombatDataUpdatedSignal")
			combatDataSig:Connect(onCombatDataUpdated)
		else
			warn("[PlayerHUDController] CombatDataUpdatedSignal not available")
		end

		local currentProf = StateSyncController.GetCurrentProfile and StateSyncController.GetCurrentProfile()
		if currentProf then
			print("[PlayerHUDController] Initial profile loaded, calling onProfileLoaded...")
			onProfileLoaded(currentProf)
		else
			print("[PlayerHUDController] Profile not yet available at Start time (expected - will arrive via ProfileData event)")
		end
	else
		warn("[PlayerHUDController] StateSyncController not available in Start()")
	end

	-- Posture (driven by server RemoteEvent, not profile poll)
	local postureEvent = NetworkProvider:GetRemoteEvent("PostureChanged")
	if postureEvent then
		postureEvent.OnClientEvent:Connect(function(
			playerId: number,
			current:  number,
			max:      number
		)
			if playerId ~= Players.LocalPlayer.UserId then return end
			updatePosture(current, max)
		end)
	else
		warn("[PlayerHUDController] PostureChanged RemoteEvent not found")
	end

	-- Zone / ring notification + aspect border
	if NetworkController then
		NetworkController:RegisterHandler("RingChanged", showZoneChange)

		NetworkController:RegisterHandler("SwitchAspectResult", function(packet: any)
			updateAspectBorder(packet and packet.AspectId)
		end)
		NetworkController:RegisterHandler("SelectAspectResult", function(packet: any)
			updateAspectBorder(packet and packet.AspectId)
		end)
	else
		warn("[PlayerHUDController] NetworkController not available")
	end

	print("[PlayerHUDController] HUD active")
end

function PlayerHUDController:Shutdown()
	stopCritPulse()
	if zoneFadeThread then task.cancel(zoneFadeThread); zoneFadeThread = nil end
	if clusterGui then clusterGui:Destroy() end
	print("[PlayerHUDController] Shutdown")
end

function PlayerHUDController:HideHUD()
	if clusterGui and hudVisible then
		clusterGui.Enabled = false
		hudVisible = false
	end
end

function PlayerHUDController:ShowHUD()
	if clusterGui and not hudVisible then
		clusterGui.Enabled = true
		hudVisible = true
	end
end

-- Exposed so AspectController can call directly after aspect selection
PlayerHUDController.UpdateAspectBorder = updateAspectBorder
PlayerHUDController.UpdateHealth       = updateHealth
PlayerHUDController.UpdatePosture      = updatePosture
PlayerHUDController.UpdateLuminance    = updateLuminance

return PlayerHUDController
