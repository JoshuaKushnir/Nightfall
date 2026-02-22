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
local Logger = require(ReplicatedStorage.Shared.modules.Logger)

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
	
	Logger.Log("DebugInput", "Debug input handler initialized")
	Logger.Log("DebugInput", "Press L to toggle hitbox visualization")
	Logger.Log("DebugInput", "Press K to toggle state labels")
	Logger.Log("DebugInput", "Press M to cycle slow-motion speed")
	Logger.Log("DebugInput", "Press H to spawn test hitbox")
	Logger.Log("DebugInput", "Press J to spawn combat dummy")
	Logger.Log("DebugInput", "Press Ctrl+Shift+J to admin-spawn a dummy (dev only)")
	Logger.Log("DebugInput", "Press / to open local command prompt (commands are NOT broadcast to chat)")
	Logger.Log("DebugInput", "Press Ctrl+Shift+D to list all settings")

	-- Listen for admin/debug responses from server (DebugInfo)
	local networkFolder = ReplicatedStorage:FindFirstChild("NetworkEvents")
	if networkFolder then
		local debugEvent = networkFolder:FindFirstChild("DebugInfo")
		if debugEvent and debugEvent:IsA("RemoteEvent") then
			debugEvent.OnClientEvent:Connect(function(packet)
				if packet and packet.Category == "AdminCommand" then
					Logger.Log("DebugInput", "AdminCommand response: %s", tostring(packet.Data.Result or packet.Data.Error))
				end
			end)
		end
	end
	
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

		-- J: Spawn combat dummy (plain)
		if input.KeyCode == Enum.KeyCode.J and not (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)) then
			DebugInput._SpawnCombatDummy()
		end

		-- Ctrl+Shift+J: Admin spawn dummy (sends AdminCommand - does NOT broadcast chat)
		if input.KeyCode == Enum.KeyCode.J and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			DebugInput._SendAdminSpawnDummy()
		end

		-- / (Slash): open local command prompt (commands typed here are NOT sent to public chat)
		if input.KeyCode == Enum.KeyCode.Slash then
			DebugInput._OpenCommandPrompt()
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
	
	Logger.Log("DebugInput", "Spawning test hitbox...")
	DebugSettings.Set("ShowHitboxes", true)
	
	local testHitbox = HitboxService.CreateHitbox({
		Shape = "Sphere",
		Owner = player,
		Position = rootPart.Position + rootPart.CFrame.LookVector * 10,
		Size = Vector3.new(6, 6, 6),
		Damage = 10,
		LifeTime = 5, -- Show for 5 seconds
		OnHit = function(target, hitData)
			Logger.Log("DebugInput", "Test hitbox hit {target.Name}")
		end,
	})
	
	Logger.Log("DebugInput", "Test hitbox spawned: {testHitbox.Id}")
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

--[[
	Send an admin command packet to the server (uses AdminCommand network event)
	This is a local-only command path and does NOT broadcast input to public chat.
]]
function DebugInput._SendAdminCommand(packet: { Command: string, Args: {string}? })
	local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)
	local adminEvent = NetworkProvider:GetRemoteEvent("AdminCommand")
	if not adminEvent then
		print("[DebugInput] AdminCommand event not available")
		return
	end

	-- Fire server-only admin command (server will validate permissions)
	adminEvent:FireServer(packet)
	Logger.Log("DebugInput", "AdminCommand sent: %s (%s)", packet.Command, table.concat(packet.Args or {}, " "))
end

--[[
	Spawn a dummy via AdminCommand (sends request to server; local-only input)
]]
function DebugInput._SendAdminSpawnDummy()
	local player = Players.LocalPlayer
	if not player or not player.Character then
		print("[DebugInput] Cannot spawn dummy - no character")
		return
	end

	-- Use "here" so server positions it safely in front of player
	DebugInput._SendAdminCommand({ Command = "spawn_dummy", Args = { "here" } })
end

--[[
	Open a small, local command prompt (does NOT send typed text to public chat)
]]
function DebugInput._OpenCommandPrompt()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	-- Simple transient UI
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DebugCommandPrompt"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local textBox = Instance.new("TextBox")
	textBox.Size = UDim2.new(0, 400, 0, 30)
	textBox.Position = UDim2.new(0.5, -200, 0.05, 0)
	textBox.BackgroundTransparency = 0.25
	textBox.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	textBox.PlaceholderText = "/admin spawn_dummy [here|x y z]"
	textBox.ClearTextOnFocus = true
	textBox.Text = ""
	textBox.Parent = screenGui

	textBox:CaptureFocus()

	textBox.FocusLost:Connect(function(enterPressed)
		local text = textBox.Text or ""
		screenGui:Destroy()
		if enterPressed and text ~= "" then
			DebugInput._HandleCommand(text)
		end
	end)
end

--[[
	Parse and handle local commands (only a small subset supported here)
]]
function DebugInput._HandleCommand(text: string)
	local tokens = {}
	for token in string.gmatch(text, "%S+") do
		table.insert(tokens, token)
	end

	if #tokens == 0 then
		return
	end

	local cmdRoot = string.lower(tokens[1])
	if cmdRoot == "/log" or cmdRoot == "log" then
		local module = tokens[2]
		if module then
			Logger.Log("DebugInput", "toggling logging for module {module}")
			DebugSettings.ToggleLogging(module)
		else
			Logger.Log("DebugInput", "usage: /log <moduleName>")
		end
		return
	end
	if cmdRoot == "/admin" or cmdRoot == "admin" then
		local sub = tokens[2] and string.lower(tokens[2]) or ""
		if sub == "spawn_dummy" then
			-- Support: /admin spawn_dummy
			--          /admin spawn_dummy here
			--          /admin spawn_dummy x y z
			local args = {}
			for i = 3, #tokens do
				table.insert(args, tokens[i])
			end

			if #args == 0 then
				DebugInput._SendAdminSpawnDummy()
				return
			elseif #args == 1 and string.lower(args[1]) == "here" then
				DebugInput._SendAdminSpawnDummy()
				return
			elseif #args >= 3 then
				-- Validate numeric args
				local x = tonumber(args[1])
				local y = tonumber(args[2])
				local z = tonumber(args[3])
				if x and y and z then
					DebugInput._SendAdminCommand({ Command = "spawn_dummy", Args = { tostring(x), tostring(y), tostring(z) } })
					return
				end
			end

			print("[DebugInput] Invalid args for /admin spawn_dummy")
			return
		end
	end

	Logger.Log("DebugInput", "Unknown command: {text}")
end

return DebugInput
