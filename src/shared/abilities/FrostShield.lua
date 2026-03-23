--!strict
--[[
	FrostShield.lua  — Active ability
	Status: Shielded

	Encases the caster in a brief frost barrier, reducing incoming
	damage by 35% for 5 seconds. Shorter duration than IronWill
	but faster cooldown — intended for quick defensive windows.

	Sets "DamageReduction" character attribute (read by CombatService).
]]

-- #189: require at module scope to avoid per-call overhead
local NetworkProvider = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)

local FrostShield = {
	Id          = "FrostShield",
	Type        = "Active",
	Description = "Freeze incoming force — take 35% less damage for 5 seconds. 12s cooldown.",

	Cooldown  = 12,  -- seconds; enforced server-side in AbilitySystem
	Duration  = 5,   -- seconds of frost shielding

	DamageReductionMultiplier = 0.65,  -- incoming damage × 0.65
}

--[[
	Called by AbilitySystem when the player activates this ability.
	Applies a temporary DamageReduction attribute on the character.
]]
function FrostShield.OnActivate(player: Player, _weapon: any)
	local character = player.Character
	if not character then return end

	character:SetAttribute("DamageReduction", FrostShield.DamageReductionMultiplier)
	character:SetAttribute("StatusEffect", "Shielded")
	print(("[FrostShield] %s activated FrostShield (%.0fs)"):format(player.Name, FrostShield.Duration))

	task.delay(FrostShield.Duration, function()
		if character and character:GetAttribute("DamageReduction") == FrostShield.DamageReductionMultiplier then
			character:SetAttribute("DamageReduction", nil)
			character:SetAttribute("StatusEffect", nil)
			print(("[FrostShield] %s FrostShield expired"):format(player.Name))
		end
	end)
end

function FrostShield.ClientActivate(targetPosition: Vector3?)
    local remote = NetworkProvider:GetRemoteEvent("AbilityCastRequest")
    if remote then
        remote:FireServer({AbilityId = FrostShield.Id, TargetPosition = targetPosition})
    end
end

return FrostShield
