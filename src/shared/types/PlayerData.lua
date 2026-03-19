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
local CodexTypes = require(game:GetService("ReplicatedStorage").Shared.types.CodexTypes) :: any

-- Ember Point definitions
export type SerializedVector3 = { X: number, Y: number, Z: number }

export type EmberPointData = {
	Id: string,
	Position: SerializedVector3,
	Ring: number,
	SetAt: number,
	UsedCount: number,
}

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

export type LuminanceComponent = {
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
	Luminance: LuminanceComponent,

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

	-- Discipline (computed soft label — not a locked choice)
	DisciplineId: string,

	-- Stat Allocation (free distribution; no locked class)
	StatPoints: number,   -- unspent points available to invest
	Stats: {
		Strength:     number,
		Fortitude:    number,
		Agility:      number,
		Intelligence: number,
		Willpower:    number,
		Charisma:     number,
	},

	-- Progression System
	CurrentRing: number,  -- 0–5: which Ring the player is currently in
	OmenMarks: number,    -- 0–5 Umbral Marks (Omen system — Phase 4+)

	-- Ring 1 Progression Data (#179)
	CodexEntries: {[CodexTypes.CodexEntryId]: CodexTypes.CodexEntry}, -- keys are e.g. Hollowed variant IDs or "Duskwalker"
	EmberPoints: {[string]: EmberPointData},  -- custom placed spawn points
	ActiveEmberPointId: string?,       -- the currently active respawn point id
	DuskwalkerSurvived: boolean?,      -- has the player passed the Duskwalker encounter?

	-- Inventory & equipment (items stored in the player's backpack/config)
	Inventory: {ItemTypes.Item},      -- items in backpack or stash
	EquippedItems: {ItemTypes.Item?},  -- slot index -> item (nil if empty)

	-- Metadata
	Level: number,
	Experience: number,
}

return {}
