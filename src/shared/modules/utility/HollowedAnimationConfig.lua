--!strict
-- HollowedAnimationConfig: modular anim config per enemy variant.
-- Add/edit entries here to change what animations each variant plays.
-- HollowedService reads this at runtime - no changes needed there.
local RS = game:GetService('ReplicatedStorage')
local DB = require(RS.Shared.AnimationDatabase)

local FIST = {
    DB.Combat.General.Punch1, DB.Combat.General.Punch2,
    DB.Combat.General.Punch3, DB.Combat.General.Punch4,
    DB.Combat.General.Punch5, DB.Combat.General.LeftHit,
    DB.Combat.General.RightHit,
}
local HEAVY = {
    DB.Combat.General.Punch3,
    DB.Combat.General.Punch4,
    DB.Combat.General.Punch5,
}

local CONFIGS = {
    basic_hollowed      = { Movement={Idle=DB.Movement.Idle, Walk=DB.Movement.Running}, Attack={Pool=FIST,  BlockIdle=DB.Combat.General.BlockIdle} },
    ironclad_hollowed   = { Movement={Idle=DB.Movement.Idle, Walk=DB.Movement.Running}, Attack={Pool=HEAVY, BlockIdle=DB.Combat.General.BlockIdle} },
    silhouette_hollowed = { Movement={Idle=DB.Movement.Idle, Walk=DB.Movement.Running}, Attack={Pool=FIST,  BlockIdle=DB.Combat.General.BlockIdle} },
    resonant_hollowed   = { Movement={Idle=DB.Movement.Idle, Walk=DB.Movement.Running}, Attack={Pool={DB.Combat.General.Punch1,DB.Combat.General.Punch2,DB.Combat.General.LeftHit,DB.Combat.General.RightHit}, BlockIdle=DB.Combat.General.BlockIdle} },
    ember_hollowed      = { Movement={Idle=DB.Movement.Idle, Walk=DB.Movement.Running}, Attack={Pool=FIST,  BlockIdle=DB.Combat.General.BlockIdle} },
}

local M = {}

function M.Get(configId)
    return CONFIGS[configId] or CONFIGS.basic_hollowed
end

function M.PickAttack(configId)
    local pool = M.Get(configId).Attack.Pool
    local valid = {}
    for _, id in ipairs(pool) do
        if id and id ~= '' and id ~= 'rbxassetid://0' and id ~= 'rbxassetid://' then
            table.insert(valid, id)
        end
    end
    if #valid == 0 then return '' end
    return valid[math.random(1, #valid)]
end

return M