--!strict
--[[
	ActionTypes.lua

	Issue #8: Action Controller (Animation & Feel)
	Epic: Phase 2 - Combat & Fluidity

	Type definitions for combat actions with animations, hit-stop, and game feel.
]]

local AnimationDatabase = require(game.ReplicatedStorage.Shared.AnimationDatabase)

export type AnimationKey = AnimationDatabase.AnimationKey

export type ActionType = "Attack" | "Ability" | "Skill" | "Dodge" | "Parry" | "Block"

export type ActionConfig = {
	-- Identity
	Id: string,
	Name: string,
	Type: ActionType,

	-- Animation (use project folder when set; otherwise AnimationId)
	AnimationId: string,
	AnimationName: AnimationKey?, -- key from AnimationDatabase (e.g. "FrontRoll" or "Walk")
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
	IsCanceled: boolean, -- Set to true when action is canceled early (feint/interrupt)
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
-- example union of valid animation keys (needed for static analysis)
-- note: this is not exhaustive; add new values when database grows
export type SampleAnimationKey = AnimationKey

local ATTACK_LIGHT: ActionConfig = {
	Id = "atk_light",
	Name = "Light Attack",
	Type = "Attack",
	AnimationId = "",
	AnimationName = "Fists",
	AnimationAssetName = "punch 1",
	AnimationSpeed = 1.3,   -- snappier swing
	Duration = 0.45,        -- tighter window
	HitStartFrame = 0.3,
	HitStopDuration = 0.07, -- shorter freeze on contact
	CancelFrame = 0.55,     -- can chain next hit at 55% of duration (~0.25 s)
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

-- Feint action used to cancel a current swing. Separate config so we can
-- assign its own cooldown and animation without altering attack handling.
local FEINT: ActionConfig = {
	Id = "feint",
	Name = "Feint",
	Type = "Attack",                -- treated as an Attack for animation purposes
	AnimationId = "",
	AnimationName = "FeintRecovery", -- animation stub in AnimationDatabase
	AnimationAssetName = "",
	AnimationSpeed = 1.0,
	Duration = 0.25,                  -- brief cancel commitment window
	CancelFrame = 1.0,                -- not cancellable once started
	CameraShake = 0.0,
	SoundId = "",
	Cooldown = 1.0,                   -- base cooldown; may be overridden by weapon
	RequiredState = "Idle",
}

return {
	ATTACK_LIGHT = ATTACK_LIGHT,
	ATTACK_HEAVY = ATTACK_HEAVY,
	DODGE = DODGE,
	BLOCK = BLOCK,
	PARRY = PARRY,
	LUNGE_ATTACK = LUNGE_ATTACK,
	FEINT = FEINT,
}
