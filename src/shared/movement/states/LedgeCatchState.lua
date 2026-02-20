--!strict
--[[
Class: LedgeCatchState
Description: Owns ledge-catch state, hang physics, and pull-up tweens.
Refactored for NF-034 to prioritize catching and handle wall-flush characters.

Public surface:
  TryStart(ctx)     -- checks if a ledge is catchable and initiates a hang/snap.
  CanCatch(ctx)     -- checks if a ledge is reachable without changing state.
  PullUp(ctx)       -- performs the vault-over/up onto the ledge.
  Update(dt, ctx)   -- handles safety timeouts or duration-based releases.
  Stop(ctx)         -- cleans up anchoring/state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MovementConfig = require(ReplicatedStorage.Shared.modules.MovementConfig)

-- Config constants
local HEIGHT_OFFSET = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.HeightCheckOffset) or 6.0
local REACH_WINDOW = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.ReachWindow) or 5.0
local PULL_DURATION = (MovementConfig.LedgeCatch and MovementConfig.LedgeCatch.PullUpDuration) or 0.4

-- Module-private state
local _isLedgeCatching = false
local _currentLedgeY = 0
local _catchTime = 0
local _lookDir = Vector3.new(0, 0, 1)

local LedgeCatchState = {}

-- Internal: Probes for a ledge above and ahead of the character.
-- Returns { hit, lookDir, ledgeY } or nil.
local function _probeLedge(ctx: any)
	local humanoid = ctx.Humanoid
	local rootPart = ctx.RootPart
	if not humanoid or not rootPart or not ctx.Character then return nil end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { ctx.Character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local lookDir = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
	if lookDir.Magnitude < 0.01 then return nil end
	lookDir = lookDir.Unit

	local charTopY = rootPart.Position.Y + 1.5
	local probeUp = HEIGHT_OFFSET + 0.5
	local probeDown = HEIGHT_OFFSET + 2.5

	-- Scan from close-in (0.2) to far (3.0) to catch ledges at varying distances.
	local scanDistances = { 0.2, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 3.0 }
	for _, dist in ipairs(scanDistances) do
		local probeOrigin = rootPart.Position + lookDir * dist + Vector3.new(0, probeUp, 0)

		-- Detect if there is a wall in front of the probe. If so, step just into the top surface.
		local wallHit = workspace:Raycast(rootPart.Position, lookDir * (dist + 0.5), params)
		if wallHit and wallHit.Distance < dist then
			-- We hit a wall face. We want to probe DOWN onto its top edge.
			probeOrigin = wallHit.Position + lookDir * 0.2 + Vector3.new(0, probeUp, 0)
		end

		local hitDown = workspace:Raycast(probeOrigin, Vector3.new(0, -probeDown, 0), params)
		if hitDown then
			local ledgeY = hitDown.Position.Y
			-- Reachable check: from eye level + ReachWindow down to eye level - 1.5 studs.
			-- NF-034: Lowered the min-ledge check. When climbing, the RootPart often moves 
			-- PAST the ledge level. We still want to catch if the ledge is above our feet.
			if ledgeY <= charTopY + REACH_WINDOW and ledgeY >= charTopY - 1.5 
               and ledgeY > rootPart.Position.Y - 1.0 then
				return { 
					hit = hitDown, 
					lookDir = lookDir, 
					ledgeY = ledgeY,
					edgeXZ = Vector3.new(probeOrigin.X, 0, probeOrigin.Z) 
				}
			end
		end
	end
	return nil
end

--[[
TryStart: Snaps character to hanging position on the ledge.
Returns: boolean (true if success)
]]
function LedgeCatchState.TryStart(ctx: any): boolean
	local humanoid = ctx.Humanoid
	local rootPart = ctx.RootPart
	if not humanoid or not rootPart or not ctx.Character then return false end
	if _isLedgeCatching then return false end

	-- Block if in a conflicting state.
	if ctx.Blackboard.IsVaulting or ctx.Blackboard.IsWallRunning or ctx.Blackboard.IsSliding then
		return false
	end

	local probe = _probeLedge(ctx)
	if not probe then
		return false
	end

	-- Trigger Catch
	_isLedgeCatching = true
	ctx.Blackboard.IsLedgeCatching = true
	_currentLedgeY = probe.ledgeY
	_catchTime = tick()
	_lookDir = probe.lookDir
	
	print("[LedgeCatchState] Catch success at Y=" .. tostring(math.floor(_currentLedgeY)))

	-- Stop physics and snap
	rootPart.Anchored = true
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	
	-- Position char: hands at ledge edge, body flush against wall.
	-- We move the XZ to edge - (lookDir * radius) to avoid clipping.
	local bodyOffset = _lookDir * 0.65
	local catchXZ = probe.edgeXZ - bodyOffset
	
	-- NF-034 Optimization: Check height BEFORE snapping down. 
	-- If we are already looking OVER the ledge (hands at chest level), 
	-- trigger an automatic pull-up immediately instead of hanging and dropping the player.
	local currentY = rootPart.Position.Y
	if currentY > _currentLedgeY - 1.55 then
		print("[LedgeCatchState] Hand-off high -> Auto PullUp (Y=" .. tostring(currentY) .. ")")
		-- Position at the ledge but don't drop the Y as much to keep it smooth
		local catchPos = Vector3.new(catchXZ.X, math.max(currentY, _currentLedgeY - 1.1), catchXZ.Z)
		rootPart.CFrame = CFrame.new(catchPos, catchPos + _lookDir)
		
		task.defer(function()
			-- Pass true to bypass the 0.2s duration check
			LedgeCatchState.PullUp(ctx, true) 
		end)
	else
		-- Normal hang positioning
		local catchPos = Vector3.new(catchXZ.X, _currentLedgeY - 1.5, catchXZ.Z)
		rootPart.CFrame = CFrame.new(catchPos, catchPos + _lookDir)
	end

	return true
end

--[[
CanCatch: returns (boolean, probe) for use by other states (Climb).
]]
function LedgeCatchState.CanCatch(ctx: any): (boolean, any)
	local probe = _probeLedge(ctx)
	if not probe then return false, nil end
	return true, probe
end

--[[
PullUp: Tweens the character onto the ledge top.
]]
function LedgeCatchState.PullUp(ctx: any, force: boolean?)
	local humanoid = ctx.Humanoid
	local rootPart = ctx.RootPart
	if not humanoid or not rootPart or not _isLedgeCatching then return end

	-- Prevent immediate pull-up if we just caught to avoid accidental triple-jump.
	-- We bypass this if 'force' is true (used for Auto PullUp).
	if not force and tick() - _catchTime < 0.2 then return end

	-- Target is 2.2 studs FORWARD from the body position (approx 1.5 studs past the ledge edge)
	local pullTarget = Vector3.new(
		rootPart.Position.X + _lookDir.X * 2.2,
		_currentLedgeY + (humanoid.HipHeight or 2.0) + 0.2,
		rootPart.Position.Z + _lookDir.Z * 2.2
	)

	local pullStart = rootPart.Position
	local startTime = tick()
	local conn: RBXScriptConnection

	ctx.Blackboard.IsPullingUp = true

	conn = RunService.Heartbeat:Connect(function()
		local t = math.min(1.0, (tick() - startTime) / PULL_DURATION)
		local easedT = t * t * (3 - 2 * t) -- basic smoothstep
		
		if rootPart then
			rootPart.CFrame = CFrame.new(
				pullStart:Lerp(pullTarget, easedT),
				pullTarget + _lookDir
			)
		end

		if t < 1.0 then return end
		conn:Disconnect()

		-- Finish: restore physics control and landing state
		if rootPart then 
			rootPart.Anchored = false 
			-- Stop any residual momentum from tweening to prevent the "fling"
			rootPart.AssemblyLinearVelocity = Vector3.zero 
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
		
		if humanoid then
			humanoid.PlatformStand = false
			humanoid.AutoRotate = true
			-- Explicitly land the humanoid to prevent the "stuck in jump anim"
			humanoid:ChangeState(Enum.HumanoidStateType.Landed)
		end
		
		_isLedgeCatching = false
		ctx.Blackboard.IsLedgeCatching = false
		ctx.Blackboard.IsPullingUp = false
		ctx.ChainAction() -- Successful climb-up grants momentum
		print("[LedgeCatchState] Pull-up complete")
	end)
end

function LedgeCatchState.Update(dt: number, ctx: any)
	if not _isLedgeCatching then return true end

	-- Release after 30s as a safety measure.
	if tick() - _catchTime > 30 then
		LedgeCatchState.Stop(ctx)
		return false
	end

	return true
end

--[[
Enter: Called by the dispatcher when this state becomes active.
Ensures anchoring is maintained even if the previous state's Exit tried to unanchor.
]]
function LedgeCatchState.Enter(ctx: any)
	if not _isLedgeCatching then return end
	if ctx.RootPart then
		ctx.RootPart.Anchored = true
		ctx.RootPart.AssemblyLinearVelocity = Vector3.zero
	end
	if ctx.Humanoid then
		ctx.Humanoid.PlatformStand = true
		ctx.Humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
end

function LedgeCatchState.Stop(ctx: any)
	if not _isLedgeCatching then return end
	_isLedgeCatching = false
	ctx.Blackboard.IsLedgeCatching = false
	ctx.Blackboard.IsPullingUp = false
	
	if ctx.RootPart then
		ctx.RootPart.Anchored = false
		ctx.RootPart.AssemblyLinearVelocity = Vector3.zero
	end
	if ctx.Humanoid then
		ctx.Humanoid.PlatformStand = false
		ctx.Humanoid.AutoRotate = true
		ctx.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
end

function LedgeCatchState.IsLedgeCatching(): boolean
	return _isLedgeCatching
end

return LedgeCatchState
