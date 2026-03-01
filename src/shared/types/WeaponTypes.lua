--!strict
--[[
	WeaponTypes.lua

	Issue #68: WeaponModule Schema — typed definition and validator
	Epic #66: Modular Weapon Library & Equip System
	Epic: Phase 2 - Combat & Fluidity

	Strict Luau types for the weapon module format.
	Every weapon ModuleScript in src/shared/weapons/ must return a WeaponConfig.

	Usage:
		local WeaponTypes = require(ReplicatedStorage.Shared.types.WeaponTypes)
		type WeaponConfig = WeaponTypes.WeaponConfig
]]

-- ─── Enums ────────────────────────────────────────────────────────────────────

export type WeaponRarity   = "Common" | "Uncommon" | "Rare" | "Legendary"
export type WeaponToolType = "Melee" | "Ranged" | "Magic"

-- ─── Animation Entries ────────────────────────────────────────────────────────

--[[
	A single animation reference.
	Folder: folder name under ReplicatedStorage.animations (via AnimationLoader)
	Asset:  asset name within that folder
	HitFrame: optional 0–1 normalized time when the hit should register
]]
export type WeaponAnimEntry = {
	Folder: string,
	Asset: string,
	HitFrame: number?,
}

-- ─── Hitbox Config ────────────────────────────────────────────────────────────

export type WeaponHitbox = {
	Size: Vector3,
	-- CFrame offset relative to the character's HumanoidRootPart
	Offset: CFrame,
}

-- ─── Ability References ───────────────────────────────────────────────────────

export type WeaponAbilities = {
	Active: string?,   -- Id key into AbilityRegistry (e.g. "IronWill")
	Passive: string?,  -- Id key into AbilityRegistry (e.g. "Stagger")
}

-- ─── VFX / SFX ────────────────────────────────────────────────────────────────

export type WeaponEffects = {
	SwingTrail: string?,    -- rbxassetid:// for a particle/beam
	HitImpact: string?,     -- rbxassetid:// particle at hit position
	EquipSound: string?,    -- rbxassetid:// sound on equip
	HitSound: string?,      -- rbxassetid:// sound on hit
	BlockSound: string?,    -- rbxassetid:// sound on block
}

-- ─── Full Weapon Config ───────────────────────────────────────────────────────

export type WeaponConfig = {
	-- ── Identity (required) ──────────────────────────────────────────────────
	Id: string,
	Name: string,
	Description: string,
	Lore: string?,

	-- ── Rarity & Loot (required) ─────────────────────────────────────────────
	-- Rarity tier drives drop probability bracket.
	Rarity: WeaponRarity,
	-- Weight within the rarity tier when rolling from a loot pool (1–100).
	LootWeight: number,
	-- List of loot pool names this weapon belongs to (e.g. "WorldDrop", "BanditChest").
	LootPools: {string},

	-- ── Tool (required) ──────────────────────────────────────────────────────
	-- Asset id for the Tool's handle model ("" = placeholder until art is ready).
	ToolModelId: string,
	-- CFrame offset applied to the grip weld inside the handle.
	GripOffset: CFrame?,
	ToolType: WeaponToolType,
	-- Determines which Discipline's proficiency applies. Absent = always full proficiency.
	WeightClass: ("Light" | "Medium" | "Heavy")?

	-- ── Stats (required) ─────────────────────────────────────────────────────
	BaseDamage: number,
	-- Multiplier on base combo animation speed (< 1 = slower, > 1 = faster).
	AttackSpeed: number,
	-- Maximum hitbox reach in studs.
	Range: number,
	-- Multiplier on base knockback. Defaults to 1.0 if absent.
	KnockbackPower: number?,
	-- Movement speed modifier applied via MovementController while equipped.
	Weight: number?,
	-- cooldowns associated with this weapon (seconds)
	FeintCooldown: number?,  -- cooldown applied to feint actions
	HeavyCooldown: number?,  -- cooldown applied to the heavy attack action

	-- ── Animations (required) ────────────────────────────────────────────────
	Animations: {
		Equip: WeaponAnimEntry,
		Idle: WeaponAnimEntry,
		Walk: WeaponAnimEntry,
		Run: WeaponAnimEntry,
		-- Ordered combo sequence. Length determines max combo count for this weapon.
		Combo: {WeaponAnimEntry},
		LungeAttack: WeaponAnimEntry?,
		HeavyAttack: WeaponAnimEntry?,
	},

	-- ── Hitboxes (required) ──────────────────────────────────────────────────
	-- Keyed by attack type ("Default", "Heavy", "Lunge", etc.)
	Hitboxes: {[string]: WeaponHitbox},

	-- ── Abilities (optional) ─────────────────────────────────────────────────
	Abilities: WeaponAbilities?,

	-- ── VFX / SFX (optional) ─────────────────────────────────────────────────
	Effects: WeaponEffects?,
}


-- ─── Weapon Weight Class Definitions ───────────────────────────────────────

-- Five canonical weight classes describe the physical feel and discipline
-- affinity of a weapon.  Names and numbers are tuned in Section 3 of the
-- discipline combat spec (see issue #80).

export type WeaponWeightClass = "Stinger" | "Pivot" | "Bulwark" | "Breaker" | "Chord"

export type WeaponClassProfile = {
    displayName: string,
    flavour: string,
    nativeAccess: {string},    -- disciplines that wield this with full proficiency
    penaltyAccess: {string},   -- disciplines that can use it with a performance hit

    hpDamage: {light: number, heavy: number},     -- 0–100 scale proposals
    postureDamage: {light: number, heavy: number},

    attackSpeed: "very slow" | "slow" | "medium" | "fast" | "very fast",
    breathCostPerSwing: number,  -- typical breath cost for a combo string
    meleeReach: number,          -- approximate studs

    clashEligible: boolean,      -- very slow weapons may forego Clash
    grooveFlavour: string,       -- descriptive hint for Resonance Groove mods
}

local WeaponClassProfiles: {[WeaponWeightClass]: WeaponClassProfile} = {
    Stinger = {
        displayName = "Stinger",
        flavour = "A dagger‑light tool built for birds‑footed strikes.",
        nativeAccess = {"Silhouette"},
        penaltyAccess = {"Wayward","Ironclad","Resonant"},
        hpDamage = {light = 15, heavy = 25},
        postureDamage = {light = 10, heavy = 20},
        attackSpeed = "very fast",
        breathCostPerSwing = 5,
        meleeReach = 2.5,
        clashEligible = true,
        grooveFlavour = "rapid, darting jabs",
    },
    Pivot = {
        displayName = "Pivot",
        flavour = "A balanced blade that can be swung or thrust with equal ease.",
        nativeAccess = {"Wayward"},
        penaltyAccess = {"Silhouette","Ironclad","Resonant"},
        hpDamage = {light = 25, heavy = 40},
        postureDamage = {light = 20, heavy = 35},
        attackSpeed = "fast",
        breathCostPerSwing = 8,
        meleeReach = 3.0,
        clashEligible = true,
        grooveFlavour = "versatile arcs and cuts",
    },
    Bulwark = {
        displayName = "Bulwark",
        flavour = "A solid, dependable weapon for those who stand their ground.",
        nativeAccess = {"Wayward","Ironclad"},
        penaltyAccess = {"Silhouette","Resonant"},
        hpDamage = {light = 40, heavy = 60},
        postureDamage = {light = 35, heavy = 55},
        attackSpeed = "medium",
        breathCostPerSwing = 12,
        meleeReach = 3.5,
        clashEligible = true,
        grooveFlavour = "steady, wall‑breaking blows",
    },
    Breaker = {
        displayName = "Breaker",
        flavour = "A cumbersome implement that shatters posture with every swing.",
        nativeAccess = {"Ironclad"},
        penaltyAccess = {"Wayward","Silhouette","Resonant"},
        hpDamage = {light = 55, heavy = 80},
        postureDamage = {light = 60, heavy = 90},
        attackSpeed = "slow",
        breathCostPerSwing = 18,
        meleeReach = 4.0,
        clashEligible = false,  -- too slow to consistently clash
        grooveFlavour = "crushing, seismic strikes",
    },
    Chord = {
        displayName = "Chord",
        flavour = "An esoteric instrument‑weapon that resonates with intention.",
        nativeAccess = {"Resonant"},
        penaltyAccess = {"Wayward","Ironclad","Silhouette"},
        hpDamage = {light = 30, heavy = 45},
        postureDamage = {light = 25, heavy = 40},
        attackSpeed = "medium",
        breathCostPerSwing = 10,
        meleeReach = 3.0,
        clashEligible = true,
        grooveFlavour = "harmonic pulses and sustained notes",
    },
}

return {
    WeaponClassProfiles = WeaponClassProfiles,
}

