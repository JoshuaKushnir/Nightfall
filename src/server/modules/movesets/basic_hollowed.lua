--!strict
--[[
    Class: basic_hollowed
    Description: Moveset definition for the Wayward Hollowed enemy.
    Dependencies: None
    Usage: Required by ModularEnemyService to define the stats and behaviors of this enemy.
]]

local moveset = {
    DisplayName = "Wayward Hollowed",
    Stats = {
        MaxHealth = 80,
        MaxPoise = 100,
        MoveSpeed = 8,
        AggroRange = 30,
        AttackDamage = 12,
        PostureDamage = 18,
        ResonanceGrant = 25,
        RespawnDelay = 12,
    },
    Personality = {
        Aggression = 0.6,
        Caution = 0.4,
        Feintiness = 0.7,
        PackRole = "Flanker",
    },
    Attacks = {
        Slash1 = {
            Type = "Melee",
            Range = 5,
            Telegraph = 0.4,
            Active = 0.3,
            Recovery = 0.6,
            Damage = 12,
            PoiseDmg = 18,
            Weight = 1.0,
            Anim = "basic_hollowed.Slash1",
            Sfx = "slash_whoosh",
            HitboxOffset = CFrame.new(0, 0, -3),
            Size = Vector3.new(4, 4, 4),
            ComboFollow = "Slash2",
        },
        Slash2 = {
            Type = "Melee",
            Range = 5,
            Telegraph = 0.3,
            Active = 0.3,
            Recovery = 0.8,
            Damage = 15,
            PoiseDmg = 20,
            Weight = 0.0,
            Anim = "basic_hollowed.Slash2",
            Sfx = "slash_whoosh",
            HitboxOffset = CFrame.new(0, 0, -3),
            Size = Vector3.new(4, 4, 4),
        },
        Lunge = {
            Type = "MeleeLunge",
            Range = 8,
            Telegraph = 0.5,
            Active = 0.2,
            Recovery = 1.0,
            Damage = 18,
            PoiseDmg = 25,
            Weight = 0.4,
            Anim = "basic_hollowed.Lunge",
            Velocity = 15,
            HitboxOffset = CFrame.new(0, 0, -3),
            Size = Vector3.new(4, 4, 4),
        },
        ParryStance = {
            Type = "Defensive",
            Duration = 0.4,
            Chance = 0.2,
            ReflectMult = 1.5,
        },
        DodgeRoll = {
            Type = "Dodge",
            Distance = 7,
            Duration = 0.45,
            Invuln = true,
        },
    },
    PatrolRadius = 20,
    LeashRadius = 50,
}

return moveset
