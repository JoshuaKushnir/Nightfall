return {
	Id = "training_tool_fortitude_common",
	Name = "Common Fortitude Training Tool",
	Description = "A basic endurance manual that increases Fortitude by 1. Equip and press M1 to train.",
	Category = "Tools",
	Rarity = "Common",
	Weight = 0.1,
	LootPools = { "WorldDrop", "TrainingToolDrop" },
	-- Training tool config
	IsEquipable = true,
	ToolModelId = "",
	TrainingToolId = "training_tool_fortitude_common",
	StatToIncrease = "Fortitude",
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
