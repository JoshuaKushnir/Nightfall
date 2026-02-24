--!strict
-- MovementController discipline integration tests

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementController = require(ReplicatedStorage.Client.controllers.MovementController)
local DisciplineConfig = require(ReplicatedStorage.Shared.modules.DisciplineConfig)
local StateService = require(ReplicatedStorage.Shared.modules.StateService)

return {
	name = "MovementController Discipline Tests",
	tests = {
		{
			name = "breath pool matches discipline on start",
			fn = function()
				-- fake player and patch StateService
				local orig = StateService.GetPlayerData
				StateService.GetPlayerData = function()
					return {DisciplineId = "Silhouette"}
				end

				-- call helper directly
				MovementController:Init({})
				MovementController:Start()
				assert(MovementController.GetBreathPool() == DisciplineConfig.Get("Silhouette").breathPool)

				StateService.GetPlayerData = orig
			end,
		},
	},
}
