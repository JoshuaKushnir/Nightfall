--!strict
--[[
	Adrenaline.lua  — Active ability (test)
	Issue #72: Weapon abilities — active + passive framework

	Active: press E while Fists are equipped to surge with adrenaline,
	boosting outgoing damage by 50% for 4 seconds.
	Cooldown enforced server-side in AbilitySystem.

	Implementation: sets a "DamageBoost" character attribute (number ≥ 1)
	that CombatService multiplies onto finalDamage before applying.
]]

local Adrenaline = {
	Id          = "Adrenaline",
	Type        = "Active",
	Description = "Channel raw aggression — deal 50% more damage for 4 seconds. 12s cooldown.",

	Cooldown = 12,  -- seconds; enforced server-side
	Duration = 4,   -- seconds of boosted damage

	DamageBoostMultiplier = 1.5, -- finalDamage × 1.5
}

--[[
	Called by AbilitySystem when the player presses E.
	Sets a temporary DamageBoost attribute on the character.
	CombatService reads this when computing outgoing damage.
	@param player  The activating player
	@param weapon  WeaponConfig that owns this ability (unused here)
]]
function Adrenaline.OnActivate(player: Player, _weapon: any)
	local character = player.Character
	if not character then return end

	character:SetAttribute("DamageBoost", Adrenaline.DamageBoostMultiplier)
	print(("[Adrenaline] %s activated Adrenaline (+50%% dmg for %.0fs)"):format(
		player.Name, Adrenaline.Duration))

	task.delay(Adrenaline.Duration, function()
		-- Only clear if we're still the ones who set it (avoids clearing a
		-- re-trigger that started during this window, though cooldown should
		-- prevent that from AbilitySystem).
		if character and character:GetAttribute("DamageBoost") == Adrenaline.DamageBoostMultiplier then
			character:SetAttribute("DamageBoost", nil)
			print(("[Adrenaline] %s Adrenaline expired"):format(player.Name))
		end
	end)
end

return Adrenaline
