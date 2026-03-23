--!strict
--[[
    Class: EffectHandlers
    Description: Registers all concrete effect implementations with EffectRunner.
                 Called once at server startup. Each handler corresponds to one
                 EffectDef.kind string.  To add a new effect type: add a new
                 Register() call here, reference the kind in ability data.
                 Nothing else needs to change.
    Issue: #170
    Dependencies: EffectRunner, PostureService, StateService, NetworkProvider
    Usage:
        -- In server runtime AFTER EffectRunner and PostureService are started:
        local EffectHandlers = require(...)
        EffectHandlers.RegisterAll(EffectRunner, PostureService, StateService, NetworkProvider)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StateService      = require(ReplicatedStorage.Shared.modules.core.StateService)

local EffectHandlers = {}

-- ─── Private helpers ─────────────────────────────────────────────────────────

-- Resolve a target's Character model regardless of whether target is a Player or Model
local function _getChar(target: any): Model?
    if typeof(target) == "Instance" then
        if target:IsA("Player") then
            return (target :: Player).Character
        elseif target:IsA("Model") then
            return target :: Model
        end
    end
    return nil
end

-- Retrieve a player's stat value by name from PlayerData (server StateService)
local function _getStat(casterPlayer: Player, statName: string): number
    local data = StateService:GetPlayerData(casterPlayer)
    if not data then return 0 end
    local stats = (data :: any).Stats
    if stats and type(stats[statName]) == "number" then
        return stats[statName]
    end
    return 0
end

-- Apply HP damage to a character via the IncomingHPDamage attribute pipeline
-- (read by CombatService._ProcessDamageAttributes on Heartbeat)
local function _applyHPDamage(char: Model, amount: number, source: string)
    local current = (char:GetAttribute("IncomingHPDamage") or 0) :: number
    char:SetAttribute("IncomingHPDamage", current + math.max(0, math.floor(amount)))
    char:SetAttribute("IncomingHPDamageSource", source)
end

-- Apply a status-effect attribute to a character for `duration` seconds
local function _applyStatus(char: Model, statusId: string, duration: number)
    char:SetAttribute("Status_" .. statusId, true)
    char:SetAttribute("StatusDuration_" .. statusId, duration)
    task.delay(duration, function()
        if char and char.Parent then
            char:SetAttribute("Status_" .. statusId, nil)
            char:SetAttribute("StatusDuration_" .. statusId, nil)
        end
    end)
end

-- ─── RegisterAll ─────────────────────────────────────────────────────────────

--[[
    Call this once at server bootstrap, after EffectRunner:Start().

    @param effectRunner   EffectRunner singleton
    @param postureService PostureService singleton (may be nil in test envs)
]]
function EffectHandlers.RegisterAll(effectRunner: any, postureService: any?)

    -- ── "Damage" ──────────────────────────────────────────────────────────────
    -- Deals HP damage to all targets in hitCtx.targets.
    -- Placeholder: base = 15 / 30 / 50 (depth 1/2/3 per spec).
    effectRunner:Register("Damage", function(
        def:      { kind: string, base: number?, scalingStat: string?,
                    scalingRatio: number?, damageType: string?, [string]: any },
        eventCtx: { casterPlayer: Player, abilityId: string, [string]: any },
        hitCtx:   { targets: {any}, [string]: any }?
    )
        if not hitCtx or #hitCtx.targets == 0 then return end

        local base = def.base or 15  -- placeholder depth-1 default
        local amount = base

        -- Stat scaling (optional)
        if def.scalingStat then
            local statVal = _getStat(eventCtx.casterPlayer, def.scalingStat)
            amount = amount + statVal * (def.scalingRatio or 1.0)
        end
        amount = math.floor(amount)

        for _, target in hitCtx.targets do
            local char = _getChar(target)
            if char then
                -- VFX STUB: intended effect — damage number flash on target
                _applyHPDamage(char, amount, eventCtx.abilityId .. "_Damage")
                print(("[EffectHandlers/Damage] %s → %s: %d HP (%s)")
                    :format(eventCtx.casterPlayer.Name, char.Name, amount, eventCtx.abilityId))
            end
        end
    end)

    -- ── "PostureDamage" ───────────────────────────────────────────────────────
    -- Drains posture on all targets via PostureService.
    -- Placeholder: postureBase = 15 / 25 / 35 per spec.
    effectRunner:Register("PostureDamage", function(
        def:      { kind: string, postureBase: number?, [string]: any },
        eventCtx: { casterPlayer: Player, abilityId: string, [string]: any },
        hitCtx:   { targets: {any}, [string]: any }?
    )
        if not hitCtx or #hitCtx.targets == 0 then return end
        if not postureService then
            warn("[EffectHandlers/PostureDamage] PostureService not available")
            return
        end

        local amount = def.postureBase or 15

        for _, target in hitCtx.targets do
            if typeof(target) == "Instance" and target:IsA("Player") then
                -- VFX STUB: intended effect — posture bar shake on target HUD
                postureService.DrainPosture(target, amount, "AspectHit")
                print(("[EffectHandlers/PostureDamage] %s → %s: %d posture")
                    :format(eventCtx.casterPlayer.Name, (target :: Player).Name, amount))
            end
        end
    end)

    -- ── "ApplyStatus" ────────────────────────────────────────────────────────
    -- Applies a named status effect to all targets for `duration` seconds.
    -- statusId examples: "Burning", "Grounded", "Slow", "Exposed", "Silenced"
    effectRunner:Register("ApplyStatus", function(
        def:      { kind: string, statusId: string?, duration: number?, [string]: any },
        eventCtx: { casterPlayer: Player, abilityId: string, [string]: any },
        hitCtx:   { targets: {any}, [string]: any }?
    )
        if not hitCtx or #hitCtx.targets == 0 then return end
        local statusId = def.statusId
        if not statusId or statusId == "" then
            warn("[EffectHandlers/ApplyStatus] missing statusId in effectDef")
            return
        end
        local duration = def.duration or 3

        for _, target in hitCtx.targets do
            local char = _getChar(target)
            if char then
                -- VFX STUB: intended effect — status icon appears on target HUD
                _applyStatus(char, statusId, duration)
                print(("[EffectHandlers/ApplyStatus] %s → %s: Status_%s (%.1fs)")
                    :format(eventCtx.casterPlayer.Name, char.Name, statusId, duration))
            end
        end
    end)

    -- ── "Knockback" ───────────────────────────────────────────────────────────
    -- Impulse push away from castOrigin.
    -- Placeholder knockback: 20 studs equivalent velocity.
    effectRunner:Register("Knockback", function(
        def:      { kind: string, knockbackDist: number?, [string]: any },
        eventCtx: { casterPlayer: Player, castOrigin: Vector3, abilityId: string, [string]: any },
        hitCtx:   { targets: {any}, [string]: any }?
    )
        if not hitCtx or #hitCtx.targets == 0 then return end
        local dist = def.knockbackDist or 20  -- placeholder

        for _, target in hitCtx.targets do
            local char = _getChar(target)
            if not char then continue end
            local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
            if not root then continue end
            local dir = (root.Position - eventCtx.castOrigin)
            if dir.Magnitude < 0.01 then dir = Vector3.new(1, 0, 0) end
            dir = dir.Unit
            -- VFX STUB: intended effect — dust cloud at knockback origin
            root.AssemblyLinearVelocity = dir * dist * 20
            print(("[EffectHandlers/Knockback] %s → %s: knockback %.0f")
                :format(eventCtx.casterPlayer.Name, char.Name, dist))
        end
    end)

    -- ── "Heal" ───────────────────────────────────────────────────────────────
    -- Restores HP to the caster (self-targeting).
    -- Placeholder: healBase = 15.
    effectRunner:Register("Heal", function(
        def:      { kind: string, healBase: number?, [string]: any },
        eventCtx: { casterPlayer: Player, abilityId: string, [string]: any },
        _hitCtx:  { targets: {any}, [string]: any }?
    )
        local char = eventCtx.casterPlayer.Character
        if not char then return end
        local humanoid = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
        if not humanoid then return end
        local amount = def.healBase or 15
        -- VFX STUB: intended effect — green heal pulse around caster
        humanoid.Health = math.min(humanoid.Health + amount, humanoid.MaxHealth)
        print(("[EffectHandlers/Heal] %s: +%d HP"):format(
            eventCtx.casterPlayer.Name, amount))
    end)

    print("[EffectHandlers] All handlers registered (Damage, PostureDamage, ApplyStatus, Knockback, Heal)")
end

-- ─── Lifecycle (service pattern) ─────────────────────────────────────────────
-- EffectHandlers is a plain module, not a service — no :Init/:Start needed.

return EffectHandlers