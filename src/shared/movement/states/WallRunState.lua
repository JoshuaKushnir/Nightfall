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
local MAX_STEPS         = (MovementConfig.WallRun and MovementConfig.WallRun.MaxSteps)           or 5
local MIN_ENTRY_SPEED   = (MovementConfig.WallRun and MovementConfig.WallRun.MinEntrySpeed)      or 12
local MAX_DURATION      = (MovementConfig.WallRun and MovementConfig.WallRun.MaxDuration)        or 5.0
local DETECT_DIST       = (MovementConfig.WallRun and MovementConfig.WallRun.WallDetectDistance) or 4.5
local JUMP_LATERAL      = (MovementConfig.WallRun and MovementConfig.WallRun.JumpOffLateralForce)or 22
local JUMP_UP           = (MovementConfig.WallRun and MovementConfig.WallRun.JumpOffUpForce)     or 26
local GRAVITY_SCALE     = (MovementConfig.WallRun and MovementConfig.WallRun.GravityScale)       or 0.12
local SPEED_MULT        = (MovementConfig.WallRun and MovementConfig.WallRun.SpeedMultiplier)    or 1.05
local BREATH_WALL_DRAIN = (MovementConfig.Breath and MovementConfig.Breath.WallRunDrainRate)     or 20

-- NF-038: Configurable polish
local MAX_STUDS         = (MovementConfig.WallRun and MovementConfig.WallRun.MaxStuds)           or 30
local REENTRY_COOLDOWN  = (MovementConfig.WallRun and MovementConfig.WallRun.ReentryCooldown)    or 0.4
local LERP_SPEED        = (MovementConfig.WallRun and MovementConfig.WallRun.NormalLerpSpeed)    or 10
local GROUND_GRACE      = (MovementConfig.WallRun and MovementConfig.WallRun.GroundedGrace)      or 0.15

-- ── Module-private state ──────────────────────────────────────────────────────
local _isWallRunning: boolean  = false
local _wallNormal   : Vector3  = Vector3.zero
local _stepsUsed    : number   = 0
local _startTime    : number   = 0
local _lastPos      : Vector3  = Vector3.zero
local _distAccum    : number   = 0
local _totalDistTraveled: number = 0
local _lastRunEndTime: number  = 0 -- NF-038
local STEP_DISTANCE             = 6.0 -- distance in studs for one "step" animation/logic cycle

-- ── Internal helpers ──────────────────────────────────────────────────────────

local function _stopWallRun(ctx: any, reason: string?)
	if not _isWallRunning then return end
	_isWallRunning = false
	_wallNormal    = Vector3.zero
	ctx.Blackboard.IsWallRunning   = false
	ctx.Blackboard.WallRunNormal   = Vector3.zero
	_lastRunEndTime = tick() -- NF-038: Set cooldown
	
	-- Restore humanoid state
	if ctx.Humanoid then
		ctx.Humanoid.PlatformStand = false
		ctx.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
		ctx.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
		ctx.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
		ctx.Humanoid.AutoRotate = true
		-- Force update state
		ctx.Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	
	print(("[WallRunState] Wall-run ended%s"):format(reason and (" (Reason: " .. reason .. ")") or ""))
end

local function _startWallRun(normal: Vector3, ctx: any)
	if _isWallRunning then return end
	local maxSteps = math.floor(MAX_STEPS * (ctx.Blackboard.MomentumMultiplier or 1))
	if _stepsUsed >= maxSteps then return end

	_isWallRunning = true
	_wallNormal    = normal
	-- Increment by 1 for the initial "step" onto the wall
	_stepsUsed    += 1
	_startTime     = tick()
	_lastPos       = ctx.RootPart.Position
	
	-- NF-038: Reset accumulators only on land (reset happens in OnLand/Detect)
	-- If we re-enter mid-air, we continue the distance tracking towards the 30-stud cap.
	if _totalDistTraveled == 0 then
		_distAccum = 0
	end
	
	ctx.Blackboard.IsWallRunning = true
	ctx.Blackboard.WallRunNormal = normal
	
	-- Suspend normal physics to prevent Humanoid from fighting the velocity
	if ctx.Humanoid then 
		ctx.Humanoid.PlatformStand = true
		ctx.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
		ctx.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		ctx.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
		ctx.Humanoid.AutoRotate = false -- Prevent fighting the orientation
	end
	
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
	-- temporary kill switch for debugging/rollback
	if MovementConfig.DisableWallRun then return end
	local rootPart = ctx.RootPart
	local humanoid = ctx.Humanoid
	if not rootPart or not humanoid then return end

	-- ── On ground: stop active run, reset step count ──────────────────
	if ctx.OnGround then
		local isActuallyOnFlatGround = false
		if _isWallRunning then
			-- Verify it's actually a flat floor, not just a steep wall triggering FloorMaterial
			local floorParams = RaycastParams.new()
			floorParams.FilterDescendantsInstances = { ctx.Character }
			floorParams.FilterType = Enum.RaycastFilterType.Exclude
			local floorHit = workspace:Raycast(rootPart.Position, Vector3.new(0, -3.5, 0), floorParams)
			if floorHit and floorHit.Normal.Y > 0.707 then
				isActuallyOnFlatGround = true
			end
		else
			isActuallyOnFlatGround = true
		end

		if isActuallyOnFlatGround then
			if _isWallRunning and (tick() - _startTime) > GROUND_GRACE then
				print(("[WallRunState] Dropped because OnGround was true (Flat floor). Time since start: %.2f"):format(tick() - _startTime))
				_stopWallRun(ctx, "On Ground")
			elseif not _isWallRunning then
				_stepsUsed = 0
				_totalDistTraveled = 0
				_distAccum = 0
			end
			-- NF-038: Do NOT return here if we are in the grace period, let the update loop run
			if not _isWallRunning then return end
		end
	end

	-- Passive wall-run activation was removed to make the mechanic more intentional.
	-- Wall runs are now only initiated via an explicit Jump press in the air (in MovementController).
end

--[[
	Called every frame from MovementController._Update while state is active.
	Handles physics maintenance (gravity, sticking, speed).
]]
function WallRunState.Update(dt: number, ctx: any)
	if not _isWallRunning then return end
	
	local rootPart = ctx.RootPart
	local humanoid = ctx.Humanoid
	if not rootPart or not humanoid then return end

	-- 1. Refresh Wall Normal (Session NF-035 Curve Support)
	-- Start slightly AWAY and UP from the wall to ensure we don't start inside geometry or hit the floor.
	local refreshParams = RaycastParams.new()
	refreshParams.FilterDescendantsInstances = { ctx.Character }
	refreshParams.FilterType = Enum.RaycastFilterType.Exclude
	
	-- NF-038: Use multiple rays to refresh the normal to prevent dropping off when hitting a seam
	local refreshOrigin = rootPart.Position + Vector3.new(0, 1.2, 0) + (_wallNormal * 1.5)
	local refreshHit = workspace:Raycast(refreshOrigin, -_wallNormal * (DETECT_DIST + 3.0), refreshParams)
	
	if not refreshHit then
		-- Try a lower ray if the top one missed
		refreshOrigin = rootPart.Position + Vector3.new(0, -0.8, 0) + (_wallNormal * 1.5)
		refreshHit = workspace:Raycast(refreshOrigin, -_wallNormal * (DETECT_DIST + 3.0), refreshParams)
	end
	
	if not refreshHit then
		-- Try a center ray
		refreshOrigin = rootPart.Position + (_wallNormal * 1.5)
		refreshHit = workspace:Raycast(refreshOrigin, -_wallNormal * (DETECT_DIST + 3.0), refreshParams)
	end

	if refreshHit and refreshHit.Normal.Y < 0.707 then
		-- NF-038: Smooth out the normal to prevent screen shake/jitter
		_wallNormal = _wallNormal:Lerp(refreshHit.Normal, math.clamp(dt * LERP_SPEED, 0, 1))
		ctx.Blackboard.WallRunNormal = _wallNormal
	else
		-- Lost the wall or surface too sloped, stop running
		print(("[WallRunState] Lost wall. Hit: %s"):format(tostring(refreshHit ~= nil)))
		_stopWallRun(ctx, "Lost Wall / Slope")
		return
	end

	-- Check max duration
	if tick() - _startTime > MAX_DURATION then
		_stopWallRun(ctx, "Time Limit")
		return
	end

	-- Drain Breath each frame
	if not ctx.DrainBreath(BREATH_WALL_DRAIN * dt) then
		_stopWallRun(ctx, "Out of Breath")
		return
	end

	-- Distance and Step counting based on distance traveled
	local currentPos = rootPart.Position
	local movedDist = (currentPos - _lastPos).Magnitude
	_distAccum += movedDist
	_totalDistTraveled += movedDist
	_lastPos = currentPos
	
	-- End run if total distance limit reached
	if _totalDistTraveled >= MAX_STUDS then
		_stopWallRun(ctx, "Dist Cap (30)")
		return
	end
	
	local maxSteps = math.floor(MAX_STEPS * (ctx.Blackboard.MomentumMultiplier or 1))

	if _distAccum >= STEP_DISTANCE then
		_stepsUsed += 1
		_distAccum -= STEP_DISTANCE
		print(("[WallRunState] Step taken (%d/%d)"):format(_stepsUsed, maxSteps))
	end

	-- End run if steps exceeded
	if _stepsUsed >= maxSteps then
		_stopWallRun(ctx, "Step Limit")
		return
	end

	-- Use a STABLE velocity base
	local baseSpeed = ctx.Humanoid.WalkSpeed 
	local runSpeed = baseSpeed * SPEED_MULT

	-- Calculate direction along the wall based on Camera/Input
	local wallRight = Vector3.new(0, 1, 0):Cross(_wallNormal).Unit
	local inputDir = ctx.MoveDir
	
	local moveDir
	if inputDir.Magnitude > 0.1 then
		local inputProj = inputDir - inputDir:Dot(_wallNormal) * _wallNormal
		if inputProj.Magnitude > 0.01 then
			moveDir = (inputProj:Dot(wallRight) > 0) and wallRight or -wallRight
		else
			moveDir = (rootPart.AssemblyLinearVelocity:Dot(wallRight) > 0) and wallRight or -wallRight
		end
	else
		moveDir = (rootPart.AssemblyLinearVelocity:Dot(wallRight) > 0) and wallRight or -wallRight
	end
	
	-- Orientation: Look in the move direction (smoothly)
	if moveDir.Magnitude > 0.1 then
		rootPart.CFrame = rootPart.CFrame:Lerp(CFrame.new(rootPart.Position, rootPart.Position + moveDir), 0.25)
	end

	-- Check for forward progress
	local runDuration = tick() - _startTime
	if runDuration > 0.2 then -- Increased grace period to allow velocity to normalize
		local speedAlongWall = rootPart.AssemblyLinearVelocity:Dot(moveDir)
		if speedAlongWall < 3 then
			-- NF-038 Debug: Print why we dropped for low speed
			print(("[WallRunState] Dropped for low speed. Speed along wall: %.2f"):format(speedAlongWall))
			_stopWallRun(ctx, "Low Speed")
			return
		end
	end

	-- NF-038: Improved Y-Axis preservation and gravity arc
	local targetY = rootPart.AssemblyLinearVelocity.Y
	local runDuration = tick() - _startTime
	
	if targetY > 0 then
		-- Preserve upward momentum for longer at start, then decay
		local decayFactor = (runDuration < 0.3) and 0.98 or 0.91
		targetY = targetY * decayFactor
		-- Cap upward speed to prevent "super-climbing"
		targetY = math.min(targetY, 12) 
	else
		-- Gradual gravity arc
		targetY = targetY - (workspace.Gravity * GRAVITY_SCALE * dt)
	end
	
	-- Wall sticking force: project normal onto flat plane to avoid vertical interference
	local stickDir = Vector3.new(-_wallNormal.X, 0, -_wallNormal.Z).Unit
	
	-- Final Velocity: (Wall Tangent * Speed) + (Wall Stick) + (Y Preservation)
	-- Stronger stick (35.0) and lower Y bias for reliability.
	rootPart.AssemblyLinearVelocity = (moveDir * runSpeed) + (stickDir * 35.0) + Vector3.new(0, targetY, 0)

	-- Check if player is holding input towards the wall
	local lateralInput = inputDir:Dot(_wallNormal)
	if lateralInput > 0.95 then -- Intentional detach (made stricter to prevent accidental detach)
		print("[WallRunState] Intentional detach triggered")
		_stopWallRun(ctx, "Intentional Detach")
	end
end

--[[
	Attempt to start a wall-run immediately (explicit user jump press).
	Returns true if a wall-run was started.
]]
function WallRunState.TryStart(ctx: any): boolean
	-- early out when feature is disabled
	if MovementConfig.DisableWallRun then return false end
	local rootPart = ctx.RootPart
	if not rootPart then return false end

	-- ── NF-038: Cooldown & Spam Prevention ───────────────────────────
	if tick() - _lastRunEndTime < REENTRY_COOLDOWN then return false end
	
	-- ── Config & Checks ──────────────────────────────────────────────
	local bb = ctx.Blackboard
	local maxSteps = math.floor(MAX_STEPS * (bb.MomentumMultiplier or 1))
	if _stepsUsed >= maxSteps then return false end

	local vel = rootPart.AssemblyLinearVelocity
	local horzSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	
	-- Requirements for manual initiation: decent speed
	-- lowered to 10 for more forgiving entry alongside walls
	if horzSpeed < MIN_ENTRY_SPEED then return false end

	-- ── Multi-directional Probe Arc ──────────────────────────────────
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { ctx.Character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	-- Directions to probe (relative to LookVector)
	-- [Angle in degrees, Priority]
	local probes = {
		{ 90,  1.1 }, { -90,  1.1 }, -- Exact sideways (High Priority)
		{ 75,  1.0 }, { -75,  1.0 }, -- Forward-side
		{ 105, 0.9 }, { -105, 0.9 }, -- Mid-side
		{ 45,  0.5 }, { -45,  0.5 }, -- Sharp forward
		{ 135, 0.3 }, { -135, 0.3 }  -- Shallow back
	}

	local upOffset = Vector3.new(0, 1.2, 0)
	local downOffset = Vector3.new(0, -0.8, 0)
	
	local firstCandidateNormal = nil
	local detectorDist = DETECT_DIST + 1.5 -- Extended reach for initiation
	
	for _, probe in ipairs(probes) do
		local angle = math.rad(probe[1])
		-- Rotate the lookVector by the angle on Y axis
		local cosA = math.cos(angle)
		local sinA = math.sin(angle)
		local look = rootPart.CFrame.LookVector
		local rayDir = Vector3.new(
			look.X * cosA - look.Z * sinA,
			0,
			look.X * sinA + look.Z * cosA
		).Unit

		-- NF-038 Debug: Draw the probes if needed
		-- print(("[WallRunState] Probing angle %d | dist %.1f"):format(probe[1], detectorDist))

		local hit = workspace:Raycast(rootPart.Position + upOffset, rayDir * detectorDist, params)
		if not hit then
			hit = workspace:Raycast(rootPart.Position + downOffset, rayDir * detectorDist, params)
		end
		-- SIDEWAYS ATTACHMENT FIX: Also probe from Center to catch walls directly beside the root
		if not hit then
			hit = workspace:Raycast(rootPart.Position, rayDir * detectorDist, params)
		end
		
		if hit then
			-- Ensure surface is vertical enough (~45 deg)
			if hit.Position.Y > (rootPart.Position.Y + 2) then
				-- Optimization: Ignore hits that are way above the character (ceilings)
				continue
			end

			-- Ensure surface is vertical enough (steeper than 60 degrees)
			if math.abs(hit.Normal.Y) < 0.5 then
				firstCandidateNormal = hit.Normal
				print(("[WallRunState] Hit wall at angle %d! Normal: %s"):format(probe[1], tostring(hit.Normal)))
				break
			end
		end
	end

	if not firstCandidateNormal then return false end
	
	-- Accept the normal and start run
	_startWallRun(firstCandidateNormal, ctx)
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
	_totalDistTraveled = 0
	_distAccum = 0
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
