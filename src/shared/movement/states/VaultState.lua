--!strict
--[[
	Class: VaultState
	Description: Owns all vault-mechanic state and physics. Replaces the monolithic TryVault body.

	The vault is a short, async lerp over an obstacle. It uses PlatformStand to take control of the
	Humanoid and tween the RootPart CFrame, then releases control and preserves momentum.

	Private state:
	  • _isVaulting   — mirrors Blackboard.IsVaulting.
	  • _lastVaultTime — enforces per-vault cooldown.

	Public surface:
	  TryStart(ctx)    — called by MovementController._Update() every frame when not restricted.
	                     Runs a raycast probe; starts vault if conditions are met.
	  Update(dt, ctx)  — lightweight; vault lerp runs inside task.spawn logic inside TryStart.
	  Exit(ctx)        — dispatcher-triggered forced exit (interrupts active vault).

	Dependencies: MovementConfig, RunService, workspace
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")

local MovementConfig = require(ReplicatedStorage.Shared.modules.utility.MovementConfig)

-- ── Config constants ──────────────────────────────────────────────────────────
local MAX_HEIGHT    = (MovementConfig.Vault and MovementConfig.Vault.MaxObstacleHeight)     or 5.5
local MIN_HEIGHT    = (MovementConfig.Vault and MovementConfig.Vault.MinObstacleHeight)     or 1.5
local FORWARD_DIST  = (MovementConfig.Vault and MovementConfig.Vault.ForwardDetectDistance) or 2.5
local DURATION      = (MovementConfig.Vault and MovementConfig.Vault.Duration)              or 0.35
local MOMENTUM_KEEP = (MovementConfig.Vault and MovementConfig.Vault.MomentumPreservePct)   or 0.85
local VAULT_COOLDOWN= (MovementConfig.Vault and MovementConfig.Vault.Cooldown)              or 1.0

-- ── Module-private state ──────────────────────────────────────────────────────
local _isVaulting    : boolean = false
local _lastVaultTime : number  = 0

-- Running speed at vault moment (captured for momentum restore)
local _capturedSpeed : number  = 0

-- ── Public API ────────────────────────────────────────────────────────────────

local VaultState = {}

--[[
	Called every frame from MovementController when movement is not restricted.
	Runs a forward raycast to detect a low obstacle, then checks clearance above it.
]]
function VaultState.TryStart(ctx: any, probeDistOverride: number?)
	local humanoid = ctx.Humanoid
	local rootPart = ctx.RootPart
	if not humanoid or not rootPart or not ctx.Character then return end
	if _isVaulting then return end
	if not ctx.IsSprinting then return end
	if not ctx.OnGround then return end
	if tick() - _lastVaultTime < VAULT_COOLDOWN then return end
	if ctx.Blackboard.IsSliding or ctx.Blackboard.IsLedgeCatching or ctx.Blackboard.IsWallRunning then return end

	local lookDir = rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
	if lookDir.Magnitude < 0.01 then return end
	lookDir = lookDir.Unit

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { ctx.Character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local forwardCheckDist = probeDistOverride or FORWARD_DIST
	local hitForward = workspace:Raycast(rootPart.Position, lookDir * forwardCheckDist, params)
	if not hitForward then return end

	local hipHeightEstimate = (humanoid and humanoid.HipHeight) or 2.0
	local groundY           = rootPart.Position.Y - hipHeightEstimate

	-- Find the top of the obstacle
	local topCheckOrigin = hitForward.Position + lookDir * 0.1 + Vector3.new(0, MAX_HEIGHT + 2, 0)
	local topHit = workspace:Raycast(topCheckOrigin, Vector3.new(0, -(MAX_HEIGHT + 4), 0), params)
	if not topHit then return end

	local obstacleRelHeight = topHit.Position.Y - groundY
	if obstacleRelHeight < MIN_HEIGHT or obstacleRelHeight > MAX_HEIGHT then return end

	-- Confirm head clearance above the obstacle
	local headroomCheck = workspace:Raycast(topHit.Position, Vector3.new(0, 5, 0), params)
	if headroomCheck then return end -- no headroom

	-- Determine landing spot. Check past the obstacle (e.g., 2.5 studs forward from hit)
	local pastObstacleOrigin = hitForward.Position + lookDir * 2.5 + Vector3.new(0, MAX_HEIGHT + 2, 0)
	local landingHit = workspace:Raycast(pastObstacleOrigin, Vector3.new(0, -(MAX_HEIGHT + 6), 0), params)

	local targetPos
	if landingHit and landingHit.Position.Y < topHit.Position.Y - 0.5 then
		-- The obstacle is thin, we can land on the ground past it
		targetPos = landingHit.Position + Vector3.new(0, hipHeightEstimate + 0.5, 0)
	else
		-- The obstacle is deep/wide, land on top of it
		-- Check if there's a wall on top of the obstacle
		local wallCheck = workspace:Raycast(topHit.Position + Vector3.new(0, 1, 0), lookDir * 1.5, params)
		local forwardDist = wallCheck and math.max(0, wallCheck.Distance - 0.5) or 1.5
		targetPos = topHit.Position + lookDir * forwardDist + Vector3.new(0, hipHeightEstimate + 0.5, 0)
	end

	-- ── Execute vault ─────────────────────────────────────────────────────
	_isVaulting    = true
	_lastVaultTime = tick()
	ctx.Blackboard.IsVaulting = true
	-- Capture current speed for momentum restore
	_capturedSpeed = ctx.Blackboard.CurrentSpeed

	print(("[VaultState] Vaulting obstacle at %.1f studs height"):format(obstacleRelHeight))

	local startCF   = rootPart.CFrame
	local targetCF = CFrame.new(targetPos, targetPos + lookDir)

	humanoid.PlatformStand = true
	rootPart.AssemblyLinearVelocity = Vector3.zero

	local vaultStart = tick()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local t      = math.min(1.0, (tick() - vaultStart) / DURATION)
		local easedT = 1 - math.pow(1 - t, 2) -- ease-out quad
		if rootPart then
			rootPart.CFrame = startCF:Lerp(targetCF, easedT)
		end
		if t < 1.0 then return end

		conn:Disconnect()
		if humanoid then
			humanoid.PlatformStand = false
		end
		-- Restore forward momentum
		if rootPart then
			rootPart.AssemblyLinearVelocity = lookDir * (_capturedSpeed * MOMENTUM_KEEP)
		end
		_isVaulting = false
		ctx.Blackboard.IsVaulting = false
		ctx.ChainAction()
		print("[VaultState] Vault complete")
	end)
	-- Signal to caller that the vault was successfully initiated (blocks default jump)
	return true
end

function VaultState.Update(_dt: number, _ctx: any)
	-- Vault lerp runs in RunService.Heartbeat inside TryStart's task.spawn-equivalent (conn).
end

function VaultState.Enter(_ctx: any) end

function VaultState.Exit(ctx: any)
	if _isVaulting then
		-- Forced exit: release platform stand if held
		if ctx.Humanoid then
			ctx.Humanoid.PlatformStand = false
			ctx.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
		if ctx.RootPart then
			ctx.RootPart.Anchored = false
			ctx.RootPart.AssemblyLinearVelocity = Vector3.zero
		end
		_isVaulting = false
		ctx.Blackboard.IsVaulting = false
		print("[VaultState] Forcibly exited")
	end
end

function VaultState.IsVaulting(): boolean
	return _isVaulting
end

return VaultState
