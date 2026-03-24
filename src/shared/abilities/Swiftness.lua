
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
	Swiftness.lua  — Active ability
	Status: Hasted

	Floods the body with kinetic energy, boosting WalkSpeed and
	sprint velocity for 6 seconds. Useful for closing gaps or
	escaping dangerous positioning.

	Sets "WalkSpeedBonus" character attribute (read by MovementService)
	and directly adjusts Humanoid.WalkSpeed as an immediate effect.
]]

local Swiftness = {
	Id          = "Swiftness",
	Type        = "Active",
	Description = "Move like wind — +14 WalkSpeed for 6 seconds. 14s cooldown.",

	Cooldown       = 14,   -- seconds
	Duration       = 6,    -- seconds
	SpeedBonus     = 14,   -- added to base WalkSpeed
	BaseWalkSpeed  = 16,   -- Roblox default; MovementService may override
}

--[[
	Called by AbilitySystem when activated.
	Bumps Humanoid.WalkSpeed for the duration, then restores it.
]]
function Swiftness.OnActivate(player: Player, _weapon: any)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then return end

	local original = humanoid.WalkSpeed
	humanoid.WalkSpeed = original + Swiftness.SpeedBonus
	character:SetAttribute("WalkSpeedBonus", Swiftness.SpeedBonus)
	character:SetAttribute("StatusEffect",   "Hasted")
	print(("[Swiftness] %s activated Swiftness (%.0fs, +%d speed)"):format(
		player.Name, Swiftness.Duration, Swiftness.SpeedBonus))

	task.delay(Swiftness.Duration, function()
		if character and humanoid then
			-- Restore only if we're still the modifier
			if character:GetAttribute("WalkSpeedBonus") == Swiftness.SpeedBonus then
				humanoid.WalkSpeed = original
				character:SetAttribute("WalkSpeedBonus", nil)
				if character:GetAttribute("StatusEffect") == "Hasted" then
					character:SetAttribute("StatusEffect", nil)
				end
				print(("[Swiftness] %s Swiftness expired"):format(player.Name))
			end
		end
	end)
end

function Swiftness.ClientActivate(targetPosition: Vector3?)
    local NetworkProvider = GetService("NetworkProvider")
    local remote = NetworkProvider:GetRemoteEvent("AbilityCastRequest")
    if remote then
        remote:FireServer({AbilityId = Swiftness.Id, TargetPosition = targetPosition})
    end
end

return Swiftness
