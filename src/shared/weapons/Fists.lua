--!strict
--[[
	Fists.lua

	Issue #66: Modular Weapon Library & Equip System
	Epic: Phase 2 - Combat & Fluidity

	The default weapon every player spawns with.
	No model, no loot pool — always equipped automatically by WeaponService
	when a character loads.  Serves as the baseline for all combat stats.

	5-hit combo using the existing "punch N" animation assets under the
	"Fists" folder in ReplicatedStorage.animations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTypesModule = require(ReplicatedStorage.Shared.types.WeaponTypes)
type WeaponConfig = WeaponTypesModule.WeaponConfig

local Fists: WeaponConfig = {
	-- ── Identity ──────────────────────────────────────────────────────────────
	Id          = "fists",
	Name        = "Fists",
	Description = "Your bare hands. Better than nothing.",
	Lore        = "",

	-- ── Rarity & Loot ─────────────────────────────────────────────────────────
	Rarity      = "Common",
	LootWeight  = 1,     -- minimum valid value; fists are never in a loot pool
	LootPools   = {},    -- intentionally empty

	-- ── Tool ──────────────────────────────────────────────────────────────────
	ToolModelId = "",   -- no visible tool model
	GripOffset  = CFrame.new(),
	ToolType    = "Melee",

	-- ── Stats ─────────────────────────────────────────────────────────────────
	BaseDamage     = 6,
	AttackSpeed    = 1.0,   -- baseline speed; other weapons are relative to this
	Range          = 3.5,   -- shorter reach than any bladed weapon
	KnockbackPower = 0.5,
	Weight         = 0.1,   -- near-zero; no meaningful movement penalty

	-- ── Animations ────────────────────────────────────────────────────────────
	-- Reuses the existing punch 1-5 animation assets already in the project.
	Animations = {
		Equip = { Folder = "Fists", Asset = "Idle"  }, -- no special equip anim
		Idle  = { Folder = "Fists", Asset = "Idle"  },
		Walk  = { Folder = "Fists", Asset = "Walk"  },
		Run   = { Folder = "Fists", Asset = "Run"   },

		-- 5-hit combo — matches legacy "punch N" names ActionController used
		Combo = {
			{ Folder = "Fists", Asset = "punch 1", HitFrame = 0.40 },
			{ Folder = "Fists", Asset = "punch 2", HitFrame = 0.40 },
			{ Folder = "Fists", Asset = "punch 3", HitFrame = 0.40 },
			{ Folder = "Fists", Asset = "punch 4", HitFrame = 0.40 },
			{ Folder = "Fists", Asset = "punch 5", HitFrame = 0.35 },
		},

		LungeAttack = { Folder = "Fists", Asset = "punch 2", HitFrame = 0.45 },
		HeavyAttack = { Folder = "Fists", Asset = "punch 5", HitFrame = 0.50 },
	},

	-- ── Hitboxes ──────────────────────────────────────────────────────────────
	Hitboxes = {
		Default = {
			Size   = Vector3.new(3.5, 3.5, 3.5),
			Offset = CFrame.new(0, 0, -1.75),
		},
		Heavy = {
			Size   = Vector3.new(4, 4, 4),
			Offset = CFrame.new(0, 0, -2.0),
		},
		Lunge = {
			Size   = Vector3.new(3, 3, 5),
			Offset = CFrame.new(0, 0, -2.5),
		},
	},

	-- ── Abilities ─────────────────────────────────────────────────────────────
	Abilities = {
		Active  = nil,  -- no active ability
		Passive = nil,  -- no passive ability
	},

	-- ── VFX / SFX ─────────────────────────────────────────────────────────────
	Effects = {
		SwingTrail = "",
		HitImpact  = "",
		EquipSound = "",
		HitSound   = "",
		BlockSound = "",
	},
}

return Fists
