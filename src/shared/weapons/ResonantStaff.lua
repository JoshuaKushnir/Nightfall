--!strict
--[[
	ResonantStaff.lua

	Issue #132: WeaponRegistry — define 5 starter weapons
	Epic #66: Modular Weapon Library & Equip System

	Starter weapon for the Resonant discipline.
	A channeling staff — slow swings and long reach. Resonants leverage
	their Aspect/magic investment rather than pure melee volume, so this
	weapon complements cast-heavy play rather than replacing it.

	Stats are placeholders (✏️) pending Phase 4 balancing pass.

	Dependencies: WeaponTypes
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTypesModule = require(ReplicatedStorage.Shared.types.WeaponTypes)
type WeaponConfig = WeaponTypesModule.WeaponConfig

local ResonantStaff: WeaponConfig = {
	-- ── Identity ──────────────────────────────────────────────────────────────
	Id          = "resonant_staff",
	Name        = "Resonant Staff",
	Description = "A long focus-rod carved from petrified ashwood. Channels rather than cuts.",
	Lore        = "Resonants speak in frequencies the untrained ear mistakes for silence.",

	-- ── Rarity & Loot ─────────────────────────────────────────────────────────
	Rarity      = "Common",
	LootWeight  = 55,           -- ✏️ slightly rarer by feel; magic weapons are more intentional finds
	LootPools   = { "WorldDrop", "StarterKit" },

	-- ── Tool ──────────────────────────────────────────────────────────────────
	ToolModelId = "",           -- TODO: replace with rbxassetid:// when art is ready
	GripOffset  = CFrame.new(0, -1.5, 0),
	ToolType    = "Melee",      -- physical swings still melee; Aspect abilities are separate
	WeightClass = "Medium",      -- Resonant primary range; cross-train penalty for Silhouette

	-- ── Stats ─────────────────────────────────────────────────────────────────
	BaseDamage     = 10,        -- ✏️ modest — Resonant playstyle augments this with cast damage
	AttackSpeed    = 0.75,      -- ✏️ sluggish meter; players are expected to mostly cast
	Range          = 8.0,       -- ✏️ longest reach in the starter set; sweeping staff arcs
	KnockbackPower = 0.7,       -- ✏️ solid knockback despite low damage (staff mass)
	Weight         = 0.9,       -- ✏️ medium-heavy; slightly slower but not as bad as Iron Sword
	FeintCooldown  = 1.2,
	HeavyCooldown  = 1.8,       -- long heavy cooldown — the one heavy is a powerful cleave

	-- ── Animations ────────────────────────────────────────────────────────────
	Animations = {
		Equip = { Folder = "ResonantStaff", Asset = "Equip" },
		Idle  = { Folder = "ResonantStaff", Asset = "Idle"  },
		Walk  = { Folder = "ResonantStaff", Asset = "Walk"  },
		Run   = { Folder = "ResonantStaff", Asset = "Run"   },

		-- 2-hit combo: deliberate, wide sweeps
		Combo = {
			{ Folder = "ResonantStaff", Asset = "Sweep1", HitFrame = 0.50 },
			{ Folder = "ResonantStaff", Asset = "Sweep2", HitFrame = 0.55 },
		},

		LungeAttack = { Folder = "ResonantStaff", Asset = "ChannelThrust", HitFrame = 0.45 },
		HeavyAttack = { Folder = "ResonantStaff", Asset = "GroundSlam",    HitFrame = 0.65 },
	},

	-- ── Hitboxes ──────────────────────────────────────────────────────────────
	Hitboxes = {
		Default = {
			Size   = Vector3.new(6, 4, 8.0),
			Offset = CFrame.new(0, 0, -4.0),
		},
		Heavy = {
			Size   = Vector3.new(10, 3, 10),   -- wide ground slam AoE
			Offset = CFrame.new(0, -1.5, -5.0),
		},
		Lunge = {
			Size   = Vector3.new(3, 3, 9),
			Offset = CFrame.new(0, 0, -4.5),
		},
	},

	-- ── Abilities ─────────────────────────────────────────────────────────────
	Abilities = {
		Active  = "FrostShield",  -- defensive barrier; compensates for low attack speed
		Passive = "Regenerate",   -- passive HP regen while staff is equipped
	},

	-- ── VFX / SFX ─────────────────────────────────────────────────────────────
	Effects = {
		SwingTrail = "",  -- TODO: rbxassetid://
		HitImpact  = "",  -- TODO: rbxassetid://
		EquipSound = "",  -- TODO: rbxassetid://
		HitSound   = "",  -- TODO: rbxassetid://
		BlockSound = "",  -- TODO: rbxassetid://
	},
}

return ResonantStaff
