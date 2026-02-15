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
	
	-- Listen for hit events from network (NetworkProvider ready after Start)
	local hitEvent = NetworkProvider:GetRemoteEvent("HitConfirmed")
	if hitEvent then
		hitEvent.OnClientEvent:Connect(function(attacker, target, damage, isCritical, isDummy)
			CombatFeedbackUI.ShowDamageNumber(target, damage, isCritical or false, isDummy or false)
		end)
	end
	
	-- Update loop for floating numbers
	game:GetService("RunService").RenderStepped:Connect(function()
		CombatFeedbackUI._UpdateFloatingNumbers()
	end)
	
	print("[CombatFeedbackUI] Started successfully")
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
		local dummyModel = Workspace:FindFirstChild(`Dummy_{dummyId}`)
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
