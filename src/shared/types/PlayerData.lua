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
	| "Dodging"
	| "Stunned" 
	| "Ragdolled" 
	| "Casting"
	| "Dead"
	| "Clashing"           -- initial push-apart state
	| "ClashWindow"       -- awaiting follow-up input
	| "ClashFollowSuccess"-- successfully executed follow-up
	| "ClashFollowMiss"   -- failed/missed follow-up

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

--[[
	PlayerProfile is the slimmed-down version of PlayerData that is sent
	over the network. It contains only the fields the client needs to render

the HUD or make decisions and uses simple numeric values rather than
	nested components. Adding Luminance here allows the HUD to show the
	player's current light level, defaulting to 0 until the mechanic exists.
]]
export type PlayerProfile = {
	UserId: number,
	Username: string?,
	DisplayName: string,

	-- Stats exposed to client
	Level: number,
	Experience: number,
	CurrentHealth: number,
	MaxHealth: number,
	CurrentMana: number,
	MaxMana: number,
	CurrentPosture: number,
	MaxPosture: number,
	Luminance: number?,
	Coins: number,
	Class: string,
	EquippedMantras: {Mantra}?,
}

return {}
