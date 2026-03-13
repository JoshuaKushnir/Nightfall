return {
	Id = "training_tool_strength_common",
	Name = "Common Strength Training Tool",
	Description = "A simple weightlifting guide that increases Strength by 1.",
	Category = "Tools",
	Rarity = "Common",
	Weight = 0.1,
	LootPools = { "WorldDrop", "TrainingToolDrop" },
	-- TrainingToolId is used by TrainingToolService to look up the effect
	TrainingToolId = "training_tool_strength_common",
	StatToIncrease = "Strength",
	Amount = 1,
}