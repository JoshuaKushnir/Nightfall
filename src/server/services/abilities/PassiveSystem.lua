--!strict
--[[
    Class: PassiveSystem
    Description: Iterates all active passives for a caster and applies their hooks
                 to the mutable EffectEvent that EffectRunner passes through.
                 This issue implements only "BeforeEffect", "AfterEffect", and
                 "OnOutgoingDamage" hook stages. Full talent hooks (OnParry, OnDodge)
                 are deferred until the Talent system issue.
    Issue: #170
    Dependencies: AbilityRegistry, StateService (for equipped passives lookup)
    Usage:
        local PassiveSystem = require(...)
        PassiveSystem:Init(deps)
        PassiveSystem:Start()
        -- In EffectRunner:
        PassiveSystem:ApplyHooks("BeforeEffect", event)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AbilityRegistry   = require(ReplicatedStorage.Shared.modules.combat.AbilityRegistry)
local StateService      = require(ReplicatedStorage.Shared.modules.core.StateService)

local PassiveSystem = {}
PassiveSystem.__index = PassiveSystem

-- ─── Types ────────────────────────────────────────────────────────────────────

type EffectEvent = {
    effectDef:       { kind: string, tags: {string}?, [string]: any },
    eventCtx:        { casterId: number, casterPlayer: Player, abilityId: string, [string]: any },
    hitCtx:          { targets: {any}, hitPosition: Vector3? }?,
    computedDamage:  number?,
    computedPosture: number?,
    cancelled:       boolean,
}

type PassiveDef = {
    Id:    string,
    Type:  string,
    hooks: { [string]: { { filters: {[string]: any}?, modifier: {[string]: any}? } } }?,
    [string]: any,
}

-- ─── Private helpers ─────────────────────────────────────────────────────────

-- Returns all passive ability configs active for a player.
-- Currently sources from AspectData passives (unlocked branch passives) and
-- any weapon passives registered in AbilityRegistry.
local function _getActivePassives(player: Player): {PassiveDef}
    local result: {PassiveDef} = {}

    -- Weapon passive (from AbilityRegistry via Type == "Passive" entries)
    local allAbilities = AbilityRegistry.GetAll()
    for _, ability in allAbilities do
        if type(ability) == "table" and ability.Type == "Passive" then
            -- Only include if this player has it (currently: any registered passive applies)
            -- TODO: Filter by equipped weapon when WeaponService lookup is stable
            table.insert(result, ability :: PassiveDef)
        end
    end

    return result
end

-- Check if a passive hook's filters match the event
local function _filterMatches(filters: {[string]: any}?, event: EffectEvent): boolean
    if not filters then return true end

    -- Tag filter: passive only fires if effectDef has the required tag
    if filters.tag then
        local tags = event.effectDef.tags
        if not tags then return false end
        local found = false
        for _, t in tags do
            if t == filters.tag then found = true; break end
        end
        if not found then return false end
    end

    -- Kind filter
    if filters.kind and event.effectDef.kind ~= filters.kind then
        return false
    end

    return true
end

-- Apply one modifier to the mutable event
local function _applyModifier(modifier: {[string]: any}, event: EffectEvent)
    if modifier.kind == "Multiply" then
        if modifier.field == "computedDamage" and event.computedDamage ~= nil then
            event.computedDamage = event.computedDamage * (modifier.value or 1)
        elseif modifier.field == "computedPosture" and event.computedPosture ~= nil then
            event.computedPosture = event.computedPosture * (modifier.value or 1)
        end
    elseif modifier.kind == "Add" then
        if modifier.field == "computedDamage" then
            event.computedDamage = (event.computedDamage or 0) + (modifier.value or 0)
        elseif modifier.field == "computedPosture" then
            event.computedPosture = (event.computedPosture or 0) + (modifier.value or 0)
        end
    elseif modifier.kind == "Cancel" then
        event.cancelled = true
    end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
    Apply all matching passive hooks for the given stage to the event.
    Mutates event in place (passive modifiers write to event.computedDamage, etc.)

    @param stage  "BeforeEffect" | "AfterEffect" | "OnOutgoingDamage"
    @param event  EffectEvent (mutable)
]]
function PassiveSystem:ApplyHooks(stage: string, event: EffectEvent)
    local casterPlayer = event.eventCtx.casterPlayer
    if not casterPlayer then return end

    local passives = _getActivePassives(casterPlayer)

    for _, passiveDef in passives do
        local hooksForStage = passiveDef.hooks and passiveDef.hooks[stage]
        if not hooksForStage then continue end

        for _, hookEntry in hooksForStage do
            if _filterMatches(hookEntry.filters, event) then
                if hookEntry.modifier then
                    _applyModifier(hookEntry.modifier, event)
                end
            end
        end
    end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function PassiveSystem:Init(_deps: {[string]: any}?)
    print("[PassiveSystem] Initialized")
end

function PassiveSystem:Start()
    print("[PassiveSystem] Started")
end

return PassiveSystem