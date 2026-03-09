--!strict
--[[
	Class: SlideState
	Description: Owns all slide-mechanic state and physics. Replaces the monolithic
	             _TrySlide function body; MovementController._TrySlide() delegates here.

	Private state (not exposed directly):
	  • _isSliding      — mirrors Blackboard.IsSliding; written here, read by monolith from Blackboard.
	  • _lastSlideTime  — enforces server-matched cooldown.
	  • _bodyVelocity   — the BodyVelocity driving the slide momentum.

	Public surface:
	  TryStart(ctx)        — called by MovementController on SLIDE_KEY press.
	  Update(dt, ctx)      — called by dispatcher while IsSliding (lightweight; decay runs in task.spawn).
	  OnJumpRequest(ctx)   — called by _OnJumpRequest when Blackboard.IsSliding is true.
	  Exit(ctx)            — called by dispatcher on state transition out.

	Formula: Exponential-out decay over SLIDE_DURATION. Scale by momentum multiplier.

	Dependencies: MovementConfig, RunService, AnimationLoader (via ctx)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")

local MovementConfig = require(ReplicatedStorage.Shared.modules.MovementConfig)

-- ── Config constants ──────────────────────────────────────────────────────────
local SLIDE_SPEED     = (MovementConfig.Dodge and MovementConfig.Dodge.Speed)          or 50
local SLIDE_DURATION  = (MovementConfig.Dodge and MovementConfig.Dodge.SlideDuration)  or 0.9
local SLIDE_COOLDOWN  = (MovementConfig.Dodge and MovementConfig.Dodge.Cooldown)       or 0.8
local LEAP_FORWARD    = (MovementConfig.Dodge and MovementConfig.Dodge.LeapForwardForce) or 35
local LEAP_UP         = (MovementConfig.Dodge and MovementConfig.Dodge.LeapUpForce)    or 28
local BREATH_DASH_COST = (MovementConfig.Breath and MovementConfig.Breath.DashDrainFlat) or 15

-- ── Module-private state ──────────────────────────────────────────────────────
local _isSliding    : boolean       = false
local _lastSlideTime: number        = 0
local _bodyVelocity : BodyVelocity? = nil

-- ── Internal helpers ──────────────────────────────────────────────────────────

local function _stopSlide(ctx: any)
	_isSliding = false
	ctx.Blackboard.IsSliding = false

	-- Kill BodyVelocity momentum
	if _bodyVelocity then
		_bodyVelocity.MaxForce = Vector3.zero
		_bodyVelocity:Destroy()
		_bodyVelocity = nil
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

local SlideState = {}

--[[
	Called by MovementController when the slide key (C) is pressed.
	Validates conditions and initiates the slide if eligible.
]]
function SlideState.TryStart(ctx: any)
	local humanoid = ctx.Humanoid
	local rootPart = ctx.RootPart
	if not humanoid or not rootPart then return end
	if humanoid.Health <= 0 then return end
	if not ctx.IsSprinting then
		print("[SlideState] Rejected: not sprinting")
		return
	end
	if not ctx.OnGround then
		print("[SlideState] Rejected: airborne")
		return
	end
	if tick() - _lastSlideTime < SLIDE_COOLDOWN then
		local remaining = math.floor((SLIDE_COOLDOWN - (tick() - _lastSlideTime)) * 100) / 100
		print(("[SlideState] On cooldown (%.2fs)"):format(remaining))
		return
	end
	if ctx.LastMoveDir.Magnitude < 0.5 then
		print("[SlideState] Rejected: no move direction")
		return
	end
	if _isSliding then
		print("[SlideState] Already sliding")
		return
	end

	-- ── Initiate ─────────────────────────────────────────────────────────
	_isSliding = true
	_lastSlideTime = tick()
	ctx.Blackboard.IsSliding = true
	
	-- Play slide animation (MovementController handles the main loop, but we trigger a burst here?)
	-- Actually, let MovementController handle all state animations to avoid conflicts.
	
	-- Count as a momentum chain link
	ctx.ChainAction()

	print("[SlideState] Slide started")

	-- Scale slide distance by momentum multiplier (1× at rest, up to 3× at cap)
	local momentumScale  = ctx.GetMomentumMultiplier()
	local effectiveSpeed = SLIDE_SPEED * momentumScale
	local slideDir       = ctx.LastMoveDir.Unit

	-- Create BodyVelocity for horizontal momentum
	local bv = Instance.new("BodyVelocity")
	bv.Name      = "SlideVelocity"
	bv.MaxForce  = Vector3.new(math.huge, 0, math.huge)
	bv.Velocity  = slideDir * effectiveSpeed
	bv.P         = 1500
	bv.Parent    = rootPart
	_bodyVelocity = bv

	-- Fire server validation (optimistic — server may reject)
	if ctx.NetworkController and ctx.NetworkController.SendToServer then
		ctx.NetworkController.SendToServer("RequestSlide", { Type = "Start", Timestamp = tick() })
	end

	-- ── Exponential-out decay over SLIDE_DURATION ───────────────────────────
	task.spawn(function()
		local startTime = tick()
		while _isSliding and _bodyVelocity do
			local elapsed  = tick() - startTime
			local progress = math.min(1.0, elapsed / SLIDE_DURATION)
			-- Exponential.Out: 1 - (1-p)^3
			local eased    = 1 - math.pow(1 - progress, 3)
			local speed    = effectiveSpeed * (1 - eased)

			if _bodyVelocity and speed > 0.5 then
				_bodyVelocity.Velocity = slideDir * speed
			end

			if progress >= 1.0 then break end
			RunService.Heartbeat:Wait()
		end

		-- Decay finished
		if _bodyVelocity then
			_bodyVelocity.MaxForce = Vector3.zero
			_bodyVelocity:Destroy()
			_bodyVelocity = nil
		end
		_isSliding = false
		ctx.Blackboard.IsSliding = false
		print("[SlideState] Slide momentum fully decayed")
	end)
end

--[[
	Called by the dispatcher each frame while Blackboard.IsSliding is true.
	The heavy lifting is in the task.spawn decay loop above; this is a lightweight watchdog.
]]
function SlideState.Update(_dt: number, _ctx: any)
	-- Decay runs in task.spawn; nothing extra needed per frame here.
	-- Future: particle density scaling, posture drain during slide, etc.
end

--[[
	Called by MovementController._OnJumpRequest() when Blackboard.IsSliding is true.
	Launches the character forward + upward (slide leap).
]]
function SlideState.OnJumpRequest(ctx: any)
	local rootPart = ctx.RootPart
	_stopSlide(ctx)

	-- Resolve launch direction from last move dir or look vector
	local hor: Vector3
	if ctx.LastMoveDir.Magnitude > 0.1 then
		hor = ctx.LastMoveDir.Unit
	elseif rootPart then
		hor = (rootPart.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	else
		hor = Vector3.new(0, 0, -1)
	end

	if rootPart then
		-- Bias the launch so horizontal components dominate; vertical is a fixed
		-- value rather than scaling with forward speed.
		rootPart.AssemblyLinearVelocity = Vector3.new(
			hor.X * LEAP_FORWARD,
			LEAP_UP,
			hor.Z * LEAP_FORWARD
		)
	end

	ctx.ChainAction()
	ctx.Blackboard.SlideJumped = true
	print("[SlideState] Slide leap!")
	-- Animation: MovementController stopped the slide anim before calling here;
	-- the state machine will resolve to Jump on the next frame and play that track.
	-- No separate SlideJump animation is loaded here to avoid blending conflicts.

	-- Server validation
	if ctx.NetworkController and ctx.NetworkController.SendToServer then
		ctx.NetworkController.SendToServer("RequestSlide", { Type = "Leap", Timestamp = tick() })
	end
end

--[[
	Called by the dispatcher on state transition OUT of Slide (e.g., interrupted by stun).
]]
function SlideState.Exit(ctx: any)
	if _isSliding then
		_stopSlide(ctx)
		print("[SlideState] Forcibly exited")
	end
end

--[[
	Readable from outside (e.g., for unit tests or GetMomentumMultiplier context).
]]
function SlideState.IsSliding(): boolean
	return _isSliding
end

return SlideState
