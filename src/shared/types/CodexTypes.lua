--!strict
--[[
    Class: CodexTypes
    Description: Type definitions for the Codex and Witnessing progression system.
    Dependencies: None
]]

-- A unique identifier for a piece of knowledge a player can witness/discover.
-- e.g. "Hollowed_Variant_A", "Hollowed_Variant_B", "Duskwalker_Survive"
export type CodexEntryId = string

-- The state of a piece of knowledge for a specific player.
export type CodexEntryState =
    | "Hidden"      -- Not yet discovered
    | "Discovering" -- Currently observing but timer not complete (transient state, usually not persisted)
    | "Witnessed"   -- Fully observed and unlocked

-- The persistent data shape for an unlocked codex entry
export type CodexEntry = {
    Id: CodexEntryId,
    State: CodexEntryState,
    WitnessedAt: number, -- OS time when it was unlocked
}

-- Sent to the client when a new codex entry is unlocked (for a small UI toast)
export type CodexUnlockPacket = {
    EntryId: CodexEntryId,
    Title: string, -- E.g. "Hollowed Ambusher Witnessed"
}

return {}
