return {
	Id = "training_tool_willpower_common",
	Name = "Common Willpower Training Tool",
	Description = "A basic meditation guide that increases Willpower by 1. Equip and press M1 to train.",
	Category = "Tools",
	Rarity = "Common",
	Weight = 0.1,
	LootPools = { "WorldDrop", "TrainingToolDrop" },
	-- Training tool config
	IsEquipable = true,
	ToolModelId = "",
	TrainingToolId = "training_tool_willpower_common",
	StatToIncrease = "Willpower",
	Amount = 1,
	Cooldown = 3,
	-- Animation config
	Animations = {
		Attack1 = { Folder = "Fists", Asset = "Attack1" },
		Attack2 = { Folder = "Fists", Asset = "Attack2" },
		Attack3 = { Folder = "Fists", Asset = "Attack3" },
		Attack4 = { Folder = "Fists", Asset = "Attack4" },
		Attack5 = { Folder = "Fists", Asset = "Attack5" },
	},
}
