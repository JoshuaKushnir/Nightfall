--!strict
--[[
	SilhouetteDagger.lua

	Issue #132: WeaponRegistry — define 5 starter weapons
	Epic #66: Modular Weapon Library & Equip System

	Starter weapon for the Silhouette discipline.
	A fast, light dagger — built for rapid consecutive hits at the cost
	of reach and break damage. Pairs with Silhouette's mobility and
	evasion stat profile.

	Stats are placeholders (✏️) pending Phase 4 balancing pass.

	Dependencies: WeaponTypes
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponTypesModule = require(ReplicatedStorage.Shared.types.WeaponTypes)
type WeaponConfig = WeaponTypesModule.WeaponConfig

local SilhouetteDagger: WeaponConfig = {
	-- ── Identity ──────────────────────────────────────────────────────────────
	Id          = "silhouette_dagger",
	Name        = "Silhouette Dagger",
	Description = "Paper-thin and razor-sharp. Made for those who fight fast and vanish faster.",
	Lore        = "Silhouettes don't win by taking hits. They win by not being there.",

	-- ── Rarity & Loot ─────────────────────────────────────────────────────────
	Rarity      = "Common",
	LootWeight  = 65,           -- ✏️ comparable common tier drop rate
	LootPools   = { "WorldDrop", "StarterKit" },

	-- ── Tool ──────────────────────────────────────────────────────────────────
	ToolModelId = "",           -- TODO: replace with rbxassetid:// when art is ready
	GripOffset  = CFrame.new(0, -0.6, 0),
	ToolType    = "Melee",
	WeightClass = "Light",       -- Silhouette primary; all disciplines can use freely

	-- ── Stats ─────────────────────────────────────────────────────────────────
	BaseDamage     = 8,         -- ✏️ lowest per-hit; damage comes from combo frequency
	AttackSpeed    = 1.6,       -- ✏️ fastest combo of the starter set
	Range          = 3.0,       -- ✏️ short reach; Silhouette must close distance
	KnockbackPower = 0.3,       -- minimal knockback — dagger stings but doesn't push
	Weight         = 0.2,       -- ✏️ near-weightless; virtually no movement penalty
	FeintCooldown  = 0.6,       -- very short feint window
	HeavyCooldown  = 0.9,       -- quick heavy recovery

	-- ── Animations ────────────────────────────────────────────────────────────
	Animations = {
		Equip = { Folder = "SilhouetteDagger", Asset = "Equip" },
		Idle  = { Folder = "SilhouetteDagger", Asset = "Idle"  },
		Walk  = { Folder = "SilhouetteDagger", Asset = "Walk"  },
		Run   = { Folder = "SilhouetteDagger", Asset = "Run"   },

		-- 6-hit combo: fastest cadence in the starter set
		Combo = {
			{ Folder = "SilhouetteDagger", Asset = "Jab1",    Id = "", HitFrame = 0.25 }, -- STUB
			{ Folder = "SilhouetteDagger", Asset = "Jab2",    Id = "", HitFrame = 0.25 }, -- STUB
			{ Folder = "SilhouetteDagger", Asset = "Slash1",  Id = "", HitFrame = 0.28 }, -- STUB
			{ Folder = "SilhouetteDagger", Asset = "Slash2",  Id = "", HitFrame = 0.28 }, -- STUB
			{ Folder = "SilhouetteDagger", Asset = "Flurry1", Id = "", HitFrame = 0.22 }, -- STUB
			{ Folder = "SilhouetteDagger", Asset = "Flurry2", Id = "", HitFrame = 0.22 }, -- STUB
		},

		LungeAttack = { Folder = "SilhouetteDagger", Asset = "Dart",      HitFrame = 0.30 },
		HeavyAttack = { Folder = "SilhouetteDagger", Asset = "PierceDrive", HitFrame = 0.38 },
	},

	-- ── Hitboxes ──────────────────────────────────────────────────────────────
	Hitboxes = {
		Default = {
			Size   = Vector3.new(3, 3, 3.5),
			Offset = CFrame.new(0, 0, -1.75),
		},
		Heavy = {
			Size   = Vector3.new(3.5, 3.5, 4),
			Offset = CFrame.new(0, 0, -2.0),
		},
		Lunge = {
			Size   = Vector3.new(2.5, 2.5, 5),
			Offset = CFrame.new(0, 0, -2.5),
		},
	},

	-- ── Abilities ─────────────────────────────────────────────────────────────
	Abilities = {
		Active  = "BloodRage",  -- damage amp at the cost of increased damage taken
		Passive = "Swiftness",  -- on hit, temporarily increases movement speed
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

return SilhouetteDagger
