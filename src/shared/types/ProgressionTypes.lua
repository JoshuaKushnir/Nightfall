--!strict
--[[
    Class: ProgressionTypes
    Description: Type definitions for the Progression system — Resonance,
                 Ring soft caps, Discipline selection, and Omen marks.
    Dependencies: None

    Issue #138: ProgressionService — Resonance grants, Ring soft caps, Shard loss
    Issue #139: Discipline selection flow
    Epic #51: Phase 4 — World & Narrative
]]

-- ─── Ring Identifiers ─────────────────────────────────────────────────────────

-- Numeric ring index (0 = Hearthspire social hub, 5 = The Null endgame zone)
export type RingId = number  -- 0-5

-- ─── Discipline Identifiers ───────────────────────────────────────────────────

export type DisciplineId = "Wayward" | "Ironclad" | "Silhouette" | "Resonant"

-- ─── Resonance Sources ────────────────────────────────────────────────────────

-- All authoritative sources that can grant Resonance.
-- Server validates every grant comes from one of these.
export type ResonanceSource =
    | "Kill_Dummy"     -- killing a training dummy (low award)
    | "Kill_Player"    -- defeating another player in open world
    | "Kill_Enemy"     -- structured enemy kill (future PvE)
    | "Exploration"    -- discovering a new area (future)
    | "Survival"       -- staying alive in a deep zone over time (future)
    | "Debug"          -- admin/testing grants

-- ─── Ring Config ──────────────────────────────────────────────────────────────

-- Per-ring progression gate configuration.
-- SPEC-GAP: SoftCap values are placeholders; tracked in issue #129.
export type RingConfig = {
    SoftCap: number,            -- TotalResonance ceiling for this ring
    DiminishThreshold: number,  -- fraction of SoftCap where diminishing returns begin
    DiminishMultiplier: number, -- Shard grant multiplier above threshold (0-1)
    HardBlock: boolean,         -- if true: Shard grants are zero at SoftCap
}

-- ─── Network Packets ──────────────────────────────────────────────────────────

-- Fired server→client after any Resonance change (grant or death loss)
export type ResonanceUpdatePacket = {
    TotalResonance: number,   -- current permanent total
    ResonanceShards: number,  -- current spendable shards
    CurrentRing: number,      -- player's current ring (0-5)
    SoftCap: number,          -- soft cap for CurrentRing (math.huge = none)
    ShardDelta: number,       -- signed: positive = gain, negative = loss
    IsSoftCapped: boolean,    -- true when TotalResonance >= SoftCap
    Source: ResonanceSource?, -- what caused this update (nil for death loss)
}

-- Full progression state sync sent on join (server→client)
export type ProgressionSyncPacket = {
    TotalResonance: number,
    ResonanceShards: number,
    CurrentRing: number,
    SoftCap: number,
    HasChosenDiscipline: boolean,
    DisciplineId: DisciplineId,
    OmenMarks: number,
}

-- Sent server→client when the player hasn't selected a Discipline yet
export type DisciplineSelectRequiredPacket = {
    -- empty; presence of the event is the trigger
}

-- Sent client→server with the player's Discipline choice
export type DisciplineSelectedPacket = {
    DisciplineId: DisciplineId,
}

-- Sent server→client confirming the Discipline lock-in
export type DisciplineConfirmedPacket = {
    DisciplineId: DisciplineId,
}

-- ─── Ring Config Table (Single Source of Truth) ───────────────────────────────

-- Indexed by RingId (0-5).
-- SPEC-GAP: SoftCap numbers are design placeholders — issue #129.
-- DiminishThreshold values match design doc (75-85% onset per ring).
local RING_CONFIGS: {[number]: RingConfig} = {
    [0] = { -- Hearthspire — social hub, no progression gate
        SoftCap           = math.huge,
        DiminishThreshold = 1.0,
        DiminishMultiplier = 1.0,
        HardBlock         = false,
    },
    [1] = { -- The Verdant Shelf (Ring 1)
        SoftCap           = 2000,   -- SPEC-GAP placeholder — issue #129
        DiminishThreshold = 0.75,   -- per design doc
        DiminishMultiplier = 0.10,  -- 90% reduction above threshold
        HardBlock         = true,   -- Shards blocked entirely at cap
    },
    [2] = { -- The Ashfeld (Ring 2)
        SoftCap           = 10000,  -- SPEC-GAP placeholder
        DiminishThreshold = 0.80,
        DiminishMultiplier = 0.10,
        HardBlock         = true,
    },
    [3] = { -- The Vael Depths (Ring 3)
        SoftCap           = 30000,  -- SPEC-GAP placeholder
        DiminishThreshold = 0.82,
        DiminishMultiplier = 0.10,
        HardBlock         = true,
    },
    [4] = { -- The Gloam (Ring 4)
        SoftCap           = 100000, -- SPEC-GAP placeholder
        DiminishThreshold = 0.85,
        DiminishMultiplier = 0.10,
        HardBlock         = true,
    },
    [5] = { -- The Null — no cap, full power
        SoftCap           = math.huge,
        DiminishThreshold = 1.0,
        DiminishMultiplier = 1.0,
        HardBlock         = false,
    },
}

-- Resonance awarded per source (spec-gap placeholders)
-- SPEC-GAP: Exact per-kill amounts need design sign-off — issue #129.
local RESONANCE_GRANTS: {[ResonanceSource]: number} = {
    Kill_Dummy   = 10,   -- low — training target
    Kill_Player  = 50,   -- high — risk-reward
    Kill_Enemy   = 25,   -- mid — future PvE
    Exploration  = 15,   -- moderate flat discovery reward
    Survival     = 5,    -- per-tick in deep zones (future)
    Debug        = 9999, -- uncapped for testing
}

-- Fraction of ResonanceShards lost on death (15% per spec-gap doc)
-- SPEC-GAP: tracked in issue #129
local SHARD_LOSS_FRACTION = 0.15

-- Valid Discipline IDs for validation
local VALID_DISCIPLINES: {[string]: true} = {
    Wayward   = true,
    Ironclad  = true,
    Silhouette = true,
    Resonant  = true,
}

return {
    RING_CONFIGS          = RING_CONFIGS,
    RESONANCE_GRANTS      = RESONANCE_GRANTS,
    SHARD_LOSS_FRACTION   = SHARD_LOSS_FRACTION,
    VALID_DISCIPLINES     = VALID_DISCIPLINES,
}
