--!strict
--[[
	Class: WallBoostState
	Description: One-shot airborne wall-burst mechanic.

	When the player presses Jump while airborne with a climbable wall <=DetectDistance studs
	ahead, consumes one WallBoostsAvailable charge and launches the character with an
	upward-biased impulse off the wall normal.

	Lifecycle (one-shot pattern):
	  1. _OnJumpRequest (MovementController) calls TryStart(ctx).
	     - Raycasts for a wall.
	     - Guards: WallBoostsAvailable > 0, airborne, not in restricted state.
	     - Sets Blackboard.IsWallBoosting = true. Returns true.
	  2. _resolveActiveState sees IsWallBoosting → "WallBoost".
	  3. FSM calls Enter(ctx):
	     - Applies AssemblyLinearVelocity impulse.
	     - Drains Breath.
	     - Decrements WallBoostsAvailable.
	     - Clears IsWallBoosting = false immediately.
	  4. Next frame _resolveActiveState no longer matches → falls through to "Jump".
	  5. Landing resets WallBoostsAvailable = 1 (done in MovementController._Update).

	Dependencies: MovementConfig, workspace
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementConfig = require(ReplicatedStorage.Shared.modules.MovementConfig)

-- Config (safe fallbacks if section missing)
local CFG_ENABLED      = (MovementConfig.WallBoost and MovementConfig.WallBoost.Enabled)            ~= false
local CFG_DETECT_DIST  = (MovementConfig.WallBoost and MovementConfig.WallBoost.DetectDistance)      or 2.5
local CFG_SPEED        = (MovementConfig.WallBoost and MovementConfig.WallBoost.ImpulseSpeed)        or 45
local CFG_UPWARD_BIAS  = (MovementConfig.WallBoost and MovementConfig.WallBoost.UpwardBias)          or 1.5
local CFG_BREATH_COST  = (MovementConfig.WallBoost and MovementConfig.WallBoost.BreathCost)          or 25

-- Module-private: wall normal captured in TryStart, applied in Enter.
local _pendingWallNormal: Vector3? = nil

local WallBoostState = {}

--[[
	TryStart — called from _OnJumpRequest when airborne.
	Detects a wall directly ahead and sets up for a boost.
	Returns true if a boost was armed (Blackboard.IsWallBoosting).
]]
function WallBoostState.TryStart(ctx: any): boolean
	if not CFG_ENABLED then return false end

	local rootPart = ctx.RootPart
	local humanoid = ctx.Humanoid
	if not rootPart or not humanoid then return false end
	if ctx.OnGround then return false end

	-- State guards
	local bb = ctx.Blackboard
	if bb.WallBoostsAvailable <= 0 then return false end
	if bb.IsVaulting or bb.IsWallRunning or bb.IsSliding or bb.IsClimbing or bb.IsLedgeCatching then return false end

	-- Raycast forward for a wall
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { ctx.Character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local lookDir = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
	if lookDir.Magnitude < 0.01 then return false end
	lookDir = lookDir.Unit

	local hit = workspace:Raycast(rootPart.Position, lookDir * CFG_DETECT_DIST, params)
	if not hit then return false end

	-- Only boost off near-vertical surfaces (not floors/ceilings)
	if math.abs(hit.Normal.Y) > 0.5 then return false end

	-- Arm the boost
	_pendingWallNormal = hit.Normal
	bb.IsWallBoosting = true
	print("[WallBoostState] Boost armed — wall normal:", hit.Normal)
	return true
end

--[[
	Enter — FSM transition hook. Apply the impulse and immediately retire the state.
	This makes WallBoost a one-frame state that drops back to Jump automatically.
]]
function WallBoostState.Enter(ctx: any)
	local rootPart = ctx.RootPart
	local bb = ctx.Blackboard

	if not rootPart then
		bb.IsWallBoosting = false
		return
	end

	local wallNormal = _pendingWallNormal or Vector3.new(0, 0, 1)
	_pendingWallNormal = nil

	-- Launch: bias upward relative to wall normal
	local launchDir = (wallNormal + Vector3.new(0, CFG_UPWARD_BIAS, 0))
	launchDir = launchDir.Unit * CFG_SPEED
	rootPart.AssemblyLinearVelocity = launchDir

	-- Drain Breath (DrainBreath returns false if exhausted — we still boost)
	if ctx.DrainBreath then
		ctx.DrainBreath(CFG_BREATH_COST)
	end

	-- Consume charge
	bb.WallBoostsAvailable = math.max(0, bb.WallBoostsAvailable - 1)

	-- Immediately retire so _resolveActiveState falls through next frame
	bb.IsWallBoosting = false

	print(("[WallBoostState] Boost applied — charges left: %d"):format(bb.WallBoostsAvailable))
end

function WallBoostState.Update(_dt: number, _ctx: any) end
function WallBoostState.Exit(_ctx: any) end
function WallBoostState.OnLand(_ctx: any) end

return WallBoostState
