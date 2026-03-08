--!strict
--[[
    Class: EffectRunner
    Description: Central dispatcher for all ability effects.
                 Handlers are registered by `kind` string at startup (EffectHandlers.lua).
                 Every Run() call fires BeforeEffect → handler → AfterEffect hooks through
                 PassiveSystem, so passives can intercept and modify any effect.
    Issue: #170
    Dependencies: (PassiveSystem injected at runtime to break circular require)
    Usage:
        -- In EffectHandlers.lua (startup):
        EffectRunner:Register("Damage", fn)
        -- In AbilitySystem:
        EffectRunner:Run(effectDef, eventCtx, hitCtx, passiveSystem)
]]

local EffectRunner = {}
EffectRunner.__index = EffectRunner

-- ─── Types (local aliases) ────────────────────────────────────────────────────

type EffectDef     = { kind: string, [string]: any }
type EffectContext  = { casterId: number, casterPlayer: Player, abilityId: string,
                        castOrigin: Vector3, castTargetPoint: Vector3? }
type HitContext    = { targets: {any}, hitPosition: Vector3? }
type EffectEvent   = { effectDef: EffectDef, eventCtx: EffectContext, hitCtx: HitContext?,
                       computedDamage: number?, computedPosture: number?, cancelled: boolean }
type HandlerFn     = (effectDef: EffectDef, eventCtx: EffectContext, hitCtx: HitContext?) -> ()
type PassiveSystem = { ApplyHooks: (PassiveSystem, string, EffectEvent) -> () }

-- ─── Internal state ───────────────────────────────────────────────────────────

local _handlers: {[string]: HandlerFn} = {}
local _initialized = false

-- ─── Public API ───────────────────────────────────────────────────────────────

--[[
    Register an effect handler.
    @param kind     string — must match EffectDef.kind in ability data
    @param handler  fn(effectDef, eventCtx, hitCtx?) → ()
]]
function EffectRunner:Register(kind: string, handler: HandlerFn)
    if _handlers[kind] then
        warn(("[EffectRunner] Overwriting handler for kind '%s'"):format(kind))
    end
    _handlers[kind] = handler
    print(("[EffectRunner] ✓ Registered: %s"):format(kind))
end

--[[
    Run one effect through the full pipeline:
        1. Build EffectEvent
        2. PassiveSystem:ApplyHooks("BeforeEffect", event)
        3. If not cancelled → call handler
        4. PassiveSystem:ApplyHooks("AfterEffect", event)

    @param effectDef     EffectDef
    @param eventCtx      EffectContext  (cast metadata)
    @param hitCtx        HitContext?    (nil for self-targeting effects)
    @param passiveSystem PassiveSystem  (injected to avoid circular require)
]]
function EffectRunner:Run(
    effectDef:     EffectDef,
    eventCtx:      EffectContext,
    hitCtx:        HitContext?,
    passiveSystem: PassiveSystem?
)
    local handler = _handlers[effectDef.kind]
    if not handler then
        warn(("[EffectRunner] No handler registered for kind '%s' (ability: %s)")
            :format(effectDef.kind, eventCtx.abilityId))
        return
    end

    -- Build mutable event table
    local event: EffectEvent = {
        effectDef        = effectDef,
        eventCtx         = eventCtx,
        hitCtx           = hitCtx,
        computedDamage   = effectDef.base,
        computedPosture  = effectDef.postureBase,
        cancelled        = false,
    }

    -- Before-effect passive hooks (may modify computedDamage, set cancelled, etc.)
    if passiveSystem then
        local ok, err = pcall(passiveSystem.ApplyHooks, passiveSystem, "BeforeEffect", event)
        if not ok then
            warn(("[EffectRunner] PassiveSystem BeforeEffect error: %s"):format(tostring(err)))
        end
    end

    if event.cancelled then
        print(("[EffectRunner] Effect '%s' cancelled by passive"):format(effectDef.kind))
        return
    end

    -- Write passive-modified values back to effectDef copies so handlers see them
    local resolvedDef: EffectDef = table.clone(effectDef) :: any
    if event.computedDamage ~= nil then
        resolvedDef.base = event.computedDamage
    end
    if event.computedPosture ~= nil then
        resolvedDef.postureBase = event.computedPosture
    end

    -- Fire the handler
    local ok2, err2 = pcall(handler, resolvedDef, eventCtx, hitCtx)
    if not ok2 then
        warn(("[EffectRunner] Handler '%s' error: %s"):format(effectDef.kind, tostring(err2)))
    end

    -- After-effect passive hooks
    if passiveSystem then
        local ok3, err3 = pcall(passiveSystem.ApplyHooks, passiveSystem, "AfterEffect", event)
        if not ok3 then
            warn(("[EffectRunner] PassiveSystem AfterEffect error: %s"):format(tostring(err3)))
        end
    end
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function EffectRunner:Init(_deps: {[string]: any}?)
    _initialized = true
    print("[EffectRunner] Initialized")
end

function EffectRunner:Start()
    print("[EffectRunner] Started — handlers will be registered by EffectHandlers")
end

return EffectRunner