--!strict
--[[
    Class: ProgressionTypes
    Description: Type definitions for the Progression system — Resonance,
                 Ring soft caps with diminishing returns, stat-based progression,
                 and Omen marks. Discipline is a computed soft label, not a lock.
    Dependencies: None

    Issue #138: ProgressionService — Resonance grants, Ring soft caps, Shard loss
    Issue #140: Stat-based progression — replace Discipline lock-in
    Epic #51: Phase 4 — World & Narrative
]]

-- ─── Ring Identifiers ─────────────────────────────────────────────────────────

-- Numeric ring index (0 = Hearthspire social hub, 5 = The Null endgame zone)
export type RingId = number  -- 0-5

-- ─── Discipline Identifiers ───────────────────────────────────────────────────
-- DisciplineId is now a *computed soft label* derived from the player's stat
-- allocation — not a locked choice.  It updates every time stats change.
export type DisciplineId = "Wayward" | "Ironclad" | "Silhouette" | "Resonant"

-- ─── Stat Names ───────────────────────────────────────────────────────────────
export type StatName =
    | "Strength"     -- physical power; HealthMax + BreakBase
    | "Fortitude"    -- defensive endurance; PostureMax + PostureRecovery
    | "Agility"      -- mobility; Breath pool (Phase 2+)
    | "Intelligence" -- Aspect / mana; ManaMax + ManaRegen
    | "Willpower"    -- mana half-rate; DebuffResist (Phase 4+)
    | "Charisma"     -- social / NPC (Phase 4+, no current game effect)

-- ─── Stat Allocation Map ──────────────────────────────────────────────────────
export type StatAllocation = {
    Strength:     number,
    Fortitude:    number,
    Agility:      number,
    Intelligence: number,
    Willpower:    number,
    Charisma:     number,
}

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
    DisciplineId: DisciplineId,  -- computed soft label
    OmenMarks: number,
    StatPoints: number,          -- unspent points available to allocate
    Stats: StatAllocation,       -- how many points are in each stat
}

-- Sent client→server: request to spend stat points
export type StatAllocatePacket = {
    StatName: StatName,
    Amount: number,  -- number of points to invest (usually 1)
}

-- Sent server→client: confirms allocation + sends updated values
export type StatAllocatedPacket = {
    StatName: StatName,
    NewAmount: number,        -- total points in that stat after this change
    StatPoints: number,       -- remaining unspent points
    DisciplineId: DisciplineId, -- recalculated soft label
    -- Updated derived combat values
    HealthMax: number,
    PostureMax: number,
    ManaMax: number,
    ManaRegen: number,
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

-- Valid stat names for request validation
local VALID_STAT_NAMES: {[string]: true} = {
    Strength     = true,
    Fortitude    = true,
    Agility      = true,
    Intelligence = true,
    Willpower    = true,
    Charisma     = true,
}

-- TotalResonance milestone interval for stat point awards
-- Every STAT_POINT_MILESTONE cumulative Resonance = 1 new unspent StatPoint
-- SPEC-GAP: value is a placeholder — issue #129
local STAT_POINT_MILESTONE = 200

-- Configuration flag to enable/disable stat point milestone awards
-- When false, players must use training tools to increase stats instead of earning StatPoints from Resonance
local ENABLE_STAT_POINT_MILESTONES = true

-- Maximum points a player may invest in a single stat
-- SPEC-GAP: cap needs design sign-off — issue #129
local STAT_MAX_PER_STAT = 20

-- Training tool stat level caps by rarity
-- Higher rarity tools can level stats higher; lower rarity tools have a cap
local TRAINING_TOOL_STAT_CAPS: {[string]: number} = {
    Common   = 5,   -- Common tools can only level stat up to 5
    Uncommon = 10,  -- Uncommon tools can level up to 10
    Rare     = 20,  -- Rare tools can level up to 20 (matches STAT_MAX_PER_STAT)
    Legendary = 20, -- Legendary tools can also level to max
}

-- How much each allocated point adds to combat values (server-authoritative)
-- Layout: { HealthMax, PostureMax, ManaMax, ManaRegen, BreakBase }
-- SPEC-GAP: scaling values are design placeholders — issue #129
local STAT_PER_POINT: {[string]: {[string]: number}} = {
    Strength     = { HealthMax = 5, BreakBase = 2 },
    Fortitude    = { PostureMax = 6, PostureRecovery = 0.2 },
    Agility      = {},        -- Breath system (Phase 2+); no current derived value
    Intelligence = { ManaMax = 8, ManaRegen = 0.3 },
    Willpower    = { ManaMax = 4, ManaRegen = 0.1 },
    Charisma     = {},        -- Phase 4 social; no current derived value
}

-- Which stat dominance maps to which Discipline soft label.
-- Evaluated server-side in _computeDisciplineLabel().
-- Fortitude → Ironclad, Agility → Silhouette, Intelligence → Resonant, else Wayward
local DISCIPLINE_STAT_MAP: {[DisciplineId]: {string}} = {
    Ironclad   = { "Fortitude" },
    Silhouette = { "Agility" },
    Resonant   = { "Intelligence", "Willpower" },
    Wayward    = { "Strength", "Charisma" },
}

return {
    RING_CONFIGS              = RING_CONFIGS,
    RESONANCE_GRANTS          = RESONANCE_GRANTS,
    SHARD_LOSS_FRACTION       = SHARD_LOSS_FRACTION,
    VALID_STAT_NAMES          = VALID_STAT_NAMES,
    STAT_POINT_MILESTONE      = STAT_POINT_MILESTONE,
    ENABLE_STAT_POINT_MILESTONES = ENABLE_STAT_POINT_MILESTONES,
    STAT_MAX_PER_STAT         = STAT_MAX_PER_STAT,
    STAT_PER_POINT            = STAT_PER_POINT,
    DISCIPLINE_STAT_MAP       = DISCIPLINE_STAT_MAP,
    TRAINING_TOOL_STAT_CAPS   = TRAINING_TOOL_STAT_CAPS,
}
