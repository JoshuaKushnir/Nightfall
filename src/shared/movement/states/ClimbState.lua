--!strict
--[[
	Class: ClimbState
	Description: Single-burst wall climb triggered by Space while airborne near a wall.

	Behaviour:
	  • TryStart    — detects a near-vertical wall ahead, anchors the character and
	                  records a target position ~ClimbDistance studs above the current Y.
	  • Update      — every frame: checks for a catchable ledge first (auto-hangs if found),
	                  then slides the character upward toward the target at ClimbSpeed studs/s.
	                  Exits cleanly if the wall vanishes or the target is reached.
	  • OnJumpRequest — while climbing, Space jumps the player off the wall (0.25 s anti-bounce).
	  • Exit        — restores PlatformStand / Anchored and clears all state.

	Activation: Space (JumpRequest) while airborne, checked AFTER ledge-catch probe in controller.
	Auto-ledge: if LedgeCatchState.CanCatch() is true mid-climb, exit and call LedgeCatch.TryStart.

	Dependencies: MovementConfig (Climb table), LedgeCatchState
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Shared.modules.MovementConfig)

-- Cache LedgeCatchState safely — syntax errors during dev must not break climbing.
local _ledgeCatchOk, LedgeCatchMod = pcall(require, script.Parent.LedgeCatchState)
if not _ledgeCatchOk then
	warn("[ClimbState] LedgeCatchState failed to load — auto-ledge disabled. " .. tostring(LedgeCatchMod))
	LedgeCatchMod = nil
end

local ClimbState = {}

-- Module-private state
local _isClimbing             = false
local _gripPoint: Vector3?    = nil
local _gripNormal: Vector3?   = nil
local _climbTarget: Vector3?  = nil   -- world Y we're rising toward
local _startGripTime          = 0

-- ──────────────────────────────────────────────────────────────────────────────
-- Internal: multi-height wall probe. Scans at three heights so the grip fires
-- whether the player is rising or falling past the wall.
-- ──────────────────────────────────────────────────────────────────────────────
local function _detectGrip(ctx: any)
	local rootPart = ctx.RootPart
	if not rootPart then return nil end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { ctx.Character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local lookDir = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
	if lookDir.Magnitude < 0.01 then return nil end
	lookDir = lookDir.Unit

	local offsets = {
		Vector3.new(0,  0.6, 0),   -- chest
		Vector3.new(0,  1.2, 0),   -- head
		Vector3.new(0, -0.4, 0),   -- hip
	}
	for _, off in ipairs(offsets) do
		local origin = rootPart.Position + off
		local hit = workspace:Raycast(origin, lookDir * MovementConfig.Climb.GripReach, params)
		if hit and math.abs(hit.Normal.Y) < 0.3 then   -- near-vertical surface only
			return { point = hit.Position, normal = hit.Normal }
		end
	end
	return nil
end

-- ──────────────────────────────────────────────────────────────────────────────
-- TryStart: called from _OnJumpRequest while airborne, AFTER the ledge-catch check.
-- ──────────────────────────────────────────────────────────────────────────────
function ClimbState.TryStart(ctx: any): boolean
	if not MovementConfig.Climb.Enabled then return false end
	if _isClimbing then return false end
	if not ctx or not ctx.RootPart or not ctx.Humanoid then return false end

	if ctx.OnGround
		or ctx.Blackboard.IsVaulting
		or ctx.Blackboard.IsWallRunning
		or ctx.Blackboard.IsSliding
		or ctx.Blackboard.IsLedgeCatching then
		return false
	end

	local grip = _detectGrip(ctx)
	if not grip then return false end

	local climbDist = MovementConfig.Climb.ClimbDistance or 8
	local startPos  = ctx.RootPart.Position

	_isClimbing    = true
	_gripPoint     = grip.point
	_gripNormal    = grip.normal
	_startGripTime = tick()
	_climbTarget   = Vector3.new(grip.point.X, startPos.Y + climbDist, grip.point.Z)

	ctx.Blackboard.IsClimbing           = true
	ctx.Humanoid.PlatformStand          = true
	ctx.RootPart.Anchored               = true
	ctx.RootPart.AssemblyLinearVelocity = Vector3.zero

	-- Snap character flush to wall (normal points toward player, add it to stay off surface)
	local offset     = grip.normal.Unit * 0.6
	local wallFacing = Vector3.new(-grip.normal.X, 0, -grip.normal.Z)
	if wallFacing.Magnitude > 0.01 then
		local snapBase = Vector3.new(grip.point.X, startPos.Y, grip.point.Z) + offset
		ctx.RootPart.CFrame = CFrame.new(snapBase, snapBase + wallFacing.Unit)
	end

	print("[ClimbState] Burst climb started — target +" .. tostring(climbDist) .. " studs")
	return true
end

function ClimbState.Enter(_ctx: any) end

-- ──────────────────────────────────────────────────────────────────────────────
-- Update: per-frame upward travel.
-- Priority each frame:
--   (1) Ledge found mid-climb   → auto-hang (LedgeCatchState.TryStart)
--   (2) Wall disappeared        → release (character falls)
--   (3) Breath drained          → release
--   (4) Move upward / at target → tiny pop + release
-- ──────────────────────────────────────────────────────────────────────────────
function ClimbState.Update(dt: number, ctx: any)
	if not _isClimbing or not ctx or not ctx.RootPart or not ctx.Humanoid then return end

	local root = ctx.RootPart

	-- (1) Auto-hang if a ledge becomes reachable during the upward burst
	if LedgeCatchMod and LedgeCatchMod.CanCatch then
		local canCatch = LedgeCatchMod.CanCatch(ctx)
		if canCatch then
			print("[ClimbState] Ledge reached mid-climb — handing off to LedgeCatchState")
			ClimbState.Exit(ctx)
			LedgeCatchMod.TryStart(ctx)
			return
		end
	end

	-- (2) Re-confirm the wall is still there
	local grip = _detectGrip(ctx)
	if not grip then
		print("[ClimbState] Wall lost — releasing")
		ClimbState.Exit(ctx)
		return
	end

	-- (3) Breath drain
	if not ctx.DrainBreath((MovementConfig.Climb.DrainRate or 12) * dt) then
		ClimbState.Exit(ctx)
		return
	end

	-- (4) Slide upward toward target
	local targetY = (_climbTarget and _climbTarget.Y) or (root.Position.Y + 8)
	local speed   = MovementConfig.Climb.ClimbSpeed or 8
	local newY    = math.min(root.Position.Y + speed * dt, targetY)
	local offset  = grip.normal.Unit * 0.6
	local newPos  = Vector3.new(grip.point.X, newY, grip.point.Z) + offset
	local facing  = Vector3.new(-grip.normal.X, 0, -grip.normal.Z)

	root.CFrame = CFrame.new(newPos, newPos + facing.Unit)

	-- Reached the burst target — tiny pop upward and release
	if newY >= targetY - 0.05 then
		local capturedNormal = _gripNormal
		ClimbState.Exit(ctx)
		if root and capturedNormal then
			root.AssemblyLinearVelocity = (capturedNormal + Vector3.new(0, 0.5, 0)).Unit * 12
		end
		print("[ClimbState] Burst complete")
	end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- OnJumpRequest: Space while climbing → prefer hang if ledge reachable, else jump off.
-- 0.25 s guard prevents the activating press from immediately triggering this.
-- ──────────────────────────────────────────────────────────────────────────────
function ClimbState.OnJumpRequest(ctx: any)
	if not _isClimbing then return end
	if tick() - _startGripTime < 0.25 then return end

	local rootPart = ctx.RootPart
	if not rootPart then return end

	-- Prefer ledge hang over wall-jump
	if LedgeCatchMod and LedgeCatchMod.CanCatch then
		local canCatch = LedgeCatchMod.CanCatch(ctx)
		if canCatch then
			ClimbState.Exit(ctx)
			LedgeCatchMod.TryStart(ctx)
			return
		end
	end

	local capturedNormal = _gripNormal
	ClimbState.Exit(ctx)
	if rootPart and capturedNormal then
		rootPart.AssemblyLinearVelocity = (capturedNormal + Vector3.new(0, 1.5, 0)).Unit * 45
	end
	if ctx.ChainAction then ctx.ChainAction() end
	print("[ClimbState] Jumped off wall")
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Exit: restore physics and clear all module state.
-- ──────────────────────────────────────────────────────────────────────────────
function ClimbState.Exit(ctx: any)
	_isClimbing    = false
	_gripPoint     = nil
	_gripNormal    = nil
	_climbTarget   = nil
	_startGripTime = 0
	if ctx and ctx.Blackboard then ctx.Blackboard.IsClimbing = false end
	if ctx and ctx.Humanoid   then ctx.Humanoid.PlatformStand = false end
	if ctx and ctx.RootPart   then ctx.RootPart.Anchored = false end
	print("[ClimbState] Exited climb")
end

function ClimbState.IsClimbing(): boolean
	return _isClimbing
end

return ClimbState