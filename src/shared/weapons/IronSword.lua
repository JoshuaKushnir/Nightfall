--!strict
--[[
	IronSword.lua

	Issue #69: Weapon Equip System
	Issue #66: Modular Weapon Library & Equip System
	Epic: Phase 2 - Combat & Fluidity

	Complete sample weapon definition for the Iron Sword.
	Serves as the reference implementation for the WeaponConfig schema.

	Drop any WeaponConfig ModuleScript into src/shared/weapons/ and
	WeaponRegistry will auto-discover it on next startup — no other changes needed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTypesModule = require(ReplicatedStorage.Shared.types.WeaponTypes)
type WeaponConfig = WeaponTypesModule.WeaponConfig

local IronSword: WeaponConfig = {
	-- ── Identity ──────────────────────────────────────────────────────────────
	Id          = "iron_sword",
	Name        = "Iron Sword",
	Description = "A heavy blade forged from bog iron. Slow but punishing.",
	Lore        = "Carried by the soldiers of the Forgotten March.",

	-- ── Rarity & Loot ─────────────────────────────────────────────────────────
	Rarity      = "Common",
	LootWeight  = 60,           -- relative weight within the Common tier
	LootPools   = { "WorldDrop" },

	-- ── Tool ──────────────────────────────────────────────────────────────────
	ToolModelId = "",           -- TODO: replace with rbxassetid:// once art is ready
	GripOffset  = CFrame.new(0, -1.2, 0),
	ToolType    = "Melee",

	-- ── Stats ─────────────────────────────────────────────────────────────────
	BaseDamage     = 18,
	AttackSpeed    = 0.85,      -- 85% of base combo timing (slightly slower than fists)
	Range          = 5.5,       -- hitbox reach in studs
	KnockbackPower = 1.0,
	Weight         = 1.2,       -- applied as a speed modifier: player moves at 1/1.2 ≈ 83% speed

	-- ── Animations ────────────────────────────────────────────────────────────
	-- Folder names reference folders under ReplicatedStorage.animations
	-- Asset names reference individual AnimSaves within those folders
	Animations = {
		Equip = { Folder = "IronSword", Asset = "Equip" },
		Idle  = { Folder = "IronSword", Asset = "Idle"  },
		Walk  = { Folder = "IronSword", Asset = "Walk"  },
		Run   = { Folder = "IronSword", Asset = "Run"   },

		-- 3-hit combo sequence; length drives max combo count for this weapon
		Combo = {
			{ Folder = "IronSword", Asset = "Slash1",   HitFrame = 0.35 },
			{ Folder = "IronSword", Asset = "Slash2",   HitFrame = 0.40 },
			{ Folder = "IronSword", Asset = "Stab",     HitFrame = 0.30 },
		},

		LungeAttack = { Folder = "IronSword", Asset = "LungeSlash", HitFrame = 0.45 },
		HeavyAttack = { Folder = "IronSword", Asset = "Overhead",   HitFrame = 0.55 },
	},

	-- ── Hitboxes ──────────────────────────────────────────────────────────────
	Hitboxes = {
		Default = {
			Size   = Vector3.new(5, 4, 5),
			Offset = CFrame.new(0, 0, -2.5),
		},
		Heavy = {
			Size   = Vector3.new(6, 5, 6),
			Offset = CFrame.new(0, 0, -3.0),
		},
		Lunge = {
			Size   = Vector3.new(4, 4, 7),
			Offset = CFrame.new(0, 0, -3.5),
		},
	},

	-- ── Abilities ─────────────────────────────────────────────────────────────
	Abilities = {
		Active  = "IronWill", -- damage reduction active (see AbilityRegistry)
		Passive = "Stagger",  -- applies stagger to target on every 3rd hit
	},

	-- ── VFX / SFX ─────────────────────────────────────────────────────────────
	Effects = {
		SwingTrail  = "", -- TODO: rbxassetid://
		HitImpact   = "", -- TODO: rbxassetid://
		EquipSound  = "", -- TODO: rbxassetid://
		HitSound    = "", -- TODO: rbxassetid://
		BlockSound  = "", -- TODO: rbxassetid://
	},
}

return IronSword
