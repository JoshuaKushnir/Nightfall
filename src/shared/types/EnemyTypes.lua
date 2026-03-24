--!strict
--[[
    Class: EnemyTypes
    Description: Type definitions for the Modular Enemy System (MES).
    Dependencies: None
    Usage: Required by ModularEnemyService and other combat systems.
]]

export type EnemyStats = {
    MaxHealth: number,
    MaxPoise: number,
    MoveSpeed: number,
    AggroRange: number,
    AttackDamage: number,
    PostureDamage: number,
    ResonanceGrant: number,
    RespawnDelay: number,
}

export type EnemyPersonality = {
    Aggression: number,
    Caution: number,
    Feintiness: number,
    PackRole: string,
}

export type EnemyAttack = {
    Type: string,
    Range: number?,
    Telegraph: number?,
    Active: number?,
    Recovery: number?,
    Damage: number?,
    PoiseDmg: number?,
    Weight: number?,
    Anim: string?,
    Sfx: string?,
    HitboxOffset: CFrame?,
    Size: Vector3?,
    ComboFollow: string?,
    Velocity: number?,
    Duration: number?,
    Chance: number?,
    ReflectMult: number?,
    Distance: number?,
    Invuln: boolean?,
}

export type EnemyMoveset = {
    DisplayName: string,
    Stats: EnemyStats,
    Personality: EnemyPersonality,
    Attacks: { [string]: EnemyAttack },
    PatrolRadius: number,
    LeashRadius: number,
}

export type EnemyState = "Patrol" | "Alert" | "Combat" | "Dead" | "Attacking" | "Dodging" | "Blocking" | "Staggered"

export type EnemyData = {
    InstanceId: string,
    ConfigId: string,
    Model: Model,
    Moveset: EnemyMoveset,
    State: EnemyState,
    CurrentHealth: number,
    CurrentPoise: number,
    SpawnPosition: Vector3,
}

return {}
