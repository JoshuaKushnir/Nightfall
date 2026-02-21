--!strict
-- DisciplineConfig
-- Contains numeric balancing values for each Discipline.
-- Accessible from server and client; lightweight lookups only.

local DisciplineConfig: {[string]: any} = {
	Wayward = {
		BreathPool           = 100,
		SprintDrain          = 10,
		DashDrain            = 15,
		WallRunDrain         = 20,
		BreathRegenGround    = 30,
		PosturePool          = 100,
		PostureRegen         = 6,
		PostureRegenBlocking = 3,
		BlockDrainMultiplier = 1.0,
		StaggerDuration      = 0.80,
		WeightClasses        = {"Light","Medium"},
		AspectCoeff          = 1.0,
	},

	Ironclad = {
		BreathPool           = 110,
		SprintDrain          = 12,
		DashDrain            = 18,
		WallRunDrain         = 22,
		BreathRegenGround    = 25,
		PosturePool          = 120,
		PostureRegen         = 8,
		PostureRegenBlocking = 4,
		BlockDrainMultiplier = 0.75,
		StaggerDuration      = 0.90,
		WeightClasses        = {"Light","Medium","Heavy"},
		AspectCoeff          = 1.0,
	},

	Silhouette = {
		BreathPool           = 90,
		SprintDrain          = 9,
		DashDrain            = 12,
		WallRunDrain         = 18,
		BreathRegenGround    = 35,
		PosturePool          = 80,
		PostureRegen         = 5,
		PostureRegenBlocking = 2.5,
		BlockDrainMultiplier = 1.25,
		StaggerDuration      = 0.60,
		WeightClasses        = {"Light"},
		AspectCoeff          = 1.0,
	},

	Resonant = {
		BreathPool           = 100,
		SprintDrain          = 11,
		DashDrain            = 16,
		WallRunDrain         = 20,
		BreathRegenGround    = 30,
		PosturePool          = 90,
		PostureRegen         = 6,
		PostureRegenBlocking = 3,
		BlockDrainMultiplier = 1.0,
		StaggerDuration      = 0.80,
		WeightClasses        = {"Light","Medium"},
		AspectCoeff          = 1.0,
	},
}

-- fallback accessor
local function Get(id: string)
	return DisciplineConfig[id] or DisciplineConfig.Wayward
end

return {
	Get = Get,
	Raw = DisciplineConfig,
}
