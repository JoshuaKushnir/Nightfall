--!strict
--[[
	MovementController.lua

	Issue #9: Movement Controller & Momentum System
	Epic #56: Smooth Movement System (Deepwoken-style / Hardcore RPG)
	Depends on: #8 (ActionController), #56 (Epic)

	Client-side controller for weighty, responsive movement:
	- Smoothed acceleration/deceleration using MovementConfig curves
	- DirectionSmoothing for responsive, flowing direction changes
	- Coyote time: jump shortly after leaving ledge
	- Jump buffer: jump input just before landing queues a jump
	- Sprint (toggle via double-tap W) with FOV parallax
	- Slide mechanic (press C while sprinting) using LinearVelocity momentum
	- Dynamic speed modifiers via SetModifier() for combat integration
	- Respects combat state (no sprint during Attacking/Blocking/Stunned)
	
	Core Systems:
	1. **Smooth Motion**: Heartbeat-driven acceleration lerping
	2. **Direction Flow**: Camera-relative movement with temporal smoothing
	3. **Momentum Slides**: LinearVelocity-based directional skids on 'C' press
	4. **Modifier Stack**: Combat systems can apply speed multipliers
	5. **State Respect**: Reads PlayerState to restrict movement during animations
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local PlayerData = require(ReplicatedStorage.Shared.types.PlayerData)
local AnimationLoader = require(ReplicatedStorage.Shared.modules.AnimationLoader)
local MovementConfig = require(ReplicatedStorage.Shared.modules.MovementConfig)
type PlayerState = PlayerData.PlayerState

local MovementController = {}

-- Refs (set in Init)
local Player: Player? = nil
local Character: Model? = nil
local Humanoid: Humanoid? = nil
local RootPart: BasePart? = nil
local LinearVelocityInstance: LinearVelocity? = nil

-- Movement config (from MovementConfig or fallback)
local WALK_SPEED = MovementConfig.Movement.WalkSpeed or 12
local SPRINT_SPEED = MovementConfig.Movement.SprintSpeed or 20
local ACCELERATION = MovementConfig.Movement.Acceleration or 45
local DECELERATION = MovementConfig.Movement.Deceleration or 55
local COYOTE_TIME = MovementConfig.Movement.CoyoteTime or 0.12
local JUMP_BUFFER_TIME = MovementConfig.Movement.JumpBufferTime or 0.15

-- Slide mechanics
local SPRINT_DOUBLE_TAP_WINDOW = 0.3 -- seconds to detect double-tap
local SLIDE_KEY = Enum.KeyCode.C
local SLIDE_SPEED = MovementConfig.Dodge.Speed or 50 -- studs/s initial momentum
local SLIDE_DURATION = MovementConfig.Dodge.Duration or 0.5 -- seconds before decay
local SLIDE_COOLDOWN = MovementConfig.Dodge.Cooldown or 0.8 -- seconds before next slide
local SLIDE_DECAY_EASING = MovementConfig.Dodge.DecayEasing or Enum.EasingStyle.Exponential
local SLIDE_DECAY_DIRECTION = MovementConfig.Dodge.DecayDirection or Enum.EasingDirection.Out

-- State
local currentSpeed = 0.0
local smoothedDirection: Vector3 = Vector3.zero -- Smoothed input direction
local coyoteTimeLeft = 0.0
local jumpBufferLeft = 0.0
local lastWasOnGround = false
local lastMoveDirection: Vector3 = Vector3.zero
local isSprinting = false
local lastSprintState = false
local currentAnimationTrack: AnimationTrack? = nil
local currentAnimationState: string? = nil -- "Idle", "Walk", "Running"
local lastWKeyPressTime = 0 -- Time of last W key press
local isSliding = false
local lastSlideTime = 0 -- Track slide cooldown

-- Speed Modifiers: combat systems can apply multipliers via SetModifier()
-- Example: SetModifier("Attacking", 0.5) = 50% walk/sprint speed during attack
local speedModifiers: {[string]: number} = {}

--[[
	Get the effective speed multiplier by finding the minimum modifier value.
	If multiple modifiers are active, returns the lowest multiplier (most restrictive).
	Default: 1.0 (no modification)
	
	@return number - Speed multiplier (0.0 to 1.0+)
]]
local function getEffectiveSpeedMultiplier(): number
	local minMultiplier = 1.0
	for _, multiplier in speedModifiers do
		minMultiplier = math.min(minMultiplier, multiplier)
	end
	return minMultiplier
end

--[[
	Set a named speed modifier for this movement session.
	Combat systems (e.g., ActionController) call this to restrict speed during actions.
	
	Multiple modifiers can be active; the lowest multiplier wins (most restrictive).
	
	@param name: string - Identifier for this modifier (e.g., "Attacking", "Stunned")
	@param multiplier: number - Speed factor (1.0 = normal, 0.5 = half speed, 0.0 = frozen)
	
	Example:
		MovementController.SetModifier("Attacking", 0.5)  -- 50% speed while attacking
		MovementController.SetModifier("Attacking", 1.0)  -- Remove modifier
]]
function MovementController.SetModifier(name: string, multiplier: number)
	if multiplier >= 1.0 then
		-- Remove modifier (1.0 = no modification)
		speedModifiers[name] = nil
		print("[MovementController] Modifier removed: " .. tostring(name))
	else
		speedModifiers[name] = math.max(0, multiplier)
		print("[MovementController] Modifier set: " .. tostring(name) .. " = " .. tostring(multiplier) .. "x speed")
	end
end

-- Movement state export (for ActionController)
--[[
	Get current sprint state.
	ActionController calls this to detect sprint-based attacks (e.g., Lunge).
	
	@return boolean - True if currently sprinting
]]
function MovementController._isSprinting(): boolean
	return isSprinting
end

-- Camera effects
local DEFAULT_FOV = MovementConfig.Camera.DefaultFOV or 70
local SPRINT_FOV = MovementConfig.Camera.SprintFOV or 80 -- configurable via MovementConfig
local SPRINT_FOV_ENABLED = MovementConfig.Camera.FOVPunchEnabled or false
local currentFOV = DEFAULT_FOV
local targetFOV = DEFAULT_FOV

-- States that block sprint and use walk speed
local COMBAT_STATES: {[PlayerState]: boolean} = {
	Attacking = true,
	Blocking = true,
	Stunned = true,
	Ragdolled = true,
	Dead = true,
	Casting = true,
}

local function getStateSyncController(): any
	return MovementController._stateSyncRef
end

local function getCurrentState(): PlayerState?
	local sync = getStateSyncController()
	if sync and sync.GetCurrentState then
		return sync.GetCurrentState()
	end
	return nil
end

local function isMovementRestricted(): boolean
	local state = getCurrentState()
	if not state then return false end
	return COMBAT_STATES[state] == true
end

local function canSprint(): boolean
	if isMovementRestricted() then
		return false
	end
	return true
end

local function isOnGround(h: Humanoid): boolean
	return h.FloorMaterial ~= Enum.Material.Air
end

-- Get move direction from WASD relative to camera (Roblox has no UserInputService:GetMoveDirection)
local function getMoveDirection(): Vector3
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero
	end
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
	local move = (forward * z + right * x)
	if move.Magnitude > 0 then
		return move.Unit
	end
	return Vector3.zero
end

--[[
	Initialize the MovementController with character references.
	
	Called once at startup before :Start().
	Loads character, humanoid, and optional StateSyncController dependency.
	
	@param dependencies: {[string]: any}? - Optional table with StateSyncController reference
	
	Example:
		MovementController:Init({StateSyncController = stateSyncService})
]]
function MovementController:Init(dependencies: {[string]: any}?)
	print("[MovementController] Initializing...")
	Player = Players.LocalPlayer
	if not Player then
		error("[MovementController] LocalPlayer not found")
	end
	Character = Player.Character or Player.CharacterAdded:Wait()
	local hum = Character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not hum then
		error("[MovementController] Humanoid not found")
	end
	Humanoid = hum
	RootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not RootPart then
		warn("[MovementController] HumanoidRootPart not found")
	end
	MovementController._stateSyncRef = (dependencies and dependencies.StateSyncController) or nil
	print("[MovementController] Character ready")
end

--[[
	Start the MovementController.
	
	Hooks Heartbeat loop for smooth motion updates and binds input events for:
	- Jump buffering (Space key)
	- Sprint toggling (double-tap W)
	- Slide initiation (press C)
	
	Call this after :Init().
]]
function MovementController:Start()
	print("[MovementController] Starting...")
	lastWasOnGround = isOnGround(Humanoid :: Humanoid)
	currentSpeed = (Humanoid :: Humanoid).WalkSpeed
	
	-- Initialize camera FOV
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = DEFAULT_FOV
		currentFOV = DEFAULT_FOV
		targetFOV = DEFAULT_FOV
		print("[MovementController] Camera FOV initialized to " .. tostring(DEFAULT_FOV))
	end

	RunService.Heartbeat:Connect(function(dt: number)
		MovementController._Update(dt)
	end)

	UserInputService.JumpRequest:Connect(function()
		MovementController._OnJumpRequest()
	end)
	
	-- Double-tap W to toggle sprint
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == Enum.KeyCode.W then
			local currentTime = tick()
			if currentTime - lastWKeyPressTime < SPRINT_DOUBLE_TAP_WINDOW then
				-- Double-tap detected
				isSprinting = not isSprinting
				print("[MovementController] Sprint toggled: " .. (isSprinting and "ON" or "OFF"))
			end
			lastWKeyPressTime = currentTime
		elseif input.KeyCode == SLIDE_KEY then
			-- Attempt to slide
			MovementController._TrySlide()
		end
	end)

	print("[MovementController] Started")
end

--[[
	Attempt to initiate a slide if conditions are met:
	- Currently sprinting
	- On ground
	- Not in cooldown
	- Move direction exists
	
	Uses LinearVelocity to preserve momentum with exponential decay.
]]
function MovementController._TrySlide()
	local humanoid = Humanoid
	local rootPart = RootPart
	if not humanoid or not rootPart or not Character or humanoid.Health <= 0 then
		return
	end
	
	-- Check conditions
	if not isSprinting then
		print("[MovementController] Cannot slide: not sprinting")
		return
	end
	
	if not isOnGround(humanoid) then
		print("[MovementController] Cannot slide: not on ground")
		return
	end
	
	local currentTime = tick()
	if currentTime - lastSlideTime < SLIDE_COOLDOWN then
		local remaining = math.floor((SLIDE_COOLDOWN - (currentTime - lastSlideTime)) * 100) / 100
		print("[MovementController] Slide on cooldown (" .. tostring(remaining) .. "s remaining)")
		return
	end
	
	if lastMoveDirection.Magnitude < 0.5 then
		print("[MovementController] Cannot slide: no movement direction")
		return
	end
	
	-- Slide initiated
	isSliding = true
	lastSlideTime = currentTime
	print("[MovementController] ✓ SLIDE INITIATED")
	
	-- Create or reuse LinearVelocity for momentum
	if not LinearVelocityInstance then
		LinearVelocityInstance = Instance.new("LinearVelocity")
		LinearVelocityInstance.Parent = rootPart
		print("[MovementController] LinearVelocity instance created")
	end
	
	-- Set up slide trajectory
	local slideDirection = lastMoveDirection.Unit
	local slideVelocity = slideDirection * SLIDE_SPEED
	
	LinearVelocityInstance.Enabled = true
	LinearVelocityInstance.MaxForce = Vector3.new(math.huge, 0, math.huge) -- Only horizontal momentum
	LinearVelocityInstance.Velocity = slideVelocity
	
	print("[MovementController] Slide momentum: " .. tostring(math.floor(SLIDE_SPEED)) .. " studs/s in direction " .. tostring(slideDirection))
	
	-- Decay the slide momentum using exponential easing over SLIDE_DURATION
	task.spawn(function()
		local slideStartTime = tick()
		while isSliding and LinearVelocityInstance do
			local elapsedTime = tick() - slideStartTime
			local progress = math.min(1.0, elapsedTime / SLIDE_DURATION)
			
			-- Exponential.Out easing: 1 - (1 - progress)^3
			local easeProgress = 1 - math.pow(1 - progress, 3)
			local currentVelocityMagnitude = SLIDE_SPEED * (1 - easeProgress)
			
			if LinearVelocityInstance and currentVelocityMagnitude > 0.5 then
				LinearVelocityInstance.Velocity = slideDirection * currentVelocityMagnitude
			end
			
			if progress >= 1.0 then
				break
			end
			
			RunService.Heartbeat:Wait()
		end
		
		-- Slide complete
		if LinearVelocityInstance then
			LinearVelocityInstance.Enabled = false
			print("[MovementController] Slide momentum fully decayed")
		end
		isSliding = false
	end)
end

--[[
	Internal: Main update loop run on Heartbeat.
	
	Handles:
	- Direction smoothing and camera-relative input
	- Speed acceleration/deceleration with modifier stacking
	- Sprint FOV parallax effects
	- Animation state transitions
	- Coyote time and jump buffering
	
	@param dt: number - Delta time since last frame (seconds)
]]
function MovementController._Update(dt: number)
	local humanoid = Humanoid
	local rootPart = RootPart
	if not humanoid or not rootPart or not Character or humanoid.Health <= 0 then
		return
	end

	local moveDir = getMoveDirection()
	local onGround = isOnGround(humanoid)
	
	-- Smooth direction transitions (lerp towards target direction)
	if moveDir.Magnitude > 0.1 then
		-- Moving - smoothly turn towards input direction
		local alpha = math.min(1, dt * 12) -- Measured response, ~70ms to reach 90%
		smoothedDirection = smoothedDirection:Lerp(moveDir.Unit, alpha)
	else
		-- Not moving - quickly reduce direction
		smoothedDirection = smoothedDirection * math.max(0, 1 - dt * 15)
	end

	-- Coyote time: grant jump window after leaving ground
	if lastWasOnGround and not onGround then
		coyoteTimeLeft = COYOTE_TIME
	end
	if not onGround then
		coyoteTimeLeft = math.max(0, coyoteTimeLeft - dt)
	end
	lastWasOnGround = onGround

	-- Jump buffer: count down when on ground and consume
	if onGround then
		if jumpBufferLeft > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			jumpBufferLeft = 0
		end
	else
		jumpBufferLeft = math.max(0, jumpBufferLeft - dt)
	end

	-- Target speed from input and sprint
	local wantsSprint = isSprinting and canSprint() and moveDir.Magnitude > 0.5
	
	local targetSpeed = 0
	if moveDir.Magnitude > 0.5 then
		targetSpeed = wantsSprint and SPRINT_SPEED or WALK_SPEED
		lastMoveDirection = smoothedDirection
	else
		lastMoveDirection = Vector3.zero
	end
	
	-- Apply speed modifiers (combat systems use SetModifier to restrict speed)
	local speedMultiplier = getEffectiveSpeedMultiplier()
	targetSpeed = targetSpeed * speedMultiplier
	
	-- FOV effect for sprint (only if enabled in MovementConfig)
	if SPRINT_FOV_ENABLED then
		targetFOV = wantsSprint and SPRINT_FOV or DEFAULT_FOV
		local fovSpeed = 12 -- Faster FOV changes for more noticeable effect
		currentFOV = currentFOV + (targetFOV - currentFOV) * math.min(1, dt * fovSpeed)
	
		local camera = workspace.CurrentCamera
		if camera then
			camera.FieldOfView = currentFOV
			-- Debug: print FOV changes
			if isSprinting ~= lastSprintState then
				print("[MovementController] Sprint " .. (isSprinting and "START" or "STOP") .. " - FOV: " .. tostring(math.floor(currentFOV)))
				lastSprintState = isSprinting
			end
		end
	else
		-- Ensure FOV stays default when disabled
		targetFOV = DEFAULT_FOV
		currentFOV = DEFAULT_FOV
	end

	-- Simplified acceleration with slight easing
	local speedDiff = targetSpeed - currentSpeed
	if math.abs(speedDiff) > 0.01 then
		local accel = (targetSpeed > currentSpeed) and ACCELERATION or DECELERATION
		-- Apply with slight smoothing for weight without feeling sluggish
		local change = math.clamp(speedDiff, -accel * dt, accel * dt)
		currentSpeed = currentSpeed + change
	else
		currentSpeed = targetSpeed
	end
	
	if currentSpeed < 0.5 then
		currentSpeed = 0
	end

	humanoid.WalkSpeed = currentSpeed
	
	-- Handle animation state transitions
	local newAnimState = "Idle"
	if moveDir.Magnitude > 0.5 then
		newAnimState = wantsSprint and "Sprint" or "Walk"
	end
	
	if newAnimState ~= currentAnimationState then
		print("[MovementController] Animation transition: " .. tostring(currentAnimationState) .. " -> " .. tostring(newAnimState))
		
		-- Stop current animation
		if currentAnimationTrack then
			currentAnimationTrack:Stop()
			currentAnimationTrack = nil
		end
		
		-- Play new animation
		if newAnimState == "Walk" then
			currentAnimationTrack = AnimationLoader.LoadTrack(Humanoid, "Walk")
			if currentAnimationTrack then
				currentAnimationTrack:Play()
				print("[MovementController] ✓ Walk animation playing")
			end
		elseif newAnimState == "Sprint" then
			currentAnimationTrack = AnimationLoader.LoadTrack(Humanoid, "Sprint")
			if currentAnimationTrack then
				currentAnimationTrack:Play()
				print("[MovementController] ✓ Sprint animation playing")
			end
		end
		
		currentAnimationState = newAnimState
	end
	
	-- Camera tilt effect based on movement direction changes
	if camera and moveDir.Magnitude > 0.5 then
		local rootPartCFrame = rootPart.CFrame
		local relativeDir = rootPartCFrame:VectorToObjectSpace(smoothedDirection)
		-- Tilt camera slightly based on strafe direction
		local tiltAmount = relativeDir.X * 1.5 -- Degrees of tilt
		local currentTilt = camera.CFrame:ToEulerAnglesYXZ()
		-- Apply subtle roll for direction changes
		local targetRoll = math.rad(tiltAmount)
		local rollSpeed = 6
		local newRoll = currentTilt + (targetRoll - currentTilt) * math.min(1, dt * rollSpeed) * 0
		-- Disabled for now, can be enabled by changing * 0 to * 1
	end
	
	-- Landing effect
	if not lastWasOnGround and onGround and humanoid.FloorMaterial ~= Enum.Material.Air then
		-- Just landed - create visible impact
		print("[MovementController] LANDING EFFECT!")
		task.spawn(function()
			if camera then
				local originalCFrame = camera.CFrame
				local originalFOV = camera.FieldOfView
				
				-- Quick downward punch + FOV change
				camera.CFrame = originalCFrame * CFrame.new(0, -0.8, 0)
				camera.FieldOfView = originalFOV - 5
				
				task.wait(0.08)
				
				if camera then
					camera.CFrame = originalCFrame
					camera.FieldOfView = originalFOV
				end
			end
		end)
	end
end

--[[
	Internal: Handle jump request input.
	
	Implements coyote time (jump window after leaving ledge) and jump buffering
	(queue jump before landing).
	
	Called when player presses Space or jumps via JumpRequest.
]]
function MovementController._OnJumpRequest()
	local humanoid = Humanoid
	if not humanoid then return end

	local onGround = isOnGround(humanoid)
	if onGround then
		-- Normal jump
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	else
		-- Buffer jump for when we land
		if coyoteTimeLeft > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			coyoteTimeLeft = 0
		else
			jumpBufferLeft = JUMP_BUFFER_TIME
		end
	end
end

--[[
	Called when character respawns. Resets all movement state.
	
	@param newCharacter: Model - The respawned character model
]]
function MovementController:OnCharacterAdded(newCharacter: Model)
	Character = newCharacter
	local hum = newCharacter:WaitForChild("Humanoid", 5) :: Humanoid?
	Humanoid = hum or nil
	RootPart = newCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	
	-- Reset animation state
	if currentAnimationTrack then
		currentAnimationTrack:Stop()
		currentAnimationTrack = nil
	end
	currentAnimationState = nil
	lastWasOnGround = false
	coyoteTimeLeft = 0
	jumpBufferLeft = 0
	if Humanoid then
		currentSpeed = Humanoid.WalkSpeed
	end
	print("[MovementController] Character reset")
end

--[[
	Get the last recorded move direction (world-space, camera-relative).
	Returns Vector3.zero if not moving.
]]
function MovementController:GetLastMoveDirection(): Vector3
	return lastMoveDirection
end

return MovementController
