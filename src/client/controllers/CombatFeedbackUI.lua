--!strict
--[[
	CombatFeedbackUI.lua

	Issue #43: Combat Feedback UI (Health Bar, Damage Numbers, VFX)
	Epic: Phase 2 - Combat & Fluidity

	Client-side module for displaying combat feedback including:
	- Floating damage numbers
	- Hit/Miss indicators
	- Block/Parry visual feedback
	- Enemy health bars

	Dependencies: UIBinding (for reactive updates), HitboxService (for hit events)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
local UITheme = require(script.Parent.Parent.modules.UITheme)
local HUDLayout = require(script.Parent.Parent.modules.HUDLayout)

local CombatFeedbackUI = {}

-- Animation & timing constants (use UITheme.Motion where possible)
local DAMAGE_NUMBER_DURATION = 1.5  -- Seconds to show damage number
local DAMAGE_NUMBER_SPEED = 30      -- Studs per second upward
local CRITICAL_MULTIPLIER = 2.0
local STAGGER_FLASH_INTERVAL = 0.08 -- Duration per flash in stagger cycle
local STAGGER_FLASH_CYCLES = 3      -- Number of orange flashes
local FADE_STEP_DURATION = 0.05     -- Standard fade step timing

-- Color references from UITheme (instead of hardcoded RGB)
local CRITICAL_COLOR = UITheme.Palette.CriticalDamage
local NORMAL_COLOR = UITheme.Palette.NormalDamage
local HEAL_COLOR = UITheme.Palette.HealthGreen

-- Active floating numbers
local FloatingNumbers: {{
	TextLabel: TextLabel,
	StartTime: number,
	StartPosition: Vector3,
	Damage: number,
	IsCritical: boolean,
}} = {}

--[[
	Initialize the combat feedback system
]]
function CombatFeedbackUI:Init()
	print("[CombatFeedbackUI] Initializing...")
	-- Initialization deferred to Start() when NetworkProvider is ready
	print("[CombatFeedbackUI] Initialized successfully")
end

--[[
	Start the update loop
]]
function CombatFeedbackUI:Start()
	print("[CombatFeedbackUI] Starting...")

	-- ── Damage numbers ─────────────────────────────────────────────────────
	local hitEvent = NetworkProvider:GetRemoteEvent("HitConfirmed")
	if hitEvent then
		hitEvent.OnClientEvent:Connect(function(attacker, target, damage, isCritical, isDummy)
			CombatFeedbackUI.ShowDamageNumber(target, damage, isCritical or false, isDummy or false)
		end)
	end

	-- ── Block / Parry feedback ─────────────────────────────────────────────
	local blockEvent = NetworkProvider:GetRemoteEvent("BlockFeedback")
	if blockEvent then
		blockEvent.OnClientEvent:Connect(function(blocker, _attacker, _dmg)
			CombatFeedbackUI.ShowBlockFeedback(blocker)
		end)
	end

	local parryEvent = NetworkProvider:GetRemoteEvent("ParryFeedback")
	if parryEvent then
		parryEvent.OnClientEvent:Connect(function(parrier, attacker)
			CombatFeedbackUI.ShowParryFeedback(parrier, attacker)
		end)
	end

	-- Clash feedback (bonus opportunity)
	local clashEvent = NetworkProvider:GetRemoteEvent("ClashOccurred")
	if clashEvent then
		clashEvent.OnClientEvent:Connect(function(attacker, defender, window)
			CombatFeedbackUI.ShowClashFeedback(attacker, defender, window)
		end)
	end

	-- ── Posture bar (local player only) ────────────────────────────────────
	-- PostureChanged is now handled by PlayerHUDController's cluster bar.
	-- CombatFeedbackUI no longer owns a standalone posture bar.


	-- ── Stagger flash (all visible players) ────────────────────────────────
	local staggerEvent = NetworkProvider:GetRemoteEvent("Staggered")
	if staggerEvent then
		staggerEvent.OnClientEvent:Connect(function(playerId: number, duration: number)
			CombatFeedbackUI._PlayStaggerFlash(playerId, duration)
		end)
	end

	-- ── Break executed ─────────────────────────────────────────────────────
	local breakEvent = NetworkProvider:GetRemoteEvent("BreakExecuted")
	if breakEvent then
		breakEvent.OnClientEvent:Connect(function(attackerId: number, targetId: number, damage: number)
			-- Show a special "BREAK!" label above the target
			CombatFeedbackUI._ShowBreakFeedback(targetId, damage)
		end)
	end

	-- ── Death screen ─────────────────────────────────────────────────────────
	local stateChangedEvent = NetworkProvider:GetRemoteEvent("StateChanged")
	if stateChangedEvent then
		stateChangedEvent.OnClientEvent:Connect(function(packet: any)
			if type(packet) == "table" and packet.NewState == "Dead" then
				CombatFeedbackUI._ShowDeathScreen()
			end
		end)
	end

	-- ── Suppressed vignette (posture break) ────────────────────────────────
	local suppressedEvent = NetworkProvider:GetRemoteEvent("Suppressed")
	if suppressedEvent then
		suppressedEvent.OnClientEvent:Connect(function(playerId: number)
			if playerId == Players.LocalPlayer.UserId then
				CombatFeedbackUI._PlaySuppressedVignette()
			end
		end)
	end

	-- Update loop for floating numbers
	game:GetService("RunService").RenderStepped:Connect(function()
		CombatFeedbackUI._UpdateFloatingNumbers()
	end)

	print("[CombatFeedbackUI] Started successfully")
end

-- ─── Posture bar helpers ─────────────────────────────────────────────────────

--[[
	DEPRECATED — posture bar is now part of PlayerHUDController's HUD cluster.
	Kept as a no-op so any stale call sites don't hard-error.
]]
function CombatFeedbackUI._BuildPostureBar(): {bar: Frame, fill: Frame}
	-- No-op: returns a dummy table so stale callers won't nil-index.
	local dummy = Instance.new("Frame")
	return { bar = dummy, fill = dummy }
end

--[[
	Play a brief red flash on the character who was just staggered.
	We find the player by UserId and flash their parts.
]]
function CombatFeedbackUI._PlayStaggerFlash(playerId: number, duration: number)
	-- Find player by UserId
	local target: Player? = nil
	for _, p in Players:GetPlayers() do
		if p.UserId == playerId then
			target = p
			break
		end
	end
	if not target or not target.Character then return end

	local parts: {BasePart} = {}
	for _, desc in target.Character:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end

	-- Flash orange × STAGGER_FLASH_CYCLES then revert
	task.spawn(function()
		for _ = 1, STAGGER_FLASH_CYCLES do
			for _, part in parts do
				part.Color = UITheme.Palette.PostureOrange
			end
			task.wait(STAGGER_FLASH_INTERVAL)
			for _, part in parts do
				-- Revert to default (let Roblox Humanoid handle actual colour)
				part.Color = Color3.fromRGB(163, 162, 165)
			end
			task.wait(STAGGER_FLASH_INTERVAL)
		end
	end)
end

--[[
	Show "BREAK!" floating text above the given target (looked up by UserId).
]]
function CombatFeedbackUI._ShowBreakFeedback(targetId: number, damage: number)
	local target: Player? = nil
	for _, p in Players:GetPlayers() do
		if p.UserId == targetId then
			target = p
			break
		end
	end
	if not target or not target.Character then return end

	local rootPart = Utils.GetRootPart(target)
	if not rootPart then return end

	local screenGui = Instance.new("ScreenGui")
	screenGui.ResetOnSpawn = false
	screenGui.Name = "BreakFeedback"
	screenGui.DisplayOrder = HUDLayout.Layers.HUD
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 160, 0, 50)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = UITheme.Typography.FontBold
	label.TextColor3 = UITheme.Palette.BreakText
	label.Text = ("BREAK! -%d"):format(damage)

	local camera = workspace.CurrentCamera
	local screenPos = camera:WorldToScreenPoint(rootPart.Position + Vector3.new(0, 4, 0))
	label.Position = UDim2.new(0, screenPos.X - 80, 0, screenPos.Y - 25)
	label.Parent = screenGui

	task.spawn(function()
		for i = 1, 15 do
			label.TextTransparency = i / 15
			task.wait(FADE_STEP_DURATION)
		end
		screenGui:Destroy()
	end)
end

--[[
	Show a floating damage number above a target
	@param target The target player to show damage for
	@param damage The damage amount
	@param isCritical Whether this is a critical hit
]]
function CombatFeedbackUI.ShowDamageNumber(target: any, damage: number, isCritical: boolean, isDummy: boolean)
	local rootPart = nil

	if isDummy then
		-- Target is a dummy ID (string)
		local dummyId = target
		local dummyModel = workspace:FindFirstChild(`Dummy_{dummyId}`)
		if dummyModel then
			rootPart = dummyModel:FindFirstChild("Body")
		end
	else
		-- Target is a player
		local player = target
		if not player or not player.Character then
			return
		end
		rootPart = Utils.GetRootPart(player)
	end

	if not rootPart then
		return
	end

	-- Create floating number UI
	local screenGui = Instance.new("ScreenGui")
	screenGui.ResetOnSpawn = false
	screenGui.Name = "DamageNumber"
	screenGui.DisplayOrder = HUDLayout.Layers.HUD
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "DamageLabel"
	textLabel.Size = UDim2.new(0, 100, 0, 50)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.Font = UITheme.Typography.FontBold
	textLabel.TextColor3 = isCritical and CRITICAL_COLOR or NORMAL_COLOR

	-- Format damage text
	local damageText = tostring(math.floor(damage))
	if isCritical then
		damageText = "CRIT! " .. damageText
	end
	textLabel.Text = damageText

	-- Convert world position to screen position
	local rootPosition = rootPart.Position + Vector3.new(0, 3, 0) -- Above target
	local camera = workspace.CurrentCamera
	local screenPosition = camera:WorldToScreenPoint(rootPosition)
	textLabel.Position = UDim2.new(0, screenPosition.X - 50, 0, screenPosition.Y - 25)

	textLabel.Parent = screenGui

	-- Track floating number
	table.insert(FloatingNumbers, {
		TextLabel = textLabel,
		StartTime = tick(),
		StartPosition = rootPosition,
		Damage = damage,
		IsCritical = isCritical,
	})

	print(`[CombatFeedbackUI] ✓ Damage number: {damage} (Critical: {isCritical})`)
end

--[[
	Update all floating numbers
]]
function CombatFeedbackUI._UpdateFloatingNumbers()
	local now = tick()
	local camera = workspace.CurrentCamera

	for i = #FloatingNumbers, 1, -1 do
		local floatNum = FloatingNumbers[i]
		local elapsed = now - floatNum.StartTime

		-- Check if duration expired
		if elapsed >= DAMAGE_NUMBER_DURATION then
			floatNum.TextLabel.Parent:Destroy()
			table.remove(FloatingNumbers, i)
			continue
		end

		-- Update position (drift upward and fade out)
		local newWorldPos = floatNum.StartPosition + Vector3.new(0, DAMAGE_NUMBER_SPEED * elapsed, 0)
		local screenPos = camera:WorldToScreenPoint(newWorldPos)

		floatNum.TextLabel.Position = UDim2.new(0, screenPos.X - 50, 0, screenPos.Y - 25)

		-- Fade out
		local fade = 1 - (elapsed / DAMAGE_NUMBER_DURATION)
		floatNum.TextLabel.TextTransparency = 1 - fade
	end
end

--[[
	Show block feedback (brief visual indication)
	@param player The player who blocked
]]
function CombatFeedbackUI.ShowBlockFeedback(player: Player?)
	if not player or not player.Character then
		return
	end

	local rootPart = Utils.GetRootPart(player)
	if not rootPart then
		return
	end

	-- Create brief visual feedback
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1, 1, 1)
	part.CanCollide = false
	part.CFrame = rootPart.CFrame + rootPart.CFrame.LookVector * 5
	part.Color = UITheme.Palette.BlockShield
	part.Transparency = 0.5
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = workspace

	-- Fade out
	task.spawn(function()
		for i = 1, 10 do
			part.Transparency = 0.5 + (i / 10) * 0.5
			task.wait(FADE_STEP_DURATION)
		end
		part:Destroy()
	end)
end

--[[
	Show parry feedback (visual effect on successful parry)
	@param player The player who parried
	@param attacker The attacking player
]]
function CombatFeedbackUI.ShowParryFeedback(player: Player?, attacker: Player?)
	if not player or not player.Character then
		return
	end

	local rootPart = Utils.GetRootPart(player)
	if not rootPart then
		return
	end

	-- Create visual spark effect
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.CanCollide = false
	part.CFrame = rootPart.CFrame + rootPart.CFrame.LookVector * 3
	part.Color = UITheme.Palette.PostureOrange
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = workspace

	-- Rise and fade
	task.spawn(function()
		for i = 1, 15 do
			part.CFrame = part.CFrame + Vector3.new(0, 0.3, 0)
			part.Transparency = i / 15
			task.wait(0.03)
		end
		part:Destroy()
	end)
end

--[[
	Show clash feedback (visual cue when two attacks collide)
	@param attacker The player who initiated one of the attacks
	@param defender The other player involved in the clash
	@param window Follow-up window length (seconds)
]]
function CombatFeedbackUI.ShowClashFeedback(attacker: Player?, defender: Player?, window: number?)
	-- simple text indicator above defender for now
	if defender and defender.Character then
		local rootPart = Utils.GetRootPart(defender)
		if rootPart then
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.new(0, 100, 0, 40)
			billboard.StudsOffset = Vector3.new(0, 3, 0)
			billboard.AlwaysOnTop = true
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.Text = "CLASH!"
			label.TextColor3 = UITheme.Palette.HealthRed
			label.Font = UITheme.Typography.FontBold
			label.TextScaled = true
			label.Parent = billboard
			billboard.Parent = rootPart
			-- fade out
			task.delay(0.5, function()
				billboard:Destroy()
			end)
		end
	end
end

--[[
	Show miss indicator
	@param attacker The attacking player
	@param target The target player
]]
function CombatFeedbackUI.ShowMiss(attacker: Player?, target: Player?)
	if not target or not target.Character then
		return
	end

	local rootPart = Utils.GetRootPart(target)
	if not rootPart then
		return
	end

	-- Create "MISS" text above target
	local screenGui = Instance.new("ScreenGui")
	screenGui.ResetOnSpawn = false
	screenGui.Name = "MissIndicator"
	screenGui.DisplayOrder = HUDLayout.Layers.HUD
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "MissLabel"
	textLabel.Size = UDim2.new(0, 150, 0, 50)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.Font = UITheme.Typography.FontBold
	textLabel.TextColor3 = UITheme.Palette.MissText
	textLabel.Text = "MISS"

	local camera = workspace.CurrentCamera
	local screenPosition = camera:WorldToScreenPoint(rootPart.Position + Vector3.new(0, 3, 0))
	textLabel.Position = UDim2.new(0, screenPosition.X - 75, 0, screenPosition.Y - 25)

	textLabel.Parent = screenGui

	-- Fade out quickly
	task.spawn(function()
		for i = 1, 10 do
			textLabel.TextTransparency = i / 10
			task.wait(FADE_STEP_DURATION)
		end
		screenGui:Destroy()
	end)
end

--[[
	Show a full-screen YOU DIED overlay when the local player enters Dead state.
	Fades in over 1 s, waits 2.5 s, then fades out and destroys itself.
	Respawn detection: the overlay self-removes so the next spawn is clean.

	TIMING IS CRITICAL - must preserve exactly:
	- Fade IN: 1s (20 steps × 0.05s)
	- HOLD: 2.5s at full opacity
	- Fade OUT: 0.5s (10 steps × 0.05s)
]]
function CombatFeedbackUI._ShowDeathScreen()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Only one death screen at a time
	local existing = playerGui:FindFirstChild("DeathScreen")
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DeathScreen"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = HUDLayout.Layers.Modal
	gui.Parent = playerGui

	-- Dark overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = UITheme.Palette.HealthRed
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Parent = gui

	-- YOU DIED label
	local label = Instance.new("TextLabel")
	label.Name = "YouDied"
	label.Size = UDim2.new(0, 400, 0, 100)
	label.Position = UDim2.new(0.5, -200, 0.4, -50)
	label.BackgroundTransparency = 1
	label.TextColor3 = UITheme.Palette.HealthRed
	label.Font = UITheme.Typography.FontBold
	label.TextSize = 72
	label.Text = "YOU DIED"
	label.TextTransparency = 1
	label.Parent = overlay

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Size = UDim2.new(0, 400, 0, 40)
	sub.Position = UDim2.new(0.5, -200, 0.4, 60)
	sub.BackgroundTransparency = 1
	sub.TextColor3 = UITheme.Palette.TextSecondary
	sub.Font = UITheme.Typography.FontRegular
	sub.TextSize = 22
	sub.Text = "Respawning..."
	sub.TextTransparency = 1
	sub.Parent = overlay

	task.spawn(function()
		-- Fade in (1 s) - 20 steps × 0.05s
		for i = 1, 20 do
			overlay.BackgroundTransparency = 1 - (i / 20) * 0.70
			label.TextTransparency = 1 - (i / 20)
			sub.TextTransparency = 1 - (i / 20)
			task.wait(FADE_STEP_DURATION)
		end

		task.wait(2.5)

		-- Fade out (0.5 s) - 10 steps × 0.05s
		for i = 1, 10 do
			overlay.BackgroundTransparency = 0.30 + (i / 10) * 0.70
			label.TextTransparency = i / 10
			sub.TextTransparency = i / 10
			task.wait(FADE_STEP_DURATION)
		end
		gui:Destroy()
	end)
end

--[[
	Play a brief red vignette flash when the local player becomes Suppressed
	(posture fully broken). Pulses the screen edge red then fades.
]]
function CombatFeedbackUI._PlaySuppressedVignette()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild("SuppressedVignette")
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SuppressedVignette"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = HUDLayout.Layers.Modal
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = UITheme.Palette.HealthRed
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	Instance.new("UIGradient", frame).Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.35, 1),
		NumberSequenceKeypoint.new(1, 1),
	})

	task.spawn(function()
		-- Two quick pulses - 2 × (8 + 8 steps × 0.04s) = ~0.64s total
		for _ = 1, 2 do
			for i = 1, 8 do
				frame.BackgroundTransparency = 1 - (i / 8) * 0.6
				task.wait(0.04)
			end
			for i = 1, 8 do
				frame.BackgroundTransparency = 0.4 + (i / 8) * 0.6
				task.wait(0.04)
			end
		end
		gui:Destroy()
	end)
end

return CombatFeedbackUI
