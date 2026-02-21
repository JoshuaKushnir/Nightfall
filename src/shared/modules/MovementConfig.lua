--[[
	MovementConfig.lua
	
	Centralized configuration for all movement-related constants.
	Adjust these values to tune the feel of movement, dodge, and camera effects.
]]

local MovementConfig = {}

-- Base movement speeds and acceleration
MovementConfig.Movement = {
	WalkSpeed = 12, -- studs per second
	SprintSpeed = 20, -- studs per second
	LungeSpeed = 45, -- studs per second for sprint->attack lunge (configurable)
	Acceleration = 45, -- studs/s^2 when speeding up
	Deceleration = 55, -- studs/s^2 when slowing down
	
	-- Direction smoothing (spring-based)
	DirectionSmoothFrequency = 15, -- Hz - higher = more responsive, lower = smoother
	DirectionDampingRatio = 0.8, -- 0-1 - higher = less overshoot, lower = more bounce
	
	-- Jump mechanics
	CoyoteTime = 0.12, -- seconds to allow jump after leaving ground
	JumpBufferTime = 0.15, -- seconds to buffer jump before landing
	
	-- Input
	SprintKey = Enum.KeyCode.LeftShift,
}

-- Dodge/roll mechanics
MovementConfig.Dodge = {
	Speed = 50, -- studs per second (initial velocity)
	Duration = 0.5, -- dodge duration (seconds)
	SlideDuration = 1.2, -- slide duration (seconds)
	Cooldown = 1.5, -- seconds (increased to reduce instant chaining)
	
	-- Slide-jump landing: grace window to resume sprint if movement input is held
	LandingSprintGraceWindow = 0.15, -- seconds
	
	-- Velocity decay (for smooth slowdown)
	DecayEasing = Enum.EasingStyle.Exponential,
	DecayDirection = Enum.EasingDirection.Out,
	
	-- Force parameters (no longer using BodyVelocity, kept for reference)
	MaxForce = 25000, -- legacy value

	-- Slide leap: jump pressed during an active slide
	LeapForwardForce = 35, -- horizontal launch speed (studs/s)
	LeapUpForce = 28,      -- vertical launch speed (studs/s)
}

-- Camera effects configuration
MovementConfig.Camera = {
	-- Camera shake (spring-based trauma system)
	--ShakeFrequency = 25, -- Hz - oscillation speed
	ShakeDampingRatio = 0.7, -- 0-1 - controls decay
	ShakeTraumaDecay = 2.0, -- trauma units per second
	
	-- Trauma amounts per action type
	LightAttackTrauma = 0.2,
	HeavyAttackTrauma = 0.4,
	ParryTrauma = 0.3,
	DodgeTrauma = 0.15,
	HitReceivedTrauma = 0.5,
	
	-- FOV punch effects
	FOVPunchEnabled = false, -- disable FOV punch/zoom by default (toggleable)
	--DodgeFOVIncrease = 8, -- degrees
	--HeavyAttackFOVDecrease = 5, -- degrees
	FOVPunchDuration = 0.3, -- seconds
	FOVPunchEasing = Enum.EasingStyle.Exponential,
	FOVPunchDirection = Enum.EasingDirection.Out,
	DefaultFOV = 70, -- base field of view
}

-- Hit-stop/freeze frame effects
MovementConfig.HitStop = {
	-- Time scale approach (multiplier for animation speeds)
	TimeScale = 0.1, -- 0-1, how slow things get during hit-stop
	
	-- Durations per action
	LightAttackDuration = 0.05, -- seconds
	HeavyAttackDuration = 0.1, -- seconds
	ParryDuration = 0.08, -- seconds
	CriticalHitDuration = 0.15, -- seconds
}

-- Audio configuration
MovementConfig.Audio = {
	FootstepInterval = 3, -- studs traveled between footsteps
	FootstepVolumeWalk = 0.3, -- 0-1
	FootstepVolumeSprint = 0.6, -- 0-1
	
	-- Material sound mappings (asset IDs to be filled in)
	MaterialSounds = {
		[Enum.Material.Grass] = "rbxasset://sounds/walk_grass.ogg",
		[Enum.Material.Concrete] = "rbxasset://sounds/walk_stone.ogg",
		[Enum.Material.Metal] = "rbxasset://sounds/walk_metal.ogg",
		[Enum.Material.Wood] = "rbxasset://sounds/walk_wood.ogg",
		-- Add more materials as needed
	},
}

-- Breath resource system (Issue #95)
-- Drain rates per action; regen fastest when grounded + stationary.
-- All values are TBD tuning numbers — change here, re-test in Roblox.
MovementConfig.Breath = {
	Pool = 100,                -- maximum Breath units
	RegenRateStationary = 25,  -- /sec — grounded and not moving
	RegenRateMoving = 12,      -- /sec — grounded and moving
	-- No regen while airborne.
	SprintDrainRate = 10,      -- /sec — sustained sprint cost
	DashDrainFlat = 15,        -- flat cost per dash / slide use
	WallRunDrainRate = 20,     -- /sec — fastest drain (wall-run)
	-- Stumble animation fires on Breath reaching 0 (asset: TODO — ref #95)
}

-- Momentum multiplier (Issue #95)
-- Accumulates by chaining movement actions; cap confirmed at 3×.
-- Ramp curve is linear (ChainGainPerAction added per chained action).
MovementConfig.Momentum = {
	Cap = 3.0,                  -- confirmed maximum multiplier
	CombatCap = 1.5,                -- separate cap for combat bonus (auto goes down when put in combat)
	ChainGainPerAction = 0.4,   -- multiplier added per chained movement action
	ChainWindowSec = 1.5,       -- seconds of inactivity before chain breaks
	DecayRatePerSec = 2.0,      -- multiplier/sec lost after chain breaks
	-- Effects at >1× (full bonus at Cap):
	--   Dash/slide distance  ×Cap
	--   Jump height          +JumpHeightBonus at Cap
	--   Forward melee bonus  exposed via GetMomentumMultiplier() → CombatService
	JumpHeightBonus = 0.25,     -- fraction of base JumpHeight added at 3×
}

-- Wall-run (Issue #95)
-- Overhauled for speed and verticality (Session NF-035)
MovementConfig.WallRun = {
	MaxSteps = 5,               
	MinEntrySpeed = 8,          -- Lowered from 12: more lenient entry speed
	MaxDuration = 5.0,          
	WallDetectDistance = 5.5,
	-- temporarily disable wall-running for repro/testing
	DisableWallRun = false,   -- Increased from 4.5: wider catch window
	GravityScale = 0.12,        
	SpeedMultiplier = 1.05,
	
		-- NF-038: Polish & Prevention 
	ReentryCooldown  = 0.4,     -- seconds before player can wall-run again (prevents upward spamming)
	NormalLerpSpeed  = 10,      -- speed for smoothing wall normals (prevents screen shake)
	MaxStuds         = 30,      -- absolute cap on wall-run distance
	GroundedGrace    = 0.15,    -- seconds to ignore OnGround after starting (prevents initial dropout)
}

-- Vault (Issue #95)
MovementConfig.Vault = {
	MaxObstacleHeight = 5.5,       -- studs — tallest obstacle to vault
	MinObstacleHeight = 1.5,       -- studs — ignore tiny bumps below this
	ForwardDetectDistance = 3.5,   -- studs ahead to raycast (wider vault window)
	Duration = 0.40,               -- seconds for vault tween (smoother)
	MomentumPreservePct = 0.85,    -- fraction of sprint speed kept after vault
	Cooldown = 1.0,                -- seconds before another vault can trigger
}

-- Ledge catch (Issue #95)
-- Auto-triggers when player is falling and near a ledge edge.
MovementConfig.LedgeCatch = {
	ForwardDetectDistance = 2.8,   -- studs ahead to probe
	-- Probe starts this many studs above the RootPart so it can detect ledges
	-- that are up to a full character-height above the player.
	HeightCheckOffset = 6.0,       -- was 2.5; raised so probe clears ledges above the head
	-- Vertical offset from detected ledge Y to the character's hang/snap position.
	-- Smaller values mean the character hangs higher (closer to the ledge).
	HangOffset = 2.3,              -- tunable: default moved slightly up from 2.8 → 2.5
	HangDuration = 0.6,            -- seconds for internal timing (hang exits via Space only)
	PullUpDuration = 0.4,          -- seconds for pull-up tween
	TriggerFallSpeed = -6,         -- velocity.Y threshold (negative = falling)
	-- Ledge must be within root+1.5 to root+1.5+ReachWindow studs.
	-- 5.0 ≈ one full character height of reach above the head.
	ReachWindow = 5.0,             -- was 3.0; wider vertical window for catching
}

-- Climbing (phase‑1 defaults)
MovementConfig.Climb = {
	Enabled       = true,
	GripReach     = 2.2,    -- studs: forward raycast to detect a climbable wall
	-- increased height & velocity per user request
	ClimbDistance = 12,     -- studs: fixed upward burst distance per Space press (was 8)
	ClimbSpeed    = 20,     -- studs/s: travel speed of the upward burst (~0.6 s for 12 studs)
	DrainRate     = 12,     -- Breath units / sec drained while climbing
	MaxGripTime   = 12,     -- seconds maximum before forced release (safety valve)
}

-- Wall Boost (one-shot airborne wall burst)
MovementConfig.WallBoost = {
	Enabled            = true,
	DetectDistance     = 2.5,   -- studs: max distance to wall for a boost to trigger
	ImpulseSpeed       = 32,    -- tuned down from 45 (reduced "fling" effect)
	UpwardBias         = 1.4,   -- slightly less vertical launch
	BreathCost         = 25,    -- Breath units drained per boost
	BoostsPerGrounding = 1,     -- charges refilled on landing
	BoostDuration      = 0.30,  -- tuned down from 0.35s
}

-- Particle effects
MovementConfig.Particles = {
	-- Sprint dust trail
	SprintParticlesEnabled = true,
	SprintParticleRate = 20, -- particles per second
	SprintParticleLifetime = 0.5, -- seconds
	SprintParticleSize = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0)
	}),
	SprintParticleTransparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	}),
	
	-- Dodge burst effect
	DodgeParticlesEnabled = true,
	DodgeBurstCount = 10, -- particles emitted on dodge
	DodgeParticleLifetime = 0.3, -- seconds
}

return MovementConfig
