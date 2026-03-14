--!strict
--[[
	HollowedTypes.lua

	Issue #143: HollowedService — Ring 1 enemy with patrol, aggro, basic attack
	Epic: Phase 4 — World & Narrative

	Shared type definitions for the Hollowed enemy system.
	Used by HollowedService (server) and any client-side rendering code
	that needs to know about enemy configuration.

	Dependencies: none
]]

local HollowedTypes = {}

-- ─── Config ──────────────────────────────────────────────────────────────────

--[[
	Per-enemy-type static configuration. Registered in HollowedService.CONFIGS.
]]
export type HollowedConfig = {
	Id             : string,   -- unique config id, e.g. "basic_hollowed"
	DisplayName    : string,   -- shown in the model billboard
	MaxHealth      : number,   -- full HP pool
	MaxPoise       : number,   -- max posture pressure before staggering
	AttackDamage   : number,   -- HP damage dealt per swing
	PostureDamage  : number,   -- posture pressure added per hit
	AggroRange     : number,   -- studs — detect players within this radius
	AttackRange    : number,   -- studs — swing when within this radius
	PatrolRadius   : number,   -- studs — random wander distance from spawn
	MoveSpeed      : number,   -- studs/second walk speed
	AttackCooldown : number,   -- seconds between each attack
	ResonanceGrant : number,   -- Resonance Shards awarded to killer on death
	RespawnDelay   : number,   -- seconds before respawning at spawn point
	BodyColor      : BrickColor, -- placeholder tint for all body parts
}

-- ─── Instance ────────────────────────────────────────────────────────────────

--[[
	AI state machine values for an active Hollowed instance.
]]
export type HollowedState = "Patrol" | "Aggro" | "Attacking" | "Dead" | "Dodging" | "Stunned" | "Blocking"

--[[
	Runtime data for a single spawned Hollowed.
	Stored in HollowedService's internal table.
]]
export type HollowedData = {
	InstanceId       : string,       -- unique e.g. "Hollowed_1"
	ConfigId         : string,       -- key into CONFIGS
	SpawnCFrame      : CFrame,       -- original spawn position + orientation
	RootPosition     : Vector3,      -- current world position of HumanoidRootPart
	CurrentHealth    : number,
	CurrentPoise     : number,
	MaxHealth        : number,
	State            : HollowedState,
	Target           : Player?,      -- current aggro target (nil when patrolling)
	LastAttackTick   : number,       -- tick() of last swing
	PatrolTarget     : Vector3?,     -- current waypoint (nil = pick a new one)
	PatrolWaitUntil  : number,       -- tick() timestamp — idle at waypoint until then
	LastAITick       : number,       -- tick() of last AI evaluation (throttle)
	KillerId         : number?,      -- UserId of killing player (set on death)
	IsActive         : boolean,
}

return HollowedTypes
