--!strict
--[[
	NetworkTypes - Type definitions for all network packets and events
	
	Issue #4: Centralized Network Communication Provider
	Epic: Phase 1 - Core Framework
	
	This module defines all network event types and packet structures
	for type-safe client-server communication.
	
	All network packets should be defined here to ensure consistency
	across server and client implementations.
]]

-- import shared type modules that may be referenced in packet definitions
local ItemTypes = require(game:GetService("ReplicatedStorage").Shared.types.ItemTypes) :: any

-- Network Event Registry (enum-based)
export type NetworkEvent =
	-- State Management
	| "StateChanged"
	| "StateRequest"
	| "RequestStateSync"
	| "ProfileData"
	| "ProfileUpdate"
	| "CombatData"
	
	-- Combat
	| "DamageDealt"
	| "HealReceived"
	| "PostureDamage"
	| "PostureBroken"
	| "PostureChanged"
	| "Staggered"
	| "BreakExecuted"
	| "HitConfirmed"
	| "BlockFeedback"
	| "ParryFeedback"
	| "ClashOccurred"         -- server broadcast when a Clash begins
	| "AttackInitiated"       -- client→server: player attempted an attack
	| "ClashStart"            -- server→client: individual player enters clash state
	| "ClashFollowup"         -- client→server: follow-up input during clash window
	| "ClashOutcome"          -- server→clients near event: result of clash
	
	-- Abilities/Mantras
	| "MantraCast"
	| "MantraHit"
	| "CooldownUpdate"
	
	-- Equipment
	| "EquipItem"
	| "UnequipItem"
	| "UseItem"
	| "EquipWeapon"
	| "UnequipWeapon"
	| "WeaponEquipped"
	| "WeaponUnequipped"
	| "InventorySync"          -- server → client: send full inventory

	-- Dialogue/Quests
	| "DialogueStart"
	| "DialogueChoice"
	| "QuestAccept"
	| "QuestComplete"
	
	-- UI
	| "OpenUI"
	| "CloseUI"
	| "UIInteraction"

	-- Dev/Debug (spawn/despawn dummies)
	| "SpawnDummy"
	| "DespawnDummy"
	| "DummyStateChanged"

	-- Abilities
	| "UseAbility"

	-- Aspect System Events
	| "AspectAssigned"         -- Server → Client: tell client their Aspect was set
	| "AspectInvestRequest"    -- Client → Server: request to invest Shards in a branch
	| "AspectInvestResult"     -- Server → Client: success/failure result
	| "AbilityCastRequest"     -- Client → Server: request to cast an ability
	| "AbilityCastResult"      -- Server → Client: success/failure + target info
	| "AbilityDataSync"        -- Server → Client: sync current cooldowns on join

	-- Progression
	| "ResonanceUpdate"          -- Server → Client: Resonance/Shard state change
	| "ProgressionSync"          -- Server → Client: full progression state on join
	| "DisciplineSelectRequired" -- Server → Client: player must choose Discipline
	| "DisciplineSelected"       -- Client → Server: player's Discipline choice
	| "DisciplineConfirmed"      -- Server → Client: Discipline lock-in confirmed

	-- Movement (client requests validated on server)
	| "RequestSlide"

	-- Admin/Debug
	| "AdminCommand"
	| "DebugInfo"

-- Packet Definitions

export type StateChangedPacket = {
	NewState: string,
	Timestamp: number?,
}

export type StateRequestPacket = {
	NewState: string,
}

export type RequestStateSyncPacket = {
	Timestamp: number,
}

export type ProfileDataPacket = {
	ProfileData: any, -- PlayerProfile type
}

export type ProfileUpdatePacket = {
	ProfileData: any, -- PlayerProfile type
}

export type CombatDataPacket = {
	Health: number,
	Mana: number,
	Posture: number,
	Level: number,
}

export type DamageDealtPacket = {
	Target: Player | Model,
	Damage: number,
	DamageType: string,
	Source: Player | Model,
}

export type HealReceivedPacket = {
	Amount: number,
	Source: string,
}

export type PostureDamagePacket = {
	Target: Player,
	Damage: number,
	Source: Player,
}

export type PostureBrokenPacket = {
	Target: Player,
}

-- Advanced combat packets
export type ClashOccurredPacket = {
	Attacker: Player,
	Defender: Player,
	FollowupWindow: number, -- seconds the target has to input a follow-up
}

-- Packet sent when a client tells the server an attack has been initiated.
--
-- Clash detection flow (see Section 4 of discipline spec):
-- 1. Player A issues an attack; client fires "AttackInitiated" with a local
--    timestamp.
-- 2. Server records T_A. If another "AttackInitiated" from Player B arrives
--    within CLASH_TOLERANCE_MS of T_A, a clash is triggered.
-- 3. Server enters CLASHING state for both players and sends them individual
--    "ClashStart" packets.  This state locks normal actions briefly.
-- 4. Server begins the 0.5s CLASH_WINDOW. Clients may choose a follow-up and
--    send "ClashFollowup" with the chosen input and timestamp.
-- 5. Server evaluates follow-ups:
--       SUCCESS -> apply discipline-specific effects, transition to
--                  CLASH_FOLLOW_SUCCESS, broadcast "ClashOutcome" to nearby
--                  players for VFX/SFX.
--       MISS    -> transition to CLASH_FOLLOW_MISS, player becomes exposed,
--                  also broadcast "ClashOutcome".
-- 6. After resolution, players exit clash states and combat resumes normally.
--
-- The events defined below correspond to these steps.
export type AttackInitiatedPacket = {
	Timestamp: number, -- os.time() or tick() value from client when input occurred
}

-- Server notifies a specific player that they have entered the CLASHING state.
export type ClashStartPacket = {
	Partner: Player, -- opposing player
	Window: number,  -- duration of follow-up window (0.5s)
}

-- Follow-up input packet sent from client during CLASH_WINDOW.
export type ClashFollowupPacket = {
	InputType: "Parry" | "Counter" | "Dash" | "Other", -- based on discipline
	Timestamp: number,
}

-- Outcome broadcast when a clash resolves, for nearby clients to play SFX/VFX.
export type ClashOutcomePacket = {
	Winner: Player?, -- nil if both miss
	Loser: Player?,
	Success: boolean,
}

export type CondemnedStatusPacket = {
	Target: Player,
	IsCondemned: boolean,
}

-- Aspect system packets
export type AspectAssignedPacket = {
	AspectId: string,
}

export type AspectInvestRequestPacket = {
	AspectId: string,
	Branch: string,
	Amount: number,
}

export type AspectInvestResultPacket = {
	Success: boolean,
	Reason: string?,
}

export type AbilityCastRequestPacket = {
	AbilityId: string,
	TargetPosition: Vector3?,
}

-- Progression packets (Issue #138, #139)
export type ResonanceUpdatePacket = {
	TotalResonance: number,
	ResonanceShards: number,
	CurrentRing: number,
	SoftCap: number,     -- -1 signals no cap (Ring 0 / Ring 5)
	ShardDelta: number,  -- signed: positive = gain, negative = loss
	IsSoftCapped: boolean,
	Source: string?,
}

export type ProgressionSyncPacket = {
	TotalResonance: number,
	ResonanceShards: number,
	CurrentRing: number,
	SoftCap: number,
	HasChosenDiscipline: boolean,
	DisciplineId: string,
	OmenMarks: number,
}

export type DisciplineSelectRequiredPacket = {}

export type DisciplineSelectedPacket = {
	DisciplineId: string,
}

export type DisciplineConfirmedPacket = {
	DisciplineId: string,
}

export type AbilityCastResultPacket = {
	Success: boolean,
	Reason: string?,
	AbilityId: string?,
	TargetPosition: Vector3?,
}

export type AbilityDataSyncPacket = {
	Cooldowns: {[string]: number},
}

export type PostureChangedPacket = {
	-- playerId / playername so non-local clients can look up the character
	PlayerId: number,
	Current: number,
	Max: number,
}

export type StaggeredPacket = {
	PlayerId: number,
	Duration: number,
}

export type BreakExecutedPacket = {
	AttackerId: number,
	TargetId: number,
	Damage: number,
}

export type HitConfirmedPacket = {
	Attacker: Player,
	Target: Player,
	Damage: number,
	IsCritical: boolean?,
	HitType: "Normal" | "Block" | "Parry" | "Block"?,
	-- Optional reaction animation info for clients to play (prefer project animations under
	-- ReplicatedStorage.Shared.animations; clients should fall back to AnimationId if provided).
	AnimationName: string?, -- Folder name under Shared.animations (e.g. "Crouching")
	AnimationAssetName: string?, -- Optional specific asset under AnimSaves
	AnimationDuration: number?, -- Optional duration hint (seconds)
}

-- Spawn/Despawn dev dummies
export type SpawnDummyPacket = {
	Position: Vector3?, -- Optional; server may place relative to player if omitted
}

export type DespawnDummyPacket = {
	DummyId: string,
}

export type DummyStateChangedPacket = {
	DummyId: string,
	State: string, -- "Normal" | "Blocking" | "Staggered"
	Health: number,
	MaxHealth: number,
}

export type BlockFeedbackPacket = {
	Blocker: Player,
	Attacker: Player,
	BlockedDamage: number,
}

export type ParryFeedbackPacket = {
	Parrier: Player,
	Attacker: Player,
}

export type MantraCastPacket = {
	MantraId: string,
	TargetPosition: Vector3?,
	TargetPlayer: Player?,
}

export type MantraHitPacket = {
	MantraId: string,
	Target: Player | Model,
	Damage: number,
	Effects: {string}?,
}

export type CooldownUpdatePacket = {
	MantraId: string,
	CooldownRemaining: number,
	TotalCooldown: number,
}

export type EquipItemPacket = {
	ItemId: string,
	Slot: "Weapon" | "Armor" | "Helmet" | "Accessory1" | "Accessory2",
}

export type UnequipItemPacket = {
	Slot: "Weapon" | "Armor" | "Helmet" | "Accessory1" | "Accessory2",
}

export type UseItemPacket = {
	ItemId: string,
	Target: Player?,
}

export type InventoryPacket = {
	Inventory: {ItemTypes.Item},
	Equipped: {[string]: ItemTypes.Item?},
}

export type DialogueStartPacket = {
	NPC: string,
	DialogueId: string,
}

export type DialogueChoicePacket = {
	DialogueId: string,
	ChoiceIndex: number,
}

export type QuestAcceptPacket = {
	QuestId: string,
}

export type QuestCompletePacket = {
	QuestId: string,
	Rewards: {string},
}

export type OpenUIPacket = {
	UIName: string,
	Data: {[string]: any}?,
}

export type CloseUIPacket = {
	UIName: string,
}

export type UIInteractionPacket = {
	UIName: string,
	Action: string,
	Data: {[string]: any}?,
}

export type UseAbilityPacket = {
	-- No payload needed: server resolves equipped weapon from sender
}

export type AdminCommandPacket = {
	Command: string,
	Args: {string},
}

export type DebugInfoPacket = {
	Category: string,
	Data: {[string]: any},
}

-- Slide request packet (Start | Leap)
export type SlideRequestPacket = {
	Type: "Start" | "Leap",
	Timestamp: number?,
}

-- Unified packet type for type safety
export type NetworkPacket = 
	StateChangedPacket
	| StateRequestPacket
	| RequestStateSyncPacket
	| ProfileDataPacket
	| ProfileUpdatePacket
	| CombatDataPacket
	| DamageDealtPacket
	| HealReceivedPacket
	| PostureDamagePacket
	| PostureBrokenPacket
	| PostureChangedPacket
	| StaggeredPacket
	| BreakExecutedPacket
	| HitConfirmedPacket
	| BlockFeedbackPacket
	| ParryFeedbackPacket
	| ClashOccurredPacket         -- advanced combat
	| CondemnedStatusPacket      -- advanced combat
	| MantraCastPacket
	| MantraHitPacket
	| CooldownUpdatePacket
	| EquipItemPacket
	| UnequipItemPacket
	| UseItemPacket
	| DialogueStartPacket
	| DialogueChoicePacket
	| QuestAcceptPacket
	| QuestCompletePacket
	| OpenUIPacket
	| CloseUIPacket
	| UIInteractionPacket
	| SpawnDummyPacket
	| DespawnDummyPacket
	| DummyStateChangedPacket
	| UseAbilityPacket
	| AdminCommandPacket
	| DebugInfoPacket

-- Network Event Direction
export type EventDirection = "ServerToClient" | "ClientToServer" | "Bidirectional"

-- Event metadata for configuration
export type EventMetadata = {
	Direction: EventDirection,
	RateLimitPerSecond: number?, -- Max fires per second per player (nil = unlimited)
	RequiresValidation: boolean, -- Whether to run validation middleware
	Description: string,
}

-- Event registry with metadata
local EVENT_METADATA: {[NetworkEvent]: EventMetadata} = {
	-- State Management
	StateChanged = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Notify client of state change",
	},
	StateRequest = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		RequiresValidation = true,
		Description = "Client requests state change",
	},
	RequestStateSync = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 1,
		RequiresValidation = false,
		Description = "Client requests full state sync",
	},

	-- Client requests to start a slide or perform a slide-jump; validated server-side
	RequestSlide = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		RequiresValidation = true,
		Description = "Client requests a slide start or slide-jump (server validates cooldown/state)",
	},
	ProfileData = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Send initial profile data to client",
	},
	ProfileUpdate = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Send profile updates to client",
	},
	CombatData = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Send combat stat updates to client",
	},
	
	-- Combat
	DamageDealt = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Notify client of damage",
	},
	HealReceived = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Notify client of healing",
	},
	PostureDamage = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Notify client of posture damage",
	},
	PostureBroken = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Notify client posture is broken",
	},
	PostureChanged = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Broadcast current/max posture for a player so clients can update posture bars",
	},
	Staggered = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Broadcast that a player entered Staggered state (posture break)",
	},
	BreakExecuted = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Broadcast that a Break attack was executed during a Stagger window",
	},
	HitConfirmed = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Notify client of confirmed hit for feedback",
	},
	BlockFeedback = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Show block feedback UI",
	},
	ParryFeedback = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Show parry feedback UI",
	},
	ClashOccurred = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Notify clients that a clash occurred between two players",
	},
	CondemnedStatus = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Notify client when a player gains/loses Condemned status",
	},

	-- Dev/Debug dummies
	SpawnDummy = {
		Direction = "Bidirectional",
		RateLimitPerSecond = 5,
		RequiresValidation = false,
		Description = "Spawn or broadcast a dev test dummy (dev-only)",
	},

	DespawnDummy = {
		Direction = "Bidirectional",
		RateLimitPerSecond = 5,
		RequiresValidation = false,
		Description = "Despawn a dev test dummy (dev-only)",
	},

	DummyStateChanged = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Broadcast dummy state change (Normal/Blocking/Staggered) to all clients",
	},
	
	-- Abilities/Mantras
	AbilityCastRequest = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 10,
		RequiresValidation = true,
		Description = "Client requests an aspect ability cast",
	},
	AbilityCastResult = {
		Direction = "ServerToClient",
		RateLimitPerSecond = 20,
		RequiresValidation = false,
		Description = "Reply to ability cast with success/failure and cooldown",
	},
	MantraCast = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 10,
		RequiresValidation = true,
		Description = "Client requests mantra cast",
	},
	MantraHit = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Notify client of mantra hit",
	},
	CooldownUpdate = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Update client on cooldown status",
	},
	
	-- Equipment
	EquipItem = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 2,
		RequiresValidation = true,
		Description = "Client requests to equip item",
	},
	UnequipItem = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 2,
		RequiresValidation = true,
		Description = "Client requests to unequip item",
	},
	EquipWeapon = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 2,
		RequiresValidation = true,
		Description = "Client requests to equip a weapon by id",
	},
	UnequipWeapon = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 2,
		RequiresValidation = true,
		Description = "Client requests to unequip current weapon",
	},
	WeaponEquipped = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Broadcast to all clients that a player equipped a weapon",
	},
	WeaponUnequipped = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Broadcast to all clients that a player unequipped their weapon",
	},
	UseItem = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		RequiresValidation = true,
		Description = "Client requests to use item",
	},
	AbilityDataSync = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Sync ability cooldowns on join",
	},
	InventorySync = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Send full inventory to client",
	},
	
	-- Dialogue/Quests
	DialogueStart = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Start dialogue with NPC",
	},
	DialogueChoice = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 3,
		RequiresValidation = true,
		Description = "Client makes dialogue choice",
	},
	QuestAccept = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 1,
		RequiresValidation = true,
		Description = "Client accepts quest",
	},
	QuestComplete = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Notify client quest completed",
	},
	
	-- UI
	OpenUI = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Tell client to open UI",
	},
	CloseUI = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Tell client to close UI",
	},
	UIInteraction = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 10,
		RequiresValidation = true,
		Description = "Client interacts with UI",
	},
	
	-- Progression (Issue #138, #139)
	ResonanceUpdate = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Resonance/Shard state changed — fires after any grant or death loss",
	},
	ProgressionSync = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Full progression state sync sent to client on join",
	},
	DisciplineSelectRequired = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Prompt client to open Discipline selection UI",
	},
	DisciplineSelected = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 1,
		RequiresValidation = true,
		Description = "Client submits their Discipline choice (one-time)",
	},
	DisciplineConfirmed = {
		Direction = "ServerToClient",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Server confirms Discipline lock-in",
	},

	-- Abilities
	UseAbility = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 2,
		RequiresValidation = true,
		Description = "Client activates their weapon's active ability",
	},

	-- Admin/Debug
	AdminCommand = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 1,
		RequiresValidation = true,
		Description = "Client sends admin command",
	},
	DebugInfo = {
		Direction = "Bidirectional",
		RateLimitPerSecond = nil,
		RequiresValidation = false,
		Description = "Debug information exchange",
	},
}

-- Export metadata accessor
local NetworkTypes = {}

function NetworkTypes.GetEventMetadata(event: NetworkEvent): EventMetadata?
	return EVENT_METADATA[event]
end

function NetworkTypes.GetAllEvents(): {NetworkEvent}
	local events: {NetworkEvent} = {}
	for event in EVENT_METADATA do
		table.insert(events, event)
	end
	return events
end

return NetworkTypes
