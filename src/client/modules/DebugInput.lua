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
local RunService = game:GetService("RunService")

local DebugSettings = require(ReplicatedStorage.Shared.modules.DebugSettings)
local HitboxService = require(ReplicatedStorage.Shared.modules.HitboxService)

local DebugInput = {}
DebugInput._lastRingIndex = 0  -- For cycling rings in debug

-- Debug mode is ONLY active inside Roblox Studio — never in public servers
local DebugMode = RunService:IsStudio()

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
	print("[DebugInput] Press Ctrl+Shift+J to admin-spawn a dummy (dev only)")
	print("[DebugInput] Press / to open local command prompt (commands are NOT broadcast to chat)")
	print("[DebugInput] Press Ctrl+Shift+D to list all settings")
	print("[DebugInput] Press G to grant 200 debug Resonance (earns 1 stat point for panel testing)")
	print("[DebugInput] Press Y to cycle debug aspect (assign & max branches)")
	print("[DebugInput] Press Ctrl+K to kill yourself (test shard loss on death)")
	print("[DebugInput] Press Ctrl+R to reset all progression")
	print("[DebugInput] Press Ctrl+T to cycle rings (0-5)")
	print("[DebugInput] Press Ctrl+Shift+G to grant 10 stat points directly")

	-- Listen for admin/debug responses from server (DebugInfo)
	local networkFolder = ReplicatedStorage:FindFirstChild("NetworkEvents")
	if networkFolder then
		local debugEvent = networkFolder:FindFirstChild("DebugInfo")
		if debugEvent and debugEvent:IsA("RemoteEvent") then
			debugEvent.OnClientEvent:Connect(function(packet)
				if packet and packet.Category == "AdminCommand" then
					print(`[DebugInput] AdminCommand response: {tostring(packet.Data.Result or packet.Data.Error)}`)
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
			local newState = DebugSettings.Toggle("ShowHitboxes")
			DebugInput._SendAdminCommand({ Command = "toggle_hitboxes", Args = { tostring(newState) } })
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

		-- G: Grant 200 debug Resonance (1 stat point) to test stat allocation panel
		if input.KeyCode == Enum.KeyCode.G then
			DebugInput._SendAdminCommand({ Command = "grant_resonance", Args = { "200" } })
		end
		-- Y: cycle through aspects and assign debug aspect
		if input.KeyCode == Enum.KeyCode.Y then
			DebugInput._CycleAspect()
		end

		-- Ctrl+K: Kill self (test shard loss on death)
		if input.KeyCode == Enum.KeyCode.K and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			DebugInput._SendAdminCommand({ Command = "kill_player", Args = {} })
		end

		-- Ctrl+R: Reset all progression
		if input.KeyCode == Enum.KeyCode.R and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			DebugInput._SendAdminCommand({ Command = "reset_progression", Args = {} })
		end

		-- Ctrl+T: Cycle rings (0-5)
		if input.KeyCode == Enum.KeyCode.T and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			DebugInput._CycleRing()
		end

		-- Ctrl+Shift+G: Grant 10 stat points directly
		if input.KeyCode == Enum.KeyCode.G and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			DebugInput._SendAdminCommand({ Command = "grant_stat_points", Args = { "10" } })
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
	print(`[DebugInput] AdminCommand sent: {packet.Command} ({table.concat(packet.Args or {}, " ")})`)
end

--[[
	Cycle through the list of aspect IDs and send an admin command to set the
	current aspect in debug mode. This gives full branches so the client has all
	moves available immediately.
]]
function DebugInput._CycleAspect()
	local aspectIds = {"Ash","Tide","Ember","Gale","Void","Marrow"}
	DebugInput._lastAspectIndex = (DebugInput._lastAspectIndex or 0) + 1
	if DebugInput._lastAspectIndex > #aspectIds then
		DebugInput._lastAspectIndex = 1
	end
	local id = aspectIds[DebugInput._lastAspectIndex]
	DebugInput._SendAdminCommand({ Command = "set_aspect", Args = { id } })
	print("[DebugInput] cycling debug aspect -> "..id)
end

--[[
	Cycle through rings (0-5) to test soft caps and ring transitions.
	Ring 0 = Hearthspire (no cap)
	Ring 1 = The Verdant Shelf (cap: 2000)
	Ring 2 = The Ashfeld (cap: 10000)
	Ring 3 = The Vael Depths (cap: 30000)
	Ring 4 = The Gloam (cap: 100000)
	Ring 5 = The Null (no cap)
]]
function DebugInput._CycleRing()
	local rings = {0, 1, 2, 3, 4, 5}
	DebugInput._lastRingIndex = (DebugInput._lastRingIndex or 0) + 1
	if DebugInput._lastRingIndex > #rings then
		DebugInput._lastRingIndex = 1
	end
	local ring = rings[DebugInput._lastRingIndex]
	DebugInput._SendAdminCommand({ Command = "set_ring", Args = { tostring(ring) } })
	print("[DebugInput] cycling debug ring -> "..ring)
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
		elseif sub == "grant_resonance" then
			-- /admin grant_resonance [amount]
			local amount = tokens[3] or "200"
			DebugInput._SendAdminCommand({ Command = "grant_resonance", Args = { amount } })
			return
		elseif sub == "kill_player" then
			-- /admin kill_player
			DebugInput._SendAdminCommand({ Command = "kill_player", Args = {} })
			return
		elseif sub == "set_ring" then
			-- /admin set_ring [0-5]
			local ring = tokens[3] or "1"
			DebugInput._SendAdminCommand({ Command = "set_ring", Args = { ring } })
			return
		elseif sub == "reset_progression" then
			-- /admin reset_progression
			DebugInput._SendAdminCommand({ Command = "reset_progression", Args = {} })
			return
		elseif sub == "grant_stat_points" then
			-- /admin grant_stat_points [amount]
			local amount = tokens[3] or "1"
			DebugInput._SendAdminCommand({ Command = "grant_stat_points", Args = { amount } })
			return
		elseif sub == "grant_training_tool" then
			-- /admin grant_training_tool [stat] [rarity]
			-- stat: Strength, Fortitude, Agility, Intelligence, Willpower, Charisma
			-- rarity: Common, Uncommon, Rare
			local stat = tokens[3] or "Strength"
			local rarity = tokens[4] or "Common"
			DebugInput._SendAdminCommand({ Command = "grant_training_tool", Args = { stat, rarity } })
			return
		else
			-- fallback: forward any other admin command verbatim
			local args = {}
			for i = 3, #tokens do
				table.insert(args, tokens[i])
			end
			DebugInput._SendAdminCommand({ Command = sub, Args = args })
			return
		end
	end

	print("[DebugInput] Unknown command: " .. text)
end

return DebugInput
