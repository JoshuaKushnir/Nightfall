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

	-- Animation (use project folder when set; otherwise AnimationId)
	AnimationId: string,
	AnimationName: string?, -- Folder name under Shared.animations (e.g. "Front Roll")
	AnimationAssetName: string?, -- Optional asset name under AnimSaves (e.g. "BackRoll")
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

	-- Combo System
	IsFinisher: boolean?, -- True if this is the final hit in a combo
	KnockbackPower: number?, -- Knockback force applied on hit
	CancelFrame: number?,   -- Fraction of Duration after which a queued action can interrupt (e.g. 0.55)
	AttackImpulse: number?, -- Brief forward studs/s nudge applied at swing start (non-lunge attacks)

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
	Hitbox: any?, -- HitboxTypes.Hitbox (can't import due to circular dep)

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
	AnimationId = "",
	AnimationName = "Fists",
	AnimationAssetName = "punch 1",
	AnimationSpeed = 1.0,   -- matched to 0.6s base cooldown
	Duration = 0.6,         -- base cooldown
	HitStartFrame = 0.4,
	HitStopDuration = 0.07, -- shorter freeze on contact
	CancelFrame = 0.85,     -- can chain next hit at 85% of duration (~0.51 s)
	AttackImpulse = 14,     -- small forward nudge per swing
	CameraShake = 0.3,
	SoundId = "rbxassetid://12345679",
	Cooldown = 0.3,
	RequiredState = "Idle",
}

local ATTACK_HEAVY: ActionConfig = {
	Id = "atk_heavy",
	Name = "Heavy Attack",
	Type = "Attack",
	AnimationId = "",
	AnimationName = "Fists",
	AnimationAssetName = "punch 5",
	AnimationSpeed = 1.0,
	Duration = 0.9,         -- was 1.2; still a commitment but less punishing
	HitStartFrame = 0.45,
	HitStopDuration = 0.12,
	CancelFrame = 0.65,     -- can cancel into a dodge/combo at 65% (~0.59 s)
	AttackImpulse = 10,
	CameraShake = 0.6,
	SoundId = "rbxassetid://12345681",
	Cooldown = 0.6,
	RequiredState = "Idle",
}

local DODGE: ActionConfig = {
	Id = "dodge",
	Name = "Dodge",
	Type = "Dodge",
	AnimationId = "",
	AnimationName = "FrontRoll",
	AnimationAssetName = "FrontRoll",
	AnimationSpeed = 1.2,
	Duration = 0.35,
	CameraShake = 0.1,
	Cooldown = 0.8, -- Prevent spam dodging
	RequiredState = "Idle",
}

local BLOCK: ActionConfig = {
	Id = "block",
	Name = "Block",
	Type = "Block",
	AnimationId = "",
	AnimationName = "Fists",
	AnimationAssetName = "BlockIdle",
	AnimationSpeed = 1.0,
	Duration = 999, -- Held until released
	CameraShake = 0,
	Cooldown = 0.1,
	RequiredState = "Idle",
	Interruptible = true,
}

local PARRY: ActionConfig = {
	Id = "parry",
	Name = "Parry",
	Type = "Parry",
	AnimationId = "",
	AnimationName = "FrontRoll",
	AnimationAssetName = "FrontRoll",
	AnimationSpeed = 1.5,
	Duration = 0.19, -- Quick parry window
	HitStartFrame = 0.1,
	HitStopDuration = 0.05,
	CameraShake = 0.2,
	SoundId = "rbxassetid://12345685",
	Cooldown = 0.5,
	RequiredState = "Idle",
}

local LUNGE_ATTACK: ActionConfig = {
	Id = "atk_lunge",
	Name = "Lunge Attack",
	Type = "Attack",
	AnimationId = "",
	AnimationName = "Fists",
	AnimationAssetName = "punch 2",
	AnimationSpeed = 1.1,
	Duration = 0.8,
	HitStartFrame = 0.4,
	HitStopDuration = 0.12,
	CancelFrame = 0.60,     -- can cancel into next attack after the hit lands
	CameraShake = 0.7,
	SoundId = "rbxassetid://12345681",
	KnockbackPower = 1.2,
	Cooldown = 1.0,
	RequiredState = "Idle",
}

return {
	ATTACK_LIGHT = ATTACK_LIGHT,
	ATTACK_HEAVY = ATTACK_HEAVY,
	DODGE = DODGE,
	BLOCK = BLOCK,
	PARRY = PARRY,
	LUNGE_ATTACK = LUNGE_ATTACK,
}
