return {
	Id = "training_tool_fortitude_uncommon",
	Name = "Uncommon Fortitude Training Tool",
	Description = "An advanced endurance manual that increases Fortitude by 2. Equip and press M1 to train.",
	Category = "Tools",
	Rarity = "Uncommon",
	Weight = 0.05,
	LootPools = { "TrainingToolDrop" },
	-- Training tool config
	IsEquipable = true,
	ToolModelId = "",
	TrainingToolId = "training_tool_fortitude_uncommon",
	StatToIncrease = "Fortitude",
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
