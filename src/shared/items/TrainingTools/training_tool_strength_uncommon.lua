return {
	Id = "training_tool_strength_uncommon",
	Name = "Uncommon Strength Training Tool",
	Description = "An advanced weightlifting guide that increases Strength by 2. Equip and press M1 to train.",
	Category = "Tools",
	Rarity = "Uncommon",
	Weight = 0.05,
	LootPools = { "TrainingToolDrop" },
	-- Training tool config
	IsEquipable = true,
	ToolModelId = "",
	TrainingToolId = "training_tool_strength_uncommon",
	StatToIncrease = "Strength",
	Amount = 2,
	Cooldown = 4,
	-- Animation config
	Animations = {
		Attack1 = { Folder = "Fists", Asset = "Attack1" },
		Attack2 = { Folder = "Fists", Asset = "Attack2" },
		Attack3 = { Folder = "Fists", Asset = "Attack3" },
		Attack4 = { Folder = "Fists", Asset = "Attack4" },
		Attack5 = { Folder = "Fists", Asset = "Attack5" },
	},
}
