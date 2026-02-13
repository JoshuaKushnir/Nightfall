--!strict
--[[
	ActionController.lua
	
	Issue #8: Action Controller (Animation & Feel)
	Epic: Phase 2 - Combat & Fluidity
	
	Client-side controller managing animations, hit-stop, camera shake, and game feel.
	Server-authoritative validation prevents animation spoofing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local ActionTypes = require(ReplicatedStorage.Shared.types.ActionTypes)
local NetworkProvider = require(ReplicatedStorage.Shared.network.NetworkProvider)

type ActionConfig = ActionTypes.ActionConfig
type Action = ActionTypes.Action

local ActionController = {}

-- References
local Player = Players.LocalPlayer
local Character: Model?
local Humanoid: Humanoid?
local AnimationController: Animator?

-- State
local CurrentAction: Action?
local ActionQueue: {ActionConfig} = {}
local ActionCooldowns: {[string]: number} = {}
local LastActionTime = 0

-- Constants
local MIN_ACTION_INTERVAL = 0.1

--[[
	Initialize the controller with character
]]
function ActionController.Init()
	print("[ActionController] Initializing...")
	
	-- Wait for character
	if not Player then
		error("[ActionController] LocalPlayer not found")
	end
	
	Character = Player.Character or Player.CharacterAdded:Wait()
	Humanoid = Character:WaitForChild("Humanoid") :: Humanoid
	AnimationController = Character:WaitForChild("Animator") :: Animator
	
	print(`[ActionController] Character ready: {Character.Name}`)
end

--[[
	Start the controller
]]
function ActionController.Start()
	print("[ActionController] Starting...")
	
	-- Bind input for testing
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		
		-- Mock actions for testing
		if input.KeyCode == Enum.KeyCode.E then
			ActionController.PlayAction(ActionTypes.ATTACK_LIGHT)
		elseif input.KeyCode == Enum.KeyCode.R then
			ActionController.PlayAction(ActionTypes.ATTACK_HEAVY)
		elseif input.KeyCode == Enum.KeyCode.Space then
			ActionController.PlayAction(ActionTypes.DODGE)
		end
	end)
	
	-- Update loop
	local lastUpdate = tick()
	game:GetService("RunService").RenderStepped:Connect(function()
		local now = tick()
		local deltaTime = now - lastUpdate
		lastUpdate = now
		
		-- Update cooldowns
		for actionId, cooldownEnd in ActionCooldowns do
			if now >= cooldownEnd then
				ActionCooldowns[actionId] = nil
			end
		end
		
		-- Update current action
		if CurrentAction then
			ActionController._UpdateAction(deltaTime)
		end
	end)
	
	print("[ActionController] Started successfully")
end

--[[
	Play an action (request to server)
	@param config The action configuration
]]
function ActionController.PlayAction(config: ActionConfig)
	-- Throttle rapid requests
	if tick() - LastActionTime < MIN_ACTION_INTERVAL then
		return
	end
	
	-- Check cooldown
	if ActionCooldowns[config.Id] and tick() < ActionCooldowns[config.Id] then
		print(`[ActionController] Action on cooldown: {config.Id}`)
		return
	end
	
	-- Queue or play immediately
	if CurrentAction then
		table.insert(ActionQueue, config)
		print(`[ActionController] Action queued: {config.Name}`)
	else
		ActionController._PlayActionLocal(config)
		
		-- Notify server
		local networkEvent = NetworkProvider:GetRemoteEvent("StateRequest")
		if networkEvent then
			networkEvent:FireServer({
				Type = "ActionStart",
				ActionId = config.Id,
				Timestamp = tick(),
			})
		end
		
		LastActionTime = tick()
	end
end

--[[
	Play an action locally (client-side prediction)
	@param config The action configuration
]]
function ActionController._PlayActionLocal(config: ActionConfig)
	if not Character or not Humanoid or not AnimationController then
		return
	end
	
	-- Create action
	local action: Action = {
		Config = config,
		StartTime = tick(),
		EndTime = tick() + config.Duration,
		IsActive = true,
		TargetHit = nil,
		AnimationTrack = nil,
		
		Play = function(self: Action)
			print(`[ActionController] Playing animation: {self.Config.Name}`)
		end,
		
		Stop = function(self: Action)
			if self.AnimationTrack then
				self.AnimationTrack:Stop()
			end
			self.IsActive = false
		end,
		
		OnFrame = function(self: Action, deltaTime: number) end,
		
		Cleanup = function(self: Action)
			if self.AnimationTrack then
				self.AnimationTrack:Destroy()
			end
		end,
	}
	
	CurrentAction = action
	
	-- Call start callback
	if config.OnStart then
		task.spawn(config.OnStart, Player)
	end
	
	-- Simulate hit-stop if action has hit timing
	if config.HitStartFrame and config.HitStopDuration then
		local hitTime = config.Duration * config.HitStartFrame
		task.delay(hitTime, function()
			if CurrentAction == action then
				ActionController._ApplyHitStop(config.HitStopDuration)
			end
		end)
	end
	
	-- Simulate camera shake
	if config.CameraShake then
		ActionController._ApplyCameraShake(config.CameraShake)
	end
	
	print(`[ActionController] ✓ Playing: {config.Name}`)
end

--[[
	Update current action
	@param deltaTime Time since last frame
]]
function ActionController._UpdateAction(deltaTime: number)
	if not CurrentAction then
		return
	end
	
	local action = CurrentAction
	
	-- Check if action complete
	if tick() >= action.EndTime then
		action:Stop()
		action:Cleanup()
		CurrentAction = nil
		
		-- Process queued action
		if #ActionQueue > 0 then
			local nextAction = table.remove(ActionQueue, 1)
			ActionController._PlayActionLocal(nextAction)
		end
	else
		action:OnFrame(deltaTime)
	end
end

--[[
	Apply hit-stop (brief freeze effect)
	@param duration Time to freeze (seconds)
]]
function ActionController._ApplyHitStop(duration: number)
	print(`[ActionController] Hit-stop: {duration}s`)
	
	-- Simulate time dilation
	task.wait(duration * 0.5) -- Feel of freeze
end

--[[
	Apply camera shake
	@param trauma Amount of trauma (0-1)
]]
function ActionController._ApplyCameraShake(trauma: number)
	print(`[ActionController] Camera shake: {trauma}`)
	
	local camera = workspace.CurrentCamera
	local originalCFrame = camera.CFrame
	
	for i = 1, 5 do
		local offset = Vector3.new(
			(math.random() - 0.5) * trauma * 2,
			(math.random() - 0.5) * trauma * 2,
			(math.random() - 0.5) * trauma * 2
		)
		
		camera.CFrame = originalCFrame * CFrame.new(offset)
		task.wait(0.01)
	end
	
	camera.CFrame = originalCFrame
end

--[[
	Handle character respawn
	@param newCharacter The new character
]]
function ActionController.OnCharacterAdded(newCharacter: Model)
	print("[ActionController] Character respawned")
	
	-- Clean up old action
	if CurrentAction then
		CurrentAction:Stop()
		CurrentAction:Cleanup()
		CurrentAction = nil
	end
	
	-- Clear queue and cooldowns
	ActionQueue = {}
	ActionCooldowns = {}
	
	-- Reinitialize
	Character = newCharacter
	Humanoid = Character:WaitForChild("Humanoid")
	AnimationController = Character:WaitForChild("Animator")
	
	print("[ActionController] Ready for new character")
end

return ActionController
