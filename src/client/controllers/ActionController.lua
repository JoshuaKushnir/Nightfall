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
local HitboxService = require(ReplicatedStorage.Shared.modules.HitboxService)
local Utils = require(ReplicatedStorage.Shared.modules.Utils)
local AnimationLoader = require(ReplicatedStorage.Shared.modules.AnimationLoader)

type ActionConfig = ActionTypes.ActionConfig
type Action = ActionTypes.Action

local ActionController = {}

-- References
local Player = Players.LocalPlayer
local Character: Model?
local Humanoid: Humanoid?
local AnimationController: Animator?
local MovementController: any = nil

-- State
local CurrentAction: Action?
local ActionQueue: {ActionConfig} = {}
local ActionCooldowns: {[string]: number} = {}
local LastActionTime = 0
local LastLungeAttackTime = 0 -- Track lunge cooldown

-- Combo State
local ComboCount = 0
local LastComboTime = 0
local COMBO_TIMEOUT = 1.5 -- Reset combo if no attack within 1.5 seconds
local COMBO_FINISH_COOLDOWN = 0.6 -- Cooldown after completing 5-hit combo

-- Constants
local MIN_ACTION_INTERVAL = 0.1
local MAX_QUEUE_SIZE = 1 -- Limit action queue to prevent spam stacking

--[[
	Initialize the controller with character and dependencies
]]
function ActionController:Init(dependencies: {[string]: any}?)
	print("[ActionController] Initializing...")

	-- Store dependency references
	if dependencies then
		MovementController = dependencies.MovementController
	end

	-- Wait for character
	if not Player then
		error("[ActionController] LocalPlayer not found")
	end

	Character = Player.Character or Player.CharacterAdded:Wait()
	local humanoid = Character:WaitForChild("Humanoid", 5)
	if not humanoid then
		error("[ActionController] Character missing Humanoid")
	end
	Humanoid = humanoid :: Humanoid

	-- Ensure Animator exists on the Humanoid (standard R15 setup)
	local animator = Humanoid:FindFirstChildOfClass("Animator") :: Animator?
	if not animator then
		warn("[ActionController] Animator not found on Humanoid - creating one")
		animator = Instance.new("Animator")
		animator.Parent = Humanoid
	end
	AnimationController = animator

	print(`[ActionController] Character ready: {Character.Name}`)
end

--[[
	Start the controller
]]
function ActionController:Start()
	print("[ActionController] Starting...")

	-- Bind input for testing
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		print(`[ActionController INPUT] Key: {input.KeyCode}, MouseButton: {input.UserInputType}, GameProcessed: {gameProcessed}`)

		if gameProcessed then
			print("[ActionController INPUT] Ignoring - GUI has focus")
			return
		end

		-- Mock actions for testing
		-- Left click to light attack
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			print("[ActionController INPUT] LIGHT ATTACK triggered")
			ActionController.PlayAction(ActionTypes.ATTACK_LIGHT)
		-- Right click to heavy attack
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			print("[ActionController INPUT] HEAVY ATTACK triggered")
			ActionController.PlayAction(ActionTypes.ATTACK_HEAVY)
		-- Q to dodge
		elseif input.KeyCode == Enum.KeyCode.Q then
			print("[ActionController INPUT] DODGE triggered")
			ActionController.PlayAction(ActionTypes.DODGE)
		-- F to parry
		elseif input.KeyCode == Enum.KeyCode.F then
			print("[ActionController INPUT] PARRY/BLOCK triggered")
			ActionController.PlayAction(ActionTypes.PARRY)
			task.delay(0.3, function()
				if UserInputService:IsKeyDown(Enum.KeyCode.F) then
					ActionController.PlayAction(ActionTypes.BLOCK)
				end
			end)
		end
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.F then
			-- Release block by ending the current action if it's a block
			if CurrentAction and CurrentAction.Config.Type == "Block" then
				CurrentAction:Stop()
				CurrentAction:Cleanup()
				CurrentAction = nil
			end
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

	print("[ActionController] Started")
end

--[[
	Helper function to get the correct roll type based on move direction
	@param moveDir Movement direction vector
	@return string, string Folder name and asset name (e.g. "Front Roll", "FrontRoll")
]]
local function GetRollForDirection(moveDir: Vector3): (string, string)
	if moveDir.Magnitude < 0.1 then
		-- No movement, default to front roll
		return "Front Roll", "FrontRoll"
	end

	-- Get character's forward direction
	if not Character or not Character.PrimaryPart then
		return "Front Roll", "FrontRoll"
	end

	local lookVector = Character.PrimaryPart.CFrame.LookVector
	local rightVector = Character.PrimaryPart.CFrame.RightVector

	-- Project movement onto character's forward/right axes
	local forwardDot = moveDir:Dot(lookVector)
	local rightDot = moveDir:Dot(rightVector)

	-- Determine dominant direction
	if math.abs(forwardDot) > math.abs(rightDot) then
		-- Forward or backward
		if forwardDot > 0 then
			return "FrontRoll", "FrontRoll"
		else
			return "BackRoll", "BackRoll"
		end
	else
		-- Left or right
		if rightDot > 0 then
			return "RightRoll", "RightRoll"
		else
			return "LeftRoll", "LeftRoll"
		end

	return "FrontRoll", "FrontRoll"
	end
end

--[[
	Play an action (request to server)
	@param config The action configuration
]]
function ActionController.PlayAction(config: ActionConfig)
	print(`[ActionController] PlayAction called: {config.Name} (Type: {config.Type})`)

	-- Validate character
	if not Character or not Humanoid or Humanoid.Health <= 0 then
		print(`[ActionController] ✗ Cannot play action - Character: {if Character then "yes" else "NO"}, Humanoid: {if Humanoid then "yes" else "NO"}, Health: {if Humanoid then Humanoid.Health else "N/A"}`)
		return
	end

	-- For dodge actions, determine roll direction based on current input (real-time)
	if config.Type == "Dodge" then
		-- Get current move input direction (not cached) - always check, don't depend on MovementController
		local camera = workspace.CurrentCamera
		if camera then
			local look = camera.CFrame.LookVector
			local forward = Vector3.new(look.X, 0, look.Z).Unit
			if forward.Magnitude < 0.1 then
				forward = Vector3.new(0, 0, -1)
			end
			local right = Vector3.new(-forward.Z, 0, forward.X)
			local x, z = 0, 0
			if UserInputService:IsKeyDown(Enum.KeyCode.W) then z += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.S) then z -= 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
			if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
			local moveDir = forward * z + right * x
			
			if moveDir.Magnitude > 0 then
				moveDir = moveDir.Unit
			else
				moveDir = Vector3.zero
			end
			
			local rollFolder, rollAsset = GetRollForDirection(moveDir)
			print(`[ActionController] Dodge direction: {rollFolder}/{rollAsset} (moveDir magnitude: {moveDir.Magnitude})`)

			-- Clone config and update both folder and asset names
			config = table.clone(config)
			config.AnimationName = rollFolder
			config.AnimationAssetName = rollAsset
		end
	end
		-- For light attacks, handle combo system and check for lunge
	if config.Id == "atk_light" then
		-- Check if sprinting (use lunge attack instead)
		local isCurrentlySprinting = MovementController and MovementController._isSprinting() or false
		if isCurrentlySprinting then
			-- Check lunge cooldown
			local now = tick()
			if now - LastLungeAttackTime > 0.3 then
				print("[ActionController] Lunge attack triggered (sprinting + attack)")
				ActionController.PlayAction(ActionTypes.LUNGE_ATTACK)
				LastLungeAttackTime = now
				return
			end
		end
		
		local now = tick()

		-- Reset combo if timeout
		if now - LastComboTime > COMBO_TIMEOUT then
			ComboCount = 0
		end

		-- Increment combo
		ComboCount = ComboCount + 1
		if ComboCount > 5 then
			ComboCount = 1
		end

		LastComboTime = now

		-- Clone config and set punch animation
		config = table.clone(config)
		config.AnimationAssetName = `punch {ComboCount}`

		-- Mark if this is the final combo hit for knockback
		if ComboCount == 5 then
			config.IsFinisher = true
			config.KnockbackPower = 50 -- Strong knockback on 5th hit
			-- Apply cooldown after finishing combo
			ActionCooldowns[config.Id] = now + COMBO_FINISH_COOLDOWN
		else
			config.IsFinisher = false
		end

		print(`[ActionController] Combo: {ComboCount}/5 - Using {config.AnimationAssetName}`)
	end
		-- Throttle rapid requests
	if tick() - LastActionTime < MIN_ACTION_INTERVAL then
		print(`[ActionController] Throttled - too soon`)
		return
	end

	-- Check cooldown
	if ActionCooldowns[config.Id] and tick() < ActionCooldowns[config.Id] then
		print(`[ActionController] Action on cooldown: {config.Id}`)
		return
	end

	-- Special handling for movement actions (Dodge) - prevent spam queueing
	if config.Type == "Dodge" then
		-- Don't queue dodge if currently dodging
		if CurrentAction and CurrentAction.Config.Type == "Dodge" then
			print(`[ActionController] Cannot dodge while already dodging`)
			return
		end

		-- Don't queue dodge if another dodge is already queued
		for _, queuedAction in ActionQueue do
			if queuedAction.Type == "Dodge" then
				print(`[ActionController] Dodge already queued, ignoring duplicate`)
				return
			end
		end

		-- Apply cooldown immediately when dodge starts (not after it finishes)
		if config.Cooldown then
			ActionCooldowns[config.Id] = tick() + config.Cooldown
		end
	end

	-- Queue or play immediately
	if CurrentAction then
		-- Check if queue is full
		if #ActionQueue >= MAX_QUEUE_SIZE then
			print(`[ActionController] Action queue full ({MAX_QUEUE_SIZE}), ignoring {config.Name}`)
			return
		end

		-- Only allow certain actions to queue during certain states
		-- Dodge actions can queue during attacks for smooth transitions
		if config.Type == "Dodge" or config.Type == "Attack" then
			table.insert(ActionQueue, config)
			print(`[ActionController] Action queued: {config.Name} ({#ActionQueue}/{MAX_QUEUE_SIZE})`)
		else
			print(`[ActionController] Cannot queue {config.Type} while {CurrentAction.Config.Type} is active`)
		end
	else
		print(`[ActionController] Playing action locally: {config.Name}`)
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
	if not Character or not Humanoid then
		print(`[ActionController] Cannot play action - missing character components`)
		return
	end

	print(`[ActionController] ===== PLAYING ACTION: {config.Name} (Duration: {config.Duration}s) =====`)

	-- Create action
	local action: Action = {
		Config = config,
		StartTime = tick(),
		EndTime = tick() + config.Duration,
		IsActive = true,
		TargetHit = nil,
		AnimationTrack = nil,
		Hitbox = nil,

		Play = function(self: Action)
			if self.AnimationTrack then
				self.AnimationTrack:Play()
			end
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
			-- Clean up hitbox
			if self.Hitbox then
				HitboxService.RemoveHitbox(self.Hitbox)
				self.Hitbox = nil
			end
		end,
	}

	CurrentAction = action

	-- If this is an attack, apply movement slowdown via MovementController.SetModifier()
	if config.Type == "Attack" and MovementController and MovementController.SetModifier then
		-- Default attack slowdown to 50% of normal speed
		MovementController.SetModifier("Attacking", 0.5)
		print("[ActionController] Applied movement modifier: Attacking = 0.5x")
	end

	-- Load and play animation if configured. Prefer project animations under
	-- ReplicatedStorage.animations when `AnimationName` is provided;
	-- otherwise fall back to `AnimationId` (asset id string).
	if not AnimationController then
		print(`[ActionController] ✗ No AnimationController for {config.Name}`)
	elseif not Humanoid then
		print(`[ActionController] ✗ No Humanoid for {config.Name}`)
	else
		local track: AnimationTrack?

		-- Try loading from project folder (ReplicatedStorage.animations)
		if config.AnimationName and config.AnimationName ~= "" then
			print(`[ActionController] Trying AnimationLoader: {config.AnimationName} (asset: {config.AnimationAssetName or "nil"})`)
			track = AnimationLoader.LoadTrack(Humanoid, config.AnimationName, config.AnimationAssetName)
			if track then
				print(`[ActionController] ✓ Loaded project animation: {config.AnimationName}`)
			else
				print(`[ActionController] ✗ Failed to load project animation: {config.AnimationName}`)
			end
		end

		-- Fallback to AnimationId if no project animation loaded
		if (not track) and config.AnimationId and config.AnimationId ~= "" then
			print(`[ActionController] Falling back to AnimationId: {config.AnimationId}`)
			local animation = Instance.new("Animation")
			animation.AnimationId = config.AnimationId
			local success, loaded = pcall(function()
				return AnimationController:LoadAnimation(animation)
			end)
			if success and loaded then
				track = loaded :: AnimationTrack
				print(`[ActionController] ✓ Loaded AnimationId track`)
			else
				print(`[ActionController] ✗ Failed to load AnimationId: {if success then "loaded is nil" else tostring(loaded)}`)
				if animation then
					animation:Destroy()
				end
			end
		end

		if track then
			if config.AnimationPriority then
				track.Priority = config.AnimationPriority
			else
				track.Priority = Enum.AnimationPriority.Action
			end

			if config.AnimationSpeed then
				track:AdjustSpeed(config.AnimationSpeed)
			end

			action.AnimationTrack = track
			action:Play()
			print(`[ActionController] ✓ Animation playing for {config.Name}`)
		else
			print(`[ActionController] ⚠ No animation found for {config.Name} - action proceeding without animation`)
			-- Don't block action - let it proceed even without animation
		end

		-- Still trigger Play even without animation (for game feel)
		action:Play()
	end

	-- Call start callback
	if config.OnStart then
		task.spawn(config.OnStart, Player)
	end

	-- Handle dodge movement and iframes
	if config.Type == "Dodge" then
		local rootPart = Utils.GetRootPart(Player)
		if rootPart then
			-- Determine dodge direction from real-time input (same as animation direction)
			local camera = workspace.CurrentCamera
			local dodgeDir = rootPart.CFrame.LookVector
			
			if camera then
				local look = camera.CFrame.LookVector
				local forward = Vector3.new(look.X, 0, look.Z).Unit
				if forward.Magnitude < 0.1 then
					forward = Vector3.new(0, 0, -1)
				end
				local right = Vector3.new(-forward.Z, 0, forward.X)
				local x, z = 0, 0
				if UserInputService:IsKeyDown(Enum.KeyCode.W) then z += 1 end
				if UserInputService:IsKeyDown(Enum.KeyCode.S) then z -= 1 end
				if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
				if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
				local moveDir = forward * z + right * x
				
				if moveDir.Magnitude > 0 then
					dodgeDir = moveDir.Unit
				end
			end

			-- Apply velocity impulse for dodge movement
			local DODGE_SPEED = 65 -- Snappy dodge speed
			local dodgeVelocity = dodgeDir * DODGE_SPEED

			-- Use BodyVelocity for consistent movement during dodge
			local bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.MaxForce = Vector3.new(30000, 0, 30000)
			bodyVelocity.Velocity = dodgeVelocity
			bodyVelocity.P = 5000
			bodyVelocity.Parent = rootPart

			print(`[ActionController] Dodge velocity applied: {dodgeVelocity}`)

			-- Camera effect for dodge (FOV zoom + directional push)
			print("[ActionController] DODGE CAMERA EFFECT!")
			task.spawn(function()
				local camera = workspace.CurrentCamera
				if not camera then return end

				local startFOV = camera.FieldOfView
				local startCFrame = camera.CFrame

				-- DRAMATIC zoom out effect
				camera.FieldOfView = startFOV + 15 -- Much more noticeable

				-- Camera speed blur effect by pushing back
				local pushAmount = 1.2
				camera.CFrame = startCFrame * CFrame.new(-dodgeDir * pushAmount)

				-- Smooth return over dodge duration
				local startTime = tick()
				while tick() - startTime < config.Duration and camera do
					local progress = (tick() - startTime) / config.Duration
					camera.FieldOfView = startFOV + 15 * (1 - progress)
					task.wait(0.05)
				end
			end)

			-- Clean up after dodge completes
			task.delay(config.Duration, function()
				if bodyVelocity and bodyVelocity.Parent then
					bodyVelocity:Destroy()
				end
			end)
		end

		-- Notify server to set Dodging state (for iframes)
		local networkEvent = NetworkProvider:GetRemoteEvent("StateRequest")
		if networkEvent then
			networkEvent:FireServer({
				Type = "SetState",
				State = "Dodging",
				Timestamp = tick(),
			})
			print(`[ActionController] Requested Dodging state from server`)

			-- Return to Idle after dodge completes
			task.delay(config.Duration, function()
				networkEvent:FireServer({
					Type = "SetState",
					State = "Idle",
					Timestamp = tick(),
				})
				print(`[ActionController] Dodge complete, returning to Idle`)
			end)
		end
	end

	-- Create hitbox for attack actions
	if config.Type == "Attack" and config.HitStartFrame then
		local hitTime = config.Duration * config.HitStartFrame
		print(`[ActionController] Scheduling hitbox creation in {hitTime}s for {config.Name}`)
		task.delay(hitTime, function()
			print(`[ActionController] Hitbox creation callback fired for {config.Name}`)
			if CurrentAction == action and action.IsActive and Character then
				local rootPart = Utils.GetRootPart(Player)
				if rootPart then
					print(`[ActionController] Creating hitbox at {rootPart.Position}`)
					-- Create sphere hitbox in front of player
					local hitboxConfig = {
						Shape = "Sphere",
						Owner = Player,
						Damage = 10, -- Base damage, will be adjusted by mantra/equipment
						Position = rootPart.Position + (rootPart.CFrame.LookVector * 5),
						Size = Vector3.new(6, 6, 6), -- 6 stud radius
						LifeTime = 1.0, -- Hitbox active for 1 second (debug)
						OnHit = function(target: any, hitData)
							local targetName = ""
							if typeof(target) == "Instance" and target:IsA("Player") then
								targetName = target.Name
							elseif type(target) == "string" then
								targetName = target -- dummy ID
							else
								print(`[ActionController] Unknown target type: {typeof(target)}`)
								return
							end

							print(`[ActionController] ✓ Hit {targetName} with {config.Name}`)

						-- Apply knockback on finisher (5th punch)
						if config.IsFinisher and typeof(target) == "Instance" then
							local targetChar = target.Character
							if targetChar then
								local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
								local rootPart = Utils.GetRootPart(Player)
								if targetRoot and rootPart then
									-- Calculate knockback direction (away from attacker)
									local knockbackDir = (targetRoot.Position - rootPart.Position).Unit
									local knockbackVelocity = knockbackDir * (config.KnockbackPower or 50)

									-- Apply velocity (upward component for better feel)
									knockbackVelocity = Vector3.new(knockbackVelocity.X, 20, knockbackVelocity.Z)

									-- Apply to target's root part
									if targetRoot:IsA("BasePart") then
										targetRoot.AssemblyLinearVelocity = knockbackVelocity
										print(`[ActionController] Applied knockback to {targetName}: {knockbackVelocity}`)
									end
								end
							end
						end

						-- Notify server for validation
						local StateRequestEvent = NetworkProvider:GetRemoteEvent("StateRequest")
						if StateRequestEvent then
							StateRequestEvent:FireServer({
								Type = "HitRequest",
								Timestamp = tick(),
								ActionId = config.Id,
								HitData = {
									TargetName = targetName,
									Damage = config.Damage or 10,
									HitType = config.Type,
									ActionName = config.Name,
									IsFinisher = config.IsFinisher or false,
									KnockbackPower = config.KnockbackPower,
									},
								})
							end
						end,
					}

					action.Hitbox = HitboxService.CreateHitbox(hitboxConfig)
					print(`[ActionController] Hitbox created: {action.Hitbox.Id}`)
				else
					print(`[ActionController] Cannot create hitbox - root part not found`)
				end
			else
				print(`[ActionController] Cannot create hitbox - action no longer active`)
			end
		end)
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

	-- Simulate camera shake - DISABLED
	if config.CameraShake then
		-- Camera shake disabled per user request
		-- ActionController._ApplyCameraShake(config.CameraShake)
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
		print(`[ActionController] Action COMPLETE: {action.Config.Name}`)
		action:Stop()
		action:Cleanup()

		-- If this was an attack, clear the movement slowdown modifier
		if action.Config and action.Config.Type == "Attack" and MovementController and MovementController.SetModifier then
			MovementController.SetModifier("Attacking", 1.0)
			print("[ActionController] Removed movement modifier: Attacking")
		end

		CurrentAction = nil

		-- Process queued action
		if #ActionQueue > 0 then
			local nextAction = table.remove(ActionQueue, 1)
			print(`[ActionController] Processing queued action: {nextAction.Name}`)
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

	-- DRAMATIC camera zoom for impact - DISABLED
	-- task.spawn(function()
	-- 	local camera = workspace.CurrentCamera
	-- 	if camera then
	-- 		local startFOV = camera.FieldOfView
	-- 		-- Big zoom in
	-- 		camera.FieldOfView = startFOV - 10
	-- 		task.wait(duration * 0.3)
	-- 		-- Quick zoom out past normal
	-- 		if camera then
	-- 			camera.FieldOfView = startFOV + 3
	-- 			task.wait(duration * 0.7)
	-- 			if camera then
	-- 				camera.FieldOfView = startFOV
	-- 			end
	-- 		end
	-- 	end
	-- end)

	-- Briefly slow down animations for impact feel
	if Humanoid then
		local animator = Humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				local originalSpeed = track.Speed
				track:AdjustSpeed(0.05) -- Slow to 5% speed for more dramatic effect
				task.delay(duration, function()
					if track.IsPlaying then
						track:AdjustSpeed(originalSpeed)
					end
				end)
			end
		end
	end
end

--[[
	Apply camera shake (non-blocking)
	@param trauma Amount of trauma (0-1)
]]
function ActionController._ApplyCameraShake(trauma: number)
	print(`[ActionController] Camera shake: {trauma}`)

	-- Spawn in separate thread to avoid blocking gameplay
	task.spawn(function()
		local camera = workspace.CurrentCamera
		if not camera then return end

		local startCFrame = camera.CFrame

		-- Smooth, elegant camera shake
		for i = 1, 15 do
			local decay = (1 - (i / 15)) ^ 1.5 -- Smoother decay curve
			local intensity = trauma * decay * 1.5 -- Polished intensity

			local offset = Vector3.new(
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity
			)

			-- Gentle rotation shake
			local rotationShake = CFrame.Angles(
				math.rad((math.random() - 0.5) * intensity * 1.5),
				math.rad((math.random() - 0.5) * intensity * 1.5),
				math.rad((math.random() - 0.5) * intensity * 1)
			)

			camera.CFrame = startCFrame * CFrame.new(offset) * rotationShake
			task.wait(0.016)
		end

		camera.CFrame = startCFrame
	end)
end

--[[
	Handle character respawn
	@param newCharacter The new character
]]
function ActionController:OnCharacterAdded(newCharacter: Model)
	print("[ActionController] Character respawned")

	-- Clean up old action
	if CurrentAction then
		-- Ensure any attack slowdown modifier is cleared
		if CurrentAction.Config and CurrentAction.Config.Type == "Attack" and MovementController and MovementController.SetModifier then
			MovementController.SetModifier("Attacking", 1.0)
			print("[ActionController] Removed movement modifier on respawn: Attacking")
		end

		CurrentAction:Stop()
		CurrentAction:Cleanup()
		CurrentAction = nil
	end

	-- Clear queue and cooldowns
	ActionQueue = {}
	ActionCooldowns = {}

	-- Reinitialize
	Character = newCharacter
	local humanoid = Character:WaitForChild("Humanoid", 5)
	if not humanoid then
		warn("[ActionController] New character missing Humanoid")
		Humanoid = nil
		AnimationController = nil
	else
		Humanoid = humanoid

		-- Ensure Animator exists on the new Humanoid as well
		local animator = Humanoid:FindFirstChildOfClass("Animator") :: Animator?
		if not animator then
			warn("[ActionController] Animator not found on new Humanoid - creating one")
			animator = Instance.new("Animator")
			animator.Parent = Humanoid
		end
		AnimationController = animator
	end

	print("[ActionController] Ready for new character")
end

return ActionController
