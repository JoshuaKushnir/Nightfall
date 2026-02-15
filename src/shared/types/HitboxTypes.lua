--!strict
--[[
	HitboxTypes.lua
	
	Issue #7: Modular Raycast-Based Hitbox System
	Epic: Phase 2 - Combat & Fluidity
	
	Type definitions for hitbox system supporting multiple shapes and configurations.
]]

export type HitboxShape = "Box" | "Sphere" | "Raycast"

export type HitboxConfig = {
	-- Core properties
	Shape: HitboxShape,
	Owner: Player,
	Damage: number,
	
	-- Box/Sphere properties
	Position: Vector3?,
	Size: Vector3?, -- For Box: width, height, depth; For Sphere: radius in all axes
	
	-- Raycast properties
	Origin: Vector3?,
	Direction: Vector3?,
	Length: number?,
	
	-- Behavior
	Blacklist: {Player}?, -- Players to not hit (teammates, self)
	CanHitTwice: boolean?, -- Default: false
	LifeTime: number?, -- Seconds before auto-expire
	
	-- Callbacks
	OnHit: ((target: any, hitData: HitData) -> ())?,
	OnExpire: (() -> ())?,
	
	-- Validation
	StunAffinity: {string}?, -- Can only hit players in these states
}

export type HitData = {
	Hitbox: Hitbox,
	Target: Player,
	Position: Vector3,
	Distance: number?,
	HitTime: number,
	Damage: number,
}

export type Hitbox = {
	Id: string,
	Config: HitboxConfig,
	Active: boolean,
	CreatedTime: number,
	HitTargets: {Player}, -- Already hit
	
	-- Methods
	Hit: (self: Hitbox, target: Player) -> boolean,
	Update: (self: Hitbox, position: Vector3?) -> (),
	Expire: (self: Hitbox) -> (),
	IsValidTarget: (self: Hitbox, target: Player) -> boolean,
	CheckShape: (self: Hitbox, targetPosition: Vector3) -> boolean,
}

return {}
