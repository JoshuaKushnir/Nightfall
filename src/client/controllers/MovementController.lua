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
local BodyVelocityInstance: BodyVelocity? = nil

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
local SLIDE_DURATION = MovementConfig.Dodge.SlideDuration or 1.2 -- seconds before decay
local SLIDE_COOLDOWN = MovementConfig.Dodge.Cooldown or 0.8 -- seconds before next slide
local SLIDE_DECAY_EASING = MovementConfig.Dodge.DecayEasing or Enum.EasingStyle.Exponential
local SLIDE_DECAY_DIRECTION = MovementConfig.Dodge.DecayDirection or Enum.EasingDirection.Out
local SLIDE_LEAP_FORWARD = MovementConfig.Dodge.LeapForwardForce or 35  -- horizontal launch on slide jump
local SLIDE_LEAP_UP      = MovementConfig.Dodge.LeapUpForce      or 28  -- vertical launch on slide jump

-- Breath resource (#95)
local BREATH_POOL              = (MovementConfig.Breath and MovementConfig.Breath.Pool) or 100
local BREATH_REGEN_STATIONARY  = (MovementConfig.Breath and MovementConfig.Breath.RegenRateStationary) or 25
local BREATH_REGEN_MOVING      = (MovementConfig.Breath and MovementConfig.Breath.RegenRateMoving) or 12
local BREATH_SPRINT_DRAIN      = (MovementConfig.Breath and MovementConfig.Breath.SprintDrainRate) or 10
local BREATH_DASH_DRAIN        = (MovementConfig.Breath and MovementConfig.Breath.DashDrainFlat) or 15
local BREATH_WALL_DRAIN        = (MovementConfig.Breath and MovementConfig.Breath.WallRunDrainRate) or 20

-- Momentum (#95)
local MOMENTUM_CAP          = (MovementConfig.Momentum and MovementConfig.Momentum.Cap) or 3.0
local MOMENTUM_GAIN         = (MovementConfig.Momentum and MovementConfig.Momentum.ChainGainPerAction) or 0.4
local MOMENTUM_CHAIN_WINDOW = (MovementConfig.Momentum and MovementConfig.Momentum.ChainWindowSec) or 1.5
local MOMENTUM_DECAY        = (MovementConfig.Momentum and MovementConfig.Momentum.DecayRatePerSec) or 2.0
local MOMENTUM_JUMP_BONUS   = (MovementConfig.Momentum and MovementConfig.Momentum.JumpHeightBonus) or 0.25

-- Wall-run (#95)
local WALLRUN_MAX_STEPS      = (MovementConfig.WallRun and MovementConfig.WallRun.MaxSteps) or 3
local WALLRUN_MIN_SPEED      = (MovementConfig.WallRun and MovementConfig.WallRun.MinEntrySpeed) or 14
local WALLRUN_MAX_DURATION   = (MovementConfig.WallRun and MovementConfig.WallRun.MaxDuration) or 1.8
local WALLRUN_DETECT_DIST    = (MovementConfig.WallRun and MovementConfig.WallRun.WallDetectDistance) or 3.0
local WALLRUN_JUMP_LATERAL   = (MovementConfig.WallRun and MovementConfig.WallRun.JumpOffLateralForce) or 22
local WALLRUN_JUMP_UP        = (MovementConfig.WallRun and MovementConfig.WallRun.JumpOffUpForce) or 30

-- Vault (#95)
local VAULT_MAX_HEIGHT    = (MovementConfig.Vault and MovementConfig.Vault.MaxObstacleHeight) or 5.5
local VAULT_MIN_HEIGHT    = (MovementConfig.Vault and MovementConfig.Vault.MinObstacleHeight) or 1.5
local VAULT_FORWARD_DIST  = (MovementConfig.Vault and MovementConfig.Vault.ForwardDetectDistance) or 2.5
local VAULT_DURATION      = (MovementConfig.Vault and MovementConfig.Vault.Duration) or 0.35
local VAULT_MOMENTUM_KEEP = (MovementConfig.Vault and MovementConfig.Vault.MomentumPreservePct) or 0.85
local VAULT_COOLDOWN      = (MovementConfig.Vault and MovementConfig.Vault.Cooldown) or 1.0

-- Ledge catch (#95)
local LEDGE_FORWARD_DIST  = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.ForwardDetectDistance) or 2.0
local LEDGE_HEIGHT_OFFSET = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.HeightCheckOffset) or 2.5
local LEDGE_HANG_DURATION = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.HangDuration) or 0.6
local LEDGE_PULL_DURATION = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.PullUpDuration) or 0.4
local LEDGE_TRIGGER_SPEED = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.TriggerFallSpeed) or -8
local LEDGE_REACH_WINDOW  = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.ReachWindow) or 2.5

-- State
local currentSpeed = 0.0
local smoothedDirection: Vector3 = Vector3.zero -- Smoothed input direction
local coyoteTimeLeft = 0.0
local jumpBufferLeft = 0.0
local lastWasOnGround = false
local lastMoveDirection: Vector3 = Vector3.zero
local isSprinting = false
local sprintAllowed = false -- set when double-tap W, cleared on W release
local lastSprintState = false
local currentAnimationTrack: AnimationTrack? = nil
local currentAnimationState: string? = nil -- "Idle", "Walk", "Running"
local lastWKeyPressTime = 0 -- Time of last W key press
local isSliding = false
local lastSlideTime = 0 -- Track slide cooldown

-- Breath state (#95)
local breathPool: number = BREATH_POOL
local isBreathExhausted: boolean = false

-- Momentum state (#95)
local momentumMultiplier: number = 1.0
local lastChainActionTime: number = 0
local chainTimerActive: boolean = false

-- Wall-run state (#95)
local isWallRunning: boolean = false
local wallRunNormal: Vector3 = Vector3.zero   -- surface normal of current wall
local wallRunStepsUsed: number = 0            -- resets each time player lands
local wallRunStartTime: number = 0

-- Vault state (#95)
local isVaulting: boolean = false
local lastVaultTime: number = 0

-- Ledge-catch state (#95)
local isLedgeCatching: boolean = false

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

-- ============================================================
-- BREATH SYSTEM  (#95)
-- ============================================================

--[[
	Drain Breath by `amount`. Returns true if pool still has Breath.
	Returns false and sets exhausted flag when pool hits 0.
	TODO: fire stumble animation when asset is available (ref #95 spec gap).
]]
local function DrainBreath(amount: number): boolean
	if isBreathExhausted then return false end
	breathPool = math.max(0, breathPool - amount)
	if breathPool <= 0 then
		isBreathExhausted = true
		-- Force to walk speed; block sprint while exhausted
		speedModifiers["BreathExhaust"] = 0.5
		sprintAllowed = false
		print("[MovementController] ⚠ BREATH EXHAUSTED — stumble (TODO: play stumble anim when asset ready)")
		return false
	end
	return true
end

--[[
	Called each frame. Handles regen when not actively draining.
	Sprint drain and wall-run drain are applied at their call sites.
]]
local function UpdateBreath(dt: number, onGround: boolean, moving: boolean)
	if isWallRunning then return end -- wall-run drain handled in UpdateWallRun
	if isSprinting and onGround then
		DrainBreath(BREATH_SPRINT_DRAIN * dt)
		return
	end
	-- Regen
	local regenRate = 0
	if onGround then
		regenRate = (not moving) and BREATH_REGEN_STATIONARY or BREATH_REGEN_MOVING
	end
	if regenRate > 0 then
		breathPool = math.min(BREATH_POOL, breathPool + regenRate * dt)
		if isBreathExhausted and breathPool > 5 then
			isBreathExhausted = false
			speedModifiers["BreathExhaust"] = nil  -- remove the penalty
			print("[MovementController] Breath recovered")
		end
	end
end

-- ============================================================
-- MOMENTUM SYSTEM  (#95)
-- Ramp: +MOMENTUM_GAIN per chained action, cap 3×, linear ramp.
-- Decay: -MOMENTUM_DECAY/sec after MOMENTUM_CHAIN_WINDOW of inactivity.
-- Effects exposed via GetMomentumMultiplier():
--   • Dash/slide distance scaled by multiplier (applied in _TrySlide)
--   • Jump height bonus applied in _OnJumpRequest
--   • Melee bonus read by CombatService / ActionController
-- ============================================================

local function ChainAction()
	momentumMultiplier = math.min(MOMENTUM_CAP, momentumMultiplier + MOMENTUM_GAIN)
	lastChainActionTime = tick()
	chainTimerActive = true
	print(string.format("[MovementController] Momentum chained → %.2f×", momentumMultiplier))
end

local function UpdateMomentum(dt: number)
	if not chainTimerActive then return end
	if tick() - lastChainActionTime <= MOMENTUM_CHAIN_WINDOW then return end
	-- Chain broken — decay toward 1.0
	if momentumMultiplier > 1.0 then
		momentumMultiplier = math.max(1.0, momentumMultiplier - MOMENTUM_DECAY * dt)
	else
		momentumMultiplier = 1.0
		chainTimerActive = false
	end
end

-- ============================================================
-- WALL-RUN  (#95)
-- Detected via lateral raycasts while airborne.
-- MaxSteps = 3 per air session (resets on landing).
-- Gravity countered by zeroing negative Y velocity each frame.
-- ============================================================

local function StopWallRun()
	if not isWallRunning then return end
	isWallRunning = false
	wallRunNormal = Vector3.zero
	print("[MovementController] Wall-run ended")
end

local function StartWallRun(normal: Vector3)
	if isWallRunning then return end
	if wallRunStepsUsed >= WALLRUN_MAX_STEPS then return end
	isWallRunning = true
	wallRunNormal = normal
	wallRunStepsUsed += 1
	wallRunStartTime = tick()
	ChainAction()
	print(string.format("[MovementController] Wall-run started (step %d/%d)", wallRunStepsUsed, WALLRUN_MAX_STEPS))
end

--[[
	Called every frame from _Update.
	Starts a wall-run when airborne, fast enough, and adjacent to a wall.
	Maintains the active wall-run each frame (anti-gravity, duration check, Breath drain).
]]
local function UpdateWallRun(dt: number, onGround: boolean)
	local rootPart = RootPart
	local humanoid = Humanoid
	if not rootPart or not humanoid then return end

	-- Reset step count on landing
	if onGround then
		if isWallRunning then
			StopWallRun()
		end
		wallRunStepsUsed = 0
		return
	end

	-- Maintain an active wall-run
	if isWallRunning then
		-- Drain Breath
		if not DrainBreath(BREATH_WALL_DRAIN * dt) then
			StopWallRun()
			return
		end
		-- Timeout
		if tick() - wallRunStartTime > WALLRUN_MAX_DURATION then
			StopWallRun()
			return
		end
		-- Counter gravity: clamp Y velocity so player doesn't fall during run
		local vel = rootPart.AssemblyLinearVelocity
		if vel.Y < 0 then
			rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
		end
		return
	end

	-- Don't start if no steps remaining
	if wallRunStepsUsed >= WALLRUN_MAX_STEPS then return end
	-- Don't start if moving too slow
	local vel = rootPart.AssemblyLinearVelocity
	local horzSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if horzSpeed < WALLRUN_MIN_SPEED then return end

	-- Raycast left and right to find a wall
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { Character :: Model }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local rightDir = rootPart.CFrame.RightVector * Vector3.new(1, 0, 1)
	local leftDir  = -rightDir

	local hitRight = workspace:Raycast(rootPart.Position, rightDir * WALLRUN_DETECT_DIST, params)
	local hitLeft  = workspace:Raycast(rootPart.Position, leftDir  * WALLRUN_DETECT_DIST, params)

	if hitRight then
		StartWallRun(hitRight.Normal)
	elseif hitLeft then
		StartWallRun(hitLeft.Normal)
	end
end

-- ============================================================
-- VAULT  (#95)
-- Detects low obstacles during sprint, auto-vaults if clearance exists.
-- ============================================================

local function TryVault()
	local humanoid = Humanoid
	local rootPart = RootPart
	if not humanoid or not rootPart or not Character then return end
	if isVaulting or isLedgeCatching or isWallRunning then return end
	if not isSprinting then return end
	if humanoid.FloorMaterial == Enum.Material.Air then return end -- not on ground
	if tick() - lastVaultTime < VAULT_COOLDOWN then return end

	local lookDir = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
	if lookDir.Magnitude < 0.01 then return end
	lookDir = lookDir.Unit

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { Character :: Model }
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Cast forward at waist level to find obstacle face
	local hitForward = workspace:Raycast(rootPart.Position, lookDir * VAULT_FORWARD_DIST, params)
	if not hitForward then return end

	-- Estimate obstacle height relative to ground
	local groundY = rootPart.Position.Y - 2.5 -- approximate ground under character
	local obstacleRelHeight = hitForward.Position.Y - groundY

	if obstacleRelHeight < VAULT_MIN_HEIGHT or obstacleRelHeight > VAULT_MAX_HEIGHT then return end

	-- Confirm clearance above the obstacle top (player head must fit)
	local topCheck = hitForward.Position + Vector3.new(0, 0.5, 0) + lookDir * 0.5
	local clearHit = workspace:Raycast(topCheck, Vector3.new(0, 6, 0), params)
	if clearHit then return end -- no headroom

	-- Vault!
	isVaulting = true
	lastVaultTime = tick()
	print(string.format("[MovementController] Vault → obstacle %.1f studs", obstacleRelHeight))

	local startCFrame = rootPart.CFrame
	-- Target: on top of the obstacle, one step forward
	local targetPos = Vector3.new(
		hitForward.Position.X + lookDir.X * 1.5,
		hitForward.Position.Y + 0.6,
		hitForward.Position.Z + lookDir.Z * 1.5
	)
	local targetCFrame = CFrame.new(targetPos, targetPos + lookDir)

	humanoid.PlatformStand = true
	rootPart.AssemblyLinearVelocity = Vector3.zero

	local vaultStart = tick()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local t = math.min(1.0, (tick() - vaultStart) / VAULT_DURATION)
		local easedT = 1 - math.pow(1 - t, 2) -- ease-out quad
		if rootPart then
			rootPart.CFrame = startCFrame:Lerp(targetCFrame, easedT)
		end
		if t >= 1.0 then
			conn:Disconnect()
			if humanoid then
				humanoid.PlatformStand = false
			end
			-- Preserve forward momentum
			if rootPart then
				rootPart.AssemblyLinearVelocity = lookDir * (currentSpeed * VAULT_MOMENTUM_KEEP)
			end
			isVaulting = false
			ChainAction()
			print("[MovementController] Vault complete")
		end
	end)
end

-- ============================================================
-- LEDGE CATCH  (#95)
-- Auto-triggers when falling and near a ledge edge above character.
-- Brief hang → auto pull-up.
-- ============================================================

local function TryLedgeCatch()
	local humanoid = Humanoid
	local rootPart = RootPart
	if not humanoid or not rootPart or not Character then return end
	if isLedgeCatching or isVaulting or isWallRunning then return end
	if humanoid.FloorMaterial ~= Enum.Material.Air then return end -- on ground, skip

	-- Only trigger when falling at sufficient speed
	local vel = rootPart.AssemblyLinearVelocity
	if vel.Y > LEDGE_TRIGGER_SPEED then return end -- not falling fast enough

	local lookDir = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
	if lookDir.Magnitude < 0.01 then return end
	lookDir = lookDir.Unit

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { Character :: Model }
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Cast downward from a point ahead of the character near head height
	local probeOrigin = rootPart.Position + lookDir * LEDGE_FORWARD_DIST
		+ Vector3.new(0, LEDGE_HEIGHT_OFFSET + 0.5, 0)
	local hitDown = workspace:Raycast(probeOrigin, Vector3.new(0, -(LEDGE_HEIGHT_OFFSET + 2), 0), params)
	if not hitDown then return end

	local ledgeY = hitDown.Position.Y
	local charTopY = rootPart.Position.Y + 1.5 -- approximate top of character

	-- Ledge must be just above the character's reach
	if ledgeY < charTopY or ledgeY > charTopY + LEDGE_REACH_WINDOW then return end

	-- Catch!
	isLedgeCatching = true
	print("[MovementController] Ledge catch triggered")

	-- Snap character to hang position
	humanoid.PlatformStand = true
	local catchPos = Vector3.new(
		hitDown.Position.X - lookDir.X * 0.6,
		ledgeY - 2.0, -- root hangs below ledge surface
		hitDown.Position.Z - lookDir.Z * 0.6
	)
	rootPart.CFrame = CFrame.new(catchPos, catchPos + lookDir)
	rootPart.AssemblyLinearVelocity = Vector3.zero

	-- Hang for HangDuration, then pull up
	task.delay(LEDGE_HANG_DURATION, function()
		if not isLedgeCatching then return end
		print("[MovementController] Ledge pull-up")

		local pullTarget = Vector3.new(
			hitDown.Position.X + lookDir.X * 1.0,
			ledgeY + 0.5,
			hitDown.Position.Z + lookDir.Z * 1.0
		)
		local pullStart = rootPart and rootPart.Position or pullTarget
		local startTime = tick()
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function()
			local t = math.min(1.0, (tick() - startTime) / LEDGE_PULL_DURATION)
			if rootPart then
				rootPart.CFrame = CFrame.new(
					pullStart:Lerp(pullTarget, t),
					pullTarget + lookDir
				)
			end
			if t >= 1.0 then
				conn:Disconnect()
				if humanoid then
					humanoid.PlatformStand = false
				end
				isLedgeCatching = false
				ChainAction()
				print("[MovementController] Ledge pull-up complete")
			end
		end)
	end)
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

-- Apply a short client-side impulse (used by actions like Lunge)
-- direction: world-space horizontal Vector3 (will be projected to XZ)
-- speed: studs/s magnitude
-- duration: seconds to hold the impulse (will be clamped)
-- tag: optional name for debugging
function MovementController.ApplyImpulse(direction: Vector3, speed: number, duration: number, tag: string?)
	local rootPart = RootPart
	local humanoid = Humanoid
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		print("[MovementController] ✗ ApplyImpulse failed - missing character/rootPart")
		return false
	end

	-- Sanitize inputs
	if not direction or direction.Magnitude < 0.01 then
		print("[MovementController] ✗ ApplyImpulse failed - invalid direction: " .. tostring(direction))
		return false
	end
	duration = math.clamp(duration or 0.2, 0.05, 1.0)

	-- Project to horizontal plane and normalize
	local hor = Vector3.new(direction.X, 0, direction.Z)
	if hor.Magnitude < 0.01 then
		hor = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	local dir = hor.Unit

	local vel = dir * (speed or 40)

	-- Create a transient BodyVelocity instance for the impulse (using BodyVelocity for simplicity/reliability over LinearVelocity without attachments)
	local impulseName = (tag and ("_impulse_" .. tag)) or ("_impulse_" .. tostring(tick()))
	local lv = Instance.new("BodyVelocity")
	lv.Name = impulseName
	lv.Parent = rootPart
	lv.MaxForce = Vector3.new(math.huge, 0, math.huge)
	lv.Velocity = vel
	lv.P = 1250 -- High P for responsiveness
	-- lv.Enabled = true (BodyVelocity is enabled by default)

	-- Immediate fallback: set AssemblyLinearVelocity for instant displacement
	if rootPart and rootPart:IsA("BasePart") then
		rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, rootPart.AssemblyLinearVelocity.Y, vel.Z)
	end

	print(string.format("[MovementController] Impulse applied (%s) speed=%.1f duration=%.2f", tostring(tag or "anon"), vel.Magnitude, duration))

	-- Clean up after duration (BodyVelocity has no Enabled property, just destroy it)
	task.delay(duration, function()
		if lv and lv.Parent then
			lv:Destroy()
			print(string.format("[MovementController] Impulse ended (%s)", tostring(tag or "anon")))
		end
	end)

	return true
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
	
		-- Double-tap W to 'prime' sprint for the next hold (not a persistent toggle)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == Enum.KeyCode.W then
			local currentTime = tick()
			if currentTime - lastWKeyPressTime < SPRINT_DOUBLE_TAP_WINDOW then
				-- Double-tap detected: prime sprint until W is released
				sprintAllowed = true
				print("[MovementController] Sprint primed — hold W to sprint")
			end
			lastWKeyPressTime = currentTime
		elseif input.KeyCode == SLIDE_KEY then
			-- Attempt to slide
			MovementController._TrySlide()
		end
	end)

	-- Clear sprint allowance when all movement keys are released
	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.KeyCode == Enum.KeyCode.W
			or input.KeyCode == Enum.KeyCode.A
			or input.KeyCode == Enum.KeyCode.S
			or input.KeyCode == Enum.KeyCode.D
		then
			local anyMovementHeld = UserInputService:IsKeyDown(Enum.KeyCode.W)
				or UserInputService:IsKeyDown(Enum.KeyCode.A)
				or UserInputService:IsKeyDown(Enum.KeyCode.S)
				or UserInputService:IsKeyDown(Enum.KeyCode.D)
			if not anyMovementHeld then
				sprintAllowed = false
			end
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
	DrainBreath(BREATH_DASH_DRAIN) -- flat Breath cost per slide (#95)
	ChainAction()                  -- count as a momentum chain link (#95)
	print("[MovementController] ✓ SLIDE INITIATED")
	
	-- Create or reuse BodyVelocity for momentum
	if not BodyVelocityInstance then
		BodyVelocityInstance = Instance.new("BodyVelocity")
		BodyVelocityInstance.Name = "SlideVelocity"
		BodyVelocityInstance.Parent = rootPart
		print("[MovementController] BodyVelocity instance created")
	end
	
	-- Set up slide trajectory — distance scales with momentum multiplier (#95)
	local momentumScale = momentumMultiplier  -- 1.0 at rest, up to 3.0 at cap
	local effectiveSlideSpeed = SLIDE_SPEED * momentumScale
	local slideDirection = lastMoveDirection.Unit
	local slideVelocity = slideDirection * effectiveSlideSpeed

	BodyVelocityInstance.MaxForce = Vector3.new(math.huge, 0, math.huge) -- Only horizontal momentum
	BodyVelocityInstance.Velocity = slideVelocity
	BodyVelocityInstance.P = 1500 -- Slightly softer P for sliding

	print(string.format("[MovementController] Slide %.0f studs/s (%.1f× momentum)", effectiveSlideSpeed, momentumScale))

	-- Play slide animation (if available) and mark animation state
	if currentAnimationTrack then
		currentAnimationTrack:Stop()
		currentAnimationTrack = nil
	end
	local slideTrack = AnimationLoader.LoadTrack(Humanoid, "Slide")
	if slideTrack then
		slideTrack.Looped = true
		slideTrack:Play()
		currentAnimationTrack = slideTrack
		currentAnimationState = "Sliding"
		print("[MovementController] ✓ Slide animation playing")
	end

	-- Decay the slide momentum using exponential easing over SLIDE_DURATION
	task.spawn(function()
		local slideStartTime = tick()
		while isSliding and BodyVelocityInstance do
			local elapsedTime = tick() - slideStartTime
			local progress = math.min(1.0, elapsedTime / SLIDE_DURATION)

			-- Exponential.Out easing: 1 - (1 - progress)^3
			local easeProgress = 1 - math.pow(1 - progress, 3)
			local currentVelocityMagnitude = effectiveSlideSpeed * (1 - easeProgress)
			
			if BodyVelocityInstance and currentVelocityMagnitude > 0.5 then
				BodyVelocityInstance.Velocity = slideDirection * currentVelocityMagnitude
			end
			
			if progress >= 1.0 then
				break
			end
			
			RunService.Heartbeat:Wait()
		end
		
		-- Slide complete
		if BodyVelocityInstance then
			BodyVelocityInstance.MaxForce = Vector3.zero
			print("[MovementController] Slide momentum fully decayed")
		end
		-- Stop slide animation immediately (if playing)
		if currentAnimationState == "Sliding" and currentAnimationTrack then
			currentAnimationTrack:Stop()
			currentAnimationTrack = nil
			currentAnimationState = nil
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
	local isMoving = moveDir.Magnitude > 0.1

	-- #95 systems — run first so their output is available below
	UpdateBreath(dt, onGround, isMoving)
	UpdateMomentum(dt)
	UpdateWallRun(dt, onGround)
	if not isMovementRestricted() then
		TryVault()
		TryLedgeCatch()
	end
	
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
	-- Sprint only when primed (double-tap) AND while holding W
	local wantsSprint = sprintAllowed and canSprint() and moveDir.Magnitude > 0.5
	-- Expose current sprinting state for ActionController
	isSprinting = wantsSprint

	local targetSpeed = 0
	if moveDir.Magnitude > 0.5 then
		if wantsSprint then
			-- Momentum adds up to +20% sprint speed at cap (#95)
			local momentumSpeedBonus = (momentumMultiplier - 1.0) / (MOMENTUM_CAP - 1.0) * 0.20
			targetSpeed = SPRINT_SPEED * (1 + momentumSpeedBonus)
		else
			targetSpeed = WALK_SPEED
		end
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
		newAnimState = wantsSprint and "Running" or "Walk"
	end
	-- Preserve slide animation while sliding
	if isSliding then
		newAnimState = "Sliding"
	end
	
	if newAnimState ~= currentAnimationState then
		print("[MovementController] Animation transition: " .. tostring(currentAnimationState) .. " -> " .. tostring(newAnimState))
		
		-- Stop current animation
		if currentAnimationTrack then
			currentAnimationTrack:Stop()
			currentAnimationTrack = nil
		end
		
		-- Play new animation
		if newAnimState == "Idle" then
			currentAnimationTrack = AnimationLoader.LoadTrack(Humanoid, "Idle")
			if currentAnimationTrack then
				currentAnimationTrack.Looped = true
				currentAnimationTrack:Play()
				print("[MovementController] ✓ Idle animation playing")
			end
		elseif newAnimState == "Walk" then
			currentAnimationTrack = AnimationLoader.LoadTrack(Humanoid, "Walk")
			if currentAnimationTrack then
				currentAnimationTrack:Play()
				print("[MovementController] ✓ Walk animation playing")
			end
		elseif newAnimState == "Running" then
		-- Prefer a dedicated Sprint animation; fall back to Walk if Sprint missing
		currentAnimationTrack = AnimationLoader.LoadTrack(Humanoid, "Running")
		if currentAnimationTrack then
			currentAnimationTrack:Play()
			print("[MovementController] ✓ Running animation playing")
		else
			-- Fallback: reuse Walk animation (play slightly faster for visual feedback)
			currentAnimationTrack = AnimationLoader.LoadTrack(Humanoid, "Walk")
			if currentAnimationTrack then
				currentAnimationTrack:AdjustSpeed(1.15)
				currentAnimationTrack:Play()
				print("[MovementController] ✓ Running animation missing — using Walk fallback")
			end
			end
		-- Sliding animation state
		elseif newAnimState == "Sliding" then
			currentAnimationTrack = AnimationLoader.LoadTrack(Humanoid, "Slide")
			if currentAnimationTrack then
				currentAnimationTrack.Looped = true
				currentAnimationTrack:Play()
				print("[MovementController] ✓ Slide animation playing")
			end
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

	-- Slide leap: jump during a slide launches forward + upward
	if isSliding then
		local rootPart = RootPart
		isSliding = false  -- break the slide decay loop
		if BodyVelocityInstance then
			BodyVelocityInstance.MaxForce = Vector3.zero
		end
		-- Stop slide animation immediately (if playing)
		if currentAnimationState == "Sliding" and currentAnimationTrack then
			currentAnimationTrack:Stop()
			currentAnimationTrack = nil
			currentAnimationState = nil
		end
		if rootPart then
			local hor = lastMoveDirection.Magnitude > 0.1
				and lastMoveDirection.Unit
				or (rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
			rootPart.AssemblyLinearVelocity = Vector3.new(
				hor.X * SLIDE_LEAP_FORWARD,
				SLIDE_LEAP_UP,
				hor.Z * SLIDE_LEAP_FORWARD
			)
		end
		ChainAction()
		print("[MovementController] Slide leap!")
		return
	end

	-- Wall-jump: jump off current wall if wall-running (#95)
	if isWallRunning then
		local rootPart = RootPart
		if rootPart then
			-- Kick perpendicular from wall + upward
			local kickLateral = Vector3.new(wallRunNormal.X, 0, wallRunNormal.Z).Unit
			rootPart.AssemblyLinearVelocity = Vector3.new(
				kickLateral.X * WALLRUN_JUMP_LATERAL,
				WALLRUN_JUMP_UP,
				kickLateral.Z * WALLRUN_JUMP_LATERAL
			)
		end
		StopWallRun()
		ChainAction()
		print("[MovementController] Wall-jump!")
		return
	end

	-- Apply momentum jump bonus (#95): scale JumpHeight at peak multiplier
	if momentumMultiplier > 1.0 then
		local bonus = (momentumMultiplier - 1.0) / (MOMENTUM_CAP - 1.0) * MOMENTUM_JUMP_BONUS
		local base = humanoid.JumpHeight
		humanoid.JumpHeight = base * (1 + bonus)
		task.defer(function()
			if humanoid then humanoid.JumpHeight = base end
		end)
	end

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

-- ============================================================
-- PUBLIC GETTERS — #95 systems (for HUD, CombatService, etc.)
-- ============================================================

--[[
	Current Breath value (0 – BREATH_POOL).
	PlayerHUDController reads this to render the Breath bar.
]]
function MovementController.GetBreath(): number
	return breathPool
end

function MovementController.GetBreathMax(): number
	return BREATH_POOL
end

function MovementController.IsBreathExhausted(): boolean
	return isBreathExhausted
end

--[[
	Current momentum multiplier (1.0 – 3.0).
	CombatService / ActionController reads this to apply the forward-melee bonus.
	HUD may display this as a chain indicator.
]]
function MovementController.GetMomentumMultiplier(): number
	return momentumMultiplier
end

function MovementController.IsWallRunning(): boolean
	return isWallRunning
end

function MovementController.IsVaulting(): boolean
	return isVaulting
end

function MovementController.IsLedgeCatching(): boolean
	return isLedgeCatching
end

-- ============================================================
-- ASPECT MOVEMENT MODIFIERS  (#95)
-- Blocked by #78 (Aspect system). Stubs only — do not implement until #78 lands.
-- Each stub accepts the player's resolved Aspect string from AbilityRegistry and
-- gates the behaviour behind a feature flag that #78 will populate.
-- ============================================================
-- TODO(#78): Ash   — dash leaves false afterimage trails
-- TODO(#78): Tide  — slides further; momentum preserved on wet terrain surfaces
-- TODO(#78): Gale  — one mid-air directional redirect per jump
-- TODO(#78): Ember — faster sprint acceleration ramp (reduce ACCELERATION to ~30, SPRINT_SPEED +2)
-- TODO(#78): Void  — brief phase through geometry corners on cooldown (WALLRUN_DETECT_DIST × 2)
-- TODO(#78): Marrow— Poise regenerates faster during movement (expose tick to PostureService)

return MovementController
