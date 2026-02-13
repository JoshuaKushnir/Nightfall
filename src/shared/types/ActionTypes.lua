--!strict
--[[
	ActionTypes.lua
	
	Issue #8: Action Controller (Animation & Feel)
	Epic: Phase 2 - Combat & Fluidity
	
	Type definitions for combat actions with animations, hit-stop, and game feel.
]]

export type ActionType = "Attack" | "Ability" | "Skill" | "Dodge" | "Parry" | "Block"

export type ActionConfig = {
	-- Identity
	Id: string,
	Name: string,
	Type: ActionType,
	
	-- Animation
	AnimationId: string,
	AnimationSpeed: number?,
	AnimationPriority: Enum.AnimationPriority?,
	CanQueueWhile: {string}?, -- Animation names that allow queueing during them
	Interruptible: boolean?,
	
	-- Timing
	Duration: number, -- Total action duration
	HitStartFrame: number?, -- Frame when hit occurs (0-1)
	HitStopDuration: number?, -- Freeze time on hit
	
	-- Game Feel
	CameraShake: number?, -- Trauma amount (0-1)
	SoundId: string?, -- Sound effect
	VfxId: string?, -- VFX effect
	VfxAttachPoint: string?, -- Bone to attach VFX
	
	-- Server Validation
	Cooldown: number?, -- Seconds between uses
	RequiredState: string?, -- Required player state
	RequiredResource: string?, -- Mantra, energy, etc
	ResourceCost: number?,
	
	-- Callbacks
	OnStart: ((player: Player) -> ())?,
	OnHit: ((player: Player, target: Player) -> ())?,
	OnComplete: ((player: Player) -> ())?,
}

export type Action = {
	Config: ActionConfig,
	StartTime: number,
	EndTime: number,
	IsActive: boolean,
	TargetHit: Player?,
	AnimationTrack: AnimationTrack?,
	
	-- Methods
	Play: (self: Action) -> (),
	Stop: (self: Action) -> (),
	OnFrame: (self: Action, deltaTime: number) -> (),
	Cleanup: (self: Action) -> (),
}

-- Predefined action configs
local ATTACK_LIGHT: ActionConfig = {
	Id = "atk_light",
	Name = "Light Attack",
	Type = "Attack",
	AnimationId = "rbxassetid://12345678",
	AnimationSpeed = 1.0,
	Duration = 0.6,
	HitStartFrame = 0.3,
	HitStopDuration = 0.1,
	CameraShake = 0.3,
	SoundId = "rbxassetid://12345679",
	Cooldown = 0.5,
	RequiredState = "Idle",
}

local ATTACK_HEAVY: ActionConfig = {
	Id = "atk_heavy",
	Name = "Heavy Attack",
	Type = "Attack",
	AnimationId = "rbxassetid://12345680",
	AnimationSpeed = 0.8,
	Duration = 1.2,
	HitStartFrame = 0.5,
	HitStopDuration = 0.15,
	CameraShake = 0.6,
	SoundId = "rbxassetid://12345681",
	Cooldown = 1.0,
	RequiredState = "Idle",
}

local DODGE: ActionConfig = {
	Id = "dodge",
	Name = "Dodge",
	Type = "Dodge",
	AnimationId = "rbxassetid://12345682",
	AnimationSpeed = 1.2,
	Duration = 0.5,
	CameraShake = 0.1,
	Cooldown = 0.3,
	RequiredState = "Idle",
}

return {
	ATTACK_LIGHT = ATTACK_LIGHT,
	ATTACK_HEAVY = ATTACK_HEAVY,
	DODGE = DODGE,
}
