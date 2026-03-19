import os

path = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "src",
    "client",
    "controllers",
    "PlayerHUDController.lua",
)

# Read existing file, keep only the first 610 complete lines
with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

keep = "".join(lines[:610])

# The remainder that was truncated
remainder = r"""
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
"""

with open(path, "w", encoding="utf-8") as f:
    f.write(keep + remainder)

with open(path, "r", encoding="utf-8") as f:
    final = f.readlines()

print(f"Done. PlayerHUDController.lua now has {len(final)} lines.")
