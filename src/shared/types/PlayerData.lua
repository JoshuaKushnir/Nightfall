--!strict
--[[
	Class: PlayerData
	Description: Strictly typed player data structure for Nightfall
	Dependencies: None
	
	This module defines the core data structures for player state management.
	All player data should conform to these types for type safety across the codebase.
]]

local AspectTypes = require(game:GetService("ReplicatedStorage").Shared.types.AspectTypes) :: any
local ItemTypes = require(game:GetService("ReplicatedStorage").Shared.types.ItemTypes) :: any

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
	
	-- Aspect System
	AspectData: AspectTypes.PlayerAspectData?,    -- nil until Aspect chosen at character creation
	ResonanceShards: number,          -- in-flight currency, lost on death
	TotalResonance: number,           -- permanent, never lost
	
	-- Discipline
	DisciplineId: string,
	HasChosenDiscipline: boolean, -- false until first-login selection screen

	-- Progression System
	CurrentRing: number,  -- 0–5: which Ring the player is currently in
	OmenMarks: number,    -- 0–5 Umbral Marks (Omen system — Phase 4+)

	-- Inventory & equipment (items stored in the player's backpack/config)
	Inventory: {ItemTypes.Item},      -- items in backpack or stash
	EquippedItems: {ItemTypes.Item?},  -- slot index -> item (nil if empty)

	-- Metadata
	Level: number,
	Experience: number,
}

return {}
