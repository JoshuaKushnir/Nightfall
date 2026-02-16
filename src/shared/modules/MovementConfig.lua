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
	Duration = 0.5, -- seconds
	Cooldown = 0.8, -- seconds
	
	-- Velocity decay (for smooth slowdown)
	DecayEasing = Enum.EasingStyle.Exponential,
	DecayDirection = Enum.EasingDirection.Out,
	
	-- Force parameters (no longer using BodyVelocity, kept for reference)
	MaxForce = 25000, -- legacy value
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
	FOVPunchEnabled = true,
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
