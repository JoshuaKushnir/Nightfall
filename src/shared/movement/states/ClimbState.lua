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
local Utils = require(ReplicatedStorage.Shared.modules.Utils)

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
	-- exclude the character and any zone-trigger parts so transparent volumes
	-- don't register as climbable walls
	local filter = { ctx.Character }
	local zoneParts = Utils.GetZoneTriggerParts()
	for _, p in ipairs(zoneParts) do
		table.insert(filter, p)
	end
	params.FilterDescendantsInstances = filter
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

	if ctx.Blackboard.IsVaulting
		or ctx.Blackboard.IsWallRunning
		or ctx.Blackboard.IsSliding
		or ctx.Blackboard.IsLedgeCatching then
		return false
	end

	-- Ledge catch always takes priority over climbing.
	-- This is the secondary check (primary is in MovementController).
	if LedgeCatchMod and LedgeCatchMod.CanCatch and LedgeCatchMod.CanCatch(ctx) then
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

	ctx.Blackboard.IsClimbing = true
	ctx.Humanoid.PlatformStand = true
	-- NOTE: RootPart is NOT anchored — anchoring bypasses Roblox collision detection
	-- when CFrame is set each frame, allowing the character to phase through geometry.
	-- Velocity-based movement in Update keeps physics collision active.
	ctx.RootPart.AssemblyLinearVelocity = Vector3.zero

	-- Snap character flush to wall (one-time initial position — CFrame ok here, no movement yet)
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
-- _tryLedgeHandoff: pull the character 1.5 studs away from the wall so that
-- LedgeCatchState._probeLedge fires its ray from OUTSIDE the wall geometry
-- (not inside it), then call TryStart.  Returns true if the hang succeeded.
-- ──────────────────────────────────────────────────────────────────────────────
local function _tryLedgeHandoff(ctx: any, capturedNormal: Vector3?): boolean
	if not LedgeCatchMod or not LedgeCatchMod.TryStart then return false end
	local root = ctx.RootPart
	if not root then return false end

	-- Temporarily nudge the character back from the wall so the downward probe
	-- origin is in open air rather than inside the wall mesh.
	if capturedNormal then
		root.CFrame = root.CFrame + capturedNormal.Unit * 1.5
	end

	-- Quick feasibility check (uses current – now pulled-back – position).
	local canCatch = LedgeCatchMod.CanCatch and LedgeCatchMod.CanCatch(ctx)
	if not canCatch then
		-- No ledge found; put character back and signal failure.
		if capturedNormal then
			root.CFrame = root.CFrame - capturedNormal.Unit * 1.5
		end
		return false
	end

	LedgeCatchMod.TryStart(ctx)
	return true
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Update: per-frame upward travel.
-- Priority each frame:
--   (1) Move upward
--   (2) Wall gone OR burst complete → pull back + try ledge hang → else pop/fall
--   (3) Breath drain
-- Mid-climb ledge detection is handled implicitly: when the wall surface ends
-- (top of the wall), _detectGrip returns nil → wallGone branch triggers and
-- _tryLedgeHandoff is called with the pull-back probe.
-- ──────────────────────────────────────────────────────────────────────────────
function ClimbState.Update(dt: number, ctx: any)
	if not _isClimbing or not ctx or not ctx.RootPart or not ctx.Humanoid then return end

	local root    = ctx.RootPart
	local targetY = (_climbTarget and _climbTarget.Y) or (root.Position.Y + 8)
	local speed   = MovementConfig.Climb.ClimbSpeed or 14

	-- (1) Move character upward while wall is present
	local grip = _detectGrip(ctx)
	-- fall back to previous grip if detection misses but the wall is still
	-- clearly there (common when the original multi-height scan briefly
	-- fails due to uneven geometry or being very close to the surface).
	if not grip and _gripNormal then
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { ctx.Character }
		params.FilterType = Enum.RaycastFilterType.Exclude
		-- cast a short straight ray into the wall using the cached normal
		local hit = workspace:Raycast(root.Position, -_gripNormal.Unit * 1.0, params)
		if hit and math.abs(hit.Normal.Y) < 0.3 then
			grip = { point = hit.Position, normal = hit.Normal }
			-- debug print could be enabled if needed
			-- print("[ClimbState] grip fallback applied")
		end
	end

	local newY: number
	if grip then
		-- Velocity-based movement: physics moves the character, collision detection applies.
		-- Direct CFrame-per-frame with Anchored=true bypassed collision and caused wall phasing.
		local remaining = targetY - root.Position.Y
		local upSpeed   = math.min(speed, math.max(0, remaining / dt))
		-- Push character gently into the wall to maintain contact as they rise.
		local wallInward = -grip.normal.Unit
		-- Rotation update only (no positional teleport — orient to face away from wall).
		local facing = Vector3.new(-grip.normal.X, 0, -grip.normal.Z)
		if facing.Magnitude > 0.01 then
			root.CFrame = CFrame.new(root.Position, root.Position + facing.Unit)
		end
		root.AssemblyLinearVelocity = Vector3.new(
			wallInward.X * 3,
			upSpeed,
			wallInward.Z * 3
		)
		newY = root.Position.Y + upSpeed * dt  -- estimate for exit threshold check
	else
		newY = root.Position.Y
	end

	-- (2) Wall surface ended (top reached) OR burst distance completed.
	--     In both cases: pull character back from wall and probe for a ledge before releasing.
	local wallGone = (grip == nil)
	local atTarget = (newY >= targetY - 0.05)

	if wallGone or atTarget then
		local capturedNormal = _gripNormal
		ClimbState.Exit(ctx)
		if _tryLedgeHandoff(ctx, capturedNormal) then
			print("[ClimbState] " .. (wallGone and "Wall top reached" or "Burst complete") .. " → ledge hang")
			return
		end
		-- No ledge above — small outward pop so the player clears the wall top
		if root and capturedNormal then
			root.AssemblyLinearVelocity = (capturedNormal + Vector3.new(0, 0.5, 0)).Unit * 12
		end
		print("[ClimbState] " .. (wallGone and "Wall lost — no ledge" or "Burst complete — no ledge") .. " — released")
		return
	end

	-- (3) Breath drain
	if not ctx.DrainBreath((MovementConfig.Climb.DrainRate or 12) * dt) then
		ClimbState.Exit(ctx)
		return
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
	if _tryLedgeHandoff(ctx, capturedNormal) then
		print("[ClimbState] Jump request -> ledge hang (pull-back probe)")
		return
	end
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
	if ctx and ctx.Humanoid   then 
		ctx.Humanoid.PlatformStand = false 
		ctx.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
	if ctx and ctx.RootPart   then 
		ctx.RootPart.AssemblyLinearVelocity = Vector3.zero
	end
	print("[ClimbState] Exited climb")
end

function ClimbState.IsClimbing(): boolean
	return _isClimbing
end

return ClimbState