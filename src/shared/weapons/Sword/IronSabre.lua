--!strict
--[[
    IronSabre.lua
    Class: IronSabre
    Description: Reference weapon under the Sword class. Faster and lighter than
                 the Iron Sword — trades raw damage for a quicker three-hit combo
                 and better posture-break efficiency.
    Dependencies: WeaponTypes

    Issue: #171 — Weapon-attack pipeline, movement modifiers, registry class index

    Usage:
        Auto-discovered by WeaponRegistry via recursive folder scan of
        ReplicatedStorage.Shared.weapons.  No manual registration needed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTypesModule = require(ReplicatedStorage.Shared.types.WeaponTypes)
type WeaponConfig = WeaponTypesModule.WeaponConfig

local IronSabre: WeaponConfig = {
    -- ── Identity ──────────────────────────────────────────────────────────────
    Id          = "iron_sabre",
    Name        = "Iron Sabre",
    Description = "A curved iron blade favoured by outriders. Swift, relentless.",
    Lore        = "Worn at the hip by the Ashfields scouts.",

    -- ── Classification (#171) ─────────────────────────────────────────────────
    Class = "Sword",   -- used by WeaponRegistry.GetClass("Sword")

    -- ── Rarity & Loot ─────────────────────────────────────────────────────────
    Rarity     = "Common",
    LootWeight = 55,
    LootPools  = { "WorldDrop" },

    -- ── Tool ──────────────────────────────────────────────────────────────────
    ToolModelId = "",               -- TODO: rbxassetid:// once art is ready
    GripOffset  = CFrame.new(0, -1.0, 0),
    ToolType    = "Melee",
    WeightClass = "Medium",

    -- ── Stats ──────────────────────────────────────────────────────────────────
    BaseDamage     = 14,
    AttackSpeed    = 1.1,           -- slightly faster than base
    Range          = 5.0,
    KnockbackPower = 0.85,
    Weight         = 1.0,           -- no speed penalty

    -- ── Combat Timing (#171) ──────────────────────────────────────────────────
    PostureDamage      = 8,         -- light hit posture damage
    HeavyPostureDamage = 16,        -- heavy attack posture damage (2×)
    StaminaCost        = 12,        -- stamina cost per swing

    -- Per-swing duration overrides for the three-hit combo (seconds).
    -- Shorter than default to reflect the sabre's quicker tempo.
    LightSequence = { 0.55, 0.50, 0.45 },

    HeavyWindup     = 0.6,          -- windup before heavy attack lands
    HitWindowStart  = 0.15,         -- hitbox opens at 15% through the animation
    HitWindowEnd    = 0.25,         -- hitbox closes at 25% (tight window = precise timing)

    -- ── Animations ────────────────────────────────────────────────────────────
    Animations = {
        Equip = { Folder = "IronSabre", Asset = "Equip" },
        Idle  = { Folder = "IronSabre", Asset = "Idle"  },
        Walk  = { Folder = "IronSabre", Asset = "Walk"  },
        Run   = { Folder = "IronSabre", Asset = "Run"   },

        Combo = {
            { Folder = "IronSabre", Asset = "Slash1",   Id = "", HitFrame = 0.30 }, -- STUB
            { Folder = "IronSabre", Asset = "Slash2",   Id = "", HitFrame = 0.32 }, -- STUB
            { Folder = "IronSabre", Asset = "SpinSlash", Id = "", HitFrame = 0.28 }, -- STUB
        },

        LungeAttack = { Folder = "IronSabre", Asset = "LungeCut",  HitFrame = 0.40 },
        HeavyAttack = { Folder = "IronSabre", Asset = "CrossSlash", HitFrame = 0.50 },
    },

    -- ── Hitboxes ──────────────────────────────────────────────────────────────
    Hitboxes = {
        Default = {
            Size   = Vector3.new(5, 4, 4.5),
            Offset = CFrame.new(0, 0, -2.25),
        },
        Heavy = {
            Size   = Vector3.new(5.5, 4.5, 5),
            Offset = CFrame.new(0, 0, -2.5),
        },
        Lunge = {
            Size   = Vector3.new(3.5, 4, 6.5),
            Offset = CFrame.new(0, 0, -3.25),
        },
    },

    -- ── Abilities ─────────────────────────────────────────────────────────────
    Abilities = {
        Active  = nil,             -- no active ability yet (spec gap)
        Passive = "Bleed",         -- applies bleed on third combo hit (STUB)
    },

    -- ── Client Lifecycle Hooks (#171) ─────────────────────────────────────────
    -- These run purely on the client (cosmetic / sound); server never calls them.
    OnEquipClient = function(_char: Model, _weaponModel: Tool?)
        -- VFX STUB: play equip sound, activate weapon trail on weaponModel
    end,

    OnUnequipClient = function(_char: Model, _weaponModel: Tool?)
        -- VFX STUB: deactivate weapon trail, stop equip sound
    end,

    -- ── VFX / SFX ─────────────────────────────────────────────────────────────
    Effects = {
        SwingTrail = "",  -- TODO: rbxassetid://
        HitImpact  = "",  -- TODO: rbxassetid://
        EquipSound = "",  -- TODO: rbxassetid://
        HitSound   = "",  -- TODO: rbxassetid://
        BlockSound = "",  -- TODO: rbxassetid://
    },
}

return IronSabre
