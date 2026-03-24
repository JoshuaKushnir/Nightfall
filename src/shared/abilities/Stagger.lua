--!strict
--[[
	Stagger.lua  — Passive ability
	Issue #72: Weapon abilities — active + passive framework
	Epic #66: Modular Weapon Library & Equip System

	Every 3rd hit against the same target applies the Stagger state,
	briefly stunning them and interrupting any ongoing action.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StateService = require(ReplicatedStorage.Shared.modules.StateService)

local Stagger = {
	Id               = "Stagger",
	Type             = "Passive",
	Description      = "Every 3rd hit staggers the target, briefly interrupting their action.",

	-- Passive trigger condition
	TriggerEveryNHits = 3,
	StaggerDuration   = 0.6, -- seconds
}

--[[
	Called by AbilitySystem after the hit counter threshold is reached.
	@param attacker  Player who owns this weapon
	@param target    The instance that was hit (Player or Model/dummy)
	@param weapon    WeaponConfig that triggered this
]]
function Stagger.OnTrigger(attacker: Player, target: any, weapon: any)
	-- Apply Stagger state via StateService if target is a player
	if typeof(target) == "Instance" and target:IsA("Player") then
		local ok, err = pcall(function()
			StateService:SetState(target, "Stunned", Stagger.StaggerDuration)
		end)
		if not ok then
			warn(("[Stagger] Failed to apply stagger to %s: %s"):format(tostring(target), tostring(err)))
		else
			print(("[Stagger] %s staggered %s"):format(attacker.Name, (target :: Player).Name))
		end
	end
end

return Stagger
