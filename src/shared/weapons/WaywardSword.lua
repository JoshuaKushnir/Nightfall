--!strict
--[[
	WaywardSword.lua

	Issue #132: WeaponRegistry — define 5 starter weapons
	Epic #66: Modular Weapon Library & Equip System

	Starter weapon for the Wayward discipline.
	A balanced one-handed sword — versatile, forgiving, and consistent.
	Suits the Wayward archetype's even stat spread and medium skill ceiling.

	Stats are placeholders (✏️) pending Phase 4 balancing pass.

	Dependencies: WeaponTypes
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTypesModule = require(ReplicatedStorage.Shared.types.WeaponTypes)
type WeaponConfig = WeaponTypesModule.WeaponConfig

local WaywardSword: WeaponConfig = {
	-- ── Identity ──────────────────────────────────────────────────────────────
	Id          = "wayward_sword",
	Name        = "Wayward Sword",
	Description = "A balanced one-handed blade. Nothing flashy — just reliable.",
	Lore        = "The Wayward carry no banner and swear no oath. Their swords speak plainly.",

	-- ── Rarity & Loot ─────────────────────────────────────────────────────────
	Rarity      = "Common",
	LootWeight  = 70,           -- ✏️ slightly more common than the Iron Sword
	LootPools   = { "WorldDrop", "StarterKit" },

	-- ── Tool ──────────────────────────────────────────────────────────────────
	ToolModelId = "",           -- TODO: replace with rbxassetid:// when art is ready
	GripOffset  = CFrame.new(0, -1.0, 0),
	ToolType    = "Melee",

	-- ── Stats ─────────────────────────────────────────────────────────────────
	BaseDamage     = 14,        -- ✏️ moderate; lower than Iron Sword, higher than Fists
	AttackSpeed    = 1.0,       -- ✏️ baseline — matches the default combo window
	Range          = 5.0,       -- ✏️ standard one-handed reach
	KnockbackPower = 0.8,
	Weight         = 0.8,       -- ✏️ lighter than Iron Sword; ~89% movement speed
	FeintCooldown  = 0.9,
	HeavyCooldown  = 1.2,

	-- ── Animations ────────────────────────────────────────────────────────────
	Animations = {
		Equip = { Folder = "WaywardSword", Asset = "Equip" },
		Idle  = { Folder = "WaywardSword", Asset = "Idle"  },
		Walk  = { Folder = "WaywardSword", Asset = "Walk"  },
		Run   = { Folder = "WaywardSword", Asset = "Run"   },

		-- 4-hit combo: balanced rhythm
		Combo = {
			{ Folder = "WaywardSword", Asset = "Slash1",    HitFrame = 0.38 },
			{ Folder = "WaywardSword", Asset = "Slash2",    HitFrame = 0.42 },
			{ Folder = "WaywardSword", Asset = "Thrust",    HitFrame = 0.35 },
			{ Folder = "WaywardSword", Asset = "Riposte",   HitFrame = 0.30 },
		},

		LungeAttack = { Folder = "WaywardSword", Asset = "Lunge",     HitFrame = 0.40 },
		HeavyAttack = { Folder = "WaywardSword", Asset = "Downstrike", HitFrame = 0.50 },
	},

	-- ── Hitboxes ──────────────────────────────────────────────────────────────
	Hitboxes = {
		Default = {
			Size   = Vector3.new(4.5, 4, 5.0),
			Offset = CFrame.new(0, 0, -2.5),
		},
		Heavy = {
			Size   = Vector3.new(5, 5, 5.5),
			Offset = CFrame.new(0, 0, -2.75),
		},
		Lunge = {
			Size   = Vector3.new(3.5, 3.5, 7),
			Offset = CFrame.new(0, 0, -3.5),
		},
	},

	-- ── Abilities ─────────────────────────────────────────────────────────────
	Abilities = {
		Active  = "Adrenaline",  -- short burst of stamina / attack speed (see AbilityRegistry)
		Passive = "Stagger",     -- small chance to apply stagger on heavy attack
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

return WaywardSword
