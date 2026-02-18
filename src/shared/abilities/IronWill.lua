--!strict
--[[
	IronWill.lua  — Active ability
	Issue #72: Weapon abilities — active + passive framework
	Epic #66: Modular Weapon Library & Equip System

	Active: press E while the Iron Sword is equipped to gain a short
	window of 40% damage reduction.  Cooldown enforced server-side.
]]

local IronWill = {
	Id          = "IronWill",
	Type        = "Active",
	Description = "Brace yourself — take 40% less damage for 3 seconds. 8s cooldown.",

	Cooldown    = 8,   -- seconds; enforced server-side in AbilitySystem
	Duration    = 3,   -- seconds of damage reduction

	DamageReductionMultiplier = 0.6, -- incoming damage × 0.6
}

--[[
	Called by AbilitySystem when the player presses the active keybind.
	Applies a temporary damage-reduction modifier on the server.
	@param player  The player activating this ability
	@param weapon  WeaponConfig that owns this ability
]]
function IronWill.OnActivate(player: Player, weapon: any)
	-- Store a damage-reduction flag on the character attribute.
	-- CombatService reads this when processing incoming hits.
	local character = player.Character
	if not character then return end

	character:SetAttribute("DamageReduction", IronWill.DamageReductionMultiplier)
	print(("[IronWill] %s activated IronWill (%.0fs)"):format(player.Name, IronWill.Duration))

	task.delay(IronWill.Duration, function()
		-- Only clear if we're still the ones who set it (no double-trigger race)
		if character and character:GetAttribute("DamageReduction") == IronWill.DamageReductionMultiplier then
			character:SetAttribute("DamageReduction", nil)
			print(("[IronWill] %s IronWill expired"):format(player.Name))
		end
	end)
end

return IronWill
