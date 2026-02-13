--!strict
--[[
	Class: PlayerData
	Description: Strictly typed player data structure for Nightfall
	Dependencies: None
	
	This module defines the core data structures for player state management.
	All player data should conform to these types for type safety across the codebase.
]]

-- Component Types
export type HealthComponent = {
	Current: number,
	Max: number,
}

export type ManaComponent = {
	Current: number,
	Max: number,
	Regeneration: number,
}

export type PostureComponent = {
	Current: number,
	Max: number,
	Broken: boolean,
}

-- Player State
export type PlayerState = 
	"Idle" 
	| "Walking" 
	| "Running" 
	| "Attacking" 
	| "Blocking" 
	| "Stunned" 
	| "Ragdolled" 
	| "Casting"
	| "Dead"

-- Mantra Definition
export type Mantra = {
	Name: string,
	BaseDamage: number,
	CastTime: number,
	Cooldown: number,
	ManaCost: number,
	VFX_Function: (player: Player) -> (),
}

-- Complete Player Data Structure
export type PlayerData = {
	UserId: number,
	DisplayName: string,
	
	-- Core Stats
	Health: HealthComponent,
	Mana: ManaComponent,
	Posture: PostureComponent,
	
	-- State Management
	State: PlayerState,
	LastStateChange: number, -- tick() timestamp
	
	-- Combat Data
	Mantras: {Mantra},
	ActiveCooldowns: {[string]: number}, -- Mantra name -> cooldown end time
	
	-- Metadata
	Level: number,
	Experience: number,
}

return {}
