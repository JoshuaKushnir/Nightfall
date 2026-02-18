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

return {}
