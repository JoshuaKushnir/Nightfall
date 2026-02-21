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

local CombatFeedbackUI = {}

-- Constants
local DAMAGE_NUMBER_DURATION = 1.5 -- Seconds to show damage number
local DAMAGE_NUMBER_SPEED = 30 -- Studs per second upward
local CRITICAL_MULTIPLIER = 2.0
local CRITICAL_COLOR = Color3.fromRGB(255, 215, 0) -- Gold
local NORMAL_COLOR = Color3.fromRGB(255, 255, 255) -- White
local HEAL_COLOR = Color3.fromRGB(0, 255, 0) -- Green

-- Posture bar colours
local POSTURE_COLOR_NORMAL   = Color3.fromRGB(100, 200, 255) -- Blue
local POSTURE_COLOR_CRITICAL = Color3.fromRGB(255, 120,  50) -- Orange when low
local POSTURE_LOW_THRESHOLD  = 0.25  -- switch colour below 25% posture

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
	local postureBar = CombatFeedbackUI._BuildPostureBar()

	local postureEvent = NetworkProvider:GetRemoteEvent("PostureChanged")
	if postureEvent then
		postureEvent.OnClientEvent:Connect(function(playerId: number, current: number, max: number)
			-- Only update bar for the local player
			if playerId ~= Players.LocalPlayer.UserId then return end
			CombatFeedbackUI._UpdatePostureBar(postureBar, current, max)
		end)
	end

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
	
	-- Update loop for floating numbers
	game:GetService("RunService").RenderStepped:Connect(function()
		CombatFeedbackUI._UpdateFloatingNumbers()
	end)

	print("[CombatFeedbackUI] Started successfully")
end

-- ─── Posture bar helpers ─────────────────────────────────────────────────────

--[[
	Create a simple posture bar ScreenGui attached to the local PlayerGui.
	Returns a table { bar: Frame, fill: Frame } for later updates.
]]
function CombatFeedbackUI._BuildPostureBar(): {bar: Frame, fill: Frame}
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "PostureHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- Outer container (bottom-centre of screen, just below the HP bar)
	local bar = Instance.new("Frame")
	bar.Name = "PostureBar"
	bar.Size = UDim2.new(0, 300, 0, 18)
	bar.Position = UDim2.new(0.5, -150, 1, -85)  -- above the bottom edge
	bar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	bar.BorderSizePixel = 0
	bar.Parent = gui

	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 4)

	-- Fill bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.Position = UDim2.new(0, 0, 0, 0)
	fill.BackgroundColor3 = POSTURE_COLOR_NORMAL
	fill.BorderSizePixel = 0
	fill.Parent = bar

	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

	-- Label
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0, 14)
	label.Position = UDim2.new(0, 0, -1.2, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(200, 200, 200)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 11
	label.Text = "POSTURE"
	label.Parent = bar

	-- Immediately render at full posture so the bar is visible on spawn
	-- before the first PostureChanged event arrives from the server.
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = POSTURE_COLOR_NORMAL

	print("[CombatFeedbackUI] Posture bar created")
	return { bar = bar, fill = fill }
end

--[[
	Update the fill width and colour of the posture bar.
]]
function CombatFeedbackUI._UpdatePostureBar(postureBar: {bar: Frame, fill: Frame}, current: number, max: number)
	if not postureBar then return end
	local ratio = if max > 0 then math.clamp(current / max, 0, 1) else 0
	postureBar.fill.Size = UDim2.new(ratio, 0, 1, 0)
	postureBar.fill.BackgroundColor3 = ratio <= POSTURE_LOW_THRESHOLD
		and POSTURE_COLOR_CRITICAL
		or POSTURE_COLOR_NORMAL
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

	-- Flash orange × 3 then revert
	task.spawn(function()
		for _ = 1, 3 do
			for _, part in parts do
				part.Color = Color3.fromRGB(255, 140, 40)
			end
			task.wait(0.08)
			for _, part in parts do
				-- Revert to default (let Roblox Humanoid handle actual colour)
				part.Color = Color3.fromRGB(163, 162, 165)
			end
			task.wait(0.08)
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
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 160, 0, 50)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 80, 0)
	label.Text = ("BREAK! -%d"):format(damage)

	local camera = workspace.CurrentCamera
	local screenPos = camera:WorldToScreenPoint(rootPart.Position + Vector3.new(0, 4, 0))
	label.Position = UDim2.new(0, screenPos.X - 80, 0, screenPos.Y - 25)
	label.Parent = screenGui

	task.spawn(function()
		for i = 1, 15 do
			label.TextTransparency = i / 15
			task.wait(0.04)
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
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "DamageLabel"
	textLabel.Size = UDim2.new(0, 100, 0, 50)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.GothamBold
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
	part.Color = Color3.fromRGB(100, 100, 255) -- Blue shield
	part.Transparency = 0.5
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = workspace
	
	-- Fade out
	task.spawn(function()
		for i = 1, 10 do
			part.Transparency = 0.5 + (i / 10) * 0.5
			task.wait(0.05)
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
	part.Color = Color3.fromRGB(255, 165, 0) -- Orange spark
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
			label.TextColor3 = Color3.new(1, 0, 0)
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
	screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "MissLabel"
	textLabel.Size = UDim2.new(0, 150, 0, 50)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextColor3 = Color3.fromRGB(200, 200, 200) -- Gray
	textLabel.Text = "MISS"
	
	local camera = workspace.CurrentCamera
	local screenPosition = camera:WorldToScreenPoint(rootPart.Position + Vector3.new(0, 3, 0))
	textLabel.Position = UDim2.new(0, screenPosition.X - 75, 0, screenPosition.Y - 25)
	
	textLabel.Parent = screenGui
	
	-- Fade out quickly
	task.spawn(function()
		for i = 1, 10 do
			textLabel.TextTransparency = i / 10
			task.wait(0.05)
		end
		screenGui:Destroy()
	end)
end

return CombatFeedbackUI
