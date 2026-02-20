--!strict
--[[
	Class: WallRunState
	Description: Owns all wall-run state and physics. Replaces the monolithic
	             StartWallRun / StopWallRun / UpdateWallRun function bodies.

	Private state:
	  • _isWallRunning  — mirrors Blackboard.IsWallRunning.
	  • _wallNormal     — surface normal of current wall (exposed for wall-jump direction).
	  • _stepsUsed      — resets each time player lands; prevents infinite wall-runs.
	  • _startTime      — enforces MaxDuration timeout.

	Public surface:
	  Detect(dt, ctx)       — called by MovementController every frame (replaces UpdateWallRun).
	                          Handles both detection-start and active-frame maintenance.
	  OnJumpRequest(ctx)    — called by _OnJumpRequest when Blackboard.IsWallRunning is true.
	  OnLand(ctx)           — called by MonolithController's landing block to reset step count.
	  Exit(ctx)             — called by dispatcher on forced state exit.

	Dependencies: MovementConfig, workspace
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Shared.modules.MovementConfig)

-- ── Config constants ──────────────────────────────────────────────────────────
local MAX_STEPS         = (MovementConfig.WallRun and MovementConfig.WallRun.MaxSteps)           or 3
local MIN_ENTRY_SPEED   = (MovementConfig.WallRun and MovementConfig.WallRun.MinEntrySpeed)      or 14
local MAX_DURATION      = (MovementConfig.WallRun and MovementConfig.WallRun.MaxDuration)        or 1.8
local DETECT_DIST       = (MovementConfig.WallRun and MovementConfig.WallRun.WallDetectDistance) or 3.0
local JUMP_LATERAL      = (MovementConfig.WallRun and MovementConfig.WallRun.JumpOffLateralForce)or 22
local JUMP_UP           = (MovementConfig.WallRun and MovementConfig.WallRun.JumpOffUpForce)     or 30
local BREATH_WALL_DRAIN = (MovementConfig.Breath and MovementConfig.Breath.WallRunDrainRate)     or 20

-- ── Module-private state ──────────────────────────────────────────────────────
local _isWallRunning: boolean  = false
local _wallNormal   : Vector3  = Vector3.zero
local _stepsUsed    : number   = 0
local _startTime    : number   = 0

-- ── Internal helpers ──────────────────────────────────────────────────────────

local function _stopWallRun(ctx: any)
	if not _isWallRunning then return end
	_isWallRunning = false
	_wallNormal    = Vector3.zero
	ctx.Blackboard.IsWallRunning   = false
	ctx.Blackboard.WallRunNormal   = Vector3.zero
	print("[WallRunState] Wall-run ended")
end

local function _startWallRun(normal: Vector3, ctx: any)
	if _isWallRunning then return end
	local maxSteps = math.floor(MAX_STEPS * (ctx.Blackboard.MomentumMultiplier or 1))
	if _stepsUsed >= maxSteps then return end
	_isWallRunning = true
	_wallNormal    = normal
	_stepsUsed    += 1
	_startTime     = tick()
	ctx.Blackboard.IsWallRunning = true
	ctx.Blackboard.WallRunNormal = normal
	ctx.ChainAction()
	print(("[WallRunState] Wall-run started (step %d/%d)"):format(_stepsUsed, maxSteps))
end

-- ── Public API ────────────────────────────────────────────────────────────────

local WallRunState = {}

--[[
	Called every frame from MovementController._Update.
	Handles per-frame maintenance (gravity cancel, timeout, Breath drain).
]]
function WallRunState.Detect(dt: number, ctx: any)
	local rootPart = ctx.RootPart
	local humanoid = ctx.Humanoid
	if not rootPart or not humanoid then return end

	-- ── On ground: stop active run, reset step count ──────────────────
	if ctx.OnGround then
		if _isWallRunning then
			_stopWallRun(ctx)
		end
		_stepsUsed = 0
		return
	end

	-- ── Active wall-run maintenance ───────────────────────────────────
	if _isWallRunning then
		-- Drain Breath each frame
		if not ctx.DrainBreath(BREATH_WALL_DRAIN * dt) then
			_stopWallRun(ctx)
			return
		end
		
		-- Stick to wall and maintain momentum
		local vel = rootPart.AssemblyLinearVelocity
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		
		-- Calculate direction along the wall
		local wallRight = Vector3.new(0, 1, 0):Cross(_wallNormal).Unit
		local moveDir = (vel:Dot(wallRight) > 0) and wallRight or -wallRight
		
		-- Apply velocity: move along wall, push slightly into wall to stick, zero Y gravity
		rootPart.AssemblyLinearVelocity = (moveDir * speed) + (-_wallNormal * 4)
		
		return
	end

	-- Detection (airborne, no active run) is now provided to callers via TryStart/CanStart.
end

--[[
	Attempt to start a wall-run immediately (explicit user jump press).
	Returns true if a wall-run was started.
]]
function WallRunState.TryStart(ctx: any): boolean
	local rootPart = ctx.RootPart
	if not rootPart then return false end

	-- reuse the detection raycast from Detect() by calling the lower-level probe
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { ctx.Character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local rightDir = rootPart.CFrame.RightVector * Vector3.new(1, 0, 1)
	local leftDir  = -rightDir

		-- Try raycasts at two vertical offsets (hip/head) for more robust detection
	local upOffset = Vector3.new(0, 1.2, 0)
	local downOffset = Vector3.new(0, -0.8, 0)

	local hitRight = workspace:Raycast(rootPart.Position + upOffset, rightDir * DETECT_DIST, params)
	or workspace:Raycast(rootPart.Position + downOffset, rightDir * DETECT_DIST, params)
	local hitLeft  = workspace:Raycast(rootPart.Position + upOffset, leftDir * DETECT_DIST, params)
	or workspace:Raycast(rootPart.Position + downOffset, leftDir * DETECT_DIST, params)

	local normal = (hitRight and hitRight.Normal) or (hitLeft and hitLeft.Normal) or nil
	if not normal then return false end

	-- Accept slightly lower horizontal speed if player just pressed Jump (caller responsibility may handle this)
	local vel = rootPart.AssemblyLinearVelocity
	local horzSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if horzSpeed < MIN_ENTRY_SPEED then
		-- allow a small forgiveness window (10% below threshold)
		if horzSpeed < (MIN_ENTRY_SPEED * 0.9) then return false end
	end

	-- speed and step checks
	local vel = rootPart.AssemblyLinearVelocity
	local horzSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if horzSpeed < MIN_ENTRY_SPEED then return false end
	local maxSteps = math.floor(MAX_STEPS * (ctx.Blackboard.MomentumMultiplier or 1))
	if _stepsUsed >= maxSteps then return false end

	_startWallRun(normal, ctx)
	return true
end

--[[
	Called by MovementController._OnJumpRequest when Blackboard.IsWallRunning.
	Kicks the player perpendicular from the wall and upward.
]]
function WallRunState.OnJumpRequest(ctx: any)
	local rootPart = ctx.RootPart
	if rootPart then
		local kickDir = Vector3.new(_wallNormal.X, 0, _wallNormal.Z)
		if kickDir.Magnitude > 0.01 then
			kickDir = kickDir.Unit
		else
			kickDir = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
			if kickDir.Magnitude > 0.01 then kickDir = kickDir.Unit end
		end
		rootPart.AssemblyLinearVelocity = Vector3.new(
			kickDir.X * JUMP_LATERAL,
			JUMP_UP,
			kickDir.Z * JUMP_LATERAL
		)
	end
	_stopWallRun(ctx)
	ctx.ChainAction()
	print("[WallRunState] Wall-jump!")
end

--[[
	Called from MovementController's landing block when the player touches ground.
	Resets the step count so subsequent jumps allow fresh wall runs.
	(Note: Detect() also resets stepsUsed on ground, so this is a belt-and-suspenders call.)
]]
function WallRunState.OnLand(_ctx: any)
	_stepsUsed = 0
end

--[[
	Called by the dispatcher on forced state exit.
]]
function WallRunState.Exit(ctx: any)
	if _isWallRunning then
		_stopWallRun(ctx)
		print("[WallRunState] Forcibly exited")
	end
end

function WallRunState.IsWallRunning(): boolean
	return _isWallRunning
end

return WallRunState
