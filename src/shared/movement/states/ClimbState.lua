--!strict
--[[
	Class: ClimbState (scaffold)
	Description: Initial scaffold for a Deepwoken-like climbing system.

	Responsibilities (phase 1 scaffold):
	  • Expose TryStart(ctx) to attempt entering a climbing grip
	  • Maintain IsClimbing flag on the Blackboard while climbing
	  • Provide Enter/Update/Exit hooks for later implementation
	  • Provide a public IsClimbing() helper

	Notes: Full climbing (grips, stamina, ladder of handholds, dynamic movement)
	will be implemented in follow-up tasks. This scaffold wires the state into the
	MovementController so it can be iterated on safely without touching the core loop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MovementConfig = require(ReplicatedStorage.Shared.modules.MovementConfig)

-- Cache LedgeCatchState safely at module load — it may have a syntax error during development.
-- Usage sites nil-guard so climbing still works while LedgeCatch is broken.
local _ledgeCatchOk, LedgeCatchMod = pcall(require, script.Parent.LedgeCatchState)
if not _ledgeCatchOk then
	warn("[ClimbState] LedgeCatchState failed to load — ledge transitions disabled")
	LedgeCatchMod = nil
end

local ClimbState = {}

local _isClimbing = false
local _gripPoint: Vector3? = nil
local _gripNormal: Vector3? = nil
local _startGripTime = 0

local function _detectGrip(ctx: any)
	local rootPart = ctx.RootPart
	local humanoid = ctx.Humanoid
	if not rootPart or not humanoid then return nil end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { ctx.Character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local lookDir = rootPart.CFrame.LookVector * Vector3.new(1,0,1)
	if lookDir.Magnitude < 0.01 then return nil end
	lookDir = lookDir.Unit

	local offsets = { Vector3.new(0, 0.6, 0), Vector3.new(0, 1.2, 0), Vector3.new(0, -0.4, 0) }
	for _, off in ipairs(offsets) do
		local origin = rootPart.Position + off
		local hit = workspace:Raycast(origin, lookDir * MovementConfig.Climb.GripReach, params)
		if hit and math.abs(hit.Normal.Y) < 0.3 then
			return { point = hit.Position, normal = hit.Normal }
		end
	end
	return nil
end

function ClimbState.TryStart(ctx: any): boolean
	if not MovementConfig.Climb.Enabled then return false end
	if _isClimbing then return false end
	if not ctx or not ctx.RootPart or not ctx.Humanoid then return false end
	-- Don't start while grounded or during restricted states
	if ctx.OnGround or ctx.Blackboard.IsVaulting or ctx.Blackboard.IsWallRunning or ctx.Blackboard.IsSliding then return false end

	local grip = _detectGrip(ctx)
	if not grip then return false end

	-- Begin climbing grip
	_isClimbing = true
	_gripPoint = grip.point
	_gripNormal = grip.normal
	_startGripTime = tick()
	if ctx.Blackboard then ctx.Blackboard.IsClimbing = true end
	if ctx.Humanoid then ctx.Humanoid.PlatformStand = true end
	if ctx.RootPart then ctx.RootPart.Anchored = true end
	print("[ClimbState] Grip acquired — entering climb")
	return true
end

function ClimbState.Enter(_ctx: any) end

function ClimbState.Update(dt: number, ctx: any)
	if not _isClimbing or not ctx or not ctx.RootPart or not ctx.Humanoid then return end

	-- Check if we still have a grip
	local grip = _detectGrip(ctx)
	if not grip then
		-- We lost grip. Are we at a ledge?
		if LedgeCatchMod then
			local canCatch, _ = LedgeCatchMod.CanCatch(ctx)
			if canCatch then
				ClimbState.Exit(ctx)
				LedgeCatchMod.TryStart(ctx)
				return
			end
		end
		
		-- Otherwise, just fall
		ClimbState.Exit(ctx)
		return
	end

	-- Drain Breath/stamina while climbing
	local drainedOK = ctx.DrainBreath((MovementConfig.Climb.DrainRate or 12) * dt)
	if not drainedOK then
		ClimbState.Exit(ctx)
		return
	end

	-- Simple vertical movement on the wall: W = up, S = down
	local moveUp = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local moveDown = UserInputService:IsKeyDown(Enum.KeyCode.S)
	local climbVel = 0
	if moveUp then climbVel = MovementConfig.Climb.ClimbSpeed end
	if moveDown then climbVel = -MovementConfig.Climb.ClimbSpeed end

	if climbVel ~= 0 and _gripNormal then
		local root = ctx.RootPart
		-- Project a vertical move along world Y but keep horizontal offset from wall
		local targetPos = root.Position + Vector3.new(0, climbVel * dt, 0)
		-- Keep a small offset from the wall so the player doesn't intersect geometry
		local horizontalOffset = (_gripNormal and (_gripNormal.Unit * 0.6)) or Vector3.new(0,0,0)
		targetPos = Vector3.new(_gripPoint.X, targetPos.Y, _gripPoint.Z) - horizontalOffset
		root.CFrame = CFrame.new(targetPos, targetPos + (root.CFrame.LookVector * Vector3.new(1,0,1)))
	end

	-- Auto-release if grip time exceeded
	if tick() - _startGripTime > (MovementConfig.Climb.MaxGripTime or 12) then
		ClimbState.Exit(ctx)
		return
	end
end

function ClimbState.OnJumpRequest(ctx: any)
	if not _isClimbing then return end
	
	local rootPart = ctx.RootPart
	if not rootPart then return end
	
	-- Check if we can pull up onto a ledge
	if LedgeCatchMod then
		local canCatch, _ = LedgeCatchMod.CanCatch(ctx)
		if canCatch then
			ClimbState.Exit(ctx)
			LedgeCatchMod.TryStart(ctx)
			return
		end
	end
	
	-- Otherwise, jump off the wall
	if _gripNormal then
		local jumpDir = _gripNormal + Vector3.new(0, 1.5, 0)
		rootPart.AssemblyLinearVelocity = jumpDir.Unit * 45
	end
	
	ClimbState.Exit(ctx)
	if ctx.ChainAction then ctx.ChainAction() end
	print("[ClimbState] Jumped off wall")
end

function ClimbState.Exit(ctx: any)
	_isClimbing = false
	_gripPoint = nil
	_gripNormal = nil
	_startGripTime = 0
	if ctx and ctx.Blackboard then ctx.Blackboard.IsClimbing = false end
	if ctx and ctx.Humanoid then ctx.Humanoid.PlatformStand = false end
	if ctx and ctx.RootPart then ctx.RootPart.Anchored = false end
	print("[ClimbState] Exited climb")
end

function ClimbState.IsClimbing(): boolean
	return _isClimbing
end

return ClimbState