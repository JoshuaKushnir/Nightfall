--!strict
-- CombatController unit tests

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatController = require(ReplicatedStorage.Client.controllers.CombatController)
local CombatBlackboard = require(ReplicatedStorage.Shared.modules.CombatBlackboard)

-- bootstrap minimal controller lifecycle for testing
if CombatController.Init then
	CombatController:Init({})
end
if CombatController.Start then
	CombatController:Start()
end

return {
	name = "CombatController Unit Tests",
	tests = {
		{
			name = "basic API existence",
			fn = function()
				assert(type(CombatController.Init) == "function")
				assert(type(CombatController.Start) == "function")
				assert(type(CombatController.GetCurrentState) == "function")
				assert(type(CombatController.NotifyActionStarted) == "function")
				assert(type(CombatController.NotifyActionEnded) == "function")
				assert(type(CombatController.TriggerStun) == "function")
			end,
		},
		{
			name = "state resolution simple cases",
			fn = function()
				-- ensure fresh blackboard
				CombatBlackboard.IsAttacking = false
				CombatBlackboard.IsBlocking = false
				CombatBlackboard.IsStunned = false
				assert(CombatController.GetCurrentState() == "Idle")

				-- notify an attack action
				CombatController.NotifyActionStarted({Type="Attack"})
				assert(CombatBlackboard.IsAttacking == true)
				-- give controller a heartbeat cycle (simulated by an extra call)
				-- direct resolution works immediately since we set flag
				assert(CombatController.GetCurrentState() ~= "Idle")
				CombatController.NotifyActionEnded({Type="Attack"})
				assert(CombatBlackboard.IsAttacking == false)
				-- can't guarantee which until controller starts; just ensure variables change
			end,
		},
	},
}
