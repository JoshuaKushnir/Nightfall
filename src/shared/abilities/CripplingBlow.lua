--!strict
--[[
	CripplingBlow.lua  — Passive ability
	Status applied to target: Weakened

	Every 4th confirmed hit against the same target saps their strength,
	applying the "Weakened" status. While Weakened, the target's outgoing
	damage is halved for 3 seconds.

	Implementation: sets a "DamageBoost" attribute of 0.5 on the TARGET's
	character. CombatService checks DamageBoost < 1 and applies it as a
	damage penalty (added in same update as this ability).
]]

local CripplingBlow = {
	Id               = "CripplingBlow",
	Type             = "Passive",
	Description      = "Every 4th hit weakens the target, halving their damage output for 3 seconds.",

	TriggerEveryNHits  = 4,
	WeakenDuration     = 3,    -- seconds
	WeakenDamageBoost  = 0.5,  -- target's DamageBoost set to 0.5 (50% penalty)
}

--[[
	Called by AbilitySystem when the hit-count threshold is reached.
	@param attacker  Player who owns this weapon
	@param target    Hit instance (Player or Model/dummy)
	@param weapon    WeaponConfig that triggered this
]]
function CripplingBlow.OnTrigger(attacker: Player, target: any, _weapon: any)
	if typeof(target) ~= "Instance" or not target:IsA("Player") then
		-- Weaken only applies to players (dummies have no character)
		return
	end

	local targetPlayer = target :: Player
	local character = targetPlayer.Character
	if not character then return end

	character:SetAttribute("DamageBoost",  CripplingBlow.WeakenDamageBoost)
	character:SetAttribute("StatusEffect", "Weakened")
	print(("[CripplingBlow] %s weakened %s (-50%% dmg, %.0fs)"):format(
		attacker.Name, targetPlayer.Name, CripplingBlow.WeakenDuration))

	task.delay(CripplingBlow.WeakenDuration, function()
		if character and character:GetAttribute("DamageBoost") == CripplingBlow.WeakenDamageBoost then
			character:SetAttribute("DamageBoost", nil)
			if character:GetAttribute("StatusEffect") == "Weakened" then
				character:SetAttribute("StatusEffect", nil)
			end
			print(("[CripplingBlow] %s Weakened expired"):format(targetPlayer.Name))
		end
	end)
end

return CripplingBlow
