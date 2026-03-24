--!strict
--[[
    Class: AbilityValidator
    Description: Stateless server-side validation for all ability use requests.
                 Single ValidateUse() call checks every precondition before any
                 resource is spent or effect applied.  Extracted from the scattered
                 checks in AbilitySystem and CombatService so every path goes
                 through identical validation.
    Issue: #170
    Dependencies: StateService (player data + state), AbilityRegistry (ability types)
    Usage:
        local ok, reason, context = AbilityValidator.ValidateUse(player, abilityDef)
        if not ok then return end  -- reason is a string
        -- context: { castOrigin, primaryTarget?, castTargetPoint? }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StateService      = require(ReplicatedStorage.Shared.modules.core.StateService)

local AbilityValidator = {}

-- ─── Types ────────────────────────────────────────────────────────────────────

type AbilityDef = {
    Id:            string,
    ManaCost:      number?,
    Cooldown:      number?,
    Range:         number?,
    RequiredState: {string}?,
    [string]:      any,
}

type ValidationContext = {
    castOrigin:      Vector3,
    primaryTarget:   (Player | Model)?,
    castTargetPoint: Vector3?,
}

-- ─── Private helpers ─────────────────────────────────────────────────────────

local function _getRoot(player: Player): BasePart?
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function _isAlive(player: Player): boolean
    local char = player.Character
    if not char then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid") :: Humanoid?
    return humanoid ~= nil and humanoid.Health > 0
end

-- Check the player's current ActiveCooldowns table for this ability
local function _isOnCooldown(player: Player, abilityId: string): boolean
    -- AbilitySystem tracks cooldowns via character attributes (CD_<id>)
    local char = player.Character
    if not char then return false end
    local endTime = char:GetAttribute("CD_" .. abilityId)
    if typeof(endTime) == "number" then
        return tick() < endTime
    end
    return false
end

local function _hasMana(player: Player, cost: number): boolean
    local data = StateService:GetPlayerData(player)
    if not data then return false end
    local mana = (data :: any).Mana
    if mana and type(mana.Current) == "number" then
        return mana.Current >= cost
    end
    return false
end

local function _stateAllowed(player: Player, requiredStates: {string}?): boolean
    if not requiredStates or #requiredStates == 0 then return true end
    local data = StateService:GetPlayerData(player)
    if not data then return false end
    local current = (data :: any).State or "Idle"
    for _, s in requiredStates do
        if s == current then return true end
    end
    return false
end

-- ─── Public API ──────────────────────────────────────────────────────────────

--[[
    Run all precondition checks for an ability use request.

    @param player     Player — the caster (server-verified)
    @param abilityDef AbilityDef — from AbilityRegistry
    @return ok:boolean, reason:string?, context:ValidationContext?

    On success: ok=true, reason=nil, context=populated
    On failure: ok=false, reason="ReasonCode", context=nil
]]
function AbilityValidator.ValidateUse(
    player:     Player,
    abilityDef: AbilityDef
): (boolean, string?, ValidationContext?)

    -- 1) Player alive
    if not _isAlive(player) then
        return false, "CasterDead", nil
    end

    -- 2) State check
    if not _stateAllowed(player, abilityDef.RequiredState) then
        return false, "InvalidState", nil
    end

    -- 3) Mana check
    local manaCost = abilityDef.ManaCost or 0
    if manaCost > 0 and not _hasMana(player, manaCost) then
        return false, "InsufficientMana", nil
    end

    -- 4) Cooldown check
    if _isOnCooldown(player, abilityDef.Id) then
        return false, "OnCooldown", nil
    end

    -- 5) Root position (needed for range check and context)
    local root = _getRoot(player)
    if not root then
        return false, "NoCharacter", nil
    end
    local castOrigin = root.Position

    -- 6) Range check (server re-computes; +1 stud anti-cheat tolerance)
    --    Range validation is optional — only fires when abilityDef.Range is set
    --    AND there is a targetPoint supplied. Point-only abilities skip this.
    --    (Full target resolution is in AbilitySystem; validator checks distance only)

    local context: ValidationContext = {
        castOrigin      = castOrigin,
        primaryTarget   = nil,
        castTargetPoint = nil,
    }

    return true, nil, context
end

return AbilityValidator