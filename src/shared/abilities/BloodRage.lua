
-- Service caching to avoid per-hit require overhead (Optimization #189)
local _services = {}
local function GetService(name)
	if _services[name] ~= nil then return _services[name] end
	local RunService = game:GetService("RunService")
	
	if name == "NetworkProvider" then
		_services[name] = require(game:GetService("ReplicatedStorage").Shared.network.NetworkProvider)
	elseif name == "HitboxService" then
		_services[name] = require(game:GetService("ReplicatedStorage").Shared.modules.combat.HitboxService)
	elseif name == "PostureService" then
		if RunService:IsServer() then
			local result = require(game:GetService("ServerScriptService").Server.services.PostureService)
			local success = true
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	elseif name == "CombatService" then
		if RunService:IsServer() then
			local result = require(game:GetService("ServerScriptService").Server.services.CombatService)
			local success = true
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	elseif name == "DummyService" then
		if RunService:IsServer() then
			local result = require(game:GetService("ServerScriptService").Server.services.DummyService)
			local success = true
			_services[name] = success and result or false
		else
			_services[name] = false
		end
	end
	
	return _services[name]
end
--!strict
--[[
	BloodRage.lua  — Active ability
	Status: Enraged

	Channels raw aggression into a violent surge — dealing 80% more
	damage for 5 seconds. The recklessness of rage also causes the
	caster to take 20% more incoming damage during the window.

	Sets "DamageBoost" (1.8) and "DamageTaken" (1.2) character attributes.
	CombatService reads DamageBoost on attacker; DamageTaken is read below
	and applied to incoming finalDamage before the variance step.
]]

local BloodRage = {
	Id          = "BloodRage",
	Type        = "Active",
	Description = "Embrace the rage — +80% damage but take 20% more for 5 seconds. 18s cooldown.",

	Cooldown = 18,  -- seconds
	Duration = 5,   -- seconds

	DamageBoostMultiplier = 1.8,
	DamageTakenMultiplier = 1.2,

    Requirement = {
        Strength = 10,
        Willpower = 5,
    }
}

--[[
	Called by AbilitySystem (or InventoryService UseItem) when activated.
]]
function BloodRage.OnActivate(player: Player, _weapon: any)
	local character = player.Character
	if not character then return end

	character:SetAttribute("DamageBoost",  BloodRage.DamageBoostMultiplier)
	character:SetAttribute("DamageTaken",  BloodRage.DamageTakenMultiplier)
	character:SetAttribute("StatusEffect", "Enraged")
	print(("[BloodRage] %s enters BloodRage (+80%% dmg / +20%% taken, %.0fs)"):format(
		player.Name, BloodRage.Duration))

	task.delay(BloodRage.Duration, function()
		if character then
			if character:GetAttribute("DamageBoost") == BloodRage.DamageBoostMultiplier then
				character:SetAttribute("DamageBoost", nil)
			end
			if character:GetAttribute("DamageTaken") == BloodRage.DamageTakenMultiplier then
				character:SetAttribute("DamageTaken", nil)
			end
			if character:GetAttribute("StatusEffect") == "Enraged" then
				character:SetAttribute("StatusEffect", nil)
			end
			print(("[BloodRage] %s BloodRage expired"):format(player.Name))
		end
	end)
end

function BloodRage.ClientActivate(targetPosition: Vector3?)
    local NetworkProvider = GetService("NetworkProvider")
    local remote = NetworkProvider:GetRemoteEvent("AbilityCastRequest")
    if remote then
        remote:FireServer({AbilityId = BloodRage.Id, TargetPosition = targetPosition})
    end
end

return BloodRage
