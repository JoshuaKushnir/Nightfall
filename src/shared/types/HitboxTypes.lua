--!strict
--[[
	HitboxTypes.lua
	
	Issue #7: Modular Raycast-Based Hitbox System
	Epic: Phase 2 - Combat & Fluidity
	
	Type definitions for hitbox system supporting multiple shapes and configurations.
]]

export type HitboxShape = "Box" | "Sphere" | "Raycast" | "Circle" | "Square" | "Cylinder" | "Cone"

export type HitboxConfig = {
	-- Core properties
	Shape: HitboxShape,
	Owner: Player,
	Damage: number,
	
	-- Box/Sphere properties
	Position: Vector3?,
	CFrame: CFrame?, -- For rotated boxes
	Size: Vector3?, -- For Box: width, height, depth; For Sphere: radius in X axis
	
	-- Raycast & Cone/Cylinder properties
	Origin: Vector3?,
	Direction: Vector3?,
	Length: number?,
	Angle: number?, -- For Cones
	Radius: number?, -- For Circles/Cylinders/Cones (can also use Size.X)
	Width: number?, -- Explicit width for elliptical cones
	Height: number?, -- Explicit height for elliptical cones
	
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
