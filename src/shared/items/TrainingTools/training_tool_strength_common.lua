return {
	Id = "training_tool_strength_common",
	Name = "Common Strength Training Tool",
	Description = "A simple weightlifting guide that increases Strength by 1. Equip and press M1 to train.",
	Category = "Tools",
	Rarity = "Common",
	Weight = 0.1,
	LootPools = { "WorldDrop", "TrainingToolDrop" },
	-- Training tool config
	IsEquipable = true,  -- Can be equipped and held like a weapon
	ToolModelId = "",     -- Empty = uses fists/hand animation
	TrainingToolId = "training_tool_strength_common",
	StatToIncrease = "Strength",
	Amount = 1,           -- How much stat increases per M1 attack
	Cooldown = 3,         -- seconds between stat gains
	-- Animation config (use fist animations as fallback)
	Animations = {
		Attack1 = { Folder = "Fists", Asset = "Attack1" },
		Attack2 = { Folder = "Fists", Asset = "Attack2" },
		Attack3 = { Folder = "Fists", Asset = "Attack3" },
		Attack4 = { Folder = "Fists", Asset = "Attack4" },
		Attack5 = { Folder = "Fists", Asset = "Attack5" },
	},
}
