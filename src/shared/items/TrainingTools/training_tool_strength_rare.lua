return {
	Id = "training_tool_strength_rare",
	Name = "Rare Strength Training Tool",
	Description = "An elite weightlifting guide that increases Strength by 3. Equip and press M1 to train.",
	Category = "Tools",
	Rarity = "Rare",
	Weight = 0.02,
	LootPools = { "TrainingToolDrop" },
	-- Training tool config
	IsEquipable = true,
	ToolModelId = "",
	TrainingToolId = "training_tool_strength_rare",
	StatToIncrease = "Strength",
	Amount = 3,
	Cooldown = 5,
	-- Animation config
	Animations = {
		Attack1 = { Folder = "Fists", Asset = "Attack1" },
		Attack2 = { Folder = "Fists", Asset = "Attack2" },
		Attack3 = { Folder = "Fists", Asset = "Attack3" },
		Attack4 = { Folder = "Fists", Asset = "Attack4" },
		Attack5 = { Folder = "Fists", Asset = "Attack5" },
	},
}
