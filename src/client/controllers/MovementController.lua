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

-- Blackboard (shared physics state readable by all client systems)
local Blackboard = require(ReplicatedStorage.Shared.modules.MovementBlackboard)

-- Movement state modules (Open/Closed mechanic decomposition)
-- safeRequire: if a state module fails to load (syntax / runtime error at require-time),
-- return a no-op stub so the rest of the controller continues to function.
-- The Blackboard flag for the dead state is never set, so it is simply skipped in
-- _resolveActiveState and the player falls through to the next-priority state.
local function safeRequire(moduleInstance: ModuleScript, name: string): any
	local ok, result = pcall(require, moduleInstance)
	if ok then
		return result
	end
	warn(("[MovementController] ⚠ State module '%s' failed to load — stubbed out. Error: %s"):format(name, tostring(result)))
	-- Minimal stub: satisfies every call-site in MovementController.
	return {
		-- Dispatcher hooks
		Enter          = function() end,
		Update         = function() end,
		Exit           = function() end,
		-- Per-frame passive detect (WallRunState)
		Detect         = function() end,
		-- Input-driven triggers
		TryStart       = function(): boolean return false end,
		OnJumpRequest  = function() end,
		OnLand         = function() end,
		-- Query helpers (LedgeCatchState)
		CanCatch       = function(): (boolean, any) return false, nil end,
	}
end

local IdleState       = safeRequire(ReplicatedStorage.Shared.movement.states.IdleState,       "IdleState")
local WalkState       = safeRequire(ReplicatedStorage.Shared.movement.states.WalkState,       "WalkState")
local SprintState     = safeRequire(ReplicatedStorage.Shared.movement.states.SprintState,     "SprintState")
local JumpState       = safeRequire(ReplicatedStorage.Shared.movement.states.JumpState,       "JumpState")
local SlideState      = safeRequire(ReplicatedStorage.Shared.movement.states.SlideState,      "SlideState")
local WallRunState    = safeRequire(ReplicatedStorage.Shared.movement.states.WallRunState,    "WallRunState")
local VaultState      = safeRequire(ReplicatedStorage.Shared.movement.states.VaultState,      "VaultState")
local LedgeCatchState = safeRequire(ReplicatedStorage.Shared.movement.states.LedgeCatchState, "LedgeCatchState")
local ClimbState      = safeRequire(ReplicatedStorage.Shared.movement.states.ClimbState,      "ClimbState")

local MovementController = {}

-- Refs (set in Init)
local Player: Player? = nil
local Character: Model? = nil
local Humanoid: Humanoid? = nil
local RootPart: BasePart? = nil
local NetworkController: any = nil -- injected dependency (used to send slide requests to server)

-- Movement config (from MovementConfig or fallback)
local WALK_SPEED = MovementConfig.Movement.WalkSpeed or 12
local SPRINT_SPEED = MovementConfig.Movement.SprintSpeed or 20
local ACCELERATION = MovementConfig.Movement.Acceleration or 45
local DECELERATION = MovementConfig.Movement.Deceleration or 55
local COYOTE_TIME = MovementConfig.Movement.CoyoteTime or 0.12
local JUMP_BUFFER_TIME = MovementConfig.Movement.JumpBufferTime or 0.15

-- Slide mechanics (slide-specific constants are owned by SlideState.lua)
local SPRINT_DOUBLE_TAP_WINDOW = 0.3 -- seconds to detect double-tap
local SLIDE_KEY = Enum.KeyCode.C
local LANDING_SPRINT_GRACE = (MovementConfig.Dodge and MovementConfig.Dodge.LandingSprintGraceWindow) or 0.15 -- seconds to resume sprint after slide-jump landing

-- Breath resource (#95)
local BREATH_POOL              = (MovementConfig.Breath and MovementConfig.Breath.Pool) or 100
local BREATH_REGEN_STATIONARY  = (MovementConfig.Breath and MovementConfig.Breath.RegenRateStationary) or 25
local BREATH_REGEN_MOVING      = (MovementConfig.Breath and MovementConfig.Breath.RegenRateMoving) or 12
local BREATH_SPRINT_DRAIN      = (MovementConfig.Breath and MovementConfig.Breath.SprintDrainRate) or 10
-- BREATH_DASH_DRAIN moved to SlideState.lua | BREATH_WALL_DRAIN moved to WallRunState.lua

-- Momentum (#95)
local MOMENTUM_CAP          = (MovementConfig.Momentum and MovementConfig.Momentum.Cap) or 3.0
local MOMENTUM_GAIN         = (MovementConfig.Momentum and MovementConfig.Momentum.ChainGainPerAction) or 0.4
local MOMENTUM_CHAIN_WINDOW = (MovementConfig.Momentum and MovementConfig.Momentum.ChainWindowSec) or 1.5
local MOMENTUM_DECAY        = (MovementConfig.Momentum and MovementConfig.Momentum.DecayRatePerSec) or 2.0
local MOMENTUM_JUMP_BONUS   = (MovementConfig.Momentum and MovementConfig.Momentum.JumpHeightBonus) or 0.25
-- WallRun / Vault / LedgeCatch config constants moved to their respective state modules.

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
local landingSprintExpiry = 0 -- temporary sprint allowance after slide-jump landing (grace window)
-- isSliding / slideJumped / lastSlideTime → owned by SlideState; exposed via Blackboard.

-- Breath state (#95)
local breathPool: number = BREATH_POOL
local isBreathExhausted: boolean = false

-- Momentum state (#95)
local momentumMultiplier: number = 1.0
local lastChainActionTime: number = 0
local chainTimerActive: boolean = false

-- IsWallRunning / IsVaulting / IsLedgeCatching → private to state modules; exposed via Blackboard.

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
	if Blackboard.IsWallRunning then return end -- wall-run Breath drain handled in WallRunState.Detect
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
-- STATE DISPATCHER
-- Priority-ordered FSM: determines the active movement state every frame
-- and delegates Enter / Exit / Update calls to state modules.
-- State modules write physics flags to Blackboard; the monolith reads from there.
-- Priority (high→low): LedgeCatch > Vault > WallRun > Slide > Jump > Sprint > Walk > Idle
-- ============================================================

local _currentStateName: string = "Idle"
local _stateModules: {[string]: any} = {
	Idle       = IdleState,
	Walk       = WalkState,
	Sprint     = SprintState,
	Jump       = JumpState,
	Slide      = SlideState,
	WallRun    = WallRunState,
	Vault      = VaultState,
	LedgeCatch = LedgeCatchState,
	Climb      = ClimbState,
}

local function _resolveActiveState(
	blackboard: any,
	onGround: boolean,
	wantsSpr: boolean,
	moveDir: Vector3): string
	if blackboard.IsLedgeCatching then return "LedgeCatch" end
	if blackboard.IsClimbing      then return "Climb"      end
	if blackboard.IsVaulting       then return "Vault"      end
	if blackboard.IsWallRunning    then return "WallRun"    end
	if blackboard.IsSliding        then return "Slide"      end
	if blackboard.IsDodging        then return "Dodge"      end
	if not onGround                then return "Jump"       end
	if wantsSpr and moveDir.Magnitude > 0.5 then return "Sprint" end
	if moveDir.Magnitude > 0.5     then return "Walk"       end
	return "Idle"
end

-- Builds the context table passed to all state module methods.
-- Call with current-frame values so state modules always see fresh data.
local function _buildCtx(moveDir: Vector3, onGround: boolean, wantsSpr: boolean): any
	return {
		Humanoid              = Humanoid :: Humanoid,
		RootPart              = RootPart :: BasePart,
		Character             = Character :: Model,
		MoveDir               = moveDir,
		OnGround              = onGround,
		IsSprinting           = wantsSpr,
		LastMoveDir           = lastMoveDirection,
		Blackboard            = Blackboard,
		ChainAction           = ChainAction,
		DrainBreath           = DrainBreath,
		GetMomentumMultiplier = MovementController.GetMomentumMultiplier,
		AnimationLoader       = AnimationLoader,
		NetworkController     = NetworkController,
	}
end

-- (Vault logic moved to VaultState.lua)

-- (LedgeCatch logic moved to LedgeCatchState.lua)

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
	NetworkController = (dependencies and dependencies.NetworkController) or nil
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
	Thin wrapper — delegates to SlideState.TryStart(ctx).
	All slide mechanics (conditions, BodyVelocity, decay, animation) live in SlideState.lua.
]]
function MovementController._TrySlide()
	local humanoid = Humanoid
	if not humanoid then return end
	-- Clear any buffered jump so it doesn't fire as a normal jump after slide starts.
	-- SlideState.OnJumpRequest handles the slide-leap case explicitly.
	jumpBufferLeft = 0
	local ctx = _buildCtx(lastMoveDirection, isOnGround(humanoid), isSprinting)
	SlideState.TryStart(ctx)
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

	-- Shared subsystems (Breath/Momentum stay in MovementController)
	UpdateBreath(dt, onGround, isMoving)
	UpdateMomentum(dt)
	
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
	-- NOTE: Do NOT consume buffered jumps while sliding — jump should be disabled
	-- during an active slide (only slide->jump allowed). Any buffered jump is
	-- cleared on slide start to avoid accidental normal jumps.
	if onGround then
		if jumpBufferLeft > 0 and not Blackboard.IsSliding then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			jumpBufferLeft = 0
		end
	else
		jumpBufferLeft = math.max(0, jumpBufferLeft - dt)
	end

	-- Target speed from input and sprint
	-- Sprint only when primed (double-tap) AND while holding W
	local wantsSprint = (sprintAllowed or tick() < landingSprintExpiry) and canSprint() and moveDir.Magnitude > 0.5
	-- Expose current sprinting state for ActionController
	isSprinting = wantsSprint

	-- ── State dispatcher ──────────────────────────────────────────────────────────────
	do
		local ctx = _buildCtx(moveDir, onGround, wantsSprint)
		-- Passive auto-detect triggers (evaluated every frame when eligible)
		WallRunState.Detect(dt, ctx)
		if not isMovementRestricted() then
			-- Vaulting is now manual (triggered via JumpRequest)
			-- Ledge catch is now manual: requires Jump press (LedgeCatchState.CanCatch / TryStart)
		end
		-- Resolve highest-priority active state
		local resolved = _resolveActiveState(Blackboard, onGround, wantsSprint, moveDir)
		if resolved ~= _currentStateName then
			local oldMod = _stateModules[_currentStateName]
			if oldMod and oldMod.Exit then oldMod.Exit(ctx) end
			_currentStateName = resolved
			Blackboard.ActiveState = resolved
			local newMod = _stateModules[resolved]
			if newMod and newMod.Enter then newMod.Enter(ctx) end
		end
		local activeMod = _stateModules[_currentStateName]
		if activeMod and activeMod.Update then activeMod.Update(dt, ctx) end
	end
	-- ── End dispatcher ──────────────────────────────────────────────────────────────

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
	if Blackboard.IsLedgeCatching then
		newAnimState = Blackboard.IsPullingUp and "LedgeClimb" or "LedgeHold"
	elseif Blackboard.IsVaulting then
		newAnimState = "Vault"
	elseif Blackboard.IsSliding then
		newAnimState = "Slide"
	elseif Blackboard.IsWallRunning then
		newAnimState = "Running" -- Fallback until a dedicated WallRun animation is added
	elseif Blackboard.IsClimbing then
		newAnimState = "LedgeHold" -- Fallback until a dedicated Climb animation is added
	elseif not onGround then
		newAnimState = "Jump"
	elseif moveDir.Magnitude > 0.5 then
		newAnimState = wantsSprint and "Running" or "Walk"
	end
	
	if newAnimState ~= currentAnimationState then
		print("[MovementController] Animation transition: " .. tostring(currentAnimationState) .. " -> " .. tostring(newAnimState))
		
		-- Stop current animation
		if currentAnimationTrack then
			currentAnimationTrack:Stop()
			currentAnimationTrack = nil
		end
		
		-- Play new animation
		currentAnimationTrack = AnimationLoader.LoadTrack(Humanoid, newAnimState)
		if currentAnimationTrack then
			-- Some animations should loop, others shouldn't
			local loopedAnims = {
				Idle = true,
				Walk = true,
				Running = true,
				Slide = true,
				LedgeHold = true,
				Jump = true,
			}
			currentAnimationTrack.Looped = loopedAnims[newAnimState] or false
			currentAnimationTrack:Play()
			print("[MovementController] ✓ " .. newAnimState .. " animation playing")
			
			if newAnimState == "Idle" then
				-- Safety: stop any other playing tracks that might cause perpetual walk/run visuals
				local animator = (Humanoid and Humanoid:FindFirstChildOfClass("Animator"))
				if animator then
					for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
						if t ~= currentAnimationTrack then
							-- stop rogue tracks (defensive fix for stuck animations)
							t:Stop()
						end
					end
				end
			end
		else
			print("[MovementController] ⚠ " .. newAnimState .. " animation missing")
			-- Fallbacks
			if newAnimState == "Running" then
				currentAnimationTrack = AnimationLoader.LoadTrack(Humanoid, "Walk")
				if currentAnimationTrack then
					currentAnimationTrack.Looped = true
					currentAnimationTrack:AdjustSpeed(1.15)
					currentAnimationTrack:Play()
				end
			elseif newAnimState == "Slide" then
				currentAnimationTrack = AnimationLoader.LoadTrack(Humanoid, "Running") or AnimationLoader.LoadTrack(Humanoid, "Walk")
				if currentAnimationTrack then
					currentAnimationTrack.Looped = true
					currentAnimationTrack:AdjustSpeed(0.95)
					currentAnimationTrack:Play()
				end
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

		-- Handle slide-jump landing recovery (roll + resume sprint if moving)
		if Blackboard.SlideJumped then
			Blackboard.SlideJumped = false
			-- Choose landing/roll animation based on last move direction
			local rollName = "Landing"
			if lastMoveDirection.Magnitude > 0.1 and RootPart then
				local localDir = RootPart.CFrame:VectorToObjectSpace(lastMoveDirection)
				if localDir.Z > 0.5 then
					rollName = "FrontRoll"
				elseif localDir.Z < -0.5 then
					rollName = "BackRoll"
				elseif localDir.X > 0 then
					rollName = "RightRoll"
				else
					rollName = "LeftRoll"
				end
			end

			local rollTrack = AnimationLoader.LoadTrack(Humanoid, rollName)
			if rollTrack then
				rollTrack:Play()
				currentAnimationTrack = rollTrack
				currentAnimationState = "Landing"
				print(string.format("[MovementController] ✓ Played landing roll '%s'", rollName))
			end

			-- Give a short sprint-grace so player can continue sprinting on land if input held
			if moveDir.Magnitude > 0.5 then
				landingSprintExpiry = tick() + LANDING_SPRINT_GRACE
			end
		end

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
	end -- close: if not lastWasOnGround and onGround (landing effect)
	-- Flush locomotion state to Blackboard each frame (readable by all client systems)
	Blackboard.IsGrounded          = onGround
	Blackboard.IsSprinting         = wantsSprint
	Blackboard.CurrentSpeed        = currentSpeed
	Blackboard.MoveDir             = moveDir
	Blackboard.LastMoveDir         = lastMoveDirection
	Blackboard.MomentumMultiplier  = momentumMultiplier
	Blackboard.Breath              = breathPool
	Blackboard.BreathExhausted     = isBreathExhausted
	-- NOTE: IsSliding/IsWallRunning/IsVaulting/IsLedgeCatching/SlideJumped/WallRunNormal
	--       are written directly by state modules; no re-flush needed here.
end

--[[
	
	Implements coyote time (jump window after leaving ledge) and jump buffering
	(queue jump before landing).
	
	Called when player presses Space or jumps via JumpRequest.
]]
function MovementController._OnJumpRequest()
	local humanoid = Humanoid
	if not humanoid then return end

	-- Slide leap: delegate to SlideState which owns all slide physics
	if Blackboard.IsSliding then
		local ctx = _buildCtx(lastMoveDirection, false, isSprinting)
		SlideState.OnJumpRequest(ctx)
		-- Clear the animation that was playing during slide
		if currentAnimationState == "Sliding" and currentAnimationTrack then
			currentAnimationTrack:Stop()
			currentAnimationTrack = nil
			currentAnimationState = nil
		end
		return
	end

	-- If player is already wall-running, jump off the wall
	if Blackboard.IsWallRunning then
		local ctx = _buildCtx(lastMoveDirection, false, isSprinting)
		WallRunState.OnJumpRequest(ctx)
		return
	end

	-- If player is climbing, jump off or pull up
	if Blackboard.IsClimbing then
		local ctx = _buildCtx(lastMoveDirection, false, isSprinting)
		if ClimbState.OnJumpRequest then
			ClimbState.OnJumpRequest(ctx)
		end
		return
	end

	local onGround = isOnGround(humanoid)

	-- AIRBORNE: explicit jump-press can START a wall-run or initiate a ledge-hang/pull-up
	if not onGround then
		local ctx = _buildCtx(lastMoveDirection, false, isSprinting)

		-- Try to *start* a wall-run only when player presses Jump near a wall
		if WallRunState.TryStart and WallRunState.TryStart(ctx) then
			return
		end

		-- If already hanging, Jump again → PullUp
		if Blackboard.IsLedgeCatching and LedgeCatchState.PullUp then
			LedgeCatchState.PullUp(ctx)
			return
		end

		-- If in position to catch a ledge, pressing Jump should start the hang
		local canCatch, _ = (LedgeCatchState.CanCatch and LedgeCatchState.CanCatch(ctx))
		if canCatch then
			LedgeCatchState.TryStart(ctx)
			return
		end

		-- Try to start a climb (manual Jump-driven grip). Falls back to ledge/hang if appropriate.
		if ClimbState.TryStart and ClimbState.TryStart(ctx) then
			return
		end
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

-- GROUND: pressing Jump should attempt a buffered vault first (makes vault timing forgiving)
if onGround then
	local ctx = _buildCtx(lastMoveDirection, true, isSprinting)
	local vaultProbeDist = (MovementConfig.Vault and MovementConfig.Vault.ForwardDetectDistance or 2.5) + 1.0
	if VaultState.TryStart and VaultState.TryStart(ctx, vaultProbeDist) then
		return
	end
end

-- Default: perform a normal jump if on ground, otherwise queue in buffer
if onGround then
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	jumpBufferLeft = 0
else
	jumpBufferLeft = JUMP_BUFFER_TIME
end

end

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
	-- Clear slide/jump landing state
	Blackboard.SlideJumped = false
	landingSprintExpiry = 0
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
	return Blackboard.IsWallRunning
end

function MovementController.IsVaulting(): boolean
	return Blackboard.IsVaulting
end

function MovementController.IsLedgeCatching(): boolean
	return Blackboard.IsLedgeCatching
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
