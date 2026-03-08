--!strict
--[[
    Class: EffectTypes
    Description: Shared type definitions for the data-driven EffectRunner pipeline.
                 Every ability effect is described as an EffectDef table; the
                 EffectRunner dispatches to the correct handler by `kind`.
    Issue: #170
    Dependencies: None
]]

-- ─── Core effect descriptor ───────────────────────────────────────────────────

--[[
    EffectDef — the declarative description of one effect inside an ability.
    Ability files put these in an `effects = { ... }` array.
    Fields beyond `kind` are handler-specific; unused fields are ignored.
]]
export type EffectDef = {
    kind: string,            -- matches a registered handler key ("Damage", "ApplyStatus", …)
    tags: {string}?,         -- optional tags used by PassiveSystem filters (e.g. {"Melee","AoE"})

    -- "Damage" handler fields
    base: number?,           -- flat base HP damage (placeholder: 15 / 30 / 50)
    scalingStat: string?,    -- PlayerData stat name to scale with ("Strength", "Intelligence", …)
    scalingRatio: number?,   -- how much of the stat is added to base (default 1.0)
    damageType: string?,     -- "Physical" | "Magic" | "Expression" — for passive filtering

    -- "PostureDamage" handler fields
    postureBase: number?,    -- flat posture damage

    -- "ApplyStatus" handler fields
    statusId: string?,       -- e.g. "Burning", "Grounded", "Slow", "Exposed", "Silenced"
    duration: number?,       -- seconds

    -- "Knockback" handler fields
    knockbackDist: number?,  -- studs of impulse

    -- "Heal" handler fields
    healBase: number?,       -- flat HP to restore
}

-- ─── Runtime context tables ───────────────────────────────────────────────────

--[[
    EffectContext — built at request-time; shared across all effects in one cast.
]]
export type EffectContext = {
    casterId:        number,   -- player UserId
    casterPlayer:    Player,
    abilityId:       string,
    castOrigin:      Vector3,
    castTargetPoint: Vector3?,
}

--[[
    HitContext — populated when a hit is confirmed (nil for self-targeting effects).
]]
export type HitContext = {
    targets: {Player | Model},  -- confirmed hit targets
    hitPosition: Vector3?,
}

--[[
    EffectEvent — the mutable event object passed through PassiveSystem hooks.
    Handlers and passives read/write this table.
]]
export type EffectEvent = {
    effectDef:  EffectDef,
    eventCtx:   EffectContext,
    hitCtx:     HitContext?,
    -- Computed values that passives may modify before the handler fires
    computedDamage:  number?,
    computedPosture: number?,
    cancelled:       boolean,   -- if true, EffectRunner skips the handler
}

return {}