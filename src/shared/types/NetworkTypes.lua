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

-- Network Event Registry (enum-based)
export type NetworkEvent =
	-- State Management
	| "StateChanged"
	| "StateRequest"
	
	-- Combat
	| "DamageDealt"
	| "HealReceived"
	| "PostureDamage"
	| "PostureBroken"
	
	-- Abilities/Mantras
	| "MantraCast"
	| "MantraHit"
	| "CooldownUpdate"
	
	-- Equipment
	| "EquipItem"
	| "UnequipItem"
	| "UseItem"
	
	-- Dialogue/Quests
	| "DialogueStart"
	| "DialogueChoice"
	| "QuestAccept"
	| "QuestComplete"
	
	-- UI
	| "OpenUI"
	| "CloseUI"
	| "UIInteraction"
	
	-- Admin/Debug
	| "AdminCommand"
	| "DebugInfo"

-- Packet Definitions

export type StateChangedPacket = {
	Player: Player,
	OldState: string,
	NewState: string,
}

export type StateRequestPacket = {
	NewState: string,
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

export type AdminCommandPacket = {
	Command: string,
	Args: {string},
}

export type DebugInfoPacket = {
	Category: string,
	Data: {[string]: any},
}

-- Unified packet type for type safety
export type NetworkPacket =
	StateChangedPacket
	| StateRequestPacket
	| DamageDealtPacket
	| HealReceivedPacket
	| PostureDamagePacket
	| PostureBrokenPacket
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
	
	-- Abilities/Mantras
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
	UseItem = {
		Direction = "ClientToServer",
		RateLimitPerSecond = 5,
		RequiresValidation = true,
		Description = "Client requests to use item",
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
