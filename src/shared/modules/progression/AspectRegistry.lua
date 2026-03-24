--!strict
--[[
    Class: AspectRegistry
    Description: Read-only data store containing all Aspect configurations,
                 abilities, passives, and synergies. No logic; consumers can query
                 for data only.
    Dependencies: AspectTypes
]]

local AspectTypes = require(script.Parent.Parent.Parent.types.AspectTypes)
local ItemTypes = require(script.Parent.Parent.Parent.types.ItemTypes)

local Registry = {}

-- Placeholder colors for UI themes
local ASPECT_COLORS: {[AspectTypes.AspectId]: Color3} = {
    Ash = Color3.fromRGB(128, 64, 0),
    Tide = Color3.fromRGB(0, 128, 192),
    Ember = Color3.fromRGB(192, 64, 0),
    Gale = Color3.fromRGB(192, 192, 64),
    Void = Color3.fromRGB(64, 0, 128),
    Marrow = Color3.fromRGB(96, 0, 0),
}

-- Aspect configs
Registry.Aspects = {} :: {[AspectTypes.AspectId]: AspectTypes.AspectConfig}
Registry.Aspects = {
    Ash = {
        Id = "Ash",
        DisplayName = "Ash",
        Description = "Concealment and misdirection.",
        IsLocked = false,
        ThemeColor = ASPECT_COLORS.Ash,
        MovementModifier = "Creates decoy trails when sprinting", -- design-only
    },
    Tide = {
        Id = "Tide",
        DisplayName = "Tide",
        Description = "Flow and terrain control.",
        IsLocked = false,
        ThemeColor = ASPECT_COLORS.Tide,
        MovementModifier = "Wet surfaces have slippery physics when moving", -- design-only
    },
    Ember = {
        Id = "Ember",
        DisplayName = "Ember",
        Description = "Aggression and sustained offense.",
        IsLocked = false,
        ThemeColor = ASPECT_COLORS.Ember,
        MovementModifier = "Leaves a faint trail of embers when dashing", -- design-only
    },
    Gale = {
        Id = "Gale",
        DisplayName = "Gale",
        Description = "Speed and aerial pressure.",
        IsLocked = false,
        ThemeColor = ASPECT_COLORS.Gale,
        MovementModifier = "Wind currents assist small jumps", -- design-only
    },
    Void = {
        Id = "Void",
        DisplayName = "Void",
        Description = "Phase and silence.",
        IsLocked = false,
        ThemeColor = ASPECT_COLORS.Void,
        MovementModifier = "Can phase through thin walls briefly", -- design-only
    },
    Marrow = {
        Id = "Marrow",
        DisplayName = "Marrow",
        Description = "Corruption and self-damage.",
        IsLocked = true,
        ThemeColor = ASPECT_COLORS.Marrow,
        MovementModifier = "Body seems heavier when airborne", -- design-only
    },
}

-- Ability and passive tables
Registry.Abilities = {} :: {[string]: AspectTypes.AspectAbility}
Registry.Passives = {} :: {[string]: AspectTypes.AspectPassive}

-- Move item registry (maps item id -> AspectMoveItem)
Registry.MoveItems = {} :: {[string]: ItemTypes.AspectMoveItem}

local function makeMoveItem(params: ItemTypes.AspectMoveItem)
    Registry.MoveItems[params.Id] = params
end

local function makeAbility(params: AspectTypes.AspectAbility)
    Registry.Abilities[params.Id] = params
end

local function makePassive(params: AspectTypes.AspectPassive)
    Registry.Passives[params.Id] = params
end

-- stub helpers for VFX and effects
local function emptyVFX(caster, targetPos)
    -- VFX stub; no visuals implemented yet
end

local function emptyEffect(player, playerData)
    -- Form passive stub
end

--[[
    Expression abilities are now registered via AbilityRegistry, which auto-discovers
    the Ash/Tide/Ember/Gale/Void moveset modules and registers each of the 5 moves
    per Aspect individually. AspectRegistry.Abilities holds only legacy or special-case
    entries (e.g. test utilities). Do not add hand-registered placeholder loops here.

    Form passives and Communion stubs are deferred tech debt (Phase 4+).
    Track in respective GitHub issues when scope is resolved.
]]

-- Marrow: locked Aspect — no abilities until Phase 4 design is finalised

-- cross-aspect synergies data
Registry.Synergies = {} :: {AspectTypes.AspectSynergy}
Registry.Synergies = {
    {
        AspectA = "Ash",
        AspectB = "Void",
        Name = "Deepghost",
        Description = "Dash reduces Luminance signature.",
    },
    {
        AspectA = "Tide",
        AspectB = "Gale",
        Name = "Stormfront",
        Description = "Sustained usage creates obscuring mist.",
    },
    {
        AspectA = "Ember",
        AspectB = "Marrow",
        Name = "Cauterize",
        Description = "Marrow self-damage converts to Posture recovery.",
    },
    {
        AspectA = "Ash",
        AspectB = "Tide",
        Name = "Mistveil",
        Description = "False trails persist longer.",
    },
    {
        AspectA = "Gale",
        AspectB = "Void",
        Name = "Slipstream",
        Description = "Phase-through on dash chains with Gale redirect.",
    },
    {
        AspectA = "Ember",
        AspectB = "Gale",
        Name = "Ignition Draft",
        Description = "Airborne targets take bonus Ember damage.",
    },
}

-- public API
function Registry.GetAspect(id: AspectTypes.AspectId)
    return Registry.Aspects[id]
end

function Registry.GetAbilitiesForAspect(id: AspectTypes.AspectId, branch: AspectTypes.BranchId?)
    local out = {}
    for _, ability in pairs(Registry.Abilities) do
        if ability.AspectId == id and (not branch or ability.Branch == branch) then
            table.insert(out, ability)
        end
    end
    return out
end

function Registry.GetPassivesForAspect(id: AspectTypes.AspectId, branch: AspectTypes.BranchId?)
    local out = {}
    for _, passive in pairs(Registry.Passives) do
        if passive.AspectId == id and (not branch or passive.Branch == branch) then
            table.insert(out, passive)
        end
    end
    return out
end

function Registry.GetSynergy(aspectA: AspectTypes.AspectId, aspectB: AspectTypes.AspectId)
    for _, syn in ipairs(Registry.Synergies) do
        if (syn.AspectA == aspectA and syn.AspectB == aspectB) or
           (syn.AspectA == aspectB and syn.AspectB == aspectA) then
            return syn
        end
    end
    return nil
end

return Registry
