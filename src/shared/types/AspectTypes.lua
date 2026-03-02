--!strict
--[[
    Class: AspectTypes
    Description: Declarations for types used by the Aspect System.
                 Each Aspect is an attunement with a full moveset of 5 abilities
                 and 3 talent stubs per ability (like Deepwoken attunements).
    Dependencies: none (used by both client & server)
]]

export type AspectId = "Ash" | "Tide" | "Ember" | "Gale" | "Void" | "Marrow"
export type BranchId = "Expression" | "Form" | "Communion"

-- Role each move plays within its Aspect kit
export type MoveType = "Offensive" | "Defensive" | "UtilityProc" | "SelfBuff"

---
--- BranchDepth represents investment tiers; runtime logic enforces values 1–3.
--- Using plain number type because Luau does not support numeric literal unions.
export type BranchDepth = number

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

--[[
    AspectTalent — one of the three talent stubs attached to every move.
    Talent hooks are coded as stubs now; full implementation is deferred until all
    Depth-1 moves are verified in Studio and the Talent system infrastructure exists.
    (See docs/Game Plan/Depth1_Expression_Moves.md footer note.)
]]
export type AspectTalent = {
    Id: string,              -- e.g. "HollowEcho"
    Name: string,            -- display name
    InteractsWith: string,   -- system mechanic this talent hooks into (e.g. "Stagger", "Momentum")
    Description: string,     -- full design description from spec
    IsUnlocked: boolean,     -- always false until Talent system is built
    -- OnActivate stub — to be wired when talent system exists
    OnActivate: ((player: Player, context: any) -> ())?,
}

export type AspectAbility = {
    -- Identity
    Id: string,
    Name: string,
    AspectId: AspectId,
    Slot: number,            -- 1-5 position within the moveset
    MoveType: MoveType,      -- role: Offensive / Defensive / UtilityProc / SelfBuff
    Type: string,            -- always "Expression" for moveset abilities
    Description: string,

    -- Legacy branch fields (kept for backward compat with AspectRegistry passives)
    Branch: BranchId?,
    MinDepth: BranchDepth?,

    -- Combat values
    BaseDamage: number?,     -- nil if move deals no direct HP damage
    PostureDamage: number?,  -- nil if move deals no posture damage
    ManaCost: number,
    Cooldown: number,        -- seconds
    CastTime: number,        -- seconds before effect lands

    -- Hitbox
    Range: number?,          -- sphere radius (studs); default applied in AspectService
    IsAoE: boolean?,         -- true → ValidateAoEHit used

    -- State gating
    RequiredState: {string}, -- valid PlayerStates to cast from

    -- Talents (3 stubs per move, all IsUnlocked = false at Depth 1)
    Talents: {AspectTalent},

    -- Execution hooks
    VFX_Function: (caster: Player, targetPosition: Vector3?) -> (),
    OnActivate: (player: Player, targetPos: Vector3?) -> (),
    ClientActivate: ((targetPosition: Vector3?) -> ())?,

    -- Optional hit callback
    OnHit_Function: ((caster: Player, target: Player, damage: number) -> ())?,
}

--[[
    AspectMoveset — returned by each ability file.
    Each file in src/shared/abilities/ that corresponds to an Aspect returns one of these.
    AbilityRegistry detects the .Moves field and registers each move individually.
]]
export type AspectMoveset = {
    AspectId: AspectId,
    DisplayName: string,
    Moves: {AspectAbility},  -- exactly 5 per Aspect at Depth 1
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
    IsLocked: boolean,        -- true for Marrow
    ThemeColor: Color3,       -- for UI
    MovementModifier: string, -- description only, implemented in MovementController later
}

-- return a table with type aliases for runtime requires
local _exports: any = {}
_exports.AspectId = ({} :: any) :: AspectId
_exports.BranchId = ({} :: any) :: BranchId
_exports.MoveType = ({} :: any) :: MoveType
_exports.BranchDepth = ({} :: any) :: BranchDepth
_exports.AspectBranchState = ({} :: any) :: AspectBranchState
_exports.PlayerAspectData = ({} :: any) :: PlayerAspectData
_exports.AspectTalent = ({} :: any) :: AspectTalent
_exports.AspectAbility = ({} :: any) :: AspectAbility
_exports.AspectMoveset = ({} :: any) :: AspectMoveset
_exports.AspectPassive = ({} :: any) :: AspectPassive
_exports.AspectSynergy = ({} :: any) :: AspectSynergy
_exports.AspectConfig = ({} :: any) :: AspectConfig

return _exports
