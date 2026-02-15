--!strict
--[[
	DebugInput.lua
	
	Handles debug keyboard shortcuts for development.
	
	Keybinds:
	- L: Toggle hitbox visualization
	- K: Toggle state labels
	- M: Cycle slow-motion speeds
	- Ctrl+Shift+D: List all debug settings
	
	Dependencies: DebugSettings, UserInputService
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DebugSettings = require(ReplicatedStorage.Shared.modules.DebugSettings)
local HitboxService = require(ReplicatedStorage.Shared.modules.HitboxService)

local DebugInput = {}

-- Track if we're in debug mode
local DebugMode = true -- Change to false to disable in production

--[[
	Initialize debug input handler
]]
function DebugInput:Init()
	if not DebugMode then
		return
	end
	
	print("[DebugInput] Debug input handler initialized")
	print("[DebugInput] Press L to toggle hitbox visualization")
	print("[DebugInput] Press K to toggle state labels")
	print("[DebugInput] Press M to cycle slow-motion speed")
	print("[DebugInput] Press H to spawn test hitbox")
	print("[DebugInput] Press J to spawn combat dummy")
	print("[DebugInput] Press Ctrl+Shift+D to list all settings")
	
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		
		-- L: Toggle hitbox visualization
		if input.KeyCode == Enum.KeyCode.L then
			DebugSettings.Toggle("ShowHitboxes")
		end
		
		-- K: Toggle state labels
		if input.KeyCode == Enum.KeyCode.K then
			DebugSettings.Toggle("ShowStateLabels")
		end
		
		-- M: Cycle slow-motion speed
		if input.KeyCode == Enum.KeyCode.M then
			local current = DebugSettings.Get("SlowMotionSpeed") :: number
			local nextSpeed = 0.5
			
			if current == 0.5 then
				nextSpeed = 0.25
			elseif current == 0.25 then
				nextSpeed = 0.1
			elseif current == 0.1 then
				nextSpeed = 1.0 -- Back to normal
			end
			
			DebugSettings.Set("SlowMotionSpeed", nextSpeed)
			DebugSettings.Toggle("SlowMotion")
		end
		
		-- H: Spawn test hitbox
		if input.KeyCode == Enum.KeyCode.H then
			DebugInput._SpawnTestHitbox()
		end
		
		-- J: Spawn combat dummy
		if input.KeyCode == Enum.KeyCode.J then
			DebugInput._SpawnCombatDummy()
		end
		
		-- Ctrl+Shift+D: List all settings
		if input.KeyCode == Enum.KeyCode.D and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			DebugSettings.ListSettings()
		end
	end)
end

--[[
	Spawn a test hitbox for debugging
]]
function DebugInput._SpawnTestHitbox()
	local player = Players.LocalPlayer
	if not player or not player.Character then
		print("[DebugInput] Cannot spawn test hitbox - no character")
		return
	end
	
	local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		print("[DebugInput] Cannot spawn test hitbox - no root part")
		return
	end
	
	print("[DebugInput] Spawning test hitbox...")
	DebugSettings.Set("ShowHitboxes", true)
	
	local testHitbox = HitboxService.CreateHitbox({
		Shape = "Sphere",
		Owner = player,
		Position = rootPart.Position + rootPart.CFrame.LookVector * 10,
		Size = Vector3.new(6, 6, 6),
		Damage = 10,
		LifeTime = 5, -- Show for 5 seconds
		OnHit = function(target, hitData)
			print(`[DebugInput] Test hitbox hit {target.Name}`)
		end,
	})
	
	print(`[DebugInput] Test hitbox spawned: {testHitbox.Id}`)
end

--[[
	Spawn a combat dummy for testing
]]
function DebugInput._SpawnCombatDummy()
	local player = Players.LocalPlayer
	if not player or not player.Character then
		print("[DebugInput] Cannot spawn combat dummy - no character")
		return
	end
	
	local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		print("[DebugInput] Cannot spawn combat dummy - no root part")
		return
	end
	
	local spawnPosition = rootPart.Position + rootPart.CFrame.LookVector * 10
	
	print("[DebugInput] Spawning combat dummy...")
	
	-- Fire event to server
	local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
	local spawnEvent = NetworkProvider:GetRemoteEvent("SpawnDummy")
	if spawnEvent then
		spawnEvent:FireServer(spawnPosition)
		print("[DebugInput] Spawn request sent to server")
	else
		print("[DebugInput] SpawnDummy event not found")
	end
end

return DebugInput
