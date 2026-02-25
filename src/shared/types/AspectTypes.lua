--!strict
--[[
    Class: AspectTypes
    Description: Declarations for types used by the Aspect System
    Dependencies: none (used by both client & server)
]]

export type AspectId = "Ash" | "Tide" | "Ember" | "Gale" | "Void" | "Marrow"
export type BranchId = "Expression" | "Form" | "Communion"

export type BranchDepth = 1 | 2 | 3

export type AspectBranchState = {
    Depth: number, -- 0 = no investment
    ShardsInvested: number,
}

export type PlayerAspectData = {
    AspectId: AspectId,
    IsUnlocked: boolean,
    Branches: {
        Expression: AspectBranchState,
        Form: AspectBranchState,
        Communion: AspectBranchState,
    },
    TotalShardsInvested: number,
}

export type AspectAbility = {
    Id: string,
    Name: string,
    AspectId: AspectId,
    Branch: BranchId,
    MinDepth: BranchDepth,         -- minimum branch depth to unlock
    BaseDamage: number?,            -- nil for Form/Communion
    PostureDamage: number?,
    ManaCost: number,
    Cooldown: number,
    CastTime: number,
    RequiredState: {string},        -- valid PlayerStates to cast from
    VFX_Function: (caster: Player, targetPosition: Vector3?) -> (),
    OnHit_Function: ((caster: Player, target: Player, damage: number) -> ())?,
}

export type AspectPassive = {
    Id: string,
    Name: string,
    AspectId: AspectId,
    Branch: BranchId,
    MinDepth: BranchDepth,
    ApplyEffect: (player: Player, playerData: any) -> (),
    RemoveEffect: (player: Player) -> (),
}

export type AspectSynergy = {
    AspectA: AspectId,
    AspectB: AspectId,
    Name: string,
    Description: string,
    -- Implementation deferred — define data, no behavior
}

export type AspectConfig = {
    Id: AspectId,
    DisplayName: string,
    Description: string,
    IsLocked: boolean,       -- true for Marrow
    ThemeColor: Color3,      -- for UI, set placeholder values
    MovementModifier: string, -- description only, implemented in MovementController later
}
